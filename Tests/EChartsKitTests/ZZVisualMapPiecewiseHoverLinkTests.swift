// Regression test — the PIECEWISE visualMap's HOVER-LINK (PiecewiseVisualMapView._enableHoverLink).
//
// Proves, HEADLESSLY through the REAL pointer stack (like ZZVisualMapPiecewiseSelectTests):
//   (1) HOVERING (mousemove over) a piece block HIGHLIGHTS every series data point whose value falls in
//       that piece's value range — the itemGroup's `mouseover` binding dispatches
//       {type:'highlight', batch: makeHighDownBatch(findTargetDataIndices(pieceIndex))}, which drives the
//       matching bars into the "emphasis" state, and
//   (2) moving the pointer OFF the piece (mouseout leg) dispatches the matching `downplay`, clearing it.
//
// It does NOT call dispatchAction('highlight') directly — the highlight MUST be produced by the injected
// pointer travelling through the live zr Handler + the itemGroup mouseover/mouseout bubbling.
//
// A BAR series is used (its bars are highDown dispatchers via BarView.updateStyle → toggleHoverEmphasis),
// so the emphasis lands observably on the matching data elements. (The heatmap-piecewise gallery is the
// motivating case, but heatmap cells are not yet emphasis dispatchers — an unrelated deferred gap.)
import XCTest
import ZRenderKit
@testable import EChartsKit

final class ZZVisualMapPiecewiseHoverLinkTests: XCTestCase {

    override func setUp() {
        super.setUp()
        ComponentModel.registerClass(SlimXAxisModel.self)
        ComponentModel.registerClass(SlimYAxisModel.self)
        ComponentModel.registerClass(BarSeriesModel.self)
    }

    /// A category-bar chart coloured by a piecewise (splitNumber) visualMap over the bar values.
    private func makeView(hoverLink: Any? = nil) -> EChartsView {
        let view = EChartsView(width: 480, height: 320)
        var visualMap: [String: Any] = [
            "type": "piecewise", "min": 0.0, "max": 60.0, "splitNumber": 3,
            "dimension": 1.0, "orient": "horizontal", "left": "center", "bottom": 0.0
        ]
        if let hoverLink = hoverLink { visualMap["hoverLink"] = hoverLink }
        view.setOption([
            "grid": ["left": 50.0, "top": 20.0, "width": 380.0, "height": 200.0] as [String: Any],
            "xAxis": ["type": "category", "data": ["A", "B", "C", "D", "E", "F"]] as [String: Any],
            "yAxis": ["type": "value"] as [String: Any],
            "visualMap": visualMap,
            "series": [["type": "bar", "data": [5.0, 25.0, 15.0, 45.0, 35.0, 55.0]] as [String: Any]]
        ])
        _ = view.zr.storage.getDisplayList(true)
        return view
    }

    private func piecewiseView(_ view: EChartsView) -> PiecewiseVisualMapView? {
        for cv in view.ec._componentsViews {
            if let p = cv as? PiecewiseVisualMapView { return p }
        }
        return nil
    }

    private func model(_ view: EChartsView) -> PiecewiseModel? {
        return view.ec.getModel()?.getComponent("visualMap", 0) as? PiecewiseModel
    }

    private func firstSeries(_ view: EChartsView) -> SeriesModel? {
        var found: SeriesModel?
        view.ec.getModel()?.eachSeries { s, _ in if found == nil { found = s } }
        return found
    }

    /// The set of data indices a hover over the given piece must highlight.
    private func targetIndices(_ mdl: PiecewiseModel, _ pieceIndex: Int) -> Set<Int> {
        return Set(mdl.findTargetDataIndices(Double(pieceIndex))
            .compactMap { $0["dataIndex"] as? [Double] }.flatMap { $0 }.map { Int($0) })
    }

