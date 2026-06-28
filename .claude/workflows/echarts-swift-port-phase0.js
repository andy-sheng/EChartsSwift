export const meta = {
  name: 'echarts-swift-port-phase0',
  description: 'Phase 0: faithfully translate zrender/core geometry foundation to Swift, mirroring upstream structure, with golden tests',
  phases: [
    { title: 'Scaffold', detail: 'Create SwiftPM layout + translation conventions + Renderer/PathRebuilder protocols' },
    { title: 'Translate', detail: 'Parallel direct TS->Swift translation of 14 zrender/core files' },
    { title: 'Golden', detail: 'Node display-list dumper + XCTest oracle harness + fixtures' },
    { title: 'Review', detail: 'Adversarial per-file review of each translation against the TS source' },
    { title: 'Synthesize', detail: 'Write PORT_STATUS manifest and next-phase plan' },
  ],
}

const SRC = '/private/tmp/claude-501/-Volumes-EXT-Storage-Developer-iOS-Chart/21753b38-f505-4ea4-a4d1-9954364436c9/scratchpad/zrender/src/core'
const PROJ = '/Volumes/EXT-Storage/Developer/iOS-Chart'
const DST = PROJ + '/Sources/ZRenderKit/Core'

// Phase 0 geometry foundation, ordered roughly by dependency depth (all translated in parallel; conventions keep them coherent)
const FILES = [
  { name: 'types',         src: 'types.ts',         dst: 'types.swift',         note: 'Core type aliases (MatrixArray, VectorArray, etc). Establishes the shared numeric typealiases everything else uses.' },
  { name: 'env',           src: 'env.ts',           dst: 'env.swift',           note: 'Environment detection. On iOS most browser checks collapse to constants; translate the struct shape, hardcode the native-relevant flags, mark browser-only fields with // PORT-TODO.' },
  { name: 'util',          src: 'util.ts',          dst: 'util.swift',          note: 'Large general helper module. Translate the numeric/array helpers actually used by the geometry layer (clamp-like, map/each over numbers, retrieve/defaults). For JS object-merge/duck-typing helpers that do not map to Swift, provide Swift-idiomatic equivalents only where geometry needs them and mark the rest // PORT-TODO with a list. Do not invent.' },
  { name: 'LRU',           src: 'LRU.ts',           dst: 'LRU.swift',           note: 'LRU cache used by text/path caching. Generic. Translate faithfully as a final class.' },
  { name: 'WeakMap',       src: 'WeakMap.ts',       dst: 'WeakMap.swift',       note: 'zrender browser WeakMap shim. On Swift use NSMapTable weakToStrong or a thin wrapper; preserve the public API surface.' },
  { name: 'matrix',        src: 'matrix.ts',        dst: 'matrix.swift',        note: '2x3 affine matrix as a flat [a,b,c,d,e,f]. CRITICAL: functions mutate an `out` array. Follow the conventions doc decision on out-param mutation EXACTLY (inout vs SIMD). This file sets the precedent reviewers will check vector/Point against.' },
  { name: 'vector',        src: 'vector.ts',        dst: 'vector.swift',        note: 'vec2 helpers. Same out-param mutation hazard as matrix. Must use the SAME mutation strategy as matrix.swift per conventions.' },
  { name: 'Point',         src: 'Point.ts',         dst: 'Point.swift',         note: 'Point class (reference type in TS, used mutably). Translate as final class. Uses matrix/vector.' },
  { name: 'curve',         src: 'curve.ts',         dst: 'curve.swift',         note: 'Cubic/quadratic bezier math: length, subdivide, root finding. Pure numeric — highest-value, must be exact. Watch integer-vs-Double division and epsilon constants.' },
  { name: 'bbox',          src: 'bbox.ts',          dst: 'bbox.swift',          note: 'Bounding-box-from-primitive helpers (fromLine/fromCubic/fromQuadratic/fromArc), mutate an out min/max. Same out-param convention.' },
  { name: 'BoundingRect',  src: 'BoundingRect.ts',  dst: 'BoundingRect.swift',  note: 'Axis-aligned rect with union/intersect/applyTransform. final class. Uses matrix/vector.' },
  { name: 'Transformable', src: 'Transformable.ts', dst: 'Transformable.swift', note: 'SRT decomposed transform mixin -> compose to MatrixArray. In TS this is mixed into Element; translate as a base class or protocol+extension per conventions. Uses matrix/vector/Point/BoundingRect.' },
  { name: 'platform',      src: 'platform.ts',      dst: 'platform.swift',      note: 'platformApi injection point (measureText/createCanvas/loadImage). Define a PlatformAPI protocol + global setPlatformAPI. CRUCIALLY translate the built-in ASCII-width-table measureText FALLBACK so text measurement works with zero Core Text dependency in Phase 0. Mark createCanvas/loadImage as // PORT-TODO stubs.' },
  { name: 'PathProxy',     src: 'PathProxy.ts',     dst: 'PathProxy.swift',     note: 'THE CENTERPIECE. Records path commands into a numeric buffer (CMD opcodes M/L/C/Q/A/Z/R), computes bounding rect & arc length, and rebuildPath(rebuilder, percent) replays into a PathRebuilder (use the protocol scaffold defines). Float32Array buffer -> choose [Float]/ContiguousArray per conventions. getVersion() caching must be preserved. This is what the native Painter will consume.' },
]

