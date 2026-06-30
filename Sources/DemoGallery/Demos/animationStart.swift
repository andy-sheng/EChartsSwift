import ZRenderKit
import Foundation
// Migrated from zrender test/animationStart.html
extension DemoRegistry {
    static let demo_animationStart: Demo = Demo(
        name: "animationStart", category: "Animation",
        summary: "Ring of red dots; every mousemove flings them outward with an elasticOut tween",
        width: 800, height: 600
    ) { zr in
        // Faithful port of animationStart.html. The html scatters `count` tiny red circles
        // (shape {cx:0,cy:0,r:3}, style {fill:'red',opacity:0.2}) at RANDOM points on a ring band
        // around the canvas center, then on every `mousemove` runs update(point): for each dot
        //     dist   = |point - el.position|
        //     ratio  = (baseRadius + rand*60) / dist
        //     target = point + (el.position - point) * ratio
        // and `el.stopAnimation().animate('').when(3000,{position:target}).start('elasticOut')`.
        // That elasticOut fling on mouse MOVEMENT is the whole demo — the initial frame is just the
        // static scatter ring, exactly like the html before you move the mouse.
        //
        // position ↔ x/y: this port maps an element's `position` array onto its x/y, so the shape
        // stays centred on the origin (cx=cy=0) and the dot's *position* (x/y) is what tweens —
        // mirroring the html's `position` track. (Element.x/y are Optional, hence the `?? 0` reads.)
        //
        // Gallery input note: the macOS host feeds zr `mousemove` from pointer movement over the
        // view (bare hover via its tracking area, or a drag), so sweeping the cursor across the
        // dots flings them outward — the same gesture as the html.
        //
        // DEVIATIONS (documented): count 5000→500 (native CALayer budget; the per-dot call sequence
        // is byte-for-byte the same); Math.random()→a deterministic LCG (reproducible scatter +
        // per-mousemove jitter); the unused red→black LinearGradient (dead code in the html) and the
        // per-dot `onclick: alert(i)` debug handler are dropped.

        let viewW = 800.0, viewH = 600.0
        let center = (x: viewW / 2, y: viewH / 2)          // [400, 300]
        let baseRadius = min(viewW, viewH) * 0.3            // 180
        let count = 500                                     // html: 5000 (perf deviation)

        // Deterministic stand-in for Math.random() (a small LCG) — reproducible across runs.
        var seed: UInt64 = 0x9E3779B97F4A7C15
        func rnd() -> Double {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return Double(seed >> 11) / Double(1 << 53)     // [0, 1)
        }

        var els: [Circle] = []
        for _ in 0..<count {
            let theta = rnd() * 2 * π
            let r = baseRadius + rnd() * 60
            // shape centred on the origin (cx=cy=0, r=3); the ring point is the element position.
            let dot = styled(circle(0, 0, 3), fill: "#ff0000", opacity: 0.2)
            dot.x = center.x + r * cos(theta)
            dot.y = center.y + r * sin(theta)
            zr.add(dot)
            els.append(dot)
        }

        // update(point) — the html's per-dot elasticOut fling, re-run on every mousemove.
        func update(_ px: Double, _ py: Double) {
            for el in els {
                let ex = el.x ?? 0, ey = el.y ?? 0
                let dx = px - ex, dy = py - ey
                let dist = (dx * dx + dy * dy).squareRoot()
                if dist < 0.1 { return }                    // html early-out (returns from update)
                let ratio = (baseRadius + rnd() * 60) / dist
                let tx = px + (ex - px) * ratio
                let ty = py + (ey - py) * ratio
                // el.stopAnimation().animate('').when(3000, {position}).start('elasticOut')
                el.stopAnimation().animate("")
                    .when(3000, ["x": tx, "y": ty])
                    .start(.named("elasticOut"))
            }
        }

        // zr.on('mousemove', e => update([e.offsetX, e.offsetY]))
        zr.on("mousemove") { _, args in
            guard let ev = args.first as? ElementEvent else { return nil }
            update(ev.offsetX, ev.offsetY)
            return nil
        }
    }
}
