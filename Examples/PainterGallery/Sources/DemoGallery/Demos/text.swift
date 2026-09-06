import ZRenderKit
// Faithful port of zrender test/text.html — a Text feature matrix on a 1200×2200 grid.
//
// Upstream draws, in order: a #ddd grid (vertical + horizontal Lines, silent), a dark '#333' Rect
// bar behind one label, then ~20 Text elements exercising every Text feature: CJK wrap, fill/stroke
// +lineWidth, rotation/scale/origin transforms, align/verticalAlign, text & box shadow, padding,
// background (color AND {image}), border (color/width/radius), and full rich text (named parts
// a–s, dot0–dot4). Most createText() targets are draggable:true. Two page buttons,
// showBoundingRect() / showBoundingRectBeforeAddingToZr(), traverse the texts, call
// getBoundingRect() and overlay a stroked Rect honoring each el's x/y/rotation/scale/origin — the
// second over a parallel list of Texts that were never added to zr. Those are exposed here as the
// two DemoControls (zrender.color.random() → a deterministic palette, an acceptable stand-in).
//
// NOTES (acceptable deviations): style `align:'middle'` (an invalid CanvasTextAlign, a no-op
// upstream) is omitted on the one text that used it; upstream's `boxShadow*` keys on the bordered
// label are not real Text props (ignored upstream) and are likewise omitted. Each createText() is
// described once as a `TextSpec`, instantiated both into zr (real) and a never-added list (for the
// second button), mirroring upstream's clone-and-push.

// MARK: - one createText() target, captured declaratively

private struct TextSpec {
    var x: Double = 0
    var y: Double = 0
    var rotation: Double = 0
    var scaleX: Double = 1
    var scaleY: Double = 1
    var originX: Double? = nil
    var originY: Double? = nil
    var draggable: Bool = false
    let style: (inout TextStyleProps) -> Void
}

private func textMakePart(_ configure: (inout TextStylePropsPart) -> Void) -> TextStylePropsPart {
    var p = TextStylePropsPart(); configure(&p); return p
}

private func textInstantiate(_ spec: TextSpec) -> ZRText {
    var st = TextStyleProps(); spec.style(&st)
    let t = ZRText(); t.useStyle(st)
    t.x = spec.x; t.y = spec.y
    t.rotation = spec.rotation
    t.scaleX = spec.scaleX; t.scaleY = spec.scaleY
    if let ox = spec.originX { t.originX = ox }
    if let oy = spec.originY { t.originY = oy }
    if spec.draggable { t.draggable = .true }
    return t
}

// MARK: - reused rich parts (shared by the big block + the two rotated blocks)

private func textPartJ() -> TextStylePropsPart {
    textMakePart { $0.font = "23px Arial"; $0.fill = "#922889"; $0.verticalAlign = .top; $0.lineHeight = 100 }
}
private func textPartL() -> TextStylePropsPart {
    textMakePart {
        $0.font = "18px Arial"; $0.fill = "#331199"
        $0.borderColor = "#11aa11"; $0.borderWidth = 2; $0.borderRadius = .number(4)
        $0.backgroundColor = .string("rgba(0,0,0,0.1)"); $0.padding = .array([10, 20])
    }
}
private func textPartM() -> TextStylePropsPart {
    textMakePart {
        $0.font = "9px Arial"; $0.fill = "#aabbcc"
        $0.backgroundColor = .string("#224433"); $0.borderRadius = .number(8)
        $0.padding = .array([10, 20, 30, 40]); $0.verticalAlign = .top
    }
}
private func textPartN() -> TextStylePropsPart {
    textMakePart { $0.align = .right; $0.verticalAlign = .bottom; $0.backgroundColor = .string("#6712ab"); $0.width = .number(100) }
}
private func textPartO() -> TextStylePropsPart {
    textMakePart { $0.align = .center; $0.width = .number(100); $0.backgroundColor = .string("#99aa44") }
}

