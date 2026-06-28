export const meta = {
  name: 'echarts-swift-port-phase2',
  description: 'Phase 2 (rendering-complete): Text/TSpan/Image + contain hit-testing + 10 remaining shapes + gradient/pattern/text paint + Storage display list + ZRender host facade; build green; geometry parity + ported unit tests',
  phases: [
    { title: 'Foundations', detail: 'contain math + contain/text + TSpan + Image + color completions + 10 remaining shapes' },
    { title: 'Composites', detail: 'Text (ZRText) + contain/path + CompoundPath/IncrementalDisplayable' },
    { title: 'Host', detail: 'Storage display list + NativePainter gradient/pattern/text/image paint' },
    { title: 'Facade', detail: 'ZRender host facade + wire contain into Path/Displayable + real ZRenderType' },
    { title: 'Integrate', detail: 'swift build, iteratively fix to green' },
    { title: 'Verify', detail: 'review + extend golden geometry to new shapes + port & run zrender unit tests' },
    { title: 'Synthesize', detail: 'update PORT_STATUS + Phase 3 plan' },
  ],
}

const Z = '/private/tmp/claude-501/-Volumes-EXT-Storage-Developer-iOS-Chart/21753b38-f505-4ea4-a4d1-9954364436c9/scratchpad/zrender/src'
const ZL = '/Volumes/EXT-Storage/Developer/iOS-Chart/upstream/zrender/src'
const PROJ = '/Volumes/EXT-Storage/Developer/iOS-Chart'

const PREAMBLE = `FAITHFUL line-by-line port of Apache ZRender (TypeScript) to Swift; preserve upstream structure so future upstream diffs re-sync mechanically.

READ FIRST (binding rules + current state):
- ${PROJ}/CONVENTIONS.md  (number->Double; free-fn module->caseless enum namespace; classes->final class; VectorArray=SIMD2<Double>, value-returning no out-params; header '// Ported from <upstream> — keep in sync with upstream'; mark gaps '// PORT-TODO')
- ${PROJ}/PORT_STATUS.md   (Phase 0+1 landed; section 5 is the Phase 2 plan with exact file targets/deps; section 4 lists open issues)

Phases 0+1 already translated into ${PROJ}/Sources/ZRenderKit/: Core/* (matrix, vector=SIMD2, Point, curve, bbox, BoundingRect, Transformable, PathProxy, platform, util[partial], LRU, types, env, Eventful), Element.swift, Graphic/{Displayable,Group,Path,Gradient,LinearGradient,RadialGradient,Pattern,constants}, Graphic/Shape/{Rect,Circle,Sector,Arc,BezierCurve,Polygon}, Graphic/Helper/{roundRect,roundSector,poly,smoothBezier,subPixelOptimize}, Animation/{Animator(stub),easing}, Tool/color(partial). Reuse those APIs; do not re-translate. NativePainter/ is the hand-written CG/CA backend (CGPathRebuilder, CGRenderer, CALayerPainter) — NOT a translation.

Upstream source of truth (READ-ONLY): ${Z}/ (also mirrored at ${ZL}/). Never modify upstream or scratchpad.`

// minimal schemas (reduce StructuredOutput retry failures seen in Phase 1)
const T = { type: 'object', additionalProperties: false, required: ['file', 'status'], properties: { file: { type: 'string' }, status: { type: 'string', enum: ['complete', 'partial', 'stub'] }, notes: { type: 'string', description: 'public API surface, deviations, and PORT-TODOs in one short blurb' } } }
const R = { type: 'object', additionalProperties: false, required: ['file', 'verdict'], properties: { file: { type: 'string' }, verdict: { type: 'string', enum: ['faithful', 'minor-issues', 'major-issues'] }, issues: { type: 'array', items: { type: 'string' } } } }
const BUILD = { type: 'object', additionalProperties: false, required: ['buildGreen'], properties: { buildGreen: { type: 'boolean' }, testsPass: { type: 'boolean' }, notes: { type: 'string' } } }
const TESTS = { type: 'object', additionalProperties: false, required: ['summary'], properties: { summary: { type: 'string' }, failures: { type: 'array', items: { type: 'string' } } } }

// ---------------- Foundations ----------------
phase('Foundations')

const REMAINING_SHAPES = ['Ellipse', 'Ring', 'Line', 'Polyline', 'Heart', 'Droplet', 'Isogon', 'Rose', 'Star', 'Trochoid']