    // ---- hovering a piece highlights its matching bars; mouseout clears ----
    func testHoveringPieceHighlightsMatchingBarsAndMouseoutClears() {
        let view = makeView()
        guard let pv = piecewiseView(view), let mdl = model(view), let series = firstSeries(view) else {
            XCTFail("a piecewise visualMap must produce a PiecewiseVisualMapView + PiecewiseModel"); return
        }
        let data = series.getData()

        // Find a rendered piece block whose value range contains at least one bar, but NOT all of them
        // (so we can prove selectivity: matching bars emphasise, non-matching bars do not).
        var targetSymbol: Path?
        var targetPieceIndex: Int?
        for entry in pv._viewPieceSymbolsForTest {
            let hits = targetIndices(mdl, entry.indexInModelPieceList)
            if !hits.isEmpty && hits.count < data.count() {
                targetSymbol = entry.symbol
                targetPieceIndex = entry.indexInModelPieceList
                break
            }
        }
        guard let symbol = targetSymbol, let pieceIndex = targetPieceIndex else {
            return XCTFail("no piece block with a strict subset of bars found")
        }

        let matching = targetIndices(mdl, pieceIndex)
        let nonMatching = Set(0..<data.count()).subtracting(matching)
        XCTAssertFalse(matching.isEmpty)
        XCTAssertFalse(nonMatching.isEmpty)

        func inEmphasis(_ i: Int) -> Bool {
            return data.getItemGraphicEl(i)?.currentStates.contains("emphasis") ?? false
        }

        // Sanity: every bar is a highDown dispatcher (so emphasis is observable) and none is highlighted.
        for i in 0..<data.count() {
            XCTAssertTrue(states.isHighDownDispatcher(data.getItemGraphicEl(i)!),
                          "bar \(i) must be a highDown dispatcher")
            XCTAssertFalse(inEmphasis(i), "bar \(i) must not be in emphasis before hover")
        }

        // ---- (1) Inject a mousemove OVER the piece block → the itemGroup mouseover leg fires. ----
        guard let bb = symbol.getBoundingRect() else { return XCTFail("piece symbol has no bounds") }
        let center = symbol.transformCoordToGlobal(bb.x + bb.width / 2, bb.y + bb.height / 2)
        // Start off the piece so the Handler registers a fresh mouseover transition onto it.
        view._injectPointerForTest(type: "mousemove", zrX: 5, zrY: 5)
        view._injectPointerForTest(type: "mousemove", zrX: center[0], zrY: center[1])

        for i in matching {
            XCTAssertTrue(inEmphasis(i),
                "hovering the piece must drive its matching bar \(i) into emphasis via the highlight batch")
        }
        for i in nonMatching {
            XCTAssertFalse(inEmphasis(i),
                "a bar \(i) outside the hovered piece's value range must NOT enter emphasis")
        }

        // ---- (2) Inject a mousemove OFF the piece → the mouseout leg dispatches downplay. ----
        view._injectPointerForTest(type: "mousemove", zrX: 5, zrY: 5)
        for i in matching {
            XCTAssertFalse(inEmphasis(i),
                "moving off the piece must clear the emphasis of its bar \(i) via the downplay batch")
        }
    }

    // ---- hoverLink:false disables the hover-link ----
    func testHoverLinkFalseDisablesHighlight() {
        let view = makeView(hoverLink: false)
        guard let pv = piecewiseView(view), let mdl = model(view), let series = firstSeries(view) else {
            return XCTFail("no view/model/series")
        }
        let data = series.getData()

        var targetSymbol: Path?
        var matching: Set<Int> = []
        for entry in pv._viewPieceSymbolsForTest {
            let idx = targetIndices(mdl, entry.indexInModelPieceList)
            if !idx.isEmpty { targetSymbol = entry.symbol; matching = idx; break }
        }
        guard let symbol = targetSymbol else { return XCTFail("no piece with bars") }

        guard let bb = symbol.getBoundingRect() else { return XCTFail("no bounds") }
        let center = symbol.transformCoordToGlobal(bb.x + bb.width / 2, bb.y + bb.height / 2)
        view._injectPointerForTest(type: "mousemove", zrX: 5, zrY: 5)
        view._injectPointerForTest(type: "mousemove", zrX: center[0], zrY: center[1])

        for i in matching {
            XCTAssertFalse(data.getItemGraphicEl(i)?.currentStates.contains("emphasis") ?? false,
                "with hoverLink:false, hovering a piece must NOT highlight bar \(i)")
        }
    }
}
