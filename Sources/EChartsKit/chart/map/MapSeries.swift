// Ported from echarts/src/chart/map/MapSeries.ts — keep in sync with upstream
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
//   import * as zrUtil from 'zrender/src/core/util';               -> `util.*` / `createHashMap` (ZRenderKit / modelUtil shim).
//   import createSeriesDataSimply from '../helper/createSeriesDataSimply';
//       -> `createSeriesDataSimply` (chart/helper/createSeriesDataSimply.swift).
//   import SeriesModel from '../../model/Series';                  -> SeriesModel (model/Series.swift).
//   import geoSourceManager from '../../coord/geo/geoSourceManager';
//       -> `geoSourceManager.*` (coord/geo/geoSourceManager.swift).
//   import { makeSeriesEncodeForNameBased } from '../../data/helper/sourceHelper';
//       -> `sourceHelper.makeSeriesEncodeForNameBased` (data/helper/sourceHelper.swift).
//   import { ... } from '../../util/types';                        -> type-only; the dynamic option tree is
//       the `[String: Any]` bag per CONVENTIONS §2.
//   import { Dictionary, NullUndefined } from 'zrender/src/core/types';  -> type-only.
//   import GeoModel, { GeoCommonOptionMixin, GeoItemStyleOption } from '../../coord/geo/GeoModel';
//       -> GeoModel (coord/geo/GeoModel.swift). Mixins type-only.
//   import SeriesData from '../../data/SeriesData';                -> SeriesData (data/SeriesData.swift).
//   import Model from '../../model/Model';                         -> Model (model/Model.swift).
//   import Geo from '../../coord/geo/Geo';                         -> Geo (coord/geo/Geo.swift).
//   import { createTooltipMarkup } from '../../component/tooltip/tooltipMarkup';
//       -> PORT-TODO: component/tooltip/tooltipMarkup.ts NOT ported (tooltip component deferred).
//   import {createSymbol, ECSymbol} from '../../util/symbol';
//       -> PORT-TODO: util/symbol.ts NOT ported (legend icon deferred).
//   import {LegendIconParams} from '../../component/legend/LegendModel';  -> PORT-TODO: legend NOT ported.
//   import {Group} from '../../util/graphic';                      -> ZRenderKit.Group.
//   import { COORD_SYS_USAGE_KIND_BOX, decideCoordSysUsageKind } from '../../core/CoordinateSystem';
//       -> `COORD_SYS_USAGE_KIND_BOX` + `decideCoordSysUsageKind` (core/CoordinateSystemManager.swift).
//   import { GeoJSONRegion } from '../../coord/geo/Region';        -> GeoJSONRegion (coord/geo/Region.swift).
//   import tokens from '../../visual/tokens';
//       -> PORT-TODO: visual/tokens.ts NOT ported; consumed color values are inlined verbatim below.
//   import GlobalModel from '../../model/Global';                  -> GlobalModel (model/Global.swift).

// ============================================================================
// The upstream `interface`/`type` declarations (MapStateOption, MapDataItemOption, MapSeriesOption)
// describe the (dynamic) option tree. Per CONVENTIONS §2 the option tree is the `[String: Any]` bag;
// these types are kept as documentation only — no Swift types are emitted.
// ============================================================================

// export type MapValueCalculationType = 'sum' | 'average' | 'min' | 'max';
// PORT: the string-literal union is modeled as `String`; consumed by `mapDataStatistic`
//   (`mainSeries.get('mapValueCalculation')`).
public typealias MapValueCalculationType = String

// See MAP_SERIES_GROUP
// upstream:
//   export type MapSeriesGroup = {
//       // Raw (a group of series before series filtering). Never be empty.
//       r: MapSeries[];
//       // Filtered (a group of series after series filtering).
//       f: MapSeries[];
//   };
//   type AllMapSeriesGroups = Dictionary<MapSeriesGroup>;
// CONVENTIONS §2/§4: this record is MUTATED in place (`group.f.push(...)` / `group.r.push(...)` in
//   `buildAllMapSeriesGroups`), so it is a reference type (`final class`) — a value struct would not
//   accumulate pushes through the `allMapSeriesGroups[key]` dictionary slot.
public final class MapSeriesGroup {
    // Raw (a group of series before series filtering). Never be empty.
    public var r: [MapSeriesModel] = []
    // Filtered (a group of series after series filtering). If `getMainMapSeries` is falsy, `f` is empty.
    public var f: [MapSeriesModel] = []
    public init() {}
}
public typealias AllMapSeriesGroups = [String: MapSeriesGroup]

