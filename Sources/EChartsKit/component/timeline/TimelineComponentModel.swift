// Ported from echarts/src/component/timeline/TimelineModel.ts + SliderTimelineModel.ts
//   — keep in sync with upstream.
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

// upstream imports (mapped to this port):
//   import ComponentModel from '../../model/Component';        -> `ComponentModel`.
//   import SeriesData from '../../data/SeriesData';            -> `SeriesData`.
//   import Model from '../../model/Model';                     -> `Model`.
//   import GlobalModel from '../../model/Global';              -> `GlobalModel`.
//   import { each, isObject, clone } from 'zrender/src/core/util';  -> `util.each/isObject/clone`.
//   import { convertOptionIdName, getDataItemValue } from '../../util/model';
//       -> `model.convertOptionIdName` / `model.getDataItemValue` (util/modelUtil.swift).
//   import tokens from '../../visual/tokens';                  -> `tokens` (visual/tokens.swift).
//   The big `TimelineOption`/`TimelineDataItemOption`/... interfaces collapse to the dynamic
//     `[String: Any]` option bag (CONVENTIONS §2); preserved as commented source in upstream.

// upstream: class TimelineModel extends ComponentModel<TimelineOption>
// CONVENTIONS §2: reference type extending `ComponentModel` -> `open class` (SliderTimelineModel
//   subclasses it), keeping the base + subtype in one diffable file (cf. title/legend).
open class TimelineModel: ComponentModel {

    // static type = 'timeline'; type = TimelineModel.type;
    public override class var type: ComponentFullType { return "timeline" }

    // layoutMode = 'box';
    public override class var layoutMode: Any? { return "box" }

    // private _data: SeriesData<TimelineModel>;
    private var _data: SeriesData!

    // private _names: string[];
    private var _names: [String] = []

    /**
     * @override
     */
    // init(option, parentModel, ecModel) { this.mergeDefaultAndTheme(option, ecModel); this._initData(); }
    open override func `init`(
        _ option: ModelOption?, _ parentModel: Model? = nil, _ ecModel: GlobalModel? = nil, _ rest: Any...
    ) {
        self.mergeDefaultAndTheme(option, ecModel)
        self._initData()
    }

    /**
     * @override
     */
    // mergeOption(option) { super.mergeOption.apply(this, arguments); this._initData(); }
    open override func mergeOption(_ option: ModelOption?, _ ecModel: GlobalModel?) {
        super.mergeOption(option, ecModel)
        self._initData()
    }

    // setCurrentIndex(currentIndex: number)
    open func setCurrentIndex(_ currentIndexIn: Int?) {
        // if (currentIndex == null) { currentIndex = this.option.currentIndex; }
        var currentIndex = currentIndexIn ?? (tlReadInt(self.get("currentIndex")) ?? 0)
        let count = self._data.count()

        // if (this.option.loop) { currentIndex = (currentIndex % count + count) % count; }
        if tlTruthy(self.get("loop")) {
            if count > 0 {
                currentIndex = ((currentIndex % count) + count) % count
            }
            else {
                currentIndex = 0
            }
        }
        else {
            // currentIndex >= count && (currentIndex = count - 1);
            if currentIndex >= count { currentIndex = count - 1 }
            // currentIndex < 0 && (currentIndex = 0);
            if currentIndex < 0 { currentIndex = 0 }
        }

        // this.option.currentIndex = currentIndex;
        if var opt = self.option as? [String: Any] {
            opt["currentIndex"] = currentIndex
            self.option = opt
        }
    }

    /**
     * @return {number} currentIndex
     */
    // getCurrentIndex() { return this.option.currentIndex; }
    open func getCurrentIndex() -> Int {
        return tlReadInt(self.get("currentIndex")) ?? 0
    }

    /**
     * @return {boolean}
     */
    // isIndexMax() { return this.getCurrentIndex() >= this._data.count() - 1; }
    open func isIndexMax() -> Bool {
        return self.getCurrentIndex() >= self._data.count() - 1
    }

