# DemoGallery ↔ zrender test/*.html — parity gaps

_Generated from the parity audit (49 non-Shapes demos). The 6 Shapes demos
(bezier/curves/fullSector/pin/poly/sector) are already aligned. 2 aligned (pattern, event);
31 demo-fix (tracked separately); 4 not-migratable; 12 need framework work (below)._

## 🏗 Framework changes required (12)

### clipping  _(Paint)_

- **What it does / why it diverges:** HTML clips a 50x50 grid of draggable test.png Images by nested group clips (circle growing 0->300) intersected with a rect; native draws a static 90-cell color mosaic with per-cell circle clips and no animation/drag — a reinterpretation, not a port.
- **Framework gap:** NativePainter (CALayerPainter drawPath/drawTSpan/drawZRImage, lines 86/148/181) applies only each leaf element's own single el.getClipPath(); it never consumes the propagated el.__clipPaths array that Storage._updateAndAddDisplayable (Storage.swift:105-166) correctly builds from parent Group clips. So Group.setClipPath() does NOT clip a group's children, and nested clip intersection (circle ∩ rect) cannot render. Faithful port requires the painter to apply the full __clipPaths chain (clip by every path in the array) rather than just getClipPath().
- **Demo-side fix (after framework lands):** After the framework fix (painter honors __clipPaths), rewrite Demos/clipping.swift to mirror the HTML: build two nested Groups (g1.add(g2); zr.add(g1)), set g1.setClipPath(rect(x:-250,y:-20,w:500,h:300) positioned at x:200,y:150) and g2.setClipPath(circle(cx:0,cy:0,r:0) positioned at x:200,y:200), fill g2 with a grid of Image cells (or styled Rect cells if no asset) at x:i*cell, y:j*cell, each draggable=true, then animate the circle clip's shape via circle.animate("shape").when(1000,{r:300}).start() (or animateTo(shape:{r:300})). Drop the two decorative dashed outline shapes that have no HTML counterpart.

### pattern-transform  _(Paint)_

- **What it does / why it diverges:** A single Rect filled by an image Pattern carrying a transform; native matches the Rect+Pattern calls and honors scaleX/x, but pattern rotation isn't rendered and the HTML background-image call is unported — so alignment needs framework changes.
- **Framework gap:** Two NativePainter/ZRenderKit gaps block full parity: (1) CGRenderer.tilePattern (Sources/NativePainter/CGRenderer.swift:202-231) ignores pattern.rotation — it always tiles axis-aligned (documented PORT-TODO), so the Pattern's rotation:π/6 set by the demo is not painted. (2) ZRender.setBackgroundColor (Sources/ZRenderKit/ZRender.swift:228-237) only stores _backgroundColor; the painter hook is a PORT-TODO and CALayerPainter has no image-background path, so zr.setBackgroundColor({image, repeat:'no-repeat'}) cannot be reproduced.
- **Demo-side fix (after framework lands):** Demo side is already mostly correct (it sets pat.x=100, pat.scaleX=0.5, pat.rotation=π/6 and fills one Rect via gradFill(r, .pattern(pat))). For full mirroring once the framework supports it: add a zr.setBackgroundColor(...) call carrying an image with no-repeat, and optionally restore the HTML's shape (x:0,y:0,width:200,height:200) instead of rect(250,10,180,180). But the rotation and image-background will only render after the framework changes above.

### state  _(Paint)_

- **What it does / why it diverges:** Demo toggles 6 named states (ensureState/toggleState/stateTransition) on ONE Rect; native fakes it with two static rects + two labels — not aligned, requires the states machinery.
- **Framework gap:** The states machinery — el.ensureState / useState / toggleState / clearStates / useStates and el.stateTransition (additive cubicOut transitions) — is a Phase-2 stub. This demo's entire content IS state registration + toggling, so faithful alignment is impossible without it.
- **Demo-side fix (after framework lands):** Once states land: create ONE Rect (shape {x:-50,y:-50,width:100,height:100}, x:100, y:100, style {fill:'red', shadowColor:'rgba(0,0,0,0.5)'}); register the 6 states exactly — moveRight.x=200, moveDown.y=200, rotate.rotation=2, enlarge.shape={-100,-100,200,200}, changeFill.style.fill='green', shadow.style.shadowBlur=20; set el.stateTransition={duration:1000, additive:true, easing:'cubicOut'}; wire native control-panel toggles to toggleState(name,on) plus clearStates / applyAllStates(useStates(all)). Remove the second (emphasis) rect and both ZRText labels — neither exists in the html.

