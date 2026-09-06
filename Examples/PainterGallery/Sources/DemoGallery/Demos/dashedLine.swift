import ZRenderKit
// Faithful port of zrender test/dashedLine.html  (#main is 1200x600 → default canvas size)
//
// Upstream draws FOUR stroke-only elements, each with a looping `lineDashOffset` style animation
// (`el.animate('style', true).when(1000, {lineDashOffset: V}).start()`) so the dashes march:
//   1. Polyline  shape {points: 10 random pts (x∈300..1100, y∈100..600), smooth: 0.5},
//                style {lineDash:[10,10], stroke:'rgba(220,20,60,0.8)', lineWidth:10}   → offset +20
//   2. Line      shape {x1:100,y1:100, x2:500,y2:500},
//                style {lineDash:[10,10], stroke:'rgba(10,80,60,0.8)'} (default lineWidth) → offset -20
//   3. Star      shape {n:5, r:100, cx:300, cy:200},
//                style {lineDash:[20,10], stroke:'black', fill:null}                      → offset +30
//   4. BezierCurve shape {x1:100,y1:100, x2:100,y2:500},
//                style {lineDash:[5,5], lineDashOffset:0}                                 → offset -10
//
// NOTES (acceptable deviations):
//  - Math.random() points → a fixed deterministic stand-in (10 scattered pts in the same range).
//  - The html's BezierCurve also writes x3/y3/x4/y4, but zrender's BezierCurveShape only reads
//    x1/y1/x2/y2 (+cpx1/cpy1, default 0,0) — so those extra fields are ignored upstream too; the
//    rendered curve is the quadratic (100,100)→(100,500) with control point (0,0).
//  - The html curve sets NO stroke; zrender's BezierCurve.getDefaultStyle() supplies stroke '#000'.
//    The `styled()` helper replaces the style wholesale (dropping that default), so we pass the
//    effective stroke "#000" explicitly to reproduce zrender's actual black dashed stroke.
//    `styled()`'s forced fill:"none" matches these stroke-only shapes (and the Star's fill:null).
extension DemoRegistry {
    static let demo_dashedLine: Demo = Demo(
        name: "dashedLine", category: "Paint",
        summary: "Dashed Polyline / Line / Star / BezierCurve with looping lineDashOffset animations"
    ) { zr in
        // 1. Polyline — 10 deterministic points (Math.random stand-in), smooth 0.5.
        let raw: [[Double]] = [
            [340, 520], [560, 140], [780, 480], [430, 260], [980, 360],
            [660, 580], [1080, 200], [510, 420], [880, 130], [1010, 560]
        ]
        var plShape = PolylineShape()
        plShape.points = raw.map { VectorArray($0[0], $0[1]) }
        plShape.smooth = 0.5
        let polyline = Polyline(); polyline.setShape(plShape)
        zr.add(styled(polyline, stroke: "rgba(220, 20, 60, 0.8)", lineWidth: 10, dash: [10, 10]))
        polyline.animate("style", true).when(1000, ["lineDashOffset": 20.0]).start()

        // 2. Line.
        var lnShape = LineShape(); lnShape.x1 = 100; lnShape.y1 = 100; lnShape.x2 = 500; lnShape.y2 = 500
        let line = Line(); line.setShape(lnShape)
        zr.add(styled(line, stroke: "rgba(10, 80, 60, 0.8)", dash: [10, 10]))
        line.animate("style", true).when(1000, ["lineDashOffset": -20.0]).start()

        // 3. Star (fill:null → styled() fill "none").
        var stShape = StarShape(); stShape.n = 5; stShape.r = 100; stShape.cx = 300; stShape.cy = 200
        let star = Star(); star.setShape(stShape)
        zr.add(styled(star, stroke: "black", dash: [20, 10]))
        star.animate("style", true).when(1000, ["lineDashOffset": 30.0]).start()

        // 4. BezierCurve (no stroke in html → effective default stroke "#000").
        var bcShape = BezierCurveShape(); bcShape.x1 = 100; bcShape.y1 = 100; bcShape.x2 = 100; bcShape.y2 = 500
        let curve = BezierCurve(); curve.setShape(bcShape)
        zr.add(styled(curve, stroke: "#000", dash: [5, 5]))
        curve.animate("style", true).when(1000, ["lineDashOffset": -10.0]).start()
    }
}
