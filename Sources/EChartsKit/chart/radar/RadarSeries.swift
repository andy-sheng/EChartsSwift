// Ported from echarts/src/chart/radar/RadarSeries.ts — keep in sync with upstream
/*
* Licensed to the Apache Software Foundation (ASF) under one
* or more contributor license agreements.  See the NOTICE file
* distributed with this work for additional information
* regarding copyright ownership.  The ASF licenses this file
* to you under the Apache License, Version 2.0 (the
* "License"); you may not use this file except in compliance
* with the License.  You may obtain a copy of the License at
*
*   http://www.apache.org/licenses/LICENSE-2.0
*
* Unless required by applicable law or agreed to in writing,
* software distributed under the License is distributed on an
* "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
* KIND, either express or implied.  See the License for the
* specific language governing permissions and limitations
* under the License.
*/

import Foundation
import ZRenderKit

// upstream imports:
//   import SeriesModel from '../../model/Series';                           -> SeriesModel (model/Series.swift).
//   import createSeriesDataSimply from '../helper/createSeriesDataSimply';  -> `createSeriesDataSimply` (sibling
//       chart/helper/createSeriesDataSimply.swift).
//   import * as zrUtil from 'zrender/src/core/util';                        -> `util.*` (ZRenderKit).
//   import LegendVisualProvider from '../../visual/LegendVisualProvider';
//       -> PORT-TODO: visual/LegendVisualProvider.ts NOT ported (legend component deferred).
//   import { ... option mixins ... } from '../../util/types';               -> util/types.swift (type-only; the
//       dynamic option tree is `[String: Any]`, CONVENTIONS §2).
//   import GlobalModel from '../../model/Global';                           -> GlobalModel (model/Global.swift).
//   import SeriesData from '../../data/SeriesData';                         -> SeriesData (data/SeriesData.swift).
//   import Radar from '../../coord/radar/Radar';                            -> Radar (coord/radar/Radar.swift — the
//       radar coordinate system; see integration notes).
//   import { createTooltipMarkup, retrieveVisualColorForTooltipMarker } from '../../component/tooltip/tooltipMarkup';
//       -> PORT-TODO: component/tooltip/tooltipMarkup.ts NOT ported (tooltip component deferred).

// ============================================================================
// The following upstream `interface`/`type` declarations describe the (dynamic) option tree.
// Per CONVENTIONS §2, the option tree is the `[String: Any]` bag; these types are kept as
// documentation only (the diffable surface) — no Swift types are emitted for them.
// ============================================================================
//
// type RadarSeriesDataValue = OptionDataValue[];
//
// interface RadarStatesMixin { emphasis?: DefaultStatesMixinEmphasis }
// export interface RadarSeriesStateOption<TCbParams = never> {
//     lineStyle?: LineStyleOption
//     areaStyle?: AreaStyleOption
//     label?: SeriesLabelOption
//     itemStyle?: ItemStyleOption<TCbParams>
// }
// export interface RadarSeriesDataItemOption extends SymbolOptionMixin,
//     RadarSeriesStateOption<CallbackDataParams>,
//     StatesOptionMixin<RadarSeriesStateOption<CallbackDataParams>, RadarStatesMixin>,
//     OptionDataItemObject<RadarSeriesDataValue> {}
// export interface RadarSeriesOption
//     extends SeriesOption<RadarSeriesStateOption, RadarStatesMixin>,
//     RadarSeriesStateOption, SeriesOnRadarOptionMixin,
//     SymbolOptionMixin<CallbackDataParams>, SeriesEncodeOptionMixin {
//     type?: 'radar'
//     coordinateSystem?: 'radar'
//     data?: (RadarSeriesDataItemOption | RadarSeriesDataValue)[]
// }

