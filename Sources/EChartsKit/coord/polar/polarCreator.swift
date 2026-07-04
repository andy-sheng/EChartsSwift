// Ported from echarts/src/coord/polar/polarCreator.ts — keep in sync with upstream
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
//   import * as zrUtil from 'zrender/src/core/util';                       -> `util.*` (ZRenderKit).
//   import Polar, { polarDimensions } from './Polar';                      -> Polar + polarDimensions (sibling, Polar.swift).
//   import {parsePercent} from '../../util/number';                        -> `number.parsePercent` (util/number.swift).
//   import { createScaleByModel, determineAxisType, isAxisOnBand } from '../../coord/axisHelper';
//       -> `axisHelper.*` (coord/axisHelper.swift).
//   import PolarModel, { COMPONENT_TYPE_POLAR, COORD_SYS_TYPE_POLAR } from './PolarModel';
//       -> PolarModel + constants (sibling, PolarModel.swift).
//   import ExtensionAPI from '../../core/ExtensionAPI';                    -> ExtensionAPI (core/ExtensionAPI.swift).
//   import GlobalModel from '../../model/Global';                          -> GlobalModel.
//   import OrdinalScale from '../../scale/Ordinal';                        -> OrdinalScale (scale/Ordinal.swift).
//   import RadiusAxis from './RadiusAxis';                                 -> RadiusAxis (sibling, RadiusAxis.swift).
//   import AngleAxis from './AngleAxis';                                   -> AngleAxis (sibling, AngleAxis.swift).
//   import { PolarAxisModel, AngleAxisModel, RadiusAxisModel } from './AxisModel';
//       -> PolarAxisModel / AngleAxisModel / RadiusAxisModel (sibling, AxisModel.swift).
//   import SeriesModel from '../../model/Series';                          -> SeriesModel.
//   import { SeriesOption } from '../../util/types';                       -> collapsed (dynamic option bag).
//   import { SINGLE_REFERRING } from '../../util/model';                   -> `model.SINGLE_REFERRING` (util/modelUtil.swift).
//   import { createBoxLayoutReference } from '../../util/layout';          -> `layout.createBoxLayoutReference` (util/layout.swift).
//   import { scaleCalcNice } from '../axisNiceTicks';                      -> `scaleCalcNice` (coord/axisNiceTicks.swift).
//   import { AXIS_EXTENT_INFO_BUILD_FROM_COORD_SYS_UPDATE, scaleRawExtentInfoCreate } from '../scaleRawExtentInfo';
//       -> scaleRawExtentInfoCreate / AXIS_EXTENT_INFO_BUILD_FROM_COORD_SYS_UPDATE (coord/scaleRawExtentInfo.swift).
//   import { associateSeriesWithAxis } from '../axisStatistics';          -> associateSeriesWithAxis (coord/axisStatistics.swift).

/**
 * Resize method bound to the polar
 */
// upstream: function resizePolar(polar: Polar, polarModel: PolarModel, api: ExtensionAPI)
private func resizePolar(_ polar: Polar, _ polarModel: PolarModel, _ api: ExtensionAPI) {
    // const center = polarModel.get('center');
    let center = (polarModel.get("center") as? [Any]) ?? []

    // const refContainer = createBoxLayoutReference(polarModel, api).refContainer;
    let refContainer = layout.createBoxLayoutReference(polarModel, api).refContainer

    // polar.cx = parsePercent(center[0], refContainer.width) + refContainer.x;
    polar.cx = number.parsePercent(center.count > 0 ? center[0] : nil, refContainer.width) + refContainer.x
    // polar.cy = parsePercent(center[1], refContainer.height) + refContainer.y;
    polar.cy = number.parsePercent(center.count > 1 ? center[1] : nil, refContainer.height) + refContainer.y

    // const radiusAxis = polar.getRadiusAxis();
    let radiusAxis = polar.getRadiusAxis()
    // const size = Math.min(refContainer.width, refContainer.height) / 2;
    let size = Swift.min(refContainer.width, refContainer.height) / 2

    // let radius = polarModel.get('radius');
    var radius: [Any]
    let radiusRaw = polarModel.get("radius")
    if radiusRaw == nil {
        // radius = [0, '100%'];
        radius = [0.0, "100%"]
    }
    else if !util.isArray(radiusRaw) {
        // r0 = 0
        // radius = [0, radius];
        radius = [0.0, radiusRaw as Any]
    }
    else {
        radius = (radiusRaw as? [Any]) ?? [0.0, 0.0]
    }
    // const parsedRadius = [parsePercent(radius[0], size), parsePercent(radius[1], size)];
    let parsedRadius = [
        number.parsePercent(radius.count > 0 ? radius[0] : nil, size),
        number.parsePercent(radius.count > 1 ? radius[1] : nil, size)
    ]

    // radiusAxis.inverse ? radiusAxis.setExtent(parsedRadius[1], parsedRadius[0])
    //                    : radiusAxis.setExtent(parsedRadius[0], parsedRadius[1]);
    if radiusAxis.inverse {
        radiusAxis.setExtent(parsedRadius[1], parsedRadius[0])
    }
    else {
        radiusAxis.setExtent(parsedRadius[0], parsedRadius[1])
    }
}

