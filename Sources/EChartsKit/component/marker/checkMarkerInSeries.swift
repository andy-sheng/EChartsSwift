// Ported from echarts/src/component/marker/checkMarkerInSeries.ts — keep in sync with upstream
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

import ZRenderKit
// import { isArray } from 'zrender/src/core/util';   -> ZRenderKit `util.isArray`
// import { SeriesOption } from '../../util/types';    -> EChartsKit util/types.swift (dynamic option bag)

// type MarkerTypes = 'markPoint' | 'markLine' | 'markArea';
// PORT-TODO: string-literal union modeled as `String` (values: "markPoint" | "markLine" | "markArea").
public typealias MarkerTypes = String

// type SeriesWithMarkerOption = SeriesOption & Partial<Record<MarkerTypes, unknown>>;
// PORT-TODO: `SeriesOption` (a typed option interface) is the dynamic option bag `[String: Any]` in
//   the port; the `Partial<Record<MarkerTypes, unknown>>` intersection is a dynamic keyed lookup.

// upstream: export default function checkMarkerInSeries(seriesOpts, markerType): boolean
// PORT-TODO: `seriesOpts: SeriesOption | SeriesOption[]` modeled as `Any?` (a dict or an array of
//   dicts) matching the dynamic option bag; `!seriesOpts` -> `nil` check (CONVENTIONS §6).
public func checkMarkerInSeries(_ seriesOpts: Any?, _ markerType: MarkerTypes) -> Bool {
    if seriesOpts == nil {
        return false
    }
    // const seriesOptArr = isArray(seriesOpts) ? seriesOpts : [seriesOpts];
    let seriesOptArr: [Any?] = util.isArray(seriesOpts)
        ? ((seriesOpts as? [Any])?.map { $0 as Any? } ?? [])
        : [seriesOpts]
    for idx in 0..<seriesOptArr.count {
        // if (seriesOptArr[idx] && (seriesOptArr[idx] as SeriesWithMarkerOption)[markerType])
        if let seriesOpt = seriesOptArr[idx] as? [String: Any], isTruthy(seriesOpt[markerType]) {
            return true
        }
    }
    return false
}

// JS truthiness for the dynamic `seriesOpt[markerType]` lookup (CONVENTIONS §6): a present,
// non-nil, non-false, non-empty value is truthy. Marker options are objects/arrays here.
private func isTruthy(_ value: Any?) -> Bool {
    guard let value = value else { return false }
    if let b = value as? Bool { return b }
    return true
}
