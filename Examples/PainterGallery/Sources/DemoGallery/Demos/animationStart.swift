import ZRenderKit
import Foundation
// Migrated from zrender test/animationStart.html
extension DemoRegistry {
    static let demo_animationStart: Demo = {
        var d = Demo(
            name: "animationStart", category: "Animation",
            summary: "Ring of red dots; every mousemove flings them outward with an elasticOut tween",
            width: 800, height: 600
        ) { zr in
            // Headless / no-panel path: build the scene with the html defaults (count 5000).
            _ = AnimationStartScene(zr, count: 5000, throttleMs: 50)
        }

        // Faithful port of animationStart.html's control panel: `count` (5000) + `throttle-rate`
        // (50) inputs with an OK button. Here `count` rebuilds the scene live (the OK button's job)
        // and `throttle-rate` adjusts the mousemove throttle delay in place.
        d.controls = { zr in
            let scene = AnimationStartScene(zr, count: 5000, throttleMs: 50)
            return [
                // html `Circles:` input — default 5000, matching upstream.
                DemoControl(label: "count", kind: .slider(min: 50, max: 5000), value: 5000) { v in
                    scene.rebuild(count: Int(v))
                },
                // html `Throttle Rate:` input (default 50ms).
                DemoControl(label: "throttle", kind: .slider(min: 0, max: 200), value: 50) { v in
                    scene.throttleMs = v
                },
            ]
        }
        return d
    }()
}

/// The animationStart scene + its mousemove fling logic, factored out so the control panel can
/// rebuild it (count slider) and retune it (throttle slider) without re-registering the demo.
private final class AnimationStartScene {
    private let zr: ZRender
    private let viewW = 800.0, viewH = 600.0
    private let center: (x: Double, y: Double)
    private let baseRadius: Double
    private var els: [Circle] = []

    // Deterministic stand-in for Math.random() (a small LCG) — reproducible across runs.
    private var seed: UInt64 = 0x9E3779B97F4A7C15
    private func rnd() -> Double {
        seed = seed &* 6364136223846793005 &+ 1442695040888963407
        return Double(seed >> 11) / Double(1 << 53)     // [0, 1)
    }

    /// html `throttle-rate` (ms). Mutable so the control panel can retune it live.
    var throttleMs: Double
    private var lastExecMs = 0.0
    private var pending: DispatchWorkItem?
    private func nowMs() -> Double { Date().timeIntervalSince1970 * 1000 }

    init(_ zr: ZRender, count: Int, throttleMs: Double) {
        self.zr = zr
        self.center = (viewW / 2, viewH / 2)          // [400, 300]
        self.baseRadius = min(viewW, viewH) * 0.3      // 180
        self.throttleMs = throttleMs

        buildDots(count: count)

        // zr.on('mousemove', e => update([e.offsetX, e.offsetY]))
        zr.on("mousemove") { [weak self] _, args in
            guard let self = self, let ev = args.first as? ElementEvent else { return nil }
            self.scheduleUpdate(ev.offsetX, ev.offsetY)
            return nil
        }
    }

    /// Scatter `count` tiny red dots on the ring band (shape centred on origin; position is x/y).
    private func buildDots(count: Int) {
        for _ in 0..<count {
            let theta = rnd() * 2 * π
            let r = baseRadius + rnd() * 60
            let dot = styled(circle(0, 0, 3), fill: "#ff0000", opacity: 0.2)
            dot.x = center.x + r * cos(theta)
            dot.y = center.y + r * sin(theta)
            zr.add(dot)
            els.append(dot)
        }
    }

    /// OK-button behaviour: tear down the current dots and re-scatter `count` of them.
    func rebuild(count: Int) {
        pending?.cancel(); pending = nil
        for el in els { zr.remove(el) }
        els.removeAll(keepingCapacity: true)
        seed = 0x9E3779B97F4A7C15        // reset the LCG so the scatter is reproducible
        buildDots(count: count)
        zr.refresh()
    }

    // update(point) — the html's per-dot elasticOut fling, re-run on every (throttled) mousemove.
    private func update(_ px: Double, _ py: Double) {
        for el in els {
            let ex = el.x, ey = el.y
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

    // Faithful port of the html's leading-edge `throttle(update, throttleRate)`: exec immediately
    // if ≥throttleMs since the last exec, else schedule a single trailing exec for the remainder.
    private func scheduleUpdate(_ px: Double, _ py: Double) {
        let currCall = nowMs()
        let diff = currCall - lastExecMs - throttleMs
        pending?.cancel()
        let exec = { [weak self] in
            guard let self = self else { return }
            self.lastExecMs = self.nowMs()
            self.pending = nil
            self.update(px, py)
        }
        if diff >= 0 {
            exec()
        } else {
            let work = DispatchWorkItem(block: exec)
            pending = work
            DispatchQueue.main.asyncAfter(deadline: .now() + (-diff) / 1000, execute: work)
        }
    }
}
