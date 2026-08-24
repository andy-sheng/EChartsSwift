// Ported from echarts/src/component/toolbox/feature/{SaveAsImage,Restore,MagicType,DataZoom}.ts
//   (the icon default-options + onclick cores) — keep in sync with upstream.
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

// ════════════════════════════════════════════════════════════════════════════════════════════
// feature/DataView.ts — on-canvas feature + native host presentation seam
// ════════════════════════════════════════════════════════════════════════════════════════════
private let DATA_VIEW_BLOCK_SPLITTER = String(repeating: "-", count: 59)
private let DATA_VIEW_ITEM_SPLITTER = "\t"

public enum ToolboxDataViewError: Error {
    case invalidFormat(String)
}

/// Native-host equivalent of the browser data-view overlay. The feature owns content generation and
/// parsing; the app owns presentation (sheet/popover/editor) and calls `refresh` with edited text.
public final class ToolboxDataViewPresentation {
    public let title: String
    public let lang: [String]
    public let readOnly: Bool
    public let content: String
    private let refreshHandler: (String) throws -> Void

    public init(
        title: String, lang: [String], readOnly: Bool, content: String,
        refresh: @escaping (String) throws -> Void
    ) {
        self.title = title
        self.lang = lang
        self.readOnly = readOnly
        self.content = content
        self.refreshHandler = refresh
    }

    public func refresh(_ editedContent: String) throws {
        guard !readOnly else { return }
        try refreshHandler(editedContent)
    }
}

private func dataViewString(_ value: Any?) -> String {
    guard let value, !(value is NSNull) else { return "" }
    if let string = value as? String { return string }
    if let numberValue = value as? NSNumber {
        return number.jsNumberString(numberValue.doubleValue)
    }
    return String(describing: value)
}

private func dataViewValues(_ value: Any?) -> [String] {
    if let values = value as? [Any] { return values.map(dataViewString) }
    if let values = value as? [Double] { return values.map { number.jsNumberString($0) } }
    if let values = value as? [Int] { return values.map(String.init) }
    return [dataViewString(value)]
}

private func dataViewContent(_ ecModel: GlobalModel) -> String {
    var blocks: [String] = []
    ecModel.eachRawSeries { series, _ in
        let data = series.getRawData()
        var lines = [series.name]
        for index in 0..<data.count() {
            let raw = data.getRawDataItem(index)
            let name: String
            let value: Any?
            if let item = raw as? [String: Any] {
                name = (item["name"] as? String) ?? data.getName(index)
                value = item["value"]
            }
            else {
                name = data.getName(index)
                value = raw
            }
            let valueText = dataViewValues(value).joined(separator: DATA_VIEW_ITEM_SPLITTER)
            lines.append(name.isEmpty ? valueText : name + DATA_VIEW_ITEM_SPLITTER + valueText)
        }
        blocks.append(lines.joined(separator: "\n"))
    }
    return blocks.joined(separator: "\n\n\(DATA_VIEW_BLOCK_SPLITTER)\n\n")
}

private func parseDataViewContent(_ content: String) throws -> [String: Any] {
    let blocks = content.components(separatedBy: DATA_VIEW_BLOCK_SPLITTER)
    var seriesOptions: [[String: Any]] = []
    for rawBlock in blocks {
        let block = rawBlock.trimmingCharacters(in: .whitespacesAndNewlines)
        if block.isEmpty { continue }
        var lines = block.split(whereSeparator: \Character.isNewline).map(String.init)
        guard !lines.isEmpty else { continue }
        let seriesName = lines.removeFirst().trimmingCharacters(in: .whitespaces)
        guard !seriesName.isEmpty else {
            throw ToolboxDataViewError.invalidFormat("series name is empty")
        }
        var data: [Any] = []
        for rawLine in lines {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }
            var items = line.components(separatedBy: DATA_VIEW_ITEM_SPLITTER)
                .filter { !$0.isEmpty }
            guard !items.isEmpty else { continue }
            let hasName = Double(items[0]) == nil
            let name = hasName ? items.removeFirst() : nil
            let values = try items.map { token -> Double in
                guard let value = Double(token.trimmingCharacters(in: .whitespaces)) else {
                    throw ToolboxDataViewError.invalidFormat("non-numeric value: \(token)")
                }
                return value
            }
            guard !values.isEmpty else {
                throw ToolboxDataViewError.invalidFormat("data row has no values")
            }
            let value: Any = values.count == 1 ? values[0] : values
            if let name { data.append(["name": name, "value": value] as [String: Any]) }
            else { data.append(value) }
        }
        seriesOptions.append(["name": seriesName, "data": data] as [String: Any])
    }
    guard !seriesOptions.isEmpty else {
        throw ToolboxDataViewError.invalidFormat("no series blocks")
    }
    return ["series": seriesOptions]
}

