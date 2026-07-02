// Ported from echarts/src/visual/style.ts — keep in sync with upstream

import ZRenderKit
// import { isFunction, extend, createHashMap } from 'zrender/src/core/util';
//   -> util.isFunction / util.extend (ZRenderKit); createHashMap (EChartsKit modelUtil shim)
// import { StageHandler, CallbackDataParams, ZRColor, Dictionary, InnerDecalObject } from '../util/types';
//   -> StageHandler / CallbackDataParams / ZRColor / Dictionary / InnerDecalObject (EChartsKit util/types.swift + ZRenderKit Dictionary)
// import makeStyleMapper from '../model/mixin/makeStyleMapper';  -> makeStyleMapper (EChartsKit model/mixin)
// import { ITEM_STYLE_KEY_MAP } from '../model/mixin/itemStyle';  -> ITEM_STYLE_KEY_MAP (EChartsKit model/mixin)
// import { LINE_STYLE_KEY_MAP } from '../model/mixin/lineStyle';  -> LINE_STYLE_KEY_MAP (EChartsKit model/mixin)
// import SeriesModel from '../model/Series';                      -> SeriesModel (EChartsKit model/Series.swift)
// import Model from '../model/Model';                             -> Model (EChartsKit model/Model.swift)
// import { makeInner } from '../util/model';                      -> model.makeInner (EChartsKit util/modelUtil.swift)

// PORT-TODO: no upstream alias — the mapper closure type is spelled out for Swift. It mirrors
//   makeStyleMapper's returned closure `(model, excludes?, includes?) => Dictionary<any>`.
//   (Swift closures cannot carry defaulted params, so callers pass `nil` for excludes/includes.)
private typealias StyleMapper = (Model, [String]?, [String]?) -> Dictionary<Any>

// upstream: const inner = makeInner<{scope: object}, SeriesModel>();
// PORT-TODO: upstream inner store is the anonymous bag `{scope: object}`; modeled as a
//   reference type so `makeInner`'s WeakMap can key/store it (CONVENTIONS §4).
final class StyleInner {
    var scope: AnyObject?   // upstream: scope: object (an identity object for palette scoping)
    init() {}
}
private let inner: (SeriesModel) -> StyleInner = model.makeInner { StyleInner() }

// PORT-TODO: upstream palette `scope` is the object literal `{}`, used only as a WeakMap
//   identity key by getColorFromPalette (see model/mixin/palette.swift). Modeled as an empty class.
private final class PaletteScope {}

private let defaultStyleMappers: [String: StyleMapper] = [
    "itemStyle": makeStyleMapper(ITEM_STYLE_KEY_MAP, true),
    "lineStyle": makeStyleMapper(LINE_STYLE_KEY_MAP, true)
]

private let defaultColorKey: [String: String] = [
    "lineStyle": "stroke",
    "itemStyle": "fill"
]

private func getStyleMapper(_ seriesModel: SeriesModel, _ stylePath: String) -> StyleMapper {
    let styleMapper = seriesModel.visualStyleMapper
        ?? defaultStyleMappers[stylePath]   // stylePath as 'itemStyle' | 'lineStyle'
    if styleMapper == nil {
        log.warn("Unknown style type '\(stylePath)'.")
        return defaultStyleMappers["itemStyle"]!
    }
    return styleMapper!
}

private func getDefaultColorKey(_ seriesModel: SeriesModel, _ stylePath: String) -> String {   // 'stroke' | 'fill'
    // return defaultColorKey[stylePath] ||
    // upstream: visualDrawType is a non-optional string on the prototype; the `||` guards
    //   subclass overrides that clear it, so replicate the truthy (non-empty) test.
    let colorKey: String? = !seriesModel.visualDrawType.isEmpty
        ? seriesModel.visualDrawType
        : defaultColorKey[stylePath]   // stylePath as 'itemStyle' | 'lineStyle'

    if colorKey == nil {
        log.warn("Unknown style type '\(stylePath)'.")
        return "fill"
    }

    return colorKey!
}

// upstream: type ColorCallback = (params: CallbackDataParams) => ZRColor;
private typealias ColorCallback = (CallbackDataParams) -> ZRColor

