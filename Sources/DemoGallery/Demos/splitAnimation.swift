import ZRenderKit
// Faithful port of zrender test/splitAnimation.html (the html's native coords, drawn on the default
// 1200x600 surface; the three sub-demos sit at element x-offsets 0 / 300 / 600 — no rescale needed).
//
// Each sub-demo morphs ONE source shape <-> MANY circles forever, exactly like the html's
// morphBetween(one, many):
//   zr.add(one); then separateMorph(one, circles) and animateFrom each circle from its source
//   subpath's style; on done combineMorph(circles, one) + animateFrom; ping-pong via the morph's
//   done callback (the html's setTimeout(100)/setTimeout(1200) scheduling is a harness detail).
// zrender.color.random() is replaced by a deterministic palette (varied by index) per CONVENTIONS.
//   1. Simple one->many                : a single red Rect.
//   2. Batch->many (same path count)   : a CompoundPath of a 5x5 grid of 30x30 rects.
//   3. Batch->many (diff path count)   : a CompoundPath of 4 nested-size rects.
extension DemoRegistry {
    static let demo_splitAnimation: Demo = Demo(
        name: "splitAnimation", category: "Animation",
        summary: "Split morph: rect / rect-grid / nested rects <-> 5x5 circle grid (separate/combineMorph)"
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

        // The aligned call is the html's morphBetween(one, many): ping-pong forever between the source
        // and a 5x5 circle grid via separateMorph(one, many)/combineMorph(many, one), each followed by
        // animateFrom on the sub-paths' styles.
        // DEFERRED: ZRenderKit's separateMorph/combineMorph (Tool/dividePath.swift `split` →
        // defaultDividePath) currently CRASHES (bad pointer dereference) when run, so the morph loop is
        // omitted and the 3 STATIC source shapes are shown. `makeCircles` (the morph target) is kept for
        // provenance. See DEMO_PARITY_GAPS.md (framework gap).
        func morphBetween(_ one: Path, _ many: [Path]) {
            _ = many               // morph target — unused while the split morph is deferred
            zr.add(one)
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
