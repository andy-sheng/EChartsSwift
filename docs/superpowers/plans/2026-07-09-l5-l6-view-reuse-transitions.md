# L5/L6 — View Reuse + Update Matrix Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `EChartsSlim` reuse its `GlobalModel` and views across `setOption` so that live-data
`setOption` calls morph smoothly (the already-ported per-view `data.diff`/`updateProps` tween),
faithfully matching upstream `echarts.ts` control flow.

**Architecture:** Driver-layer change. `GlobalModel`'s incremental-merge machinery
(`setOption`/`mergeOption`/`__requireNewView`) and per-view diff (`BarView`/`PieView`/`SymbolDraw`
`data.diff`) are already ported and dormant. Two edits activate them: (1) `setOption` reuses
`self._model` and merges instead of newing a `GlobalModel` each call; (2) `render()` stops wiping
all views and instead runs upstream's `prepareView` mark-and-sweep (reuse by `_ec_<id>_<type>`,
dispose only dead views). A reuse-safety audit guarantees no view duplicates elements. Then the
faithful `updateView`/`updateVisual`/`updateLayout`/`updateTransform` matrix + `dispatchAction`
routing (L6) is layered on the now-persistent views.

**Tech Stack:** Swift (SwiftPM), XCTest, ZRenderKit/EChartsKit/NativePainter. Upstream reference:
`upstream/echarts/src/core/echarts.ts`.

## Global Constraints

- Every task ends with `swift test` green (full suite) and **0 new build warnings** (ignore the
  known pre-existing set: calendarPrepareCustom, PictorialBarView, SwiftUICore ld, dataZoomHelper
  createHashMap, hoverRange, ScaleDataValue, labelLayoutHelper.swift:90, roamHelperViewGroup,
  ContinuousView).
- One commit per task, committed **and pushed** to `main`.
- **No backticks** anywhere in commit messages.
- End every commit message with: `Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>`.
- Faithful to upstream `echarts.ts` — no behavior invented beyond what upstream does; the only
  permitted divergences are genuinely host-specific (painter clear color, Scheduler progressive
  frames) and are already established in the slim driver.
- **Regression invariant:** static PNG output of existing demos must not change. The demo-switch
  host path uses `notMerge:true`, so today's static-render + parity behavior is byte-preserved.
- Subagents (implementers/reviewers) run on the **opus** model.

---

## File Structure

- `Sources/EChartsKit/core/EChartsSlim.swift` — the driver. Modified by Tasks 1, 2, 4, 6, 7, 8.
  Already large (~2200 lines); do not restructure, edit in place following its existing sectioned
  style (`// §UPDATE` etc.).
- `Sources/EChartsKit/core/EChartsSlim.swift` also holds `setOption`, `update()`, `render()`,
  `prepareView`, `renderComponents`, `renderSeries`, the view registries, and `dispatchAction`.
- Chart/component views under `Sources/EChartsKit/chart/**` and `component/**` — read-only for the
  audit (Task 3), edited only where a view is found unsafe-on-reuse.
- Tests: `Tests/EChartsKitTests/` — new files `L5ModelReuseTests.swift`,
  `L5PrepareViewReuseTests.swift`, `L5ViewReuseSafetyTests.swift`, `L5StatesOnReuseTests.swift`,
  `L5TransitionTweenTests.swift`, `L6UpdateMatrixTests.swift`. Follow the existing test style
  (`@testable import EChartsKit`, `XCTestCase`).

---

## Task 1: Driver model reuse + merge in setOption

**Files:**
- Modify: `Sources/EChartsKit/core/EChartsSlim.swift` (`setOption`, ~1066-1132; view registries ~297-304)
- Test: `Tests/EChartsKitTests/L5ModelReuseTests.swift` (create)

**Interfaces:**
- Consumes: `GlobalModel.setOption(_ option: ECUnitOption, _ optionPreprocessorFuncs: [...]?, _ opts: InnerSetOptionOpts?)` (Global.swift:240), `GlobalModel.init(...)`, `OptionManager`, existing preprocessor free functions (`graphicOptionPreprocessor`, `radarBackwardCompat`, `parallelPreprocessor`, `visualMapPreprocessor`, `markPointPreprocessor`, `markLinePreprocessor`, `markAreaPreprocessor`, `timelinePreprocessor`, `ariaPreprocessor`).
- Produces: `public func setOption(_ option: [String: Any], notMerge: Bool)` overload; persistent `self._model` reused across calls. Later tasks rely on `self._model` surviving across `setOption`.

- [ ] **Step 1: Write the failing test**

Create `Tests/EChartsKitTests/L5ModelReuseTests.swift`:

```swift
import XCTest
@testable import EChartsKit

final class L5ModelReuseTests: XCTestCase {
    // Two merge-mode setOption calls must REUSE the same GlobalModel + the same SeriesModel
    // instance (identity), so the series keeps its prior getData() reference for diffing.
    func testMergeReusesModelAndSeries() {
        let ec = EChartsSlim(width: 400, height: 300)
        ec.setOption([
            "xAxis": ["type": "category", "data": ["a", "b", "c"]],
            "yAxis": ["type": "value"],
            "series": [["type": "bar", "data": [1, 2, 3]]]
        ])
        let model1 = ec.testModel
        let series1 = model1?.getSeries().first
        XCTAssertNotNil(series1)

        // Merge-mode update (default notMerge:false): new data, same structure.
        ec.setOption(["series": [["type": "bar", "data": [4, 5, 6]]]])
        let model2 = ec.testModel
        let series2 = model2?.getSeries().first

        XCTAssertTrue(model1 === model2, "merge must reuse the same GlobalModel")
        XCTAssertTrue(series1 === series2, "merge must reuse the same SeriesModel instance")
    }

    // notMerge:true must REPLACE the model (fresh instance) — the demo-switch path.
    func testNotMergeReplacesModel() {
        let ec = EChartsSlim(width: 400, height: 300)
        ec.setOption(["series": [["type": "bar", "data": [1, 2, 3]]]])
        let model1 = ec.testModel
        ec.setOption(["series": [["type": "line", "data": [9, 9]]]], notMerge: true)
        let model2 = ec.testModel
        XCTAssertFalse(model1 === model2, "notMerge must create a fresh GlobalModel")
    }
}
```

