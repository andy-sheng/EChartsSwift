// Ported from echarts/src/coord/polar/AngleAxis.ts — keep in sync with upstream
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
//   import * as textContain from 'zrender/src/contain/text';           -> `text.*` (ZRenderKit Contain/ContainText.swift).
//   import Axis from '../Axis';                                        -> Axis (coord/Axis.swift).
//   import {makeInner} from '../../util/model';                        -> `model.makeInner` (util/modelUtil.swift).
//   import Scale from '../../scale/Scale';                             -> Scale (scale/Scale.swift).
//   import OrdinalScale from '../../scale/Ordinal';                    -> OrdinalScale (scale/Ordinal.swift).
//   import Polar from './Polar';                                       -> Polar (sibling, this phase).
//   import { AngleAxisModel } from './AxisModel';                      -> AngleAxisModel.
//       PORT-TODO: coord/polar/AxisModel.ts (AngleAxisModel) is a sibling not yet landed. The inherited
//       `Axis.model: AxisBaseModel!` already provides the model slot — no re-declaration needed.

// upstream:
//   const inner = makeInner<{
//       lastAutoInterval: number
//       lastTickCount: number
//   }, AngleAxisModel>();
//   Object-literal cache record → `final class` (identity-keyed on the model host; both fields lazily
//   populated so modeled as optional Doubles matching the upstream `!= null` checks).
private final class AngleAxisInnerCache {
    var lastAutoInterval: Double?
    var lastTickCount: Double?
}
private let angleAxisInner: (AxisBaseModel) -> AngleAxisInnerCache = model.makeInner { AngleAxisInnerCache() }

// upstream:
//   interface AngleAxis {
//       dataToAngle: Axis['dataToCoord']
//       angleToData: Axis['coordToData']
//   }
//   Prototype-aliased members (see the two `AngleAxis.prototype.* = Axis.prototype.*` assignments at
//   the end of the upstream file) become plain forwarding methods here.

// upstream: class AngleAxis extends Axis { ... }
//   Not further subclassed → `final class` (CONVENTIONS §2).
public final class AngleAxis: Axis {

    // upstream: polar: Polar;  (injected by Polar's constructor).
    public var polar: Polar!

    // upstream (property narrowing): model: AngleAxisModel;  — see the import note above.

    // upstream: constructor(scale?: Scale, angleExtent?: [number, number]) {
    //     super('angle', scale, angleExtent || [0, 360]);
    // }
    //   `scale` is upstream-optional, left `undefined` until `polarCreator` injects the real scale;
    //   a placeholder `IntervalScale()` stands in until then (see RadiusAxis for the same note).
    public init(_ scale: Scale? = nil, _ angleExtent: [Double]? = nil) {
        super.init("angle", scale ?? IntervalScale(), angleExtent ?? [0, 360])
    }

    // upstream: pointToData(point: number[], clamp?: boolean) {
    //     return this.polar.pointToData(point, clamp)[this.dim === 'radius' ? 0 : 1];
    // }
    public override func pointToData(_ point: [Double], _ clamp: Bool? = nil) -> Double {
        return self.polar.pointToData(point, clamp)[self.dim == "radius" ? 0 : 1]
    }

    /**
     * Only be called in category axis.
     * Angle axis uses text height to decide interval
     *
     * @override
     * @return {number} Auto interval for cateogry axis tick and label
     */
    // upstream: calculateCategoryInterval() { ... }
    //   The upstream override takes no argument; the ported base signature carries an optional
    //   `AxisLabelsComputingContext?` param (unused here) so this overrides it.
    public override func calculateCategoryInterval(_ ctx: AxisLabelsComputingContext? = nil) -> Double {
        let axis = self
        let labelModel = axis.getLabelModel()

        // upstream: const ordinalScale = axis.scale as OrdinalScale;
        let ordinalScale = axis.scale as! OrdinalScale
        let ordinalExtent = ordinalScale.getExtent()
        // Providing this method is for optimization:
        // avoid generating a long array by `getTicks`
        // in large category data case.
        let tickCount = ordinalScale.count()

        if ordinalExtent[1] - ordinalExtent[0] < 1 {
            return 0
        }

        let tickValue = ordinalExtent[0]
        // upstream: const unitSpan = axis.dataToCoord(tickValue + 1) - axis.dataToCoord(tickValue);
        let unitSpan = axis.dataToCoord(tickValue + 1) - axis.dataToCoord(tickValue)
        let unitH = abs(unitSpan)

        // Not precise, just use height as text width
        // and each distance from axis line yet.
        // upstream: textContain.getBoundingRect(tickValue == null ? '' : tickValue + '', labelModel.getFont(), 'center', 'top')
        //   `tickValue` here is the numeric ordinal index (never null); `tickValue + ''` is its string form.
        let rect = text.getBoundingRect(
            String(tickValue),
            labelModel.getFont(),
            .center,
            .top
        )
        let maxH = Swift.max(rect.height, 7)

        var dh = maxH / unitH
        // 0/0 is NaN, 1/0 is Infinity.
        if dh.isNaN { dh = .infinity }
        var interval = Swift.max(0, dh.rounded(.down))  // upstream: Math.max(0, Math.floor(dh))

        let cache = angleAxisInner(axis.model)
        let lastAutoInterval = cache.lastAutoInterval
        let lastTickCount = cache.lastTickCount

        // Use cache to keep interval stable while moving zoom window,
        // otherwise the calculated interval might jitter when the zoom
        // window size is close to the interval-changing size.
        if lastAutoInterval != nil
            && lastTickCount != nil
            && abs(lastAutoInterval! - interval) <= 1
            && abs(lastTickCount! - tickCount) <= 1
            // Always choose the bigger one, otherwise the critical
            // point is not the same when zooming in or zooming out.
            && lastAutoInterval! > interval
        {
            interval = lastAutoInterval!
        }
        // Only update cache if cache not used, otherwise the
        // changing of interval is too insensitive.
        else {
            cache.lastTickCount = tickCount
            cache.lastAutoInterval = interval
        }

        return interval
    }

    // upstream: AngleAxis.prototype.dataToAngle = Axis.prototype.dataToCoord;
    public func dataToAngle(_ data: ScaleDataValue, _ clamp: Bool? = nil) -> Double {
        return self.dataToCoord(data, clamp)
    }

    // upstream: AngleAxis.prototype.angleToData = Axis.prototype.coordToData;
    public func angleToData(_ coord: Double, _ clamp: Bool? = nil) -> Double {
        return self.coordToData(coord, clamp)
    }
}

// export default AngleAxis;  -> `public final class AngleAxis` above.
