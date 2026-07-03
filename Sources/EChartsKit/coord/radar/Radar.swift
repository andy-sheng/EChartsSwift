// Ported from echarts/src/coord/radar/Radar.ts — keep in sync with upstream
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
//   import IndicatorAxis from './IndicatorAxis';                            -> IndicatorAxis (sibling).
//   import IntervalScale from '../../scale/Interval';                       -> IntervalScale (scale/Interval.swift).
//   import * as numberUtil from '../../util/number';                        -> `number.*` (util/number.swift).
//   import { CoordinateSystemMaster, CoordinateSystem } from '../CoordinateSystem';
//       -> CoordinateSystemMaster (coord/CoordinateSystem.swift). PORT-TODO: upstream also `implements
//       CoordinateSystem`, but Radar's `dataToPoint(value, indicatorIndex)` / `coordToPoint(coord,
//       indicatorIndex)` have radar-specific signatures that do NOT match the `CoordinateSystem`
//       protocol requirements (`dataToPoint(data, opt?)`). Since every use site holds the *concrete*
//       `Radar` type (RadarModel.coordinateSystem `as? Radar`, RadarSeriesModel.radarCoordinateSystem),
//       the `CoordinateSystem` conformance is dropped and the radar-specific methods are plain concrete
//       methods (the `convert*`/`containPoint` members were upstream `console.warn('Not implemented.')`
//       stubs anyway). Radar conforms to `CoordinateSystemMaster` only — what the coord-sys creator needs.
//   import RadarModel, { ... } from './RadarModel';                        -> RadarModel + constants (sibling).
//   import GlobalModel from '../../model/Global';                          -> GlobalModel.
//   import ExtensionAPI from '../../core/ExtensionAPI';                    -> ExtensionAPI.
//   import { ScaleDataValue } from '../../util/types';                     -> ScaleDataValue (util/types.swift).
//   import { ParsedModelFinder } from '../../util/model';                  -> ParsedModelFinder.
//   import { map, each, isString, isNumber } from 'zrender/src/core/util'; -> `util.*` (ZRenderKit).
//   import { scaleCalcAlign } from '../axisAlignTicks';                    -> scaleCalcAlign (coord/axisAlignTicks.swift).
//   import { createBoxLayoutReference } from '../../util/layout';          -> layout.createBoxLayoutReference (util/layout.swift).
//   import { AXIS_EXTENT_INFO_BUILD_FROM_COORD_SYS_UPDATE, scaleRawExtentInfoCreate } from '../scaleRawExtentInfo';
//       -> scaleRawExtentInfoCreate / AXIS_EXTENT_INFO_BUILD_FROM_COORD_SYS_UPDATE (coord/scaleRawExtentInfo.swift).
//   import { ensureValidSplitNumber } from '../../scale/helper';           -> `helper.ensureValidSplitNumber` (scale/helper.swift).
//   import { associateSeriesWithAxis } from '../axisStatistics';           -> associateSeriesWithAxis (coord/axisStatistics.swift).

// upstream: class Radar implements CoordinateSystem, CoordinateSystemMaster { ... }
//   Reference type (like Grid) → `public final class : CoordinateSystemMaster`.
public final class Radar: CoordinateSystemMaster {

    // upstream: readonly type = COORD_SYS_TYPE_RADAR;
    public let type = COORD_SYS_TYPE_RADAR

    // upstream: readonly dimensions: string[] = [];  (populated per-indicator in the constructor).
    //   Also witnesses `CoordinateSystemMaster.dimensions: [DimensionName] { get set }`.
    public var dimensions: [DimensionName] = []

    // upstream: cx / cy / r / r0 / startAngle: number;  (assigned in `resize`).
    public var cx: Double = 0
    public var cy: Double = 0
    public var r: Double = 0
    public var r0: Double = 0
    public var startAngle: Double = 0

    // upstream: private _model: RadarModel;
    private let _model: RadarModel

    // upstream: private _indicatorAxes: IndicatorAxis[];
    private var _indicatorAxes: [IndicatorAxis] = []

    // upstream: constructor(radarModel: RadarModel, ecModel: GlobalModel, api: ExtensionAPI)
    public init(_ radarModel: RadarModel, _ ecModel: GlobalModel, _ api: ExtensionAPI) {
        self._model = radarModel

        // this._indicatorAxes = map(radarModel.getIndicatorModels(), function (indicatorModel, idx) { ... });
        self._indicatorAxes = util.map(radarModel.getIndicatorModels()) { (indicatorModel: AxisBaseModel, idx: Int) -> IndicatorAxis in
            // const dim = 'indicator_' + idx;
            let dim = "indicator_" + String(idx)
            // const indicatorAxis = new IndicatorAxis(dim, new IntervalScale());
            let indicatorAxis = IndicatorAxis(dim, IntervalScale())
            // indicatorAxis.name = indicatorModel.get('name');
            indicatorAxis.name = (indicatorModel.get("name") as? String) ?? ""
            // Inject model and axis
            // indicatorAxis.model = indicatorModel;
            indicatorAxis.model = indicatorModel
            // indicatorModel.axis = indicatorAxis;
            indicatorModel.axis = indicatorAxis
            // this.dimensions.push(dim);
            self.dimensions.append(dim)
            return indicatorAxis
        }

        // this.resize(radarModel, api);
        self.resize(radarModel, api)
    }

