# Live Animation Host Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the native side actually animate — starting with the effectScatter ripple — by giving the gallery a live, frame-driven native host instead of a static image.

**Architecture:** Three parts. (A3) `EffectScatterView` builds real looping scale+opacity animators on ripple symbols, faithful to `chart/helper/EffectSymbol.ts`. (A2) A guard test proves those animators register with `zr.animation` when `EChartsView._syncRoot()` adds the root (the `Group.addSelfToZr` recursion already does this). (A1) A new `EChartsHostView` (macOS `NSView`) hosts an `EChartsView` + `CALayerPainter` + `AnimationLoop`, reusing `ZRenderView`'s proven `AnimationLoop → zr.animation.update() → zr._flush → painter.refresh` frame chain; the gallery GUI's static native pane is replaced with it.

**Tech Stack:** Swift, SwiftPM. ZRenderKit (Animator/Animation), EChartsKit (EChartsView/EChartsSlim/EffectScatterView), NativePainter (CALayerPainter/AnimationLoop/NativeHandlerProxy), AppKit (gallery GUI, macOS).

## Global Constraints

- Faithful to vendored upstream `upstream/echarts/src/` — it is ground truth for port-bug vs harness-artifact decisions.
- Build with **0 warnings**.
- `swift test` stays green: **310 tests, 0 failures, 58 skipped** (new tests add to this).
- Commit + push to `main` after each task. **No backticks in commit messages.** End every commit message with:
  `Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>`
- Do NOT change the headless PNG render path (`--render` / `--render-all` / `--compare` → `EChartsSlim` → `renderToImage`); it stays the static-parity oracle.
- Layering rule: `EChartsKit` depends only on `ZRenderKit` (NOT NativePainter). The animation loop is driven by the host, never from inside `EChartsView`.

---

## File Structure

- `Sources/EChartsKit/chart/effectScatter/EffectScatterView.swift` — **modify**: replace the static concentric-ring approximation (~lines 140–172) with per-point `EffectSymbol`-style groups carrying looping animators. This is the only behavioral change to the render tree.
- `Tests/EChartsKitTests/EffectScatterAnimationTests.swift` — **create**: headless proof the ripple builds looping scale+opacity animators and that stepping their clips interpolates (Task 1), plus the `zr.animation` registration guard (Task 2).
- `Sources/EChartsDemoGallery/EChartsHostView.swift` — **create**: macOS `NSView` live host wrapping `EChartsView`. Lives in the gallery target because that target already depends on both EChartsKit and NativePainter; placing it in NativePainter would invert the intended layering (NativePainter does not depend on EChartsKit). Promotion to a shared `EChartsHost` module is a follow-up when the real app needs it.
- `Sources/EChartsDemoGallery/Entry.swift` — **modify**: `buildUI()` / `show(_:)` swap the static `nativeImageView` for a live `EChartsHostView`.

---

### Task 1: effectScatter looping ripple animation (A3)

**Files:**
- Modify: `Sources/EChartsKit/chart/effectScatter/EffectScatterView.swift` (ripple block, currently ~lines 140–172, inside the `for i in 0..<data.count()` loop)
- Test: `Tests/EChartsKitTests/EffectScatterAnimationTests.swift`

