#!/usr/bin/env bash
#
# Sync the pinned upstream reference checkouts for the Swift port.
#
# Reads upstream/upstream.lock and checks out each repo at its EXACT commit,
# then fetches the matching prebuilt echarts dist (needed by
# Oracle/dump-displaylist.js to regenerate golden fixtures — echarts gitignores
# its own dist/, so a source checkout alone does not contain it).
#
# Usage:
#   scripts/sync-upstream.sh              clone/fetch each repo to the locked SHA + get dist
#   scripts/sync-upstream.sh --check      verify checkouts match the lock; non-zero exit on drift
#   scripts/sync-upstream.sh --force-dist re-download the echarts dist even if present
#
# To bump a version: edit upstream/upstream.lock (new SHA + version), re-run this
# script, regenerate fixtures (cd Oracle && ECHARTS_DIST=../upstream/echarts/dist/echarts.js
# node dump-displaylist.js), update the Swift mirrors for whatever changed, and `swift test`.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOCK="$ROOT/upstream/upstream.lock"
CDN="https://cdn.jsdelivr.net/npm"

CHECK_ONLY=0
FORCE_DIST=0
for a in "$@"; do
  case "$a" in
    --check)      CHECK_ONLY=1 ;;
    --force-dist) FORCE_DIST=1 ;;
    -h|--help)    sed -n '2,20p' "$0"; exit 0 ;;
    *) echo "unknown arg: $a" >&2; exit 2 ;;
  esac
done

[ -f "$LOCK" ] || { echo "missing lock file: $LOCK" >&2; exit 1; }

fail=0
echarts_version=""

while read -r name url sha version _rest; do
  [ -z "${name:-}" ] && continue
  case "$name" in \#*) continue ;; esac
  dir="$ROOT/upstream/$name"
  [ "$name" = "echarts" ] && echarts_version="$version"

  if [ "$CHECK_ONLY" = 1 ]; then
    if [ -d "$dir/.git" ]; then
      cur="$(git -C "$dir" rev-parse HEAD)"
      if [ "$cur" = "$sha" ]; then
        echo "ok      $name $sha (v$version)"
      else
        echo "DRIFT   $name: have ${cur:0:12}, want ${sha:0:12}" >&2; fail=1
      fi
    else
      echo "MISSING $name checkout at $dir" >&2; fail=1
    fi
    continue
  fi

  if [ ! -d "$dir/.git" ]; then
    echo ">> cloning $name ..."
    # partial clone: full history graph, blobs fetched lazily — lets us check out any SHA cheaply
    git clone --filter=blob:none "$url" "$dir"
  fi
  cur="$(git -C "$dir" rev-parse HEAD 2>/dev/null || echo none)"
  if [ "$cur" != "$sha" ]; then
    echo ">> $name: checking out ${sha:0:12} ..."
    git -C "$dir" fetch --depth 1 origin "$sha" 2>/dev/null || git -C "$dir" fetch origin
    git -C "$dir" checkout --quiet --detach "$sha"
  fi
  echo "ok      $name $(git -C "$dir" rev-parse --short HEAD) (v$version)"
done < "$LOCK"

# echarts prebuilt dist — pinned by version, pulled from the npm CDN (no local build needed)
dist="$ROOT/upstream/echarts/dist/echarts.js"
if [ "$CHECK_ONLY" = 1 ]; then
  if [ -f "$dist" ]; then echo "ok      echarts dist present"; else echo "MISSING echarts dist ($dist) — run without --check" >&2; fail=1; fi
elif [ -n "$echarts_version" ]; then
  if [ "$FORCE_DIST" = 1 ] || [ ! -f "$dist" ]; then
    echo ">> downloading echarts@$echarts_version prebuilt dist ..."
    mkdir -p "$(dirname "$dist")"
    curl -fsSL "$CDN/echarts@$echarts_version/dist/echarts.js" -o "$dist"
  fi
  echo "ok      echarts dist (v$echarts_version)"
fi

if [ "$fail" -ne 0 ]; then
  echo "" >&2
  echo "checkouts do not match upstream.lock — run scripts/sync-upstream.sh to reconcile" >&2
fi
exit "$fail"
