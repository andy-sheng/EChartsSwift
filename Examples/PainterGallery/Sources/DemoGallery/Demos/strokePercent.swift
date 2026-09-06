import ZRenderKit
// Migrated from zrender test/strokePercent.html
extension DemoRegistry {
    static let demo_strokePercent: Demo = Demo(
        name: "strokePercent", category: "Paint", summary: "Partial strokes via style.strokePercent (draw-on)"
    ) { zr in
        // Faithful to test/strokePercent.html: Circle / Rect / Sector / Polyline / Smoothed
        // Polyline, all drawn fill:'none', stroke:'#000', lineWidth:5, each with its label
        // attached `textConfig.position:'inside'` (centred in the shape). The html starts
        // strokePercent at 0 and drives every element 0→1 on a continuous ~2s linear loop
        // (setInterval: config.percent = (config.percent + 0.01) % 1 every 20ms) — that
        // draw-on IS the point of the demo, so we arm the engine's own looping animator.

        // strokePercent isn't exposed by the `styled` helper, so build the style by hand —
        // same manual PathStyleProps + useStyle pattern `styled` uses internally. Start at 0
        // (html's config.percent default) and let the looping animator draw it on.
        func stroked(_ el: Path) -> Path {
            var st = PathStyleProps()
            st.fill = .string("none")
            st.stroke = .string("#000")
            st.lineWidth = 5
            st.strokePercent = 0
            el.useStyle(st)
            return el
        }

        // shared zigzag base for the two polylines, scaled 0.55 to fit the 680-wide band.
        let base: [[Double]] = [[50, 50], [200, 10], [100, 200], [50, 150], [10, 70]]
        func polyAt(_ cx: Double, smooth: Double) -> Polyline {
            let s = 0.55
            // scaled bbox is (5.5,5.5)…(110,110) → center (57.75,57.75); re-center at (cx,100)
            let dx = cx - 57.75, dy = 100 - 57.75
            var shp = PolylineShape()
            shp.points = base.map { VectorArray($0[0] * s + dx, $0[1] * s + dy) }
            shp.smooth = smooth
            let e = Polyline(); e.setShape(shp); return e
        }

        // Build + add each shape, then arm the looping draw-on animator. Must add to `zr`
        // first so the animator registers with the host animation loop (cf. barAnimation),
        // matching upstream `el.animate('style', true).when(t, {strokePercent: 1}).start()`.
        let els: [Path] = [
            stroked(circle(70, 100, 45)),
            stroked(rect(160, 55, 90, 90)),
            stroked(sector(340, 100, 22, 52, 1, 5)),
            stroked(polyAt(475, smooth: 0)),
            stroked(polyAt(610, smooth: 0.5)),
        ]
        for el in els {
            zr.add(el)
            el.animate("style", true)
                .when(2000, ["strokePercent": 1.0])
                .start(.named("linear"))
        }

        // Labels: html attaches each as a textContent child with textConfig.position:'inside'
        // (centred in the shape). Element.updateInnerText is a deferred no-op in this port, so —
        // as in rectText.swift — we reproduce the layout with a standalone ZRText placed at the
        // shape's centre via align .center / verticalAlign .middle.
        func label(_ str: String, _ x: Double, _ y: Double) {
            var st = TextStyleProps()
            st.text = str; st.x = x; st.y = y; st.fill = "#000"
            st.fontSize = .number(12); st.align = .center; st.verticalAlign = .middle
            let t = ZRText(); t.useStyle(st); zr.add(t)
        }

        label("Circle",            70, 100)
        label("Rect",             205, 100)
        label("Sector",           340, 100)
        label("Polyline",         475, 100)
        label("Smoothed Polyline", 610, 100)
    }
}
