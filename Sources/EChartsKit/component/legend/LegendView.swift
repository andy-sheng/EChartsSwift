// Ported from echarts/src/component/legend/LegendView.ts — keep in sync with upstream
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
//   import * as zrUtil from 'zrender/src/core/util';                 -> `util.*` (ZRenderKit) + `createHashMap`
//     (EChartsKit modelUtil.swift). `curry`/`each` aliases below are inlined at their call sites.
//   import { PathStyleProps } from 'zrender/src/graphic/Path';       -> the dynamic style bag `[String: Any]`
//     (getVisual('style')/getItemStyle/getLineStyle all surface `[String: Any]` in this port).
//   import { parse, stringify } from 'zrender/src/tool/color';       -> `color.parse` / `color.stringify` (ZRenderKit).
//   import * as graphic from '../../util/graphic';
//     -> `util/graphic` is NOT ported as a namespace. `graphic.Group` / `graphic.Text` / `graphic.Rect`
//        are the ZRenderKit scene-graph types `Group` / `ZRText` / `Rect` (used directly).
//        `graphic.setTooltipConfig` is deferred (interaction — PORT-TODO in `_createItem`).
//   import { enableHoverEmphasis } from '../../util/states';
//     -> PORT-TODO: `util/states` (emphasis/blur) NOT ported — DEFERRED interaction (task: STATIC RENDER
//        ONLY). Every `enableHoverEmphasis(...)` call is a documented no-op below.
//   import {setLabelStyle, createTextStyle} from '../../label/labelStyle';
//     -> `createTextStyle` reuses the module-internal `createTextStyle(_ textStyleModel, text:, fill:,
//        align:, verticalAlign:)` (AxisBuilder.swift) — a faithful minimal reproduction of
//        `label/labelStyle.createTextStyle` (its `{inheritColor}` opt / rich-text path are out of
//        static-render scope). `setLabelStyle` (selector labels) is DEFERRED — PORT-TODO in `_createSelector`.
//   import {makeBackground} from '../helper/listComponent';
//     -> PORT-TODO: `component/helper/listComponent` NOT ported. A faithful minimal `makeBackground`
//        lives at the bottom of this file (delete once component/helper/listComponent.swift lands).
//   import * as layoutUtil from '../../util/layout';                 -> `layout.*` (util/layout.swift):
//        `layout.createBoxLayoutReference` / `layout.getLayoutRect` / `layout.box` / `layout.markNewline`.
//   import ComponentView from '../../view/Component';                -> `ComponentView` (view/ComponentView.swift).
//   import LegendModel, { ...option interfaces... } from './LegendModel';
//     -> `LegendModel` (component/legend/LegendModel.swift). The `LegendItemStyleOption` /
//        `LegendLineStyleOption` / `LegendOption` / `LegendSelectorButtonOption` / `LegendIconParams` /
//        `LegendTooltipFormatterParams` interfaces collapse to the dynamic `[String: Any]` bag / typed
//        params (CONVENTIONS §2). `LegendIconParams` is emitted below (a real value bag used by
//        `getDefaultLegendIcon`).
//   import GlobalModel from '../../model/Global';                    -> `GlobalModel`.
//   import ExtensionAPI from '../../core/ExtensionAPI';              -> `ExtensionAPI`.
//   import { ZRTextAlign, ZRRectLike, ... } from '../../util/types'; -> `ZRTextAlign` (TextAlign),
//        `ZRRectLike` (RectLike/BoundingRect); the remaining are type-only.
//   import Model from '../../model/Model';                           -> `Model`.
//   import {LineStyleProps} from '../../model/mixin/lineStyle';      -> `[String: Any]` bag.
//   import {createSymbol, ECSymbol} from '../../util/symbol';        -> `symbol.createSymbol` / `ECSymbol`.
//   import SeriesModel from '../../model/Series';                    -> `SeriesModel`.
//   import { createOrUpdatePatternFromDecal } from '../../util/decal';
//     -> PORT-TODO: `util/decal` NOT ported — decal pattern from option deferred (PORT-TODO in `getLegendStyle`).
//   import { getECData } from '../../util/innerStore';               -> `innerStore.getECData` (event wiring — deferred).
//   import tokens from '../../visual/tokens';
//     -> PORT-TODO: `visual/tokens.ts` NOT ported; `tokens.color.neutral00` inlined verbatim as '#fff'
//        (same deviation as symbol.swift / axisDefault.swift).
//   import Element from 'zrender/src/Element';                       -> ZRenderKit `Element`.

// const curry = zrUtil.curry;   -> inlined at call sites (deferred action wiring).
// const each = zrUtil.each;     -> `util.each`.
// const Group = graphic.Group;  -> ZRenderKit `Group`.

