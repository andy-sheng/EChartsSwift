import ZRenderKit
import Foundation
// Migrated from zrender test/segmentIgnoreThreshold.html
extension DemoRegistry {
    static let demo_segmentIgnoreThreshold: Demo = Demo(
        name: "segmentIgnoreThreshold", category: "Rendering",
        summary: "Dense stroked polygons (100-point circles) in one segmentIgnoreThreshold CompoundPath"
    ) { zr in
        // HTML builds ONE CompoundPath (segmentIgnoreThreshold:20, fill:null, stroke:'#000',
        // lineWidth:2) whose shape.paths holds 30 closed Polygons — each a circle approximated by
        // 100 points (the dense-path case the demo exists to showcase). Each iteration shrinks the
        // radius (r /= 1.3), steps cx right by max(r*2, 15), and drops a rotated "R: <r>" label.
        // CompoundPath + Path.segmentIgnoreThreshold are both public in ZRenderKit, so we mirror
        // the HTML exactly: collect the unstyled sub-Polygons and add a single styled CompoundPath.
        var r = 100.0
        var cx = r
        let cy = r + 10                 // HTML: cy = r + 10, computed once → constant 110
        let segments = 100             // 100 points per circle — the dense-path case

        // Round to 2 significant figures, then drop trailing zeros — mirrors HTML `+r.toPrecision(2)`.
        func twoSigFigs(_ x: Double) -> String {
            guard x > 0 else { return "0" }
            let factor = pow(10.0, floor(log10(x)) - 1)
            let rounded = (x / factor).rounded() * factor
            if rounded == rounded.rounded() { return String(Int(rounded.rounded())) }
            var s = String(format: "%.10f", rounded)
            while s.hasSuffix("0") { s.removeLast() }
            if s.hasSuffix(".") { s.removeLast() }
            return s
        }

        var polys: [Path] = []
        polys.reserveCapacity(30)
        for _ in 0..<30 {
            // One closed Polygon == one circle sampled at `segments` points (unstyled — the
            // CompoundPath's own style drives rendering of every concatenated subpath).
            var pts: [VectorArray] = []
            pts.reserveCapacity(segments)
            for k in 0..<segments {
                let rad = π * 2 * Double(k) / Double(segments)
                pts.append(VectorArray(cos(rad) * r + cx, sin(rad) * r + cy))
            }
            var poly = PolygonShape()
            poly.points = pts
            let pg = ZRenderKit.Polygon(); pg.setShape(poly)
            polys.append(pg)

            // Rotated radius label (HTML: Text at x:cx, y:cy+100, rotation:-π/2, align:'left',
            // default fill '#000' and default fontSize 12 — no overrides).
            var st = TextStyleProps()
            st.text = "R: \(twoSigFigs(r))"
            st.align = .left
            let label = ZRText(); label.useStyle(st)
            label.x = cx; label.y = cy + 100; label.rotation = -π / 2
            zr.add(label)

            cx += max(r * 2, 15)
            r /= 1.3
        }

        // The whole point of the demo: one CompoundPath holding all 30 dense polygons, with
        // segmentIgnoreThreshold:20 so subpixel segments are skipped at small global scales.
        let cp = CompoundPath()
        cp.setShape(CompoundPathShape(paths: polys))
        cp.segmentIgnoreThreshold = 20
        zr.add(styled(cp, stroke: "#000", lineWidth: 2))   // fill:none, matching the HTML's fill:null
    }
}