    /**
     * @param {boolean} state true: play, false: stop
     */
    // setPlayState(state) { this.option.autoPlay = !!state; }
    open func setPlayState(_ state: Bool) {
        if var opt = self.option as? [String: Any] {
            opt["autoPlay"] = state
            self.option = opt
        }
    }

    /**
     * @return {boolean} true: play, false: stop
     */
    // getPlayState() { return !!this.option.autoPlay; }
    open func getPlayState() -> Bool {
        return tlTruthy(self.get("autoPlay"))
    }

    /**
     * @private
     */
    // _initData()
    func _initData() {
        // const thisOption = this.option;
        // const dataArr = thisOption.data || [];
        let dataArr = (self.get("data") as? [Any]) ?? []
        // const axisType = thisOption.axisType;
        let axisType = self.get("axisType") as? String
        // const names: string[] = this._names = [];
        var names: [String] = []

        // let processedDataArr: TimelineOption['data'];
        var processedDataArr: [Any]
        if axisType == "category" {
            processedDataArr = []
            // each(dataArr, function (item, index) { ... });
            util.each(dataArr) { item, index in
                // const value = convertOptionIdName(getDataItemValue(item), '');
                let value = model.convertOptionIdName(model.getDataItemValue(item), "") ?? ""
                let newItem: Any
                if util.isObject(item) && !util.isArray(item) {
                    // newItem = clone(item); newItem.value = index;
                    var cloned = (util.clone(item) as? [String: Any]) ?? [:]
                    cloned["value"] = index
                    newItem = cloned
                }
                else {
                    // newItem = index;
                    newItem = index
                }
                processedDataArr.append(newItem)
                names.append(value)
            }
        }
        else {
            processedDataArr = dataArr
        }

        self._names = names

        // const dimType = ({category:'ordinal', time:'time', value:'number'})[axisType] || 'number';
        let dimType: DimensionType
        switch axisType {
        case "category": dimType = .ordinal
        case "time": dimType = .time
        case "value": dimType = .number
        default: dimType = .number
        }

        // const data = this._data = new SeriesData([{name:'value', type:dimType}], this);
        // PORT-DEVIATION: the object-literal dimension `{name, type}` loses its `type` through
        //   `SeriesData.init` (its object-literal branch copies only `name` — see SeriesData.swift
        //   note). Build the `SeriesDimensionDefine` directly so the store dim TYPE (ordinal/
        //   time/number) is honored (time date-strings must parse as time, not float).
        let dim = SeriesDimensionDefine()
        dim.name = "value"
        dim.type = dimType
        let data = SeriesData([dim], self)

        // data.initData(processedDataArr, names);
        data.initData(processedDataArr, names.map { Optional($0) })
        self._data = data
    }

    // getData() { return this._data; }
    // PORT: relaxed to accept the DataHost `getData(dataType?)` contract that `DataFormatMixin`
    //   (mixed into `SliderTimelineModel` below) refines — its getRawValue/getDataParams call
    //   `self.getData(dataType)`. Timeline has a single data table, so `dataType` is ignored (as
    //   upstream `getData()` takes no arg). Same idiom as `SeriesModel.getData(_:)`.
    open func getData(_ dataType: SeriesDataType? = nil) -> SeriesData {
        return self._data
    }

    // getCategories() { if (this.get('axisType') === 'category') { return this._names.slice(); } }
    open func getCategories() -> [String]? {
        if (self.get("axisType") as? String) == "category" {
            return self._names
        }
        return nil
    }

    /**
     * @protected
     */
    // static defaultOption: TimelineOption = { ... }
    public override class var defaultOption: ModelOption? {
        return [
            // zlevel: 0,
            "z": 4.0,                       // 二级层叠
            "show": true,

            "axisType": "time",             // 模式是时间类型，支持 value, category

            "realtime": true,

            "left": "20%",
            "top": NSNull(),
            "right": "20%",
            "bottom": 0.0,
            "width": NSNull(),
            "height": 40.0,
            "padding": tokens.size.m,

            "controlPosition": "left",      // 'left' 'right' 'top' 'bottom' 'none'
            "autoPlay": false,
            "rewind": false,                // 反向播放
            "loop": true,
            "playInterval": 2000.0,         // 播放时间间隔，单位ms

            "currentIndex": 0,

            "itemStyle": [String: Any](),
            "label": [
                "color": tokens.color.secondary
            ] as [String: Any],

            "data": [Any]()
        ] as [String: Any]
    }
}

