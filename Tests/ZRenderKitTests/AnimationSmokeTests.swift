// Animation interpolation smoke test — the in-flight-frame analog of GoldenTests' geometry
// parity. There is no display-list oracle for *interpolated* frames (real ECharts only dumps
// resolved end states with `animation:false`), so instead of byte-comparing against a fixture
// this drives the real Animator/Track + easing + color tween machinery at synthetic timestamps
// and asserts the interpolation invariants directly (monotonic toward target; exact endpoint;
// linear midpoint == arithmetic mean; eased midpoint == easing(0.5) applied; channel-wise color
// lerp). It validates Animator + easing + color.lerp end-to-end.
//
// NOTE on the seam this exercises: upstream `Element.animateTo({ shape/style })` routes a Path's
// style/shape *sub-bags* through `animateToShallow`, whose animate target must be a reference-type
// keyed `AnimationTarget`. The ported Path exposes `style`/`shape` as VALUE-type structs
// (PathStyleProps / PathShape) that do NOT yet expose keyed `animationGet`/`animationSet`, so the
// high-level `path.animateTo(style:)`/`(shape:)` sub-bag path is a deferred surface (PORT_STATUS
// §10 #8, §11a). This test therefore builds a real Path (to anchor to the task) but drives the
// Animator directly on a conforming `AnimationTarget` — exactly the seam Path's style/shape will
// plug into once they expose keyed access — so the Track/Clip/easing/color.lerp logic is what is
// under test, end-to-end.

import XCTest
import Foundation
@testable import ZRenderKit

final class AnimationSmokeTests: XCTestCase {

    /// A minimal reference-type keyed animate target (the AnimationTarget seam the Animator
    /// reads/writes through). Stands in for a Path's keyed style/shape access (deferred).
    private final class TweenTarget: AnimationTarget {
        var values: [String: Any]
        init(_ values: [String: Any]) { self.values = values }
        func animationGet(_ key: String) -> Any? { return values[key] }
        func animationSet(_ key: String, _ value: Any?) { values[key] = value }
    }

    private let duration: Double = 1000   // ms
    /// Drive fractions: 0, 25%, 50%, 100% of the duration (the task's synthetic timestamps).
    private let fractions: [Double] = [0, 0.25, 0.5, 1.0]

    /// Build an Animator on `target` for one keyed prop, start it with `easing`, then step its
    /// Clip at synthetic global times `duration * fractions[i]` (this is exactly what
    /// `Animation.update` does internally via `clip.step(time, delta)`, but at deterministic
    /// timestamps instead of the wall-clock `getTime()`), returning the value read back from the
    /// target after each step.
    private func driveSequence(
        target: TweenTarget,
        propName: String,
        finalValue: Any,
        easing: AnimationEasing
    ) -> [Any?] {
        let animator = Animator<TweenTarget>(target, false)
        // `when(duration, props)` auto-seeds a keyframe at t=0 from the target's current value
        // (read via animationGet) and a keyframe at t=duration from `props`.
        animator.when(duration, [propName: finalValue])
        animator.start(easing)

        guard let clip = animator.getClip() else {
            XCTFail("Animator produced no clip — track was inert (initial value missing?)")
            return []
        }

        var out: [Any?] = []
        var prevTime: Double = 0
        for f in fractions {
            let t = duration * f
            clip.step(t, t - prevTime)
            prevTime = t
            out.append(target.animationGet(propName))
        }
        return out
    }

    // MARK: - Number tween (linear easing)

    func test_linear_number_tween_midpoint_and_endpoint() throws {
        // Anchor to the task: build a real Path (Rect). Its style/shape value-bags are a deferred
        // animate surface, so the numeric tween runs on the conforming AnimationTarget seam.
        var rectShape = RectShape()
        rectShape.x = 0; rectShape.y = 0; rectShape.width = 100; rectShape.height = 50
        let rect = Rect()
        rect.setShape(rectShape)
        XCTAssertNotNil(rect)

        // Animate a numeric prop from 0 -> 100 with linear easing.
        let target = TweenTarget(["x": 0.0])
        let frames = driveSequence(
            target: target,
            propName: "x",
            finalValue: 100.0,
            easing: .named("linear")
        ).map { ($0 as? Double) ?? Double.nan }

        // [0, 0.25, 0.5, 1.0] -> linear -> [0, 25, 50, 100]
        XCTAssertEqual(frames.count, 4)

        // Monotonic non-decreasing toward the target.
        for i in 1..<frames.count {
            XCTAssertGreaterThanOrEqual(frames[i], frames[i - 1],
                "linear tween must be monotonic toward target (frame \(i))")
        }

        // t=0 -> source exactly.
        XCTAssertEqual(frames[0], 0.0, accuracy: 1e-9)
        // t=50% with linear easing -> arithmetic midpoint, within 1e-9.
        XCTAssertEqual(frames[2], 50.0, accuracy: 1e-9)
        // t=duration -> EXACTLY the target (not merely within tolerance).
        XCTAssertEqual(frames[3], 100.0, "endpoint must equal target exactly")
    }

