// Ported from zrender/test/ut/spec/core/util.test.ts — keep in sync with upstream
//
// PORTING NOTES — util.ts is a dynamic-JS helper module; the Swift port operates on
// `[String: Any]` value-type bags. Several upstream assertions exercise JS semantics that are
// not representable in Swift's static type system and are therefore omitted (with an inline note)
// or the whole `it` block is `XCTSkip`-ed:
//   - `undefined`-valued object keys (`{a: undefined}`): a nil value means "absent key" in a
//     Swift dictionary, so an explicit-undefined value cannot be stored. (`null` → `NSNull()`.)
//   - reference identity (`result.a === b`): Swift dictionaries/arrays are value types, so there
//     is no shared-reference identity to assert (clone always yields a separate value).
//   - JS built-in / TypedArray / user-class clone-by-reference: see the relevant skips.
// `toEqual` deep equality is implemented via NSDictionary/NSArray `isEqual(to:)`.

import XCTest
import Foundation
@testable import ZRenderKit

private func deepEqual(_ a: [String: Any], _ b: [String: Any]) -> Bool {
    return (a as NSDictionary).isEqual(to: b)
}

final class UtilUnitTests: XCTestCase {

    // ----- describe('merge') -----

    // upstream: it('basic')
    func test_merge_basic() throws {
        var t1: [String: Any] = [:]
        XCTAssertTrue(deepEqual(util.merge(&t1, ["a": 121.0]), ["a": 121.0]))

        var t2: [String: Any] = ["a": "zz"]
        XCTAssertTrue(deepEqual(util.merge(&t2, ["a": "121"], true), ["a": "121"]))

        var t3: [String: Any] = ["a": "zz", "b": ["c": 1212.0] as [String: Any]]
        let src3: [String: Any] = ["b": ["c": "zxcv"] as [String: Any]]
        XCTAssertTrue(deepEqual(util.merge(&t3, src3, true),
            ["a": "zz", "b": ["c": "zxcv"] as [String: Any]]))
    }

    // upstream: it('overwrite')
    func test_merge_overwrite() throws {
        var t1: [String: Any] = ["a": ["b": "zz"] as [String: Any]]
        XCTAssertTrue(deepEqual(util.merge(&t1, ["a": "121"], true), ["a": "121"]))

        var t2: [String: Any] = ["a": NSNull()]
        XCTAssertTrue(deepEqual(util.merge(&t2, ["a": "121"], true), ["a": "121"]))

        var t3: [String: Any] = ["a": "12"]
        XCTAssertTrue(deepEqual(util.merge(&t3, ["a": NSNull()], true), ["a": NSNull()]))

        // OMITTED — upstream `merge({a:{a:'asdf'}}, {a: undefined}, true)` → {a: undefined}:
        //   `undefined`-valued object keys are not representable in Swift `[String: Any]`.

        let b: [String: Any] = ["b": "vvv"]   // not same object
        var t5: [String: Any] = ["a": NSNull()]
        let result = util.merge(&t5, ["a": b], true)
        XCTAssertTrue(deepEqual(result, ["a": ["b": "vvv"] as [String: Any]]))
        // OMITTED — upstream `expect(result.a === b).toEqual(false)`: value-type identity is moot.
    }

    // upstream: it('not_overwrite')
    func test_merge_not_overwrite() throws {
        var t1: [String: Any] = ["a": ["b": "zz"] as [String: Any]]
        XCTAssertTrue(deepEqual(util.merge(&t1, ["a": "121"], false),
            ["a": ["b": "zz"] as [String: Any]]))

        var t2: [String: Any] = ["a": NSNull()]
        XCTAssertTrue(deepEqual(util.merge(&t2, ["a": "121"], false), ["a": NSNull()]))

        var t3: [String: Any] = ["a": "12"]
        XCTAssertTrue(deepEqual(util.merge(&t3, ["a": NSNull()], false), ["a": "12"]))

        // OMITTED — upstream `merge({a:{a:'asdf'}}, {a: undefined}, false)` → {a:{a:'asdf'}}:
        //   `undefined`-valued object key — see test_merge_overwrite.
    }

    // upstream: it('array')
    func test_merge_array() throws {
        var t1: [String: Any] = ["a": ["a": "asdf"] as [String: Any]]
        let src1: [String: Any] = ["a": ["asdf", "zxcv"] as [Any]]
        XCTAssertTrue(deepEqual(util.merge(&t1, src1, true), ["a": ["asdf", "zxcv"] as [Any]]))

        var t2: [String: Any] = ["a": ["a": [12.0, 23.0, 34.0] as [Any]] as [String: Any]]
        let src2: [String: Any] = ["a": ["a": [99.0, 88.0] as [Any]] as [String: Any]]
        XCTAssertTrue(deepEqual(util.merge(&t2, src2, false),
            ["a": ["a": [12.0, 23.0, 34.0] as [Any]] as [String: Any]]))

        let b: [Any] = [99.0, 88.0]   // not same object
        var t3: [String: Any] = ["a": ["a": [12.0, 23.0, 34.0] as [Any]] as [String: Any]]
        let src3: [String: Any] = ["a": ["a": b] as [String: Any]]
        let result = util.merge(&t3, src3, true)
        XCTAssertTrue(deepEqual(result, ["a": ["a": b] as [String: Any]]))
        // OMITTED — upstream `expect(result.a.a === b).toEqual(false)`: value-type identity is moot.
    }