const foundationTasks = [
  () => agent(`${PREAMBLE}

TASK: Translate the contain/ hit-testing MATH (small, interrelated, pure numeric — depend on Phase-0 curve/vector):
- ${Z}/contain/line.ts -> ${PROJ}/Sources/ZRenderKit/Contain/line.swift
- ${Z}/contain/quadratic.ts -> .../quadratic.swift
- ${Z}/contain/cubic.ts -> .../cubic.swift
- ${Z}/contain/arc.ts -> .../arc.swift
- ${Z}/contain/windingLine.ts -> .../windingLine.swift
- ${Z}/contain/polygon.ts -> .../polygon.swift
- ${Z}/contain/util.ts -> .../util.swift  (the contain-specific util: normalizeRadian, etc.)
Each is a caseless enum namespace named after the file. Exact numeric fidelity (winding numbers, on-curve epsilon). These feed contain/path (Composites phase).`, { label: 'translate:contain-math', phase: 'Foundations', schema: T }),

  () => agent(`${PREAMBLE}

TASK: Translate ${Z}/contain/text.ts -> ${PROJ}/Sources/ZRenderKit/Contain/text.swift (327 lines). This is the TEXT LAYOUT/GEOMETRY core: parsePlainText, parseRichText, calculateTextPosition, parsePercent, getLineHeight/measureWidth helpers, truncate. Depends on Phase-0 platform.measureText (already ASCII-width-fallback capable), BoundingRect, util, LRU. READ the upstream imports to see what it pulls from contain/ or tool/. This UNBLOCKS Text.swift and the Element inner-text stub. Keep the rich-text segment model intact (it pre-bakes layout into positioned runs before any rendering).`, { label: 'translate:contain-text', phase: 'Foundations', schema: T }),

  () => agent(`${PREAMBLE}

TASK: Translate ${Z}/graphic/TSpan.ts -> ${PROJ}/Sources/ZRenderKit/Graphic/TSpan.swift (97 lines). A Displayable subclass = a single positioned text run (the actual text primitive the painter draws). TSpanStyleProps (text, font, textAlign, textBaseline, x/y, fill/stroke). final class extends Displayable.`, { label: 'translate:TSpan', phase: 'Foundations', schema: T }),

  () => agent(`${PREAMBLE}

TASK: Translate ${Z}/graphic/Image.ts -> ${PROJ}/Sources/ZRenderKit/Graphic/Image.swift (125 lines). A Displayable subclass for raster images. ImageStyleProps (image source, x/y/width/height, sx/sy/sWidth/sHeight). The 'image' source is browser HTMLImageElement upstream -> model as a Swift seam: an 'ImageLike' protocol / an associated native image handle (CGImage on the painter side); keep the source typed as an opaque/Any or a small protocol with a '// PORT-TODO: native image loading via platform.loadImage' note. getBoundingRect from x/y/width/height.`, { label: 'translate:Image', phase: 'Foundations', schema: T }),

  () => agent(`${PREAMBLE}

TASK: EXTEND ${PROJ}/Sources/ZRenderKit/Tool/color.swift with the helpers deferred in Phase 1 (PORT_STATUS §4 item 4), needed for gradient/pattern paint: lerp (color interpolation), mapToColor, modifyHSL, modifyAlpha (if missing), liftColor, and the number->string fidelity they need. Translate faithfully from ${Z}/tool/color.ts. Append; keep existing parse/stringify/lum working. After editing, 'cd ${PROJ} && swift build' must still pass.`, { label: 'color:completions', phase: 'Foundations', schema: T }),

  ...REMAINING_SHAPES.map(s => () => agent(`${PREAMBLE}

TASK: Translate ${Z}/graphic/shape/${s}.ts -> ${PROJ}/Sources/ZRenderKit/Graphic/Shape/${s}.swift . A Path subclass: '${s}Shape' struct + buildPath emitting PathProxy commands. Match the Path<Shape> pattern already established in ${PROJ}/Sources/ZRenderKit/Graphic/Path.swift and the existing shapes (READ Graphic/Shape/Rect.swift and Circle.swift for the pattern). Translate buildPath MATH EXACTLY. ${s === 'Polyline' ? 'NOTE: Polyline unblocks the Element.swift Polyline placeholder — its public type must match what Element references.' : ''} If it needs a Graphic/Helper not yet ported, translate that helper too (under Graphic/Helper/) with a header comment.`, { label: 'translate:shape:' + s, phase: 'Foundations', schema: T })),
]
const foundations = (await parallel(foundationTasks)).filter(Boolean)
log('Foundations done: ' + foundations.length)

