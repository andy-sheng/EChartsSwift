#!/usr/bin/env bash
# Compatibility entry point; the optional painter repository owns the dependency.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT/RasterizerPainter/scripts/sync-rasterizer.sh"
if [ ! -f "$SCRIPT" ]; then
  echo "RasterizerPainter repository is missing. Core builds do not require it." >&2
  exit 1
fi
exec bash "$SCRIPT" "$@"