    // upstream: getIndicatorAxes() { return this._indicatorAxes; }
    public func getIndicatorAxes() -> [IndicatorAxis] {
        return self._indicatorAxes
    }

    // upstream: dataToPoint(value: ScaleDataValue, indicatorIndex: number)
    //   Radar-specific 2-arg form (value + indicator index); see the CoordinateSystem drop note above.
    public func dataToPoint(_ value: ScaleDataValue, _ indicatorIndex: Double) -> [Double] {
        let indicatorAxis = self._indicatorAxes[Int(indicatorIndex)]
        return self.coordToPoint(indicatorAxis.dataToCoord(value), indicatorIndex)
    }

    // TODO: API should be coordToPoint([coord, indicatorIndex])
    // upstream: coordToPoint(coord: number, indicatorIndex: number)
    public func coordToPoint(_ coord: Double, _ indicatorIndex: Double) -> [Double] {
        let indicatorAxis = self._indicatorAxes[Int(indicatorIndex)]
        let angle = indicatorAxis.angle
        let x = self.cx + coord * cos(angle)
        let y = self.cy - coord * sin(angle)
        return [x, y]
    }

    // upstream: pointToData(pt: number[])
    public func pointToData(_ pt: [Double]) -> [Double] {
        var dx = pt[0] - self.cx
        var dy = pt[1] - self.cy
        let radius = (dx * dx + dy * dy).squareRoot()
        dx /= radius
        dy /= radius

        let radian = atan2(-dy, dx)

        // Find the closest angle
        // FIXME index can calculated directly
        var minRadianDiff = Double.infinity
        var closestAxis: IndicatorAxis?
        var closestAxisIdx = -1
        for i in 0..<self._indicatorAxes.count {
            let indicatorAxis = self._indicatorAxes[i]
            let diff = abs(radian - indicatorAxis.angle)
            if diff < minRadianDiff {
                closestAxis = indicatorAxis
                closestAxisIdx = i
                minRadianDiff = diff
            }
        }

        // return [closestAxisIdx, +(closestAxis && closestAxis.coordToData(radius))];
        //   JS `+(undefined)` is NaN when no axis found; `+(number)` is the number.
        let dataVal = closestAxis != nil ? closestAxis!.coordToData(radius) : Double.nan
        return [Double(closestAxisIdx), dataVal]
    }

    // upstream: resize(radarModel: RadarModel, api: ExtensionAPI)
    public func resize(_ radarModel: RadarModel, _ api: ExtensionAPI) {
        let refContainer = layout.createBoxLayoutReference(radarModel, api).refContainer

        let center = (radarModel.get("center") as? [Any]) ?? []
        // const clockwise = radarModel.get('clockwise') || false;
        let clockwise = (radarModel.get("clockwise") as? Bool) ?? false
        let viewSize = Swift.min(refContainer.width, refContainer.height) / 2
        self.cx = number.parsePercent(center.count > 0 ? center[0] : nil, refContainer.width) + refContainer.x
        self.cy = number.parsePercent(center.count > 1 ? center[1] : nil, refContainer.height) + refContainer.y

        // this.startAngle = radarModel.get('startAngle') * Math.PI / 180;
        //   default startAngle is 90 (stored as an Int literal) → coerce Int→Double, else the whole
        //   radar rotates 90° (axis[0] would point right instead of up).
        let startAngleDeg = radarNumOpt(radarModel.get("startAngle")) ?? 0
        self.startAngle = startAngleDeg * Double.pi / 180

        // radius may be single value like `20`, `'80%'`, or array like `[10, '80%']`
        var radius: [Any]
        let radiusRaw = radarModel.get("radius")
        if util.isString(radiusRaw as Any) || radarIsNumber(radiusRaw) {
            // radius = [0, radius];
            radius = [0.0, radiusRaw as Any]
        }
        else {
            radius = (radiusRaw as? [Any]) ?? [0.0, 0.0]
        }
        self.r0 = number.parsePercent(radius.count > 0 ? radius[0] : nil, viewSize)
        self.r = number.parsePercent(radius.count > 1 ? radius[1] : nil, viewSize)

        let sign: Double = clockwise ? -1 : 1

        // each(this._indicatorAxes, function (indicatorAxis, idx) { ... });
        let count = self._indicatorAxes.count
        for idx in 0..<count {
            let indicatorAxis = self._indicatorAxes[idx]
            indicatorAxis.setExtent(self.r0, self.r)
            // let angle = (this.startAngle + sign * idx * Math.PI * 2 / this._indicatorAxes.length);
            var angle = self.startAngle + sign * Double(idx) * Double.pi * 2 / Double(count)
            // Normalize to [-PI, PI]
            angle = atan2(sin(angle), cos(angle))
            indicatorAxis.angle = angle
        }
    }

