export const meta = {
  name: 'echarts-swift-port-phase1',
  description: 'Phase 1: translate zrender scene graph (Element/Displayable/Group/Path) + 6 fixture shapes + first CALayerPainter; build green; geometry parity vs real-ECharts oracle',
  phases: [
    { title: 'Foundations', detail: 'Correctness sweep of Phase-0 core + leaf deps (Eventful, Animator-stub, constants, config, color, gradient/pattern types, util completions)' },
    { title: 'Element', detail: 'Translate Element.ts core (transform/hierarchy/dirty/clip) with animation/text/states stubbed' },
    { title: 'Scene', detail: 'Displayable + Group' },
    { title: 'Path', detail: 'graphic/Path.ts (extends Displayable, drives PathProxy)' },
    { title: 'Shapes', detail: 'Rect, Circle, Sector, Arc, BezierCurve, Polygon buildPath' },
    { title: 'Painter', detail: 'First real NativePainter: CGRenderer (PathProxy->CGPath) + CALayerPainter' },
    { title: 'Integrate', detail: 'swift build, iteratively fix compile errors to green' },
    { title: 'Verify', detail: 'Per-file adversarial review + geometry-parity golden tests vs oracle' },
    { title: 'Synthesize', detail: 'Update PORT_STATUS.md with Phase 1 results and Phase 2 plan' },
  ],
}

const Z = '/private/tmp/claude-501/-Volumes-EXT-Storage-Developer-iOS-Chart/21753b38-f505-4ea4-a4d1-9954364436c9/scratchpad/zrender/src'
const PROJ = '/Volumes/EXT-Storage/Developer/iOS-Chart'

const PREAMBLE = `This is a FAITHFUL, line-by-line port of Apache ECharts/ZRender (TypeScript) to Swift. The overriding goal: preserve upstream structure so future upstream changes can be re-synced by diffing.

BEFORE writing anything, READ these two files for the binding rules and current state:
- ${PROJ}/CONVENTIONS.md   (translation rulebook: number->Double; free-fn modules->caseless enum namespace; classes->final class; VectorArray=SIMD2<Double>, value-returning no out-params; header comment '// Ported from <upstream> — keep in sync with upstream'; mark every gap '// PORT-TODO')
- ${PROJ}/PORT_STATUS.md   (what Phase 0 landed; the open-issue backlog; the Phase 1 plan in section 4)

Phase 0 already translated zrender/core (matrix, vector=SIMD2<Double>, Point, curve, bbox, BoundingRect, Transformable, PathProxy, platform, util[partial], LRU, WeakMap, types, env) into ${PROJ}/Sources/ZRenderKit/Core/. Reuse those public APIs; do not re-translate them. Source of truth (READ-ONLY) is the cloned zrender at ${Z}/ — never modify the scratchpad.`

const T_SCHEMA = {
  type: 'object', additionalProperties: false,
  required: ['file', 'status', 'publicAPI', 'deviations', 'portTodos'],
  properties: {
    file: { type: 'string' },
    status: { type: 'string', enum: ['complete', 'partial', 'stub'] },
    publicAPI: { type: 'string', description: 'Public types/methods exposed, so dependents & reviewers know the surface.' },
    deviations: { type: 'string', description: 'Where Swift necessarily diverges from TS and why.' },
    portTodos: { type: 'array', items: { type: 'string' } },
  },
}
const R_SCHEMA = {
  type: 'object', additionalProperties: false,
  required: ['file', 'verdict', 'issues'],
  properties: {
    file: { type: 'string' },
    verdict: { type: 'string', enum: ['faithful', 'minor-issues', 'major-issues'] },
    issues: { type: 'array', items: { type: 'object', additionalProperties: false, required: ['severity', 'detail'], properties: {
      severity: { type: 'string', enum: ['blocker', 'correctness', 'style'] },
      detail: { type: 'string' },
    } } },
  },
}

// ---------------- Phase: Foundations (parallel barrier) ----------------
phase('Foundations')

