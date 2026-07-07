# B5 — Gauge pointer sweep + Funnel fade-in Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:subagent-driven-development. Checkbox steps.

**Goal:** Gauge pointer sweeps from startAngle to the value angle; funnel pieces fade in (opacity 0→final). Faithful to upstream GaugeView.ts / FunnelView.ts.

**Architecture:** Gauge — `createPointer(idx, startAngle)` (pointer at the start rotation), then `initProps(pointer, ["rotation": valueRotation], seriesModel)` (rotation is a scalar transform prop — pass directly, no dict). Funnel — create the polygon at final points, set `style.opacity = 0`, `initProps(polygon, ["style": ["opacity": finalOpacity]], seriesModel, idx)` (a STYLE dict). Funnel additionally requires a `Path.attrKV` fix so a partial `"style"` dict works on the animation-OFF `attr` path (B1 only fixed `"shape"`), else funnel renders invisible when animation is off.

**Tech Stack:** EChartsKit (GaugeView, FunnelView, animation/basicTransition), ZRenderKit (Path.attrKV, transform.rotation, PathStyleProps).

## Global Constraints

- Faithful to `upstream/echarts/src/chart/gauge/GaugeView.ts` (pointer `initProps({rotation})`) and `upstream/echarts/src/chart/funnel/FunnelView.ts` (`initProps({style:{opacity}})`).
- Build 0 warnings (ignore pre-existing `calendarPrepareCustom.swift`). `swift test` green (337 baseline).
- Commit + push to `main`. No backticks in commit messages. End with `Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>`.
- rotation is a scalar transform prop (pass directly). opacity is a STYLE sub-bag → `["style": ["opacity": v]]` dict; both the animate and attr paths must set it.
- Test pattern: assert an animator with the right track exists; step it t=0/t=1 for the real delta; setToFinal jumps the live prop to final so assert the TRACK. The animation-OFF test must assert the FINAL value is set (0 animators) — for funnel this guards the invisible-piece risk.

---

### Task 1: Gauge pointer rotation sweep

**Files:**
- Modify: `Sources/EChartsKit/chart/gauge/GaugeView.swift` (`_renderPointer` — the createPointer invocation + add to group)
- Test: `Tests/EChartsKitTests/GaugeTransitionTests.swift`

**Interfaces:** Consumes shared `initProps`; `Path.rotation` (scalar transform).

- [ ] **Step 1: Read the pointer invocation**

Run: `grep -n "createPointer(\|createProgress(\|group.add\|setItemGraphicEl\|linearMap\|valueExtent\|angleExtent\|rotation" Sources/EChartsKit/chart/gauge/GaugeView.swift | head -20`
Find where `createPointer(idx, <angle>)` is called and how the VALUE angle is computed (upstream: `linearMap(val, valueExtent, angleExtent, true)`, then `rotation = -(valueAngle + π/2)`). `createPointer` already sets `pointer.rotation = -(angle + π/2)`, so passing the value angle gives the final rotation, and passing `startAngle` gives the collapsed start. Confirm `startAngle` is in scope at the call site (it is — `_renderPointer` param). Note the pointer is a `Path` named nothing specific — the test will match `PointerPath`.

- [ ] **Step 2: Write the failing test**

Create `Tests/EChartsKitTests/GaugeTransitionTests.swift`:

```swift
// Gauge pointer sweeps from startAngle to the value angle (rotation transform) when animation on.
// Faithful to GaugeView.ts pointer initProps({rotation}).
import XCTest
@testable import EChartsKit
@testable import ZRenderKit

final class GaugeTransitionTests: XCTestCase {
    private func firstPointer(_ el: Element) -> Path? {
        if let p = el as? PointerPath { return p }
        if let g = el as? Group { for c in g.children() { if let h = firstPointer(c) { return h } } }
        return nil
    }
    private func option(_ animation: Bool) -> [String: Any] {
        ["animation": animation,
         "series": [["type": "gauge", "min": 0.0, "max": 100.0, "data": [["value": 50.0]]]]]
    }
    func test_pointer_sweeps_when_animation_on() {
        let ec = EChartsSlim(width: 400, height: 400); ec.setOption(option(true))
        guard let p = firstPointer(ec.getRoot()) else { return XCTFail("no gauge pointer (PointerPath)") }
        let anim = p.animators.first { $0.getTrack("rotation") != nil }
        XCTAssertNotNil(anim, "pointer should have a rotation animator when animation on")
        if let track = anim?.getTrack("rotation") {
            track.step(p, 0.0); let atStart = p.rotation
            track.step(p, 1.0); let atEnd = p.rotation
            XCTAssertNotEqual(atStart, atEnd, accuracy: 1e-9, "rotation track must carry a real start→value delta")
        }
    }
    func test_pointer_final_rotation_when_animation_off() {
        let ec = EChartsSlim(width: 400, height: 400); ec.setOption(option(false))
        guard let p = firstPointer(ec.getRoot()) else { return XCTFail("no gauge pointer") }
        XCTAssertEqual(p.animators.count, 0, "no animator when animation off")
    }
}
```
If the pointer type isn't `PointerPath` when a custom `pointer.icon` is set, the default (no icon) demo above builds a `PointerPath` — keep the option iconless. Verify the matcher finds the pointer (fail on "no animator", not "no pointer").