// upstream: interface LegendIconParams { itemWidth; itemHeight; icon; iconRotate; itemStyle; lineStyle;
//   symbolKeepAspect } (declared in LegendModel.ts, consumed here). Emitted as a value bag.
public struct LegendIconParams {
    public var itemWidth: Double
    public var itemHeight: Double
    public var icon: String
    // upstream: iconRotate: number | 'inherit'
    public var iconRotate: Any?
    // upstream: itemStyle: LegendItemStyleOption — the dynamic style bag.
    public var itemStyle: [String: Any]
    // upstream: lineStyle: LineStyleProps — the dynamic style bag.
    public var lineStyle: [String: Any]
    public var symbolKeepAspect: Bool?
}

// upstream: class LegendView extends ComponentView
// CONVENTIONS §2: reference type + subclassed by ScrollableLegendView -> `open class`.
open class LegendView: ComponentView {

    // static type = 'legend.plain';
    public static let type = "legend.plain"
    // type = LegendView.type;
    open var type: String { return LegendView.type }

    public var newlineDisabled = false

    // private _contentGroup: graphic.Group;
    private var _contentGroup: Group!

    // private _backgroundEl: graphic.Rect;
    private var _backgroundEl: Rect?

    // private _selectorGroup: graphic.Group;
    private var _selectorGroup: Group!

    /**
     * If first rendering, `contentGroup.position` is [0, 0], which
     * does not make sense and may cause unexpected animation if adopted.
     */
    // private _isFirstRender: boolean;
    private var _isFirstRender: Bool = true

    // init() { this.group.add(this._contentGroup = new Group()); ... }
    //   The overridable base hook is `init(_ ecModel:, _ api:)` (ComponentView). Upstream `init()` takes
    //   no args (JS); the two args are ignored here to match.
    open override func `init`(_ ecModel: GlobalModel, _ api: ExtensionAPI) {
        self._contentGroup = Group()
        _ = self.group.add(self._contentGroup)
        self._selectorGroup = Group()
        _ = self.group.add(self._selectorGroup)

        self._isFirstRender = true
    }

    /**
     * @protected
     */
    public func getContentGroup() -> Group {
        return self._contentGroup
    }

    /**
     * @protected
     */
    public func getSelectorGroup() -> Group {
        return self._selectorGroup
    }

    /**
     * @override
     */
    // upstream: render(legendModel: LegendModel, ecModel: GlobalModel, api: ExtensionAPI)
    //   The base `ComponentView.render` is (model, ecModel, api, payload); upstream declares only
    //   (legendModel, ecModel, api). The override matches the full base signature (payload unused) and
    //   narrows `model` to `LegendModel` (cf. TitleView.render).
    open override func render(
        _ model: ComponentModel, _ ecModel: GlobalModel, _ api: ExtensionAPI, _ payload: Payload
    ) {
        let legendModel = model as! LegendModel

        // PORT-TODO: defensive lazy init of the persistent content/selector groups. Upstream relies on
        //   the pipeline calling `init(ecModel, api)` before `render`; other ported views (TitleView /
        //   CartesianAxisView) build their groups in `render`, so we guarantee the groups exist here.
        if self._contentGroup == nil {
            self.`init`(ecModel, api)
        }

        let isFirstRender = self._isFirstRender
        self._isFirstRender = false

        self.resetInner()

        // if (!legendModel.get('show', true)) { return; }
        if (legendModel.get("show", true) as? Bool) == false {
            return
        }

        // let itemAlign = legendModel.get('align');
        var itemAlign = legendModel.get("align") as? String
        let orient = legendModel.get("orient") as? String
        if itemAlign == nil || itemAlign == "auto" {
            itemAlign = (
                (legendModel.get("left") as? String) == "right"
                && orient == "vertical"
            ) ? "right" : "left"
        }

        // selector has been normalized to an array in model
        // const selector = legendModel.get('selector', true) as LegendSelectorButtonOption[];
        let selector = legendModel.get("selector", true) as? [Any]
        // let selectorPosition = legendModel.get('selectorPosition', true);
        var selectorPosition = legendModel.get("selectorPosition", true) as? String
        if selector != nil && (selectorPosition == nil || selectorPosition == "auto") {
            selectorPosition = orient == "horizontal" ? "end" : "start"
        }

        self.renderInner(itemAlign, legendModel, ecModel, api, selector, orient, selectorPosition)

        // Perform layout.
        let refContainer = layout.createBoxLayoutReference(legendModel, api).refContainer
        let positionInfo = legendModel.getBoxLayoutParams()
        let padding = legendModel.get("padding")

        let maxSize = layout.getLayoutRect(positionInfo, refContainer, padding)

        let mainRect = self.layoutInner(legendModel, itemAlign, maxSize, isFirstRender, selector, selectorPosition)

        // Place mainGroup, based on the calculated `mainRect`.
        // const layoutRect = layoutUtil.getLayoutRect(zrUtil.defaults({width, height}, positionInfo), ...);
        var mergedPosition = positionInfo
        mergedPosition.width = mainRect.width
        mergedPosition.height = mainRect.height
        let layoutRect = layout.getLayoutRect(mergedPosition, refContainer, padding)
        self.group.x = layoutRect.x - mainRect.x
        self.group.y = layoutRect.y - mainRect.y
        self.group.markRedraw()

        // Render background after group is layout.
        // FXIME: most itemStyle options does not work in background because inherit is not handled yet.
        let bg = makeBackground(mainRect, legendModel)
        self._backgroundEl = bg
        _ = self.group.add(bg)
    }

