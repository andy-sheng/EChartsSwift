#!/bin/zsh
# Generate and capture every demo shown under the official gallery's `scatter` section.

set -u
set -o pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
binary="${DEMO_CAPTURE_BINARY:-$repo_root/.build/debug/EChartsDemoGallery}"
scenario_root="${1:-$repo_root/build/scatter-interaction-scenarios}"
output_root="${2:-$repo_root/build/scatter-interaction-visuals}"

[[ -x "$binary" ]] || {
  print -u2 "EChartsDemoGallery binary is not executable: $binary"
  exit 2
}

mkdir -p "$scenario_root" "$output_root"
"$binary" --interaction-generate-scatter "$scenario_root" || exit 1

passed=()
failed=()
scenarios=("$scenario_root"/scatter-all-*.json(N))
total=${#scenarios}
index=0
for scenario in "${scenarios[@]}"; do
  index=$((index + 1))
  case_id="${scenario:t:r}"
  print "[$index/$total] $case_id"
  if DEMO_CAPTURE_BINARY="$binary" \
      "$repo_root/scripts/capture-interaction-visuals.sh" "$scenario" "$output_root"; then
    passed+=("$case_id")
  else
    failed+=("$case_id")
    print -u2 "FAILED $case_id"
  fi
done

print "scatter interaction captures: ${#passed} passed, ${#failed} failed, $total total"
if (( ${#failed} > 0 )); then
  print -u2 "failed cases: ${(j:, :)failed}"
  exit 1
fi
