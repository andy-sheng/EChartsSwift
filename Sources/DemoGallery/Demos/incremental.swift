import ZRenderKit
// Migrated from zrender test/incremental.html
extension DemoRegistry {
    static let demo_incremental: Demo = Demo(
        name: "incremental", category: "Rendering",
        summary: "Incremental render — additive-blended dark-green dots accumulated over a red field"
    ) { zr in
        let W = 680.0, H = 200.0

        // faithful background: incremental.html fills the whole canvas with red.
        zr.add(styled(rect(0, 0, W, H), fill: "red"))

        // incremental.html funnels every circle through a single container
        // (`new zrender.IncrementalDisplayable()` → `zr.add(inc)` → per-circle
        // `inc.addDisplayable(circleShape, true)`). IncrementalDisplayable IS ported, but
        // NativePainter has no incremental-layer brush and neither display-list flattener
        // recurses into it (it is not GroupLike), so routing circles through it would render
        // nothing. A plain Group is the render-correct stand-in for the html's single
        // circle container (same approach as incremental3.swift) and preserves the structure:
        // one container, every circle added to it.
        let group = Group()
        zr.add(group)

        // The HTML appends 2000 dots per animation frame (fill '#121', blend 'lighter')
        // and clears every 5s. For a representative static frame we lay down a deterministic
        // pseudo-random scatter (stdlib integer LCG; no Foundation / Date / random — the
        // established convention for the incremental demos).
        let count = 800
        var seed: UInt64 = 0x2545F4914F6CDD1D
        for _ in 0..<count {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            let cx = Double(seed >> 33) / 2147483648.0 * W
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            let cy = Double(seed >> 33) / 2147483648.0 * H
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            let r  = 1.0 + Double(seed >> 33) / 2147483648.0 * 1.0   // shape.r = 1 + random*1 → [1, 2)
            let c = circle(cx, cy, r)
            var st = PathStyleProps()
            st.fill = .string("#121")     // very dark green; 'lighter' blend stacks overlaps toward green
            st.blend = "lighter"           // additive composite (faithful to html; painter ignores it for now)
            c.useStyle(st)
            group.add(c)                   // mirrors inc.addDisplayable(circleShape, true)
        }

        // Running count overlay (HTML: 40px white text with a 2px black outline:
        // textFill '#fff' / textStroke '#000' / textStrokeWidth 2). The text() helper has
        // no stroke, so the style is built by hand — same useStyle path as the siblings.
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
