import ZRenderKit
import Foundation
// Faithful port of zrender test/splitAnimation.html (the html's native coords, drawn on the default
// 1200x600 surface; the three sub-demos sit at element x-offsets 0 / 300 / 600 — no rescale needed).
//
// Each sub-demo morphs ONE source shape <-> MANY circles forever, exactly like the html's
// morphBetween(one, many): zr.add(one); then oneToMany → separateMorph(one, many) + animateFrom each
// circle from its source subpath's style; manyToOne → combineMorph(many, one) + animateFrom.
//
// SCHEDULING (the bit that has to match): the html drives the ping-pong with `setTimeout(next, 1200)`
// — a FIXED wall-clock schedule, fully decoupled from when the morph animation finishes. The direct
// analog here is `DispatchQueue.main.asyncAfter` (the gallery's live view pumps the main run loop +
// the zr animation clock). This matters: an earlier version fired the next phase off the morph's
// `done` callback, which (a) ran inside Animation.update() so the freshly-created combine clip got a
// stale start time and snapped to its end instantly (the combine never visibly morphed), and (b) let
// each of the three sub-demos drift out of phase (each keyed off its own first-circle's done). The
// setTimeout schedule keeps all three in lock-step and gives each morph a clean 1000ms window plus the
// html's ~200ms dwell at each extreme (1200ms cadence vs the 1000ms morph).
//
// zrender.color.random() is replaced by a deterministic palette (varied by index) per CONVENTIONS.
//   1. Simple one->many                : a single red Rect.
//   2. Batch->many (same path count)   : a CompoundPath of a 5x5 grid of 30x30 rects.
//   3. Batch->many (diff path count)   : a CompoundPath of 4 nested-size rects.
extension DemoRegistry {
    static let demo_splitAnimation: Demo = Demo(
        name: "splitAnimation", category: "Animation",
        summary: "Split morph: rect / rect-grid / nested rects <-> 5x5 circle grid (separate/combineMorph), looping"
    ) { zr in
        // Deterministic stand-in for zrender.color.random(), varied by index.
        let palette = ["#5470c6", "#91cc75", "#fac858", "#ee6666", "#73c0de",
                       "#3ba272", "#fc8452", "#9a60b4", "#ea7ccc", "#c0504d"]
        func paletteColor(_ i: Int) -> String { palette[i % palette.count] }

        // 25 circles (r=20, cx=i*60+50, cy=k*60+50, opacity 0.5) at element offset (ox, 0).
        func makeCircles(_ ox: Double) -> [Path] {
            var circles: [Path] = []
            var idx = 0
            for i in 0..<5 {
                for k in 0..<5 {
                    let c = styled(circle(Double(i) * 60 + 50, Double(k) * 60 + 50, 20),
                                   fill: paletteColor(idx), opacity: 0.5)
                    c.x = ox
                    circles.append(c)
                    idx += 1
                }
            }
            return circles
        }

        // morphBetween(one, many): the html's ping-pong, scheduled by setTimeout (→ asyncAfter).
        // const config = { duration: 1000, easing: 'cubicInOut' } — one shared base config (struct
        // copy semantics make passing it by value safe; morphPath never mutates the original).
        var config = ElementAnimateConfig(); config.duration = 1000; config.easing = .named("cubicInOut")

        func morphBetween(_ one: Path, _ many: [Path]) {
            zr.add(one)
            let pp = SplitPingPong()

            // animateIndividuals: each toIndividual.animateFrom({ style: fromIndividuals[idx].style }).
            func animateIndividuals(_ res: MorphResult) {
                for (idx, to) in res.toIndividuals.enumerated() where idx < res.fromIndividuals.count {
                    let fromStyle = splitStyleDict(res.fromIndividuals[idx])
                    if fromStyle.isEmpty { continue }
                    to.animateFrom(["style": fromStyle], config)
                }
            }

            // function oneToMany() { zr.remove(one); many.forEach(zr.add); separateMorph(one, many,
            //   config); animateIndividuals(result); setTimeout(manyToOne, 1200); }
            pp.oneToMany = { [weak zr] in
                guard let zr = zr, !zr.isDisposed else { pp.oneToMany = nil; pp.manyToOne = nil; return }
                zr.remove(one)
                for m in many { zr.add(m) }
                let res = separateMorph(one, many, SeparateConfig(base: config))
                animateIndividuals(res)
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { pp.manyToOne?() }
            }
            // function manyToOne() { zr.add(one); many.forEach(zr.remove); combineMorph(many, one,
            //   config); animateIndividuals(result); setTimeout(oneToMany, 1200); }
            pp.manyToOne = { [weak zr] in
                guard let zr = zr, !zr.isDisposed else { pp.oneToMany = nil; pp.manyToOne = nil; return }
                zr.add(one)
                for m in many { zr.remove(m) }
                let res = combineMorph(many, one, CombineConfig(base: config))
                animateIndividuals(res)
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { pp.oneToMany?() }
            }
            // setTimeout(oneToMany, 100)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { pp.oneToMany?() }
        }

        // 1. Simple one->many — a single red Rect (x50 y50 200x200, fill red 0.5).
        let rect1 = styled(rect(50, 50, 200, 200), fill: "red", opacity: 0.5)
        morphBetween(rect1, makeCircles(0))

        // 2. Batch->many (same path count) — CompoundPath of a 5x5 grid of 30x30 rects, group x:300.
        var paths2: [Path] = []
        for i in 0..<5 {
            for k in 0..<5 {
                paths2.append(rect(Double(i) * 40 + 50, Double(k) * 40 + 50, 30, 30))
            }
        }
        let comp2 = CompoundPath(); comp2.setShape(CompoundPathShape(paths: paths2))
        styled(comp2, fill: "red", opacity: 0.5)
        comp2.x = 300
        morphBetween(comp2, makeCircles(300))

        // 3. Batch->many (different path count) — CompoundPath of 4 nested-size rects, group x:600.
        var paths3: [Path] = []
        for i in 0..<4 {
            let size = 80 - Double(i) * 10                 // 80, 70, 60, 50
            paths3.append(rect(Double(i) * 100 + 50, 100, size, size))
        }
        let comp3 = CompoundPath(); comp3.setShape(CompoundPathShape(paths: paths3))
        styled(comp3, fill: "red", opacity: 0.5)
        comp3.x = 600
        morphBetween(comp3, makeCircles(600))
    }
}

/// Mutable box holding the two self-rescheduling phase closures (so each morph's `done` can re-fire
/// the other). `zr` is captured weakly inside; when the gallery tears down the live view the loop
/// simply stops firing.
private final class SplitPingPong {
    var oneToMany: (() -> Void)?
    var manyToOne: (() -> Void)?
}

/// The animatable style keys (fill / opacity) of a path as an animateFrom sub-bag. Fill is taken as a
/// raw color string (the color tween needs a String, not a ZRColor — same as the state demo).
private func splitStyleDict(_ p: Path) -> [String: Any] {
    var d: [String: Any] = [:]
    if case .some(.string(let s)) = p.pathStyle.fill { d["fill"] = s }
    if let op = p.pathStyle.opacity { d["opacity"] = op }
    return d
}
