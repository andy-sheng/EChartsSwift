// official-map-usa-projection — replica of https://echarts.apache.org/examples/zh/editor.html?c=map-usa-projection
// title: USA Choropleth Map with Projection / titleCN: 自定义地图投影
// The 2012 US census population choropleth, drawn through a CUSTOM PROJECTION: the series' `projection`
// hands echarts d3-geo's `geoAlbersUsa()` (project + unproject), the composite conic-equal-area
// projection that folds Alaska (0.35× scale) and Hawaii into insets under the lower-48.
//
// DEVIATIONS from the official source:
//   - DATA INLINED / registerMap MOVED OUT. Upstream fetches the map inside
//     `$.when($.get(ROOT_PATH + '/data/asset/geo/USA.json'), ...).done(function (res) { const usaJson =
//     res[0]; ... echarts.registerMap('USA', usaJson); ... })`. The page has no network, so the GeoJSON
//     (assets/geo/USA.json, the upstream asset byte-for-byte) is declared in `mapRegistrations` —
//     WebPage.swift injects `echarts.registerMap('USA', ...)` into the page before the option script, and
//     the native pane registers the same GeoJSON. `usaJson` and the registerMap call therefore drop out
//     of the JS and the `.done` CALLBACK BODY runs at the top level; everything else in it is verbatim
//     (`showLoading` / `hideLoading` / `myChart.setOption(option)` included).
//   - CDN SCRIPTS VENDORED. The example's other two fetches are `$.getScript(CDN_PATH +
//     'd3-array@2.8.0/dist/d3-array.js')` and `$.getScript(CDN_PATH + 'd3-geo@2.0.1/dist/d3-geo.js')` —
//     `d3.geoAlbersUsa` IS the example. Both dists are mirrored into assets/lib/ and spliced verbatim
//     into the head of webOptionJS (their UMD wrappers publish the same `d3` global the CDN scripts do),
//     so the web pane runs the REAL d3-geo.
//   - NATIVE PROJECTION PORTED, NOT DROPPED. `projection: { project(p) { return projection(p); },
//     unproject(p) { return projection.invert(p); } }` is a pair of JS closures — but they are only a
//     thin wrapper around d3's projection, and EChartsKit reads `projection` as a `GeoProjection` object
//     (`project` / `unproject`), not as a function. So instead of omitting the key, d3-geo v2.0.1's
//     `geoAlbersUsa` is PORTED to Swift below (`AlbersUsaProjection`) and handed to the native pane —
//     same three sub-projections, same parallels / rotations / scales / clip extents, verified by
//     round-trip (≈1e-14) and by the canonical 960×500 layout it produces.
//   - NATIVE MAP NAME. `ECharts.registerMap` is a process-wide registry shared by every demo in the
//     gallery, and `official-map-usa` / `map-bar-morph` register 'USA' WITH `specialAreas` (they have no
//     projection, so they relocate Alaska/Hawaii/PR by hand). This example needs the RAW GeoJSON —
//     albersUsa does the relocation itself — so the native pane registers it under 'USA_projection' and
//     the native option's `map` names that. The web pane keeps the upstream 'USA' (its page is its own).
//     Geometry and rendering are identical; only the registry key differs.
//   - Puerto Rico is dropped by geoAlbersUsa (it falls outside all three clip extents, so `project`
//     returns null) — on BOTH panes, exactly as on the official example page. Its datum stays in `data`,
//     verbatim.
import Foundation
import EChartsKit

// MARK: - assets (the upstream /data/asset/geo/USA.json + the two vendored CDN scripts)

/// The USA states GeoJSON (50 states + DC + Puerto Rico), read from the repo asset. A parse failure
/// degrades to an empty FeatureCollection (blank pane rather than a crash).
private let mapUSAProjectionGeoJSON: [String: Any] = {
    let url = Upstream.repoRoot.appendingPathComponent("assets/geo/USA.json")
    guard let data = try? Data(contentsOf: url),
          let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
        return ["type": "FeatureCollection", "features": [] as [Any]]
    }
    return obj
}()

