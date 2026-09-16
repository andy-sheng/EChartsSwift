// Ported from echarts/src/component/legend/ScrollableLegendView.ts — keep in sync with upstream
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

/**
 * Separate legend and scrollable legend to reduce package size.
 */

import Foundation
import ZRenderKit

// upstream imports (mapped to this port):
//   import * as zrUtil from 'zrender/src/core/util';               -> `util.*` (ZRenderKit) / inlined idioms.
//   import * as graphic from '../../util/graphic';
//     -> `graphic.Group` / `graphic.Text` / `graphic.Rect` = ZRenderKit `Group` / `ZRText` / `Rect`.
//        `graphic.updateProps` = `updateProps` (animation/basicTransition.swift).
//        `graphic.createIcon` is NOT ported (util/graphic note); reproduced minimally as
//        `scrollLegendCreateIcon` below (path:// / makePath branch — the only branch page icons use).
//   import * as layoutUtil from '../../util/layout';               -> `layout.box` (util/layout.swift).
//   import LegendView from './LegendView';                         -> `LegendView` (the base class).
//   import { LegendSelectorButtonOption } from './LegendModel';    -> (type-only; `[Any]?`).
//   import ExtensionAPI from '../../core/ExtensionAPI';            -> `ExtensionAPI`.
//   import GlobalModel from '../../model/Global';                  -> `GlobalModel`.
//   import ScrollableLegendModel, {ScrollableLegendOption} from './ScrollableLegendModel';
//     -> `ScrollableLegendModel` (component/legend/ScrollableLegendModel.swift); the option is the bag.
//   import Displayable from 'zrender/src/graphic/Displayable';     -> `Displayable`.
//   import Element from 'zrender/src/Element';                     -> `Element`.
//   import { ZRRectLike } from '../../util/types';                 -> `BoundingRect` / `RectShape`.
//
// const Group = graphic.Group;
// const WH = ['width', 'height'] as const;   -> modeled by `orientIdx`-keyed accessor closures.
// const XY = ['x', 'y'] as const;

// interface PageInfo { contentPosition, pageCount, pageIndex, pagePrevDataIndex, pageNextDataIndex }
private struct ScrollPageInfo {
    var contentPosition: [Double]
    var pageCount: Int
    // pageIndex: number, null when data item not found. Never null on the non-empty path taken here.
    var pageIndex: Int
    var pagePrevDataIndex: Double?
    var pageNextDataIndex: Double?
}

// interface ItemInfo { s: number /* start */; e: number /* end */; i: number /* index */ }
private struct ScrollItemInfo {
    let s: Double
    let e: Double
    let i: Double
}

// type LegendGroup = graphic.Group & { __rectSize: number };
//   -> the single `_containerGroup` per view; `__rectSize` lives on the view as `_containerRectSize`.
// type LegendItemElement = Element & { __legendDataIndex: number };
//   -> `__legendDataIndex` lives in an inner-store side table (Element is not dynamically extensible);
//      set by `LegendView._createItem` (via `legendItemDataIndexInner`) and read here.

// class ScrollableLegendView extends LegendView
open class ScrollableLegendView: LegendView {

    // static type = 'legend.scroll';
    public static let scrollType = "legend.scroll"
    open override var type: String { return ScrollableLegendView.scrollType }

    // newlineDisabled = true;   (scroll legend never inserts a newline spacer)
    //   NOTE: `newlineDisabled` is a stored `var` on the base; set it in `init`.

    // private _containerGroup: LegendGroup;
    private var _containerGroup: Group!
    // private _controllerGroup: graphic.Group;
    private var _controllerGroup: Group!

    // private _currentIndex: number = 0;  (only read by the DEFERRED page-scroll interaction)
    private var _currentIndex: Double = 0

    // private _showController: boolean;
    private var _showController: Bool = false

    // __rectSize on the container group (see type note above).
    private var _containerRectSize: Double? = nil

    // init()
    open override func `init`(_ ecModel: GlobalModel, _ api: ExtensionAPI) {
        // super.init();
        super.`init`(ecModel, api)

        self.newlineDisabled = true

        // this.group.add(this._containerGroup = new Group());
        self._containerGroup = Group()
        _ = self.group.add(self._containerGroup)
        // this._containerGroup.add(this.getContentGroup());  (reparents contentGroup out of this.group)
        _ = self._containerGroup.add(self.getContentGroup())

        // this.group.add(this._controllerGroup = new Group());
        self._controllerGroup = Group()
        _ = self.group.add(self._controllerGroup)
    }

