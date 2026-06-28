export const meta = {
  name: 'echarts-swift-port-phase3',
  description: 'Phase 3 (logic-complete): real animation system (Animator/Animation/Clip/easing + CADisplayLink) + path-morphing tools (path/transformPath/dividePath/morphPath) + color completion; build green; ported animation/color unit tests + animation smoke',
  phases: [
    { title: 'Foundations', detail: 'color completion + easing table + Clip + tool/path + tool/transformPath' },
    { title: 'Animator', detail: 'real Animator (Track/keyframe interpolation), replacing the Phase-1 stub' },
    { title: 'Scheduler', detail: 'Animation loop + tool/dividePath' },
    { title: 'Morph+Wire', detail: 'tool/morphPath + wire animateTo/stopAnimation into Element/ZRender + CADisplayLink host loop' },
    { title: 'Integrate', detail: 'swift build iteratively to green; keep 50 tests passing' },
    { title: 'Verify', detail: 'reviews + port & run animation/color unit tests + animation interpolation smoke' },
    { title: 'Synthesize', detail: 'update PORT_STATUS + Phase 4 plan (interaction)' },
  ],
}

const Z = '/private/tmp/claude-501/-Volumes-EXT-Storage-Developer-iOS-Chart/21753b38-f505-4ea4-a4d1-9954364436c9/scratchpad/zrender/src'
const PROJ = '/Volumes/EXT-Storage/Developer/iOS-Chart'

const PREAMBLE = `FAITHFUL line-by-line port of Apache ZRender (TypeScript) to Swift; preserve upstream structure for mechanical re-sync.

READ FIRST: ${PROJ}/CONVENTIONS.md (number->Double; free-fn module->caseless enum namespace; classes->final class; VectorArray=SIMD2<Double>, value-returning no out-params; header '// Ported from <upstream> — keep in sync with upstream'; mark gaps '// PORT-TODO') and ${PROJ}/PORT_STATUS.md (Phase 0-2 landed; §11 is the Phase 3 plan with exact file targets/deps; §10/§4/§P0-3 are the open-issue backlogs).

Phases 0-2 already translated zrender into ${PROJ}/Sources/ZRenderKit/ — Core/*, Element, Graphic/* (Displayable/Group/Path/Text/TSpan/Image/CompoundPath/IncrementalDisplayable + gradients/pattern), Graphic/Shape/* (all 16 shapes), Contain/* (hit-testing), Storage, ZRender host facade, Animation/{Animator(STUB),easing(STUB)}, Tool/color(partial). NativePainter/ is the hand-written CG/CA backend (CGPathRebuilder/CGRenderer/CALayerPainter, now also gradient/text/image paint). Reuse those APIs; do not re-translate.

Upstream source of truth (READ-ONLY): ${Z}/ . Build is currently GREEN with 50 tests passing — keep it that way.`

const T = { type: 'object', additionalProperties: false, required: ['file', 'status'], properties: { file: { type: 'string' }, status: { type: 'string', enum: ['complete', 'partial', 'stub'] }, notes: { type: 'string' } } }
const R = { type: 'object', additionalProperties: false, required: ['file', 'verdict'], properties: { file: { type: 'string' }, verdict: { type: 'string', enum: ['faithful', 'minor-issues', 'major-issues'] }, issues: { type: 'array', items: { type: 'string' } } } }
const BUILD = { type: 'object', additionalProperties: false, required: ['buildGreen'], properties: { buildGreen: { type: 'boolean' }, testsPass: { type: 'boolean' }, notes: { type: 'string' } } }
const TESTS = { type: 'object', additionalProperties: false, required: ['summary'], properties: { summary: { type: 'string' }, failures: { type: 'array', items: { type: 'string' } } } }

