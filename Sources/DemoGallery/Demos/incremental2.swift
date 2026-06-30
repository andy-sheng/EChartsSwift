import ZRenderKit
// Faithful port of zrender test/incremental2.html
//
// Per-frame accumulation: `zr.animation.on('frame', …)` adds 200 circles each frame via `zr.add`
// (each `incremental: true`, fill '#121', blend 'lighter'), incrementing a count overlay, until the
// total passes 2e4 — exactly the html. The dots are plain displayables (the `incremental` flag is a
// retained-layer perf hint upstream; natively they render through the normal display list), and the
// 'lighter' blend is now applied by the painter so the dark '#121' dots accumulate into a bright glow.
extension DemoRegistry {
    static let demo_incremental2: Demo = Demo(
        name: "incremental2", category: "Rendering",
        summary: "Incremental render — 200 additive-blended dots added per frame, accumulating to 20000",
        width: 1000, height: 600
    ) { zr in
        let W = zr.getWidth() ?? 1000, H = zr.getHeight() ?? 600

        // Canvas-filling red background (HTML: full-size Rect, fill 'red').
        zr.add(styled(rect(0, 0, W, H), fill: "red"))

        // Count overlay (HTML: zlevel 1, 40px white text with 2px black stroke), starts at 0.
        var ts = TextStyleProps()
        ts.text = "0"; ts.x = 10; ts.y = 10
        ts.fill = "#fff"; ts.stroke = "#000"; ts.lineWidth = 2; ts.fontSize = .number(40)
        let countText = ZRText(); countText.zlevel = 1; countText.useStyle(ts)
        zr.add(countText)

        // Deterministic stand-in for Math.random() (stdlib integer LCG; no Foundation/Date/random).
        var seed: UInt64 = 0x9E3779B97F4A7C15
        func rnd() -> Double {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return Double(seed >> 33) / 2147483648.0
        }

        var count = 0
        // zr.animation.on('frame', () => { if (count > 2e4) return; for 200 { … zr.add } count += 200 })
        _ = zr.animation.on("frame") { _, _ in
            if count > 20000 { return nil }
            for _ in 0..<200 {
                let c = circle(rnd() * W, rnd() * H, 5 + rnd() * 5)   // shape.r = 5 + random*5
                c.incremental = INCREMENTAL_ID_TRUE_COMPAT            // html: { incremental: true }
                var st = PathStyleProps()
                st.fill = .string("#121")                            // dark green; 'lighter' stacks to glow
                st.blend = "lighter"                                  // additive composite (painter applies it)
                c.useStyle(st)
                zr.add(c)
            }
            count += 200
            // countText.style.text += 200; countText.dirty()
            var nts = ts; nts.text = String(count); countText.useStyle(nts)
            return nil
        }
    }
}
