import XCTest
@testable import EChartsKit
@testable import ZRenderKit

// Regression: markLine / markArea had NO hover effect — upstream wires emphasis on the marker
// elements (Line.ts:243-336 for the markLine group; MarkAreaView.ts:388-392 for the area polygon).
// PORT-NOTE: both are now wired (MarkLineView.swift:698 / MarkAreaView.swift:479-481) as highDown
// dispatchers carrying emphasis states; this test guards that.
final class MarkerHoverTests: XCTestCase {
    private func strokeString(_ el: Path?) -> String? {
        if case let .string(s)? = el?.pathStyle?.stroke { return s }
        return nil
    }
    private func fillString(_ el: Path?) -> String? {
        if case let .string(s)? = el?.pathStyle?.fill { return s }
        return nil
    }

    func testMarkLineHoverLiftsAndRestores() {
        let v = EChartsView(width: 480, height: 360)
        v.setOption(["animation": false,
                     "xAxis": ["type": "category", "data": ["a", "b", "c"]] as [String: Any],
                     "yAxis": ["type": "value"],
                     "series": [["type": "bar", "data": [10, 20, 30],
                                 "markLine": ["data": [["type": "average", "name": "avg"] as [String: Any]]]
                                     as [String: Any]] as [String: Any]]])
        _ = v.zr.storage.getDisplayList(true)

        var lineEl: Polyline?
        _ = v.ec.getRoot().traverse { el in
            if lineEl == nil, el.name == "line", let p = el as? Polyline { lineEl = p }
            return false
        }
        guard let line = lineEl, let shape = line.shape as? PolylineShape,
              let pts = shape.points, pts.count >= 2 else {
            XCTFail("markLine must render a polyline"); return
        }

        let normalStroke = strokeString(line)
        XCTAssertNotNil(normalStroke, "markLine polyline has a stroke")

        // Hover the segment midpoint (global coords — LineDraw group is untransformed).
        let mid = line.transformCoordToGlobal((pts[0].x + pts[1].x) / 2, (pts[0].y + pts[1].y) / 2)
        v._injectPointerForTest(type: "mousemove", zrX: mid[0], zrY: mid[1])

        XCTAssertTrue(line.currentStates.contains("emphasis"),
                      "hovering the markLine must enter emphasis (states=\(line.currentStates))")
        XCTAssertNotEqual(strokeString(line), normalStroke,
                          "default emphasis must LIFT the line stroke — normal=\(normalStroke ?? "nil")")

        v._injectPointerForTest(type: "mousemove", zrX: 2, zrY: 2)
        XCTAssertFalse(line.currentStates.contains("emphasis"), "mouseout restores")
        XCTAssertEqual(strokeString(line), normalStroke, "stroke restored after mouseout")
    }

    func testMarkAreaHoverLiftsAndRestores() {
        let v = EChartsView(width: 480, height: 360)
        v.setOption(["animation": false,
                     "xAxis": ["type": "category", "data": ["a", "b", "c"]] as [String: Any],
                     "yAxis": ["type": "value"],
                     "series": [["type": "bar", "data": [10, 20, 30],
                                 "markArea": ["data": [[["xAxis": "a"] as [String: Any],
                                                        ["xAxis": "b"] as [String: Any]]]]
                                     as [String: Any]] as [String: Any]]])
        _ = v.zr.storage.getDisplayList(true)

        var areaEl: ZRenderKit.Polygon?
        _ = v.ec.getRoot().traverse { el in
            if areaEl == nil, let p = el as? ZRenderKit.Polygon { areaEl = p }
            return false
        }
        guard let area = areaEl, let rect = area.getBoundingRect() else {
            XCTFail("markArea must render a polygon"); return
        }

        let normalFill = fillString(area)
        XCTAssertNotNil(normalFill, "markArea polygon has a fill")

        let c = area.transformCoordToGlobal(rect.x + rect.width / 2, rect.y + rect.height / 2)
        v._injectPointerForTest(type: "mousemove", zrX: c[0], zrY: c[1])

        XCTAssertTrue(area.currentStates.contains("emphasis"),
                      "hovering the markArea must enter emphasis (states=\(area.currentStates))")
        XCTAssertNotEqual(fillString(area), normalFill,
                          "default emphasis must LIFT the area fill — normal=\(normalFill ?? "nil")")

        v._injectPointerForTest(type: "mousemove", zrX: 2, zrY: 2)
        XCTAssertFalse(area.currentStates.contains("emphasis"), "mouseout restores")
        XCTAssertEqual(fillString(area), normalFill, "fill restored after mouseout")
    }
}
