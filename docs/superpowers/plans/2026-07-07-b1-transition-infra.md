# B1 Transition Infrastructure Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Port the shared `animation/basicTransition` helpers (real animation) and wire Bar + Candlestick so entrance/update/leave transitions animate, with a gallery toggle to view them.

**Architecture:** A new `Sources/EChartsKit/animation/basicTransition.swift` faithfully ports `basicTransition.ts` (`getAnimationConfig`/`animateOrSetProps`/`initProps`/`updateProps`/`removeElement`/`removeElementWithFadeOut`). BarView and CandlestickView drop their local no-op shims and call it. The gallery gets an `NSSwitch` to inject `animation:false` (default, matches the static HTML pane) or leave animation on (watch transitions).

**Tech Stack:** Swift, SwiftPM. ZRenderKit (Element.animateTo/animateFrom/attr/stopAnimation, ElementAnimateConfig, Animator/Clip), EChartsKit (Series.isAnimationEnabled, Model.getShallow, BarView, CandlestickView), AppKit gallery.

## Global Constraints

- Faithful to vendored `upstream/echarts/src/animation/basicTransition.ts` — ground truth.
- Build 0 warnings; `swift test` green (currently 316 tests, 58 skipped, 0 failures — new tests add to it).
- Commit + push to `main` after each task. No backticks in commit messages. End every commit message with: `Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>`
- `EChartsKit` depends only on `ZRenderKit`. The `--render`/`--compare` PNG path stays a deterministic instant-final oracle.
- Int/Double option reads must coerce (Int-literal `animationDuration` must not be dropped) — the known int-vs-double trap.

---

### Task 1: Port shared `basicTransition.swift`

**Files:**
- Create: `Sources/EChartsKit/animation/basicTransition.swift`
- Test: `Tests/EChartsKitTests/BasicTransitionTests.swift`

**Interfaces:**
- Consumes: `Model.getShallow(_:) -> ModelOption?`, `Model.isAnimationEnabled() -> Bool?` (SeriesModel overrides it); `Element.animateTo(_ target: ElementProps, _ cfg: ElementAnimateConfig?)`, `.animateFrom(...)`, `.stopAnimation(_ scope: String?)`, `.attr(_ keyOrObj: ElementProps)`; `ElementAnimateConfig{duration,delay,easing,during,done}`; `Displayable`/`Group`/`Element`. Confirm `ElementProps` is `[String:Any]` (ShapeAnimationWiringTests calls `rect.animateTo(["shape": ["height": 100.0]], cfg)`); if it is a distinct type, add a `[String:Any]`→`ElementProps` bridge.
- Produces (used by Tasks 2-3): free functions
  - `func getAnimationConfig(_ type: ECAnimType, _ model: Model?, _ dataIndex: Int, _ extra: (duration: Double?, easing: AnimationEasing?, delay: Double?)?) -> (duration: Double, delay: Double, easing: AnimationEasing?)?`
  - `func initProps(_ el: Element, _ props: [String: Any], _ model: Model?, _ dataIndex: Int?, _ cb: (() -> Void)?, _ during: ((Double) -> Void)?)`
  - `func updateProps(_ el: Element, _ props: [String: Any], _ model: Model?, _ dataIndex: Int?, _ cb: (() -> Void)?, _ during: ((Double) -> Void)?)` (both with defaulted trailing params so `initProps(el, props, model, idx)` compiles)
  - `func removeElementWithFadeOut(_ el: Element, _ model: Model?, _ dataIndex: Int)`
  - `func saveOldStyle(_ el: Displayable)` / `func getOldStyle(_ el: Displayable) -> PathStyleProps?`
  - `enum ECAnimType { case enter, update, leave }`

- [ ] **Step 1: Write failing tests**

Create `Tests/EChartsKitTests/BasicTransitionTests.swift`:

