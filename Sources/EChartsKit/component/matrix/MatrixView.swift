// Ported from echarts/src/component/matrix/MatrixView.ts — keep in sync with upstream
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
//   import MatrixModel, { MatrixBaseCellOption, MatrixCellStyleOption, MatrixOption } from '../../coord/matrix/MatrixModel';
//     → `MatrixModel` (coord/matrix sibling; ComponentModel subclass). The TS interfaces
//       `MatrixBaseCellOption` / `MatrixCellStyleOption` / `MatrixOption` are dynamic option bags — in this
//       port the cell options are `[String: Any]` (ModelOption) read by key (`option["itemStyle"]` etc.).
//   import ComponentView from '../../view/Component';            → `ComponentView` (view/ComponentView.swift).
//   import { MatrixCellLayoutInfo, MatrixDim, MatrixXYLocator } from '../../coord/matrix/MatrixDim';
//     → `MatrixCellLayoutInfo` / `MatrixDim` / `MatrixXYLocator` (coord/matrix siblings). `MatrixXYLocator`
//       is a Point coordinate → `Double`.
//   import Model from '../../model/Model';                       → `Model`.
//   import { NullUndefined } from '../../util/types';            → collapsed to `nil` (CONVENTIONS §6).
//   import BoundingRect, { RectLike } from 'zrender/src/core/BoundingRect';  → ZRenderKit `BoundingRect` / `RectLike`.
//   import * as vectorUtil from 'zrender/src/core/vector';
//     → `vectorUtil.set(out, a, b)` (write a 2-vector) is inlined as a fresh `[Double]` locator per
//       CONVENTIONS §3 (no out-param mutation); the reused-scratch perf intent is a JS GC concern only.
//   import { RectShape } from 'zrender/src/graphic/shape/Rect';  → ZRenderKit `RectShape`.
//   import { ItemStyleProps } from '../../model/mixin/itemStyle';  → `ItemStyleProps` (= [String: Any]).
//   import { LineStyleProps } from '../../model/mixin/lineStyle';  → `LineStyleProps` (= [String: Any]).
//   import { LineShape } from 'zrender/src/graphic/shape/Line';  → ZRenderKit `LineShape`.
//   import { subPixelOptimize } from 'zrender/src/graphic/helper/subPixelOptimize';
//     → `subPixelOptimizeNS.subPixelOptimize`.
//   import { Group, Text, Rect, Line, XY, setTooltipConfig, expandOrShrinkRect } from '../../util/graphic';
//     → `Group` / `Rect` / `Line` are the ZRenderKit scene-graph types used directly (the sanctioned DRAWING
//       deviation, cf. CalendarView / SingleAxisView); `Text` → ZRenderKit `ZRText`. `XY` has NOT landed in
//       util/graphic.swift yet — it is reproduced as the file-private `XY` constant at the bottom of this file
//       (see its PORT-NOTE there); delete that and import the shared sibling once it lands.
//       `setTooltipConfig` → the file-scope `setTooltipConfig(...)` in util/graphic.swift. `expandOrShrinkRect`
//       (util/graphic.swift) is used only by the deferred text-overflow clip path.
//   import { clearTmpModel, ListIterator } from '../../util/model';
//     → `model.clearTmpModel` (util/modelUtil.swift `enum model`) + top-level `ListIterator` (modelUtil.swift).
//   import { getECData } from '../../util/innerStore';           → `innerStore.getECData` (eventData wiring
//     is live below; see the `triggerEvent` block in `createMatrixCell`).
//   import { clone, retrieve2, isFunction, isString } from 'zrender/src/core/util';
//     → `retrieve2(a, b)` == `a != null ? a : b` (inlined `?? default` on the numeric reads);
//       `util.isFunction` / `util.isString`; `clone` used only by the deferred clip path.
//   import { formatTplSimple } from '../../util/format';         → `format.formatTplSimple`.
//   import { invert } from 'zrender/src/core/matrix';            → used only by the deferred clip path.
//   import { MatrixBodyCorner, MatrixBodyOrCornerKind } from '../../coord/matrix/MatrixBodyCorner';
//     → `MatrixBodyCorner` (coord/matrix sibling). PORT-NOTE: upstream is generic over the string-literal
//       `MatrixBodyOrCornerKind` ('body' | 'corner'); Swift has no string-literal generics, so the kind is a
//       plain `String` argument and `MatrixBodyCorner` is referenced non-generically (kind held internally).
//   import { setLabelStyle } from '../../label/labelStyle';
//     → `label/labelStyle.swift`. Cell labels are attached to their rect via setLabelStyle, including
//       inside positioning and the matrix cell's auto-overflow/layoutRect constraints.
//   import GlobalModel from '../../model/Global';                → `GlobalModel`.
//
//   The sibling coord/matrix types (assumed API, mirroring upstream MatrixDim.ts / MatrixBodyCorner.ts /
//   MatrixModel.ts / Matrix.ts — landed by the matrix-coord phase):
//     final class Matrix: CoordinateSystemMaster { func getRect() -> LayoutRect }
//     open class MatrixModel: ComponentModel {
//         var coordinateSystem: CoordinateSystemMaster!    // downcast to `Matrix`
//         func getDimensionModel(_ dim: String) -> MatrixDimensionModel   // 'x' | 'y'
//         func getBody() -> MatrixBodyCorner
//         func getCorner() -> MatrixBodyCorner
//         // inherits getShallow / get / getModel / componentIndex
//     }
//     open class MatrixDimensionModel: Model { var dim: MatrixDim }
//     final class MatrixDim {
//         var dim: String                 // 'x' | 'y'
//         var dimIdx: Int                 // 0 | 1
//         func shouldShow() -> Bool
//         func getUnitLayoutInfo(_ dimIdx: Int, _ locator: Double) -> MatrixCellLayoutInfo?
//         func getLayout(_ outRect: RectLike, _ dimIdx: Int, _ locator: Double)   // mutates outRect in place
//         func resetCellIterator(_ it: ListIterator<MatrixDimensionCell>?) -> ListIterator<MatrixDimensionCell>
//         func resetLayoutIterator(_ it: ListIterator<MatrixCellLayoutInfo>?, _ dimIdx: Int,
//                                  _ startLocator: Double?, _ count: Double?) -> ListIterator<MatrixCellLayoutInfo>
//     }
//     class MatrixCellLayoutInfo { var id: Point; var xy: Double; var wh: Double; var dim: MatrixDim; ... }
//     final class MatrixDimensionCell: MatrixCellLayoutInfo {
//         var span: Point; var option: [String: Any]; var rect: RectLike; ...
//     }
//     final class MatrixBodyCorner {
//         func getCell(_ xy: [Double]) -> MatrixBodyCornerCell?
//     }
//     final class MatrixBodyCornerCell {   // reference type — `inSpanOf` identity compared
//         var id: Point; var option: [String: Any]?; var inSpanOf: MatrixBodyCornerCell?;
//         var span: Point?; var spanRect: RectLike?; ...
//     }

