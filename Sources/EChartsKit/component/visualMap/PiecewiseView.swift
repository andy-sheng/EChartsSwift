// Ported from echarts/src/component/visualMap/PiecewiseView.ts — keep in sync with upstream
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
//   import * as zrUtil from 'zrender/src/core/util';                 → `util.*` (ZRenderKit; `map`/`retrieve2`).
//   import VisualMapView from './VisualMapView';                     → `VisualMapView` (base, same dir).
//   import * as graphic from '../../util/graphic';                   → `Group` / `ZRText` (ZRenderKit).
//   import {createSymbol} from '../../util/symbol';                  → `symbol.createSymbol` (util/symbol.swift).
//   import * as layout from '../../util/layout';                     → `layout.box` (util/layout.swift).
//   import * as helper from './helper';
//     → `visualMap/helper` -> visualMapHelper.swift (reference source). `helper.getItemAlign` and
//        `helper.makeHighDownBatch` are reproduced (module-internal) and used live in ContinuousView.swift;
//        `helper.ItemAlign` collapses to `String`.
//   import type PiecewiseModel from './PiecewiseModel';
//     → `PiecewiseModel` (component/visualMap/PiecewiseModel.swift). Surface consumed here:
//        `getPieceList() -> [[String: Any]]`, `getRepresentValue(_ piece: [String: Any]) -> Any?`,
//        `getValueState(_) -> String`, plus (inherited) `get(...)`, `itemSize`, `textStyleModel`,
//        `getControllerVisual`. The base stores the instance as `VisualMapModel`; narrowed via cast.
//   import { TextAlign } from 'zrender/src/core/types';              → `TextAlign`.
//   import { VisualMappingOption } from '../../visual/VisualMapping'; → type-only (piece is a dynamic bag).
//   import { createTextStyle } from '../../label/labelStyle';        → the module-internal `createTextStyle`
//        (AxisBuilder.swift) — faithful minimal reproduction of `label/labelStyle.createTextStyle`.

// upstream: type of the mapped viewPieceList entry: { piece, indexInModelPieceList }.
private struct ViewPiece {
    // upstream `piece: VisualMappingOption['pieceList'][number]` — a dynamic bag.
    var piece: [String: Any]
    var indexInModelPieceList: Int
}

private struct ViewData {
    var viewPieceList: [ViewPiece]
    // upstream `endsText: string[]` (order [high, low], possibly reversed).
    var endsText: [Any]?
}

// upstream: class PiecewiseVisualMapView extends VisualMapView
// CONVENTIONS §2/§4: reference type → `final class`.
public final class PiecewiseVisualMapView: VisualMapView {

    // static type = 'visualMap.piecewise' as const;
    public static let piecewiseType = "visualMap.piecewise"
    // type = PiecewiseVisualMapView.type;
    public override var type: String { return PiecewiseVisualMapView.piecewiseType }

    // visualMapModel: PiecewiseModel;  (narrowed; base stores the same instance)

    // ---- test seam (no upstream analog): expose each rendered piece's clickable item symbol keyed by
    //   its model-pieceList index, so a headless test can compute the symbol's global pixel centre and
    //   inject a synthetic pointer click over it (mirrors ContinuousView._handleThumbForTest).
    internal private(set) var _viewPieceSymbolsForTest: [(indexInModelPieceList: Int, symbol: Path)] = []

