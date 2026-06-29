import ZRenderKit
// Faithful port of zrender test/animation-additive-simple.html  (#main is the full window)
//
// Upstream: two identical red hexagons (Isogon, n=6, r=100) — "Additive" at element x=150 and
// "Normal" at x=400 (both y=200), each carrying a white textContent label. `window.onclick` advances a
// SHARED rotation + scale by a random step (flipping `sign` each click) and calls `animateTo` on BOTH:
//   hexogonAdditive.animateTo({rotation, scaleX:scale, scaleY:scale}, {duration:2000, additive:true, easing:'cubicInOut'})
//   hexogonNormal  .animateTo({rotation, scaleX:scale, scaleY:scale}, {duration:2000,                easing:'cubicInOut'})
// The whole point is additive vs normal: clicking again while a tween is still running makes the
// additive hexagon LAYER the new tween on top of the running one, while the normal hexagon restarts
// from its current state. (A single tween looks identical for both — the difference only shows up
// across overlapping clicks, hence the live toggle below.)
//
// DEVIATIONS (the only allowed ones): (1) Math.random() → a deterministic per-click stand-in with the
// same ranges; (2) window.onclick → an `animate` toggle control (the native analog of repeated clicks),
// while the headless `build` path auto-fires one step like bezier.swift; (3) the white label is a
// standalone centred ZRText rather than an attached textContent — `Element.updateInnerText` (the
// inner-text layout) is a deferred no-op in this port, so an attached textContent would not render;
// same look, except the label does not rotate/scale with the hexagon. Fill 'red' → "#ff0000".
//
// NOTE: the hexagon shape is centred on the element origin (shape x/y = 0) and the element is placed
//   via x/y, so rotation/scale happen AROUND the hexagon centre (in place) — exactly like upstream,
//   whose Isogon has element x/y = 150|400,200 and shape {cx:0,cy:0}.

/// Drives the shared rotation/scale state across clicks and issues the additive + normal `animateTo`.
private final class AdditiveSimpleDriver {
    let additive: Isogon
    let normal: Isogon
    var rotation = 0.0
    var scale = 1.0
    var sign = 1.0
    var step = 1
    init(_ additive: Isogon, _ normal: Isogon) { self.additive = additive; self.normal = normal }

    /// One `window.onclick`: advance by a deterministic "random" step, then animate both hexagons.
    func click() {
        // deterministic stand-in for Math.random() in [0,1), varied per click
        func frac(_ k: Int) -> Double { Double((k &* 2654435761) & 0x7fffffff) / Double(0x7fffffff) }

        rotation += (frac(step) * 3 + 10) * sign           // (Math.random()*3)+10  →  [10,13)
        let scaleRand = frac(step &* 7 &+ 1)               // Math.random()*1       →  [0,1)
        scale += scaleRand * sign
        scale += scaleRand * sign                          // upstream adds it twice
        sign = -sign
        step += 1

        var add = ElementAnimateConfig()
        add.duration = 2000; add.additive = true; add.easing = .named("cubicInOut")
        additive.animateTo(["rotation": rotation, "scaleX": scale, "scaleY": scale], add)

        var norm = ElementAnimateConfig()
        norm.duration = 2000; norm.easing = .named("cubicInOut")
        normal.animateTo(["rotation": rotation, "scaleX": scale, "scaleY": scale], norm)
    }
}

/// Build the scene and return the two hexagon refs (so the controls can drive them).
private func buildAdditiveSimpleScene(_ zr: ZRender) -> AdditiveSimpleDriver {
    func hexogon(_ x: Double, _ label: String) -> Isogon {
        var s = IsogonShape(); s.x = 0; s.y = 0; s.r = 100; s.n = 6   // centred on the element origin
        let e = Isogon(); e.setShape(s)
        e.x = x; e.y = 200                                            // rotate/scale around (x, 200)
        zr.add(styled(e, fill: "#ff0000"))                           // style { fill: 'red' }
        // white textContent label, drawn standalone (default vertical align is 'top', so lift by ~half
        // the font height to centre it on the hexagon).
        zr.add(text(label, x, 200 - 7, "#ffffff", size: 14, align: .center))
        return e
    }
    return AdditiveSimpleDriver(hexogon(150, "Additive"), hexogon(400, "Normal"))
}

extension DemoRegistry {
    static let demo_animation_additive_simple: Demo = {
        var d = Demo(
            name: "animation-additive-simple", category: "Animation",
            summary: "Two red hexagons; click runs an additive (left) vs normal (right) rotate+scale tween"
        ) { zr in
            // Headless / no-controls path: build + auto-fire one click (like bezier.swift).
            buildAdditiveSimpleScene(zr).click()
        }

        // Interactive path: same scene + an `animate` toggle — the native analog of window.onclick.
        // Each flip is one click; flipping it back and forth replays the additive-vs-normal contrast.
        d.controls = { zr in
            let driver = buildAdditiveSimpleScene(zr)
            return [
                DemoControl(label: "animate (click)", kind: .toggle, value: 0) { _ in
                    driver.click()
                }
            ]
        }
        return d
    }()
}
