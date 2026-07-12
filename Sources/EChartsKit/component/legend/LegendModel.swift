// Ported from echarts/src/component/legend/LegendModel.ts — keep in sync with upstream
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

// import * as zrUtil from 'zrender/src/core/util';               -> ZRenderKit `util` (util.each / util.map / util.filter / util.merge / util.indexOf / util.isArray / util.isString / util.isNumber) + `createHashMap` (EChartsKit modelUtil.swift)
// import Model from '../../model/Model';                          -> Model (model/Model.swift)
// import {isNameSpecified} from '../../util/model';               -> model.isNameSpecified (EChartsKit util/modelUtil.swift)
// import ComponentModel from '../../model/Component';             -> ComponentModel (model/Component.swift)
// import { ... many option interfaces ... } from '../../util/types';
//   -> The dynamic option tree is modeled as the `[String: Any]` bag (CONVENTIONS §2); the TS
//      `LegendOption` / `LegendStyleOption` / `DataItem` / etc. interfaces are not emitted as Swift
//      structs. They are preserved as comments only where load-bearing.
// import { Dictionary } from 'zrender/src/core/types';            -> Dictionary<T> = [String: T]
// import GlobalModel from '../../model/Global';                   -> GlobalModel (model/Global.swift)
// import { ItemStyleProps } from '../../model/mixin/itemStyle';   -> (type-only)
// import { LineStyleProps } from './../../model/mixin/lineStyle'; -> (type-only)
// import {PathStyleProps} from 'zrender/src/graphic/Path';        -> (type-only)
// import tokens from '../../visual/tokens';
//   -> visual/tokens.swift is ported. The `tokens.*` values consumed in `defaultOption` are still
//      inlined verbatim as their resolved constants (they could be re-wired to the real `tokens`
//      namespace).
//        tokens.color.transparent = 'rgba(0,0,0,0)'
//        tokens.color.border      = color.neutral30 = '#b7b9be'
//        tokens.color.disabled    = color.neutral20 = '#cfd2d7'
//        tokens.color.secondary   = color.neutral70 = '#54555a'
//        tokens.color.tertiary    = color.neutral60 = '#6d6e73'
//        tokens.color.quaternary  = color.neutral50 = '#86878c'
//        tokens.size.m            = 15

// visual/LegendVisualProvider.swift (PORTED). `seriesModel.legendVisualProvider` is typed `Any?` on
//   SeriesModel; pie/radar/funnel/chord/themeRiver assign a data-item `LegendVisualProvider` and graph a
//   category one, all conforming to `LegendVisualProviderLike` (the shape `_updateData` consumes below).
//   A series with no provider falls back to `isPotential = true` (the series name as the legend entry).
// `LegendVisualProviderLike` is declared in visual/LegendVisualProvider.swift (the full surface:
//   getAllNames / containName / indexOfName / getItemVisual).

// type LegendDefaultSelectorOptionsProps = { type: string; title: string; };
// const getDefaultSelectorOptions = function (ecModel: GlobalModel, type: string): LegendDefaultSelectorOptionsProps
private func getDefaultSelectorOptions(_ ecModel: GlobalModel?, _ type: String) -> [String: Any]? {
    if type == "all" {
        // return { type: 'all', title: ecModel.getLocaleModel().get(['legend', 'selector', 'all']) };
        var out: [String: Any] = ["type": "all"]
        if let title = ecModel?.getLocaleModel().get(["legend", "selector", "all"]) {
            out["title"] = title
        }
        return out
    }
    else if type == "inverse" {
        // return { type: 'inverse', title: ecModel.getLocaleModel().get(['legend', 'selector', 'inverse']) };
        var out: [String: Any] = ["type": "inverse"]
        if let title = ecModel?.getLocaleModel().get(["legend", "selector", "inverse"]) {
            out["title"] = title
        }
        return out
    }
    return nil
}

// upstream overloaded return of `getOrient()`: { index: 0|1, name: 'horizontal'|'vertical' }.
public struct LegendOrientResult {
    public let index: Double
    public let name: String
}

// class LegendModel<Ops extends LegendOption = LegendOption> extends ComponentModel<Ops>
//   -> generic `Ops` dropped per CONVENTIONS §2 (dynamic option bag).
open class LegendModel: ComponentModel {

