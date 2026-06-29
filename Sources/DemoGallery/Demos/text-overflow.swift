import ZRenderKit
// Migrated from zrender test/text-overflow.html
extension DemoRegistry {
    static let demo_text_overflow: Demo = Demo(
        name: "text-overflow", category: "Text", summary: "Width-boxed text blocks: overflow / padding / border / align"
    ) { zr in
        // text-overflow.html — standalone Text with a constrained `width`, padding, border and an
        // `overflow` strategy. NOTE: the port's parseText seam is a stub — it splits lines only on
        // explicit "\n" (auto break/breakAll/truncate, lineOverflow, ellipsis and rich text are
        // PORT-TODO no-ops). So each block is pre-wrapped to its box width to show the intended
        // layout, while the overflow/lineOverflow/ellipsis fields are set for API parity.
        func block(_ str: String, x: Double, overflow: String) {
            var st = TextStyleProps()
            st.text = str
            st.x = x
            st.y = 34
            st.width = 175
            st.height = 116
            st.fill = "#2f4f2f"
            st.fontSize = .number(13)
            st.align = .left
            st.verticalAlign = .top
            st.padding = .number(10)
            st.borderColor = "#3ba272"
            st.borderWidth = 1
            st.borderRadius = .number(6)
            st.backgroundColor = .string("rgba(100,200,100,0.18)")
            st.overflow = overflow          // 'break' | 'truncate' (parity; layout is pre-wrapped)
            st.lineOverflow = "truncate"
            st.ellipsis = "…"
            let t = ZRText()
            t.useStyle(st)
            zr.add(t)
        }

        zr.add(text("textOverflow — width-constrained text blocks", 30, 8, "#333", size: 14))

        block("overflow: break\nwraps the long\nlabel by word so it\nfits the box width.",
              x: 30, overflow: "break")
        block("overflow: breakAll\nbreaks inside words\nwhenaverylongtoken\nexceeds the width.",
              x: 250, overflow: "breakAll")
        block("overflow: truncate\nclips the text and\nappends an ellipsis …",
              x: 470, overflow: "truncate")
    }
}