/// d3-array@2.8.0 + d3-geo@2.0.1 (the exact dists the example `$.getScript`s), spliced into the page.
/// Order matters: d3-geo's UMD factory reads d3-array's exports off the shared `d3` global.
private let mapUSAProjectionD3JS: String = {
    func read(_ rel: String) -> String {
        let url = Upstream.repoRoot.appendingPathComponent(rel)
        return (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    }
    return read("assets/lib/d3-array.js") + "\n" + read("assets/lib/d3-geo.js")
}()

/// The name the NATIVE pane registers the raw (unrelocated) USA GeoJSON under — see the header's
/// "NATIVE MAP NAME" deviation. The web pane uses upstream's 'USA'.
private let mapUSAProjectionMapName = "USA_projection"

// MARK: - d3.geoAlbersUsa(), ported (d3-geo v2.0.1)

private let d3Epsilon = 1e-6
private let d3Radians = Double.pi / 180
private let d3Degrees = 180 / Double.pi
private let d3Tau = 2 * Double.pi

/// Math.sign
private func d3Sign(_ x: Double) -> Double { x > 0 ? 1 : (x < 0 ? -1 : 0) }

/// One conic-equal-area projection with the setters albersUsa uses — `rotate([λ, 0])`, `center`,
/// `parallels`, `scale`, `translate`, `clipExtent`. Point flow (d3's stream pipeline, collapsed to the
/// single-point case): degrees → rotate → conicEqualAreaRaw → scaleTranslate → clipRectangle.
private final class ConicEqualAreaProjection {
    // conicEqualAreaRaw(y0, y1). The |n| < ε fallback (cylindricalEqualAreaRaw, parallels symmetric about
    // the Equator) is unreachable for the three pairs albersUsa uses — [29.5,45.5], [55,65], [8,18].
    private let n: Double
    private let c: Double
    private let r0: Double
    private let deltaLambda: Double                                  // rotate([λ, 0]), radians
    private let k: Double                                            // scale
    private let dx: Double                                           // scaleTranslate offsets, post-recenter()
    private let dy: Double
    private let clip: (x0: Double, y0: Double, x1: Double, y1: Double)   // clipExtent (postclip)

    init(parallels: (Double, Double), rotateLambda: Double, center: (Double, Double),
         scale: Double, translate: (Double, Double),
         clipExtent: (Double, Double, Double, Double)) {
        let y0 = parallels.0 * d3Radians
        let y1 = parallels.1 * d3Radians
        let sy0 = sin(y0)
        let nn = (sy0 + sin(y1)) / 2
        let cc = 1 + sy0 * (2 * nn - sy0)
        let rr0 = cc.squareRoot() / nn
        self.n = nn
        self.c = cc
        self.r0 = rr0
        self.deltaLambda = rotateLambda.truncatingRemainder(dividingBy: 360) * d3Radians
        self.k = scale
        // recenter(): center = scaleTranslate(k, 0, 0)(project(λc, φc)) = [k·px, -k·py], and the live
        // transform is scaleTranslate(k, x - center[0], y - center[1]). The center is in the ROTATED
        // frame (d3 applies `project` to it directly, without the rotation).
        let p = ConicEqualAreaProjection.raw(center.0 * d3Radians, center.1 * d3Radians, nn, cc, rr0)
        self.dx = translate.0 - scale * p.0
        self.dy = translate.1 + scale * p.1
        self.clip = clipExtent
    }

    // function project(x, y) { var r = sqrt(c - 2 * n * sin(y)) / n; return [r * sin(x *= n), r0 - r * cos(x)]; }
    private static func raw(_ x: Double, _ y: Double,
                            _ n: Double, _ c: Double, _ r0: Double) -> (Double, Double) {
        let r = (c - 2 * n * sin(y)).squareRoot() / n
        let xn = x * n
        return (r * sin(xn), r0 - r * cos(xn))
    }

    // project.invert(x, y)
    private static func rawInvert(_ x: Double, _ y: Double,
                                  _ n: Double, _ c: Double, _ r0: Double) -> (Double, Double) {
        let r0y = r0 - y
        var l = atan2(x, abs(r0y)) * d3Sign(r0y)
        if r0y * n < 0 {
            l -= Double.pi * d3Sign(x) * d3Sign(r0y)
        }
        return (l / n, asin((c - (x * x + r0y * r0y) * n * n) / (2 * n)))
    }

    /// nil = the point falls outside this sub-projection's clipExtent (d3's clipRectangle emits nothing,
    /// which is what makes albersUsa's lower48 → alaska → hawaii `||` chain pick a region).
    func forward(_ lon: Double, _ lat: Double) -> [Double]? {
        // forwardRotationLambda: λ += Δλ, wrapped into (-π, π].
        var lambda = lon * d3Radians + deltaLambda
        if lambda > Double.pi { lambda -= d3Tau }
        else if lambda < -Double.pi { lambda += d3Tau }
        let p = ConicEqualAreaProjection.raw(lambda, lat * d3Radians, n, c, r0)
        let x = dx + k * p.0
        let y = dy - k * p.1
        guard x.isFinite, y.isFinite else { return nil }
        guard clip.x0 <= x, x <= clip.x1, clip.y0 <= y, y <= clip.y1 else { return nil }
        return [x, y]
    }

    /// d3's `projection.invert` ignores the postclip rectangle — albersUsa picks the sub-projection
    /// itself, from the normalized coordinates.
    func invert(_ x: Double, _ y: Double) -> [Double]? {
        let p = ConicEqualAreaProjection.rawInvert((x - dx) / k, (dy - y) / k, n, c, r0)
        guard p.0.isFinite, p.1.isFinite else { return nil }   // asin out of domain → NaN in JS too
        var lambda = p.0 - deltaLambda
        if lambda > Double.pi { lambda -= d3Tau }
        else if lambda < -Double.pi { lambda += d3Tau }
        return [lambda * d3Degrees, p.1 * d3Degrees]
    }
}

/// d3.geoAlbersUsa() at its default scale(1070) / translate([480, 250]) — the composite projection the
/// example builds. Conforms to EChartsKit's `GeoProjection`, i.e. it IS the `projection` option value.
private final class AlbersUsaProjection: GeoProjection {
    private let lower48: ConicEqualAreaProjection
    private let alaska: ConicEqualAreaProjection
    private let hawaii: ConicEqualAreaProjection
    // lower48's scale / translate. `albersUsa.invert` reads them back off lower48 (`var k =
    // lower48.scale(), t = lower48.translate()`), so they must be the SAME values `init` laid the three
    // sub-projections out with — kept here as the single source of truth rather than re-typed in
    // `unproject` (where a drifting copy would silently desync invert from project).
    private let k: Double
    private let tx: Double
    private let ty: Double

    init() {
        // albersUsa.scale(1070) → lower48.scale(1070), alaska.scale(1070 * 0.35), hawaii.scale(1070);
        // albersUsa.translate([480, 250]) → the three translates + clipExtents below.
        let k = 1070.0, x = 480.0, y = 250.0, e = d3Epsilon
        self.k = k; self.tx = x; self.ty = y
        // albers(): parallels([29.5, 45.5]).rotate([96, 0]).center([-0.6, 38.7])
        lower48 = ConicEqualAreaProjection(
            parallels: (29.5, 45.5), rotateLambda: 96, center: (-0.6, 38.7),
            scale: k, translate: (x, y),
            clipExtent: (x - 0.455 * k, y - 0.238 * k, x + 0.455 * k, y + 0.238 * k))
        // EPSG:3338
        alaska = ConicEqualAreaProjection(
            parallels: (55, 65), rotateLambda: 154, center: (-2, 58.5),
            scale: k * 0.35, translate: (x - 0.307 * k, y + 0.201 * k),
            clipExtent: (x - 0.425 * k + e, y + 0.120 * k + e, x - 0.214 * k - e, y + 0.234 * k - e))
        // ESRI:102007
        hawaii = ConicEqualAreaProjection(
            parallels: (8, 18), rotateLambda: 157, center: (-3, 19.9),
            scale: k, translate: (x - 0.205 * k, y + 0.212 * k),
            clipExtent: (x - 0.214 * k + e, y + 0.166 * k + e, x - 0.115 * k - e, y + 0.234 * k - e))
    }

    // return (lower48Point.point(x, y), point) || (alaskaPoint.point(x, y), point) || (hawaiiPoint.point(x, y), point);
    func project(_ point: [Double]) -> [Double]? {
        guard point.count >= 2 else { return nil }
        return lower48.forward(point[0], point[1])
            ?? alaska.forward(point[0], point[1])
            ?? hawaii.forward(point[0], point[1])
    }

    // albersUsa.invert: pick the sub-projection from the lower48-normalized pixel coordinates.
    //   var k = lower48.scale(), t = lower48.translate(),
    //       x = (coordinates[0] - t[0]) / k, y = (coordinates[1] - t[1]) / k;
    func unproject(_ point: [Double]) -> [Double]? {
        guard point.count >= 2 else { return nil }
        let x = (point[0] - tx) / k
        let y = (point[1] - ty) / k
        let target: ConicEqualAreaProjection
        if y >= 0.120 && y < 0.234 && x >= -0.425 && x < -0.214 { target = alaska }
        else if y >= 0.166 && y < 0.234 && x >= -0.214 && x < -0.115 { target = hawaii }
        else { target = lower48 }
        return target.invert(point[0], point[1])
    }
}

private let mapUSAProjectionAlbers = AlbersUsaProjection()

// MARK: - data (2012 US Census population estimates, verbatim)

private let mapUSAProjectionData: [[String: Any]] = [
    ["name": "Alabama", "value": 4822023.0], ["name": "Alaska", "value": 731449.0],
    ["name": "Arizona", "value": 6553255.0], ["name": "Arkansas", "value": 2949131.0],
    ["name": "California", "value": 38041430.0], ["name": "Colorado", "value": 5187582.0],
    ["name": "Connecticut", "value": 3590347.0], ["name": "Delaware", "value": 917092.0],
    ["name": "District of Columbia", "value": 632323.0], ["name": "Florida", "value": 19317568.0],
    ["name": "Georgia", "value": 9919945.0], ["name": "Hawaii", "value": 1392313.0],
    ["name": "Idaho", "value": 1595728.0], ["name": "Illinois", "value": 12875255.0],
    ["name": "Indiana", "value": 6537334.0], ["name": "Iowa", "value": 3074186.0],
    ["name": "Kansas", "value": 2885905.0], ["name": "Kentucky", "value": 4380415.0],
    ["name": "Louisiana", "value": 4601893.0], ["name": "Maine", "value": 1329192.0],
    ["name": "Maryland", "value": 5884563.0], ["name": "Massachusetts", "value": 6646144.0],
    ["name": "Michigan", "value": 9883360.0], ["name": "Minnesota", "value": 5379139.0],
    ["name": "Mississippi", "value": 2984926.0], ["name": "Missouri", "value": 6021988.0],
    ["name": "Montana", "value": 1005141.0], ["name": "Nebraska", "value": 1855525.0],
    ["name": "Nevada", "value": 2758931.0], ["name": "New Hampshire", "value": 1320718.0],
    ["name": "New Jersey", "value": 8864590.0], ["name": "New Mexico", "value": 2085538.0],
    ["name": "New York", "value": 19570261.0], ["name": "North Carolina", "value": 9752073.0],
    ["name": "North Dakota", "value": 699628.0], ["name": "Ohio", "value": 11544225.0],
    ["name": "Oklahoma", "value": 3814820.0], ["name": "Oregon", "value": 3899353.0],
    ["name": "Pennsylvania", "value": 12763536.0], ["name": "Rhode Island", "value": 1050292.0],
    ["name": "South Carolina", "value": 4723723.0], ["name": "South Dakota", "value": 833354.0],
    ["name": "Tennessee", "value": 6456243.0], ["name": "Texas", "value": 26059203.0],
    ["name": "Utah", "value": 2855287.0], ["name": "Vermont", "value": 626011.0],
    ["name": "Virginia", "value": 8185867.0], ["name": "Washington", "value": 6897012.0],
    ["name": "West Virginia", "value": 1855413.0], ["name": "Wisconsin", "value": 5726398.0],
    ["name": "Wyoming", "value": 576412.0], ["name": "Puerto Rico", "value": 3667084.0]
]

private let mapUSAProjectionColors: [String] = [
    "#313695", "#4575b4", "#74add1", "#abd9e9", "#e0f3f8", "#ffffbf",
    "#fee090", "#fdae61", "#f46d43", "#d73027", "#a50026"
]

extension EChartsDemoRegistry {
    static let official_map_usa_projection = EChartsDemo(
        name: "official-map-usa-projection", category: "map",
        summary: "自定义地图投影 — USA Choropleth Map with Projection",
        width: 720, height: 460,
        nativeSupported: true,
        // Upstream's `echarts.registerMap('USA', usaJson)` for the web pane, injected before the option
        // script (the native pane registers the same GeoJSON under 'USA_projection' — see the header).
        mapRegistrations: ["USA": mapUSAProjectionGeoJSON],
        collection: .official,
        webOptionJS: #"""
// $.getScript(CDN_PATH + 'd3-array@2.8.0/dist/d3-array.js') + $.getScript(CDN_PATH + 'd3-geo@2.0.1/dist/
// d3-geo.js') — the page has no network, so the two dists (assets/lib/) are spliced in verbatim. Their
// UMD wrappers publish the same `d3` global (and `d3.geoAlbersUsa`) the CDN scripts do.
\#(mapUSAProjectionD3JS)

myChart.showLoading();

// $.when($.get(ROOT_PATH + '/data/asset/geo/USA.json'), <the two d3 scripts above>).done(function (res) {
//   const usaJson = res[0]; ... echarts.registerMap('USA', usaJson); ... });
// The GeoJSON is registered into this page by the gallery (mapRegistrations), so the fetch, `usaJson` and
// the registerMap call drop out; the .done CALLBACK BODY runs at the top level, otherwise verbatim.

const projection = d3.geoAlbersUsa();

myChart.hideLoading();

option = {
  title: {
    text: 'USA Population Estimates (2012)',
    subtext: 'Data from www.census.gov',
    sublink: 'http://www.census.gov/popest/data/datasets.html',
    left: 'right'
  },
  tooltip: {
    trigger: 'item',
    showDelay: 0,
    transitionDuration: 0.2
  },
  visualMap: {
    left: 'right',
    min: 500000,
    max: 38000000,
    inRange: {
      color: [
        '#313695',
        '#4575b4',
        '#74add1',
        '#abd9e9',
        '#e0f3f8',
        '#ffffbf',
        '#fee090',
        '#fdae61',
        '#f46d43',
        '#d73027',
        '#a50026'
      ]
    },
    text: ['High', 'Low'], // 文本，默认为数值文本
    calculable: true
  },
  toolbox: {
    show: true,
    //orient: 'vertical',
    left: 'left',
    top: 'top',
    feature: {
      dataView: { readOnly: false },
      restore: {},
      saveAsImage: {}
    }
  },
  series: [
    {
      name: 'USA PopEstimates',
      type: 'map',
      map: 'USA',
      projection: {
        project: function (point) {
          return projection(point);
        },
        unproject: function (point) {
          return projection.invert(point);
        }
      },
      emphasis: {
        label: {
          show: true
        }
      },
      data: [
        { name: 'Alabama', value: 4822023 },
        { name: 'Alaska', value: 731449 },
        { name: 'Arizona', value: 6553255 },
        { name: 'Arkansas', value: 2949131 },
        { name: 'California', value: 38041430 },
        { name: 'Colorado', value: 5187582 },
        { name: 'Connecticut', value: 3590347 },
        { name: 'Delaware', value: 917092 },
        { name: 'District of Columbia', value: 632323 },
        { name: 'Florida', value: 19317568 },
        { name: 'Georgia', value: 9919945 },
        { name: 'Hawaii', value: 1392313 },
        { name: 'Idaho', value: 1595728 },
        { name: 'Illinois', value: 12875255 },
        { name: 'Indiana', value: 6537334 },
        { name: 'Iowa', value: 3074186 },
        { name: 'Kansas', value: 2885905 },
        { name: 'Kentucky', value: 4380415 },
        { name: 'Louisiana', value: 4601893 },
        { name: 'Maine', value: 1329192 },
        { name: 'Maryland', value: 5884563 },
        { name: 'Massachusetts', value: 6646144 },
        { name: 'Michigan', value: 9883360 },
        { name: 'Minnesota', value: 5379139 },
        { name: 'Mississippi', value: 2984926 },
        { name: 'Missouri', value: 6021988 },
        { name: 'Montana', value: 1005141 },
        { name: 'Nebraska', value: 1855525 },
        { name: 'Nevada', value: 2758931 },
        { name: 'New Hampshire', value: 1320718 },
        { name: 'New Jersey', value: 8864590 },
        { name: 'New Mexico', value: 2085538 },
        { name: 'New York', value: 19570261 },
        { name: 'North Carolina', value: 9752073 },
        { name: 'North Dakota', value: 699628 },
        { name: 'Ohio', value: 11544225 },
        { name: 'Oklahoma', value: 3814820 },
        { name: 'Oregon', value: 3899353 },
        { name: 'Pennsylvania', value: 12763536 },
        { name: 'Rhode Island', value: 1050292 },
        { name: 'South Carolina', value: 4723723 },
        { name: 'South Dakota', value: 833354 },
        { name: 'Tennessee', value: 6456243 },
        { name: 'Texas', value: 26059203 },
        { name: 'Utah', value: 2855287 },
        { name: 'Vermont', value: 626011 },
        { name: 'Virginia', value: 8185867 },
        { name: 'Washington', value: 6897012 },
        { name: 'West Virginia', value: 1855413 },
        { name: 'Wisconsin', value: 5726398 },
        { name: 'Wyoming', value: 576412 },
        { name: 'Puerto Rico', value: 3667084 }
      ]
    }
  ]
};

myChart.setOption(option);
"""#,
        option: {
            // Upstream `echarts.registerMap('USA', usaJson)` (raw GeoJSON — albersUsa relocates Alaska /
            // Hawaii itself, so there are no specialAreas here). Registered under 'USA_projection': the
            // native map registry is process-global and official-map-usa / map-bar-morph own 'USA'.
            ECharts.registerMap(mapUSAProjectionMapName, mapUSAProjectionGeoJSON)
            return [
                "title": [
                    "text": "USA Population Estimates (2012)",
                    "subtext": "Data from www.census.gov",
                    "sublink": "http://www.census.gov/popest/data/datasets.html",
                    "left": "right"
                ] as [String: Any],
                "tooltip": [
                    "trigger": "item",
                    "showDelay": 0.0,
                    "transitionDuration": 0.2
                ] as [String: Any],
                "visualMap": [
                    "left": "right",
                    "min": 500000.0,
                    "max": 38000000.0,
                    "inRange": [
                        "color": mapUSAProjectionColors
                    ] as [String: Any],
                    "text": ["High", "Low"],
                    "calculable": true
                ] as [String: Any],
                "toolbox": [
                    "show": true,
                    "left": "left",
                    "top": "top",
                    "feature": [
                        "dataView": ["readOnly": false] as [String: Any],
                        "restore": [:] as [String: Any],
                        "saveAsImage": [:] as [String: Any]
                    ] as [String: Any]
                ] as [String: Any],
                "series": [
                    [
                        "name": "USA PopEstimates",
                        "type": "map",
                        "map": mapUSAProjectionMapName,
                        // The example's `{ project, unproject }` closures wrap d3.geoAlbersUsa(); EChartsKit
                        // takes the projection as a GeoProjection object, so the Swift port goes in directly.
                        "projection": mapUSAProjectionAlbers,
                        "emphasis": [
                            "label": ["show": true] as [String: Any]
                        ] as [String: Any],
                        "data": mapUSAProjectionData as [Any]
                    ] as [String: Any]
                ]
            ]
        }())
}
