import ZRenderKit
// Faithful port of zrender test/globalScaleRatio.html
//
// Upstream: ONE gradient Circle (red → black, default horizontal LinearGradient) at position
// [300,300], shape { cx:0, cy:0, r:50 }, style { fill: gradient, lineWidth:5, text:'circle',
// textPosition:'inside' }. The whole point of the demo is the LOOPING root-transform tween
//   circle.animate('', true).when(0,{scale:[1,1]}).when(1000,{scale:[3,3]}).when(2000,{scale:[1,1]}).start()
// which pulses the circle (and its inside label) 1→3→1 forever. A range input also drives
// `circle.globalScaleRatio` — the demo's namesake property.
//
// PORT NOTES / acceptable deviations:
//  - legacy `scale:[s,s]` array → scaleX/scaleY keys (the only transform props this port animates).
//  - the 'circle' label is upstream a textContent child positioned 'inside'; attached inner-text
//    layout (Element.updateInnerText) is a deferred no-op here, so the circle + a centred ZRText
//    live in ONE Group and the GROUP's scale is tweened — equivalent to upstream animating the
//    circle's root transform with its textContent child, so the label scales WITH the circle.
//  - the range-input → globalScaleRatio binding (a dat.GUI-style control) is not wired (residual).
extension DemoRegistry {
    static let demo_globalScaleRatio: Demo = Demo(
        name: "globalScaleRatio", category: "Transform",
        summary: "A red→black gradient circle with an inside 'circle' label, looping scale 1→3→1"
    ) { zr in
        // `new LinearGradient(); addColorStop(0,'red'); addColorStop(1,'black')`
        // (default coords 0,0,1,0 → horizontal red → black).
        let gradient = LinearGradient(0, 0, 1, 0)
        gradient.addColorStop(0, "#ff0000")
        gradient.addColorStop(1, "#000000")

        // The single Circle: shape { cx:0, cy:0, r:50 }, style { fill: gradient, lineWidth:5 }.
        // (lineWidth is harmless — Circle's default stroke is null, so nothing strokes.)
        let c = circle(0, 0, 50)
        var st = PathStyleProps()
        st.fill = .linearGradient(gradient)
        st.lineWidth = 5
        c.useStyle(st)

        // style.text:'circle', textPosition:'inside' — the in-shape label.
        let label = text("circle", 0, 0, "#ffffff", size: 14, align: .center)

        // Both centred at the group origin; the group sits at the upstream position [300,300].
        let g = Group()
        g.add(c)
        g.add(label)
        g.x = 300; g.y = 300
        zr.add(g)

        // circle.animate('', true).when(0,{scale:[1,1]}).when(1000,{scale:[3,3]}).when(2000,{scale:[1,1]}).start()
        g.animate("", true)
            .when(0, ["scaleX": 1.0, "scaleY": 1.0])
            .when(1000, ["scaleX": 3.0, "scaleY": 3.0])
            .when(2000, ["scaleX": 1.0, "scaleY": 1.0])
            .start(.named("linear"))
    }
}