- [ ] **Step 3: Run to verify failure** — `swift test --filter GaugeTransitionTests` → "on" test FAILS (0 rotation animators).

- [ ] **Step 4: Add the sweep** — at the pointer creation/add site: create the pointer at `startAngle` instead of the value angle, then initProps toward the value rotation:
```swift
                let valueAngle = number.linearMap(val, valueExtent, angleExtent, true)   // match the real linearMap API
                let pointer = createPointer(idx, startAngle)
                initProps(pointer, ["rotation": -(valueAngle + Double.pi / 2)], seriesModel)
                _ = group.add(pointer)
                data.setItemGraphicEl(idx, pointer)
```
Adapt `val`/`valueDim`/`linearMap` to the real symbols already in `_renderPointer` (the value is `data.get(valueDim, idx)`). If the code currently computes the value angle inline and passes it to createPointer, reuse that value; just pass `startAngle` to createPointer and feed the value rotation to initProps. `initProps` with a scalar `rotation` needs no dict. When animation off → attr sets rotation to the value (pointer at final) — no invisible-pointer risk (it's a transform, always applied).

- [ ] **Step 5: Green + full suite; Step 6: build + commit**
```bash
swift build 2>&1 | grep -iE "error|warning" | grep -v calendarPrepareCustom
git add Sources/EChartsKit/chart/gauge/GaugeView.swift Tests/EChartsKitTests/GaugeTransitionTests.swift
git commit -m "$(cat <<'EOF'
gauge: pointer rotation sweep entrance via shared basicTransition

Faithful to GaugeView.ts: create the pointer at startAngle, then initProps its rotation
to the value angle, so the needle sweeps up when animation is enabled (instant final
rotation when off).

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
)"
git push origin main
```

---

### Task 2: Funnel piece fade-in (+ Path.attrKV style partial-dict fix)

**Files:**
- Modify: `Sources/ZRenderKit/Graphic/Path.swift` (`attrKV` — add partial `"style"` dict merge, mirroring the existing `"shape"` branch)
- Modify: `Sources/EChartsKit/chart/funnel/FunnelView.swift` (polygon creation — opacity 0 + initProps)
- Test: `Tests/EChartsKitTests/FunnelTransitionTests.swift`

**Interfaces:** Consumes shared `initProps`; `Path.attrKV` style partial-dict; `PathStyleProps.opacity`.

- [ ] **Step 1: Fix Path.attrKV for a partial "style" dict**

Read the existing `"shape"` partial-dict branch in `Path.attrKV` (it does `else if let partial = value as? [String: Any], var s = self.shape { for (k,v) in partial { s.animationSet(coerceToDouble...) }; self.shape = s }`). Add an analogous branch for `key == "style"`: when the value is a partial `[String:Any]` dict, merge each key into `self.pathStyle` via the PathStyleProps setter (the same field the PathStyleAnimationAccessor writes — Path.swift ~line 332), coercing Int→Double, then mark the style dirty (`dirtyStyle()` or the existing style-dirty call the shape branch's counterpart uses). Confirm the exact PathStyleProps per-key setter (it likely has `animationSet`/keyed access like the accessor uses); if PathStyleProps exposes `animationSet`, use it. When the value is a full `PathStyleProps` (existing callers), keep the current behavior. This unlocks the animation-OFF `attr(["style": ["opacity": v]])` path.

Add a unit test to an existing Path test (or the new funnel test) that `path.attr(["style": ["opacity": 0.5]])` sets `path.pathStyle.opacity == 0.5` (Double) and `["opacity": 1]` (Int) coerces to 1.0.

- [ ] **Step 2: Write the failing funnel test**

Create `Tests/EChartsKitTests/FunnelTransitionTests.swift`:

```swift
// Funnel pieces fade in (style.opacity 0→final) when animation on, and are at final opacity with no
// animator when off (the invisible-piece guard). Faithful to FunnelView.ts initProps({style:{opacity}}).
import XCTest
@testable import EChartsKit
@testable import ZRenderKit

final class FunnelTransitionTests: XCTestCase {
    private func firstPiece(_ el: Element) -> Polygon? {
        if let p = el as? Polygon { return p }
        if let g = el as? Group { for c in g.children() { if let h = firstPiece(c) { return h } } }
        return nil
    }
    private func option(_ animation: Bool) -> [String: Any] {
        ["animation": animation,
         "series": [["type": "funnel", "data": [["value": 60.0, "name": "a"], ["value": 40.0, "name": "b"]]]]]
    }
    func test_piece_fades_in_when_animation_on() {
        let ec = EChartsSlim(width: 400, height: 400); ec.setOption(option(true))
        guard let poly = firstPiece(ec.getRoot()) else { return XCTFail("no funnel polygon") }
        let anim = poly.animators.first { $0.getTrack("opacity") != nil || $0.targetName == "style" }
        XCTAssertNotNil(anim, "funnel piece should have an opacity animator when animation on")
    }
    func test_piece_final_opacity_when_animation_off() {
        let ec = EChartsSlim(width: 400, height: 400); ec.setOption(option(false))
        guard let poly = firstPiece(ec.getRoot()) else { return XCTFail("no funnel polygon") }
        XCTAssertEqual(poly.animators.count, 0, "no animator when animation off")
        XCTAssertGreaterThan(poly.pathStyle.opacity ?? 0, 0.0, "piece must be at final (visible) opacity when off — not invisible")
    }
}
```
Adjust the animator-track matcher to how a `"style"` sub-animator is named (inspect via the PieTransitionTests/ShapeAnimationWiringTests idiom — the style animator has `targetName == "style"` and a leaf `"opacity"` track). Fix the matcher to what actually holds.

- [ ] **Step 3: Run to verify failure** — `swift test --filter FunnelTransitionTests` → "on" fails (0 animators). The "off" test currently passes (funnel already sets final opacity directly) — after your change it must STILL pass (the attr fix keeps it final).

- [ ] **Step 4: Add the fade-in** — in FunnelView's polygon creation, set the style opacity to 0 and initProps toward the final opacity, instead of setting the final opacity directly:
```swift
            // upstream FunnelPiece firstCreate: polygon.style.opacity = 0; initProps(polygon, {style:{opacity}}).
            style.opacity = 0
            polygon.useStyle(style)
            initProps(polygon, ["style": ["opacity": opacity] as [String: Any]], seriesModel, idx)
```
Keep the polygon shape (points) set to final. Confirm `opacity` (the final value) and `style`/`polygon`/`seriesModel`/`idx` var names. When animation off → attr(["style":["opacity":opacity]]) → final opacity (visible) via the Step 1 fix.

- [ ] **Step 5: Green + full suite; Step 6: build + commit**
```bash
swift build 2>&1 | grep -iE "error|warning" | grep -v calendarPrepareCustom
git add Sources/ZRenderKit/Graphic/Path.swift Sources/EChartsKit/chart/funnel/FunnelView.swift Tests/EChartsKitTests/FunnelTransitionTests.swift
git commit -m "$(cat <<'EOF'
funnel: piece fade-in entrance + Path.attrKV partial style-dict

Add a partial "style" dict merge to Path.attrKV (mirroring the "shape" branch) so
attr(["style":{opacity}]) works on the animation-off path, then fade funnel pieces in
(style.opacity 0 → final) via initProps. Off path sets final opacity (pieces visible),
guarded by a test.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
)"
git push origin main
```

---

## Self-Review

- **Coverage:** gauge pointer sweep → Task 1; funnel fade-in + style-dict infra → Task 2. Gauge progress-arc endAngle and radar polygon-from-center deferred.
- **Placeholders:** none — Step 1s are real find/verify steps.
- **Type consistency:** rotation scalar (no dict); opacity via `"style"` dict; the Path.attrKV style branch mirrors the proven shape branch with Int coercion.
- **Risks:** (1) the funnel OFF path invisibility — mitigated by the attrKV style fix + the explicit "final opacity when off" guard test. (2) The `"style"` sub-animator track key — the funnel test matcher must match how the style animator is named (verify). (3) `linearMap` API name in gauge — confirm against the real number util.