    // protected doRender()
    public override func doRender(
        _ visualMapModelIn: VisualMapModel,
        _ ecModel: GlobalModel,
        _ api: ExtensionAPI,
        _ payload: Payload
    ) {
        let thisGroup = self.group

        _ = thisGroup.removeAll()
        self._viewPieceSymbolsForTest = []

        // upstream `this.visualMapModel: PiecewiseModel`. The base stores it as VisualMapModel; narrow it.
        let visualMapModel = self.visualMapModel as! PiecewiseModel
        let textGap = visualMapAsDouble(visualMapModel.get("textGap")) ?? 0
        let textStyleModel = visualMapModel.textStyleModel
        let itemAlign = self._getItemAlign()
        let itemSize = visualMapModel.itemSize
        let viewData = self._getViewData()
        let endsText = viewData.endsText
        // const showLabel = zrUtil.retrieve(visualMapModel.get('showLabel', true), !endsText);
        let showLabelOpt = visualMapModel.get("showLabel", true)
        let showLabel: Bool = (showLabelOpt as? Bool)
            ?? (showLabelOpt != nil ? visualMapJsTruthy(showLabelOpt) : (endsText == nil))
        // const silent = !visualMapModel.get('selectedMode');
        let silent = !visualMapJsTruthy(visualMapModel.get("selectedMode"))

        // endsText && this._renderEndsText(thisGroup, endsText[0], itemSize, showLabel, itemAlign);
        if let endsText = endsText, endsText.indices.contains(0) {
            self._renderEndsText(thisGroup, stringifyAny(endsText[0]), itemSize, showLabel, itemAlign)
        }

        util.each(viewData.viewPieceList) { item, _ in
            let piece = item.piece

            let itemGroup = Group()
            // itemGroup.onclick = zrUtil.bind(this._onItemClick, this, piece);
            //   Wired faithfully via the live-host click seam (Group.on("click", ...)); the piece is
            //   captured and toggled by `_onItemClick`, which dispatches `selectDataRange`. The headless
            //   render pipeline never fires it; a test/host dispatch drives it end-to-end.
            _ = itemGroup.on("click", { [weak self] _, _ in
                self?._onItemClick(piece)
                return nil
            })

            // this._enableHoverLink(itemGroup, item.indexInModelPieceList);
            self._enableHoverLink(itemGroup, item.indexInModelPieceList)

            // TODO Category
            // const representValue = visualMapModel.getRepresentValue(piece) as number;
            //   `getRepresentValue` returns `Any?`; upstream casts `as number` but for a `categories`
            //   visualMap it is the raw category (a STRING), which `getControllerVisual` maps through the
            //   category mapping. Pass it through un-coerced (the old `?? 0` collapsed every category
            //   swatch to the same colour).
            let representValue: Any? = visualMapModel.getRepresentValue(piece)

            let itemSymbolPath = self._createItemSymbol(
                itemGroup, representValue, [0, 0, itemSize[0], itemSize[1]], silent
            )
            self._viewPieceSymbolsForTest.append(
                (indexInModelPieceList: item.indexInModelPieceList, symbol: itemSymbolPath)
            )

            if showLabel {
                // const visualState = this.visualMapModel.getValueState(representValue);
                let visualState = visualMapModel.getValueState(representValue)
                // const align = textStyleModel.get('align') || itemAlign;
                let alignStr = (textStyleModel.get("align") as? String) ?? itemAlign

                var style = createTextStyle(
                    textStyleModel,
                    text: piece["text"] as? String,
                    align: TextAlign(rawValue: alignStr),
                    verticalAlign: TextVerticalAlign(rawValue: (textStyleModel.get("verticalAlign") as? String) ?? "middle")
                )
                // x: align === 'right' ? -textGap : itemSize[0] + textGap
                style.x = alignStr == "right" ? -textGap : itemSize[0] + textGap
                // y: itemSize[1] / 2
                style.y = itemSize[1] / 2
                // opacity: zrUtil.retrieve2(textStyleModel.get('opacity'), visualState === 'outOfRange' ? 0.5 : 1)
                style.opacity = visualMapAsDouble(textStyleModel.get("opacity"))
                    ?? (visualState == "outOfRange" ? 0.5 : 1)

                _ = itemGroup.add(ZRText([
                    "style": style,
                    "silent": silent
                ]))
            }

            _ = thisGroup.add(itemGroup)
        }

        // endsText && this._renderEndsText(thisGroup, endsText[1], itemSize, showLabel, itemAlign);
        if let endsText = endsText, endsText.indices.contains(1) {
            self._renderEndsText(thisGroup, stringifyAny(endsText[1]), itemSize, showLabel, itemAlign)
        }

        // layout.box(visualMapModel.get('orient'), thisGroup, visualMapModel.get('itemGap'));
        layout.box(
            (visualMapModel.get("orient") as? String) ?? "vertical",
            thisGroup,
            visualMapAsDouble(visualMapModel.get("itemGap")) ?? 0
        )

        self.renderBackground(thisGroup)

        self.positionGroup(thisGroup)

        _ = visualMapModelIn
    }

    // private _enableHoverLink(itemGroup: graphic.Group, pieceIndex: number)
    //   Wired faithfully via the live-host hover seam (Group.on("mouseover"/"mouseout", ...)); the event
    //   BUBBLES from the hit child up to `itemGroup`. On mouseover the matching-value series data points
    //   are HIGHLIGHTED (a batch built from `findTargetDataIndices(pieceIndex)`); mouseout downplays them.
    private func _enableHoverLink(_ itemGroup: Group, _ pieceIndex: Int) {
        // itemGroup
        //     .on('mouseover', () => onHoverLink('highlight'))
        //     .on('mouseout', () => onHoverLink('downplay'));
        _ = itemGroup.on("mouseover", { [weak self] _, _ in
            self?._onHoverLink("highlight", pieceIndex)
            return nil
        })
        _ = itemGroup.on("mouseout", { [weak self] _, _ in
            self?._onHoverLink("downplay", pieceIndex)
            return nil
        })
    }

