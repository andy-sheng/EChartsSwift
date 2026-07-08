// Ported from echarts/src/processor/negativeDataFilter.ts — keep in sync with upstream
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

// import { isNumber } from 'zrender/src/core/util';
// import { StageHandler } from '../util/types';

// export default function negativeDataFilter(seriesType: string): StageHandler
public func negativeDataFilter(_ seriesType: String) -> StageHandler {
    var handler = StageHandler()
    handler.seriesType = seriesType
    handler.reset = { seriesModel, _, _, _ in
        let data = seriesModel.getData()
        // upstream `data.filterSelf(function (idx) {...})`. The port's `FilterCb` receives an args array;
        //   with no dims the trailing (only) element is the dataIndex `i` (DataStore.filter: `cb([Double(i)])`).
        _ = data.filterSelf { args in
            let idx = Int(negativeDataFilterNumberOf(args.last) ?? 0)
            // handle negative value condition
            guard let valueDim = data.mapDimension("value") else { return true }
            let curValue = data.get(valueDim, idx)
            // upstream: isNumber(curValue) && !isNaN(curValue) && curValue < 0 -> drop
            if let num = negativeDataFilterNumberOf(curValue), !num.isNaN, num < 0 {
                return false
            }
            return true
        }
        return nil
    }
    return handler
}

// upstream `isNumber(curValue)`: true only when the raw value is a JS number. A boxed String / nil
// is not a number, so those data are kept (return nil here → the caller keeps them).
private func negativeDataFilterNumberOf(_ v: Any?) -> Double? {
    guard let v = v else { return nil }
    if let d = v as? Double { return d }
    if let i = v as? Int { return Double(i) }
    if let n = v as? NSNumber { return n.doubleValue }
    return nil
}