### rectText  _(Text)_

- **What it does / why it diverges:** Demo shows labels placed at a Rect's edges/corners/inside; native fakes it with standalone ZRText (manual align) because the host-attached textConfig.position path is a no-op, so it does NOT issue the same zrender calls.
- **Framework gap:** Element.updateInnerText is a deferred no-op (Element.swift:401-407, Phase-2 stub). The faithful body must lay out an attached _textContent from textConfig.position via contain/text.ts calculateTextPosition and resolve inside/outside fill+stroke. setTextContent/setTextConfig exist but feed this dead path, so a Rect with {textContent, textConfig:{position}} renders the label unpositioned. Implementing updateInnerText is required to issue the same calls as the html.
- **Demo-side fix (after framework lands):** Two layers. Framework: implement updateInnerText so attached labels position by textConfig.position (+ inside/outside fill resolution). Demo: once that lands, build the actual zrender call sequence — for each of the 13 positions (left, right, top, bottom, inside, insideTop, insideLeft, insideRight, insideBottom, insideTopLeft, insideTopRight, insideBottomLeft, insideBottomRight) create a Rect (shape x:100,y:50,w:150,h:70), attach a ZRText via setTextContent(...) and setTextConfig(ElementTextConfig position), grid-laid via x/y, fill = sequential colorList entry (NO stroke — html rect is fill-only). Even before the framework change, the demo could at least cover all 13 positions (it omits insideTop/insideLeft/insideRight/insideBottom) and drop the extra stroke to improve parity.

### ssr-measureText  _(Text)_

- **What it does / why it diverges:** SSR measureText test: draws a Text label and strokes its getBoundingRect() box; native substitutes an estimated box because ZRText.getBoundingRect() crashes — the core call is missing.
- **Framework gap:** ZRText.getBoundingRect() crashes with a fatalError ('Index out of range') in the text-measurement path, so the verification Rect cannot be built from the real measured text box. Fixing ZRText text measurement / getBoundingRect is required for true parity; until then the demo can only approximate.
- **Demo-side fix (after framework lands):** After ZRText.getBoundingRect() is fixed: in the loop, replace the estimated box (w = str.count*size*0.58, h = size*1.3) with a real measurement — get each ZRText element's rect via el.getBoundingRect() and build the Rect from rect.x/y/width/height offset by the text's x/y, mirroring HTML's Rect({shape: rect, x: el.x, y: el.y}). Also drop the explicit '#333333' text fill so it defaults to '#000' to match the HTML (or keep it as a deliberate readability tweak and note it). The styled() fill:'none' already matches HTML's fill:null, and lineWidth:1 + fixed stroke colors (for color.random()) are correct.

### text-overflow  _(Text)_

- **What it does / why it diverges:** Width-boxed Text overflow demo; native fakes wrapping with pre-wrapped strings because the ZRText layout engine (parseText) is a stub, so it cannot actually issue the demo's overflow/wrap behavior.
- **Framework gap:** ZRText text layout engine (upstream graphic/helper/parseText) is a PORT-TODO stub in Sources/ZRenderKit/Graphic/Text.swift (lines 15-25): parsePlainText implements only the no-wrap/no-truncate subset; overflow 'break'/'breakAll'/'truncate', lineOverflow:'truncate', and ellipsis/truncate-to-placeholder are no-ops; parseRichText returns an empty content block; isTruncated is never computed. The width-based line wrapping, overflow strategies, ellipsis, and rich-text layout that this demo is built to exercise cannot be rendered until the parseText seam is ported.
- **Demo-side fix (after framework lands):** After the parseText layout engine lands (framework): rebuild block() to mirror the HTML default state — 4 standalone ZRText using the real texts (LARGE_TEXT_EN, LARGE_TEXT_ZH, 'abcde', '红黄蓝'), width=200, height=400, x=100/350/600/850, y=0, borderColor='#000', default fill (drop fill='#2f4f2f'), remove backgroundColor and borderRadius, add rich={"highlight": backgroundColor 'yellow' fontSize 20}, and stop pre-wrapping (pass the raw long text so overflow:'break'/'breakAll'/'truncate' does the wrapping). The dat.GUI panel → native control panel substitution is an acceptable gallery deviation; the extra title Text is a gallery label, not in the HTML. Until the layout engine exists, the demo can only approximate, so a pure Demos-side fix is not sufficient.

