import ZRenderKit
// Migrated from zrender test/animation.html
extension DemoRegistry {
    static let demo_animation: Demo = Demo(
        name: "animation", category: "Animation",
        summary: "Shapes animateTo new positions and fill colors (position + style tweens)"
    ) { zr in
        // animation.html builds ONE gradient Circle (red → black) labelled 'Circle', then drives
        // it with several animators: a looping square `position` path and a fill tween toward a
        // second gradient. The label is attached via `textConfig: { position: 'inside' }`, but the
        // port's inner-text layout (Element.updateInnerText) is a deferred no-op, so a standalone
        // centred ZRText reproduces the same look. We build the INITIAL frame (so the static thumb
        // shows the start state) and call the PUBLIC Element.animateTo so the gallery's animation
        // loop tweens each shape — faithful to upstream `circle.animate(...).when(...).start()`.

        // The HTML's first gradient (`gradient`): red → black. (Its second gradient — black → blue
        // → white — drove the fill tween; here the colour animation is shown with solid fills below,
        // the proven animation path — see barAnimation.)
        let gradient = LinearGradient(0, 0, 1, 1)
        gradient.addColorStop(0, "#ff0000")
        gradient.addColorStop(1, "#000000")

        // The labelled gradient circle. Drawn at its element origin (shape centred on 0,0) and held
        // in place so the 'Circle' label stays centred, while its radius pulses — one representative
        // `shape` animation in lieu of the off-canvas square `position` loop.
        let main = gradFill(circle(0, 0, 40), .linearGradient(gradient))
        main.x = 110; main.y = 100
        zr.add(main)
        zr.add(text("Circle", 110, 100, "#ffffff", size: 15, align: .center))
        var pulse = ElementAnimateConfig(); pulse.duration = 1200
        main.animateTo(["shape": ["r": 58.0] as [String: Any]], pulse)

        // Two solid circles that animate to NEW POSITIONS and NEW COLORS — the core of the HTML
        // (which animates `position` and the style `fill`). Element x/y are Transformable props
        // (the position tween) and the style fill tween mirrors barAnimation's proven path.
        let blue = styled(circle(0, 0, 30), fill: "#0000ff")
        blue.x = 300; blue.y = 60
        zr.add(blue)
        var moveA = ElementAnimateConfig(); moveA.duration = 1400
        blue.animateTo(["x": 560.0, "y": 60.0,
                        "style": ["fill": "#00c853"] as [String: Any]], moveA)

        let green = styled(circle(0, 0, 30), fill: "#3ba272")
        green.x = 300; green.y = 150
        zr.add(green)
        var moveB = ElementAnimateConfig(); moveB.duration = 1400
        green.animateTo(["x": 560.0, "y": 150.0,
                         "style": ["fill": "#ee6666"] as [String: Any]], moveB)
    }
}
