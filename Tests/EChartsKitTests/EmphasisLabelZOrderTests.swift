import XCTest
@testable import EChartsKit
@testable import ZRenderKit

// Regression: on hover-emphasis the host lifts its z2 by Z2_EMPHASIS_LIFT (10). The attached LABEL
// (textContent) must lift by the same amount, or the emphasized fill/area sorts ABOVE the label and
// occludes it (reported: a themeRiver band hiding its own "gamma" name on hover). The fix installs the
// default-state proxy on textContent + textGuide (upstream states.ts:350-353) so useState propagation
// gives the label its own emphasis default state, including the z2 lift. This is systemic — it covers
// every labeled element with hover-emphasis, not just themeRiver.
final class EmphasisLabelZOrderTests: XCTestCase {

    private func firstBandWithLabel(_ el: Element) -> Path? {
        if let p = el as? Path, p.getTextContent() != nil, p.pathStyle?.fill != nil { return p }
        if let g = el as? Group {
            for c in g.children() { if let hit = firstBandWithLabel(c) { return hit } }
        }
        return nil
    }

    func testThemeRiverLabelLiftsWithBandOnEmphasis() {
        let v = EChartsView(width: 500, height: 300)
        v.setOption([
            "singleAxis": ["type": "time"] as [String: Any],
            "series": [[
                "type": "themeRiver",
                "data": [
                    [1.0, 10.0, "alpha"], [2.0, 15.0, "alpha"],
                    [1.0, 12.0, "beta"], [2.0, 8.0, "beta"],
                    [1.0, 9.0, "gamma"], [2.0, 14.0, "gamma"]
                ]
            ] as [String: Any]]
        ])
        _ = v.zr.storage.getDisplayList(true)
        guard let band = firstBandWithLabel(v.ec.getRoot()), let label = band.getTextContent() else {
            return XCTFail("no themeRiver band with an attached label found")
        }
        XCTAssertEqual(band.z2, label.z2, "before hover, band and label share a z2 (label drawn just above)")

        // Assert the terminal state, not the first frame of the configured state transition.
        // With a working animationGet("z2"), z2 now interpolates from 0 to 10 instead of jumping.
        band.useState("emphasis", nil, true)
        _ = v.zr.storage.getDisplayList(true)

        XCTAssertEqual(band.z2, 10.0, accuracy: 1e-9, "emphasis lifts the band z2 by Z2_EMPHASIS_LIFT")
        XCTAssertEqual(label.z2, band.z2, accuracy: 1e-9,
                       "the label MUST lift with the band on emphasis, else the band occludes it — label z2=\(label.z2)")
    }

    func testLabelLiftIsSystemicOnBar() {
        // A bar with a label: same mechanism. The label must not be occluded by the emphasized bar.
        let v = EChartsView(width: 400, height: 300)
        v.setOption([
            "xAxis": ["type": "category", "data": ["A", "B"]],
            "yAxis": ["type": "value"],
            "series": [["type": "bar", "data": [10, 20],
                        "label": ["show": true, "position": "inside"] as [String: Any]] as [String: Any]]
        ])
        _ = v.zr.storage.getDisplayList(true)
        guard let bar = firstBandWithLabel(v.ec.getRoot()), let label = bar.getTextContent() else {
            return XCTFail("no bar with a label found")
        }
        let baseGap = label.z2 - bar.z2
        bar.useState("emphasis", nil, true)
        _ = v.zr.storage.getDisplayList(true)
        XCTAssertEqual(label.z2 - bar.z2, baseGap, accuracy: 1e-9,
                       "the label keeps its relative z2 above the bar after emphasis (both lift by 10)")
    }
}