    // static type = 'legend.plain';
    // type = LegendModel.type;   (instance `type` already mirrors the static in ComponentModel)
    public override class var type: ComponentFullType { return "legend.plain" }

    // static readonly dependencies = ['series'];
    public override class var dependencies: [String] { return ["series"] }

    // readonly layoutMode = { type: 'box', ignoreSize: true } as const;
    // PORT-NOTE: upstream declares `layoutMode` here as an INSTANCE readonly member (not static),
    //   whereas the Swift ComponentModel exposes `layoutMode` as `open class var`. Modeled as a
    //   class-var override returning the same object literal. `layout.fetchLayoutMode` (not yet
    //   ported) is the sole consumer.
    public override class var layoutMode: Any? {
        return [
            "type": "box",
            // legend.width/height are maxWidth/maxHeight actually,
            // whereas real width/height is calculated by its content.
            // (Setting {left: 10, right: 10} does not make sense).
            // So consider the case:
            // `setOption({legend: {left: 10});`
            // then `setOption({legend: {right: 10});`
            // The previous `left` should be cleared by setting `ignoreSize`.
            "ignoreSize": true
        ] as [String: Any]
    }

    // private _data: Model<DataItem>[];
    // PORT-NOTE: upstream leaves these uninitialized (assigned by `_updateData`); Swift requires a
    //   stored value, so they default to empty.
    private var _data: [Model] = []
    // private _availableNames: string[];
    private var _availableNames: [String] = []

    // init(option: Ops, parentModel: Model, ecModel: GlobalModel)
    open override func `init`(_ option: ModelOption?, _ parentModel: Model? = nil, _ ecModel: GlobalModel? = nil, _ rest: Any...) {
        // this.mergeDefaultAndTheme(option, ecModel);
        self.mergeDefaultAndTheme(option, ecModel)

        // option.selected = option.selected || {};
        // PORT-NOTE: upstream mutates the shared `option` object (=== this.option). Swift option
        //   bags are value types; after `mergeDefaultAndTheme` wrote `self.option`, operate on
        //   `self.option`. Empty object `{}` is truthy in JS, so only null/undefined trigger the
        //   default -> `nil`-check only.
        if var opt = self.option as? [String: Any] {
            if opt["selected"] == nil {
                opt["selected"] = [String: Any]()
            }
            self.option = opt
        }

        // this._updateSelector(option);
        self._updateSelector(option)
    }

    // mergeOption(option: Ops, ecModel: GlobalModel)
    open override func mergeOption(_ option: ModelOption?, _ ecModel: GlobalModel?) {
        // super.mergeOption(option, ecModel);
        super.mergeOption(option, ecModel)
        // this._updateSelector(option);
        self._updateSelector(option)
    }

    // _updateSelector(option: Ops)
    func _updateSelector(_ option: ModelOption?) {
        // let selector = option.selector;
        // const {ecModel} = this;
        // PORT-NOTE: upstream reads/writes `option.selector`, where `option === this.option`. Swift
        //   option bags are value types, so we normalize the selector on `self.option` (in
        //   `mergeOption`, `super.mergeOption` has already merged the incremental option into
        //   `self.option`, so the normalized selector lands where the view reads it; idempotent for
        //   an already-normalized selector). `option` param retained for signature fidelity.
        _ = option
        guard var opt = self.option as? [String: Any] else {
            return
        }
        var selector = opt["selector"]
        let ecModel = self.ecModel
        // if (selector === true) { selector = option.selector = ['all', 'inverse']; }
        if let b = selector as? Bool, b == true {
            selector = ["all", "inverse"]
            opt["selector"] = selector
        }
        // if (zrUtil.isArray(selector)) {
        if var selectorArr = selector as? [Any] {
            // zrUtil.each(selector, function (item, index) {
            util.each(selectorArr) { _, index in
                var item: Any = selectorArr[index]
                // zrUtil.isString(item) && (item = {type: item});
                if util.isString(item) {
                    item = ["type": item] as [String: Any]
                }
                // (selector)[index] = zrUtil.merge(item, getDefaultSelectorOptions(ecModel, item.type));
                if var itemDict = item as? [String: Any] {
                    let itemType = itemDict["type"] as? String ?? ""
                    if let defaults = getDefaultSelectorOptions(ecModel, itemType) {
                        util.merge(&itemDict, defaults, false)
                    }
                    // else: getDefaultSelectorOptions returned undefined; merge(item, undefined) is a
                    //   no-op in zrender — item unchanged.
                    selectorArr[index] = itemDict
                }
            }
            opt["selector"] = selectorArr
        }
        self.option = opt
    }

