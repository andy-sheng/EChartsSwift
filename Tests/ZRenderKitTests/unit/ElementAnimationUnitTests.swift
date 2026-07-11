// Ported from zrender/test/ut/spec/animation/ElementAnimation.test.ts — keep in sync with upstream

import XCTest
@testable import ZRenderKit

// upstream: import {Polyline, Rect, init} from '../zrender';
//           import Animation from '../../../../src/animation/Animation';
//   → Graphic/Shape/{Polyline,Rect}.swift, Animation/Animation.swift. `init` (the host facade) is
//     unused by these specs.
//
// jest → XCTest (per task brief): describe/it → XCTestCase/test_ methods; toEqual/toBe →
//   XCTAssertEqual; the two Promise-based async `it`s → XCTestExpectation.
//
// ── SUB-BAG NOTE ─────────────────────────────────────────────────────────────────────────────
// The animate target's keyed get/set is routed through `AnimationTarget` (Animator.swift). The
// base `Element` exposes its primary/Transformable props (x/y/rotation/scale/…) via
// `animationGet`/`animationSet`; the `shape` and `style` SUB-BAGS are value-type structs on
// Path/Displayable and are now ALSO exposed through `AnimationTarget` (Displayable/Path override
// `animationGet`/`animationSet` — see the Element.swift `_getKnownKV` PORT-NOTE and Path.swift /
// Displayable.swift). So `animateTo({shape:{…}})` / `animateTo({style:{…}})` reads an initial
// sub-value and writes the interpolated/final sub-value. Assertions over primary props (x, y), the
// shape/style sub-bags, and the animator count / callback surface all run; the one remaining skip
// (Original_reference) is for a DIFFERENT reason — JS array reference identity, inexpressible on a
// value-type shape — not the sub-bag.
final class ElementAnimationUnitTests: XCTestCase {

    // upstream: it('Undefined value should not be animated.')
    func test_Undefined_value_should_not_be_animated() {
        let polyline = Polyline()
        // upstream: polyline.animateTo({ shape: { foo: 2 } as any }, { setToFinal: true });
        var cfg = ElementAnimateConfig()
        cfg.setToFinal = true
        polyline.animateTo(["shape": ["foo": 2.0]], cfg)

        // upstream: expect(polyline.animators.length).toEqual(0);
        // NOTE: upstream reaches 0 by recursing into the live `shape` bag and filtering `foo`
        //   (absent → equal-to-set → no track). The port reaches the SAME observable 0 by a
        //   different path: `shape` is treated as a direct key (the sub-bag isn't exposed), the
        //   resulting empty-track animator completes immediately and `addAnimator`'s `done` hook
        //   self-removes it from `animators`. The asserted surface (animators.length) matches.
        XCTAssertEqual(polyline.animators.count, 0)
    }

    // upstream: it('Equal value should not be animated.')
    func test_Equal_value_should_not_be_animated() {
        let polyline = Polyline()
        polyline.x = 100
        // upstream: polyline.animateTo({ x: 100 }, { setToFinal: true });
        var cfg = ElementAnimateConfig()
        cfg.setToFinal = true
        polyline.animateTo(["x": 100.0], cfg)

        // upstream: expect(polyline.animators.length).toEqual(0);
        // `x` is a primary prop (fully wired): initial 100 == target 100 → filtered as unchanged.
        XCTAssertEqual(polyline.animators.count, 0)
    }

    // upstream: it('Should be final state when setToFinal')
    func test_Should_be_final_state_when_setToFinal() throws {
        let polyline = Polyline()
        // upstream: polyline.animateTo({ shape: { points: [[10,10],[20,20],[20,10]] },
        //                               style: { fill: 'red' }, x: 10, y: 10 }, { setToFinal: true });
        var cfg = ElementAnimateConfig()
        cfg.setToFinal = true
        polyline.animateTo([
            "shape": ["points": [[10.0, 10.0], [20.0, 20.0], [20.0, 10.0]]],
            "style": ["fill": "red"],
            "x": 10.0,
            "y": 10.0
        ], cfg)

        // Primary props are fully wired and set-to-final immediately (copyValue). These run:
        // upstream: expect(polyline.x).toBe(10); expect(polyline.y).toBe(10);
        XCTAssertEqual(polyline.x, 10)
        XCTAssertEqual(polyline.y, 10)

        // Now WIRED (PORT_STATUS §11a follow-up): the value-type shape/style sub-bags expose keyed
        // animationGet/animationSet (PolylineShape.points / PathStyleProps.fill), routed through
        // ShapeAnimationAccessor / PathStyleAnimationAccessor, so `setToFinal` writes them through.
        // upstream: expect(polyline.shape.points).toEqual([[10,10],[20,20],[20,10]]);
        let points = try XCTUnwrap((polyline.shape as? PolylineShape)?.points)
        XCTAssertEqual(points, [VectorArray(10, 10), VectorArray(20, 20), VectorArray(20, 10)])

        // upstream: expect(polyline.style.fill).toBe('red');  (port: the rich style is `pathStyle`)
        guard case .string(let fill)? = polyline.pathStyle.fill else {
            return XCTFail("style.fill was not set to a color string by setToFinal")
        }
        XCTAssertEqual(fill, "red")
    }

