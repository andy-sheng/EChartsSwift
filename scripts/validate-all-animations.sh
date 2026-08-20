#!/bin/zsh
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
output_root="${1:-$repo_root/build/animation-validation}"
binary="$repo_root/.build/release/EChartsDemoGallery"
capture_frames="${ANIMATION_CAPTURE_FRAMES:-1}"

mkdir -p "$output_root"
cd "$repo_root"

swift build -c release
"$binary" --scene-manifest "$output_root/manifest.json" 2
"$binary" --list-driven > "$output_root/driven-demos.txt"

# Layer 1: all native-supported examples. Compare animator presence on initial render and on the
# same first reachable update (currently a legend/dataZoom action when derivable, otherwise a
# merge-mode option refresh). Both TSV writers are durable/resumable.
"$binary" --anim-probe "$output_root/manifest.json" "$output_root/native-animation.tsv"
"$binary" --anim-probe-web "$output_root/manifest.json" "$output_root/web-animation.tsv"

awk -F '\t' 'NR==FNR { if (NR > 1) web[$1]=$2 FS $3 FS $4 FS $5; next }
  NR > 1 && ($1 in web) { split(web[$1], w, FS); print $1 FS $2 FS $3 FS $4 FS $5 FS $6 FS w[1] FS w[2] FS w[3] FS w[4] }' \
  "$output_root/web-animation.tsv" "$output_root/native-animation.tsv" \
  > "$output_root/animation-joined.tsv"

awk -F '\t' '$4 ~ /^[0-9]+$/ && $8 ~ /^[0-9]+$/ && (($4 == 0) != ($8 == 0)) {
  print $1 "\tnative=" $4 "/" $3 "\tweb=" $8 "/" $7
}' "$output_root/animation-joined.tsv" > "$output_root/initial-presence-mismatches.tsv"

awk -F '\t' '$6 ~ /^[0-9]+$/ && $10 ~ /^[0-9]+$/ && (($6 == 0) != ($10 == 0)) {
  print $1 "\tnative=" $6 "/" $5 "\tweb=" $10 "/" $9
}' "$output_root/animation-joined.tsv" > "$output_root/update-presence-mismatches.tsv"

# Layer 2: every timer-driven native example. Identity overlap catches update-time rebuild/reset
# bugs; the disabled pass proves the UI switch suppresses interpolation without pausing data.
while IFS= read -r demo; do
  case "$demo" in
    official-custom-spiral-race) offsets="500,1100,2000,3000,4500,6500,8000" ;;
    official-bar-race) offsets="500,1100,2000,2900,3100,3500,4000" ;;
    official-bar-race-country) offsets="100,250,500,900,1300,1800,2500" ;;
    *graph-force-dynamic*) offsets="100,250,450,750,1100,1600,2200" ;;
    *scatter-symbol-morph*) offsets="100,500,800,1100,1500,2200,2900" ;;
    *pictorialBar-forest*) offsets="100,500,900,1200,1700,2500,3300" ;;
    *pictorialBar-bar-transition*) offsets="100,1000,2400,2600,2800,3300,5000" ;;
    *custom-gauge*|*treemap-sunburst-transition*) offsets="100,1000,2900,3100,3500,4500,6000" ;;
    *) offsets="100,700,1100,1900,2100,2500,3200" ;;
  esac
  demo_dir="$output_root/driven/$demo"
  mkdir -p "$demo_dir"
  "$binary" --anim-invariant "$demo" "$offsets" > "$demo_dir/invariants.txt"
  "$binary" --anim-disabled-invariant "$demo" "$offsets" > "$demo_dir/disabled.txt"
  if [[ "$capture_frames" == "1" ]]; then
    "$binary" --anim-native "$demo" "$demo_dir" "$offsets"
    "$binary" --anim-web "$demo" "$demo_dir" "$offsets"
  fi
done < "$output_root/driven-demos.txt"

print "initial presence mismatches: $(wc -l < "$output_root/initial-presence-mismatches.tsv" | tr -d ' ')"
print "update presence mismatches:  $(wc -l < "$output_root/update-presence-mismatches.tsv" | tr -d ' ')"
print "driven examples:             $(wc -l < "$output_root/driven-demos.txt" | tr -d ' ')"
print "report: $output_root"
