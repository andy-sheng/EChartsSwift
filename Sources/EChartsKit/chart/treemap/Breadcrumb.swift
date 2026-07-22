// Ported from echarts/src/chart/treemap/Breadcrumb.ts — keep in sync with upstream
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
//   import * as graphic from '../../util/graphic';                  -> ZRenderKit `Group` / `Polygon` / `ZRText` (used directly).
//   import {getECData} from '../../util/innerStore';                -> `innerStore.getECData`.
//   import * as layout from '../../util/layout';                    -> `layout.*` (util/layout.swift).
//   import {wrapTreePathInfo} from '../helper/treeHelper';          -> treeHelper.wrapTreePathInfo
//       (chart/helper/treeHelper.swift, fully ported); consumed by `packEventData` below.
//   import TreemapSeriesModel, { TreemapSeriesNodeItemOption, TreemapSeriesOption } from './TreemapSeries';
//       -> sibling TreemapSeries.swift.
//   import ExtensionAPI from '../../core/ExtensionAPI';             -> `ExtensionAPI`.
//   import { TreeNode } from '../../data/Tree';                     -> `TreeNode` (data/Tree.swift).
//   import { curry, defaults } from 'zrender/src/core/util';        -> `util.defaults` (curry: only for the deferred onclick).
//   import { ZRElementEvent, ECElement } from '../../util/types';   -> type-only.
//   import Element from 'zrender/src/Element';                      -> `Element`.
//   import Model from '../../model/Model';                          -> `Model`.
//   import { convertOptionIdName } from '../../util/model';         -> `model.convertOptionIdName`.
//   import { toggleHoverEmphasis, Z2_EMPHASIS_LIFT } from '../../util/states';
//       -> `states.toggleHoverEmphasis` / `states.Z2_EMPHASIS_LIFT` (util/states.swift). APPLIED below.
//          A local `Z2_EMPHASIS_LIFT` (== 10) mirror is kept for the z2 computation.
//   import { createTextStyle } from '../../label/labelStyle';
//       -> `labelStyle.createTextStyle` (label/labelStyle.swift), wired directly at the draw site.

// const TEXT_PADDING = 8;
private let TEXT_PADDING: Double = 8
// const ITEM_GAP = 8;
private let ITEM_GAP: Double = 8
// const ARRAY_LENGTH = 5;
private let ARRAY_LENGTH: Double = 5

// Local mirror of `states.Z2_EMPHASIS_LIFT` (== 10, util/states.swift) for the z2 computation below.
private let Z2_EMPHASIS_LIFT: Double = 10

// interface OnSelectCallback { (node: TreeNode, e: ZRElementEvent): void }
// PORT-NOTE: the `e: ZRElementEvent` arg is dropped — no consumer reads it (upstream's TreemapView
//   breadcrumb `onSelect` uses only `node`); the TreemapView call site passes a single-arg closure.
public typealias OnSelectCallback = (TreeNode) -> Void

// interface LayoutParam { emptyItemWidth; totalWidth; renderList: {node, text, width}[] }
private struct BreadcrumbRenderItem {
    var node: TreeNode
    var text: String?
    var width: Double
}
private final class LayoutParam {
    var emptyItemWidth: Double
    var totalWidth: Double
    var renderList: [BreadcrumbRenderItem]
    init(emptyItemWidth: Double, totalWidth: Double, renderList: [BreadcrumbRenderItem]) {
        self.emptyItemWidth = emptyItemWidth
        self.totalWidth = totalWidth
        self.renderList = renderList
    }
}

// type BreadcrumbItemStyleModel / BreadcrumbEmphasisItemStyleModel / BreadcrumbTextStyleModel -> `Model`.

// upstream: class Breadcrumb
open class Breadcrumb {

    // group = new graphic.Group();
    public let group = Group()

    // constructor(containerGroup: graphic.Group) { containerGroup.add(this.group); }
    public init(_ containerGroup: Group) {
        _ = containerGroup.add(self.group)
    }