// ---------------- Composites ----------------
phase('Composites')
const composites = (await parallel([
  () => agent(`${PREAMBLE}

TASK: Translate ${Z}/graphic/Text.ts -> ${PROJ}/Sources/ZRenderKit/Graphic/Text.swift (1113 lines, ZRText — the big one). ZRText is a COMPOSITE Displayable: it lays itself out (via contain/text.swift, now ported) into child TSpan/Rect/Image nodes. Translate: TextStyleProps (rich text, overflow, padding, lineHeight, backgroundColor/border, etc.), _updatePlainTexts/_updateRichTexts, the child-TSpan creation + positioning, DefaultTextStyle. Depends on Displayable, TSpan (Foundations), Contain/text (Foundations), platform. This is what makes labels render. Where it references states/animation (Element stubs), keep '// PORT-TODO'. Faithful method order.`, { label: 'translate:Text', phase: 'Composites', schema: T }),

  () => agent(`${PREAMBLE}

TASK: Translate ${Z}/contain/path.ts -> ${PROJ}/Sources/ZRenderKit/Contain/path.swift . The path containment test (point-in-path / point-on-stroke) that replays a PathProxy buffer and accumulates winding numbers via the Foundations contain-math (line/quadratic/cubic/arc/windingLine). Depends on Phase-0 PathProxy + curve + the contain-math just ported. Exact winding/epsilon fidelity.`, { label: 'translate:contain-path', phase: 'Composites', schema: T }),

  () => agent(`${PREAMBLE}

TASK: Translate two small composite displayables:
- ${Z}/graphic/CompoundPath.ts -> ${PROJ}/Sources/ZRenderKit/Graphic/CompoundPath.swift (58 lines; concatenates sub-paths into one buildPath).
- ${Z}/graphic/IncrementalDisplayable.ts -> ${PROJ}/Sources/ZRenderKit/Graphic/IncrementalDisplayable.swift (154 lines; the large-data batched displayable). Both extend Path/Displayable (Phase 1).`, { label: 'translate:compound+incremental', phase: 'Composites', schema: T }),
])).filter(Boolean)

// ---------------- Host (Storage + painter paint additions) ----------------
phase('Host')
const host = (await parallel([
  () => agent(`${PREAMBLE}

TASK: Translate ${Z}/Storage.ts -> ${PROJ}/Sources/ZRenderKit/Storage.swift (245 lines). Builds the FLATTENED, z-sorted display list the painter consumes: walks the Element/Group tree, flattens Groups, updates each Displayable's transform + __clipPaths chain + injects attached textContent, then sorts by (zlevel, z, z2, insertion). Depends on Element, Group, Displayable, util (and a stable sort — Phase 0 may have timsort; if not, use a stable Swift sort with a documented note). This replaces the ad-hoc Group walk currently in CALayerPainter.`, { label: 'translate:Storage', phase: 'Host', schema: T }),

  () => agent(`${PREAMBLE}

TASK: EXTEND the hand-written NativePainter (NOT a translation; targets the seam in ${PROJ}/Sources/NativePainter/Renderer.swift) so it paints the features added this phase. Edit ${PROJ}/Sources/NativePainter/CGRenderer.swift and CALayerPainter.swift:
- GRADIENT fill/stroke: resolve LinearGradientObject/RadialGradientObject (Graphic/*.swift data types) -> CGGradient with colorStops (use Tool/color for stop parsing); objectBoundingBox vs userSpaceOnUse coords; draw via CGContext.drawLinearGradient/drawRadialGradient clipped to the path.
- PATTERN fill: PatternObject -> tiled CGImage paint (best-effort; '// PORT-TODO' the exotic cases).
- TEXT: drawText for a TSpan/positioned run via Core Text (CTLine) — font from the resolved TextStyle, fill+stroke, text-anchor (start/middle/end), baseline. (Layout already pre-baked by Contain/text + ZRText into positioned TSpans.)
- IMAGE: drawImage for ZRImage -> draw a native CGImage into the dest rect.
- fill rule (even-odd vs nonzero), line-cap/join keyword presets if not already.
Keep iOS+macOS guarded. READ the existing CGRenderer/CALayerPainter and the new Text/TSpan/Image/Gradient types first.`, { label: 'painter:paint-additions', phase: 'Host', schema: T }),
])).filter(Boolean)

