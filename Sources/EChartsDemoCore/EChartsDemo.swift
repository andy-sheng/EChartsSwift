// EChartsDemo.swift — shared scaffolding for the ECharts demo galleries.
//
// The ECharts analog of Sources/DemoGallery (which compares the ported ZRenderKit against zrender's
// test/*.html). Here each demo is a REAL ECharts `option`, rendered two ways for a direct visual diff:
//   - NATIVE:  EChartsKit (the ported echarts) → ECharts driver → ZRenderKit scene graph →
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

// MARK: - Live chart handle (the native pane's `myChart`)

/// The live chart a demo's `drive` hook talks to — the native counterpart of the `myChart` the
/// official example editor puts in scope.
///
/// Plenty of official examples are not a static option at all: their behaviour IS a timeline
/// (`map-bar-morph` flips a map series and a bar series every 2s; `dynamic-data` shifts a point in
/// every second). Rendering only their first frame turns them into a different, duller example.
/// A demo therefore ships an `option` (the initial frame) AND, when the example is dynamic, a
/// `drive` closure that reproduces the example's own `setInterval` / `setOption` timeline.
///
/// The gallery's live pane implements this; the headless still-frame render does not call `drive`
/// (a PNG has no timeline). Timers are owned by the host and die with it.
@MainActor
public protocol EChartsDemoChart: AnyObject {
    /// `notMerge: true` REPLACES the option (upstream's `setOption(option, true)`) — what an example
    /// swapping one chart type for another passes.
    func setOption(_ option: [String: Any], notMerge: Bool)
    /// The example's `setInterval(fn, ms)`.
    func every(_ seconds: Double, _ body: @escaping @MainActor () -> Void)
    /// The example's `setTimeout(fn, ms)`.
    func after(_ seconds: Double, _ body: @escaping @MainActor () -> Void)
}

// MARK: - Demo value type (mirrors DemoGallery.Demo, option-driven)

/// One gallery case: a named ECharts `option` plus the logical canvas size both panes render at.
public struct EChartsDemo {
    /// Stable id, also the PNG basename and the `--render` / `--compare` argument. Official-tab demos
    /// are named `official-<example-id>`: the two collections' ids overlap (both have a `gauge-simple`
    /// and a `tree-basic`), and `byName` must stay unambiguous. The galleries show `displayName`.
    public let name: String
    public let category: String    // sidebar grouping
    public let summary: String     // one-line description
    public let width: Double
    public let height: Double
    public let option: [String: Any]
    /// Whether the native (EChartsKit) pane can render this demo today (see PHASE-6b LIMITATION).
    /// HTML always renders. Non-bar demos set this false so the gallery shows an honest "native N/A".
    public let nativeSupported: Bool
    /// Maps this demo registers (name → GeoJSON dict, or `["svg": <string>]` for SVG maps).
    /// The native pane registers these via `ECharts.registerMap` (usually in the option IIFE); the
    /// HTML pane needs the SAME `echarts.registerMap(name, data)` injected into the page BEFORE
    /// setOption — real echarts has no map registered otherwise, so a `map`/`geo` demo renders blank.
    /// Declare a demo's maps here so BOTH panes register them. Order is not significant.
    public let mapRegistrations: [String: Any]

    /// Which demo set this belongs to: the port-driven gallery (`.port`, default) or the
    /// official-examples replica tab (`.official` — cases mirrored from
    /// echarts.apache.org/examples, one representative per chart-type category).
    public enum Collection { case port, official }
    public let collection: Collection

    /// Verbatim JS from the official example (must assign `option`; may define helper vars/
    /// functions above it). When set, the HTML pane RUNS THIS instead of serializing `option`
    /// to JSON — option closures (formatters, renderItem, ...) then execute as real JS, which
    /// JSON round-tripping cannot express. The native pane always uses `option`.
    public let webOptionJS: String?

    /// Reproduces the example's own timeline on the NATIVE pane, after the initial `option` is applied
    /// — the Swift counterpart of the `setInterval` / `myChart.setOption` the example runs in JS.
    /// Only set it for examples that ARE dynamic; the still-frame render ignores it. See
    /// `EChartsDemoChart`.
    public let drive: (@MainActor (EChartsDemoChart) -> Void)?

    /// What the galleries label this demo: the bare example id for the official tab (the tab already
    /// says these are the official examples), the plain name otherwise.
    public var displayName: String {
        let p = "official-"
        return name.hasPrefix(p) ? String(name.dropFirst(p.count)) : name
    }

    public init(name: String, category: String, summary: String,
                width: Double = 400, height: Double = 300,
                nativeSupported: Bool = true,
                mapRegistrations: [String: Any] = [:],
                collection: Collection = .port,
                webOptionJS: String? = nil,
                drive: (@MainActor (EChartsDemoChart) -> Void)? = nil,
                option: [String: Any]) {
        self.name = name; self.category = category; self.summary = summary
        self.width = width; self.height = height
        self.nativeSupported = nativeSupported
        self.mapRegistrations = mapRegistrations
        self.collection = collection
        self.webOptionJS = webOptionJS
        self.drive = drive
        self.option = option
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
