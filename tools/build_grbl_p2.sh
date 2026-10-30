#!/usr/bin/env bash
# Compile GRBL's portable core for the Propeller 2 with flexspin and print a
# size report.
#
#   tools/build_grbl_p2.sh [--src DIR] [--out DIR]
#
#   --src DIR   GRBL source dir (default: <repo>/grbl, i.e. upstream layout)
#   --out DIR   build/output dir   (default: <repo>/build/p2)
#
# Env: FLEXSPIN=/path/to/flexspin (default: tools/.flexspin/bin/flexspin, then PATH)
#      FLEXSPIN_EXTRA_FLAGS="..." appended to the compile flags.
#
# Phase 0 build model (see docs/phase0-fixes.md):
#   * the GRBL sources are copied into <out>/src, never edited in place;
#   * patches/*.diff are applied to the copy unless already present upstream
#     (so this keeps working after Phase 1 commits the fixes to grbl/);
#   * p2/stub/ supplies fake <avr/*.h>/<util/delay.h> plus fakeregs.c.
# Output: <out>/grbl_p2.binary, <out>/flexspin.log, <out>/size_report.txt/.json.
# If $GITHUB_STEP_SUMMARY is set, a markdown size table is appended to it.
set -euo pipefail

TOOLS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$TOOLS_DIR/.." && pwd)"
SRC_DIR="${GRBL_SRC:-$REPO_ROOT/grbl}"
OUT_DIR="${GRBL_P2_OUT:-$REPO_ROOT/build/p2}"
while [ $# -gt 0 ]; do
  case "$1" in
    --src) SRC_DIR="$2"; shift 2 ;;
    --src=*) SRC_DIR="${1#*=}"; shift ;;
    --out) OUT_DIR="$2"; shift 2 ;;
    --out=*) OUT_DIR="${1#*=}"; shift ;;
    -h|--help) sed -n '2,21p' "$0"; exit 0 ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
done
log() { printf '[build_grbl_p2] %s\n' "$*"; }

if [ -z "${FLEXSPIN:-}" ]; then
  if [ -x "$TOOLS_DIR/.flexspin/bin/flexspin" ]; then FLEXSPIN="$TOOLS_DIR/.flexspin/bin/flexspin"
  elif command -v flexspin >/dev/null 2>&1; then FLEXSPIN="$(command -v flexspin)"
  else echo "error: flexspin not found; run tools/build_flexspin.sh first or set FLEXSPIN=" >&2; exit 1; fi
fi
[ -f "$SRC_DIR/main.c" ] || { echo "error: $SRC_DIR does not look like GRBL sources (no main.c)" >&2; exit 1; }
FLEXSPIN_VERSION="$("$FLEXSPIN" --version 2>&1 | grep -m1 -i '^version' || true)"
log "flexspin: $FLEXSPIN ($FLEXSPIN_VERSION)"
log "sources:  $SRC_DIR"