// ---------------- Foundations ----------------
phase('Foundations')
const foundations = (await parallel([
  () => agent(`${PREAMBLE}

TASK: COMPLETE ${PROJ}/Sources/ZRenderKit/Tool/color.swift — the Phase-1 partial. Translate from ${Z}/tool/color.ts the still-missing: lerp (per-channel color interpolation), fastLerp/fastMapToColor if absent, mapToColor, modifyHSL, modifyAlpha, liftColor (need util.isFunction/isString guards, GradientObject). These are REQUIRED by the Animator's keyframe color interpolation (Animator phase). Append; keep parse/stringify/lum/rgba working. 'cd ${PROJ} && swift build' must still pass.`, { label: 'color:complete', phase: 'Foundations', schema: T }),

  () => agent(`${PREAMBLE}

TASK: COMPLETE ${PROJ}/Sources/ZRenderKit/Animation/easing.swift — fill the stubbed easing table. Translate the full easing function set from ${Z}/animation/easing.ts (quadraticIn/Out/InOut, cubic, quartic, quintic, sinusoidal, exponential, circular, elastic, back, bounce, etc.) as faithful Swift functions, keyed by name (the AnimationEasing string -> function lookup). Exact numeric formulas.`, { label: 'easing:complete', phase: 'Foundations', schema: T }),

  () => agent(`${PREAMBLE}

TASK: Translate ${Z}/animation/Clip.ts -> ${PROJ}/Sources/ZRenderKit/Animation/Clip.swift (per-clip timeline: _life, _delay, _startTime, loop, gap, onframe/ondestroy, the step(time) that returns progress + applies easing). Depends on easing (being completed in parallel — reference the easing-name lookup). final class.`, { label: 'translate:Clip', phase: 'Foundations', schema: T }),

  () => agent(`${PREAMBLE}

TASK: Translate ${Z}/tool/path.ts -> ${PROJ}/Sources/ZRenderKit/Tool/path.swift (the path utilities: createFromString/parsePathString SVG-path parsing if present, mergePath, clonePath, the path<->shape helpers used by morphing). Depends on PathProxy, Path, all shapes, BoundingRect, matrix (all ported). For any SVG-string-parsing that pulls a big parser, port the core and '// PORT-TODO' exotic edge cases. READ the upstream imports.`, { label: 'translate:tool-path', phase: 'Foundations', schema: T }),

  () => agent(`${PREAMBLE}

TASK: Translate ${Z}/tool/transformPath.ts -> ${PROJ}/Sources/ZRenderKit/Tool/transformPath.swift (applies a matrix transform to a PathProxy's command buffer in place / into a new buffer). Depends on PathProxy, matrix, vector. Exact per-opcode transform math (M/L/C/Q/A/R), incl. the arc/ellipse center+radius+rotation transform.`, { label: 'translate:transformPath', phase: 'Foundations', schema: T }),
])).filter(Boolean)
log('Foundations done: ' + foundations.length)

// ---------------- Animator (real) ----------------
phase('Animator')
const animator = await agent(`${PREAMBLE}

TASK: Replace the Phase-1 STUB at ${PROJ}/Sources/ZRenderKit/Animation/Animator.swift with the REAL translation of ${Z}/animation/Animator.ts. This is the keystone of the animation system. Translate faithfully:
- Track (per-property keyframe list) + the per-type interpolation: number, 1D/2D arrays (colors as [r,g,b,a], points), and color strings (via Tool/color.lerp — just completed). The 'isValueColor'/'isArrayValueType' dispatch.
- Keyframe add/sort, the catmull-rom/linear interpolation between keyframes, percent + easing per keyframe.
- Animator: animateTo target collection, start/step(time)/stop, onframe/ondestroy/done callbacks, the 'additive' animation path, delay/duration/loop.
- cloneValue and the value-cloning helpers Element references.
Keep upstream method order/names. Reference easing (name->fn) and color.lerp. final class. Where it references the Animation scheduler (added next phase) or Element internals, use the existing hooks / '// PORT-TODO'. This unblocks morphPath and the Element animate wiring.`, { label: 'translate:Animator', phase: 'Animator', schema: T })

