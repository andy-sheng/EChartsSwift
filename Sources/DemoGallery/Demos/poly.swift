import ZRenderKit
// Faithful port of zrender test/poly.html  (no explicit #main size → use a snug 500x400)
//
// Upstream: a Polygon and a Polyline, BOTH at x:100,y:100 sharing the SAME shape
//   { points: [[50,50],[200,10],[100,200],[50,150],[10,70]], smooth: 0.5 }.
//   - Polygon  style { fill: 'rgba(220,20,60,0.4)' }
//   - Polyline style { stroke: 'rgba(220,20,60,1)', lineWidth: 10 }, strokePercent animated 0→1.
// A dat.GUI panel drives `smooth` (0–1), `percent` (0–1) and `animatePercent`; a setInterval loops
// `percent` (config.percent = (config.percent + 0.01) % 1 every 20ms ≈ a 2s linear loop) while the
// toggle is on. The native gallery exposes the same three controls (see `controls` below); the loop
// is the engine's own looping animator (the faithful zrender call), `animatePercent` arms/disarms it.
//
// NOTE: upstream shares ONE shape object across the two elements (`shape: polygon.shape`). Swift shapes
// are value types (no shared identity), so the two shapes are built separately with identical params.

/// Build the poly scene and return the live element refs (so the gallery's controls can drive them).
@discardableResult
private func buildPolyScene(_ zr: ZRender) -> (outline: Polyline, polygon: ZRenderKit.Polygon, pts: [VectorArray]) {
    let raw: [[Double]] = [[50, 50], [200, 10], [100, 200], [50, 150], [10, 70]]
    let pts = raw.map { VectorArray($0[0], $0[1]) }

    var pgShape = PolygonShape(); pgShape.points = pts; pgShape.smooth = 0.5
    let polygon = ZRenderKit.Polygon(); polygon.setShape(pgShape)
    polygon.x = 100; polygon.y = 100
    zr.add(styled(polygon, fill: "rgba(220, 20, 60, 0.4)"))

    var plShape = PolylineShape(); plShape.points = pts; plShape.smooth = 0.5
    let outline = Polyline(); outline.setShape(plShape)
    outline.x = 100; outline.y = 100
    var st = PathStyleProps()
    st.fill = .string("none")
    st.stroke = .string("rgba(220, 20, 60, 1)")
    st.lineWidth = 10
    st.strokePercent = 0       // config.percent starts at 0
    outline.useStyle(st)
    zr.add(outline)

    return (outline, polygon, pts)
}

/// The looping strokePercent 0→1 animator (armed while `animatePercent` is on).
private func armPolyLoop(_ outline: Polyline) {
    outline.animate("style", true)
        .when(2000, ["strokePercent": 1.0])
        .start(.named("linear"))
}

extension DemoRegistry {
    static let demo_poly: Demo = {
        var d = Demo(
            name: "poly", category: "Shapes",
            summary: "Smoothed Polygon + Polyline outline; live smooth / percent / animatePercent controls",
            width: 500, height: 400
        ) { zr in
            // Headless / no-controls path: build + arm the loop (animatePercent defaults on).
            let s = buildPolyScene(zr)
            armPolyLoop(s.outline)
        }

        // Interactive path: same scene + the three dat.GUI-equivalent controls, wired to the live refs.
        d.controls = { zr in
            let (outline, polygon, pts) = buildPolyScene(zr)
            armPolyLoop(outline)   // animatePercent default ON

            return [
                // gui.add(config, 'smooth', 0, 1).onChange(update) → setShape({smooth}) on both.
                DemoControl(label: "smooth", kind: .slider(min: 0, max: 1), value: 0.5) { v in
                    var pg = PolygonShape(); pg.points = pts; pg.smooth = v
                    polygon.setShape(pg)
                    var pl = PolylineShape(); pl.points = pts; pl.smooth = v
                    outline.setShape(pl)
                },
                // gui.add(config, 'percent', 0, 1).onChange(update) → setStyle({strokePercent}).
                // Dragging it takes manual control, so stop the auto-loop first.
                DemoControl(label: "percent", kind: .slider(min: 0, max: 1), value: 0) { v in
                    outline.stopAnimation()
                    outline.pathStyle.strokePercent = v
                    outline.dirtyStyle()
                },
                // gui.add(config, 'animatePercent') → arm / disarm the loop.
                DemoControl(label: "animatePercent", kind: .toggle, value: 1) { on in
                    if on != 0 { armPolyLoop(outline) } else { outline.stopAnimation() }
                },
            ]
        }
        return d
    }()
}