**Interfaces:**
- Consumes (existing, verified): `ZRenderKit.Group()`, `group.add(_:) -> Group`; `symbol.createSymbol(_ type:String, _ x:Double, _ y:Double, _ w:Double, _ h:Double, _ fill:ZRColor?) -> ECSymbol`; `Path` with settable `.x/.y/.scaleX/.scaleY` (Transformable) and `.pathStyle: PathStyleProps` (`.opacity`, `.fill`, `.stroke`, `.lineWidth`); `Element.animate(_ key:String?, _ loop:Bool?) -> Animator<Any>`; `Animator.when(_ time:Double, _ props:Dictionary<Any>) -> Animator`, `.delay(_:) -> Animator`, `.start() -> Animator`, `.getClip()`, `.targetName`; `Clip.step(_ time:Double, _ delta:Double)`.
- Produces (for Task 2's test): ripple symbol `Path`s named `"ripple"`, each carrying exactly two animators — one transform animator (`targetName` nil/`""`) tweening `scaleX/scaleY` and one style animator (`targetName == "style"`) tweening `opacity`.

- [ ] **Step 1: Write the failing test**

Create `Tests/EChartsKitTests/EffectScatterAnimationTests.swift`:

```swift
// Proves the effectScatter ripple builds real LOOPING animators (faithful to
// chart/helper/EffectSymbol.ts) instead of the old static concentric rings, and that stepping
// their clips interpolates scaleX (0.5 → rippleScale/2) and opacity (→ 0). Headless: no zr tick,
// clips are stepped directly at synthetic times — the AnimationSmokeTests / ShapeAnimationWiringTests
// pattern.
import XCTest
@testable import EChartsKit
@testable import ZRenderKit

final class EffectScatterAnimationTests: XCTestCase {

    /// A single-point effectScatter so ring 0's delay is exactly 0 (effectOffset = idx/count = 0),
    /// letting the clip step cleanly from t=0.
    private func makeView() -> EChartsView {
        let option: [String: Any] = [
            "xAxis": ["type": "value"],
            "yAxis": ["type": "value"],
            "series": [[
                "type": "effectScatter",
                "symbolSize": 20,
                "rippleEffect": ["scale": 2.5, "number": 3, "period": 4, "brushType": "fill"],
                "data": [[1.0, 1.0]]
            ]]
        ]
        let view = EChartsView(width: 400, height: 300)
        view.setOption(option)
        return view
    }

    /// Depth-first find the first ripple symbol path (named "ripple") in the ec render tree.
    private func findRipple(_ el: Element) -> Path? {
        if let p = el as? Path, p.name == "ripple" { return p }
        if let g = el as? Group {
            for c in g.children() { if let hit = findRipple(c) { return hit } }
        }
        return nil
    }

    func test_ripple_has_looping_scale_and_opacity_animators() throws {
        let view = makeView()
        guard let ripple = findRipple(view.ec.getRoot()) else {
            return XCTFail("no ripple symbol path found (expected name == \"ripple\")")
        }

        // Two animators: transform (scaleX/scaleY) + style (opacity).
        XCTAssertEqual(ripple.animators.count, 2, "expected transform + style ripple animators")

        let transform = ripple.animators.first { ($0.targetName ?? "") == "" }
        let style = ripple.animators.first { $0.targetName == "style" }
        XCTAssertNotNil(transform, "missing transform (scale) animator")
        XCTAssertNotNil(style, "missing style (opacity) animator")

        // Baseline: ripple starts at scaleX 0.5.
        XCTAssertEqual(ripple.scaleX, 0.5, accuracy: 1e-9, "ripple should start at scaleX 0.5")

        // Step the transform clip to 50% of a 4000ms period → halfway from 0.5 to rippleScale/2 (1.25).
        guard let tClip = transform?.getClip() else { return XCTFail("no transform clip") }
        _ = tClip.step(0, 0)
        _ = tClip.step(2000, 2000)
        XCTAssertEqual(ripple.scaleX, (0.5 + 1.25) / 2, accuracy: 1e-3, "scaleX should tween 0.5 → 1.25")

        // Step the style clip to 100% → opacity 0.
        guard let sClip = style?.getClip() else { return XCTFail("no style clip") }
        _ = sClip.step(0, 0)
        _ = sClip.step(4000, 4000)
        XCTAssertEqual(ripple.pathStyle.opacity ?? -1, 0.0, accuracy: 1e-3, "opacity should tween to 0")
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter EffectScatterAnimationTests`
Expected: FAIL — the current static rings are named nothing / are `Circle`s with no animators, so `findRipple` returns nil → "no ripple symbol path found".

- [ ] **Step 3: Write the ripple refactor**

In `EffectScatterView.swift`, replace the static ripple block (the `let rippleModel = ...` block through the `for k in 0..<rNumber { ... }` loop that builds `Circle`s) with per-point `EffectSymbol`-style groups. Faithful to `upstream/echarts/src/chart/helper/EffectSymbol.ts` `startEffectAnimation` + `updateData` (`rippleGroup.setScale(symbolSize)`; ripple path `createSymbol(type,-1,-1,2,2)` at `scaleX/Y=0.5`; looping `animate('',true)` scale + `animate('style',true)` opacity; `delay = -i/number*period + effectOffset`):

```swift
            // Faithful port of EffectSymbol.startEffectAnimation (chart/helper/EffectSymbol.ts).
            //   A per-point group is translated to the data point; a rippleGroup scaled to symbolSize
            //   holds `number` ripple symbols, each a 2x2 unit symbol (see upstream #4136) at scaleX/Y
            //   0.5, LOOPING-animated to rippleScale/2 with a staggered delay, fading opacity → 0.
            let rippleModel = seriesModel.getModel("rippleEffect")
            let rScale = (rippleModel.get("scale") as? Double) ?? 2.5
            let rNumber = Int((rippleModel.get("number") as? Double) ?? 3)
            let rBrush = (rippleModel.get("brushType") as? String) ?? "fill"
            let rPeriod = ((rippleModel.get("period") as? Double) ?? 4) * 1000    // seconds → ms
            let showOn = (seriesModel.get("showEffectOn") as? String) ?? "render"
            if rScale > 1, rNumber > 0, showOn == "render", let cs = colorString(itemStyle?["fill"]) {
                // Per-point group at the data point; rippleGroup scaled to the symbol size.
                let pointGroup = Group()
                pointGroup.x = point[0]
                pointGroup.y = point[1]
                let rippleGroup = Group()
                rippleGroup.scaleX = sizeW
                rippleGroup.scaleY = sizeH
                let effectOffset = Double(i) / Double(Swift.max(1, data.count()))
                for k in 0..<rNumber {
                    // 2x2 unit symbol centered at local origin (upstream -1,-1,2,2 / #4136).
                    guard let el = symbol.createSymbol(symbolType, -1, -1, 2, 2, .string(cs)) as? Path
                    else { continue }
                    el.name = "ripple"
                    var rstyle = PathStyleProps()
                    if rBrush == "stroke" {
                        rstyle.stroke = .string(cs); rstyle.lineWidth = 1; rstyle.fill = nil
                    } else {
                        rstyle.fill = .string(cs)
                    }
                    rstyle.opacity = 1
                    el.useStyle(rstyle)
                    if rBrush == "stroke" { el.pathStyle.fill = nil }   // Class-1 guard (no black fill)
                    el.scaleX = 0.5
                    el.scaleY = 0.5
                    el.z2 = 99
                    let delay = -Double(k) / Double(rNumber) * rPeriod + effectOffset
                    _ = el.animate("", true)
                        .when(rPeriod, ["scaleX": rScale / 2, "scaleY": rScale / 2])
                        .delay(delay)
                        .start()
                    _ = el.animate("style", true)
                        .when(rPeriod, ["opacity": 0.0])
                        .delay(delay)
                        .start()
                    _ = rippleGroup.add(el)
                }
                _ = pointGroup.add(rippleGroup)
                _ = group.add(pointGroup)
            }
```

Note: keep the existing base-symbol block (the `symbol.createSymbol(symbolType, point[0]-sizeW/2, ...)` that follows) unchanged — the base symbol still draws at the point. Only the ripple approximation is replaced.

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter EffectScatterAnimationTests`
Expected: PASS.

- [ ] **Step 5: Verify no static-render regression + full suite**

Run: `swift build 2>&1 | grep -i warning | head` (expect no output), then
`swift test 2>&1 | tail -5` (expect 0 failures; count is 310 + new tests).
Then confirm the PNG path still renders: `swift run EChartsDemoGallery --render effectscatter-basic /tmp/es.png` (expect it to write a PNG; the frozen first frame is fine).

- [ ] **Step 6: Commit**

```bash
git add Sources/EChartsKit/chart/effectScatter/EffectScatterView.swift Tests/EChartsKitTests/EffectScatterAnimationTests.swift
git commit -m "$(cat <<'EOF'
effectScatter: real looping ripple animators (faithful to EffectSymbol.ts)

Replace the static concentric-ring approximation with per-point EffectSymbol-style
groups: 2x2 unit ripple symbols at scaleX/Y 0.5, looping animate('',true) scale to
rippleScale/2 + animate('style',true) opacity to 0, staggered by -i/number*period.
Headless test steps the clips to assert scale/opacity interpolation.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
)"
git push origin main
```

---

### Task 2: animator-registration guard (A2)

**Files:**
- Test: `Tests/EChartsKitTests/EffectScatterAnimationTests.swift` (add a second test method)
- Modify (only if the test fails): `Sources/EChartsKit/core/EChartsView.swift` (`_syncRoot`)

**Interfaces:**
- Consumes: `EChartsView.zr: ZRender` (public), `zr.animation: Animation?`; `Element.__zr` (internal, visible via `@testable`); the ripple `Path`s from Task 1.
- Produces: nothing new — this is a characterization/guard test of the existing `Group.addSelfToZr` → `zr.animation.addAnimator` chain (`Group.swift:269`, `Element.swift:1289`, `ZRender.swift:209`). It documents the invariant that A1's frame loop depends on.

- [ ] **Step 1: Write the test**

Add to `EffectScatterAnimationTests.swift`:

```swift
    func test_ripple_animators_register_with_zr_animation_on_sync() throws {
        let view = makeView()               // setOption already ran _syncRoot()
        guard let ripple = findRipple(view.ec.getRoot()) else {
            return XCTFail("no ripple symbol path found")
        }
        // _syncRoot added ec.getRoot() to view.zr; Group.addSelfToZr recurses to every child,
        // so each ripple path's __zr must now be the live zr — which is what registered its
        // animators with zr.animation (the prerequisite for the host frame loop to tick them).
        XCTAssertTrue(ripple.__zr === view.zr,
                      "ripple path was not added to the live zr — animators never registered")
        XCTAssertEqual(ripple.animators.count, 2, "ripple should still carry both animators")
    }
