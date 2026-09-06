# Optional Rasterizer dependency

Rasterizer is owned by the independent `../RasterizerPainter` Git repository. Its
engine lock, local patch, provenance notes and reconstruction script live there.

The core builds and tests without the painter repository or engine checkout. Only
`Examples/PainterGallery` combines the core with this optional plugin.

The root `scripts/sync-rasterizer.sh` forwards to the plugin's reconstruction script.
