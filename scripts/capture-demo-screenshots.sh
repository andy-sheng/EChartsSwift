#!/bin/zsh
# Capture deterministic animation keyframes for any gallery demo and renderer.
# Run with --help for examples and all options.

set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
output_root="$repo_root/build/demo-screenshots"
renderers_csv="native,web"
interval_ms=250
duration_ms=2000
times_csv=""
config="${DEMO_CAPTURE_CONFIG:-debug}"
binary="${DEMO_CAPTURE_BINARY:-}"
force="${DEMO_CAPTURE_FORCE:-0}"
reference=""
case_names=()

usage() {
  cat <<'EOF'
Usage: scripts/capture-demo-screenshots.sh [options] [demo ...]

Options:
  -r, --renderers LIST   Comma-separated native,raster,web (default: native,web)
  -c, --cases LIST       Comma-separated demo names (default: all registered demos)
  -i, --interval MS      Animation sample interval (default: 250)
  -d, --duration MS      Last animation sample time (default: 2000)
  -t, --times LIST       Exact comma-separated times; overrides interval/duration
  -o, --output DIR       Output directory (default: build/demo-screenshots)
      --reference NAME   Comparison reference renderer (default: web, or last renderer)
      --binary PATH      Existing EChartsDemoGallery binary; skips Swift build
      --config NAME      Swift build configuration: debug or release (default: debug)
  -f, --force            Replace existing screenshots
  -h, --help             Show this help

Demo names can also be passed positionally. Repeating --cases is supported.

Examples:
  # All registered demos, Native compared with Web, every 250ms through 2000ms.
  scripts/capture-demo-screenshots.sh

  # One demo through Rasterizer Metal and Web, every 100ms through 1000ms.
  scripts/capture-demo-screenshots.sh -r raster,web -c official-area-pieces -i 100 -d 1000

  # Several demos and exact keyframes, without a comparison renderer.
  scripts/capture-demo-screenshots.sh -r native -t 0,150,500,1000 \
    official-line-sections official-line-polar2

Environment equivalents:
  DEMO_CAPTURE_BINARY, DEMO_CAPTURE_CONFIG, DEMO_CAPTURE_FORCE

Output:
  <output>/<demo>/contacts/entrance-page-XXX.png
  <output>/<demo>/frames/{web,native,raster}/<demo>.tXXXX.<platform>.png
  <output>/<demo>/report/<platform>-vs-<reference>.tsv
  <output>/<demo>/report/logs/<platform>.log
EOF
}

append_cases() {
  local value="$1"
  local item
  for item in "${(@s:,:)value}"; do
    [[ -n "$item" ]] && case_names+=("$item")
  done
}

while (( $# > 0 )); do
  case "$1" in
    -r|--renderer|--renderers)
      (( $# >= 2 )) || { print -u2 "missing value for $1"; exit 2; }
      renderers_csv="$2"; shift 2 ;;
    -c|--case|--cases)
      (( $# >= 2 )) || { print -u2 "missing value for $1"; exit 2; }
      append_cases "$2"; shift 2 ;;
    -i|--interval)
      (( $# >= 2 )) || { print -u2 "missing value for $1"; exit 2; }
      interval_ms="$2"; shift 2 ;;
    -d|--duration)
      (( $# >= 2 )) || { print -u2 "missing value for $1"; exit 2; }
      duration_ms="$2"; shift 2 ;;
    -t|--times)
      (( $# >= 2 )) || { print -u2 "missing value for $1"; exit 2; }
      times_csv="$2"; shift 2 ;;
    -o|--output)
      (( $# >= 2 )) || { print -u2 "missing value for $1"; exit 2; }
      output_root="$2"; shift 2 ;;
    --reference)
      (( $# >= 2 )) || { print -u2 "missing value for $1"; exit 2; }
      reference="$2"; shift 2 ;;
    --binary)
      (( $# >= 2 )) || { print -u2 "missing value for $1"; exit 2; }
      binary="$2"; shift 2 ;;
    --config)
      (( $# >= 2 )) || { print -u2 "missing value for $1"; exit 2; }
      config="$2"; shift 2 ;;
    -f|--force) force=1; shift ;;
    -h|--help) usage; exit 0 ;;
    --) shift; case_names+=("$@"); break ;;
    -*) print -u2 "unknown option: $1"; usage >&2; exit 2 ;;
    *) case_names+=("$1"); shift ;;
  esac
done

case "$config" in
  debug|release) ;;
  *) print -u2 "--config must be debug or release"; exit 2 ;;
esac
case "$force" in
  0|1) ;;
  *) print -u2 "DEMO_CAPTURE_FORCE must be 0 or 1"; exit 2 ;;
esac

if [[ -z "$times_csv" ]]; then
  case "$interval_ms" in ''|*[!0-9]*) print -u2 "--interval must be a positive integer"; exit 2 ;; esac
  case "$duration_ms" in ''|*[!0-9]*) print -u2 "--duration must be a non-negative integer"; exit 2 ;; esac
  (( interval_ms > 0 )) || { print -u2 "--interval must be greater than zero"; exit 2; }
  time_values=()
  for (( time_ms = 0; time_ms <= duration_ms; time_ms += interval_ms )); do
    time_values+=("$time_ms")
  done
  if (( ${time_values[-1]} != duration_ms )); then
    time_values+=("$duration_ms")
  fi
