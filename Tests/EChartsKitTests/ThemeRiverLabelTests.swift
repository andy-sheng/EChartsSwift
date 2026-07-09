// LABEL RETROFIT TEST for ThemeRiverView: the per-layer band label must be produced by the shared
// label core (`labelStyle.setLabelStyle`) attached as the band Polygon's textContent — NOT the old
// inline ZRText path. Upstream ThemeRiverView.ts routes the layer/series name through
// `setLabelStyle(polygon, getLabelStatesModels(seriesModel), { defaultText: data.getName(...) }, ...)`,
// then overrides the textConfig with `{ position: null, local: true }` and positions the label element
// manually at the band's left-edge vertical center. This test drives ECharts with a real themeRiver
// option and asserts, for every band, that:
//   1. the band has a getTextContent() (setLabelStyle attached one),
//   2. its textStyle.text == the layer name (the default label the core resolved from opt.defaultText),
//   3. textConfig.local == true and textConfig.position == nil (upstream's post-setLabelStyle override).
// The OLD inline path set textConfig.position = "insideLeft" and never set `local`, so it FAILS 3.
import XCTest
import ZRenderKit
@testable import EChartsKit

final class ThemeRiverLabelTests: XCTestCase {
    func testThemeRiverBandLabelsRouteThroughSetLabelStyle() {
        let w = 520.0, h = 380.0
        let ec = ECharts(width: w, height: h)
        ec.setOption([
            "singleAxis": ["type": "value", "left": "10%", "right": "10%",
                           "top": "10%", "bottom": "10%"] as [String: Any],
            "series": [["type": "themeRiver",
                        "data": [
                            [0.0, 10.0, "Alpha"], [1.0, 15.0, "Alpha"], [2.0, 12.0, "Alpha"],
                            [3.0, 18.0, "Alpha"], [4.0, 14.0, "Alpha"],
                            [0.0,  8.0, "Beta"],  [1.0,  6.0, "Beta"],  [2.0, 11.0, "Beta"],
                            [3.0,  9.0, "Beta"],  [4.0, 13.0, "Beta"],
                            [0.0,  5.0, "Gamma"], [1.0,  9.0, "Gamma"], [2.0,  7.0, "Gamma"],
                            [3.0,  4.0, "Gamma"], [4.0, 10.0, "Gamma"]
                        ]] as [String: Any]]
        ])

        var bands: [ThemeRiverBand] = []
        _ = ec.getRoot().traverse { el in
            if el.name == "item", let band = el as? ThemeRiverBand {
                bands.append(band)
            }
            return false
        }

        XCTAssertEqual(bands.count, 3, "themeRiver → one band per layer")

        var labelTexts: Set<String> = []
        for band in bands {
            // 1. setLabelStyle attached the label as the band's textContent.
            guard let labelEl = band.getTextContent() else {
                return XCTFail("band must have a getTextContent() attached by setLabelStyle")
            }
            // 2. The core resolved the default label (the layer/series name) into the text style.
            guard let text = labelEl.textStyle?.text, !text.isEmpty else {
                return XCTFail("band label textStyle.text must be the layer name")
            }
            labelTexts.insert(text)

            // 3. Upstream overrides the textConfig after setLabelStyle with { position: null, local: true }.
            //    The OLD inline path set position = "insideLeft" and never set `local`.
            guard let tc = band.textConfig else {
                return XCTFail("band must carry a textConfig")
            }
            XCTAssertEqual(tc.local, true, "themeRiver label uses local text placement (upstream local:true)")
            XCTAssertNil(tc.position, "themeRiver nulls textConfig.position and positions the label manually")
        }

        XCTAssertEqual(labelTexts, ["Alpha", "Beta", "Gamma"],
                       "each band's label is its layer name, resolved via opt.defaultText")
    }
}
