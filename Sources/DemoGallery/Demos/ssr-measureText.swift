import ZRenderKit
// Migrated from zrender test/ssr-measureText.html
extension DemoRegistry {
    static let demo_ssr_measureText: Demo = Demo(
        name: "ssr-measureText", category: "Text",
        summary: "measureText: text labels with their (estimated) measured box"
    ) { zr in
        // ssr-measureText.html (zrender#947 / echarts#17326) builds two SSR Text elements and,
        // for each, strokes a Rect using `text.getBoundingRect()` to verify SSR measurement.
        //
        // PORT FINDING: calling `ZRText.getBoundingRect()` in this build crashes with
        // "Index out of range" (text measurement path), at least under the headless renderer.
        // Since a fatalError can't be caught and this is a tests-only change (no framework
        // edits), the demo avoids that call and draws an *estimated* box from the glyph count
        // instead — enough to convey the "measure each label" intent. Flip back to the real
        // `getBoundingRect()` once the framework's text measurement is fixed.
        let lines = ["BEFORE: ABCDEFG1234567", "AFTER: ABCDEFG1234567"]
        let strokes = ["#ee6666", "#5470c6"]   // HTML uses color.random(); fixed for determinism.
        let size = 18.0
        for (i, str) in lines.enumerated() {
            let x = 40.0, y = 55.0 + Double(i) * 70.0
            zr.add(text(str, x, y, "#333333", size: size))
            // Rough box: ~0.58·fontSize per char wide, ~1.3·fontSize tall (placeholder for the
            // real measured rect — see PORT FINDING above).
            let w = Double(str.count) * size * 0.58
            zr.add(styled(rect(x, y, w, size * 1.3),
                          stroke: strokes[i % strokes.count], lineWidth: 1))
        }
    }
}
