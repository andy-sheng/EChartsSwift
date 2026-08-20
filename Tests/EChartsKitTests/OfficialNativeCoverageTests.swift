import XCTest
import ZRenderKit
import EChartsDemoCore
@testable import EChartsKit

/// Regression coverage for the native capabilities used by the two official demos that previously
/// remained disabled: official-pictorialBar-spirit and official-matrix-mbti.
final class OfficialNativeCoverageTests: XCTestCase {

    override func setUp() {
        super.setUp()
        ComponentModel.registerClass(PictorialBarSeriesModel.self)
    }

    func testCirclePackingRecomputesPerRenderAndCreatesOfficialShapeUpdateTween() throws {
        let demo = try XCTUnwrap(EChartsDemoRegistry.byName("official-circle-packing-with-d3"))
        let view = EChartsView(width: demo.width, height: demo.height)
        view.setOption(demo.option)

        // Settle the entrance before issuing the merge update that the official example uses for
        // drilldown. The d3-v2 enclosure recomputation changes sub-pixel circle geometry and its
        // explicit `transition: ['shape']` must therefore create update animators.
        _ = view.ec.getRoot().traverse { element in
            _ = element.stopAnimation(nil, true)
            return false
        }
        view.setOption(demo.option)

        var circles = 0
        var animated = 0
        _ = view.ec.getRoot().traverse { element in
            if element is Circle {
                circles += 1
                if element.animators.contains(where: { $0.scope == "update" }) { animated += 1 }
            }
            return false
        }
        XCTAssertGreaterThan(circles, 500)
        XCTAssertGreaterThan(animated, 0,
            "custom params.context must reset per setOption so d3 shape transitions are not suppressed")
    }

    func testFixedImagePictorialBarClipsForegroundAndFormatsBackgroundLabel() {
        let onePixelPNG =
            "image://data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJ" +
            "AAAADUlEQVQIHWP4z8DwHwAFgAI/ScL6WQAAAABJRU5ErkJggg=="
        let percent: (CallbackDataParams) -> String = { params in
            let value = (params.value as? NSNumber)?.doubleValue ?? 0
            return String(format: "%.1f %%", value)
        }

        let ec = ECharts(width: 400, height: 220)
        ec.setOption([
            "animation": false,
            "grid": ["left": 40.0, "right": 40.0, "top": 40.0, "height": 80.0] as [String: Any],
            "xAxis": ["type": "value", "max": 100.0] as [String: Any],
            "yAxis": ["type": "category", "data": ["row"]] as [String: Any],
            "series": [
                [
                    "type": "pictorialBar", "symbol": onePixelPNG,
                    "symbolRepeat": "fixed", "symbolSize": 20.0,
                    "symbolBoundingData": 100.0, "symbolClip": true,
                    "data": [40.0], "z": 10.0
                ] as [String: Any],
                [
                    "type": "pictorialBar", "symbol": onePixelPNG,
                    "symbolRepeat": "fixed", "symbolSize": 20.0,
                    "symbolBoundingData": 100.0, "itemStyle": ["opacity": 0.2] as [String: Any],
                    "label": ["show": true, "formatter": percent, "position": "right"] as [String: Any],
                    "data": [40.0], "z": 5.0
                ] as [String: Any]
            ]
        ])

        var foreground: PictorialBarElement?
        var background: PictorialBarElement?
        _ = ec.getRoot().traverse { element in
            guard let bar = element as? PictorialBarElement else { return false }
            if bar.__pictorialSymbolMeta.symbolClip { foreground = bar }
            else { background = bar }
            return false
        }

        let fg = try? XCTUnwrap(foreground)
        let bg = try? XCTUnwrap(background)
        XCTAssertNotNil(fg)
        XCTAssertNotNil(bg)
        guard let fg, let bg else { return }

        XCTAssertTrue(fg.__pictorialBundle.children().contains { $0 is ZRImage })
        XCTAssertTrue(bg.__pictorialBundle.children().contains { $0 is ZRImage })
        guard let clipShape = fg.__pictorialBundle.getClipPath()?.shape as? RectShape else {
            return XCTFail("the clipped foreground must install a Rect clip path on its repeated-image bundle")
        }
        XCTAssertGreaterThan(clipShape.width, 0)
        XCTAssertLessThan(clipShape.width, abs(fg.__pictorialSymbolMeta.boundingLength),
                          "value 40 must reveal only part of the full 100-unit repeated sprite row")
        XCTAssertEqual(bg.__pictorialBarRect?.getTextContent()?.textStyle?.text, "40.0 %")
    }

