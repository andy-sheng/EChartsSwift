import XCTest
@testable import ZRenderKit

// Regression: `color.liftColor` force-unwrapped `lift(s, -0.1)`, which returns nil for any string
// `color.parse` can't handle — e.g. the sankey/chord edge sentinel "source"/"target"/"gradient"
// that legitimately survives on a ribbon's STROKE. Hovering such an element crashed the demo app
// (createEmphasisDefaultState → liftZRColor → liftColor → SIGTRAP). Upstream `lift` returns
// undefined on a parse failure and the lift is simply skipped — mirror that by returning the
// input unchanged.
final class LiftColorSafetyTests: XCTestCase {
    func testLiftColorUnparseableStringDoesNotCrash() {
        for bad in ["source", "target", "gradient", "inherit", "", "not-a-color"] {
            let out = color.liftColor(.string(bad))
            if case let .string(s) = out {
                XCTAssertEqual(s, bad, "unparseable color must round-trip unchanged")
            } else {
                XCTFail("string in, string out")
            }
        }
    }

    private struct TestGradient: GradientObject {
        var id: Double?
        var type: String = "linear"
        var colorStops: [GradientColorStop]
        var global: Bool?
    }

    func testLiftColorGradientWithUnparseableStopDoesNotCrash() {
        let g = TestGradient(colorStops: [
            GradientColorStop(offset: 0, color: "source"),
            GradientColorStop(offset: 1, color: "#ff0000")
        ])
        let out = color.liftColor(.gradient(g))
        if case let .gradient(lifted) = out {
            XCTAssertEqual(lifted.colorStops.first?.color, "source",
                           "unparseable stop must survive unchanged")
            XCTAssertNotEqual(lifted.colorStops.last?.color, "#ff0000",
                              "parseable stop must still be lifted")
        } else {
            XCTFail("gradient in, gradient out")
        }
    }

    func testLiftColorStillLiftsValidColors() {
        let out = color.liftColor(.string("#ff0000"))
        if case let .string(s) = out {
            XCTAssertNotEqual(s, "#ff0000", "a valid color must be lifted (brightened)")
        } else {
            XCTFail("string in, string out")
        }
    }
}
