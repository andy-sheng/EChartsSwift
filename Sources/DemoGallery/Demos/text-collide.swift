import ZRenderKit
// Migrated from zrender test/text-collide.html
//
// Upstream scatters thousands of `new zrender.Text({ text:'AAAAAAA-'+i, x,y,rotation })`
// labels, then `calculateCollide()` walks them in order, keeping a label only if its
// bounding rect does NOT intersect any already-displayed label (overlapMargin 0) and
// `hide()`s the rest. We mirror that 1:1 for a deterministic, axis-aligned field:
// place a dense set of labels with a seeded LCG (no Date/random), run the SAME
// fast-rejection AABB test, then render ONLY the survivors — the overlapped labels are
// dropped, exactly like upstream's `text.hide()` (which sets `ignore`, so they never paint).
// Every Text uses ZRText's default black fill ('#000'), since upstream sets only
// style.text + style.fontSize (no per-label color).
//
// PORT NOTE: the `rotate` branch (OrientedBoundingRect collision) is omitted; we render
// the axis-aligned case (config.rotate = false), which keeps placement deterministic.
extension DemoRegistry {
    static let demo_text_collide: Demo = Demo(
        name: "text-collide", category: "Text",
        summary: "Label collision: overlapping labels hidden (not drawn), survivors kept"
    ) { zr in
        // deterministic pseudo-random spread (no Date/random) — a simple LCG.
        var seed = 1234567
        func rnd() -> Double {
            seed = (seed &* 1103515245 &+ 12345) & 0x7fffffff
            return Double(seed) / Double(0x7fffffff)
        }

        struct Lbl { let i: Int; let str: String; let x: Double; let y: Double
                     let fs: Double; let w: Double; let h: Double }

        // 1) generate the candidate labels.
        let count = 64
        var labels: [Lbl] = []
        for i in 0..<count {
            let fs = 13.0 + (rnd() * 7).rounded()          // 13…20
            let str = "AAAAAAA-\(i)"
            let w = Double(str.count) * fs * 0.6           // approx measured text width
            let h = fs * 1.2
            let x = 8 + rnd() * max(0, 652 - w)
            let y = 8 + rnd() * max(0, 176 - h)
            labels.append(Lbl(i: i, str: str, x: x, y: y, fs: fs, w: w, h: h))
        }

        // 2) collision pass — same fast-rejection as upstream calculateCollide (margin 0).
        func intersects(_ a: Lbl, _ b: Lbl) -> Bool {
            return !(a.x + a.w <= b.x || b.x + b.w <= a.x
                  || a.y + a.h <= b.y || b.y + b.h <= a.y)
        }
        var displayed: [Lbl] = []
        var results: [(Lbl, Bool)] = []
        for lbl in labels {
            var overlapped = false
            for d in displayed where intersects(lbl, d) { overlapped = true; break }
            results.append((lbl, !overlapped))
            if !overlapped { displayed.append(lbl) }       // showText → keep for next tests
        }

        // 3) render ONLY the survivors. Upstream `hideText` calls `text.hide()` (sets `ignore`),
        //    so the overlapped labels are never painted — we simply skip them. Each kept Text uses
        //    ZRText's default black fill ('#000') to match upstream (which sets no per-label color).
        for (l, kept) in results where kept {
            zr.add(text(l.str, l.x, l.y, "#000", size: l.fs, align: .left))
        }
    }
}