    // protected resetInner()
    open func resetInner() {
        _ = self.getContentGroup().removeAll()
        // this._backgroundEl && this.group.remove(this._backgroundEl);
        if let bg = self._backgroundEl {
            _ = self.group.remove(bg)
        }
        _ = self.getSelectorGroup().removeAll()
    }

    // protected renderInner(itemAlign, legendModel, ecModel, api, selector, orient, selectorPosition)
    open func renderInner(
        _ itemAlign: String?,
        _ legendModel: LegendModel,
        _ ecModel: GlobalModel,
        _ api: ExtensionAPI,
        _ selector: [Any]?,
        _ orient: String?,
        _ selectorPosition: String?
    ) {
        let contentGroup = self.getContentGroup()
        let legendDrawnMap: HashMap<Bool> = createHashMap()
        let selectMode = legendModel.get("selectedMode")
        let triggerEvent = legendModel.get("triggerEvent")

        var excludeSeriesId: [String] = []
        ecModel.eachRawSeries { seriesModel, _ in
            // !seriesModel.get('legendHoverLink') && excludeSeriesId.push(seriesModel.id);
            if !legendJsTruthy(seriesModel.get("legendHoverLink")) {
                excludeSeriesId.append(seriesModel.id)
            }
        }

        util.each(legendModel.getData()) { legendItemModel, dataIndex in
            let name = legendItemModel.get("name") as? String

            // Use empty string or \n as a newline string
            if !self.newlineDisabled && (name == "" || name == "\n") {
                let g = Group()
                // @ts-ignore
                // g.newline = true;
                layout.markNewline(g)   // PORT-TODO: NewlineElement flag via side table (util/layout.swift).
                _ = contentGroup.add(g)
                return
            }

            // Representitive series.
            // const seriesModel = ecModel.getSeriesByName(name)[0] as SeriesModel<...>;
            //   `name` is `String?` here (PORT-TODO: numeric names become nil, LegendModel); a nil name
            //   yields no series -> the pie/funnel (`else`) branch, matching upstream when name is a data name.
            let seriesModel = name.flatMap { ecModel.getSeriesByName($0).first }

            if legendDrawnMap.get(name) == true {
                // Have been drawn
                return
            }

            // Legend to control series.
            if let seriesModel = seriesModel {
                let data = seriesModel.getData()
                let lineVisualStyle = (data.getVisual("legendLineStyle") as? [String: Any]) ?? [:]
                let legendIcon = data.getVisual("legendIcon") as? String

                // `data.getVisual('style')` may be the color from the register in series.
                let style = (data.getVisual("style") as? [String: Any]) ?? [:]

                let itemGroup = self._createItem(
                    seriesModel, name ?? "", Double(dataIndex),
                    legendItemModel, legendModel, itemAlign,
                    lineVisualStyle, style, legendIcon, selectMode, api
                )

                // PORT-TODO: DEFERRED interaction wiring (task: STATIC RENDER ONLY):
                //   itemGroup.on('click', curry(dispatchSelectAction, name, null, api, excludeSeriesId))
                //     .on('mouseover', curry(dispatchHighlightAction, seriesModel.name, null, api, excludeSeriesId))
                //     .on('mouseout', curry(dispatchDownplayAction, seriesModel.name, null, api, excludeSeriesId));
                _ = itemGroup

                // PORT-TODO: DEFERRED SSR wiring — `if (ecModel.ssr) { itemGroup.eachChild(child => {
                //   getECData(child).seriesIndex/dataIndex/ssrType = ... }) }`.

                // PORT-TODO: DEFERRED event wiring — `if (triggerEvent) { itemGroup.eachChild(child =>
                //   this.packEventData(child, legendModel, seriesModel, dataIndex, name)) }`.
                _ = triggerEvent

                legendDrawnMap.set(name, true)
            }
            else {
                // Legend to control data. In pie and funnel.
                ecModel.eachRawSeries { seriesModel, _ in

                    // In case multiple series has same data name
                    if legendDrawnMap.get(name) == true {
                        return
                    }

                    // if (seriesModel.legendVisualProvider) { ... }  — legend controls each DATA item
                    //   (pie/radar/funnel): read the item's encoded style + legendIcon from the provider
                    //   and build a legend item for it.
                    if let provider = seriesModel.legendVisualProvider as? LegendVisualProviderLike {
                        guard let name = name, provider.containName(name) else { return }
                        let dataIdx = provider.indexOfName(name)
                        let style = (provider.getItemVisual(dataIdx, "style") as? [String: Any]) ?? [:]
                        let legendIcon = provider.getItemVisual(dataIdx, "legendIcon") as? String

                        // PORT-TODO: the transparent-fill → 0.2-alpha fix-up (color.parse/stringify) and the
                        //   click/mouseover/mouseout dispatch wiring are DEFERRED (interaction). The visible
                        //   normal-state legend item is built faithfully.
                        _ = self._createItem(
                            seriesModel, name, Double(dataIndex),
                            legendItemModel, legendModel, itemAlign,
                            [:], style, legendIcon, selectMode, api
                        )

                        legendDrawnMap.set(name, true)
                    }
                }
            }

            // if (__DEV__) { if (!legendDrawnMap.get(name)) { console.warn(name + ' series not exists...'); } }
            // PORT-TODO: __DEV__ warning dropped (dev-only diagnostic).
        }

        // if (selector) { this._createSelector(selector, legendModel, api, orient, selectorPosition); }
        if let selector = selector {
            self._createSelector(selector, legendModel, api, orient, selectorPosition)
        }
    }

