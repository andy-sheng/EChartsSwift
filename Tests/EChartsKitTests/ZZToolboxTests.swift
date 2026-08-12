// Phase 49 regression test — the toolbox ACTION core: `changeMagicType` (line ↔ bar swap via
// ecModel.mergeOption) and `restore` (reset to the original option via ecModel.resetOption('recreate')).
// These are the option-expressible toolbox features; the on-canvas icon view is deferred.
import XCTest
import ZRenderKit
@testable import EChartsKit

final class ZZToolboxTests: XCTestCase {

    override func setUp() {
        super.setUp()
        ComponentModel.registerClass(BarSeriesModel.self)
        ComponentModel.registerClass(LineSeriesModel.self)
    }

    private func makeChart() -> EChartsView {
        let view = EChartsView(width: 460, height: 300)
        view.setOption([
            "grid": ["left": 50.0, "top": 20.0, "width": 380.0, "height": 240.0] as [String: Any],
            "toolbox": ["feature": ["magicType": ["type": ["line", "bar"]] as [String: Any],
                                    "restore": [String: Any]()] as [String: Any]] as [String: Any],
            "xAxis": ["type": "category", "data": ["A","B","C","D","E"]] as [String: Any],
            "yAxis": ["type": "value"] as [String: Any],
            "series": [["name": "s", "type": "line", "data": [5.0, 9, 7, 12, 6]] as [String: Any]]
        ])
        return view
    }

    private func seriesType(_ view: EChartsView) -> String? {
        var t: String?
        view.ec.getModel()?.eachSeries { s, _ in if t == nil { t = s.subType } }
        return t
    }

    // ---- (1) a toolbox is a valid component; the magicType action swaps line → bar ----
    func testMagicTypeSwapsLineToBar() {
        let view = makeChart()
        XCTAssertNotNil(view.ec.getModel()?.getComponent("toolbox"), "toolbox component must exist")
        XCTAssertEqual(seriesType(view), "line", "chart starts as a line series")

        // Compute the magicType 'bar' merge option (what the toolbox icon onclick would build) and dispatch.
        let newOption = computeMagicTypeOption(view.ec.getModel()!, "bar")
        var p = Payload(type: "changeMagicType")
        p.other["newOption"] = newOption
        view.ec.dispatchAction(p)

        XCTAssertEqual(seriesType(view), "bar", "changeMagicType('bar') must merge the series to type:'bar'")
    }

    // ---- (1b) magicType 'stack' sets each series' stack, 'tiled' clears it ----
    func testMagicTypeStackAndTiled() {
        let view = makeChart()
        func stackOf(_ v: EChartsView) -> String? {
            var s: String?
            v.ec.getModel()?.eachSeries { m, _ in if s == nil { s = m.get("stack") as? String } }
            return s
        }
        XCTAssertNil(stackOf(view), "no stack initially")

        var stackP = Payload(type: "changeMagicType")
        stackP.other["newOption"] = computeMagicTypeOption(view.ec.getModel()!, "stack")
        view.ec.dispatchAction(stackP)
        XCTAssertEqual(stackOf(view), TOOLBOX_MAGIC_STACK_KEYWORD, "magicType('stack') sets the shared stack key")

        var tiledP = Payload(type: "changeMagicType")
        tiledP.other["newOption"] = computeMagicTypeOption(view.ec.getModel()!, "tiled")
        view.ec.dispatchAction(tiledP)
        XCTAssertNil(stackOf(view), "magicType('tiled') clears the stack")
    }

