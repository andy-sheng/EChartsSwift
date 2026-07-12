// Ported from echarts/src/chart/bar/BaseBarSeries.ts — keep in sync with upstream
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

// import SeriesModel from '../../model/Series';                       -> SeriesModel (model/Series.swift)
// import createSeriesData from '../helper/createSeriesData';          -> createSeriesData IS ported
//   (chart/helper/createSeriesData.swift). Referenced by its conventional public API
//   `createSeriesData(sourceRaw, seriesModel, opt)` (called in getInitialData below); the former local
//   stub has been removed (see the note at the bottom of this file).
// import {
//     SeriesOption, SeriesOnCartesianOptionMixin, SeriesOnPolarOptionMixin, ScaleDataValue,
//     DefaultStatesMixin, StatesMixinBase
// } from '../../util/types';                                          -> util/types.swift (same module)
// import GlobalModel from '../../model/Global';                       -> GlobalModel (model/Global.swift)
// import Cartesian2D from '../../coord/cartesian/Cartesian2D';        -> Cartesian2D (coord/cartesian/Cartesian2D.swift)
// import SeriesData from '../../data/SeriesData';                     -> SeriesData (data/SeriesData.swift)
// import {dimPermutations} from '../../component/marker/MarkAreaView';
//   -> MarkAreaView IS ported (component/marker/MarkAreaView.swift), which exports `dimPermutations`
//      (the 4 x/y start/end permutations); the `dims` param of `getMarkerPosition` is typed `[String]?`
//      until the marker component lands.
// import { each } from 'zrender/src/core/util';                       -> util.each (ZRenderKit)
// import type Axis2D from '../../coord/cartesian/Axis2D';             -> Axis2D (coord/cartesian/Axis2D.swift)
// import type Model from '../../model/Model';                         -> Model (model/Model.swift)
// import { CategoryAxisBaseOption } from '../../coord/axisCommonTypes';  -> coord/axisCommonTypes.swift (type-only)
// import type Axis from '../../coord/Axis';                           -> Axis (coord/Axis.swift)


// export interface BaseBarSeriesOption<StateOption, ExtraStateOption extends StatesMixinBase = DefaultStatesMixin>
//     extends SeriesOption<StateOption, ExtraStateOption>,
//     SeriesOnCartesianOptionMixin, SeriesOnPolarOptionMixin {
//     barMinHeight?: number       // Min height of bar
//     barMinAngle?: number        // Min angle of bar. Available on polar coordinate system.
//     barMaxWidth?: number | string   // Max width of bar. Defaults to 1 on cartesian. Otherwise null.
//     barMinWidth?: number | string
//     barWidth?: number | string  // Bar width. Will be calculated automatically. Pixel or percent string.
//     barGap?: string | number    // Gap between each bar inside category. Default 30%. Or absolute pixel value.
//     defaultBarGap?: string | number   // @private
//     barCategoryGap?: string | number  // Gap between each category. Default 20%. Or absolute pixel value.
//     large?: boolean
//     largeThreshold?: number
// }
//
// PORT-NOTE: TS `interface BaseBarSeriesOption` describes the dynamic option shape; per CONVENTIONS §2
//   the option tree is modeled as the dynamic bag ([String: Any], keyed access via Model.get), so no
//   standalone Swift struct is emitted. Preserved above for the diffable surface.

// class BaseBarSeriesModel<Opts extends BaseBarSeriesOption<unknown> = BaseBarSeriesOption<unknown>>
//     extends SeriesModel<Opts>
//
// PORT-NOTE: the generic `Opts` is dropped per CONVENTIONS §2 (the dynamic option tree is the `Any`
//   bag). `open class` because concrete bar series (BarSeriesModel / PictorialBarSeriesModel) subclass it.
open class BaseBarSeriesModel: SeriesModel {

    // static type = 'series.__base_bar__';
    // type = BaseBarSeriesModel.type;   (instance `type` mirrors the static via inherited `var type`)
    open override class var type: ComponentFullType { return "series.__base_bar__" }

    // getInitialData(option: Opts, ecModel: GlobalModel): SeriesData
    open override func getInitialData(_ option: ModelOption?, _ ecModel: GlobalModel?) -> SeriesData? {
        // return createSeriesData(null, this, {useEncodeDefaulter: true});
        _ = (option, ecModel)
        return createSeriesData(nil, self, CreateSeriesDataOpt(useEncodeDefaulter: true))
    }