// ---------------- Facade ----------------
phase('Facade')
const facade = await agent(`${PREAMBLE}

TASK: Translate ${Z}/zrender.ts -> ${PROJ}/Sources/ZRenderKit/ZRender.swift (585 lines) AND wire up two integration points:
1. The ZRender host facade: class ZRender with init(host/painter), add/remove(Element), refresh (build Storage display list -> Painter), resize, dispose, the animation clock hooks (addAnimator/removeAnimator — bodies stay Phase-3 '// PORT-TODO' stubs, but the type surface must be real). Use Storage.swift (Host phase) + NativePainter.Painter (CALayerPainter) + Element.
2. Replace the 'ZRenderType' forward-declaration placeholder in ${PROJ}/Sources/ZRenderKit/Element.swift (and the Path/Group/Polyline placeholders if now resolvable) with the real types — Element.__zr should be the real ZRender. Keep edits minimal and faithful.
3. Wire the contain/ hit-testing into the scene graph: Path.contain/containStroke (stubs today) -> Contain/path.swift; Displayable.contain -> its bounding/path test. Small faithful edits to the existing Path.swift/Displayable.swift.
Document anything still stubbed. If a clean integration needs a small helper, add it with PORT-TODO.`, { label: 'translate:ZRender+wire', phase: 'Facade', schema: T })

// ---------------- Integrate (build-fix loop) ----------------
phase('Integrate')
const integrate = await agent(`${PREAMBLE}

TASK: Make the whole package COMPILE GREEN and keep existing tests passing. Many interdependent files were generated in parallel — expect integration errors (missing members, signature mismatches, the ZRenderType/Path/Group placeholder replacement, new Sources/ZRenderKit/Contain/ dir).
Loop: run 'cd ${PROJ} && swift build' (timeout ~400s), read errors, fix with MINIMAL FAITHFUL edits across the generated files. Repeat up to ~12 iterations until green. Rules:
- Fix real mismatches (wrong member name/arg) over deleting logic.
- For genuinely-deferred deps (animation, native image loading, states), a '// PORT-TODO' stub with a faithful signature is OK to unblock — never weaken shape/text/contain MATH to dodge an error; fix the call site.
- Then run 'swift test' — the 44 existing tests (5 golden + 39 unit) must still pass; fix any regressions you introduced.
Report buildGreen, testsPass, and a short notes of fixes + anything unresolved.`, { label: 'build-fix-loop', phase: 'Integrate', schema: BUILD })

// ---------------- Verify (review + golden + unit tests) ----------------
phase('Verify')
const REVIEW = [
  { name: 'Text', dst: 'Sources/ZRenderKit/Graphic/Text.swift', src: 'graphic/Text.ts' },
  { name: 'contain-text', dst: 'Sources/ZRenderKit/Contain/text.swift', src: 'contain/text.ts' },
  { name: 'contain-path', dst: 'Sources/ZRenderKit/Contain/path.swift', src: 'contain/path.ts' },
  { name: 'Storage', dst: 'Sources/ZRenderKit/Storage.swift', src: 'Storage.ts' },
  { name: 'ZRender', dst: 'Sources/ZRenderKit/ZRender.swift', src: 'zrender.ts' },
  ...REMAINING_SHAPES.map(s => ({ name: 'shape:' + s, dst: 'Sources/ZRenderKit/Graphic/Shape/' + s + '.swift', src: 'graphic/shape/' + s + '.ts' })),
]
const verifyTasks = [
  ...REVIEW.map(t => () => agent(`${PREAMBLE}

TASK: Adversarially review ONE Swift translation vs its TS source for SEMANTIC faithfulness. Assume a bug until proven otherwise.
TS SOURCE (authority): ${Z}/${t.src}
SWIFT: ${PROJ}/${t.dst}
Hunt: value-vs-reference semantics (scene nodes MUST be final class); buildPath/curve/winding math divergence (angles, anticlockwise, epsilon); text layout (line breaking, baseline, truncation); Storage sort key order (zlevel,z,z2,insertion) + clip-path chain; integer-vs-Double; off-by-one; NaN/||0 per Phase-0 policy. Only real divergences — cite TS behavior + Swift line + consequence.`, { label: 'review:' + t.name, phase: 'Verify', schema: R })),

  () => agent(`${PREAMBLE}

TASK: Extend the golden GEOMETRY-PARITY tests to the shapes added this phase that ECharts can express. In ${PROJ}/Tests/ZRenderKitTests/GoldenTests.swift the pattern 'assertGeometryParity(name, PathInstance, shape)' compares a Swift Shape.buildPath's rebuilt 'd' to the real-ECharts fixture byte-for-byte.
1. For shapes ECharts' \`graphic\` component supports (ellipse, ring, line, polyline — verify which are expressible), add option specs under ${PROJ}/Oracle/options/<name>.json and regenerate fixtures: 'cd ${PROJ}/Oracle && ECHARTS_DIST=${PROJ}/upstream/echarts/dist/echarts.js node dump-displaylist.js'. Then add assertGeometryParity assertions for each (instantiate EllipseShape/RingShape/etc. with the fixture params).
2. For zrender-ONLY decorative shapes with no ECharts oracle (Heart, Droplet, Isogon, Rose, Star, Trochoid): do NOT fabricate an oracle. Add a compile/exercise smoke test that builds each shape's PathProxy and asserts it produced a non-empty, NaN-free command buffer; note '// no ECharts oracle — covered by ported zrender unit tests / visual'.
Run 'swift test' and report which new shapes PASS geometry parity, which are smoke-only, and any FAIL with the d-diff.`, { label: 'golden:new-shapes', phase: 'Verify', schema: TESTS }),

  () => agent(`${PREAMBLE}

TASK: Per the standing rule, port the matching upstream zrender Jest unit tests to XCTest for modules now ported, and run them as a behavioral oracle. Sources (READ-ONLY): ${PROJ}/upstream/zrender/test/ut/spec/ . Port these (their modules now exist):
- contain/Sector.test.ts -> Tests/ZRenderKitTests/unit/ContainSectorUnitTests.swift  (Sector containment — needs Contain/path or Sector.contain wiring)
- graphic/Image.test.ts -> .../ImageUnitTests.swift
- graphic/Text.test.ts -> .../TextUnitTests.swift
jest->XCTest: toBe/toEqual->XCTAssertEqual; toBeCloseTo(v,n)->XCTAssertEqual(..,accuracy:pow(10,-Double(n))); describe/it->XCTestCase/test_ methods. Match the ACTUAL Swift API (read the ported Swift). For any assertion referencing a not-yet-ported/stubbed API, wrap that test body in 'throw XCTSkip("<which API>")' — never invent or silently drop. For genuine FAILURES, determine test-porting-error (fix test) vs real faithfulness bug (leave failing / XCTExpectFailure with a precise comment, and REPORT it — do NOT edit Sources to paper over). Run 'swift test', report total/pass/fail/skip + every skip reason + every real bug found.`, { label: 'unit-tests:contain+text+image', phase: 'Verify', schema: TESTS }),
]
const verify = (await parallel(verifyTasks)).filter(Boolean)
const reviews = verify.slice(0, REVIEW.length)
const goldenNew = verify[REVIEW.length]
const unitNew = verify[REVIEW.length + 1]

