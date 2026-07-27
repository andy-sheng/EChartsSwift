#!/bin/bash
# scene-sweep.sh — drive the structural (scene-graph) sweep to completion across hard crashes.
#
# `--scene-sweep-native` is resumable: it claims each slot with a `.skip` marker before running it, so
# a slot that hard-crashes the process (fatalError / index-out-of-range are not catchable in Swift) is
# stepped over on the next invocation and is left identifiable as the one slot with a `.skip` and no
# `.json`. Re-invoking here until a pass adds nothing new drives the whole corpus to completion.
#
# Usage: scripts/scene-sweep.sh <manifest.json> <outdir> [maxPasses]
set -u
MANIFEST="${1:?usage: scene-sweep.sh <manifest.json> <outdir> [maxPasses]}"
OUTDIR="${2:?usage: scene-sweep.sh <manifest.json> <outdir> [maxPasses]}"
MAXPASS="${3:-60}"
BIN=".build/debug/EChartsDemoGallery"

[ -x "$BIN" ] || { echo "build first: swift build"; exit 1; }
mkdir -p "$OUTDIR"

# Progress is measured in CLAIMED slots (dump OR marker), not in dumps: several consecutive slots can
# crash, and a dumps-only counter would read that as "no progress" and stop with the rest of the corpus
# never attempted.
claimed() { ls "$OUTDIR"/*.native.json "$OUTDIR"/*.native.json.skip 2>/dev/null | wc -l | tr -d ' '; }

for ((pass = 1; pass <= MAXPASS; pass++)); do
    before=$(claimed)
    beforeDumps=$(ls "$OUTDIR"/*.native.json 2>/dev/null | wc -l | tr -d ' ')
    # The crashing slot is whatever RUN line came last on stderr.
    last=$("$BIN" --scene-sweep-native "$MANIFEST" "$OUTDIR" 2>&1 >/dev/null | grep '^RUN ' | tail -1)
    after=$(claimed)
    afterDumps=$(ls "$OUTDIR"/*.native.json 2>/dev/null | wc -l | tr -d ' ')
    echo "pass $pass: claimed $before -> $after (dumps $beforeDumps -> $afterDumps) ${last:+last=$last}"
    [ "$after" = "$before" ] && { echo "all slots claimed; done"; break; }
done

echo
echo "=== CRASHED SLOTS (claimed but never produced a dump) ==="
for f in "$OUTDIR"/*.native.json.skip; do
    [ -e "$f" ] || continue
    base="${f%.skip}"
    [ -e "$base" ] || echo "  $(basename "$base" .native.json)"
done