open class ToolboxDataViewFeature: ToolboxFeature {
    open override func onclick(_ ecModel: GlobalModel, _ api: ExtensionAPI, _ type: String) {
        let model = self.model!
        let lang = (model.get("lang") as? [String]) ?? []
        let title = lang.first ?? (model.get("title") as? String) ?? "Data View"
        let readOnly = (model.get("readOnly") as? Bool) ?? false
        let presentation = ToolboxDataViewPresentation(
            title: title, lang: lang, readOnly: readOnly, content: dataViewContent(ecModel)
        ) { editedContent in
            var payload = Payload(type: "changeDataView")
            payload.other["newOption"] = try parseDataViewContent(editedContent)
            api.dispatchAction(payload)
        }
        api.presentDataView(presentation)
    }

    public static func getDefaultOption(_ ecModel: GlobalModel) -> [String: Any] {
        var opt: [String: Any] = [
            "show": true,
            "readOnly": false,
            "icon": "M17.5,17.3H33 M17.5,17.3H33 M45.4,29.5h-28 M11.5,2v56H51V14.8L38.4,2H11.5z M38.4,2.2v12.7H51 M45.4,41.7h-28",
            "backgroundColor": tokens.color.background,
            "textColor": tokens.color.primary,
            "textareaColor": tokens.color.background,
            "textareaBorderColor": tokens.color.border,
            "buttonColor": tokens.color.accent50,
            "buttonTextColor": tokens.color.neutral00
        ]
        if let title = ecModel.getLocaleModel().get(["toolbox", "dataView", "title"]) {
            opt["title"] = title
        }
        if let lang = ecModel.getLocaleModel().get(["toolbox", "dataView", "lang"]) {
            opt["lang"] = lang
        }
        return opt
    }
}

// ════════════════════════════════════════════════════════════════════════════════════════════
// feature/SaveAsImage.ts — class SaveAsImage extends ToolboxFeature
// ════════════════════════════════════════════════════════════════════════════════════════════
open class ToolboxSaveAsImageFeature: ToolboxFeature {

    // onclick(ecModel, api) { const url = api.getConnectedDataURL(...); ...download the data URL... }
    //   PORT: the SVG-painter branch + the browser download machinery (`<a download>` /
    //   `msSaveOrOpenBlob` / `window.open`) collapse to the host seam: `api.getConnectedDataURL` returns
    //   the ENCODED PNG bytes (rendered by the host-injected `ECharts.getRenderedImage`) and
    //   `api.saveAsImage` hands them to the host (`ECharts.onSaveImage`) — the download analog. Both
    //   nil in pure headless → silent no-op. The URL-building option bag is faithful.
    open override func onclick(_ ecModel: GlobalModel, _ api: ExtensionAPI, _ type: String) {
        let model = self.model!
        // const title = model.get('name') || ecModel.get('title.0.text') || 'echarts';
        var title = "echarts"
        if let name = model.get("name") as? String, !name.isEmpty {
            title = name
        }
        else if let titleText = ecModel.getComponent("title")?.get("text") as? String, !titleText.isEmpty {
            // upstream `ecModel.get('title.0.text')` — the first title component's text.
            title = titleText
        }
        // const isSvg = api.getZr().painter.getType() === 'svg';  (native painter is raster → png)
        //   type = isSvg ? 'svg' : model.get('type', true) || 'png';
        let imgType = (model.get("type", true) as? String) ?? "png"
        // const url = api.getConnectedDataURL({ type, backgroundColor, connectedBackgroundColor,
        //     excludeComponents, pixelRatio });
        var opts: [String: Any] = ["type": imgType]
        if let bg = model.get("backgroundColor", true) ?? ecModel.get("backgroundColor") {
            opts["backgroundColor"] = bg
        }
        if let cbg = model.get("connectedBackgroundColor") {
            opts["connectedBackgroundColor"] = cbg
        }
        if let exclude = model.get("excludeComponents") {
            opts["excludeComponents"] = exclude
        }
        if let pixelRatio = model.get("pixelRatio") {
            opts["pixelRatio"] = pixelRatio
        }
        guard let data = api.getConnectedDataURL(opts) else {
            // PORT-STUB: the host has no rasterizer wired (`ExtensionAPI.getConnectedDataURL`), so
            // clicking Save-as-Image does nothing at all — the toolbox icon is drawn and inert.
            PortStub.hit("toolboxFeatures.SaveAsImage",
                         "no host rasterizer wired; the Save-as-Image toolbox button silently does nothing")
            return
        }
        // The browser `<a download>` → the host save callback (PORT SEAM).
        api.saveAsImage(data, title + "." + imgType)
    }

