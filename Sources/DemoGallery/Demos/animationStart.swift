import ZRenderKit
import Foundation
// Migrated from zrender test/animationStart.html
extension DemoRegistry {
    static let demo_animationStart: Demo = Demo(
        name: "animationStart", category: "Animation",
        summary: "Ring of red dots flung outward with an elasticOut position tween"
    ) { zr in
        // animationStart.html scatters `count` tiny circles — shape {cx:0, cy:0, r:3},
        // style {fill:'red', opacity:0.2} — whose ELEMENT position is a point on a ring band
        // of width 60 around the canvas center. On mousemove it runs update(point): for every
        // dot it computes
        //     dist   = |point - dot.position|
        //     ratio  = (baseRadius + rand*60) / dist
        //     target = point + (dot.position - point) * ratio
        // then fires el.stopAnimation().animate('').when(3000,{position:target}).start('elasticOut').
        // That elasticOut fling IS the demo. A static gallery has no mouse, so we drive the SAME
        // update() math once against a fixed deterministic point P (the ring center) — reproducing
        // the signature motion. The position track is animated by carrying the ring position as the
        // element's x/y (shape stays centred on the origin), so x/y are what tweens — mirroring the
        // html's `position` array.
        //
        // DEVIATIONS (the only allowed ones): Math.random()→deterministic per-dot stand-in (varied
        // by index); center [400,300]→(340,100), baseRadius 180→50, band 60→~35 (native canvas size);
        // the unused red→black LinearGradient (dead code) and the per-dot onclick:alert(i) debug
        // handler are dropped.
        let center = (x: 340.0, y: 100.0)
        let baseRadius = 50.0
        let rings = 6                  // sub-rings across the band
        let perRing = 60               // dots per sub-ring
        let step = 7.0                 // radial gap between sub-rings (band ≈ 35 wide)

        // update(point) is driven against a fixed point P = ring center (the mousemove stand-in).
        let P = (x: center.x, y: center.y)

        for ring in 0..<rings {
            let radius = baseRadius + Double(ring) * step
            // stagger each sub-ring's angular phase so dots don't line up radially
            let phase = Double(ring) * (2 * π / Double(perRing)) * 0.5
            for j in 0..<perRing {
                let theta = 2 * π * Double(j) / Double(perRing) + phase
                let px = center.x + radius * cos(theta)
                let py = center.y + radius * sin(theta)

                // Build: shape centred on the origin (cx=cy=0, r=3); the ring position is carried
                // as the element's x/y so the elasticOut tween animates x/y (the `position` track).
                let dot = styled(circle(0, 0, 3), fill: "#ff0000", opacity: 0.2)
                dot.x = px; dot.y = py
                zr.add(dot)

                // update(P) — faithful to the html's per-dot math.
                let dx = P.x - px, dy = P.y - py
                let dist = (dx * dx + dy * dy).squareRoot()
                if dist < 0.1 { continue }                            // html's early-out guard
                // deterministic stand-in for `baseRadius + Math.random() * 60`, varied per dot
                let randTerm = Double(((ring * perRing + j) * 37) % 60)
                let ratio = (baseRadius + randTerm) / dist
                let tx = P.x + (px - P.x) * ratio
                let ty = P.y + (py - P.y) * ratio

                // el.stopAnimation().animate('').when(3000,{position:[tx,ty]}).start('elasticOut')
                dot.animate("")
                    .when(3000, ["x": tx, "y": ty])
                    .start(.named("elasticOut"))
            }
        }
    }
}