/// The full `rich` dictionary (parts a–s) for the big block at (200, 300). 'a' is intentionally
/// undefined upstream (the `{a|…}` token falls back to the base style), so it is not in the map.
private func textRichBlock() -> [String: TextStylePropsPart] {
    var rich: [String: TextStylePropsPart] = [:]
    rich["b"] = textMakePart { $0.textShadowBlur = 3; $0.textShadowColor = "#555"; $0.textShadowOffsetX = 2; $0.textShadowOffsetY = 2 }
    rich["c"] = textMakePart { $0.font = "30px Microsoft YaHei"; $0.fill = "green" }
    rich["d"] = textMakePart { $0.font = "22px Arial"; $0.fill = "#871299"; $0.align = .right }
    rich["e"] = textMakePart { $0.font = "22px Arial"; $0.fill = "#367199"; $0.align = .center }
    rich["f"] = textMakePart {
        $0.font = "12px Arial"; $0.fill = "#941122"; $0.backgroundColor = .string("#eee")
        $0.padding = .array([0, 0, 0, 20]); $0.width = .number(180); $0.align = .center
    }
    rich["g"] = textMakePart { $0.font = "12px Arial"; $0.verticalAlign = .top }
    rich["h"] = textMakePart { $0.font = "34px Arial" }
    rich["i"] = textMakePart { $0.font = "18px Arial"; $0.verticalAlign = .bottom }
    rich["j"] = textPartJ()
    rich["k"] = textMakePart { $0.font = "14px Arial"; $0.fill = "#126354"; $0.verticalAlign = .bottom }
    rich["l"] = textPartL()
    rich["m"] = textPartM()
    rich["n"] = textPartN()
    rich["o"] = textPartO()
    rich["p"] = textMakePart { $0.backgroundColor = .image(.url("./data/hill-Qomolangma.png")); $0.width = .number(100) }
    rich["q"] = textMakePart { $0.backgroundColor = .image(.url("./data/hill-Kilimanjaro.png")); $0.width = .number(30); $0.height = 90 }
    rich["r"] = textMakePart { $0.backgroundColor = .image(.url("./data/hill-Kilimanjaro.png")); $0.width = .number(30); $0.height = 12; $0.verticalAlign = .bottom }
    rich["s"] = textMakePart { $0.backgroundColor = .image(.url("./data/hill-Qomolangma.png")) }
    return rich
}

/// genarateTooltipStyle('Some series', items, colorList) → {text, rich} for the tooltip-style label.
private func textTooltipStyle() -> (text: String, rich: [String: TextStylePropsPart]) {
    let items = ["C: 1223 km", "D: 12 km", "Q: 2323 km", "Z: 4.23 km", "A: 23 km"]
    let colorList = ["#c23531", "#2f4554", "#61a0a8", "#d48265", "#91c7ae"]
    var lines = ["Some series"]
    var rich: [String: TextStylePropsPart] = [:]
    for (i, item) in items.enumerated() {
        lines.append("{dot\(i)|} \(item)")
        rich["dot\(i)"] = textMakePart {       // getDotStyle(color)
            $0.width = .number(12); $0.height = 12; $0.borderRadius = .number(6)
            $0.backgroundColor = .string(colorList[i])
        }
    }
    return (lines.joined(separator: "\n"), rich)
}

// MARK: - the createText() list (each defined once; built into zr AND into a never-added list)

