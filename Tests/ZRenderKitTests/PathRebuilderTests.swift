import XCTest
@testable import ZRenderKit

/// Smoke test: confirms the renderer-seam protocol is conformable and that a recorder
/// receives commands in order. Real PathProxy.rebuildPath tests land once PathProxy is
/// ported. PORT-TODO: add golden-path replay tests against upstream fixtures.
final class PathRebuilderTests: XCTestCase {

    /// Minimal in-memory PathRebuilder that records the ops it receives.
    final class Recorder: PathRebuilder {
        var ops: [String] = []
        func moveTo(_ x: Double, _ y: Double) { ops.append("M \(x) \(y)") }
        func lineTo(_ x: Double, _ y: Double) { ops.append("L \(x) \(y)") }
        func bezierCurveTo(_ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double, _ x3: Double, _ y3: Double) {
            ops.append("C \(x1) \(y1) \(x2) \(y2) \(x3) \(y3)")
        }
        func quadraticCurveTo(_ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double) {
            ops.append("Q \(x1) \(y1) \(x2) \(y2)")
        }
        func arc(_ cx: Double, _ cy: Double, _ r: Double, _ startAngle: Double, _ endAngle: Double, _ anticlockwise: Bool) {
            ops.append("A \(cx) \(cy) \(r)")
        }
        func ellipse(_ cx: Double, _ cy: Double, _ rx: Double, _ ry: Double, _ rotation: Double, _ startAngle: Double, _ endAngle: Double, _ anticlockwise: Bool) {
            ops.append("E \(cx) \(cy) \(rx) \(ry)")
        }
        func rect(_ x: Double, _ y: Double, _ w: Double, _ h: Double) { ops.append("R \(x) \(y) \(w) \(h)") }
        func closePath() { ops.append("Z") }
    }

    func testRecorderConformsAndOrders() {
        let r: PathRebuilder = Recorder()
        r.moveTo(0, 0)
        r.lineTo(10, 0)
        r.closePath()
        XCTAssertEqual((r as! Recorder).ops, ["M 0.0 0.0", "L 10.0 0.0", "Z"])
    }
}
