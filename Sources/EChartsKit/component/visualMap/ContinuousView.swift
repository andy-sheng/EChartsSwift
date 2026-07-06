// Ported from echarts/src/component/visualMap/ContinuousView.ts — keep in sync with upstream
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
//   import * as zrUtil from 'zrender/src/core/util';                 → `util.*` (ZRenderKit).
//   import LinearGradient from 'zrender/src/graphic/LinearGradient'; → `LinearGradient` (ZRenderKit).
//   import * as eventTool from 'zrender/src/core/event';             → PORT-TODO: DEFERRED (drag/interaction).
//   import VisualMapView from './VisualMapView';                     → `VisualMapView` (base, same dir).
//   import * as graphic from '../../util/graphic';
//     → `Group` / `Rect` / `ZRText` (ZRenderKit). `graphic.Polygon` (the upstream bar is a Polygon whose
//        points/fill are set by the DEFERRED `_updateView`); the STATIC bar here is a gradient-filled `Rect`.
//        `graphic.getTransform` / `graphic.applyTransform` / `graphic.transformDirection` (util/graphic — NOT
//        ported) are reproduced locally at the bottom (used only by the static `_renderEndsText`).
//   import {linearMap, mathMax, mathMin, mathPI} from '../../util/number';
//     → `mathPI` == `Double.pi`; `mathMax`/`mathMin` == `Swift.max`/`Swift.min`; `linearMap` (util/number.swift,
//        used only by the DEFERRED handle/hover machinery).
//   import sliderMove from '../helper/sliderMove';                   → PORT-TODO: DEFERRED (drag).
//   import * as helper from './helper';
//     → PORT-TODO: `visualMap/helper` NOT ported. `helper.getItemAlign` reproduced locally (bottom);
//        `helper.getCursor` / `helper.makeHighDownBatch` are DEFERRED (interaction).
//   import * as modelUtil from '../../util/model';                   → PORT-TODO: DEFERRED (makeInner / hover batches).
//   import ContinuousModel from './ContinuousModel';
//     → PORT-TODO: `ContinuousModel` is an ASSUMED sibling (models phase). Surface consumed here:
//        `get(...)`, `itemSize`, `getExtent()`, `textStyleModel`, plus (inherited) `controllerVisuals` /
//        `getValueState` via the base `getControllerVisual`.
//   import Element, { ElementEvent } from 'zrender/src/Element';     → `Element` / DEFERRED events.
//   import { TextVerticalAlign, TextAlign } from 'zrender/src/core/types';  → `TextVerticalAlign` / `TextAlign`.
//   import { parsePercent } from 'zrender/src/contain/text';         → DEFERRED (handle sizing).
//   import { createSymbol } from '../../util/symbol';                → DEFERRED (handle/indicator symbols).
//   import { createTextStyle } from '../../label/labelStyle';        → the module-internal `createTextStyle`
//        (AxisBuilder.swift) — faithful minimal reproduction of `label/labelStyle.createTextStyle`.
//   (all remaining imports — states / innerStore / event / BoundingRect — feed the DEFERRED interaction paths.)

// Arbitrary value
// PORT-TODO: HOVER_LINK_SIZE / HOVER_LINK_OUT / HANDLE_LABEL_MERGE_MARGIN feed the DEFERRED hover-link /
//   handle-label machinery. Preserved for the diffable surface.
// const HOVER_LINK_SIZE = 12; const HOVER_LINK_OUT = 6; const HANDLE_LABEL_MERGE_MARGIN = 2;

// type Orient = VisualMapModel['option']['orient'];   → `String` ('horizontal' | 'vertical').

// upstream: type ShapeStorage = { handleThumbs; handleLabelPoints; handleLabels; inRange; outOfRange;
//   mainGroup; indicator; indicatorLabel; indicatorLabelPoint }.
//   STATIC subset: only `mainGroup` (+ the gradient bar it holds) is built here; the handle/indicator
//   slots are DEFERRED with the drag interaction.
private final class ShapeStorage {
    var mainGroup: Group!
    // PORT-TODO: DEFERRED — handleThumbs / handleLabels / handleLabelPoints / inRange / outOfRange (Polygons) /
    //   indicator / indicatorLabel / indicatorLabelPoint (drag handle + hover indicator).
    init() {}
}

