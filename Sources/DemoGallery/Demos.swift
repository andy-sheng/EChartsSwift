// Demos.swift — shared support for the demo gallery.
//
// The migrated demos live one-per-file under Demos/<name>.swift, mirroring zrender's
// test/<name>.html 1:1 (see Registry.swift for the assembled index). This file holds only
// the shared scaffolding they all use:
//   - the `Demo` value type,
//   - the `DemoRegistry` namespace (+ byName),
//   - the tiny shape/style builders (circle/rect/sector/text/styled/gradFill, π).
//
// Depends ONLY on ZRenderKit's public API; touches no framework source.

import ZRenderKit

/// A single live control (the native analog of one `dat.GUI` row) some demos expose so the gallery
/// can drive the scene interactively — e.g. poly.html's `smooth` / `percent` / `animatePercent`.
public struct DemoControl {
    public enum Kind {
        case slider(min: Double, max: Double)   // continuous, like `gui.add(cfg, k, min, max)`
        case toggle                              // checkbox, like `gui.add(cfg, k)` on a bool
    }
    public let label: String
    public let kind: Kind
    public let value: Double                      // initial value (slider) / 0|1 (toggle)
    public let onChange: (Double) -> Void
    public init(label: String, kind: Kind, value: Double, onChange: @escaping (Double) -> Void) {
        self.label = label; self.kind = kind; self.value = value; self.onChange = onChange
    }
}

/// One migrated demo scene.
public struct Demo {
    public let name: String          // stable id (matches the upstream html basename)
    public let category: String      // sidebar grouping
    public let summary: String       // one-line description shown in the gallery
    public let width: Double          // upstream canvas size (the html's #main div) — coords are
    public let height: Double         // ported 1:1, so the render must use the SAME logical size.
    public let build: (ZRender) -> Void

    /// Optional: builds the scene AND returns its `dat.GUI`-equivalent controls (so the controls can
    /// capture the scene's element refs). When set, the gallery calls THIS instead of `build` and
    /// renders the returned controls as a floating panel; `build` remains for headless `--render`.
    public var controls: ((ZRender) -> [DemoControl])? = nil

    public init(name: String, category: String, summary: String,
                width: Double = 1200, height: Double = 600,
                build: @escaping (ZRender) -> Void) {
        self.name = name; self.category = category; self.summary = summary
        self.width = width; self.height = height; self.build = build
    }
}

// MARK: - tiny builders that mirror the HTML's `{ shape, style }` ergonomics

@discardableResult
func styled<P: Path>(_ el: P, fill: String? = nil, stroke: String? = nil,
                     lineWidth: Double = 1, opacity: Double? = nil,
                     dash: [Double]? = nil) -> P {
    var st = PathStyleProps()
    // `createStyle` injects a default black fill when none is given, so a stroke-only shape
    // must opt out explicitly with 'none' (the renderer maps 'none' → no paint).
    st.fill = .string(fill ?? "none")
    if let stroke = stroke { st.stroke = .string(stroke); st.lineWidth = lineWidth }
    if let opacity = opacity { st.opacity = opacity }
    if let dash = dash { st.lineDash = .values(dash) }
    el.useStyle(st)
    return el
}

func gradFill<P: Path>(_ el: P, _ g: ZRColor) -> P {
    var st = PathStyleProps(); st.fill = g; el.useStyle(st); return el
}

func circle(_ cx: Double, _ cy: Double, _ r: Double) -> Circle {
    var s = CircleShape(); s.cx = cx; s.cy = cy; s.r = r
    let e = Circle(); e.setShape(s); return e
}
func rect(_ x: Double, _ y: Double, _ w: Double, _ h: Double, r: Double = 0) -> Rect {
    var s = RectShape(); s.x = x; s.y = y; s.width = w; s.height = h
    if r > 0 { s.r = .number(r) }
    let e = Rect(); e.setShape(s); return e
}
func sector(_ cx: Double, _ cy: Double, _ r0: Double, _ r: Double,
            _ start: Double, _ end: Double) -> Sector {
    var s = SectorShape(); s.cx = cx; s.cy = cy; s.r0 = r0; s.r = r
    s.startAngle = start; s.endAngle = end
    let e = Sector(); e.setShape(s); return e
}
func text(_ str: String, _ x: Double, _ y: Double, _ fill: String,
          size: Double = 18, align: TextAlign = .left) -> ZRText {
    var st = TextStyleProps()
    st.text = str; st.x = x; st.y = y; st.fill = fill
    st.fontSize = .number(size); st.align = align
    let t = ZRText(); t.useStyle(st); return t   // upstream `ZRText` (class Text in TS)
}

let π = Double.pi

// MARK: - registry namespace

public enum DemoRegistry {
    /// All demos assembled in Registry.swift — one per upstream test/*.html.
    public static func byName(_ name: String) -> Demo? { everything.first { $0.name == name } }
}
