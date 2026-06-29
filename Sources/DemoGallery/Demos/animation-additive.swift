import ZRenderKit
// Migrated from zrender test/animation-additive.html
extension DemoRegistry {
    static let demo_animation_additive: Demo = Demo(
        name: "animation-additive", category: "Animation",
        summary: "Additive vs normal animateTo/animateFrom hexagons — click to animate rotation + scale",
        width: 760, height: 800
    ) { zr in
        // Faithful port of the upstream interaction. Four 2x2 cells, each an Isogon (n=6, r=40,
        // shape centred on 0,0) positioned via the element transform (x/y = cell centre). Every
        // cell has two black "backbone" outlines marking the scale bounds — one at scaleX/Y = 1
        // (MIN) and one at scaleX/Y = 4 (MAX) with `strokeNoScale` so the 2px stroke holds under
        // the 4x scale — plus a red 60%-opacity animated hexagon at scale 1 carrying a yellow
        // `textContent` label placed by `textConfig.position = 'inside'`.
        //
        // Clicking the canvas runs updateAnimation(): the two top hexagons `animateTo` the new
        // rotation/scale (additive on the left, normal on the right); the two bottom hexagons are
        // snapped to the new state and `animateFrom` their previous state (additive left / normal
        // right) — exactly mirroring the html's hexogonAdditive/Normal + hexogon2Additive/Normal.
        //
        // DETERMINISTIC STAND-IN: the html's default 'fixed' param mode is used (no Math.random):
        // rotation toggles +-4π and scale toggles MAX<->MIN as rotationSign/scaleSign flip each
        // click, identical to updateAnimation()'s `else` branch with {updateRotate, updateScale}.
        //
        // RESIDUALS (acceptable dat.GUI / framework deviations):
        //  - The control bar (param: random|fixed, easing: cubicInOut|linear, and the
        //    rotate / rotate-and-scale / scale buttons + remaining-ms timers) is not reproduced;
        //    the canvas click stands in for the "rotate and scale" button (zr.on('click')).
        //  - The label uses textContent + textConfig.position 'inside' faithfully, but
        //    Element.updateInnerText (the inside-layout math) is a deferred no-op in this port,
        //    so the label renders at the host origin rather than the measured inside position.
        let MAX = 4.0          // MAX_SCALE_VALUE
        let MIN = 1.0          // MIN_SCALE_VALUE
        let DURATION = 3000.0

        // createHexogon(text, position, scale, isBackbone) from the html.
        func makeHex(_ px: Double, _ py: Double, _ sc: Double, backbone: Bool, label: String?) -> Isogon {
            var s = IsogonShape(); s.x = 0; s.y = 0; s.r = 40; s.n = 6   // shape { cx:0, cy:0, r:40, n:6 }
            let e = Isogon(); e.setShape(s)
            e.x = px; e.y = py                                            // position
            e.scaleX = sc; e.scaleY = sc                                  // scale
            var st = PathStyleProps()
            if backbone {
                st.fill = .string("none")        // upstream fill: null
                st.stroke = .string("#000000")   // '#000'
                st.lineWidth = 2
                st.strokeNoScale = true          // keep 2px under scaleX/Y = 4
            } else {
                st.fill = .string("#ff0000")     // 'red'
                st.opacity = 0.6
            }
            e.useStyle(st)
            if let label = label {               // textContent: new Text({ style:{ fill:'yellow', text } })
                var ts = TextStyleProps()
                ts.text = label; ts.fill = "yellow"
                let t = ZRText(); t.useStyle(ts)
                e.setTextContent(t)
                var tc = ElementTextConfig(); tc.position = "inside"   // textConfig: { position: 'inside' }
                e.setTextConfig(tc)
            }
            return e
        }

        // Top-left: animationTo / Additive.
        zr.add(makeHex(180, 200, MIN, backbone: true,  label: nil))
        zr.add(makeHex(180, 200, MAX, backbone: true,  label: nil))
        let hexogonAdditive = makeHex(180, 200, MIN, backbone: false, label: "animationTo\nAdditive")
        zr.add(hexogonAdditive)

        // Top-right: animationTo / Normal.
        zr.add(makeHex(530, 200, MIN, backbone: true,  label: nil))
        zr.add(makeHex(530, 200, MAX, backbone: true,  label: nil))
        let hexogonNormal = makeHex(530, 200, MIN, backbone: false, label: "animationTo\nNormal")
        zr.add(hexogonNormal)

        // Bottom-left: animationFrom / Additive.
        zr.add(makeHex(180, 550, MIN, backbone: true,  label: nil))
        zr.add(makeHex(180, 550, MAX, backbone: true,  label: nil))
        let hexogon2Additive = makeHex(180, 550, MIN, backbone: false, label: "animationFrom\nAdditive")
        zr.add(hexogon2Additive)

        // Bottom-right: animationFrom / Normal.
        zr.add(makeHex(530, 550, MIN, backbone: true,  label: nil))
        zr.add(makeHex(530, 550, MAX, backbone: true,  label: nil))
        let hexogon2Normal = makeHex(530, 550, MIN, backbone: false, label: "animationFrom\nNormal")
        zr.add(hexogon2Normal)

        // updateAnimation() state (html lines 104-108).
        var rotation = 0.0
        var scale = MIN
        var rotationSign = 1.0
        var scaleSign = 1.0

        func cfg(_ additive: Bool) -> ElementAnimateConfig {
            var c = ElementAnimateConfig()
            c.duration = DURATION
            c.easing = .named("linear")   // html default easing
            c.additive = additive
            return c
        }

        // updateAnimation({updateRotate: true, updateScale: true}) — the 'fixed' param branch.
        func updateAnimation() {
            rotation = π * 4 * rotationSign
            scale = scaleSign > 0 ? MAX : MIN

            var props: ElementProps = [:]
            rotationSign = -rotationSign
            props["rotation"] = rotation
            scaleSign = -scaleSign
            props["scaleX"] = scale
            props["scaleY"] = scale

            hexogonAdditive.animateTo(props, cfg(true))
            hexogonNormal.animateTo(props, cfg(false))

            // hexogon2Additive: capture current props, snap element to new state, animate FROM old.
            var currA: ElementProps = [:]
            currA["rotation"] = hexogon2Additive.rotation
            hexogon2Additive.rotation = rotation
            currA["scaleX"] = hexogon2Additive.scaleX
            currA["scaleY"] = hexogon2Additive.scaleY
            hexogon2Additive.scaleX = scale
            hexogon2Additive.scaleY = scale
            hexogon2Additive.animateFrom(currA, cfg(true))

            // hexogon2Normal: same, non-additive.
            var currN: ElementProps = [:]
            currN["rotation"] = hexogon2Normal.rotation
            hexogon2Normal.rotation = rotation
            currN["scaleX"] = hexogon2Normal.scaleX
            currN["scaleY"] = hexogon2Normal.scaleY
            hexogon2Normal.scaleX = scale
            hexogon2Normal.scaleY = scale
            hexogon2Normal.animateFrom(currN, cfg(false))
        }

        // zr.on('click', () => updateAnimation({updateRotate:true, updateScale:true})) (html line 147).
        zr.on("click") { _, _ in updateAnimation(); return nil }
    }
}
