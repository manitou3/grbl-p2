#!/usr/bin/env bash
# Download the reference documents listed in docs/ref/manifest.tsv into
# docs/ref/vendor/ (git-ignored; nothing fetched here is ever committed).
#
#   tools/fetch_ref_docs.sh [--refresh] [--strict] [--check] [--only ID]...
#
#   (default)  fetch anything missing; files with a pinned sha256 are
#              re-fetched if their hash is wrong; existing unpinned files are kept
#   --refresh  re-download unpinned (live) documents as well
#   --check    no network: verify what is already in vendor/ against the manifest
#   --strict   exit non-zero if any document could not be fetched
#   --only ID  restrict to one manifest id (repeatable)
#
# Exit status: 1 on a sha256 mismatch or a bad manifest (always fatal);
# download failures (404, captcha/HTML pages, network) are reported and only
# fail the run with --strict. A per-run record is written to
# docs/ref/vendor/FETCHED.tsv (id, status, sha256, bytes, url, time UTC).
set -euo pipefail

TOOLS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$TOOLS_DIR/.." && pwd)"
MANIFEST="${REF_MANIFEST:-$REPO_ROOT/docs/ref/manifest.tsv}"
VENDOR="${REF_VENDOR_DIR:-$REPO_ROOT/docs/ref/vendor}"
UA="Mozilla/5.0 (X11; Linux x86_64) grbl-p2-fetch_ref_docs"

REFRESH=0 STRICT=0 CHECK=0
ONLY=()
while [ $# -gt 0 ]; do
  case "$1" in
    --refresh) REFRESH=1; shift ;;
    --strict) STRICT=1; shift ;;
    --check) CHECK=1; shift ;;
    --only) ONLY+=("$2"); shift 2 ;;
    --only=*) ONLY+=("${1#*=}"); shift ;;
    -h|--help) sed -n '2,19p' "$0"; exit 0 ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
done

[ -r "$MANIFEST" ] || { echo "error: manifest not found: $MANIFEST" >&2; exit 1; }
command -v curl >/dev/null || { echo "error: curl is required" >&2; exit 1; }
mkdir -p "$VENDOR"
LOG="$VENDOR/FETCHED.tsv"
TMPD="$(mktemp -d)"
trap 'rm -rf "$TMPD"' EXIT
[ "$CHECK" = 1 ] || printf 'id\tstatus\tsha256\tbytes\turl\tretrieved_utc\n' > "$LOG"

sha_of() { sha256sum "$1" | cut -d' ' -f1; }

# Reject HTML error/captcha pages and wrong file types.
kind_ok() {
  local kind="$1" f="$2" head
  [ -s "$f" ] || return 1
  head="$(head -c 512 "$f" | tr -d '\0' | tr '[:upper:]' '[:lower:]')"
  case "$kind" in
    pdf)       [ "$(head -c 4 "$f")" = "%PDF" ] ;;
    docx|xlsx) [ "$(head -c 2 "$f")" = "PK" ] ;;
    text|csv)  case "$head" in *"<!doctype html"*|*"<html"*) return 1 ;; *) return 0 ;; esac ;;
    *) echo "error: unknown kind '$kind'" >&2; return 1 ;;
  esac
}

