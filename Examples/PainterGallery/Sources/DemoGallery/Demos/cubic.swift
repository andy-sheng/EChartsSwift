import ZRenderKit
// Migrated from zrender test/cubic.html
extension DemoRegistry {
    static let demo_cubic: Demo = Demo(
        name: "cubic", category: "Path tools", summary: "Cubic Bézier curve with markers sampled at t values"
    ) { zr in
        // cubic.html samples points along a cubic Bézier via curve.cubicAt. Here the
        // BezierCurve element strokes the curve, and BezierCurve.pointAt(t) — which is
        // backed by the same curve.cubicAt helper — yields the sampled marker positions.
        var b = BezierCurveShape()
        b.x1 = 60;  b.y1 = 170
        b.cpx1 = 200; b.cpy1 = 10
        b.cpx2 = 460; b.cpy2 = 190
        b.x2 = 620; b.y2 = 30
        let curveEl = BezierCurve(); curveEl.setShape(b)
        zr.add(styled(curveEl, stroke: "#5470c6", lineWidth: 4))

        // Small red markers at sampled t values along the curve (t = 0.0 … 1.0).
        for i in 0...10 {
            let t = Double(i) / 10.0
            let p = curveEl.pointAt(t)
            zr.add(styled(circle(p[0], p[1], 4), fill: "#ee6666"))
        }
    }
}
