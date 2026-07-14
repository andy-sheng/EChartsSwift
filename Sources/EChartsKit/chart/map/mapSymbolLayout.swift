// Ported from echarts/src/chart/map/mapSymbolLayout.ts — keep in sync with upstream
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

// upstream imports (mapped to this port; `→` marks the Swift symbol used):
//   import GlobalModel from '../../model/Global';                  → `GlobalModel`.
//   import { buildAllMapSeriesGroups, getMainMapSeries, mapSeriesGroupHasOwnGeo, SERIES_TYPE_MAP }
//       from './MapSeries';   → assumed sibling `MapSeries.swift` free functions (see MapView.swift's
//       assumed-API block). `buildAllMapSeriesGroups(ecModel) -> [String: MapSeriesGroup]`,
//       `getMainMapSeries(group) -> MapSeriesModel?`, `mapSeriesGroupHasOwnGeo(groupKey) -> Bool`.
//   import { Dictionary } from '../../util/types';                 → `[String: T]`.
//   import { createSimpleOverallStageHandler } from '../../util/model';
//       → `model.createSimpleOverallStageHandler` (util/modelUtil.swift).
//   import { each } from 'zrender/src/core/util';                  → `util.each` (ZRenderKit).

// upstream:
//   export const mapSymbolLayoutStageHandler = createSimpleOverallStageHandler(SERIES_TYPE_MAP, mapSymbolLayout);
// `createSimpleOverallStageHandler` expects `StageHandlerOverallReset = (GlobalModel, ExtensionAPI,
// Payload?) -> Void`; the upstream `mapSymbolLayout` is 1-arg `(ecModel)`. Adapt with a thin wrapper that
// drops the (unused) api/payload, keeping `mapSymbolLayout` faithful (1-arg) below (see sankeyLayout.swift).
public let mapSymbolLayoutStageHandler = model.createSimpleOverallStageHandler(
    SERIES_TYPE_MAP,
    { ecModel, _, _ in mapSymbolLayout(ecModel) }
)

// upstream: function mapSymbolLayout(ecModel: GlobalModel)
//   Places the per-region legend symbol markers at the projected region CENTERS (and stamps `showLabel`
//   on the main series so label-less regions still get a name label). Exposed for the driver, mirroring
//   sankeyLayout.
public func mapSymbolLayout(_ ecModel: GlobalModel) {

    // upstream: each(buildAllMapSeriesGroups(ecModel), function (mapSeriesGroup, groupKey) { ... })
    for (groupKey, mapSeriesGroup) in buildAllMapSeriesGroups(ecModel) {

        // upstream: if (!getMainMapSeries(mapSeriesGroup) || !mapSeriesGroupHasOwnGeo(groupKey)) { return; }
        //   map series on separate geo components only provide "choropleth map"; symbols are ignored.
        guard let mainSeries = getMainMapSeries(mapSeriesGroup), mapSeriesGroupHasOwnGeo(groupKey) else {
            continue
        }

        // upstream: const mapSymbolOffsets = {} as Dictionary<number>;
        var mapSymbolOffsets: [String: Double] = [:]

        // upstream: each(mapSeriesGroup.f, function (subMapSeries) { ... })
        for subMapSeries in mapSeriesGroup.f {
            let geo = subMapSeries.coordinateSystem as! Geo
            // `originalData` is `SeriesData!` (IUO); annotate the binding type so it force-unwraps to
            //   `SeriesData` (the IUO-bound-to-`let` trap infers Optional otherwise).
            let data: SeriesData = subMapSeries.originalData

            // upstream: if (subMapSeries.get('showLegendSymbol') && ecModel.getComponent('legend')) { ... }
            if mapSymbolLayoutJsTruthy(subMapSeries.get("showLegendSymbol"))
                && ecModel.getComponent("legend") != nil {

                guard let valueDim = data.mapDimension("value") else {
                    continue
                }
                // upstream: data.each(data.mapDimension('value'), function (value, idx) { ... })
                data.each(valueDim as Any) { args in
                    // args == [value, idx]
                    let value = mapSymbolLayoutToNumber(args[0]) ?? Double.nan
                    let idx = Int((args[1] as? Double) ?? -1)

                    // upstream: const name = data.getName(idx); const region = geo.getRegion(name);
                    let name = data.getName(idx)
                    let region = geo.getRegion(name)

                    // upstream: if (!region || isNaN(value as number)) { return; }
                    //   `series.data` fills gaps with NaN; NaN is not drawn.
                    guard let region = region, !value.isNaN else {
                        return
                    }

                    // upstream: const offset = mapSymbolOffsets[name] || 0;
                    let offset = mapSymbolOffsets[name] ?? 0

                    // upstream: const point = geo.dataToPoint(region.getCenter());
                    //   The explicit `[Double]?` picks Geo's own (Optional-returning) `dataToPoint`
                    //   overload rather than the `CoordinateSystem` protocol witness added in Geo.swift
                    //   (which collapses a null projection to [NaN, NaN]); a nil point must stay nil here
                    //   so the symbol is skipped, as it was before.
                    let point: [Double]? = geo.dataToPoint(region.getCenter(), false)

                    // upstream: mapSymbolOffsets[name] = offset + 1;
                    mapSymbolOffsets[name] = offset + 1

                    // upstream: data.setItemLayout(idx, { point: point, offset: offset });
                    //   A null projected point is stored as absent so the symbol is skipped downstream
                    //   (upstream `layout.point` would be `undefined` → falsy).
                    var layout: [String: Any] = ["offset": offset]
                    if let point = point {
                        layout["point"] = point
                    }
                    data.setItemLayout(idx, layout)
                }
            }
        }

        // upstream: Show label of those regions that have no legendIcon (offset 0).
        //   const data = getMainMapSeries(mapSeriesGroup).getData();
        //   data.each(function (idx) { ...layout.showLabel = !mapSymbolOffsets[name]... });
        let data = mainSeries.getData()
        data.each { args in
            // args == [idx]
            let idx = Int((args[0] as? Double) ?? -1)
            let name = data.getName(idx)
            var layout = (data.getItemLayout(idx) as? [String: Any]) ?? [:]
            // upstream: layout.showLabel = !mapSymbolOffsets[name];
            layout["showLabel"] = ((mapSymbolOffsets[name] ?? 0) == 0)
            data.setItemLayout(idx, layout)
        }
    }
}

// ============================================================================
// PORT-NOTE helpers — NOT part of mapSymbolLayout.ts upstream. Dynamic-option /
// ParsedValue coercions (CONVENTIONS trap #1 / §6). Delete when the shared
// coercions land and call them directly.
// ============================================================================

/// Coerce a dynamic option / ParsedValue to Double, tolerating Int boxing.
private func mapSymbolLayoutToNumber(_ v: Any?) -> Double? {
    if let d = v as? Double { return d }
    if let i = v as? Int { return Double(i) }
    if let n = v as? NSNumber, !(n === kCFBooleanTrue || n === kCFBooleanFalse) { return n.doubleValue }
    return nil
}

/// JS truthiness for the dynamic option bag (`if (x)`).
private func mapSymbolLayoutJsTruthy(_ v: Any?) -> Bool {
    guard let v = v, !(v is NSNull) else { return false }
    if let b = v as? Bool { return b }
    if let d = v as? Double { return d != 0 && !d.isNaN }
    if let i = v as? Int { return i != 0 }
    if let s = v as? String { return !s.isEmpty }
    if let a = v as? [Any] { return !a.isEmpty }
    return true
}
