import ZRenderKit
// Faithful port of zrender test/incremental.html
//
// Uses the REAL `IncrementalDisplayable` (now render-enabled — it exposes its displayables via
// childrenRef so the shared container duck-typing descends into them). The html's loop is reproduced
// 1:1: `zr.animation.on('frame', …)` adds N circles per frame via `inc.addDisplayable(c, true)` and
// bumps a running count; a 5s timer calls `inc.clearDisplaybles()`. The dark '#121' dots are drawn
// with blend 'lighter' (the painter now applies the additive composite), so dense overlaps glow.
//
// The native painter now implements the incremental RETAINED layer (CALayerPainter.drawIncrementalRetained):
// each flush draws only the PENDING displayables into a persistent bitmap and composites it, so old dots
// are never redrawn and the per-frame cost is O(batch), not O(total). That lets this run the html's real
// 2000 dots/frame. The `setInterval(clear, 5000)` is driven off accumulated frame delta (no wall-clock
// timer) so it also works headless. Math.random() → a deterministic stdlib LCG.
extension DemoRegistry {
    static let demo_incremental: Demo = Demo(
        name: "incremental", category: "Rendering",
        summary: "Incremental render — dark-green dots added every frame (additive glow), cleared every 5s",
        width: 1000, height: 600
    ) { zr in
        let W = zr.getWidth() ?? 1000, H = zr.getHeight() ?? 600

        // Full-canvas red background (HTML: Rect filling getWidth()×getHeight()).
        zr.add(styled(rect(0, 0, W, H), fill: "red"))

        // The single incremental container every dot is funnelled through (HTML:
        // `new zrender.IncrementalDisplayable(); zr.add(inc)`).
        let inc = IncrementalDisplayable()
        zr.add(inc)

        // Count overlay (HTML: text 0, 40px, white fill + 2px black stroke), starts at 0.
        var ts = TextStyleProps()
        ts.text = "0"; ts.x = 10; ts.y = 10
        ts.fill = "#fff"; ts.stroke = "#000"; ts.lineWidth = 2; ts.fontSize = .number(40)
        let countText = ZRText(); countText.useStyle(ts)
        zr.add(countText)

        // Deterministic stand-in for Math.random() (stdlib integer LCG; no Foundation/Date/random).
        var seed: UInt64 = 0x2545F4914F6CDD1D
        func rnd() -> Double {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return Double(seed >> 33) / 2147483648.0
        }

        let perFrame = 2000         // html: 2000/frame (retained layer keeps this O(batch))
        var count = 0               // running total ever added (html never resets this — only the dots clear)
        var sinceClearMs = 0.0      // accumulated frame delta → the html's setInterval(clear, 5000)

        // zr.animation.on('frame', () => { for 2000 { … inc.addDisplayable(c, true) } count += 2000; … })
        _ = zr.animation.on("frame") { _, args in
            for _ in 0..<perFrame {
                let c = circle(rnd() * W, rnd() * H, 1 + rnd() * 1)   // shape.r = 1 + random*1
                var st = PathStyleProps()
                st.fill = .string("#121")                            // dark green; 'lighter' → additive glow
                st.blend = "lighter"
                c.useStyle(st)
                inc.addDisplayable(c, true)                          // html: addDisplayable(circleShape, true)
            }
            count += perFrame
            // countText.style.text += 2000; countText.dirty()
            var nts = ts; nts.text = String(count); countText.useStyle(nts)

            // setInterval(() => inc.clearDisplaybles(), 5000) — driven off accumulated frame delta.
            let delta = (args.first as? Double) ?? 16
            sinceClearMs += delta
            if sinceClearMs >= 5000 {
                inc.clearDisplaybles()
                sinceClearMs = 0
            }
            return nil
        }
    }
}