private func textSceneSpecs() -> [TextSpec] {
    var specs: [TextSpec] = []

    // 1. CJK wrap text (fill #c0f), draggable.
    specs.append(TextSpec(draggable: true) {
        $0.x = 0; $0.y = 0
        $0.text = "国国国国\n国国国国国\n国国国国国国"
        $0.width = 50; $0.height = 50; $0.fill = "#c0f"; $0.font = "18px Microsoft Yahei"
    })

    // 2. green fill / red stroke, lineWidth 10, draggable.
    specs.append(TextSpec(x: 100, y: 100, draggable: true) {
        $0.x = 0; $0.y = 0
        $0.text = "position\n[100, 100]\nlineWidth: 10"
        $0.width = 50; $0.height = 50; $0.fill = "green"; $0.stroke = "red"; $0.lineWidth = 10
        $0.font = "18px Microsoft Yahei"
    })

    // 3. rotation 2, scale 0.5, draggable.
    specs.append(TextSpec(x: 200, y: 100, rotation: 2, scaleX: 0.5, scaleY: 0.5, draggable: true) {
        $0.x = 0; $0.y = 0
        $0.text = "position\n[200, 100],\nrotation: 2\nscale: 0.5"
        $0.width = 50; $0.height = 50; $0.fill = "#c0f"; $0.font = "18px Microsoft Yahei"
    })

    // 4. rotation -1, origin [0,50], scale 0.5, verticalAlign bottom, draggable.
    //    (upstream also sets `align:'middle'`, an invalid CanvasTextAlign / no-op — omitted.)
    specs.append(TextSpec(x: 100, y: 200, rotation: -1, scaleX: 0.5, scaleY: 0.5,
                          originX: 0, originY: 50, draggable: true) {
        $0.x = 0; $0.y = 0
        $0.text = "position\n[100, 200],\nrotation: -1\nscale: 0.5\nalign: middle\nverticalAlign: bottom\norigin:[0, 50]"
        $0.width = 50; $0.height = 50; $0.fill = "#c0f"; $0.font = "18px Microsoft Yahei"
        $0.verticalAlign = .bottom
    })

    // 5. white label over the dark bar (no offset).
    specs.append(TextSpec(x: 300, y: 100) {
        $0.x = 0; $0.y = 0; $0.text = "微软雅黑 no offset gg"; $0.fill = "#fff"; $0.font = "16px Microsoft Yahei"
    })

    // 6. align right / verticalAlign middle.
    specs.append(TextSpec(x: 400, y: 50) {
        $0.x = 0; $0.y = 0
        $0.text = "position: [400, 50]\nalign: right\nverticalAlign: middle"
        $0.fill = "#456"; $0.align = .right; $0.verticalAlign = .middle
    })

    // 7. align center / verticalAlign bottom.
    specs.append(TextSpec(x: 500, y: 50) {
        $0.x = 0; $0.y = 0
        $0.text = "position: [500, 50]\nalign: center\nverticalAlign: bottom"
        $0.fill = "#456"; $0.align = .center; $0.verticalAlign = .bottom
    })

    // 8. text shadow.
    specs.append(TextSpec(x: 600, y: 0) {
        $0.x = 0; $0.y = 0; $0.text = "阴影阴影\nshadow"; $0.fill = "#456"; $0.font = "18px Arial"
        $0.textShadowBlur = 3; $0.textShadowColor = "#893e95"; $0.textShadowOffsetX = 5; $0.textShadowOffsetY = 10
    })

    // 9. text background + padding 10, with text shadow.
    specs.append(TextSpec(x: 700, y: 0) {
        $0.x = 0; $0.y = 0
        $0.text = "有文字背景没有框背景和 padding: 10 \nshadow"
        $0.fill = "#ffe"; $0.font = "18px Arial"; $0.padding = .number(10)
        $0.backgroundColor = .string("rgba(124, 0, 123, 0.4)")
        $0.textShadowBlur = 3; $0.textShadowColor = "#893e95"; $0.textShadowOffsetX = 5; $0.textShadowOffsetY = 10
    })

    // 10. box background + border (width/radius) + padding [10,20,30,40], rotation -PI/16.
    //     (upstream's boxShadow* keys are not real Text props / no-op upstream — omitted.)
    specs.append(TextSpec(x: 600, y: 100, rotation: -π / 16) {
        $0.x = 0; $0.y = 0
        $0.text = [
            "有文字背景也有框背景",
            "borderWidth: 2 和 borderRadius: 5",
            "padding: [10, 20, 30, 40]",
            "rotation: -Math.PI / 16",
        ].joined(separator: "\n")
        $0.fill = "#ffe"; $0.font = "18px Arial"
        $0.padding = .array([10, 20, 30, 40]); $0.backgroundColor = .string("rgba(124, 0, 123, 0.4)")
        $0.borderColor = "#112233"; $0.borderWidth = 2; $0.borderRadius = .number(5)
        $0.textShadowBlur = 2; $0.textShadowColor = "#893e95"; $0.textShadowOffsetX = 2; $0.textShadowOffsetY = 4
    })

    // 11. empty text but has background (padding [10,20,30,40]).
    specs.append(TextSpec(x: 100, y: 300) {
        $0.text = ""; $0.x = 0; $0.y = 0
        $0.padding = .array([10, 20, 30, 40]); $0.backgroundColor = .string("rgba(124, 0, 123, 0.4)")
    })

    // 12. the big rich block (parts a–s), draggable.
    specs.append(TextSpec(draggable: true) {
        $0.x = 200; $0.y = 300
        $0.text = [
            "x: 200, y: 300{j|这行指定了 lineHeight 100px (vertical top)}所以比较宽裕{k|vertical bottom}",
            "{l|padding: [10, 20]}{m|padding: [10, 20, 30, 40], vertical: top}{o|width100}{n|width100}",
            "默认样式red 18px",
            "{a|富文本，样式a没定义}",
            "{b|默认字体大小但有阴影}默认样式18px{c|绿色 30px}{b|这句非常非常长最长。阴影样式。中间有\n换行}",
            "{c|align: left}紧跟左{e|这两块}{f|在剩余区域居中}{d|align: right}",
            "这是指定宽默认取lineHeight的图片{p|} 这是指定高宽的图片{q|}{r|}",
            "这个自动获取长宽比的图片{s|}只高度指定",
            "{g|verticalAlign: top}{h|最大文字}{i|verticalAlign: bottom}",
        ].joined(separator: "\n")
        $0.fill = "red"; $0.font = "18px Arial"; $0.rich = textRichBlock()
    })

    // 13. rich block, rotation -0.1, whole-block align center / verticalAlign middle, draggable.
    specs.append(TextSpec(x: 500, y: 900, rotation: -0.1, draggable: true) {
        $0.text = [
            "position: [500, 900]{j|rotation: -0.1}",
            "{l|且有 padding: [20, 30, 40, 50]}{m|padding, vertical: top}{o|width100}{n|width100}",
            "整体的 textAlign center, verticalAlign middle",
        ].joined(separator: "\n")
        $0.fill = "red"; $0.font = "18px Arial"; $0.borderRadius = .number(10)
        $0.backgroundColor = .string("rgba(0, 255, 0, 0.3)"); $0.borderColor = "#191933"; $0.borderWidth = 4
        $0.padding = .array([20, 30, 40, 50]); $0.verticalAlign = .middle; $0.align = .center
        $0.rich = ["j": textPartJ(), "l": textPartL(), "m": textPartM(), "n": textPartN(), "o": textPartO()]
    })

    // 14. rich block, rotation -0.1, whole-block align right / verticalAlign bottom + box shadow, draggable.
    specs.append(TextSpec(x: 500, y: 1300, rotation: -0.1, draggable: true) {
        $0.text = [
            "position: [500, 1300]{j|rotation: -0.1}",
            "整体的 textAlign right, verticalAlign bottom",
            "shadow",
        ].joined(separator: "\n")
        $0.fill = "red"; $0.font = "18px Arial"; $0.borderRadius = .number(10)
        $0.backgroundColor = .string("rgba(0, 255, 0, 0.3)"); $0.borderColor = "#191933"; $0.borderWidth = 4
        $0.shadowBlur = 5; $0.shadowColor = "#1099ee"; $0.shadowOffsetX = 5; $0.shadowOffsetY = 10
        $0.padding = .array([20, 30, 40, 50]); $0.verticalAlign = .bottom; $0.align = .right
        $0.rich = ["j": textPartJ()]
    })

    // 15. plain text, only padding 10.
    specs.append(TextSpec(x: 100, y: 1300) {
        $0.x = 0; $0.y = 0; $0.padding = .number(10)
        $0.text = "Plain text, only padding 10, no visible outer parts"
        $0.fill = "rgba(100, 50, 0, 1)"; $0.font = "12px Arial"
    })

    // 16. width 10 / height 10.
    specs.append(TextSpec(x: 100, y: 1400) {
        $0.x = 0; $0.y = 0; $0.width = 10; $0.height = 10
        $0.text = "Plain text, width 10, height: 10,\nno visible outer parts.\noverflow:undefined"
        $0.fill = "rgba(100, 50, 0, 1)"; $0.font = "12px Arial"
    })

    // 17. width 200 / height 100.
    specs.append(TextSpec(x: 300, y: 1400) {
        $0.x = 0; $0.y = 0; $0.width = 200; $0.height = 100
        $0.text = "Plain text, width 200, height: 100,\nno visible outer parts.\noverflow:undefined"
        $0.fill = "rgba(100, 50, 0, 1)"; $0.font = "12px Arial"
    })

    // 18. rich text, only padding 10 (part a).
    specs.append(TextSpec(x: 100, y: 1500) {
        $0.x = 0; $0.y = 0; $0.padding = .number(10)
        $0.text = "Rich text, {a|only padding 10}, no visible outer parts"
        $0.fill = "rgba(100, 50, 0, 1)"; $0.font = "12px Arial"
        $0.rich = ["a": textMakePart {
            $0.font = "12px Arial"; $0.backgroundColor = .string("rgba(100, 50, 0, 0.5)"); $0.padding = .array([15, 0, 0, 0])
        }]
    })

    // 19. tooltip-style label with colored dots, rotation -0.1, draggable.
    let tooltip = textTooltipStyle()
    specs.append(TextSpec(x: 800, y: 1100, rotation: -0.1, draggable: true) {
        $0.text = tooltip.text; $0.fill = "#333"; $0.font = "18px Arial"
        $0.borderRadius = .number(10); $0.borderColor = "#191933"; $0.borderWidth = 2
        $0.padding = .array([20, 30, 40, 50]); $0.rich = tooltip.rich
    })

    return specs
}