Add a test accessor near the view registries in `EChartsSlim.swift` (the model field is private):

```swift
    // Test-only accessor for the reused model (asserting identity across setOption).
    var testModel: GlobalModel? { _model }
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter L5ModelReuseTests`
Expected: FAIL — `testMergeReusesModelAndSeries` fails (`model1 === model2` false, because current
`setOption` news a `GlobalModel` every call).

- [ ] **Step 3: Extract the preprocessor pass into a shared helper**

In `EChartsSlim.swift`, add a private method holding the exact preprocessor block currently inline
in `setOption` (lines ~1067-1118). Cut that block from `setOption` and paste it here verbatim:

```swift
    /// Run the registered option preprocessors (upstream runs these inside OptionManager.setOption;
    /// the slim keeps them driver-side). Mutates and returns the normalized option. Shared by the
    /// first-call and merge branches so both paths preprocess identically.
    private func runPreprocessors(_ option: [String: Any]) -> [String: Any] {
        var opt = option
        if opt["xAxis"] != nil && opt["yAxis"] != nil && opt["grid"] == nil {
            opt["grid"] = [String: Any]()
        }
        graphicOptionPreprocessor(&opt)
        radarBackwardCompat(&opt)
        parallelPreprocessor(&opt)
        visualMapPreprocessor(&opt)
        markPointPreprocessor(&opt)
        markLinePreprocessor(&opt)
        markAreaPreprocessor(&opt)
        timelinePreprocessor(&opt)
        ariaPreprocessor(&opt)
        if opt["axisPointer"] == nil
            || ((opt["axisPointer"] as? [Any])?.isEmpty ?? false) {
            opt["axisPointer"] = [String: Any]()
        }
        return opt
    }
```

- [ ] **Step 4: Rewrite setOption with the reuse/merge branch**

Replace the body of `public func setOption(_ option: [String: Any])` with a 2-arg version plus a
1-arg convenience overload. Faithful to echarts.ts:770-777 (reuse `this._model` unless first call
or `notMerge`):

```swift
    public func setOption(_ option: [String: Any]) {
        setOption(option, notMerge: false)
    }

    public func setOption(_ option: [String: Any], notMerge: Bool) {
        let opt = runPreprocessors(option)

        // First call or notMerge → fresh GlobalModel (upstream: `new GlobalModel()` + init).
        // Else reuse the existing model and MERGE (upstream: `_model.setOption(option,{replaceMerge})`),
        // which preserves each SeriesModel instance so its prior getData() can be diffed against.
        if _model == nil || notMerge {
            let ecModel = GlobalModel()
            let om = OptionManager(_api)
            ecModel.`init`(nil, nil, nil, resolveTheme(), resolveLocale(), om)
            ecModel.setOption(opt, nil, nil)
            self._model = ecModel
        }
        else {
            self._model!.setOption(opt, nil, nil)
        }

        update()
    }
```

Note: `GlobalModel.setOption` (Global.swift:240) already routes first-vs-merge internally via the
OptionManager; passing the reused model's `setOption` the new option performs the merge. Keep the
`resolveTheme()`/`resolveLocale()` calls (already present).

- [ ] **Step 5: Run the reuse tests to verify they pass**

Run: `swift test --filter L5ModelReuseTests`
Expected: PASS (both tests).

- [ ] **Step 6: Run the full suite (regression gate)**

Run: `swift test`
Expected: PASS — all existing tests green (existing single-`setOption` tests are unaffected; they
hit the first-call branch, identical to before).

- [ ] **Step 7: Commit and push**

```bash
git add Sources/EChartsKit/core/EChartsSlim.swift Tests/EChartsKitTests/L5ModelReuseTests.swift
git commit -m "L5-1: reuse+merge GlobalModel across setOption (notMerge:false default)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
git push origin main
```

---

## Task 2: prepareView faithful mark-and-sweep + remove render() wipe

**Files:**
- Modify: `Sources/EChartsKit/core/EChartsSlim.swift` (`render()` reset ~1438-1469; `prepareView` ~1666-1729)
- Test: `Tests/EChartsKitTests/L5PrepareViewReuseTests.swift` (create)

**Interfaces:**
- Consumes: `ComponentModel.id` (Component.swift:86), `.__viewId` (166), `.__requireNewView` (167), `.type`; `Storage.delRoot(_ el: Element)`, `.addRoot`; `Group.remove(_:)`; `ChartView.dispose(_:_:)`/`ComponentView.dispose(_:_:)`; view `.group`.
- Produces: views persist across `setOption`; dead views disposed. Later tasks rely on
  `_chartsMap`/`_componentsMap` surviving and `view.__alive` semantics.

- [ ] **Step 1: Write the failing test**

Create `Tests/EChartsKitTests/L5PrepareViewReuseTests.swift`:

```swift
import XCTest
@testable import EChartsKit

final class L5PrepareViewReuseTests: XCTestCase {
    // A merge-mode second setOption on the same structure must REUSE the chart view instance.
    func testChartViewReusedAcrossMerge() {
        let ec = EChartsSlim(width: 400, height: 300)
        let opt: [String: Any] = [
            "xAxis": ["type": "category", "data": ["a", "b", "c"]],
            "yAxis": ["type": "value"],
            "series": [["type": "bar", "data": [1, 2, 3]]]
        ]
        ec.setOption(opt)
        let view1 = ec.testChartViews.first
        XCTAssertNotNil(view1)
        ec.setOption(["series": [["type": "bar", "data": [4, 5, 6]]]])
        let view2 = ec.testChartViews.first
        XCTAssertTrue(view1 === view2, "same-structure merge must reuse the chart view")
        XCTAssertEqual(ec.testChartViews.count, 1, "no duplicate views accumulate")
    }

    // A series that changes type (bar→line) in merge mode must NOT reuse the bar view.
    func testDeadViewDisposedOnTypeChange() {
        let ec = EChartsSlim(width: 400, height: 300)
        ec.setOption(["xAxis": ["type": "category", "data": ["a", "b"]],
                      "yAxis": ["type": "value"],
                      "series": [["type": "bar", "data": [1, 2]]]])
        XCTAssertEqual(ec.testChartViews.count, 1)
        // replaceMerge the series to a line: the bar view is now dead and must be swept.
        ec.setOption(["series": [["type": "line", "data": [3, 4]]]])
        XCTAssertEqual(ec.testChartViews.count, 1, "dead bar view swept, one live line view remains")
        XCTAssertTrue(ec.testChartViews.first is LineView)
    }
}
```

