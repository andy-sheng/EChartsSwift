# DemoGallery ↔ zrender test/*.html — parity gaps

_Generated from the parity audit (49 non-Shapes demos). The 6 Shapes demos
(bezier/curves/fullSector/pin/poly/sector) are already aligned. 2 aligned (pattern, event);
31 demo-fix (tracked separately); 4 not-migratable; 12 need framework work (below)._

## 🏗 Framework changes required (12 — clipping ✅ pattern-transform ✅ state ✅ rectText ✅ fixed; ssr-measureText crash ✅ fixed (text/text-collide unblocked too); ~7 remaining; pattern-transform bg-image still pending)

### clipping  _(Paint)_ — FIXED ✅

- **What it diverged from:** HTML clips a grid of cells by nested group clips (a circle growing 0->300) intersected with a rect; native used to draw a static 90-cell mosaic with per-cell circle clips and no animation — a reinterpretation, not a port.
- **Root cause (painter, not Storage):** `Storage._updateAndAddDisplayable` (Storage.swift:118-165) already built each leaf's full inherited `__clipPaths` chain (parent Group clips ∩ own clip) correctly. The gap was purely in the painter: `CALayerPainter.drawPath/drawTSpan/drawZRImage` applied only each element's OWN `getClipPath()` (nil for a group's children), so `Group.setClipPath()` never clipped children and circle ∩ rect could not render.
- **Fix:** added `CALayerPainter.applyClipChain(_:into:)` — applies every path in `el.__clipPaths` (each baking its own world transform; `setClipPath` intersects → nested intersection), falling back to `getClipPath()` for the unused `renderScene` path. Wired into all three draw helpers.
- **Demo now:** `Demos/clipping.swift` mirrors the html — `g1.add(g2); zr.add(g1)`, `g1.setClipPath(rect(-250,-20,500,300)@200,150)`, `g2.setClipPath(circle(0,0,0)@200,200)`, a grid of **real test.png** `ZRImage` cells (50×50, the SAME asset as the html, decoded once and shared via `decodedUpstreamAsset`) added to g2, and `clipCircle.animate("shape").when(1000,["r":300]).start()` wiping it into view. (Allowed deviations: grid bounded to the clip-visible band instead of 50x50; no draggable; the two decorative dashed outlines dropped.)
- **Regression test:** `CALayerPainterSmokeTests.testGroupClipChainPropagatesToChildren` — a clip-less leaf nested in g1(rect)⊃g2(circle) paints only inside rect ∩ circle (probes inside / circle-excluded / rect-excluded; asserts `cell.__clipPaths.count == 2`).

### pattern-transform  _(Paint)_ — FIXED ✅ (rotation; bg-image still pending)

- **What it diverged from:** A single Rect filled by an image Pattern carrying a transform; native matched the Rect+Pattern calls and honored scaleX/x, but pattern **rotation** wasn't rendered (axis-aligned tiling) and the HTML background-image call is unported.
- **Fix (rotation):** `CGRenderer.tilePattern` now applies the full pattern matrix `M = translate(x,y) · rotate(rotation) · scale(scaleX,scaleY)` (the same compose order as upstream `createCanvasPattern`, canvas/graphic.ts:81-85): it concatenates M onto the world CTM, tiles the RAW image (period = image size) in pattern-local space, and bounds the tile indices by mapping the clip's world bbox back through M⁻¹. Reduces to the old axis-aligned tiling when rotation=0 (the `pattern` demo is unchanged). Verified by rendering the native demo with the SAME upstream asset (test.png) and diffing against `--web-snapshot pattern-transform`: identical clockwise π/6 tilt + horizontal squash.
- **Demo now:** `Demos/pattern-transform.swift` restores the html's exact shape `rect(0,0,200,200)`, fills with the **real test.png** (`upstreamAsset("test.png")`, same asset as the html), and keeps `pat.x=100; pat.scaleX=0.5; pat.rotation=π/6` — the tiles render rotated+squashed, matching the html.
- **Regression test:** `CALayerPainterSmokeTests.testRotatedPatternFillsRectAndClips` — a rotated-pattern-filled rect paints inside and stays clipped (no tiling spill outside).
- **STILL PENDING (bg-image):** `zr.setBackgroundColor({image, repeat:'no-repeat'})` is unported — `ZRender.setBackgroundColor` only stores `_backgroundColor` and `CALayerPainter` has no image-background path. The demo documents this single call as a deviation; the rect+pattern itself is now faithful.

### state  _(Paint)_ — FIXED ✅

- **What it diverged from:** Demo toggles 6 named states (ensureState/toggleState/stateTransition) on ONE Rect; native used to fake it with two static rects + two labels.
- **Fix (states machinery):** ported `Element.useState / useStates / clearStates / toggleState / removeState / replaceState / saveCurrentToNormalState / _innerSaveToNormal / _mergeStates` + `stateTransition`. `ElementState` is now a `class` (upstream states are mutable reference objects, so `ensureState('x').x = …` mutates the stored state). **PORT-NOTE on structure:** rather than upstream's per-class `_applyStateObj` (transform/style/shape split + hover-layer branches), this port computes the full target prop bag (active states merged over saved-normal, with dropped props/sub-keys restored) and applies it via the existing `animateTo`/`_transitionState` — which already drives transform / shape / style uniformly. Same observable behavior; hover-layer (`shouldUseHoverLayer`, a no-op for non-text elements) and the in-flight-animation-final-save loop are omitted (documented in code).
- **Demo now:** `Demos/state.swift` is ONE Rect (shape {-50,-50,100,100}, x:100, y:100, fill:'red', shadowColor) with the 6 states registered exactly (moveRight.x=200, moveDown.y=200, rotate.rotation=2, enlarge.shape, changeFill.style.fill='green', shadow.style.shadowBlur=20), `stateTransition={duration:1000, additive:true, easing:'cubicOut'}`, and a control panel wiring toggleState / clearStates / applyAllStates(useStates(all)) + an animation toggle. The two emphasis rects + labels are gone.
- **Gotcha found & fixed:** state `fill` must be a raw color **string** (`'green'`), not a `ZRColor` enum — the color tween bridges `ZRColor↔string` via `pathStyle.animationGet/Set("fill")`, so a raw `ZRColor` target mismatched the bridged current value and went discrete (fill stayed red). Matching the html's `'green'` string makes the color interpolate.
- **Regression tests:** `StateMachineryTests` (6) — transform / shape / style(shadow) / fill-color apply+restore, additive accumulation + clearStates, and useStates merge + restore-dropped, each driven to completion and asserted.

### rectText  _(Text)_ — FIXED ✅

- **What it diverged from:** Demo shows labels at a Rect's edges/corners/inside; native used to fake it with standalone ZRText because the host-attached `textConfig.position` path was a no-op.
- **Fix:** implemented `Element.updateInnerText` — positions the attached `_textContent` from `textConfig` (position via contain/text `calculateTextPosition`, + rotation / offset / origin) into the text's `innerTransformable` (which `ZRText.getLocalTransform` renders from; Storage already adds the attached text to the display list), and resolves inside/outside fill+stroke into the text's default style. (PORT-NOTE: the `autoOverflowArea`/`overflowRect` branch is deferred.)
- **Demo now:** `Demos/rectText.swift` builds the real attach calls — for all 13 positions a Rect(shape x:100,y:50,w:150,h:70) with `setTextContent(ZRText)` + `setTextConfig({position})`, grid-laid, fill-only. Inside/outside text color is auto-resolved (zrender contrast logic). Adds a control panel (textConfig.distance / rotation / text padding) driving every cell.

### ssr-measureText  _(Text)_ — crash fixed (getBoundingRect)

- **What it diverged from:** SSR measureText test: draws a Text and strokes its `getBoundingRect()` box; native substituted an estimated box because `ZRText.getBoundingRect()` crashed.
- **Framework fix:** `getBoundingRect()` crashed with "Index out of range" because it passed an empty scratch `tmpMat: MatrixArray = []` to `getLocalTransform`, which only allocated when `m == nil`, then wrote `m[4]`. Fixed at the single point — `Transformable.getLocalTransform` now reallocates an empty/short scratch to the 6-slot identity. (Also unblocks the `text` demo's "Show boundingRect" button and `text-collide`'s real collision.)
- **Demo-side (optional, not yet done):** the ssr-measureText demo can now replace its estimated box with the real `el.getBoundingRect()`.

### text-overflow  _(Text)_  — web pane fixed; native still parseText-gapped

- **Web pane FIXED ✅:** the upstream html rendered BLANK in the gallery's right pane because it loads dat.gui from a dead `http://localhost:8001/...` URL (the working jsdelivr CDN line right above it is commented out). The gallery now sanitizes such pages (`Entry.sanitizedTestPage`): inline the local scripts as `data:` URIs + repoint the dead dat.gui at the CDN, then load self-contained. The original html now renders (dat.GUI panel + text blocks + isTruncated readout).
- **What it does / why it diverges:** Width-boxed Text overflow demo; native fakes wrapping with pre-wrapped strings because the ZRText layout engine (parseText) is a stub, so it cannot actually issue the demo's overflow/wrap behavior.
- **Framework gap:** ZRText text layout engine (upstream graphic/helper/parseText) is a PORT-TODO stub in Sources/ZRenderKit/Graphic/Text.swift (lines 15-25): parsePlainText implements only the no-wrap/no-truncate subset; overflow 'break'/'breakAll'/'truncate', lineOverflow:'truncate', and ellipsis/truncate-to-placeholder are no-ops; parseRichText returns an empty content block; isTruncated is never computed. The width-based line wrapping, overflow strategies, ellipsis, and rich-text layout that this demo is built to exercise cannot be rendered until the parseText seam is ported.
- **Demo-side fix (after framework lands):** After the parseText layout engine lands (framework): rebuild block() to mirror the HTML default state — 4 standalone ZRText using the real texts (LARGE_TEXT_EN, LARGE_TEXT_ZH, 'abcde', '红黄蓝'), width=200, height=400, x=100/350/600/850, y=0, borderColor='#000', default fill (drop fill='#2f4f2f'), remove backgroundColor and borderRadius, add rich={"highlight": backgroundColor 'yellow' fontSize 20}, and stop pre-wrapping (pass the raw long text so overflow:'break'/'breakAll'/'truncate' does the wrapping). The dat.GUI panel → native control panel substitution is an acceptable gallery deviation; the extra title Text is a gallery label, not in the HTML. Until the layout engine exists, the demo can only approximate, so a pure Demos-side fix is not sufficient.

### transform  _(Transform)_

- **What it does / why it diverges:** Upstream is an interactive "SVG Compare" demo: one Text glyph "4" via setLocalTransform(matrix) + two parseSVG renderings; native is a wholesale reinterpretation (4 Polygon arrows via x/y/rotation/scaleX/scaleY) — not aligned, full parity blocked on parseSVG.
- **Framework gap:** zrender.parseSVG / SVG parser is not implemented in the native port (no parseSVG, SVGParser or parseXML in Sources/). transform.html's two parseSVG-based renderings (transform: matrix(...) and method(...)) require it and therefore cannot be migrated without a framework change. The setLocalTransform path is supported (Transformable.setLocalTransform / updateTransform exist).
- **Demo-side fix (after framework lands):** For the migratable third: rebuild the demo around a ZRText glyph "4" (font '70px Arial', fill 'blue', align .center, verticalAlign .middle) and call text.setLocalTransform(m) + text.updateTransform(), where m is a 6-element affine matrix composed from translate/rotate/skew/scale (mirroring upstream's CSS-computed matrix), driven by the native control panel (the dat.GUI-style sliders + drag-to-reorder order items are an acceptable control-panel deviation, but they are what produce the matrix). Add skewX/skewY to the composition. The two parseSVG renderings (matrix and method) remain blocked until an SVG parser exists in the framework.

### animation  _(Animation)_ — FIXED ✅

- **What it diverged from:** animation.html drives ONE gradient circle (inner label) through a looping square position path + a gradient1→gradient2 fill tween; native used to draw 3 circles (1 gradient + 2 fabricated solid) with a radius pulse and no gradient fill tween.
- **Framework fix (gradient fill tween):** `util.isGradientObject` now detects the concrete `Gradient` base class (LinearGradient/RadialGradient — they can't adopt the `GradientObject` protocol, `global: Bool` vs `Bool?`); `zrColorToAnimValue` hands the Animator the gradient (was nil); the Animator's gradient parse branch copies x/y/x2/y2/r geometry; and `animValueToZRColor` rebuilds a Linear/RadialGradient `ZRColor` from the interpolated dict. The Animator's interpolation + `fillColorStops` stop-padding were already there. Test: `GradientTweenTests` (fill tweens red→black ⇒ black→blue→white, 2→3 stops padded).
- **Demo now:** `Demos/animation.swift` is ONE gradient circle (shape cx50/cy50/r50 @100,100, fill gradient1, lineWidth 5) with the real attached `textContent` 'Circle' (via the now-implemented `updateInnerText`, textConfig position 'inside'), the one-shot `when(200,[200,0])` move, the looping `animate('style',true).when(1000,fill:gradient2)` tween, and the looping square position path. The 2 fabricated circles + radius pulse are gone.

### event_bubbling  _(Interaction)_

- **What it does / why it diverges:** Demo builds the same 4-deep Group nest (Circle in g1⊂g2⊂g3⊂g4) with click handlers on circle/g1/g3/g4 and zr.add(g4), but the demo's whole point — g3 cancelling the bubble so g4 never fires — does NOT work natively; verdict: framework-change.
- **Framework gap:** zr/element event bubble-cancel is non-functional. dispatchToElement (Handler.swift L390-405) breaks only when eventPacket.cancelBubble is true, but (a) ElementEvent is a value-type struct (Element.swift L127) so a listener's e.cancelBubble=true mutates a copy that never reaches the loop's packet, (b) Eventful.trigger (Core/Eventful.swift L270-277) discards each handler's Bool? return (`_ = hItem.h(...)`) so returning true is inert, and (c) the upstream on-prop path `eventPacket.cancelBubble = !!el[eventKey].call(...)` is a PORT-TODO (omitted). Documented FAITHFULNESS GAP in InteractionSmokeTests.test_stopPropagation_child_stops_parent. Fix: make ElementEvent a final class (reference) and/or have Eventful.trigger set eventPacket.cancelBubble from the handler's Bool return, then dispatchToElement will break correctly. Result today: g4's handler fires despite g3 returning true — the opposite of what the demo demonstrates.
- **Demo-side fix (after framework lands):** The demo's event code already follows the documented "return true to cancel bubble" contract (g3.on returns true), so no demo-side event change is needed — the cancellation simply has no effect until the framework gap above is fixed. Cosmetic alignment (optional, low priority): upstream Circle uses r:100 — native uses circle(0,0,78); set r=100. Upstream applies NO style to the circle so it renders with zrender's default black fill and no stroke; native's styled(circle0, fill:"#5470c6", stroke:"#22337a", lineWidth:2) is an added style not present upstream (drop it or accept the deviation). The extra text() caption ("click bubbles Circle → g1 → g3 (cancels) → g4") has no upstream analog (upstream handlers only console.log) — it is a gallery caption; keep but be aware it is an extra ZRText element + zr.add not issued by the html.

### hoverLayer  _(Rendering)_

- **What it does / why it diverges:** Wandering quadratic BezierCurves whose hovered element is redrawn on a separate hover layer; native draws a static highlighted curve with no events, so the demo's core (addHover) is unrepresented.
- **Framework gap:** Hover layer is not implemented in native ZRenderKit: zr.addHover / zr.removeHover (redraw of a single element on a dedicated hover canvas) has no analog, so the demo's defining behavior cannot be reproduced as a real zrender call sequence.
- **Demo-side fix (after framework lands):** Demo-side, to maximize parity within native limits: register el.on("mouseover")/el.on("mouseout") on each base BezierCurve so the event-registration calls match the HTML. Since the hover LAYER (addHover/removeHover) is unavailable, approximate the highlight by toggling the element's own style in-place inside the handlers — setStyle(stroke:"yellow", lineWidth:10, opacity:1) on mouseover, restore the original grayscale style on mouseout, then zr.refresh(). This reproduces the on/setStyle/refresh call shape and the highlight visual; true hover-layer parity (separate canvas redraw of a single el) still requires the ZRenderKit hover-layer feature noted above.

### incremental / incremental2 / incremental3  _(Rendering)_ — FIXED ✅

Originally framework-blocked on two counts; both now implemented, and all three demos use the upstream calls (fill '#121', blend 'lighter', the real per-frame accumulation):
- **`style.blend` now applied by the painter.** `CGRenderer.setBlendMode(_ blend:)` maps the canvas composite-op string onto a `CGBlendMode` ('lighter' → `.plusLighter`, plus the full table) and `drawPath` sets it inside the element's save/restore bracket. So dark '#121' dots now additively accumulate into the orange→yellow→white glow (verified) instead of the old light-green-opacity stand-in. Guarded by `testLighterBlendIsAdditive`.
- **`IncrementalDisplayable` now renders via a true RETAINED bitmap layer.** `CALayerPainter.drawIncrementalRetained` keeps a persistent device-pixel bitmap per IncrementalDisplayable: each flush draws ONLY the pending displayables (`eachPendingDisplayable`/cursor) into it and composites the whole bitmap into the frame in raw pixel space (the same way `beginFrame` composites the motion-blur `_lastFrameImage`). Old dots are never repainted → per-frame cost is O(batch), not O(total). `clearDisplaybles()` (notClear==false) wipes the bitmap. `incremental.swift` runs the html's REAL 2000 dots/frame + 5s clear and saturates to a dense green field (verified to 300k+ dots while staying fast). Guarded by `testIncrementalRetainedLayerAccumulatesAndClears` (a dot survives a later flush without being redrawn; clear wipes it) + `testIncrementalDisplayableRendersAddedDisplayables` (the one-shot snapshot path).
- **Per-frame accumulation.** incremental & incremental2 drive `zr.animation.on('frame', …)` exactly like the html (add N dots/frame, bump the count overlay; incremental2 stops at 2e4, incremental clears every 5s). incremental3 stays a one-shot bulk add (it is static in upstream).
- **Remaining minor deviation:** incremental2/incremental3 use the per-element `incremental:true` FLAG (a separate upstream layer pattern with multi-zlevel cursor splitting — not ported); their dots are plain displayables redrawn each frame, so incremental2 caps at 2e4 and incremental3 uses 4000 (both bounded, both smooth). The IncrementalDisplayable retained-layer pattern (incremental.html) is now full-fidelity.

### progressive  _(Rendering)_

- **What it does / why it diverges:** Renders many quadratic BezierCurves (stroke-only, lineWidth 2 / opacity 0.1 / grayscale random-walk) matching the html on elements+styles; only the namesake per-element `progressive` hint is dropped (a framework gap, no visual effect).
- **Framework gap:** progressive/incremental rendering not implemented: Displayable has no functional `progressive` (or `incremental`) property and there is no IncrementalDisplayable / progressive-layer renderer. It is listed only as a dropped key in the PORT-TODO at Sources/ZRenderKit/Graphic/Displayable.swift:132.
- **Demo-side fix (after framework lands):** Demo-side change is gated on the framework: once Displayable supports a `progressive` property (and a progressive painter), set it per element in progressive.swift, e.g. on each BezierCurve `progressive = (i % groupSize == 0) ? -1 : i / 100` to mirror `progressive: checkpoint ? -1 : Math.floor(i/100)`. No element/style/animation/event change is needed otherwise — those already align (the styled() fill:\"none\" is correct for stroke-only BezierCurve, lineWidth/opacity/grayscale match, and count 500 vs 10000, canvas 680x200, LCG vs Math.random, and clamping the walk in-bounds are acceptable deviations).

## ⛔ Not migratable (4)

- **asciiWidthMap** _(Text)_ — ALIGNED ✅: now mirrors the html algorithm 1:1 (measure ASCII 32–126 via `text.getWidth`, `ratio = round(width/12*100)`, pack `charCode(ratio+20)`) and renders the resulting width-map string — the analogue of the html's `document.write`. (Was: 4 measured-width boxes, a reinterpretation.)
- **css-transform** _(Transform)_ — Upstream is an interactive pointer-mapping test: green boxes are CSS divs, transforms are CSS, and the only zrender calls are per-box zr.init + zr.on drawing handlers; native fabricates a static transformed-box scene with no upstream zrender-call counterpart.
- **css-transform-inverse** _(Transform)_ — Native draws a static rect-under-2D-transform illustration, but upstream is a DOM/CSS-transform inverse pointer-coordinate test with zero zrender draw calls — no native analog.
- **cubic** _(Path tools)_ — cubic.html is a raw Canvas2D test of zrender's curve-math helpers (cubicRootAt/cubicProjectPoint/cubicAt + quadratic), drawing with ctx directly and creating zero zrender elements; the native BezierCurve+markers demo is a creative stand-in with no zrender-call parity to match.

## ✅ Already aligned (2)

- **pattern** _(Paint)_ — Two image-Pattern-filled Circles with centered white labels; native matches HTML element set + tiled-pattern fill, now using the **real asset/test.png** (`upstreamAsset`) like the html — aligned.
- **event** _(Interaction)_ — Two circles with chained Element.on handlers + draggable; native faithfully mirrors all zrender calls (incl. circle2's default-black fill) — aligned, only gallery/DOM-adaptation deviations.

## 🏗 Reclassified to framework-change during the fix pass (2 → 1 fixed)

The audit marked these "demo-fix"; applying the aligned morph calls then exposed a CRASH/inert path in the
path-morphing tools (same pattern as the earlier strokePercent → `_calculateLength` discovery). The
splitAnimation demo still shows its static source shapes until its framework bug is fixed.

### morphPath  _(Path tools)_ — FIXED ✅
- **Root cause (not a dangling pointer):** `__morphT` was not wired into `Path.animationGet/animationSet`,
  so `morphPath()` → `animateTo({__morphT: 1})` read a `nil` start value → **no animator created**
  (the `__morphT` track was inert). The morph never ran; the demo could only show a static source shape.
- **Fix:** expose `__morphT` as an animatable scalar in `Path.animationGet/animationSet`
  (Graphic/Path.swift). One-line wiring — the morph build/restore lifecycle was already correct.
- **Demo now:** runs the continuous single-element morph loop (html `morphShape`), deterministic +1
  cycle, `cfg.delay = 100` for the `setTimeout(…, 100)` pause. Regression test: `MorphPathTests`
  (animator tweens 0→1; all 7 html targets morph + rebuild geometry without crashing).

### splitAnimation  _(Animation)_ — FIXED ✅
- **Crash root cause (same as the text getBoundingRect crash):** `separateMorph`/`combineMorph` →
  `dividePath` → `morphPath.swift:931` set each split sub-path's transform via `getLocalTransform`,
  which trapped "Index out of range" on an empty scratch `MatrixArray`. The single-point
  `Transformable.getLocalTransform` fix (reallocate an empty/short scratch to the 6-slot identity)
  resolved it — the "bad pointer dereference" was this trap.
- **Demo now:** `Demos/splitAnimation.swift` runs the real html ping-pong — `morphBetween(one, many)`:
  `oneToMany` → `separateMorph(one, many)` + per-individual `animateFrom(style)`, `manyToOne`
  → `combineMorph(many, one)`, looping forever.
- **Second pass (animation didn't match html):** two more issues surfaced once the morph was driven over
  real time (frame-dumped + eyeballed):
  1. **`combineMorph` was invisible — Storage bug (framework).** A combine `toPath` is monkey-patched with a
     `childrenRef` so Storage should descend into its sub-paths and NOT draw the toPath's own (un-morphed)
     shape. Upstream Storage duck-types this (`(el as GroupLike).childrenRef` truthy). Our Storage used a
     hard `el as? GroupLike` **type** cast, which a `Path` never satisfies — so the toPath was drawn as a
     full source shape and its sub-paths never entered the display list (the combine phase just snapped to
     the source). **Fix:** `Storage._updateAndAddDisplayable` now also takes the container branch for a
     `Path` whose `__morphChildrenRef` is set (combine-morphing). Sub-paths render; the toPath does not.
  2. **Ping-pong scheduling — demo.** Re-firing the next phase off the morph's `done` ran inside
     `Animation.update()` (the freshly-created combine clip got a stale start time → snapped to its end) and
     let the three sub-demos drift out of phase. Replaced with the html's fixed `setTimeout(…, 1200)`
     schedule via `DispatchQueue.main.asyncAfter` — all three stay in lock-step, each morph gets a clean
     1000ms window + the html's ~200ms dwell.
- **Regression test:** `SplitAnimationTests` — separateMorph reaches the target; combineMorph runs without
  trapping; `test_combineMorph_subpaths_enter_displayList_not_toPath` guards the Storage childrenRef fix.

### Monkey-patch seam audit — "duck-type narrowed to a type check" (whole class) ✅
Triggered by the Storage childrenRef bug: upstream relies on dynamic method-existence (`(el as GroupLike).childrenRef` is truthy when the method is *assigned*), and a static-Swift port can silently *narrow* that to a concrete-type/protocol cast and miss cases. Swept every monkey-patch seam (all live in `morphPath.ts`: `buildPath`, `updateTransform`, `addSelfToZr`, `removeSelfFromZr`, `childrenRef`) plus every container/capability cast.
- **Two live instances, both fixed & unified.** `Storage._updateAndAddDisplayable` (`as? GroupLike`, missed the combine Path) and the painter's `flattenDisplayList` (`el.isGroup`, missed BOTH `ZRText` spans and the combine Path — feeds the retained `render`, `renderComposite`/motion-blur, and `renderToImage` routes). Both now go through one shared **`Element.activeChildrenRef()`** (Group/Text via GroupLike + a combine-morphing Path via `__morphChildrenRef`). Guarded by `test_activeChildrenRef_duckTypes_every_container_kind`.
- **Ruled out:** the four morph method-hooks (`__morphBuildPath`/`__morphIgnoreTransform`/`__morphAddSelfToZrAfter`/`__morphRemoveSelfFromZrAfter`) are all consumed *internally* by the patched method's own class with `if let hook` checks — faithful. `ZRender.clear()`'s `roots[i] is Group` matches upstream `instanceof Group` exactly. `getDecalElement()` is a real `Path` method returning optional (decal stubbed) — called, not narrowed.
- **Same shape, now resolved:** `IncrementalDisplayable` — upstream duck-types `getTemporalDisplayables` in the canvas painter for a separate retained layer. Ours now stays a single LEAF Displayable and the painter renders it through a real retained device-pixel bitmap (`CALayerPainter.drawIncrementalRetained`), so the dots accumulate at O(batch)/frame (see the incremental demos above). Both the rendering AND the retained-layer perf model are now in place.

## ✅ Fixed after review (1)

### group  _(Transform)_ — motion blur IMPLEMENTED
- `zr.configLayer` + `LayerConfig{motionBlur, lastFrameAlpha}` are now plumbed to the painter
  (ZRender.swift / PainterBase), and `CALayerPainter.beginFrame` composites the previous frame at
  `lastFrameAlpha` (instead of clearing) before drawing the new scene → fading trails, matching the html.
  Verified with a 24-frame sweep (geometric fade). The demo re-enables
  `zr.configLayer(0, LayerConfig(motionBlur: true, lastFrameAlpha: 0.99))`.
