// Ported from echarts/src/coord/geo/GeoModel.ts — keep in sync with upstream
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

// import * as zrUtil from 'zrender/src/core/util';                      -> `util.*` (ZRenderKit) / inline
// import * as modelUtil from '../../util/model';                        -> modelUtil.* (util/modelUtil.swift)
// import ComponentModel from '../../model/Component';                   -> ComponentModel (model/Component.swift)
// import Model from '../../model/Model';                                -> Model (model/Model.swift)
// import geoCreator from './geoCreator';                                -> geoCreator (coord/geo/geoCreator.swift)
// import Geo from './Geo';                                              -> Geo (coord/geo/Geo.swift; coord-sys master)
// import { ... } from '../../util/types';                               -> option interfaces dropped (dynamic option bag, §2)
// import { GeoProjection, NameMap } from './geoTypes';                  -> GeoProjection / NameMap (coord/geo/geoTypes.swift)
// import GlobalModel from '../../model/Global';                         -> GlobalModel (model/Global.swift)
// import geoSourceManager from './geoSourceManager';                    -> geoSourceManager (coord/geo/geoSourceManager.swift)
// import tokens from '../../visual/tokens';                             -> tokens.* (visual/tokens.ts not ported yet; inlined below)
//
//   `geoSourceManager` (coord/geo/geoSourceManager.swift), `geoCreator` (coord/geo/geoCreator.swift, the
//   singleton `geoCreator`), and `Geo` (coord/geo/Geo.swift, the GEO coordinate-system master — the 7th
//   coord system, projects [lng, lat] -> pixel) are ALL ported and wired below.
// `Geo` now declares `CoordinateSystemMaster` conformance (see Geo.swift class decl). The
//   `coordinateSystem: CoordinateSystemMaster?` slot required by `CoordinateSystemHostModel` holds it
//   at runtime (assigned by geoCreator.create); narrow via `as? Geo` / `as! Geo` at use (as GeoView does).

// NOTE: visual/tokens.ts is not ported yet. The `tokens.*` values consumed by `defaultOption` / `init` are
// inlined verbatim as their resolved constants (mirrors CalendarModel / axisDefault). Re-wire to the real
// `tokens` namespace once visual/tokens.swift lands:
//   tokens.color.tertiary       = color.neutral60 = '#6d6e73'
//   tokens.color.border         = color.neutral30 = '#b7b9be'
//   tokens.color.primary        = color.neutral80 = '#3c3c41'
//   tokens.color.highlight      =                    'rgba(255,231,130,0.8)'
//   tokens.color.backgroundTint =                    'rgba(234,237,245,0.5)'

// upstream:
// export interface GeoItemStyleOption<TCbParams = never> extends ItemStyleOption<TCbParams> { areaColor?: ZRColor; }
// interface GeoLabelOption extends LabelOption { formatter?: string | ((params) => string) }
// export interface GeoStateOption { itemStyle?; label? }
// interface GeoLabelFormatterDataParams { name: string; status: DisplayState; }
// export interface RegionOption extends GeoStateOption, StatesOptionMixin<...> { name?; selected?; tooltip?; silent? }
// export interface RegoinOption extends RegionOption {}   // @deprecated typo alias
// export interface GeoTooltipFormatterParams { componentType: 'geo'; geoIndex; name; $vars }
// export interface GeoCommonOptionMixin extends RoamOptionMixin, PreserveAspectMixin { map?; aspectScale?;
//     layoutCenter?; layoutSize?; clip?; boundingCoords?; nameMap?; nameProperty?; projection?; }
// export interface GeoOption extends ComponentOption, ..., GeoCommonOptionMixin, GeoStateOption { ... }
//   all of the above option/param interfaces describe the dynamic option shape; modeled as the
//   dynamic option bag ([String: Any]) per CONVENTIONS §2 — no standalone Swift structs emitted. The
//   `label.formatter` callback (string | (params) -> string) is stored as a closure in the bag at use time.