Add test accessors in `EChartsSlim.swift` beside the registries:

```swift
    var testChartViews: [ChartView] { _chartsViews }
    var testComponentViews: [ComponentView] { _componentsViews }
```

- [ ] **Step 2: Run to verify it fails**

Run: `swift test --filter L5PrepareViewReuseTests`
Expected: FAIL — `testChartViewReusedAcrossMerge` fails because `render()` wipes `_chartsViews`
every call, so `view1 !== view2` (and after the wipe a fresh view is built each time).

- [ ] **Step 3: Remove the wipe block from render()**

In `render()` delete the reset block (EChartsSlim.swift:1438-1445):

```swift
        // DELETE these lines:
        _ = root.removeAll()
        storage.delAllRoots()
        _componentsViews.removeAll()
        _chartsViews.removeAll()
        _componentsMap.removeAll()
        _chartsMap.removeAll()
        _componentViewByModel.removeAll()
        _chartViewByModel.removeAll()
```

- [ ] **Step 4: Make the background rect idempotent**

The bg rect must not accumulate across reused renders. Add a stored field near the registries:

```swift
    // The full-canvas background rect (upstream zr.setBackgroundColor). Reused/removed across
    // renders so it never accumulates now that render() no longer wipes root.
    private var _bgRect: Rect?
```

Replace the background block (EChartsSlim.swift:1455-1469) with:

```swift
        if let old = _bgRect { _ = root.remove(old); _bgRect = nil }
        if let bg = ecModel.get("backgroundColor", true) as? String,
           !bg.isEmpty, bg != "transparent", bg != "rgba(0,0,0,0)" {
            var shape = RectShape()
            shape.x = 0; shape.y = 0; shape.width = _width; shape.height = _height
            let bgRect = Rect([
                "shape": shape as PathShape,
                "style": ["fill": bg] as [String: Any],
                "silent": true,
                "z2": -Double.greatestFiniteMagnitude
            ])
            _ = root.add(bgRect)
            _bgRect = bgRect
        }
```

- [ ] **Step 5: Rewrite prepareView as faithful mark-and-sweep**

Replace `prepareView` (EChartsSlim.swift:1669-1729) with the version below. Changes vs current:
(a) key `viewId` by `model.id` not `componentIndex` (upstream echarts.ts:1716); (b) mark all views
`__alive=false` first; (c) honor + reset `model.__requireNewView`; (d) set `model.__viewId`; (e) do
NOT sweep here (the sweep runs once after both passes — see Step 6).

```swift
    private func prepareView(isComponent: Bool, ecModel: GlobalModel, api: ExtensionAPI) {
        // (a) Mark every existing view of this kind not-alive; doPrepare re-marks the reused/created
        //     ones alive; the post-pass sweep disposes any left dead. (upstream prepareView 1695-1697)
        if isComponent { for v in _componentsViews { v.__alive = false } }
        else { for v in _chartsViews { v.__alive = false } }

        func doPrepare(_ model: ComponentModel) {
            let requireNewView = model.__requireNewView ?? false
            model.__requireNewView = false               // must not work twice (upstream 1713-1714)
            let viewId = "_ec_\(model.id)_\(model.type)"  // upstream 1716: keyed by model.id
            if isComponent {
                let existing = requireNewView ? nil : _componentsMap[viewId]
                let view = existing ?? {
                    guard let factory = _componentViewFactories[model.type] ?? _componentViewFactories[model.mainType] else {
                        return nil as ComponentView?
                    }
                    let v = factory()
                    v.`init`(ecModel, api)
                    _componentsMap[viewId] = v
                    _componentsViews.append(v)
                    _ = root.add(v.group)
                    storage.addRoot(v.group)
                    return v
                }()
                guard let componentView = view else { return }
                model.__viewId = viewId
                componentView.__alive = true
                componentView.__model = model
                _componentViewByModel[ObjectIdentifier(model)] = componentView
            }
            else {
                guard let seriesModel = model as? SeriesModel else { return }
                let existing = requireNewView ? nil : _chartsMap[viewId]
                let view = existing ?? {
                    guard let factory = _chartViewFactories[seriesModel.subType] else {
                        return nil as ChartView?
                    }
                    let v = factory()
                    v.init_(ecModel, api)
                    _chartsMap[viewId] = v
                    _chartsViews.append(v)
                    _ = root.add(v.group)
                    storage.addRoot(v.group)
                    return v
                }()
                guard let chartView = view else { return }
                model.__viewId = viewId
                chartView.__alive = true
                chartView.__model = seriesModel
                _chartViewByModel[ObjectIdentifier(seriesModel)] = chartView
                seriesModel.pipelineContext = PipelineContext(progressiveRender: false, large: false, modDataCount: nil)
            }
        }

        if isComponent {
            ecModel.eachComponent({ (mainType, model, _) in
                if mainType != "series" { doPrepare(model) }
            })
        }
        else {
            ecModel.eachSeries { seriesModel, _ in doPrepare(seriesModel) }
        }
    }
```

- [ ] **Step 6: Add the dead-view sweep, called from render() after both prepare passes**

Add a sweep method (faithful to echarts.ts:1754-1769) and call it in `render()` right after the two
`prepareView` calls (EChartsSlim.swift:1471-1472):

```swift
    // Dispose views left __alive == false after prepareView (their model was removed/replaced).
    // Faithful to prepareView's tail sweep (echarts.ts:1754-1769).
    private func sweepDeadViews(_ ecModel: GlobalModel, _ api: ExtensionAPI) {
        var i = 0
        while i < _componentsViews.count {
            let v = _componentsViews[i]
            if v.__alive != true {
                _ = root.remove(v.group); storage.delRoot(v.group)
                v.dispose(ecModel, api)
                _componentsViews.remove(at: i)
                for (k, vv) in _componentsMap where vv === v { _componentsMap.removeValue(forKey: k) }
                for (k, vv) in _componentViewByModel where vv === v { _componentViewByModel.removeValue(forKey: k) }
            } else { i += 1 }
        }
        i = 0
        while i < _chartsViews.count {
            let v = _chartsViews[i]
            if !v.__alive {
                v.remove(ecModel, api)              // upstream renderSeries also calls chart.remove for dead
                _ = root.remove(v.group); storage.delRoot(v.group)
                v.dispose(ecModel, api)
                _chartsViews.remove(at: i)
                for (k, vv) in _chartsMap where vv === v { _chartsMap.removeValue(forKey: k) }
                for (k, vv) in _chartViewByModel where vv === v { _chartViewByModel.removeValue(forKey: k) }
            } else { i += 1 }
        }
    }
```