    // upstream: it('null_undefined')
    func test_merge_null_undefined() throws {
        throw XCTSkip("util.merge does not accept null/undefined target or source: the Swift "
            + "signature is non-optional `merge(_ target: inout [String: Any], _ source: "
            + "[String: Any], _ overwrite)`, so upstream's `if (!isObject(source)||!isObject(target))"
            + " return overwrite ? clone(source) : target` guard (which makes merge(null,x)→null, "
            + "merge(undefined,x)→undefined, merge(x,null)→x, merge(x,undefined)→x) is NOT modeled. "
            + "FAITHFULNESS GAP — see report. (util.swift)")
    }

    // ----- describe('clone') -----

    // upstream: it('primary')
    func test_clone_primary() throws {
        let null = NSNull()                             // upstream clone(null) → null (same value)
        XCTAssertTrue(util.clone(null) === null)        // NSNull passed through unchanged
        // OMITTED — upstream clone(undefined) → undefined (undefined not representable).
        XCTAssertEqual(util.clone(11.0), 11.0)
        XCTAssertEqual(util.clone("11"), "11")
        XCTAssertEqual(util.clone("aa"), "aa")
    }

    // upstream: it('array')
    func test_clone_array() throws {
        let inner: [Any] = [1.0, "2", "a", 4.0, ["x": "r", "y": [2.0, 3.0] as [Any]] as [String: Any]]
        let expected: [Any] = [1.0, "2", "a", 4.0, ["x": "r", "y": [2.0, 3.0] as [Any]] as [String: Any]]

        XCTAssertTrue((util.clone(inner) as NSArray).isEqual(to: expected))

        let o1: [String: Any] = ["a": inner]
        XCTAssertTrue(((util.clone(o1)["a"] as! [Any]) as NSArray).isEqual(to: expected))

        let o2: [String: Any] = ["a": [1.0, inner] as [Any]]
        let a = util.clone(o2)["a"] as! [Any]
        XCTAssertTrue(((a[1] as! [Any]) as NSArray).isEqual(to: expected))
    }

    // upstream: it('object')
    func test_clone_object() throws {
        let src: [String: Any] = ["x": 1.0, "y": [2.0, 3.0] as [Any], "z": ["a": 3.0] as [String: Any]]
        let expected: [String: Any] = ["x": 1.0, "y": [2.0, 3.0] as [Any], "z": ["a": 3.0] as [String: Any]]

        XCTAssertTrue((util.clone(src) as NSDictionary).isEqual(to: expected))

        let o1: [String: Any] = ["a": src]
        XCTAssertTrue(((util.clone(o1)["a"] as! [String: Any]) as NSDictionary).isEqual(to: expected))

        let o2: [String: Any] = ["a": [1.0, src] as [Any]]
        let a = util.clone(o2)["a"] as! [Any]
        XCTAssertTrue(((a[1] as! [String: Any]) as NSDictionary).isEqual(to: expected))
    }

    // upstream: it('built-in')
    func test_clone_built_in() throws {
        throw XCTSkip("util.clone built-in passthrough is not faithfully testable: upstream returns "
            + "Date/function/RegExp/Error BY REFERENCE (BUILTIN_OBJECT branch). In Swift, Date is a "
            + "value type (no `===`), functions are not representable, so the reference-equality "
            + "assertions `clone(d) === d` cannot be expressed. (util.swift PORT-TODO: BUILTIN_OBJECT)")
    }

    // upstream: it('TypedArray')
    func test_clone_TypedArray() throws {
        throw XCTSkip("util.clone TypedArray branch is not ported: upstream allocates a NEW typed "
            + "array (distinct reference, equal contents). Swift ContiguousArray is a value type, so "
            + "the `cloned !== original` reference test is moot and clone() passes the value through. "
            + "(util.swift PORT-TODO: TYPED_ARRAY branch)")
    }

    // upstream: it('user_defined_class')
    func test_clone_user_defined_class() throws {
        throw XCTSkip("util.clone of a user-defined class instance → plain object (dropping "
            + "prototype props) is not modeled: Swift `clone` returns class instances by reference, "
            + "not a `{bb: 2}` plain object. (util.swift)")
    }
}