// export const SERIES_TYPE_MAP = 'map';
public let SERIES_TYPE_MAP = "map"

// upstream: class MapSeries extends SeriesModel<MapSeriesOption> implements RoamHostModel
//   (The port class is named `MapSeriesModel`, consistent with the other series ports, e.g. PieSeriesModel.)
open class MapSeriesModel: SeriesModel {

    // upstream: static readonly type = 'series.' + SERIES_TYPE_MAP;  /  readonly type = MapSeries.type;
    //   The static drives the instance `type` (inherited `var type { Self.type }` from ComponentModel).
    public override class var type: ComponentFullType { return "series." + SERIES_TYPE_MAP }

    // upstream: static dependencies = ['geo'];
    open override class var dependencies: [String] { return ["geo"] }

    // upstream: static layoutMode = 'box' as const;
    public override class var layoutMode: Any? { return "box" }

    // upstream: coordinateSystem: Geo;
    //   The base `SeriesModel.coordinateSystem` is typed `Any?` (coord/CoordinateSystem impedance). Swift
    //   can not re-type an inherited stored property, so callers downcast `self.coordinateSystem as? Geo`
    //   (see `getTooltipPosition`). The map-series geo is injected by `geoCreator` (map-series-group path).

    // -----------------
    // Injected outside
    // upstream: originalData: SeriesData;
    //   Set by `mapDataStatistic` (holds the per-series data before it is replaced by the shared/merged
    //   statistic data). Upstream types it NON-optional (injected, never re-declared) and consumers
    //   (MapView._renderSymbols) read `originalData.mapDimension(...)` non-optionally, so it is an
    //   implicitly-unwrapped optional (explicit `SeriesData!` type — the IUO-bound-to-`let` trap does not
    //   apply to an annotated stored property).
    open var originalData: SeriesData!
    // upstream: seriesGroup: MapSeriesGroup | NullUndefined;
    //   Set by `mapDataStatistic` (and cleared to nil by `geoCreator`'s map-series-group path).
    open var seriesGroup: MapSeriesGroup?