wanted() {
  [ ${#ONLY[@]} -eq 0 ] && return 0
  local o; for o in "${ONLY[@]}"; do [ "$o" = "$1" ] && return 0; done
  return 1
}

n_ok=0 n_cached=0 n_fail=0 n_bad=0
failed=() mismatched=()
record() { [ "$CHECK" = 1 ] || printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$@" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" >> "$LOG"; }

lineno=0
while IFS=$'\t' read -r id kind dest sha version licence title urls extra || [ -n "${id:-}" ]; do
  lineno=$((lineno + 1))
  case "${id:-}" in ''|'#'*) continue ;; esac
  if [ -z "${urls:-}" ] || [ -n "${extra:-}" ]; then
    echo "error: $MANIFEST:$lineno: expected 8 tab-separated fields" >&2; exit 1
  fi
  case "$dest" in /*|*..*) echo "error: $MANIFEST:$lineno: unsafe dest '$dest'" >&2; exit 1 ;; esac
  wanted "$id" || continue
  out="$VENDOR/$dest"
  : "$version" "$licence"   # informational columns

  if [ -f "$out" ]; then
    have="$(sha_of "$out")"
    if [ "$sha" != "-" ] && [ "$have" = "$sha" ]; then
      echo "ok      $id (cached, sha256 verified)"; n_cached=$((n_cached + 1)); record "$id" cached-verified "$have" "$(wc -c < "$out")" "-"; continue
    elif [ "$sha" = "-" ] && { [ "$REFRESH" = 0 ] || [ "$CHECK" = 1 ]; }; then
      echo "ok      $id (cached, unpinned)"; n_cached=$((n_cached + 1)); record "$id" cached "$have" "$(wc -c < "$out")" "-"; continue
    elif [ "$sha" != "-" ] && [ "$CHECK" = 1 ]; then
      echo "BAD     $id: sha256 $have != expected $sha" >&2; n_bad=$((n_bad + 1)); mismatched+=("$id"); continue
    fi
  elif [ "$CHECK" = 1 ]; then
    echo "missing $id ($dest)"; n_fail=$((n_fail + 1)); failed+=("$id"); continue
  fi

  got=0 last_err=""
  read -r -a url_list <<< "$urls"
  for url in "${url_list[@]}"; do
    tmp="$TMPD/dl"
    rm -f "$tmp"
    code="$(curl -sSL --retry 2 --retry-delay 2 --connect-timeout 20 --max-time 300 \
                 -A "$UA" -o "$tmp" -w '%{http_code}' "$url" 2>"$TMPD/err" || true)"
    if [ "$code" != "200" ]; then
      last_err="HTTP ${code:-000} $(head -c 200 "$TMPD/err" | tr '\n' ' ')"
      echo "  ..    $id: $last_err from $url" >&2; record "$id" "fail-http-${code:-000}" "-" 0 "$url"; continue
    fi
    if ! kind_ok "$kind" "$tmp"; then
      last_err="not a $kind file (HTML/captcha page?)"
      echo "  ..    $id: $last_err from $url" >&2; record "$id" fail-not-"$kind" "$(sha_of "$tmp")" "$(wc -c < "$tmp")" "$url"; continue
    fi
    have="$(sha_of "$tmp")"
    if [ "$sha" != "-" ] && [ "$have" != "$sha" ]; then
      echo "BAD     $id: sha256 $have != expected $sha (from $url)" >&2
      record "$id" sha256-mismatch "$have" "$(wc -c < "$tmp")" "$url"; last_err="sha256 mismatch"; continue
    fi
    mkdir -p "$(dirname "$out")"
    mv "$tmp" "$out"
    bytes="$(wc -c < "$out" | tr -d ' ')"
    if [ "$sha" != "-" ]; then
      echo "ok      $id ($bytes B, sha256 verified)"; record "$id" fetched-verified "$have" "$bytes" "$url"
    else
      echo "ok      $id ($bytes B, sha256 $have, unpinned)"; record "$id" fetched "$have" "$bytes" "$url"
    fi
    got=1; n_ok=$((n_ok + 1)); break
  done
  if [ "$got" = 0 ]; then
    if [ "$last_err" = "sha256 mismatch" ]; then n_bad=$((n_bad + 1)); mismatched+=("$id")
    else echo "FAILED  $id: $title"; n_fail=$((n_fail + 1)); failed+=("$id"); fi
  fi
done < "$MANIFEST"

echo "---- fetch_ref_docs: $n_ok fetched, $n_cached cached, $n_fail failed, $n_bad sha256 mismatch -> $VENDOR"
[ ${#failed[@]} -eq 0 ] || echo "failed: ${failed[*]} (fetch these by hand into docs/ref/vendor/; see docs/ref/README.md)"
if [ ${#mismatched[@]} -gt 0 ]; then echo "error: sha256 mismatch: ${mismatched[*]}" >&2; exit 1; fi
if [ "$STRICT" = 1 ] && [ ${#failed[@]} -gt 0 ]; then exit 1; fi
exit 0