    // @override resetInner()
    open override func resetInner() {
        // super.resetInner();
        super.resetInner()

        // this._controllerGroup.removeAll();
        _ = self._controllerGroup.removeAll()
        // this._containerGroup.removeClipPath();
        self._containerGroup.removeClipPath()
        // this._containerGroup.__rectSize = null;
        self._containerRectSize = nil
    }

    // @override renderInner(itemAlign, legendModel, ecModel, api, selector, orient, selectorPosition)
    open override func renderInner(
        _ itemAlign: String?,
        _ legendModel: LegendModel,
        _ ecModel: GlobalModel,
        _ api: ExtensionAPI,
        _ selector: [Any]?,
        _ orient: String?,
        _ selectorPosition: String?
    ) {
        // Render content items.
        // super.renderInner(itemAlign, legendModel, ecModel, api, selector, orient, selectorPosition);
        super.renderInner(itemAlign, legendModel, ecModel, api, selector, orient, selectorPosition)

        let controllerGroup = self._controllerGroup!

        // FIXME: support 'auto' adapt to size number text length.
        // const pageIconSize = legendModel.get('pageIconSize', true);
        // const pageIconSizeArr = isArray(pageIconSize) ? pageIconSize : [pageIconSize, pageIconSize];
        let pageIconSizeArr = scrollLegendPageIconSizeArr(legendModel.get("pageIconSize", true))

        // createPageButton('pagePrev', 0);
        self.createPageButton(controllerGroup, legendModel, api, "pagePrev", 0, pageIconSizeArr)

        // const pageTextStyleModel = legendModel.getModel('pageTextStyle');
        let pageTextStyleModel = legendModel.getModel("pageTextStyle")
        // controllerGroup.add(new graphic.Text({ name: 'pageText', style: {...}, silent: true }));
        var pageTextStyle = TextStyleProps()
        // Placeholder to calculate a proper layout.
        pageTextStyle.text = "xx/xx"
        pageTextStyle.fill = pageTextStyleModel.getTextColor()
        pageTextStyle.font = pageTextStyleModel.getFont()
        pageTextStyle.verticalAlign = .middle
        pageTextStyle.align = .center
        let pageText = ZRText(["style": pageTextStyle, "name": "pageText", "silent": true])
        _ = controllerGroup.add(pageText)

        // createPageButton('pageNext', 1);
        self.createPageButton(controllerGroup, legendModel, api, "pageNext", 1, pageIconSizeArr)
    }

    // function createPageButton(name, iconIdx)
    private func createPageButton(
        _ controllerGroup: Group,
        _ legendModel: LegendModel,
        _ api: ExtensionAPI,
        _ name: String,
        _ iconIdx: Int,
        _ pageIconSizeArr: [Double]
    ) {
        // const pageDataIndexName = (name + 'DataIndex');
        let pageDataIndexName = name + "DataIndex"
        // const icon = graphic.createIcon(
        //   legendModel.get('pageIcons', true)[legendModel.getOrient().name][iconIdx],
        //   { onclick: bind(self._pageGo, ...) },
        //   { x: -w/2, y: -h/2, width, height });
        let icons = (legendModel.get("pageIcons", true) as? [String: Any]) ?? [:]
        let orientName = legendModel.getOrient().name
        let iconArr = (icons[orientName] as? [Any]) ?? []
        let iconStr = (iconArr.count > iconIdx ? (iconArr[iconIdx] as? String) : nil) ?? ""

        let icon = scrollLegendCreateIcon(
            iconStr,
            BoundingRect(-pageIconSizeArr[0] / 2, -pageIconSizeArr[1] / 2, pageIconSizeArr[0], pageIconSizeArr[1])
        )
        // icon.name = name;
        icon.name = name
        // onclick: zrUtil.bind(self._pageGo, self, pageDataIndexName, legendModel, api)
        //   The scroll view always renders a ScrollableLegendModel; cast to satisfy `_pageGo`.
        let scrollModel = legendModel as? ScrollableLegendModel
        _ = icon.on("click", { [weak self] _, _ in
            if let scrollModel = scrollModel {
                self?._pageGo(pageDataIndexName, scrollModel, api)
            }
            return nil
        }, nil)
        _ = controllerGroup.add(icon)
    }

