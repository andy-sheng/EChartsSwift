#!/usr/bin/env bash
#
# Build the DemoGallery test app — the native equivalent of opening zrender's
# test/*.html in a browser. Wraps the three steps you'd otherwise run by hand:
#
#   1. Sync the pinned upstream checkouts (scripts/sync-upstream.sh).
#   2. Ensure upstream zrender's `dist/zrender.js` is present — the GUI's
#      right-pane WebView and `--web-snapshot` load test/*.html, which all
#      `<script src="../dist/zrender.js">`. The dist is committed at the pinned
#      SHA, so step 1 normally provides it; we only (re)build it via npm if it's
#      missing or you pass --build-zrender.
#   3. Build the DemoGallery SwiftPM product and stage a launchable .app bundle
#      into ./build/ (gitignored).
#
# Usage:
#   scripts/build-demo-gallery.sh                fast development build (debug)
#   scripts/build-demo-gallery.sh --release      optimized release build
#   scripts/build-demo-gallery.sh --build-zrender force-rebuild upstream zrender's dist via npm
#   scripts/build-demo-gallery.sh --run          launch the app after building
#   scripts/build-demo-gallery.sh --out <dir>    stage into <dir> instead of ./build
#   scripts/build-demo-gallery.sh -h | --help
#
# Note: the app resolves upstream/zrender/test/ via the source path baked in at
# compile time (#filePath), so the staged .app only runs on this machine with the
# repo in place — it is a local dev/test artifact, which is why build/ is ignored.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ZR_DIR="$ROOT/upstream/zrender"
DIST="$ZR_DIR/dist/zrender.js"

CONFIG="debug"
BUILD_ZRENDER=0
RUN=0
OUT="$ROOT/build"

while [ "$#" -gt 0 ]; do
  case "$1" in
    --debug)         CONFIG="debug" ;;
    --release)       CONFIG="release" ;;
    --build-zrender) BUILD_ZRENDER=1 ;;
    --run)           RUN=1 ;;
    --out)           shift; OUT="${1:?--out needs a path}" ;;
    -h|--help)       sed -n '2,25p' "$0"; exit 0 ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
  shift
done

# OUT may be relative — anchor it to the repo root if so.
case "$OUT" in /*) ;; *) OUT="$ROOT/$OUT" ;; esac

say() { printf '\n\033[1;36m==>\033[0m %s\n' "$*"; }

# ---------------------------------------------------------------------------
# 1. Sync upstream (clone/fetch each repo to the locked SHA + echarts dist).
# ---------------------------------------------------------------------------
say "1/3  Syncing pinned upstream checkouts"
"$ROOT/scripts/sync-upstream.sh"

# ---------------------------------------------------------------------------
# 2. Ensure upstream zrender's dist (the html dependency) is built/present.
# ---------------------------------------------------------------------------
say "2/3  Ensuring upstream zrender dist (test/*.html depends on ../dist/zrender.js)"
if [ "$BUILD_ZRENDER" = 1 ] || [ ! -f "$DIST" ]; then
  if [ ! -f "$DIST" ]; then
    echo ">> dist/zrender.js missing — building zrender from source"
  else
    echo ">> --build-zrender: rebuilding zrender from source"
  fi
  command -v npm >/dev/null 2>&1 || {
    echo "ERROR: npm not found, cannot build zrender. Install Node.js, or re-run" >&2
    echo "       scripts/sync-upstream.sh to restore the committed dist." >&2
    exit 1
  }
  ( cd "$ZR_DIR"
    if [ -f package-lock.json ]; then npm ci; else npm install; fi
    npm run build:bundle )
  [ -f "$DIST" ] || { echo "ERROR: build did not produce $DIST" >&2; exit 1; }
  echo "ok      built $DIST"
else
  echo "ok      dist present ($(cd "$ROOT" && du -h "$DIST" | cut -f1)) — $DIST"
fi

# ---------------------------------------------------------------------------
# 3. Build the DemoGallery product and stage a launchable .app into ./build.
# ---------------------------------------------------------------------------
say "3/3  Building DemoGallery ($CONFIG) and staging .app into ${OUT#$ROOT/}"
swift build --package-path "$ROOT" -c "$CONFIG" --product DemoGallery
BIN_DIR="$(swift build --package-path "$ROOT" -c "$CONFIG" --product DemoGallery --show-bin-path | tail -1)"
BIN="$BIN_DIR/DemoGallery"
[ -x "$BIN" ] || { echo "ERROR: built binary not found at $BIN" >&2; exit 1; }

APP="$OUT/DemoGallery.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/DemoGallery"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>            <string>DemoGallery</string>
    <key>CFBundleDisplayName</key>     <string>ZRender DemoGallery</string>
    <key>CFBundleExecutable</key>      <string>DemoGallery</string>
    <key>CFBundleIdentifier</key>      <string>com.ios-chart.zrenderkit.DemoGallery</string>
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
  printf '\n# DemoGallery staged .app (local dev/test artifact, built by scripts/build-demo-gallery.sh)\n%s\n' "$PATTERN" >> "$GI"
  echo "added '$PATTERN' to .gitignore"
fi

say "Done — $APP"
echo "Launch:  open \"$APP\""
echo "  ...or directly:  \"$APP/Contents/MacOS/DemoGallery\""
echo "CLI:     \"$BIN\" --list | --render-all <dir> | --web-snapshot <demo> <png>"

if [ "$RUN" = 1 ]; then
  say "Launching DemoGallery"
  open "$APP"
fi