    // static getDefaultOption(ecModel)
    public static func getDefaultOption(_ ecModel: GlobalModel) -> [String: Any] {
        var opt: [String: Any] = [
            "show": true,
            "icon": "M4.7,22.9L29.3,45.5L54.7,23.4M4.6,43.6L4.6,58L53.8,58L53.8,43.6M29.2,45.1L29.2,0",
            "type": "png",
            // Default use option.backgroundColor
            "connectedBackgroundColor": tokens.color.neutral00,
            "name": "",
            "excludeComponents": ["toolbox"]
            // pixelRatio: use current device pixel ratio by default.
        ]
        // title: ecModel.getLocaleModel().get(['toolbox', 'saveAsImage', 'title'])
        if let title = ecModel.getLocaleModel().get(["toolbox", "saveAsImage", "title"]) {
            opt["title"] = title
        }
        if let lang = ecModel.getLocaleModel().get(["toolbox", "saveAsImage", "lang"]) {
            opt["lang"] = lang
        }
        return opt
    }
}

// ════════════════════════════════════════════════════════════════════════════════════════════
// feature/Restore.ts — class RestoreOption extends ToolboxFeature
// ════════════════════════════════════════════════════════════════════════════════════════════
open class ToolboxRestoreFeature: ToolboxFeature {

    // onclick(ecModel, api) {
    //     history.clear(ecModel);
    //     api.dispatchAction({ type: 'restore', from: this.uid });
    // }
    open override func onclick(_ ecModel: GlobalModel, _ api: ExtensionAPI, _ type: String) {
        // history.clear(ecModel) — drop the toolbox dataZoom snapshot stack (the `restore` action then
        //   resets the full option via the registered handler).
        dataZoomHistoryClear(ecModel)
        var payload = Payload(type: "restore")
        payload.other["from"] = self.uid
        api.dispatchAction(payload)
    }

    // static getDefaultOption(ecModel)
    public static func getDefaultOption(_ ecModel: GlobalModel) -> [String: Any] {
        var opt: [String: Any] = [
            "show": true,
            "icon": "M3.8,33.4 M47,18.9h9.8V8.7 M56.3,20.1 C52.1,9,40.5,0.6,26.8,2.1C12.6,3.7,1.6,16.2,2.1,30.6 M13,41.1H3.1v10.2 M3.7,39.9c4.2,11.1,15.8,19.5,29.5,18 c14.2-1.6,25.2-14.1,24.7-28.5"
        ]
        if let title = ecModel.getLocaleModel().get(["toolbox", "restore", "title"]) {
            opt["title"] = title
        }
        return opt
    }
}

// ════════════════════════════════════════════════════════════════════════════════════════════
// feature/MagicType.ts — class MagicType extends ToolboxFeature
// ════════════════════════════════════════════════════════════════════════════════════════════

