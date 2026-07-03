// COORD-LEVEL oracle test for the Phase-12 radar coordinate system (Radar + IndicatorAxis), the
// first non-cartesian coord system. Builds a GlobalModel from a raw radar option and runs
// `Radar.create` directly (mirrors CartesianCoordTests). Pins the angle math — specifically the
// default `startAngle: 90` → axis[0].angle == π/2 (axis 0 points straight up). This guards the
// CRITICAL Int-vs-Double option-read fix: `startAngle` is stored as a bare Int literal in
// defaultOption, and a `get(...) as? Double` returns nil on an Int, which would silently rotate the
// entire radar 90°. axis[0] is chosen because idx==0 makes the clockwise `sign` irrelevant, so the
// assertion isolates startAngle alone. See PORT_STATUS §43.

import XCTest
@testable import EChartsKit

private final class RadarTestEChartsInstance: EChartsType {}
private final class RadarTestExtensionAPI: ExtensionAPI {
    private let w: Double
    private let h: Double
    init(width: Double, height: Double) {
        self.w = width; self.h = height
        super.init(ecInstance: RadarTestEChartsInstance())
    }
    override func getWidth() -> Double { w }
    override func getHeight() -> Double { h }
}

final class RadarCoordTests: XCTestCase {

    override func setUp() {
        super.setUp()
        // ComponentModel.registerClass is a GLOBAL registry — safe to re-register (idempotent).
        ComponentModel.registerClass(RadarModel.self)
    }

    private func buildRadarModel(width: Double = 460, height: Double = 360) -> (GlobalModel, ExtensionAPI) {
        let api = RadarTestExtensionAPI(width: width, height: height)
        let ecModel = GlobalModel()
        let om = OptionManager(api)
        ecModel.`init`(nil, nil, nil, [String: Any](), [String: Any](), om)
        ecModel.setOption([
            "radar": [
                "center": ["50%", "50%"],
                "radius": "70%",
                // NOTE: no explicit startAngle → the default 90 (an Int literal) must still yield π/2.
                "indicator": [
                    ["name": "A", "max": 100.0],
                    ["name": "B", "max": 100.0],
                    ["name": "C", "max": 100.0],
                    ["name": "D", "max": 100.0]
                ]
            ] as [String: Any]
        ], nil, [])
        return (ecModel, api)
    }

    func testDefaultStartAngle90PlacesAxisZeroStraightUp() {
        let (ecModel, api) = buildRadarModel()
        let radars = Radar.create(ecModel, api)
        XCTAssertEqual(radars.count, 1, "one Radar per radar component")

        let axes = radars[0].getIndicatorAxes()
        XCTAssertEqual(axes.count, 4, "one IndicatorAxis per indicator")

        // Default startAngle is 90° → axis 0 points straight up (π/2). THE critical guard: if the
        // Int-boxed default were dropped by an `as? Double` read, axis 0 would sit at 0 rad (right).
        // idx == 0 zeroes the clockwise-`sign` term, so this isolates startAngle.
        XCTAssertEqual(axes[0].angle, .pi / 2, accuracy: 1e-9)
    }
}
