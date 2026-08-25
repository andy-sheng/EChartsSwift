// Phase 38 regression test — LIVE mouse-wheel → inside-dataZoom interactive zoom, proven HEADLESSLY
// through the REAL pointer stack.
//
// Unlike ZZDataZoomTests (which sets a static `dataZoom:[{start,end}]` window via setOption), this test
// injects a synthetic WHEEL event and proves the whole chain fires end to end:
//
//     EChartsView._injectWheelForTest(zrDelta, x, y)
//       -> zr.handler.mousewheel(ZRRawEvent{zrDelta,zrX,zrY})   (ZRenderKit Handler)
//       -> handler.dispatchToElement(...) -> zr-level "mousewheel" trigger
//       -> EChartsView._bindInsideZoom's listener
//       -> _handleInsideZoomWheel: RoamController scale + InsideZoomView.zoom range recompute
//       -> ec.dispatchAction({type:'dataZoom', batch:[{dataZoomId,start,end}]})
//       -> setRawRange -> update() -> dataZoomProcessor re-filters the series data
//
// It does NOT call dispatchAction('dataZoom') directly — the new window MUST be produced by the injected
// wheel travelling through the live Handler and the bound listener.
import XCTest
import ZRenderKit
@testable import EChartsKit

final class ZZInsideZoomTests: XCTestCase {

    override func setUp() {
        super.setUp()
        ComponentModel.registerClass(BarSeriesModel.self)
        ComponentModel.registerClass(LineSeriesModel.self)
    }

    /// 10 categories c0..c9, series data [0..9], grid + category xAxis + value yAxis, and an INSIDE
    /// dataZoom over the full [0, 100] window.
    private func makeZoomView() -> EChartsView {
        let cats: [Any] = (0..<10).map { "c\($0)" }
        let data: [Any] = (0..<10).map { Double($0) }
        let view = EChartsView(width: 400, height: 300)
        view.setOption([
            "grid": ["left": 50.0, "top": 20.0, "width": 300.0, "height": 200.0] as [String: Any],
            "xAxis": ["type": "category", "data": cats] as [String: Any],
            "yAxis": ["type": "value"] as [String: Any],
            "series": [["type": "bar", "data": data] as [String: Any]],
            "dataZoom": [["type": "inside", "start": 0, "end": 100] as [String: Any]]
        ])
        // Flatten the display list so the Handler can hit-test / dispatch over the echarts elements.
        _ = view.zr.storage.getDisplayList(true)
        return view
    }

    private func renderedCount(_ view: EChartsView) -> Int {
        return view.ec.getModel()?.getSeriesByIndex(0)?.getData().count() ?? -1
    }

    private func percentRange(_ view: EChartsView) -> [Double]? {
        return (view.ec.getModel()?.getComponent("dataZoom", 0) as? InsideZoomModel)?.getPercentRange()
    }

    private func namedLine(_ view: EChartsView) -> ECPolyline? {
        var found: ECPolyline?
        _ = view.ec.getRoot().traverse { el in
            if found == nil, let line = el as? ECPolyline, line.name == "line" {
                found = line
            }
            return false
        }
        return found
    }

