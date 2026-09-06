import ZRenderKit
// Faithful port of zrender test/text-color.html
//
// Upstream builds 100 zrender.Rect (100x50) on a white background; each rect is filled with
// zrender.color.random() and carries a bold 12px ATTACHED textContent label "A Text in Rect(i)"
// with `textConfig:{position:'inside'}` and NO explicit fill — so zrender's inside auto-contrast
// picks the text color (white on dark, dark on light). Laid out in a wrapping grid (margin 40).
//
// This now uses the real attach path: `rect.setTextContent(Text)` + `setTextConfig({position:'inside'})`
// (Element.updateInnerText is implemented), and the label carries no fill so the inside contrast
// color is resolved per rect. color.random() → deterministic per-index hash (stable golden dump).
// The dat.GUI panel (fontSize / position / backgroundColor) is a DOM-only control, omitted.
extension DemoRegistry {
    static let demo_text_color: Demo = Demo(
        name: "text-color", category: "Text",
        summary: "100 random-filled rects with bold inside auto-contrast labels on a white background",
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
            let r = styled(rect(x, y, RECT_WIDTH, RECT_HEIGHT), fill: "#" + hex)

            // textContent: Text { text, fontWeight:'bold', fontSize:12 } — NO fill (inside auto-contrast).
            var st = TextStyleProps()
            st.text = "A Text in Rect(\(i))"
            st.fontSize = .number(12)
            st.fontWeight = .bold
            let label = ZRText(); label.useStyle(st)
            r.setTextContent(label)
            var tc = ElementTextConfig(); tc.position = "inside"   // textConfig: { position: 'inside' }
            r.setTextConfig(tc)
            zr.add(r)

            x += RECT_WIDTH + RECT_MARGIN
        }
    }
}
