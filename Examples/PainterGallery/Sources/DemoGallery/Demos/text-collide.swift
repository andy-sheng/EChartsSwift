import ZRenderKit
// Faithful port of zrender test/text-collide.html
//
// Upstream scatters thousands of `new zrender.Text({ text:'AAAAAAA-'+i, fontSize, x, y })` over the
// canvas, adds them ALL to zr, then `calculateCollide()` walks them in order: it reads each label's
// `getComputedTransform()` + `getBoundingRect()`, builds the global rect, and keeps the label only
// if it doesn't intersect any already-displayed label (within `overlapMargin`) — `hide()`ing the
// rest (which sets `ignore`, so they aren't painted). A dat.GUI toggles hideOverlap / overlapMargin.
//
// This now mirrors that 1:1 for the axis-aligned case: real ZRText labels added to zr, real
// getBoundingRect-based collision, real `el.hide()` for the losers. The dat.GUI maps to the native
// control panel (hideOverlap + overlapMargin). Deterministic LCG positions (no Date/random).
//
// the `rotate` branch (random rotation → OrientedBoundingRect collision) is omitted; this
// renders config.rotate=false (axis-aligned), keeping placement deterministic.

private func textCollideLabels(_ zr: ZRender) -> [ZRText] {
    var seed = 20240131
    func rnd() -> Double {
        seed = (seed &* 1103515245 &+ 12345) & 0x7fffffff
        return Double(seed) / Double(0x7fffffff)
    }
    let w = zr.getWidth() ?? 1000, h = zr.getHeight() ?? 600
    var labels: [ZRText] = []
    for i in 0..<400 {
        // style: { text:'AAAAAAA-'+i, fontSize: round(random()*10)+15 }; x,y random over the canvas.
        let fs = (rnd() * 10).rounded() + 15        // 15…25
        let t = text("AAAAAAA-\(i)", rnd() * w, rnd() * h, "#000", size: fs, align: .left)
        zr.add(t)
        labels.append(t)
    }
    return labels
}

/// calculateCollide: keep a label only if its global rect doesn't intersect an already-kept one
/// (expanded by `overlapMargin`); `hide()` the overlapped ones (sets ignore → not painted).
private func textCollideRun(_ labels: [ZRText], _ hideOverlap: Bool, _ overlapMargin: Double) {
    for el in labels { el.show() }
    if !hideOverlap { return }

    func overlaps(_ a: BoundingRect, _ b: BoundingRect, _ m: Double) -> Bool {
        return !(a.x + a.width + m <= b.x || b.x + b.width + m <= a.x
              || a.y + a.height + m <= b.y || b.y + b.height + m <= a.y)
    }

    var displayed: [BoundingRect] = []
    for el in labels {
        guard let local = el.getBoundingRect() else { continue }
        let global = local.clone()
        if let tf = el.getComputedTransform() { global.applyTransform(tf) }
        var overlapped = false
        for d in displayed where overlaps(global, d, overlapMargin) { overlapped = true; break }
        if overlapped { el.hide() } else { displayed.append(global) }
    }
}

extension DemoRegistry {
    static let demo_text_collide: Demo = {
        var d = Demo(
            name: "text-collide", category: "Text",
            summary: "Label collision: overlapping labels hidden via getBoundingRect (survivors kept)",
            width: 1000, height: 600
        ) { zr in
            let labels = textCollideLabels(zr)
            textCollideRun(labels, true, 0)         // hideOverlap default on, overlapMargin 0
        }

        // dat.GUI → native control panel (hideOverlap toggle + overlapMargin slider).
        d.controls = { zr in
            let labels = textCollideLabels(zr)
            var hideOverlap = true
            var margin = 0.0
            textCollideRun(labels, hideOverlap, margin)
            return [
                DemoControl(label: "hideOverlap", kind: .toggle, value: 1) { on in
                    hideOverlap = on != 0
                    textCollideRun(labels, hideOverlap, margin)
                    zr.refresh()
                },
                DemoControl(label: "overlapMargin", kind: .slider(min: 0, max: 100), value: 0) { v in
                    margin = v
                    textCollideRun(labels, hideOverlap, margin)
                    zr.refresh()
                },
            ]
        }
        return d
    }()
}