    // @override layoutInner(legendModel, itemAlign, maxSize, isFirstRender, selector, selectorPosition)
    open override func layoutInner(
        _ legendModel: LegendModel,
        _ itemAlign: String?,
        _ maxSize: BoundingRect,
        _ isFirstRender: Bool,
        _ selector: [Any]?,
        _ selectorPosition: String?
    ) -> BoundingRect {
        let selectorGroup = self.getSelectorGroup()

        let orientIdx = Int(legendModel.getOrient().index)
        // wh/hw index-keyed accessors (WH = ['width','height'], orientIdx 0 == horizontal).
        func whv(_ r: BoundingRect) -> Double { orientIdx == 0 ? r.width : r.height }
        func hwv(_ r: BoundingRect) -> Double { orientIdx == 0 ? r.height : r.width }
        // yx = XY[1 - orientIdx] (cross axis coordinate name).
        func yxv(_ r: BoundingRect) -> Double { orientIdx == 0 ? r.y : r.x }

        // selector && layoutUtil.box('horizontal', selectorGroup, legendModel.get('selectorItemGap', true));
        if selector != nil {
            layout.box(
                "horizontal",
                selectorGroup,
                scrollLegendAsDouble(legendModel.get("selectorItemGap", true)) ?? 0
            )
        }

        let selectorButtonGap = scrollLegendAsDouble(legendModel.get("selectorButtonGap", true)) ?? 0
        let selectorRect = selectorGroup.getBoundingRect() ?? BoundingRect(0, 0, 0, 0)
        var selectorPos: [Double] = [-selectorRect.x, -selectorRect.y]

        // const processMaxSize = clone(maxSize);
        let processMaxSize = BoundingRect(maxSize.x, maxSize.y, maxSize.width, maxSize.height)
        // selector && (processMaxSize[wh] = maxSize[wh] - selectorRect[wh] - selectorButtonGap);
        if selector != nil {
            if orientIdx == 0 {
                processMaxSize.width = whv(maxSize) - whv(selectorRect) - selectorButtonGap
            }
            else {
                processMaxSize.height = whv(maxSize) - whv(selectorRect) - selectorButtonGap
            }
        }

        // const mainRect = this._layoutContentAndController(...);
        let mainRect = self._layoutContentAndController(
            legendModel, isFirstRender, processMaxSize, orientIdx
        )

        if selector != nil {
            // helpers to read/write mainRect by orient-index name.
            func mainWH() -> Double { orientIdx == 0 ? mainRect.width : mainRect.height }
            func setMainWH(_ v: Double) { if orientIdx == 0 { mainRect.width = v } else { mainRect.height = v } }
            func mainXY() -> Double { orientIdx == 0 ? mainRect.x : mainRect.y }
            func setMainXY(_ v: Double) { if orientIdx == 0 { mainRect.x = v } else { mainRect.y = v } }
            func setMainHW(_ v: Double) { if orientIdx == 0 { mainRect.height = v } else { mainRect.width = v } }
            func mainHW() -> Double { orientIdx == 0 ? mainRect.height : mainRect.width }
            func mainYX() -> Double { orientIdx == 0 ? mainRect.y : mainRect.x }
            func setMainYX(_ v: Double) { if orientIdx == 0 { mainRect.y = v } else { mainRect.x = v } }

            if selectorPosition == "end" {
                selectorPos[orientIdx] += mainWH() + selectorButtonGap
            }
            else {
                let offset = whv(selectorRect) + selectorButtonGap
                selectorPos[orientIdx] -= offset
                setMainXY(mainXY() - offset)
            }
            // mainRect[wh] += selectorRect[wh] + selectorButtonGap;
            setMainWH(mainWH() + whv(selectorRect) + selectorButtonGap)

            // selectorPos[1 - orientIdx] += mainRect[yx] + mainRect[hw] / 2 - selectorRect[hw] / 2;
            selectorPos[1 - orientIdx] += mainYX() + mainHW() / 2 - hwv(selectorRect) / 2
            // mainRect[hw] = Math.max(mainRect[hw], selectorRect[hw]);
            setMainHW(Swift.max(mainHW(), hwv(selectorRect)))
            // mainRect[yx] = Math.min(mainRect[yx], selectorRect[yx] + selectorPos[1 - orientIdx]);
            setMainYX(Swift.min(mainYX(), yxv(selectorRect) + selectorPos[1 - orientIdx]))

            selectorGroup.x = selectorPos[0]
            selectorGroup.y = selectorPos[1]
            selectorGroup.markRedraw()
        }

        return mainRect
    }

