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

    func testRadarSymbolNoneStillUsesRoundRectLegendIcon() {
        let ec = ECharts(width: 440, height: 360)
        ec.setOption([
            "legend": ["data": ["AQI"]] as [String: Any],
            "radar": ["indicator": [
                ["name": "S", "max": 100.0] as [String: Any],
                ["name": "T", "max": 100.0] as [String: Any],
                ["name": "U", "max": 100.0] as [String: Any]
            ]] as [String: Any],
            "series": [[
                "name": "AQI",
                "type": "radar",
                "symbol": "none",
                "data": [["name": "AQI", "value": [80.0, 70.0, 60.0]] as [String: Any]]
            ] as [String: Any]]
        ])

        var legendText: ZRText?
        _ = ec.getRoot().traverse { element in
            if let text = element as? ZRText, text.textStyle?.text == "AQI" {
                legendText = text
            }
            return false
        }
        guard let itemGroup = legendText?.parent as? Group,
              let legendPath = itemGroup.childAt(0) as? SymbolPath,
              let legendShape = legendPath.shape as? SymbolShape else {
            return XCTFail("radar legend must render a visible symbol path beside its text")
        }
        XCTAssertEqual(legendShape.symbolType, "roundRect")
        XCTAssertEqual(
            ec.getModel()?.getSeriesByIndex(0)?.getData().getVisual("legendIcon") as? String,
            "roundRect",
            "chart rendering must not erase the icon needed by later component-only legend updates"
        )
    }

    func testInitiallyFilteredRadarKeepsSymbolNoneLegendIcon() {
        let ec = ECharts(width: 440, height: 360)
        let radar = ["indicator": [
            ["name": "S", "max": 100.0] as [String: Any],
            ["name": "T", "max": 100.0] as [String: Any],
            ["name": "U", "max": 100.0] as [String: Any]
        ]] as [String: Any]
        func series(_ name: String, _ values: [Double]) -> [String: Any] {
            ["name": name, "type": "radar", "symbol": "none", "data": [values]]
        }
        ec.setOption([
            "legend": [
                "selectedMode": "single",
                "data": ["Active", "Initially filtered"]
            ] as [String: Any],
            "radar": radar,
            "series": [
                series("Active", [80, 70, 60]),
                series("Initially filtered", [60, 80, 70])
            ]
        ])

        func renderedLegendSymbol(_ name: String) -> String? {
            var legendText: ZRText?
            _ = ec.getRoot().traverse { element in
                if let text = element as? ZRText, text.textStyle?.text == name {
                    legendText = text
                }
                return false
            }
            guard let itemGroup = legendText?.parent as? Group,
                  let path = itemGroup.childAt(0) as? SymbolPath,
                  let shape = path.shape as? SymbolShape else { return nil }
            return shape.symbolType
        }

        XCTAssertEqual(renderedLegendSymbol("Active"), "roundRect")
        XCTAssertEqual(
            renderedLegendSymbol("Initially filtered"),
            "none",
            "a radar series filtered before its first chart visual pass must not gain an inactive swatch"
        )
        XCTAssertEqual(
            ec.getModel()?.getSeriesByIndex(0)?.getData().getVisual("legendIcon") as? String,
            "roundRect"
        )
        XCTAssertEqual(
            ec.getModel()?.getSeriesByIndex(1)?.getData().getVisual("legendIcon") as? String,
            "none"
        )
    }
}
