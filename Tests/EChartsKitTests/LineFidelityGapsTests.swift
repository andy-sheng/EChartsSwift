// Regression coverage for the five LineView fidelity gaps closed against upstream
// echarts/src/chart/line/LineView.ts:
//   L1 getVisualGradient + clipColorStops — a visualMap colours the LINE (stroke) and AREA (fill)
//      by region via a LinearGradient along the axis (LineView.ts:268/837/869).
//   L3 lineAnimationDiff + the upstream element-reuse gate — a data-window change (dataZoom shape)
//      RESHAPES the reused polyline instead of rebuilding it and replaying the clip-reveal enter
//      animation (LineView.ts:707 gate / :1327 _doUpdateAnimation).
//   L5 createPolarClipPath — a polar line gets a Sector clip path (and therefore an enter animation)
//      instead of no clip at all (LineView.ts:575).
import XCTest
import ZRenderKit
@testable import EChartsKit

final class LineFidelityGapsTests: XCTestCase {
    override func setUp() { super.setUp(); ComponentModel.registerClass(LineSeriesModel.self) }

    private func firstECPolyline(_ ec: ECharts) -> ECPolyline? {
        var found: ECPolyline?
        _ = ec.getRoot().traverse { el in
            if found == nil, let p = el as? ECPolyline, p.name == "line" { found = p }
            return false
        }
        return found
    }

    private func firstECPolygon(_ ec: ECharts) -> ECPolygon? {
        var found: ECPolygon?
        _ = ec.getRoot().traverse { el in
            if found == nil, let p = el as? ECPolygon, p.name == "area" { found = p }
            return false
        }
        return found
    }

    // The Group carrying the line clipPath (the lineGroup), and that clip.
    private func firstClip(_ ec: ECharts) -> Path? {
        var found: Path?
        _ = ec.getRoot().traverse { el in
            if found == nil, let cp = el.getClipPath() { found = cp }
            return false
        }
        return found
    }

    // ── L1 ──────────────────────────────────────────────────────────────────────────────────────
    // A line under a piecewise visualMap ends up with a GRADIENT stroke, and — with areaStyle — a
    // gradient fill, whose stops carry the visualMap piece colours (not a flat colour).
    func test_L1_visualMap_gives_line_and_area_a_gradient_by_region() {
        let ec = ECharts(width: 400, height: 300)
        // Distinct per-region colours so we can prove the stops came from the pieces.
        let pieces: [[String: Any]] = [
            ["gte": 0.0, "lt": 15.0, "color": "#11ee22"],
            ["gte": 15.0, "lt": 30.0, "color": "#3344ff"],
            ["gte": 30.0, "color": "#ff2211"]
        ]
        ec.setOption([
            "grid": ["left": 50.0, "top": 20.0, "width": 300.0, "height": 200.0] as [String: Any],
            "xAxis": ["type": "category", "data": ["A", "B", "C", "D", "E"]] as [String: Any],
            "yAxis": ["type": "value"] as [String: Any],
            // dimension 1 == the y (value) dimension → gradient runs along the y axis.
            "visualMap": [
                "type": "piecewise", "show": false, "dimension": 1.0, "seriesIndex": 0.0, "pieces": pieces
            ] as [String: Any],
            "series": [["type": "line", "areaStyle": [:] as [String: Any],
                        "data": [5.0, 18.0, 27.0, 33.0, 40.0]] as [String: Any]]
        ])

        guard let line = firstECPolyline(ec) else { return XCTFail("no line polyline") }
        guard case let .linearGradient(grad)? = line.pathStyle?.stroke else {
            return XCTFail("L1: the visualMap must colour the LINE with a LinearGradient stroke, got \(String(describing: line.pathStyle?.stroke))")
        }
        // The gradient runs along y (coordDim 'y'): x==x2==0, y != y2.
        XCTAssertEqual(grad.x, 0); XCTAssertEqual(grad.x2, 0)
        XCTAssertNotEqual(grad.y, grad.y2, "the gradient spans the y axis")
        XCTAssertTrue(grad.global, "visualMap gradient is in global (pixel) coordinates")

        // Every piece colour appears among the gradient stops (rgba-normalised).
        let stopColors = Set(grad.colorStops.map { normHex($0.color) })
        for hex in ["#11ee22", "#3344ff", "#ff2211"] {
            XCTAssertTrue(stopColors.contains(normHex(hex)),
                          "L1: gradient stops must carry the visualMap piece colour \(hex); got \(stopColors)")
        }

        // With areaStyle, the AREA fill is the SAME kind of gradient (LineView.ts:869 `fill: visualColor`).
        guard let area = firstECPolygon(ec) else { return XCTFail("no area band") }
        guard case .linearGradient? = area.pathStyle?.fill else {
            return XCTFail("L1: the visualMap must colour the AREA with a LinearGradient fill, got \(String(describing: area.pathStyle?.fill))")
        }
    }

