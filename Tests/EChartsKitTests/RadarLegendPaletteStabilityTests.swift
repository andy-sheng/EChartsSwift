import XCTest
@testable import EChartsKit
@testable import ZRenderKit

// Regression: toggling a radar legend item must NOT shift the palette colors of the remaining
// items. Upstream dataColorPaletteTask iterates the RAW data and lets a filtered-out item still
// consume its palette slot (style.ts:207-222 — "make sure color from palette can be consistent
// when toggling legend"); the Swift port's `idx != nil` guard skipped the getColorFromPalette
// call for the filtered item, so every later item slid one palette slot down (B off → C took
// B's color).
final class RadarLegendPaletteStabilityTests: XCTestCase {
    private func option() -> [String: Any] {
        ["animation": false,
         "legend": ["top": 4.0] as [String: Any],
         "radar": ["indicator": [
             ["name": "S", "max": 100.0] as [String: Any],
             ["name": "T", "max": 100.0] as [String: Any],
             ["name": "U", "max": 100.0] as [String: Any]
         ]] as [String: Any],
         "series": [["type": "radar", "data": [
             ["value": [80.0, 70, 60], "name": "A"] as [String: Any],
             ["value": [60.0, 82, 74], "name": "B"] as [String: Any],
             ["value": [45.0, 50, 92], "name": "C"] as [String: Any]
         ]]] as [[String: Any]]]
    }

    private func colorOf(_ ec: ECharts, name: String) -> String? {
        guard let series = ec.getModel()?.getSeriesByIndex(0) else { return nil }
        let data = series.getData()
        for i in 0..<data.count() where data.getName(i) == name {
            let style = data.getItemVisual(i, "style") as? [String: Any]
            if let s = style?["fill"] as? String { return s }
            if case let .color(s)? = style?["fill"] as? EChartsKit.ZRColor { return s }
            if case let .string(s)? = style?["fill"] as? ZRenderKit.ZRColor { return s }
        }
        return nil
    }

    func testLegendToggleKeepsSiblingPaletteColor() {
        let ec = ECharts(width: 440, height: 360)
        ec.setOption(option())
        guard let cBefore = colorOf(ec, name: "C"), let bBefore = colorOf(ec, name: "B") else {
            XCTFail("radar items must carry palette colors"); return
        }
        XCTAssertNotEqual(cBefore, bBefore, "B and C start on distinct palette slots")

        // Legend click on "B" (hide it).
        var off = Payload(type: "legendToggleSelect"); off.other["name"] = "B"
        ec.dispatchAction(off)

        XCTAssertEqual(colorOf(ec, name: "C"), cBefore,
                       "hiding B must NOT shift C onto B's palette color (got \(String(describing: colorOf(ec, name: "C"))), want \(cBefore))")

        // Toggle B back on: everyone at their original color.
        var on = Payload(type: "legendToggleSelect"); on.other["name"] = "B"
        ec.dispatchAction(on)
        XCTAssertEqual(colorOf(ec, name: "B"), bBefore, "restored B keeps its original color")
        XCTAssertEqual(colorOf(ec, name: "C"), cBefore, "C keeps its color after restore")
    }
}