    // private packEventData(el, legendModel, seriesModel, dataIndex, name)
    // PORT-TODO: DEFERRED — event-data packing (`getECData(el).eventData = {...}`) is interaction/event
    //   wiring, out of static-render scope. Reproduce with `innerStore.getECData` when events land.

    // private _createSelector(selector, legendModel, api, orient, selectorPosition)
    open func _createSelector(
        _ selector: [Any],
        _ legendModel: LegendModel,
        _ api: ExtensionAPI,
        _ orient: String?,
        _ selectorPosition: String?
    ) {
        let selectorGroup = self.getSelectorGroup()

        // each(selector, function createSelectorButton(selectorItem) { ... });
        util.each(selector) { selectorItemAny, _ in
            let selectorItem = selectorItemAny as? [String: Any] ?? [:]
            // const type = selectorItem.type;
            _ = selectorItem["type"] as? String   // PORT-TODO: `type` drives the DEFERRED onclick dispatch.

            // const labelText = new graphic.Text({ style: {x,y,align,verticalAlign}, onclick() {...} });
            // PORT-TODO: DEFERRED onclick — `api.dispatchAction({type: 'legendAllSelect'|'legendInverseSelect'})`.
            var textStyle = TextStyleProps()
            textStyle.x = 0
            textStyle.y = 0
            textStyle.align = .center
            textStyle.verticalAlign = .middle
            let labelText = ZRText(["style": textStyle])

            _ = selectorGroup.add(labelText)

            let labelModel = legendModel.getModel("selectorLabel")
            _ = legendModel.getModel(["emphasis", "selectorLabel"])

            // setLabelStyle(labelText, {normal: labelModel, emphasis: emphasisLabelModel},
            //   { defaultText: selectorItem.title });
            // PORT-TODO: DEFERRED — `label/labelStyle.setLabelStyle` (normal/emphasis state + rich text)
            //   NOT ported. Reproduce the visible normal-state text so the selector geometry is meaningful.
            var s = labelText.textStyle ?? TextStyleProps()
            s.text = selectorItem["title"] as? String
            s.font = labelModel.getFont()
            s.fill = labelModel.getTextColor()
            s.align = .center
            s.verticalAlign = .middle
            labelText.textStyle = s
            labelText.dirtyStyle()

            // enableHoverEmphasis(labelText);
            // PORT-TODO: DEFERRED — emphasis/blur (util/states) out of static-render scope.
        }
    }