// upstream: class ContinuousView extends VisualMapView
// CONVENTIONS §2/§4: reference type → `final class`.
public final class ContinuousView: VisualMapView {

    // static type = 'visualMap.continuous';
    public static let continuousType = "visualMap.continuous"
    // type = ContinuousView.type;
    public override var type: String { return ContinuousView.continuousType }

    // visualMapModel: ContinuousModel;  (narrowed; the base stores the same instance as VisualMapModel)

    // private _shapes = {} as ShapeStorage;
    private var _shapes = ShapeStorage()

    // private _orient: Orient;
    private var _orient: String = "vertical"

    // private _useHandle: boolean;
    private var _useHandle: Bool = false

    // PORT-TODO: DEFERRED interaction state — `_dataInterval` / `_handleEnds` / `_hoverLinkDataIndices` /
    //   `_dragging` / `_hovering` / `_firstShowIndicator` drive drag + hover-link, all deferred.

    // init(ecModel, api) { super.init(...); bind hover handlers... }
    //   The DEFERRED `zrUtil.bind` of the hover handlers is dropped (interaction). Base init is inherited.

    // upstream: doRender(visualMapModel, ecModel, api, payload: {type, from})
    public override func doRender(
        _ visualMapModel: VisualMapModel,
        _ ecModel: GlobalModel,
        _ api: ExtensionAPI,
        _ payload: Payload
    ) {
        // if (!payload || payload.type !== 'selectDataRange' || payload.from !== this.uid) { this._buildView(); }
        //   `selectDataRange` is a self-dispatched DRAG action (interaction, DEFERRED). For the static
        //   render we always (re)build — the guard only suppresses rebuilds triggered by the deferred drag.
        let from = payload.other["from"] as? String
        if payload.type != "selectDataRange" || from != self.uid {
            self._buildView()
        }
    }

    private func _buildView() {
        _ = self.group.removeAll()

        let visualMapModel = self.visualMapModel!
        let thisGroup = self.group

        self._orient = (visualMapModel.get("orient") as? String) ?? "vertical"
        self._useHandle = visualMapJsTruthy(visualMapModel.get("calculable"))

        // PORT-TODO: DEFERRED — `this._resetInterval()` seeds `_dataInterval` / `_handleEnds` from the
        //   selected range for the drag handles. The static gradient bar uses the full data extent instead.

        self._renderBar(thisGroup)

        // const dataRangeText = visualMapModel.get('text');
        let dataRangeText = visualMapModel.get("text") as? [Any]
        self._renderEndsText(thisGroup, dataRangeText, 0)
        self._renderEndsText(thisGroup, dataRangeText, 1)

        // PORT-TODO: DEFERRED — `this._updateView(true)` (sketch) + `this._updateView()` (real) set the
        //   in/out-of-range Polygon points + handle positions. That is the drag machinery; the static bar
        //   is filled directly in `_renderBar`.

        // After updating view, inner shapes is built completely, and then background can be rendered.
        self.renderBackground(thisGroup)

        // PORT-TODO: DEFERRED — `this._enableHoverLinkToSeries()` / `this._enableHoverLinkFromSeries()`
        //   (hover-link interaction, out of static-render scope).

        self.positionGroup(thisGroup)
    }

