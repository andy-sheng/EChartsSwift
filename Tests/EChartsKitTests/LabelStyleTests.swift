// SHARED LABEL CORE tests — label/labelStyle.ts (upstream echarts/src/label/labelStyle.ts) ported to
// label/labelStyle.swift. This is foundational: every chart's label rendering will eventually route
// through `labelStyle.setLabelStyle` / `labelStyle.getLabelStatesModels`. These tests exercise the
// public surface headlessly (no UIView / pointer host), matching the sibling ZZEmphasisTests style.
import XCTest
import ZRenderKit
@testable import EChartsKit

final class LabelStyleTests: XCTestCase {

    // ---- (a) getLabelStatesModels returns all 4 display-state sub-models ----
    func testGetLabelStatesModelsReturnsFourModels() {
        let itemModel = Model([
            "label": ["show": true, "position": "top", "formatter": "{b}"] as [String: Any],
            "emphasis": ["label": ["show": true]] as [String: Any],
            "blur": ["label": [:] as [String: Any]] as [String: Any],
            "select": ["label": [:] as [String: Any]] as [String: Any]
        ] as [String: Any])

        let statesModels = labelStyle.getLabelStatesModels(itemModel)

        XCTAssertEqual(statesModels.count, 4, "normal + emphasis + blur + select")
        XCTAssertNotNil(statesModels[.normal])
        XCTAssertNotNil(statesModels[.emphasis])
        XCTAssertNotNil(statesModels[.blur])
        XCTAssertNotNil(statesModels[.select])
        XCTAssertEqual(statesModels[.normal]?.getShallow("position") as? String, "top")
        XCTAssertEqual(statesModels[.emphasis]?.getShallow("show") as? Bool, true)
    }

    // ---- (b) setLabelStyle attaches a ZRText textContent with resolved text + textConfig.position ----
    func testSetLabelStyleAttachesTextContentWithDefaultText() {
        let itemModel = Model([
            "label": ["show": true, "position": "top"] as [String: Any]
        ] as [String: Any])
        let statesModels = labelStyle.getLabelStatesModels(itemModel)

        var opt = SetLabelStyleOpt()
        opt.defaultText = "Hi"

        let el = Group()
        labelStyle.setLabelStyle(el, statesModels, opt)

        guard let text = el.getTextContent() else {
            return XCTFail("setLabelStyle should attach a ZRText as textContent when label.show is true")
        }
        XCTAssertEqual(text.textStyle.text, "Hi")
        XCTAssertFalse(text.ignore, "label.show == true -> the attached ZRText must not be ignored")

        guard let textConfig = el.textConfig else {
            return XCTFail("setLabelStyle should set el.textConfig")
        }
        XCTAssertEqual(textConfig.position as? String, "top", "position comes from the normal label model")
    }

    // setLabelStyle on a label whose `show` is false (default, unset) across every state must NOT
    // attach/create a text content (mirrors upstream's `needsCreateText` early-out).
    func testSetLabelStyleDoesNotCreateTextWhenNotShown() {
        let itemModel = Model([String: Any]())
        let statesModels = labelStyle.getLabelStatesModels(itemModel)

        var opt = SetLabelStyleOpt()
        opt.defaultText = "Hi"

        let el = Group()
        labelStyle.setLabelStyle(el, statesModels, opt)

        XCTAssertNil(el.getTextContent(), "no label state has show:true -> no textContent should be created")
    }

    // ---- (c) a "{b}" formatter resolves through a real SeriesModel's getFormattedLabel ----
    func testSetLabelStyleResolvesFormatterThroughLabelFetcher() {
        ComponentModel.registerClass(PieSeriesModel.self)
        let ec = EChartsSlim(width: 400, height: 320)
        ec.setOption([
            "series": [["type": "pie",
                        "data": [["value": 40.0, "name": "Alpha"],
                                 ["value": 10.0, "name": "Beta"]]] as [String: Any]]
        ])

        var seriesModel: SeriesModel?
        ec.getModel()?.eachSeries { s, _ in seriesModel = s }
        guard let seriesModel = seriesModel else {
            return XCTFail("EChartsSlim.setOption should have built a pie SeriesModel")
        }
        XCTAssertEqual(seriesModel.getData().count(), 2)

        // itemModel for row 0 carries label.formatter = '{b}' (the series-name template var).
        let itemModel = Model([
            "label": ["show": true, "formatter": "{b}"] as [String: Any]
        ] as [String: Any])
        let statesModels = labelStyle.getLabelStatesModels(itemModel)

        var opt = SetLabelStyleOpt()
        opt.labelFetcher = seriesModel
        opt.labelDataIndex = 0
        opt.defaultText = "fallback"

        let el = Group()
        labelStyle.setLabelStyle(el, statesModels, opt)

        guard let text = el.getTextContent() else {
            return XCTFail("setLabelStyle should attach a ZRText")
        }
        XCTAssertEqual(text.textStyle.text, "Alpha", "'{b}' should resolve to the row-0 series/data name via getFormattedLabel")
    }
}
