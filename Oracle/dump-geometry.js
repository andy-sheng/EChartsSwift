#!/usr/bin/env node
/*
 * Oracle/dump-geometry.js
 *
 * A SECOND golden-test oracle, sibling to dump-displaylist.js.
 *
 * Where dump-displaylist.js drives ECharts SSR (option -> sorted display list) to pin
 * the *path command stream*, this generator drives the low-level **zrender shape geometry
 * API** directly (the same surface the algorithm-class `test/*.html` demos exercise but
 * never assert on) and records the two renderer-independent, deterministic outputs that
 * those demos only ever showed to a human's eyes:
 *
 *   - `boundingRect`  : shape.getBoundingRect()  -> {x, y, width, height}
 *                       (boundingbox.html / sector.html — exercises arc + cubic-extrema math)
 *   - `contain`       : shape.contain(x, y) over a fixed grid of probe points -> [bool]
 *                       (pathContain.html / poly.html — exercises fill hit-testing)
 *
 * It loads the *real* zrender from the UMD bundle the .html demos themselves load
 * (`upstream/zrender/dist/zrender.js`), so the recorded numbers are ground truth.
 *
 * Output: Oracle/fixtures/geometry.json   (consumed by Tests/.../GeometryGoldenTests.swift)
 *
 * Usage:
 *   node dump-geometry.js
 *
 * NOTE: this writes ONLY fixtures (test data). It does not touch Sources/. The Swift port
 * is "correct" iff its ported Sector/Circle/Ring/Ellipse/Polygon/BezierCurve reproduce
 * these getBoundingRect + contain results.
 */

'use strict';

const fs = require('fs');
const path = require('path');

const ROOT = path.join(__dirname);
const ZR_UMD = path.join(ROOT, '..', 'upstream', 'zrender', 'dist', 'zrender.js');
const FIXTURES_DIR = path.join(ROOT, 'fixtures');
const OUT = path.join(FIXTURES_DIR, 'geometry.json');

const PRECISION = 6;
// Probe grid: every GRID_STEP px across a CANVAS_W x CANVAS_H field. Dense enough to make
// the contain[] signature a meaningful hit-test fingerprint that diverges on any bug.
const CANVAS_W = 200;
const CANVAS_H = 150;
const GRID_STEP = 10;

function round(n) {
  if (typeof n !== 'number' || !isFinite(n)) return n;
  let r = Math.round(n * 1e6) / 1e6;
  if (Object.is(r, -0)) r = 0;
  return r;
}

function loadZRender() {
  if (!fs.existsSync(ZR_UMD)) {
    console.error('Missing zrender UMD bundle at: ' + ZR_UMD);
    process.exit(1);
  }
  const zr = require(ZR_UMD);
  // The demos run in a browser; under node there is no <canvas>. None of the shapes we
  // probe need a 2d context for getBoundingRect / fill-contain, but stub createCanvas so
  // any incidental measureText path cannot throw.
  if (typeof zr.setPlatformAPI === 'function') {
    zr.setPlatformAPI({ createCanvas: function () { return null; } });
  }
  return zr;
}

const zr = loadZRender();

// ---------------------------------------------------------------------------
// Cases — each mirrors a specific algorithm-class .html demo. `make` returns a
// constructed zrender shape; `shape` is the literal prop bag the Swift test must
// reconstruct verbatim into the matching Swift *Shape struct.
// ---------------------------------------------------------------------------