// const ICON_TYPES = ['line', 'bar', 'stack'];
let TOOLBOX_MAGICTYPE_ICON_TYPES = ["line", "bar", "stack"]
// const radioTypes = [ ['line', 'bar'], ['stack'] ];
private let toolboxMagicRadioTypes: [[String]] = [["line", "bar"], ["stack"]]

open class ToolboxMagicTypeFeature: ToolboxFeature {

    // getIcons() { each(model.get('type'), type => { if (availableIcons[type]) icons[type] = availableIcons[type]; }); }
    open override func getIcons() -> [String: String]? {
        let availableIcons = (self.model.get("icon") as? [String: Any]) ?? [:]
        var icons: [String: String] = [:]
        let types = (self.model.get("type") as? [Any]) ?? []
        for t in types {
            guard let type = t as? String else { continue }
            if let icon = availableIcons[type] as? String {
                icons[type] = icon
            }
        }
        return icons
    }

    // static getDefaultOption(ecModel)
    public static func getDefaultOption(_ ecModel: GlobalModel) -> [String: Any] {
        var opt: [String: Any] = [
            "show": true,
            "type": [String](),
            // Icon group
            "icon": [
                "line": "M4.1,28.9h7.1l9.3-22l7.4,38l9.7-19.7l3,12.8h14.9M4.1,58h51.4",
                "bar": "M6.7,22.9h10V48h-10V22.9zM24.9,13h10v35h-10V13zM43.2,2h10v46h-10V2zM3.1,58h53.7",
                "stack": "M8.2,38.4l-8.4,4.1l30.6,15.3L60,42.5l-8.1-4.1l-21.5,11L8.2,38.4z M51.9,30l-8.1,4.2l-13.4,6.9l-13.9-6.9L8.2,30l-8.4,4.2l8.4,4.2l22.2,11l21.5-11l8.1-4.2L51.9,30z M51.9,21.7l-8.1,4.2L35.7,30l-5.3,2.8L24.9,30l-8.4-4.1l-8.3-4.2l-8.4,4.2L8.2,30l8.3,4.2l13.9,6.9l13.4-6.9l8.1-4.2l8.1-4.1L51.9,21.7zM30.4,2.2L-0.2,17.5l8.4,4.1l8.3,4.2l8.4,4.2l5.5,2.7l5.3-2.7l8.1-4.2l8.1-4.2l8.1-4.1L30.4,2.2z"
            ] as [String: Any],
            "option": [String: Any](),
            "seriesIndex": [String: Any]()
        ]
        // title: ecModel.getLocaleModel().get(['toolbox', 'magicType', 'title'])  (`line`,`bar`,`stack`,`tiled`)
        if let title = ecModel.getLocaleModel().get(["toolbox", "magicType", "title"]) {
            opt["title"] = title
        }
        return opt
    }

    // onclick(ecModel, api, type) — builds the `newOption` that swaps every convertible series to
    //   `type` and dispatches `changeMagicType`. PORT REDUCTION: the per-series `seriesOptGenreator`
    //   (data/stack/markPoint/markLine carry-over + boundaryGap flip) is factored into the shared
    //   `computeMagicTypeOption(ecModel, targetType)` (toolboxAction.swift) — see its header for the
    //   documented scope (line↔bar + stack/tiled; data/marker carry-over deferred). The
    //   `radioTypes`/`setIconStatus` bookkeeping + the stack↔tiled title flip are faithful below.
    open override func onclick(_ ecModel: GlobalModel, _ api: ExtensionAPI, _ type: String) {
        let model = self.model!

        // each(radioTypes, radio => { if (indexOf(radio, type) >= 0) each(radio, item => setIconStatus(item,'normal')); });
        for radio in toolboxMagicRadioTypes where radio.contains(type) {
            for item in radio {
                toolboxSetIconStatus(model, item, "normal")
            }
        }
        // model.setIconStatus(type, 'emphasis');
        toolboxSetIconStatus(model, type, "emphasis")

        // For 'stack', upstream toggles based on the CURRENT stack state (stack ↔ tiled). Decide the
        //   effective target so `computeMagicTypeOption` sets vs clears the shared stack key.
        var currentType = type
        if type == "stack" {
            var isStacked = false
            ecModel.eachSeries { seriesModel, _ in
                if (seriesModel.get("stack") as? String) == TOOLBOX_MAGIC_STACK_KEYWORD {
                    isStacked = true
                }
            }
            // if (model.get(['iconStatus', type]) !== 'emphasis') currentType = 'tiled';
            currentType = isStacked ? "tiled" : "stack"
        }

        // const newOption = { series: [...], [axisType]?: [...] };
        let newOption = computeMagicTypeOption(ecModel, currentType)

        // api.dispatchAction({ type:'changeMagicType', currentType, newOption, newTitle, featureName:'magicType' });
        var payload = Payload(type: "changeMagicType")
        payload.other["currentType"] = currentType
        payload.other["newOption"] = newOption
        payload.other["featureName"] = "magicType"
        // PORT-NOTE (deferred): `newTitle` (the stack↔tiled title flip merged into the feature option,
        //   FIX#11236) requires the consuming side ToolboxView payload.newTitle merge (ToolboxView.ts:152,
        //   `featureOpt.title = payload.newTitle`), which is not ported — so emitting newTitle here would
        //   be inert (no live title update). Wire once ToolboxView consumes payload.newTitle.
        api.dispatchAction(payload)
    }
}