    // upstream: it('Original reference should not be replaced')
    func test_Original_reference_should_not_be_replaced() throws {
        // upstream relies on JS array reference identity: `polyline.shape.points` must `toBe`
        // (===) the SAME `points` array passed in, while `animateTo` mutates that array's contents
        // in place. The Swift port models `PolylineShape.points` as a value-type `[VectorArray]`
        // (no shared identity), and — as in the test above — shape-bag animation is not wired, so
        // neither the identity assertion nor the in-place-mutation assertion is expressible.
        throw XCTSkip("Inexpressible by a DIFFERENT unported surface than the shape bag (which is "
            + "now wired): the assertions test JS array *reference identity* — `expect(shape.points)"
            + ".toBe(points)` (the SAME array object) plus in-place mutation of the caller's `points` "
            + "/ `firstPoint`. Swift `PolylineShape.points` is a value-type [VectorArray] with no "
            + "shared identity (CONVENTIONS §3/§4), and the keyed shape accessor round-trips values "
            + "through [[Double]], so neither `===` nor caller-side mutation is expressible. The "
            + "value-equality half is already covered by test_Should_be_final_state_when_setToFinal.")
    }

    // upstream: it('Should call done after animation finished')  — Promise-based.
    func test_Should_call_done_after_animation_finished() {
        let doneExpectation = expectation(description: "animation done callback fires")

        let rect = Rect()
        let animation = Animation()
        animation.start()
        var cfg = ElementAnimateConfig()
        cfg.duration = 100
        cfg.done = {
            animation.stop()
            doneExpectation.fulfill()   // upstream: resolve(undefined)
        }
        // upstream: rect.animateTo({ shape: { x: 10, y: 10 } }, { duration: 100, done: ... });
        rect.animateTo(["shape": ["x": 10.0, "y": 10.0]], cfg)
        // upstream: for (i in rect.animators) animation.addAnimator(rect.animators[i]);
        // Now that the `shape` sub-bag is WIRED, this produces a REAL 100ms shape animator (RectShape
        //   exposes x/y), so `done` fires after the duration elapses — exactly as upstream. The
        //   animator's clip must be driven each frame: upstream uses requestAnimationFrame; the port
        //   leaves the per-frame tick to the host (Animation._startLoop is host-driven — see
        //   Animation.swift). A repeating Timer on the main run loop (which `wait(for:)` spins) stands
        //   in for that display-link tick, calling `animation.update()` until the clip completes.
        XCTAssertEqual(rect.animators.count, 1, "a real shape animator must exist (shape bag wired)")
        for i in 0..<rect.animators.count {
            animation.addAnimator(rect.animators[i])
        }

        let frameTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { _ in
            animation.update()
        }
        wait(for: [doneExpectation], timeout: 2.0)
        frameTimer.invalidate()
    }

    // upstream: it('Should call abort after animation aborted')  — Promise-based.
    func test_Should_call_abort_after_animation_aborted() {
        // upstream: a 200ms animator on shape{x,y}; 100ms later a second animateTo on the SAME shape
        // props aborts the first, firing `aborted`. Now that the `shape` sub-bag is WIRED, the first
        // animateTo({shape:{x,y}}) yields a REAL 200ms animator (RectShape exposes x/y), so it CAN be
        // aborted. The port aborts deterministically/synchronously rather than via setTimeout: the
        // second animateTo on the same topKey ("shape") + same props calls `stopTracks` on the first
        // animator (which has not yet stepped, _started==1), firing its `aborted` callback inline —
        // no wall-clock delay is needed to observe the asserted behaviour ("abort is called").
        let rect = Rect()
        var abortedCalled = false
        var cfg = ElementAnimateConfig()
        cfg.duration = 200
        cfg.aborted = { abortedCalled = true }
        // upstream: rect.animateTo({ shape: { x: 10, y: 10 } }, { duration: 200, aborted: resolve });
        rect.animateTo(["shape": ["x": 10.0, "y": 10.0]], cfg)
        XCTAssertEqual(rect.animators.count, 1, "a real 200ms shape animator must exist to be aborted")
        XCTAssertFalse(abortedCalled, "not aborted until the second animateTo")

        // upstream (after setTimeout 100): rect.animateTo({ shape: { x: 10, y: 10 } });
        rect.animateTo(["shape": ["x": 10.0, "y": 10.0]])
        XCTAssertTrue(abortedCalled, "the first animator's `aborted` callback must fire when the "
            + "second animateTo stops its tracks")
    }
}
