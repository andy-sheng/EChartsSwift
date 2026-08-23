// Phase 4 (interaction) smoke: prove the scene graph is hit-testable / dispatchable end-to-end.
//
// This is the input-side analog of the geometry GoldenTests: fixed pointer coordinates, known
// elements at known positions, and deterministic dispatch. It drives the now-real `Handler`
// (findHover + dispatchToElement) directly over a z-sorted `Storage` display list — NOT the UIKit
// bridge — and asserts:
//   - findHover: a point inside rect A returns A; a point in an A/B overlap returns the TOP (higher
//     z2) rect; a point outside returns no target; a `silent` rect is never a hover *target* (but is
//     reported as `topTarget`); an `ignore` rect is not hovered at all.
//   - dispatch + bubbling: a `click` on a child Rect fires the child handler THEN the parent Group
//     handler THEN bubbles to the ZRender host.
//   - stopPropagation: documented faithfulness gap (see `test_stopPropagation_child_stops_parent`).
//
// We use `CALayerPainter` only as the `PainterBase` the Handler needs for boundary checks; no
// rendering or UIKit input is involved.

#if canImport(QuartzCore) && canImport(CoreGraphics)
import XCTest
import CoreGraphics
import ZRenderKit
import NativePainter
#if canImport(AppKit)
import AppKit
#endif

final class InteractionSmokeTests: XCTestCase {

    func testClearingEmphasisRemovesAStateOnlyPathStroke() {
        let rect = Rect([
            "shape": ["x": 0.0, "y": 0.0, "width": 100.0, "height": 40.0],
            "style": ["fill": "#8fd3e8"]
        ])
        XCTAssertNil(rect.pathStyle.stroke)
        rect.ensureState("emphasis").style = ["stroke": "#000"]

        _ = rect.useState("emphasis", false, true)
        guard case .some(.string("#000")) = rect.pathStyle.stroke else {
            return XCTFail("emphasis must apply its black stroke")
        }

        rect.clearStates(true)
        guard case .some(.string("none")) = rect.pathStyle.stroke else {
            return XCTFail("a color introduced only by emphasis must be removed on pointer leave")
        }
    }

#if canImport(AppKit)
    func testAppKitViewForwardsMouseExitAsGlobalOut() throws {
        let view = ZRenderView(frame: CGRect(x: 0, y: 0, width: 200, height: 200))
        view.updateTrackingAreas()
        XCTAssertTrue(view.trackingAreas.contains {
            $0.options.contains(.mouseEnteredAndExited)
        }, "the AppKit host must subscribe to mouse-exit delivery")

        var globalOutCount = 0
        view.zr.on("globalout", { _, _ in globalOutCount += 1; return nil })

        let event = try XCTUnwrap(NSEvent.enterExitEvent(
            with: .mouseExited,
            location: NSPoint(x: 201, y: 100),
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            eventNumber: 1,
            trackingNumber: 1,
            userData: nil
        ))
        view.mouseExited(with: event)

        XCTAssertEqual(globalOutCount, 1,
                       "leaving the native AppKit view must forward mouseout/globalout to zrender")
    }
#endif

    // MARK: - helpers

    private func makePointerEvent(_ x: Double, _ y: Double) -> ZRRawEvent {
        let e = ZRRawEvent()
        e.zrX = x; e.zrY = y
        e.clientX = x; e.clientY = y
        e.which = 1
        return e
    }

    private func makeZR() -> ZRender {
        let painter = CALayerPainter(size: CGSize(width: 200, height: 200))
        let proxy = NativeHandlerProxy()
        return ZRenderKit.`init`(nil, nil, painter: painter, proxy: proxy)
    }

    func test_hover_updates_native_cursor_semantic() {
        let painter = CALayerPainter(size: CGSize(width: 200, height: 200))
        let proxy = NativeHandlerProxy()
        let zr = ZRenderKit.`init`(nil, nil, painter: painter, proxy: proxy)
        defer { zr.dispose() }

        let rect = makeRect(20, 20, 80, 80)
        rect.cursor = "pointer"
        zr.add(rect)

        zr.handler.mousemove(makePointerEvent(50, 50))
        XCTAssertEqual(proxy.currentCursorStyle, "pointer",
                       "hovering an interactive data element must request the pointing-hand cursor")
        zr.handler.mousemove(makePointerEvent(150, 150))
        XCTAssertEqual(proxy.currentCursorStyle, "default",
                       "moving off every element must restore the arrow cursor")
    }

