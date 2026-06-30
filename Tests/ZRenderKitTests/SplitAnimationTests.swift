// SplitAnimationTests.swift — guards the split-morph path behind test/splitAnimation.html.
//
// separateMorph/combineMorph crashed in `dividePath` (→ getLocalTransform on an empty scratch
// MatrixArray) — fixed. This drives the resulting morph animators to completion and asserts the
// geometry morph reaches its target (__morphT → 1).
//
// It ALSO guards the Storage fix that made `combineMorph` actually render: a combine `toPath`
// acquires a (monkey-patched) `childrenRef` so Storage must descend into its sub-paths and NOT draw
// the toPath itself. Our Storage duck-types that the way upstream does; before the fix the toPath
// (un-morphed shape) was drawn and the sub-paths never entered the display list, so the whole combine
// phase was invisible (it just snapped to the source shape).

import XCTest
@testable import ZRenderKit

final class SplitAnimationTests: XCTestCase {

    private func redRect() -> Rect {
        var rs = RectShape(); rs.x = 50; rs.y = 50; rs.width = 200; rs.height = 200
        let r = Rect(); r.setShape(rs)
        var st = PathStyleProps(); st.fill = .string("red"); st.opacity = 0.5; r.useStyle(st)
        return r
    }
    private func circles(_ n: Int) -> [Path] {
        var cs: [Path] = []
        for i in 0..<n {
            var s = CircleShape(); s.cx = Double(i % 5) * 60 + 50; s.cy = Double(i / 5) * 60 + 50; s.r = 20
            let c = Circle(); c.setShape(s)
            var st = PathStyleProps(); st.fill = .string("blue"); st.opacity = 0.5; c.useStyle(st)
            cs.append(c)
        }
        return cs
    }

    private var clock: Double = 0
    private func drive(_ els: [Path], _ ms: Double = 1000) {
        let start = clock
        for el in els { for a in el.animators { _ = a.getClip()?.step(start, 0) } }
        clock = start + ms
        for el in els { for a in el.animators { _ = a.getClip()?.step(clock, ms) } }
    }

    func test_separateMorph_animates_to_target() throws {
        let rect = redRect()
        let many = circles(25)
        var base = ElementAnimateConfig(); base.duration = 1000; base.easing = .named("cubicInOut")

        let res = separateMorph(rect, many, SeparateConfig(base: base))
        XCTAssertEqual(res.toIndividuals.count, 25, "one rect divides into 25 morph targets")
        // Before driving, every individual is at the morph start.
        for c in res.toIndividuals { XCTAssertEqual(c.__morphT, 0, accuracy: 1e-9) }

        drive(res.toIndividuals)
        // After driving to completion, each individual reached the morph target (the circle shape).
        for c in res.toIndividuals {
            XCTAssertEqual(c.__morphT, 1, accuracy: 1e-6, "each individual should reach the morph target")
        }
    }

    func test_combineMorph_runs_without_crash() throws {
        let rect = redRect()
        let many = circles(25)
        var base = ElementAnimateConfig(); base.duration = 1000
        let res = combineMorph(many, rect, CombineConfig(base: base))
        XCTAssertGreaterThan(res.toIndividuals.count, 0, "combine morph produces individuals")
        drive(res.toIndividuals)   // must not trap (the dividePath/getLocalTransform crash path)
    }

    // A plain (non-morphing) path is drawn as itself; once it is the toPath of a combineMorph it
    // becomes a container (childrenRef) and Storage draws its sub-paths in its place. Guards the
    // Storage duck-typing of `childrenRef` for combine-morphing Paths.
    func test_combineMorph_subpaths_enter_displayList_not_toPath() throws {
        // Control: a normal rect IS in the display list.
        let plain = redRect()
        let s0 = Storage(); s0.addRoot(plain)
        let baseline = s0.getDisplayList(true)
        XCTAssertTrue(baseline.contains { $0 === plain }, "a normal path renders as itself")

        // Combine: the toPath becomes a container; its sub-paths render, it does not.
        let rect = redRect()
        let many = circles(25)
        var base = ElementAnimateConfig(); base.duration = 1000
        let res = combineMorph(many, rect, CombineConfig(base: base))

        let storage = Storage()
        storage.addRoot(rect)
        let list = storage.getDisplayList(true)

        XCTAssertFalse(list.contains { $0 === rect },
                       "a combine-morphing toPath must NOT be drawn as its own shape")
        for sub in res.toIndividuals {
            XCTAssertTrue(list.contains { $0 === sub },
                          "every combine sub-path must enter the display list")
        }
        XCTAssertEqual(list.count, res.toIndividuals.count,
                       "display list is exactly the sub-paths (toPath replaced by its children)")
    }

    // Guards the shared `activeChildrenRef()` duck-typing — the single source of truth used by BOTH
    // Storage and the painter's flattenDisplayList. Narrowing it (to `as? GroupLike` or `isGroup`)
    // silently drops combine-morph sub-paths and/or ZRText spans from the display list.
    func test_activeChildrenRef_duckTypes_every_container_kind() throws {
        // Leaf: a plain path is NOT a container.
        XCTAssertNil(redRect().activeChildrenRef(), "a plain Path is a leaf displayable")

        // Group: always a container.
        let g = Group(); let child = redRect(); _ = g.add(child)
        let gc = try XCTUnwrap(g.activeChildrenRef(), "Group is a container")
        XCTAssertTrue(gc.contains { $0 === child })

        // ZRText: a container (GroupLike) even though isGroup == false — the case `isGroup` missed.
        let t = ZRText()
        XCTAssertFalse(t.isGroup, "ZRText is not a Group…")
        XCTAssertNotNil(t.activeChildrenRef(), "…but it IS an active container (GroupLike)")

        // Combine-morph Path: a container ONLY while morphing — the case `as? GroupLike` missed.
        let rect = redRect()
        XCTAssertNil(rect.activeChildrenRef(), "a non-morphing Path is a leaf")
        let res = combineMorph(circles(25), rect, CombineConfig(base: ElementAnimateConfig()))
        let sub = try XCTUnwrap(rect.activeChildrenRef(), "a combine-morphing toPath becomes a container")
        XCTAssertEqual(sub.count, res.toIndividuals.count, "its children are the morph sub-paths")
    }
}