    private func _renderEndsText(_ group: Group, _ dataRangeText: [Any]?, _ endsIndex: Int) {
        let visualMapModel = self.visualMapModel!

        // Compatible with ec2, text[0] maps to the high value, text[1] to the low value.
        let text: String
        if let dataRangeText = dataRangeText {
            let rawText = dataRangeText.indices.contains(1 - endsIndex) ? dataRangeText[1 - endsIndex] : nil
            text = rawText != nil ? stringifyAny(rawText) : ""
        }
        else if self._useHandle {
            // A `calculable` visualMap without an explicit `text` shows its range-handle VALUES at the ends
            //   — the '100'/'0' endpoint labels. `_applyTransform` runs the end point through the bar
            //   group's scaleY:-1 transform, so endsIndex 0 lands at the VISUAL BOTTOM (low value) and
            //   endsIndex 1 at the top (high value).
            let vExtent = visualMapModel.getExtent()
            let value = endsIndex == 0 ? Swift.min(vExtent[0], vExtent[1]) : Swift.max(vExtent[0], vExtent[1])
            text = visualMapModel.formatValueText(value)
        }
        else {
            return
        }

        let textGap = visualMapAsDouble(visualMapModel.get("textGap")) ?? 0
        let itemSize = visualMapModel.itemSize

        let barGroup = self._shapes.mainGroup!
        // const position = this._applyTransform([itemSize[0]/2, endsIndex===0 ? -textGap : itemSize[1]+textGap], barGroup);
        let position = self._applyTransform(
            [
                itemSize[0] / 2,
                endsIndex == 0 ? -textGap : itemSize[1] + textGap
            ],
            barGroup
        )
        // const align = this._applyTransform(endsIndex===0 ? 'bottom' : 'top', barGroup);
        let align = self._applyTransform(endsIndex == 0 ? "bottom" : "top", barGroup)
        let orient = self._orient
        let textStyleModel = visualMapModel.textStyleModel

        // verticalAlign: textStyleModel.get('verticalAlign') || (orient==='horizontal' ? 'middle' : align)
        let vAlignStr = (textStyleModel.get("verticalAlign") as? String)
            ?? (orient == "horizontal" ? "middle" : align)
        // align: textStyleModel.get('align') || (orient==='horizontal' ? align : 'center')
        let alignStr = (textStyleModel.get("align") as? String)
            ?? (orient == "horizontal" ? align : "center")

        // this.group.add(new graphic.Text({ style: createTextStyle(textStyleModel, {x, y, verticalAlign, align, text}) }));
        var style = createTextStyle(
            textStyleModel,
            text: text,
            align: TextAlign(rawValue: alignStr),
            verticalAlign: TextVerticalAlign(rawValue: vAlignStr)
        )
        style.x = position[0]
        style.y = position[1]
        _ = self.group.add(ZRText(["style": style]))
    }

    private func _renderBar(_ targetGroup: Group) {
        let visualMapModel = self.visualMapModel!
        let shapes = self._shapes
        let itemSize = visualMapModel.itemSize
        // const itemAlign = helper.getItemAlign(visualMapModel, this.api, itemSize);
        let itemAlign = getItemAlign(visualMapModel, self.api!, itemSize)
        let mainGroup = self._createBarGroup(itemAlign)
        shapes.mainGroup = mainGroup

        let gradientBarGroup = Group()
        _ = mainGroup.add(gradientBarGroup)

        // Bar
        // PORT-TODO: upstream builds two `graphic.Polygon`s (`outOfRange`, `inRange`) whose points + fill
        //   are assigned by the DEFERRED `_updateView`, and mounts drag on `inRange`. The STATIC render
        //   draws a single gradient-filled `Rect` spanning the item — the value→visual color encoding via
        //   `_makeColorGradient` (getControllerVisual('color')) is preserved; the drag/handle path is deferred.
        let dataExtent = visualMapModel.getExtent()
        let colorStops = self._makeColorGradient(dataExtent, forceState: nil, convertOpacityToAlpha: true)
        // new LinearGradient(0, 0, 0, 1, colorStops)  (vertical bar gradient, low→high along y)
        let barColor = LinearGradient(0, 0, 0, 1, colorStops)

        var barShape = RectShape()
        barShape.x = 0
        barShape.y = 0
        barShape.width = itemSize[0]
        barShape.height = itemSize[1]
        let barRect = Rect(["shape": barShape as PathShape])
        barRect.pathStyle.fill = .linearGradient(barColor)
        _ = gradientBarGroup.add(barRect)

        // A border radius clip.
        // gradientBarGroup.setClipPath(new graphic.Rect({ shape: {x:0,y:0,width,height,r:3} }));
        var clipShape = RectShape()
        clipShape.x = 0
        clipShape.y = 0
        clipShape.width = itemSize[0]
        clipShape.height = itemSize[1]
        clipShape.r = .number(3)
        gradientBarGroup.setClipPath(Rect(["shape": clipShape as PathShape]))

        // Calculable handles — STATIC form. The full drag/indicator widget is deferred, but a `calculable`
        //   visualMap must still show the two range handles + their value labels (echarts draws them at the
        //   current window ends; static = the full data extent). For a vertical bar the TOP handle marks the
        //   high value, the BOTTOM the low (matching `_renderEndsText`'s high→low mapping). Each handle is a
        //   thin bar tinted with that end's mapped color, with the formatted value beside it.
        if self._useHandle {
            let vExtent = visualMapModel.getExtent()
            let highVal = Swift.max(vExtent[0], vExtent[1])
            let lowVal = Swift.min(vExtent[0], vExtent[1])
            // The gradient bar renders colorStops along y=0→1 (top→bottom); its top end is the high value,
            //   so the top handle uses colorStops.first, the bottom colorStops.last (matching the bar).
            let highColor = colorStops.first?.color ?? "#000"
            let lowColor = colorStops.last?.color ?? "#000"
            let textStyleModel = visualMapModel.textStyleModel
            let isVertical = self._orient != "horizontal"
            for endsIndex in 0..<2 {
                let isHighEnd = endsIndex == 0
                let value = isHighEnd ? highVal : lowVal
                let color = isHighEnd ? highColor : lowColor

                var hShape = RectShape()
                if isVertical {
                    let y = isHighEnd ? 0.0 : itemSize[1]
                    hShape.x = -1; hShape.y = y - 2; hShape.width = itemSize[0] + 2; hShape.height = 4
                } else {
                    let x = isHighEnd ? itemSize[0] : 0.0
                    hShape.x = x - 2; hShape.y = -1; hShape.width = 4; hShape.height = itemSize[1] + 2
                }
                let handle = Rect(["shape": hShape as PathShape])
                handle.pathStyle.fill = .string(color)
                handle.pathStyle.stroke = .string("#fff")
                handle.pathStyle.lineWidth = 1
                _ = mainGroup.add(handle)
                // The value labels are drawn by `_renderEndsText` (in the UNFLIPPED outer group via
                //   _applyTransform) so they are not mirrored by this group's scaleY:-1 transform.
                _ = (value, textStyleModel, isVertical)
            }
        }

        _ = targetGroup.add(mainGroup)
    }

