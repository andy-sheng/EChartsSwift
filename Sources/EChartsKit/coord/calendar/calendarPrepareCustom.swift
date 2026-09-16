// Ported from echarts/src/coord/calendar/prepareCustom.ts — keep in sync with upstream
//   NOTE: named calendarPrepareCustom.swift (not prepareCustom.swift) to avoid a SwiftPM object-name
//   collision with coord/polar/prepareCustom.swift (duplicate basenames collide in one target).
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

// import type Calendar from './Calendar';                              -> Calendar (coord/calendar/Calendar.swift; coord-sys master)
//
// `Calendar` (coord/calendar/Calendar.swift) is the coordinate-system master (registered via
//   CoordinateSystemManager.register("calendar", ...)) and is ported. The surface referenced below
//   (getRect(), getRangeInfo(), getCellWidth(), getCellHeight(), dataToPoint(_ , _), dataToLayout(_ , _))
//   mirrors upstream Calendar.ts.

// upstream: export default function calendarPrepareCustom(coordSys: Calendar) { ... }
public func calendarPrepareCustom(_ coordSys: Calendar) -> [String: Any] {
    // const rect = coordSys.getRect();
    let rect = coordSys.getRect()
    // const rangeInfo = coordSys.getRangeInfo();
    let rangeInfo = coordSys.getRangeInfo()

    // return { coordSys: {...}, api: {...} };
    return [
        "coordSys": [
            "type": "calendar",
            "x": rect.x,
            "y": rect.y,
            "width": rect.width,
            "height": rect.height,
            "cellWidth": coordSys.getCellWidth(),
            "cellHeight": coordSys.getCellHeight(),
            "rangeInfo": [
                "start": rangeInfo.start,
                "end": rangeInfo.end,
                "weeks": rangeInfo.weeks,
                // dayCount: rangeInfo.allDay
                "dayCount": rangeInfo.allDay
            ] as [String: Any]
        ] as [String: Any],
        "api": [
            // coord: function (data, clamp?) { return coordSys.dataToPoint(data, clamp); }
            //   `data` is OptionDataValueDate | OptionDataValueDate[] (no Swift union) -> `Any`;
            //   `clamp` is an optional boolean -> `Bool?`.
            "coord": { (data: Any, clamp: Bool?) -> [Double] in
                return coordSys.dataToPoint(data, clamp)
            } as (Any, Bool?) -> [Double],
            // layout: function (data, clamp?) { return coordSys.dataToLayout(data, clamp); }
            //   returns CoordinateSystemDataLayout (rect + contentRect); modeled as the dynamic result of
            //   coordSys.dataToLayout (narrow at the custom-series call site).
            "layout": { (data: Any, clamp: Bool?) -> Any in
                let result: CoordinateSystemDataLayout = coordSys.dataToLayout(
                    data as OptionDataValueDate?, clamp
                )
                return result
            } as (Any, Bool?) -> Any
        ] as [String: Any]
    ]
}
