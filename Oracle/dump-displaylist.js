#!/usr/bin/env node
/*
 * Oracle/dump-displaylist.js
 *
 * The Golden Test oracle generator.
 *
 * For a given ECharts `option` JSON, this:
 *   1. Inits ECharts in SSR mode (renderer 'svg', ssr:true, fixed width/height),
 *   2. setOption(),
 *   3. Walks `chart.getZr().storage.getDisplayList(true)` (the *sorted* paint order),
 *   4. For every element dumps { type, shape, style, transform, z, zlevel, z2 },
 *   5. For every *Path* element additionally dumps the renderer-independent path math:
 *        - pathData      : the raw PathProxy command stream (CMD codes + coords),
 *        - pathCommands  : that stream replayed through PathProxy.rebuildPath() into a
 *                          recorder — i.e. the exact moveTo/lineTo/bezierCurveTo/arc/...
 *                          sequence the Swift `PathRebuilder` protocol must reproduce,
 *        - rebuiltD      : a canonical, deterministic string form of pathCommands
 *                          (the thing the Swift GoldenTests assert byte-for-byte),
 *   6. And the real SVG `<path d=...>` strings emitted by ZRender's SVG renderer
 *      (top-level `svgPaths`), as an independent cross-check of the geometry.
 *
 * All floats are rounded to a fixed precision (PRECISION) for stable diffs.
 *
 * Output: Oracle/fixtures/<name>.json
 *
 * Usage:
 *   node dump-displaylist.js                       # build every Oracle/options/*.json
 *   node dump-displaylist.js sector                # build just options/sector.json
 *   node dump-displaylist.js path/to/opt.json name # build an arbitrary option file
 *
 * Locating ECharts (a node_modules-free checkout is supported):
 *   1. `require('echarts')` if it resolves,
 *   2. else env  ECHARTS_DIST=/abs/path/to/echarts/dist/echarts.js,
 *   3. else the cloned dist this harness was authored against (see ECHARTS_FALLBACK).
 *   If none resolve, the script prints the exact `npm i` step needed and exits 1.
 */

'use strict';

const fs = require('fs');
const path = require('path');

// ---------------------------------------------------------------------------
// Config
// ---------------------------------------------------------------------------

const PRECISION = 6;            // decimal places kept for every float
const CANVAS_W = 200;           // fixed SSR canvas size — keep stable across runs
const CANVAS_H = 150;

const ROOT = __dirname;
const OPTIONS_DIR = path.join(ROOT, 'options');
const FIXTURES_DIR = path.join(ROOT, 'fixtures');

// Authored against this clone. Only used as a last resort; documented in README.
const ECHARTS_FALLBACK =
  '/private/tmp/claude-501/-Volumes-EXT-Storage-Developer-iOS-Chart' +
  '/21753b38-f505-4ea4-a4d1-9954364436c9/scratchpad/echarts/dist/echarts.js';

// ---------------------------------------------------------------------------
// Resolve ECharts
// ---------------------------------------------------------------------------

function loadECharts() {
  // 1. Normal install.
  try {
    return require('echarts');
  } catch (_) { /* fall through */ }

  // 2. Explicit env override.
  const envDist = process.env.ECHARTS_DIST;
  if (envDist && fs.existsSync(envDist)) {
    return require(path.resolve(envDist));
  }

  // 3. The clone this harness was authored against.
  if (fs.existsSync(ECHARTS_FALLBACK)) {
    return require(ECHARTS_FALLBACK);
  }

  console.error(
    'Could not resolve ECharts.\n' +
    'Fix it one of these ways:\n' +
    '  a) cd Oracle && npm init -y && npm i echarts@6\n' +
    '  b) ECHARTS_DIST=/abs/path/to/echarts/dist/echarts.js node dump-displaylist.js\n' +
    '     (the CommonJS UMD bundle — dist/echarts.js — works under plain node;\n' +
    '      the SVG renderer + SSR are bundled in.)\n'
  );
  process.exit(1);
}

const echarts = loadECharts();

// ---------------------------------------------------------------------------
// Float rounding / canonical number formatting
// ---------------------------------------------------------------------------

function round(n) {
  if (typeof n !== 'number' || !isFinite(n)) return n;
  let r = Math.round(n * 1e6) / 1e6;
  if (Object.is(r, -0)) r = 0;       // normalise negative zero
  return r;
}

// Canonical string form of a single number, shared (by contract) with the Swift
// side. Round to PRECISION, then String() which drops trailing zeros.
function fmt(n) {
  return String(round(n));
}

// Deep-round any JSON-able value (arrays, plain objects, numbers).
function roundDeep(v) {
  if (typeof v === 'number') return round(v);
  if (Array.isArray(v)) return v.map(roundDeep);
  if (v && typeof v === 'object') {
    const out = {};
    for (const k of Object.keys(v)) out[k] = roundDeep(v[k]);
    return out;
  }
  return v;
}

