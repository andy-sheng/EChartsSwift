#!/usr/bin/env bash
#
# Build the iOS EChartsDemoGallery test app — the same gallery as
# scripts/build-echarts-gallery.sh, but as a UIKit app for the iOS SIMULATOR
# (demo list + native | echarts.js panes, shared demo registry via EChartsDemoCore).
#
#   1. Sync the pinned upstream checkouts (scripts/sync-upstream.sh).
#   2. Ensure upstream echarts's `dist/echarts.js` is present — the detail view's
#      web pane inlines this UMD bundle, read off the HOST filesystem at the
#      source path baked in via #filePath. Only the simulator shares the host
#      filesystem, which is why this app is simulator-only.
#   3. Cross-compile the EChartsDemoGalleryiOS SwiftPM product for the arm64
#      simulator triple and stage a launchable .app bundle into ./build/.
#
# Usage:
#   scripts/build-echarts-gallery-ios.sh              fast development build (debug)
#   scripts/build-echarts-gallery-ios.sh --release    optimized, incremental release build
#   scripts/build-echarts-gallery-ios.sh --release-wmo maximum-optimization release build
#   scripts/build-echarts-gallery-ios.sh --run        install + launch in a booted iPhone simulator
#                                                     (boots the newest available iPhone if none is)
#   scripts/build-echarts-gallery-ios.sh --out <dir>  stage into <dir> instead of ./build
#   scripts/build-echarts-gallery-ios.sh -h | --help
#
# Note: like the mac gallery, the staged .app only runs on this machine with the
# repo in place — it is a local dev/test artifact, which is why build/ is ignored.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST="$ROOT/upstream/echarts/dist/echarts.js"
TRIPLE="arm64-apple-ios15.0-simulator"
BUNDLE_ID="com.ios-chart.echartskit.EChartsDemoGalleryiOS"
# Keep cross-compiled artifacts and SwiftPM's build database separate from the
# host galleries. Sharing .build makes alternating iOS/macOS builds invalidate
# each other's build descriptions and incremental cache.
SCRATCH_PATH="$ROOT/build/swiftpm-ios"

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

case "$OUT" in /*) ;; *) OUT="$ROOT/$OUT" ;; esac

SWIFT_ARGS=(--scratch-path "$SCRATCH_PATH")
BUILD_MODE="$CONFIG"
if [ "$CONFIG" = "release" ]; then
  if [ "$WMO" = 1 ]; then
    BUILD_MODE="release, WMO"
    SWIFT_ARGS=(--scratch-path "$ROOT/build/swiftpm-ios-wmo")
  else
    BUILD_MODE="release, incremental -O"
    SWIFT_ARGS+=( -Xswiftc -no-whole-module-optimization -Xswiftc -incremental )
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
# ---------------------------------------------------------------------------
say "2/3  Ensuring upstream echarts dist (web pane inlines dist/echarts.js)"
if [ ! -f "$DIST" ]; then
  echo "ERROR: $DIST missing." >&2
  echo "       Re-run scripts/sync-upstream.sh to fetch the pinned echarts dist." >&2
  exit 1
fi
echo "ok      dist present ($(cd "$ROOT" && du -h "$DIST" | cut -f1)) — $DIST"

# ---------------------------------------------------------------------------
# 3. Cross-compile for the simulator and stage a launchable iOS .app.
# ---------------------------------------------------------------------------
say "3/3  Building EChartsDemoGalleryiOS ($BUILD_MODE, $TRIPLE) and staging .app into ${OUT#$ROOT/}"
SDK_PATH="$(xcrun --sdk iphonesimulator --show-sdk-path)"
swift build --package-path "$ROOT" -c "$CONFIG" --product EChartsDemoGalleryiOS \
  "${SWIFT_ARGS[@]}" --triple "$TRIPLE" --sdk "$SDK_PATH"
BIN_DIR="$(swift build --package-path "$ROOT" -c "$CONFIG" --product EChartsDemoGalleryiOS \
  "${SWIFT_ARGS[@]}" --triple "$TRIPLE" --sdk "$SDK_PATH" --show-bin-path | tail -1)"
BIN="$BIN_DIR/EChartsDemoGalleryiOS"
[ -x "$BIN" ] || { echo "ERROR: built binary not found at $BIN" >&2; exit 1; }

APP="$OUT/EChartsDemoGalleryiOS.app"
rm -rf "$APP"
mkdir -p "$APP"
cp "$BIN" "$APP/EChartsDemoGalleryiOS"

# iOS bundles are flat (no Contents/MacOS). UILaunchScreen (empty dict) opts into the modern
# launch screen so the app gets the device's full logical resolution instead of letterboxing.
cat > "$APP/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>            <string>EChartsDemoGalleryiOS</string>
    <key>CFBundleDisplayName</key>     <string>ECharts Gallery</string>
    <key>CFBundleExecutable</key>      <string>EChartsDemoGalleryiOS</string>
    <key>CFBundleIdentifier</key>      <string>com.ios-chart.echartskit.EChartsDemoGalleryiOS</string>
    <key>CFBundlePackageType</key>     <string>APPL</string>
    <key>CFBundleShortVersionString</key> <string>1.0</string>
    <key>CFBundleVersion</key>         <string>1</string>
    <key>MinimumOSVersion</key>        <string>15.0</string>
    <key>CFBundleSupportedPlatforms</key> <array><string>iPhoneSimulator</string></array>
    <key>UIDeviceFamily</key>          <array><integer>1</integer><integer>2</integer></array>
    <key>UILaunchScreen</key>          <dict/>
    <key>UISupportedInterfaceOrientations</key>
    <array>
        <string>UIInterfaceOrientationPortrait</string>
        <string>UIInterfaceOrientationLandscapeLeft</string>
        <string>UIInterfaceOrientationLandscapeRight</string>
    </array>
</dict>
</plist>
PLIST

# Ad-hoc sign — arm64 simulator binaries must carry a code signature to launch.
codesign --force --sign - "$APP" >/dev/null 2>&1 || true

say "Done — $APP"
echo "Install: xcrun simctl install booted \"$APP\""
echo "Launch:  xcrun simctl launch booted $BUNDLE_ID"

if [ "$RUN" = 1 ]; then
  # Reuse a booted device, else boot the newest available iPhone.
  DEVICE="$(xcrun simctl list devices booted | grep -Eo '[0-9A-F-]{36}' | head -1 || true)"
  if [ -z "$DEVICE" ]; then
    DEVICE="$(xcrun simctl list devices available | grep -E '^\s+iPhone' | grep -Eo '[0-9A-F-]{36}' | tail -1)"
    [ -n "$DEVICE" ] || { echo "ERROR: no available iPhone simulator found" >&2; exit 1; }
    say "Booting simulator $DEVICE"
    xcrun simctl boot "$DEVICE"
    xcrun simctl bootstatus "$DEVICE" -b
  fi
  open -a Simulator
  say "Installing + launching on $DEVICE"
  xcrun simctl install "$DEVICE" "$APP"
  xcrun simctl launch "$DEVICE" "$BUNDLE_ID"
fi
