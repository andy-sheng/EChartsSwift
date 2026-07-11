// Ported from echarts/src/coord/axisModelCommonMixin.ts — keep in sync with upstream
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
// import Model from '../model/Model';                                  -> Model (EChartsKit model/Model.swift)
// import Axis from './Axis';                                           -> Axis  (coord/Axis.swift)
// import { AxisBaseOption, ValueAxisBaseOption } from './axisCommonTypes'; -> AxisBaseOption / ValueAxisBaseOption
//     (coord/axisCommonTypes.swift; PORT-NOTE: option interfaces not yet ported — dynamic bag used)
// import { CoordinateSystemHostModel } from './CoordinateSystem';      -> CoordinateSystemHostModel
//     (coord/CoordinateSystem.swift, T2; PORT-NOTE: ported — still typed as `Any?` here)

// PORT-NOTE: upstream is a mixin (`interface` + `class` declaration-merged, grafted onto axis
//   models via `applyMixin` / `util.inherits`). Per CONVENTIONS §2 mixins are ported as a
//   protocol + protocol-extension that preserves the upstream method set. The
//   `Pick<Model<Opt>, 'option'>` and `axis: Axis` members of the interface become protocol
//   requirements; conforming axis models (AxisBaseModel + AxisModel, later phases) satisfy
//   `option` through their `Model` inheritance and declare `axis` themselves.

// upstream:
// interface AxisModelCommonMixin<Opt extends AxisBaseOption> extends Pick<Model<Opt>, 'option'> {
//     axis: Axis;
// }
public protocol AxisModelCommonMixin: AnyObject {

    // From Pick<Model<Opt>, 'option'>
    var option: ModelOption? { get }

    // PORT-NOTE: coord/Axis.swift is ported; `axis` is still typed as `Any` here.
    var axis: Any { get }
}

// eslint-disable-next-line @typescript-eslint/no-unused-vars
// class AxisModelCommonMixin<Opt extends AxisBaseOption>
public extension AxisModelCommonMixin {

    func needIncludeZero() -> Bool {
        // return !(this.option as ValueAxisBaseOption).scale;
        // PORT-NOTE: ValueAxisBaseOption not ported — read `scale` from the dynamic option bag.
        //   JS truthiness: a missing/false `scale` yields `true` here.
        let scale = (self.option as? [String: Any])?["scale"] as? Bool ?? false
        return !scale
    }

    /**
     * Should be implemented by each axis model if necessary.
     * @return coordinate system model
     */
    // upstream: getCoordSysModel(): CoordinateSystemHostModel
    // PORT-NOTE: CoordinateSystemHostModel (coord/CoordinateSystem.swift, T2) is ported —
    //   still typed as `Any?` here. Upstream returns `undefined` here; overridden by each axis model.
    func getCoordSysModel() -> Any? {
        return nil
    }

}

// export {AxisModelCommonMixin};
