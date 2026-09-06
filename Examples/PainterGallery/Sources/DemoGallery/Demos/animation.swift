import ZRenderKit
// Faithful port of zrender test/animation.html
//
// ONE gradient Circle (shape cx:50,cy:50,r:50 at position [100,100], fill = gradient1 red→black,
// lineWidth 5) with an attached white "Circle" label (textConfig position 'inside'), driven by three
// animators:
//   1. circle.animate('').when(200, {position:[200,0]}).start()                 — one-shot quick move
//   2. circle.animate('style', true).when(1000, {fill: gradient2}).start()      — LOOPING fill tween
//   3. circle.animate('', true).when(1000,[200,0])…when(4000,[100,100]).start() — LOOPING square path
//
// All three are now real: the looping square `position` path animates root x/y (supported), the inner
// label uses the real attached textContent (Element.updateInnerText), and the gradient1→gradient2 fill
// tween works now that the Animator's gradient interpolation is wired (util.isGradientObject +
// zrColorToAnimValue gradients). zrender's legacy `position:[x,y]` array maps to element x/y.
extension DemoRegistry {
    static let demo_animation: Demo = Demo(
        name: "animation", category: "Animation",
        summary: "One gradient circle: looping square position path + looping gradient→gradient fill tween + inner label",
        width: 340, height: 340
    ) { zr in
        // gradient = red → black; gradient2 = black → blue → white.
        let gradient = LinearGradient(0, 0, 1, 1)
        gradient.addColorStop(0, "red"); gradient.addColorStop(1, "black")
        let gradient2 = LinearGradient(0, 0, 1, 1)
        gradient2.addColorStop(0, "black"); gradient2.addColorStop(0.5, "blue"); gradient2.addColorStop(1, "white")

        // Circle: shape {cx:50,cy:50,r:50}, position [100,100], style {fill: gradient, lineWidth: 5}.
        var cs = CircleShape(); cs.cx = 50; cs.cy = 50; cs.r = 50
        let circ = Circle(); circ.setShape(cs)
        circ.x = 100; circ.y = 100
        var st = PathStyleProps(); st.fill = .linearGradient(gradient); st.lineWidth = 5
        circ.useStyle(st)

        // textContent: Text { fill:'white', text:'Circle' }, textConfig { position:'inside' }.
        var ts = TextStyleProps(); ts.text = "Circle"; ts.fill = "white"
        let label = ZRText(); label.useStyle(ts)
        circ.setTextContent(label)
        var tc = ElementTextConfig(); tc.position = "inside"
        circ.setTextConfig(tc)
        zr.add(circ)

        // 1. one-shot quick move to [200, 0].
        _ = circ.animate("").when(200, ["x": 200.0, "y": 0.0]).start()
        // 2. looping fill tween gradient → gradient2.
        _ = circ.animate("style", true).when(1000, ["fill": gradient2]).start()
        // 3. looping square position path.
        _ = circ.animate("", true)
            .when(1000, ["x": 200.0, "y": 0.0])
            .when(2000, ["x": 200.0, "y": 200.0])
            .when(3000, ["x": 0.0, "y": 200.0])
            .when(4000, ["x": 100.0, "y": 100.0])
            .start()
    }
}
