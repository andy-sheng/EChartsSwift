// Ported from echarts/src/chart/candlestick/preprocessor.ts — keep in sync with upstream
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
//   import * as zrUtil from 'zrender/src/core/util';                 -> `util.isArray` / `util.each` / `util.isObject`.
//   import { ECUnitOption } from '../../util/types';                 -> ECUnitOption (util/types.swift; == [String: Any]).
//   import { SERIES_TYPE_CANDLESTICK } from './CandlestickSeries';   -> `SERIES_TYPE_CANDLESTICK` (sibling).

// upstream: export default function candlestickPreprocessor(option: ECUnitOption)
//
// `option.series` items are objects that upstream mutates IN PLACE (`seriesItem.type = ...`).
//   Swift `[String: Any]` is a value type, so the port takes `inout` and writes the mutated item back
//   into the array (mirrors marker/installMarkPoint.swift's `markPointPreprocessor(_:)` precedent).
//   The `OptionPreprocessor` typealias registration is owned by the Integrate stage.
public func candlestickPreprocessor(_ option: inout ECUnitOption) {
    // if (!option || !zrUtil.isArray(option.series)) { return; }
    guard var series = option["series"] as? [Any] else {
        return
    }

    // Translate 'k' to 'candlestick'.
    util.each(series) { seriesItem, index in
        if util.isObject(seriesItem),
            var item = seriesItem as? [String: Any],
            (item["type"] as? String) == "k" {
            item["type"] = SERIES_TYPE_CANDLESTICK
            series[index] = item
        }
    }
    option["series"] = series
}