// upstream: const round = Math.round;
// PORT-NOTE: JS `Math.round` rounds half toward +Infinity; replicated here with `floor(x + 0.5)` (CONVENTIONS §5).
private func round(_ x: Double) -> Double {
    return floor(x + 0.5)
}

// When special border style is defined on cell, it
// should be over all of the other borders.
// upstream: type Z2CellDefault = {normal: number, special: number};
private struct Z2CellDefault {
    var normal: Double
    var special: Double
}
private let Z2_BACKGROUND: Double = 0
private let Z2_OUTER_BORDER: Double = 99
private let Z2_BODY_CORNER_CELL_DEFAULT = Z2CellDefault(normal: 25, special: 100)
private let Z2_DIMENSION_CELL_DEFAULT = Z2CellDefault(normal: 50, special: 125)

// upstream: class MatrixView extends ComponentView { ... }
// CONVENTIONS §2/§4: reference type extending the reference `ComponentView` → `final class`.
public final class MatrixView: ComponentView {

    // upstream: static type = 'matrix';
    public static let matrixType = "matrix"
    // upstream: type = MatrixView.type;
    public let type = "matrix"

    // upstream: render(matrixModel: MatrixModel, ecModel: GlobalModel)
    //   The base `ComponentView.render` signature is (model, ecModel, api, payload); upstream declares
    //   only (matrixModel, ecModel). The override matches the full base signature and narrows `model` to
    //   `MatrixModel` (cf. CalendarView.render / SingleAxisView.render).
    public override func render(
        _ matrixModel: ComponentModel, _ ecModel: GlobalModel, _ api: ExtensionAPI, _ payload: Payload
    ) {
        let matrixModel = matrixModel as! MatrixModel

        _ = self.group.removeAll()

        let group = self.group
        let coordSys = matrixModel.coordinateSystem as! Matrix
        let rect = coordSys.getRect()
        let xDimModel = matrixModel.getDimensionModel("x")
        let yDimModel = matrixModel.getDimensionModel("y")
        // `dim` is IUO (`MatrixDim!`); annotate the `let` type so it doesn't infer Optional (IUO-to-let trap).
        let xDim: MatrixDim = xDimModel.dim
        let yDim: MatrixDim = yDimModel.dim

        // PENDING:
        //  reuse the existing text and rect elements for performance?

        renderDimensionCells(
            group,
            matrixModel,
            ecModel
        )

        createBodyAndCorner(
            group,
            matrixModel,
            xDim,
            yDim,
            ecModel
        )

        // upstream: const borderZ2Option = matrixModel.getShallow('borderZ2', true);
        //           const outerBorderZ2 = retrieve2(borderZ2Option, Z2_OUTER_BORDER);
        //   Read with `numOpt` (NOT a bare `as? Double`) — the Int-vs-Double option-read trap (CONVENTIONS
        //   trap #1); `retrieve2(a, b)` == `a != null ? a : b` → `?? default`.
        let outerBorderZ2 = numOpt(matrixModel.getShallow("borderZ2", true)) ?? Z2_OUTER_BORDER
        let dividerLineZ2 = outerBorderZ2 - 1

        // Outer border and overall background. Use separate elements because of z-order:
        // The overall background should appear below any other elements.
        // But in most cases, the outer border and the divider line should be above the normal cell borders -
        // especially when cell borders have different colors. But users may highlight some specific cells by
        // overstirking their border, in which case it should be above the outer border.
        // upstream: const bgStyle = matrixModel.getModel('backgroundStyle').getItemStyle(['borderWidth']);
        //           bgStyle.lineWidth = 0;
        var bgStyle = matrixModel.getModel("backgroundStyle").getItemStyle(["borderWidth"])
        bgStyle["lineWidth"] = 0.0
        // upstream: const borderStyle = matrixModel.getModel('backgroundStyle').getItemStyle(
        //             ['color', 'decal', 'shadowColor', 'shadowBlur', 'shadowOffsetX', 'shadowOffsetY']);
        //           borderStyle.fill = 'none';
        var borderStyle = matrixModel.getModel("backgroundStyle").getItemStyle(
            ["color", "decal", "shadowColor", "shadowBlur", "shadowOffsetX", "shadowOffsetY"]
        )
        borderStyle["fill"] = "none"
        let bgRect = createMatrixRect(rect.clone(), bgStyle, Z2_BACKGROUND)
        let borderRect = createMatrixRect(rect.clone(), borderStyle, outerBorderZ2)
        bgRect.silent = true
        borderRect.silent = true
        _ = group.add(bgRect)
        _ = group.add(borderRect)

        // Header split line.
        let xDimCell0 = xDim.getUnitLayoutInfo(0, 0)
        let yDimCell0 = yDim.getUnitLayoutInfo(1, 0)
        if xDimCell0 != nil && yDimCell0 != nil {
            if xDim.shouldShow() {
                var shape = LineShape()
                shape.x1 = rect.x
                shape.y1 = yDimCell0!.xy
                shape.x2 = rect.x + rect.width
                shape.y2 = yDimCell0!.xy
                _ = group.add(createMatrixLine(
                    shape,
                    xDimModel.getModel("dividerLineStyle").getLineStyle(),
                    dividerLineZ2
                ))
            }
            if yDim.shouldShow() {
                var shape = LineShape()
                shape.x1 = xDimCell0!.xy
                shape.y1 = rect.y
                shape.x2 = xDimCell0!.xy
                shape.y2 = rect.y + rect.height
                _ = group.add(createMatrixLine(
                    shape,
                    yDimModel.getModel("dividerLineStyle").getLineStyle(),
                    dividerLineZ2
                ))
            }
        }
    }
}

