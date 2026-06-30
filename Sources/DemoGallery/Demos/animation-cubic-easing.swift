import ZRenderKit
// Faithful port of zrender test/animation-cubic-easing.html
//
// Upstream: 5 red circles (shape cx=cy=r=30) at x:100, y:i*80. `startAnimation(easing)` does, per
// circle, `circle.x = 100; circle.animate('').when(1000, {x:800}).delay(idx*100).start(easing)` — a
// one-shot x slide 100→800, staggered idx*100ms, ALL with the same `easing`. `easing` is a
// `cubic-bezier(x1,y1,x2,y2)` string from a tweakpane picker (default linear); `startAnimation()` is
// called once at load.
//
// Same call sequence here (now that `createCubicEasingFunc` is ported, the `cubic-bezier(...)` string
// resolves). The DOM tweakpane picker maps to the native control panel — an `easing` preset selector
// that re-runs `startAnimation` (its onChange is exactly the html's). Sizes are scaled to the canvas.
extension DemoRegistry {
    static let demo_animation_cubic_easing: Demo = {
        // (label, cubic-bezier string) presets — the tweakpane stand-in. Index 0 is the html default.
        let presets: [(String, String)] = [
            ("linear",      "cubic-bezier(0, 0, 1, 1)"),
            ("ease",        "cubic-bezier(0.25, 0.1, 0.25, 1)"),
            ("ease-in-out", "cubic-bezier(0.42, 0, 0.58, 1)"),
            ("back",        "cubic-bezier(0.68, -0.55, 0.27, 1.55)"),
        ]

        // Build the 5 circles; return them so startAnimation can re-drive them.
        func buildCircles(_ zr: ZRender) -> [Circle] {
            var circles: [Circle] = []
            for i in 0..<5 {
                let e = circle(20, 20, 20)         // shape cx=cy=r (scaled from 30)
                e.x = 100; e.y = Double(i) * 40    // x:100, one row per circle
                zr.add(styled(e, fill: "#ff0000"))
                circles.append(e)
            }
            return circles
        }

        // startAnimation(easing): per circle reset x and arm the staggered slide with `easing`.
        func startAnimation(_ circles: [Circle], _ easing: String) {
            for (idx, e) in circles.enumerated() {
                e.x = 100
                e.animate("").when(1000, ["x": 640.0]).delay(Double(idx) * 100).start(.named(easing))
            }
        }

        var d = Demo(
            name: "animation-cubic-easing", category: "Animation",
            summary: "5 circles slide x with a cubic-bezier easing (staggered) — easing chosen like the tweakpane picker",
            width: 700, height: 200
        ) { zr in
            // Headless / no-controls: start with a visible cubic-bezier (the demo's namesake).
            startAnimation(buildCircles(zr), presets[3].1)   // 'back' so the easing is obvious
        }

        // tweakpane picker → native preset selector: changing it re-runs startAnimation (= html onChange).
        d.controls = { zr in
            let circles = buildCircles(zr)
            startAnimation(circles, presets[3].1)
            return [
                DemoControl(label: "easing", kind: .slider(min: 0, max: Double(presets.count - 1)), value: 3) { v in
                    let idx = max(0, min(presets.count - 1, Int(v.rounded())))
                    startAnimation(circles, presets[idx].1)
                    zr.refresh()
                },
            ]
        }
        return d
    }()
}
