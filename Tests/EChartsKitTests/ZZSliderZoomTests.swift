// Phase 41 regression test — the on-screen dataZoom SLIDER widget (SliderZoomView).
//
// Proves (a) the slider RENDERS: after setOption with dataZoom:{type:"slider",start:20,end:60}, the
// SliderZoomView built its background/handles/filler band, and the selected window maps to ~20%–60%;
// and (b) a handle DRAG changes the window: calling the view's `_onDragMove` (the `drift` callback the
// live-zr Handler fires on a real drag) for the right handle shifts the range.
import XCTest
import ZRenderKit
@testable import EChartsKit

final class ZZSliderZoomTests: XCTestCase {

    override func setUp() {
        super.setUp()
        ComponentModel.registerClass(BarSeriesModel.self)
    }

    private func makeSliderChart() -> EChartsView {
        let view = EChartsView(width: 400, height: 320)
        view.setOption([
            "grid": ["left": 50.0, "top": 20.0, "width": 300.0, "height": 200.0] as [String: Any],
            "xAxis": ["type": "category", "data": ["a","b","c","d","e","f","g","h","i","j"]] as [String: Any],
            "yAxis": ["type": "value"] as [String: Any],
            "dataZoom": [["type": "slider", "start": 20, "end": 60] as [String: Any]],
            "series": [["type": "bar", "data": [1.0,2,3,4,5,6,7,8,9,10]] as [String: Any]]
        ])
        return view
    }

    private func sliderView(_ view: EChartsView) -> SliderZoomView? {
        for cv in view.ec._componentsViews {
            if let s = cv as? SliderZoomView { return s }
        }
        return nil
    }

    // ---- (1) the slider renders: background + two handles + the filler band at the 20–60% window ----
    func testSliderRendersWithWindowBand() {
        let view = makeSliderChart()
        guard let s = sliderView(view) else {
            XCTFail("a dataZoom:{type:'slider'} must produce a rendered SliderZoomView"); return
        }
        XCTAssertNotNil(s._displayables.filler, "the slider must render the selected-window filler band")
        XCTAssertNotNil(s._displayables.handles[0], "the slider must render handle 0")
        XCTAssertNotNil(s._displayables.handles[1], "the slider must render handle 1")

        // The percent window the slider is showing must be ~[20, 60].
        XCTAssertEqual(s._range[0], 20, accuracy: 1.0, "slider window start ~20% — got \(s._range)")
        XCTAssertEqual(s._range[1], 60, accuracy: 1.0, "slider window end ~60% — got \(s._range)")
    }

    // ---- (2) dragging the right handle changes the window (the drift callback the Handler fires) ----
    func testDragRightHandleWidensWindow() {
        let view = makeSliderChart()
        guard let s = sliderView(view) else { XCTFail("no SliderZoomView"); return }

        let before = s._range
        XCTAssertEqual(before[1], 60, accuracy: 1.0)

        // Drift the RIGHT handle (index 1) by a positive pixel delta along the (horizontal) slider —
        // exactly what the live-zr Handler's Draggable mixin calls on a real drag of that handle.
        s._onDragMove(.at(1), 40, 0, nil)

        XCTAssertGreaterThan(s._range[1], before[1] + 1,
                             "dragging the right handle right must move the window END up — got \(s._range)")
        // start unchanged (only the right handle moved).
        XCTAssertEqual(s._range[0], before[0], accuracy: 1.5, "left handle should be ~unchanged")
    }
}