```swift
// Faithful port checks for animation/basicTransition.ts: getAnimationConfig reads the series'
// animation option (enabled/disabled, enter vs update durations, Int coercion), and initProps
// animates a shape when enabled but sets it instantly when disabled (the no-op branch).
import XCTest
@testable import EChartsKit
@testable import ZRenderKit

final class BasicTransitionTests: XCTestCase {

    // A minimal SeriesModel carrying just the animation options through a real GlobalModel.
    private func seriesModel(_ extra: [String: Any] = [:]) -> SeriesModel {
        var opt: [String: Any] = ["type": "bar", "data": [1.0]]
        for (k, v) in extra { opt[k] = v }
        let full: [String: Any] = ["series": [opt]]
        let ec = EChartsSlim(width: 200, height: 200)
        ec.setOption(full)
        return ec.getModel()!.getSeriesByType("bar").first!
    }

    func test_getAnimationConfig_disabled_returns_nil() {
        let m = seriesModel(["animation": false])
        XCTAssertNil(getAnimationConfig(.enter, m, 0, nil))
    }

    func test_getAnimationConfig_enter_and_update_durations() {
        let m = seriesModel([:])   // default animation on
        let enter = getAnimationConfig(.enter, m, 0, nil)
        let update = getAnimationConfig(.update, m, 0, nil)
        XCTAssertEqual(enter?.duration, 1000, "enter uses animationDuration default 1000")
        XCTAssertEqual(update?.duration, 500, "update uses animationDurationUpdate default 500")
    }

    func test_getAnimationConfig_coerces_int_duration() {
        let m = seriesModel(["animationDuration": 800])   // Int literal
        XCTAssertEqual(getAnimationConfig(.enter, m, 0, nil)?.duration, 800,
                       "Int-literal animationDuration must coerce, not drop to default")
    }

    func test_initProps_animates_shape_when_enabled() {
        let m = seriesModel([:])
        let rect = Rect()
        var s = RectShape(); s.x = 0; s.y = 0; s.width = 10; s.height = 100
        rect.shape = s
        // initProps toward the final shape; enabled → an animator is created.
        initProps(rect, ["shape": ["height": 100.0] as [String: Any]], m, 0, nil, nil)
        XCTAssertEqual(rect.animators.count, 1, "enabled animation should create one shape animator")
    }

    func test_initProps_sets_instantly_when_disabled() {
        let m = seriesModel(["animation": false])
        let rect = Rect()
        var s = RectShape(); s.x = 0; s.y = 0; s.width = 10; s.height = 0
        rect.shape = s
        initProps(rect, ["shape": ["height": 100.0] as [String: Any]], m, 0, nil, nil)
        XCTAssertEqual(rect.animators.count, 0, "disabled animation should not create an animator")
        XCTAssertEqual((rect.shape as? RectShape)?.height ?? -1, 100.0, accuracy: 1e-9,
                       "disabled animation should set the final shape immediately (attr branch)")
    }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `swift test --filter BasicTransitionTests`
Expected: FAIL — `getAnimationConfig`/`initProps` don't exist ("cannot find … in scope"). If `getSeriesByType`/`getModel` accessors differ, fix the helper to the real API (grep `Sources/EChartsKit/model/Global.swift` for the series accessor) before proceeding — this is a real-API fix, not optional.

- [ ] **Step 3: Implement `basicTransition.swift`**

Port `basicTransition.ts` faithfully. Key body (adapt names to the real APIs confirmed in Step 2):

```swift
// Ported from echarts/src/animation/basicTransition.ts — keep in sync with upstream.
// Real animation replacing the per-view no-op shims (BarView/CandlestickView). `initProps`/`updateProps`
// animate via el.animateTo when the series has animation enabled, else set the props instantly.
import Foundation
import ZRenderKit

enum ECAnimType { case enter, update, leave }

private func transNum(_ v: Any?) -> Double? {
    if let d = v as? Double { return d }
    if let i = v as? Int { return Double(i) }
    if let n = v as? NSNumber { return n.doubleValue }
    return nil
}