// upstream: export interface RegionOption extends GeoStateOption, StatesOptionMixin<...> { name?; selected?; ... }
//   The per-region option object -> dynamic option bag ([String: Any]). Declared here (not in geoTypes) so
//   the sibling `geoCreator` (coord/geo/geoCreator.swift, which `import`s `RegionOption` from './GeoModel')
//   resolves it — it builds `var regionOption: RegionOption = ["name": name]`.
public typealias RegionOption = [String: Any]
// upstream: /** @deprecated Use `RegionOption` instead. */ export interface RegoinOption extends RegionOption {}
public typealias RegoinOption = RegionOption

// upstream: class GeoModel extends ComponentModel<GeoOption> implements RoamHostModel { ... }
//   Component reference type -> `final class : ComponentModel, CoordinateSystemHostModel` (mirrors RadarModel;
//   its `coordinateSystem: Geo` satisfies CoordinateSystemHostModel since Geo is a CoordinateSystemMaster).
//   TODO: requires the ROAM interaction module (RoamHostModel). Upstream also
//   `implements RoamHostModel` (via `__ownRoamView()` below). ROAM (pan/zoom)
//   interaction is DEFERRED per the phase brief; the `RoamHostModel` conformance (whose `__ownRoamView`
//   returns a `View?`) is not declared here until View/Geo land — the method is kept below, staged.
public final class GeoModel: ComponentModel, CoordinateSystemHostModel {

    // static type = 'geo';
    // readonly type = GeoModel.type;  (the instance `type` mirrors the static via ComponentModel's `type`.)
    public override class var type: ComponentFullType { return "geo" }

    // coordinateSystem: Geo;
    //   upstream types this the concrete `Geo`, injected once the coordinate system is built. Typed here as
    //   the `CoordinateSystemMaster?` required by `CoordinateSystemHostModel` (Geo.swift does not declare the
    //   conformance yet — see class note); narrow via `as? Geo` / `as! Geo` at use (as GeoView does).
    public var coordinateSystem: CoordinateSystemMaster?

    // static layoutMode = 'box' as const;
    public override class var layoutMode: Any? { return "box" }

    // private _optionModelMap: zrUtil.HashMap<Model<RegionOption>>;
    //   Modeled as a plain `[String: Model]` (equivalent keyed lookup; `Model<RegionOption>` generic arg
    //   erased). IUO upstream (assigned in `optionUpdated` before any `getRegionModel` call); given a `[:]`
    //   default to dodge the IUO-bound-to-`let` inference trap.
    private var _optionModelMap: [String: Model] = [:]

    // static defaultOption: GeoOption = { ... }
    //   Numbers -> Double (CONVENTIONS §1) so a bare `as? Double` read does not silently drop them
    //   (INT-vs-DOUBLE option-read trap). `null` -> NSNull() (the key is present with a null value upstream).
    public override class var defaultOption: ModelOption? {
        return [

            // zlevel: 0,

            "z": 0.0,

            "show": true,

            "left": "center",

            "top": "center",

            // Default value:
            // for geoSVG source: 1,
            // for geoJSON source: 0.75.
            "aspectScale": NSNull(),

            // /// Layout with center and size
            // If you want to put map in a fixed size box with right aspect ratio
            // This two properties may be more convenient
            // layoutCenter: [50%, 50%]
            // layoutSize: 100

            "silent": false,

            // Map type
            "map": "",

            // Define left-top, right-bottom coords to control view
            // For example, [ [180, 90], [-180, -90] ]
            "boundingCoords": NSNull(),

            // Default on center of map
            "center": NSNull(),

            "zoom": 1.0,

            "scaleLimit": NSNull(),

            // selectedMode: false

            "label": [
                "show": false,
                "color": "#6d6e73"                 // tokens.color.tertiary
            ] as [String: Any],

            "itemStyle": [
                "borderWidth": 0.5,
                "borderColor": "#b7b9be"           // tokens.color.border
                // Default color:
                // + geoJSON: #eee
                // + geoSVG: null (use SVG original `fill`)
                // color: '#eee'
            ] as [String: Any],

            "emphasis": [
                "label": [
                    "show": true,
                    "color": "#3c3c41"             // tokens.color.primary
                ] as [String: Any],
                "itemStyle": [
                    "color": "rgba(255,231,130,0.8)"   // tokens.color.highlight
                ] as [String: Any]
            ] as [String: Any],

            "select": [
                "label": [
                    "show": true,
                    "color": "#3c3c41"             // tokens.color.primary
                ] as [String: Any],
                "itemStyle": [
                    "color": "rgba(255,231,130,0.8)"   // tokens.color.highlight
                ] as [String: Any]
            ] as [String: Any],

            "regions": [] as [Any]

            // tooltip: {
            //     show: false
            // }
        ] as [String: Any]
    }