// upstream: export const SERIES_TYPE_RADAR = 'radar';
//   PORT-TODO (single-module dedupe): upstream RadarSeries.ts re-declares/exports this constant, but
//   coord/radar/RadarModel.swift already declares the module-level `public let SERIES_TYPE_RADAR`
//   (= COORD_SYS_TYPE_RADAR). In a single Swift module the two `public let`s collide, so this
//   re-declaration is dropped and the RadarModel one is used (same value "radar").

// upstream: class RadarSeriesModel extends SeriesModel<RadarSeriesOption>
//   The generic `Opts` is dropped per CONVENTIONS §2 (the dynamic option tree is the `[String: Any]`
//   bag). `open class` to match the port's model style (Series/Component are `open`).
open class RadarSeriesModel: SeriesModel {

    // upstream: static readonly type = 'series.' + SERIES_TYPE_RADAR;  /  readonly type = RadarSeriesModel.type;
    //   The static drives the instance `type` (inherited `var type { Self.type }` from ComponentModel).
    public override class var type: ComponentFullType { return "series." + SERIES_TYPE_RADAR }

    // upstream: static dependencies = ['radar'];
    public override class var dependencies: [String] {
        return ["radar"]
    }

    // upstream (instance field): coordinateSystem: Radar;
    //   The base `SeriesModel` declares `open var coordinateSystem: Any?`; upstream narrows it to `Radar`.
    //   A stored `Any?` var can not be overridden by a typed one, so the typed view is exposed as a
    //   computed accessor and use sites downcast (mirrors ScatterView/CandlestickLayout's `as? Cartesian2D`).
    open var radarCoordinateSystem: Radar? { return self.coordinateSystem as? Radar }

    // upstream (instance field): hasSymbolVisual = true;
    //   LOAD-BEARING: the symbol visual stage (visual/symbol.ts) reads `seriesModel.hasSymbolVisual` to
    //   decide whether to populate the 'symbol'/'symbolSize' item visuals. The base `SeriesModel` declares
    //   `open var hasSymbolVisual = false` (a stored property, can't be re-defaulted by a subclass field),
    //   so it is flipped to `true` in the `init` override below — faithful to the upstream instance field.

    // Overwrite
    // upstream: init(option: RadarSeriesOption) { super.init.apply(this, arguments as any); ... }
    open override func `init`(_ option: ModelOption?, _ parentModel: Model? = nil, _ ecModel: GlobalModel? = nil, _ rest: Any...) {
        super.`init`(option, parentModel, ecModel)

        self.hasSymbolVisual = true

        // Enable legend selection for each data item (each radar polygon is a legend entry).
        self.legendVisualProvider = LegendVisualProvider(
            { [unowned self] in self.getData() },
            { [unowned self] in self.getRawData() }
        )
    }

    // upstream: getInitialData(option: RadarSeriesOption, ecModel: GlobalModel): SeriesData { ... }
    open override func getInitialData(_ option: ModelOption?, _ ecModel: GlobalModel?) -> SeriesData? {
        // return createSeriesDataSimply(this, {
        //     generateCoord: 'indicator_',
        //     generateCoordCount: Infinity
        // });
        //   The `{generateCoord, generateCoordCount}` object literal is the `PrepareSeriesDataSchemaParams`
        //   overload of `createSeriesDataSimply` (the `extend({encodeDefine: getEncode()}, opt)` branch).
        //   One store dimension is generated per indicator (`indicator_0`, `indicator_1`, …).
        return createSeriesDataSimply(self, PrepareSeriesDataSchemaParams(
            generateCoord: "indicator_",
            generateCoordCount: Double.infinity
        ))
    }

