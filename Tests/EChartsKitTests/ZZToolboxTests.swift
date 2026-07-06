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
