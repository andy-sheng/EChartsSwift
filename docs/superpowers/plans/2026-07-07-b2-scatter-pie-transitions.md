# B2 — Scatter + Pie Entrance Transitions Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or superpowers:executing-plans. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Apply B1's shared `animation/basicTransition` helpers to ScatterView (symbol scale-in) and PieView (sector angle-expansion), so those charts animate in when the series has animation enabled — faithful to upstream Symbol.ts and PieView.ts.

**Architecture:** Both views currently `group.removeAll()` + statically place elements. Because the reset-fix makes every render a fresh "enter", entrance animation needs no data.diff — just set each element's initial (collapsed) state on creation and call `initProps` toward the final state. Scatter animates the scalar transform `scaleX/scaleY 0→1` (origin at the point). Pie animates the sector `shape.endAngle` from `startAngle→final` (a partial shape DICT, per B1's struct→dict rule).

**Tech Stack:** Swift, EChartsKit (ScatterView, PieView, animation/basicTransition), ZRenderKit (Path transform scaleX/scaleY/originX/originY, SectorShape).

## Global Constraints

- Faithful to `upstream/echarts/src/chart/helper/Symbol.ts` (scale-in) and `upstream/echarts/src/chart/pie/PieView.ts` (`PiePiece.updateData` expansion branch).
- Build 0 warnings (ignore the pre-existing `calendarPrepareCustom.swift` warning; add no new ones). `swift test` green (currently 325).
- Commit + push to `main` after each task. No backticks in commit messages. End with: `Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>`
- Shape animation props MUST be a `[String:Any]` dict of animatable fields, NOT a full PathShape struct (a struct is opaque to `animateToShallow` → snaps to final). Transform props (scaleX/scaleY) are scalar — pass directly.
- Int/Double coercion where option values are read.

---

### Task 1: Scatter symbol scale-in entrance

**Files:**
- Modify: `Sources/EChartsKit/chart/scatter/ScatterView.swift` (symbol creation block ~lines 148-168)
- Test: `Tests/EChartsKitTests/ScatterTransitionTests.swift`

**Interfaces:**
- Consumes: shared `initProps(el, props, model?, dataIndex?, cb?, during?)`; `Path.scaleX`/`.scaleY`/`.originX`/`.originY` (Transformable, settable).
- Produces: entering scatter symbols carry a transform animator when animation on.

Upstream (Symbol.ts:196-198): on first create, `symbolPath.scaleX = symbolPath.scaleY = 0` then `initProps(symbolPath, target, seriesModel, idx)`. In the port, `createSymbol` sizes the path via its shape at full pixel size, so the normal scale is 1 (not symbolSize/2). Set the transform origin to the point center so it grows from the point.

- [ ] **Step 1: Write failing test**

Create `Tests/EChartsKitTests/ScatterTransitionTests.swift`:

```swift
// Entering scatter symbols scale in (scaleX/scaleY 0→1) when the series has animation on, and are at
// full scale with no animator when off. Faithful to chart/helper/Symbol.ts first-create scale-in.
import XCTest
@testable import EChartsKit
@testable import ZRenderKit

final class ScatterTransitionTests: XCTestCase {

    private func firstSymbol(_ el: Element) -> Path? {
        if let p = el as? Path, p.name == "item" { return p }
        if let g = el as? Group { for c in g.children() { if let hit = firstSymbol(c) { return hit } } }
        return nil
    }

    private func option(_ animation: Bool) -> [String: Any] {
        [
            "animation": animation,
            "xAxis": ["type": "value"], "yAxis": ["type": "value"],
            "series": [["type": "scatter", "symbolSize": 20, "data": [[10.0, 10.0], [20.0, 20.0]]]]
        ]
    }

    func test_symbol_scales_in_when_animation_on() {
        let ec = EChartsSlim(width: 400, height: 300)
        ec.setOption(option(true))
        guard let sym = firstSymbol(ec.getRoot()) else { return XCTFail("no scatter symbol") }
        XCTAssertGreaterThan(sym.animators.count, 0, "symbol should have a scale-in animator when animation on")
        XCTAssertEqual(sym.scaleX, 0.0, accuracy: 1e-9, "symbol starts at scaleX 0 before the loop ticks")
    }

    func test_symbol_full_scale_when_animation_off() {
        let ec = EChartsSlim(width: 400, height: 300)
        ec.setOption(option(false))
        guard let sym = firstSymbol(ec.getRoot()) else { return XCTFail("no scatter symbol") }
        XCTAssertEqual(sym.animators.count, 0, "no animator when animation off")
        XCTAssertEqual(sym.scaleX, 1.0, accuracy: 1e-9, "symbol at full scale immediately when animation off")
    }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `swift test --filter ScatterTransitionTests`
Expected: `test_symbol_scales_in_when_animation_on` FAILS (0 animators; scaleX defaults 1). Confirm `Path.scaleX` default is 1 and the symbol is named "item" (it is, ScatterView.swift:152). If `firstSymbol`/accessors differ, fix to real API.

- [ ] **Step 3: Add the scale-in**

In `ScatterView.swift`, after `path.name = "item"` and after `data.setItemGraphicEl(i, path)` (before/around `group.add(path)`), add the entrance. Insert just before `_ = group.add(path)`:

```swift
                // Entrance: scale the symbol in from 0 about the point (upstream Symbol.ts first-create:
                //   symbolPath.scaleX = scaleY = 0; initProps(symbolPath, {scaleX,scaleY}, seriesModel, idx)).
                //   The port's createSymbol sizes via the shape (normal scale 1), so animate 0 → 1 with the
                //   transform origin at the point so it grows from the datum.
                path.originX = point[0]
                path.originY = point[1]
                path.scaleX = 0
                path.scaleY = 0
                initProps(path, ["scaleX": 1.0, "scaleY": 1.0], seriesModel, i)