// ---------------------------------------------------------------------------
// PathProxy command codes (mirror zrender/src/core/PathProxy CMD)
// ---------------------------------------------------------------------------

const CMD_NAME = { 1: 'M', 2: 'L', 3: 'C', 4: 'Q', 5: 'A', 6: 'Z', 7: 'R' };

// ---------------------------------------------------------------------------
// Recorder: implements the same surface as the Swift `PathRebuilder` protocol.
// PathProxy.rebuildPath(recorder, 1) feeds it the canonical command stream.
// ---------------------------------------------------------------------------

function makeRecorder() {
  const cmds = [];
  return {
    cmds,
    moveTo(x, y) { cmds.push(['moveTo', x, y]); },
    lineTo(x, y) { cmds.push(['lineTo', x, y]); },
    bezierCurveTo(x1, y1, x2, y2, x3, y3) {
      cmds.push(['bezierCurveTo', x1, y1, x2, y2, x3, y3]);
    },
    quadraticCurveTo(x1, y1, x2, y2) {
      cmds.push(['quadraticCurveTo', x1, y1, x2, y2]);
    },
    arc(cx, cy, r, startAngle, endAngle, anticlockwise) {
      cmds.push(['arc', cx, cy, r, startAngle, endAngle, !!anticlockwise]);
    },
    ellipse(cx, cy, rx, ry, rotation, startAngle, endAngle, anticlockwise) {
      cmds.push(['ellipse', cx, cy, rx, ry, rotation, startAngle, endAngle, !!anticlockwise]);
    },
    rect(x, y, w, h) { cmds.push(['rect', x, y, w, h]); },
    closePath() { cmds.push(['closePath']); }
  };
}

// Canonical, deterministic stringification of a recorded command list.
// This is the byte-for-byte golden string the Swift test reproduces from its
// own PathRebuilder. Tokens are intentionally NOT the SVG `d` grammar (arcs are
// kept as arcs, not converted to cubics) so the math stays 1:1 with PathProxy.
const TOKEN = {
  moveTo: 'M', lineTo: 'L', bezierCurveTo: 'C', quadraticCurveTo: 'Q',
  arc: 'ARC', ellipse: 'ELL', rect: 'RECT', closePath: 'Z'
};

function commandsToD(cmds) {
  const parts = [];
  for (const c of cmds) {
    const [op, ...args] = c;
    const tok = TOKEN[op];
    const a = args.map((v) => (typeof v === 'boolean' ? (v ? '1' : '0') : fmt(v)));
    parts.push([tok, ...a].join(' '));
  }
  return parts.join(' ');
}

// Round the numbers inside a recorded command list (keep booleans / op name).
function roundCommands(cmds) {
  return cmds.map((c) =>
    c.map((v) => (typeof v === 'number' ? round(v) : v))
  );
}

// ---------------------------------------------------------------------------
// Style: capture a stable whitelist of paint/geometry keys that are defined.
// (The full computed style object is huge and noisy; this keeps diffs tight.)
// ---------------------------------------------------------------------------

const STYLE_KEYS = [
  'fill', 'stroke', 'lineWidth', 'opacity', 'fillOpacity', 'strokeOpacity',
  'lineDash', 'lineDashOffset', 'lineCap', 'lineJoin', 'miterLimit',
  'shadowBlur', 'shadowColor', 'shadowOffsetX', 'shadowOffsetY'
];

function captureStyle(style) {
  if (!style) return null;
  const out = {};
  for (const k of STYLE_KEYS) {
    if (style[k] !== undefined && style[k] !== null) out[k] = roundDeep(style[k]);
  }
  return out;
}

// ---------------------------------------------------------------------------
// Dump one element of the display list.
// ---------------------------------------------------------------------------

function dumpElement(el) {
  const entry = {
    type: el.type,
    shape: el.shape ? roundDeep(JSON.parse(JSON.stringify(el.shape))) : null,
    style: captureStyle(el.style),
    transform: el.transform ? Array.from(el.transform).map(round) : null,
    z: round(el.z),
    zlevel: round(el.zlevel),
    z2: round(el.z2)
  };

  // Path math (the heart of the oracle). Non-Path elements (Group/Text/Image)
  // simply won't expose getUpdatedPathProxy.
  if (typeof el.getUpdatedPathProxy === 'function') {
    let proxy;
    try {
      proxy = el.getUpdatedPathProxy();
    } catch (e) {
      proxy = null;
    }
    if (proxy && proxy.data) {
      // Raw command stream: CMD codes interleaved with coordinates.
      entry.pathData = Array.from(proxy.data).map(round);

      // Decode the leading CMD codes into a readable opcode list (debugging aid).
      entry.pathDataOps = decodeOps(proxy.data);

      // Replay through the PathRebuilder surface (the Swift contract).
      const rec = makeRecorder();
      proxy.rebuildPath(rec, 1);
      entry.pathCommands = roundCommands(rec.cmds);
      entry.rebuiltD = commandsToD(rec.cmds);
    }
  }

  return entry;
}