// ════════════════════════════════════════════════════════════════════════════════════════════
// feature/DataZoom.ts — class DataZoomFeature extends ToolboxFeature
// ════════════════════════════════════════════════════════════════════════════════════════════

// const ICON_TYPES = ['zoom', 'back'];
open class ToolboxDataZoomFeature: ToolboxFeature {

    // upstream: `_isZoomActive: boolean` (toggled by the `zoom` icon; enables the BrushController drag).
    //   The port drives the actual box-drag from the live host (EChartsView) reading the driver-level
    //   `dataZoomSelectActive` flag; this per-feature copy tracks the icon's emphasis state.
    var _isZoomActive: Bool = false

    // getIcons() — same pattern as MagicType: filter the icon group by the enabled `type`s.
    open override func getIcons() -> [String: String]? {
        let availableIcons = (self.model.get("icon") as? [String: Any]) ?? [:]
        var icons: [String: String] = [:]
        let types = (self.model.get("type") as? [Any]) ?? ["zoom", "back"]
        for t in types {
            guard let type = t as? String else { continue }
            if let icon = availableIcons[type] as? String {
                icons[type] = icon
            }
        }
        return icons
    }

    // render(featureModel, ecModel, api, payload) — upstream mounts the BrushController then
    //   `updateZoomBtnStatus` + `updateBackBtnStatus`. PORT: the BrushController mount is DEFERRED (the
    //   live host `EChartsView` owns the rect-drag); this keeps the icon-status bookkeeping faithful —
    //   the `zoom` icon reflects the arm state (flipped by a `takeGlobalCursor` payload) and the `back`
    //   icon is emphasized only while there is history to pop.
    open override func render(
        _ featureModel: ToolboxFeatureModel, _ ecModel: GlobalModel, _ api: ExtensionAPI, _ payload: Payload
    ) {
        // updateZoomBtnStatus
        var zoomActive = _isZoomActive
        if payload.type == "takeGlobalCursor" {
            zoomActive = (payload.other["key"] as? String) == "dataZoomSelect"
                ? ((payload.other["dataZoomSelectActive"] as? Bool) ?? false)
                : false
        }
        _isZoomActive = zoomActive
        toolboxSetIconStatus(featureModel, "zoom", zoomActive ? "emphasis" : "normal")
        // updateBackBtnStatus: history.count(ecModel) > 1 ? 'emphasis' : 'normal'
        toolboxSetIconStatus(featureModel, "back", dataZoomHistoryCount(ecModel) > 1 ? "emphasis" : "normal")
    }

