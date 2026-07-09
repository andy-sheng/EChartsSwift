// Ported (MINIMAL SUBSET) from echarts/src/chart/line/LineSeries.ts — keep in sync with upstream.
//
// A deliberately minimal `series.line` model: enough for the cartesian line vertical (grid + x/y axis
// + a polyline through the data points) to render end-to-end through the slim driver. The full
// LineSeries option surface (areaStyle, step, stack, emphasis, endLabel, sampling, …) is a documented
// PORT-TODO — this mirrors how `EChartsSlim`/`BarSeries` are minimal subsets of their upstream files.

import Foundation
import ZRenderKit

// upstream: const SERIES_TYPE_LINE (implicit) — the series subtype string.
public let SERIES_TYPE_LINE = "line"

// upstream: class LineSeriesModel extends SeriesModel<LineSeriesOption>
open class LineSeriesModel: SeriesModel {

    // upstream: static type = 'series.line'; type = LineSeriesModel.type;
    public override class var type: ComponentFullType { return "series." + SERIES_TYPE_LINE }

    // upstream: static dependencies = ['grid', 'polar'];
    public override class var dependencies: [String] { return ["grid", "polar"] }

    // upstream: getInitialData(option): SeriesData { ... createSeriesData(null, this, {useEncodeDefaulter:true}) }
    //   Same as bar, `createSeriesData → SourceManager.getSource()` is the documented Phase-6b fatalError
    //   stub (data/helper/sourceManager.ts not ported); the demo/tests supply a populated-DataStore double.
    open override func getInitialData(_ option: ModelOption?, _ ecModel: GlobalModel?) -> SeriesData? {
        return createSeriesData(nil, self, CreateSeriesDataOpt(useEncodeDefaulter: true))
    }

    // upstream (instance field): hasSymbolVisual = true; — the symbol visual stage (visual/symbol.ts)
    //   reads it to populate the symbol / symbolSize / symbolRotate / symbolOffset item visuals that
    //   LineView's SymbolDraw pass consumes. The base declares `open var hasSymbolVisual = false`, so
    //   flip it in the init override (faithful to the upstream instance field). `defaultSymbol` stays
    //   'circle', but the line defaultOption already sets `symbol: 'emptyCircle'`, so `get("symbol")`
    //   supplies it before the fallback.
    open override func `init`(_ option: ModelOption?, _ parentModel: Model? = nil, _ ecModel: GlobalModel? = nil, _ rest: Any...) {
        super.`init`(option, parentModel, ecModel)
        self.hasSymbolVisual = true
    }

    // upstream basic line uses the default `visualStyleAccessPath = 'itemStyle'` / `visualDrawType = 'fill'`
    //   (NOT the `lineStyle`/`stroke` override that parallel/lines series use), so the palette color lands
    //   under the item visual style's `fill` key — `LineView` reads it and applies it as the line stroke.

    // upstream: static defaultOption = { z: 3, coordinateSystem: 'cartesian2d', clip: true, ... }.
    //   MINIMAL subset: only the fields the cartesian line vertical needs. `coordinateSystem` is
    //   LOAD-BEARING — `decideCoordSysUsageKind` reads `getShallow("coordinateSystem")` (fed by this
    //   static default via mergeDefaultAndTheme) to decide whether to inject the cartesian coord system;
    //   without it the line series gets NO coordinateSystem and `LineView` renders nothing.
    open override class var defaultOption: ModelOption? {
        return [
            "z": 3.0,
            "coordinateSystem": "cartesian2d",
            "legendHoverLink": true,
            "clip": true,
            // LOAD-BEARING for LineView's showSymbol pass: upstream defaultOption defaults
            //   `symbol: 'emptyCircle'`, `symbolSize: 6`, `showSymbol: true` (LineSeries.ts:202 — echarts
            //   6.x bumped the default from 4 to 6). Without these the symbol pass reads nil and draws
            //   nothing. PORT-TODO: symbolRotate / symbolKeepAspect and the rest of upstream's
            //   SymbolOptionMixin defaults deferred with the symbol subsystem.
            "symbol": "emptyCircle",
            "symbolSize": 6.0,
            "showSymbol": true,
            // upstream LineSeries.ts:210 — 'auto' hides the point symbols when the line is dense (see
            //   LineView's getIsIgnoreFunc / canShowAllSymbolForCategory density check).
            "showAllSymbol": "auto"
        ] as [String: Any]
    }

    // upstream LineSeriesModel.getLegendIcon: a Group holding a horizontal 'line' symbol plus the series'
    //   data symbol (default 'circle'), so the legend swatch reads as a line series rather than the
    //   default filled rect. Faithful reduction (emphasis rotate/inherit kept minimal).
    open override func getLegendIcon(_ opt: LegendIconParams) -> Element? {
        let group = Group()

        // Prefer the legend-computed `opt.itemStyle.fill` / `opt.lineStyle.stroke` (the resolved series
        //   color when SELECTED, grey `inactiveColor` when UNSELECTED). This is stable even for a
        //   legend-filtered (toggled-off) series whose data visual is gone — reading getData().getVisual
        //   there returned nil, so the icon lost its color and VANISHED instead of greying out. Fall back
        //   to the series data visual only when the legend style carries no usable color.
        let colorZR: ZRenderKit.ZRColor? = {
            for bag in [opt.itemStyle, opt.lineStyle] {
                for key in ["fill", "stroke"] {
                    if let z = bag[key] as? EChartsKit.ZRColor, case let .color(c) = z { return .string(c) }
                    if let s = bag[key] as? String, !s.isEmpty, s != "inherit", s != "auto", s != "none" { return .string(s) }
                }
            }
            guard let s = self.getData().getVisual("style") as? [String: Any] else { return nil }
            for key in ["stroke", "fill"] {
                if let z = s[key] as? EChartsKit.ZRColor, case let .color(c) = z { return .string(c) }
                if let str = s[key] as? String, !str.isEmpty, str != "inherit", str != "auto" { return .string(str) }
            }
            return nil
        }()

        // Horizontal line spanning the swatch, vertically centered.
        let line = symbol.createSymbol("line", 0, opt.itemHeight / 2, opt.itemWidth, 0, nil, false)
        if let linePath = line as? Path {
            linePath.pathStyle.stroke = colorZR
            linePath.pathStyle.lineWidth = 2
            linePath.pathStyle.fill = nil
            _ = group.add(linePath)
        }

        // The series' data symbol (default 'emptyCircle' → hollow) centered on the line, at 80% height.
        //   Fall back to the series `symbol` option when the series-level visual is unset.
        let visualType = (self.getData().getVisual("symbol") as? String) ?? (self.get("symbol", false) as? String)
        let symbolType = (visualType == nil || visualType == "none") ? "circle" : visualType!
        let size = opt.itemHeight * 0.8
        let sym = symbol.createSymbol(
            symbolType, (opt.itemWidth - size) / 2, (opt.itemHeight - size) / 2, size, size, colorZR
        )
        if let symPath = sym as? Path {
            if symbolType.contains("empty") {
                symPath.pathStyle.stroke = colorZR
                symPath.pathStyle.fill = .string("#fff")
                symPath.pathStyle.lineWidth = 2
            } else {
                symPath.pathStyle.fill = colorZR
            }
            _ = group.add(symPath)
        }

        return group
    }
}