const CONV_SCHEMA = {
  type: 'object',
  additionalProperties: false,
  required: ['conventions', 'created', 'mutationStrategy'],
  properties: {
    conventions: { type: 'string', description: 'The full text of CONVENTIONS.md that every translator must follow. Self-contained; will be pasted into each translator prompt.' },
    mutationStrategy: { type: 'string', description: 'One-line: the chosen approach for TS out-param array mutation (e.g. "inout [Double]" vs "SIMD/return-new"), since this governs matrix/vector/bbox.' },
    created: { type: 'array', items: { type: 'string' }, description: 'Paths of files created (Package.swift, protocols, CONVENTIONS.md).' },
  },
}

const T_SCHEMA = {
  type: 'object',
  additionalProperties: false,
  required: ['file', 'status', 'publicAPI', 'deviations', 'portTodos'],
  properties: {
    file: { type: 'string' },
    status: { type: 'string', enum: ['complete', 'partial', 'stub'] },
    publicAPI: { type: 'string', description: 'Brief list of the public types/functions exposed (so dependents and reviewers know the surface).' },
    deviations: { type: 'string', description: 'Where the Swift necessarily diverges from the TS (value semantics, naming, idioms) and why.' },
    portTodos: { type: 'array', items: { type: 'string' }, description: 'Anything stubbed/skipped/uncertain, each as a short actionable note.' },
  },
}

const R_SCHEMA = {
  type: 'object',
  additionalProperties: false,
  required: ['file', 'verdict', 'issues'],
  properties: {
    file: { type: 'string' },
    verdict: { type: 'string', enum: ['faithful', 'minor-issues', 'major-issues'] },
    issues: {
      type: 'array',
      items: {
        type: 'object',
        additionalProperties: false,
        required: ['severity', 'detail'],
        properties: {
          severity: { type: 'string', enum: ['blocker', 'correctness', 'style'] },
          detail: { type: 'string', description: 'Concrete: cite the TS behavior, the Swift line, and the divergence. Especially: value-vs-reference semantics, integer division, epsilon/precision, mutation not propagating, off-by-one, NaN handling.' },
        },
      },
    },
  },
}

const G_SCHEMA = {
  type: 'object',
  additionalProperties: false,
  required: ['created', 'howToRun', 'fixtures'],
  properties: {
    created: { type: 'array', items: { type: 'string' } },
    howToRun: { type: 'string' },
    fixtures: { type: 'array', items: { type: 'string' }, description: 'Names of the display-list fixtures generated.' },
  },
}

