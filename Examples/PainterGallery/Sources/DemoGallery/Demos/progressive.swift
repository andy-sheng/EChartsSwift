import ZRenderKit
// Migrated from zrender test/progressive.html
extension DemoRegistry {
    static let demo_progressive: Demo = Demo(
        name: "progressive", category: "Rendering", summary: "Progressive render — a deterministic random-walk of many faint Bézier curves"
    ) { zr in
        // progressive.html adds 10000 quadratic BezierCurves whose endpoints/control point
        // each drift by a small random step every iteration (a random walk), every one drawn
        // with lineWidth 2, opacity 0.1 and a grayscale stroke keyed off the "checkpoint"
        // group index (round(i/1000) → 0..10, gray = round(255 * idx / 10)). Here we render a
        // deterministic, bounded version: fewer curves (still "many"), the same drift/coloring,
        // using an LCG instead of Math.random so the frame is reproducible.
        let W = 680.0, H = 200.0

        // hex grayscale without Foundation (stdlib only).
        let hexChars = Array("0123456789abcdef")
        func gray(_ v: Int) -> String {
            let c = max(0, min(255, v))
            let pair = String([hexChars[c >> 4], hexChars[c & 0xf]])
            return "#" + pair + pair + pair
        }

        // deterministic pseudo-random source (LCG; only stdlib overflow ops).
        var seed: UInt64 = 0x2545F4914F6CDD1D
        func rnd() -> Double {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return Double(seed >> 33) / 2147483648.0   // [0, 1)
        }
        // clamp the walk so the scatter stays inside the canvas.
        func clamp(_ v: Double, _ lo: Double, _ hi: Double) -> Double {
            return v < lo ? lo : (v > hi ? hi : v)
        }

        // initial positions (mirrors the HTML's seeding off random()).
        var x1  = rnd() * 2
        var y1  = rnd() * H
        var cpx1 = rnd() * W
        var cpy1 = rnd() * H
        var x2  = rnd() * W
        var y2  = rnd() * H

        let count = 500
        let groupSize = count / 10        // 10 checkpoint groups, like round(i/1000)
        for i in 0..<count {
            x1   = clamp(x1   + (rnd() - 0.5) * 10, 4, W - 4)
            y1   = clamp(y1   + (rnd() - 0.5) * 10, 4, H - 4)
            cpx1 = clamp(cpx1 + (rnd() - 0.5) * 10, 4, W - 4)
            cpy1 = clamp(cpy1 + (rnd() - 0.5) * 10, 4, H - 4)
            x2   = clamp(x2   + (rnd() - 0.5) * 10, 4, W - 4)
            y2   = clamp(y2   + (rnd() - 0.5) * 10, 4, H - 4)

            let checkpointIdx = Int((Double(i) / Double(groupSize)).rounded())
            let g = Int((255 * Double(checkpointIdx) / 10).rounded())

            // quadratic curve: only cpx1/cpy1 set (cpx2/cpy2 nil), as in the HTML.
            var b = BezierCurveShape()
            b.x1 = x1; b.y1 = y1
            b.cpx1 = cpx1; b.cpy1 = cpy1
            b.x2 = x2; b.y2 = y2
            let e = BezierCurve(); e.setShape(b)
            zr.add(styled(e, stroke: gray(g), lineWidth: 2, opacity: 0.1))
        }
    }
}
