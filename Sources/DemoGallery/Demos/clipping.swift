import ZRenderKit
// Migrated from zrender test/clipping.html
extension DemoRegistry {
    static let demo_clipping: Demo = Demo(
        name: "clipping", category: "Paint", summary: "Circle clip carving a color mosaic, inside a rect clip band"
    ) { zr in
        // zrender's clipping.html nests two clips: a grid of images lives in an inner
        // group clipped by a circle, inside an outer group clipped by a rect — so the
        // grid shows only where it falls inside BOTH regions (circle ∩ rect).
        //
        // The NativePainter applies the clip from each *leaf* displayable's getClipPath()
        // and does NOT propagate a Group's clip down to its children, so here we clip every
        // mosaic cell with its own circle clip path (clips can't be shared between elements)
        // and emulate the outer rect clip by confining the mosaic to a rectangular band —
        // reproducing the same "circle clipped by a rect" look the HTML animates toward.
        let palette = ["#5470c6", "#91cc75", "#fac858", "#ee6666",
                       "#73c0de", "#3ba272", "#fc8452", "#9a60b4"]
        let cell = 24.0, cols = 18, rows = 5
        let mx = 124.0, my = 40.0                       // mosaic band origin (the emulated rect clip)
        for i in 0..<cols {
            for j in 0..<rows {
                let c = rect(mx + Double(i) * cell + 1, my + Double(j) * cell + 1,
                             cell - 2, cell - 2, r: 3)
                styled(c, fill: palette[(i + j) % palette.count])
                c.setClipPath(circle(340, 100, 82))     // real clip — fresh instance per cell
                zr.add(c)
            }
        }
        // outline the two clip regions so the nested-clip intent stays legible
        zr.add(styled(rect(mx, my, Double(cols) * cell, Double(rows) * cell),
                      stroke: "#888", lineWidth: 1.5, dash: [4, 4]))
        zr.add(styled(circle(340, 100, 82),
                      stroke: "#333", lineWidth: 1.5, dash: [4, 4]))
    }
}