func getAnimationConfig(
    _ type: ECAnimType, _ model: Model?, _ dataIndex: Int,
    _ extra: (duration: Double?, easing: AnimationEasing?, delay: Double?)?
) -> (duration: Double, delay: Double, easing: AnimationEasing?)? {
    let isUpdate = (type == .update)
    guard let model = model, model.isAnimationEnabled() == true else { return nil }
    let duration: Double
    let delay: Double
    let easing: AnimationEasing?
    if let extra = extra {
        duration = extra.duration ?? 200
        easing = extra.easing ?? .named("cubicOut")
        delay = 0
    } else {
        duration = transNum(model.getShallow(isUpdate ? "animationDurationUpdate" : "animationDuration")) ?? 0
        delay = transNum(model.getShallow(isUpdate ? "animationDelayUpdate" : "animationDelay")) ?? 0
        if let e = model.getShallow(isUpdate ? "animationEasingUpdate" : "animationEasing") as? String {
            easing = .named(e)
        } else { easing = nil }
    }
    return (duration: duration, delay: delay, easing: easing)
}

private func animateOrSetProps(
    _ type: ECAnimType, _ el: Element, _ props: [String: Any], _ model: Model?,
    _ dataIndex: Int?, _ isFrom: Bool, _ cb: (() -> Void)?, _ during: ((Double) -> Void)?
) {
    let isRemove = (type == .leave)
    if !isRemove { _ = el.stopAnimation("leave") }
    let cfg = getAnimationConfig(type, model, dataIndex ?? 0, nil)
    if let cfg = cfg, cfg.duration > 0 {
        var ac = ElementAnimateConfig()
        ac.duration = cfg.duration
        ac.delay = cfg.delay
        ac.easing = cfg.easing
        ac.during = during
        ac.done = cb
        if isFrom { el.animateFrom(props, ac) } else { el.animateTo(props, ac) }
    } else {
        _ = el.stopAnimation()
        if !isFrom { _ = el.attr(props) }   // add [String:Any]→ElementProps bridge here if attr needs it
        during?(1)
        cb?()
    }
}

func initProps(_ el: Element, _ props: [String: Any], _ model: Model? = nil,
               _ dataIndex: Int? = nil, _ cb: (() -> Void)? = nil, _ during: ((Double) -> Void)? = nil) {
    animateOrSetProps(.enter, el, props, model, dataIndex, false, cb, during)
}

func updateProps(_ el: Element, _ props: [String: Any], _ model: Model? = nil,
                 _ dataIndex: Int? = nil, _ cb: (() -> Void)? = nil, _ during: ((Double) -> Void)? = nil) {
    animateOrSetProps(.update, el, props, model, dataIndex, false, cb, during)
}

private func isElementRemoved(_ el: Element) -> Bool {
    if el.__zr == nil { return true }
    // PORT-TODO: ElementAnimateConfig has no `scope`, so leave-animators aren't tagged — cannot detect
    //   an in-flight leave animation. Conservative: not-removed. Documented deviation.
    return false
}

private func fadeOutDisplayable(_ el: Displayable, _ model: Model?, _ dataIndex: Int, _ done: (() -> Void)?) {
    el.removeTextContent()
    el.removeTextGuideLine()
    animateOrSetProps(.leave, el, ["style": ["opacity": 0.0] as [String: Any]], model, dataIndex, false, done, nil)
}

func removeElementWithFadeOut(_ el: Element, _ model: Model? = nil, _ dataIndex: Int = -1) {
    if isElementRemoved(el) { return }
    func doRemove() { if let p = el.parent { _ = p.remove(el) } }
    if let disp = el as? Displayable, !(el is Group) {
        fadeOutDisplayable(disp, model, dataIndex, doRemove)
    } else if let g = el as? Group {
        _ = g.traverse { child in
            if let disp = child as? Displayable, !(child is Group) {
                fadeOutDisplayable(disp, model, dataIndex, doRemove)
            }
            return false
        }
    } else { doRemove() }
}