    // onclick(ecModel, api, type) { handlers[type].call(this); }  // 'zoom' arms a box-select; 'back' pops history
    open override func onclick(_ ecModel: GlobalModel, _ api: ExtensionAPI, _ type: String) {
        switch type {
        case "zoom":
            // handlers.zoom: `const nextActive = !this._isZoomActive; api.dispatchAction({type:
            //   'takeGlobalCursor', key: 'dataZoomSelect', dataZoomSelectActive: nextActive});`
            //   Read the CURRENT arm state off the driver (via the api) so the toggle is correct even
            //   though the feature instance is rebuilt each render (its `_isZoomActive` would otherwise
            //   reset). Falls back to the per-feature copy for a non-api.
            let current = (api as? EChartsExtensionAPI)?.dataZoomSelectActiveValue ?? _isZoomActive
            let nextActive = !current
            _isZoomActive = nextActive
            var payload = Payload(type: "takeGlobalCursor")
            payload.other["key"] = "dataZoomSelect"
            payload.other["dataZoomSelectActive"] = nextActive
            api.dispatchAction(payload)
        case "back":
            // handlers.back: `this._dispatchZoomAction(history.pop(this.ecModel));`
            _dispatchZoomAction(dataZoomHistoryPop(ecModel), api)
        default:
            break
        }
    }

    // dispose(ecModel, api) { this._brushController && this._brushController.dispose(); }
    //   PORT: no live BrushController (the host owns the drag) → nothing to dispose.

    // _dispatchZoomAction(snapshot) — convert the { dataZoomId: batchItem } snapshot to a dataZoom
    //   action batch and dispatch (upstream `this.api.dispatchAction({type:'dataZoom', from:uid, batch})`).
    func _dispatchZoomAction(_ snapshot: DataZoomStoreSnapshot, _ api: ExtensionAPI) {
        var batch: [PayloadItem] = []
        for (_, batchItem) in snapshot {
            var item = PayloadItem()
            item.other = batchItem   // { dataZoomId, start/end | startValue/endValue }
            batch.append(item)
        }
        if !batch.isEmpty {
            var payload = Payload(type: "dataZoom")
            payload.other["from"] = self.uid
            payload.batch = batch
            api.dispatchAction(payload)
        }
    }

    // static getDefaultOption(ecModel)
    public static func getDefaultOption(_ ecModel: GlobalModel) -> [String: Any] {
        var opt: [String: Any] = [
            "show": true,
            // Icon group
            "icon": [
                "zoom": "M0,13.5h26.9 M13.5,26.9V0 M32.1,13.5H58V58H13.5 V32.1",
                "back": "M22,1.4L9.9,13.5l12.3,12.3 M10.3,13.5H54.9v44.6 H10.3v-26"
            ] as [String: Any],
            // 'zoom' & 'back'
            "type": ["zoom", "back"],
            "filterMode": "filter"
        ]
        if let title = ecModel.getLocaleModel().get(["toolbox", "dataZoom", "title"]) {
            opt["title"] = title
        }
        if let brushStyle = ecModel.getLocaleModel().get(["toolbox", "dataZoom", "brushStyle"]) {
            opt["brushStyle"] = brushStyle
        }
        return opt
    }
}

// ════════════════════════════════════════════════════════════════════════════════════════════
// component/toolbox/install.ts — built-in feature registrations.
// ════════════════════════════════════════════════════════════════════════════════════════════
public func registerToolboxFeatures() {
    registerFeature("saveAsImage", ToolboxFeatureRegistration(
        create: { ToolboxSaveAsImageFeature() },
        getDefaultOption: { ToolboxSaveAsImageFeature.getDefaultOption($0) }
    ))
    registerFeature("magicType", ToolboxFeatureRegistration(
        create: { ToolboxMagicTypeFeature() },
        getDefaultOption: { ToolboxMagicTypeFeature.getDefaultOption($0) }
    ))
    registerFeature("dataZoom", ToolboxFeatureRegistration(
        create: { ToolboxDataZoomFeature() },
        getDefaultOption: { ToolboxDataZoomFeature.getDefaultOption($0) }
    ))
    registerFeature("restore", ToolboxFeatureRegistration(
        create: { ToolboxRestoreFeature() },
        getDefaultOption: { ToolboxRestoreFeature.getDefaultOption($0) }
    ))
    registerFeature("dataView", ToolboxFeatureRegistration(
        create: { ToolboxDataViewFeature() },
        getDefaultOption: { ToolboxDataViewFeature.getDefaultOption($0) }
    ))
}
