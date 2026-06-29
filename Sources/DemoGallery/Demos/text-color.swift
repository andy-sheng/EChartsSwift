import ZRenderKit
// Migrated from zrender test/text-color.html
//
// Upstream builds 100 zrender.Rect (100x50) on a white background; each rect is filled
// with zrender.color.random() and carries a bold 12px inside textContent label
// "A Text in Rect(i)", laid out in a wrapping grid (margin 40). A dat.GUI tweaks
// fontSize / label position / background color.
//
// Faithful-port notes (allowed deviations):
//  - color.random() is non-deterministic (Double.random); to keep the geometry golden
//    dump stable we derive each rect fill from its index with a stdlib LCG-style hash
//    (deterministic stand-in for Math.random — see curves.swift / progressive.swift).
//  - Element.updateInnerText is a Phase-2 no-op, so an attached textContent + textConfig
//    {position:'inside'} would never be laid out. We reproduce the inside label with a
//    standalone centered ZRText (align .center / verticalAlign .middle, white per zrender's
//    inside default) — the same rectText-style workaround used by rectText.swift. The
//    text() helper does not expose fontWeight, so the label is built inline.
//  - The dat.GUI panel is omitted: its position toggle relies on updateInnerText (a no-op
//    here) and DemoControl has no color picker for backgroundColor. Noted as residual.
extension DemoRegistry {
    static let demo_text_color: Demo = Demo(
        name: "text-color", category: "Text",
        summary: "100 random-filled rects with bold inside labels on a white background",
        width: 1200, height: 600
    ) { zr in
        zr.setBackgroundColor("#fff")   // html: zr.setBackgroundColor(config.backgroundColor)

        let RECT_WIDTH = 100.0, RECT_HEIGHT = 50.0, RECT_MARGIN = 40.0
        let canvasWidth = 1200.0        // wrap on the demo's logical width (html uses window width)

        // layoutRects(): wrapping grid starting at (margin, margin), advancing by w+margin.
        var x = RECT_MARGIN
        var y = RECT_MARGIN
        for i in 0..<100 {
            if x + RECT_WIDTH + RECT_MARGIN > canvasWidth {
                x = RECT_MARGIN
                y += RECT_HEIGHT + RECT_MARGIN
            }

            // deterministic stand-in for zrender.color.random() (stable golden dump).
            let h = (UInt32(truncatingIfNeeded: i) &* 2654435761) & 0xFFFFFF
            var hex = String(h, radix: 16)
            while hex.count < 6 { hex = "0" + hex }
            zr.add(styled(rect(x, y, RECT_WIDTH, RECT_HEIGHT), fill: "#" + hex))

            // bold 12px white label, centered inside the rect (textConfig position 'inside').
            var st = TextStyleProps()
            st.text = "A Text in Rect(\(i))"
            st.x = x + RECT_WIDTH / 2
            st.y = y + RECT_HEIGHT / 2
            st.fill = "#fff"
            st.fontSize = .number(12)
            st.fontWeight = .bold
            st.align = .center
            st.verticalAlign = .middle
            let label = ZRText(); label.useStyle(st); zr.add(label)

            x += RECT_WIDTH + RECT_MARGIN
        }
    }
}
