#!/usr/bin/env bash
#
# Sync the pinned mindbrix/Rasterizer checkout for the experimental Metal painter.
#
# Reads third_party/rasterizer.lock, checks the repo out at its EXACT commit,
# copies the SwiftPM package (the repo's Package/ subtree + LICENSE.txt) into
# third_party/Rasterizer/, and applies third_party/rasterizer-local.patch (our
# local modifications). The checkout is gitignored — run this once after clone
# or whenever the lock/patch changes, BEFORE `swift build` (Package.swift has a
# local path dependency on third_party/Rasterizer).
#
# Usage:
#   scripts/sync-rasterizer.sh            reconstruct the checkout from lock + patch
#   scripts/sync-rasterizer.sh --check    verify the checkout matches; non-zero on drift
#
# To bump the pinned commit: edit third_party/rasterizer.lock, re-run this script;
# if the patch no longer applies, re-resolve it against the new base (the patch is a
# plain `git diff --binary` over the Package/ subtree) and update rasterizer-local.patch.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOCK="$ROOT/third_party/rasterizer.lock"
PATCH="$ROOT/third_party/rasterizer-local.patch"
DEST="$ROOT/third_party/Rasterizer"
STAMP="$DEST/.sync-stamp"

CHECK_ONLY=0
for a in "$@"; do
  case "$a" in
    --check)   CHECK_ONLY=1 ;;
    -h|--help) sed -n '2,19p' "$0"; exit 0 ;;
    *) echo "unknown arg: $a" >&2; exit 2 ;;
  esac
done

[ -f "$LOCK" ]  || { echo "missing lock file: $LOCK" >&2; exit 1; }
[ -f "$PATCH" ] || { echo "missing patch file: $PATCH" >&2; exit 1; }

read -r _name URL SHA < <(grep -v '^\s*#' "$LOCK" | grep -v '^\s*$' | head -1)
PATCH_SUM="$(shasum -a 256 "$PATCH" | awk '{print $1}')"
WANT="$SHA $PATCH_SUM"

if [ "$CHECK_ONLY" = 1 ]; then
  if [ -f "$STAMP" ] && [ "$(cat "$STAMP")" = "$WANT" ]; then
    echo "OK: third_party/Rasterizer matches the lock + patch"
    exit 0
  fi
  echo "DRIFT: third_party/Rasterizer missing or stale — run scripts/sync-rasterizer.sh" >&2
  exit 1
fi

if [ -f "$STAMP" ] && [ "$(cat "$STAMP")" = "$WANT" ]; then
  echo "third_party/Rasterizer already up to date ($SHA)"
  exit 0
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "fetching mindbrix/Rasterizer @ $SHA ..."
git clone -q --filter=blob:none "$URL" "$WORK/repo"
git -C "$WORK/repo" checkout -q "$SHA"

echo "staging Package/ + LICENSE.txt ..."
rm -rf "$DEST"
mkdir -p "$DEST"
cp -R "$WORK/repo/Package/." "$DEST/"
cp "$WORK/repo/LICENSE.txt" "$DEST/LICENSE.txt"

echo "applying rasterizer-local.patch ..."
git apply --whitespace=nowarn --directory="third_party/Rasterizer" --unsafe-paths "$PATCH" 2>/dev/null \
  || (cd "$DEST" && git apply --whitespace=nowarn "$PATCH")

echo "$WANT" > "$STAMP"
echo "done: third_party/Rasterizer @ $SHA (+local patch)"
