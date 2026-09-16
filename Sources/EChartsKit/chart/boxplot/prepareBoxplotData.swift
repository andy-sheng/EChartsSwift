// Ported from echarts/src/chart/boxplot/prepareBoxplotData.ts — keep in sync with upstream
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
//   import { quantile, asc } from '../../util/number';                  -> `number.quantile` / `number.asc`.
//   import { isFunction, isString } from 'zrender/src/core/util';       -> `util.isFunction` / `util.isString`.

// upstream:
//   export interface PrepareBoxplotDataOpt {
//       boundIQR?: number | 'none';
//       itemNameFormatter?: string | ((params: { value: number }) => string);
//   }
public struct PrepareBoxplotDataOpt {
    // upstream `number | 'none'` union -> `Any?` (a `Double` or the string 'none').
    public var boundIQR: Any?
    // Like "expriment{value}" produce: "expriment0", "expriment1", ...
    // upstream `string | ((params: { value: number }) => string)` union -> `Any?` (a `String`
    //   or a `(Double) -> String` closure; the `{ value }` param object is flattened to the bare value).
    public var itemNameFormatter: Any?
    public init(boundIQR: Any? = nil, itemNameFormatter: Any? = nil) {
        self.boundIQR = boundIQR
        self.itemNameFormatter = itemNameFormatter
    }
}

// upstream: the anonymous return type `{ boxData; outliers }`.
//   boxData/outliers elements are `(number | string)[]` (a mixed itemName-string + numbers row) -> `[Any]`.
public struct PrepareBoxplotDataResult {
    public var boxData: [[Any]]
    public var outliers: [[Any]]
    public init(boxData: [[Any]], outliers: [[Any]]) {
        self.boxData = boxData
        self.outliers = outliers
    }
}

/**
 * See:
 *  <https://en.wikipedia.org/wiki/Box_plot#cite_note-frigge_hoaglin_iglewicz-2>
 *  <http://stat.ethz.ch/R-manual/R-devel/library/grDevices/html/boxplot.stats.html>
 *
 * Helper method for preparing data.
 *
 * @param rawData like
 *        [
 *            [12,232,443], (raw data set for the first box)
 *            [3843,5545,1232], (raw data set for the second box)
 *            ...
 *        ]
 * @param opt.boundIQR=1.5 Data less than min bound is outlier.
 *      default 1.5, means Q1 - 1.5 * (Q3 - Q1).
 *      If 'none'/0 passed, min bound will not be used.
 */
// upstream `export default function prepareBoxplotData(rawData, opt)` -> free function (CONVENTIONS §2).
public func prepareBoxplotData(
    _ rawData: [[Double]],
    _ opt: PrepareBoxplotDataOpt?
) -> PrepareBoxplotDataResult {
    // opt = opt || {};
    let opt = opt ?? PrepareBoxplotDataOpt()
    var boxData: [[Any]] = []
    var outliers: [[Any]] = []
    let boundIQR = opt.boundIQR
    // const useExtreme = boundIQR === 'none' || boundIQR === 0;
    let useExtreme = (boundIQR as? String) == "none" || (boundIQR as? Double) == 0

    for i in 0..<rawData.count {
        let ascList = number.asc(rawData[i])   // rawData[i].slice() — asc copies internally

        let Q1 = number.quantile(ascList, 0.25)
        let Q2 = number.quantile(ascList, 0.5)
        let Q3 = number.quantile(ascList, 0.75)
        let min = ascList[0]
        let max = ascList[ascList.count - 1]

        // const bound = (boundIQR == null ? 1.5 : boundIQR as number) * (Q3 - Q1);
        let bound = (boundIQR == nil ? 1.5 : (boundIQR as? Double ?? Double.nan)) * (Q3 - Q1)

        let low = useExtreme
            ? min
            : Swift.max(min, Q1 - bound)
        let high = useExtreme
            ? max
            : Swift.min(max, Q3 + bound)

        let itemNameFormatter = opt.itemNameFormatter
        let itemName: String
        if let fn = itemNameFormatter as? (Double) -> String {
            itemName = fn(Double(i))
        }
        else if let s = itemNameFormatter as? String {
            itemName = s.replacingOccurrences(of: "{value}", with: "\(i)")
        }
        else {
            itemName = "\(i)"   // i + ''
        }

        boxData.append([itemName, low, Q1, Q2, Q3, high])

        for j in 0..<ascList.count {
            let dataItem = ascList[j]
            if dataItem < low || dataItem > high {
                let outlier: [Any] = [itemName, dataItem]
                outliers.append(outlier)
            }
        }
    }
    return PrepareBoxplotDataResult(
        boxData: boxData,
        outliers: outliers
    )
}