    // _layoutContentAndController(legendModel, isFirstRender, maxSize, orientIdx, wh, hw, yx, xy)
    //   (wh/hw/yx/xy are recovered from `orientIdx` via the accessor closures below.)
    private func _layoutContentAndController(
        _ legendModel: LegendModel,
        _ isFirstRender: Bool,
        _ maxSize: BoundingRect,
        _ orientIdx: Int
    ) -> BoundingRect {
        let contentGroup = self.getContentGroup()
        let containerGroup = self._containerGroup!
        let controllerGroup = self._controllerGroup!

        func whv(_ r: BoundingRect) -> Double { orientIdx == 0 ? r.width : r.height }
        func hwv(_ r: BoundingRect) -> Double { orientIdx == 0 ? r.height : r.width }
        func yxv(_ r: BoundingRect) -> Double { orientIdx == 0 ? r.y : r.x }  // XY[1-orientIdx]

        // Place items in contentGroup.
        // layoutUtil.box(orient, contentGroup, itemGap, !orientIdx ? null : maxSize.width,
        //   orientIdx ? null : maxSize.height);
        layout.box(
            (legendModel.get("orient") as? String) ?? "horizontal",
            contentGroup,
            scrollLegendAsDouble(legendModel.get("itemGap")) ?? 0,
            orientIdx == 0 ? nil : maxSize.width,
            orientIdx == 0 ? maxSize.height : nil
        )

        // Buttons in controller are laid out always horizontally.
        // layoutUtil.box('horizontal', controllerGroup, legendModel.get('pageButtonItemGap', true));
        layout.box(
            "horizontal",
            controllerGroup,
            scrollLegendAsDouble(legendModel.get("pageButtonItemGap", true)) ?? 0
        )

        let contentRect = contentGroup.getBoundingRect() ?? BoundingRect(0, 0, 0, 0)
        let controllerRect = controllerGroup.getBoundingRect() ?? BoundingRect(0, 0, 0, 0)
        // const showController = this._showController = contentRect[wh] > maxSize[wh];
        let showController = whv(contentRect) > whv(maxSize)
        self._showController = showController

        // In case that inner elements of contentGroup layout do not start at [0, 0].
        var contentPos: [Double] = [-contentRect.x, -contentRect.y]
        // Remain contentPos when scroll animation performing.
        if !isFirstRender {
            contentPos[orientIdx] = orientIdx == 0 ? contentGroup.x : contentGroup.y
        }

        // Layout container group based on 0.
        var containerPos: [Double] = [0, 0]
        var controllerPos: [Double] = [-controllerRect.x, -controllerRect.y]
        // const pageButtonGap = retrieve2(get('pageButtonGap', true), get('itemGap', true));
        let pageButtonGap = scrollLegendAsDouble(legendModel.get("pageButtonGap", true))
            ?? scrollLegendAsDouble(legendModel.get("itemGap", true)) ?? 0

        // Place containerGroup, controllerGroup and contentGroup.
        if showController {
            let pageButtonPosition = legendModel.get("pageButtonPosition", true) as? String
            // controller is on the right / bottom.
            if pageButtonPosition == "end" {
                controllerPos[orientIdx] += whv(maxSize) - whv(controllerRect)
            }
            // controller is on the left / top.
            else {
                containerPos[orientIdx] += whv(controllerRect) + pageButtonGap
            }
        }

        // Always align controller to content as 'middle'.
        // controllerPos[1 - orientIdx] += contentRect[hw] / 2 - controllerRect[hw] / 2;
        controllerPos[1 - orientIdx] += hwv(contentRect) / 2 - hwv(controllerRect) / 2

        contentGroup.setPosition(contentPos)
        containerGroup.setPosition(containerPos)
        controllerGroup.setPosition(controllerPos)

        // Calculate `mainRect` and set `clipPath`.
        let mainRect = BoundingRect(0, 0, 0, 0)

        // mainRect[wh] = showController ? maxSize[wh] : contentRect[wh];
        let mainWH = showController ? whv(maxSize) : whv(contentRect)
        // mainRect[hw] = Math.max(contentRect[hw], controllerRect[hw]);
        let mainHW = Swift.max(hwv(contentRect), hwv(controllerRect))
        // mainRect[yx] = Math.min(0, controllerRect[yx] + controllerPos[1 - orientIdx]);
        let mainYX = Swift.min(0, yxv(controllerRect) + controllerPos[1 - orientIdx])
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

        // containerGroup.__rectSize = maxSize[wh];
        self._containerRectSize = whv(maxSize)
        if showController {
            // const clipShape = {x: 0, y: 0}; clipShape[wh] = max(maxSize[wh]-controllerRect[wh]-gap, 0);
            //   clipShape[hw] = mainRect[hw];
            var clipShape = RectShape()
            clipShape.x = 0
            clipShape.y = 0
            let clipWH = Swift.max(whv(maxSize) - whv(controllerRect) - pageButtonGap, 0)
            if orientIdx == 0 {
                clipShape.width = clipWH
                clipShape.height = mainHW
            }
            else {
                clipShape.height = clipWH
                clipShape.width = mainHW
            }
            // containerGroup.setClipPath(new graphic.Rect({shape: clipShape}));
            containerGroup.setClipPath(Rect(["shape": clipShape as PathShape]))
            // containerGroup.__rectSize = clipShape[wh];
            self._containerRectSize = clipWH
        }
        else {
            // Keep the controller elements as invisible/silent placeholders.
            _ = controllerGroup.eachChild { child, _ in
                if let d = child as? Displayable {
                    d.invisible = true
                }
                child.silent = true
            }
        }

        // Content translate animation.
        let pageInfo = self._getPageInfo(legendModel)
        // pageInfo.pageIndex != null && graphic.updateProps(contentGroup,
        //   {x: contentPosition[0], y: contentPosition[1]}, showController ? legendModel : null);
        updateProps(
            contentGroup,
            ["x": pageInfo.contentPosition[0], "y": pageInfo.contentPosition[1]],
            showController ? legendModel : nil
        )

        self._updatePageInfoView(legendModel, pageInfo)

        return mainRect
    }