let seriesStyleTask: StageHandler = {
    var handler = StageHandler()
    handler.createOnAllSeries = true
    handler.performRawSeries = true
    // upstream reset(seriesModel, ecModel); the ported StageHandlerReset carries (api, payload) too.
    handler.reset = { (seriesModel: SeriesModel, ecModel: GlobalModel, _ api: ExtensionAPI, _ payload: Payload?) -> Any? in
        let data = seriesModel.getData()
        // upstream: seriesModel.visualStyleAccessPath || 'itemStyle'
        let stylePath = !seriesModel.visualStyleAccessPath.isEmpty
            ? seriesModel.visualStyleAccessPath
            : "itemStyle"
        // Set in itemStyle
        let styleModel = seriesModel.getModel(stylePath)
        let getStyle = getStyleMapper(seriesModel, stylePath)

        var globalStyle = getStyle(styleModel, nil, nil)

        let decalOption = styleModel.getShallow("decal")   // as InnerDecalObject
        if decalOption != nil {
            data.setVisual("decal", decalOption)
            // decalOption.dirty = true;
            // PORT-TODO: InnerDecalObject is a value struct; the in-place `dirty = true` mutation
            //   does not propagate to the stored visual. Decal is out of bar-render scope.
        }

        // TODO
        let colorKey = getDefaultColorKey(seriesModel, stylePath)
        let color = globalStyle[colorKey]

        // TODO style callback
        let colorCallback: ColorCallback? = util.isFunction(color) ? (color as? ColorCallback) : nil
        let hasAutoColor = (globalStyle["fill"] as? String) == "auto" || (globalStyle["stroke"] as? String) == "auto"
        // Get from color palette by default.
        if globalStyle[colorKey] == nil || colorCallback != nil || hasAutoColor {
            // Note: If some series has color specified (e.g., by itemStyle.color), we DO NOT
            // make it effect palette. Because some scenarios users need to make some series
            // transparent or as background, which should better not effect the palette.
            let colorPalette = seriesModel.getColorFromPalette(
                // TODO series count changed.
                seriesModel.name, nil, ecModel.getSeriesCount()
            )
            if globalStyle[colorKey] == nil {
                globalStyle[colorKey] = colorPalette
                data.setVisual("colorFromPalette", true)
            }
            globalStyle["fill"] = ((globalStyle["fill"] as? String) == "auto" || util.isFunction(globalStyle["fill"]))
                ? (colorPalette as Any?)
                : globalStyle["fill"]
            globalStyle["stroke"] = ((globalStyle["stroke"] as? String) == "auto" || util.isFunction(globalStyle["stroke"]))
                ? (colorPalette as Any?)
                : globalStyle["stroke"]
        }

        data.setVisual("style", globalStyle)
        data.setVisual("drawType", colorKey)

        // Only visible series has each data be visual encoded
        if !ecModel.isSeriesFiltered(seriesModel) && colorCallback != nil {
            data.setVisual("colorFromPalette", false)

            var executor = StageHandlerProgressExecutor()
            executor.dataEach = { (data: SeriesData, idxD: Double) in
                // PORT-TODO: the color-callback path needs SeriesModel.getDataParams, which is
                //   provided by DataFormatMixin — not yet conformed on SeriesModel (see
                //   model/Series.swift PORT-TODO). Deferred; out of bar-render scope.
                // const dataParams = seriesModel.getDataParams(idx);
                // const itemStyle = extend({}, globalStyle);
                // itemStyle[colorKey] = colorCallback(dataParams);
                // data.setItemVisual(idx, 'style', itemStyle);
                _ = data
                _ = idxD
            }
            return executor
        }
        return nil
    }
    return handler
}()

