// END-TO-END RENDER TEST for the Phase-19 chord (circular flow) chart vertical: a Sector arc per node
// placed around a ring + a filled ribbon ChordPath per edge, laid out by the coordless chord
// circular-layout stage. Drives ECharts with a real chord option and asserts BOTH node arc Sectors
// (one per node) and edge ribbon Paths (one per edge) reach the ZRenderKit scene graph, plus a GEOMETRY
// guard: every node arc must sit inside the view rect and carry a positive radius (which is exactly what
// the chord circular layout must compute from center ['50%','50%'] / radius).
import XCTest
import ZRenderKit
@testable import EChartsKit

final class ChordRenderTests: XCTestCase {
    func testChordRendersNodeArcsAndEdgeRibbons() {
        let width = 460.0, height = 360.0
        let ec = ECharts(width: width, height: height)
        ec.setOption([
            "series": [["type": "chord",
                        "center": ["50%", "50%"],
                        "radius": ["60%", "70%"],
                        "padAngle": 3.0,
                        "data": [["name": "a"], ["name": "b"], ["name": "c"], ["name": "d"]],
                        "links": [["source": "a", "target": "b", "value": 5.0],
                                  ["source": "a", "target": "c", "value": 3.0],
                                  ["source": "b", "target": "c", "value": 4.0],
                                  ["source": "b", "target": "d", "value": 2.0],
                                  ["source": "c", "target": "d", "value": 6.0]]] as [String: Any]]
        ])

        var nodeArcs = 0
        var ribbons = 0
        var arcsInRect = 0
        _ = ec.getRoot().traverse { el in
            // Edge ribbons: ChordEdge is a custom Path subclass carrying a ChordPathShape.
            if let edge = el as? ChordEdge, edge.shape is ChordPathShape {
                ribbons += 1
            }
            // Node arcs: ChordPiece is a Sector subclass carrying a SectorShape.
            else if let piece = el as? ChordPiece, let shape = piece.shape as? SectorShape {
                nodeArcs += 1
                let inRect = shape.cx >= 0 && shape.cx <= width
                    && shape.cy >= 0 && shape.cy <= height && shape.r > 0
                if inRect { arcsInRect += 1 }
            }
            return false
        }

        // 4 nodes → 4 arc Sectors; 5 links → 5 ribbon Paths.
        XCTAssertEqual(nodeArcs, 4, "chord nodes → one arc Sector each")
        XCTAssertGreaterThan(ribbons, 0, "chord edges → ribbon ChordPaths")
        XCTAssertEqual(ribbons, 5, "chord edges → one ribbon Path each")

        // GEOMETRY GUARD: every node arc must be laid out inside the view rect with a positive radius.
        XCTAssertEqual(arcsInRect, nodeArcs, "every node arc must sit within the view rect (r > 0)")
    }

    func testInsideNodeLabelsPaintAboveChordArcs() {
        let ec = ECharts(width: 460, height: 360)
        ec.setOption([
            "series": [[
                "type": "chord",
                "radius": ["60%", "70%"],
                "data": [["name": "A"], ["name": "B"], ["name": "C"]],
                "links": [
                    ["source": "A", "target": "B", "value": 5.0],
                    ["source": "B", "target": "C", "value": 4.0],
                    ["source": "C", "target": "A", "value": 3.0]
                ],
                "label": [
                    "show": true,
                    "position": "inside",
                    "color": "#fff"
                ] as [String: Any]
            ] as [String: Any]]
        ])

        var pieces: [ChordPiece] = []
        _ = ec.getRoot().traverse { el in
            if let piece = el as? ChordPiece { pieces.append(piece) }
            return false
        }
        XCTAssertEqual(pieces.count, 3)
        XCTAssertEqual(Set(pieces.compactMap { $0.getTextContent()?.textStyle?.text }), Set(["A", "B", "C"]))
        for piece in pieces {
            guard let label = piece.getTextContent() else {
                XCTFail("each chord node should own an attached label")
                continue
            }
            XCTAssertFalse(label.ignore)
            XCTAssertGreaterThan(label.z2, piece.z2,
                "inside chord labels must paint above the opaque node arcs")
        }
    }
}
