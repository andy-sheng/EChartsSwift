import ZRenderKit
// Faithful port of zrender test/globalScaleRatio.html
//
// Upstream: ONE gradient Circle (red → black, default horizontal LinearGradient) at position
// [300,300], shape { cx:0, cy:0, r:50 }, style { fill: gradient, lineWidth:5, text:'circle',
// textPosition:'inside' }. The whole point is the LOOPING root-transform tween on THE CIRCLE:
//   circle.animate('', true).when(0,{scale:[1,1]}).when(1000,{scale:[3,3]}).when(2000,{scale:[1,1]}).start()
// pulsing the circle (and its inside label) 1→3→1 forever. A range input also drives
// `circle.globalScaleRatio` (the namesake property — a real, animatable framework prop).
//
// Now animates the CIRCLE directly (matching the html call) with the label as an attached
// `textContent` positioned 'inside' with `local:true`, so the label scales WITH the circle's
// transform (Element.updateInnerText). legacy `scale:[s,s]` → scaleX/scaleY (the keys this port
// animates). The range-input → globalScaleRatio (DOM control) is omitted.
extension DemoRegistry {
    static let demo_globalScaleRatio: Demo = Demo(
        name: "globalScaleRatio", category: "Transform",
        summary: "A red→black gradient circle with an inside 'circle' label, looping scale 1→3→1"
    ) { zr in
        // `new LinearGradient(); addColorStop(0,'red'); addColorStop(1,'black')` (default 0,0,1,0 horizontal).
        let gradient = LinearGradient(0, 0, 1, 0)
        gradient.addColorStop(0, "#ff0000")
        gradient.addColorStop(1, "#000000")

        // The single Circle: shape { cx:0, cy:0, r:50 }, position [300,300], style { fill, lineWidth:5 }.
        let c = circle(0, 0, 50)
        c.x = 300; c.y = 300
        var st = PathStyleProps(); st.fill = .linearGradient(gradient); st.lineWidth = 5
        c.useStyle(st)

        // style.text:'circle', textPosition:'inside' → attached textContent, inside, local so it
        // inherits the circle's scale.
        var ts = TextStyleProps(); ts.text = "circle"; ts.fill = "white"; ts.fontSize = .number(14)
        let label = ZRText(); label.useStyle(ts)
        c.setTextContent(label)
        var tc = ElementTextConfig(); tc.position = "inside"; tc.local = true
        c.setTextConfig(tc)
        zr.add(c)

        // circle.animate('', true).when(0,{scale:[1,1]}).when(1000,{scale:[3,3]}).when(2000,{scale:[1,1]}).start()
        c.animate("", true)
            .when(0, ["scaleX": 1.0, "scaleY": 1.0])
            .when(1000, ["scaleX": 3.0, "scaleY": 3.0])
            .when(2000, ["scaleX": 1.0, "scaleY": 1.0])
            .start(.named("linear"))
    }
}