    // _pageGo(to, legendModel, api)
    //   Reached from the page-arrow onclick wired in `createPageButton`; dispatches `legendScroll`.
    func _pageGo(_ to: String, _ legendModel: ScrollableLegendModel, _ api: ExtensionAPI) {
        let info = self._getPageInfo(legendModel)
        let scrollDataIndex: Double? = to == "pagePrevDataIndex" ? info.pagePrevDataIndex : info.pageNextDataIndex
        if let scrollDataIndex = scrollDataIndex {
            var payload = Payload(type: "legendScroll")
            payload.other["scrollDataIndex"] = scrollDataIndex
            payload.other["legendId"] = legendModel.id
            api.dispatchAction(payload)
        }
    }

    // _updatePageInfoView(legendModel, pageInfo)
    private func _updatePageInfoView(_ legendModel: LegendModel, _ pageInfo: ScrollPageInfo) {
        let controllerGroup = self._controllerGroup!

        // each(['pagePrev', 'pageNext'], ...)
        for name in ["pagePrev", "pageNext"] {
            let canJump = (name == "pagePrev" ? pageInfo.pagePrevDataIndex : pageInfo.pageNextDataIndex) != nil
            if let icon = controllerGroup.childOfName(name) as? Path {
                // icon.setStyle('fill', canJump ? pageIconColor : pageIconInactiveColor);
                let colorKey = canJump ? "pageIconColor" : "pageIconInactiveColor"
                icon.pathStyle.fill = scrollLegendZRColor(legendModel.get(colorKey, true))
                icon.dirtyStyle()
                // icon.cursor = canJump ? 'pointer' : 'default';
                icon.cursor = canJump ? "pointer" : "default"
            }
        }

        // const pageText = controllerGroup.childOfName('pageText');
        // const pageFormatter = legendModel.get('pageFormatter');
        let pageFormatter = legendModel.get("pageFormatter")
        // const current = pageIndex != null ? pageIndex + 1 : 0;
        let current = pageInfo.pageIndex + 1
        let total = pageInfo.pageCount

        // pageText && pageFormatter && pageText.setStyle('text',
        //   isString(pageFormatter) ? pageFormatter.replace('{current}', ...).replace('{total}', ...)
        //     : pageFormatter({current, total}));
        if let pageText = controllerGroup.childOfName("pageText") as? ZRText {
            var text: String? = nil
            // `pageFormatter &&` — an empty string is falsy upstream, so skip it.
            if let fmt = pageFormatter as? String, !fmt.isEmpty {
                text = fmt
                    .replacingOccurrences(of: "{current}", with: String(current))
                    .replacingOccurrences(of: "{total}", with: String(total))
            }
            // function-valued `pageFormatter({current, total})` (dynamic callback).
            else if let fn = pageFormatter as? ([String: Any]) -> String {
                text = fn(["current": current, "total": total])
            }
            if let text = text {
                var s = pageText.textStyle ?? TextStyleProps()
                s.text = text
                pageText.textStyle = s
                pageText.dirtyStyle()
            }
        }
    }