# Fresh staging copy (upstream layout: <stage>/grbl/*.c so patch paths match).
mkdir -p "$OUT_DIR"
OUT_DIR="$(cd "$OUT_DIR" && pwd)"
STAGE="$OUT_DIR/src"
rm -rf "$STAGE"
mkdir -p "$STAGE/grbl"
cp "$SRC_DIR"/*.c "$SRC_DIR"/*.h "$STAGE/grbl/"

# GIT_CEILING_DIRECTORIES stops git from discovering the enclosing repo, so
# `git apply` treats the staging dir as a plain directory tree.
gapply() { (cd "$STAGE" && GIT_CEILING_DIRECTORIES="$OUT_DIR" git apply -p1 "$@"); }
shopt -s nullglob
for p in "$REPO_ROOT"/patches/*.diff "$REPO_ROOT"/patches/*.patch; do
  name="$(basename "$p")"
  if gapply --check "$p" 2>/dev/null; then
    gapply "$p"; log "applied patch $name"
  elif gapply --check --reverse "$p" 2>/dev/null; then
    log "patch $name already present in sources; skipped"
  else
    echo "error: patch $name neither applies nor is already applied to $SRC_DIR" >&2; exit 1
  fi
done
shopt -u nullglob

cp "$REPO_ROOT/p2/stub/fakeregs.c" "$STAGE/grbl/"
STUB_INC="$REPO_ROOT/p2/stub"

# Flags reproduce the proposal's measured build (52,948 B with flexspin 7.8.0-beta):
#   -2 -O2           P2 native (hub-exec) code, full optimisation
#   -D__flash=       AVR named address space qualifier -> nothing (fix #1)
#   -DF_CPU, -DM_PI  normally provided by avr-gcc / avr-libc <math.h>
# shellcheck disable=SC2206
FLAGS=(-2 -O2 -I "$STUB_INC" -D__flash= -DF_CPU=16000000 -DM_PI=3.14159265358979323846 ${FLEXSPIN_EXTRA_FLAGS:-})
BIN="$OUT_DIR/grbl_p2.binary"
rm -f "$BIN"
log "flexspin ${FLAGS[*]} -o grbl_p2.binary *.c"
set +e
(cd "$STAGE/grbl" && "$FLEXSPIN" "${FLAGS[@]}" -o "$BIN" ./*.c) >"$OUT_DIR/flexspin.log" 2>&1
rc=$?
set -e
if [ $rc -ne 0 ] || [ ! -s "$BIN" ]; then
  grep -iE 'error|fail' "$OUT_DIR/flexspin.log" | head -40 >&2 || tail -40 "$OUT_DIR/flexspin.log" >&2
  echo "error: flexspin failed (rc=$rc) or $BIN missing; log: $OUT_DIR/flexspin.log" >&2
  exit 1
fi

# ---- size report -----------------------------------------------------------
HUB=524288   # P2X8C4M64P hub RAM, 512 KB
BYTES=$(wc -c < "$BIN" | tr -d ' ')
REPORTED=$(sed -n 's/^Program size is \([0-9]*\) bytes.*/\1/p' "$OUT_DIR/flexspin.log" | tail -1)
WARN=$(grep -c 'warning:' "$OUT_DIR/flexspin.log" || true)
KB=$(awk -v b="$BYTES" 'BEGIN{printf "%.2f", b/1024}')
PCT=$(awk -v b="$BYTES" -v h="$HUB" 'BEGIN{printf "%.2f", 100*b/h}')
FREE=$((HUB - BYTES))
FREE_KB=$(awk -v b="$FREE" 'BEGIN{printf "%.2f", b/1024}')
SHA=$(sha256sum "$BIN" | cut -d' ' -f1)

REPORT="$OUT_DIR/size_report.txt"
{
  echo "==== grbl_p2.binary size report ===="
  echo "flexspin:        ${FLEXSPIN_VERSION:-unknown}"
  echo "flags:           ${FLAGS[*]}"
  echo "image:           $BYTES bytes ($KB KB)"
  echo "flexspin says:   ${REPORTED:-n/a} bytes"
  echo "P2 hub RAM:      $HUB bytes (512 KB)"
  echo "hub used:        $PCT %"
  echo "hub free:        $FREE bytes ($FREE_KB KB) before runtime buffers/stacks"
  echo "warning lines:   $WARN"
  echo "sha256:          $SHA"
  echo "===================================="
} > "$REPORT"
cat "$REPORT"

cat > "$OUT_DIR/size_report.json" <<JSON
{"binary":"grbl_p2.binary","bytes":$BYTES,"kib":$KB,"hub_bytes":$HUB,"hub_used_pct":$PCT,"hub_free_bytes":$FREE,"warnings":$WARN,"sha256":"$SHA","flexspin":"${FLEXSPIN_VERSION}"}
JSON

if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
  {
    echo "### grbl_p2.binary size"
    echo ""
    echo "| Metric | Value |"
    echo "|---|---|"
    echo "| Image size | **$BYTES bytes ($KB KB)** |"
    echo "| P2 hub RAM | $HUB bytes (512 KB) |"
    echo "| Hub used | $PCT % |"
    echo "| Hub free | $FREE bytes ($FREE_KB KB) |"
    echo "| flexspin | ${FLEXSPIN_VERSION:-unknown} |"
    echo "| Flags | \`${FLAGS[*]}\` |"
    echo "| Warning lines | $WARN |"
    echo "| sha256 | \`$SHA\` |"
  } >> "$GITHUB_STEP_SUMMARY"
fi

if [ "$BYTES" -gt "$HUB" ]; then
  echo "error: image ($BYTES B) exceeds P2 hub RAM ($HUB B)" >&2; exit 1
fi
log "ok: $BIN"