// saveOldStyle/getOldStyle: universalTransition support (later sub-project). B1 stub via an associated
//   side-table keyed by ObjectIdentifier, or a stored property on Displayable — pick the minimal one.
func saveOldStyle(_ el: Displayable) { /* B1 stub — see PORT-TODO */ }
func getOldStyle(_ el: Displayable) -> PathStyleProps? { return nil }
```

Confirm against source: `Model.getShallow`, `SeriesModel.isAnimationEnabled`, `Element.animateTo/animateFrom(_:_ :)`, `.attr`, `.stopAnimation`, `.removeTextContent`/`.removeTextGuideLine`, `Group.remove`/`.traverse`, `AnimationEasing.named(_:)`, `ElementAnimateConfig` fields. Fix any mismatch to the real API.

- [ ] **Step 4: Run tests to green**

Run: `swift test --filter BasicTransitionTests`
Expected: PASS (5/5).

- [ ] **Step 5: Build clean + commit**

Run: `swift build 2>&1 | grep -iE "error|warning"` (expect empty).
```bash
git add Sources/EChartsKit/animation/basicTransition.swift Tests/EChartsKitTests/BasicTransitionTests.swift
git commit -m "$(cat <<'EOF'
animation: port shared basicTransition (real initProps/updateProps/removeElement)

Faithful port of animation/basicTransition.ts: getAnimationConfig reads the series'
animationDuration/Easing/Delay (and Update variants); animateOrSetProps animates via
el.animateTo/animateFrom when enabled, else sets props instantly (the no-op branch the
per-view shims currently hardcode). Not yet wired into any view.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
)"
git push origin main
```

---

### Task 2: Wire BarView to the shared helpers

**Files:**
- Modify: `Sources/EChartsKit/chart/bar/BarView.swift` (delete local shims ~605-660; keep call sites 345/375/403/414/444/454/585)
- Test: `Tests/EChartsKitTests/BarTransitionTests.swift`

**Interfaces:**
- Consumes: the Task 1 module functions (`initProps`/`updateProps`/`removeElementWithFadeOut`/`saveOldStyle`).
- Produces: nothing new — BarView now animates entering bars.

- [ ] **Step 1: Write failing test**

Create `Tests/EChartsKitTests/BarTransitionTests.swift`:

```swift
// Entering bars animate their rect shape when the series has animation on, and are at final geometry
// instantly when off. Uses the ec render tree (BarView.render → data.diff enter → initProps).
import XCTest
@testable import EChartsKit
@testable import ZRenderKit

final class BarTransitionTests: XCTestCase {

    private func firstBarRect(_ el: Element) -> Rect? {
        if let r = el as? Rect { return r }
        if let g = el as? Group { for c in g.children() { if let hit = firstBarRect(c) { return hit } } }
        return nil
    }

    private func option(_ animation: Bool) -> [String: Any] {
        [
            "animation": animation,
            "xAxis": ["type": "category", "data": ["a", "b", "c"]],
            "yAxis": ["type": "value"],
            "series": [["type": "bar", "data": [10.0, 20.0, 30.0]]]
        ]
    }

    func test_bar_enter_animates_when_animation_on() {
        let ec = EChartsSlim(width: 400, height: 300)
        ec.setOption(option(true))
        guard let rect = firstBarRect(ec.getRoot()) else { return XCTFail("no bar Rect") }
        XCTAssertGreaterThan(rect.animators.count, 0, "bar should have an enter animator when animation is on")
    }