private let sharedModel = Model()
let dataStyleTask: StageHandler = {
    var handler = StageHandler()
    handler.createOnAllSeries = true
    handler.reset = { (seriesModel: SeriesModel, ecModel: GlobalModel, _ api: ExtensionAPI, _ payload: Payload?) -> Any? in
        if seriesModel.ignoreStyleOnData {
            return nil
        }

        let data = seriesModel.getData()
        let stylePath = !seriesModel.visualStyleAccessPath.isEmpty
            ? seriesModel.visualStyleAccessPath
            : "itemStyle"
        // Set in itemStyle
        let getStyle = getStyleMapper(seriesModel, stylePath)

        let colorKey = data.getVisual("drawType")   // upstream: string

        var executor = StageHandlerProgressExecutor()
        executor.dataEach = data.hasItemOption ? { (data: SeriesData, idxD: Double) in
            let idx = Int(idxD)
            // Not use getItemModel for performance considuration
            let rawItem = data.getRawDataItem(idx)   // as any
            if let rawDict = rawItem as? [String: Any], let stylePathVal = rawDict[stylePath] {
                sharedModel.option = stylePathVal
                let style = getStyle(sharedModel, nil, nil)

                // PORT-TODO: upstream `existsStyle` is the very object stored in the item visual and
                //   `extend(existsStyle, style)` mutates it in place. Swift dictionaries are value
                //   types, so extend a local copy and write it back via setItemVisual (CONVENTIONS §3).
                var existsStyle = (data.ensureUniqueItemVisual(idx, "style") as? [String: Any]) ?? [:]
                existsStyle = util.extend(&existsStyle, style)
                data.setItemVisual(idx, "style", existsStyle)

                if let decal = (sharedModel.option as? [String: Any])?["decal"] {
                    data.setItemVisual(idx, "decal", decal)
                    // sharedModel.option.decal.dirty = true;
                    // PORT-TODO: value-type option bag; `dirty = true` mutation not propagated. Deferred.
                }

                if let ck = colorKey as? String, style[ck] != nil {   // colorKey in style
                    data.setItemVisual(idx, "colorFromPalette", false)
                }
            }
        } : nil
        return executor
    }
    return handler
}()

// Pick color from palette for the data which has not been set with color yet.
// Note: do not support stream rendering. No such cases yet.
let dataColorPaletteTask: StageHandler = {
    var handler = StageHandler()
    handler.performRawSeries = true
    handler.overallReset = { (ecModel: GlobalModel, _ api: ExtensionAPI, _ payload: Payload?) in
        // Each type of series uses one scope.
        // Pie and funnel are using different scopes.
        // upstream: createHashMap<object>(); Swift cannot spell explicit generic args on a
        //   free-function call, so annotate the result type instead.
        let paletteScopeGroupByType: HashMap<PaletteScope> = createHashMap()
        ecModel.eachSeries { (seriesModel: SeriesModel, _ idx: Double) in
            if !seriesModel.isColorBySeries() {
                let key = seriesModel.type + "-" + seriesModel.getColorBy().rawValue
                inner(seriesModel).scope = paletteScopeGroupByType.get(key)
                    ?? paletteScopeGroupByType.set(key, PaletteScope())
            }
        }

        ecModel.eachSeries { (seriesModel: SeriesModel, _ idx: Double) in
            if seriesModel.isColorBySeries() {
                return
            }

            let dataAll = seriesModel.getRawData()
            // upstream: const idxMap: Dictionary<number> = {};  (number key coerced to string)
            var idxMap: [Int: Int] = [:]
            let data = seriesModel.getData()
            let colorScope = inner(seriesModel).scope

            let stylePath = !seriesModel.visualStyleAccessPath.isEmpty
                ? seriesModel.visualStyleAccessPath
                : "itemStyle"
            let colorKey = getDefaultColorKey(seriesModel, stylePath)

            data.each { (args: [ParsedValue]) in
                let idx = Int(args[0] as! Double)
                let rawIdx = data.getRawIndex(idx)
                idxMap[rawIdx] = idx
            }

            // Iterate on data before filtered. To make sure color from palette can be
            // Consistent when toggling legend.
            dataAll.each { (args: [ParsedValue]) in
                let rawIdx = Int(args[0] as! Double)
                let idx = idxMap[rawIdx]
                let fromPalette = idx != nil ? data.getItemVisual(idx!, "colorFromPalette") : nil
                // Get color from palette for each data only when the color is inherited from series color, which is
                // also picked from color palette. So following situation is not in the case:
                // 1. series.itemStyle.color is set
                // 2. color is encoded by visualMap
                if (fromPalette as? Bool) == true {
                    // PORT-TODO: value-type writeback (CONVENTIONS §3) — upstream mutates the stored
                    //   item-visual object in place; here we copy, set the key, and write it back.
                    var itemStyle = (data.ensureUniqueItemVisual(idx!, "style") as? [String: Any]) ?? [:]
                    let name = !dataAll.getName(rawIdx).isEmpty ? dataAll.getName(rawIdx) : String(rawIdx)
                    let dataCount = dataAll.count()
                    itemStyle[colorKey] = seriesModel.getColorFromPalette(name, colorScope, Double(dataCount))
                    data.setItemVisual(idx!, "style", itemStyle)
                }
            }
        }
    }
    return handler
}()

// export { seriesStyleTask, dataStyleTask, dataColorPaletteTask };