    // upstream: private _makeColorGradient(dataInterval, opts) — sample the (possibly non-linear, e.g.
    //   colorHue) mapping into gradient color stops. Faithful.
    private func _makeColorGradient(
        _ dataInterval: [Double],
        forceState: VisualState?,
        convertOpacityToAlpha: Bool
    ) -> [GradientColorStop] {
        // Considering colorHue, which is not linear, so we have to sample to calculate gradient color
        // stops, but not only calculate head and tail.
        let sampleNumber = 100 // Arbitrary value.
        var colorStops: [GradientColorStop] = []
        let step = (dataInterval[1] - dataInterval[0]) / Double(sampleNumber)

        // colorStops.push({ color: getControllerVisual(dataInterval[0], 'color', opts), offset: 0 });
        colorStops.append(GradientColorStop(
            offset: 0,
            color: colorToString(self.getControllerVisual(
                dataInterval[0], "color", forceState: forceState, convertOpacityToAlpha: convertOpacityToAlpha
            ))
        ))

        // for (let i = 1; i < sampleNumber; i++) { ... }
        var i = 1
        while i < sampleNumber {
            let currValue = dataInterval[0] + step * Double(i)
            if currValue > dataInterval[1] {
                break
            }
            colorStops.append(GradientColorStop(
                offset: Double(i) / Double(sampleNumber),
                color: colorToString(self.getControllerVisual(
                    currValue, "color", forceState: forceState, convertOpacityToAlpha: convertOpacityToAlpha
                ))
            ))
            i += 1
        }

        // colorStops.push({ color: getControllerVisual(dataInterval[1], 'color', opts), offset: 1 });
        colorStops.append(GradientColorStop(
            offset: 1,
            color: colorToString(self.getControllerVisual(
                dataInterval[1], "color", forceState: forceState, convertOpacityToAlpha: convertOpacityToAlpha
            ))
        ))

        return colorStops
    }