    // upstream: getInitialData(this: MapSeries, option: MapSeriesOption): SeriesData
    //   Overrides the base `getInitialData(option, ecModel) -> SeriesData?`.
    open override func getInitialData(_ option: ModelOption?, _ ecModel: GlobalModel?) -> SeriesData? {
        // const data = createSeriesDataSimply(this, {
        //     coordDimensions: ['value'],
        //     encodeDefaulter: zrUtil.curry(makeSeriesEncodeForNameBased, this)
        // });
        //   Same `{coordDimensions, encodeDefaulter}` bridge as PieSeries: `curry(makeSeriesEncodeForNameBased,
        //   this)` binds the series as the first arg, leaving `(source, dimCount) -> encode`; the internal
        //   `[String: [DimensionIndex]]` widens to `OptionEncode` via `mapValues`.
        let data = createSeriesDataSimply(self, PrepareSeriesDataSchemaParams(
            coordDimensions: ["value"],
            encodeDefaulter: { (source: Source, dimCount: Double) -> OptionEncode in
                let internalEncode = sourceHelper.makeSeriesEncodeForNameBased(self, source, dimCount)
                return internalEncode.mapValues { $0 as Any } as OptionEncode
            }
        ))

        // const dataNameIndexMap = zrUtil.createHashMap<number>();
        let dataNameIndexMap: HashMap<Int> = createHashMap()
        // const toAppendItems: MapDataItemOption[] = [];
        var toAppendItems: [[String: Any]] = []

        // for (let i = 0, len = data.count(); i < len; i++) { dataNameIndexMap.set(data.getName(i), i); }
        let len = data.count()
        var i = 0
        while i < len {
            let name = data.getName(i)
            _ = dataNameIndexMap.set(name, i)
            i += 1
        }

        // const geoSource = geoSourceManager.load(this.getMapType(), this.option.nameMap, this.option.nameProperty);
        let optBag = (self.option as? [String: Any]) ?? [:]
        let geoSource = geoSourceManager.load(
            self.getMapType(),
            optBag["nameMap"] as? NameMap,
            optBag["nameProperty"] as? String
        )

        // zrUtil.each(geoSource.regions, function (region) { ... });
        util.each(geoSource.regions) { region, _ in
            // const name = region.name;
            let name = region.name
            // const dataNameIdx = dataNameIndexMap.get(name);
            let dataNameIdx = dataNameIndexMap.get(name)
            // apply specified echarts style in GeoJSON data
            // const specifiedGeoJSONRegionStyle = (region as GeoJSONRegion).properties
            //     && (region as GeoJSONRegion).properties.echartsStyle;
            let specifiedGeoJSONRegionStyle = (region as? GeoJSONRegion)?.properties["echartsStyle"] as? [String: Any]

            // let dataItem: MapDataItemOption;
            if dataNameIdx == nil {
                // dataItem = { name: name }; toAppendItems.push(dataItem);
                var dataItem: [String: Any] = ["name": name]
                // specifiedGeoJSONRegionStyle && zrUtil.merge(dataItem, specifiedGeoJSONRegionStyle);
                //   (upstream merges after the push; JS reference makes order irrelevant. Here `dataItem`
                //   is a value dict, so merge BEFORE pushing so the appended item carries the style.)
                if let style = specifiedGeoJSONRegionStyle {
                    _ = util.merge(&dataItem, style)
                }
                toAppendItems.append(dataItem)
            }
            else {
                // dataItem = data.getRawDataItem(dataNameIdx) as MapDataItemOption;
                // specifiedGeoJSONRegionStyle && zrUtil.merge(dataItem, specifiedGeoJSONRegionStyle);
                // PORT-TODO: upstream mutates the raw data item OBJECT in place (JS reference), so the
                //   `echartsStyle` merge persists into the store's raw item. `getRawDataItem` returns a
                //   value copy here (no `setRawDataItem`), so the in-place merge for an EXISTING data item
                //   is deferred. Only reachable when a GeoJSON region carries `properties.echartsStyle`
                //   AND the series `data` already has that region — a rare combination. Faithful body:
                //     var dataItem = data.getRawDataItem(dataNameIdx!) as? [String: Any]
                //     if let style = specifiedGeoJSONRegionStyle, var di = dataItem { _ = util.merge(&di, style) /* write back */ }
                _ = specifiedGeoJSONRegionStyle
            }
        }

        // Complete data with missing regions. The consequent processes (like visual map and render)
        // can not be performed without a "full data". For example, find `dataIndex` by name.
        // data.appendData(toAppendItems);
        data.appendData(toAppendItems as [Any])

        // return data;
        return data
    }

    /**
     * If no host geo model, return null, which means using a inner exclusive geo model.
     */
    // upstream: getHostGeoModel(): GeoModel
    open func getHostGeoModel() -> GeoModel? {
        // if (decideCoordSysUsageKind(this).kind === COORD_SYS_USAGE_KIND_BOX) {
        //     // Always use an internal geo if specify as `COORD_SYS_USAGE_KIND_BOX`.
        //     return;
        // }
        if decideCoordSysUsageKind(self).kind == COORD_SYS_USAGE_KIND_BOX {
            return nil
        }
        // return this.getReferringComponents(
        //     'geo', {useDefault: false, enableAll: false, enableNone: false}
        // ).models[0] as GeoModel;
        return self.getReferringComponents(
            "geo", QueryReferringOpt(useDefault: false, enableAll: false, enableNone: false)
        ).models.first as? GeoModel
    }

    // upstream: getMapType(): string { return (this.getHostGeoModel() || this).option.map; }
    open func getMapType() -> String {
        // (this.getHostGeoModel() || this).option.map
        let target: ComponentModel = self.getHostGeoModel() ?? self
        return ((target.option as? [String: Any])?["map"] as? String) ?? ""
    }

    // _fillOption(option, mapName) { ... }  (commented out upstream — omitted)