// ---------------- Scheduler + dividePath ----------------
phase('Scheduler')
const scheduler = (await parallel([
  () => agent(`${PREAMBLE}

TASK: Translate ${Z}/animation/Animation.ts -> ${PROJ}/Sources/ZRenderKit/Animation/Animation.swift (the animation loop/scheduler: the Animator list, addAnimator/removeAnimator/addClip/removeClip, the _update(time) that steps all clips each frame, start/stop, the onframe/stage hooks, Eventful-based events). Depends on Animator (just translated), Clip, Eventful, util. The actual frame TICK (requestAnimationFrame) is supplied by the host — model 'update(time)' as the entry the CADisplayLink host loop will call (NativePainter, Morph+Wire phase).`, { label: 'translate:Animation', phase: 'Scheduler', schema: T }),

  () => agent(`${PREAMBLE}

TASK: Translate ${Z}/tool/dividePath.ts -> ${PROJ}/Sources/ZRenderKit/Tool/dividePath.swift (splits/subdivides a path into N parts for morph alignment — used by morphPath to make two paths have matching segment counts). Depends on Tool/path (just translated), PathProxy. Faithful subdivision math.`, { label: 'translate:dividePath', phase: 'Scheduler', schema: T }),
])).filter(Boolean)

// ---------------- Morph + Wire + host loop ----------------
phase('Morph+Wire')
const morphWire = (await parallel([
  () => agent(`${PREAMBLE}

TASK: Translate ${Z}/tool/morphPath.ts -> ${PROJ}/Sources/ZRenderKit/Tool/morphPath.swift (path morphing: alignBezierCurves, centroid, the morphing 'combine'/'separate' helpers, morphPath(fromPath, toPath, animationOpts) that builds an interpolating path). Depends on Tool/dividePath (just translated), Animator (for the animation hookup), curve, vector, Path. Faithful geometry — this is the bar->pie style morph. Where it builds an Animator, use the real Animator API.`, { label: 'translate:morphPath', phase: 'Morph+Wire', schema: T }),

  () => agent(`${PREAMBLE}

TASK: Wire the now-real animation system into the scene graph by replacing the Phase-1/2 stubs (faithful, minimal edits):
- ${PROJ}/Sources/ZRenderKit/Element.swift: make animateTo/animateFrom/stopAnimation/animate/addAnimator/removeAnimator/updateDuringAnimation REAL (they were '// PORT-TODO' no-ops referencing the Animator stub). Translate the upstream bodies from ${Z}/Element.ts (the animation section), using the real Animator + the element's animators list. Keep the states/event stubs as-is (Phase 4).
- ${PROJ}/Sources/ZRenderKit/ZRender.swift: wire the animation clock — ZRender owns an Animation (just translated); add/refresh should register animators and the flush/refresh hook should be driven by Animation.update. Replace the Phase-2 '// PORT-TODO' animation-clock stub.
READ both upstream files for the exact bodies. Document anything still deferred.`, { label: 'wire:Element+ZRender-animation', phase: 'Morph+Wire', schema: T }),

  () => agent(`${PREAMBLE}

TASK: Add the rAF→CADisplayLink host loop to the hand-written NativePainter (NOT a translation; this is the platform glue zrender expects the host to provide). In ${PROJ}/Sources/NativePainter/ add a small driver (e.g. AnimationLoop.swift) that uses CADisplayLink (iOS) / CVDisplayLink or a timer fallback (macOS) to call the ZRender/Animation update(time) each frame, then triggers a CALayerPainter refresh. Provide start()/stop(); guard iOS+macOS; getTime via CACurrentMediaTime. Keep it minimal — it just pumps Animation.update on a frame clock. READ ZRender.swift/Animation.swift for the exact entry point to call.`, { label: 'painter:CADisplayLink-loop', phase: 'Morph+Wire', schema: T }),
])).filter(Boolean)