    // private _createItem(seriesModel, name, dataIndex, legendItemModel, legendModel, itemAlign,
    //   lineVisualStyle, itemVisualStyle, legendIcon, selectMode, api)
    open func _createItem(
        _ seriesModel: SeriesModel,
        _ name: String,
        _ dataIndex: Double,
        _ legendItemModel: Model,
        _ legendModel: LegendModel,
        _ itemAlign: String?,
        _ lineVisualStyle: [String: Any],
        _ itemVisualStyle: [String: Any],
        _ legendIconIn: String?,
        _ selectMode: Any?,
        _ api: ExtensionAPI
    ) -> Group {
        let drawType = seriesModel.visualDrawType
        let itemWidth = (legendModel.get("itemWidth") as? Double) ?? 0
        let itemHeight = (legendModel.get("itemHeight") as? Double) ?? 0
        let isSelected = legendModel.isSelected(name)

        let iconRotate = legendItemModel.get("symbolRotate")
        let symbolKeepAspect = legendItemModel.get("symbolKeepAspect") as? Bool

        let legendIconType = legendItemModel.get("icon") as? String
        // legendIcon = legendIconType || legendIcon || 'roundRect';
        let legendIcon = legendJsTruthy(legendIconType) ? legendIconType!
            : (legendJsTruthy(legendIconIn) ? legendIconIn! : "roundRect")

        let style = getLegendStyle(
            legendIcon,
            legendItemModel,
            lineVisualStyle,
            itemVisualStyle,
            drawType,
            isSelected,
            api
        )

        let itemGroup = Group()

        let textStyleModel = legendItemModel.getModel("textStyle")

        let iconParams = LegendIconParams(
            itemWidth: itemWidth,
            itemHeight: itemHeight,
            icon: legendIcon,
            iconRotate: 0.0,
            itemStyle: style.itemStyle,
            lineStyle: style.lineStyle,
            symbolKeepAspect: symbolKeepAspect
        )

        // if (isFunction(seriesModel.getLegendIcon) && (!legendIconType || legendIconType === 'inherit')) {
        //   // Series has a specific way to define its legend icon (line → line+symbol, scatter → symbol).
        //   itemGroup.add(seriesModel.getLegendIcon(iconParams));
        // } else { default icon }
        //   `getLegendIcon` is now ported on the base (returns nil) + overridden by line/scatter, so the
        //   guard becomes: no explicit legend `icon` (or 'inherit') AND the series supplies a custom icon.
        if (!legendJsTruthy(legendIconType) || legendIconType == "inherit"),
           let custom = seriesModel.getLegendIcon(iconParams) {
            _ = itemGroup.add(custom)
        }
        else {
            // Use default legend icon policy for most series.
            var params = iconParams
            if legendIconType == "inherit" && legendJsTruthy(seriesModel.getData().getVisual("symbol")) {
                params.iconRotate = legendIsInherit(iconRotate)
                    ? seriesModel.getData().getVisual("symbolRotate")
                    : iconRotate
            }
            _ = itemGroup.add(getDefaultLegendIcon(params) as? Element)
        }

        let textX = itemAlign == "left" ? itemWidth + 5 : -5
        let textAlign = (itemAlign).flatMap { TextAlign(rawValue: $0) }

        let formatter = legendModel.get("formatter")
        var content = name
        // if (zrUtil.isString(formatter) && formatter) { content = formatter.replace('{name}', name != null ? name : ''); }
        if let fmt = formatter as? String, legendJsTruthy(fmt) {
            content = legendReplaceOnce(fmt, "{name}", name)
        }
        // else if (zrUtil.isFunction(formatter)) { content = formatter(name); }
        // PORT-TODO: DEFERRED — function `formatter(name)` (dynamic callback) not modeled in the option bag.

        // const textColor = isSelected ? textStyleModel.getTextColor() : legendItemModel.get('inactiveColor');
        let textColor = isSelected
            ? textStyleModel.getTextColor()
            : legendItemModel.get("inactiveColor") as? String

        // itemGroup.add(new graphic.Text({ style: createTextStyle(textStyleModel, {text, x, y, fill, align,
        //   verticalAlign}, {inheritColor: textColor}) }));
        // PORT-TODO: the `{inheritColor: textColor}` 3rd arg (labelStyle rich behavior) is out of scope.
        var textStyle = createTextStyle(
            textStyleModel,
            text: content,
            fill: textColor,
            align: textAlign,
            verticalAlign: .middle
        )
        textStyle.x = textX
        textStyle.y = itemHeight / 2
        _ = itemGroup.add(ZRText(["style": textStyle]))

        // Add a invisible rect to increase the area of mouse hover
        // const hitRect = new graphic.Rect({ shape: itemGroup.getBoundingRect(), style: {fill: 'transparent'} });
        let bounding = itemGroup.getBoundingRect()!
        var hitShape = RectShape()
        hitShape.x = bounding.x
        hitShape.y = bounding.y
        hitShape.width = bounding.width
        hitShape.height = bounding.height
        let hitRect = Rect([
            "shape": hitShape as PathShape,
            // Cannot use 'invisible' because SVG SSR will miss the node
            "style": barStyleFromDict(["fill": "transparent"])
        ])

        // const tooltipModel = legendItemModel.getModel('tooltip') as Model<...>;
        // if (tooltipModel.get('show')) { graphic.setTooltipConfig({...}); }
        // PORT-TODO: DEFERRED — tooltip wiring (`graphic.setTooltipConfig`) out of static-render scope.
        _ = itemGroup.add(hitRect)

        // itemGroup.eachChild(function (child) { child.silent = true; });
        _ = itemGroup.eachChild { child, _ in
            child.silent = true
        }

        // hitRect.silent = !selectMode;
        hitRect.silent = !legendJsTruthy(selectMode)

        _ = self.getContentGroup().add(itemGroup)

        // enableHoverEmphasis(itemGroup);
        // PORT-TODO: DEFERRED — emphasis/blur (util/states) out of static-render scope.

        // @ts-ignore
        // itemGroup.__legendDataIndex = dataIndex;
        //   Element is not dynamically extensible in Swift, so the value lives in an inner-store side
        //   table (legendItemDataIndexInner, declared in ScrollableLegendView.swift). Read ONLY by
        //   ScrollableLegendView's pagination scan; plain LegendView never reads it, so this write is a
        //   behavioural no-op for the plain legend.
        legendItemDataIndexInner(itemGroup).value = dataIndex

        return itemGroup
    }

