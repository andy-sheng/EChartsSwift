// Regression test — the PIECEWISE visualMap's coloured piece blocks act as a SELECTOR
// (PiecewiseVisualMapView._onItemClick → dispatchAction('selectDataRange')).
//
// Proves, HEADLESSLY through the REAL pointer stack (like ZZVisualMapContinuousInteractionTests):
//   (1) clicking a piece block TOGGLES that value range off in the model (option.selected[key] = false),
//       which flips the model's getValueState for a value in that range from 'inRange' -> 'outOfRange', and
//   (2) the visualMap VISUAL stage re-runs (the action's update:'update') and re-encodes the heatmap
//       cells, so the cells whose value falls in the toggled-off range change their rendered fill while
//       the cells in the still-selected ranges keep theirs.
//
// The click is injected through the live zr Handler (mousedown → mouseup) over a piece block's item
// symbol; the event bubbles to the itemGroup's click handler (PiecewiseVisualMapView._onItemClick).
import XCTest
import ZRenderKit
@testable import EChartsKit

final class ZZVisualMapPiecewiseSelectTests: XCTestCase {

    override func setUp() {
        super.setUp()
        ComponentModel.registerClass(EChartsXAxisModel.self)
        ComponentModel.registerClass(EChartsYAxisModel.self)
        ComponentModel.registerClass(HeatmapSeriesModel.self)
    }