    // upstream: update(ecModel: GlobalModel, api: ExtensionAPI)
    //   Witnesses `CoordinateSystemMaster.update` (which has a no-op default in the protocol extension).
    public func update(_ ecModel: GlobalModel, _ api: ExtensionAPI) {
        let indicatorAxes = self._indicatorAxes
        let radarModel = self._model

        let splitNumber = helper.ensureValidSplitNumber(
            radarNumOpt(radarModel.get("splitNumber")), RADAR_DEFAULT_SPLIT_NUMBER
        )
        let dummyScale = IntervalScale()
        dummyScale.setExtent(0, splitNumber)
        dummyScale.setConfig(IntervalScaleConfig(interval: 1))
        // Force all the axis fixing the maxSplitNumber.
        for indicatorAxis in indicatorAxes {
            scaleRawExtentInfoCreate(indicatorAxis, AXIS_EXTENT_INFO_BUILD_FROM_COORD_SYS_UPDATE)
            scaleCalcAlign(indicatorAxis, dummyScale)
        }
    }

    // upstream: convertToPixel/convertFromPixel/containPoint — `console.warn('Not implemented.')` stubs.
    //   `containPoint` has no protocol default, so it is implemented here (returns false as upstream).
    public func containPoint(_ point: [Double]) -> Bool {
        // console.warn('Not implemented.');
        return false
    }

    // upstream: static dimensions: string[] = [];  (Radar dimensions is based on the data.)
    //   The coord-sys creator reports this static (empty) dimension list.
    public static let dimensions: [DimensionName] = []

    // upstream: static create(ecModel: GlobalModel, api: ExtensionAPI)
    public static func create(_ ecModel: GlobalModel, _ api: ExtensionAPI) -> [Radar] {
        var radarList: [Radar] = []
        // ecModel.eachComponent(COMPONENT_TYPE_RADAR, function (radarModel: RadarModel) { ... });
        ecModel.eachComponent(COMPONENT_TYPE_RADAR) { (radarModelComp: ComponentModel, _: Double) in
            guard let radarModel = radarModelComp as? RadarModel else { return }
            let radar = Radar(radarModel, ecModel, api)
            radarList.append(radar)
            radarModel.coordinateSystem = radar
        }
        // ecModel.eachSeriesByType(SERIES_TYPE_RADAR, function (radarSeries) { ... });
        ecModel.eachSeriesByType(SERIES_TYPE_RADAR) { (radarSeries: SeriesModel, _: Double) in
            // if (radarSeries.get('coordinateSystem') === COORD_SYS_TYPE_RADAR) { ... }
            if (radarSeries.get("coordinateSystem") as? String) == COORD_SYS_TYPE_RADAR {
                // Inject coordinate system
                // const radar = radarSeries.coordinateSystem = radarList[radarSeries.get('radarIndex') || 0];
                let radarIndex = Int(radarNumOpt(radarSeries.get("radarIndex")) ?? 0)
                let radar = radarIndex >= 0 && radarIndex < radarList.count ? radarList[radarIndex] : nil
                radarSeries.coordinateSystem = radar
                if let radar = radar {
                    // each(radar.getIndicatorAxes(), function (indicatorAxis) { ... });
                    for indicatorAxis in radar.getIndicatorAxes() {
                        associateSeriesWithAxis(indicatorAxis, radarSeries, COORD_SYS_TYPE_RADAR)
                    }
                }
            }
        }
        return radarList
    }
}

// Coerce a dynamic option value to Double, tolerating the Int boxing that `[String: Any]`
// defaultOption literals use (e.g. `"startAngle": 90`). A bare `as? Double` returns nil on an
// Int, which silently drops the value — the recurring Int-vs-Double option-read trap.
private func radarNumOpt(_ v: Any?) -> Double? {
    if let d = v as? Double { return d }
    if let i = v as? Int { return Double(i) }
    if let n = v as? NSNumber, !(n === kCFBooleanTrue || n === kCFBooleanFalse) { return n.doubleValue }
    return nil
}

// JS `isNumber` for the dynamic radius option value (Double / Int / NSNumber, excluding Bool).
private func radarIsNumber(_ v: Any?) -> Bool {
    switch v {
    case is Double, is Int: return true
    case let n as NSNumber: return !(n === kCFBooleanTrue || n === kCFBooleanFalse)
    default: return false
    }
}

// export default Radar;  -> `public final class Radar` above.
