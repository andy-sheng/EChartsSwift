#!/bin/zsh
# Capture a same-instance interaction sequence for Native and the real echarts.js reference.

set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
scenario="${1:-}"
output_root="${2:-$repo_root/build/interaction-visuals}"
binary="${DEMO_CAPTURE_BINARY:-}"

if [[ -z "$scenario" ]]; then
  print -u2 "usage: scripts/capture-interaction-visuals.sh <scenario.json> [output-root]"
  exit 2
fi
[[ -f "$scenario" ]] || { print -u2 "scenario not found: $scenario"; exit 2; }

case_id="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["id"])' "$scenario")"
case "$case_id" in
  ''|*[!A-Za-z0-9_-]*) print -u2 "scenario id must contain only letters, numbers, dash, underscore"; exit 2 ;;
esac

if [[ -z "$binary" ]]; then
  swift build --package-path "$repo_root/Examples/PainterGallery" --product EChartsDemoGallery
  bin_dir="$(swift build --package-path "$repo_root/Examples/PainterGallery" --show-bin-path | tail -1)"
  binary="$bin_dir/EChartsDemoGallery"
fi
[[ -x "$binary" ]] || { print -u2 "EChartsDemoGallery binary is not executable: $binary"; exit 2; }

case_root="$output_root/$case_id"
native_dir="$case_root/frames/native"
web_dir="$case_root/frames/web"
mkdir -p "$native_dir" "$web_dir"
rm -f "$native_dir"/*.png(N) "$web_dir"/*.png(N)

"$binary" --interaction-native "$scenario" "$native_dir" "$case_root/resolved.native.json"
"$binary" --interaction-web "$scenario" "$web_dir" "$case_root/resolved.web.json"
"$binary" --interaction-contact "$scenario" "$case_root"
python3 "$repo_root/scripts/interaction-visual-report.py" "$scenario" "$case_root"

print "visual-agent input: $case_root/review-request.json"