    // init(option: GeoOption, parentModel: Model, ecModel: GlobalModel): void { ... }
    //   NOTE: upstream `init` does NOT call `super.init`; it calls `this.mergeDefaultAndTheme` directly
    //   (exactly what ComponentModel's default `init` does), then runs the geo-specific defaulting. Mirrored.
    public override func `init`(_ option: ModelOption?, _ parentModel: Model? = nil, _ ecModel: GlobalModel? = nil, _ rest: Any...) {
        // this.mergeDefaultAndTheme(option, ecModel);
        self.mergeDefaultAndTheme(option, ecModel)

        // const source = geoSourceManager.getGeoResource(option.map);
        // if (source && source.type === 'geoJSON') {
        //     const itemStyle = option.itemStyle = option.itemStyle || {};
        //     if (!('color' in itemStyle)) {
        //         itemStyle.color = option.defaultItemStyleColor || tokens.color.backgroundTint;
        //     }
        // }
        //   `option` upstream === `self.option` after mergeDefaultAndTheme; read/write the option bag.
        if var opt = self.option as? [String: Any] {
            // const source = geoSourceManager.getGeoResource(option.map);
            //   `option.map` is a string (default ""); getGeoResource takes a non-optional String.
            let map = (opt["map"] as? String) ?? ""
            let source: GeoResource? = geoSourceManager.getGeoResource(map)
            if let source = source, source.type == "geoJSON" {
                var itemStyle = (opt["itemStyle"] as? [String: Any]) ?? [:]
                // if (!('color' in itemStyle)) { ... }
                if itemStyle["color"] == nil {
                    // option.defaultItemStyleColor || tokens.color.backgroundTint
                    let defaultItemStyleColor = opt["defaultItemStyleColor"]
                    itemStyle["color"] = jsTruthy(defaultItemStyleColor)
                        ? defaultItemStyleColor!
                        : "rgba(234,237,245,0.5)"     // tokens.color.backgroundTint
                }
                opt["itemStyle"] = itemStyle
            }
            self.option = opt
        }

        // Default label emphasis `show`
        // modelUtil.defaultEmphasis(option, 'label', ['show']);
        //   `option` upstream === `self.option`. `model.defaultEmphasis` takes a typed
        //   `DisplayStateHostOption` (struct); bridge the dynamic option bag ([String: Any]) through
        //   it (mirrors Series.defaultEmphasisOnBag) and write the mutated bag back.
        if let bag = self.option as? [String: Any] {
            self.option = GeoModel.defaultEmphasisOnBag(bag, "label", ["show"])
        }
    }

    // Bridge the dynamic `[String: Any]` option bag to the typed `DisplayStateHostOption` struct that
    // model.defaultEmphasis consumes, run it, and return the mutated bag (mirrors Series.defaultEmphasisOnBag).
    // Upstream mutates the option object in place (reference semantics); Swift value types require
    // read-modify-write-back.
    private static func defaultEmphasisOnBag(_ bag: [String: Any], _ key: String, _ subOpts: [String]) -> [String: Any] {
        var host: DisplayStateHostOption? = DisplayStateHostOption()
        host!.other = bag
        host!.emphasis = bag["emphasis"] as? [String: Any]
        model.defaultEmphasis(&host, key, subOpts)
        var result = host!.other
        if let emphasis = host!.emphasis {
            result["emphasis"] = emphasis
        }
        return result
    }

