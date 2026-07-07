# B3 — Line clip-path draw-on Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:subagent-driven-development / executing-plans. Checkbox steps.

**Goal:** Cartesian line series "draw on" left-to-right (or bottom-to-top) via a growing clip rect, faithful to upstream `createGridClipPath` + `LineView.setClipPath`.

**Architecture:** `createGridClipPath` (already ported, 271 lines) builds a clip `Rect` collapsed along the base axis and had a PORT-TODO no-animation stub where `initProps` should be. B1 ported `initProps`, so swap the stub for the real call (shape props as a DICT). LineView creates the clip and `setClipPath`s it onto a `lineGroup` wrapping the polyline (+ area), so the line is revealed as the rect grows. Animation OFF → `initProps` attr branch → clip at full size instantly (no visual clip).

**Tech Stack:** EChartsKit (LineView, chart/helper/createClipPathFromCoordSys, animation/basicTransition), ZRenderKit (Element.setClipPath, Rect/RectShape, Group).

## Global Constraints

- Faithful to `upstream/echarts/src/chart/helper/createClipPathFromCoordSys.ts` (`createGridClipPath`) and `upstream/echarts/src/chart/line/LineView.ts` (clip creation + `lineGroup.setClipPath`).
- Build 0 warnings (ignore the pre-existing `calendarPrepareCustom.swift` warning). `swift test` green (329 baseline).
- Commit + push to `main`. No backticks in commit messages. End with `Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>`.
- Shape animation props MUST be a `[String:Any]` dict (struct→dict rule from B1).

---

### Task 1: clip-path draw-on for cartesian line

**Files:**
- Modify: `Sources/EChartsKit/chart/helper/createClipPathFromCoordSys.swift` (`createGridClipPath` — replace the no-animation stub ~lines 116-131 with real `initProps`)
- Modify: `Sources/EChartsKit/chart/line/LineView.swift` (cartesian `render` — wrap polyline+area in a lineGroup, create + attach the clip)
- Test: `Tests/EChartsKitTests/LineTransitionTests.swift`

**Interfaces:**
- Consumes: shared `initProps(el, props, model?, dataIndex?, cb?, during?)`; `createGridClipPath(cartesian, hasAnimation, seriesModel, ...)-> Rect`; `Element.setClipPath(_ clipPath: Path)`; `Group`; `SeriesModel.isAnimationEnabled()`.
- Produces: a cartesian line series whose polyline is clipped by a growing Rect (draw-on).

- [ ] **Step 1: Confirm the exact `createGridClipPath` signature + the stub lines**

Run: `grep -n "func createGridClipPath\|during:\|done:\|_ seriesModel\|-> Rect" Sources/EChartsKit/chart/helper/createClipPathFromCoordSys.swift | head`
Note the exact parameter list (order of `hasAnimation`/`seriesModel`/`done`/`during`). The stub to replace is the block that sets `finalShape` to full width/height/x/y then calls `duringCb?(1)` and `done?()` (around lines 116-131). Read it in full before editing.

- [ ] **Step 2: Write the failing test**

Create `Tests/EChartsKitTests/LineTransitionTests.swift`:

```swift
// Cartesian line draws on via a growing clip rect: with animation on, the line group's clipPath is a
// Rect whose width animates from 0 to full; with animation off, the clip is at full width (no animator).
// Faithful to createGridClipPath + LineView.setClipPath.
import XCTest
@testable import EChartsKit
@testable import ZRenderKit

final class LineTransitionTests: XCTestCase {

    // Find the first Group carrying a clipPath (the lineGroup) and return that clipPath as a Rect.
    private func firstClipRect(_ el: Element) -> Rect? {
        if let cp = el.getClipPath() as? Rect { return cp }
        if let g = el as? Group { for c in g.children() { if let hit = firstClipRect(c) { return hit } } }
        return nil
    }

    private func option(_ animation: Bool) -> [String: Any] {
        [
            "animation": animation,
            "xAxis": ["type": "category", "data": ["a", "b", "c", "d"]],
            "yAxis": ["type": "value"],
            "series": [["type": "line", "data": [10.0, 20.0, 15.0, 25.0]]]
        ]
    }

    func test_line_clip_grows_when_animation_on() {
        let ec = EChartsSlim(width: 400, height: 300)
        ec.setOption(option(true))
        guard let clip = firstClipRect(ec.getRoot()) else { return XCTFail("no line clip rect") }
        let anim = clip.animators.first { $0.getTrack("width") != nil }
        XCTAssertNotNil(anim, "clip rect should have a width animator when animation on")
        // Prove the real 0→full delta by stepping the width track (setToFinal jumps the live value to full).
        if let track = anim?.getTrack("width") {
            track.step(clip, 0.0)
            XCTAssertEqual((clip.shape as? RectShape)?.width ?? -1, 0.0, accuracy: 1e-6, "clip starts collapsed (width 0)")
            track.step(clip, 1.0)
            XCTAssertGreaterThan((clip.shape as? RectShape)?.width ?? 0, 0.0, "clip ends at full width")
        }
    }

    func test_line_clip_full_when_animation_off() {
        let ec = EChartsSlim(width: 400, height: 300)
        ec.setOption(option(false))
        guard let clip = firstClipRect(ec.getRoot()) else { return XCTFail("no line clip rect") }
        XCTAssertEqual(clip.animators.count, 0, "no clip animator when animation off")
        XCTAssertGreaterThan((clip.shape as? RectShape)?.width ?? 0, 0.0, "clip at full width when animation off")
    }
}
```