```

- [ ] **Step 2: Run the test**

Run: `swift test --filter EffectScatterAnimationTests/test_ripple_animators_register_with_zr_animation_on_sync`
Expected: PASS (the `Group.addSelfToZr` recursion already registers them). If it FAILS, `_syncRoot` is not reaching the ripple subtree — fix by ensuring `zr.add(ec.getRoot())` runs after the render populated the root, and that later re-renders re-add fresh series groups to the in-zr root (Step 3). Do not proceed to Task 3 until this passes.

- [ ] **Step 3: (Contingency) fix `_syncRoot` only if Step 2 failed**

If and only if Step 2 failed, in `EChartsView.swift` ensure the root is synced *after* the ec render tree is built each `setOption` and that the add-once guard does not skip registering newly-added series subtrees. Concretely, drop the add-once short-circuit for the child-registration path so a rebuilt series group added under the already-in-zr root still triggers `child.addSelfToZr(zr)` (`Group.add` at `Group.swift:173` already does this when the parent's `__zr` is set — verify `ec.getRoot().__zr === zr` after the first sync). Re-run Step 2 to confirm PASS. If Step 2 passed, skip this step entirely (no code change).

- [ ] **Step 4: Commit**

```bash
git add Tests/EChartsKitTests/EffectScatterAnimationTests.swift Sources/EChartsKit/core/EChartsView.swift
git commit -m "$(cat <<'EOF'
effectScatter: guard test — ripple animators register with zr.animation on sync