    /// The gallery `heatmap-piecewise` option — a heatmap coloured by a piecewise (splitNumber) visualMap.
    private func makeView() -> EChartsView {
        let view = EChartsView(width: 480, height: 320)
        view.setOption([
            "grid": ["left": 50.0, "top": 20.0, "width": 380.0, "height": 200.0] as [String: Any],
            "xAxis": ["type": "category", "data": (0..<8).map { "c\($0)" }] as [String: Any],
            "yAxis": ["type": "category", "data": (0..<5).map { "r\($0)" }] as [String: Any],
            "visualMap": ["type": "piecewise", "min": 0.0, "max": 10.0, "splitNumber": 5,
                          "orient": "horizontal", "left": "center", "bottom": 0.0] as [String: Any],
            "series": [["type": "heatmap", "data": {
                var d: [[Double]] = []
                for x in 0..<8 { for y in 0..<5 { d.append([Double(x), Double(y), Double((x * 3 + y * 2) % 11)]) } }
                return d
            }()] as [String: Any]]
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

    /// Read every heatmap cell's rendered fill string, indexed by data index.
    private func cellFills(_ view: EChartsView) -> [String] {
        guard let series = firstSeries(view) else { return [] }
        let data = series.getData()
        var fills: [String] = []
        for i in 0..<data.count() {
            if let rect = data.getItemGraphicEl(i) as? Rect,
               let fill = rect.pathStyle?.fill, case let .string(s) = fill {
                fills.append(s)
            } else {
                fills.append("")
            }
        }
        return fills
    }

    // ---- (1) + (2): clicking a piece block toggles it off and re-colours its cells ----
    func testClickingPieceTogglesRangeOffAndDimsCells() {
        let view = makeView()
        guard let pv = piecewiseView(view), let mdl = model(view) else {
            XCTFail("a piecewise visualMap must produce a PiecewiseVisualMapView + PiecewiseModel"); return
        }

        // Pick a rendered piece block that has at least one data cell inside it.
        guard let series = firstSeries(view) else { return XCTFail("no series") }
        let data = series.getData()
        let valueDimIdx = mdl.getDataDimensionIndex(data)!
        let valueDim = data.getDimension(Double(valueDimIdx))
        var cellValues: [Double] = []
        for i in 0..<data.count() { cellValues.append((data.get(valueDim, i) as? Double) ?? Double.nan) }

        // Find a piece symbol whose piece contains at least one cell value.
        let pieceList = mdl.getPieceList()
        var targetSymbol: Path?
        var targetKey: String?
        var cellsInTarget: [Int] = []
        for entry in pv._viewPieceSymbolsForTest {
            let piece = pieceList[entry.indexInModelPieceList]
            let key = mdl.getSelectedMapKey(piece)
            let inThis = (0..<cellValues.count).filter { i in
                !cellValues[i].isNaN && mdl.getSelectedMapKey(pieceForValue(mdl, cellValues[i])) == key
            }
            if !inThis.isEmpty {
                targetSymbol = entry.symbol
                targetKey = key
                cellsInTarget = inThis
                break
            }
        }
        guard let symbol = targetSymbol, let key = targetKey else {
            return XCTFail("no piece block with data cells found")
        }

        // Before the click: every piece is selected → cells inside the target piece are 'inRange'.
        XCTAssertTrue((mdl.option as! [String: Any])["selected"] is [String: Any])
        for i in cellsInTarget {
            XCTAssertEqual(mdl.getValueState(cellValues[i]), "inRange",
                           "before click, a cell in the target piece must be inRange")
        }
        let fillsBefore = cellFills(view)

        // Inject a real pointer click over the piece block's item symbol (its bounding-box centre,
        // run through the full transform chain to a global pixel).
        guard let bb = symbol.getBoundingRect() else { return XCTFail("piece symbol has no bounds") }
        let center = symbol.transformCoordToGlobal(bb.x + bb.width / 2, bb.y + bb.height / 2)
        view._injectPointerForTest(type: "mousemove", zrX: center[0], zrY: center[1])
        view._injectPointerForTest(type: "mousedown", zrX: center[0], zrY: center[1])
        view._injectPointerForTest(type: "mouseup", zrX: center[0], zrY: center[1])
        view._injectPointerForTest(type: "click", zrX: center[0], zrY: center[1])

        // (1) The model toggled the clicked piece OFF.
        let selected = (model(view)?.option as? [String: Any])?["selected"] as? [String: Any] ?? [:]
        XCTAssertEqual(selected[key] as? Bool, false,
                       "clicking a piece must toggle its selected flag to false — selected=\(selected)")

        // The clicked piece's cells are now 'outOfRange'; other pieces stay 'inRange'.
        let mdlAfter = model(view)!
        let seriesAfter = firstSeries(view)!
        let dataAfter = seriesAfter.getData()
        var valuesAfter: [Double] = []
        for i in 0..<dataAfter.count() { valuesAfter.append((dataAfter.get(valueDim, i) as? Double) ?? Double.nan) }
        for i in 0..<valuesAfter.count where !valuesAfter[i].isNaN {
            let expected = mdlAfter.getSelectedMapKey(pieceForValue(mdlAfter, valuesAfter[i])) == key
                ? "outOfRange" : "inRange"
            XCTAssertEqual(mdlAfter.getValueState(valuesAfter[i]), expected,
                           "value \(valuesAfter[i]) valueState")
        }

        // (2) The visual stage re-ran: at least one cell in the toggled-off piece changed its fill.
        let fillsAfter = cellFills(view)
        XCTAssertEqual(fillsAfter.count, fillsBefore.count, "cell count is stable across the toggle")
        var changed = 0
        for i in 0..<Swift.min(fillsBefore.count, fillsAfter.count) where fillsBefore[i] != fillsAfter[i] {
            changed += 1
        }
        XCTAssertGreaterThan(changed, 0,
            "toggling a piece off must re-encode (dim) the cells in that value range")
    }

    func testExternalVisualHarnessTargetsOwnedPiece() {
        let view = makeView()
        guard let mdl = model(view), let pv = piecewiseView(view),
              let entry = pv._viewPieceSymbolsForTest.first else {
            return XCTFail("piecewise visualMap did not render a selectable piece")
        }
        let piece = mdl.getPieceList()[entry.indexInModelPieceList]
        let key = mdl.getSelectedMapKey(piece)
        XCTAssertNotNil(view._injectPiecewiseVisualMapClickForTest(
            componentIndex: 0, pieceIndex: entry.indexInModelPieceList
        ))
        let selected = (model(view)?.option as? [String: Any])?["selected"] as? [String: Any]
        XCTAssertEqual(selected?[key] as? Bool, false)
    }

    // ---- headless dispatch parity: dispatching selectDataRange directly flips the same visual state ----
    func testDispatchSelectDataRangeMapsPieceToOutOfRange() {
        let view = makeView()
        guard let mdl = model(view) else { return XCTFail("no PiecewiseModel") }

        // Toggle the first piece off via a direct action (as the view's onclick would).
        let firstPiece = mdl.getPieceList()[0]
        let key = mdl.getSelectedMapKey(firstPiece)
        var selected = ((mdl.option as? [String: Any])?["selected"] as? [String: Any]) ?? [:]
        selected[key] = false

        var payload = Payload(type: "selectDataRange")
        payload.other["visualMapId"] = mdl.id
        payload.other["selected"] = selected
        view.ec.dispatchAction(payload)

        let after = model(view)!
        // A representative value inside the first piece is now outOfRange.
        let rep = after.getRepresentValue(after.getPieceList()[0]) as? Double ?? Double.nan
        XCTAssertEqual(after.getValueState(rep), "outOfRange",
                       "after dispatching selectDataRange, a value in the toggled piece must be outOfRange")
    }

    /// The model piece a value maps to (mirrors VisualMapping.findPieceIndex: close[0]=lower bound
    /// closed, close[1]=upper bound closed).
    private func pieceForValue(_ mdl: PiecewiseModel, _ v: Double) -> [String: Any] {
        for piece in mdl.getPieceList() {
            if let interval = piece["interval"] as? [Double], interval.count == 2 {
                let close = (piece["close"] as? [Double]) ?? [0, 0]
                let lo = interval[0], hi = interval[1]
                let geLo = close[0] != 0 ? v >= lo : v > lo
                let leHi = close[1] != 0 ? v <= hi : v < hi
                if geLo && leHi { return piece }
            }
        }
        return mdl.getPieceList().first ?? [:]
    }
}

extension ZZVisualMapPiecewiseSelectTests {
    // The outOfRange visual is the transparent default (visualDefault color 'inactive' = rgba(0,0,0,0)
    // + the ec2-compat opacity [0,0]), so a toggled-off piece's cells become fully transparent (hidden)
    // while the still-selected cells keep their gradient colour.
    func testToggledPieceCellsBecomeTransparent() {
        let view = makeView()
        guard let mdl = model(view), let series = firstSeries(view) else { return XCTFail("no model/series") }
        let data = series.getData()
        let valueDim = data.getDimension(Double(mdl.getDataDimensionIndex(data)!))
        var values: [Double] = []
        for i in 0..<data.count() { values.append((data.get(valueDim, i) as? Double) ?? Double.nan) }

        let firstPiece = mdl.getPieceList()[0]
        let key = mdl.getSelectedMapKey(firstPiece)
        var selected = ((mdl.option as? [String: Any])?["selected"] as? [String: Any]) ?? [:]
        selected[key] = false
        var payload = Payload(type: "selectDataRange")
        payload.other["visualMapId"] = mdl.id
        payload.other["selected"] = selected
        view.ec.dispatchAction(payload)

        let after = model(view)!
        let fills = cellFills(view)
        func isTransparent(_ s: String) -> Bool {
            return s == "rgba(0,0,0,0)" || s == "transparent" || s == "rgba(0, 0, 0, 0)"
        }
        var sawTransparentInPiece = false
        for i in 0..<fills.count where !values[i].isNaN {
            let inToggledPiece = after.getValueState(values[i]) == "outOfRange"
            if inToggledPiece {
                XCTAssertTrue(isTransparent(fills[i]),
                              "an outOfRange (toggled-off) cell must be transparent, got \(fills[i])")
                sawTransparentInPiece = true
            } else {
                XCTAssertFalse(isTransparent(fills[i]),
                               "a still-selected cell must keep its colour, got \(fills[i])")
            }
        }
        XCTAssertTrue(sawTransparentInPiece, "the toggled piece must contain at least one hidden cell")
    }
}
