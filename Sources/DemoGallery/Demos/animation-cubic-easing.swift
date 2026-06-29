import ZRenderKit
// Migrated from zrender test/animation-cubic-easing.html
extension DemoRegistry {
    static let demo_animation_cubic_easing: Demo = Demo(
        name: "animation-cubic-easing", category: "Animation",
        summary: "Cubic-bezier easing — 5 red circles slide left→right, staggered per row",
        width: 680, height: 200
    ) { zr in
        // HTML builds 5 red circles (shape cx=cy=r=30) at element x=100, y=i*80, then on
        // startAnimation() animates element.x 100 -> 800 over 1000ms with a per-circle delay
        // (idx*100ms), mirroring `circle.animate('').when(1000,{x:800}).delay(idx*100).start()`.
        // We reproduce the SAME call chain so native drives the slide rather than freezing on
        // the start frame. Sizes/spacing/target-x are scaled to fit the 680x200 demo canvas.
        // The html's tweakpane cubic-bezier picker drives start(easing); the baseline
        // startAnimation() call uses default easing, which is what we replay here.
        for i in 0..<5 {
            let e = circle(20, 20, 20)   // local circle: cx = cy = r
            e.x = 50                      // initial animation position (start of the slide)
            e.y = Double(i) * 40          // one row per circle
            zr.add(styled(e, fill: "#ff0000"))
            // add to zr first (so the animator registers with the host loop), then arm the
            // slide — faithful to html `circle.animate('').when(1000,{x:800}).delay(idx*100).start()`.
            e.animate("")
                .when(1000, ["x": 600.0])
                .delay(Double(i) * 100)
                .start()
        }
    }
}
