// Timeline component regression test — the bottom playhead + the baseOption/options[currentIndex] merge.
//
// Proves (a) the PREPROCESSOR/MERGE is load-bearing: a `{ baseOption, options:[...], timeline:{...} }`
//   option resolves the CURRENT INDEX merged over baseOption (title switches to options[currentIndex]);
//   and (b) the SliderTimelineView RENDERS the STATIC timeline: the axis line, one tick symbol per
//   option index, the current-index checkpoint symbol, and the prev/next/play control buttons.
// Play AUTO-ADVANCE is DEFERRED (needs the live host) — not covered here.
import XCTest
import ZRenderKit
@testable import EChartsKit

final class ZZTimelineTests: XCTestCase {

    private func makeTimelineChart(currentIndex: Int) -> EChartsView {
        let view = EChartsView(width: 500, height: 360)
        view.setOption([
            "baseOption": [
                "title": ["text": "base", "left": "center"] as [String: Any],
                "timeline": [
                    "axisType": "value",
                    "currentIndex": currentIndex,
                    "bottom": 0.0,
                    "data": [0.0, 1.0, 2.0]
                ] as [String: Any]
            ] as [String: Any],
            "options": [
                ["title": ["text": "A"] as [String: Any]] as [String: Any],
                ["title": ["text": "B"] as [String: Any]] as [String: Any],
                ["title": ["text": "C"] as [String: Any]] as [String: Any]
            ]
        ])
        return view
    }

    private func timelineView(_ view: EChartsView) -> SliderTimelineView? {
        for cv in view.ec._componentsViews {
            if let s = cv as? SliderTimelineView { return s }
        }
        return nil
    }

    // ---- (1) the baseOption + options[currentIndex] merge resolves the current snapshot ----
    func testPreprocessorMergesCurrentIndexOption() {
        // currentIndex 1 → options[1] = { title: { text: "B" } } merged over baseOption.
        let view = makeTimelineChart(currentIndex: 1)
        guard let ecModel = view.ec.getModel() else { XCTFail("no ecModel"); return }

        let title = ecModel.getComponent("title", 0)
        XCTAssertNotNil(title, "the merged baseOption must carry the title component")
        XCTAssertEqual(title?.get("text") as? String, "B",
                       "options[currentIndex=1].title.text ('B') must be merged over baseOption ('base')")

        // The timeline model exists and reports the current index.
        let timeline = ecModel.getComponent("timeline", 0) as? TimelineModel
        XCTAssertNotNil(timeline, "a timeline component must be instantiated")
        XCTAssertEqual(timeline?.getCurrentIndex(), 1, "currentIndex must be 1")
        XCTAssertEqual(timeline?.getData().count(), 3, "the timeline has 3 option snapshots")
    }

    // A different current index resolves a different snapshot (proves the index is truly read).
    func testDifferentCurrentIndexResolvesDifferentSnapshot() {
        let view = makeTimelineChart(currentIndex: 2)
        let title = view.ec.getModel()?.getComponent("title", 0)
        XCTAssertEqual(title?.get("text") as? String, "C",
                       "currentIndex=2 must resolve options[2].title.text ('C')")
    }

    // ---- (2) the SliderTimelineView renders the static timeline (axis + ticks + controls + pointer) ----
    func testTimelineAxisAndControlsRender() {
        let view = makeTimelineChart(currentIndex: 1)
        guard let s = timelineView(view) else {
            XCTFail("a timeline option must produce a rendered SliderTimelineView"); return
        }

        // The axis was built.
        XCTAssertNotNil(s._axis, "the timeline axis must be built")

        // One tick symbol per option index (3).
        XCTAssertEqual(s._tickSymbols.count, 3, "one tick symbol per option index (3) — got \(s._tickSymbols.count)")

        // Axis labels (3).
        XCTAssertEqual(s._tickLabels.count, 3, "one axis label per option index (3) — got \(s._tickLabels.count)")

        // The current-index checkpoint pointer was created.
        XCTAssertNotNil(s._currentPointer, "the current-index checkpoint symbol must render")

        // The axis line + progress line are in the main group.
        XCTAssertNotNil(s._progressLine, "the progress line must render")
        let mainChildren = s._mainGroup.children()
        let lineCount = mainChildren.filter { $0 is Line }.count
        XCTAssertGreaterThanOrEqual(lineCount, 2, "the axis line + progress line must be present (got \(lineCount))")

        // The control buttons (play + prev + next = 3 icon paths) render into the main group.
        // Controls are SVGPath icons (built via makePath); the tick/pointer symbols are ECSymbol paths.
        // Count Path children that are NOT tick symbols and NOT the pointer → the 3 control icons.
        let tickSet = Set(s._tickSymbols.map { ObjectIdentifier($0) })
        let pointerId = s._currentPointer.map { ObjectIdentifier($0) }
        var controlCount = 0
        for child in mainChildren {
            if child is Line { continue }   // Line is a Path subclass — the axis + progress lines.
            guard let p = child as? Path else { continue }
            let oid = ObjectIdentifier(p)
            if tickSet.contains(oid) { continue }
            if oid == pointerId { continue }
            controlCount += 1
        }
        XCTAssertEqual(controlCount, 3, "prev + next + play control buttons must render (got \(controlCount))")
    }

    // The current pointer sits at the current-index coordinate (index 1 → the middle of the axis).
    func testCurrentPointerAtCurrentIndexCoord() {
        let view = makeTimelineChart(currentIndex: 1)
        guard let s = timelineView(view), let pointer = s._currentPointer else {
            XCTFail("no timeline pointer"); return
        }
        let axisExtent = s._axis.getExtent()      // [xLeft, xRight] in main-group coords
        let mid = (axisExtent[0] + axisExtent[1]) / 2
        // data value 1 (of 0..2) maps to the axis midpoint.
        XCTAssertEqual(pointer.x, mid, accuracy: 1.0,
                       "the checkpoint at currentIndex=1 (value 1 of 0..2) must sit at the axis midpoint")
    }

    func testVerticalCategoryTimelineUsesLabelHeightForAutoInterval() {
        let view = EChartsView(width: 640, height: 420)
        view.setOption([
            "baseOption": [
                "timeline": [
                    "axisType": "category",
                    "orient": "vertical",
                    "top": "center",
                    "right": 50.0,
                    "height": 300.0,
                    "width": 10.0,
                    "label": ["formatter": "step {value}", "position": 10.0] as [String: Any],
                    "data": (0..<6).map(String.init)
                ] as [String: Any]
            ] as [String: Any],
            "options": (0..<6).map { _ in [String: Any]() }
        ])

        guard let timeline = timelineView(view) else {
            XCTFail("vertical timeline must render")
            return
        }
        XCTAssertEqual(timeline._tickLabels.count, 6,
                       "50pt vertical spacing fits every one-line step label; width must not thin them")
    }
}