// upstream: class SliderTimelineModel extends TimelineModel
//   + `mixin(SliderTimelineModel, DataFormatMixin.prototype)` (adds getDataParams/getRawValue/
//   getFormattedLabel/formatTooltip — the tooltip CONTENT).
// CONVENTIONS §2: `final class` (no further subclass). The `mixin(...)` is ported as a
//   `DataFormatMixin` conformance — the protocol-extension default methods graft the four
//   DataFormatMixin methods onto the model exactly as `zrUtil.mixin` would (same idiom as
//   `SeriesModel: ... DataFormatMixin`). The host-supplied requirements (ecModel/mainType/
//   subType/componentIndex/id/name) come from the `ComponentModel` base; the `DataHost`
//   `getData(dataType?)` witness is inherited from `TimelineModel` above.
public final class SliderTimelineModel: TimelineModel, DataFormatMixin {

    // static type = 'timeline.slider'; type = SliderTimelineModel.type;
    public override class var type: ComponentFullType { return "timeline.slider" }

    // static defaultOption = inheritDefaultOption(TimelineModel.defaultOption, { ... });
    public override class var defaultOption: ModelOption? {
        let base = (TimelineModel.defaultOption as? [String: Any]) ?? [:]
        return component.inheritDefaultOption(base, [
            "backgroundColor": "rgba(0,0,0,0)",     // 时间轴背景颜色
            "borderColor": tokens.color.border,      // 时间轴边框颜色
            "borderWidth": 0.0,                      // 时间轴边框线宽，默认为0（无边框）

            "orient": "horizontal",                 // 'vertical'
            "inverse": false,

            "tooltip": [                             // boolean or Object
                "trigger": "item"
            ] as [String: Any],

            "symbol": "circle",
            "symbolSize": 12.0,

            "lineStyle": [
                "show": true,
                "width": 2.0,
                "color": tokens.color.accent10
            ] as [String: Any],
            "label": [                              // 文本标签
                "position": "auto",
                "show": true,
                "interval": "auto",
                "rotate": 0.0,
                "color": tokens.color.tertiary
            ] as [String: Any],
            "itemStyle": [
                "color": tokens.color.accent20,
                "borderWidth": 0.0
            ] as [String: Any],

            "checkpointStyle": [
                "symbol": "circle",
                "symbolSize": 15.0,
                "color": tokens.color.accent50,
                "borderColor": tokens.color.accent50,
                "borderWidth": 0.0,
                "shadowBlur": 0.0,
                "shadowOffsetX": 0.0,
                "shadowOffsetY": 0.0,
                "shadowColor": "rgba(0, 0, 0, 0)",
                "animation": true,
                "animationDuration": 300.0,
                "animationEasing": "quinticInOut"
            ] as [String: Any],

            "controlStyle": [
                "show": true,
                "showPlayBtn": true,
                "showPrevBtn": true,
                "showNextBtn": true,

                "itemSize": 24.0,
                "itemGap": 12.0,

                "position": "left",  // 'left' 'right' 'top' 'bottom'

                "playIcon": "path://M15 0C23.2843 0 30 6.71573 30 15C30 23.2843 23.2843 30 15 30C6.71573 30 0 23.2843 0 15C0 6.71573 6.71573 0 15 0ZM15 3C8.37258 3 3 8.37258 3 15C3 21.6274 8.37258 27 15 27C21.6274 27 27 21.6274 27 15C27 8.37258 21.6274 3 15 3ZM11.5 10.6699C11.5 9.90014 12.3333 9.41887 13 9.80371L20.5 14.1338C21.1667 14.5187 21.1667 15.4813 20.5 15.8662L13 20.1963C12.3333 20.5811 11.5 20.0999 11.5 19.3301V10.6699Z",
                "stopIcon": "path://M15 0C23.2843 0 30 6.71573 30 15C30 23.2843 23.2843 30 15 30C6.71573 30 0 23.2843 0 15C0 6.71573 6.71573 0 15 0ZM15 3C8.37258 3 3 8.37258 3 15C3 21.6274 8.37258 27 15 27C21.6274 27 27 21.6274 27 15C27 8.37258 21.6274 3 15 3ZM11.5 10C12.3284 10 13 10.6716 13 11.5V18.5C13 19.3284 12.3284 20 11.5 20C10.6716 20 10 19.3284 10 18.5V11.5C10 10.6716 10.6716 10 11.5 10ZM18.5 10C19.3284 10 20 10.6716 20 11.5V18.5C20 19.3284 19.3284 20 18.5 20C17.6716 20 17 19.3284 17 18.5V11.5C17 10.6716 17.6716 10 18.5 10Z",
                "nextIcon": "path://M0.838834 18.7383C0.253048 18.1525 0.253048 17.2028 0.838834 16.617L7.55635 9.89949L0.838834 3.18198C0.253048 2.59619 0.253048 1.64645 0.838834 1.06066C1.42462 0.474874 2.37437 0.474874 2.96015 1.06066L10.7383 8.83883L10.8412 8.95277C11.2897 9.50267 11.2897 10.2963 10.8412 10.8462L10.7383 10.9602L2.96015 18.7383C2.37437 19.3241 1.42462 19.3241 0.838834 18.7383Z",
                "prevIcon": "path://M10.9602 1.06066C11.5459 1.64645 11.5459 2.59619 10.9602 3.18198L4.24264 9.89949L10.9602 16.617C11.5459 17.2028 11.5459 18.1525 10.9602 18.7383C10.3744 19.3241 9.42462 19.3241 8.83883 18.7383L1.06066 10.9602L0.957771 10.8462C0.509245 10.2963 0.509245 9.50267 0.957771 8.95277L1.06066 8.83883L8.83883 1.06066C9.42462 0.474874 10.3744 0.474874 10.9602 1.06066Z",

                "prevBtnSize": 18.0,
                "nextBtnSize": 18.0,

                "color": tokens.color.accent50,
                "borderColor": tokens.color.accent50,
                "borderWidth": 0.0
            ] as [String: Any],
            "emphasis": [
                "label": [
                    "show": true,
                    "color": tokens.color.accent60
                ] as [String: Any],
                "itemStyle": [
                    "color": tokens.color.accent60,
                    "borderColor": tokens.color.accent60
                ] as [String: Any],
                "controlStyle": [
                    "color": tokens.color.accent70,
                    "borderColor": tokens.color.accent70
                ] as [String: Any]
            ] as [String: Any],

            "progress": [
                "lineStyle": [
                    "color": tokens.color.accent30
                ] as [String: Any],
                "itemStyle": [
                    "color": tokens.color.accent40
                ] as [String: Any]
            ] as [String: Any],

            "data": [Any]()
        ])
    }
}

// ============================================================================
// PORT helpers (local to the timeline component). JS truthiness + Int coercion for the dynamic bag.
// ============================================================================

/// JS truthiness for the dynamic option bag (`if (x)` / `!!x`).
func tlTruthy(_ v: Any?) -> Bool {
    guard let v = v, !(v is NSNull) else { return false }
    if let b = v as? Bool { return b }
    if let d = v as? Double { return d != 0 && !d.isNaN }
    if let i = v as? Int { return i != 0 }
    if let s = v as? String { return !s.isEmpty }
    return true
}

/// Coerce an option-bag number (may box as Int OR Double — the recurring Int-vs-Double trap).
func tlReadInt(_ v: Any?) -> Int? {
    if let i = v as? Int { return i }
    if let d = v as? Double { return Int(d) }
    if let n = v as? NSNumber { return n.intValue }
    return nil
}

/// Coerce an option-bag number to Double (Int-vs-Double trap).
func tlReadDouble(_ v: Any?) -> Double? {
    if let d = v as? Double { return d }
    if let i = v as? Int { return Double(i) }
    if let n = v as? NSNumber { return n.doubleValue }
    return nil
}