    // upstream: private _createBarGroup(itemAlign) — the orient/inverse/itemAlign transform of the bar.
    private func _createBarGroup(_ itemAlign: String) -> Group {
        let isVertical = self._orient == "vertical"
        let isItemAlignButtom = itemAlign == "bottom"
        let isItemAlignLeft = itemAlign == "left"
        let inverse = visualMapJsTruthy(self.visualMapModel!.get("inverse"))

        let props: [String: Any]
        if !isVertical && !inverse {
            props = ["scaleX": isItemAlignButtom ? 1.0 : -1.0, "rotation": Double.pi / 2]
        }
        else if !isVertical && inverse {
            props = ["scaleX": isItemAlignButtom ? -1.0 : 1.0, "rotation": -Double.pi / 2]
        }
        else if isVertical && !inverse {
            props = ["scaleX": isItemAlignLeft ? 1.0 : -1.0, "scaleY": -1.0]
        }
        else { // isVertical && inverse
            props = ["scaleX": isItemAlignLeft ? 1.0 : -1.0]
        }
        return Group(props)
    }

    // PORT-TODO: DEFERRED — the whole drag/handle/indicator/hover-link surface of ContinuousView.ts is
    //   out of static-render scope (CONVENTIONS §5): `_createHandle`, `_createIndicator`, `_mountDrag`,
    //   `_dragHandle`, `_resetInterval`, `_updateInterval`, `_updateView`, `_createBarVisual`,
    //   `_createBarPoints`, `_updateHandle`, `_showIndicator`, `_enableHoverLinkToSeries`,
    //   `_enableHoverLinkFromSeries`, `_doHoverLinkToSeries`, `_hoverLinkFromSeriesMouseOver`,
    //   `_hideIndicator`, `_clearHoverLinkToSeries`, `_clearHoverLinkFromSeries`, `_dispatchHighDown`,
    //   `dispose`, and the module helpers `createPolygon` / `getHalfHoverLinkSize` / `useHoverLinkOnHandle`
    //   / `getCursor`. Port alongside the action/interaction layer.

    // upstream overloaded: _applyTransform(vertex: number[] | Direction, element, inverse?, global?)
    private func _applyTransform(_ vertex: [Double], _ element: Element, _ inverse: Bool = false, _ global: Bool = false) -> [Double] {
        let transform = getTransform(element, global ? nil : self.group)
        return applyTransformPoint(vertex, transform, inverse)
    }

    private func _applyTransform(_ vertex: String, _ element: Element, _ inverse: Bool = false, _ global: Bool = false) -> String {
        let transform = getTransform(element, global ? nil : self.group)
        return transformDirection(vertex, transform, inverse)
    }
}

// export default ContinuousView;  → `final class ContinuousView` above.

// ============================================================================
// PORT-TODO helpers — NOT part of visualMap/ContinuousView.ts upstream. These reproduce out-of-phase
// sibling APIs (`util/graphic` transform helpers, `visualMap/helper.getItemAlign`) so the static render
// compiles. Delete each when its real sibling lands and call the sibling directly.
// ============================================================================

/// upstream `util/graphic.getTransform(target, ancestor)` — matrix from `target` up to (excluding) `ancestor`.
private func getTransform(_ target: Transformable?, _ ancestor: Transformable?) -> MatrixArray {
    var mat = matrix.identity()
    var t = target
    while let cur = t, cur !== ancestor {
        // matrix.mul(mat, target.getLocalTransform(), mat)  → out = mul(m1, m2)
        mat = matrix.mul(cur.getLocalTransform(), mat)
        t = cur.parent
    }
    return mat
}

/// upstream `util/graphic.applyTransform(target, transform, invert?)` — apply matrix (or its inverse) to a point.
private func applyTransformPoint(_ target: [Double], _ transform: MatrixArray, _ invert: Bool) -> [Double] {
    var m = transform
    if invert {
        m = matrix.invert(m) ?? m
    }
    let r = vector.applyTransform(VectorArray(target[0], target[1]), m)
    return [r[0], r[1]]
}

