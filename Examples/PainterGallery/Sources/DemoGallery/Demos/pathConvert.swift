import ZRenderKit
import Foundation
// Faithful port of zrender test/pathConvert.html  (canvas 1600x1600 → snug 1100x880)
//
// Two test blocks, both exercising tool/convertPath on a PathProxy:
//   buildSector():  4 rows (k=0..3) × 20 cols (i=0..19) of Sectors. endAngle = startAngle +
//                   2π·(1 - i/10) (a FULL circle at i=0, shrinking sweeps after) and the winding
//                   alternates (clockwise = !(k<2)) to "choose the most complex sector path to test".
//                   r0 = r/2. Each sector's PathProxy is fed to pathToBezierCurves / pathToPolygons.
//   buildPolygon(): 20 hand-built closed polygons (N = k+3 vertices) constructed via a fresh
//                   PathProxy.moveTo/lineTo/closePath, then run through the same two converters.
//
// Per source path, three rows are drawn (HTML translate 0/G/2G):
//   green  — the ORIGINAL path (stroke only, lineWidth 2)
//   red    — pathToBezierCurves rebuilt as ONE continuous cubic contour (moveTo + bezierCurveTo…),
//            filled rgba(0,0,0,0.2) + stroked red  (a real fillable Path subclass, like pin.html)
//   blue   — pathToPolygons rebuilt as ONE closed Polygon, filled rgba(0,0,0,0.2) + stroked blue
//
// The dat.GUI `startAngle` slider (-10..10) is exposed as a native DemoControl that clears + rebuilds.
//
// Deviations (acceptable): canvas trimmed to the used area; legacy `translate` → element y; the HTML
// only fills/strokes arr[0] / polygon[0] (the first contour) — these single-contour paths have exactly
// one, so we mirror that by drawing the first subpath.

// MARK: - a fillable single-contour cubic-bezier path (red row)
// Mirrors the html's drawBezier(): moveTo(seg[0],seg[1]) + bezierCurveTo per 6-tuple. Being a closed
// fillable Path (not separate BezierCurve elements) is what lets the rgba(0,0,0,0.2) fill render.
private struct BezierContourShape: PathShape {
    var seg: [Double] = []   // one subpath: [x0,y0, c1x,c1y,c2x,c2y, x1,y1, …]
    init() {}
    func animationGet(_ key: String) -> Any? { nil }
    mutating func animationSet(_ key: String, _ value: Any?) {}
}
private final class BezierContour: Path {
    override func getDefaultShape() -> PathShape { BezierContourShape() }
    override func buildPath(_ path: PathProxy, _ shape: PathShape, _ inBatch: Bool) {
        let s = (shape as! BezierContourShape).seg
        guard s.count >= 8 else { return }
        _ = path.moveTo(s[0], s[1])
        var k = 2
        while k + 5 < s.count {
            _ = path.bezierCurveTo(s[k], s[k + 1], s[k + 2], s[k + 3], s[k + 4], s[k + 5])
            k += 6
        }
        // No closePath: a converted closed contour already returns to its start (mirrors drawBezier).
    }
}

private let R = 20.0
private let G = 50.0

// red bezier row (offset +G) and blue polygon row (offset +2G) for one source PathProxy.
private func visualize(_ zr: ZRender, _ proxy: PathProxy, bezierLW: Double, polygonLW: Double) {
    // path → cubic bezier curves (red). HTML draws arr[0] only; single-contour here.
    if let seg = pathToBezierCurves(proxy).first {
        var bs = BezierContourShape(); bs.seg = seg
        let bez = BezierContour(); bez.type = "bezierContour"; bez.setShape(bs)
        bez.y = G                                  // translate(0, G)
        zr.add(styled(bez, fill: "rgba(0,0,0,0.2)", stroke: "red", lineWidth: bezierLW))
    }

    // path → flattened polygon (blue). HTML draws polygon[0] only; closed + filled.
    if let sub = pathToPolygons(proxy).first {
        var pts: [VectorArray] = []
        var k = 0
        while k + 1 < sub.count { pts.append(VectorArray(sub[k], sub[k + 1])); k += 2 }
        var ps = PolygonShape(); ps.points = pts
        let pl = ZRenderKit.Polygon(); pl.setShape(ps)
        pl.y = G * 2                               // translate(0, G*2)
        zr.add(styled(pl, fill: "rgba(0,0,0,0.2)", stroke: "blue", lineWidth: polygonLW))
    }
}

private func buildPathConvertScene(_ zr: ZRender, startAngle: Double) {
    // buildSector(): "the most complex sector path to test" — full grid + alternating winding.
    for k in 0..<4 {
        for i in 0..<20 {
            let anticlockwise = k < 2
            let endAngle = startAngle + π * 2 * (1 - Double(i) / 10)   // full 2π at i=0
            var s = SectorShape()
            s.cx = Double(i) * G + G
            s.cy = G + Double(k) * G * 3
            s.r = R; s.r0 = R / 2
            s.startAngle = startAngle; s.endAngle = endAngle
            s.clockwise = !anticlockwise
            let sec = Sector(); sec.setShape(s)
            zr.add(styled(sec, stroke: "green", lineWidth: 2))     // original (green), stroke only
            // HTML: red bezier inherits lineWidth 2 from green; blue polygon inherits 2 too.
            visualize(zr, sec.getUpdatedPathProxy(), bezierLW: 2, polygonLW: 2)
        }
    }

    // buildPolygon(): 20 hand-built closed polygons via a fresh PathProxy (N = k+3 vertices).
    for k in 0..<20 {
        let N = k + 3
        let dStep = 2 * π / Double(N)
        var pts: [VectorArray] = []
        let proxy = PathProxy()
        for i in 0..<N {
            let x = Double(k) * G + G + cos(Double(i) * dStep) * R
            let y = G * 14 + sin(Double(i) * dStep) * R
            pts.append(VectorArray(x, y))
            _ = (i == 0) ? proxy.moveTo(x, y) : proxy.lineTo(x, y)
        }
        _ = proxy.closePath()

        var pg = PolygonShape(); pg.points = pts
        let poly = ZRenderKit.Polygon(); poly.setShape(pg)
        zr.add(styled(poly, stroke: "green", lineWidth: 2))        // original (green), stroke only
        // HTML: red bezier lineWidth 1; blue polygon inherits 1 from it.
        visualize(zr, proxy, bezierLW: 1, polygonLW: 1)
    }
}

extension DemoRegistry {
    static let demo_pathConvert: Demo = {
        var d = Demo(
            name: "pathConvert", category: "Path tools",
            summary: "Tool: pathToBezierCurves / pathToPolygons on Sector + hand-built polygon paths",
            width: 1100, height: 880
        ) { zr in
            buildPathConvertScene(zr, startAngle: 0)
        }
        // dat.GUI: gui.add(config, 'startAngle', -10, 10).onChange(update)
        d.controls = { zr in
            buildPathConvertScene(zr, startAngle: 0)
            return [
                DemoControl(label: "startAngle", kind: .slider(min: -10, max: 10), value: 0) { v in
                    zr.clear()
                    buildPathConvertScene(zr, startAngle: v)
                },
            ]
        }
        return d
    }()
}