    // upstream: getRawValue(dataIndex: number): ParsedValue
    open func getRawValue(_ dataIndex: Int) -> ParsedValue? {
        // Use value stored in data instead because it is calculated from multiple series
        // FIXME Provide all value of multiple series ?
        // const data = this.getData();
        let data = self.getData()
        // return data.get(data.mapDimension('value'), dataIndex);
        return data.get(data.mapDimension("value") ?? "value", dataIndex)
    }

    /**
     * Get model of region
     */
    // upstream: getRegionModel(regionName: string): Model<MapDataItemOption>
    open func getRegionModel(_ regionName: String) -> Model {
        // const data = this.getData();
        let data = self.getData()
        // return data.getItemModel(data.indexOfName(regionName));
        return data.getItemModel(data.indexOfName(regionName))
    }

    /**
     * Map tooltip formatter
     */
    // upstream: formatTooltip(dataIndex, multipleSeries, dataType)
    //   Overrides the base `formatTooltip(...) -> TooltipFormatResult?`.
    // PORT-TODO (DEFERRED — tooltip component): depends on `createTooltipMarkup`
    //   (component/tooltip/tooltipMarkup.ts NOT ported). The faithful body below computes the section
    //   header (names of the sibling map series that have a non-NaN value for this region) and the
    //   name/value block; restore the `createTooltipMarkup(...)` build when tooltip lands. Returns nil.
    open override func formatTooltip(
        _ dataIndex: Double,
        _ multipleSeries: Bool? = nil,
        _ dataType: SeriesDataType? = nil
    ) -> TooltipFormatResult? {
        // FIXME originalData and data is a bit confusing
        // const data = this.getData();
        let data = self.getData()
        // const value = this.getRawValue(dataIndex);
        let value = self.getRawValue(Int(dataIndex))
        // const name = data.getName(dataIndex);
        let name = data.getName(Int(dataIndex))

        // const seriesNames: string[] = [];
        var seriesNames: [String] = []
        // zrUtil.each(this.seriesGroup.f, function (mapSeries) { ... });
        util.each(self.seriesGroup?.f ?? []) { mapSeries, _ in
            // const otherIndex = mapSeries.originalData.indexOfName(name);
            guard let originalData = mapSeries.originalData else { return }
            let otherIndex = originalData.indexOfName(name)
            // const valueDim = data.mapDimension('value');
            let valueDim = data.mapDimension("value") ?? "value"
            // if (!isNaN(mapSeries.originalData.get(valueDim, otherIndex) as number)) { seriesNames.push(mapSeries.name); }
            // if (!isNaN(mapSeries.originalData.get(valueDim, otherIndex) as number)) { ... }
            //   Map values are numeric; the numeric non-NaN case is the reachable path.
            let otherVal = originalData.get(valueDim, otherIndex)
            if let d = otherVal as? Double, !d.isNaN {
                seriesNames.append(mapSeries.name)
            }
        }

        _ = (multipleSeries, dataType, value, seriesNames)

        // return createTooltipMarkup('section', {
        //     header: seriesNames.join(', '),
        //     noHeader: !seriesNames.length,
        //     blocks: [createTooltipMarkup('nameValue', { name: name, value: value })]
        // });
        return nil
    }

    // upstream: getTooltipPosition = function (this: MapSeries, dataIndex: number): number[] { ... }
    //   (An assigned function property upstream; ported as an instance method — it is one of the
    //   optional `SeriesModel` interface methods callers null-check.)
    open func getTooltipPosition(_ dataIndex: Int?) -> [Double]? {
        // if (dataIndex != null) { ... }
        guard let dataIndex = dataIndex else { return nil }
        // const name = this.getData().getName(dataIndex);
        let name = self.getData().getName(dataIndex)
        // const geo = this.coordinateSystem;
        guard let geo = self.coordinateSystem as? Geo else { return nil }
        // const region = geo.getRegion(name);
        let region = geo.getRegion(name)
        // return region && geo.dataToPoint(region.getCenter());
        guard let region = region else { return nil }
        return geo.dataToPoint(region.getCenter())
    }