    // upstream: const onHoverLink = (method?: 'highlight' | 'downplay') => { ... }
    private func _onHoverLink(_ method: String, _ pieceIndex: Int) {
        // const visualMapModel = this.visualMapModel;
        let visualMapModel = self.visualMapModel as! PiecewiseModel

        // visualMapModel.option.hoverLink && this.api.dispatchAction({ type: method, batch:
        //     helper.makeHighDownBatch(visualMapModel.findTargetDataIndices(pieceIndex), visualMapModel) });
        //   `get('hoverLink')` resolves the default (true) — equivalent to reading `option.hoverLink`.
        guard visualMapJsTruthy(visualMapModel.get("hoverLink")) else { return }

        var payload = Payload(type: method)
        payload.batch = piecewiseMakeHighDownBatch(
            visualMapModel.findTargetDataIndices(Double(pieceIndex)),
            visualMapModel
        )
        self.api!.dispatchAction(payload)
    }

    // private _getItemAlign(): helper.ItemAlign
    private func _getItemAlign() -> String {
        let visualMapModel = self.visualMapModel!

        // if (modelOption.orient === 'vertical') { return helper.getItemAlign(visualMapModel, api, itemSize); }
        if (visualMapModel.get("orient") as? String) == "vertical" {
            return getItemAlign(visualMapModel, self.api!, visualMapModel.itemSize)
        }
        else { // horizontal, most case left unless specifying right.
            // let align = modelOption.align;
            var align = visualMapModel.get("align") as? String
            if align == nil || align == "auto" {
                align = "left"
            }
            return align!
        }
    }

    // private _renderEndsText(group, text, itemSize, showLabel, itemAlign)
    private func _renderEndsText(
        _ group: Group,
        _ text: String,
        _ itemSize: [Double],
        _ showLabel: Bool,
        _ itemAlign: String
    ) {
        // if (!text) { return; }
        if text.isEmpty {
            return
        }

        let itemGroup = Group()
        let textStyleModel = self.visualMapModel!.textStyleModel

        // itemGroup.add(new graphic.Text({ style: createTextStyle(textStyleModel, {x, y, verticalAlign, align, text}) }));
        var style = createTextStyle(
            textStyleModel,
            text: text,
            // align: showLabel ? itemAlign : 'center'
            align: TextAlign(rawValue: showLabel ? itemAlign : "center"),
            verticalAlign: .middle
        )
        // x: showLabel ? (itemAlign === 'right' ? itemSize[0] : 0) : itemSize[0] / 2
        style.x = showLabel ? (itemAlign == "right" ? itemSize[0] : 0) : itemSize[0] / 2
        // y: itemSize[1] / 2
        style.y = itemSize[1] / 2

        _ = itemGroup.add(ZRText(["style": style]))

        _ = group.add(itemGroup)
    }

    /**
     * @private
     * @return {Object} {peiceList, endsText} The order is the same as screen pixel order.
     */
    private func _getViewData() -> ViewData {
        let visualMapModel = self.visualMapModel as! PiecewiseModel

        // const viewPieceList = zrUtil.map(visualMapModel.getPieceList(), (piece, index) => ({piece, indexInModelPieceList: index}));
        var viewPieceList = util.map(visualMapModel.getPieceList()) { piece, index in
            ViewPiece(piece: piece, indexInModelPieceList: index)
        }
        // let endsText = visualMapModel.get('text');
        var endsText = visualMapModel.get("text") as? [Any]

        // Consider orient and inverse.
        let orient = visualMapModel.get("orient") as? String
        let inverse = visualMapJsTruthy(visualMapModel.get("inverse"))

        // Order of model pieceList is always [low, ..., high]
        // if (orient === 'horizontal' ? inverse : !inverse) { viewPieceList.reverse(); }
        if orient == "horizontal" ? inverse : !inverse {
            viewPieceList.reverse()
        }
        // Origin order of endsText is [high, low]
        // else if (endsText) { endsText = endsText.slice().reverse(); }
        else if endsText != nil {
            endsText = Array(endsText!.reversed())
        }

        return ViewData(viewPieceList: viewPieceList, endsText: endsText)
    }