// Decode just the opcode sequence (e.g. ["M","A","L","A","Z"]) for readability.
function decodeOps(data) {
  const ops = [];
  let i = 0;
  const N = data.length;
  while (i < N) {
    const cmd = data[i];
    const name = CMD_NAME[cmd] || ('?' + cmd);
    ops.push(name);
    // advance i past this command's payload (see zrender PathProxy.addData arities)
    switch (cmd) {
      case 1: i += 1 + 2; break;            // M x y
      case 2: i += 1 + 2; break;            // L x y
      case 3: i += 1 + 6; break;            // C x1 y1 x2 y2 x3 y3
      case 4: i += 1 + 4; break;            // Q x1 y1 x2 y2
      case 5: i += 1 + 8; break;            // A cx cy rx ry start end flag isFirst
      case 6: i += 1; break;                // Z
      case 7: i += 1 + 4; break;            // R x y w h
      default: i = N; break;                // unknown — stop to avoid looping
    }
  }
  return ops;
}

// ---------------------------------------------------------------------------
// Extract the real SVG <path d="..."> strings from the rendered SVG.
// ---------------------------------------------------------------------------

function extractSvgPaths(svg) {
  const out = [];
  const re = /<path\b[^>]*\bd="([^"]*)"/g;
  let m;
  while ((m = re.exec(svg)) !== null) out.push(m[1]);
  return out;
}

// ---------------------------------------------------------------------------
// Build one fixture from an option object.
// ---------------------------------------------------------------------------

function buildFixture(name, option, meta) {
  // Force-disable animation so the display list is final & deterministic, and so
  // the node process can exit without lingering animation timers.
  const opt = Object.assign({ animation: false }, option);

  const chart = echarts.init(null, null, {
    renderer: 'svg',
    ssr: true,
    width: CANVAS_W,
    height: CANVAS_H
  });
  chart.setOption(opt);

  const dl = chart.getZr().storage.getDisplayList(true);
  const elements = dl.map(dumpElement);

  const svg = chart.renderToSVGString();
  const svgPaths = extractSvgPaths(svg);

  chart.dispose();

  return {
    // Provenance so a fixture is self-describing.
    name,
    generator: 'Oracle/dump-displaylist.js',
    echartsVersion: echarts.version,
    precision: PRECISION,
    canvas: { width: CANVAS_W, height: CANVAS_H, renderer: 'svg', ssr: true },
    description: (meta && meta.description) || '',
    option: roundDeep(opt),
    elements,
    svgPaths
  };
}

function writeFixture(name, fixture) {
  if (!fs.existsSync(FIXTURES_DIR)) fs.mkdirSync(FIXTURES_DIR, { recursive: true });
  const out = path.join(FIXTURES_DIR, name + '.json');
  fs.writeFileSync(out, JSON.stringify(fixture, null, 2) + '\n');
  return out;
}

// ---------------------------------------------------------------------------
// Option-file loading.  An option file is a JSON with shape:
//   { "description": "...", "option": { ...echarts option... } }
// (a bare echarts option object is also accepted).
// ---------------------------------------------------------------------------

function loadOptionFile(file) {
  const raw = JSON.parse(fs.readFileSync(file, 'utf8'));
  if (raw && raw.option) return { option: raw.option, meta: { description: raw.description } };
  return { option: raw, meta: {} };
}

// ---------------------------------------------------------------------------
// main
// ---------------------------------------------------------------------------

function main() {
  const args = process.argv.slice(2);
  let jobs = [];

  if (args.length >= 2 && args[0].endsWith('.json')) {
    // arbitrary option file + explicit name
    jobs.push({ name: args[1], file: path.resolve(args[0]) });
  } else if (args.length === 1) {
    // single named option from Oracle/options/<name>.json
    jobs.push({ name: args[0], file: path.join(OPTIONS_DIR, args[0] + '.json') });
  } else {
    // every Oracle/options/*.json
    const files = fs.existsSync(OPTIONS_DIR)
      ? fs.readdirSync(OPTIONS_DIR).filter((f) => f.endsWith('.json'))
      : [];
    jobs = files.map((f) => ({ name: f.replace(/\.json$/, ''), file: path.join(OPTIONS_DIR, f) }));
  }

  if (jobs.length === 0) {
    console.error('No option files found in ' + OPTIONS_DIR);
    process.exit(1);
  }

  for (const job of jobs) {
    if (!fs.existsSync(job.file)) {
      console.error('Missing option file: ' + job.file);
      process.exitCode = 1;
      continue;
    }
    const { option, meta } = loadOptionFile(job.file);
    const fixture = buildFixture(job.name, option, meta);
    const out = writeFixture(job.name, fixture);
    console.log(
      `wrote ${path.relative(ROOT, out)}  ` +
      `(${fixture.elements.length} element(s), ${fixture.svgPaths.length} svg path(s))`
    );
  }

  // ECharts may leave timers; exit explicitly so the harness returns promptly.
  process.exit(process.exitCode || 0);
}

main();