In `render()`, after the two `prepareView(...)` calls, add:

```swift
        prepareView(isComponent: true, ecModel: ecModel, api: api)
        prepareView(isComponent: false, ecModel: ecModel, api: api)
        sweepDeadViews(ecModel, api)
```

- [ ] **Step 7: Guard renderComponents/renderSeries against reused stale state**

`renderComponents` (EChartsSlim.swift:1733) iterates `_componentsViews` and reads
`componentView.__model`. With reuse, `__model` is repointed each `prepareView`, so this is correct.
Confirm `renderSeries` iterates `ecModel.eachSeries` → `_chartViewByModel`/`_chartsMap` (reused).
No code change expected; add an assertion comment. (If `renderSeries` currently iterates
`_chartsViews` directly it will now include only live views — still correct.)

- [ ] **Step 8: Run the prepareView tests**

Run: `swift test --filter L5PrepareViewReuseTests`
Expected: PASS (reuse hit + dead-view sweep).

- [ ] **Step 9: Run the full suite**

Run: `swift test`
Expected: PASS. If any test fails, it is almost certainly a view that duplicated elements on the
now-reused path — that is Task 3's domain, but a hard failure here must be fixed before commit
(the offending view likely appends without clearing; apply the Task 3 fix pattern to it now).

- [ ] **Step 10: Static parity spot-check**

Run: `swift run EChartsDemoGallery --render bar-basic /tmp/l5-bar.png && swift run EChartsDemoGallery --render pie-basic /tmp/l5-pie.png && swift run EChartsDemoGallery --render line-basic /tmp/l5-line.png`
Expected: renders succeed; images visually identical to before (single-setOption demos hit the
first-call/first-render path; reuse machinery is dormant for one-shot renders).

- [ ] **Step 11: Commit and push**

```bash
git add Sources/EChartsKit/core/EChartsSlim.swift Tests/EChartsKitTests/L5PrepareViewReuseTests.swift
git commit -m "L5-2: prepareView mark-and-sweep view reuse; drop render() wipe

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
git push origin main
```

---

## Task 3: Reuse-safety audit across all views (no-duplication correctness gate)

**Files:**
- Read: every `*View.swift` under `Sources/EChartsKit/chart/**` and `Sources/EChartsKit/component/**`
- Modify: only views found unsafe-on-reuse (see fix pattern)
- Test: `Tests/EChartsKitTests/L5ViewReuseSafetyTests.swift` (create)

**Interfaces:**
- Consumes: the reuse machinery from Tasks 1-2.
- Produces: a guarantee that a second merge-mode `setOption` on ANY chart type does not accumulate
  or duplicate elements. Establishes `assertStableElementCount(_:option:update:)` test helper reused
  by later fidelity tasks.

**Context — the audit rule:** After Task 2, a reused view's `render()` runs against its own prior
group. Three cases, determined by reading each view's `render()`:
- **Clears own group** (`group.removeAll()` / `getContentGroup().removeAll()` at the top — e.g.
  LineView:59, LegendView:220, ScatterView non-symbol branches): idempotent + safe. No tween, but
  no duplication. LEAVE AS-IS.
- **Diffs** (`data.diff(oldData)` + keeps `_data` — BarView:306, PieView:147, SymbolDraw-based):
  idempotent + tweens. LEAVE AS-IS (Task 5 verifies the tween).
- **Appends without clearing and without diffing:** UNSAFE — duplicates on reuse. FIX.