    /**
     *  contentPosition, pageIndex, pageCount, pagePrevDataIndex, pageNextDataIndex
     */
    // _getPageInfo(legendModel): PageInfo
    private func _getPageInfo(_ legendModel: LegendModel) -> ScrollPageInfo {
        // const scrollDataIndex = legendModel.get('scrollDataIndex', true);
        let scrollDataIndex = scrollLegendAsDouble(legendModel.get("scrollDataIndex", true)) ?? 0
        let contentGroup = self.getContentGroup()
        let containerRectSize = self._containerRectSize ?? 0
        let orientIdx = Int(legendModel.getOrient().index)

        // getItemInfo(el): { s, e, i } — start/end along the main axis + __legendDataIndex.
        func getItemInfo(_ el: Element?) -> ScrollItemInfo? {
            guard let el = el else { return nil }
            let itemRect = el.getBoundingRect() ?? BoundingRect(0, 0, 0, 0)
            // start = itemRect[xy] + el[xy]  (xy = XY[orientIdx]).
            let elXY = orientIdx == 0 ? el.x : el.y
            let start = (orientIdx == 0 ? itemRect.x : itemRect.y) + elXY
            let wh = orientIdx == 0 ? itemRect.width : itemRect.height
            return ScrollItemInfo(s: start, e: start + wh, i: legendItemDataIndex(el) ?? 0)
        }

        // intersect(itemInfo, winStart): itemInfo.e >= winStart && itemInfo.s <= winStart + rectSize
        func intersect(_ itemInfo: ScrollItemInfo, _ winStart: Double) -> Bool {
            return itemInfo.e >= winStart && itemInfo.s <= winStart + containerRectSize
        }

        let targetItemIndex = self._findTargetItemIndex(scrollDataIndex)
        let children = contentGroup.children()
        func childAt(_ idx: Int) -> Element? {
            return (idx >= 0 && idx < children.count) ? children[idx] : nil
        }
        let targetItem = childAt(targetItemIndex)
        let itemCount = children.count
        let pCount = itemCount == 0 ? 0 : 1

        var result = ScrollPageInfo(
            contentPosition: [contentGroup.x, contentGroup.y],
            pageCount: pCount,
            pageIndex: pCount - 1,
            pagePrevDataIndex: nil,
            pageNextDataIndex: nil
        )

        guard let targetItemInfo = getItemInfo(targetItem) else {
            return result
        }

        // result.contentPosition[orientIdx] = -targetItemInfo.s;
        result.contentPosition[orientIdx] = -targetItemInfo.s

        // Forward scan: find the next-page start item.
        do {
            var winStart: ScrollItemInfo? = targetItemInfo
            var winEnd: ScrollItemInfo? = targetItemInfo
            var i = targetItemIndex + 1
            while i <= itemCount {
                let curr = getItemInfo(childAt(i))
                let cond1 = (curr == nil) && (winEnd!.e > winStart!.s + containerRectSize)
                let cond2 = (curr != nil) && !intersect(curr!, winStart!.s)
                if cond1 || cond2 {
                    if winEnd!.i > winStart!.i {
                        winStart = winEnd
                    }
                    else {   // e.g. when page size is smaller than item size.
                        winStart = curr
                    }
                    if let ws = winStart {
                        if result.pageNextDataIndex == nil {
                            result.pageNextDataIndex = ws.i
                        }
                        result.pageCount += 1
                    }
                }
                winEnd = curr
                i += 1
            }
        }

        // Backward scan: find the previous-page start item + total page index.
        do {
            var winStart: ScrollItemInfo? = targetItemInfo
            var winEnd: ScrollItemInfo? = targetItemInfo
            var i = targetItemIndex - 1
            while i >= -1 {
                let curr = getItemInfo(childAt(i))
                let cond = ((curr == nil) || !intersect(winEnd!, curr!.s)) && (winStart!.i < winEnd!.i)
                if cond {
                    winEnd = winStart
                    if result.pagePrevDataIndex == nil {
                        result.pagePrevDataIndex = winStart!.i
                    }
                    result.pageCount += 1
                    result.pageIndex += 1
                }
                winStart = curr
                i -= 1
            }
        }

        return result
    }

