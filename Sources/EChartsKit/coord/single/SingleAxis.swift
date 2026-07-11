// Ported from echarts/src/coord/single/SingleAxis.ts — keep in sync with upstream
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
//   import Axis from '../Axis';                                        -> Axis (coord/Axis.swift, base class).
//   import Scale from '../../scale/Scale';                             -> Scale (scale/Scale.swift).
//   import { OptionAxisType } from '../axisCommonTypes';               -> OptionAxisType (String alias).
//   import SingleAxisModel, { SingleAxisPosition } from './AxisModel'; -> SingleAxisModel / SingleAxisPosition.
//       PORT-NOTE: `SingleAxisModel` is landed (coord/single/SingleAxisModel.swift — named
//       `SingleAxisModel.swift`, NOT `AxisModel.swift`, to avoid a SwiftPM object-name collision with the
//       existing coord/cartesian/AxisModel.swift). It exports:
//         - `public typealias SingleAxisPosition = String`  (upstream: 'top' | 'bottom' | 'left' | 'right')
//         - `open class SingleAxisModel: AxisBaseModel` with narrowed `axis: SingleAxis` /
//           `coordinateSystem: Single`.
//       The inherited `Axis.model: AxisBaseModel!` already supplies the model slot (upstream narrows it to
//       `SingleAxisModel`, but Swift cannot narrow an inherited settable stored property — see Axis2D for
//       the same convention; callers cast where they need the concrete `SingleAxisModel`).
//   import { LayoutOrient } from '../../util/types';                   -> LayoutOrient (util/types.swift, String-raw enum).
//   import Single from './Single';                                     -> Single (sibling, this batch).

// upstream:
//   interface SingleAxis {
//       toLocalCoord(coord: number): number;
//       toGlobalCoord(coord: number): number;
//   }
//   These are declaration-merged onto the class and injected per-instance by `Single._updateAxisTransform`.
//   Swift has no declaration merging → modeled as injectable function-typed fields (mirroring Axis2D's
//   `toLocalCoord` / `toGlobalCoord`, and the base `Axis.getRotate`).

// upstream: class SingleAxis extends Axis { ... }
//   Not further subclassed → `final class` (CONVENTIONS §2).
public final class SingleAxis: Axis {

    /**
     * Transform global coord to local coord,
     * i.e. let localCoord = axis.toLocalCoord(80);
     */
    // upstream: (interface) toLocalCoord(coord: number): number;  — injected by Single.
    public var toLocalCoord: ((Double) -> Double)!

    /**
     * Transform global coord to local coord,
     * i.e. let globalCoord = axis.toLocalCoord(40);
     */
    // upstream: (interface) toGlobalCoord(coord: number): number;  — injected by Single.
    public var toGlobalCoord: ((Double) -> Double)!

    // upstream: position: SingleAxisPosition;  (set in the constructor / by axisModel).
    public var position: SingleAxisPosition

    // upstream: orient: LayoutOrient;  (injected by `Single._init`).
    public var orient: LayoutOrient = .horizontal

    // upstream: coordinateSystem: Single;  (injected by `Single._init`).
    public var coordinateSystem: Single!

    // upstream (property narrowing): model: SingleAxisModel;  — see the import note above; the inherited
    //   `Axis.model: AxisBaseModel!` slot is reused (Swift cannot narrow an inherited stored property).

    // upstream:
    //   constructor(dim, scale, coordExtent, axisType?, position?) {
    //       super(dim, scale, coordExtent);
    //       this.type = axisType || 'value';
    //       this.position = position || 'bottom';
    //   }
    public init(
        _ dim: String,
        _ scale: Scale,
        _ coordExtent: [Double],
        _ axisType: OptionAxisType? = nil,
        _ position: SingleAxisPosition? = nil
    ) {
        self.position = position ?? "bottom"  // must precede super.init in Swift; upstream: position || 'bottom'
        super.init(dim, scale, coordExtent)
        self.type = axisType ?? "value"  // upstream: this.type = axisType || 'value';
    }

    /**
     * Judge the orient of the axis.
     */
    // upstream: isHorizontal() { const position = this.position; return position === 'top' || position === 'bottom'; }
    public func isHorizontal() -> Bool {
        let position = self.position
        return position == "top" || position == "bottom"
    }

    // upstream: pointToData(point: number[], clamp?: boolean) { return this.coordinateSystem.pointToData(point)[0]; }
    //   TODO(upstream): clamp is not used.
    public override func pointToData(_ point: [Double], _ clamp: Bool? = nil) -> Double {
        return self.coordinateSystem.pointToData(point)[0]
    }
}

// export default SingleAxis;  -> `public final class SingleAxis` above.