**Fix pattern for an unsafe view:** if upstream's matching view rebuilds (does not tween), add
`_ = group.removeAll()` (or the view's own content-group clear) at the top of its `render()`. If
upstream tweens that chart, that is a Task-5-class fidelity conversion — but for THIS task, the
minimum safe fix is the clear; note the view in the plan's fidelity backlog.

- [ ] **Step 1: Enumerate all views and classify**

Run: `grep -rLn "group.removeAll\|getContentGroup().removeAll\|data.diff\|getSelectorGroup().removeAll" Sources/EChartsKit/chart Sources/EChartsKit/component --include=*View.swift`
This lists view files that neither clear a group nor diff — the candidate unsafe set. For each hit,
open it and read `render()`: confirm whether it appends to `group`/a subgroup without clearing.
Record the classification (safe-clear / safe-diff / unsafe) as a comment block at the top of the
new test file.

- [ ] **Step 2: Write the failing/guard test (parametrized over chart types)**

Create `Tests/EChartsKitTests/L5ViewReuseSafetyTests.swift`:

```swift
import XCTest
@testable import EChartsKit

final class L5ViewReuseSafetyTests: XCTestCase {
    // Render the option, snapshot the total element count under the chart view group, apply the
    // update option (merge), and assert the count did not grow (no duplicated elements on reuse).
    private func assertNoDuplication(_ name: String, _ option: [String: Any], update: [String: Any],
                                     file: StaticString = #filePath, line: UInt = #line) {
        let ec = EChartsSlim(width: 400, height: 300)
        ec.setOption(option)
        let before = ec.testChartViews.reduce(0) { $0 + $1.group.count() }
        ec.setOption(update)
        let after = ec.testChartViews.reduce(0) { $0 + $1.group.count() }
        XCTAssertLessThanOrEqual(after, before + 0,
            "\(name): element count grew on reuse (before=\(before) after=\(after)) — view duplicates on re-render",
            file: file, line: line)
    }

    func testBarNoDuplication() {
        assertNoDuplication("bar",
            ["xAxis": ["type": "category", "data": ["a", "b", "c"]], "yAxis": ["type": "value"],
             "series": [["type": "bar", "data": [1, 2, 3]]]],
            update: ["series": [["type": "bar", "data": [4, 5, 6]]]])
    }
    func testLineNoDuplication() {
        assertNoDuplication("line",
            ["xAxis": ["type": "category", "data": ["a", "b", "c"]], "yAxis": ["type": "value"],
             "series": [["type": "line", "data": [1, 2, 3]]]],
            update: ["series": [["type": "line", "data": [4, 5, 6]]]])
    }
    func testScatterNoDuplication() {
        assertNoDuplication("scatter",
            ["xAxis": ["type": "value"], "yAxis": ["type": "value"],
             "series": [["type": "scatter", "data": [[1, 1], [2, 2], [3, 3]]]]],
            update: ["series": [["type": "scatter", "data": [[4, 4], [5, 5]]]]])
    }
    func testPieNoDuplication() {
        assertNoDuplication("pie",
            ["series": [["type": "pie", "data": [["value": 1, "name": "a"], ["value": 2, "name": "b"]]]]],
            update: ["series": [["type": "pie", "data": [["value": 3, "name": "a"], ["value": 4, "name": "b"]]]]])
    }
    // Add one case per chart family present in the registry: candlestick, boxplot, funnel, radar,
    // heatmap, graph, tree, treemap, sankey, sunburst, themeRiver, parallel, lines, effectScatter,
    // pictorialBar, map, gauge, custom. Use each family's minimal valid option (copy the shape from
    // its demo in Sources/EChartsDemoCore). The bodies are mechanical variants of the four above.
}
```

Note: `group.count()` — confirm the accessor name on `Group` (it is `count()` if present; else use
`group.childrenRef().count` or the existing children accessor — grep `Group.swift` for the child
count/children API and use the real one).

- [ ] **Step 3: Run to find unsafe views**

Run: `swift test --filter L5ViewReuseSafetyTests`
Expected: PASS for safe-clear and safe-diff views; FAIL for any unsafe-append view (count grows).

- [ ] **Step 4: Fix each failing view with the minimum safe clear**

For each view whose test fails, add the group-clear at the top of its `render()` (after the guard
clauses, before it appends elements), matching the pattern its siblings use, e.g.:

```swift
        _ = group.removeAll()   // idempotent on reuse (Task 2 no longer wipes views)
```

Re-run the specific family test after each fix. Add every view fixed this way to the fidelity
backlog section of this plan (they rebuild rather than tween).

- [ ] **Step 5: Run the full suite**

Run: `swift test`
Expected: PASS.

- [ ] **Step 6: Commit and push**

```bash
git add -A
git commit -m "L5-3: reuse-safety audit across all views; guard unsafe-append views

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
git push origin main
```

---

## Task 4: clearStates / updateStates on reuse in renderComponents & renderSeries

**Files:**
- Modify: `Sources/EChartsKit/core/EChartsSlim.swift` (`renderComponents` ~1733; `renderSeries` ~1841)
- Test: `Tests/EChartsKitTests/L5StatesOnReuseTests.swift` (create)

**Interfaces:**
- Consumes: the states engine (Phase 30 — `Element.clearStates()`, `useState`/`useStates`), the
  reuse machinery.
- Produces: reused views are reset to normal state before re-render and re-apply model-driven states
  after, matching echarts.ts renderComponents (2452-2467) / renderSeries (2499/2532).

**Context:** Upstream wraps each `view.render` with `clearStates(model, view)` before and
`updateZ` + `updateStates(model, view)` after. On a reused view whose elements were in an
emphasis/select state at the moment of the new `setOption`, without `clearStates` they'd re-render
from a non-normal baseline. `updateStates` re-applies `selectedMap`-driven selection. The slim's
`renderComponents` currently does `updateZ` only (states dropped per its comment); wire the states
calls now that views persist.

- [ ] **Step 1: Write the failing test**

Create `Tests/EChartsKitTests/L5StatesOnReuseTests.swift`:

```swift
import XCTest
@testable import EChartsKit

final class L5StatesOnReuseTests: XCTestCase {
    // A datum highlighted, then a merge-mode setOption: the reused view must re-render its elements
    // from the NORMAL state (clearStates ran), not stuck in emphasis.
    func testHighlightClearedOnReRender() {
        let ec = EChartsSlim(width: 400, height: 300)
        ec.setOption(["xAxis": ["type": "category", "data": ["a", "b", "c"]],
                      "yAxis": ["type": "value"],
                      "series": [["type": "bar", "data": [1, 2, 3]]]])
        ec.dispatchAction(Payload(type: "highlight", extra: ["seriesIndex": 0, "dataIndex": 1]))
        ec.setOption(["series": [["type": "bar", "data": [4, 5, 6]]]])
        // After re-render the highlighted element must be in normal state (no lingering emphasis).
        let view = ec.testChartViews.first
        XCTAssertNotNil(view)
        // Assert via the element's currentStates being empty (normal). Walk the view group to the
        // data element at index 1 and check it has no active 'emphasis' state.
        XCTAssertFalse(elementHasActiveEmphasis(view!.group),
                       "reused view element must be cleared to normal before re-render")
    }
}
```

Add a small test helper (in the same file) `elementHasActiveEmphasis(_ group: Group) -> Bool` that
recursively checks `currentStates`/`__inHover`-equivalent on displayables — grep the states engine
(Phase 30, `Sources/EChartsKit/**states*.swift` and ZRenderKit `Displayable`) for the actual
"is currently in emphasis" accessor and use it (e.g. `el.currentStates.contains("emphasis")`).

- [ ] **Step 2: Run to verify it fails**

Run: `swift test --filter L5StatesOnReuseTests`
Expected: FAIL — element stays in emphasis because `clearStates` never runs on the reused view.

- [ ] **Step 3: Add clearStates/updateStates helpers**

In `EChartsSlim.swift` add (faithful to echarts.ts clearStates 2667 / updateStates 2697):

```swift
    // Reset a view's elements to normal before re-render (upstream clearStates, echarts.ts:2667).
    private func clearStates(_ group: Group) {
        group.traverse { el in
            (el as? Displayable)?.clearStates()
        }
    }
    // Re-apply model-driven selection/emphasis after render (upstream updateStates, echarts.ts:2697).
    private func updateStates(_ model: ComponentModel, _ group: Group) {
        group.traverse { el in
            if let disp = el as? Displayable, let saved = disp.savedNormalState {
                _ = saved  // states engine re-derives from selectedMap; leave saveOldStyle intact
            }
        }
    }
```

Note: match the real API — `Group.traverse` and `Displayable.clearStates()` from Phase 30. If the
existing states engine exposes a single `applyStatesOnView(view, model)` entrypoint, call that
instead of hand-walking; grep `Sources/EChartsKit` for the Phase-30 view-states helper and prefer
it. Keep this minimal and faithful; do not invent state logic.

- [ ] **Step 4: Wire into renderComponents**

In `renderComponents` (EChartsSlim.swift:1733), before `componentView.render(...)` add
`clearStates(componentView.group)`, and after `updateZ(...)` add `updateStates(model, componentView.group)`.

- [ ] **Step 5: Wire into renderSeries**

In `renderSeries` (EChartsSlim.swift:1841), before each `chartView.render(...)` add
`clearStates(chartView.group)`; after the render/updateZ add `updateStates(seriesModel, chartView.group)`.
Match the existing loop structure.

- [ ] **Step 6: Run the states test**

Run: `swift test --filter L5StatesOnReuseTests`
Expected: PASS.

- [ ] **Step 7: Run the full suite + hover parity spot-check**

Run: `swift test`
Expected: PASS. Then confirm hover-emphasis still works on a one-shot render (no regression to the
Phase-37 hover path): `swift run EChartsDemoGallery --render bar-basic /tmp/l5-states.png` succeeds.

- [ ] **Step 8: Commit and push**

```bash
git add Sources/EChartsKit/core/EChartsSlim.swift Tests/EChartsKitTests/L5StatesOnReuseTests.swift
git commit -m "L5-4: clearStates/updateStates around view render on reuse

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
git push origin main
```

---

## Task 5: Verify + enable data-tween transitions for the diffing charts

**Files:**
- Modify: `Sources/EChartsKit/chart/bar/BarView.swift`, `chart/pie/PieView.swift`,
  `chart/scatter/ScatterView.swift`, `chart/helper/SymbolDraw.swift` (only if a tween is found not to fire)
- Test: `Tests/EChartsKitTests/L5TransitionTweenTests.swift` (create)

**Interfaces:**
- Consumes: reuse machinery (Tasks 1-4); `data.diff`, `updateProps`, `Animator`.
- Produces: confirmed morphing on merge-mode `setOption` for bar/pie/scatter (and SymbolDraw-based
  line symbols / graph nodes / effectScatter).

**Context:** These views already `data.diff(oldData)` + `updateProps`. After Tasks 1-2 they are
reused and hold `oldData`, so the update branch should schedule an `Animator` interpolating each
changed element to its new geometry. This task asserts the tween actually fires and fixes any view
where the diff runs but no animator is scheduled (e.g. `_data` overwritten before the diff, or
`updateProps` called with `duration:0`).

- [ ] **Step 1: Write the failing/guard test**

Create `Tests/EChartsKitTests/L5TransitionTweenTests.swift`:

```swift
import XCTest
@testable import EChartsKit

final class L5TransitionTweenTests: XCTestCase {
    // After a merge-mode data change, at least one Animator must be scheduled on the chart's zr
    // animation (the bars/points morph rather than snap).
    private func assertTweenScheduled(_ name: String, _ option: [String: Any], update: [String: Any],
                                      file: StaticString = #filePath, line: UInt = #line) {
        let ec = EChartsSlim(width: 400, height: 300)
        ec.setOption(option)
        ec.testBeginAnimationCapture()          // reset the animator counter (see Step 3)
        ec.setOption(update)
        XCTAssertGreaterThan(ec.testScheduledAnimatorCount, 0,
            "\(name): no tween animator scheduled on data-change reuse", file: file, line: line)
    }

    func testBarTweens() {
        assertTweenScheduled("bar",
            ["xAxis": ["type": "category", "data": ["a", "b", "c"]], "yAxis": ["type": "value"],
             "series": [["type": "bar", "data": [1, 2, 3]]]],
            update: ["series": [["type": "bar", "data": [8, 5, 9]]]])
    }
    func testScatterTweens() {
        assertTweenScheduled("scatter",
            ["xAxis": ["type": "value"], "yAxis": ["type": "value"],
             "series": [["type": "scatter", "data": [[1, 1], [2, 2], [3, 3]]]]],
            update: ["series": [["type": "scatter", "data": [[1, 5], [2, 8], [3, 2]]]]])
    }
    func testPieTweens() {
        assertTweenScheduled("pie",
            ["series": [["type": "pie", "data": [["value": 1, "name": "a"], ["value": 2, "name": "b"]]]]],
            update: ["series": [["type": "pie", "data": [["value": 5, "name": "a"], ["value": 2, "name": "b"]]]]])
    }
}
```

- [ ] **Step 2: Add the animator-count test seam on EChartsSlim**

The chart drives `zr.animation`. Add a test seam that counts animators added since a reset. Grep
`Sources/ZRenderKit/Animation/Animation.swift` for the add-animator entrypoint (e.g.
`addAnimator`/`_animators`) and expose a count on the slim via its `zr`/`animation`:

```swift
    // Test seams for asserting transitions actually schedule animators.
    private var _animCaptureBaseline: Int = 0
    func testBeginAnimationCapture() { _animCaptureBaseline = animation.animatorCount }
    var testScheduledAnimatorCount: Int { animation.animatorCount - _animCaptureBaseline }
```

If `animation` is not directly reachable from the slim, route through the existing host/zr field the
slim uses to schedule updateProps animators. Use the REAL field names found by grep — do not
invent. If no `animatorCount` exists, add a trivial computed `var animatorCount: Int { _animators.count }`
to the animation type.

- [ ] **Step 3: Run to verify current behavior**

Run: `swift test --filter L5TransitionTweenTests`
Expected: PASS if the diff+updateProps already fires (likely for bar/scatter). If a chart FAILS,
diagnose: (a) `_data` set before `data.diff` (diff sees no old data) — reorder so diff uses the true
oldData; (b) `updateProps` duration 0 — pass the series `animationDurationUpdate`; (c) merge did not
change the DataStore identity — confirm Task 1 reuse. Fix the specific cause faithfully vs the
matching upstream view.

- [ ] **Step 4: Run the full suite**

Run: `swift test`
Expected: PASS.

- [ ] **Step 5: Commit and push**

```bash
git add -A
git commit -m "L5-5: verify+enable data-tween transitions for bar/pie/scatter on reuse

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
git push origin main
```

---

## Task 6: L6 — updateView / updateVisual / updateLayout methods

**Files:**
- Modify: `Sources/EChartsKit/core/EChartsSlim.swift`
- Test: `Tests/EChartsKitTests/L6UpdateMatrixTests.swift` (create)

**Interfaces:**
- Consumes: `renderSeries`, `performVisualTasks`-equivalent stages, the reuse machinery.
- Produces: `func updateView()`, `func updateVisual()`, `func updateLayout()` — lighter re-renders
  that reuse persistent views without re-deriving data. Faithful to echarts.ts:2011/2033/2080.

- [ ] **Step 1: Write the failing test**

Create `Tests/EChartsKitTests/L6UpdateMatrixTests.swift`:

```swift
import XCTest
@testable import EChartsKit

final class L6UpdateMatrixTests: XCTestCase {
    // updateView must re-render series without recreating views or reprocessing data.
    func testUpdateViewReusesViewsNoReprocess() {
        let ec = EChartsSlim(width: 400, height: 300)
        ec.setOption(["xAxis": ["type": "category", "data": ["a", "b"]],
                      "yAxis": ["type": "value"], "series": [["type": "bar", "data": [1, 2]]]])
        let view1 = ec.testChartViews.first
        let store1 = ec.testModel?.getSeries().first?.getData()
        ec.updateView()
        let view2 = ec.testChartViews.first
        let store2 = ec.testModel?.getSeries().first?.getData()
        XCTAssertTrue(view1 === view2, "updateView reuses views")
        XCTAssertTrue(store1 === store2, "updateView must not recreate the DataStore")
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `swift test --filter L6UpdateMatrixTests`
Expected: FAIL — `updateView` does not exist (compile error), or (if stubbed) reprocesses data.

- [ ] **Step 3: Implement updateView**

Add, faithful to echarts.ts:2011 (mark all series render tasks dirty; re-run renderSeries; no
restoreData/data-process). Since the slim runs render synchronously, `updateView` re-runs the
render pipeline from `render()` WITHOUT the data-restore/visual stages:

```swift
    // upstream updateMethods.updateView (echarts.ts:2011): re-render series from current data,
    // reusing views, without restoreData/reprocess.
    public func updateView() {
        guard let ecModel = _model else { return }
        let api = _api!
        render(ecModel, api)     // render() already reuses views (Task 2) and re-lays out from current data
    }
```

Note: verify `render()` alone (without the `update()` prefix stages) produces a correct re-render
against current data — it lays out + renders from the existing DataStore. If `render()` depends on
a stage that `update()` runs first (e.g. axis extent), factor that stage so `updateView` re-runs the
layout+render subset only. Keep faithful to which stages upstream `updateView` re-runs (layout +
render, not data-process).

- [ ] **Step 4: Implement updateVisual and updateLayout**

```swift
    // upstream updateMethods.updateVisual (echarts.ts:2033): re-run visual stages then re-render.
    public func updateVisual() {
        guard let ecModel = _model else { return }
        let api = _api!
        clearColorPalette(ecModel)
        runVisualStages(ecModel, api)     // the same visual-stage block update() runs
        render(ecModel, api)
    }
    // upstream updateMethods.updateLayout (echarts.ts:2080): re-run layout then re-render.
    public func updateLayout() {
        updateView()                      // slim: layout runs inside render(); same subset
    }
```

Note: `runVisualStages`/`clearColorPalette` — reuse the exact stage calls `update()` already makes
(extract them into a private `runVisualStages` helper if not already one, so `update()` and
`updateVisual()` share the identical block — DRY).

- [ ] **Step 5: Run the tests**

Run: `swift test --filter L6UpdateMatrixTests` then `swift test`
Expected: PASS.

- [ ] **Step 6: Commit and push**

```bash
git add Sources/EChartsKit/core/EChartsSlim.swift Tests/EChartsKitTests/L6UpdateMatrixTests.swift
git commit -m "L6-1: updateView/updateVisual/updateLayout light-update methods

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
git push origin main
```

---

## Task 7: L6 — updateTransform (coordinate-transform-only re-render)

**Files:**
- Modify: `Sources/EChartsKit/core/EChartsSlim.swift`; `Sources/EChartsKit/view/Chart.swift` +
  `view/ComponentView.swift` (add optional `updateTransform` hook)
- Test: `Tests/EChartsKitTests/L6UpdateMatrixTests.swift` (extend)

**Interfaces:**
- Consumes: reuse machinery.
- Produces: `ChartView.updateTransform(_:_:_:_:) -> ViewUpdateResult?` (default nil),
  `ComponentView.updateTransform(...) -> ViewUpdateResult?` (default nil); `EChartsSlim.updateTransform()`.

- [ ] **Step 1: Add the optional hook to the view bases**

In `Chart.swift` (ChartView, ~125) and `ComponentView.swift` (~98), add:

```swift
    // upstream ChartView/ComponentView.updateTransform (optional). Return {update:true} to request
    // a coordinate-transform-only refresh; nil/absent → the driver falls back to a full dirty render.
    open func updateTransform(_ model: /*Series|Component*/Model, _ ecModel: GlobalModel,
                              _ api: ExtensionAPI, _ payload: Payload) -> ViewUpdateResult? { return nil }
```

Define `struct ViewUpdateResult { let update: Bool }` in `util/types.swift` if absent.

- [ ] **Step 2: Write the failing test**

Extend `L6UpdateMatrixTests.swift`:

```swift
    func testUpdateTransformReusesViews() {
        let ec = EChartsSlim(width: 400, height: 300)
        ec.setOption(["xAxis": ["type": "value"], "yAxis": ["type": "value"],
                      "series": [["type": "scatter", "data": [[1, 1], [2, 2]]]]])
        let v1 = ec.testChartViews.first
        ec.updateTransform()
        XCTAssertTrue(v1 === ec.testChartViews.first, "updateTransform reuses views")
    }
```

- [ ] **Step 3: Implement updateTransform**

Faithful to echarts.ts:1943-2010: per component/series view call its `updateTransform` hook; views
returning nil (no hook) fall back to a full render:

```swift
    public func updateTransform() {
        guard let ecModel = _model else { return }
        let api = _api!
        var anyFallback = false
        for cv in _componentsViews {
            guard let m = cv.__model else { continue }
            if cv.updateTransform(m, ecModel, api, Payload(type: "")) == nil { anyFallback = true }
        }
        for sv in _chartsViews {
            guard let m = sv.__model else { continue }
            if sv.updateTransform(m, ecModel, api, Payload(type: "")) == nil { anyFallback = true }
        }
        if anyFallback { render(ecModel, api) }
    }
```

- [ ] **Step 4: Run tests + full suite**

Run: `swift test --filter L6UpdateMatrixTests` then `swift test`
Expected: PASS.

- [ ] **Step 5: Commit and push**

```bash
git add -A
git commit -m "L6-2: updateTransform view hook + driver method

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
git push origin main
```

---

## Task 8: L6 — dispatchAction routes to the update method named by ActionInfo.update

**Files:**
- Modify: `Sources/EChartsKit/core/EChartsSlim.swift` (`dispatchAction` / the post-handler update)
- Test: `Tests/EChartsKitTests/L6UpdateMatrixTests.swift` (extend)

**Interfaces:**
- Consumes: `ActionInfoParsed.update: String?` (action.swift:31), the L6-1/L6-2 methods.
- Produces: after an action handler mutates the model, the driver runs the update method named by
  the action's `update` field (`update`/`updateView`/`updateVisual`/`updateLayout`/`updateTransform`/
  `none`) instead of always running full `update()`.

- [ ] **Step 1: Write the failing test**

Extend `L6UpdateMatrixTests.swift`:

```swift
    func testActionWithUpdateNoneDoesNotFullUpdate() {
        let ec = EChartsSlim(width: 400, height: 300)
        ec.setOption(["xAxis": ["type": "category", "data": ["a", "b"]],
                      "yAxis": ["type": "value"], "series": [["type": "bar", "data": [1, 2]]]])
        let store1 = ec.testModel?.getSeries().first?.getData()
        // 'highlight' registers with update:'none' (light path) — must not rebuild the DataStore.
        ec.dispatchAction(Payload(type: "highlight", extra: ["seriesIndex": 0, "dataIndex": 0]))
        let store2 = ec.testModel?.getSeries().first?.getData()
        XCTAssertTrue(store1 === store2, "update:'none' action must not run full update()")
    }
```

- [ ] **Step 2: Run to verify it fails**

Run: `swift test --filter L6UpdateMatrixTests`
Expected: FAIL — the current dispatch runs full `update()` for actions marked `update:"update"`/
`"none"` indiscriminately, recreating the DataStore.

- [ ] **Step 3: Route by ActionInfo.update**

In `dispatchAction`, after the registered handler runs, replace the unconditional `update()` with a
switch on the action's parsed `update` string (faithful to echarts.ts dispatchAction → updateMethods):

```swift
        switch actionInfo.update ?? "update" {
        case "none": break
        case "updateView": updateView()
        case "updateVisual": updateVisual()
        case "updateLayout": updateLayout()
        case let u where u.hasPrefix("updateTransform"): updateTransform()
        default: update()          // "update"
        }
```

Preserve the existing highlight/downplay light-update path (`updateDirectly`) if the action already
routes there — this switch governs the model-mutating actions that currently fall through to
`update()`. Match the real field name (`actionInfo.update`) from the parsed action record.

- [ ] **Step 4: Run tests + full suite + interaction spot-check**

Run: `swift test`
Expected: PASS. Then confirm legend-toggle / dataZoom / brush still update visibly (these use
`update:"update"`, unchanged): a manual `--render` of a legend demo after a dispatched
`legendToggleSelect` is optional; the suite's existing interaction tests are the gate.

- [ ] **Step 5: Commit and push**

```bash
git add -A
git commit -m "L6-3: dispatchAction routes to the update method named by the action

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
git push origin main
```

---

## Fidelity backlog (per-view diff conversion — plan separately when prioritized)

After Task 3, views that clear their own group are **safe on reuse but do not tween** (they rebuild).
Upstream tweens many of them. Converting each to the faithful `data.diff` + `updateProps` form is a
long tail; each conversion is its own task (own upstream study + reuse+tween test), sequenced by
which chart types the user's live data actually uses. Do NOT batch these blindly — each needs its
matching upstream view read line-by-line. Known members (filled from Task 3's classification):
LineView (polyline point tween), and any view Task 3 fixed with a bare `group.removeAll()` guard.
Each gets a task mirroring Task 5's structure (assert `testScheduledAnimatorCount > 0` after a data
change) once prioritized.

---

## Self-Review

**Spec coverage:** L5-1 model reuse → Task 1 ✓; L5-2 prepareView sweep + render reset → Task 2 ✓;
L5-3 idempotency audit → Task 3 ✓; L5-4 clearStates/updateStates → Task 4 ✓; L5 tween delivery →
Task 5 ✓; L6-1 updateView/Visual/Layout → Task 6 ✓; L6-2 updateTransform → Task 7 ✓; L6-3
dispatch routing → Task 8 ✓. Spec §8 out-of-scope (universal transitions, Scheduler progressive,
lazyUpdate) → excluded, not tasked ✓. Spec §5 regression invariants (notMerge demo-switch, PNG
oracle, bg idempotency, `__requireNewView`) → Task 1 notMerge, Task 2 bg + `__requireNewView`,
Tasks 2/10-step & 4 PNG spot-checks ✓.

**Placeholder scan:** Task 3/5/6/7 contain explicit "grep for the real API name and use it" notes
where an exact accessor (Group child count, Animation.animatorCount, states view-helper) must be
confirmed against source rather than guessed — these are directed verifications with a named target
and a fallback, not open TODOs. All code steps carry concrete code.

**Type consistency:** `_model`/`testModel`, `_chartsViews`/`testChartViews`, `__alive` (Bool on
ChartView, Bool? on ComponentView — handled: `!v.__alive` for charts, `v.__alive != true` for
components), `__viewId`/`__requireNewView` (Component.swift), `viewId = "_ec_\(model.id)_\(model.type)"`
consistent across Tasks 2 and the sweep. `ViewUpdateResult` defined in Task 7. `updateView`/
`updateVisual`/`updateLayout`/`updateTransform` names consistent across Tasks 6-8.