    func test_coarsePointerExpansionIsOptInForMouseAndRetainedForTouch() {
        func make(_ useCoarsePointer: Bool) -> (ZRender, Rect) {
            let painter = CALayerPainter(size: CGSize(width: 200, height: 200))
            let proxy = NativeHandlerProxy()
            var opts = ZRenderInitOpt()
            opts.useCoarsePointer = useCoarsePointer
            let zr = ZRenderKit.`init`(nil, opts, painter: painter, proxy: proxy)
            let rect = makeRect(20, 20, 20, 20)
            zr.add(rect)
            return (zr, rect)
        }

        let (mouseZR, _) = make(false)
        defer { mouseZR.dispose() }
        XCTAssertNil(mouseZR.handler.findHover(55, 30).target,
                     "desktop/Web mouse semantics must stop at the actual series geometry")

        let (touchZR, touchRect) = make(true)
        defer { touchZR.dispose() }
        XCTAssertTrue(touchZR.handler.findHover(55, 30).target === touchRect,
                      "touch keeps zrender's 44pt coarse-pointer accessibility target")
    }

    func test_defaultPointerCapabilityMatchesTheNativePlatform() {
        let painter = CALayerPainter(size: CGSize(width: 200, height: 200))
        let proxy = NativeHandlerProxy()
        let zr = ZRenderKit.`init`(nil, nil, painter: painter, proxy: proxy)
        defer { zr.dispose() }
        let rect = makeRect(20, 20, 20, 20)
        zr.add(rect)

#if canImport(UIKit)
        XCTAssertTrue(zr.handler.findHover(55, 30).target === rect,
                      "UIKit defaults to the touch-friendly coarse hit target")
#else
        XCTAssertNil(zr.handler.findHover(55, 30).target,
                     "AppKit defaults to the exact desktop-Web mouse hit target")
#endif
    }

    private func makeRect(_ x: Double, _ y: Double, _ w: Double, _ h: Double, z2: Double = 0) -> Rect {
        var shape = RectShape()
        shape.x = x; shape.y = y; shape.width = w; shape.height = h
        let rect = Rect()
        rect.setShape(shape)
        rect.z2 = z2
        return rect
    }

    // MARK: - findHover over a Group of two rects

    func test_findHover_inside_rectA_returns_A_and_outside_returns_nil() {
        let zr = makeZR()
        defer { zr.dispose() }

        // Two non-overlapping rects in a Group: A at (10,10)+30, B at (120,120)+30.
        let group = Group()
        let rectA = makeRect(10, 10, 30, 30)
        let rectB = makeRect(120, 120, 30, 30)
        _ = group.add(rectA)
        _ = group.add(rectB)
        zr.add(group)

        // Inside A.
        XCTAssertTrue(zr.handler.findHover(25, 25).target === rectA,
                      "a point inside rect A must hover rect A")
        // Inside B.
        XCTAssertTrue(zr.handler.findHover(135, 135).target === rectB,
                      "a point inside rect B must hover rect B")
        // Between A and B (covered by neither).
        XCTAssertNil(zr.handler.findHover(80, 80).target,
                     "a point outside every element must return no hover target")
    }

    func test_findHover_overlap_returns_top_z2() {
        let zr = makeZR()
        defer { zr.dispose() }

        // Two overlapping rects sharing the point (50,50). `low` has z2=1, `high` has z2=2, so the
        // display list sorts low-before-high and findHover (which walks the list top-down) hits
        // `high` first. Add `high` FIRST so insertion order can't accidentally produce the answer.
        let group = Group()
        let high = makeRect(20, 20, 60, 60, z2: 2)
        let low  = makeRect(20, 20, 60, 60, z2: 1)
        _ = group.add(high)
        _ = group.add(low)
        zr.add(group)

        let hovered = zr.handler.findHover(50, 50)
        XCTAssertTrue(hovered.target === high,
                      "in an overlap, findHover must return the topmost (higher z2) element")

        // Flip z2 and confirm the answer flips — proves it's z-driven, not identity/order luck.
        high.z2 = 1
        low.z2 = 2
        zr.storage.updateDisplayList()
        XCTAssertTrue(zr.handler.findHover(50, 50).target === low,
                      "raising the other element's z2 must make it the hover target")
    }

