// official-lines-ny — replica of https://echarts.apache.org/examples/zh/editor.html?c=lines-ny
// title: Use lines to draw 1 million New York streets / titleCN: 使用线图绘制近100万纽约街道数据
// New York's street network as a single `lines` series on a `geo` world map, zoomed to 360x on
// (-74.043, 40.867): 624,407 polylines / 2,717,611 points, streamed in as 32 binary chunks and drawn in
// `polyline: true` + `large: true` + `progressive: 20000` mode with a 0.5px, 0.3-opacity orange hairline
// and `blendMode: 'lighter'`, so the street density burns in where strokes pile up on the near-black
// (#111) canvas. The wire format is a flat, count-prefixed coordinate stream —
// `Points Count(2) | x | y | x | y | Points Count(3) | x | y | ...` — which echarts' lines series reads
// directly (`dimensions: ['value']`, `data: Float64Array`).
//
// DEVIATIONS from the official source:
//   - DATA INLINED. Upstream XHRs 32 chunks, `ROOT_PATH + '/data/asset/data/links-ny/links_ny_<i>.bin'`,
//     as ArrayBuffers. The gallery page has no network, so the SAME 32 files (23 MB total) are vendored
//     at assets/data/links-ny/ (read via Upstream.repoRoot, as map-bar-morph does) and reach the panes
//     as: base64 → atob → Float32Array per chunk in webOptionJS (byte-identical to what each XHR
//     returned), and a Swift Float32 decode for the native pane. No street is dropped: the whole 1M-ish
//     street set is on both panes.
//   - WEB PANE ORDERING. The `fetchData(idx)` recursion, its Float32→Float64 unpack loop (per-chunk
//     `offsetX`/`offsetY` re-added to every point), its `myChart.appendData({ seriesIndex: 0, data })`
//     and the `dataCount` tally are all kept VERBATIM — only the XHR is swapped for the in-page base64
//     decode. That decode is synchronous, where the XHRs were async: upstream's chunks therefore landed
//     AFTER the editor had applied `option`, so the page must now apply it itself
//     (`myChart.setOption(option)` before `fetchData(0)`) or `appendData` would find no series. The
//     `var xhr` / `xhr.open` / `xhr.send` lines and the trailing `export {}` are dropped; the TS
//     annotation `fetchData(idx: number)` is dropped (a classic script cannot parse it).
//   - NATIVE PANE: the static `option` carries the complete concatenated stream so headless stable-frame
//     rendering stays deterministic. Its `liveOption` starts with the same empty series as Web, then
//     `drive` replays all 32 `appendData` calls one chunk per run-loop turn. This preserves both the
//     official progressive build-up and the stable screenshot without first constructing the full live
//     display list and immediately throwing it away.
//   - MAP REGISTRATION: the example registers nothing — the official editor auto-injects the map named
//     by `geo.map: 'world'`. We must be explicit: assets/geo/world.json goes to BOTH panes via
//     `mapRegistrations` (WebPage.swift injects `echarts.registerMap('world', ...)` ahead of the option
//     script; the native pane registers the same GeoJSON). Same as official-lines-airline.
//   - `geo.roam: true` is interactive; the still-frame render shows the initial 360x view on both panes.
// Everything else (progressive, backgroundColor, geo center/zoom/silent/itemStyle, and the whole lines
// series incl. blendMode/dimensions/polyline/large/lineStyle) is carried verbatim by both panes.
import Foundation
import EChartsKit

// The world map GeoJSON, parsed ONCE from the repo asset (the map `geo.map: 'world'` names).
private let linesNYWorldGeoJSON: [String: Any] = {
    let url = Upstream.repoRoot.appendingPathComponent("assets/geo/world.json")
    guard let data = try? Data(contentsOf: url),
          let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
        return ["type": "FeatureCollection", "features": [] as [Any]]
    }
    return obj
}()

// upstream: var CHUNK_COUNT = 32;  — links_ny_0.bin … links_ny_31.bin, vendored byte for byte.
private let linesNYChunkCount = 32

// A FUNCTION, not a `let`: 23 MB of chunk bytes that both builders below consume ONCE, at this demo's
// static init. As a lazy global it would be retained for the life of the process on top of the two
// derived copies; as a function each call's buffer is freed as soon as its builder returns.
private func linesNYChunkBinaries() -> [Data] {
    return (0..<linesNYChunkCount).map { idx in
        let url = Upstream.repoRoot
            .appendingPathComponent("assets/data/links-ny/links_ny_\(idx).bin")
        return (try? Data(contentsOf: url)) ?? Data()  // a missing chunk degrades to "no streets", no crash
    }
}

