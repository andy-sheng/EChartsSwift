// Ported from echarts/src/coord/polar/RadiusAxis.ts — keep in sync with upstream
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
//   import Axis from '../Axis';                                        -> Axis (coord/Axis.swift).
//   import Scale from '../../scale/Scale';                             -> Scale (scale/Scale.swift).
//   import Polar from './Polar';                                       -> Polar (sibling, this phase).
//   import { RadiusAxisModel } from './AxisModel';                     -> RadiusAxisModel.
//       PORT-TODO: coord/polar/AxisModel.ts (RadiusAxisModel) is a sibling not yet landed. The
//       inherited `Axis.model: AxisBaseModel!` already provides the model slot (Swift can not narrow
//       the generic option bag; options are read identically) — no re-declaration needed.

// upstream:
//   interface RadiusAxis {
//       dataToRadius: Axis['dataToCoord']
//       radiusToData: Axis['coordToData']
//   }
//   These prototype-aliased members (see the two `RadiusAxis.prototype.* = Axis.prototype.*`
//   assignments at the end of the upstream file) become plain forwarding methods here — Swift has no
//   prototype rebinding.

// upstream: class RadiusAxis extends Axis { ... }
//   Not further subclassed → `final class` (CONVENTIONS §2).
public final class RadiusAxis: Axis {

    // upstream: polar: Polar;  (injected by Polar's constructor: `this._radiusAxis.polar = ... = this`).
    public var polar: Polar!

    // upstream (property narrowing): model: RadiusAxisModel;  — see the import note above.

    // upstream: constructor(scale?: Scale, radiusExtent?: [number, number]) {
    //     super('radius', scale, radiusExtent);
    // }
    //   `scale` is upstream-optional and left `undefined` until `polarCreator` injects the real scale
    //   via `axis.scale = createScaleByModel(...)`. Swift's `Axis.scale` is non-optional, so a fresh
    //   placeholder `IntervalScale()` stands in until injection (mirrors radar's IndicatorAxis).
    public init(_ scale: Scale? = nil, _ radiusExtent: [Double]? = nil) {
        super.init("radius", scale ?? IntervalScale(), radiusExtent)
    }

    // upstream: pointToData(point: number[], clamp?: boolean) {
    //     return this.polar.pointToData(point, clamp)[this.dim === 'radius' ? 0 : 1];
    // }
    public override func pointToData(_ point: [Double], _ clamp: Bool? = nil) -> Double {
        return self.polar.pointToData(point, clamp)[self.dim == "radius" ? 0 : 1]
    }

    // upstream: RadiusAxis.prototype.dataToRadius = Axis.prototype.dataToCoord;
    public func dataToRadius(_ data: ScaleDataValue, _ clamp: Bool? = nil) -> Double {
        return self.dataToCoord(data, clamp)
    }

    // upstream: RadiusAxis.prototype.radiusToData = Axis.prototype.coordToData;
    public func radiusToData(_ coord: Double, _ clamp: Bool? = nil) -> Double {
        return self.coordToData(coord, clamp)
    }
}

// export default RadiusAxis;  -> `public final class RadiusAxis` above.
