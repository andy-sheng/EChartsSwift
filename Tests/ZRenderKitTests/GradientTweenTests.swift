// GradientTweenTests.swift — gradient→gradient fill tweening (the animation.html gap).
//
// Was dead: util.isGradientObject hardcoded false + zrColorToAnimValue dropped gradients. Now a
// fill animated from one LinearGradient to another interpolates its color stops + geometry. Drives
// the style animator's clip to completion and asserts the fill ends at the target gradient's stops.

import XCTest
@testable import ZRenderKit

final class GradientTweenTests: XCTestCase {

    func test_isGradientObject_detects_gradients() {
        XCTAssertTrue(util.isGradientObject(LinearGradient(0, 0, 1, 1)))
        XCTAssertTrue(util.isGradientObject(RadialGradient(0.5, 0.5, 0.5)))
        XCTAssertFalse(util.isGradientObject("red"))
        XCTAssertFalse(util.isGradientObject(42.0))
    }

    private var clock: Double = 0
    private func drive(_ el: Element, _ ms: Double = 1000) {
        let start = clock
        let anims = el.animators
        for a in anims { _ = a.getClip()?.step(start, 0) }
        clock = start + ms
        for a in anims { _ = a.getClip()?.step(clock, ms) }
    }

    func test_fill_tweens_gradient_to_gradient() throws {
        // gradient1: red(0) → black(1); gradient2: black(0) → blue(0.5) → white(1)  (animation.html).
        let g1 = LinearGradient(0, 0, 1, 1)
        g1.addColorStop(0, "red"); g1.addColorStop(1, "black")
        let g2 = LinearGradient(0, 0, 1, 1)
        g2.addColorStop(0, "black"); g2.addColorStop(0.5, "blue"); g2.addColorStop(1, "white")

        var rs = RectShape(); rs.x = 0; rs.y = 0; rs.width = 100; rs.height = 100
        let r = Rect(); r.setShape(rs)
        var st = PathStyleProps(); st.fill = .linearGradient(g1); r.useStyle(st)

        // circle.animate('style', true).when(1000, {fill: gradient2}).start()
        _ = r.animate("style").when(1000, ["fill": g2]).start()

        // Mid-tween: the fill is a gradient (interpolating), not still g1's identity nor a string.
        drive(r, 500)
        guard case .some(.linearGradient(let mid)) = r.pathStyle.fill else {
            return XCTFail("mid-tween fill should be a linear gradient, got \(String(describing: r.pathStyle.fill))")
        }
        XCTAssertEqual(mid.colorStops.count, 3, "tween adopts the target's 3 stops (shorter side padded)")

        // Completion: fill reaches gradient2's stops (black → blue → white).
        drive(r, 500)
        guard case .some(.linearGradient(let end)) = r.pathStyle.fill else {
            return XCTFail("final fill should be a linear gradient")
        }
        XCTAssertEqual(end.colorStops.count, 3)
        let black = try XCTUnwrap(color.parse("black"))
        let blue = try XCTUnwrap(color.parse("blue"))
        let white = try XCTUnwrap(color.parse("white"))
        func assertColor(_ stopColor: String, _ want: [Double], _ label: String) throws {
            let got = try XCTUnwrap(color.parse(stopColor), "stop \(label) parses")
            for i in 0..<3 { XCTAssertEqual(got[i], want[i], accuracy: 2.0, "\(label) channel \(i)") }
        }
        try assertColor(end.colorStops[0].color, black, "stop0")
        try assertColor(end.colorStops[1].color, blue, "stop1")
        try assertColor(end.colorStops[2].color, white, "stop2")
        XCTAssertEqual(end.colorStops[1].offset, 0.5, accuracy: 1e-6, "middle stop offset")
    }
}
