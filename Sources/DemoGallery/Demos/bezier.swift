import ZRenderKit
// Faithful port of zrender test/bezier.html  (canvas 1000x600)
//
// Upstream is ONE BezierCurve { x1:10,y1:400, cpx1:0,cpy1:0, cpx2:0,cpy2:0, x2:300,y2:30 },
// position [0,0], scale [1,1], `draggable: true`, then `animateTo({shape:{percent:0}}, {duration:2000})`.
// BezierCurve's default style is stroke '#000', no fill; `percent` defaults to 1 (full curve).
// The native ZRenderKit supports the same calls 1:1 — `BezierCurveShape.percent` is animatable and
// `draggable` is wired through the Handler — so this issues the SAME zrender calls as the html.
extension DemoRegistry {
    static let demo_bezier: Demo = Demo(
        name: "bezier", category: "Shapes",
        summary: "A draggable cubic BezierCurve (cp at 0,0) animating percent 1→0 over 2s",
        width: 1000, height: 600
    ) { zr in
        var b = BezierCurveShape()
        b.x1 = 10; b.y1 = 400
        b.cpx1 = 0; b.cpy1 = 0
        b.cpx2 = 0; b.cpy2 = 0
        b.x2 = 300; b.y2 = 30
        let curve = BezierCurve(); curve.setShape(b)
        curve.draggable = .true               // == `draggable: true`
        zr.add(styled(curve, stroke: "#000"))   // == BezierCurve.getDefaultStyle() (stroke #000, no fill)

        // curve.animateTo({ shape: { percent: 0 } }, { duration: 2000 })
        var cfg = ElementAnimateConfig(); cfg.duration = 2000
        curve.animateTo(["shape": ["percent": 0.0]], cfg)
    }
}