    // ── L3 ──────────────────────────────────────────────────────────────────────────────────────
    // A second setOption that NARROWS the visible data window (the dataZoom shape → fewer points)
    // RESHAPES the reused polyline; it does NOT rebuild it, and does NOT create a fresh collapsed
    // clip-reveal animator. (Old broken gate compared point counts and rebuilt → replayed the reveal.)
    func test_L3_data_window_change_reuses_polyline_without_clip_reveal_replay() {
        let ec = ECharts(width: 400, height: 300)
        ec.setOption([
            "animation": true,
            "grid": ["left": 50.0, "top": 20.0, "width": 300.0, "height": 200.0] as [String: Any],
            "xAxis": ["type": "category", "data": ["a", "b", "c", "d", "e", "f", "g", "h"]] as [String: Any],
            "yAxis": ["type": "value"] as [String: Any],
            "series": [["type": "line", "animation": true,
                        "data": [1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0]] as [String: Any]]
        ])
        guard let polyline0 = firstECPolyline(ec), let clip0 = firstClip(ec) else {
            return XCTFail("first render produced no polyline/clip")
        }
        // Let the first render's enter animation settle, then clear all animators.
        _ = ec.getRoot().traverse { el in _ = el.stopAnimation(nil); return false }

        // Narrow the window: FEWER points (as a dataZoom would present). Same coord type, same step.
        ec.setOption([
            "xAxis": ["type": "category", "data": ["c", "d", "e", "f"]] as [String: Any],
            "series": [["type": "line", "data": [3.0, 4.0, 5.0, 6.0]] as [String: Any]]
        ])

        let polyline1 = firstECPolyline(ec)
        let clip1 = firstClip(ec)
        XCTAssertTrue(polyline0 === polyline1,
                      "L3: a data-window (point-count) change must REUSE the polyline (upstream gate ignores point count)")
        XCTAssertTrue(clip0 === clip1,
                      "L3: the clip is reshaped in place, not rebuilt — a rebuild would mint a NEW clip and replay the reveal")
        // No clip-reveal: the reused clip is never collapsed back to width 0 (a reveal starts at 0).
        if let rect = clip1 as? Rect, let shape = rect.shape as? RectShape {
            XCTAssertGreaterThan(shape.width, 0.0, "L3: the reused clip stays at full size (no reveal collapse)")
        }
    }

    // ── L4 ──────────────────────────────────────────────────────────────────────────────────────
    // `endLabel.show: true` attaches a Text riding the end of the line (the series-name/value label),
    // via _initOrUpdateEndLabel (LineView.ts:1179). Previously LineView had no endLabel at all.
    func test_L4_endLabel_attaches_a_text_at_the_line_end() {
        let ec = ECharts(width: 400, height: 300)
        ec.setOption([
            "animation": false,
            "grid": ["left": 50.0, "top": 20.0, "right": 80.0, "height": 200.0] as [String: Any],
            "xAxis": ["type": "category", "data": ["A", "B", "C", "D"]] as [String: Any],
            "yAxis": ["type": "value"] as [String: Any],
            "series": [["type": "line", "name": "Series 1",
                        "endLabel": ["show": true, "formatter": "{a}"] as [String: Any],
                        "data": [10.0, 20.0, 15.0, 40.0]] as [String: Any]]
        ])
        guard let line = firstECPolyline(ec) else { return XCTFail("no line polyline") }
        guard let endLabel = line.getTextContent() else {
            return XCTFail("L4: endLabel.show:true must attach a Text content to the polyline")
        }
        XCTAssertFalse(endLabel.ignore, "the end label is shown (not ignored)")
        XCTAssertTrue(endLabel.ignoreClip, "the end label ignores the line clip (rides outside the grid)")
        // z2 200 — above the item symbols (LineView.ts:1199).
        XCTAssertEqual(endLabel.z2, 200, "end label sits above the data symbols")
    }

    // ── L5 ──────────────────────────────────────────────────────────────────────────────────────
    // A polar line series gets a Sector clip path (and hence an enter animation) — previously it had
    // no clip at all because createPolarClipPath was never called.
    func test_L5_polar_line_gets_a_sector_clip_and_enter_animation() {
        let ec = ECharts(width: 400, height: 300)
        ec.setOption([
            "animation": true,
            "polar": [:] as [String: Any],
            "angleAxis": ["type": "value", "startAngle": 0.0] as [String: Any],
            "radiusAxis": [:] as [String: Any],
            "series": [["type": "line", "coordinateSystem": "polar", "animation": true,
                        "data": [[1.0, 0.0], [2.0, 60.0], [3.0, 120.0], [4.0, 180.0], [5.0, 240.0]]] as [String: Any]]
        ])
        guard let clip = firstClip(ec) else {
            return XCTFail("L5: a polar line must get a clip path (createPolarClipPath)")
        }
        guard let sector = clip as? Sector else {
            return XCTFail("L5: a polar line's clip must be a Sector, got \(type(of: clip))")
        }
        // The enter animation grows the sector (radial base axis → endAngle animates, angular → r).
        XCTAssertGreaterThan(sector.animators.count, 0,
                             "L5: the polar clip Sector must schedule an enter animator")
        // And the line itself renders.
        XCTAssertNotNil(firstECPolyline(ec), "polar line renders a polyline")
    }
}

// Normalise a hex/rgb(a) colour string to a comparable `#rrggbb` (lowercase). Gradient stops may be
// stored as `rgba(...)` (after color.lerp) or the original `#rrggbb` — compare on the RGB triplet.
private func normHex(_ s: String) -> String {
    if s.hasPrefix("#") {
        var hex = String(s.dropFirst()).lowercased()
        if hex.count == 3 { hex = hex.map { "\($0)\($0)" }.joined() }
        if hex.count >= 6 { return "#" + String(hex.prefix(6)) }
        return s.lowercased()
    }
    // rgb(a)(r, g, b[, a])
    let nums = s.replacingOccurrences(of: "rgba(", with: "")
        .replacingOccurrences(of: "rgb(", with: "")
        .replacingOccurrences(of: ")", with: "")
        .split(separator: ",")
        .prefix(3)
        .compactMap { Int(Double($0.trimmingCharacters(in: .whitespaces)) ?? -1) }
    guard nums.count == 3 else { return s.lowercased() }
    return String(format: "#%02x%02x%02x", nums[0], nums[1], nums[2])
}
