import ZRenderKit
// Migrated from zrender test/boundingbox.html
extension DemoRegistry {
    static let demo_boundingbox: Demo = Demo(
        name: "boundingbox", category: "Path tools",
        summary: "PathProxy (bezier + quadratic + arc) stroked, with its getBoundingRect() outline"
    ) { zr in
        // boundingbox.html builds a raw PathProxy and reads getBoundingRect():
        //   path.moveTo(20, 20)
        //   path.bezierCurveTo(100, 0, -100, 100, 100, 100)
        //   path.quadraticCurveTo(400, 10, 200, 200)
        //   path.arc(200, 200, 50, 1, 10, true)
        //   bb = path.getBoundingRect()
        // Reproduce the exact path in a PathProxy to obtain the true bounding rect.
        let pp = PathProxy(false)            // notSaveData == false ⇒ keeps data for bbox
        _ = pp.beginPath()
        _ = pp.moveTo(20, 20)
        _ = pp.bezierCurveTo(100, 0, -100, 100, 100, 100)
        _ = pp.quadraticCurveTo(400, 10, 200, 200)
        _ = pp.arc(200, 200, 50, 1, 10, true)
        let bb = pp.getBoundingRect()

        // zrender has no generic "draw this PathProxy" element, so the continuous stroked
        // path is composed from the equivalent primitives (same commands, same coordinates).
        // The html issues path.stroke(ctx) with the canvas defaults: strokeStyle '#000',
        // lineWidth 1, no fill — mirror those exactly here.
        let g = Group()
        let ink = "#000"

        // moveTo(20,20) → bezierCurveTo(100,0, -100,100, 100,100)   (cubic Bézier)
        var cubic = BezierCurveShape()
        cubic.x1 = 20;  cubic.y1 = 20
        cubic.cpx1 = 100; cubic.cpy1 = 0
        cubic.cpx2 = -100; cubic.cpy2 = 100
        cubic.x2 = 100; cubic.y2 = 100
        let cu = BezierCurve(); cu.setShape(cubic)
        g.add(styled(cu, stroke: ink, lineWidth: 1))

        // quadraticCurveTo(400,10, 200,200)   (quadratic ⇒ leave cpx2/cpy2 nil)
        var quad = BezierCurveShape()
        quad.x1 = 100; quad.y1 = 100
        quad.cpx1 = 400; quad.cpy1 = 10
        quad.x2 = 200; quad.y2 = 200
        let qu = BezierCurve(); qu.setShape(quad)
        g.add(styled(qu, stroke: ink, lineWidth: 1))

        // canvas arc() draws a line from the current point (200,200) to the arc's start.
        // arc start = (200 + 50·cos 1, 200 + 50·sin 1) ≈ (227.0151, 242.0735)
        var lead = LineShape()
        lead.x1 = 200; lead.y1 = 200; lead.x2 = 227.0151; lead.y2 = 242.0735
        let ln = Line(); ln.setShape(lead)
        g.add(styled(ln, stroke: ink, lineWidth: 1))

        // arc(200,200, 50, 1, 10, true)   (anticlockwise ⇒ Arc shape clockwise == false)
        var arc = ArcShape()
        arc.cx = 200; arc.cy = 200; arc.r = 50
        arc.startAngle = 1; arc.endAngle = 10; arc.clockwise = false
        let ar = Arc(); ar.setShape(arc)
        g.add(styled(ar, stroke: ink, lineWidth: 1))

        // The computed getBoundingRect(): the html draws it with ctx.strokeRect(bb...),
        // i.e. a solid '#000' outline at lineWidth 1 (no fill — styled() forces fill:"none").
        let box = rect(bb.x, bb.y, bb.width, bb.height)
        g.add(styled(box, stroke: ink, lineWidth: 1))

        // The path spans ≈ 272×233; scale + offset it to sit centered in the 680×200 canvas.
        g.scaleX = 0.7; g.scaleY = 0.7
        g.x = 245; g.y = 12
        zr.add(g)
    }
}
