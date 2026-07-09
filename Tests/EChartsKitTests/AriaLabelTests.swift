// Verifies the ported ARIA accessibility LABEL generator (Sources/EChartsKit/component/aria/
// ariaVisual.swift, upstream echarts/src/visual/aria.ts). Drives the full ECharts setOption/update
// cycle on real (SourceManager-backed) bar series and inspects `ec.getAriaLabel()` against the upstream
// locale-template composition (langEN aria.*):
//   general.withTitle  →  series.multiple.prefix + per-series withName  →  data.allData + data rows.
// Also covers the disabled paths (aria default-off; aria.enabled:false; aria.show:false via preprocessor).

import XCTest
import ZRenderKit
@testable import EChartsKit

final class AriaLabelTests: XCTestCase {

    // Other suites register empty-data `series.bar` doubles into the GLOBAL ComponentModel registry;
    // re-register the real model so this test (which uses the real data pipeline) is order-independent.
    override func setUp() { super.setUp(); ComponentModel.registerClass(BarSeriesModel.self) }

    private func baseOption(aria: Any?, title: String? = "Weekly Sales", singleSeries: Bool = false) -> [String: Any] {
        var series: [[String: Any]] = [
            ["type": "bar", "name": "Alpha", "data": [10.0, 20.0, 30.0, 40.0]]
        ]
        if !singleSeries {
            series.append(["type": "bar", "name": "Beta", "data": [5.0, 15.0, 25.0, 35.0]])
        }
        var opt: [String: Any] = [
            "grid": ["left": 50.0, "top": 20.0, "width": 300.0, "height": 200.0] as [String: Any],
            "xAxis": ["type": "category", "data": ["A", "B", "C", "D"]] as [String: Any],
            "yAxis": ["type": "value"] as [String: Any],
            "series": series
        ]
        if let title = title {
            opt["title"] = ["text": title] as [String: Any]
        }
        if let aria = aria {
            opt["aria"] = aria
        }
        return opt
    }

    // A titled multi-series chart produces the composed aria label (title + series names + data sample).
    func testTitledMultiSeriesProducesAriaLabel() {
        let ec = ECharts(width: 400, height: 300)
        ec.setOption(baseOption(aria: ["enabled": true] as [String: Any]))

        guard let label = ec.getAriaLabel() else {
            return XCTFail("aria.enabled:true should produce an aria label")
        }
        print("ARIA-LABEL: \(label)")

        // general.withTitle: 'This is a chart about "{title}"'
        XCTAssertTrue(label.contains("This is a chart about \"Weekly Sales\""), "title interpolation; got: \(label)")
        // series.multiple.prefix: '. It consists of {seriesCount} series count.'
        XCTAssertTrue(label.contains("It consists of 2 series count"), "multiple-series prefix; got: \(label)")
        // series.multiple.withName: ' The {seriesId} series is a {seriesType} representing {seriesName}.'
        XCTAssertTrue(label.contains("The 0 series is a Bar chart representing Alpha"), "series 0 name/type/id; got: \(label)")
        XCTAssertTrue(label.contains("The 1 series is a Bar chart representing Beta"), "series 1 name/type/id; got: \(label)")
        // data.allData prefix + a concrete data value sample.
        XCTAssertTrue(label.contains("The data is as follows:"), "data prefix; got: \(label)")
        XCTAssertTrue(label.contains("10"), "a data value sample; got: \(label)")
    }

    // A single-series chart uses the single-series templates (withName + withoutTitle when no title).
    func testSingleSeriesWithoutTitle() {
        let ec = ECharts(width: 400, height: 300)
        ec.setOption(baseOption(aria: ["enabled": true] as [String: Any], title: nil, singleSeries: true))

        guard let label = ec.getAriaLabel() else {
            return XCTFail("aria.enabled:true should produce an aria label")
        }
        print("ARIA-LABEL-SINGLE: \(label)")
        // general.withoutTitle
        XCTAssertTrue(label.hasPrefix("This is a chart"), "withoutTitle prefix; got: \(label)")
        XCTAssertFalse(label.contains("chart about"), "no title => withoutTitle; got: \(label)")
        // series.single.withName: ' with type {seriesType} named {seriesName}.'
        XCTAssertTrue(label.contains("with type Bar chart named Alpha"), "single-series withName; got: \(label)")
    }

    // aria is disabled by default (no aria option) => no label.
    func testNoAriaOptionYieldsNoLabel() {
        let ec = ECharts(width: 400, height: 300)
        ec.setOption(baseOption(aria: nil))
        XCTAssertNil(ec.getAriaLabel(), "aria is disabled by default; no label should be generated")
    }

    // aria.enabled:false => no label.
    func testAriaEnabledFalseYieldsNoLabel() {
        let ec = ECharts(width: 400, height: 300)
        ec.setOption(baseOption(aria: ["enabled": false] as [String: Any]))
        XCTAssertNil(ec.getAriaLabel(), "aria.enabled:false should produce no label")
    }

    // aria.show:false (deprecated) is migrated to aria.enabled:false by the preprocessor => no label.
    func testAriaShowFalseYieldsNoLabel() {
        let ec = ECharts(width: 400, height: 300)
        ec.setOption(baseOption(aria: ["show": false] as [String: Any]))
        XCTAssertNil(ec.getAriaLabel(), "aria.show:false (deprecated) should map to enabled:false => no label")
    }

    // aria.label.description overrides the generated description string.
    func testAriaDescriptionOverride() {
        let ec = ECharts(width: 400, height: 300)
        ec.setOption(baseOption(aria: [
            "enabled": true,
            "label": ["description": "Custom accessible summary"] as [String: Any]
        ] as [String: Any]))
        XCTAssertEqual(ec.getAriaLabel(), "Custom accessible summary", "explicit description should win")
    }
}
