#!/bin/zsh
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
output_root="${1:-$repo_root/build/race-animation-validation}"

cd "$repo_root"

validate_case() {
  local demo="$1"
  local offsets="$2"
  local output_dir="$output_root/$demo"

  mkdir -p "$output_dir"
  swift run EChartsDemoGallery --anim-native "$demo" "$output_dir" "$offsets"
  swift run EChartsDemoGallery --anim-web "$demo" "$output_dir" "$offsets"
  swift run EChartsDemoGallery --anim-invariant "$demo" "$offsets" \
    > "$output_dir/invariants.txt"
}

# Include a settled frame, several samples inside the first update, the update boundary, and a sample
# inside the next cycle. The longer line/custom examples need their own later checkpoints.
validate_case official-bar-race "500,1100,1500,2000,2500,3100,3500,4000,4500"
validate_case official-bar-race-country "500,1100,1500,2000,2500,3100,3500,4000"
validate_case official-custom-spiral-race "500,1100,2000,3000,4500,6500,8000"
validate_case official-line-race "500,1500,3000,5000,7500,10000"

print "Race animation captures: $output_root"
print "Compare each *.native.png with the same-time *.web.png and inspect invariants.txt."