    // optionUpdated()
    open override func optionUpdated(_ newCptOption: ModelOption?, _ isInit: Bool) {
        // this._updateData(this.ecModel);
        // POTENTIAL-BUG: `this.ecModel` is non-null upstream; force-unwrap mirrors that optimistic typing
        //   (component is mounted by then). Latent SIGTRAP if `optionUpdated` is ever reached pre-mount.
        self._updateData(self.ecModel!)

        // const legendData = this._data;
        let legendData = self._data

        // If selectedMode is single, try to select one
        // if (legendData[0] && this.get('selectedMode') === 'single') {
        if !legendData.isEmpty && (self.get("selectedMode") as? String) == "single" {
            var hasSelected = false
            // If has any selected in option.selected
            for i in 0..<legendData.count {
                // const name = legendData[i].get('name');
                let name = legendData[i].get("name") as? String ?? ""   // POTENTIAL-BUG: a numeric legend.data name (upstream allows string|number) coerces to "" here; the whole file assumes String names (select/allSelect/isSelected all `as? String`), so a systemic string-coercion is needed, not a local fix.
                if self.isSelected(name) {
                    // Force to unselect others
                    self.select(name)
                    hasSelected = true
                    break
                }
            }
            // Try select the first if selectedMode is single
            // !hasSelected && this.select(legendData[0].get('name'));
            if !hasSelected {
                self.select(legendData[0].get("name") as? String ?? "")
            }
        }
    }

    // _updateData(ecModel: GlobalModel)
    func _updateData(_ ecModel: GlobalModel) {
        var potentialData: [String] = []
        var availableNames: [String] = []

        // ecModel.eachRawSeries(function (seriesModel) {
        ecModel.eachRawSeries { seriesModel, _ in
            // const seriesName = seriesModel.name;
            let seriesName = seriesModel.name
            availableNames.append(seriesName)
            // let isPotential;   (undefined = falsy)
            var isPotential = false

            // if (seriesModel.legendVisualProvider) {
            if let provider = seriesModel.legendVisualProvider as? LegendVisualProviderLike {
                // const names = provider.getAllNames();
                let names = provider.getAllNames()

                // if (!ecModel.isSeriesFiltered(seriesModel)) {
                if !ecModel.isSeriesFiltered(seriesModel) {
                    // availableNames = availableNames.concat(names);
                    availableNames = availableNames + names
                }

                // if (names.length) {
                if names.count > 0 {
                    // potentialData = potentialData.concat(names);
                    potentialData = potentialData + names
                }
                else {
                    isPotential = true
                }
            }
            else {
                isPotential = true
            }

            // if (isPotential && isNameSpecified(seriesModel)) {
            if isPotential && model.isNameSpecified(seriesModel) {
                potentialData.append(seriesModel.name)
            }
        }

        // this._availableNames = availableNames;
        self._availableNames = availableNames

        // If legend.data is not specified in option, use availableNames as data,
        // which is convenient for user preparing option.
        // const rawData = this.get('data') || potentialData;
        // (JS: an empty array `[]` is truthy, so only null/undefined falls through to potentialData.)
        let rawData: [Any] = (self.get("data") as? [Any]) ?? (potentialData as [Any])

        // const legendNameMap = zrUtil.createHashMap();
        let legendNameMap: HashMap<Bool> = createHashMap()
        // const legendData = zrUtil.map(rawData, function (dataItem) { ... }, this);
        let legendData: [Model?] = util.map(rawData) { dataItemIn, _ in
            var dataItem: Any = dataItemIn
            // Can be string or number
            // if (zrUtil.isString(dataItem) || zrUtil.isNumber(dataItem)) { dataItem = { name: dataItem }; }
            if util.isString(dataItem) || util.isNumber(dataItem) {
                dataItem = ["name": dataItem] as [String: Any]
            }
            let name = (dataItem as? [String: Any])?["name"]
            // if (legendNameMap.get(dataItem.name)) { return null; }
            if legendNameMap.get(name) == true {
                // remove legend name duplicate
                return nil
            }
            // legendNameMap.set(dataItem.name, true);
            legendNameMap.set(name, true)
            // return new Model(dataItem, this, this.ecModel);
            return Model(dataItem, self, self.ecModel)
        }

        // this._data = zrUtil.filter(legendData, item => !!item);
        self._data = util.filter(legendData) { item, _ in item != nil }.map { $0! }
    }