// ---------------- Integrate ----------------
phase('Integrate')
const integrate = await agent(`${PREAMBLE}

TASK: Make the package COMPILE GREEN and keep the existing 50 tests passing. The real Animator replaced a stub and animation got wired into Element/ZRender — expect integration breakage at those seams.
Loop: 'cd ${PROJ} && swift build' (timeout ~400s), read errors, fix with MINIMAL FAITHFUL edits. Up to ~12 iterations. Rules: fix real mismatches over deleting logic; '// PORT-TODO' faithful-signature stubs OK for genuinely-deferred deps (Handler/event are Phase 4) but never weaken interpolation/morph/easing MATH to dodge an error — fix the call site. Then 'swift test' — the existing 50 tests (golden geometry + ported unit tests) MUST still pass; fix any regression you introduced (especially if the Element animate wiring changed shape/style state). Report buildGreen, testsPass, notes.`, { label: 'build-fix-loop', phase: 'Integrate', schema: BUILD })

// ---------------- Verify ----------------
phase('Verify')
const REVIEW = [
  { name: 'Animator', dst: 'Sources/ZRenderKit/Animation/Animator.swift', src: 'animation/Animator.ts' },
  { name: 'Animation', dst: 'Sources/ZRenderKit/Animation/Animation.swift', src: 'animation/Animation.ts' },
  { name: 'Clip', dst: 'Sources/ZRenderKit/Animation/Clip.swift', src: 'animation/Clip.ts' },
  { name: 'easing', dst: 'Sources/ZRenderKit/Animation/easing.swift', src: 'animation/easing.ts' },
  { name: 'morphPath', dst: 'Sources/ZRenderKit/Tool/morphPath.swift', src: 'tool/morphPath.ts' },
  { name: 'tool-path', dst: 'Sources/ZRenderKit/Tool/path.swift', src: 'tool/path.ts' },
  { name: 'dividePath', dst: 'Sources/ZRenderKit/Tool/dividePath.swift', src: 'tool/dividePath.ts' },
  { name: 'transformPath', dst: 'Sources/ZRenderKit/Tool/transformPath.swift', src: 'tool/transformPath.ts' },
]
const verify = (await parallel([
  ...REVIEW.map(t => () => agent(`${PREAMBLE}

TASK: Adversarially review ONE Swift translation vs its TS source for SEMANTIC faithfulness. Assume a bug until proven otherwise.
TS SOURCE (authority): ${Z}/${t.src}
SWIFT: ${PROJ}/${t.dst}
Hunt: keyframe interpolation math (linear/catmull-rom, per-channel color lerp, array interpolation), easing formula exactness, Clip timeline (life/delay/loop/gap, progress + easing application), Animation scheduler (clip add/remove, time stepping), morph alignment (segment-count matching, bezier alignment, centroid), value-vs-reference (Animator/Track MUST be final class; mutated value state), integer-vs-Double, NaN/||0. Only real divergences — cite TS behavior + Swift line + consequence.`, { label: 'review:' + t.name, phase: 'Verify', schema: R })),

  () => agent(`${PREAMBLE}

TASK: Per the standing rule, port the matching upstream zrender unit tests now that animation + color are complete, and run them as a behavioral oracle. Sources (READ-ONLY): ${PROJ}/upstream/zrender/test/ut/spec/ :
- animation/ElementAnimation.test.ts -> ${PROJ}/Tests/ZRenderKitTests/unit/ElementAnimationUnitTests.swift
- tool/color.test.ts -> ${PROJ}/Tests/ZRenderKitTests/unit/ColorUnitTests.swift  (color is now complete — un-skip what Phase-1 couldn't express)
jest->XCTest: toBe/toEqual->XCTAssertEqual; toBeCloseTo(v,n)->XCTAssertEqual(..,accuracy:pow(10,-Double(n))); describe/it->XCTestCase/test_ methods. Match the ACTUAL ported Swift API (read the Sources). The ElementAnimation spec drives animateTo + steps the clock — to step time deterministically, call the Animation/Animator update(time) entry directly with synthetic timestamps (do NOT rely on a real CADisplayLink). For any assertion referencing a still-stubbed API (states), 'throw XCTSkip("<why>")'. For genuine FAILURES: test-porting-error -> fix test; real faithfulness bug -> leave failing / XCTExpectFailure with a precise comment + REPORT it (do NOT edit Sources to paper over). Run 'swift test', report total/pass/fail/skip + every skip + every real bug.`, { label: 'unit-tests:animation+color', phase: 'Verify', schema: TESTS }),

  () => agent(`${PREAMBLE}

TASK: Add an animation INTERPOLATION smoke test (the animation analog of geometry parity, since there's no display-list oracle for in-flight frames). Create ${PROJ}/Tests/ZRenderKitTests/AnimationSmokeTests.swift:
- Build a Path (e.g. Rect or Circle), call animateTo a target shape/style over a known duration with a known easing (e.g. 'linear' and 'cubicOut'), then step the Animation/Animator update(time) at synthetic timestamps (0, 25%, 50%, 100%).
- Assert the interpolated values are monotonic toward the target and that at t=duration the value EXACTLY equals the target; at t=50% with linear easing it equals the midpoint (within 1e-9); with an easing, equals easing(0.5) applied. Use the real easing functions.
- A color tween case: animate style.fill from one rgba to another, assert the channel-wise lerp at 50%.
Run 'swift test'. Report which assertions pass and any divergence (this validates Animator+easing+color.lerp end-to-end).`, { label: 'animation-smoke', phase: 'Verify', schema: TESTS }),
])).filter(Boolean)
const reviews = verify.slice(0, REVIEW.length)
const unitNew = verify[REVIEW.length]
const animSmoke = verify[REVIEW.length + 1]