/**
 * Update polar
 */
// upstream: function updatePolarScale(this: Polar, ecModel: GlobalModel, api: ExtensionAPI)
//   `this` is the Polar the method is injected onto (see `polar.update = updatePolarScale` in `create`);
//   ported as an explicit leading `polar` parameter. The sibling Polar class stores this closure and
//   its `update(_:_:)` (CoordinateSystemMaster requirement) forwards to it — see integration notes.
func updatePolarScale(_ polar: Polar, _ ecModel: GlobalModel, _ api: ExtensionAPI) {
    // const angleAxis = polar.getAngleAxis();
    let angleAxis = polar.getAngleAxis()
    // const radiusAxis = polar.getRadiusAxis();
    let radiusAxis = polar.getRadiusAxis()

    scaleRawExtentInfoCreate(angleAxis, AXIS_EXTENT_INFO_BUILD_FROM_COORD_SYS_UPDATE)
    scaleRawExtentInfoCreate(radiusAxis, AXIS_EXTENT_INFO_BUILD_FROM_COORD_SYS_UPDATE)

    scaleCalcNice(ScaleCalcNiceAxisLike(scale: angleAxis.scale, model: angleAxis.model))
    scaleCalcNice(ScaleCalcNiceAxisLike(scale: radiusAxis.scale, model: radiusAxis.model))

    // Fix extent of category angle axis
    // if (angleAxis.type === 'category' && !angleAxis.onBand) { ... }
    if angleAxis.type == "category" && !angleAxis.onBand {
        // const extent = angleAxis.getExtent();
        var extent = angleAxis.getExtent()
        // const diff = 360 / (angleAxis.scale as OrdinalScale).count();
        let diff = 360 / (angleAxis.scale as! OrdinalScale).count()
        // angleAxis.inverse ? (extent[1] += diff) : (extent[1] -= diff);
        if angleAxis.inverse {
            extent[1] += diff
        }
        else {
            extent[1] -= diff
        }
        // angleAxis.setExtent(extent[0], extent[1]);
        angleAxis.setExtent(extent[0], extent[1])
    }
}

// upstream: function isAngleAxisModel(axisModel): axisModel is AngleAxisModel
//   { return axisModel.mainType === 'angleAxis'; }
private func isAngleAxisModel(_ axisModel: PolarAxisModel) -> Bool {
    return axisModel.mainType == "angleAxis"
}

/**
 * Set common axis properties
 */
// upstream: function setAxis(axis: RadiusAxis | AngleAxis, axisModel: PolarAxisModel)
private func setAxis(_ axis: Axis, _ axisModel: PolarAxisModel) {
    // axis.type = determineAxisType(axisModel);
    axis.type = axisHelper.determineAxisType(axisModel)
    // axis.scale = createScaleByModel(axisModel, axis.type, false);
    axis.scale = axisHelper.createScaleByModel(axisModel, axis.type, false)
    // axis.onBand = isAxisOnBand(axis.scale, axisModel);
    axis.onBand = axisHelper.isAxisOnBand(axis.scale, axisModel)
    // axis.inverse = axisModel.get('inverse');
    axis.inverse = (axisModel.get("inverse") as? Bool) ?? false

    // if (isAngleAxisModel(axisModel)) { ... }
    if isAngleAxisModel(axisModel) {
        // axis.inverse = axis.inverse !== axisModel.get('clockwise');
        let clockwise = (axisModel.get("clockwise") as? Bool) ?? false
        axis.inverse = axis.inverse != clockwise
        // const startAngle = axisModel.get('startAngle');
        //   default `startAngle` is stored as an Int literal (e.g. 90) → coerce Int→Double, else the
        //   whole polar rotates (the Int-vs-Double option-read trap).
        let startAngle = asNumberOpt(axisModel.get("startAngle")) ?? 0
        // const endAngle = axisModel.get('endAngle') ?? (startAngle + (axis.inverse ? -360 : 360));
        let endAngle = asNumberOpt(axisModel.get("endAngle")) ?? (startAngle + (axis.inverse ? -360 : 360))
        // axis.setExtent(startAngle, endAngle);
        axis.setExtent(startAngle, endAngle)
    }

    // Inject axis instance
    // axisModel.axis = axis;
    axisModel.axis = axis
    // axis.model = axisModel as AngleAxisModel | RadiusAxisModel;
    axis.model = axisModel
}

// upstream: const polarCreator = { dimensions, create };  (object literal → caseless enum namespace).
public enum polarCreator {

    // dimensions: polarDimensions,
    public static let dimensions: [DimensionName] = polarDimensions

