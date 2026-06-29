import ZRenderKit
// Migrated from zrender test/asciiWidthMap.html
//
// The HTML builds an ASCII char-width map by calling `ctx.measureText(char).width`
// for every printable character. The faithful Swift analogue uses the public
// width-measuring API `ZRenderKit.text.getWidth(_:_:)` (and `getLineHeight`) to box
// each sample string by its MEASURED pixel width — showing that equal-length strings
// of narrow vs. wide glyphs occupy very different widths.
//
// NOTE: the enum namespace is `ZRenderKit.text`; it must be fully qualified because the
// shared `func text(...)` builder shadows the bare name `text` inside this closure.
extension DemoRegistry {
    static let demo_asciiWidthMap: Demo = Demo(
        name: "asciiWidthMap", category: "Text",
        summary: "Strings boxed by their measured text width"
    ) { zr in
        let font = "20px sans-serif"
        let lineHeight = ZRenderKit.text.getLineHeight(font)

        zr.add(text("measureText — each box = measured string width", 40, 10, "#333", size: 14))

        // (string, color) samples: equal-length narrow vs. wide glyph runs, plus mixed runs.
        let samples: [(String, String)] = [
            ("iiiiiiiiiiii", "#5470c6"),
            ("WWWWWWWWWWWW", "#91cc75"),
            ("Hello, zrender!", "#fac858"),
            ("MIX 0123 ||| .,;", "#ee6666"),
        ]

        for (i, sample) in samples.enumerated() {
            let (str, col) = sample
            let y = 42 + Double(i) * 38
            let w = ZRenderKit.text.getWidth(str, font)
            // Stroke-only box sized exactly to the measured width (styled() => fill "none").
            zr.add(styled(rect(40, y, w, lineHeight), stroke: col, lineWidth: 1.5))
            zr.add(text(str, 40, y, col, size: 20))
            // Annotate the measured width to the right of the box.
            zr.add(text("\(Int(w.rounded())) px", 40 + w + 12, y + 2, "#999", size: 13))
        }
    }
}