```

(`seriesModel` is in scope in `render`; `i` is the loop index / dataIndex. Confirm both names against the actual loop.)

- [ ] **Step 4: Run tests to green + full suite**

Run: `swift test --filter ScatterTransitionTests` (PASS), then `swift test 2>&1 | grep "Executed .* tests, with"` (0 failures).

- [ ] **Step 5: Build clean + commit**

Run: `swift build 2>&1 | grep -iE "error|warning" | grep -v calendarPrepareCustom` (empty).
```bash
git add Sources/EChartsKit/chart/scatter/ScatterView.swift Tests/EChartsKitTests/ScatterTransitionTests.swift
git commit -m "$(cat <<'EOF'
scatter: symbol scale-in entrance via shared basicTransition

Faithful to chart/helper/Symbol.ts first-create: set scaleX/scaleY 0 with the transform
origin at the point, then initProps toward scale 1 so symbols grow in from the datum when
animation is enabled (instant full scale when off).

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
)"
git push origin main
```

---

### Task 2: Pie sector angle-expansion entrance

**Files:**
- Modify: `Sources/EChartsKit/chart/pie/PieView.swift` (sector creation loop ~lines 148-190)
- Possibly modify: `Sources/ZRenderKit/Graphic/Shape/Sector.swift` (add `animationSet`/`animationGet` for `endAngle`/`startAngle`/`r` if missing)
- Test: `Tests/EChartsKitTests/PieTransitionTests.swift`

**Interfaces:**
- Consumes: shared `initProps`; `SectorShape` (cx/cy/r0/r/startAngle/endAngle); `Path.attrKV` partial-shape-dict merge (B1) which calls the shape's `animationSet` per key.
- Produces: entering pie sectors sweep open (`endAngle` animates from `startAngle`).

Upstream (PieView.ts:100-118, expansion else-branch): `sector.shape.endAngle = layout.startAngle` then `updateProps(sector, {shape: {endAngle: layout.endAngle}}, seriesModel, idx)`. We use the independent-sweep form (each sector opens from its own startAngle), which needs no cross-piece startAngle threading.

- [ ] **Step 1: Verify SectorShape supports per-key shape animation**

Run: `grep -n "animationSet\|animationGet\|ShapeAnimationAccessor\|endAngle\|startAngle" Sources/ZRenderKit/Graphic/Shape/Sector.swift`
If `SectorShape` has no `animationSet(_ key:_ value:)` handling `startAngle`/`endAngle`/`r` (as `RectShape` does for x/y/width/height — see `Sources/ZRenderKit/Graphic/Shape/Rect.swift`), ADD it, mirroring RectShape exactly (coerce value `as? Double`, set the matching field; `animationGet` returns the field). Without it, the B1 partial-shape-dict merge silently drops `endAngle` and no animation (or a broken shape) results. This is the one likely prerequisite.

- [ ] **Step 2: Write failing test**

Create `Tests/EChartsKitTests/PieTransitionTests.swift`:

```swift
// Entering pie sectors sweep open: endAngle animates from startAngle to the final angle when animation
// is on; sectors are at final angle with no animator when off. Faithful to PieView.ts PiePiece expansion.
import XCTest
@testable import EChartsKit
@testable import ZRenderKit

final class PieTransitionTests: XCTestCase {

    private func firstSector(_ el: Element) -> Sector? {
        if let s = el as? Sector { return s }
        if let g = el as? Group { for c in g.children() { if let hit = firstSector(c) { return hit } } }
        return nil
    }

