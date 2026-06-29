import ZRenderKit
// Migrated from zrender test/incremental3.html
extension DemoRegistry {
    static let demo_incremental3: Demo = Demo(
        name: "incremental3", category: "Rendering",
        summary: "Incremental bulk render — hundreds of blended circles glowing over a red field"
    ) { zr in
        let W = 680.0, H = 200.0

        // incremental3.html fills the whole canvas with red, then bulk-adds 10000 tiny dark-green
        // ('#121') circles drawn with blend 'lighter' (additive glow), plus a count overlay.
        // Static port: a deterministic representative frame with a few hundred circles.
        zr.add(styled(rect(0, 0, W, H), fill: "red"))

        // The HTML circles use fill '#121' + blend 'lighter', so dense overlaps brighten toward
        // green/yellow. `blend` is real public API but the native painter does not yet apply
        // composite ops, so the additive glow is APPROXIMATED with a light-green semi-transparent
        // fill whose overlaps accumulate toward the bright fill colour (blend is still set for parity).
        func glow(_ c: Circle) -> Circle {
            var st = PathStyleProps()
            st.fill = .string("#9be15d")
            st.opacity = 0.42
            st.blend = "lighter"        // faithful to incremental3.html (painter currently ignores it)
            c.useStyle(st)
            return c
        }

        // Deterministic pseudo-random scatter (stdlib integer LCG; no Foundation / Date / random).
        // The circles live in their own Group, mirroring the HTML's `group.add(circleShape)`.
        let count = 500
        let group = Group()
        var seed: UInt64 = 0x9E3779B97F4A7C15
        for _ in 0..<count {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            let cx = Double(seed >> 33) / 2147483648.0 * W
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            let cy = Double(seed >> 33) / 2147483648.0 * H
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            let r  = 3.5 + Double(seed >> 33) / 2147483648.0 * 3.0   // r ∈ [3.5, 6.5], larger than incremental.html
            group.add(glow(circle(cx, cy, r)))
        }
        zr.add(group)

        // The running count overlay: white fill with a 2px black stroke and a 40px font, matching
        // incremental3.html's textFill '#fff' / textStroke '#000' / textStrokeWidth 2 / '40px sans-serif'.
        // (The `text()` helper has no stroke, so the style is built by hand — same useStyle path.)
        var label = TextStyleProps()
        label.text = "\(count)"
        label.x = 12
        label.y = 8
        label.fill = "#ffffff"
        label.stroke = "#000000"
        label.lineWidth = 2
        label.fontSize = .number(40)
        let countText = ZRText()
        countText.useStyle(label)
        zr.add(countText)
    }
}