    // create: function (ecModel: GlobalModel, api: ExtensionAPI) { ... }
    public static func create(_ ecModel: GlobalModel, _ api: ExtensionAPI) -> [Polar] {
        // const polarList: Polar[] = [];
        var polarList: [Polar] = []
        // ecModel.eachComponent(COMPONENT_TYPE_POLAR, function (polarModel: PolarModel, idx: number) { ... });
        ecModel.eachComponent(COMPONENT_TYPE_POLAR) { (polarModelComp: ComponentModel, idx: Double) in
            guard let polarModel = polarModelComp as? PolarModel else { return }
            // const polar = new Polar(idx + '');
            let polar = Polar(String(Int(idx)))
            // Inject resize and update method
            // polar.update = updatePolarScale;
            polar.updateHook = updatePolarScale

            // const radiusAxis = polar.getRadiusAxis();
            let radiusAxis = polar.getRadiusAxis()
            // const angleAxis = polar.getAngleAxis();
            let angleAxis = polar.getAngleAxis()

            // const radiusAxisModel = polarModel.findAxisModel('radiusAxis');
            let radiusAxisModel = polarModel.findAxisModel("radiusAxis")
            // const angleAxisModel = polarModel.findAxisModel('angleAxis');
            let angleAxisModel = polarModel.findAxisModel("angleAxis")

            // setAxis(radiusAxis, radiusAxisModel);
            //   upstream findAxisModel is non-null (PolarModel.dependencies guarantees the axis models
            //   exist); force-unwrapped here (the polar axis models are registered concrete classes).
            setAxis(radiusAxis, radiusAxisModel!)
            // setAxis(angleAxis, angleAxisModel);
            setAxis(angleAxis, angleAxisModel!)

            // resizePolar(polar, polarModel, api);
            resizePolar(polar, polarModel, api)

            // polarList.push(polar);
            polarList.append(polar)

            // polarModel.coordinateSystem = polar;
            polarModel.coordinateSystem = polar
            // polar.model = polarModel;
            polar.model = polarModel
        }
        // Inject coordinateSystem to series
        // ecModel.eachSeries(function (seriesModel) { ... });
        ecModel.eachSeries { (seriesModel: SeriesModel, _: Double) in
            // if (seriesModel.get('coordinateSystem') === COORD_SYS_TYPE_POLAR) { ... }
            if (seriesModel.get("coordinateSystem") as? String) == COORD_SYS_TYPE_POLAR {
                // const polarModel = seriesModel.getReferringComponents(
                //     COMPONENT_TYPE_POLAR, SINGLE_REFERRING
                // ).models[0] as PolarModel;
                let polarModel = seriesModel.getReferringComponents(
                    COMPONENT_TYPE_POLAR, model.SINGLE_REFERRING
                ).models.first as? PolarModel

                if __DEV__ {
                    // if (!polarModel) { throw new Error('Polar "' + zrUtil.retrieve(...) + '" not found'); }
                    if polarModel == nil {
                        // PORT-TODO: upstream `throw new Error('Polar "' + zrUtil.retrieve(polarIndex, polarId, 0)
                        //   + '" not found')`. `eachSeries`'s callback is non-throwing, so a fatalError stands in
                        //   for the dev-only throw. `retrieve` (first non-null of index/id/0) is inlined below
                        //   rather than calling `util.retrieve` — its variadic generic cannot unify Double?/String?.
                        var polarRef: Any = 0
                        if let polarIndex = asNumberOpt(seriesModel.get("polarIndex")) {
                            polarRef = polarIndex
                        }
                        else if let polarId = seriesModel.get("polarId") as? String {
                            polarRef = polarId
                        }
                        fatalError("Polar \"\(polarRef)\" not found")
                    }
                }
                // const polar = seriesModel.coordinateSystem = polarModel.coordinateSystem;
                //   PolarModel.coordinateSystem is typed `CoordinateSystemMaster?` (mirroring RadarModel),
                //   so narrow to the concrete `Polar` for the `getRadiusAxis()`/`getAngleAxis()` calls below.
                let polar = polarModel?.coordinateSystem as? Polar
                seriesModel.coordinateSystem = polar
                // if (polar) { ... }
                if let polar = polar {
                    associateSeriesWithAxis(polar.getRadiusAxis(), seriesModel, COORD_SYS_TYPE_POLAR)
                    associateSeriesWithAxis(polar.getAngleAxis(), seriesModel, COORD_SYS_TYPE_POLAR)
                }
            }
        }

        // return polarList;
        return polarList
    }
}

// export default polarCreator;  -> `public enum polarCreator` above.

// Coerce a dynamic option value to Double, tolerating the Int boxing that `[String: Any]`
// defaultOption literals use (e.g. `"startAngle": 90`). A bare `as? Double` returns nil on an
// Int, which silently drops the value — the recurring Int-vs-Double option-read trap.
private func asNumberOpt(_ v: Any?) -> Double? {
    if let d = v as? Double { return d }
    if let i = v as? Int { return Double(i) }
    if let n = v as? NSNumber, !(n === kCFBooleanTrue || n === kCFBooleanFalse) { return n.doubleValue }
    return nil
}
