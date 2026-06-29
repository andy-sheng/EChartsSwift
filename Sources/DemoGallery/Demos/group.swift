import ZRenderKit
// Faithful port of zrender test/group.html  (the html's #main div is 1000x500)
//
// Upstream builds ONE Group at position [100,100] holding two Circles, then runs two FOREVER-looping
// position animations: a 4-keyframe square path on the group, and a 4-keyframe horizontal wiggle on
// the first child circle. The first circle has NO style block, so zrender's default closed-shape fill
// (#000) applies; the second circle is filled 'red'.
//
// It ends with `zr.configLayer(0, { motionBlur:true, lastFrameAlpha:0.99 })` — each frame retains 99%
// of the previous one, leaving fading motion-blur trails behind the moving circles.
//
// DEVIATIONS (the only allowed ones): the legacy `position`/`scale` ARRAY props are not ported, so the
// position keyframes animate the equivalent x/y keys and the no-op `scale:[1,1]` is dropped.
extension DemoRegistry {
    static let demo_group: Demo = Demo(
        name: "group", category: "Transform",
        summary: "One group of two circles looping a square-path position animation (+ child wiggle)",
        width: 1000, height: 500
    ) { zr in
        // circle: shape {cx:0,cy:0,r:10}, NO style -> default closed-shape fill is black
        let c1 = styled(circle(0, 0, 10), fill: "#000")
        // circle2: shape {cx:10,cy:10,r:10}, style { fill:'red' }
        let c2 = styled(circle(10, 10, 10), fill: "red")

        // group: position [100,100] -> x:100, y:100
        let group = Group()
        group.x = 100; group.y = 100
        group.add(c1)
        group.add(c2)
        zr.add(group)

        // group.animate('', true).when(...).start() — square path, looping forever
        group.animate("", true)
            .when(1000, ["x": 200.0, "y": 0.0])
            .when(2000, ["x": 200.0, "y": 200.0])
            .when(3000, ["x": 0.0, "y": 200.0])
            .when(4000, ["x": 100.0, "y": 100.0])
            .start()

        // circle.animate('', true).when(...).start() — horizontal wiggle, looping forever
        c1.animate("", true)
            .when(100, ["x": 20.0, "y": 0.0])
            .when(200, ["x": 0.0, "y": 0.0])
            .when(300, ["x": -20.0, "y": 0.0])
            .when(400, ["x": 0.0, "y": 0.0])
            .start()

        // zr.configLayer(0, { motionBlur:true, lastFrameAlpha:0.99 }) — fading trails behind the loop.
        zr.configLayer(0, LayerConfig(motionBlur: true, lastFrameAlpha: 0.99))
    }
}
