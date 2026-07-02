// Ported from echarts/src/coord/cartesian/Axis2D.ts — keep in sync with upstream
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

// import Axis from '../Axis';                                            -> Axis (coord/Axis.swift)
// import { DimensionName, OrdinalSortInfo } from '../../util/types';     -> util/types.swift (DimensionName = String; OrdinalSortInfo struct)
// import Scale from '../../scale/Scale';                                 -> Scale (scale/Scale.swift)
// import CartesianAxisModel, { CartesianAxisPosition } from './AxisModel';
//                                                                        -> CartesianAxisModel / CartesianAxisPosition (coord/cartesian/AxisModel.swift)
//   PORT-TODO: coord/cartesian/AxisModel.swift is a sibling landing this phase; conventional API:
//     - `CartesianAxisModel` (open class : AxisBaseModel)
//     - `public typealias CartesianAxisPosition = String`  (upstream: 'top' | 'bottom' | 'left' | 'right')
// import Grid from './Grid';                                             -> Grid (coord/cartesian/Grid.swift)
//   PORT-TODO: coord/cartesian/Grid.swift is a sibling landing this phase; referenced here only as a
//     back-pointer type (`grid` field). Grid also injects the function-typed fields
//     `getAxesOnZeroOf` / `toGlobalCoord` / `toLocalCoord` on each Axis2D instance.
// import { OptionAxisType } from '../axisCommonTypes';                   -> OptionAxisType (String alias; coord/axisHelper.swift / axisCommonTypes.swift)
// import OrdinalScale from '../../scale/Ordinal';                        -> OrdinalScale (scale/Ordinal.swift)
// import type AxisBuilder from '../../component/axis/AxisBuilder';       -> AxisBuilder (component/axis/AxisBuilder — Phase 6b)
//   PORT-TODO: `AxisBuilder` lives under component/axis (Phase 6b) and is a *type-only* import here
//     (used solely to type the `axisBuilder` field). A minimal placeholder type is provided at the
//     bottom of this file so the field type-checks; remove it when component/axis/AxisBuilder.swift lands.


// upstream: `interface Axis2D { toLocalCoord(...); toGlobalCoord(...); }` merged with the class below.
//   Swift has no declaration merging; the two methods are modeled as function-typed fields on the
//   class (injected outside by Grid, mirroring the `getRotate` field on the base `Axis`).
//
// upstream: class Axis2D extends Axis { ... } — not further subclassed → `final class` (CONVENTIONS §2).
public final class Axis2D: Axis {

    /**
     * Transform global coord to local coord,
     * i.e. let localCoord = axis.toLocalCoord(80);
     */
    // upstream: (interface) toLocalCoord(coord: number): number;  — injected by Grid.
    public var toLocalCoord: ((Double) -> Double)!

    /**
     * Transform global coord to local coord,
     * i.e. let globalCoord = axis.toLocalCoord(40);
     */
    // upstream: (interface) toGlobalCoord(coord: number): number;  — injected by Grid.
    public var toGlobalCoord: ((Double) -> Double)!

    /**
     * Axis position
     *  - 'top'
     *  - 'bottom'
     *  - 'left'
     *  - 'right'
     */
    // upstream: readonly position: CartesianAxisPosition;
    public let position: CartesianAxisPosition

    /**
     * Index of axis, can be used as key
     * Injected outside.
     */
    // upstream: index: number = 0;
    public var index: Double = 0

    /**
     * Axis model. Injected outside
     */
    // upstream: model: CartesianAxisModel;
    // PORT-TODO: upstream narrows the inherited `model: AxisBaseModel` (base `Axis`) to
    //   `CartesianAxisModel`. Swift cannot narrow the type of an inherited settable stored property
    //   (property overrides are invariant), so the inherited `model: AxisBaseModel!` is reused as-is;
    //   callers needing `CartesianAxisModel` cast. The dynamic option bag (`model.option`) is
    //   accessed identically regardless.

    /**
     * Injected outside.
     */
    // upstream: grid: Grid;
    public var grid: Grid!

    /**
     * Injected outside.
     */
    // upstream: axisBuilder: AxisBuilder;
    public var axisBuilder: AxisBuilder!


    // upstream: constructor(dim, scale, coordExtent, axisType?, position?)
    public init(
        _ dim: DimensionName,
        _ scale: Scale,
        _ coordExtent: [Double],
        _ axisType: OptionAxisType? = nil,
        _ position: CartesianAxisPosition? = nil
    ) {
        self.position = position ?? "bottom"  // upstream: this.position = position || 'bottom'; (must precede super.init in Swift)
        super.init(dim, scale, coordExtent)
        self.type = axisType ?? "value"  // upstream: this.type = axisType || 'value';
    }

    /**
     * Implemented in <module:echarts/coord/cartesian/Grid>.
     * @return If not on zero of other axis, return null/undefined.
     *         If no axes, return an empty array.
     */
    // upstream: getAxesOnZeroOf: () => Axis2D[];  — injected by Grid.
    public var getAxesOnZeroOf: (() -> [Axis2D])!

    public func isHorizontal() -> Bool {
        let position = self.position
        return position == "top" || position == "bottom"
    }

    /**
     * Each item cooresponds to this.getExtent(), which
     * means globalExtent[0] may greater than globalExtent[1],
     * unless `asc` is input.
     *
     * @param {boolean} [asc]
     * @return {Array.<number>}
     */
    public func getGlobalExtent(_ asc: Bool? = nil) -> [Double] {
        var ret = self.getExtent()
        ret[0] = self.toGlobalCoord(ret[0])
        ret[1] = self.toGlobalCoord(ret[1])
        // upstream: asc && ret[0] > ret[1] && ret.reverse();
        if asc == true && ret[0] > ret[1] {
            ret.reverse()
        }
        return ret
    }

    public override func pointToData(_ point: [Double], _ clamp: Bool? = nil) -> Double {
        return self.coordToData(self.toLocalCoord(point[self.dim == "x" ? 0 : 1]), clamp)
    }

    /**
     * Set ordinalSortInfo
     * @param info new OrdinalSortInfo
     */
    @discardableResult
    public func setCategorySortInfo(_ info: OrdinalSortInfo) -> Bool {
        if self.type != "category" {
            return false
        }

        // upstream: this.model.option.categorySortInfo = info;
        //   `option` is the dynamic bag (`Any?` holding `[String: Any]`); read-modify-write since the
        //   dict is a value type stored on the (reference) model.
        if var option = self.model.option as? [String: Any] {
            option["categorySortInfo"] = info
            self.model.option = option
        }
        (self.scale as! OrdinalScale).setSortInfo(info)
        // upstream: no explicit return here (implicitly returns `undefined`, which is falsy).
        // PORT-TODO: Swift requires an explicit return; upstream's declared `boolean` return is not
        //   produced on the success path.
        return true
    }

}

// upstream: export default Axis2D;  -> `public final class Axis2D` above.

// PORT-TODO: type-only placeholder for `AxisBuilder` (upstream: component/axis/AxisBuilder — Phase 6b).
//   Only the *type name* is needed here (the `axisBuilder` field). Remove this stub when the real
//   component/axis/AxisBuilder.swift lands to avoid a duplicate declaration.
public final class AxisBuilder {}
