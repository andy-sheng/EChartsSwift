// custom-basic — a CUSTOM series on cartesian2d whose `renderItem` closure hand-rolls a bar (one `rect`
// element per datum). Demonstrates the renderItem API: api.value(dim) reads the datum's parsed value,
// api.coord([x,y]) projects data → pixel, api.size([1,0]) gives the pixel span of one x-unit (bar width).
//
// HOW THE CLOSURE IS WIRED (option bags cannot carry a Swift closure through JSONSerialization, which the
// echarts.js comparison pane uses): instead of stuffing the closure into `option["series"][0]["renderItem"]`,
// we register it in the global custom-series registry keyed by the series subType ("custom") via
// registerCustomSeries. CustomChartView resolves the callback as
//   customSeries.getRenderItem() ?? getCustomSeries(subType)
// so the registered closure is picked up while demo.option stays plain JSON. The echarts.js pane cannot
// mirror a native Swift closure, so it renders nothing for this demo (native-only), but the native pane
// draws the hand-rolled bars.
import Foundation
import EChartsKit

// Coerce a ParsedValue (Any: Double | Int | NSNumber) to Double — the recurring Int-vs-Double read trap.
private func customBasicNum(_ v: Any?) -> Double {
    if let d = v as? Double { return d }
    if let i = v as? Int { return Double(i) }
    if let n = v as? NSNumber { return n.doubleValue }
    return 0
}

// The renderItem closure — typed EXACTLY CustomSeriesRenderItem so the registry/getRenderItem cast holds.
private let customBasicRenderItem: CustomSeriesRenderItem = { _, api in
    // dim 0 = x, dim 1 = y for this datum (pass Double dims: SeriesData.getDimensionIndex force-casts a
    //   numeric dim `as! Double`, so an Int dim would crash).
    let x = customBasicNum(api.value(0.0, nil))
    let y = customBasicNum(api.value(1.0, nil))
    // Project to pixels: the bar top (data point) and its base (y = 0).
    let top = api.coord([x, y], nil)
    let base = api.coord([x, 0.0], nil)
    guard top.count >= 2, base.count >= 2 else { return nil }
    // Pixel span of one x-unit → bar width (60% of it).
    let unitWidth = (api.size([1.0, 0.0], nil) as? [Double])?.first ?? 20.0
    let width = unitWidth * 0.6
    // Return a `rect` element spec (the CONVENTIONS §2 [String: Any] element bag).
    return [
        "type": "rect",
        "shape": [
            "x": top[0] - width / 2,
            "y": top[1],
            "width": width,
            "height": base[1] - top[1]
        ] as [String: Any],
        "style": ["fill": "#5470c6"] as [String: Any]
    ] as [String: Any]
}

extension EChartsDemoRegistry {
    // Lazily initialized on first access (before ECharts.setOption reads demo.option) → registers the
    //   closure as a side effect, keeping option JSON-clean.
    static let demo_custom_basic: EChartsDemo = makeCustomBasicDemo()
}

private func makeCustomBasicDemo() -> EChartsDemo {
    registerCustomSeries("custom", customBasicRenderItem)
    return EChartsDemo(
        name: "custom-basic", category: "Custom",
        summary: "custom series on cartesian2d — renderItem returns one hand-rolled rect bar per datum",
        width: 480, height: 320,
        nativeSupported: true,
        option: [
            "grid": ["left": 40.0, "top": 20.0, "right": 20.0, "bottom": 30.0] as [String: Any],
            "xAxis": ["type": "value"] as [String: Any],
            "yAxis": ["type": "value"] as [String: Any],
            "series": [["type": "custom",
                        "data": [[0.0, 5.0], [1.0, 8.0], [2.0, 4.0], [3.0, 9.0], [4.0, 6.0]]] as [String: Any]]
        ])
}