// MARK: - scene assembly + the two boundingRect buttons

/// Build the grid, the dark bar and all texts. Returns the live (added) Text refs for the buttons.
@discardableResult
private func buildTextScene(_ zr: ZRender) -> [ZRText] {
    let zrWidth = 1200.0, zrHeight = 2200.0, unit = 100.0

    // Vertical + horizontal #ddd grid lines (silent), stepping by `unit`.
    var i = 0
    while Double(i) * unit < zrWidth {
        var ln = LineShape(); ln.x1 = Double(i) * unit; ln.y1 = 0; ln.x2 = Double(i) * unit; ln.y2 = zrHeight
        let e = Line(); e.setShape(ln); e.silent = true
        zr.add(styled(e, stroke: "#ddd"))
        i += 1
    }
    i = 0
    while Double(i) * unit < zrHeight {
        var ln = LineShape(); ln.x1 = 0; ln.y1 = Double(i) * unit; ln.x2 = zrWidth; ln.y2 = Double(i) * unit
        let e = Line(); e.setShape(ln); e.silent = true
        zr.add(styled(e, stroke: "#ddd"))
        i += 1
    }

    // Dark bar behind the '微软雅黑 no offset' label: element at (300,100), shape {0,0,200,16}.
    let bar = rect(0, 0, 200, 16); bar.x = 300; bar.y = 100
    zr.add(styled(bar, fill: "#333"))

    // The ~20 createText() targets.
    var texts: [ZRText] = []
    for spec in textSceneSpecs() {
        let t = textInstantiate(spec); zr.add(t); texts.append(t)
    }
    return texts
}

