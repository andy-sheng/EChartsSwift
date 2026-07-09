// LABEL RETROFIT TEST — proves BarView routes its data labels through the shared label core
// (`labelStyle.setLabelStyle`) instead of the old inline `renderCartesianBarLabel` ZRText.
//
// Canonical upstream behavior (BarView.ts `updateStyle`): the label is ATTACHED to the bar `Rect`
// `el` as its `textContent` (via `setTextContent` + `el.textConfig.position`), NOT added as a
// separate free ZRText in the group. After render, each bar element must therefore expose a
// `getTextContent()` whose `textStyle.text` is the datum's default label (its value) and an
// `el.textConfig.position` reflecting the label model position.

import XCTest
import ZRenderKit
@testable import EChartsKit

final class BarLabelStyleTests: XCTestCase {

    override func setUp() { super.setUp(); ComponentModel.registerClass(BarSeriesModel.self) }

    private func barChartOptionWithLabel() -> [String: Any] {
        return [
            "grid": ["left": 50.0, "top": 20.0, "width": 300.0, "height": 200.0] as [String: Any],
            "xAxis": ["type": "category", "data": ["A", "B", "C", "D"]] as [String: Any],
            "yAxis": ["type": "value"] as [String: Any],
            "series": [[
                "type": "bar",
                "data": [10.0, 20.0, 30.0, 40.0],
                "label": ["show": true, "position": "top"] as [String: Any]
            ] as [String: Any]]
        ]
    }

    private func collectBars(_ root: Group) -> [Rect] {
        var bars: [Rect] = []
        _ = root.traverse { el in
            if let rect = el as? Rect, rect.name == "item" { bars.append(rect) }
            return false
        }
        return bars
    }

    func testBarLabelIsAttachedAsTextContentOnBarRect() {
        let ec = ECharts(width: 400, height: 300)
        ec.setOption(barChartOptionWithLabel())

        let bars = collectBars(ec.getRoot())
        XCTAssertEqual(bars.count, 4, "a bar chart with 4 data points should emit 4 bar Rects")
        guard bars.count == 4 else { return }

        var texts: [String] = []
        for bar in bars {
            guard let label = bar.getTextContent() else {
                XCTFail("each bar Rect should carry the label as its textContent (setLabelStyle)"); continue
            }
            XCTAssertFalse(label.ignore, "label.show == true -> attached ZRText must not be ignored")
            guard let t = label.textStyle.text else {
                XCTFail("attached label should have resolved text"); continue
            }
            texts.append(t)

            guard let cfg = bar.textConfig else {
                XCTFail("bar el.textConfig should be set by setLabelStyle"); continue
            }
            XCTAssertEqual(cfg.position as? String, "top", "textConfig.position comes from the label model position")
        }

        // Default label is the datum value; each of the four values must appear exactly once.
        XCTAssertEqual(Set(texts), Set(["10", "20", "30", "40"]),
                       "each bar's default label is its value")
    }
}