// upstream: function renderDimensionCells(group, matrixModel, ecModel): void
private func renderDimensionCells(_ group: Group, _ matrixModel: MatrixModel, _ ecModel: GlobalModel) {

    renderOnDimension(0)
    renderOnDimension(1)

    // upstream: function renderOnDimension(dimIdx: 0 | 1) { ... } (hoisted; modeled as a local closure).
    func renderOnDimension(_ dimIdx: Int) {
        // upstream: const thisDimModel = matrixModel.getDimensionModel(XY[dimIdx]);
        let thisDimModel = matrixModel.getDimensionModel(XY[dimIdx])
        let thisDim: MatrixDim = thisDimModel.dim   // IUO `MatrixDim!`; annotate so it doesn't infer Optional.

        if !thisDim.shouldShow() {
            return
        }

        let thisDimBgStyleModel = thisDimModel.getModel("itemStyle")
        let thisDimLabelModel = thisDimModel.getModel("label")
        let tooltipOption = matrixModel.getShallow("tooltip", true)

        // upstream: for (const it = thisDim.resetCellIterator(); it.next();)
        let it = thisDim.resetCellIterator(nil)
        while it.next() {
            let dimCell = it.item!
            // upstream: const shape = {} as RectLike; BoundingRect.copy(shape, dimCell.rect);
            let shape = BoundingRect(0, 0, 0, 0)
            shape.copy(dimCell.rect)

            // upstream: vectorUtil.set(xyLocator, dimCell.id.x, dimCell.id.y);
            let xyLocator: [Double] = [dimCell.id.x, dimCell.id.y]

            createMatrixCell(
                xyLocator,
                matrixModel,
                group,
                ecModel,
                dimCell.option,
                thisDimBgStyleModel,
                thisDimLabelModel,
                thisDimModel,
                shape,
                dimCell.option["value"],
                Z2_DIMENSION_CELL_DEFAULT,
                tooltipOption,
                dimIdx == 0 ? "x" : "y"
            )
        }
    }
}