// The web pane's `LINKS_NY_CHUNKS`: the same 32 ArrayBuffers, base64'd, as a JS array literal body.
// Also a function — its 31 MB is interpolated straight into `webOptionJS` below, so holding a second
// permanent copy in a global would double the cost of the page for nothing.
private func linesNYChunksBase64JS() -> String {
    return linesNYChunkBinaries()
        .map { "'" + $0.base64EncodedString() + "'" }
        .joined(separator: ",\n  ")
}

// The native pane's data: every chunk's `xhr.onload` body, in Swift. Each chunk is a Float32Array whose
// first two values are the chunk's (offsetX, offsetY); the rest is the count-prefixed stream
// `count | x | y | ...` with the offsets SUBTRACTED out, so each point is re-formed as
// `rawData[i] + offsetX` (JS adds the two float32s as doubles — hence the widen-then-add here). The
// per-chunk Float64Arrays that upstream appendData's one by one are concatenated into the single flat
// array the option carries.
private func decodeLinesNYChunk(_ bin: Data) -> [Double] {
    let floatCount = bin.count / MemoryLayout<Float>.size
    guard floatCount > 2 else { return [] }
    var out: [Double] = []
    out.reserveCapacity(floatCount)
        // `new Float32Array(this.response)` — little-endian float32s, memcpy'd out so the file buffer's
        // alignment never matters (same decode as official-scatter-nebula).
    var rawData = [Float](repeating: 0, count: floatCount)
    rawData.withUnsafeMutableBytes { dst in _ = bin.copyBytes(to: dst) }
    let offsetX = Double(rawData[0])
    let offsetY = Double(rawData[1])
    var i = 2
    while i < floatCount {
        // (`Int(_: Float)` traps on NaN/±inf, so a corrupt chunk is stopped at, not crashed on.)
        let rawCount = rawData[i]; i += 1
        guard rawCount.isFinite, rawCount >= 0, rawCount < 1e9 else { break }
        let count = Int(rawCount)
        guard i + 2 * count <= floatCount else { break }               // truncated chunk → stop
        out.append(Double(count))
        for _ in 0..<count {
            out.append(Double(rawData[i]) + offsetX); i += 1
            out.append(Double(rawData[i]) + offsetY); i += 1
        }
    }
    return out
}

private func linesNYDecodedChunk(_ index: Int) -> [Double] {
    let url = Upstream.repoRoot
        .appendingPathComponent("assets/data/links-ny/links_ny_\(index).bin")
    return decodeLinesNYChunk((try? Data(contentsOf: url)) ?? Data())
}

private let linesNYFlatCoords: [Double] = {
    var out: [Double] = []
    out.reserveCapacity(6_100_000)
    for bin in linesNYChunkBinaries() {
        out.append(contentsOf: decodeLinesNYChunk(bin))
    }
    return out
}()

private func linesNYNativeOption(data: [Double]) -> [String: Any] {
    return [
        "progressive": 20000.0,
        "backgroundColor": "#111",
        "geo": [
            "center": [-74.04327099998152, 40.86737600240287],
            "zoom": 360.0,
            "map": "world",
            "roam": true,
            "silent": true,
            "itemStyle": [
                "color": "transparent",
                "borderColor": "rgba(255,255,255,0.1)",
                "borderWidth": 1.0
            ] as [String: Any]
        ] as [String: Any],
        "series": [[
            "type": "lines",
            "coordinateSystem": "geo",
            "blendMode": "lighter",
            "dimensions": ["value"],
            "data": data,
            "polyline": true,
            "large": true,
            "lineStyle": [
                "color": "orange",
                "width": 0.5,
                "opacity": 0.3
            ] as [String: Any]
        ] as [String: Any]]
    ]
}

@MainActor
private func streamLinesNYChunk(_ index: Int, into chart: EChartsDemoChart) {
    guard index < linesNYChunkCount else { return }
    chart.appendData(seriesIndex: 0, data: linesNYDecodedChunk(index))
    if index + 1 < linesNYChunkCount {
        // Wait until a later run-loop turn so the just-appended batch can be presented. This mirrors
        // the asynchronous XHR recursion in the official example instead of appending all chunks in
        // one blocking call that visually collapses the stream into a single frame.
        chart.after(0.03) {
            streamLinesNYChunk(index + 1, into: chart)
        }
    }
}

