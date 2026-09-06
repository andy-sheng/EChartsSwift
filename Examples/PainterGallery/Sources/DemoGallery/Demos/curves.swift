import ZRenderKit
// Faithful port of zrender test/curves.html  (the html resizes #main to 1280x800)
//
// Upstream: N=10 shapes in a loop; ShapeClass = (i%5==0) ? Trochoid : Rose, each at a random
// position with random shape params, a random hex stroke (lineWidth 1), and a small rotation. Then
// EACH shape is animated forever: `animate(shape)` picks a random track (`type`) and re-arms itself
// from the animator's `done` callback — this port issues the SAME `animate(...).when(...).done(...)
// .start(...)` calls, looping endlessly, exactly like the html.
//
// DEVIATIONS (the only allowed ones): (1) Math.random() → a deterministic per-step stand-in with the
// same ranges/counts and the same Trochoid/Rose split; (2) the legacy `scale`/`position` ARRAY props
// are not ported, so type-0/1 animate the equivalent scaleX/scaleY and x/y keys; (3) easing is the
// html's fixed `'Linear'` (its table is hardcoded to index 0).
extension DemoRegistry {
    static let demo_curves: Demo = Demo(
        name: "curves", category: "Shapes",
        summary: "10 scattered Trochoid (i%5==0) / Rose curves, thin strokes, each animating forever",
        width: 1280, height: 800
    ) { zr in
        // deterministic stand-in for the html's `random(max,min)` = floor(rand*(max-min))%(max-min)+min
        func rnd(_ seed: Int, _ maxV: Double, _ minV: Double = 0) -> Double {
            let h = Double((seed &* 1103515245 &+ 12345) & 0x7fffffff) / Double(0x7fffffff) // [0,1)
            return (minV + h * (maxV - minV)).rounded(.down)
        }
        func color(_ seed: Int) -> String {
            String(format: "#%06x", (seed &* 2654435761) & 0xFFFFFF)   // stand-in for random hex
        }
        let w = 1280.0, h = 800.0

        // A running counter so each forever-loop step gets a fresh deterministic "random" (the html
        // calls Math.random() afresh every step).
        var rngState = 1
        func nextRnd(_ maxV: Double, _ minV: Double = 0) -> Double {
            rngState = (rngState &* 1103515245 &+ 12345) & 0x7fffffff
            return rnd(rngState, maxV, minV)
        }

        // function animate(shape) { ... move.done(() => animate(shape)).start('Linear') }
        // Implicitly-unwrapped closure so it can re-arm itself from `done` (an endless loop, matching
        // the html). The self-reference forms a cycle that lives for the demo's lifetime — acceptable
        // for a gallery scene; the loop stops when the ZRenderView (and its animation clock) is torn
        // down on demo switch.
        var animate: ((Path, Bool) -> Void)!
        animate = { el, isRose in
            let time = nextRnd(1000, 100)
            // type = shape.type=='rose' ? random(6) : random(3)
            let type = Int(isRose ? nextRnd(6) : nextRnd(3))
            let move: Animator<Any>
            switch type {
            case 0:   // move.when(time, { scale: [random(3,1), random(3,1)] })
                move = el.animate("")
                _ = move.when(time, ["scaleX": nextRnd(3, 1), "scaleY": nextRnd(3, 1)])
            case 1:   // move.when(time, { position: [random(w), random(h)] })
                move = el.animate("")
                _ = move.when(time, ["x": nextRnd(w), "y": nextRnd(h)])
            case 2:   // move.when(time, { rotation: pi * 2 * random(10, 1) })
                move = el.animate("")
                _ = move.when(time, ["rotation": π * 2 * nextRnd(10, 1)])
            case 3:   // shape.animate('shape').when(time, { r: [random(100, 30)] })
                move = el.animate("shape")
                _ = move.when(time, ["r": [nextRnd(100, 30)]])
            case 4:   // shape.animate('shape').when(time, { k: random(10) })
                move = el.animate("shape")
                _ = move.when(time, ["k": nextRnd(10)])
            default:  // case 5: shape.animate('shape').when(time, { n: random(5) })
                move = el.animate("shape")
                _ = move.when(time, ["n": nextRnd(5)])
            }
            move.done { animate(el, isRose) }
            _ = move.start(.named("linear"))
        }

        for i in 0..<10 {
            let el: Path
            let isRose = (i % 5 != 0)
            if !isRose {
                // zrender.Trochoid — shape { cx:0, cy:0, r:random(50,20), r0:random(20,10),
                //   d:random(100), location:['in','out'][i%2] }
                var s = TrochoidShape()
                s.cx = 0; s.cy = 0
                s.r = rnd(i * 11 + 1, 50, 20)
                s.r0 = rnd(i * 13 + 2, 20, 10)
                s.d = rnd(i * 17 + 3, 100)
                s.location = (i % 2 == 0) ? "in" : "out"
                let e = Trochoid(); e.setShape(s); el = e
            } else {
                // zrender.Rose — shape { cx:0, cy:0, r:[random(100,30)], k:random(10), n:random(5) }
                var s = RoseShape()
                s.cx = 0; s.cy = 0
                s.r = [rnd(i * 19 + 4, 100, 30)]
                s.k = rnd(i * 23 + 5, 10)
                s.n = rnd(i * 29 + 6, 5)
                let e = Rose(); e.setShape(s); el = e
            }
            el.x = rnd(i * 31 + 7, w)                 // position: [random(w), random(h)]
            el.y = rnd(i * 37 + 8, h)
            el.rotation = π * 2 / rnd(i * 41 + 9, 360, 1)
            zr.add(styled(el, stroke: color(i + 1), lineWidth: 1))
            animate(el, isRose)                        // animate(shape) — forever
        }
    }
}