    // _findTargetItemIndex(targetDataIndex)
    private func _findTargetItemIndex(_ targetDataIndex: Double) -> Int {
        if !self._showController {
            return 0
        }

        var index: Int? = nil
        let contentGroup = self.getContentGroup()
        var defaultIndex: Int? = nil

        _ = contentGroup.eachChild { child, idx in
            let legendDataIdx = legendItemDataIndex(child)
            if defaultIndex == nil && legendDataIdx != nil {
                defaultIndex = idx
            }
            if legendDataIdx == targetDataIndex {
                index = idx
            }
        }

        return index ?? (defaultIndex ?? 0)
    }
}

// ============================================================================
// __legendDataIndex side table — upstream augments the item Element with `__legendDataIndex`.
//   Element is not dynamically extensible in Swift, so the value lives in an inner-store table keyed
//   by element identity. `LegendView._createItem` writes it via `legendItemDataIndexInner`; the
//   scrollable view reads it via `legendItemDataIndex`.
// ============================================================================
final class LegendDataIndexBox { var value: Double? = nil }
let legendItemDataIndexInner: (Element) -> LegendDataIndexBox = model.makeInner { LegendDataIndexBox() }
func legendItemDataIndex(_ el: Element) -> Double? {
    return legendItemDataIndexInner(el).value
}

// ============================================================================
// note helpers — reproduce out-of-phase sibling APIs / JS idioms so the scroll legend compiles.
// ============================================================================

// Faithful minimal reproduction of `graphic.createIcon` (util/graphic.ts) — path:// / SVG-path branch
//   only (the branch the built-in page icons use). The 'image://' branch (ZRImage) is out of scope.
//   upstream: makePath(iconStr.replace('path://', ''), {rectHover: true, style: {strokeNoScale: true}},
//     rect, 'center'); onclick wiring is DEFERRED (interaction).
private func scrollLegendCreateIcon(_ iconStr: String, _ rect: BoundingRect) -> SVGPath {
    let pathData = iconStr.hasPrefix("path://") ? String(iconStr.dropFirst("path://".count)) : iconStr
    let path = ZRenderKit.makePath(pathData, nil, rect, "center")
    // style: { strokeNoScale: true }
    path.pathStyle.strokeNoScale = true
    path.dirtyStyle()
    return path
}

// `pageIconSize` is `number | [number, number]`. Returns [width, height] (Int-vs-Double coerced).
private func scrollLegendPageIconSizeArr(_ v: Any?) -> [Double] {
    if let arr = v as? [Any] {
        let w = scrollLegendAsDouble(arr.count > 0 ? arr[0] : nil) ?? 0
        let h = scrollLegendAsDouble(arr.count > 1 ? arr[1] : nil) ?? 0
        return [w, h]
    }
    let d = scrollLegendAsDouble(v) ?? 0
    return [d, d]
}

/// Coerce an option-bag number that may be boxed as `Int` OR `Double` (the recurring Int-vs-Double
/// trap: `as? Double` returns nil on an Int literal).
private func scrollLegendAsDouble(_ v: Any?) -> Double? {
    if let d = v as? Double { return d }
    if let i = v as? Int { return Double(i) }
    return nil
}

/// Bridge a dynamic style-bag color value to `ZRColor` for a page-icon fill. Delegates to the shared
///   gradient/pattern-aware paint bridge so `pageIconColor`/`pageIconInactiveColor` may be a solid
///   string, a linear/radial gradient object, or an image pattern (not only string hex colors).
private func scrollLegendZRColor(_ v: Any?) -> ZRenderKit.ZRColor? {
    return zrPaintFromStyleValue(v)
}

// export default ScrollableLegendView; -> `open class ScrollableLegendView` above.