    // getData()
    open func getData() -> [Model] {
        return self._data
    }

    // select(name: string)
    // PORT-NOTE: the DISPATCH that invokes select/unSelect/toggleSelected on user interaction lives
    //   in the action layer (legendAction.swift / legendFilter.swift), which is ported.
    //   The method bodies themselves are pure selected-map bookkeeping (no action-layer reference)
    //   and ARE ported faithfully because `optionUpdated`'s single-select initialization (static
    //   render) depends on `select`/`isSelected`.
    open func select(_ name: String) {
        // const selected = this.option.selected;
        // const selectedMode = this.get('selectedMode');
        guard var opt = self.option as? [String: Any] else { return }
        var selected = opt["selected"] as? [String: Any] ?? [:]
        let selectedMode = self.get("selectedMode")
        // if (selectedMode === 'single') {
        if (selectedMode as? String) == "single" {
            let data = self._data
            // zrUtil.each(data, function (dataItem) { selected[dataItem.get('name')] = false; });
            util.each(data) { dataItem, _ in
                if let n = dataItem.get("name") as? String {
                    selected[n] = false
                }
            }
        }
        // selected[name] = true;
        selected[name] = true
        opt["selected"] = selected
        self.option = opt
    }

    // unSelect(name: string)
    open func unSelect(_ name: String) {
        // if (this.get('selectedMode') !== 'single') {
        if (self.get("selectedMode") as? String) != "single" {
            // this.option.selected[name] = false;
            guard var opt = self.option as? [String: Any] else { return }
            var selected = opt["selected"] as? [String: Any] ?? [:]
            selected[name] = false
            opt["selected"] = selected
            self.option = opt
        }
    }

    // toggleSelected(name: string)
    open func toggleSelected(_ name: String) {
        // const selected = this.option.selected;
        guard var opt = self.option as? [String: Any] else { return }
        var selected = opt["selected"] as? [String: Any] ?? [:]
        // Default is true
        // if (!selected.hasOwnProperty(name)) { selected[name] = true; }
        if selected[name] == nil {
            selected[name] = true
        }
        // Write the default back before delegating (upstream `selected` aliases this.option.selected).
        opt["selected"] = selected
        self.option = opt
        // this[selected[name] ? 'unSelect' : 'select'](name);
        if legendSelectedTruthy(selected[name]) {
            self.unSelect(name)
        }
        else {
            self.select(name)
        }
    }

    // allSelect()
    open func allSelect() {
        // const data = this._data;
        // const selected = this.option.selected;
        let data = self._data
        guard var opt = self.option as? [String: Any] else { return }
        var selected = opt["selected"] as? [String: Any] ?? [:]
        // zrUtil.each(data, function (dataItem) { selected[dataItem.get('name', true)] = true; });
        util.each(data) { dataItem, _ in
            if let name = dataItem.get("name", true) as? String {
                selected[name] = true
            }
        }
        opt["selected"] = selected
        self.option = opt
    }

    // inverseSelect()
    open func inverseSelect() {
        // const data = this._data;
        // const selected = this.option.selected;
        let data = self._data
        guard var opt = self.option as? [String: Any] else { return }
        var selected = opt["selected"] as? [String: Any] ?? [:]
        // zrUtil.each(data, function (dataItem) {
        util.each(data) { dataItem, _ in
            // const name = dataItem.get('name', true);
            guard let name = dataItem.get("name", true) as? String else { return }
            // Initially, default value is true
            // if (!selected.hasOwnProperty(name)) { selected[name] = true; }
            if selected[name] == nil {
                selected[name] = true
            }
            // selected[name] = !selected[name];
            selected[name] = !legendSelectedTruthy(selected[name])
        }
        opt["selected"] = selected
        self.option = opt
    }

