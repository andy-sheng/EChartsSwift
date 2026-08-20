import XCTest
@testable import EChartsKit
@testable import ZRenderKit

// Regression: pie hover must ENLARGE the hovered sector — upstream PiePiece (PieView.ts:142-145)
// registers an emphasis state whose shape.r = layout.r + scaleSize (emphasis.scale default true,
// scaleSize default 5), so entering emphasis grows the outer radius and leaving restores it.
final class PieHoverScaleTests: XCTestCase {
    private func finishStateTransition(_ el: Element) {
        for animator in el.animators where animator.__fromStateTransition != nil {
            guard let clip = animator.getClip() else { continue }
            _ = clip.step(0, 0)
            if clip.step(300, 300) { clip.ondestroy() }
        }
    }

    private func midPoint(_ s: SectorShape) -> (x: Double, y: Double) {
        let a = (s.startAngle + s.endAngle) / 2
        let r = (s.r + s.r0) / 2
        return (s.cx + cos(a) * r, s.cy + sin(a) * r)
    }

    func testPieHoverGrowsRadiusAndRestores() {
        let v = EChartsView(width: 480, height: 360)
        v.setOption(["series": [["type": "pie", "radius": ["0%", "60%"],
                                 "data": [["name": "A", "value": 60] as [String: Any],
                                          ["name": "B", "value": 40]]] as [String: Any]]])
        _ = v.zr.storage.getDisplayList(true)
        let data = v.ec.getModel()!.getSeriesByIndex(0)!.getData()
        let s0 = data.getItemGraphicEl(0) as! Sector
        let normalR = (s0.shape as! SectorShape).r

        let p = midPoint(s0.shape as! SectorShape)
        v._injectPointerForTest(type: "mousemove", zrX: p.x, zrY: p.y)

        XCTAssertTrue(s0.currentStates.contains("emphasis"), "hover enters emphasis")
        finishStateTransition(s0)
        let hoverR = (s0.shape as! SectorShape).r
        XCTAssertEqual(hoverR, normalR + 5, accuracy: 1e-6,
                       "hover must grow the sector by the default emphasis.scaleSize 5 — normal r=\(normalR) hover r=\(hoverR)")

        // Explicit scaleSize + scale:false coverage.
        v._injectPointerForTest(type: "mousemove", zrX: 2, zrY: 2)
        finishStateTransition(s0)
        XCTAssertEqual((s0.shape as! SectorShape).r, normalR, accuracy: 1e-6,
                       "mouseout must restore the normal radius")
    }

    func testPieScaleFalseDisablesGrow() {
        let v = EChartsView(width: 480, height: 360)
        v.setOption(["series": [["type": "pie", "radius": ["0%", "60%"],
                                 "emphasis": ["scale": false],
                                 "data": [["name": "A", "value": 60] as [String: Any],
                                          ["name": "B", "value": 40]]] as [String: Any]]])
        _ = v.zr.storage.getDisplayList(true)
        let data = v.ec.getModel()!.getSeriesByIndex(0)!.getData()
        let s0 = data.getItemGraphicEl(0) as! Sector
        let normalR = (s0.shape as! SectorShape).r
        let p = midPoint(s0.shape as! SectorShape)
        v._injectPointerForTest(type: "mousemove", zrX: p.x, zrY: p.y)
        XCTAssertEqual((s0.shape as! SectorShape).r, normalR, accuracy: 1e-6,
                       "emphasis.scale:false must NOT grow the sector")
    }
}