const CASES = [
  {
    name: 'sector',
    demo: 'sector.html / pathContain.html',
    type: 'Sector',
    shape: { cx: 100, cy: 75, r0: 20, r: 60, startAngle: 0, endAngle: Math.PI / 2, clockwise: true },
    make: (s) => new zr.Sector({ shape: s })
  },
  {
    name: 'circle',
    demo: 'event.html (Circle hit-test)',
    type: 'Circle',
    shape: { cx: 100, cy: 75, r: 50 },
    make: (s) => new zr.Circle({ shape: s })
  },
  {
    name: 'ring',
    demo: 'fullSector.html (annulus)',
    type: 'Ring',
    shape: { cx: 100, cy: 75, r: 60, r0: 30 },
    make: (s) => new zr.Ring({ shape: s })
  },
  {
    name: 'ellipse',
    demo: 'boundingbox.html (ellipse extents)',
    type: 'Ellipse',
    shape: { cx: 100, cy: 75, rx: 70, ry: 40 },
    make: (s) => new zr.Ellipse({ shape: s })
  },
  {
    name: 'polygon',
    demo: 'poly.html',
    type: 'Polygon',
    shape: { points: [[100, 15], [165, 60], [140, 135], [60, 135], [35, 60]] }, // pentagon
    make: (s) => new zr.Polygon({ shape: s })
  },
  {
    name: 'bezier',
    demo: 'bezier.html / boundingbox.html (cubic extrema)',
    type: 'BezierCurve',
    shape: { x1: 20, y1: 120, cpx1: 60, cpy1: 0, cpx2: 140, cpy2: 150, x2: 180, y2: 30 },
    make: (s) => new zr.BezierCurve({ shape: s })
  }
];

function probeGrid(shapeObj) {
  const samples = [];
  for (let y = 0; y <= CANVAS_H; y += GRID_STEP) {
    for (let x = 0; x <= CANVAS_W; x += GRID_STEP) {
      samples.push({ x, y, inside: !!shapeObj.contain(x, y) });
    }
  }
  return samples;
}

function rectOf(r) {
  return { x: round(r.x), y: round(r.y), width: round(r.width), height: round(r.height) };
}

function buildCase(c) {
  const obj = c.make(c.shape);

  // Two rects, on purpose:
  //  - pathRect    : PathProxy.getBoundingRect() — pure, style-independent path geometry.
  //                  This is the faithful cross-language oracle (same philosophy as
  //                  GoldenTests' path-command stream): no renderer/style policy mixed in.
  //  - styledRect  : shape.getBoundingRect() — what the .html `getBoundingRect()` shows.
  //                  For fill shapes this equals pathRect; for a *stroke-only* shape
  //                  (BezierCurve/Line/Polyline) zrender inflates it by
  //                  max(lineWidth, strokeContainThreshold=5)/2 — a style policy, recorded
  //                  here for reference but NOT used as the geometry assertion.
  const pp = (typeof obj.getUpdatedPathProxy === 'function') ? obj.getUpdatedPathProxy() : null;
  const pathRect = pp && pp.getBoundingRect ? rectOf(pp.getBoundingRect()) : null;

  return {
    name: c.name,
    demo: c.demo,
    type: c.type,
    shape: c.shape,
    pathRect: pathRect,
    styledRect: rectOf(obj.getBoundingRect()),
    hasFill: typeof obj.hasFill === 'function' ? !!obj.hasFill() : null,
    hasStroke: typeof obj.hasStroke === 'function' ? !!obj.hasStroke() : null,
    grid: { step: GRID_STEP, width: CANVAS_W, height: CANVAS_H },
    contain: probeGrid(obj)
  };
}

function main() {
  if (!fs.existsSync(FIXTURES_DIR)) fs.mkdirSync(FIXTURES_DIR, { recursive: true });
  const fixture = {
    generator: 'Oracle/dump-geometry.js',
    source: 'upstream/zrender/dist/zrender.js',
    zrenderVersion: zr.version,
    precision: PRECISION,
    cases: CASES.map(buildCase)
  };
  fs.writeFileSync(OUT, JSON.stringify(fixture, null, 2) + '\n');
  const insideCounts = fixture.cases
    .map((c) => `${c.name}:${c.contain.filter((p) => p.inside).length}/${c.contain.length}`)
    .join('  ');
  console.log('wrote ' + path.relative(ROOT, OUT));
  console.log('  zrender ' + zr.version + '  inside-probes: ' + insideCounts);
}

main();
