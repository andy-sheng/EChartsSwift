// Toolbox completion regression tests — the two features that previously landed icon-only:
//   (a) SaveAsImage — clicking the icon renders the current scene to PNG bytes and hands them to the
//       host `onSaveImage` callback (the browser `<a download>` analog). Proves non-empty PNG bytes flow
//       through the `getRenderedImage` / `onSaveImage` host seams end-to-end from `feature.onclick`.
//   (b) DataZoom box-select — arming the toolbox dataZoom (`takeGlobalCursor` key 'dataZoomSelect') then
//       dragging a rectangle over the grid dispatches a `dataZoom` box-select that NARROWS the cartesian
//       dataZoom window; the `back` icon pops the history to restore it.
import XCTest
import ZRenderKit
import NativePainter
import CoreGraphics
import ImageIO
@testable import EChartsKit

final class ZZToolboxCompletionTests: XCTestCase {

    override func setUp() {
        super.setUp()
        ComponentModel.registerClass(BarSeriesModel.self)
        ComponentModel.registerClass(LineSeriesModel.self)
    }

    private func toolboxView(_ view: EChartsView) -> ToolboxView? {
        return view.ec._componentsViews.compactMap { $0 as? ToolboxView }.first
    }

    // ---- (a) SaveAsImage: onclick renders the scene → PNG bytes → host onSaveImage ----
    func testSaveAsImageDeliversPngToHost() {
        let view = EChartsView(width: 320, height: 220)

        // Wire the host seams: `getRenderedImage` rasterizes the current display list via NativePainter's
        //   renderToImage; `onSaveImage` captures the encoded bytes (the "download").
        view.ec.getRenderedImage = { [weak view] _ in
            guard let view = view else { return nil }
            let size = CGSize(width: view.ec.getWidth(), height: view.ec.getHeight())
            guard let cg = renderToImage(group: view.ec.getRoot(), size: size) else { return nil }
            let mutable = NSMutableData()
            guard let dest = CGImageDestinationCreateWithData(mutable, "public.png" as CFString, 1, nil)
            else { return nil }
            CGImageDestinationAddImage(dest, cg, nil)
            guard CGImageDestinationFinalize(dest) else { return nil }
            return mutable as Data
        }
        var captured: Data?
        var capturedName: String?
        view.ec.onSaveImage = { data, filename in captured = data; capturedName = filename }

        view.setOption([
            "grid": ["left": 40.0, "top": 20.0, "width": 240.0, "height": 160.0] as [String: Any],
            "toolbox": ["feature": ["saveAsImage": ["type": "png", "name": "chart"] as [String: Any]] as [String: Any]] as [String: Any],
            "xAxis": ["type": "category", "data": ["A", "B", "C", "D", "E"]] as [String: Any],
            "yAxis": ["type": "value"] as [String: Any],
            "series": [["type": "bar", "data": [5.0, 9, 7, 12, 6]] as [String: Any]]
        ])

        guard let tbView = toolboxView(view) else { XCTFail("no toolbox view"); return }
        guard let feature = tbView._features["saveAsImage"] else {
            XCTFail("saveAsImage feature must be live after render"); return
        }

        // Simulate the icon click (upstream `path.on('click', bind(feature.onclick, ...))`).
        feature.onclick(view.ec.getModel()!, view.ec.api, "saveAsImage")

        guard let data = captured else { XCTFail("onSaveImage was not called with PNG bytes"); return }
        XCTAssertGreaterThan(data.count, 0, "the exported PNG must be non-empty")
        // PNG signature: 89 50 4E 47 0D 0A 1A 0A
        let sig: [UInt8] = [0x89, 0x50, 0x4E, 0x47]
        XCTAssertEqual(Array(data.prefix(4)), sig, "the exported bytes must be a PNG")
        XCTAssertEqual(capturedName, "chart.png", "filename = name + '.' + type")
    }

    // A pure-headless chart WITHOUT the host rasterizer wired → onclick is a silent no-op (no crash).
    func testSaveAsImageNoHostRendererIsNoOp() {
        let view = EChartsView(width: 320, height: 220)
        var called = false
        view.ec.onSaveImage = { _, _ in called = true }
        view.setOption([
            "toolbox": ["feature": ["saveAsImage": [String: Any]()] as [String: Any]] as [String: Any],
            "xAxis": ["type": "category", "data": ["A", "B"]] as [String: Any],
            "yAxis": ["type": "value"] as [String: Any],
            "series": [["type": "bar", "data": [1.0, 2]] as [String: Any]]
        ])
        toolboxView(view)?._features["saveAsImage"]?.onclick(view.ec.getModel()!, view.ec.api, "saveAsImage")
        XCTAssertFalse(called, "no rasterizer wired → no bytes → onSaveImage not called")
    }