    func test_findHover_silent_rect_is_not_target_but_is_topTarget() {
        let zr = makeZR()
        defer { zr.dispose() }

        // A silent rect on top of a normal rect, both covering (50,50). The silent one must NOT be
        // returned as `target`; hit-testing falls through to the normal rect below. The silent rect
        // is still reported as `topTarget` (upstream isHover → SILENT semantics).
        let group = Group()
        let normal = makeRect(20, 20, 60, 60, z2: 1)
        let silent = makeRect(20, 20, 60, 60, z2: 2)
        silent.silent = true
        _ = group.add(normal)
        _ = group.add(silent)
        zr.add(group)

        let hovered = zr.handler.findHover(50, 50)
        XCTAssertTrue(hovered.target === normal,
                      "a silent rect must not be a hover target; hit-testing falls through to the rect below")
        XCTAssertTrue(hovered.topTarget === silent,
                      "a silent rect must still be reported as topTarget")
    }

    func test_findHover_ignore_rect_is_not_hovered_at_all() {
        let zr = makeZR()
        defer { zr.dispose() }

        // A lone ignored rect over (50,50): excluded from the display list / skipped by setHoverTarget,
        // so neither target NOR topTarget is set.
        let group = Group()
        let ignored = makeRect(20, 20, 60, 60)
        ignored.ignore = true
        _ = group.add(ignored)
        zr.add(group)

        let hovered = zr.handler.findHover(50, 50)
        XCTAssertNil(hovered.target, "an ignored rect must not be a hover target")
        XCTAssertNil(hovered.topTarget, "an ignored rect must not even be a topTarget")
    }

    // MARK: - dispatch + bubbling

    func test_click_dispatches_to_child_then_bubbles_to_parent_then_zr() {
        let zr = makeZR()
        defer { zr.dispose() }

        let group = Group()
        let rect = makeRect(40, 40, 100, 100)   // (50,50) is inside
        _ = group.add(rect)
        zr.add(group)

        var order: [String] = []
        _ = rect.on("click", { _, _ in order.append("child"); return nil })
        _ = group.on("click", { _, _ in order.append("parent"); return nil })
        zr.on("click", { _, _ in order.append("zr"); return nil })

        // Drive Handler's documented dispatch seam directly: hit-test, then dispatchToElement.
        let hovered = zr.handler.findHover(50, 50)
        XCTAssertTrue(hovered.target === rect, "precondition: pointer must hover the child rect")
        zr.handler.dispatchToElement(hovered, .click, makePointerEvent(50, 50))

        XCTAssertEqual(order, ["child", "parent", "zr"],
                       "click must dispatch to the covered child, then bubble to its parent Group, then the ZR host")
    }

    func test_click_misses_when_pointer_outside_element() {
        let zr = makeZR()
        defer { zr.dispose() }

        let group = Group()
        let rect = makeRect(40, 40, 20, 20)
        _ = group.add(rect)
        zr.add(group)

        var childFired = false
        _ = rect.on("click", { _, _ in childFired = true; return nil })

        // (150,150) is well outside the 20×20 rect: findHover returns no target, so the empty
        // HoveredResult dispatches to nothing on the element.
        let hovered = zr.handler.findHover(150, 150)
        XCTAssertNil(hovered.target)
        zr.handler.dispatchToElement(hovered, .click, makePointerEvent(150, 150))
        XCTAssertFalse(childFired, "a click outside the element must not dispatch to it")
    }

    // MARK: - stopPropagation

    func test_stopPropagation_child_stops_parent() throws {
        let zr = makeZR()
        defer { zr.dispose() }

        let group = Group()
        let rect = makeRect(40, 40, 100, 100)
        _ = group.add(rect)
        zr.add(group)

        var childFired = false
        var parentFired = false
        // Upstream mechanism: an `.on` listener stops ZR bubbling by mutating the SHARED event packet
        // (`e.cancelBubble = true`); the dispatch loop re-reads `eventPacket.cancelBubble` after each
        // `el.trigger` and breaks. ElementEvent is now a reference type, so the write is visible to
        // the loop.
        _ = rect.on("click", { _, args in
            childFired = true
            if let e = args.first as? ElementEvent {
                e.cancelBubble = true   // reference type — writes back to the loop's packet
            }
            return nil
        })
        _ = group.on("click", { _, _ in parentFired = true; return nil })

        let hovered = zr.handler.findHover(50, 50)
        zr.handler.dispatchToElement(hovered, .click, makePointerEvent(50, 50))

        XCTAssertTrue(childFired, "child handler must fire")
        XCTAssertFalse(parentFired, "stopPropagation on the child must stop the parent Group handler")
    }
}
#endif
