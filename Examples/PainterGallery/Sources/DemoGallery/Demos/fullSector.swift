import ZRenderKit
// Faithful port of zrender test/fullSector.html  (canvas 1000x500)
//
// Upstream is ONE Sector { r:100, r0:0, cx:100, cy:100, startAngle:-π/2, endAngle:3π/2 } at
// position [0,0], then `animateTo({shape:{percent:0}})`. startAngle..endAngle spans a full 2π, so
// with r0=0 it is a complete disk. No style is set → default fill '#000'.
//
// NOTE: `Sector` has NO `percent` shape field (neither upstream nor here), so `animateTo({shape:
// {percent:0}})` is a no-op in BOTH the JS and the native engine — the disk stays full. The call is
// kept verbatim so the zrender call sequence matches the html exactly.
extension DemoRegistry {
    static let demo_fullSector: Demo = Demo(
        name: "fullSector", category: "Shapes",
        summary: "A single full-circle Sector (r0=0, −π/2 → 3π/2) — default black fill",
        width: 1000, height: 500
    ) { zr in
        var s = SectorShape()
        s.cx = 100; s.cy = 100; s.r0 = 0; s.r = 100
        s.startAngle = -1.5707963267948966   // -π/2
        s.endAngle = 4.71238898038469        //  3π/2
        let curve = Sector(); curve.setShape(s)
        zr.add(styled(curve, fill: "#000"))  // no style in html → default fill

        // curve.animateTo({ shape: { percent: 0 } })  — no-op (Sector has no `percent`), kept for parity
        curve.animateTo(["shape": ["percent": 0.0]])
    }
}
