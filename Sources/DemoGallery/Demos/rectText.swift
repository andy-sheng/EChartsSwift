import ZRenderKit
// Faithful port of zrender test/rectText.html (main1 grid; the html's #main1 is 1000x700)
//
// Upstream builds a grid of Rects, each with an ATTACHED Text via `setTextContent` +
// `textConfig: { position }`, over all 13 builtin positions (left/right/top/bottom/inside +
// the inside* variants), and a large control panel that tweaks textConfig.distance / rotation /
// position, padding, align, etc.
//
// This now renders the REAL attached-text path (previously faked with standalone ZRText): the host
// Rect positions its textContent by `textConfig.position` via the now-implemented
// `Element.updateInnerText` (contain/text `calculateTextPosition`), and inside/outside text color is
// auto-resolved (inside → white, outside → dark). The dat.GUI maps to the native control panel
// (textConfig.distance / textConfig.rotation / text padding) driving every cell's textContent.
extension DemoRegistry {
    static let demo_rectText: Demo = {
        var d = Demo(
            name: "rectText", category: "Text",
            summary: "Rect labels attached via textConfig.position (all 13 positions) + live distance/rotation/padding controls",
            width: 1000, height: 700
        ) { zr in
            _ = buildRectTextScene(zr)
        }

        d.controls = { zr in
            let cells = buildRectTextScene(zr)
            var distance = 5.0
            var rotation = 0.0
            var padding = 0.0

            // Re-apply the current control values to every cell's textConfig / text style.
            func apply() {
                for (host, pos) in cells {
                    var cfg = ElementTextConfig()
                    cfg.position = pos
                    cfg.distance = distance
                    if rotation != 0 { cfg.rotation = rotation }
                    host.setTextConfig(cfg)
                    if let label = host.getTextContent() {
                        var st = TextStyleProps()
                        st.text = pos + "中文"; st.fontSize = .number(14)
                        st.padding = .number(padding)
                        label.useStyle(st)
                        label.dirtyStyle()
                    }
                }
                zr.refresh()
            }

            return [
                // textConfig.distance (default 5).
                DemoControl(label: "distance", kind: .slider(min: -20, max: 20), value: 5) { v in
                    distance = v; apply()
                },
                // textConfig.rotation.
                DemoControl(label: "rotation", kind: .slider(min: -π, max: π), value: 0) { v in
                    rotation = v; apply()
                },
                // text.style.padding.
                DemoControl(label: "padding", kind: .slider(min: 0, max: 30), value: 0) { v in
                    padding = v; apply()
                },
            ]
        }
        return d
    }()
}

// zrender.color.random() stand-in — a fixed palette, varied per cell.
private let rectTextPalette = [
    "rgb(166,125,199)", "rgb(99,208,231)", "rgb(127,13,18)", "rgb(116,28,234)",
    "rgb(220,67,53)", "rgb(177,109,195)", "rgb(44,122,138)", "rgb(177,12,58)",
    "rgb(26,186,147)", "rgb(5,128,95)", "rgb(207,83,94)", "rgb(49,160,93)", "rgb(160,90,197)",
]

/// Build the 13-cell grid of Rects, each with an attached Text positioned by textConfig.position.
/// Returns (host Rect, position) pairs so the controls can re-drive every cell.
@discardableResult
private func buildRectTextScene(_ zr: ZRender) -> [(Rect, String)] {
    // The 13 builtin positions, in upstream's order.
    let posList = [
        "left", "right", "top", "bottom",
        "inside",
        "insideTop", "insideLeft", "insideRight", "insideBottom",
        "insideTopLeft", "insideTopRight", "insideBottomLeft", "insideBottomRight",
    ]

    var cells: [(Rect, String)] = []
    for (idx, pos) in posList.enumerated() {
        // shape {x:100,y:50,width:150,height:70}, element position [(idx%3)*220, 120*floor(idx/3)].
        let host = rect(100, 50, 150, 70)
        host.x = Double(idx % 3) * 220
        host.y = 120 * Double(idx / 3)
        styled(host, fill: rectTextPalette[idx % rectTextPalette.count])

        // textContent: a Text with no explicit fill — updateInnerText auto-resolves inside (white) /
        // outside (dark) color from the host.
        var ts = TextStyleProps()
        ts.text = pos + "中文"; ts.fontSize = .number(14)
        let label = ZRText(); label.useStyle(ts)
        host.setTextContent(label)

        var cfg = ElementTextConfig()
        cfg.position = pos          // textConfig: { position: textPos }
        host.setTextConfig(cfg)

        zr.add(host)
        cells.append((host, pos))
    }
    return cells
}
