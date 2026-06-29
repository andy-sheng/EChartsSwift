import ZRenderKit
// Faithful port of zrender test/dirty.html
//
// Upstream draws exactly TWO circles and wires three buttons that mutate the FIRST one:
//   - circle        : { style:{ fill:'red' },  shape:{ cx:100, cy:100, r:30 } }
//   - targetBgCircle : { style:{ fill:'#aaa' }, shape:{ cx:200, cy:100, r:40 }, z:-1 }
//   zr.add(circle); zr.add(targetBgCircle)   // grey z:-1 → always paints behind
// Buttons (exercise the renderer's dirty-region repaint):
//   "hide"               → circle.attr({ style:{ opacity:0 } })
//   "move to grey circle" → circle.attr({ shape:{ cx:200 } })
//   "show"               → circle.attr({ style:{ opacity:1 } })
// Clicked in turn, the red circle vanishes, slides to cx 200, then reappears inside the grey one.
//
// Native port: the same two circles, plus the three momentary buttons mapped to the gallery's
// DemoControl panel (the buttons->control-panel deviation, like poly.swift). The HTML's
// `attr({style:{...}})` / `attr({shape:{...}})` mutations are expressed with the demo-proven
// mutators `pathStyle.opacity = … ; dirtyStyle()` (style) and `setShape(…)` (shape). Each toggle's
// "on" branch issues the exact call its button does; "off" reverses it so the toggle is usable.

/// Build the dirty scene and return the live red circle (so the controls can mutate it).
@discardableResult
private func buildDirtyScene(_ zr: ZRender) -> Circle {
    // circle: red, cx 100, cy 100, r 30
    let redCircle = styled(circle(100, 100, 30), fill: "red")
    // targetBgCircle: grey, cx 200, cy 100, r 40, z -1 (paints behind)
    let greyCircle = styled(circle(200, 100, 40), fill: "#aaaaaa")
    greyCircle.z = -1
    zr.add(redCircle)        // mirror the HTML's add order
    zr.add(greyCircle)
    return redCircle
}

extension DemoRegistry {
    static let demo_dirty: Demo = {
        var d = Demo(
            name: "dirty", category: "Rendering",
            summary: "Dirty-region repaint: hide / move / show the red circle into the grey target"
        ) { zr in
            // Headless / no-controls path: just the initial scene (red apart, grey target).
            buildDirtyScene(zr)
        }

        // Interactive path: same scene + the three button-equivalent controls on the red circle.
        d.controls = { zr in
            let red = buildDirtyScene(zr)
            return [
                // main0Btn1 "hide" → circle.attr({ style:{ opacity:0 } })
                DemoControl(label: "hide", kind: .toggle, value: 0) { on in
                    red.pathStyle.opacity = on != 0 ? 0 : 1
                    red.dirtyStyle()
                },
                // main0Btn2 "move to grey circle" → circle.attr({ shape:{ cx:200 } })
                DemoControl(label: "move to grey circle", kind: .toggle, value: 0) { on in
                    var s = CircleShape(); s.cx = on != 0 ? 200 : 100; s.cy = 100; s.r = 30
                    red.setShape(s)
                },
                // main0Btn3 "show" → circle.attr({ style:{ opacity:1 } })
                DemoControl(label: "show", kind: .toggle, value: 0) { on in
                    red.pathStyle.opacity = on != 0 ? 1 : 0
                    red.dirtyStyle()
                },
            ]
        }
        return d
    }()
}
