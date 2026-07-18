// Ported (MINIMAL SUBSET) from echarts/src/chart/line/LineSeries.ts — keep in sync with upstream.
//
// A deliberately minimal `series.line` model: enough for the cartesian line vertical (grid + x/y axis
// + a polyline through the data points) to render end-to-end through the driver. Options are read from
// the dynamic option bag, so areaStyle, step, stack and symbols now render via LineView; only the
// exhaustive option surface (endLabel, sampling, …) stays minimal — mirroring how `ECharts`/`BarSeries`
// keep minimal defaultOption subsets of their upstream files.

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
            // upstream LineSeries.ts:167 — the default line-label placement is 'top' (above the point),
            //   not the global label default. LOAD-BEARING for label position parity.
            "label": ["position": "top"] as [String: Any],
            // LOAD-BEARING for LineView's showSymbol pass: upstream defaultOption defaults
            //   `symbol: 'emptyCircle'`, `symbolSize: 6`, `showSymbol: true` (LineSeries.ts:202 — echarts
            //   6.x bumped the default from 4 to 6). Without these the symbol pass reads nil and draws
            //   nothing. PORT-NOTE: symbolRotate / symbolKeepAspect and the rest of upstream's
            //   SymbolOptionMixin defaults deferred with the symbol subsystem.
            "symbol": "emptyCircle",
            "symbolSize": 6.0,
            "showSymbol": true,
            // upstream LineSeries.ts:210 — 'auto' hides the point symbols when the line is dense (see
            //   LineView's getIsIgnoreFunc / canShowAllSymbolForCategory density check).
            "showAllSymbol": "auto",
            // upstream LineSeries.ts:174 — the endLabel default. `valueAnimation: true` is LOAD-BEARING:
            //   it makes `_endLabelOnDuring` re-fetch/interpolate the raw value at the animated clip edge
            //   each frame, so the end label's NUMBER climbs as the reveal sweeps (e.g. official-line-race,
            //   where the income counts up to its final figure). Without this default it reads false and
            //   the label shows the final value frozen from t=0.
            "endLabel": ["show": false, "valueAnimation": true, "distance": 8.0] as [String: Any],
            // upstream LineSeries.ts:180 — the default line width/type. LOAD-BEARING now that LineView
            //   reads the stroke width from `lineStyleModel.getLineStyle()` (faithful port) instead of
            //   hard-coding 2: without this the polyline falls back to DEFAULT_PATH_STYLE.lineWidth (1).
            "lineStyle": ["width": 2.0, "type": "solid"] as [String: Any],
            // upstream LineSeries.ts:185 — `emphasis.scale: true` makes the data symbols scale up on
            //   hover by default (SymbolDraw's emphasis pass reads it). Without this default hover leaves
            //   the point symbols the same size.
            "emphasis": ["scale": true] as [String: Any],
            // upstream LineSeries.ts:224 — the morph-transition default: when a line series is universal-
            //   transitioned, each datum's shape is CLONED (rather than split) to divide into the target.
            "universalTransition": ["divideShape": "clone"] as [String: Any],
            // upstream LineSeries.ts:218 — LOAD-BEARING for the draw-on reveal CURVE. The line series
            //   OVERRIDES the global default `animationEasing: 'cubicInOut'` (globalDefault.swift:131)
            //   with 'linear'. Without this override here, `getAnimationConfig` → `getShallow` walks up
            //   to the global model and the native reveal eases (cubicInOut) while echarts.js reveals at
            //   constant speed (linear) — a visible animation-curve mismatch (e.g. official-line-race).
            "animationEasing": "linear"
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
        // upstream: const visualRotate = this.getData().getVisual('symbolRotate');
        let visualRotate = self.getData().getVisual("symbolRotate")
        let symbolType = (visualType == nil || visualType == "none") ? "circle" : visualType!
        let size = opt.itemHeight * 0.8
        let sym = symbol.createSymbol(
            symbolType, (opt.itemWidth - size) / 2, (opt.itemHeight - size) / 2, size, size, colorZR
        )
        if let symPath = sym as? Path {
            // upstream: const symbolRotate = opt.iconRotate === 'inherit' ? visualRotate : (opt.iconRotate || 0);
            //   symbol.rotation = symbolRotate * Math.PI / 180; symbol.setOrigin([itemWidth/2, itemHeight/2]);
            let symbolRotate: Double = {
                if (opt.iconRotate as? String) == "inherit" {
                    return (visualRotate as? Double) ?? 0
                }
                if let d = opt.iconRotate as? Double { return d }
                if let i = opt.iconRotate as? Int { return Double(i) }
                return 0
            }()
            symPath.rotation = symbolRotate * Double.pi / 180
            symPath.setOrigin([opt.itemWidth / 2, opt.itemHeight / 2])

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