    // protected layoutInner(legendModel, itemAlign, maxSize, isFirstRender, selector, selectorPosition): ZRRectLike
    open func layoutInner(
        _ legendModel: LegendModel,
        _ itemAlign: String?,
        _ maxSize: BoundingRect,
        _ isFirstRender: Bool,
        _ selector: [Any]?,
        _ selectorPosition: String?
    ) -> BoundingRect {
        let contentGroup = self.getContentGroup()
        let selectorGroup = self.getSelectorGroup()

        // Place items in contentGroup.
        layout.box(
            (legendModel.get("orient") as? String) ?? "horizontal",
            contentGroup,
            (legendModel.get("itemGap") as? Double) ?? 0,
            maxSize.width,
            maxSize.height
        )

        let contentRect = contentGroup.getBoundingRect()!
        var contentPos: [Double] = [-contentRect.x, -contentRect.y]

        selectorGroup.markRedraw()
        contentGroup.markRedraw()

        if selector != nil {
            // Place buttons in selectorGroup — Buttons in selectorGroup always layout horizontally
            layout.box(
                "horizontal",
                selectorGroup,
                (legendModel.get("selectorItemGap", true) as? Double) ?? 0
            )

            let selectorRect = selectorGroup.getBoundingRect()!
            var selectorPos: [Double] = [-selectorRect.x, -selectorRect.y]
            let selectorButtonGap = (legendModel.get("selectorButtonGap", true) as? Double) ?? 0

            let orientIdx = Int(legendModel.getOrient().index)
            // wh: 'width'|'height', hw: 'height'|'width', yx: 'y'|'x' (index-0 == horizontal)
            let wh: (BoundingRect) -> Double = orientIdx == 0 ? { $0.width } : { $0.height }
            let hw: (BoundingRect) -> Double = orientIdx == 0 ? { $0.height } : { $0.width }
            let yx: (BoundingRect) -> Double = orientIdx == 0 ? { $0.y } : { $0.x }

            if selectorPosition == "end" {
                selectorPos[orientIdx] += wh(contentRect) + selectorButtonGap
            }
            else {
                contentPos[orientIdx] += wh(selectorRect) + selectorButtonGap
            }

            // Always align selector to content as 'middle'
            selectorPos[1 - orientIdx] += hw(contentRect) / 2 - hw(selectorRect) / 2
            selectorGroup.x = selectorPos[0]
            selectorGroup.y = selectorPos[1]
            contentGroup.x = contentPos[0]
            contentGroup.y = contentPos[1]

            // const mainRect = {x: 0, y: 0} as ZRRectLike;
            let mainRect = BoundingRect(0, 0, 0, 0)
            // mainRect[wh] = contentRect[wh] + selectorButtonGap + selectorRect[wh];
            let mainWH = wh(contentRect) + selectorButtonGap + wh(selectorRect)
            // mainRect[hw] = Math.max(contentRect[hw], selectorRect[hw]);
            let mainHW = Swift.max(hw(contentRect), hw(selectorRect))
            // mainRect[yx] = Math.min(0, selectorRect[yx] + selectorPos[1 - orientIdx]);
            let mainYX = Swift.min(0, yx(selectorRect) + selectorPos[1 - orientIdx])
            if orientIdx == 0 {
                mainRect.width = mainWH
                mainRect.height = mainHW
                mainRect.y = mainYX
            }
            else {
                mainRect.height = mainWH
                mainRect.width = mainHW
                mainRect.x = mainYX
            }
            return mainRect
        }
        else {
            contentGroup.x = contentPos[0]
            contentGroup.y = contentPos[1]
            return self.group.getBoundingRect()!
        }
    }

    /**
     * @protected
     */
    open func remove() {
        _ = self.getContentGroup().removeAll()
        self._isFirstRender = true
    }
}