    // getMarkerPosition(value: ScaleDataValue[], dims?: typeof dimPermutations[number], startingAtTick?: boolean)
    // upstream returns `number[]`.
    open func getMarkerPosition(
        _ value: [ScaleDataValue],
        _ dims: [String]? = nil,
        _ startingAtTick: Bool? = nil
    ) -> [Double] {
        // const coordSys = this.coordinateSystem;
        // if (coordSys && coordSys.clampData) { ... }
        // PORT-NOTE: upstream duck-types `coordSys.clampData`; SCOPE is cartesian only, so we narrow
        //   `coordinateSystem` (typed `Any?` on SeriesModel) to `Cartesian2D` (which provides
        //   clampData/dataToPoint/getAxes/getBaseAxis). Polar (which also has clampData) is out of scope.
        if let coordSys = self.coordinateSystem as? Cartesian2D {
            // PENDING if clamp ?
            let clampData = coordSys.clampData(value)!
            var pt = coordSys.dataToPoint(clampData)
            if startingAtTick == true {
                util.each(coordSys.getAxes()) { (axis: Axis2D, idx: Int) in
                    // If axis type is category, use tick coords instead
                    if axis.type == "category" && dims != nil {
                        let tickCoords = axis.getTicksCoords()
                        // const alignTicksWithLabel = (axis.getTickModel() as Model<...>).get('alignWithLabel');
                        let alignTicksWithLabel = axis.getTickModel().get("alignWithLabel")

                        var targetTickId = clampData[idx]
                        // The index of rightmost tick of markArea is 1 larger than x1/y1 index
                        let isEnd = dims![idx] == "x1" || dims![idx] == "y1"
                        if isEnd && !((alignTicksWithLabel as? Bool) ?? false) {
                            targetTickId += 1
                        }

                        // The only contains one tick, tickCoords is
                        // like [{coord: 0, tickValue: 0}, {coord: 0}]
                        // to the length should always be larger than 1
                        if tickCoords.count < 2 {
                            return
                        }
                        else if tickCoords.count == 2 {
                            // The left value and right value of the axis are
                            // the same. coord is 0 in both items. Use the max
                            // value of the axis as the coord
                            pt[idx] = axis.toGlobalCoord(
                                axis.getExtent()[isEnd ? 1 : 0]
                            )
                            return
                        }

                        var leftCoord: Double? = nil
                        var coord: Double? = nil
                        var stepTickValue = 1.0
                        for i in 0..<tickCoords.count {
                            let tickCoord = tickCoords[i].coord
                            // The last item of tickCoords doesn't contain
                            // tickValue
                            let tickValue = i == tickCoords.count - 1
                                ? tickCoords[i - 1].tickValue + stepTickValue
                                : tickCoords[i].tickValue
                            if tickValue == targetTickId {
                                coord = tickCoord
                                break
                            }
                            else if tickValue < targetTickId {
                                leftCoord = tickCoord
                            }
                            else if leftCoord != nil && tickValue > targetTickId {
                                coord = (tickCoord + leftCoord!) / 2
                                break
                            }
                            if i == 1 {
                                // Here we assume the step of category axes is
                                // the same
                                stepTickValue = tickValue - tickCoords[0].tickValue
                            }
                        }
                        if coord == nil {
                            // PORT-NOTE: upstream `!leftCoord` / `else if (leftCoord)` use JS truthiness;
                            //   leftCoord is falsy when nil OR 0. Replicated explicitly here.
                            if !(leftCoord != nil && leftCoord! != 0) {
                                // targetTickId is smaller than all tick ids in the
                                // visible area, use the leftmost tick coord
                                coord = tickCoords[0].coord
                            }
                            else {
                                // targetTickId is larger than all tick ids in the
                                // visible area, use the rightmost tick coord
                                coord = tickCoords[tickCoords.count - 1].coord
                            }
                        }
                        pt[idx] = axis.toGlobalCoord(coord!)
                    }
                }
            }
            else {
                let data = self.getData()
                // upstream: data.getLayout('offset') / 'size' — return `number`; getLayout is `Any?`,
                //   read as Double (default 0).
                let offset = (data.getLayout("offset") as? Double) ?? 0
                let size = (data.getLayout("size") as? Double) ?? 0
                let offsetIndex = (coordSys as Cartesian2D).getBaseAxis().isHorizontal() ? 0 : 1
                pt[offsetIndex] += offset + size / 2
            }
            return pt
        }
        return [Double.nan, Double.nan]
    }

    /**
     * @implements
     */
    // __requireStartValue(axis: Axis): boolean
    open func __requireStartValue(_ axis: Axis) -> Bool {
        // return this.getBaseAxis() !== axis;
        // PORT-NOTE: SeriesModel.getBaseAxis() returns `Any?` (coord layer stub); compare by identity.
        return (self.getBaseAxis() as AnyObject?) !== (axis as AnyObject)
    }

    // static defaultOption: BaseBarSeriesOption<unknown, unknown> = { ... }
    open override class var defaultOption: ModelOption? {
        return [
            // zlevel: 0,
            "z": 2.0,
            "coordinateSystem": "cartesian2d",
            "legendHoverLink": true,
            // stack: null

            // Cartesian coordinate system
            // xAxisIndex: 0,
            // yAxisIndex: 0,

            "barMinHeight": 0.0,
            "barMinAngle": 0.0,
            // cursor: null,

            "large": false,
            "largeThreshold": 400.0,
            "progressive": 3e3,
            "progressiveChunkMode": "mod",

            "defaultBarGap": "10%"
        ] as [String: Any]
    }
}

// SeriesModel.registerClass(BaseBarSeriesModel);
// PORT-NOTE: upstream runs this side-effecting registration at module import time. Swift libraries have
//   no import-time hook, so it is exposed as an idempotent static bootstrap the EChartsKit registration
//   entry point must invoke once (mirrors the scale/*.swift `registerScaleClass` precedent).
extension BaseBarSeriesModel {
    @discardableResult
    public static func registerSeriesModelClass() -> Constructor {
        return SeriesModel.registerClass(BaseBarSeriesModel.self)
    }
}

// export default BaseBarSeriesModel;  -> `open class BaseBarSeriesModel` above.


// chart/helper/createSeriesData.ts is now the REAL ported free function `createSeriesData(...)`
// (+ `CreateSeriesDataOpt`) in chart/helper/createSeriesData.swift. The former local stub declared
// here was removed per its own PORT-NOTE note.
