#!/usr/bin/env bash
# Build and install flexspin from a pinned spin2cpp release.
#
#   tools/build_flexspin.sh [--prefix DIR] [--force]
#
# - Pin lives in tools/flexspin.version (tag + commit SHA).
# - Source is cached in tools/.cache/spin2cpp-<tag>; install goes to
#   tools/.flexspin by default (bin/flexspin, bin/flexcc, include/).
# - Idempotent: if <prefix>/.flexspin-stamp already matches the pin and the
#   binary runs, it exits 0 without rebuilding (that is what CI caches).
# - Needs: git, make, bison, a C compiler (cc/gcc).
set -euo pipefail

TOOLS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=tools/flexspin.version
source "$TOOLS_DIR/flexspin.version"

PREFIX="${FLEXSPIN_PREFIX:-$TOOLS_DIR/.flexspin}"
CACHE_DIR="${FLEXSPIN_CACHE_DIR:-$TOOLS_DIR/.cache}"
FORCE=0
while [ $# -gt 0 ]; do
  case "$1" in
    --prefix) PREFIX="$2"; shift 2 ;;
    --prefix=*) PREFIX="${1#*=}"; shift ;;
    --force) FORCE=1; shift ;;
    -h|--help) sed -n '2,13p' "$0"; exit 0 ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
done

STAMP="$PREFIX/.flexspin-stamp"
WANT_STAMP="$SPIN2CPP_TAG $SPIN2CPP_SHA"
log() { printf '[build_flexspin] %s\n' "$*"; }

if [ "$FORCE" = 0 ] && [ -x "$PREFIX/bin/flexspin" ] && [ -f "$STAMP" ] \
   && [ "$(cat "$STAMP")" = "$WANT_STAMP" ] && "$PREFIX/bin/flexspin" --version >/dev/null 2>&1; then
  log "up to date: $("$PREFIX/bin/flexspin" --version 2>&1 | grep -m1 -i version) ($PREFIX)"
  exit 0
fi

missing=()
for t in git make bison; do command -v "$t" >/dev/null 2>&1 || missing+=("$t"); done
command -v cc >/dev/null 2>&1 || command -v gcc >/dev/null 2>&1 || missing+=("cc/gcc")
if [ ${#missing[@]} -gt 0 ]; then
  echo "error: missing build tools: ${missing[*]} (Debian/Ubuntu: sudo apt-get install build-essential bison git)" >&2
  exit 1
fi

SRC="$CACHE_DIR/spin2cpp-$SPIN2CPP_TAG"
mkdir -p "$CACHE_DIR"
if [ -d "$SRC/.git" ]; then
  log "reusing source checkout $SRC"
else
  log "cloning $SPIN2CPP_REPO @ $SPIN2CPP_TAG"
  rm -rf "$SRC.tmp"
  git -c advice.detachedHead=false clone --quiet --depth 1 --branch "$SPIN2CPP_TAG" "$SPIN2CPP_REPO" "$SRC.tmp"
  mv "$SRC.tmp" "$SRC"
fi

# Verify the checkout is exactly the pinned commit (guards against a moved tag).
HEAD_SHA="$(git -C "$SRC" rev-parse HEAD)"
if [ "$HEAD_SHA" != "$SPIN2CPP_SHA" ]; then
  echo "error: $SRC is at $HEAD_SHA, expected $SPIN2CPP_SHA for $SPIN2CPP_TAG." >&2
  echo "       The tag may have moved upstream; investigate before updating tools/flexspin.version." >&2
  exit 1
fi
if [ -n "$(git -C "$SRC" status --porcelain --untracked-files=no)" ]; then
  log "source tree has local modifications; resetting to pinned commit"
  git -C "$SRC" checkout --quiet -- .
fi
log "verified $SPIN2CPP_TAG = $HEAD_SHA"

JOBS="$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 2)"
log "building (make -j$JOBS)"
make -C "$SRC" -j"$JOBS" >"$CACHE_DIR/build-$SPIN2CPP_TAG.log" 2>&1 || {
  tail -50 "$CACHE_DIR/build-$SPIN2CPP_TAG.log" >&2
  echo "error: flexspin build failed; full log: $CACHE_DIR/build-$SPIN2CPP_TAG.log" >&2
  exit 1
}

# flexspin locates its C/Spin libraries at <bindir>/../include, so install the
# same bin/ + include/ layout FlexProp uses.
log "installing to $PREFIX"
rm -rf "$PREFIX.tmp"
mkdir -p "$PREFIX.tmp/bin"
cp "$SRC/build/flexspin" "$SRC/build/flexcc" "$PREFIX.tmp/bin/"
cp -R "$SRC/include" "$PREFIX.tmp/include"
cp "$SRC/COPYING" "$PREFIX.tmp/COPYING.spin2cpp" 2>/dev/null || true
echo "$WANT_STAMP" > "$PREFIX.tmp/.flexspin-stamp"
rm -rf "$PREFIX"
mv "$PREFIX.tmp" "$PREFIX"

# Smoke test: compile a trivial C program for P2 using the installed include dir.
SMOKE="$(mktemp -d)"
trap 'rm -rf "$SMOKE"' EXIT
printf '#include <stdio.h>\nint main(void){printf("ok\\n");return 0;}\n' > "$SMOKE/t.c"
"$PREFIX/bin/flexspin" -2 -q -o "$SMOKE/t.binary" "$SMOKE/t.c"
[ -s "$SMOKE/t.binary" ] || { echo "error: smoke test produced no binary" >&2; exit 1; }

log "installed: $("$PREFIX/bin/flexspin" --version 2>&1 | grep -m1 -i version)"
log "flexspin = $PREFIX/bin/flexspin"