    // optionUpdated(): void { ... }
    //   upstream overrides `optionUpdated()` with NO params, but `ComponentModel.optionUpdated`
    //   is `(newCptOption, isInit)`. Swift overrides must match the signature; the two params are accepted
    //   and ignored (as upstream does implicitly).
    public override func optionUpdated(_ newCptOption: ModelOption?, _ isInit: Bool) {
        // const option = this.option;
        guard var option = self.option as? [String: Any] else { return }

        // option.regions = geoCreator.getFilledRegions(
        //     option.regions, option.map, option.nameMap, option.nameProperty
        // );
        //   `geoCreator` is the ported singleton (coord/geo/geoCreator.swift). `option.map` is a string
        //   (default ""); `nameMap` is a NameMap ([String: String]); `nameProperty` is a string.
        option["regions"] = geoCreator.getFilledRegions(
            option["regions"] as? [RegionOption],
            (option["map"] as? String) ?? "",
            option["nameMap"] as? NameMap,
            option["nameProperty"] as? String
        )

        // const selectedMap: Dictionary<boolean> = {};
        var selectedMap: [String: Bool] = [:]
        // this._optionModelMap = zrUtil.reduce(option.regions || [], (optionModelMap, regionOpt) => {
        //     const regionName = regionOpt.name;
        //     if (regionName) {
        //         optionModelMap.set(regionName, new Model(regionOpt, this, this.ecModel));
        //         if (regionOpt.selected) { selectedMap[regionName] = true; }
        //     }
        //     return optionModelMap;
        // }, zrUtil.createHashMap());
        //   HashMap/createHashMap modeled as a plain [String: Model]; `reduce` unrolled to a faithful loop.
        var optionModelMap: [String: Model] = [:]
        let regions = (option["regions"] as? [[String: Any]]) ?? []
        for regionOpt in regions {
            let regionName = regionOpt["name"] as? String
            if let regionName = regionName, !regionName.isEmpty {   // `if (regionName)` — truthy string
                optionModelMap[regionName] = Model(regionOpt, self, self.ecModel)
                // if (regionOpt.selected)
                if jsTruthy(regionOpt["selected"]) {
                    selectedMap[regionName] = true
                }
            }
        }
        self._optionModelMap = optionModelMap

        // if (!option.selectedMap) { option.selectedMap = selectedMap; }
        if !jsTruthy(option["selectedMap"]) {
            option["selectedMap"] = selectedMap
        }

        self.option = option
    }

    /**
     * Get model of region.
     */
    // getRegionModel(name: string): Model<RegionOption> {
    //     return this._optionModelMap.get(name) || new Model(null, this, this.ecModel);
    // }
    public func getRegionModel(_ name: String) -> Model {
        return self._optionModelMap[name] ?? Model(nil, self, self.ecModel)
    }

    /**
     * Format label
     * @param name Region name
     */
    // getFormattedLabel(name: string, status?: DisplayState) { ... }
    //   returns `string | undefined` -> `String?`. Upstream `status` is `DisplayState`, a string-union
    //   ('normal' | 'emphasis' | ...); typed `String?` here (its underlying representation) so the raw-string
    //   caller (GeoView passes `"normal"`) resolves, matching upstream's string semantics (`status === 'normal'`).
    public func getFormattedLabel(_ name: String, _ status: String? = nil) -> String? {
        // const regionModel = this.getRegionModel(name);
        let regionModel = self.getRegionModel(name)
        // const formatter = status === 'normal'
        //     ? regionModel.get(['label', 'formatter'])
        //     : regionModel.get(['emphasis', 'label', 'formatter']);
        let formatter: ModelOption? = (status == "normal")
            ? regionModel.get(["label", "formatter"])
            : regionModel.get(["emphasis", "label", "formatter"])
        // const params = { name: name } as GeoLabelFormatterDataParams;
        var params: [String: Any] = ["name": name]
        // if (zrUtil.isFunction(formatter)) {
        //     params.status = status;
        //     return formatter(params);
        // }
        if util.isFunction(formatter) {
            params["status"] = status
            // the formatter closure type is erased in the dynamic option bag; narrowed to the
            //   GeoLabelFormatterDataParams->String shape ([String: Any]) -> String.
            if let f = formatter as? ([String: Any]) -> String {
                return f(params)
            }
            return nil
        }
        // else if (zrUtil.isString(formatter)) {
        //     return formatter.replace('{a}', name != null ? name : '');
        // }
        else if util.isString(formatter) {
            let fmt = formatter as! String
            // JS String.replace(str, str) replaces only the FIRST occurrence; Swift
            //   replacingOccurrences replaces ALL. Reproduce first-only to stay faithful.
            let replacement = name   // name != null ? name : '' — name is non-null here
            if let range = fmt.range(of: "{a}") {
                return fmt.replacingCharacters(in: range, with: replacement)
            }
            return fmt
        }
        return nil
    }