    private func option(_ animation: Bool) -> [String: Any] {
        [
            "animation": animation,
            "series": [["type": "pie", "radius": "60%",
                        "data": [["value": 40.0, "name": "a"], ["value": 60.0, "name": "b"]]]]
        ]
    }

    func test_sector_sweeps_open_when_animation_on() {
        let ec = EChartsSlim(width: 400, height: 400)
        ec.setOption(option(true))
        guard let sec = firstSector(ec.getRoot()) else { return XCTFail("no pie sector") }
        XCTAssertGreaterThan(sec.animators.count, 0, "sector should have an expansion animator when animation on")
        // Collapsed at start: endAngle == startAngle before the loop ticks.
        let sh = sec.shape as? SectorShape
        XCTAssertEqual(sh?.endAngle ?? .nan, sh?.startAngle ?? .infinity, accuracy: 1e-6,
                       "sector starts collapsed (endAngle == startAngle)")
    }

    func test_sector_final_angle_when_animation_off() {
        let ec = EChartsSlim(width: 400, height: 400)
        ec.setOption(option(false))
        guard let sec = firstSector(ec.getRoot()) else { return XCTFail("no pie sector") }
        XCTAssertEqual(sec.animators.count, 0, "no animator when animation off")
        let sh = sec.shape as? SectorShape
        XCTAssertNotEqual(sh?.endAngle ?? 0, sh?.startAngle ?? 0, "sector at final (non-collapsed) angle when off")
    }
}
```

- [ ] **Step 3: Run to verify failure**

Run: `swift test --filter PieTransitionTests`
Expected: `test_sector_sweeps_open_when_animation_on` FAILS (0 animators; sector at final angle, not collapsed).

- [ ] **Step 4: Add the expansion entrance**

In `PieView.swift`, in the sector creation loop, after building `sectorShape` (final) and creating the `Sector`, but BEFORE `group.add(sector)` and after `sector.useStyle(...)`, insert the collapse + initProps. Replace the plain final-shape creation with a collapse-then-animate:

```swift
            let finalEndAngle = sectorShape.endAngle
            // Entrance (upstream PiePiece expansion): start collapsed at startAngle, then sweep endAngle
            //   open. Shape props MUST be a dict (a full SectorShape struct is opaque to the animator).
            var collapsed = sectorShape
            collapsed.endAngle = sectorShape.startAngle
            let sector = Sector(["shape": collapsed as PathShape])
            // ... (keep the existing z2/useStyle/name/emphasis/setItemGraphicEl lines on `sector`) ...
            initProps(sector, ["shape": ["endAngle": finalEndAngle] as [String: Any]], seriesModel, idx)
```

Integrate cleanly with the existing block (do not duplicate the useStyle/emphasis/label lines — just change the initial shape to `collapsed` and add the `initProps` call after the sector is fully configured, before or after `group.add`). When animation is off, `initProps` sets `endAngle` to final instantly via `attr` → sector at final angle. Confirm the empty-circle sector and NaN-skip paths are untouched.

- [ ] **Step 5: Run tests to green + full suite**

Run: `swift test --filter PieTransitionTests` (PASS), then full `swift test` (0 failures).

- [ ] **Step 6: Build clean + commit**

Run: `swift build 2>&1 | grep -iE "error|warning" | grep -v calendarPrepareCustom` (empty).
```bash
git add Sources/EChartsKit/chart/pie/PieView.swift Sources/ZRenderKit/Graphic/Shape/Sector.swift Tests/EChartsKitTests/PieTransitionTests.swift
git commit -m "$(cat <<'EOF'
pie: sector angle-expansion entrance via shared basicTransition

Faithful to PieView.ts PiePiece expansion: create each sector collapsed (endAngle ==
startAngle), then initProps the endAngle open so sectors sweep in when animation is enabled
(instant final angle when off). Adds SectorShape per-key animationSet if it was missing.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
)"
git push origin main
```

---

## Self-Review

- **Coverage:** Scatter scale-in → Task 1; Pie expansion → Task 2. Line clip-draw-on is explicitly deferred to B3 (different mechanism).
- **Placeholders:** none. Task 2 Step 1 is a real prerequisite-verify (SectorShape animationSet) with a concrete fallback (mirror RectShape).
- **Type consistency:** both use the shared `initProps(el, props, model, dataIndex)` from B1; scatter uses scalar transform props (no dict), pie uses a shape dict (per the struct→dict rule); tests assert real animator creation + collapsed/final initial state, not tautologies.
- **Risks:** SectorShape may lack per-key animationSet (Task 2 Step 1 handles it). Pie label is added after the sector — the label does not animate (acceptable; upstream animates labels separately — deferred). Scatter `originX/originY` must be the point so scaling grows from the datum, not the canvas origin.
