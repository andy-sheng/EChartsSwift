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
            "clip": true
        ] as [String: Any]
    }
}