- [ ] **Step 3: Run to verify failure**

Run: `swift test --filter LineTransitionTests`
Expected: both FAIL — `firstClipRect` returns nil (LineView sets no clipPath yet). Confirm `Element.getClipPath()` exists (Element.swift:1151) and returns the clip; if the accessor name differs, fix the test helper.

- [ ] **Step 4: Fix `createGridClipPath` to animate**

In `createGridClipPath`, replace the PORT-TODO no-animation stub (the `finalShape` block + `duringCb?(1)` + `done?()`) with the real `initProps` toward the full shape, passing shape props as a DICT:

```swift
        // upstream: graphic.initProps(clipPath, { shape: { width, height, x, y } }, seriesModel, null, done, duringCb);
        initProps(clipPath,
                  ["shape": ["width": width, "height": height, "x": x, "y": y] as [String: Any]],
                  seriesModel, nil,
                  done,
                  duringCb.map { cb in { (p: Double) in cb(p) } })
```
Adjust to the real `initProps` parameter types (cb is `(() -> Void)?`, during is `((Double) -> Void)?`). `duringCb` is already `((Double)->Void)?`, so pass it directly if the types line up. The collapsed initial shape (width/height 0) is already set above the stub — keep it. When `hasAnimation` is false, this whole `if` block is skipped and the clip stays at full size (correct).

- [ ] **Step 5: Wire LineView to create + attach the clip**

In `LineView.swift`'s cartesian `render` (the `coord as? Cartesian2D` branch), after building `polyline` (and the optional `areaPoly`), wrap them in a lineGroup and attach a grid clip:

```swift
        let hasAnimation = seriesModel.isAnimationEnabled() ?? false
        let lineGroup = Group()
        // (add areaPoly first if present, then polyline — same z-order as before)
        // move the existing `group.add(areaPoly)` / `group.add(polyline)` into lineGroup.add(...)
        let clipPath = createGridClipPath(coord, hasAnimation, seriesModel)   // match real signature
        lineGroup.setClipPath(clipPath)
        _ = group.add(lineGroup)
```
Concretely: change the existing `_ = group.add(areaPoly)` and `_ = group.add(polyline)` to add into `lineGroup` instead, create the clip via `createGridClipPath` with the real argument list (confirmed in Step 1 — pass nil for done/during), `lineGroup.setClipPath(clipPath)`, then `group.add(lineGroup)`. Leave the symbol loop adding symbols to `group` (unclipped) — symbol scale-in for line is deferred (note it with a PORT-TODO). Do NOT touch the polar branch (`renderPolarLine`) — polar clip is deferred.

- [ ] **Step 6: Run tests to green + full suite**

Run: `swift test --filter LineTransitionTests` (PASS), then `swift test 2>&1 | grep "Executed .* tests, with"` (0 failures).

- [ ] **Step 7: Static PNG sanity + build**

Run: `swift build 2>&1 | grep -iE "error|warning" | grep -v calendarPrepareCustom` (empty).
Then `swift run EChartsDemoGallery --render line-basic /tmp/line.png` (find the real name via `--list | grep -i line`) — the static frame injects `animation:false`, so the clip is at full width and the WHOLE line must be visible (not clipped/blank). If the line is missing or partially clipped in the static PNG, the animation-off path is wrong — fix before committing.

- [ ] **Step 8: Commit**

```bash
git add Sources/EChartsKit/chart/helper/createClipPathFromCoordSys.swift Sources/EChartsKit/chart/line/LineView.swift Tests/EChartsKitTests/LineTransitionTests.swift
git commit -m "$(cat <<'EOF'
line: clip-path draw-on entrance via createGridClipPath + basicTransition

Swap createGridClipPath's no-animation stub for the real initProps (shape dict), and
have LineView wrap the polyline/area in a lineGroup clipped by the growing rect, so a
cartesian line draws on when animation is enabled (full, unclipped, when off — static
PNG unaffected). Symbol scale-in for line and polar clip are deferred.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
)"
git push origin main
```

---

## Self-Review

- **Coverage:** clip-helper animation + LineView attach → Task 1. Polar clip + line symbol scale-in explicitly deferred (noted).
- **Placeholders:** none. Steps 1/4/5 are real verify-then-edit against the actual signature.
- **Type consistency:** uses shared `initProps` (B1) with a shape DICT; test steps the clip's `width` track for a real 0→full delta (matches the scatter/pie test pattern); `getClipPath`/`setClipPath` are the real Element API.
- **Risks:** the `during`/`done` closure type adaptation into `initProps` (Step 4) — match the real signatures. The animation-OFF static frame MUST show the full line (Step 7 guards this — a wrong collapse-direction or a clip left at width 0 would blank the line in every line PNG).
