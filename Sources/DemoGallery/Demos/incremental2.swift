import ZRenderKit
// Migrated from zrender test/incremental2.html
extension DemoRegistry {
    static let demo_incremental2: Demo = Demo(
        name: "incremental2", category: "Rendering",
        summary: "Incremental render — hundreds of additive-blended dots over a red fill"
    ) { zr in
        // Canvas-filling red background (HTML: full-size Rect, fill 'red').
        let w = 680.0, h = 200.0
        zr.add(styled(rect(0, 0, w, h), fill: "red"))

        // The HTML appends 200 dots per animation frame (incremental, blend 'lighter')
        // until ~2e4. For a representative static frame we lay down a deterministic
        // low-discrepancy scatter of a few hundred dots — the R2 (plastic-number)
        // sequence stands in for Math.random() so the layout is stable.
        let count = 300
        let g = 1.324717957244746              // plastic number
        let a1 = 1.0 / g                        // 0.7548...
        let a2 = 1.0 / (g * g)                   // 0.5698...
        for i in 0..<count {
            let di = Double(i)
            let fx = (0.5 + a1 * di).truncatingRemainder(dividingBy: 1.0)
            let fy = (0.5 + a2 * di).truncatingRemainder(dividingBy: 1.0)
            let r = 5.0 + Double(i % 6)          // 5..10, mirrors 5 + random*5
            let c = circle(fx * w, fy * h, r)
            c.incremental = INCREMENTAL_ID_TRUE_COMPAT  // HTML: new zrender.Circle({ incremental: true })
            var st = PathStyleProps()
            st.fill = .string("#121")            // very dark green; 'lighter' blend stacks
            st.blend = "lighter"                  // additive — overlaps brighten toward green
            c.useStyle(st)
            zr.add(c)
        }

        // Count overlay (HTML: zlevel 1, 40px white text with 2px black stroke).
        var ts = TextStyleProps()
        ts.text = String(count)
        ts.x = 10; ts.y = 10
        ts.fill = "#fff"
        ts.stroke = "#000"
        ts.lineWidth = 2
        ts.fontSize = .number(40)
        let countText = ZRText()
        countText.zlevel = 1
        countText.useStyle(ts)
        zr.add(countText)                         // added last → drawn on top
    }
}
