import ZRenderKit
// Faithful port of zrender test/dirty-rect.html
//
// Upstream is a `useDirtyRect: true` stress test (the engine repaints only each element's dirty
// rectangle). That repaint is a perf-only optimization with identical pixels, so call/visual parity
// does NOT depend on it — we reproduce the SCENE and its calls instead:
//   - a magenta, red-shadowed Circle (zlevel 1) whose shape animates cx 50 -> 800 over 3s, with a
//     centred white 'Start' label;
//   - three standalone blue Texts at y=100/200/300, the middle one `ignore: true` (not drawn);
//   - 20 red Rects scattered with per-element width/height + translate + scale + rotation, each with
//     mouseover/mouseout handlers toggling the fill (cyan <-> red);
//   - one big translucent green Rect `a`, scaled + rotated.
// DEVIATIONS (allowed): Math.random() -> a deterministic sequential stand-in (one draw per field, in
// source order); canvas 1000x800 as upstream; legacy scale[]/position[] arrays -> scaleX/scaleY & x/y.
// The deferred setTimeout/setInterval mutations (text->'End', circle fill->blue, the 5s removals /
// ignore-swaps, the 3s rect repositioning) are a harness/scheduling concern and are omitted.
extension DemoRegistry {
    static let demo_dirty_rect: Demo = Demo(
        name: "dirty-rect", category: "Rendering",
        summary: "Shadowed animating circle + ignore-toggled texts + 21 transformed rects with hover handlers",
        width: 1000, height: 800
    ) { zr in
        // Deterministic stand-in for Math.random() — a sequential LCG so the scatter is stable
        // (mirrors the html calling Math.random() once per field, in source order).
        var randCounter = 0
        func rnd() -> Double {
            randCounter += 1
            return Double((randCounter &* 1103515245 &+ 12345) & 0x7fffffff) / Double(0x7fffffff)
        }

        // Recolor helper — mirrors the html's `el.target.attr('style', { fill })`. Path's
        // setStyle(key,value) doesn't cover `fill`, so rebuild a PathStyleProps and useStyle it
        // (the same approach as event.swift). The handler's ctx defaults to the element (JS `this`).
        func setFill(_ ctx: AnyObject?, _ color: String) {
            guard let p = ctx as? Path else { return }
            var st = PathStyleProps(); st.fill = .string(color); p.useStyle(st)
        }

        // Magenta circle with a red drop-shadow (zlevel 1, drawn above the rects). The shape is
        // centred on (50,50) and the element is translated to (100,200); the shape `cx` then animates
        // 50 -> 800 over 3s (Path shape animation — see animation.swift).
        let circ = circle(50, 50, 50)
        var cst = PathStyleProps()
        cst.fill = .string("#f0f")
        cst.opacity = 0.8
        cst.shadowColor = "red"
        cst.shadowBlur = 30
        cst.shadowOffsetX = 20
        cst.shadowOffsetY = -20
        circ.useStyle(cst)
        circ.x = 100; circ.y = 200
        circ.zlevel = 1

        // The circle's 'Start' label, attached via textContent + textConfig.position 'inside'
        // (Element.updateInnerText). It follows the circle's centre as the shape animates.
        var startStyle = TextStyleProps()
        startStyle.text = "Start"; startStyle.fill = "#ffffff"
        let startText = ZRText(); startText.useStyle(startStyle)
        circ.setTextContent(startText)
        var circTC = ElementTextConfig(); circTC.position = "inside"
        circ.setTextConfig(circTC)
        zr.add(circ)
        var moveCfg = ElementAnimateConfig(); moveCfg.duration = 3000
        circ.animateTo(["shape": ["cx": 800.0, "cy": 200.0] as [String: Any]], moveCfg)
        // text.animateTo({style:{fill:'#444'}}, 3000)
        var textCfg = ElementAnimateConfig(); textCfg.duration = 3000
        startText.animateTo(["style": ["fill": "#444"] as [String: Any]], textCfg)

        // Three standalone blue texts; the middle one is ignored (not drawn).
        zr.add(text("This text should be removed in the end", 100, 100, "blue", size: 16))
        let textIgnored = text("This text should be shown in the end", 100, 200, "blue", size: 16)
        textIgnored.ignore = true
        zr.add(textIgnored)
        zr.add(text("This text should not be shown in the end", 100, 300, "blue", size: 16))

        // 20 red rects scattered with per-element width/height (shape), translate (x/y), scale and
        // rotation; each toggles its fill on hover (cyan) / out (red) via Element.on.
        for _ in 0..<20 {
            let w = 100 * rnd()
            let h = 100 * rnd()
            let r = styled(rect(0, 0, w, h), fill: "rgba(200, 0, 0, 0.4)")
            r.x = 800 * rnd(); r.y = 400 * rnd()
            r.scaleX = 4 * rnd(); r.scaleY = 4 * rnd()
            r.rotation = rnd() * π
            r.on("mouseover") { ctx, _ in setFill(ctx, "rgba(0, 200, 200, 0.5)"); return nil }
            r.on("mouseout")  { ctx, _ in setFill(ctx, "rgba(200, 0, 0, 0.4)"); return nil }
            zr.add(r)
        }

        // One large translucent green rect, scaled + rotated (upstream `a`).
        let a = styled(rect(0, 0, 300, 200), fill: "rgba(0, 200, 0, 0.4)")
        a.x = 100; a.y = 100
        a.scaleX = 5 * rnd(); a.scaleY = 5 * rnd()
        a.rotation = rnd() * π
        zr.add(a)
    }
}