const foundationTasks = [
  () => agent(`${PREAMBLE}

TASK: Correctness sweep of the EXISTING Phase-0 core files (edit in place under ${PROJ}/Sources/ZRenderKit/Core/). Apply the deduped backlog in PORT_STATUS.md section 3, items 2-8, with a SINGLE consistent policy so the whole layer agrees:
- NaN propagation: JS Math.min/max propagate NaN; Swift.min/max do not. Introduce a small faithful 'mathMin/mathMax' helper (NaN-propagating) and use it in the bbox/bounds accumulators in vector.min/max, BoundingRect.mathMin/Max (+4-arg), and any bbox reduction — OR, if you judge a documented 'finite-coords-only' guarantee cleaner, apply and DOCUMENT it uniformly. Pick ONE and justify in deviations.
- '|| 0' vs '?? 0': Point ctor, Transformable.getLocalTransform (originX/Y, rotation), and peers must replicate JS 'x || 0' (NaN/0 -> 0), not just nil->0. Add a faithful helper (e.g. 'jsOr0') and apply.
- platform.measureText: iterate text.utf16 code units, not grapheme clusters (match text.length).
- env: either make detect()/configureNativeEnv faithful to upstream's windowless(node) branch, or mark the divergences '// PORT-TODO: not faithful, dead on iOS' explicitly.
Keep changes minimal and faithful. Re-run 'cd ${PROJ} && swift build' and ensure it still compiles. Return a summary as the 'file' = "sweep", listing each fix.`, { label: 'sweep:core', phase: 'Foundations', schema: T_SCHEMA }),

  () => agent(`${PREAMBLE}

TASK: Translate ${Z}/core/Eventful.ts -> ${PROJ}/Sources/ZRenderKit/Core/Eventful.swift . This is the event-mixin base that Element extends. Translate faithfully (on/off/one/trigger/handlers). Generic handler/context typing -> Swift closures + AnyObject context. Depends on util (keys/etc). final class.`, { label: 'translate:Eventful', phase: 'Foundations', schema: T_SCHEMA }),

  () => agent(`${PREAMBLE}

TASK: Create a STUB of the animation layer sufficient for Element/Displayable/Path to compile and run render-only. Translate ${Z}/animation/Animator.ts -> ${PROJ}/Sources/ZRenderKit/Animation/Animator.swift but ONLY the public TYPE SURFACE that Element/Displayable/Path reference (class Animator, cloneValue, AnimationEasing type alias from animation/easing.ts, the animateTo/stopAnimation/animators-array hooks). Bodies that actually tween may be '// PORT-TODO: real animation deferred to Phase 3' no-ops, but signatures must be faithful so callers compile. Also create a minimal ${PROJ}/Sources/ZRenderKit/Animation/easing.swift with the AnimationEasing type (string name or function) as needed. Mark clearly these are Phase-3 stubs.`, { label: 'stub:Animator', phase: 'Foundations', schema: T_SCHEMA }),

  () => agent(`${PREAMBLE}

TASK: Translate the small constant/config modules:
- ${Z}/graphic/constants.ts -> ${PROJ}/Sources/ZRenderKit/Graphic/constants.swift (REDRAW_BIT, STYLE_CHANGED_BIT, SHAPE_CHANGED_BIT and the other dirty-bit flags — faithful bit values).
- ${Z}/config.ts -> ${PROJ}/Sources/ZRenderKit/config.swift (LIGHT_LABEL_COLOR, DARK_LABEL_COLOR, DARK_MODE_THRESHOLD, LIGHTER_LABEL_COLOR, devicePixelRatio default, etc.).
Both are tiny; keep names/values exact.`, { label: 'translate:constants+config', phase: 'Foundations', schema: T_SCHEMA }),

  () => agent(`${PREAMBLE}

TASK: Translate ${Z}/tool/color.ts -> ${PROJ}/Sources/ZRenderKit/Tool/color.swift . Focus on the functions Path and the painter need: parse (css color string -> [r,g,b,a]), stringify, lum (luminance, used for auto label color), modifyAlpha, and their helper tables/clamping. Numeric color math must be exact. Functions that are clearly browser/canvas-only or unused this phase may be '// PORT-TODO'. caseless enum 'color' namespace.`, { label: 'translate:color', phase: 'Foundations', schema: T_SCHEMA }),

  () => agent(`${PREAMBLE}

TASK: Translate the gradient/pattern DATA TYPES that Path's style references (so Path compiles with solid + gradient fills typed, even though the painter renders only solid colors this phase):
- ${Z}/graphic/Gradient.ts -> ${PROJ}/Sources/ZRenderKit/Graphic/Gradient.swift
- ${Z}/graphic/LinearGradient.ts -> .../LinearGradient.swift
- ${Z}/graphic/RadialGradient.ts -> .../RadialGradient.swift
- ${Z}/graphic/Pattern.ts -> .../Pattern.swift
These are small data classes (color stops, coords, global flag). Translate the type/shape faithfully (final class). Rendering of gradients/patterns is Phase 2 — fine to leave behavior PORT-TODO, but the object model must be correct so PathStyleProps.fill can be 'String | Gradient | Pattern'.`, { label: 'translate:gradient-types', phase: 'Foundations', schema: T_SCHEMA }),

  () => agent(`${PREAMBLE}

TASK: EXTEND ${PROJ}/Sources/ZRenderKit/Core/util.swift (currently partial) with the helpers Element/Displayable/Path import but that were deferred in Phase 0: clone, extend, defaults, keys, createObject, isString, isArray, isFunction, isObject, merge (and any other util.* referenced by Element.ts/Displayable.ts/Path.ts — READ those imports). Faithful to upstream semantics. Append; do not break existing helpers. After editing, 'cd ${PROJ} && swift build' must still pass.`, { label: 'util:completions', phase: 'Foundations', schema: T_SCHEMA }),
]