    /// Upstream `roams.ts` wraps inside-dataZoom dispatch in a fix-rate throttle (100ms by default).
    /// A rapid burst therefore has one immediate update and one trailing update carrying the final
    /// accumulated `InsideZoomView.range`; wait for that trailing action before reading model data.
    private func waitForInsideZoomThrottle() {
        let trailing = expectation(description: "inside-dataZoom trailing throttled dispatch")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) { trailing.fulfill() }
        wait(for: [trailing], timeout: 1.0)
    }

    // Wheel-zoom IN over the grid center must SHRINK the rendered data window (< 10) while keeping data.
    func testWheelZoomInShrinksDataWindow() {
        let view = makeZoomView()

        let initialCount = renderedCount(view)
        XCTAssertEqual(initialCount, 10, "the full [0,100] window must render all 10 categories initially")

        let initialRange = percentRange(view)
        XCTAssertEqual(initialRange?[0] ?? -1, 0, accuracy: 1e-6, "initial window start must be 0%")
        XCTAssertEqual(initialRange?[1] ?? -1, 100, accuracy: 1e-6, "initial window end must be 100%")

        // Grid is left:50 top:20 width:300 height:200 → center = (200, 120).
        let cx = 50.0 + 300.0 / 2
        let cy = 20.0 + 200.0 / 2

        // Zoom IN a few times (zrDelta > 0). One tick is a modest 1.1× zoom, so repeat to decisively
        // shrink below the full 10 categories.
        for _ in 0..<5 {
            view._injectWheelForTest(zrDelta: 1, zrX: cx, zrY: cy)
        }
        waitForInsideZoomThrottle()

        let zoomedCount = renderedCount(view)
        print("INSIDE-ZOOM wheel-in: rendered count \(initialCount) -> \(zoomedCount)")
        XCTAssertLessThan(zoomedCount, 10, "wheel zoom-in must shrink the data window below the full 10")
        XCTAssertGreaterThan(zoomedCount, 0, "wheel zoom-in must keep at least one datum")

        // Window zoomed around the CENTER anchor → start moved up from 0, end moved down from 100.
        let zoomedRange = percentRange(view)
        XCTAssertNotNil(zoomedRange)
        XCTAssertGreaterThan(zoomedRange![0], 0, "zoom-in around center must move start up from 0%")
        XCTAssertLessThan(zoomedRange![1], 100, "zoom-in around center must move end down from 100%")
    }

    // Wheel-zoom OUT (zrDelta < 0) after a zoom-in must GROW the window back toward the full 10.
    func testWheelZoomOutGrowsBack() {
        let view = makeZoomView()
        let cx = 50.0 + 300.0 / 2
        let cy = 20.0 + 200.0 / 2

        // First zoom in decisively.
        for _ in 0..<6 { view._injectWheelForTest(zrDelta: 1, zrX: cx, zrY: cy) }
        waitForInsideZoomThrottle()
        let zoomedInCount = renderedCount(view)
        XCTAssertLessThan(zoomedInCount, 10, "precondition: zoom-in shrank the window")

        // Then zoom out MORE times than we zoomed in — the window should widen back toward full.
        for _ in 0..<12 { view._injectWheelForTest(zrDelta: -1, zrX: cx, zrY: cy) }
        waitForInsideZoomThrottle()
        let zoomedOutCount = renderedCount(view)
        print("INSIDE-ZOOM wheel-out: rendered count \(zoomedInCount) -> \(zoomedOutCount)")
        XCTAssertGreaterThan(zoomedOutCount, zoomedInCount,
                             "wheel zoom-out must grow the data window back")
        XCTAssertEqual(zoomedOutCount, 10, "enough zoom-out must restore the full 10-category window")
    }

    // A wheel event whose cursor is OUTSIDE the grid must NOT zoom (containPoint gate).
    func testWheelOutsideGridDoesNotZoom() {
        let view = makeZoomView()
        // (1, 1) is inside the 400×300 canvas but well outside the grid (left:50, top:20).
        for _ in 0..<5 { view._injectWheelForTest(zrDelta: 1, zrX: 1, zrY: 1) }
        XCTAssertEqual(renderedCount(view), 10, "a wheel outside the coord system must not change the window")
        let r = percentRange(view)
        XCTAssertEqual(r?[0] ?? -1, 0, accuracy: 1e-6)
        XCTAssertEqual(r?[1] ?? -1, 100, accuracy: 1e-6)
    }

    // Upstream `roams.dispatchAction` attaches
    // `animation: {easing: 'cubicOut', duration: 100}` to every inside-dataZoom action. The payload
    // override must reach `basicTransition.getAnimationConfig`, superseding this option's deliberately
    // different 500ms update duration.
    func testWheelZoomUsesUpstreamRealtimeAnimationPayload() {
        let cats: [Any] = (0..<12).map { "c\($0)" }
        let data: [Any] = [12.0, 18.0, 15.0, 24.0, 20.0, 31.0, 27.0, 36.0, 30.0, 42.0, 37.0, 48.0]
        let view = EChartsView(width: 400, height: 300)
        view.setOption([
            "animation": true,
            "animationDuration": 0.0,
            "animationDurationUpdate": 500.0,
            "animationEasingUpdate": "linear",
            "grid": ["left": 50.0, "top": 20.0, "width": 300.0, "height": 200.0] as [String: Any],
            "xAxis": ["type": "category", "data": cats] as [String: Any],
            "yAxis": ["type": "value"] as [String: Any],
            "series": [["type": "line", "data": data] as [String: Any]],
            "dataZoom": [["type": "inside", "start": 0.0, "end": 100.0] as [String: Any]]
        ])
        _ = view.zr.storage.getDisplayList(true)
        _ = view.ec.getRoot().traverse { el in
            _ = el.stopAnimation(nil)
            return false
        }

        view._injectWheelForTest(zrDelta: 1, zrX: 200, zrY: 120)

        guard let line = namedLine(view),
              let animator = line.animators.first(where: { $0.getTrack("points") != nil }),
              let clip = animator.getClip()
        else {
            return XCTFail("wheel zoom must schedule the line update animation")
        }
        if case .named(let name)? = clip.easing {
            XCTAssertEqual(name, "cubicOut", "inside-dataZoom must use the upstream realtime easing")
        }
        else {
            XCTFail("inside-dataZoom must carry the named cubicOut easing")
        }
        XCTAssertTrue(
            clip.sampleForDeterministicRendering(at: 100),
            "inside-dataZoom update animation must finish at the upstream 100ms duration, not 500ms"
        )
    }

    // Upstream creates one fix-rate throttled dispatch per coordinate system, while
    // `InsideZoomView.range` still advances for every wheel event. Rapid input therefore produces one
    // immediate action plus one trailing action carrying the fully accumulated range.
    func testRapidWheelZoomThrottlesDispatchWithoutLosingRange() {
        let cats: [Any] = (0..<20).map { "c\($0)" }
        let data: [Any] = (0..<20).map { Double($0) }
        let view = EChartsView(width: 400, height: 300)
        view.setOption([
            "animation": true,
            "animationDurationUpdate": 500.0,
            "grid": ["left": 50.0, "top": 20.0, "width": 300.0, "height": 200.0] as [String: Any],
            "xAxis": ["type": "category", "data": cats] as [String: Any],
            "yAxis": ["type": "value"] as [String: Any],
            "series": [["type": "bar", "data": data] as [String: Any]],
            "dataZoom": [[
                "type": "inside", "start": 0.0, "end": 100.0, "throttle": 100.0
            ] as [String: Any]]
        ])
        _ = view.zr.storage.getDisplayList(true)

        var dataZoomEvents = 0
        _ = view.on("datazoom") { _ in dataZoomEvents += 1 }

        for _ in 0..<5 {
            view._injectWheelForTest(zrDelta: 1, zrX: 200, zrY: 120)
        }

        XCTAssertEqual(dataZoomEvents, 1, "fix-rate throttle must dispatch the first wheel synchronously")

        let trailing = expectation(description: "trailing throttled dataZoom dispatch")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) {
            XCTAssertEqual(dataZoomEvents, 2, "rapid wheels must coalesce into one trailing dispatch")
            guard let range = self.percentRange(view) else {
                XCTFail("inside-dataZoom range disappeared")
                trailing.fulfill()
                return
            }
            let expectedSpan = 100.0 / pow(1.1, 5.0)
            XCTAssertEqual(range[0], (100.0 - expectedSpan) / 2, accuracy: 1e-6)
            XCTAssertEqual(range[1], (100.0 + expectedSpan) / 2, accuracy: 1e-6)
            trailing.fulfill()
        }
        wait(for: [trailing], timeout: 1.0)
    }
}
