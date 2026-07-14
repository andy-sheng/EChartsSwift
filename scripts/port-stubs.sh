#!/usr/bin/env bash
#
# Which demos silently depend on behaviour we never implemented?
#
# The port's most expensive bugs were not missing files — they were empty function BODIES inside
# files marked ported. `registerSubTypeDefaulter` was a no-op, so every axis written the way the
# official examples write them (`xAxis: { data: [...] }`, no `type`) quietly became a VALUE axis: a
# plausible chart, so nothing crashed and no test went red. It survived until an official example was
# rendered next to real echarts.
#
# A stub that CRASHES is harmless: it announces itself on day one. A stub that silently degrades can
# live for a year. This script converts the second kind into the first — it renders every demo and
# reports, per unimplemented behaviour, exactly which demos depend on it.
#
# Each demo runs in its OWN process: some still hit a `fatalError`, and an in-process sweep would be
# killed by the first one, losing the whole report to the very kind of gap it exists to find. A crash
# is itself a finding, so it is reported too.
#
# Usage:
#   scripts/port-stubs.sh            report against the debug build (builds it if needed)
#   scripts/port-stubs.sh --check    non-zero if any NEW stub id appears that is not in the baseline
#                                    below — so a new silent stub cannot be added unnoticed
#
# To close a gap: implement it, delete its `PortStub.hit(...)` call, and drop its id from BASELINE.

set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

# Stub ids known to be hit today. This is the inventory — it may only ever SHRINK.
BASELINE=(
  "axisModelCreator.registerComponentModel"
  "axisModelCreator.registerSubTypeDefaulter"
  "SliderZoomView._showDataInfo"
  "toolboxFeatures.SaveAsImage"
  "axisStatistics.EChartsExtensionInstallRegisters.registerProcessor"
)

CHECK=0
[ "${1:-}" = "--check" ] && CHECK=1

BIN=".build/debug/EChartsDemoGallery"
[ -x "$BIN" ] || swift build --product EChartsDemoGallery >/dev/null || exit 1

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

"$BIN" --list 2>/dev/null | awk -F'\t' '$3 == "native:yes" { print $1 }' > "$TMP/demos.txt"
total=$(wc -l < "$TMP/demos.txt" | tr -d ' ')

crashed=0
while read -r name; do
  if ! "$BIN" --port-stubs "$name" > "$TMP/out" 2>/dev/null; then
    echo "$name" >> "$TMP/crashed.txt"; crashed=$((crashed + 1)); continue
  fi
  # STUB \t id \t count \t consequence
  awk -F'\t' -v d="$name" '$1 == "STUB" { print $2 "\t" $4 "\t" d }' "$TMP/out" >> "$TMP/hits.tsv"
done < "$TMP/demos.txt"

echo "swept $total native demos"
echo

if [ -s "$TMP/hits.tsv" ]; then
  echo "UNIMPLEMENTED BEHAVIOUR THAT DEMOS ACTUALLY DEPEND ON"
  echo
  cut -f1 "$TMP/hits.tsv" | sort -u | while read -r id; do
    n=$(awk -F'\t' -v i="$id" '$1 == i' "$TMP/hits.tsv" | cut -f3 | sort -u | wc -l | tr -d ' ')
    why=$(awk -F'\t' -v i="$id" '$1 == i { print $2; exit }' "$TMP/hits.tsv")
    printf '  %-58s %s demo(s)\n      %s\n' "$id" "$n" "$why"
  done
  echo
else
  echo "no PORT-STUB hit by any demo"
  echo
fi

if [ -s "$TMP/crashed.txt" ]; then
  echo "CRASHED (a loud gap — these are the easy kind):"
  sed 's/^/  /' "$TMP/crashed.txt"
  echo
fi

if [ "$CHECK" = 1 ]; then
  status=0
  while read -r id; do
    known=0
    for b in "${BASELINE[@]}"; do [ "$b" = "$id" ] && known=1; done
    if [ "$known" = 0 ]; then
      echo "NEW SILENT STUB (not in scripts/port-stubs.sh BASELINE): $id" >&2
      status=1
    fi
  done < <(cut -f1 "$TMP/hits.tsv" 2>/dev/null | sort -u)
  exit $status
fi