const foundations = (await parallel(foundationTasks)).filter(Boolean)
log('Foundations done: ' + foundations.length + ' tasks')

// ---------------- Phase: Element (barrier) ----------------
phase('Element')
const element = await agent(`${PREAMBLE}

TASK: Translate ${Z}/Element.ts -> ${PROJ}/Sources/ZRenderKit/Element.swift . This is the 2172-line keystone of the scene graph and is heavily entangled. SCOPE for Phase 1 (render-only): translate FAITHFULLY the parts needed to build and render a static scene graph, and STUB the rest with '// PORT-TODO' so it compiles:
- TRANSLATE: class Element extends Transformable + Eventful; id/name; the dirty-bit / __dirty flags (using Graphic/constants); parent/__zr hierarchy; clipPath (setClipPath/removeClipPath, _clipPath); getBoundingRect/getPaintRect; transform update plumbing it adds over Transformable; the attr/attrKV setter machinery; z/z2/zlevel; invisible/ignore; silent/cursor.
- STUB (PORT-TODO, faithful signatures, no/placeholder bodies, deferred to later phases): the animation surface (animateTo/animateFrom/stopAnimation/animators, uses Animator stub), textContent/textConfig/ZRText integration (Text is Phase 2 — type it as an Optional forward-declared protocol or a minimal placeholder), the states/emphasis/blur/select machinery (saveCurrentToNormalState/useState/etc — Phase 2), textGuide.
Keep upstream method order and names. Reference the Phase-0 APIs (Transformable, BoundingRect, matrix.invert, Point) and the foundation files (Eventful, Animator stub, constants). Document in 'deviations' exactly which blocks you stubbed.`, { label: 'translate:Element', phase: 'Element', schema: T_SCHEMA })

// ---------------- Phase: Scene (Displayable + Group, parallel) ----------------
phase('Scene')
const scene = (await parallel([
  () => agent(`${PREAMBLE}

TASK: Translate ${Z}/graphic/Displayable.ts -> ${PROJ}/Sources/ZRenderKit/Graphic/Displayable.swift . extends Element (now at ${PROJ}/Sources/ZRenderKit/Element.swift — READ it for the real Swift surface). Translate faithfully: class Displayable extends Element; the CommonStyleProps / style dictionary; z-order; invisible; culling; useStyle/dirtyStyle/styleChanged bits (Graphic/constants); getBoundingRect/contain hooks; innerBeforeBrush/afterBrush no-ops. Style is a property bag in TS — model PathStyleProps/CommonStyleProps as Swift structs per CONVENTIONS (known fields), with a 'style' stored property. Deferred animation/states inherited from Element stay stubbed.`, { label: 'translate:Displayable', phase: 'Scene', schema: T_SCHEMA }),
  () => agent(`${PREAMBLE}

TASK: Translate ${Z}/graphic/Group.ts -> ${PROJ}/Sources/ZRenderKit/Graphic/Group.swift . extends Element. Faithful: children array, add/addBefore/remove/removeAll/eachChild, getBoundingRect over children, _children dirty propagation. This is the non-drawing container the painter walks.`, { label: 'translate:Group', phase: 'Scene', schema: T_SCHEMA }),
])).filter(Boolean)