// ---------------- Synthesize (NO schema — write file directly, avoids structured-output crash) ----------------
phase('Synthesize')
const synthSummary = JSON.stringify({
  integrate, reviews: reviews.map(r => r && { file: r.file, verdict: r.verdict, issues: (r.issues || []).slice(0, 4) }),
  goldenNew: goldenNew && goldenNew.summary, unitNew: unitNew && unitNew.summary,
  foundations: foundations.map(f => f && f.file), composites: composites.map(c => c && c.file), host: host.map(h => h && h.file), facade: facade && facade.file,
})
const synth = await agent(`${PREAMBLE}

TASK: Update ${PROJ}/PORT_STATUS.md to reflect Phase 2. Do NOT return structured output — WRITE the file and return a short plain-text summary.
Structured results from this run:
${synthSummary}

Read the actually-produced Swift under ${PROJ}/Sources/ZRenderKit/{Graphic,Contain,Storage.swift,ZRender.swift} and ${PROJ}/Sources/NativePainter to ground the summary in reality.

Add a 'Phase 2' section (preserve Phase 0/1 history — append, do not delete) with:
1. What landed (Text/TSpan/Image, contain/* hit-testing, 10 remaining shapes, gradient/pattern/text/image paint, Storage display list, ZRender host facade) as a checklist + per-file status/verdict table.
2. Build + test status: is 'swift build' green; how many tests pass/skip/fail (golden geometry incl. new shapes + ported unit tests for contain/Sector/Image/Text).
3. Deduped, severity-sorted NEW open issues + PORT-TODOs (especially still-stubbed: animation [Phase 3], native image loading, states/emphasis, event/Handler plumbing).
4. The Phase 3 plan: animation/* full (real Animator/Animation/Clip, rAF->CADisplayLink) + tool/{path,morphPath,dividePath,transformPath} (path morphing) + tool/color completion — list upstream files + already-ported deps. After Phase 3 zrender is 'logic-complete'; Phase 4 (Handler/event/GestureMgr -> UIKit) is the final interaction layer.
5. Keep the standing upstream-sync rule.`, { label: 'synthesize-status', phase: 'Synthesize' })

return {
  buildGreen: integrate && integrate.buildGreen,
  testsPass: integrate && integrate.testsPass,
  goldenNew: goldenNew && goldenNew.summary,
  unitNew: unitNew && unitNew.summary,
  reviews: reviews.map(r => r && { file: r.file, verdict: r.verdict }),
  synth: synth && String(synth).slice(0, 400),
}