else
  time_values=()
  for time_ms in "${(@s:,:)times_csv}"; do
    case "$time_ms" in ''|*[!0-9]*) print -u2 "--times values must be non-negative integers"; exit 2 ;; esac
    (( ${time_values[(Ie)$time_ms]} == 0 )) && time_values+=("$time_ms")
  done
  (( ${#time_values} > 0 )) || { print -u2 "--times must contain at least one value"; exit 2; }
  time_values=("${(@on)time_values}")
fi
offsets="${(j:,:)time_values}"

renderers=()
for renderer in "${(@s:,:)renderers_csv}"; do
  case "$renderer" in
    native|raster|web) ;;
    *) print -u2 "unknown renderer '$renderer'; expected native, raster, or web"; exit 2 ;;
  esac
  (( ${renderers[(Ie)$renderer]} == 0 )) && renderers+=("$renderer")
done
(( ${#renderers} > 0 )) || { print -u2 "select at least one renderer"; exit 2; }

if [[ -z "$binary" ]]; then
  print "Building EChartsDemoGallery ($config)..."
  swift build --package-path "$repo_root" -c "$config" --product EChartsDemoGallery
  bin_dir="$(swift build --package-path "$repo_root" -c "$config" --show-bin-path | tail -1)"
  binary="$bin_dir/EChartsDemoGallery"
fi
[[ -x "$binary" ]] || { print -u2 "EChartsDemoGallery binary is not executable: $binary"; exit 2; }

registry_file="$(mktemp -t echarts-demo-registry.XXXXXX)"
trap 'rm -f "$registry_file"' EXIT
"$binary" --list > "$registry_file"

registered_cases=("${(@f)$(cut -f1 "$registry_file")}")
if (( ${#case_names} == 0 )) || [[ "${case_names[1]:-}" == "all" ]]; then
  case_names=("${registered_cases[@]}")
else
  unique_cases=()
  for demo in "${case_names[@]}"; do
    if (( ${registered_cases[(Ie)$demo]} == 0 )); then
      print -u2 "unknown demo: $demo"
      exit 2
    fi
    (( ${unique_cases[(Ie)$demo]} == 0 )) && unique_cases+=("$demo")
  done
  case_names=("${unique_cases[@]}")
fi

if [[ -n "$reference" ]] && (( ${renderers[(Ie)$reference]} == 0 )); then
  print -u2 "--reference '$reference' is not in --renderers"
  exit 2
fi

platform_for_renderer() {
  print "$1"
}

if [[ -z "$reference" ]] && (( ${#renderers} >= 2 )); then
  if (( ${renderers[(Ie)web]} != 0 )); then reference=web
  else reference="${renderers[-1]}"
  fi
fi

mkdir -p "$output_root"
failure_count=0
skip_count=0
total=${#case_names}
index=0

is_native_supported() {
  awk -F '\t' -v demo="$1" '$1 == demo && $3 == "native:yes" { found=1 } END { exit !found }' "$registry_file"
}

has_all_frames() {
  local demo="$1"
  local renderer="$2"
  local platform="$(platform_for_renderer "$renderer")"
  local time_ms tag
  for time_ms in "${time_values[@]}"; do
    printf -v tag '%04d' "$time_ms"
    [[ -f "$output_root/$demo/frames/$platform/$demo.t$tag.$platform.png" ]] || return 1
  done
  return 0
}

has_any_frames() {
  local -a matches
  matches=("$1"/*.png(N))
  (( ${#matches} > 0 ))
}

for demo in "${case_names[@]}"; do
  index=$((index + 1))
  case_root="$output_root/$demo"
  frames_root="$case_root/frames"
  logs_root="$case_root/report/logs"
  mkdir -p "$case_root/contacts" "$frames_root/web" "$frames_root/native" \
    "$frames_root/raster" "$logs_root"
  print "[$index/$total] $demo ($offsets ms)"

  for renderer in "${renderers[@]}"; do
    platform="$(platform_for_renderer "$renderer")"
    renderer_dir="$frames_root/$platform"
    log="$logs_root/$platform.log"
    failed="$logs_root/$platform.failed"
    skipped="$logs_root/$platform.skipped"
    rm -f "$failed" "$skipped"

    if [[ "$renderer" != "web" ]] && ! is_native_supported "$demo"; then
      print "  $renderer: skipped (native unsupported)"
      print "native unsupported" > "$skipped"
      skip_count=$((skip_count + 1))
      continue
    fi
    if [[ "$force" != "1" ]] && has_all_frames "$demo" "$renderer"; then
      print "  $renderer: cached"
      continue
    fi

    case "$renderer" in
      native)
        print "  native: capturing deterministic keyframes"
        if ! "$binary" --entrance-native "$demo" "$renderer_dir" "$offsets" > "$log" 2>&1; then
          print "capture failed" > "$failed"; failure_count=$((failure_count + 1))
        fi
        ;;
      web)
        print "  web: capturing deterministic keyframes"
        if ! "$binary" --entrance-web "$demo" "$renderer_dir" "$offsets" > "$log" 2>&1; then
          print "capture failed" > "$failed"; failure_count=$((failure_count + 1))
        fi
        ;;
      raster)
        # CAMetalLayer headless captures must remain serial to avoid exhausting drawable availability.
        : >| "$log"
        renderer_failed=0
        for time_ms in "${time_values[@]}"; do
          printf -v tag '%04d' "$time_ms"
          png="$renderer_dir/$demo.t$tag.raster.png"
          if [[ "$force" != "1" && -f "$png" ]]; then
            print "  raster: t=$time_ms cached"
            continue
          fi
          print "  raster: t=$time_ms"
          if ! "$binary" --render-rasterizer "$demo" "$png" "$time_ms" >> "$log" 2>&1; then
            renderer_failed=1
          fi
        done
        if (( renderer_failed != 0 )); then
          print "one or more frames failed" > "$failed"; failure_count=$((failure_count + 1))
        fi
        ;;
    esac
  done
done

if python3 -c 'from PIL import Image' >/dev/null 2>&1; then
  reference_platform=""
  [[ -n "$reference" ]] && reference_platform="$(platform_for_renderer "$reference")"
  for demo in "${case_names[@]}"; do
    case_root="$output_root/$demo"
    frames_root="$case_root/frames"
    available_platforms=()
    for renderer in "${renderers[@]}"; do
      platform="$(platform_for_renderer "$renderer")"
      if has_any_frames "$frames_root/$platform"; then
        available_platforms+=("$platform")
      fi
    done

    if (( ${#available_platforms} > 0 )); then
      platforms="${(j:,:)available_platforms}"
      contacts="$case_root/contacts"
      python3 "$repo_root/scripts/entrance-visual-report.py" "$frames_root" \
        --platforms "$platforms" --contacts "$contacts" --page-prefix entrance-page
      print "contact sheet:  $contacts/entrance-page-001.png"
    fi

    if (( ${#available_platforms} >= 2 )) && (( ${available_platforms[(Ie)$reference_platform]} != 0 )); then
      for platform in "${available_platforms[@]}"; do
        [[ "$platform" == "$reference_platform" ]] && continue
        report="$case_root/report/$platform-vs-$reference_platform.tsv"
        python3 "$repo_root/scripts/entrance-visual-report.py" "$frames_root" \
          --native-platform "$platform" --web-platform "$reference_platform" \
          --tsv "$report"
        print "report:         $report"
      done
    fi
  done
else
  print -u2 "warning: Pillow is unavailable; screenshots were captured without contacts/reports"
fi

print "output:         $output_root"
print "failures:       $failure_count"
print "skipped:        $skip_count"
(( failure_count == 0 ))
