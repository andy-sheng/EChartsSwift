// Ported from zrender/test/ut/spec/graphic/Group.test.ts — keep in sync with upstream

import XCTest
@testable import ZRenderKit

final class GroupUnitTests: XCTestCase {

    // upstream: it('Default properties should be right')
    func test_Default_properties_should_be_right() throws {
        let group = Group()
        XCTAssertEqual(group.x, 0)
        XCTAssertEqual(group.y, 0)
        XCTAssertEqual(group.scaleX, 1)
        XCTAssertEqual(group.scaleY, 1)
        XCTAssertEqual(group.rotation, 0)

        XCTAssertEqual(group.type, "group")
        XCTAssertEqual(group.isGroup, true)
    }

    // upstream: it('Option can be set properly')
    func test_Option_can_be_set_properly() throws {
        let group = Group([
            "x": 2.0,
            "y": 3.0,
            "scaleX": 1.5,
            "scaleY": 1.5,
            "rotation": 2.0,
            "name": "Test"
        ])
        XCTAssertEqual(group.x, 2)
        XCTAssertEqual(group.y, 3)
        XCTAssertEqual(group.scaleX, 1.5)
        XCTAssertEqual(group.scaleY, 1.5)
        XCTAssertEqual(group.rotation, 2)
        XCTAssertEqual(group.name, "Test")
    }

    // upstream: it('Group#add')
    func test_Group_add() throws {
        let group = Group()
        let g1 = Group()
        let g2 = Group()

        group.add(g1)
        group.add(g2)

        XCTAssertEqual(group.childCount(), 2)
        XCTAssertEqual(group.children().count, 2)

        XCTAssertTrue(g1.parent === group)
        XCTAssertTrue(g2.parent === group)
    }

    // upstream: it('Group#addBefore')
    func test_Group_addBefore() throws {
        let group = Group()
        let g1 = Group()
        let g2 = Group()

        group.add(g1)
        group.addBefore(g2, g1)

        XCTAssertEqual(group.childCount(), 2)
        XCTAssertTrue(group.childAt(0) === g2)
        XCTAssertTrue(group.childAt(1) === g1)
    }

    // upstream: it('Group#remove')
    func test_Group_remove() throws {
        let group = Group()
        let g1 = Group()
        let g2 = Group()

        group.add(g1)
        group.add(g2)

        group.remove(g2)

        XCTAssertEqual(group.childCount(), 1)
        XCTAssertNil(g2.parent)
        XCTAssertTrue(group.childAt(0) === g1)

        group.remove(g1)
        XCTAssertEqual(group.childCount(), 0)
    }

    // upstream: it('Group#removeAll')
    func test_Group_removeAll() throws {
        let group = Group()
        let g1 = Group()
        let g2 = Group()

        group.add(g1)
        group.add(g2)

        group.removeAll()

        XCTAssertEqual(group.childCount(), 0)
        XCTAssertNil(g1.parent)
        XCTAssertNil(g2.parent)
    }

    // upstream: it('Group#childAt')
    func test_Group_childAt() throws {
        let group = Group()
        group.add(Group(["name": "First Child"]))
        group.add(Group(["name": "Second Child"]))

        XCTAssertEqual(group.childAt(0)?.name, "First Child")
        XCTAssertEqual(group.childAt(1)?.name, "Second Child")
    }

    // upstream: it('Group#childOfName')
    func test_Group_childOfName() throws {
        let group = Group()
        group.add(Group(["name": "First Child"]))
        group.add(Group(["name": "Second Child"]))

        XCTAssertEqual(group.childOfName("Second Child")?.name, "Second Child")
    }

    // upstream: it('Group#eachChild')
    func test_Group_eachChild() throws {
        let group = Group()
        let g1 = Group(["name": "g1"])
        let g2 = Group(["name": "g2"])
        let g11 = Group(["name": "g3"])

        group.add(g1)
        group.add(g2)
        g1.add(g11)

        var children: [Element] = []
        var indices: [Int] = []
        let context: [String: Any] = ["foo": 2]
        // NOTE: upstream also asserts `expect(this.foo).toBe(2)` inside the callback, verifying the
        // callback `this` is bound to `context`. The Swift port does NOT bind `context` as `this`
        // (Group.swift PORT-TODO: closures capture, context is accepted but unused), so that
        // sub-assertion is not expressible and is omitted; the iteration/order assertions remain.
        group.eachChild({ child, idx in
            indices.append(idx)
            children.append(child)
        }, context)
        XCTAssertEqual(children.count, 2)
        XCTAssertTrue(children[0] === g1)
        XCTAssertTrue(children[1] === g2)

        XCTAssertEqual(indices, [0, 1])
    }

    // upstream: it('Group#traverse')
    func test_Group_traverse() throws {
        let group = Group()
        let g1 = Group(["name": "g1"])
        let g2 = Group(["name": "g2"])
        let g11 = Group(["name": "g3"])

        group.add(g1)
        group.add(g2)
        g1.add(g11)

        var children: [Element] = []
        let context: [String: Any] = ["foo": 2]
        // NOTE: upstream's callback returns `void` (falsy → keep descending) and asserts
        // `this.foo === 2`. Swift's `traverse` cb returns `Bool` (return `true` to stop), so we
        // `return false` to continue. The `this`-binding assertion is omitted (see eachChild note).
        group.traverse({ child -> Bool in
            children.append(child)
            return false
        }, context)
        // Check if is depth first traverse
        XCTAssertEqual(children.count, 3)
        XCTAssertTrue(children[0] === g1)
        XCTAssertTrue(children[1] === g11)
        XCTAssertTrue(children[2] === g2)
    }
}
