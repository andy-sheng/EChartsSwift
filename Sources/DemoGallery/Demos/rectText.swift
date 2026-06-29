import ZRenderKit
// Migrated from zrender test/rectText.html
extension DemoRegistry {
    static let demo_rectText: Demo = Demo(
        name: "rectText", category: "Text", summary: "Rect labels placed by textConfig.position (edges / corners / inside)"
    ) { zr in
        // rectText.html attaches a Text to a Rect via `textConfig.position`
        // ('left'/'top'/'inside'/'insideTopLeft'/...). The attach API
        // (setTextContent + setTextConfig) is public, but `Element.updateInnerText`
        // — the method that lays the label out from textConfig.position — is a
        // deferred no-op in this port, so an attached textContent would never be
        // positioned. We reproduce the intended layout faithfully with standalone
        // ZRText placed via align / verticalAlign, the same math updateInnerText
        // would apply (distance ≈ default 5).
        let x = 240.0, y = 55.0, w = 200.0, h = 90.0
        let right = x + w, bottom = y + h, cx = x + w / 2, cy = y + h / 2
        let d = 6.0

        zr.add(styled(rect(x, y, w, h), fill: "#5470c6", stroke: "#2f4b9e", lineWidth: 1))

        func label(_ s: String, _ lx: Double, _ ly: Double, _ fill: String,
                   _ a: TextAlign, _ va: TextVerticalAlign, size: Double = 11) {
            var st = TextStyleProps()
            st.text = s; st.x = lx; st.y = ly; st.fill = fill
            st.fontSize = .number(size); st.align = a; st.verticalAlign = va
            let t = ZRText(); t.useStyle(st); zr.add(t)
        }

        // Outside positions (dark text).
        label("top",    cx,        y - d,      "#333", .center, .bottom)
        label("bottom", cx,        bottom + d, "#333", .center, .top)
        label("left",   x - d,     cy,         "#333", .right,  .middle)
        label("right",  right + d, cy,         "#333", .left,   .middle)

        // Inside corners + center (inside text is white, per zrender's inside default).
        label("insideTopLeft",     x + d,     y + d,      "#fff", .left,   .top)
        label("insideTopRight",    right - d, y + d,      "#fff", .right,  .top)
        label("insideBottomLeft",  x + d,     bottom - d, "#fff", .left,   .bottom)
        label("insideBottomRight", right - d, bottom - d, "#fff", .right,  .bottom)
        label("inside",            cx,        cy,         "#fff", .center, .middle, size: 13)
    }
}