// upstream: function createBodyAndCorner(group, matrixModel, xDim, yDim, ecModel): void
private func createBodyAndCorner(
    _ group: Group,
    _ matrixModel: MatrixModel,
    _ xDim: MatrixDim,
    _ yDim: MatrixDim,
    _ ecModel: GlobalModel
) {

    createBodyOrCornerCells("body", matrixModel.getBody(), xDim, yDim)
    if xDim.shouldShow() && yDim.shouldShow() {
        createBodyOrCornerCells("corner", matrixModel.getCorner(), yDim, xDim)
    }

    // upstream: function createBodyOrCornerCells<TBodyOrCornerKind>(
    //     bodyCornerOptionRoot, bodyOrCorner, dimForCoordX, dimForCoordY): void
    //   PORT-NOTE: the string-literal generic `TBodyOrCornerKind` ('body' | 'corner') is dropped — the kind
    //     is a plain `String` and `MatrixBodyCorner` is referenced non-generically (CONVENTIONS §2).
    func createBodyOrCornerCells(
        _ bodyCornerOptionRoot: String,
        _ bodyOrCorner: MatrixBodyCorner,
        _ dimForCoordX: MatrixDim,   // Can be `matrix.y` (transposed) for corners.
        _ dimForCoordY: MatrixDim    // Can be `matrix.x` (trnasposed) for corners.
    ) {
        // Prevent inheriting from ancestor.
        let parentCellModel = Model(matrixModel.getShallow(bodyCornerOptionRoot, true))
        let parentItemStyleModel = parentCellModel.getModel("itemStyle")
        let parentLabelModel = parentCellModel.getModel("label")

        let itx = ListIterator<MatrixCellLayoutInfo>()
        let ity = ListIterator<MatrixCellLayoutInfo>()
        let tooltipOption = matrixModel.getShallow("tooltip", true)

        // upstream: for (dimForCoordY.resetLayoutIterator(ity, 1); ity.next();)
        _ = dimForCoordY.resetLayoutIterator(ity, 1, nil, nil)
        while ity.next() {
            // upstream: for (dimForCoordX.resetLayoutIterator(itx, 0); itx.next();)
            _ = dimForCoordX.resetLayoutIterator(itx, 0, nil, nil)
            while itx.next() {
                let xLayout = itx.item!
                let yLayout = ity.item!

                // upstream: vectorUtil.set(xyLocator, xLayout.id.x, yLayout.id.y);
                let xyLocator: [Double] = [xLayout.id.x, yLayout.id.y]
                let bodyCornerCell = bodyOrCorner.getCell(xyLocator)

                // If in span of an other body or corner cell, never render it.
                if let cell = bodyCornerCell, let inSpanOf = cell.inSpanOf, inSpanOf !== cell {
                    continue
                }

                // upstream: const shape = {} as RectLike;
                let shape = BoundingRect(0, 0, 0, 0)
                if let cell = bodyCornerCell, cell.span != nil {
                    // upstream: BoundingRect.copy(shape, bodyCornerCell.spanRect);
                    shape.copy(cell.spanRect!)
                }
                else {
                    // upstream: xLayout.dim.getLayout(shape, 0, xyLocator[0]);
                    //           yLayout.dim.getLayout(shape, 1, xyLocator[1]);
                    xLayout.dim.getLayout(shape, 0, xyLocator[0])
                    yLayout.dim.getLayout(shape, 1, xyLocator[1])
                }

                let bodyCornerCellOption = bodyCornerCell != nil ? bodyCornerCell!.option : nil

                createMatrixCell(
                    xyLocator,
                    matrixModel,
                    group,
                    ecModel,
                    bodyCornerCellOption,
                    parentItemStyleModel,
                    parentLabelModel,
                    parentCellModel,
                    shape,
                    bodyCornerCellOption != nil ? bodyCornerCellOption!["value"] : nil,
                    Z2_BODY_CORNER_CELL_DEFAULT,
                    tooltipOption,
                    bodyCornerOptionRoot
                )
            }
        }
    } // End of createBodyOrCornerCells
}

