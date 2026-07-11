import XCTest
@testable import EChartsKit
@testable import ZRenderKit

// Regression: gauge had NO hover effect — upstream GaugeView wires setStatesStylesFromModel +
// toggleHoverEmphasis on the pointer and the progress arc (GaugeView.ts:527-574). PORT-NOTE: both
// are now wired (GaugeView.swift:600-618), so the elements ARE highDown dispatchers carrying
// emphasis state; this test guards that.
final class GaugeHoverTests: XCTestCase {
    private func hitPoint(_ el: Path) -> (Double, Double)? {
        guard let rect = el.getBoundingRect() else { return nil }
        for iy in 1..<10 {
            for ix in 1..<10 {
                let lx = rect.x + rect.width * Double(ix) / 10
                let ly = rect.y + rect.height * Double(iy) / 10
                let g = el.transformCoordToGlobal(lx, ly)
                if el.contain(g[0], g[1]) { return (g[0], g[1]) }
            }
        }
        return nil
    }

    private func fillString(_ el: Path?) -> String? {
        if case let .string(s)? = el?.pathStyle?.fill { return s }
        return nil
    }

    func testGaugePointerHoverLiftsAndRestores() {
        let v = EChartsView(width: 460, height: 380)
        v.setOption(["animation": false,
                     "series": [["type": "gauge", "min": 0, "max": 100,
                                 "progress": ["show": true] as [String: Any],
                                 "data": [["value": 55.0, "name": "SCORE"] as [String: Any]]]
                                as [String: Any]]])
        _ = v.zr.storage.getDisplayList(true)
        let data = v.ec.getModel()!.getSeriesByIndex(0)!.getData()
        guard let pointer = data.getItemGraphicEl(0) as? Path else {
            XCTFail("gauge must register the pointer as the item graphic el"); return
        }
        XCTAssertTrue(states.isHighDownDispatcher(pointer),
                      "gauge pointer must be a highDown dispatcher")

        guard let (px, py) = hitPoint(pointer) else {
            XCTFail("could not find a point inside the pointer"); return
        }
        let normalFill = fillString(pointer)
        v._injectPointerForTest(type: "mousemove", zrX: px, zrY: py)
        XCTAssertTrue(pointer.currentStates.contains("emphasis"),
                      "hovering the gauge pointer must enter emphasis (states=\(pointer.currentStates))")
        XCTAssertNotEqual(fillString(pointer), normalFill,
                          "default emphasis must LIFT the pointer fill — normal=\(normalFill ?? "nil")")

        v._injectPointerForTest(type: "mousemove", zrX: 2, zrY: 2)
        XCTAssertFalse(pointer.currentStates.contains("emphasis"), "mouseout restores")
        XCTAssertEqual(fillString(pointer), normalFill, "fill restored after mouseout")
    }
}