    func test_bar_no_animator_when_animation_off() {
        let ec = EChartsSlim(width: 400, height: 300)
        ec.setOption(option(false))
        guard let rect = firstBarRect(ec.getRoot()) else { return XCTFail("no bar Rect") }
        XCTAssertEqual(rect.animators.count, 0, "bar should have no animator when animation is off")
        XCTAssertGreaterThan((rect.shape as? RectShape)?.height ?? 0, 0, "bar rect should be at final height")
    }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `swift test --filter BarTransitionTests`
Expected: `test_bar_enter_animates_when_animation_on` FAILS (0 animators — the local no-op shim never animates). The `_off` test likely already passes.

- [ ] **Step 3: Delete BarView's local shims, use the shared module**

In `BarView.swift`, delete the `private func initProps`, `private func updateProps`, `private func saveOldStyle`, and `private func removeElementWithFadeOut` definitions (and their PORT-TODO banner, ~lines 605-660). The call sites now resolve to the module-level functions from Task 1. Fix the two signature mismatches:
- `removeElementWithFadeOut(el, seriesModel, oldIndex, group)` call sites (403/454/585) → drop the trailing `group` arg: `removeElementWithFadeOut(el, seriesModel, oldIndex)` (the shared version removes `el` from `el.parent`). Confirm entering bars are added to `group` (so `el.parent === group`); if a bar's parent is a subgroup, that is still correct (removes from its real parent).
- Confirm `initProps(el, ["shape": layout], seriesModel, dataIndex)` and `updateProps(...)` match the shared param order `(el, props, model, dataIndex)`. `seriesModel`/`animationModel` are `Model` subclasses — pass directly.

- [ ] **Step 4: Run tests to green + full suite**

Run: `swift test --filter BarTransitionTests` (expect PASS), then `swift test 2>&1 | grep "Executed .* tests, with"` (expect 0 failures).

- [ ] **Step 5: Build clean + commit**

Run: `swift build 2>&1 | grep -iE "error|warning"` (expect empty).
```bash
git add Sources/EChartsKit/chart/bar/BarView.swift Tests/EChartsKitTests/BarTransitionTests.swift
git commit -m "$(cat <<'EOF'
bar: use shared basicTransition — entering bars animate (was no-op shim)

Delete BarView's local no-animation initProps/updateProps/saveOldStyle/
removeElementWithFadeOut shims and route the existing data.diff enter/update/leave
call sites to the shared animation/basicTransition helpers, so bars grow in when the
series has animation enabled.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
)"
git push origin main
```

---

### Task 3: Wire CandlestickView to the shared helpers

**Files:**
- Modify: `Sources/EChartsKit/chart/candlestick/CandlestickView.swift` (delete local shims ~525-545; call sites 184/222/224)
- Test: none new (Task 1 covers the helpers; Candlestick has no distinct behavior to assert beyond compile + suite). Verify via full suite + a candlestick PNG.

**Interfaces:**
- Consumes: Task 1 module functions.

- [ ] **Step 1: Delete CandlestickView's local shims**

Delete `private func initProps`, `private func updateProps`, `private func saveOldStyle` (CandlestickView.swift ~525-545). Call sites 184 (`initProps(el, ["shape": initShape], seriesModel, newIdx)`), 222 (`updateProps(el!, ["shape": shape], seriesModel, newIdx)`), 224 (`saveOldStyle(el!)`) resolve to the shared module. Confirm `saveOldStyle` takes a `Displayable` — if `el!` is a `Path` (a Displayable), fine; else cast.

- [ ] **Step 2: Build + full suite**

Run: `swift build 2>&1 | grep -iE "error|warning"` (expect empty), then `swift test 2>&1 | grep "Executed .* tests, with"` (expect 0 failures).
Then render a candlestick demo PNG to confirm no static regression: find one via `swift run EChartsDemoGallery --list | grep -i candle` and `swift run EChartsDemoGallery --render <name> /tmp/c.png` (expect a PNG written; final-state candles).

- [ ] **Step 3: Commit**

```bash
git add Sources/EChartsKit/chart/candlestick/CandlestickView.swift
git commit -m "$(cat <<'EOF'
candlestick: use shared basicTransition (drop local no-op shims)

Route CandlestickView's enter/update/saveOldStyle call sites to the shared
animation/basicTransition helpers, matching BarView.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
)"
git push origin main
```

---

### Task 4: Gallery native-animation toggle + deterministic static PNG

**Files:**
- Modify: `Sources/EChartsDemoGallery/Entry.swift` (`renderNativeGroup`; `GalleryWindowController.buildUI`/`show`)

**Interfaces:**
- Consumes: `EChartsHostView.setOption`, `EChartsDemo.option`.

- [ ] **Step 1: Inject `animation:false` in the static PNG path**

In `renderNativeGroup`, before `ec.setOption(demo.option)`, build a mutable copy with `animation:false` so `--render`/`--compare` is a deterministic instant-final frame (matching the HTML pane's `opt.animation=false`):
```swift
    var opt = demo.option
    opt["animation"] = false
    let ec = EChartsSlim(width: demo.width, height: demo.height)
    ec.setOption(opt)
    let root = ec.getRoot()
    advanceAnimationsForStaticFrame(root)
    return root
```
(effectScatter's ripple is not gated on animation and is still advanced by `advanceAnimationsForStaticFrame`.)

- [ ] **Step 2: Add the native-animation toggle to the GUI**

In `GalleryWindowController`: add `private let animSwitch = NSSwitch()` and `private var currentDemo: EChartsDemo?`. In `buildUI()`, place `animSwitch` + a "Native 动画" label near the native caption; set `animSwitch.state = .off`; `animSwitch.target = self; animSwitch.action = #selector(toggleAnim)`. Add:
```swift
    @objc private func toggleAnim() { if let d = currentDemo { show(d) } }
```
In `show(_:)`, record `currentDemo = demo` and feed the host per the switch:
```swift
        currentDemo = demo
        if demo.nativeSupported {
            var opt = demo.option
            if animSwitch.state == .off { opt["animation"] = false }   // ON → leave echarts default (animate)
            nativeHostView?.setOption(opt)
        } else {
            nativeHostView?.setOption([:])
        }
```
Confirm `NSSwitch` is available on the deployment target; if not, use an `NSButton(checkboxWithTitle:)`. Confirm the exact accessor for the option dict (`demo.option`).

- [ ] **Step 3: Build clean**

Run: `swift build 2>&1 | grep -iE "error|warning"` (expect empty; ignore any stale SourceKit "cannot find EChartsHostView" — trust swift build).

- [ ] **Step 4: Manual verification (controller/human)**

`swift run EChartsDemoGallery`, select a bar demo, flip "Native 动画" ON → bars grow in on each (re)selection; OFF → instant, matching the HTML pane. Cannot be done headlessly — note this in the commit body.

- [ ] **Step 5: Commit**

```bash
git add Sources/EChartsDemoGallery/Entry.swift
git commit -m "$(cat <<'EOF'
gallery: native-animation toggle + deterministic static PNG

Add an NSSwitch to run the live native pane's transitions on demand (OFF by default,
injecting animation:false to match the static HTML pane; ON leaves echarts' default so
bars/candles animate). renderNativeGroup now also injects animation:false so the
--render/--compare PNG oracle is a deterministic instant-final frame.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
)"
git push origin main
```

---

## Self-Review

- **Spec coverage:** basicTransition port → Task 1; Bar wiring → Task 2; Candlestick wiring → Task 3; gallery toggle + static PNG determinism → Task 4. ✓
- **Placeholder scan:** none. The "confirm the real API / add bridge if needed" notes are deliberate verify-steps (ElementProps shape, NSSwitch availability, series accessor), each with a concrete grep/fallback.
- **Type consistency:** `getAnimationConfig`/`initProps`/`updateProps`/`removeElementWithFadeOut`/`saveOldStyle`/`ECAnimType` names identical across Task 1 (produces) and Tasks 2-3 (consumes); `removeElementWithFadeOut` drops the `group` arg consistently (Task 2 Step 3).
- **Risks:** `ElementProps` vs `[String:Any]` (bridge noted); leave-scope fidelity (documented PORT-TODO); the reset-fix means every setOption is an "enter" (update-in-place transitions deferred — a later B increment, stated in the spec non-goals).