phase('Scaffold')
const scaffold = await agent(
`You are setting up the foundation for a FAITHFUL, line-by-line port of Apache ECharts + ZRender from TypeScript to Swift. The overriding goal: preserve upstream structure so we can diff against and re-sync future upstream changes.

Reference source (READ-ONLY) is the cloned zrender at: ${SRC}/.. and echarts nearby. Do not modify the scratchpad.
Target project root (currently empty, NOT a git repo): ${PROJ}

Your tasks:
1. Create a single SwiftPM package at ${PROJ}/Package.swift with library targets:
   - "ZRenderKit" (Sources/ZRenderKit, with a Core/ subdir) — the translated zrender logic.
   - "NativePainter" (Sources/NativePainter, depends on ZRenderKit) — the fresh native renderer (Core Graphics / Core Animation). NOT a translation.
   - "EChartsKit" (Sources/EChartsKit, depends on ZRenderKit) — placeholder, empty for now.
   - Test target "ZRenderKitTests" (Tests/ZRenderKitTests).
   Platforms: .iOS(.v15), .macOS(.v12). Swift tools 5.9+.

2. Define the renderer-seam protocols (this is the boundary where native rendering plugs in):
   - In Sources/ZRenderKit/Core/PathRebuilder.swift: a \`PathRebuilder\` protocol with exactly: moveTo(x,y), lineTo(x,y), bezierCurveTo(x1,y1,x2,y2,x3,y3), quadraticCurveTo(x1,y1,x2,y2), arc(cx,cy,r,startAngle,endAngle,anticlockwise), ellipse(cx,cy,rx,ry,rotation,startAngle,endAngle,anticlockwise), rect(x,y,w,h), closePath(). All coords Double. This mirrors the consumer interface of PathProxy.rebuildPath in core/PathProxy.ts — READ that file to get the exact signatures.
   - In Sources/NativePainter/Renderer.swift: a stub \`Painter\`/\`Renderer\` protocol sketch (the ~8 paint ops: fillPath/strokePath with style, drawImage, drawText, setClip, transform, opacity, shadow) with // PORT-TODO bodies. Just the contract, no implementation.

3. Write ${PROJ}/CONVENTIONS.md — the binding translation rulebook every translator agent will follow. It MUST decide and document, at minimum:
   - All JS \`number\` -> Swift \`Double\`. Typed arrays (Float32Array/Int32Array) -> chosen Swift type (e.g. ContiguousArray<Float>).
   - THE OUT-PARAM MUTATION HAZARD (most important): zrender's matrix.ts/vector.ts/bbox.ts mutate a passed-in \`out\` array in place. Swift arrays are value types so this breaks silently. DECIDE one strategy and mandate it everywhere: either (a) keep the faithful out-param API using \`inout [Double]\`, or (b) switch vec2/matrix to value-returning SIMD (simd_double2 / 2x3) — pick the one that best balances faithfulness and Swift safety, justify briefly, and show a concrete before/after for vec2.add so translators copy the pattern.
   - Free-function modules (vector.ts, matrix.ts, util.ts, bbox.ts, curve.ts) -> a caseless \`enum\` namespace named after the file (e.g. \`enum vector { static func create()... }\`) so call sites stay \`vector.create(...)\`.
   - TS classes -> Swift \`final class\` (reference semantics — REQUIRED for the scene graph; never struct for Element-like types).
   - null/undefined -> Optional; Math.* and bitwise ops -> Swift/Foundation equivalents (watch integer division).
   - Preserve upstream identifiers, file names, and code order. At the TOP of every Swift file add a header comment: \`// Ported from zrender/src/core/<File>.ts — keep in sync with upstream\`. Keep meaningful upstream comments.
   - Mark every skipped/stubbed/uncertain piece with \`// PORT-TODO: ...\`.
   Make CONVENTIONS.md self-contained and copy-pasteable — its full text is your return value's \`conventions\` field, and it will be injected verbatim into every translator's prompt.

Return the structured result. Be decisive on the mutation strategy — translators depend on it.`,
  { label: 'scaffold+conventions', phase: 'Scaffold', schema: CONV_SCHEMA }
)