// upstream: type MatrixTargetType = 'x' | 'y' | 'body' | 'corner';

// upstream: function createMatrixCell(xyLocator, matrixModel, group, ecModel, cellOption, parentItemStyleModel,
//     parentLabelModel, parentCellModel, shape, textValue, zrCellDefault, tooltipOption, targetType): void
private func createMatrixCell(
    _ xyLocator: [Double],
    _ matrixModel: MatrixModel,
    _ group: Group,
    _ ecModel: GlobalModel,
    _ cellOption: [String: Any]?,
    _ parentItemStyleModel: Model,
    _ parentLabelModel: Model,
    _ parentCellModel: Model,
    _ shape: RectLike,
    _ textValue: Any?,
    _ zrCellDefault: Z2CellDefault,
    _ tooltipOption: Any?,
    _ targetType: String   // MatrixTargetType
) {
    // Do not use getModel - a quick performance optimization.
    _tmpCellItemStyleModel.option = cellOption != nil ? cellOption!["itemStyle"] : nil
    _tmpCellItemStyleModel.parentModel = parentItemStyleModel
    _tmpCellModel.option = cellOption
    _tmpCellModel.parentModel = parentCellModel

    // Use different z2 because special border may be defined in itemStyle.
    // upstream: const z2 = retrieve2(_tmpCellModel.getShallow('z2'),
    //     (cellOption && cellOption.itemStyle) ? zrCellDefault.special : zrCellDefault.normal);
    let z2 = numOpt(_tmpCellModel.getShallow("z2"))
        ?? ((cellOption != nil && cellOption!["itemStyle"] != nil) ? zrCellDefault.special : zrCellDefault.normal)
    // upstream: const tooltipOptionShow = tooltipOption && tooltipOption.show;
    //   `tooltipOption` is the dynamic `[String: Any]` bag; read `.show` with JS-truthiness. Used below to
    //   decide the attached label's `silent`.
    let tooltipOptionShow = jsTruthy((tooltipOption as? [String: Any])?["show"])

    let cellRect = createMatrixRect(shape, _tmpCellItemStyleModel.getItemStyle(), z2)
    _ = group.add(cellRect)

    // upstream: const cursorOption = _tmpCellModel.get('cursor'); if (cursorOption != null) { cellRect.attr('cursor', ...) }
    if let cursorOption = _tmpCellModel.get("cursor") as? String {
        cellRect.cursor = cursorOption
    }

    // upstream: let cellText: Text | NullUndefined;  (held so silent/eventData below can reference it).
    var cellText: ZRText? = nil

    if textValue != nil {
        // upstream: let text = textValue + '';
        var text = stringify(textValue!)
        _tmpCellLabelModel.option = cellOption != nil ? cellOption!["label"] : nil
        _tmpCellLabelModel.parentModel = parentLabelModel
        // This is to accept `option.textStyle` as the default.
        _tmpCellLabelModel.ecModel = ecModel

        let formatter = _tmpCellLabelModel.getShallow("formatter")
        if jsTruthy(formatter) {
            let params: [String: Any] = [
                "componentType": "matrix",
                "componentIndex": matrixModel.componentIndex,
                "name": text,
                "value": textValue!,
                "coord": xyLocator
            ]
            if util.isString(formatter), let tpl = formatter as? String {
                text = format.formatTplSimple(tpl, params)
            }
            else if let formatter = formatter as? ([String: Any]) -> String {
                text = formatter(params)
            }
        }

        // Keep the label in the cell's exact layout rect. Matrix's default overflow/lineOverflow then
        // prevents dense nested headers from painting over adjacent cells.
        let labelLayoutRect = BoundingRect(shape.x, shape.y, shape.width, shape.height)
        var labelOpt = SetLabelStyleOpt()
        labelOpt.defaultText = text
        labelOpt.autoOverflowArea = true
        labelOpt.layoutRect = labelLayoutRect
        labelStyle.setLabelStyle(cellRect, [.normal: _tmpCellLabelModel], labelOpt)
        cellText = cellRect.getTextContent()
        if let cellText = cellText {
            cellText.z2 = z2 + 1
        }

        // upstream: setTooltipConfig({ // At least for text overflow.
        //     el: cellRect, componentModel: matrixModel, itemName: text, itemTooltipOption: tooltipOption,
        //     formatterParamsExtra: { xyLocator: xyLocator.slice() } });
        //   `xyLocator.slice()` is a defensive copy of the caller's array; Swift arrays are value types, so
        //   passing `xyLocator` is already a copy.
        //   `itemTooltipOption` is the dynamic `[String: Any]` bag (`matrixModel.getShallow('tooltip', true)`);
        //   `util/graphic.setTooltipConfig` bridges that bag onto `CommonTooltipOption` so the user's
        //   `matrix.tooltip` (formatter, backgroundColor, ...) reaches `ecData.tooltipConfig.option.common`
        //   exactly like upstream's `defaults(..., itemTooltipOptionObj)`.
        //   PORT-NOTE: upstream types the locator as `MatrixXYLocator[]` (integer locators); this port carries
        //   it as `[Double]`, and it is appended to `formatterParams.$vars`, hence user-visible through
        //   `format.formatTpl` aliases — so it is coerced back to `Int` here to avoid rendering `1.0` for `1`.
        setTooltipConfig(
            el: cellRect,
            componentModel: matrixModel,
            itemName: text,
            itemTooltipOption: tooltipOption,
            formatterParamsExtra: ["xyLocator": xyLocator.map { Int($0) }]
        )
    }

    // Set silent
    // upstream: const triggerEvent = matrixModel.get('triggerEvent', true);
    let triggerEvent = jsTruthy(matrixModel.get("triggerEvent", true))

    // upstream: if (cellText) { let labelSilent = _tmpCellLabelModel.get('silent');
    //     if (labelSilent == null) { labelSilent = !(triggerEvent || tooltipOptionShow); }
    //     cellText.silent = labelSilent; cellText.ignoreHostSilent = true; }
    //   By default, silent: false is needed for triggerEvent or tooltip interaction.
    if let cellText = cellText {
        var labelSilent = _tmpCellLabelModel.get("silent") as? Bool
        if labelSilent == nil {
            labelSilent = !(triggerEvent || tooltipOptionShow)
        }
        cellText.silent = labelSilent!
        cellText.ignoreHostSilent = true
    }

    // upstream: let rectSilent = _tmpCellModel.get('silent'); if (rectSilent == null) { rectSilent = (
    //     !cellRect.style || cellRect.style.fill === 'none' || !cellRect.style.fill); }
    var rectSilent = _tmpCellModel.get("silent") as? Bool
    if rectSilent == nil {
        // If no background color in cell, set `rect.silent: false` will cause that only
        // the border response to mouse hovering, which is probably weird.
        // So we deliberately make rect non-interactive if `silent` is not explicitly specified,
        // even if `triggerEvent` is set as `true`.
        // upstream: rectSilent = (!cellRect.style || cellRect.style.fill === 'none' || !cellRect.style.fill);
        //   `ZRColor` is not Equatable — pattern-match instead. `!fill` (falsy) covers nil / '' (empty
        //   string); a gradient/pattern fill is truthy → not silent.
        let style: PathStyleProps? = cellRect.pathStyle
        if style == nil {
            rectSilent = true
        }
        else if let fill = style!.fill {
            if case let .string(fs) = fill {
                rectSilent = (fs == "none" || fs.isEmpty)
            }
            else {
                rectSilent = false
            }
        }
        else {
            rectSilent = true
        }
    }
    cellRect.silent = rectSilent!

    // Both `cellRect` (typically non-transparent) and `cellText` may trigger events, depending on both
    // `matrix.triggerEvent`, `matrix.xxx.silent` and `matrix.xxx.label.silent` settings.
    // upstream: if (triggerEvent && cellRect) { const eventData = {...}; getECData(cellRect).eventData = eventData; }
    if triggerEvent {
        var eventData: ECEventData = [
            "componentType": "matrix",
            "componentIndex": matrixModel.componentIndex,
            "matrixIndex": matrixModel.componentIndex,
            "targetType": targetType,
            // upstream: coord: xyLocator.slice()  (Swift arrays are value types → already a copy).
            "coord": xyLocator
        ]
        // upstream: name: (cellText && cellText.style) ? cellText.style.text : undefined
        //   (`ZRText.style` is exposed as `.textStyle` by ZRenderKit's typed-style split).
        if let name = cellText?.textStyle?.text {
            eventData["name"] = name
        }
        // upstream: value: textValue
        if let value = textValue {
            eventData["value"] = value
        }
        innerStore.getECData(cellRect).eventData = eventData
    }

    model.clearTmpModel(_tmpCellModel)
    model.clearTmpModel(_tmpCellItemStyleModel)
    model.clearTmpModel(_tmpCellLabelModel)
}
// upstream: const _tmpCellModel = new Model(); const _tmpCellItemStyleModel = new Model();
//           const _tmpCellLabelModel = new Model(); const _tmpInnerTextTrans: number[] = [];
private let _tmpCellModel = Model()
private let _tmpCellItemStyleModel = Model()
private let _tmpCellLabelModel = Model()
// `_tmpInnerTextTrans` is used only by the deferred text-overflow clip path — omitted.

