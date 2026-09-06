import ZRenderKit
// Migrated from zrender test/hoverLayer.html
extension DemoRegistry {
    static let demo_hoverLayer: Demo = Demo(
        name: "hoverLayer", category: "Rendering",
        summary: "Hover layer — one Bézier highlighted on top of grayscale strokes"
    ) { zr in
        // hoverLayer.html builds 10000 wandering quadratic BezierCurves with grayscale
        // strokes (lineWidth 0.5, opacity 0.1) whose gray ramps with the checkpoint index
        // (255 * round(i/2000) / 5). On mouseover each calls
        //   zr.addHover(this, { stroke: 'yellow', lineWidth: 10, opacity: 1 })
        // to redraw the element on a separate hover layer. Here we render a deterministic
        // handful of those curves plus one in the highlighted hover state. (No Date/random;
        // opacity/lineWidth nudged up so the few curves read clearly.)

        // a connected chain of quadratic Béziers: x1,y1 -> control cpx1,cpy1 -> x2,y2
        let curves: [[Double]] = [
            [ 40, 120,  90,  30, 140,  40],
            [140,  40, 190, 170, 240, 160],
            [240, 160, 290,  30, 340,  50],
            [340,  50, 390, 170, 440, 150],
            [440, 150, 490,  30, 540,  60],
            [540,  60, 590, 170, 640, 130],
        ]
        // grayscale ramp (dark → light), standing in for the html's rgb(g,g,g) checkpoints
        let grays = ["#333333", "#555555", "#777777", "#999999", "#bbbbbb", "#dddddd"]

        func bezier(_ c: [Double]) -> BezierCurve {
            var b = BezierCurveShape()
            b.x1 = c[0]; b.y1 = c[1]
            b.cpx1 = c[2]; b.cpy1 = c[3]   // quadratic: no cpx2/cpy2
            b.x2 = c[4]; b.y2 = c[5]
            let e = BezierCurve(); e.setShape(b); return e
        }

        for (i, c) in curves.enumerated() {
            zr.add(styled(bezier(c), stroke: grays[i], lineWidth: 1.5, opacity: 0.7))
        }

        // the "hovered" curve, drawn on top in the addHover highlight style
        zr.add(styled(bezier(curves[2]), stroke: "#ffff00", lineWidth: 10, opacity: 1))
    }
}