    func testMatrixHeatmapCarriesDecalAndScatterFormatterLabelsCells() {
        let percentage: (CallbackDataParams) -> String = { params in
            guard let row = params.value as? [Any], row.count > 2,
                  let number = row[2] as? NSNumber else { return "" }
            return "\(Int(floor(number.doubleValue * 100 + 0.5)))%"
        }
        let axisData: [[String: Any]] = [
            ["value": "G1", "children": [["value": "A"], ["value": "B"]]],
            ["value": "G2", "children": [["value": "C"], ["value": "D"]]]
        ]
        let rows: [[String: Any]] = [
            ["value": ["A", "A", 0.25] as [Any], "itemStyle": ["decal": matrixTestDecal("#2D9A69")] as [String: Any]],
            ["value": ["A", "B", 0.50] as [Any], "itemStyle": ["decal": matrixTestDecal("#7D568F")] as [String: Any]],
            ["value": ["B", "A", 0.75] as [Any], "itemStyle": ["decal": matrixTestDecal("#3A8DAB")] as [String: Any]],
            ["value": ["B", "B", 1.00] as [Any], "itemStyle": ["decal": matrixTestDecal("#E0A433")] as [String: Any]]
        ]

        let ec = ECharts(width: 420, height: 320)
        ec.setOption([
            "animation": false,
            "matrix": [
                "left": 60.0, "top": 40.0, "width": 280.0, "height": 240.0,
                "x": ["data": axisData] as [String: Any],
                "y": ["data": axisData] as [String: Any]
            ] as [String: Any],
            "visualMap": [[
                "type": "continuous", "min": 0.0, "max": 1.0, "dimension": 2.0,
                "inRange": ["opacity": [0.0, 1.0]] as [String: Any],
                "seriesIndex": [0.0], "show": false
            ] as [String: Any]],
            "series": [
                [
                    "type": "heatmap", "coordinateSystem": "matrix", "data": rows,
                    "label": ["show": false] as [String: Any]
                ] as [String: Any],
                [
                    "type": "scatter", "coordinateSystem": "matrix", "symbolSize": 0.0,
                    "data": rows.map { ["value": $0["value"]!] as [String: Any] },
                    "label": ["show": true, "formatter": percentage] as [String: Any],
                    "silent": true
                ] as [String: Any]
            ]
        ])

        let scatterModel = ec.getModel()?.getSeriesByIndex(1)
        XCTAssertNotNil(scatterModel)
        XCTAssertNotNil(scatterModel?.getData().hostModel,
                        "render data must retain its label-fetching series model")

        var heatmapCells: [Rect] = []
        var texts = Set<String>()
        _ = ec.getRoot().traverse { element in
            if let rect = element as? Rect, rect.name == "item" { heatmapCells.append(rect) }
            if let text = element as? ZRText, let value = text.textStyle?.text { texts.insert(value) }
            if let value = element.getTextContent()?.textStyle?.text { texts.insert(value) }
            return false
        }

        XCTAssertEqual(heatmapCells.count, 4)
        XCTAssertTrue(heatmapCells.allSatisfy { $0.pathStyle.decal != nil },
                      "the generated itemStyle decal must reach every matrix heatmap cell Path")
        XCTAssertTrue(["25%", "50%", "75%", "100%"].allSatisfy(texts.contains))
        XCTAssertTrue(["G1", "G2", "A", "B", "C", "D"].allSatisfy(texts.contains),
                      "nested matrix group and child headers must render natively")
    }

    @MainActor
    func testMatrixMbtiNativeClickTogglesTheSameSummaryAndDetailSeriesAsWeb() throws {
        let demo = try XCTUnwrap(EChartsDemoRegistry.byName("official-matrix-mbti"))
        let drive = try XCTUnwrap(demo.drive)
        let chart = DemoChartSpy()
        drive(chart)

        let click = try XCTUnwrap(chart.handlers["click"])
        click(ECElementEvent(type: "click"))
        XCTAssertEqual(chart.lastSeriesIDs, ["summary-heatmap"])
        XCTAssertEqual(chart.lastSeriesDataCount, 16)

        click(ECElementEvent(type: "click"))
        XCTAssertEqual(chart.lastSeriesIDs, ["detail-heatmap", "detail-scatter"])
        XCTAssertEqual(chart.lastSeriesDataCount, 256)
    }
}

@MainActor
private final class DemoChartSpy: EChartsDemoChart {
    var handlers: [String: @MainActor (ECEventParams) -> Void] = [:]
    private var lastOption: [String: Any] = [:]

    var lastSeriesIDs: [String] {
        (lastOption["series"] as? [[String: Any]])?.compactMap { $0["id"] as? String } ?? []
    }

    var lastSeriesDataCount: Int? {
        guard let series = lastOption["series"] as? [[String: Any]],
              let first = series.first else { return nil }
        return (first["data"] as? [[String: Any]])?.count
    }

    func setOption(_ option: [String: Any], notMerge: Bool) { lastOption = option }
    func every(_ seconds: Double, _ body: @escaping @MainActor () -> Void) {}
    func after(_ seconds: Double, _ body: @escaping @MainActor () -> Void) {}
    func dispatch(_ payload: [String: Any]) {}
    func on(_ event: String, _ handler: @escaping @MainActor (ECEventParams) -> Void) {
        handlers[event] = handler
    }
}

private func matrixTestDecal(_ color: String) -> [String: Any] {
    [
        "symbol": "circle", "symbolSize": 1.0, "color": color,
        "backgroundColor": "#ffffff", "dashArrayX": [[1.0, 1.0], [0.0, 1.0, 1.0, 0.0]],
        "dashArrayY": [1.0, 0.0]
    ]
}