Characterization test proving Group.addSelfToZr recursion (via _syncRoot's
zr.add(root)) registers the ripple animators with the live zr.animation — the
prerequisite for the host frame loop to actually tick them.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
)"
git push origin main
```

---

### Task 3: EChartsHostView — live macOS host (A1)

**Files:**
- Create: `Sources/EChartsDemoGallery/EChartsHostView.swift`

**Interfaces:**
- Consumes: `NativePainter.CALayerPainter(size:dpr:backgroundColor:)`, `.rootLayer`; `NativePainter.NativeHandlerProxy()`; `NativePainter.AnimationLoop(animation:)` / `.init(_ onFrame:)` / `.start()` / `.stop()`; `EChartsKit.EChartsView(width:height:painter:proxy:)`, `.zr`, `.setOption(_:)`, `.resize(_:_:_:)`; `ZRenderKit.ZRenderResizeOpt`.
- Produces: `EChartsHostView: NSView` with `func setOption(_ option: [String: Any])` and public `let echartsView: EChartsView`.

- [ ] **Step 1: Create the host view**

Create `Sources/EChartsDemoGallery/EChartsHostView.swift`, mirroring the macOS `ZRenderView` frame chain (`ZRenderView.swift:308–400`) but hosting an `EChartsView` (whose `zr` we drive):

```swift
// Live native host for the gallery: an NSView that hosts an EChartsView + CALayerPainter and
// drives its zr.animation on a frame clock — the animated analog of the static native image pane.
// Mirrors NativePainter/ZRenderView.swift's AnimationLoop -> zr.animation.update() -> zr._flush ->
// painter.refresh chain, but the content is an echarts option instead of a raw zr scene.
//
// Placement: this target already depends on EChartsKit + NativePainter. It cannot live in
// NativePainter (which does not depend on EChartsKit); promoting it to a shared module is a
// follow-up when the real app needs it.
#if canImport(AppKit)
import AppKit
import ZRenderKit
import NativePainter
import EChartsKit

final class EChartsHostView: NSView {

    let echartsView: EChartsView
    private let painter: CALayerPainter
    private let proxy: NativeHandlerProxy
    private let animationLoop: AnimationLoop