    // isSelected(name: string)
    open func isSelected(_ name: String) -> Bool {
        // const selected = this.option.selected;
        let selected = (self.option as? [String: Any])?["selected"] as? [String: Any] ?? [:]
        // return !(selected.hasOwnProperty(name) && !selected[name])
        //     && zrUtil.indexOf(this._availableNames, name) >= 0;
        let hasOwn = selected[name] != nil
        let cond = hasOwn && !legendSelectedTruthy(selected[name])
        return !cond && util.indexOf(self._availableNames, name) >= 0
    }

    // getOrient(): {index: 0, name: 'horizontal'} | {index: 1, name: 'vertical'}
    open func getOrient() -> LegendOrientResult {
        // return this.get('orient') === 'vertical'
        //     ? {index: 1, name: 'vertical'}
        //     : {index: 0, name: 'horizontal'};
        return (self.get("orient") as? String) == "vertical"
            ? LegendOrientResult(index: 1, name: "vertical")
            : LegendOrientResult(index: 0, name: "horizontal")
    }

    // static defaultOption: LegendOption = { ... }
    public override class var defaultOption: ModelOption? {
        return [
            // zlevel: 0,
            "z": 4.0,
            "show": true,

            "orient": "horizontal",

            "left": "center",
            // right: 'center',
            // top: 0,
            "bottom": 15.0,   // tokens.size.m

            "align": "auto",

            "backgroundColor": "rgba(0,0,0,0)",   // tokens.color.transparent
            "borderColor": "#b7b9be",             // tokens.color.border
            "borderRadius": 0.0,
            "borderWidth": 0.0,
            "padding": 5.0,
            "itemGap": 8.0,
            "itemWidth": 25.0,
            "itemHeight": 14.0,
            "symbolRotate": "inherit",
            "symbolKeepAspect": true,

            "inactiveColor": "#cfd2d7",           // tokens.color.disabled
            "inactiveBorderColor": "#cfd2d7",     // tokens.color.disabled
            "inactiveBorderWidth": "auto",

            "itemStyle": [
                "color": "inherit",
                "opacity": "inherit",
                "borderColor": "inherit",
                "borderWidth": "auto",
                "borderCap": "inherit",
                "borderJoin": "inherit",
                "borderDashOffset": "inherit",
                "borderMiterLimit": "inherit"
            ] as [String: Any],

            "lineStyle": [
                "width": "auto",
                "color": "inherit",
                "inactiveColor": "#cfd2d7",       // tokens.color.disabled
                "inactiveWidth": 2.0,
                "opacity": "inherit",
                "type": "inherit",
                "cap": "inherit",
                "join": "inherit",
                "dashOffset": "inherit",
                "miterLimit": "inherit"
            ] as [String: Any],

            "textStyle": [
                "color": "#54555a"                // tokens.color.secondary
            ] as [String: Any],
            "selectedMode": true,

            "selector": false,

            "selectorLabel": [
                "show": true,
                "borderRadius": 10.0,
                "padding": [3.0, 5.0, 3.0, 5.0] as [Double],
                "fontSize": 12.0,
                "fontFamily": "sans-serif",
                "color": "#6d6e73",               // tokens.color.tertiary
                "borderWidth": 1.0,
                "borderColor": "#b7b9be"          // tokens.color.border
            ] as [String: Any],

            "emphasis": [
                "selectorLabel": [
                    "show": true,
                    "color": "#86878c"            // tokens.color.quaternary
                ] as [String: Any]
            ] as [String: Any],

            "selectorPosition": "auto",

            "selectorItemGap": 7.0,

            "selectorButtonGap": 10.0,

            "tooltip": [
                "show": false
            ] as [String: Any],

            "triggerEvent": false
        ] as [String: Any]
    }
}

// JS truthiness of a `selected[name]` value (Dictionary<boolean> in practice, but the bag holds
// `Any`). Mirrors `!!selected[name]` / `!selected[name]` used above.
private func legendSelectedTruthy(_ value: Any?) -> Bool {
    guard let value = value else { return false }
    if let b = value as? Bool { return b }
    if let n = value as? Double { return n != 0 && !n.isNaN }
    if let s = value as? String { return !s.isEmpty }
    return true
}

// export default LegendModel;  -> `open class LegendModel` above.
