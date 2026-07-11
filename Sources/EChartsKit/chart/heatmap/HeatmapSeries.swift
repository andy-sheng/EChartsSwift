// Ported from echarts/src/chart/heatmap/HeatmapSeries.ts — keep in sync with upstream
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
//   import SeriesModel from '../../model/Series';                 -> SeriesModel (model/Series.swift).
//   import createSeriesData from '../helper/createSeriesData';    -> `createSeriesData` (sibling chart/helper/createSeriesData.swift).
//   import CoordinateSystem from '../../core/CoordinateSystem';   -> core/CoordinateSystem.swift (the coord-creator registry).
//   import { ... option mixins ... } from '../../util/types';     -> util/types.swift (type-only; the dynamic
//                                                                    option tree is `[String: Any]`, CONVENTIONS §2).
//   import GlobalModel from '../../model/Global';                 -> GlobalModel (model/Global.swift).
//   import SeriesData from '../../data/SeriesData';               -> SeriesData (data/SeriesData.swift).
//   import type Geo from '../../coord/geo/Geo';                   -> coord/geo/Geo.swift (geo coord is ported; heatmap's geo render path is deferred, see below).
//   import type Cartesian2D from '../../coord/cartesian/Cartesian2D';  -> coord/cartesian/Cartesian2D.swift (the required render path).
//   import type Calendar from '../../coord/calendar/Calendar';    -> coord/calendar/Calendar.swift (ported; not wired into heatmap's render path yet).
//   import Matrix from '../../coord/matrix/Matrix';               -> coord/matrix/Matrix.swift (ported; not wired into heatmap's render path yet).
//   import tokens from '../../visual/tokens';
//       -> PORT-NOTE: visual/tokens.swift is ported; `tokens.color.primary` is still inlined verbatim as its
//          resolved constant in `defaultOption` (same convention as ScatterSeries.swift).
//            tokens.color.primary = color.neutral80 = '#3c3c41'

// ============================================================================
// The following upstream type/`interface` declarations describe the (dynamic) option tree.
// Per CONVENTIONS §2, the option tree is the `[String: Any]` bag; these types are kept as
// documentation only (the diffable surface) — no Swift types are emitted for them.
// ============================================================================
//
// type HeatmapDataValue = OptionDataValue[];
//
// export interface HeatmapStateOption<TCbParams = never> {
//     // Available on cartesian2d coordinate system
//     itemStyle?: ItemStyleOption<TCbParams> & { borderRadius?: number | number[] }
//     label?: SeriesLabelOption
// }
// interface HeatmapStatesMixin {
//     emphasis?: DefaultStatesMixinEmphasis
// }
// export interface HeatmapDataItemOption extends HeatmapStateOption,
//     StatesOptionMixin<HeatmapStateOption, HeatmapStatesMixin> {
//     value: HeatmapDataValue
// }
// export interface HeatmapSeriesOption
//     extends SeriesOption<HeatmapStateOption<CallbackDataParams>, HeatmapStatesMixin>,
//     HeatmapStateOption<CallbackDataParams>,
//     SeriesOnCartesianOptionMixin, SeriesOnGeoOptionMixin,
//     ComponentOnCalendarOptionMixin, ComponentOnMatrixOptionMixin,
//     SeriesEncodeOptionMixin {
//     type?: 'heatmap'
//     coordinateSystem?: 'cartesian2d' | 'geo' | 'calendar' | 'matrix'
//     // Available on geo coordinate system
//     blurSize?: number
//     pointSize?: number
//     maxOpacity?: number
//     minOpacity?: number
//     data?: (HeatmapDataItemOption | HeatmapDataValue)[]
// }

// upstream: class HeatmapSeriesModel extends SeriesModel<HeatmapSeriesOption>
//   The generic `Opts` is dropped per CONVENTIONS §2 (the dynamic option tree is the `[String: Any]`
//   bag). `open class` to match the port's model style (Series/Component are `open`).
open class HeatmapSeriesModel: SeriesModel {

    // upstream: static readonly type = 'series.heatmap';  /  readonly type = HeatmapSeriesModel.type;
    //   The static drives the instance `type` (inherited `var type { Self.type }` from ComponentModel).
    public override class var type: ComponentFullType { return "series.heatmap" }

    // upstream: static readonly dependencies = ['grid', 'geo', 'calendar', 'matrix'];
    //   PORT-NOTE: only grid/cartesian2d is renderable in heatmap now (the geo/calendar/matrix coord
    //   systems are ported, but heatmap's render path doesn't wire them yet);
    //   the dependency list is kept verbatim so registration/topo order matches.
    public override class var dependencies: [String] {
        return ["grid", "geo", "calendar", "matrix"]
    }

    // upstream: coordinateSystem: Cartesian2D | Geo | Calendar | Matrix;
    //   (declared on SeriesModel base — the wired coord instance; only Cartesian2D is renderable in the port.)

    // upstream:
    //   getInitialData(option, ecModel): SeriesData {
    //       return createSeriesData(null, this, { generateCoord: 'value' });
    //   }
    open override func getInitialData(_ option: ModelOption?, _ ecModel: GlobalModel?) -> SeriesData? {
        return createSeriesData(nil, self, CreateSeriesDataOpt(generateCoord: "value"))
    }

    // upstream:
    //   preventIncremental() {
    //       const coordSysCreator = CoordinateSystem.get(this.get('coordinateSystem'));
    //       if (coordSysCreator && coordSysCreator.dimensions) {
    //           return coordSysCreator.dimensions[0] === 'lng' && coordSysCreator.dimensions[1] === 'lat';
    //       }
    //   }
    // PORT-TODO: progressive/incremental rendering (core/task incremental pipeline) not ported — the static
    //   heatmap render draws every datum eagerly. Restore this override when the incremental pipeline + the
    //   geo (lng/lat) coord creator land.

    // upstream: static defaultOption: HeatmapSeriesOption = { ... }
    open override class var defaultOption: ModelOption? {
        return [

            "coordinateSystem": "cartesian2d",

            // zlevel: 0,

            "z": 2.0,

            // Cartesian coordinate system
            // xAxisIndex: 0,
            // yAxisIndex: 0,

            // Geo coordinate system
            // PORT-NOTE: geo coord is ported; kept verbatim for the diffable surface / geo-path deferral.
            "geoIndex": 0.0,

            // The following four are for the geo/large blurred-canvas path (HeatmapLayer.ts),
            // which is a PORT-TODO — the cartesian colored-Rect path ignores them. Kept for parity.
            "blurSize": 30.0,

            "pointSize": 20.0,

            "maxOpacity": 1.0,

            "minOpacity": 0.0,

            "select": [
                "itemStyle": [
                    // PORT-NOTE: tokens.color.primary inlined as resolved constant (color.neutral80);
                    //   visual/tokens.swift is ported — could re-wire to `tokens.color.primary`.
                    "borderColor": "#3c3c41"   // tokens.color.primary
                ] as [String: Any]
            ] as [String: Any]
        ] as [String: Any]
    }
}

// export default HeatmapSeriesModel;  -> `open class HeatmapSeriesModel` above.