extension EChartsDemoRegistry {
    static let official_lines_ny = EChartsDemo(
        name: "official-lines-ny", category: "map",
        summary: "使用线图绘制近100万纽约街道数据 — Use lines to draw 1 million New York streets",
        width: 720, height: 460,
        nativeSupported: true,
        mapRegistrations: ["world": linesNYWorldGeoJSON],
        collection: .official,
        webOptionJS: #"""
// The 32 upstream chunks (ROOT_PATH + '/data/asset/data/links-ny/links_ny_<idx>.bin'), inlined as
// base64 — the identical ArrayBuffers the XHRs returned. Everything below is the example, verbatim.
var LINKS_NY_CHUNKS = [
  \#(linesNYChunksBase64JS())
];

var CHUNK_COUNT = 32;

var dataCount = 0;

function fetchData(idx) {
  if (idx >= CHUNK_COUNT) {
    return;
  }
  // Upstream: an XMLHttpRequest for `dataURL` with responseType 'arraybuffer'. Inlined instead — the
  // decoded bytes ARE `this.response`, so the callback body below is unchanged.
  var bin = atob(LINKS_NY_CHUNKS[idx]);
  var bytes = new Uint8Array(bin.length);
  for (var b = 0; b < bin.length; b++) {
    bytes[b] = bin.charCodeAt(b);
  }

  var rawData = new Float32Array(bytes.buffer);
  var data = new Float64Array(rawData.length - 2);
  var offsetX = rawData[0];
  var offsetY = rawData[1];
  var off = 0;
  var addedDataCount = 0;
  for (var i = 2; i < rawData.length; ) {
    var count = rawData[i++];
    data[off++] = count;
    for (var k = 0; k < count; k++) {
      var x = rawData[i++] + offsetX;
      var y = rawData[i++] + offsetY;
      data[off++] = x;
      data[off++] = y;

      addedDataCount++;
    }
  }

  myChart.appendData({
    seriesIndex: 0,
    data: data
  });

  dataCount += addedDataCount;

  fetchData(idx + 1);
}

option = {
  progressive: 20000,
  backgroundColor: '#111',
  geo: {
    center: [-74.04327099998152, 40.86737600240287],
    zoom: 360,
    map: 'world',
    roam: true,
    silent: true,
    itemStyle: {
      color: 'transparent',
      borderColor: 'rgba(255,255,255,0.1)',
      borderWidth: 1
    }
  },
  series: [
    {
      type: 'lines',

      coordinateSystem: 'geo',

      blendMode: 'lighter',

      dimensions: ['value'],

      data: new Float64Array(),
      polyline: true,
      large: true,

      lineStyle: {
        color: 'orange',
        width: 0.5,
        opacity: 0.3
      }
    }
  ]
};

// Upstream's chunks arrived asynchronously, i.e. AFTER the editor had applied `option`; our decode is
// synchronous, so apply it here — appendData needs the series to exist already.
myChart.setOption(option);

fetchData(0);

// The default snapshot delay is intentionally short for ordinary charts, but this example paints
// 624k polylines progressively. Hold the reference capture until ZRender has stopped producing paint
// frames for a short quiet window; walking the heavyweight display list while it is rendering puts
// enough memory pressure on WebKit to terminate the content process.
if (__snapshot) {
  window.__echartsSnapshotReady = false;
  var lastStreetPaint = Date.now();
  myChart.getZr().on('rendered', function () {
    lastStreetPaint = Date.now();
  });
  setTimeout(function waitForStreetPaintToSettle() {
    if (Date.now() - lastStreetPaint < 500) {
      setTimeout(waitForStreetPaintToSettle, 100);
      return;
    }
    window.__echartsSnapshotReady = true;
  }, 500);
}
"""#,
        liveOption: linesNYNativeOption(data: []),
        drive: { chart in
            chart.after(0.03) {
                streamLinesNYChunk(0, into: chart)
            }
        },
        option: {
            // Upstream registers nothing (the editor injects the `world` map); the native pane must.
            ECharts.registerMap("world", linesNYWorldGeoJSON)
            return linesNYNativeOption(data: linesNYFlatCoords)
        }())
}