// FIXME: move all of the subpixel process to Matrix.ts resize, otherwise the result of
// `dataToLayout` is not consistent with this rendering, and the caller (like heatmap) can
// not precisely align with the matrix border.
// upstream: function createMatrixRect(shape: RectShape, style: ItemStyleProps, z2: number): Rect
//   `shape` is passed as a `RectLike` (BoundingRect) here; upstream mutates it in place (subpixel), then
//   `new Rect({shape})`. The in-place mutation is preserved (BoundingRect is a reference type) so the caller
//   reads the optimized rect (also used as the attached label's layoutRect). `style` is the dynamic `[String: Any]`
//   itemStyle bag, bridged to `PathStyleProps` via `matrixPathStyleFromDict`.
private func createMatrixRect(_ shape: RectLike, _ style: [String: Any], _ z2: Double) -> Rect {
    // Currently `subPixelOptimizeRect` can not be used here because it will break rect alignment.
    // Optimize line and rect with the same direction.
    // upstream: const lineWidth = style.lineWidth;
    //   Read with `numOpt` (NOT a bare `as? Double`) — the Int-vs-Double option-read trap (CONVENTIONS trap #1).
    let lineWidth = numOpt(style["lineWidth"])
    if let lw = lineWidth, lw != 0 {
        let x2Original = shape.x + shape.width
        let y2Original = shape.y + shape.height
        shape.x = subPixelOptimizeNS.subPixelOptimize(shape.x, lw, true)
        shape.y = subPixelOptimizeNS.subPixelOptimize(shape.y, lw, true)
        shape.width = subPixelOptimizeNS.subPixelOptimize(x2Original, lw, true) - shape.x
        shape.height = subPixelOptimizeNS.subPixelOptimize(y2Original, lw, true) - shape.y
    }
    var rectShape = RectShape()
    rectShape.x = shape.x
    rectShape.y = shape.y
    rectShape.width = shape.width
    rectShape.height = shape.height
    let rect = Rect(["shape": rectShape as PathShape])
    rect.useStyle(matrixPathStyleFromDict(style))
    rect.z2 = z2
    return rect
}