    // PENGING If selectedMode is null ?
    // select(name?: string): void { ... }
    public func select(_ name: String? = nil) {
        // const option = this.option;
        guard var option = self.option as? [String: Any] else { return }
        // const selectedMode = option.selectedMode;
        let selectedMode = option["selectedMode"]
        // if (!selectedMode) { return; }
        if !jsTruthy(selectedMode) {
            return
        }
        // if (selectedMode !== 'multiple') { option.selectedMap = null; }
        if (selectedMode as? String) != "multiple" {
            option["selectedMap"] = NSNull()
        }

        // const selectedMap = option.selectedMap || (option.selectedMap = {});
        var selectedMap = (option["selectedMap"] as? [String: Bool]) ?? [:]
        // selectedMap[name] = true;
        if let name = name {
            selectedMap[name] = true
        }
        option["selectedMap"] = selectedMap
        self.option = option
    }

    // unSelect(name?: string): void { ... }
    public func unSelect(_ name: String? = nil) {
        // const selectedMap = this.option.selectedMap;
        guard var option = self.option as? [String: Any] else { return }
        // if (selectedMap) { selectedMap[name] = false; }
        if var selectedMap = option["selectedMap"] as? [String: Bool] {
            if let name = name {
                selectedMap[name] = false
            }
            option["selectedMap"] = selectedMap
            self.option = option
        }
    }

    // toggleSelected(name?: string): void {
    //     this[this.isSelected(name) ? 'unSelect' : 'select'](name);
    // }
    public func toggleSelected(_ name: String? = nil) {
        if self.isSelected(name) {
            self.unSelect(name)
        }
        else {
            self.select(name)
        }
    }

    // isSelected(name?: string): boolean {
    //     const selectedMap = this.option.selectedMap;
    //     return !!(selectedMap && selectedMap[name]);
    // }
    public func isSelected(_ name: String? = nil) -> Bool {
        let selectedMap = (self.option as? [String: Any])?["selectedMap"] as? [String: Bool]
        guard let selectedMap = selectedMap, let name = name else { return false }
        return selectedMap[name] == true
    }

    // __ownRoamView() { return this.coordinateSystem.view; }
    //   ROAM (pan/zoom) interaction is DEFERRED per the phase brief; this returns the owning
    //   `View` of the geo coord system. Typed `Any?` (mirrors SankeySeries) since the `RoamHostModel`
    //   conformance — whose `__ownRoamView` returns `View?` — is not declared on this class yet.
    public func __ownRoamView() -> Any? {
        // return self.coordinateSystem.view
        return (self.coordinateSystem as? Geo)?.view
    }
}

// export default GeoModel;  -> `public final class GeoModel` above.

// Replicates JS truthiness for the dynamic option bag (mirrors the file-scope helper used across the port).
private func jsTruthy(_ v: Any?) -> Bool {
    guard let v = v else { return false }
    if v is NSNull { return false }
    if let b = v as? Bool { return b }
    if let n = v as? Double { return n != 0 && !n.isNaN }
    if let i = v as? Int { return i != 0 }
    if let s = v as? String { return !s.isEmpty }
    return true
}