const conventions = (scaffold && scaffold.conventions) || '(conventions doc unavailable — default: number->Double; free-fn modules->caseless enum namespace; classes->final class; use inout [Double] for out-params; preserve upstream names/structure; header comment // Ported from upstream; mark gaps // PORT-TODO.)'

log('Scaffold done. Mutation strategy: ' + ((scaffold && scaffold.mutationStrategy) || 'default inout'))

function translatePrompt(f) {
  return `Faithfully translate ONE zrender core file from TypeScript to Swift, mirroring upstream structure so we can re-sync future upstream changes.

SOURCE (read-only, the authority): ${SRC}/${f.src}
TARGET (create this file): ${DST}/${f.dst}

File-specific guidance: ${f.note}

You MUST follow this binding conventions document exactly:
--- CONVENTIONS.md ---
${conventions}
--- end CONVENTIONS.md ---

Process:
1. Read the SOURCE file fully. Also read any sibling files it imports from ${SRC}/ ONLY to understand the types/signatures you must match — do not translate them (other agents own those). Match the public API surface of dependencies as the conventions dictate (e.g. \`vector.create()\`, the PathRebuilder protocol in Sources/ZRenderKit/Core/PathRebuilder.swift).
2. Translate the logic line-by-line, preserving identifiers, function order, and meaningful comments. Add the upstream-sync header comment. number->Double. Apply the mandated out-param mutation strategy. classes->final class.
3. Write the Swift file to the TARGET path. It should be as close to compilable as possible given that sibling files are being written concurrently (reference their conventional public names; do not stub them out locally).
4. Be rigorous on numeric correctness: bezier/arc math, epsilon constants, integer vs Double division, NaN/precision handling, anticlockwise/angle sign conventions. These must match the TS exactly.
5. Mark anything you skip or are unsure about with // PORT-TODO and list it in portTodos.

Do NOT translate other files. Do NOT touch the scratchpad source. Return the structured result.`
}

function reviewPrompt(f, t) {
  return `Adversarially review ONE Swift translation against its TypeScript source for SEMANTIC correctness. Assume there is a bug until proven otherwise — faithfulness matters more than style.

TS SOURCE (authority): ${SRC}/${f.src}
SWIFT OUTPUT (review this): ${DST}/${f.dst}
Translator's own notes: status=${t && t.status}; deviations=${(t && t.deviations) || 'n/a'}; portTodos=${JSON.stringify((t && t.portTodos) || [])}

Read BOTH files. Hunt specifically for:
- Value-vs-reference semantics: did a TS in-place mutation (out-param arrays, mutable class fields) silently become a no-op on a Swift value copy? (This is the #1 expected bug — check matrix/vector/bbox out-params and any Point/rect mutation.)
- Integer vs Double division, Math.* mistranslations, off-by-one in loops, wrong epsilon/precision constants.
- Angle/anticlockwise sign conventions, NaN/Infinity handling, array bounds, opcode/buffer indexing (PathProxy).
- API mismatches against the conventions (wrong namespace shape, struct where it must be final class).
Do not nitpick formatting. Only report real divergences from TS behavior. Cite the TS behavior, the Swift line, and the concrete consequence. Return the structured verdict.`
}