// function getLegendStyle(iconType, legendItemModel, lineVisualStyle, itemVisualStyle, drawType, isSelected, api)
private func getLegendStyle(
    _ iconType: String,
    _ legendItemModel: Model,
    _ lineVisualStyle: [String: Any],
    _ itemVisualStyle: [String: Any],
    _ drawType: String,
    _ isSelected: Bool,
    _ api: ExtensionAPI
) -> (itemStyle: [String: Any], lineStyle: [String: Any]) {

    /**
     * Use series style if is inherit; elsewise, use legend style
     */
    func handleCommonProps(_ style: inout [String: Any], _ visualStyle: [String: Any]) {
        // If lineStyle.width is 'auto', it is set to be 2 if series has border
        if (style["lineWidth"] as? String) == "auto" {
            style["lineWidth"] = ((visualStyle["lineWidth"] as? Double) ?? 0) > 0 ? 2.0 : 0.0
        }

        // each(style, (propVal, propName) => { style[propName] === 'inherit' && (style[propName] = visualStyle[propName]); });
        //   iterate a snapshot of the keys (the dict is mutated in the body; `style` is an inout param).
        for propName in Array(style.keys) {
            if (style[propName] as? String) == "inherit" {
                style[propName] = visualStyle[propName]
            }
        }
    }

    // itemStyle
    let itemStyleModel = legendItemModel.getModel("itemStyle")
    var itemStyle = itemStyleModel.getItemStyle()
    // const iconBrushType = iconType.lastIndexOf('empty', 0) === 0 ? 'fill' : 'stroke';
    let iconBrushType = iconType.hasPrefix("empty") ? "fill" : "stroke"
    let decalStyle = itemStyleModel.getShallow("decal")
    // itemStyle.decal = (!decalStyle || decalStyle === 'inherit') ? itemVisualStyle.decal
    //   : createOrUpdatePatternFromDecal(decalStyle, api);
    if !legendJsTruthy(decalStyle) || (decalStyle as? String) == "inherit" {
        itemStyle["decal"] = itemVisualStyle["decal"]
    }
    else {
        // PORT-TODO: DEFERRED — `createOrUpdatePatternFromDecal(decalStyle, api)` (util/decal) NOT ported.
        //   Fall back to the series-visual decal so nothing crashes; wire the real pattern when decal lands.
        itemStyle["decal"] = itemVisualStyle["decal"]
    }
    _ = api

    if (itemStyle["fill"] as? String) == "inherit" {
        // Series with visualDrawType as 'stroke' should have series stroke as legend fill
        itemStyle["fill"] = itemVisualStyle[drawType]
    }
    if (itemStyle["stroke"] as? String) == "inherit" {
        // icon type with "emptyXXX" should use fill color in visual style
        itemStyle["stroke"] = itemVisualStyle[iconBrushType]
    }
    if (itemStyle["opacity"] as? String) == "inherit" {
        // Use lineStyle.opacity if drawType is stroke
        itemStyle["opacity"] = (drawType == "fill" ? itemVisualStyle : lineVisualStyle)["opacity"]
    }
    handleCommonProps(&itemStyle, itemVisualStyle)

    // lineStyle
    let legendLineModel = legendItemModel.getModel("lineStyle")
    var lineStyle = legendLineModel.getLineStyle()
    handleCommonProps(&lineStyle, lineVisualStyle)

    // Fix auto color to real color
    if (itemStyle["fill"] as? String) == "auto" { itemStyle["fill"] = itemVisualStyle["fill"] }
    if (itemStyle["stroke"] as? String) == "auto" { itemStyle["stroke"] = itemVisualStyle["fill"] }
    if (lineStyle["stroke"] as? String) == "auto" { lineStyle["stroke"] = itemVisualStyle["fill"] }

    if !isSelected {
        let borderWidth = legendItemModel.get("inactiveBorderWidth")
        // Since stroke is set to be inactiveBorderColor... use border only when series has border if auto
        let visualHasBorder = itemStyle[iconBrushType]
        // itemStyle.lineWidth = borderWidth === 'auto' ? (itemVisualStyle.lineWidth > 0 && visualHasBorder ? 2 : 0) : itemStyle.lineWidth;
        if (borderWidth as? String) == "auto" {
            itemStyle["lineWidth"] =
                (((itemVisualStyle["lineWidth"] as? Double) ?? 0) > 0 && legendJsTruthy(visualHasBorder)) ? 2.0 : 0.0
        }
        // else: keep itemStyle.lineWidth as-is.
        itemStyle["fill"] = legendItemModel.get("inactiveColor")
        itemStyle["stroke"] = legendItemModel.get("inactiveBorderColor")
        lineStyle["stroke"] = legendLineModel.get("inactiveColor")
        lineStyle["lineWidth"] = legendLineModel.get("inactiveWidth")
    }
    return (itemStyle: itemStyle, lineStyle: lineStyle)
}

// function getDefaultLegendIcon(opt: LegendIconParams): ECSymbol
private func getDefaultLegendIcon(_ opt: LegendIconParams) -> ECSymbol {
    // const symboType = opt.icon || 'roundRect';
    let symboType = legendJsTruthy(opt.icon) ? opt.icon : "roundRect"
    let icon = symbol.createSymbol(
        symboType,
        0,
        0,
        opt.itemWidth,
        opt.itemHeight,
        (opt.itemStyle["fill"]).flatMap { legendZRColor($0) },
        opt.symbolKeepAspect
    )

    // icon.setStyle(opt.itemStyle);
    // PORT-TODO: `ECSymbol.setStyle` — the concrete conformer is a `Path` (`SymbolPath`); bridge the
    //   dynamic style bag via `barStyleFromDict` + `useStyle` (same seam as the rest of the port).
    let iconPath = icon as! Path
    iconPath.useStyle(barStyleFromDict(opt.itemStyle))

    // icon.rotation = (opt.iconRotate as number || 0) * Math.PI / 180;
    iconPath.rotation = ((opt.iconRotate as? Double) ?? 0) * Double.pi / 180
    // icon.setOrigin([opt.itemWidth / 2, opt.itemHeight / 2]);
    iconPath.setOrigin([opt.itemWidth / 2, opt.itemHeight / 2])

    if symboType.contains("empty") {
        // icon.style.stroke = icon.style.fill; icon.style.fill = tokens.color.neutral00; icon.style.lineWidth = 2;
        //   upstream `icon.style` -> Swift `iconPath.pathStyle` (PathStyleProps; the inherited
        //   `Displayable.style` is CommonStyleProps — see Path.swift header note).
        iconPath.pathStyle.stroke = iconPath.pathStyle.fill
        iconPath.pathStyle.fill = .string("#fff")   // tokens.color.neutral00
        iconPath.pathStyle.lineWidth = 2
    }

    return icon
}