// ---------------- Phase: Path (barrier) ----------------
phase('Path')
const path = await agent(`${PREAMBLE}

TASK: Translate ${Z}/graphic/Path.ts -> ${PROJ}/Sources/ZRenderKit/Graphic/Path.swift . extends Displayable (READ ${PROJ}/Sources/ZRenderKit/Graphic/Displayable.swift). This is where shapes meet PathProxy. Translate faithfully:
- class Path<Shape> extends Displayable; the 'shape' struct bag; PathStyleProps (fill: String|Gradient|Pattern, stroke, lineWidth, lineCap/join, miterLimit, lineDash/offset, fillOpacity/strokeOpacity, strokePercent, strokeFirst, etc.).
- the path-building lifecycle: createPathProxy, the buildPath(ctx, shape) virtual (subclasses override — use a Swift overridable method or protocol), the dirty/shapeChanged bits, getUpdatedPathProxy / pathUpdated, and getBoundingRect routing through the PathProxy + bbox (this exercises the Phase-0 bbox.fromCubic fix).
- auto label color via tool/color.lum + config thresholds.
- STUB (PORT-TODO): contain()/pathContain hit-testing (contain/* is Phase 2), gradient/pattern paint resolution (types exist, rendering deferred), animation hooks.
Generics: TS 'Path<Props, Shape>' -> choose a Swift-idiomatic shape representation per CONVENTIONS (e.g. an associated 'ShapeType' or a base class with a typed 'shape'); document the choice. The KEY requirement: a subclass can define a shape struct + override buildPath to emit PathProxy commands, exactly like upstream.`, { label: 'translate:Path', phase: 'Path', schema: T_SCHEMA })

// ---------------- Phase: Shapes (parallel) + Painter (concurrent) ----------------
phase('Shapes')
const SHAPES = ['Rect', 'Circle', 'Sector', 'Arc', 'BezierCurve', 'Polygon']
const shapeThunks = SHAPES.map(s => () => agent(`${PREAMBLE}

TASK: Translate ${Z}/graphic/shape/${s}.ts -> ${PROJ}/Sources/ZRenderKit/Graphic/Shape/${s}.swift . A Path subclass: a '${s}Shape' struct of parameters + a buildPath that emits PathProxy commands. Translate the buildPath MATH EXACTLY (corner-radius arcs, sector inner/outer + rounding, bezier 'percent' partial draw, etc.) — these are validated byte-for-byte against the real-ECharts golden fixture for '${s.toLowerCase()}'. Match the Path<Shape> pattern chosen in ${PROJ}/Sources/ZRenderKit/Graphic/Path.swift (READ it). Sector/Arc/BezierCurve may use Phase-0 curve/bbox helpers and graphic/helper roundRect/roundSector — if a helper file is missing, translate the small helper inline or under Graphic/Helper with a PORT-TODO note.`, { label: 'translate:shape:' + s, phase: 'Shapes', schema: T_SCHEMA }))

const painterThunk = () => agent(`${PREAMBLE}

TASK: Write the FIRST REAL NativePainter (this is NEW Swift, NOT a translation of zrender's CanvasPainter/SVGPainter — it targets the seam protocols in ${PROJ}/Sources/NativePainter/Renderer.swift). Implement under ${PROJ}/Sources/NativePainter/ :
- 'CGPathRebuilder: PathRebuilder' — converts PathProxy.rebuildPath commands into a CGMutablePath: moveTo->move(to:), lineTo->addLine(to:), bezierCurveTo->addCurve, quadraticCurveTo->addQuadCurve, arc->addArc(center:radius:startAngle:endAngle:clockwise:) (MIND the angle/anticlockwise convention vs CoreGraphics' flipped y / clockwise sense — get this right, it's the classic bug), ellipse->apply an affine scale around center to a unit arc, rect->addRect, closePath->closeSubpath. READ ${PROJ}/Sources/ZRenderKit/Core/PathProxy.swift and PathRebuilder.swift for exact signatures.
- 'CGRenderer: Renderer' — implement the paint ops over a CGContext / CAShapeLayer: fillPath/strokePath from a PathStyleProps-derived paint (solid color via Tool/color.parse -> CGColor; lineWidth/cap/join/miterLimit/dash; fillRule), transform (MatrixArray [a,b,c,d,e,f] -> CGAffineTransform), opacity, setClip (clip path), shadow (CALayer/CG shadow). Gradients/patterns/text/image -> '// PORT-TODO' this phase.
- 'CALayerPainter: Painter' — owns a root CALayer, dpr = screen scale; walks a Group/Displayable tree (Storage display-list ordering by zlevel/z/z2) and renders each Path via a CAShapeLayer (CGPath from CGPathRebuilder + paint). beginFrame/endFrame.
- Provide a tiny 'renderToImage(group:size:)' convenience (render the root layer into a CGImage) for snapshot tests.
Platforms: guard CoreGraphics/QuartzCore imports for iOS+macOS. Keep it small and correct; this is the milestone that proves native rendering.`, { label: 'translate:CALayerPainter', phase: 'Painter', schema: T_SCHEMA })