    // ---- (1c) the toolbox VIEW renders one icon path per enabled feature icon ----
    //   magicType(type:[line,bar]) → 2 icons (line + bar), restore → 1 icon ⇒ 3 SVGPath icons.
    func testToolboxViewRendersFeatureIcons() {
        let view = makeChart()

        // The restore + magicType features must be registered so the model merges their default
        //   `icon`/`title` into the feature option (and the view can build the icon paths).
        XCTAssertNotNil(getFeature("restore"), "restore feature must be registered")
        XCTAssertNotNil(getFeature("magicType"), "magicType feature must be registered")
        XCTAssertNotNil(getFeature("saveAsImage"), "saveAsImage feature must be registered")
        XCTAssertNotNil(getFeature("dataZoom"), "dataZoom feature must be registered")
        XCTAssertNotNil(getFeature("dataView"), "dataView feature must be registered so its canvas icon renders")

        // Count the makePath icon paths (SVGPath) in the rendered display list. Icons are the only
        //   SVGPath elements in a plain bar/line + toolbox chart (axes emit Line/Rect, the toolbox
        //   background is a Rect); each enabled feature icon is exactly one SVGPath.
        var iconCount = 0
        _ = view.ec.getRoot().traverse { el in
            if el is SVGPath { iconCount += 1 }
            return false
        }
        XCTAssertEqual(iconCount, 3,
                       "toolbox should render 3 feature icons (magicType line+bar, restore), got \(iconCount)")
    }

    func testDataViewFeatureRendersItsDocumentIcon() {
        let view = EChartsView(width: 460, height: 300)
        view.setOption([
            "toolbox": ["feature": ["dataView": ["show": true] as [String: Any]] as [String: Any]] as [String: Any]
        ])
        guard let toolbox = view.ec._componentsViews.compactMap({ $0 as? ToolboxView }).first else {
            return XCTFail("expected toolbox view")
        }
        XCTAssertNotNil(toolbox._features["dataView"] as? ToolboxDataViewFeature)
        XCTAssertEqual(toolbox.group.children().filter { $0 is SVGPath }.count, 1,
                       "dataView contributes its document icon even when the native DOM editor is unavailable")
    }

    func testExplicitRightClearsDefaultLeftAndKeepsHorizontalLayout() {
        let view = EChartsView(width: 460, height: 300)
        view.setOption([
            "toolbox": [
                "right": 10.0,
                "feature": [
                    "restore": [String: Any](),
                    "saveAsImage": [String: Any]()
                ] as [String: Any]
            ] as [String: Any]
        ])

        guard let toolbox = view.ec._componentsViews.compactMap({ $0 as? ToolboxView }).first else {
            return XCTFail("expected toolbox view")
        }
        let icons = toolbox.group.children().compactMap { $0 as? SVGPath }
        XCTAssertEqual(icons.count, 2)
        XCTAssertGreaterThan(toolbox.group.x, view.ec.getWidth() / 2,
                             "right:10 must position the toolbox on the right")
        XCTAssertEqual(icons[0].y, icons[1].y, accuracy: 1e-9,
                       "the default horizontal toolbox must keep icons on one row")
        XCTAssertNotEqual(icons[0].x, icons[1].x,
                          "horizontal toolbox icons must advance along x")
    }

    func testBuiltInFeatureAndGroupedIconOrderIsStable() {
        let view = EChartsView(width: 460, height: 300)
        view.setOption([
            "toolbox": [
                "feature": [
                    "saveAsImage": [String: Any](),
                    "restore": [String: Any](),
                    "dataZoom": ["yAxisIndex": "none"] as [String: Any]
                ] as [String: Any]
            ] as [String: Any]
        ])
        guard let toolbox = view.ec._componentsViews.compactMap({ $0 as? ToolboxView }).first,
              let dzTitle = toolbox._features["dataZoom"]?.model.get("title") as? [String: Any],
              let zoomTitle = dzTitle["zoom"] as? String,
              let backTitle = dzTitle["back"] as? String,
              let restoreTitle = toolbox._features["restore"]?.model.get("title") as? String,
              let saveTitle = toolbox._features["saveAsImage"]?.model.get("title") as? String else {
            return XCTFail("expected built-in toolbox feature titles")
        }
        let renderedTitles = toolbox.group.children().compactMap { child -> String? in
            guard child is SVGPath else { return nil }
            return child.getTextContent()?.textStyle?.text
        }
        XCTAssertEqual(renderedTitles, [zoomTitle, backTitle, restoreTitle, saveTitle],
                       "Dictionary iteration must not scramble official toolbox icon order")
    }