    // upstream: getLegendIcon(opt: LegendIconParams): ECSymbol | Group { ... }
    // PORT-TODO (DEFERRED — legend/symbol): depends on `createSymbol` (util/symbol.ts) and
    //   `LegendIconParams` (component/legend), neither ported. Faithful upstream body:
    //     const iconType = opt.icon || 'roundRect';
    //     const icon = createSymbol(iconType, 0, 0, opt.itemWidth, opt.itemHeight, opt.itemStyle.fill);
    //     icon.setStyle(opt.itemStyle);
    //     icon.style.stroke = 'none';                       // Map does not use itemStyle.borderWidth as border
    //     if (iconType.indexOf('empty') > -1) {
    //         icon.style.stroke = icon.style.fill;
    //         icon.style.fill = tokens.color.neutral00;     // '#fff'
    //         icon.style.lineWidth = 2;
    //     }
    //     return icon;

    // upstream: __ownRoamView() { return mapSeriesNeedsDrawMap(this) ? this.coordinateSystem.view : null; }
    // PORT-TODO (DEFERRED — roam): `RoamHostModel.__ownRoamView` returns the geo View that this series
    //   owns (drives roam ownership). Roam is deferred (Geo has no exposed `view` on the roam path here).
    //   Faithful body:
    //     return mapSeriesNeedsDrawMap(self) ? (self.coordinateSystem as? Geo)?.view : nil

    // PORT-TODO (DEFERRED — roam): the shared-geo `center`/`zoom` state (`setCenter`/`getCenter`/`getZoom`)
    //   is NOT declared on `MapSeries` in this ECharts version — it lives on the roam View / `RoamHostView`
    //   surface (component/helper/RoamController + coord/View), which is deferred with roam. The map series
    //   reads its initial `center`/`zoom`/`scaleLimit` options only (see `defaultOption`); the geo it shares
    //   owns the live view transform. Wire these through the geo View when roam lands.

    // upstream: static defaultOption: MapSeriesOption = { ... }
    //   LOAD-BEARING: `coordinateSystem: 'geo'` (resolved to a Geo by geoCreator's map-series-group path).
    //   `tokens.color.*` are inlined as resolved constants (visual/tokens.ts NOT ported):
    //     tokens.color.tertiary  = color.neutral60 = '#6d6e73'
    //     tokens.color.border    = color.neutral30 = '#b7b9be'
    //     tokens.color.background = color.neutral05 = '#f4f7fd'
    //     tokens.color.primary   = color.neutral80 = '#3c3c41'
    //     tokens.color.highlight =                    'rgba(255,231,130,0.8)'
    open override class var defaultOption: ModelOption? {
        return [
            // zlevel: 0,
            "z": 2.0,

            "coordinateSystem": "geo",

            // map should be explicitly specified since ec3.
            "map": "",

            // If `geoIndex` is not specified, a exclusive geo will be created. Otherwise use the
            // specified geo component, and `map` and `mapType` are ignored.
            // geoIndex: 0,

            // 'center' | 'left' | 'right' | 'x%' | {number}
            "left": "center",
            // 'center' | 'top' | 'bottom' | 'x%' | {number}
            "top": "center",

            // Aspect is width / height. Inited to be geoJson bbox aspect. This parameter is used for
            // scale this aspect. Default value: geoSVG source: 1, geoJSON source: 0.75.
            // PORT-TODO: upstream value is `null`; NSNull() retains the key in the [String: Any] bag.
            "aspectScale": NSNull(),

            // Layout with center and size (layoutCenter / layoutSize) — commented upstream.

            "showLegendSymbol": true,

            // Define left-top, right-bottom coords to control view, higher priority than center/zoom.
            "boundingCoords": NSNull(),

            // Default on center of map
            "center": NSNull(),

            "zoom": 1.0,

            "scaleLimit": NSNull(),

            "selectedMode": true,

            "label": [
                "show": false,
                "color": "#6d6e73"                      // tokens.color.tertiary
            ] as [String: Any],
            // scaleLimit: null,
            "itemStyle": [
                "borderWidth": 0.5,
                "borderColor": "#b7b9be",               // tokens.color.border
                "areaColor": "#f4f7fd"                  // tokens.color.background
            ] as [String: Any],

            "emphasis": [
                "label": [
                    "show": true,
                    "color": "#3c3c41"                  // tokens.color.primary
                ] as [String: Any],
                "itemStyle": [
                    "areaColor": "rgba(255,231,130,0.8)"    // tokens.color.highlight
                ] as [String: Any]
            ] as [String: Any],

            "select": [
                "label": [
                    "show": true,
                    "color": "#3c3c41"                  // tokens.color.primary
                ] as [String: Any],
                "itemStyle": [
                    "color": "rgba(255,231,130,0.8)"    // tokens.color.highlight
                ] as [String: Any]
            ] as [String: Any],

            "nameProperty": "name"
        ] as [String: Any]
    }

}