### transform  _(Transform)_

- **What it does / why it diverges:** Upstream is an interactive "SVG Compare" demo: one Text glyph "4" via setLocalTransform(matrix) + two parseSVG renderings; native is a wholesale reinterpretation (4 Polygon arrows via x/y/rotation/scaleX/scaleY) — not aligned, full parity blocked on parseSVG.
- **Framework gap:** zrender.parseSVG / SVG parser is not implemented in the native port (no parseSVG, SVGParser or parseXML in Sources/). transform.html's two parseSVG-based renderings (transform: matrix(...) and method(...)) require it and therefore cannot be migrated without a framework change. The setLocalTransform path is supported (Transformable.setLocalTransform / updateTransform exist).
- **Demo-side fix (after framework lands):** For the migratable third: rebuild the demo around a ZRText glyph "4" (font '70px Arial', fill 'blue', align .center, verticalAlign .middle) and call text.setLocalTransform(m) + text.updateTransform(), where m is a 6-element affine matrix composed from translate/rotate/skew/scale (mirroring upstream's CSS-computed matrix), driven by the native control panel (the dat.GUI-style sliders + drag-to-reorder order items are an acceptable control-panel deviation, but they are what produce the matrix). Add skewX/skewY to the composition. The two parseSVG renderings (matrix and method) remain blocked until an SVG parser exists in the framework.

### animation  _(Animation)_

- **What it does / why it diverges:** animation.html drives ONE gradient circle (with inner label) through a looping square position path + a gradient1→gradient2 fill tween; native instead draws 3 circles (1 gradient + 2 fabricated solid), replaces the position loop with a radius pulse, and drops the gradient2 fill tween — not aligned.
- **Framework gap:** Gradient→gradient fill tweening is unsupported: Core/util.swift:382 `isGradientObject` is hardcoded `return false`, so the Animator's gradient-interpolation branch (Animator.swift:54-55, 418-422 with ParsedGradientObject/fillColorStops) is dead — `main.animate("style").when(t, fill: gradient2)` cannot interpolate. Secondary: Element.updateInnerText is a deferred no-op, so textContent + textConfig{position:'inside'} inner labels don't render (demo works around it with a standalone ZRText).
- **Demo-side fix (after framework lands):** Rewrite Demos/animation.swift to mirror animation.html 1:1: build a SINGLE gradient circle (shape cx50/cy50/r50 or shape centered + x/y=100,100, fill gradient1 red→black, lineWidth 5) and DELETE the two fabricated circles (blue/green) and the radius-pulse animateTo. Add the looping square position path via main.animate("").when(1000,["x":200,"y":0]).when(2000,["x":200,"y":200]).when(3000,["x":0,"y":200]).when(4000,["x":100,"y":100]).start() (loop=true) — root x/y keyframes are supported. Create gradient2 (black→blue@0.5→white) and main.animate("style", true).when(1000, ["fill": .linearGradient(gradient2)]).start() for the fill tween — this LAST step requires the framework gradient-tween fix first (make util.isGradientObject detect ZRColor gradients and wire ParsedGradientObject parsing). Keep the 'Circle' label (standalone ZRText acceptable until inner-text/textConfig lands).

### event_bubbling  _(Interaction)_

- **What it does / why it diverges:** Demo builds the same 4-deep Group nest (Circle in g1⊂g2⊂g3⊂g4) with click handlers on circle/g1/g3/g4 and zr.add(g4), but the demo's whole point — g3 cancelling the bubble so g4 never fires — does NOT work natively; verdict: framework-change.
- **Framework gap:** zr/element event bubble-cancel is non-functional. dispatchToElement (Handler.swift L390-405) breaks only when eventPacket.cancelBubble is true, but (a) ElementEvent is a value-type struct (Element.swift L127) so a listener's e.cancelBubble=true mutates a copy that never reaches the loop's packet, (b) Eventful.trigger (Core/Eventful.swift L270-277) discards each handler's Bool? return (`_ = hItem.h(...)`) so returning true is inert, and (c) the upstream on-prop path `eventPacket.cancelBubble = !!el[eventKey].call(...)` is a PORT-TODO (omitted). Documented FAITHFULNESS GAP in InteractionSmokeTests.test_stopPropagation_child_stops_parent. Fix: make ElementEvent a final class (reference) and/or have Eventful.trigger set eventPacket.cancelBubble from the handler's Bool return, then dispatchToElement will break correctly. Result today: g4's handler fires despite g3 returning true — the opposite of what the demo demonstrates.
- **Demo-side fix (after framework lands):** The demo's event code already follows the documented "return true to cancel bubble" contract (g3.on returns true), so no demo-side event change is needed — the cancellation simply has no effect until the framework gap above is fixed. Cosmetic alignment (optional, low priority): upstream Circle uses r:100 — native uses circle(0,0,78); set r=100. Upstream applies NO style to the circle so it renders with zrender's default black fill and no stroke; native's styled(circle0, fill:"#5470c6", stroke:"#22337a", lineWidth:2) is an added style not present upstream (drop it or accept the deviation). The extra text() caption ("click bubbles Circle → g1 → g3 (cancels) → g4") has no upstream analog (upstream handlers only console.log) — it is a gallery caption; keep but be aware it is an extra ZRText element + zr.add not issued by the html.

### hoverLayer  _(Rendering)_

- **What it does / why it diverges:** Wandering quadratic BezierCurves whose hovered element is redrawn on a separate hover layer; native draws a static highlighted curve with no events, so the demo's core (addHover) is unrepresented.
- **Framework gap:** Hover layer is not implemented in native ZRenderKit: zr.addHover / zr.removeHover (redraw of a single element on a dedicated hover canvas) has no analog, so the demo's defining behavior cannot be reproduced as a real zrender call sequence.
- **Demo-side fix (after framework lands):** Demo-side, to maximize parity within native limits: register el.on("mouseover")/el.on("mouseout") on each base BezierCurve so the event-registration calls match the HTML. Since the hover LAYER (addHover/removeHover) is unavailable, approximate the highlight by toggling the element's own style in-place inside the handlers — setStyle(stroke:"yellow", lineWidth:10, opacity:1) on mouseover, restore the original grayscale style on mouseout, then zr.refresh(). This reproduces the on/setStyle/refresh call shape and the highlight visual; true hover-layer parity (separate canvas redraw of a single el) still requires the ZRenderKit hover-layer feature noted above.

### incremental3  _(Rendering)_

- **What it does / why it diverges:** Red field + bulk-rendered glowing circles + count text; native approximates the core additive-glow effect (blend 'lighter') and bulk render because the painter ignores style.blend and there is no incremental rendering — verdict: framework-change.
- **Framework gap:** NativePainter/CGRenderer never applies style.blend: there is no CGContext.setBlendMode call and `blend` is dropped in PaintStyle.from(_:) (only fill/stroke/opacity are carried). So globalCompositeOperation 'lighter' (additive accumulation) cannot be rendered — this is exactly why the demo substitutes a light-green semi-transparent fill instead of the upstream dark '#121'. Additionally, incremental:true / IncrementalDisplayable progressive bulk rendering is not wired into the painter (the type exists in Sources/ZRenderKit/Graphic/IncrementalDisplayable.swift but no incremental layer is rendered), which is why the demo reduces 10000 circles to 500 plain Circles. True call+visual parity needs (1) painter composite-op support for style.blend and (2) incremental-render support.
- **Demo-side fix (after framework lands):** Cheap demo-side fixes that don't need the framework (do these regardless): set countText x:10 / y:10 (native uses x:12 / y:8) and add zlevel 1 to match the upstream Text({zlevel:1}); restore circle radius to 5+rand*5 (native uses 3.5..6.5). Once the painter applies style.blend (CGBlendMode .plusLighter) and supports incremental rendering, change the circles to the upstream calls: fill '#121', blend 'lighter', NO opacity override (drop opacity 0.42), incremental:true, and raise the count toward 10000 with the count text reading the real count. The deterministic LCG scatter and the textFill/textStroke→fill/stroke + textFont→fontSize:40 mapping are fine as-is.

### progressive  _(Rendering)_

- **What it does / why it diverges:** Renders many quadratic BezierCurves (stroke-only, lineWidth 2 / opacity 0.1 / grayscale random-walk) matching the html on elements+styles; only the namesake per-element `progressive` hint is dropped (a framework gap, no visual effect).
- **Framework gap:** progressive/incremental rendering not implemented: Displayable has no functional `progressive` (or `incremental`) property and there is no IncrementalDisplayable / progressive-layer renderer. It is listed only as a dropped key in the PORT-TODO at Sources/ZRenderKit/Graphic/Displayable.swift:132.
- **Demo-side fix (after framework lands):** Demo-side change is gated on the framework: once Displayable supports a `progressive` property (and a progressive painter), set it per element in progressive.swift, e.g. on each BezierCurve `progressive = (i % groupSize == 0) ? -1 : i / 100` to mirror `progressive: checkpoint ? -1 : Math.floor(i/100)`. No element/style/animation/event change is needed otherwise — those already align (the styled() fill:\"none\" is correct for stroke-only BezierCurve, lineWidth/opacity/grayscale match, and count 500 vs 10000, canvas 680x200, LCG vs Math.random, and clamping the walk in-bounds are acceptable deviations).

## ⛔ Not migratable (4)

- **asciiWidthMap** _(Text)_ — Native draws 4 measured-width boxes + text; upstream is a no-zrender utility that measureText-loops ASCII 32-126 and document.writes a width-map string — no canvas render, nothing to align.
- **css-transform** _(Transform)_ — Upstream is an interactive pointer-mapping test: green boxes are CSS divs, transforms are CSS, and the only zrender calls are per-box zr.init + zr.on drawing handlers; native fabricates a static transformed-box scene with no upstream zrender-call counterpart.
- **css-transform-inverse** _(Transform)_ — Native draws a static rect-under-2D-transform illustration, but upstream is a DOM/CSS-transform inverse pointer-coordinate test with zero zrender draw calls — no native analog.
- **cubic** _(Path tools)_ — cubic.html is a raw Canvas2D test of zrender's curve-math helpers (cubicRootAt/cubicProjectPoint/cubicAt + quadratic), drawing with ctx directly and creating zero zrender elements; the native BezierCurve+markers demo is a creative stand-in with no zrender-call parity to match.

## ✅ Already aligned (2)

- **pattern** _(Paint)_ — Two image-Pattern-filled Circles with centered white labels; native matches HTML element set + tiled-pattern fill, deviations all in the acceptable bucket — aligned.
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

### splitAnimation  _(Animation)_
- **Crash:** `separateMorph()`/`combineMorph()` → `dividePath.split` → `Rect.init`/`Path.useStyle` —
  **Bad pointer dereference** (Tool/dividePath.swift:364/440 → Tool/morphPath.swift:931).
- **Demo now:** shows the 3 static source shapes (red Rect / 5x5 rect-grid CompoundPath / 4 nested
  rects); the `makeCircles` morph target is kept for provenance.
- **To restore:** fix `defaultDividePath`/`separateMorph`, then re-enable `morphBetween`'s loop.

## ✅ Fixed after review (1)

### group  _(Transform)_ — motion blur IMPLEMENTED
- `zr.configLayer` + `LayerConfig{motionBlur, lastFrameAlpha}` are now plumbed to the painter
  (ZRender.swift / PainterBase), and `CALayerPainter.beginFrame` composites the previous frame at
  `lastFrameAlpha` (instead of clearing) before drawing the new scene → fading trails, matching the html.
  Verified with a 24-frame sweep (geometric fade). The demo re-enables
  `zr.configLayer(0, LayerConfig(motionBlur: true, lastFrameAlpha: 0.99))`.