    public func render(
        _ seriesModel: TreemapSeriesModel,
        _ api: ExtensionAPI,
        _ targetNode: TreeNode?,
        _ onSelect: @escaping OnSelectCallback
    ) {
        // const model = seriesModel.getModel('breadcrumb');
        let model = seriesModel.getModel("breadcrumb")
        // const thisGroup = this.group;
        let thisGroup = self.group

        // thisGroup.removeAll();
        _ = thisGroup.removeAll()

        // if (!model.get('show') || !targetNode) { return; }
        guard ((model.get("show") as? Bool) ?? false), let targetNode = targetNode else {
            return
        }

        // const normalStyleModel = model.getModel('itemStyle');
        let normalStyleModel = model.getModel("itemStyle")
        // const emphasisModel = model.getModel('emphasis');
        let emphasisModel = model.getModel("emphasis")
        // const textStyleModel = normalStyleModel.getModel('textStyle');
        let textStyleModel = normalStyleModel.getModel("textStyle")
        // const emphasisTextStyleModel = emphasisModel.getModel(['itemStyle', 'textStyle']);
        let emphasisTextStyleModel = emphasisModel.getModel(["itemStyle", "textStyle"])

        // const refContainer = layout.createBoxLayoutReference(seriesModel, api).refContainer;
        let refContainer = layout.createBoxLayoutReference(seriesModel, api).refContainer
        // const boxLayoutParams = { left, right, top, bottom };
        let boxLayoutParams: [String: Any] = [
            "left": model.get("left") as Any,
            "right": model.get("right") as Any,
            "top": model.get("top") as Any,
            "bottom": model.get("bottom") as Any
        ]
        // const layoutParam = { emptyItemWidth: model.get('emptyItemWidth'), totalWidth: 0, renderList: [] };
        let layoutParam = LayoutParam(
            emptyItemWidth: (model.get("emptyItemWidth") as? Double) ?? 0,
            totalWidth: 0,
            renderList: []
        )
        // const availableSize = layout.getLayoutRect(boxLayoutParams, refContainer);
        let availableSize = layout.getLayoutRect(boxLayoutParams as Any?, refContainer)
        self._prepare(targetNode, layoutParam, textStyleModel)
        self._renderContent(
            seriesModel, layoutParam, availableSize, normalStyleModel,
            emphasisModel, textStyleModel, emphasisTextStyleModel, onSelect
        )

        // layout.positionElement(thisGroup, boxLayoutParams, refContainer);
        //   Value-returning port (CONVENTIONS §3): apply the computed x/y back to the group.
        let posResult = layout.positionElement(thisGroup, boxLayoutParams, refContainer, nil, nil)
        thisGroup.x = posResult.out["x"] ?? 0
        thisGroup.y = posResult.out["y"] ?? 0
    }

    /**
     * Prepare render list and total width
     * @private
     */
    fileprivate func _prepare(_ targetNode: TreeNode, _ layoutParam: LayoutParam, _ textStyleModel: Model) {
        // for (let node = targetNode; node; node = node.parentNode) { ... }
        var node: TreeNode? = targetNode
        while let n = node {
            // const text = convertOptionIdName(node.getModel().get('name'), '');
            let text = model.convertOptionIdName(n.getModel()?.get("name"), "")
            // const textRect = textStyleModel.getTextRect(text);
            let textRect = textStyleModel.getTextRect(text ?? "")
            // const itemWidth = Math.max(textRect.width + TEXT_PADDING * 2, layoutParam.emptyItemWidth);
            let itemWidth = Swift.max(
                textRect.width + TEXT_PADDING * 2,
                layoutParam.emptyItemWidth
            )
            // layoutParam.totalWidth += itemWidth + ITEM_GAP;
            layoutParam.totalWidth += itemWidth + ITEM_GAP
            // layoutParam.renderList.push({ node, text, width: itemWidth });
            layoutParam.renderList.append(BreadcrumbRenderItem(node: n, text: text, width: itemWidth))

            node = n.parentNode
        }
    }

