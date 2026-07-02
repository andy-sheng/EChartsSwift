// EChartsDemo.swift — shared scaffolding for the ECharts demo gallery.
//
// The ECharts analog of Sources/DemoGallery (which compares the ported ZRenderKit against zrender's
// test/*.html). Here each demo is a REAL ECharts `option`, rendered two ways for a direct visual diff:
//   - NATIVE:  EChartsKit (the ported echarts) → EChartsSlim driver → ZRenderKit scene graph →
//              NativePainter (`renderToImage`) → CGImage.
//   - HTML:    the SAME option fed to the REAL echarts (`upstream/echarts/dist/echarts.js`, 6.1.0)
//              running in a WKWebView.
//
// Structure mirrors DemoGallery 1:1: an `EChartsDemo` value type, a `Demos/<name>.swift` file per
// case, a generated `Registry.swift` index, and an AppKit `Entry.swift` GUI + CLI.
//
// PHASE-6b LIMITATION (documented, not a workaround): the native pane currently renders only the
// cartesian `bar` series. The real `BarSeriesModel.getInitialData → SourceManager.getSource()` is a
// `fatalError` stub (data/helper/sourceManager.ts not ported), so — exactly as the EChartsKit tests
// do — this gallery registers `DemoBarSeriesModel`, which builds a `SeriesData` directly from the
// demo option's own `series[].data`. The HTML pane is fully general (real echarts renders anything);
// as more of EChartsKit lands, more demos' native panes will light up.

import Foundation
import ZRenderKit
import EChartsKit

// MARK: - Demo value type (mirrors DemoGallery.Demo, option-driven)

/// One gallery case: a named ECharts `option` plus the logical canvas size both panes render at.
public struct EChartsDemo {
    public let name: String        // stable id (also the PNG basename)
    public let category: String    // sidebar grouping
    public let summary: String     // one-line description
    public let width: Double
    public let height: Double
    public let option: [String: Any]
    /// Whether the native (EChartsKit) pane can render this demo today (see PHASE-6b LIMITATION).
    /// HTML always renders. Non-bar demos set this false so the gallery shows an honest "native N/A".
    public let nativeSupported: Bool

    public init(name: String, category: String, summary: String,
                width: Double = 400, height: Double = 300,
                nativeSupported: Bool = true, option: [String: Any]) {
        self.name = name; self.category = category; self.summary = summary
        self.width = width; self.height = height
        self.nativeSupported = nativeSupported; self.option = option
    }
}

// MARK: - registry namespace (mirrors DemoRegistry)

public enum EChartsDemoRegistry {
    /// Assembled in Registry.swift — one entry per Demos/<name>.swift.
    public static func byName(_ name: String) -> EChartsDemo? { everything.first { $0.name == name } }
}

// MARK: - native-render data double (see PHASE-6b LIMITATION)

/// A `series.bar` model that supplies its data from the demo option's own `series[].data`
/// (`[Double]` of category values → rows `[categoryIndex, value]`), bypassing the unported
/// `SourceManager` source path. Registered globally by `renderNativeGroup`.
final class DemoBarSeriesModel: BarSeriesModel {
    // Inherits `type == "series.bar"` from BarSeriesModel (its class `type` is not `open`, and a
    // subclass in another module can't re-declare it — but the inherited value already keys
    // registration correctly, replacing the real BarSeriesModel for `series.bar`).
    override func getInitialData(_ option: ModelOption?, _ ecModel: GlobalModel?) -> SeriesData? {
        let values = demoSeriesValues((self.option as? [String: Any])?["data"])
        let rows = values.enumerated().map { [Double($0.offset), $0.element] }
        let d = SeriesData(["x", "y"], self)
        let source = createSourceFromSeriesDataOption(rows)
        let provider = DefaultDataProvider(source, 2)
        let store = DataStore()
        store.initData(provider, [
            DataStoreDimensionDefine(type: .float, property: "x"),
            DataStoreDimensionDefine(type: .float, property: "y")
        ])
        d.initData(store)
        return d
    }
}

/// Coerce a `series.data` option (`[Double]` / `[Int]` / `[NSNumber]`) to `[Double]`.
func demoSeriesValues(_ raw: Any?) -> [Double] {
    guard let arr = raw as? [Any] else { return [] }
    return arr.compactMap { v in
        if let d = v as? Double { return d }
        if let i = v as? Int { return Double(i) }
        if let n = v as? NSNumber { return n.doubleValue }
        return nil
    }
}