    // ---- (b) DataZoom box-select: arm + drag a rectangle narrows the dataZoom window ----
    private func makeDataZoomChart() -> EChartsView {
        let view = EChartsView(width: 360, height: 260)
        view.setOption([
            "grid": ["left": 50.0, "top": 20.0, "width": 260.0, "height": 200.0] as [String: Any],
            "toolbox": ["feature": ["dataZoom": [String: Any]()] as [String: Any]] as [String: Any],
            "dataZoom": [["type": "inside", "xAxisIndex": 0] as [String: Any]],
            "xAxis": ["type": "category", "data": ["A", "B", "C", "D", "E", "F", "G", "H", "I", "J"]] as [String: Any],
            "yAxis": ["type": "value"] as [String: Any],
            "series": [["type": "bar", "data": [5.0, 9, 7, 12, 6, 8, 4, 11, 3, 10]] as [String: Any]]
        ])
        return view
    }

    private func xDataZoomRange(_ view: EChartsView) -> [Double]? {
        var range: [Double]?
        view.ec.getModel()?.eachComponent("dataZoom") { m, _ in
            if range == nil, let dz = m as? DataZoomModel { range = dz.getPercentRange() }
        }
        return range
    }

    func testDataZoomBoxSelectNarrowsWindow() {
        let view = makeDataZoomChart()
        guard let before = xDataZoomRange(view) else { XCTFail("no dataZoom window"); return }
        XCTAssertEqual(before[0], 0, accuracy: 1e-6, "starts at full window [0,100]")
        XCTAssertEqual(before[1], 100, accuracy: 1e-6)

        // Arm the toolbox dataZoom box-select (upstream: the `zoom` icon dispatches takeGlobalCursor).
        var arm = Payload(type: "takeGlobalCursor")
        arm.other["key"] = "dataZoomSelect"
        arm.other["dataZoomSelectActive"] = true
        view.ec.dispatchAction(arm)
        XCTAssertTrue(view.ec.dataZoomSelectActive, "takeGlobalCursor arms the box-select")

        // Drag a rectangle over the MIDDLE of the grid (x from 30% to 65% of the grid width).
        let gridLeft = 50.0, gridWidth = 260.0
        let x0 = gridLeft + gridWidth * 0.30   // 128
        let x1 = gridLeft + gridWidth * 0.65   // 219
        view._injectPointerForTest(type: "mousedown", zrX: x0, zrY: 60.0)
        view._injectPointerForTest(type: "mousemove", zrX: x1, zrY: 180.0)
        view._injectPointerForTest(type: "mouseup", zrX: x1, zrY: 180.0)

        guard let after = xDataZoomRange(view) else { XCTFail("no dataZoom window after drag"); return }
        let beforeSpan = before[1] - before[0]
        let afterSpan = after[1] - after[0]
        XCTAssertLessThan(afterSpan, beforeSpan, "the box-select drag must NARROW the dataZoom window")
        XCTAssertGreaterThan(afterSpan, 0, "the window must remain non-empty")
        // The window should sit inside the dragged fraction (~[30,65] of the axis).
        XCTAssertGreaterThan(after[0], 10, "left edge moved in from 0")
        XCTAssertLessThan(after[1], 90, "right edge moved in from 100")
    }

    func testDataZoomBackRestoresWindow() {
        let view = makeDataZoomChart()
        guard let before = xDataZoomRange(view) else { XCTFail("no window"); return }

        var arm = Payload(type: "takeGlobalCursor")
        arm.other["key"] = "dataZoomSelect"
        arm.other["dataZoomSelectActive"] = true
        view.ec.dispatchAction(arm)

        let gridLeft = 50.0, gridWidth = 260.0
        view._injectPointerForTest(type: "mousedown", zrX: gridLeft + gridWidth * 0.30, zrY: 60.0)
        view._injectPointerForTest(type: "mousemove", zrX: gridLeft + gridWidth * 0.65, zrY: 180.0)
        view._injectPointerForTest(type: "mouseup", zrX: gridLeft + gridWidth * 0.65, zrY: 180.0)

        guard let zoomed = xDataZoomRange(view) else { XCTFail("no zoomed window"); return }
        XCTAssertLessThan(zoomed[1] - zoomed[0], before[1] - before[0], "window narrowed after zoom")
        XCTAssertGreaterThan(dataZoomHistoryCount(view.ec.getModel()!), 1, "history has a snapshot to pop")

        // Click the `back` icon (feature.onclick pops history → dispatches a restoring dataZoom action).
        toolboxView(view)?._features["dataZoom"]?.onclick(view.ec.getModel()!, view.ec.api, "back")

        guard let restored = xDataZoomRange(view) else { XCTFail("no restored window"); return }
        XCTAssertEqual(restored[0], before[0], accuracy: 1.0, "back restores the origin start")
        XCTAssertEqual(restored[1], before[1], accuracy: 1.0, "back restores the origin end")
    }
}