    /**
     * @private
     */
    fileprivate func _renderContent(
        _ seriesModel: TreemapSeriesModel,
        _ layoutParam: LayoutParam,
        _ availableSize: LayoutRect,
        _ normalStyleModel: Model,
        _ emphasisModel: Model,
        _ textStyleModel: Model,
        _ emphasisTextStyleModel: Model,
        _ onSelect: @escaping OnSelectCallback
    ) {
        // Start rendering.
        // let lastX = 0;
        var lastX: Double = 0
        // const emptyItemWidth = layoutParam.emptyItemWidth;
        let emptyItemWidth = layoutParam.emptyItemWidth
        // const height = seriesModel.get(['breadcrumb', 'height']);
        let height = (seriesModel.get(["breadcrumb", "height"]) as? Double) ?? 0
        // let totalWidth = layoutParam.totalWidth;
        var totalWidth = layoutParam.totalWidth
        // const renderList = layoutParam.renderList;
        let renderList = layoutParam.renderList
        // const emphasisItemStyle = emphasisModel.getModel('itemStyle').getItemStyle();
        let emphasisItemStyle = emphasisModel.getModel("itemStyle").getItemStyle()

        // for (let i = renderList.length - 1; i >= 0; i--) { ... }
        var i = renderList.count - 1
        while i >= 0 {
            // const item = renderList[i]; const itemNode = item.node; let itemWidth = item.width; let text = item.text;
            let item = renderList[i]
            let itemNode = item.node
            var itemWidth = item.width
            var text = item.text

            // Hdie text and shorten width if necessary.
            if totalWidth > availableSize.width {
                totalWidth -= itemWidth - emptyItemWidth
                itemWidth = emptyItemWidth
                text = nil
            }

            // const el = new graphic.Polygon({ shape: {points: makeItemPoints(...)}, style: defaults(...), ... });
            let el = Polygon()
            var polygonShape = PolygonShape()
            polygonShape.points = makeItemPoints(
                lastX, 0, itemWidth, height,
                i == renderList.count - 1, i == 0
            )
            _ = el.setShape(polygonShape)

            // style: defaults(normalStyleModel.getItemStyle(), { lineJoin: 'bevel' })
            var styleDict = normalStyleModel.getItemStyle()
            if styleDict["lineJoin"] == nil {
                styleDict["lineJoin"] = "bevel"
            }
            el.useStyle(barStyleFromDict(styleDict))

            // textContent: new graphic.Text({ style: createTextStyle(textStyleModel, { text }) })
            let textEl = ZRText()
            var textSpecified = TextStyleProps()
            textSpecified.text = text
            textEl.useStyle(labelStyle.createTextStyle(textStyleModel, textSpecified, nil, nil, nil))
            el.setTextContent(textEl)
            // textConfig: { position: 'inside' }
            var textConfig = ElementTextConfig()
            textConfig.position = "inside"
            el.setTextConfig(textConfig)

            // z2: Z2_EMPHASIS_LIFT * 1e4  // A very large z2
            el.z2 = Z2_EMPHASIS_LIFT * 1e4
            // onclick: curry(onSelect, itemNode)
            //   The `e: ZRElementEvent` arg is dropped (OnSelectCallback is single-arg here); `itemNode`
            //   is bound as in `curry(onSelect, itemNode)`.
            _ = el.on("click", { _, _ in
                onSelect(itemNode)
                return nil
            }, nil)

            // (el as ECElement).disableLabelAnimation = true;
            // PORT-NOTE (deferred): the ECElement `disableLabelAnimation` flag gates label animation,
            //   which is not ported — setting it is a no-op (matches sibling views SankeyView / MapView / GeoView).

            // el.getTextContent().ensureState('emphasis').style = createTextStyle(emphasisTextStyleModel, {text});
            //   textEl is the textContent created above; the emphasis text style is stored on ZRText's
            //   typed per-state `textStyle` side-channel (ElementState.textStyle), mirroring labelStyle.swift.
            var emphasisTextSpecified = TextStyleProps()
            emphasisTextSpecified.text = text
            textEl.ensureState("emphasis").textStyle = labelStyle.createTextStyle(
                emphasisTextStyleModel, emphasisTextSpecified, nil, nil, nil
            )
            // el.ensureState('emphasis').style = emphasisItemStyle;
            el.ensureState("emphasis").style = emphasisItemStyle
            // toggleHoverEmphasis(el, emphasisModel.get('focus'), emphasisModel.get('blurScope'), emphasisModel.get('disabled'));
            let focus: InnerFocus? = emphasisModel.get("focus")
            let blurScope = (emphasisModel.get("blurScope") as? String).flatMap { BlurScope(rawValue: $0) }
            let isDisabled = (emphasisModel.get("disabled") as? Bool) ?? false
            states.toggleHoverEmphasis(el, focus, blurScope, isDisabled)

            // this.group.add(el);
            _ = self.group.add(el)

            // packEventData(el, seriesModel, itemNode);
            packEventData(el, seriesModel, itemNode)

            // lastX += itemWidth + ITEM_GAP;
            lastX += itemWidth + ITEM_GAP

            i -= 1
        }
    }