    init(frame: CGRect, dpr: Double? = nil) {
        let size = frame.size == .zero ? CGSize(width: 1, height: 1) : frame.size
        let painter = CALayerPainter(size: size, dpr: dpr, backgroundColor: NSColor.white.cgColor)
        let proxy = NativeHandlerProxy()
        let ecView = EChartsView(width: Double(size.width), height: Double(size.height),
                                 painter: painter, proxy: proxy)

        self.painter = painter
        self.proxy = proxy
        self.echartsView = ecView
        self.animationLoop = AnimationLoop(animation: ecView.zr.animation)

        super.init(frame: frame)

        self.wantsLayer = true
        self.layer?.addSublayer(painter.rootLayer)
        self.animationLoop.start()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    deinit {
        self.animationLoop.stop()
        self.echartsView.zr.dispose()
    }

    // Top-left / y-down, matching zrender + the flipped AppKit root layer.
    override var isFlipped: Bool { true }

    func setOption(_ option: [String: Any]) {
        self.echartsView.setOption(option)
    }

    override func layout() {
        super.layout()
        let size = bounds.size
        if size.width <= 0 || size.height <= 0 { return }
        painter.rootLayer.frame = CGRect(origin: .zero, size: size)
        echartsView.resize(Double(size.width), Double(size.height), nil)
    }

    // Pointer → proxy so hover/tooltip/emphasis (already wired in EChartsView) work live.
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero,
            options: [.activeInActiveApp, .mouseMoved, .inVisibleRect], owner: self))
    }

    override func mouseMoved(with e: NSEvent) {
        let p = convert(e.locationInWindow, from: nil)
        proxy.mousemove(ZRRawEvent(zrX: Double(p.x), zrY: Double(p.y)))
    }
    override func mouseDown(with e: NSEvent) {
        let p = convert(e.locationInWindow, from: nil)
        proxy.mousedown(ZRRawEvent(zrX: Double(p.x), zrY: Double(p.y)))
    }
    override func mouseUp(with e: NSEvent) {
        let p = convert(e.locationInWindow, from: nil)
        proxy.mouseup(ZRRawEvent(zrX: Double(p.x), zrY: Double(p.y)))
    }
}
#endif
```

- [ ] **Step 2: Verify the exact NativeHandlerProxy / ZRRawEvent API before building**

The proxy method names and `ZRRawEvent` initializer above are the likely shapes but MUST be confirmed against the source (do not invent). Run:
`grep -n "func mousemove\|func mousedown\|func mouseup\|struct ZRRawEvent\|init(" Sources/NativePainter/ZRenderView.swift | head`
and adjust the three `mouse*` overrides + the `ZRRawEvent(...)` construction to match how the macOS `ZRenderView` builds and forwards events (see `ZRenderView.swift:308–484`). If the coalesced-move pattern is needed, mirror it; for A1 a direct forward is acceptable.

- [ ] **Step 3: Build the gallery target**

Run: `swift build --target EChartsDemoGallery 2>&1 | grep -iE "error|warning" | head`
Expected: no output (compiles clean). There is no unit test for this NSView (display-link + AppKit view); its animator-ticking correctness is covered by Task 2 (registration) + Task 1 (animators), and it reuses ZRenderView's proven frame chain. Manual GUI verification happens in Task 4.

- [ ] **Step 4: Commit**

```bash
git add Sources/EChartsDemoGallery/EChartsHostView.swift
git commit -m "$(cat <<'EOF'
gallery: EChartsHostView — live macOS host that drives zr.animation

NSView hosting an EChartsView + CALayerPainter, ticking zr.animation on an
AnimationLoop (reusing ZRenderView's AnimationLoop -> update -> refresh chain) and
forwarding pointer events to the native proxy. The animated counterpart to the
static native image pane.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
)"
git push origin main
```

---

### Task 4: swap gallery GUI native pane to the live host (A1)

**Files:**
- Modify: `Sources/EChartsDemoGallery/Entry.swift` (`buildUI()` ~lines 116–173, `show(_:)` ~lines 190–203)

**Interfaces:**
- Consumes: `EChartsHostView(frame:)`, `.setOption(_:)` (Task 3); `EChartsDemo.option: [String: Any]`, `.width`, `.height`, `.nativeSupported`.
- Produces: a live-animating native pane in the comparison window.

- [ ] **Step 1: Confirm the demo option accessor**

Run: `grep -n "var option\|let option\|public let option\|nativeSupported\|var width\|var height" Sources/EChartsDemoGallery/EChartsDemo.swift | head`
Confirm `EChartsDemo` exposes the raw option dictionary fed to both panes (the same one `echartsHTMLPage` serializes). Use that property name below in place of `demo.option` if it differs.

- [ ] **Step 2: Replace the static native pane with the host view**

In `Entry.swift`, in the `AppDelegate` (the class owning `nativeImageView`), replace the `nativeImageView` property with a lazily-created host, and rewire `buildUI()` + `show(_:)`:

Replace the property declaration `let nativeImageView = NSImageView()` with:
```swift
    private var nativeHostView: EChartsHostView?
