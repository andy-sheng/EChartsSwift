import ZRenderKit
// Faithful port of zrender test/incremental3.html
//
// Unlike incremental / incremental2 this demo is STATIC in upstream: it bulk-adds 10000 tiny '#121'
// circles to a Group in one shot at build (no `animation.on('frame')`), with `countText` fixed at
// 10000. So there is no per-frame "increase" to reproduce — the faithful behaviour is the dense field
// itself. The dots use blend 'lighter' (the painter now applies the additive composite), so dense
// overlaps brighten the red toward yellow/white exactly like the canvas. Math.random() → a
// deterministic stdlib LCG; the count is reduced from 10000 (no retained incremental layer natively,
// so every dot is re-walked per frame — see incremental.swift header) while keeping the saturated look.
extension DemoRegistry {
    static let demo_incremental3: Demo = Demo(
        name: "incremental3", category: "Rendering",
        summary: "Incremental bulk render — thousands of additive-blended dots glowing over a red field",
        width: 1000, height: 600
    ) { zr in
        let W = zr.getWidth() ?? 1000, H = zr.getHeight() ?? 600

        // Full-canvas red background (HTML: Rect filling getWidth()×getHeight()).
        zr.add(styled(rect(0, 0, W, H), fill: "red"))

        // Bulk-add the circles to a Group (HTML: `group.add(circleShape)` in a 10000-iteration loop),
        // each fill '#121' + blend 'lighter' + incremental flag — drawn additively for the glow.
        let count = 4000               // html: 10000 (reduced for the non-retained native path)
        let group = Group()
        var seed: UInt64 = 0x9E3779B97F4A7C15
        func rnd() -> Double {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return Double(seed >> 33) / 2147483648.0
        }
        for _ in 0..<count {
            let c = circle(rnd() * W, rnd() * H, 5 + rnd() * 5)      // shape.r = 5 + random*5
            c.incremental = INCREMENTAL_ID_TRUE_COMPAT               // html: { incremental: true }
            var st = PathStyleProps()
            st.fill = .string("#121")                               // dark green; 'lighter' stacks to glow
            st.blend = "lighter"
            c.useStyle(st)
            group.add(c)
        }
        zr.add(group)

        // Count overlay (HTML: zlevel 1, text 10000, 40px white fill + 2px black stroke).
        var label = TextStyleProps()
        label.text = "\(count)"
        label.x = 10; label.y = 10
        label.fill = "#ffffff"; label.stroke = "#000000"; label.lineWidth = 2
        label.fontSize = .number(40)
        let countText = ZRText()
        countText.zlevel = 1            // html: Text({ zlevel: 1 })
        countText.useStyle(label)
        zr.add(countText)
    }
}
