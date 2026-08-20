// END-TO-END RENDER TEST for the Phase-25 MATRIX coordinate system (the 8th coord system) + its component
// view. Drives ECharts with a matrix option (a 3-column x 2-row table with header labels + body cells)
// and asserts the matrix BACKDROP reaches the ZRenderKit scene graph: the x/y header cell Rects + their
// text labels (ZRText), the body intersection cell Rects, plus the outer border/background Rects. Also
// guards the coord-sys wiring: CoordinateSystemManager.register("matrix", ...) → Matrix.create builds the
// coord, matrixModel.coordinateSystem is set, MatrixView reads its cell geometry (Matrix.getRect /
// Matrix.dataToLayout) back. Without any of these the table would render empty.
import XCTest
import ZRenderKit
@testable import EChartsKit

final class MatrixRenderTests: XCTestCase {

    private func makeOption() -> [String: Any] {
        return [
            "matrix": [
                "left": 40.0, "top": 40.0, "right": 40.0, "bottom": 40.0,
                "x": ["data": ["Jan", "Feb", "Mar"] as [Any]] as [String: Any],
                "y": ["data": ["North", "South"] as [Any]] as [String: Any],
                "body": [
                    "data": [
                        ["coord": [0, 0] as [Any], "value": "12"] as [String: Any],
                        ["coord": [1, 0] as [Any], "value": "34"] as [String: Any],
                        ["coord": [2, 0] as [Any], "value": "56"] as [String: Any],
                        ["coord": [0, 1] as [Any], "value": "78"] as [String: Any],
                        ["coord": [1, 1] as [Any], "value": "90"] as [String: Any],
                        ["coord": [2, 1] as [Any], "value": "21"] as [String: Any]
                    ] as [Any]
                ] as [String: Any]
            ] as [String: Any]
        ]
    }

    func testMatrixRendersTableCellsAndHeaderLabels() {
        let ec = ECharts(width: 520, height: 320)
        ec.setOption(makeOption())

        var rects = 0
        var textStrings: [String] = []
        var seen = Set<ObjectIdentifier>()
        func visit(_ el: Element?) {
            guard let el, seen.insert(ObjectIdentifier(el)).inserted else { return }
            if el is ZRenderKit.Rect { rects += 1 }
            else if let t = el as? ZRenderKit.ZRText {
                if let s = t.textStyle?.text { textStrings.append(s) }
            }
            visit(el.getClipPath())
            visit(el.getTextContent())
            visit(el.getTextGuideLine())
            if let group = el as? Group {
                for child in group.children() { visit(child) }
            }
        }
        visit(ec.getRoot())

        // 3 x-header cells + 2 y-header cells + 6 body cells = 11 table cells, each a Rect; plus the
        //   background + outer-border Rects. So the scene must carry strictly MORE Rects than the 11 cells.
        let headerPlusBodyCells = 3 + 2 + 6
        XCTAssertGreaterThan(rects, headerPlusBodyCells,
            "matrix backdrop → a Rect per header + body cell (\(headerPlusBodyCells)) plus bg/border")

        // Header cell text labels (the category values) must reach the scene graph as ZRText.
        for header in ["Jan", "Feb", "Mar", "North", "South"] {
            XCTAssertTrue(textStrings.contains(header), "matrix header label '\(header)' rendered as ZRText")
        }
    }

    func testMatrixGeometryViaDataToLayout() {
        let ec = ECharts(width: 520, height: 320)
        ec.setOption(makeOption())

        // Reach the Matrix coord instance via the matrix component model (proves the coord-sys wiring).
        guard let matrixModel = ec.getModel()?.getComponent("matrix", 0) as? MatrixModel,
              let matrix = matrixModel.coordinateSystem as? Matrix else {
            return XCTFail("matrix component model / coordinateSystem (Matrix) not wired")
        }

        let viewRect = matrix.getRect()
        let eps = 1e-6

        // dataToLayout([xLocator, yLocator]) → the body intersection cell rect. Resolve three known cells.
        let c00 = matrix.dataToLayout([0.0, 0.0]).rect
        let c20 = matrix.dataToLayout([2.0, 0.0]).rect
        let c01 = matrix.dataToLayout([0.0, 1.0]).rect
        guard let r00 = c00, let r20 = c20, let r01 = c01 else {
            return XCTFail("Matrix.dataToLayout returned no rect for a known body cell")
        }

        // Each cell must be a valid, non-degenerate rect lying WITHIN the matrix view rect.
        for r in [r00, r20, r01] {
            XCTAssertFalse(r.x.isNaN || r.y.isNaN || r.width.isNaN || r.height.isNaN, "cell rect is finite")
            XCTAssertGreaterThan(r.width, 0, "cell width > 0")
            XCTAssertGreaterThan(r.height, 0, "cell height > 0")
            XCTAssertGreaterThanOrEqual(r.x, viewRect.x - eps)
            XCTAssertLessThanOrEqual(r.x + r.width, viewRect.x + viewRect.width + eps)
            XCTAssertGreaterThanOrEqual(r.y, viewRect.y - eps)
            XCTAssertLessThanOrEqual(r.y + r.height, viewRect.y + viewRect.height + eps)
        }

        // Column 2 (Mar) sits to the RIGHT of column 0 (Jan); row 1 (South) sits BELOW row 0 (North).
        XCTAssertGreaterThan(r20.x, r00.x, "column 2 cell is right of column 0 cell")
        XCTAssertGreaterThan(r01.y, r00.y, "row 1 cell is below row 0 cell")
    }
}
