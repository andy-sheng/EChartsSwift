import XCTest
@testable import EChartsKit
@testable import ZRenderKit

// Regression: themeRiver had NO hover state — upstream ThemeRiverView wires every layer band with
// setStatesStylesFromModel + toggleHoverEmphasis (ThemeRiverView.ts:168-171), so hovering a band
// marks it a highDown dispatcher and (with no explicit emphasis.itemStyle) LIFTS the fill via the
// default state proxy.
final class ThemeRiverHoverTests: XCTestCase {
    private func fillString(_ el: Element?) -> String? {
        guard let p = el as? Path else { return nil }
        if case let .string(s)? = p.pathStyle?.fill { return s }
        return nil
    }

    func testThemeRiverHoverLiftsBandFillAndRestores() {
        let v = EChartsView(width: 520, height: 380)
        v.setOption([
            "animation": false,
            "singleAxis": ["type": "value", "left": "10%", "right": "10%",
                           "top": "10%", "bottom": "10%"] as [String: Any],
            "series": [["type": "themeRiver",
                        "data": [
                            [0.0, 10.0, "Alpha"], [1.0, 15.0, "Alpha"], [2.0, 12.0, "Alpha"],
                            [0.0,  8.0, "Beta"],  [1.0,  6.0, "Beta"],  [2.0, 11.0, "Beta"]
                        ]] as [String: Any]]
        ])
        _ = v.zr.storage.getDisplayList(true)

        var bands: [ThemeRiverBand] = []
        _ = v.ec.getRoot().traverse { el in
            if el.name == "item", let band = el as? ThemeRiverBand { bands.append(band) }
            return false
        }
        XCTAssertEqual(bands.count, 2, "one band per layer")
        guard let band = bands.first, let shape = band.shape as? ThemeRiverBandShape,
              shape.upperPoints.count > 1, shape.lowerPoints.count > 1 else {
            XCTFail("band must carry edge vertices"); return
        }

        // Pointer at the band interior: mid time-point, halfway between the edges (add the ancestor
        // group's translation — band coords are group-local).
        var groupX = 0.0, groupY = 0.0
        var node: Transformable? = band.parent
        while let n = node { groupX += n.x; groupY += n.y; node = n.parent }
        let px = shape.upperPoints[1].x + groupX
        let py = (shape.upperPoints[1].y + shape.lowerPoints[1].y) / 2 + groupY

        let normalFill = fillString(band)
        XCTAssertNotNil(normalFill, "band has a palette fill")

        v._injectPointerForTest(type: "mousemove", zrX: px, zrY: py)
        XCTAssertTrue(band.currentStates.contains("emphasis"),
                      "hovering a themeRiver band must enter emphasis (states=\(band.currentStates))")
        XCTAssertNotEqual(fillString(band), normalFill,
                          "default emphasis must LIFT the band fill — normal=\(normalFill ?? "nil") hover=\(fillString(band) ?? "nil")")

        v._injectPointerForTest(type: "mousemove", zrX: 2, zrY: 2)
        XCTAssertFalse(band.currentStates.contains("emphasis"), "mouseout leaves emphasis")
        XCTAssertEqual(fillString(band), normalFill, "fill restored after mouseout")
    }
}
