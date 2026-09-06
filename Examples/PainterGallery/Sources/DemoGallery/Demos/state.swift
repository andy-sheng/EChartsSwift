import ZRenderKit
// Faithful port of zrender test/state.html  (canvas 1000x600)
//
// Upstream is ONE Rect with 6 named states registered via `ensureState`, an additive cubicOut
// `stateTransition`, and a dat.GUI panel that toggles each state (+ animation / clearStates /
// applyAllStates). Toggling a state animates the rect to the union of the active states, restoring
// dropped props to normal — driven by the now-real state machinery (Element.useState / useStates /
// clearStates / toggleState + stateTransition).
//
// The dat.GUI panel is mapped to the native control panel (the gallery's `controls`). The headless
// `build` path shows the initial normal rect (all states off), matching the html's first render.
extension DemoRegistry {
    static let demo_state: Demo = {
        var d = Demo(
            name: "state", category: "Paint",
            summary: "One Rect toggling 6 named states (move/rotate/enlarge/fill/shadow) with animated stateTransition",
            width: 1000, height: 600
        ) { zr in
            _ = buildStateScene(zr)
        }

        // dat.GUI → native control panel: 6 state toggles + animation + clearStates + applyAllStates.
        d.controls = { zr in
            let rect = buildStateScene(zr)
            let allStates = ["moveRight", "moveDown", "rotate", "enlarge", "changeFill", "shadow"]

            // statesFolder.add(config, stateName).onChange(() => rect.toggleState(stateName, on))
            var controls: [DemoControl] = allStates.map { name in
                DemoControl(label: name, kind: .toggle, value: 0) { on in
                    rect.toggleState(name, on != 0)
                }
            }
            // gui.add(config, 'animation') → rect.stateTransition.duration = animation ? 1000 : 0
            controls.append(DemoControl(label: "animation", kind: .toggle, value: 1) { on in
                rect.stateTransition?.duration = (on != 0) ? 1000 : 0
            })
            // gui.add(config, 'applyAllStates') → rect.useStates(allStates)  (modeled as a momentary toggle)
            controls.append(DemoControl(label: "applyAllStates", kind: .toggle, value: 0) { on in
                if on != 0 { rect.useStates(allStates) }
            })
            // gui.add(config, 'clearStates') → rect.clearStates()
            controls.append(DemoControl(label: "clearStates", kind: .toggle, value: 0) { on in
                if on != 0 { rect.clearStates() }
            })
            return controls
        }
        return d
    }()
}

/// Build the single stateful Rect and return it (so the gallery's controls can drive it).
private func buildStateScene(_ zr: ZRender) -> Rect {
    // new Rect({ shape: {x:-50,y:-50,width:100,height:100}, x:100, y:100,
    //            style: { fill:'red', shadowColor:'rgba(0,0,0,0.5)' } })
    let r = rect(-50, -50, 100, 100)
    r.x = 100; r.y = 100
    var st = PathStyleProps()
    st.fill = .string("red")
    st.shadowColor = "rgba(0, 0, 0, 0.5)"   // set, but shadowBlur 0 → no visible shadow until `shadow`
    r.useStyle(st)
    zr.add(r)

    // rect.ensureState(name).<prop> = ...  (the 6 states, exactly as the html registers them)
    r.ensureState("moveRight").x = 200
    r.ensureState("moveDown").y = 200
    r.ensureState("rotate").rotation = 2
    r.ensureState("enlarge").shape = ["x": -100.0, "y": -100.0, "width": 200.0, "height": 200.0]
    r.ensureState("changeFill").style = ["fill": "green"]   // raw color string (html: fill:'green') — the color tween bridges String↔ZRColor
    r.ensureState("shadow").style = ["shadowBlur": 20.0]

    // rect.stateTransition = { duration: 1000, additive: true, easing: 'cubicOut' }
    var transition = ElementAnimateConfig()
    transition.duration = 1000
    transition.additive = true
    transition.easing = .named("cubicOut")
    r.stateTransition = transition

    return r
}
