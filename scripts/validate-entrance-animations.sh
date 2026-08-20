#!/bin/zsh
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
output_root="${1:-$repo_root/build/entrance-animation-validation}"
demo_list="${2:-/tmp/entrance-demos.txt}"
offsets="${ENTRANCE_OFFSETS:-0,250,500,800,1200,1800,2600,4000}"
binary="${ENTRANCE_BINARY:-$repo_root/.build/release/EChartsDemoGallery}"
force_web="${ENTRANCE_FORCE_WEB:-0}"

if [[ ! -s "$demo_list" ]]; then
  print -u2 "missing animated-demo list: $demo_list"
  exit 2
fi

mkdir -p "$output_root/frames" "$output_root/logs"
total="$(wc -l < "$demo_list" | tr -d ' ')"
index=0

while IFS= read -r demo; do
  [[ -z "$demo" ]] && continue
  index=$((index + 1))
  demo_dir="$output_root/frames/$demo"
  mkdir -p "$demo_dir"
  print "[$index/$total] $demo"

  if [[ ! -f "$demo_dir/$demo.t4000.native.png" && ! -f "$output_root/logs/$demo.native.failed" ]]; then
    if ! "$binary" --entrance-native "$demo" "$demo_dir" "$offsets" \
      > "$output_root/logs/$demo.native.log" 2>&1; then
      print "native capture failed" > "$output_root/logs/$demo.native.failed"
    fi
  fi
  if [[ "$force_web" == "1" || ( ! -f "$demo_dir/$demo.t4000.web.png" && ! -f "$output_root/logs/$demo.web.failed" ) ]]; then
    if ! "$binary" --entrance-web "$demo" "$demo_dir" "$offsets" \
      > "$output_root/logs/$demo.web.log" 2>&1; then
      print "web capture failed" > "$output_root/logs/$demo.web.failed"
    fi
  fi
done < "$demo_list"

python3 "$repo_root/scripts/entrance-visual-report.py" "$output_root/frames" \
  --tsv "$output_root/report.tsv" \
  --contacts "$output_root/contacts"

print "visual report: $output_root/report.tsv"
print "contact sheets: $output_root/contacts"
print "capture failures: $(find "$output_root/logs" -name '*.failed' | wc -l | tr -d ' ')"