/// upstream `util/graphic.transformDirection(direction, transform, invert?)`.
private func transformDirection(_ direction: String, _ transform: MatrixArray, _ invert: Bool) -> String {
    // Pick a base, ensure that transform result will not be (0, 0).
    let hBase = (transform[4] == 0 || transform[5] == 0 || transform[0] == 0)
        ? 1.0 : Swift.abs(2 * transform[4] / transform[0])
    let vBase = (transform[4] == 0 || transform[5] == 0 || transform[2] == 0)
        ? 1.0 : Swift.abs(2 * transform[4] / transform[2])

    var vertex: [Double] = [
        direction == "left" ? -hBase : direction == "right" ? hBase : 0,
        direction == "top" ? -vBase : direction == "bottom" ? vBase : 0
    ]
    vertex = applyTransformPoint(vertex, transform, invert)

    return Swift.abs(vertex[0]) > Swift.abs(vertex[1])
        ? (vertex[0] > 0 ? "right" : "left")
        : (vertex[1] > 0 ? "bottom" : "top")
}

/// The `getControllerVisual('color', ...)` result is a color option value (a `String` in the static path).
/// Coerce to the `String` that `GradientColorStop.color` requires.
internal func colorToString(_ v: Any?) -> String {
    if let s = v as? String { return s }
    // PORT-TODO: gradient/pattern color objects are not stringified here (out of static-render scope).
    return ""
}

/// `String(value)` for the `text + ''` idiom in `_renderEndsText`.
internal func stringifyAny(_ v: Any?) -> String {
    guard let v = v else { return "" }
    if let s = v as? String { return s }
    if let d = visualMapAsDouble(v) {
        // JS numeric stringify: drop the trailing `.0` for integral values.
        return d == d.rounded() && d.isFinite ? String(Int(d)) : String(d)
    }
    return "\(v)"
}

/// PORT-TODO: faithful reproduction of `visualMap/helper.getItemAlign` (NOT ported). Returns
///   'left'|'right'|'top'|'bottom'. The auto branch mirrors upstream except the `rect.margin[...]` term
///   (util/layout.swift `LayoutRect` has no `.margin` slot yet) is taken as 0 — the dominant term is
///   `rect[x|y] + rect[width|height]*0.5` vs `ecSize*0.5`. Delete when visualMap/helper.swift lands.
internal func getItemAlign(_ visualMapModel: VisualMapModel, _ api: ExtensionAPI, _ itemSize: [Double]) -> String {
    // const paramsSet = [['left','right','width'], ['top','bottom','height']];
    let paramsSet = [["left", "right", "width"], ["top", "bottom", "height"]]

    let itemAlign = visualMapModel.get("align") as? String
    // if (itemAlign != null && itemAlign !== 'auto') { return itemAlign; }
    if let itemAlign = itemAlign, itemAlign != "auto" {
        return itemAlign
    }

    // Auto decision align.
    let ecWidth = api.getWidth()
    let ecHeight = api.getHeight()
    let realIndex = (visualMapModel.get("orient") as? String) == "horizontal" ? 1 : 0

    let reals = paramsSet[realIndex]
    // const fakeValue = [0, null, 10];
    let fakeValue: [Any?] = [0.0, nil, 10.0]

    var layoutInput: [String: Any] = [:]
    for i in 0..<3 {
        // layoutInput[paramsSet[1 - realIndex][i]] = fakeValue[i];
        if let fv = fakeValue[i] {
            layoutInput[paramsSet[1 - realIndex][i]] = fv
        }
        // layoutInput[reals[i]] = i === 2 ? itemSize[0] : modelOption[reals[i]];
        if i == 2 {
            layoutInput[reals[i]] = itemSize[0]
        }
        else if let v = visualMapModel.get(reals[i]) {
            layoutInput[reals[i]] = v
        }
    }

    // const rParam = ([['x','width',3], ['y','height',0]])[realIndex];
    let ecSize = BoundingRect(0, 0, ecWidth, ecHeight)
    let rect = layout.getLayoutRect(layoutInput as Any?, ecSize, visualMapModel.get("padding"))

    let rectStart = realIndex == 0 ? rect.x : rect.y
    let rectLen = realIndex == 0 ? rect.width : rect.height
    let ecLen = realIndex == 0 ? ecWidth : ecHeight

    // return reals[ (margin[...] || 0) + rect[x|y] + rect[w|h]*0.5 < ecSize[w|h]*0.5 ? 0 : 1 ];
    //   PORT-TODO: margin term dropped (see doc comment) — treated as 0.
    return reals[(0 + rectStart + rectLen * 0.5) < ecLen * 0.5 ? 0 : 1]
}