// Translate+review pipelined per file; golden-test harness built concurrently (independent of translations).
const [translated, golden] = await Promise.all([
  pipeline(
    FILES,
    f => agent(translatePrompt(f), { label: 'translate:' + f.name, phase: 'Translate', schema: T_SCHEMA }),
    (t, f) => agent(reviewPrompt(f, t), { label: 'review:' + f.name, phase: 'Review', schema: R_SCHEMA }).then(r => ({ file: f.name, translate: t, review: r }))
  ),
  agent(
`Build the Golden Test harness that lets every future translation be verified against the real ECharts/ZRender output — this is the oracle that makes a faithful port possible.

Reference source (read-only): ECharts is cloned at ${SRC}/../../echarts , zrender at ${SRC}/.. . There is a node_modules-free checkout; if echarts isn't directly require-able, build the dumper to import from the cloned dist (${SRC}/../../echarts/dist) or document the exact npm install step needed.
Target project: ${PROJ}

Create under ${PROJ}/Oracle/ :
1. A Node script dump-displaylist.js that, for a given option JSON, inits echarts in SSR mode (renderer 'svg', ssr:true, fixed width/height), setOption, then dumps chart.getZr().storage.getDisplayList(true) as JSON — each entry: { type, shape, style, transform, z, zlevel, z2 }. Write outputs to ${PROJ}/Oracle/fixtures/<name>.json. Round floats to a fixed precision for stable diffs.
2. A small set of option fixtures focused on the geometry foundation (NOT full charts yet): a few raw shapes whose buildPath exercises the core math — e.g. a Rect, a Circle, a Sector, a BezierCurve, a Polygon, and a simple arc — defined via the \`graphic\` component or a minimal custom series so they hit PathProxy. Generate their display-list + the resulting SVG <path d> string fixtures.
3. A Swift XCTest scaffold at ${PROJ}/Tests/ZRenderKitTests/GoldenTests.swift that loads a fixture JSON and shows the intended assertion shape (build a PathProxy via the same commands, rebuild through a test PathRebuilder that records a 'd'-like string or command list, and assert it matches the fixture). It's fine for it to reference types that don't fully exist yet — mark with // PORT-TODO — the point is the harness + pattern.
4. A short Oracle/README.md: how to run the dumper, how fixtures map to tests, how to add new ones as later phases land.

Return the structured result.`,
    { label: 'golden-harness', phase: 'Golden', schema: G_SCHEMA }
  ),
])

const results = translated.filter(Boolean)

phase('Synthesize')
const synth = await agent(
`Write a PORT_STATUS.md at ${PROJ}/PORT_STATUS.md summarizing Phase 0 of the ECharts->Swift port and planning the next phase. You are given structured results from the scaffold, 14 file translations + their adversarial reviews, and the golden-test harness.

Translation+review results (JSON): ${JSON.stringify(results)}
Scaffold: ${JSON.stringify({ mutationStrategy: scaffold && scaffold.mutationStrategy, created: scaffold && scaffold.created })}
Golden harness: ${JSON.stringify(golden)}

The PORT_STATUS.md must contain:
1. What landed in Phase 0 (the package layout, the seam protocols, the 14 translated core files, the golden harness) — as a checklist.
2. A table of the 14 files: status (complete/partial/stub) and review verdict (faithful/minor/major).
3. A consolidated, DEDUPED list of all open issues and PORT-TODOs across files, sorted by severity (blockers first) — these are the immediate fix-ups before Phase 1.
4. The next-phase plan: Phase 1 = zrender/graphic (Element, Displayable, Group, Path, Text, TSpan, Image) + graphic/shape buildPath set + contain/text layout, PLUS writing the first real NativePainter (CALayerPainter) so a hand-built scene graph renders on iOS. List the specific upstream files Phase 1 will translate and note which already-translated Core APIs they depend on.
5. The standing rule for syncing upstream (header comments + mirrored structure + golden fixtures).

Read a few of the actual produced Swift files under ${DST} to ground the summary in reality, not just the metadata. Return a one-paragraph summary as your text; the file is the deliverable.`,
  { label: 'synthesize-status', phase: 'Synthesize', schema: { type: 'object', additionalProperties: false, required: ['summary', 'blockers'], properties: { summary: { type: 'string' }, blockers: { type: 'array', items: { type: 'string' } } } } }
)

return {
  scaffold: scaffold && { mutationStrategy: scaffold.mutationStrategy, created: scaffold.created },
  files: results.map(r => ({ file: r.file, status: r.translate && r.translate.status, verdict: r.review && r.review.verdict })),
  golden: golden && golden.created,
  summary: synth && synth.summary,
  blockers: synth && synth.blockers,
}