    // private _createItemSymbol(group, representValue, shapeParam, silent?)
    @discardableResult
    private func _createItemSymbol(
        _ group: Group,
        _ representValue: Any?,     // number for numeric pieces, category string for a `categories` map
        _ shapeParam: [Double],
        _ silent: Bool = false
    ) -> Path {
        // const itemSymbol = createSymbol(getControllerVisual(representValue, 'symbol'), x, y, w, h,
        //   getControllerVisual(representValue, 'color'));
        // PORT-NOTE: upstream passes `getControllerVisual(...,'symbol') as string` directly; when the
        //   symbol mapping yields no value we default to 'roundRect' (createSymbol requires a non-nil type).
        let symbolType = (self.getControllerVisual(representValue, "symbol") as? String) ?? "roundRect"
        let color = ZRenderKit.ZRColor.string(colorToString(self.getControllerVisual(representValue, "color")))
        let itemSymbol = symbol.createSymbol(
            symbolType,
            shapeParam[0], shapeParam[1], shapeParam[2], shapeParam[3],
            color
        )
        // itemSymbol.silent = silent;
        // PORT-NOTE: `ECSymbol` surfaces as a concrete `Path` (SymbolPath); set silent through it (same
        //   seam as LegendView.getDefaultLegendIcon).
        let itemSymbolPath = itemSymbol as! Path
        itemSymbolPath.silent = silent
        _ = group.add(itemSymbolPath)
        return itemSymbolPath
    }

    // private _onItemClick(piece: VisualMappingOption['pieceList'][number])
    private func _onItemClick(_ piece: [String: Any]) {
        // const visualMapModel = this.visualMapModel;
        let visualMapModel = self.visualMapModel as! PiecewiseModel
        // const option = visualMapModel.option;
        let option = (visualMapModel.option as? [String: Any]) ?? [:]
        // const selectedMode = option.selectedMode;
        let selectedMode = option["selectedMode"]
        // if (!selectedMode) { return; }
        if !visualMapJsTruthy(selectedMode) {
            return
        }
        // const selected = zrUtil.clone(option.selected);
        var selected = (util.clone(option["selected"] ?? [String: Any]()) as? [String: Any]) ?? [:]
        // const newKey = visualMapModel.getSelectedMapKey(piece);
        let newKey = visualMapModel.getSelectedMapKey(piece)

        // if (selectedMode === 'single' || selectedMode === true) {
        if (selectedMode as? String) == "single" || (selectedMode as? Bool) == true {
            // selected[newKey] = true;
            selected[newKey] = true
            // zrUtil.each(selected, function (o, key) { selected[key] = key === newKey; });
            for key in selected.keys {
                selected[key] = (key == newKey)
            }
        }
        else {
            // selected[newKey] = !selected[newKey];
            selected[newKey] = !visualMapJsTruthy(selected[newKey])
        }

        // this.api.dispatchAction({ type: 'selectDataRange', from: this.uid,
        //     visualMapId: this.visualMapModel.id, selected: selected });
        var payload = Payload(type: "selectDataRange")
        payload.other["from"] = self.uid
        payload.other["visualMapId"] = visualMapModel.id
        payload.other["selected"] = selected
        self.api!.dispatchAction(payload)
    }
}

// export default PiecewiseVisualMapView;  → `final class PiecewiseVisualMapView` above.

// upstream helper.makeHighDownBatch(batch, visualMapModel) — take `findTargetDataIndices`' output
//   ([{seriesId, dataIndex:[Double]}]) and, for each item, move dataIndex → dataIndexInside + stamp a
//   `highlightKey`, emitting the `[PayloadItem]` batch consumed by the highlight/downplay actions.
//   (The sibling ContinuousView.swift has an equivalent private helper over `[BatchItem]`; here the
//   input is the raw dict form, so a Piecewise-local variant is kept.)
private func piecewiseMakeHighDownBatch(_ batch: [[String: Any]], _ visualMapModel: VisualMapModel) -> [PayloadItem] {
    var out: [PayloadItem] = []
    for item in batch {
        var p = PayloadItem()
        // (seriesId is preserved; dataIndex != null → dataIndexInside = dataIndex, dataIndex = null.)
        p.other["seriesId"] = item["seriesId"]
        if let dataIndex = item["dataIndex"], !(dataIndex is NSNull) {
            p.other["dataIndexInside"] = dataIndex
        }
        p.other["highlightKey"] = "visualMap" + String(Int(visualMapModel.componentIndex))
        out.append(p)
    }
    return out
}