    func testExplicitFeatureOrderPreservesSourceObjectOrder() {
        let view = EChartsView(width: 460, height: 300)
        view.setOption([
            "toolbox": [
                "_featureOrder": ["magicType", "dataView"],
                "feature": [
                    "dataView": [String: Any](),
                    "magicType": ["type": ["stack"]] as [String: Any]
                ] as [String: Any]
            ] as [String: Any]
        ])
        guard let toolbox = view.ec._componentsViews.compactMap({ $0 as? ToolboxView }).first else {
            return XCTFail("expected toolbox view")
        }
        let titles = toolbox.group.children().compactMap { child -> String? in
            guard child is SVGPath else { return nil }
            return child.getTextContent()?.textStyle?.text
        }
        XCTAssertEqual(titles.count, 2)
        XCTAssertEqual(titles.first, (toolbox._features["magicType"]?.model.get("title") as? [String: Any])?["stack"] as? String)
        XCTAssertEqual(titles.last, toolbox._features["dataView"]?.model.get("title") as? String)
    }

    // ---- (1d) each icon carries a hidden title text content (revealed on hover) ----
    func testToolboxIconsCarryTitleTextContent() {
        let view = makeChart()
        var iconsWithText = 0
        _ = view.ec.getRoot().traverse { el in
            if let p = el as? SVGPath, p.getTextContent() != nil { iconsWithText += 1 }
            return false
        }
        XCTAssertEqual(iconsWithText, 3, "every toolbox icon should carry a title textContent")
    }

    // ---- (1e) hovering (highlight) an icon enters emphasis + reveals its title; downplay hides it ----
    //   Faithful wiring test: the toolbox icon is a highDown dispatcher whose title textContent is
    //   hidden normally (ignore=true) and visible in its emphasis state (ignore=false). Entering
    //   emphasis on the icon propagates the state to the textContent (Element.useState→textContent),
    //   so the title appears; leaving emphasis restores the hidden normal state.
    func testIconHoverEntersEmphasisAndRevealsTitle() {
        let view = makeChart()

        // Grab the first toolbox icon path (the only SVGPaths that carry a title textContent).
        var icon: SVGPath?
        _ = view.ec.getRoot().traverse { el in
            if icon == nil, let p = el as? SVGPath, p.getTextContent() != nil { icon = p }
            return false
        }
        guard let path = icon, let title = path.getTextContent() else {
            return XCTFail("expected a toolbox icon with a title textContent")
        }

        // Normal state: the title is hidden.
        XCTAssertTrue(title.ignore, "title text is hidden before hover")
        XCTAssertFalse(path.currentStates.contains("emphasis"), "icon is not emphasized initially")

        // Hover / highlight the icon (same primitive the live-host mouseover fires).
        view.ec.api.enterEmphasis(path)
        XCTAssertTrue(path.currentStates.contains("emphasis"), "icon enters emphasis on hover")
        XCTAssertFalse(title.ignore, "title text is revealed while the icon is emphasized")

        // Downplay hides the title again.
        view.ec.api.leaveEmphasis(path)
        XCTAssertFalse(path.currentStates.contains("emphasis"), "icon leaves emphasis on downplay")
        XCTAssertTrue(title.ignore, "title text is hidden again after downplay")
    }

    // ---- (2) restore resets a magicType swap back to the original option ----
    func testRestoreResetsMagicType() {
        let view = makeChart()
        XCTAssertEqual(seriesType(view), "line")

        // Swap to bar…
        var p = Payload(type: "changeMagicType")
        p.other["newOption"] = computeMagicTypeOption(view.ec.getModel()!, "bar")
        view.ec.dispatchAction(p)
        XCTAssertEqual(seriesType(view), "bar", "swapped to bar")

        // …then restore → back to the original line series.
        view.ec.dispatchAction(Payload(type: "restore"))
        XCTAssertEqual(seriesType(view), "line", "restore must reset the series back to type:'line'")
    }
}
