// EChartsDemo.swift — shared scaffolding for the ECharts demo galleries.
//
// The ECharts analog of Sources/DemoGallery (which compares the ported ZRenderKit against zrender's
// test/*.html). Here each demo is a REAL ECharts `option`, rendered two ways for a direct visual diff:
//   - NATIVE:  EChartsKit (the ported echarts) → EChartsSlim driver → ZRenderKit scene graph →
//              NativePainter (`renderToImage`) → CGImage.
//   - HTML:    the SAME option fed to the REAL echarts (`upstream/echarts/dist/echarts.js`, 6.1.0)
//              running in a WKWebView.
//
// Structure mirrors DemoGallery 1:1: an `EChartsDemo` value type, a `Demos/<name>.swift` file per
// case, and a generated `Registry.swift` index. This module (EChartsDemoCore) is the shared demo
// registry consumed by BOTH gallery front-ends: the macOS one (Sources/EChartsDemoGallery — AppKit
// GUI + headless CLI) and the iOS one (Sources/EChartsDemoGalleryiOS — UIKit app, simulator-only).
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

// NOTE: the former `DemoBarSeriesModel` / `DemoLineSeriesModel` data doubles were REMOVED in Phase 6c.
// The real `SourceManager` is now ported, so the stock `BarSeriesModel` / `LineSeriesModel`
// `getInitialData → createSeriesData → SourceManager.getSource()` builds each series' data straight
// from the option's own `series[].data` — no double needed.
