// Behavioral oracle for EChartsKit `Model` (echarts/src/model/Model.ts).
//
// Upstream ECharts has NO dedicated `test/ut/spec/model/Model.test.ts`; the Model.get /
// getModel / mergeOption / parent-cascade behavior is exercised only *indirectly* by the
// createChart-based specs (Global.test.ts, timelineMediaOptions.test.ts — both Phase-6, see
// GlobalModelUnitTests / TimelineMediaOptionsUnitTests skips). Per the task brief ("Focus on
// option-merge + Model.get — the riskiest"), this file pins the ported dynamic-option engine
// directly against its documented upstream semantics (Model.ts lines 104-291):
//   - get() / get(path) / get([path]) keyed + dotted dynamic access
//   - getShallow (single-key, parent fallback)
//   - parent-model cascade + ignoreParent
//   - getModel (sub-Model wrapping + resolveParentPath chain)
//   - mergeOption (deep merge via util.merge)
//   - isEmpty / isAnimationEnabled / clone
//
// jest -> XCTest mapping as elsewhere (describe/it -> XCTestCase/test_ methods,
// toEqual -> XCTAssertEqual). Dynamic `ModelOption? (= Any?)` returns are down-cast at the
// assertion boundary via the `d(...)`/`s(...)` helpers.

import XCTest
@testable import EChartsKit

final class ModelUnitTests: XCTestCase {

    // MARK: - helpers (down-cast the dynamic ModelOption? bag)

    private func d(_ v: ModelOption?) -> Double? { v as? Double }
    private func s(_ v: ModelOption?) -> String? { v as? String }

    // MARK: - get: keyed / dotted / array path

    func test_get_noArg_returnsOption() {
        let m = Model(["x": 1.0])
        XCTAssertEqual(d(m.get("x")), 1.0)
        // path == null branch -> the whole option
        XCTAssertNotNil(m.get() as? [String: Any])
    }

    func test_get_dottedPath() {
        let opt: [String: Any] = ["a": ["b": ["c": 5.0]]]
        let m = Model(opt)
        XCTAssertEqual(d(m.get("a.b.c")), 5.0)
        XCTAssertEqual(d(m.get(["a", "b", "c"])), 5.0)
    }

    func test_get_missingPath_returnsNil() {
        let m = Model(["a": ["b": 1.0]] as [String: Any])
        XCTAssertNil(m.get("a.z"))
        XCTAssertNil(m.get("nope"))
        // Descending into a non-object stops at nil (obj = null; break).
        XCTAssertNil(m.get("a.b.c"))
    }

    func test_get_emptyPathSegmentIsIgnored() {
        // upstream `if (!pathArr[i]) continue;` — an empty segment is skipped.
        let opt: [String: Any] = ["a": ["b": 7.0]]
        let m = Model(opt)
        XCTAssertEqual(d(m.get(["a", "", "b"])), 7.0)
    }

    // MARK: - parent-model cascade

    func test_get_fallsThroughToParent() {
        let parent = Model(["color": "red", "size": 10.0] as [String: Any])
        let child = Model(["size": 20.0] as [String: Any], parent)
        XCTAssertEqual(d(child.get("size")), 20.0)   // own value wins
        XCTAssertEqual(s(child.get("color")), "red") // inherited from parent
    }

    func test_get_ignoreParent() {
        let parent = Model(["color": "red"] as [String: Any])
        let child = Model([:] as [String: Any], parent)
        XCTAssertEqual(s(child.get("color")), "red")
        // ignoreParent = true -> no cascade
        XCTAssertNil(child.get("color", true))
    }

    func test_getShallow_singleKeyWithParentFallback() {
        let parent = Model(["a": 1.0, "b": 2.0] as [String: Any])
        let child = Model(["a": 9.0] as [String: Any], parent)
        XCTAssertEqual(d(child.getShallow("a")), 9.0)
        XCTAssertEqual(d(child.getShallow("b")), 2.0)         // fall through
        XCTAssertNil(child.getShallow("b", true))             // ignoreParent
        XCTAssertNil(child.getShallow("missing"))
    }

    // MARK: - getModel (sub-Model wrapping + parent chain)

    func test_getModel_wrapsSubOption() {
        let m = Model(["itemStyle": ["color": "blue"]] as [String: Any])
        let sub = m.getModel("itemStyle")
        XCTAssertEqual(s(sub.get("color")), "blue")
    }

    func test_getModel_noArg_wrapsWholeOption() {
        let m = Model(["color": "green"] as [String: Any])
        let sub = m.getModel()
        XCTAssertEqual(s(sub.get("color")), "green")
    }

    func test_getModel_resolvesParentPathChain() {
        // child.getModel('itemStyle') should read own color, but inherit opacity through the
        // parent's own itemStyle sub-model (resolveParentPath identity chain).
        let parent = Model(["itemStyle": ["color": "red", "opacity": 0.5]] as [String: Any])
        let child = Model(["itemStyle": ["color": "blue"]] as [String: Any], parent)
        let sub = child.getModel("itemStyle")
        XCTAssertEqual(s(sub.get("color")), "blue")
        XCTAssertEqual(d(sub.get("opacity")), 0.5)
    }

    // MARK: - mergeOption (deep merge)

    func test_mergeOption_deepMerge() {
        let m = Model(["a": ["b": 1.0], "c": 2.0] as [String: Any])
        m.mergeOption(["a": ["d": 3.0], "e": 4.0] as [String: Any])
        XCTAssertEqual(d(m.get("a.b")), 1.0)   // preserved
        XCTAssertEqual(d(m.get("a.d")), 3.0)   // merged in
        XCTAssertEqual(d(m.get("c")), 2.0)     // preserved
        XCTAssertEqual(d(m.get("e")), 4.0)     // added
    }

    func test_mergeOption_overwritesScalar() {
        let m = Model(["a": 1.0] as [String: Any])
        m.mergeOption(["a": 9.0] as [String: Any])
        XCTAssertEqual(d(m.get("a")), 9.0)
    }

    // MARK: - isEmpty / clone / isAnimationEnabled

    func test_isEmpty() {
        XCTAssertTrue(Model(nil).isEmpty())
        XCTAssertFalse(Model([:] as [String: Any]).isEmpty())
    }

    func test_clone_copiesOption() {
        let m = Model(["a": 1.0] as [String: Any])
        let c = m.clone()
        XCTAssertEqual(d(c.get("a")), 1.0)
        // independent copy: mutating clone does not touch the original
        c.mergeOption(["a": 2.0] as [String: Any])
        XCTAssertEqual(d(c.get("a")), 2.0)
        XCTAssertEqual(d(m.get("a")), 1.0)
    }

    func test_isAnimationEnabled_truthiness() {
        XCTAssertEqual(Model(["animation": true] as [String: Any]).isAnimationEnabled(), true)
        XCTAssertEqual(Model(["animation": false] as [String: Any]).isAnimationEnabled(), false)
        // absent animation, no parent -> nil
        XCTAssertNil(Model([:] as [String: Any]).isAnimationEnabled())
        // inherits from parent
        let parent = Model(["animation": true] as [String: Any])
        let child = Model([:] as [String: Any], parent)
        XCTAssertEqual(child.isAnimationEnabled(), true)
    }
}