const shapesAndPainter = (await parallel([...shapeThunks, painterThunk])).filter(Boolean)
const shapes = shapesAndPainter.slice(0, SHAPES.length)
const painter = shapesAndPainter[SHAPES.length]

// ---------------- Phase: Integrate (build-fix loop) ----------------
phase('Integrate')
const integrate = await agent(`${PREAMBLE}

TASK: Make the whole package COMPILE GREEN. This phase generated many interdependent files in parallel, so there WILL be integration errors (missing members, signature mismatches, forward-reference gaps, Package.swift target/source layout — note new dirs Sources/ZRenderKit/{Graphic,Graphic/Shape,Animation,Tool,Graphic/Helper} and Sources/NativePainter additions; update Package.swift if needed, though SwiftPM globs Sources/<target>/** by default).
Loop: run 'cd ${PROJ} && swift build' (timeout ~300s), read the errors, fix them with MINIMAL, FAITHFUL edits across the generated files. Repeat until it builds or you've done ~10 iterations. Rules:
- Prefer fixing real mismatches (wrong member name, missing arg) over deleting logic.
- For genuinely-deferred dependencies (Text, animation, gradients, contain), a '// PORT-TODO' stub with a faithful signature is acceptable to unblock the build — never silently drop translated math.
- Do NOT weaken the shape buildPath math or PathProxy logic to dodge an error; fix the call site instead.
Then run 'swift test' and report whether existing GoldenTests still pass. Return: final build status (green/partial), the list of fixes made, and any errors you could not resolve with the reason. Set status='complete' only if 'swift build' is green.`, { label: 'build-fix-loop', phase: 'Integrate', schema: { type: 'object', additionalProperties: false, required: ['file', 'status', 'buildGreen', 'fixes', 'unresolved'], properties: { file: { type: 'string' }, status: { type: 'string', enum: ['complete', 'partial', 'stub'] }, buildGreen: { type: 'boolean' }, fixes: { type: 'array', items: { type: 'string' } }, unresolved: { type: 'array', items: { type: 'string' } } } } })

// ---------------- Phase: Verify (review + geometry-parity golden, parallel) ----------------
phase('Verify')
const REVIEW_TARGETS = [
  { name: 'Element', dst: 'Sources/ZRenderKit/Element.swift', src: 'Element.ts' },
  { name: 'Displayable', dst: 'Sources/ZRenderKit/Graphic/Displayable.swift', src: 'graphic/Displayable.ts' },
  { name: 'Group', dst: 'Sources/ZRenderKit/Graphic/Group.swift', src: 'graphic/Group.ts' },
  { name: 'Path', dst: 'Sources/ZRenderKit/Graphic/Path.swift', src: 'graphic/Path.ts' },
  ...SHAPES.map(s => ({ name: 'shape:' + s, dst: 'Sources/ZRenderKit/Graphic/Shape/' + s + '.swift', src: 'graphic/shape/' + s + '.ts' })),
]
const reviewThunks = REVIEW_TARGETS.map(t => () => agent(`${PREAMBLE}

TASK: Adversarially review ONE Swift translation against its TS source for SEMANTIC faithfulness. Assume a bug until proven otherwise.
TS SOURCE (authority): ${Z}/${t.src}
SWIFT (review): ${PROJ}/${t.dst}
Hunt for: value-vs-reference semantics (scene-graph nodes MUST be final class / shared); buildPath math divergence (arc angle signs, anticlockwise, corner-radius clamping, sector rounding, bezier 'percent' subdivision); dirty-bit logic; integer vs Double; off-by-one; wrong PathProxy opcode/args; NaN/||0 handling per the Phase-0 policy. For shapes, cross-check the emitted command sequence against the intent of the golden fixture. Only report real divergences; cite TS behavior + Swift line + consequence.`, { label: 'review:' + t.name, phase: 'Verify', schema: R_SCHEMA }))