// upstream: function createMatrixLine(shape: Omit<LineShape, 'percent'>, style: LineStyleProps, z2: number): Line
private func createMatrixLine(_ shapeIn: LineShape, _ style: [String: Any], _ z2: Double) -> Line {
    var shape = shapeIn
    // upstream: const lineWidth = style.lineWidth;
    let lineWidth = numOpt(style["lineWidth"])
    if let lw = lineWidth, lw != 0 {
        if round(shape.x1 * 2) == round(shape.x2 * 2) {
            let v = subPixelOptimizeNS.subPixelOptimize(shape.x1, lw, true)
            shape.x1 = v
            shape.x2 = v
        }
        if round(shape.y1 * 2) == round(shape.y2 * 2) {
            let v = subPixelOptimizeNS.subPixelOptimize(shape.y1, lw, true)
            shape.y1 = v
            shape.y2 = v
        }
    }
    let line = Line([
        "shape": shape as PathShape,
        "silent": true
    ])
    line.useStyle(matrixPathStyleFromDict(style))
    line.z2 = z2
    return line
}

// export default MatrixView;  → `public final class MatrixView` above.


// ============================================================================
// PORT-NOTE helpers — NOT part of MatrixView.ts upstream. They reproduce the
// `XY` util/graphic sibling, the dynamic-option-read coercions, the JS `+x`
// stringify, and the `util/graphic` style-bag → PathStyleProps bridge referenced
// above so the table cells / dividers are actually drawn. Delete each when its
// real sibling lands (util/graphic `XY` + `useStyle(dict)` bridge, label/labelStyle)
// and call it directly. (Mirrors the file-private helpers in CalendarView /
// SingleAxisView.)
// ============================================================================