// ---------------- Synthesize (no schema) ----------------
phase('Synthesize')
const synthInput = JSON.stringify({
  integrate, reviews: reviews.map(r => r && { file: r.file, verdict: r.verdict, issues: (r.issues || []).slice(0, 4) }),
  unitNew: unitNew && unitNew.summary, animSmoke: animSmoke && animSmoke.summary,
  foundations: foundations.map(f => f && f.file), animator: animator && animator.file, scheduler: scheduler.map(s => s && s.file), morphWire: morphWire.map(m => m && m.file),
})
const synth = await agent(`${PREAMBLE}

TASK: Update ${PROJ}/PORT_STATUS.md to record Phase 3. Do NOT return structured output — WRITE the file, return a short plain-text summary.
Structured results:
${synthInput}

Read the produced Swift under ${PROJ}/Sources/ZRenderKit/{Animation,Tool} and the Element/ZRender animation wiring + ${PROJ}/Sources/NativePainter (CADisplayLink loop) to ground the summary.

Append a 'Phase 3' section (preserve all prior history — append, do not delete) with:
1. What landed (real Animator/Animation/Clip/easing, tool path/transformPath/dividePath/morphPath, color completion, Element/ZRender animation wiring, CADisplayLink host loop) — checklist + per-file status/verdict table.
2. Build + test status: build green; test count pass/skip/fail incl. the ported animation/color unit tests + the new animation interpolation smoke.
3. Deduped, severity-sorted NEW open issues + PORT-TODOs. Note what is now NO LONGER stubbed (animation) vs what REMAINS deferred to Phase 4 (states/emphasis/blur/select, Handler/event/GestureMgr interaction, native image loading if still stubbed).
4. State that **zrender is now LOGIC-COMPLETE** (rendering + animation + path tools); the only remaining zrender work is Phase 4 = interaction (Handler.ts, core/event, GestureMgr -> UIKit gestures, dom bridging). After Phase 4, the port moves to the ECharts layer (coord/scale/data/chart).
5. The Phase 4 plan: list upstream files (Handler.ts, core/event.ts, core/GestureMgr.ts, dom/) + how they bridge to native UIKit/AppKit gesture+event handling (this is mostly hand-written bridging, not direct translation).
6. Keep the standing upstream-sync rule.`, { label: 'synthesize-status', phase: 'Synthesize' })

return {
  buildGreen: integrate && integrate.buildGreen,
  testsPass: integrate && integrate.testsPass,
  reviews: reviews.map(r => r && { file: r.file, verdict: r.verdict }),
  unitNew: unitNew && unitNew.summary,
  animSmoke: animSmoke && animSmoke.summary,
  synth: synth && String(synth).slice(0, 400),
}