    // MARK: - Number tween (cubicOut easing) — eased midpoint uses the real easing function

    func test_cubicOut_number_tween_easing_and_monotonic() throws {
        let target = TweenTarget(["x": 0.0])
        let frames = driveSequence(
            target: target,
            propName: "x",
            finalValue: 100.0,
            easing: .named("cubicOut")
        ).map { ($0 as? Double) ?? Double.nan }

        // Monotonic non-decreasing (cubicOut is monotonic on [0,1]).
        for i in 1..<frames.count {
            XCTAssertGreaterThanOrEqual(frames[i], frames[i - 1],
                "cubicOut tween must be monotonic toward target (frame \(i))")
        }

        // t=0 -> source exactly.
        XCTAssertEqual(frames[0], 0.0, accuracy: 1e-9)

        // The clip applies the easing to `percent` before the Track interpolates linearly between
        // the two keyframes, so the value at fraction f is lerp(0, 100, easing(f)).
        // Use the REAL easing function as the oracle.
        let expected25 = interpLinear(0, 100, easing.cubicOut(0.25))
        let expected50 = interpLinear(0, 100, easing.cubicOut(0.5))
        XCTAssertEqual(frames[1], expected25, accuracy: 1e-9,
            "eased frame must equal lerp(src,dst, cubicOut(0.25))")
        XCTAssertEqual(frames[2], expected50, accuracy: 1e-9,
            "eased frame at 50% must equal easing(0.5) applied")

        // Eased value at 50% strictly leads the linear midpoint (cubicOut front-loads).
        XCTAssertGreaterThan(frames[2], 50.0,
            "cubicOut(0.5) > 0.5, so the eased 50% frame must lead the linear midpoint")

        // t=duration -> EXACTLY the target (easing(1)==1 for every easing).
        XCTAssertEqual(frames[3], 100.0, "endpoint must equal target exactly")
    }

    // MARK: - Color tween — channel-wise lerp at 50% (validates color.parse + interpolate + rgba2String)

    func test_color_tween_channelwise_lerp_at_midpoint() throws {
        // Even channels so the rgba2String floor() of each channel is exact at the midpoint.
        let src = "rgba(10,20,30,1)"   // [10,20,30,1]
        let dst = "rgba(50,80,110,1)"  // [50,80,110,1]  -> midpoint [30,50,70,1]

        let target = TweenTarget(["fill": src])
        let frames = driveSequence(
            target: target,
            propName: "fill",
            finalValue: dst,
            easing: .named("linear")
        ).map { $0 as? String }

        // t=0 -> source channels; t=duration -> target channels exactly.
        let f0 = try XCTUnwrap(frames[0].flatMap { color.parse($0) })
        let f2 = try XCTUnwrap(frames[2].flatMap { color.parse($0) })
        let f3 = try XCTUnwrap(frames[3].flatMap { color.parse($0) })

        assertChannels(f0, [10, 20, 30, 1], "color t=0 must equal source")

        // Channel-wise lerp at 50% (linear): each channel == (src + dst) / 2.
        assertChannels(f2, [30, 50, 70, 1], "color t=50% must be the channel-wise midpoint")

        // Monotonic per RGB channel across the drive (10->30->50, 20->50->80, 30->70->110).
        let f1 = try XCTUnwrap(frames[1].flatMap { color.parse($0) })
        for ch in 0..<3 {
            XCTAssertGreaterThanOrEqual(f1[ch], f0[ch], "channel \(ch) monotonic (frame 1)")
            XCTAssertGreaterThanOrEqual(f2[ch], f1[ch], "channel \(ch) monotonic (frame 2)")
            XCTAssertGreaterThanOrEqual(f3[ch], f2[ch], "channel \(ch) monotonic (frame 3)")
        }

        // Endpoint exact.
        assertChannels(f3, [50, 80, 110, 1], "color endpoint must equal target exactly")
    }

    // MARK: - Direct color.lerp at 0.5 (the function the color tween is built on)

    func test_color_lerp_direct_midpoint() throws {
        let result = color.lerp(0.5, ["rgba(10,20,30,1)", "rgba(50,80,110,1)"])
        guard case .color(let s)? = result else {
            XCTFail("color.lerp returned nil / non-color result")
            return
        }
        let channels = try XCTUnwrap(color.parse(s))
        assertChannels(channels, [30, 50, 70, 1], "color.lerp(0.5) must be the channel-wise midpoint")
    }

    // MARK: - helpers

    /// The Track's number interpolation: (p1 - p0) * percent + p0.
    private func interpLinear(_ p0: Double, _ p1: Double, _ percent: Double) -> Double {
        return (p1 - p0) * percent + p0
    }

    private func assertChannels(
        _ got: [Double], _ expected: [Double], _ msg: String,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        XCTAssertEqual(got.count, expected.count, msg, file: file, line: line)
        for i in 0..<Swift.min(got.count, expected.count) {
            XCTAssertEqual(got[i], expected[i], accuracy: 1e-9,
                "\(msg) (channel \(i))", file: file, line: line)
        }
    }
}