const goldenThunk = () => agent(`${PREAMBLE}

TASK: Upgrade the golden tests from 'rebuilt-d string parity' to TRUE GEOMETRY PARITY driven by the ported shapes. In ${PROJ}/Tests/ZRenderKitTests/GoldenTests.swift there is a compiled-out 'testSwiftBuildPathMatchesOracle' (behind #if PORT_TODO_GOLDEN) describing the intended end state. Now make it real:
- For each fixture in {rect, circle, sector, arc, bezier-curve, polygon}: READ ${PROJ}/Oracle/options/<name>.json to get the shape's input params, instantiate the ported Shape (RectShape/CircleShape/... from Sources/ZRenderKit/Graphic/Shape) with those params, call buildPath into a fresh PathProxy, rebuildPath through the existing GoldenPathRebuilder, and assert the produced canonical 'd' equals the fixture's 'rebuiltD' (${PROJ}/Oracle/fixtures/<name>.json) — byte-for-byte, same precision/formatting as Phase 0.
- Map fixture shape param names to the Swift shape struct fields (READ each shape file).
- Keep the existing testRebuiltDMatchesOracle + testAllFixturesLoad passing.
- Add a lightweight CALayerPainter smoke test (macOS/iOS guarded): build a Group with a Rect+Circle+Sector, render via CALayerPainter.renderToImage, assert non-nil image of expected size (geometry parity is covered by the buildPath test; this just proves the painter path executes).
Run 'cd ${PROJ} && swift test' and report results. Return which fixtures PASS geometry parity and which FAIL (with the diff), as the structured result.`, { label: 'golden-geometry-parity', phase: 'Verify', schema: { type: 'object', additionalProperties: false, required: ['file', 'pass', 'fail', 'notes'], properties: { file: { type: 'string' }, pass: { type: 'array', items: { type: 'string' } }, fail: { type: 'array', items: { type: 'string' } }, notes: { type: 'string' } } } })

const verify = (await parallel([...reviewThunks, goldenThunk])).filter(Boolean)
const golden = verify[verify.length - 1]
const reviews = verify.slice(0, REVIEW_TARGETS.length)

// ---------------- Phase: Synthesize ----------------
phase('Synthesize')
const synth = await agent(`${PREAMBLE}

TASK: Update ${PROJ}/PORT_STATUS.md to reflect Phase 1. You are given the structured results below. Read the actual produced Swift under ${PROJ}/Sources/ZRenderKit/{Element.swift,Graphic,Animation,Tool} and ${PROJ}/Sources/NativePainter to ground the summary.

Integrate(build): ${JSON.stringify(integrate)}
Golden geometry parity: ${JSON.stringify(golden)}
Reviews: ${JSON.stringify(reviews.map(r => r && { file: r.file, verdict: r.verdict, blockers: (r.issues || []).filter(i => i.severity !== 'style').length }))}
Foundations: ${JSON.stringify(foundations.map(f => f && f.file))}

Rewrite/extend PORT_STATUS.md to include:
1. A 'Phase 1' section: what landed (scene graph Element/Displayable/Group/Path, 6 shapes, CALayerPainter, geometry-parity golden), with a per-file status + review-verdict table.
2. Build status (green or not) and whether swift test / golden geometry parity passes per fixture.
3. A deduped, severity-sorted backlog of NEW open issues + PORT-TODOs from Phase 1 (especially anything stubbed: Text, animation, states, contain/hit-test, gradient/pattern rendering, full shape set).
4. The Phase 2 plan: Text/TSpan/Image + contain/* (hit testing) + remaining shapes + gradient/pattern paint in CALayerPainter + Storage/display-list + a real zrender 'ZRender' host facade — list the specific upstream files and their already-ported deps.
5. Keep the standing upstream-sync rule.
Preserve the Phase 0 content (append/restructure, don't delete the history). Return a one-paragraph summary as text + the list of any blockers.`, { label: 'synthesize-status', phase: 'Synthesize', schema: { type: 'object', additionalProperties: false, required: ['summary', 'blockers'], properties: { summary: { type: 'string' }, blockers: { type: 'array', items: { type: 'string' } } } } })

return {
  buildGreen: integrate && integrate.buildGreen,
  goldenParity: golden && { pass: golden.pass, fail: golden.fail },
  reviews: reviews.map(r => r && { file: r.file, verdict: r.verdict }),
  unresolved: integrate && integrate.unresolved,
  summary: synth && synth.summary,
  blockers: synth && synth.blockers,
}