// zrender.color.random() → a fixed palette (deterministic stand-in, varied by index).
private let textBBoxPalette = [
    "#c23531", "#2f4554", "#61a0a8", "#d48265", "#91c7ae",
    "#749f83", "#ca8622", "#bda29a", "#6e7074", "#546570", "#c4ccd3",
]
private func textBBoxColor(_ i: Int) -> String { textBBoxPalette[i % textBBoxPalette.count] }

/// showBoundingRect: overlay a stroked Rect on each text's getBoundingRect(), honoring transforms.
private func addTextBoundingRects(_ zr: ZRender, _ texts: [ZRText]) {
    for (i, el) in texts.enumerated() {
        guard let r = el.getBoundingRect() else { continue }
        let box = rect(r.x, r.y, r.width, r.height)
        box.x = el.x; box.y = el.y
        box.rotation = el.rotation
        box.scaleX = el.scaleX; box.scaleY = el.scaleY
        box.originX = el.originX; box.originY = el.originY
        zr.add(styled(box, stroke: textBBoxColor(i), lineWidth: 1))   // fill:null
    }
}

extension DemoRegistry {
    static let demo_text: Demo = {
        var d = Demo(
            name: "text", category: "Text",
            summary: "Text feature matrix: wrap / stroke / transforms / shadow / padding / border / background image / rich text",
            width: 1200, height: 2200
        ) { zr in
            buildTextScene(zr)
        }

        // The two page buttons → DemoControls. The second runs over a parallel list of Texts that
        // were instantiated but never added to zr (mirrors upstream's textNeverAddToZrList).
        d.controls = { zr in
            let realTexts = buildTextScene(zr)
            let neverAdded = textSceneSpecs().map { textInstantiate($0) }   // never added to zr

            return [
                DemoControl(label: "Show boundingRect", kind: .toggle, value: 0) { on in
                    if on != 0 { addTextBoundingRects(zr, realTexts) }
                },
                DemoControl(label: "Show boundingRect before adding to ZR", kind: .toggle, value: 0) { on in
                    if on != 0 { addTextBoundingRects(zr, neverAdded) }
                },
            ]
        }
        return d
    }()
}