    // remove() { this.group.removeAll(); }
    public func remove() {
        _ = self.group.removeAll()
    }
}

// function makeItemPoints(x, y, itemWidth, itemHeight, head, tail)
private func makeItemPoints(
    _ x: Double, _ y: Double, _ itemWidth: Double, _ itemHeight: Double, _ head: Bool, _ tail: Bool
) -> [VectorArray] {
    // const points = [ [head?x:x-ARRAY_LENGTH, y], [x+itemWidth, y], [x+itemWidth, y+itemHeight], [head?x:x-ARRAY_LENGTH, y+itemHeight] ];
    var points: [[Double]] = [
        [head ? x : x - ARRAY_LENGTH, y],
        [x + itemWidth, y],
        [x + itemWidth, y + itemHeight],
        [head ? x : x - ARRAY_LENGTH, y + itemHeight]
    ]
    // !tail && points.splice(2, 0, [x + itemWidth + ARRAY_LENGTH, y + itemHeight / 2]);
    if !tail {
        points.insert([x + itemWidth + ARRAY_LENGTH, y + itemHeight / 2], at: 2)
    }
    // !head && points.push([x, y + itemHeight / 2]);
    if !head {
        points.append([x, y + itemHeight / 2])
    }
    // return points;
    return points.map { VectorArray($0[0], $0[1]) }
}

// Package custom mouse event.
// function packEventData(el, seriesModel, itemNode)
private func packEventData(_ el: Element, _ seriesModel: TreemapSeriesModel, _ itemNode: TreeNode?) {
    // getECData(el).eventData = { componentType: 'series', ..., nodeData: {...}, treePathInfo: ... };
    //   `ECEventData` is `[String: Any]` in this port.
    var eventData: [String: Any] = [
        "componentType": "series",
        "componentSubType": "treemap",
        "componentIndex": seriesModel.componentIndex,
        "seriesIndex": seriesModel.seriesIndex,
        "seriesName": seriesModel.name,
        "seriesType": "treemap",
        "selfType": "breadcrumb", // Distinguish with click event on treemap node.
        "nodeData": [
            "dataIndex": itemNode.map { $0.dataIndex } as Any,
            "name": itemNode?.name as Any
        ] as [String: Any]
    ]
    // treePathInfo: itemNode && wrapTreePathInfo(itemNode, seriesModel)
    //   Upstream's `&&` yields `undefined` when `itemNode` is nullish; leave the key genuinely absent
    //   rather than storing a boxed `Optional.none`, so key-presence checks match upstream truthiness.
    if let itemNode = itemNode {
        eventData["treePathInfo"] = treeHelper.wrapTreePathInfo(itemNode, seriesModel)
    }
    // getECData(el).eventData = { ... };
    innerStore.getECData(el).eventData = eventData
}

// export default Breadcrumb;  -> `open class Breadcrumb` above.