// upstream: import { XY } from '../../util/graphic';  (== ['x', 'y'])
//   PORT-NOTE (deferred): requires shared `util/graphic.XY` (== ['x','y']), not yet in util/graphic.swift.
//   Referenced here as a file-private constant until it lands, then delete this and import it.
private let XY: [String] = ["x", "y"]

/// Coerce a dynamic option value to Double, tolerating the Int boxing that `[String: Any]` defaultOption
/// literals use (e.g. a bare `"borderWidth": 1`). A bare `as? Double` returns nil on an Int, silently
/// dropping the value — the recurring Int-vs-Double option-read trap (CONVENTIONS trap #1).
private func numOpt(_ v: Any?) -> Double? {
    if let d = v as? Double { return d }
    if let i = v as? Int { return Double(i) }
    if let n = v as? NSNumber, !(n === kCFBooleanTrue || n === kCFBooleanFalse) { return n.doubleValue }
    return nil
}

/// JS truthiness for the dynamic option bag (`if (formatter)` on `getShallow(...)` results); mirrors the
/// same file-private helper in CalendarView/SingleAxisView (CONVENTIONS §6).
private func jsTruthy(_ v: Any?) -> Bool {
    guard let v = v, !(v is NSNull) else { return false }
    if let b = v as? Bool { return b }
    if let d = v as? Double { return d != 0 && !d.isNaN }
    if let i = v as? Int { return i != 0 }
    if let s = v as? String { return !s.isEmpty }
    if let a = v as? [Any] { return !a.isEmpty }
    return true
}

/// Reproduce JS `value + ''` stringification for a cell's `value` (a String in normal matrix option, but
/// tolerating numbers from series-collected ordinals). Mirrors the `textValue + ''` upstream.
private func stringify(_ v: Any) -> String {
    // A series-auto-collected matrix category can be a BOXED Swift Optional (`Any` wrapping `String?`),
    //   so a plain `v as? String` misses and the value stringifies as `Optional("amount")`. Unwrap first
    //   (same fix as Ordinal.getLabel's `ordinalUnwrapAny`).
    let v = ordinalUnwrapAny(v)
    if let s = v as? String { return s }
    if let d = v as? Double {
        // JS number→string: integral doubles print without a trailing ".0".
        if d == d.rounded() && d.isFinite { return String(Int(d)) }
        return String(d)
    }
    if let i = v as? Int { return String(i) }
    if let b = v as? Bool { return b ? "true" : "false" }
    return "\(v)"
}

/// PORT-NOTE (deferred): requires `util/graphic`'s `useStyle(dict)` bridge, not ported. Map the dynamic style bag
///   ([String: Any] — the `getItemStyle()` / `getLineStyle()` result) onto the typed `PathStyleProps`.
///   Same deviation as CalendarView.calendarPathStyleFromDict / SingleAxisView.pathStyleFromDict; numbers are
///   read via `numOpt` (Int|Double|NSNumber) to avoid the Int-drop trap. Delete when the graphic bridge lands.
private func matrixPathStyleFromDict(_ dict: [String: Any]) -> PathStyleProps {
    var s = PathStyleProps()
    // `fill`/`stroke` may be a solid string, an EChartsKit `ZRColor`, or a gradient dict; the shared
    //   `zrPaintFromStyleValue` bridges all three (the sentinel 'none' stays a no-paint string).
    if let v = zrPaintFromStyleValue(dict["fill"]) { s.fill = v }
    if let v = zrPaintFromStyleValue(dict["stroke"]) { s.stroke = v }
    if let v = numOpt(dict["lineWidth"]) { s.lineWidth = v }
    if let v = dict["lineCap"] as? String { s.lineCap = v }
    if let v = dict["lineJoin"] as? String { s.lineJoin = v }
    if let v = numOpt(dict["miterLimit"]) { s.miterLimit = v }
    if let v = numOpt(dict["opacity"]) { s.opacity = v }
    if let v = numOpt(dict["fillOpacity"]) { s.fillOpacity = v }
    if let v = numOpt(dict["strokeOpacity"]) { s.strokeOpacity = v }
    if let v = numOpt(dict["shadowBlur"]) { s.shadowBlur = v }
    if let v = dict["shadowColor"] as? String { s.shadowColor = v }
    if let v = numOpt(dict["shadowOffsetX"]) { s.shadowOffsetX = v }
    if let v = numOpt(dict["shadowOffsetY"]) { s.shadowOffsetY = v }
    if let v = numOpt(dict["lineDashOffset"]) { s.lineDashOffset = v }
    // PORT-NOTE (deferred): `lineDash` (number[] | false) / `decal` mapping deferred.
    return s
}