    // upstream: formatTooltip(dataIndex, multipleSeries?, dataType?) { ... }
    open override func formatTooltip(
        _ dataIndex: Double,
        _ multipleSeries: Bool? = nil,
        _ dataType: SeriesDataType? = nil
    ) -> TooltipFormatResult? {
        // const data = this.getData();
        // const coordSys = this.coordinateSystem;
        // const indicatorAxes = coordSys.getIndicatorAxes();
        // const name = this.getData().getName(dataIndex);
        // const nameToDisplay = name === '' ? this.name : name;
        // const markerColor = retrieveVisualColorForTooltipMarker(this, dataIndex);
        //
        // return createTooltipMarkup('section', {
        //     header: nameToDisplay,
        //     sortBlocks: true,
        //     blocks: zrUtil.map(indicatorAxes, axis => {
        //         const val = data.get(data.mapDimension(axis.dim), dataIndex);
        //         return createTooltipMarkup('nameValue', {
        //             markerType: 'subItem',
        //             markerColor: markerColor,
        //             name: axis.name,
        //             value: val,
        //             sortParam: val
        //         });
        //     })
        // });
        // PORT-TODO: component/tooltip/tooltipMarkup.ts (createTooltipMarkup /
        //   retrieveVisualColorForTooltipMarker) NOT ported — the markup return is deferred (returns nil,
        //   matching the base stub). The faithful body is preserved above.
        _ = (dataIndex, multipleSeries, dataType)
        return nil
    }

    // upstream (declaration-merged optional method): getTooltipPosition(dataIndex: number): number[]
    //   Not a member of the base `SeriesModel`; concrete series add it (see model/Series.swift note).
    open func getTooltipPosition(_ dataIndex: Double?) -> [Double]? {
        // if (dataIndex != null) {
        if dataIndex != nil {
            let data = self.getData()
            // const coordSys = this.coordinateSystem;
            // PORT-TODO: `coordinateSystem` is `Radar?` here; upstream is non-optional `Radar`.
            guard let coordSys = self.radarCoordinateSystem else { return nil }

            // const values = data.getValues(
            //     zrUtil.map(coordSys.dimensions, function (dim) { return data.mapDimension(dim); }),
            //     dataIndex
            // );
            let values = data.getValues(
                util.map(coordSys.dimensions) { dim, _ in
                    // PORT-TODO: `mapDimension` is force-unwrapped — a radar's indicator dims are always
                    //   present (they were generated in `getInitialData`).
                    return data.mapDimension(dim)!
                },
                Int(dataIndex!)
            )

            // for (let i = 0, len = values.length; i < len; i++) {
            //     if (!isNaN(values[i] as number)) {
            //         const indicatorAxes = coordSys.getIndicatorAxes();
            //         return coordSys.coordToPoint(indicatorAxes[i].dataToCoord(values[i]), i);
            //     }
            // }
            let len = values.count
            for i in 0..<len {
                if !radarSeriesNum(values[i]).isNaN {
                    let indicatorAxes = coordSys.getIndicatorAxes()
                    return coordSys.coordToPoint(indicatorAxes[i].dataToCoord(values[i]), Double(i))
                }
            }
        }
        return nil
    }

    // upstream: static defaultOption: RadarSeriesOption = { ... }
    open override class var defaultOption: ModelOption? {
        return [
            // zlevel: 0,
            "z": 2.0,
            "colorBy": "data",
            "coordinateSystem": "radar",
            "legendHoverLink": true,
            "radarIndex": 0,
            "lineStyle": [
                "width": 2.0,
                "type": "solid",
                "join": "round"
            ] as [String: Any],
            "label": [
                "position": "top"
            ] as [String: Any],
            // areaStyle: {
            // },
            // itemStyle: {}
            "symbolSize": 8.0
            // symbolRotate: null
        ] as [String: Any]
    }
}

// export default RadarSeriesModel;  -> `open class RadarSeriesModel` above.

// `data.getValues(...)` returns `[ParsedValue]` (Any); numeric radar values are stored as `Double`.
//   Mirrors the upstream `values[i] as number` coercion for the `isNaN` check.
private func radarSeriesNum(_ v: Any?) -> Double {
    if let d = v as? Double { return d }
    if let i = v as? Int { return Double(i) }
    if let n = v as? NSNumber { return n.doubleValue }
    return Double.nan
}
