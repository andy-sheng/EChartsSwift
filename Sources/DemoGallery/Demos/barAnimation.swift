import ZRenderKit
// Migrated from zrender test/barAnimation.html
extension DemoRegistry {
    static let demo_barAnimation: Demo = Demo(
        name: "barAnimation", category: "Animation", summary: "Bars grow from the baseline while recoloring (shape + style tween, blue to red)"
    ) { zr in
        let n = 40
        let baseline = 188.0
        let barW = 680.0 / Double(n)
        for i in 0..<n {
            // deterministic varied height in ~[44, 168] (no randomness, no Date/timers)
            let h = 30.0 + 140.0 * Double((i * 37 + 11) % 100) / 100.0
            // Upstream builds each Rect COLLAPSED at the baseline (shape.y = height, shape.height = 0).
            let bar = rect(Double(i) * barW + 1.5, baseline, barW - 3, 0)
            zr.add(styled(bar, fill: "#0000b4"))   // base color rgb(0, 0, 180)
            // Faithful to upstream `barShape.animateTo({ shape: { height, y }, style: { fill: 'red' } }, { duration: 500 })`:
            // the bar grows UPWARD from the baseline (height 0 -> h, y baseline -> baseline - h) while
            // recoloring blue -> red. Must add to `zr` first so the animator registers with the host loop.
            var cfg = ElementAnimateConfig(); cfg.duration = 500
            bar.animateTo([
                "shape": ["height": h, "y": baseline - h] as [String: Any],
                "style": ["fill": "#ff0000"] as [String: Any]
            ], cfg)
        }
    }
}
