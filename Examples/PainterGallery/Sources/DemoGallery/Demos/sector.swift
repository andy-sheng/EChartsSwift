import ZRenderKit
// Faithful port of zrender test/sector.html  (canvas 1000x800)
//
// Upstream adds 14 Sectors with `style {stroke:'black'}` — and NO fill, so zrender's default path
// fill ('#000') applies → they render SOLID BLACK (+ black stroke), not as outlines. (Verified
// against the html in the gallery's right pane.) Each at a `position` with shape cx/cy defaulting to
// 0, exercising edge cases: collapsed (startAngle==endAngle → a line), full circle, assorted
// cornerRadius (number & 4-element arrays), and NaN angles (renders nothing).
extension DemoRegistry {
    static let demo_sector: Demo = Demo(
        name: "sector", category: "Shapes",
        summary: "14 black Sectors: collapsed / full-circle / cornerRadius / NaN edge cases",
        width: 1000, height: 800
    ) { zr in
        // position [px,py] → element x/y; shape cx/cy stay 0 (as in the html).
        func sec(_ px: Double, _ py: Double, _ start: Double, _ end: Double,
                 r0: Double = 0, r: Double, corner: CornerRadius? = nil, lw: Double = 1) {
            var s = SectorShape()
            s.cx = 0; s.cy = 0; s.r0 = r0; s.r = r
            s.startAngle = start; s.endAngle = end
            if let corner = corner { s.cornerRadius = corner }
            let e = Sector(); e.setShape(s)
            e.x = px; e.y = py
            // html sets only `stroke:'black'` → fill defaults to '#000' (zrender DEFAULT_PATH_STYLE).
            zr.add(styled(e, fill: "#000", stroke: "black", lineWidth: lw))
        }

        let p = π
        sec(100, 100, -p / 2, -p / 2, r0: 50, r: 100)                       // collapsed → line
        sec(100, 100,  0,      0,     r0: 50, r: 100)                       // collapsed
        sec(100, 100,  p / 2,  p / 2, r0: 50, r: 100)                       // collapsed
        sec(100, 100,  p,      p,     r0: 50, r: 100)                       // collapsed
        sec(100, 100,  0,      0,     r0: 50, r: 100, corner: .array([10, 10]))
        sec(100, 300,  0.6981317007977319, 0.6981317007977318, r: 100)      // collapsed → line
        sec(100, 550,  p * 2, -1,     r: 100, corner: .number(20))
        sec(400, 150,  p * -160 / 180, p * -20 / 180, r0: 50, r: 140, corner: .array([5, 15, 0, 70]))
        sec(400, 350,  p * -160 / 180, p * -20 / 180, r0: 50, r: 140, corner: .array([0, 0, 0, 20]))
        sec(400, 550,  p * -160 / 180, p * -20 / 180, r: 140, corner: .array([0, 0, 35, 20]))
        sec(650, 100, -1.570796326794896, 4.712388980384691, r: 100)        // full circle
        sec(650, 250,  1.0001, 1, r: 100)                                   // collapsed → line
        sec(650, 500,  1.0002, 1, r: 100)                                   // nearly a circle
        sec(400, 650,  Double.nan, Double.nan, r: 100, lw: 10)              // NaN → nothing
    }
}
