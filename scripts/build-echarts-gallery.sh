#!/usr/bin/env bash
#
# Build the EChartsDemoGallery test app — renders each demo ECharts `option` two
# ways side-by-side: NATIVE (EChartsKit -> EChartsSlim -> ZRenderKit ->
# NativePainter) and the REAL echarts.js in a WebView. Wraps the steps you'd
# otherwise run by hand:
#
#   1. Sync the pinned upstream checkouts (scripts/sync-upstream.sh).
#   2. Ensure upstream echarts's `dist/echarts.js` is present — the GUI's
#      right-pane WebView and `--web-snapshot`/`--compare` inline this UMD bundle
#      to render the option with the real echarts. The dist is committed / fetched
#      at the pinned SHA, so step 1 normally provides it; we only verify it here.
#   3. Build the EChartsDemoGallery SwiftPM product and stage a launchable .app
#      bundle into ./build/ (gitignored).
#
# Usage:
#   scripts/build-echarts-gallery.sh                fast development build (debug)
#   scripts/build-echarts-gallery.sh --release      optimized, incremental release build
#   scripts/build-echarts-gallery.sh --release-wmo  maximum-optimization release build
#   scripts/build-echarts-gallery.sh --run          launch the app after building
#   scripts/build-echarts-gallery.sh --out <dir>    stage into <dir> instead of ./build
#   scripts/build-echarts-gallery.sh -h | --help
#
# Note: the app resolves upstream/echarts/dist/ via the source path baked in at
# compile time (#filePath), so the staged .app only runs on this machine with the
# repo in place — it is a local dev/test artifact, which is why build/ is ignored.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
EC_DIR="$ROOT/upstream/echarts"
DIST="$EC_DIR/dist/echarts.js"

CONFIG="debug"
WMO=0
RUN=0
OUT="$ROOT/build"

while [ "$#" -gt 0 ]; do
  case "$1" in
    --debug)       CONFIG="debug"; WMO=0 ;;
    --release)     CONFIG="release"; WMO=0 ;;
    --release-wmo) CONFIG="release"; WMO=1 ;;
    --run)     RUN=1 ;;
    --out)     shift; OUT="${1:?--out needs a path}" ;;
    -h|--help) sed -n '2,/^$/p' "$0"; exit 0 ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
  shift
done

# OUT may be relative — anchor it to the repo root if so.
case "$OUT" in /*) ;; *) OUT="$ROOT/$OUT" ;; esac

SWIFT_ARGS=()
BUILD_MODE="$CONFIG"
if [ "$CONFIG" = "release" ]; then
  if [ "$WMO" = 1 ]; then
    BUILD_MODE="release, WMO"
  else
    BUILD_MODE="release, incremental -O"
    SWIFT_ARGS=(--scratch-path "$ROOT/build/swiftpm-release-optimized"
                -Xswiftc -no-whole-module-optimization -Xswiftc -incremental)
  fi
fi

say() { printf '\n\033[1;36m==>\033[0m %s\n' "$*"; }

# ---------------------------------------------------------------------------
# 1. Sync upstream (clone/fetch each repo to the locked SHA + echarts dist).
# ---------------------------------------------------------------------------
say "1/3  Syncing pinned upstream checkouts"
"$ROOT/scripts/sync-upstream.sh"

# ---------------------------------------------------------------------------
# 2. Ensure upstream echarts's dist (the web-pane dependency) is present.
#    Unlike zrender's dist (built from source), the echarts UMD bundle is a
#    prebuilt artifact fetched by sync-upstream; if it's missing, re-run it.
# ---------------------------------------------------------------------------
say "2/3  Ensuring upstream echarts dist (web pane inlines dist/echarts.js)"
if [ ! -f "$DIST" ]; then
  echo "ERROR: $DIST missing." >&2
  echo "       Re-run scripts/sync-upstream.sh to fetch the pinned echarts dist." >&2
  exit 1
fi
echo "ok      dist present ($(cd "$ROOT" && du -h "$DIST" | cut -f1)) — $DIST"

# ---------------------------------------------------------------------------
# 3. Build the EChartsDemoGallery product and stage a launchable .app into ./build.
# ---------------------------------------------------------------------------
say "3/3  Building EChartsDemoGallery ($BUILD_MODE) and staging .app into ${OUT#$ROOT/}"
swift build --package-path "$ROOT" -c "$CONFIG" ${SWIFT_ARGS[@]+"${SWIFT_ARGS[@]}"} --product EChartsDemoGallery
BIN_DIR="$(swift build --package-path "$ROOT" -c "$CONFIG" ${SWIFT_ARGS[@]+"${SWIFT_ARGS[@]}"} \
  --product EChartsDemoGallery --show-bin-path | tail -1)"
BIN="$BIN_DIR/EChartsDemoGallery"
[ -x "$BIN" ] || { echo "ERROR: built binary not found at $BIN" >&2; exit 1; }

APP="$OUT/EChartsDemoGallery.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/EChartsDemoGallery"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>            <string>EChartsDemoGallery</string>
    <key>CFBundleDisplayName</key>     <string>ECharts DemoGallery</string>
    <key>CFBundleExecutable</key>      <string>EChartsDemoGallery</string>
    <key>CFBundleIdentifier</key>      <string>com.ios-chart.echartskit.EChartsDemoGallery</string>
    <key>CFBundlePackageType</key>     <string>APPL</string>
    <key>CFBundleShortVersionString</key> <string>1.0</string>
    <key>CFBundleVersion</key>         <string>1</string>
    <key>LSMinimumSystemVersion</key>  <string>12.0</string>
    <key>NSPrincipalClass</key>        <string>NSApplication</string>
    <key>NSHighResolutionCapable</key> <true/>
</dict>
</plist>
PLIST

# Ad-hoc sign so Gatekeeper/WebKit are happy launching it locally (best-effort).
codesign --force --sign - "$APP" >/dev/null 2>&1 || true

# ---------------------------------------------------------------------------
# Make sure the staging dir is gitignored (it's a local artifact).
# ---------------------------------------------------------------------------
REL_OUT="${OUT#$ROOT/}"
GI="$ROOT/.gitignore"
PATTERN="/$REL_OUT/"
if [ -f "$GI" ] && ! grep -qxF "$PATTERN" "$GI"; then
  printf '\n# EChartsDemoGallery staged .app (local dev/test artifact, built by scripts/build-echarts-gallery.sh)\n%s\n' "$PATTERN" >> "$GI"
  echo "added '$PATTERN' to .gitignore"
fi

say "Done — $APP"
echo "Launch:  open \"$APP\""
echo "  ...or directly:  \"$APP/Contents/MacOS/EChartsDemoGallery\""
echo "CLI:     \"$BIN\" --list | --render <demo> <png> | --compare <demo> <dir>"

if [ "$RUN" = 1 ]; then
  say "Launching EChartsDemoGallery"
  open "$APP"
fi
