import ZRenderKit
// Faithful port of zrender test/animation-keyframe-easing.html  (the html's #main div is full-screen).
//
// Upstream builds 10 red Circles (shape cx:30,cy:30,r:30) stacked by index at transform x:100, y:i*80,
// then runs a FOREVER-looping keyframe animation on each: the element's transform `x` eases
// 100 → 800 → 100 with `sinusoidalInOut` at t=500/1000, staggered by a delay of i*100ms. The position
// is the element TRANSFORM x (animate('', true)), not baked into the shape — so the column sweeps
// left↔right with a sinusoidal ease, each circle trailing the one above it.
//
// DEVIATIONS (the only allowed ones): (1) canvas size — html is full-screen; here it is sized (900x800)
// to fit the moving content (x reaches 800+ and y reaches i*80+60); (2) html's style `lineWidth:5` is a
// no-op (no stroke color is set, so nothing is drawn with it) and the `styled` helper only applies
// lineWidth alongside a stroke, so it is omitted.
extension DemoRegistry {
    static let demo_animation_keyframe_easing: Demo = Demo(
        name: "animation-keyframe-easing", category: "Animation",
        summary: "10 red circles loop-sweeping transform x 100→800→100 with staggered sinusoidalInOut easing",
        width: 900, height: 800
    ) { zr in
        // for (i in 0..<10) new Circle({ x:100, y:i*80, shape:{cx:30,cy:30,r:30}, style:{fill:'red'} })
        for i in 0..<10 {
            let c = styled(circle(30, 30, 30), fill: "red")
            c.x = 100
            c.y = Double(i) * 80

            zr.add(c)

            // circle.animate('', true).when(500,{x:800},'sinusoidalInOut')
            //   .when(1000,{x:100},'sinusoidalInOut').delay(i*100).start()
            c.animate("", true)
                .when(500, ["x": 800.0], .named("sinusoidalInOut"))
                .when(1000, ["x": 100.0], .named("sinusoidalInOut"))
                .delay(Double(i) * 100)
                .start()
        }
    }
}
