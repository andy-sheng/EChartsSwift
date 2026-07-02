// Ported from echarts/src/coord/cartesian/Cartesian.ts — keep in sync with upstream
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


import ZRenderKit  // upstream: import * as zrUtil from 'zrender/src/core/util';
// import { DimensionName } from '../../util/types';  // typealias DimensionName = String (util/types.swift)
// import Axis from '../Axis';                        // open class Axis (coord/Axis.swift)


// upstream: class Cartesian<AxisT extends Axis> — subclassed by Cartesian2D → `open class`.
open class Cartesian<AxisT: Axis> {

    // upstream: `readonly type: string = 'cartesian'`. Ported as an overridable get-only computed
    //   property (not a stored `let`) so the `Cartesian2D` subclass can shadow it with
    //   `override var type = COORD_SYS_TYPE_CARTESIAN_2D`, mirroring the TS field re-declaration.
    open var type: String { "cartesian" }

    public let name: String

    private var _dimList: [DimensionName] = []

    private var _axes: [DimensionName: AxisT] = [:]


    public init(_ name: String?) {
        self.name = name ?? ""
    }

    // upstream returns AxisT (dict index access typed non-optional); Swift dict lookup is optional.
    public func getAxis(_ dim: DimensionName) -> AxisT? {
        return self._axes[dim]
    }

    public func getAxes() -> [AxisT] {
        return util.map(self._dimList, { dim, _ in
            return self._axes[dim]!
        })
    }

    public func getAxesByScale(_ scaleType: String) -> [AxisT] {
        let scaleType = scaleType.lowercased()
        return util.filter(
            self.getAxes(),
            { axis, _ in
                return axis.scale.type == scaleType
            }
        )
    }

    public func addAxis(_ axis: AxisT) {
        let dim = axis.dim

        self._axes[dim] = axis

        self._dimList.append(dim)
    }


    // FIXME:TS Never used. So comment `dataToCoord` and `coordToData`.
    // /**
    //  * Convert data to coord in nd space
    //  * @param {Array.<number>|Object.<string, number>} val
    //  * @return {Array.<number>|Object.<string, number>}
    //  */
    // dataToCoord(val) {
    //     return this._dataCoordConvert(val, 'dataToCoord');
    // }

    // /**
    //  * Convert coord in nd space to data
    //  * @param  {Array.<number>|Object.<string, number>} val
    //  * @return {Array.<number>|Object.<string, number>}
    //  */
    // coordToData(val) {
    //     return this._dataCoordConvert(val, 'coordToData');
    // }

    // _dataCoordConvert(input, method) {
    //     let dimList = this._dimList;

    //     let output = input instanceof Array ? [] : {};

    //     for (let i = 0; i < dimList.length; i++) {
    //         let dim = dimList[i];
    //         let axis = this._axes[dim];

    //         output[dim] = axis[method](input[dim]);
    //     }

    //     return output;
    // }
}

// upstream: export default Cartesian; -> `open class Cartesian` above.