// PORT-TODO: DEFERRED action helpers — `dispatchSelectAction` / `dispatchHighlightAction` /
//   `dispatchDownplayAction` (`api.dispatchAction({type: 'legendToggleSelect'|'highlight'|'downplay'})`)
//   are click/hover interaction, out of static-render scope. Reproduce with the action layer.

// export default LegendView;  -> `open class LegendView` above.

// ============================================================================
// PORT-TODO helpers — NOT part of legend/LegendView.ts upstream. These reproduce out-of-phase
// sibling APIs / JS idioms so the static legend render compiles. Delete each when its real
// sibling lands and call the sibling directly.
// ============================================================================

/// JS truthiness for the dynamic option bag (`if (x)` / `!x`). (CONVENTIONS §6.)
private func legendJsTruthy(_ v: Any?) -> Bool {
    guard let v = v else { return false }
    if let b = v as? Bool { return b }
    if let d = v as? Double { return d != 0 && !d.isNaN }
    if let i = v as? Int { return i != 0 }
    if let s = v as? String { return !s.isEmpty }
    return true
}

/// upstream `iconRotate === 'inherit'` test on the `number | 'inherit'` option value.
private func legendIsInherit(_ v: Any?) -> Bool {
    return (v as? String) == "inherit"
}

/// `String.prototype.replace(searchString, replaceValue)` — replaces the FIRST occurrence only.
private func legendReplaceOnce(_ s: String, _ target: String, _ replacement: String) -> String {
    guard let r = s.range(of: target) else { return s }
    return s.replacingCharacters(in: r, with: replacement)
}

/// Bridge a dynamic style-bag color value (`String`) to `ZRColor` for `createSymbol`.
private func legendZRColor(_ v: Any) -> ZRenderKit.ZRColor? {
    if let s = v as? String { return .string(s) }
    // PORT-TODO: gradient/pattern color objects not bridged (out of static-render scope).
    return nil
}

/// PORT-TODO: faithful minimal reproduction of `component/helper/listComponent.makeBackground`.
///   Delete when component/helper/listComponent.swift lands and call `makeBackground(rect, model)` directly.
///   upstream:
///     const padding = formatUtil.normalizeCssArray(componentModel.get('padding'));
///     const style = componentModel.getItemStyle(['color', 'opacity']);
///     style.fill = componentModel.get('backgroundColor');
///     const bgRect = new graphic.Rect({ shape: {x,y,width,height,r}, style, silent: true, z2: -1 });
private func makeBackground(_ rect: BoundingRect, _ componentModel: ComponentModel) -> Rect {
    let padding = legendNormalizeCssArray(componentModel.get("padding"))
    var style = componentModel.getItemStyle(["color", "opacity"])
    style["fill"] = componentModel.get("backgroundColor")

    var shape = RectShape()
    shape.x = rect.x - padding[3]
    shape.y = rect.y - padding[0]
    shape.width = rect.width + padding[1] + padding[3]
    shape.height = rect.height + padding[0] + padding[2]
    shape.r = legendBorderRadius(componentModel.get("borderRadius"))

    let bgRect = Rect([
        "shape": shape as PathShape,
        "style": barStyleFromDict(style),
        "silent": true,
        "z2": -1.0
    ])
    return bgRect
}

/// `formatUtil.normalizeCssArray(padding || 0)` on the dynamic `number | number[]` option value.
private func legendNormalizeCssArray(_ v: Any?) -> [Double] {
    if let arr = v as? [Double] {
        return format.normalizeCssArray(arr)
    }
    if let arr = v as? [Any] {
        return format.normalizeCssArray(arr.map { ($0 as? Double) ?? 0 })
    }
    if let d = v as? Double {
        return format.normalizeCssArray(d)
    }
    if let i = v as? Int {
        return format.normalizeCssArray(Double(i))
    }
    return format.normalizeCssArray(0.0)
}

/// upstream `shape.r = componentModel.get('borderRadius')` where borderRadius is `number | number[]`.
private func legendBorderRadius(_ v: Any?) -> RectRadius? {
    if let d = v as? Double { return .number(d) }
    if let i = v as? Int { return .number(Double(i)) }
    if let arr = v as? [Double] { return .array(arr) }
    if let arr = v as? [Any] { return .array(arr.map { ($0 as? Double) ?? 0 }) }
    return nil
}