/**
 * Has exclusive geo, rather than depends on a separate geo component.
 */
// upstream: export function mapSeriesGroupHasOwnGeo(groupKey: string): boolean
public func mapSeriesGroupHasOwnGeo(_ groupKey: String) -> Bool {
    // return groupKey.indexOf('i') === 0;
    return groupKey.hasPrefix("i")
}

// upstream: export function mapSeriesNeedsDrawMap(mapSeries: MapSeries): boolean
public func mapSeriesNeedsDrawMap(_ mapSeries: MapSeriesModel) -> Bool {
    // Within a MAP_SERIES_GROUP, only `mainSeries` has `needsDrawMap: true`.
    // return getMainMapSeries(mapSeries.seriesGroup) === mapSeries && !mapSeries.getHostGeoModel();
    guard let seriesGroup = mapSeries.seriesGroup else { return false }
    return getMainMapSeries(seriesGroup) === mapSeries && mapSeries.getHostGeoModel() == nil
}

// upstream: export function getMainMapSeries(mapSeriesGroup: MapSeriesGroup): MapSeries | NullUndefined
public func getMainMapSeries(_ mapSeriesGroup: MapSeriesGroup) -> MapSeriesModel? {
    // The first series after filtering in a MAP_SERIES_GROUP.
    // return mapSeriesGroup.f[0];
    return mapSeriesGroup.f.first
}

/**
 * @tutorial [MAP_SERIES_GROUP]
 *  - For map series that reference external geo components (typically via `geoIndex`/`geoId`), a map
 *    series group is all map series that reference the same geo component.
 *  - For other map series, a map series group is all map series that use the same `map`.
 *  NOTICE: series filtering (typically by legend) matters — see upstream comment.
 */
// upstream: export function buildAllMapSeriesGroups(ecModel, beforeSeriesFiltering?): AllMapSeriesGroups
public func buildAllMapSeriesGroups(_ ecModel: GlobalModel, _ beforeSeriesFiltering: Bool? = nil) -> AllMapSeriesGroups {
    // const allMapSeriesGroups: AllMapSeriesGroups = {};
    var allMapSeriesGroups: AllMapSeriesGroups = [:]
    // ecModel.eachRawSeriesByType(SERIES_TYPE_MAP, function (seriesModel: MapSeries) { ... });
    ecModel.eachRawSeriesByType(SERIES_TYPE_MAP) { (seriesModelBase: SeriesModel, _: Double) in
        guard let seriesModel = seriesModelBase as? MapSeriesModel else { return }
        // const hostGeoModel = seriesModel.getHostGeoModel();
        let hostGeoModel = seriesModel.getHostGeoModel()
        // const key = hostGeoModel ? 'o' + hostGeoModel.id : 'i' + seriesModel.getMapType();
        let key = hostGeoModel != nil ? "o" + hostGeoModel!.id : "i" + seriesModel.getMapType()
        // const group = allMapSeriesGroups[key] = allMapSeriesGroups[key] || {f: [], r: []};
        let group: MapSeriesGroup
        if let existing = allMapSeriesGroups[key] {
            group = existing
        }
        else {
            group = MapSeriesGroup()
            allMapSeriesGroups[key] = group
        }
        // if (!ecModel.isSeriesFiltered(seriesModel) && !beforeSeriesFiltering) { group.f.push(seriesModel); }
        if !ecModel.isSeriesFiltered(seriesModel) && !(beforeSeriesFiltering ?? false) {
            group.f.append(seriesModel)
        }
        // group.r.push(seriesModel);
        group.r.append(seriesModel)
    }
    // return allMapSeriesGroups;
    return allMapSeriesGroups
}

// export default MapSeries;  -> `open class MapSeriesModel` above.