```

In `buildUI()`, replace the three `nativeImageView` lines
```swift
        nativeImageView.imageScaling = .scaleProportionallyUpOrDown
        nativeImageView.translatesAutoresizingMaskIntoConstraints = false
        nativeHost.addSubview(nativeImageView)
```
and the later `pin(nativeImageView, to: nativeHost, inset: 8)` with a live host created and pinned:
```swift
        let hostView = EChartsHostView(frame: NSRect(x: 0, y: 0, width: 300, height: 300), dpr: 2.0)
        hostView.translatesAutoresizingMaskIntoConstraints = false
        nativeHost.addSubview(hostView)
        self.nativeHostView = hostView
```
and change the pin call to `pin(hostView, to: nativeHost, inset: 8)`.

In `show(_:)`, replace the native-pane block
```swift
        if demo.nativeSupported, let cg = renderNativeImage(demo) {
            nativeImageView.image = NSImage(cgImage: cg, size: NSSize(width: demo.width, height: demo.height))
        } else {
            nativeImageView.image = nil
        }
```
with feeding the option into the live host:
```swift
        if demo.nativeSupported {
            nativeHostView?.setOption(demo.option)
        }
```
(Use the accessor confirmed in Step 1 if not literally `demo.option`.)

- [ ] **Step 3: Build**

Run: `swift build --target EChartsDemoGallery 2>&1 | grep -iE "error|warning" | head`
Expected: no output.

- [ ] **Step 4: Manual verification (macOS GUI)**

Run: `swift run EChartsDemoGallery` (no args → opens the comparison window).
Select `effectscatter-basic` in the sidebar. Expected: the LEFT (native) pane now shows expanding, fading ripples animating continuously — matching the live echarts on the RIGHT. Also spot-check a non-animated demo (e.g. `bar-basic`) renders correctly in the live pane (static but present).
Note honestly in the commit body that this pane is verified by eye; the static PNG oracle cannot validate motion.

- [ ] **Step 5: Commit**

```bash
git add Sources/EChartsDemoGallery/Entry.swift
git commit -m "$(cat <<'EOF'
gallery: live native pane — replace static image with EChartsHostView

The comparison window's left pane now hosts a live EChartsHostView fed the demo
option, so effectScatter ripples (and any future animation) animate next to the
live echarts.js pane. Headless --render/--compare PNG paths are unchanged.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
)"
git push origin main
```

---

## Self-Review

**Spec coverage:**
- A1 live host → Tasks 3 + 4. ✓
- A2 animator registration → Task 2 (guard test + contingency fix). ✓
- A3 effectScatter looping ripple → Task 1. ✓
- Verification (headless oracle + manual GUI) → Task 1 clip-step test, Task 2 registration test, Task 4 manual. ✓
- Non-goals (view reuse/diff, Scheduler, update*) → untouched. ✓

**Placeholder scan:** No TBD/TODO. Two steps (Task 3 Step 2, Task 4 Step 1) are explicit *verify-the-exact-API* steps with a concrete `grep` and adjustment instruction — this is deliberate (the plan must not invent `NativeHandlerProxy`/`ZRRawEvent`/`option` signatures), not a placeholder.

**Type consistency:** `EChartsHostView.setOption(_:)`, `.echartsView`, `EChartsView.zr`, `.setOption`, `.resize`, `Element.animate/animators/targetName`, `Animator.when/delay/start/getClip`, `Clip.step`, `Path.pathStyle.opacity`, `Group.children()/add` — all match the signatures verified in the source during planning. Ripple paths named `"ripple"` consistently across Task 1 (produces) and Task 2 (consumes).

**Risks:** The single real risk (late-created animators not registering) is isolated in Task 2 with a fail-first guard and a scoped contingency fix, and analysis of `Group.addSelfToZr:269` / `Group.add:173` indicates it already holds — so the contingency is expected to be a no-op.
