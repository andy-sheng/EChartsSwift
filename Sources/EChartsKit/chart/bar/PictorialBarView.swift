// Ported from echarts/src/chart/bar/PictorialBarView.ts — keep in sync with upstream
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
//   import * as zrUtil from 'zrender/src/core/util';                 -> `util.*` (ZRenderKit).
//   import * as graphic from '../../util/graphic';                   -> `Group`/`Rect`/`Circle` (ZRenderKit) +
//       `initProps`/`updateProps`/`removeElement` (animation/basicTransition.swift).
//   import { toggleHoverEmphasis } from '../../util/states';         -> `states.toggleHoverEmphasis`.
//   import {createSymbol, normalizeSymbolOffset} from '../../util/symbol';  -> `symbol.createSymbol` / `symbol.normalizeSymbolOffset`.
//   import {parsePercent, isNumeric} from '../../util/number';       -> `number.parsePercent` / `number.isNumeric`.
//   import ChartView from '../../view/Chart';                        -> `ChartView`.
//   import PictorialBarSeriesModel from './PictorialBarSeries';      -> `PictorialBarSeriesModel`.
//   import ExtensionAPI / SeriesData / GlobalModel / Model / util/types / Cartesian2D / Axis2D    -> ported peers.
//   import { getDefaultLabel } from '../helper/labelHelper';         -> `labelHelper.getDefaultLabel`.
//   import { setLabelStyle, getLabelStatesModels } from '../../label/labelStyle';  -> `labelStyle.*`.
//   import ZRImage from 'zrender/src/graphic/Image';                 -> `ZRenderKit.ZRImage`. `symbol.createSymbol`
//       emits one for an `image://` symbol (via graphic.makeImage), so the ZRImage branch in updateCommon is live.
//   import { getECData } from '../../util/innerStore';               -> `innerStore.getECData`.
//   import { createClipPath } from '../helper/createClipPathFromCoordSys';  -> `createClipPath`.
//   import { SERIES_TYPE_PICTORIAL_BAR } from '../../layout/barCommon';  -> `SERIES_TYPE_PICTORIAL_BAR`.
//   import { symbolVisual } from visual/symbol.ts — the symbol-visual stages are run inline from render
//       (the port invokes visual stages from the view; see ScatterView / slim-visual-stage-ordering).

// upstream: const BAR_BORDER_WIDTH_QUERY = ['itemStyle', 'borderWidth'];
private let PB_BAR_BORDER_WIDTH_QUERY = ["itemStyle", "borderWidth"]

// upstream:
//   const LAYOUT_ATTRS = [
//     {xy: 'x', wh: 'width', index: 0, posDesc: ['left', 'right']},
//     {xy: 'y', wh: 'height', index: 1, posDesc: ['top', 'bottom']}
//   ] as const;  // index: +isHorizontal
struct PBLayoutAttr {
    let xy: String
    let wh: String
    let index: Int
    let posDesc: [String]
}
private let PB_LAYOUT_ATTRS: [PBLayoutAttr] = [
    PBLayoutAttr(xy: "x", wh: "width", index: 0, posDesc: ["left", "right"]),
    PBLayoutAttr(xy: "y", wh: "height", index: 1, posDesc: ["top", "bottom"])
]

// upstream: const pathForLineWidth = new graphic.Circle();  (a scratch path used only to compute the
//   scaled lineWidth in prepareLineWidth — see below).
private let pbPathForLineWidth = Circle()

// upstream `type ItemModel` monkeypatches getAnimationDelayParams / isAnimationEnabled onto the item model.
//   `getAnimationDelayParams` IS assigned (the optional stored closure on `Model`, see pbGetItemModel);
//   `isAnimationEnabled` is computed inline instead (see getSymbolMeta).

// upstream: interface SymbolMeta { ... }  — the per-bar computed layout bundle. Modeled as a reference
//   class so the several `prepare*` free functions can fill it incrementally (upstream mutates one object).
final class PBSymbolMeta {
    var dataIndex: Int = 0

    var symbolPatternSize: Double = 2
    var symbolType: String = "circle"
    var symbolMargin: Double = 0
    var symbolSize: [Double] = [0, 0]
    var symbolScale: [Double] = [0, 0]
    var symbolRepeat: Any?
    var symbolClip: Bool = false
    var symbolRepeatDirection: String?

    // layout is the per-item rect layout bag (x/y/width/height), read from data.getItemLayout.
    var layout: [String: Double] = [:]

    var repeatTimes: Double = 0

    var rotation: Double = 0

    var pathPosition: [Double] = [0, 0]
    var bundlePosition: [Double] = [0, 0]

    var pxSign: Double = 1

    var barRectShape: RectShape = RectShape()
    var clipShape: [String: Double] = [:]

    var boundingLength: Double = 0
    var repeatCutLength: Double = 0

    var valueLineWidth: Double = 0

    var style: Any?
    var z2: Double = 0

    var itemModel: Model!

    var animationModel: Model?

    var hoverScale: Bool = false
}

// upstream: interface CreateOpts { ecSize; seriesModel; coordSys; coordSysExtent; isHorizontal; valueDim; categoryDim }
struct PBCreateOpts {
    let ecWidth: Double
    let ecHeight: Double
    let seriesModel: PictorialBarSeriesModel
    let coordSys: Cartesian2D
    let coordSysExtent: [[Double]]
    let isHorizontal: Bool
    let valueDim: PBLayoutAttr
    let categoryDim: PBLayoutAttr

    // upstream indexes `opt.ecSize[categoryDim.wh]`; provide the same string-keyed access.
    func ecSize(_ wh: String) -> Double { wh == "width" ? ecWidth : ecHeight }
}

// upstream: interface PictorialBarElement extends graphic.Group { __pictorialBundle; __pictorialShapeStr;
//   __pictorialSymbolMeta; __pictorialMainPath; __pictorialBarRect; __pictorialClipPath }
//   Swift can not add stored properties to `Group`, so a dedicated subclass carries the `__pictorial*` slots.
final class PictorialBarElement: Group {
    var __pictorialBundle: Group!
    var __pictorialShapeStr: String = ""
    var __pictorialSymbolMeta: PBSymbolMeta!
    // upstream `PictorialSymbol` (a SymbolClz). Typed `Displayable` here because an `image://` symbol is a
    //   ZRImage (not a Path) — see pbCreatePath. Only Element/Displayable-level ops are used on it.
    var __pictorialMainPath: Displayable?
    var __pictorialBarRect: Rect?
    var __pictorialClipPath: Rect?
}

// upstream: class PictorialBarView extends ChartView
open class PictorialBarView: ChartView {
    // upstream: static readonly type = SERIES_TYPE_PICTORIAL_BAR;  readonly type = SERIES_TYPE_PICTORIAL_BAR;
    public static let pictorialBarType = SERIES_TYPE_PICTORIAL_BAR
    open override var type: String {
        get { SERIES_TYPE_PICTORIAL_BAR }
        set { /* readonly upstream */ }
    }

    private var _data: SeriesData?

    open override func render(
        _ seriesModel: SeriesModel, _ ecModel: GlobalModel, _ api: ExtensionAPI, _ payload: Payload
    ) {
        let seriesModel = seriesModel as! PictorialBarSeriesModel
        let group = self.group
        let data = seriesModel.getData()
        let oldData = self._data

        // Symbol-visual stages (visual/symbol.ts): populate the per-item symbol / symbolSize visuals from
        //   the series option, which getSymbolMeta reads. Run inline here (the port invokes visual stages
        //   from the view — see ScatterView / slim-visual-stage-ordering).
        symbolVisual.seriesSymbolTask(seriesModel, ecModel)
        symbolVisual.dataSymbolTask(seriesModel)

        guard let cartesian = seriesModel.coordinateSystem as? Cartesian2D else {
            return
        }
        let baseAxis = cartesian.getBaseAxis()
        let isHorizontal = baseAxis.isHorizontal()
        // upstream: const coordSysRect = cartesian.master.getRect();
        //   `master` is typed `CoordinateSystemMaster?`; its optional `getRect` is not witnessed by
        //   `Grid.getRect()` — narrow to `Grid` (same pattern as barGrid.swift).
        guard let master = cartesian.master as? Grid else { return }
        let coordSysRect = master.getRect()

        let opt = PBCreateOpts(
            ecWidth: api.getWidth(),
            ecHeight: api.getHeight(),
            seriesModel: seriesModel,
            coordSys: cartesian,
            coordSysExtent: [
                [coordSysRect.x, coordSysRect.x + coordSysRect.width],
                [coordSysRect.y, coordSysRect.y + coordSysRect.height]
            ],
            isHorizontal: isHorizontal,
            valueDim: PB_LAYOUT_ATTRS[isHorizontal ? 1 : 0],
            categoryDim: PB_LAYOUT_ATTRS[1 - (isHorizontal ? 1 : 0)]
        )

        data.diff(oldData)
            .add({ dataIndex in
                if !data.hasValue(dataIndex) {
                    return
                }
                let itemModel = pbGetItemModel(data, dataIndex)
                let symbolMeta = pbGetSymbolMeta(data, dataIndex, itemModel, opt)

                let bar = pbCreateBar(data, opt, symbolMeta, false)

                data.setItemGraphicEl(dataIndex, bar)
                _ = group.add(bar)

                pbUpdateCommon(bar, opt, symbolMeta)
            })
            .update({ newIndex, oldIndex in
                var bar = oldData?.getItemGraphicEl(oldIndex) as? PictorialBarElement

                if !data.hasValue(newIndex) {
                    if let bar = bar { _ = group.remove(bar) }
                    return
                }

                let itemModel = pbGetItemModel(data, newIndex)
                let symbolMeta = pbGetSymbolMeta(data, newIndex, itemModel, opt)

                let pictorialShapeStr = pbGetShapeStr(data, symbolMeta)
                if let b = bar, pictorialShapeStr != b.__pictorialShapeStr {
                    _ = group.remove(b)
                    data.setItemGraphicEl(newIndex, nil)
                    bar = nil
                }

                let finalBar: PictorialBarElement
                if let b = bar {
                    pbUpdateBar(b, opt, symbolMeta)
                    finalBar = b
                }
                else {
                    finalBar = pbCreateBar(data, opt, symbolMeta, true)
                }

                data.setItemGraphicEl(newIndex, finalBar)
                finalBar.__pictorialSymbolMeta = symbolMeta
                // Add back
                _ = group.add(finalBar)

                pbUpdateCommon(finalBar, opt, symbolMeta)
            })
            .remove({ dataIndex in
                // upstream: `const bar = oldData.getItemGraphicEl(dataIndex); bar && removeBar(oldData, ...)`
                //   `dataIndex` here is an OLD-data index, so the removal (including
                //   `setItemGraphicEl(dataIndex, nil)`) must be applied to `oldData`, not `data`.
                if let oldData = oldData,
                   let bar = oldData.getItemGraphicEl(dataIndex) as? PictorialBarElement {
                    pbRemoveBar(oldData, dataIndex, bar.__pictorialSymbolMeta?.animationModel, bar)
                }
            })
            .execute()

        // Do clipping. pictorialBar clip defaults to false.
        let clipPath: Path? = ((seriesModel.get("clip", true) as? Bool) ?? false)
            ? createClipPath(seriesModel.coordinateSystem, false, seriesModel)
            : nil
        if let clipPath = clipPath {
            group.setClipPath(clipPath)
        }
        else {
            group.removeClipPath()
        }

        self._data = data
    }

    open override func remove(_ ecModel: GlobalModel, _ api: ExtensionAPI) {
        let group = self.group
        let data = self._data
        // Global default is the JS-truthy string "auto", not a Bool. A Bool-only cast skipped the
        // official scale-to-zero leave transition when a legend hid the pictorial series.
        if pbTruthy(ecModel.get("animation")) {
            if let data = data {
                data.eachItemGraphicEl({ el, _ in
                    if let bar = el as? PictorialBarElement {
                        let dataIndex = innerStore.getECData(bar).dataIndex.map { Int($0) } ?? -1
                        pbRemoveBar(data, dataIndex, ecModel, bar)
                    }
                })
            }
        }
        else {
            _ = group.removeAll()
        }
    }
}

// ================================================================================================
// Free helpers — upstream module-level functions. Prefixed `pb` to avoid basename/symbol collisions.
// ================================================================================================

// upstream: `!!value` JS truthiness for symbolRepeat / boundingData etc.
private func pbTruthy(_ v: Any?) -> Bool {
    guard let v = v else { return false }
    if v is NSNull { return false }
    if let b = v as? Bool { return b }
    if let d = v as? Double { return d != 0 }
    if let i = v as? Int { return i != 0 }
    if let s = v as? String { return !s.isEmpty }
    if let arr = v as? [Any] { return !arr.isEmpty }
    return true
}

// defaultOption numbers may box as Int OR Double (int-vs-double trap). Coerce to Double.
private func pbDouble(_ v: Any?) -> Double? {
    if let d = v as? Double { return d }
    if let i = v as? Int { return Double(i) }
    if let f = v as? Float { return Double(f) }
    if let b = v as? Bool { return b ? 1 : 0 }
    if let s = v as? String, let d = Double(s) { return d }
    return nil
}

// Set or calculate default value about symbol, and calculate layout info.
// upstream: function getSymbolMeta(data, dataIndex, itemModel, opt): SymbolMeta
func pbGetSymbolMeta(
    _ data: SeriesData, _ dataIndex: Int, _ itemModel: Model, _ opt: PBCreateOpts
) -> PBSymbolMeta {
    // upstream reads `data.getItemLayout(dataIndex)` as the rect layout bag (x/y/width/height).
    let layoutBag = (data.getItemLayout(dataIndex) as? [String: Any]) ?? [:]
    var layout: [String: Double] = [:]
    for k in ["x", "y", "width", "height"] {
        layout[k] = pbDouble(layoutBag[k]) ?? Double.nan
    }

    let symbolRepeatRaw = itemModel.get("symbolRepeat")
    let symbolRepeat: Any? = (symbolRepeatRaw is NSNull) ? nil : symbolRepeatRaw
    let symbolClip = (itemModel.get("symbolClip") as? Bool) ?? false
    let symbolPosition = (itemModel.get("symbolPosition") as? String) ?? "start"
    let symbolRotate = pbDouble(itemModel.get("symbolRotate"))
    let rotation = (symbolRotate ?? 0) * Double.pi / 180
    let symbolPatternSize = pbDouble(itemModel.get("symbolPatternSize")) ?? 2
    // upstream itemModel.isAnimationEnabled() = parentModel.isAnimationEnabled() && !!getShallow('animation').
    let isAnimationEnabled = ((opt.seriesModel.isAnimationEnabled() ?? false)
        && pbTruthy(itemModel.getShallow("animation")))

    let symbolMeta = PBSymbolMeta()
    symbolMeta.dataIndex = dataIndex
    symbolMeta.layout = layout
    symbolMeta.itemModel = itemModel
    symbolMeta.symbolType = (data.getItemVisual(dataIndex, "symbol") as? String) ?? "circle"
    symbolMeta.style = data.getItemVisual(dataIndex, "style")
    symbolMeta.symbolClip = symbolClip
    symbolMeta.symbolRepeat = symbolRepeat
    symbolMeta.symbolRepeatDirection = itemModel.get("symbolRepeatDirection") as? String
    symbolMeta.symbolPatternSize = symbolPatternSize
    symbolMeta.rotation = rotation
    symbolMeta.animationModel = isAnimationEnabled ? itemModel : nil
    symbolMeta.hoverScale = isAnimationEnabled && ((itemModel.get(["emphasis", "scale"]) as? Bool) ?? false)
    symbolMeta.z2 = pbDouble(itemModel.getShallow("z", true)) ?? 0

    pbPrepareBarLength(itemModel, symbolRepeat, layout, opt, symbolMeta)

    pbPrepareSymbolSize(
        data, dataIndex, layout, symbolRepeat, symbolMeta.boundingLength,
        symbolMeta.pxSign, symbolPatternSize, opt, symbolMeta
    )

    pbPrepareLineWidth(itemModel, symbolMeta.symbolScale, rotation, opt, symbolMeta)

    let symbolSize = symbolMeta.symbolSize
    let symbolOffset = symbol.normalizeSymbolOffset(itemModel.get("symbolOffset"), symbolSize)

    pbPrepareLayoutInfo(
        itemModel, symbolSize, layout, symbolRepeat, symbolOffset,
        symbolPosition, symbolMeta.valueLineWidth, symbolMeta.boundingLength, symbolMeta.repeatCutLength,
        opt, symbolMeta
    )

    return symbolMeta
}

// bar length can be negative.
// upstream: function prepareBarLength(itemModel, symbolRepeat, layout, opt, outputSymbolMeta)
private func pbPrepareBarLength(
    _ itemModel: Model, _ symbolRepeat: Any?, _ layout: [String: Double],
    _ opt: PBCreateOpts, _ out: PBSymbolMeta
) {
    let valueDim = opt.valueDim
    let symbolBoundingDataRaw = itemModel.get("symbolBoundingData")
    let symbolBoundingData: Any? = (symbolBoundingDataRaw is NSNull) ? nil : symbolBoundingDataRaw
    let valueAxis = opt.coordSys.getOtherAxis(opt.coordSys.getBaseAxis())
    let zeroPx = valueAxis.toGlobalCoord(valueAxis.dataToCoord(0))
    let layoutWH = layout[valueDim.wh] ?? Double.nan
    let pxSignIdx = 1 - (layoutWH <= 0 ? 1 : 0)
    var boundingLength: Double

    if let arr = symbolBoundingData as? [Any], arr.count >= 2 {
        var symbolBoundingExtent = [
            pbConvertToCoordOnAxis(valueAxis, arr[0]) - zeroPx,
            pbConvertToCoordOnAxis(valueAxis, arr[1]) - zeroPx
        ]
        if symbolBoundingExtent[1] < symbolBoundingExtent[0] { symbolBoundingExtent.reverse() }
        boundingLength = symbolBoundingExtent[pxSignIdx]
    }
    else if symbolBoundingData != nil {
        boundingLength = pbConvertToCoordOnAxis(valueAxis, symbolBoundingData) - zeroPx
    }
    else if pbTruthy(symbolRepeat) {
        boundingLength = opt.coordSysExtent[valueDim.index][pxSignIdx] - zeroPx
    }
    else {
        boundingLength = layoutWH
    }

    out.boundingLength = boundingLength

    if pbTruthy(symbolRepeat) {
        out.repeatCutLength = layoutWH
    }

    // 'pxSign' means sign of pixel; it can't be zero (else symbolScale/lineWidth become NaN).
    let isXAxis = valueDim.xy == "x"
    let isInverse = valueAxis.inverse
    out.pxSign = (isXAxis && !isInverse) || (!isXAxis && isInverse)
        ? (boundingLength >= 0 ? 1 : -1)
        : (boundingLength > 0 ? 1 : -1)
}

// upstream: function convertToCoordOnAxis(axis, value) {
//   return axis.toGlobalCoord(axis.dataToCoord(axis.scale.parse(value)));
// }
private func pbConvertToCoordOnAxis(_ axis: Axis2D, _ value: Any?) -> Double {
    let parsed = axis.scale.parse(value ?? Double.nan)
    return axis.toGlobalCoord(axis.dataToCoord(parsed))
}

// Support ['100%', '100%']
// upstream: function prepareSymbolSize(data, dataIndex, layout, symbolRepeat, symbolClip, boundingLength,
//   pxSign, symbolPatternSize, opt, outputSymbolMeta)
private func pbPrepareSymbolSize(
    _ data: SeriesData, _ dataIndex: Int, _ layout: [String: Double], _ symbolRepeat: Any?,
    _ boundingLength: Double, _ pxSign: Double, _ symbolPatternSize: Double,
    _ opt: PBCreateOpts, _ out: PBSymbolMeta
) {
    let valueDim = opt.valueDim
    let categoryDim = opt.categoryDim
    let categorySize = Swift.abs(layout[categoryDim.wh] ?? Double.nan)

    let symbolSizeVisual = data.getItemVisual(dataIndex, "symbolSize")
    var parsed: [Any]
    if let arr = symbolSizeVisual as? [Any] {
        parsed = arr
    }
    else if symbolSizeVisual == nil || symbolSizeVisual is NSNull {
        // will parse to number below
        parsed = ["100%", "100%"]
    }
    else {
        parsed = [symbolSizeVisual!, symbolSizeVisual!]
    }

    // NOTE: percentage symbolSize (like '100%') does not consider lineWidth.
    var parsedNum: [Double] = [0, 0]
    parsedNum[categoryDim.index] = number.parsePercent(parsed[categoryDim.index], categorySize)
    parsedNum[valueDim.index] = number.parsePercent(
        parsed[valueDim.index],
        pbTruthy(symbolRepeat) ? categorySize : Swift.abs(boundingLength)
    )

    out.symbolSize = parsedNum

    // If x or y is less than zero, show reversed shape.
    var symbolScale = [
        parsedNum[0] / symbolPatternSize,
        parsedNum[1] / symbolPatternSize
    ]
    // Follow convention, 'right' and 'top' is the normal scale.
    symbolScale[valueDim.index] *= (opt.isHorizontal ? -1 : 1) * pxSign
    out.symbolScale = symbolScale
}

// upstream: function prepareLineWidth(itemModel, symbolScale, rotation, opt, outputSymbolMeta)
private func pbPrepareLineWidth(
    _ itemModel: Model, _ symbolScale: [Double], _ rotation: Double,
    _ opt: PBCreateOpts, _ out: PBSymbolMeta
) {
    // In symbols are drawn with scale, so do not need to care about the case that width or height are
    //   too small. But symbol use strokeNoScale, where the actual lineWidth should be calculated.
    var valueLineWidth = pbDouble(itemModel.get(PB_BAR_BORDER_WIDTH_QUERY)) ?? 0

    if valueLineWidth != 0 {
        // upstream scales the border width through a scratch Circle's `getLineScale()` (accounts for the
        //   symbol scale/rotation so `strokeNoScale` symbols draw a correct border).
        _ = pbPathForLineWidth.attr([
            "scaleX": symbolScale[0],
            "scaleY": symbolScale[1],
            "rotation": rotation
        ])
        pbPathForLineWidth.updateTransform()
        valueLineWidth /= pbPathForLineWidth.getLineScale()
        valueLineWidth *= symbolScale[opt.valueDim.index]
    }

    out.valueLineWidth = valueLineWidth
}

// upstream: function prepareLayoutInfo(itemModel, symbolSize, layout, symbolRepeat, symbolClip,
//   symbolOffset, symbolPosition, valueLineWidth, boundingLength, repeatCutLength, opt, outputSymbolMeta)
private func pbPrepareLayoutInfo(
    _ itemModel: Model, _ symbolSize: [Double], _ layout: [String: Double], _ symbolRepeat: Any?,
    _ symbolOffset: (Double, Double)?, _ symbolPosition: String,
    _ valueLineWidth: Double, _ boundingLength: Double, _ repeatCutLength: Double,
    _ opt: PBCreateOpts, _ out: PBSymbolMeta
) {
    let categoryDim = opt.categoryDim
    let valueDim = opt.valueDim
    let pxSign = out.pxSign

    let unitLength = Swift.max(symbolSize[valueDim.index] + valueLineWidth, 0)
    var pathLen = unitLength

    // Note: rotation does not affect the layout of symbols.

    if pbTruthy(symbolRepeat) {
        let absBoundingLength = Swift.abs(boundingLength)

        var symbolMarginStr = String(describing: util.retrieve(pbOptString(itemModel.get("symbolMargin")), "15%") ?? "15%")
        var hasEndGap = false
        if symbolMarginStr.hasSuffix("!") {
            hasEndGap = true
            symbolMarginStr = String(symbolMarginStr.dropLast())
        }
        var symbolMarginNumeric = number.parsePercent(symbolMarginStr, symbolSize[valueDim.index])

        var uLenWithMargin = Swift.max(unitLength + symbolMarginNumeric * 2, 0)

        // When symbol margin < 0, margin at both ends is subtracted to avoid overflow.
        var endFix = hasEndGap ? 0 : symbolMarginNumeric * 2

        let repeatSpecified = number.isNumeric(symbolRepeat)
        var repeatTimes = repeatSpecified
            ? (pbDouble(symbolRepeat) ?? 0)
            : pbToIntTimes((absBoundingLength + endFix) / uLenWithMargin)

        // Adjust margin so each symbol is displayed entirely in the given layout area.
        let mDiff = absBoundingLength - repeatTimes * unitLength
        symbolMarginNumeric = mDiff / 2 / (hasEndGap ? repeatTimes : Swift.max(repeatTimes - 1, 1))
        uLenWithMargin = unitLength + symbolMarginNumeric * 2
        endFix = hasEndGap ? 0 : symbolMarginNumeric * 2

        // Update repeatTimes when not all symbols will be shown.
        if !repeatSpecified && (symbolRepeat as? String) != "fixed" {
            repeatTimes = repeatCutLength != 0
                ? pbToIntTimes((Swift.abs(repeatCutLength) + endFix) / uLenWithMargin)
                : 0
        }

        pathLen = repeatTimes * uLenWithMargin - endFix
        out.repeatTimes = repeatTimes
        out.symbolMargin = symbolMarginNumeric
    }

    let sizeFix = pxSign * (pathLen / 2)
    var pathPosition: [Double] = [0, 0]
    pathPosition[categoryDim.index] = (layout[categoryDim.wh] ?? 0) / 2
    pathPosition[valueDim.index] = symbolPosition == "start"
        ? sizeFix
        : (symbolPosition == "end"
            ? boundingLength - sizeFix
            : boundingLength / 2)  // 'center'
    if let symbolOffset = symbolOffset {
        pathPosition[0] += symbolOffset.0
        pathPosition[1] += symbolOffset.1
    }
    out.pathPosition = pathPosition

    var bundlePosition: [Double] = [0, 0]
    bundlePosition[categoryDim.index] = layout[categoryDim.xy] ?? 0
    bundlePosition[valueDim.index] = layout[valueDim.xy] ?? 0
    out.bundlePosition = bundlePosition

    // barRectShape = extend({}, layout) with valueDim.wh / categoryDim.wh overridden.
    var barRectShape = RectShape()
    barRectShape.x = layout["x"] ?? 0
    barRectShape.y = layout["y"] ?? 0
    barRectShape.width = layout["width"] ?? 0
    barRectShape.height = layout["height"] ?? 0
    let valueWH = pxSign * Swift.max(
        Swift.abs(layout[valueDim.wh] ?? 0),
        Swift.abs(pathPosition[valueDim.index] + sizeFix)
    )
    let categoryWH = layout[categoryDim.wh] ?? 0
    pbSetRectShapeWH(&barRectShape, valueDim.wh, valueWH)
    pbSetRectShapeWH(&barRectShape, categoryDim.wh, categoryWH)
    out.barRectShape = barRectShape

    // clipShape — consider that symbol may overflow layout rect.
    var clipShape: [String: Double] = [:]
    clipShape[categoryDim.xy] = -(layout[categoryDim.xy] ?? 0)
    clipShape[categoryDim.wh] = opt.ecSize(categoryDim.wh)
    clipShape[valueDim.xy] = 0
    clipShape[valueDim.wh] = layout[valueDim.wh] ?? 0
    out.clipShape = clipShape
}

// Set the width/height field of a RectShape by its dim-key string (upstream indexes shape[wh]).
private func pbSetRectShapeWH(_ shape: inout RectShape, _ wh: String, _ value: Double) {
    if wh == "width" { shape.width = value } else { shape.height = value }
}

// itemModel.get('symbolMargin') may be a String or a number; upstream does `retrieve(x, '15%') + ''`.
private func pbOptString(_ v: Any?) -> String? {
    if v == nil || v is NSNull { return nil }
    if let s = v as? String { return s }
    if let d = pbDouble(v) { return String(d) }
    return nil
}

// upstream: function createPath(symbolMeta): PictorialSymbol
//   Returns a Displayable: a SymbolPath/SVGPath for shape symbols, or a ZRImage for an `image://` symbol.
private func pbCreatePath(_ symbolMeta: PBSymbolMeta) -> Displayable {
    let symbolPatternSize = symbolMeta.symbolPatternSize
    // Consider texture img, make a big size.
    let pathEc = symbol.createSymbol(
        symbolMeta.symbolType,
        -symbolPatternSize / 2,
        -symbolPatternSize / 2,
        symbolPatternSize,
        symbolPatternSize
    )
    guard let el = pathEc as? Displayable else {
        return SymbolPath()
    }
    _ = el.attr("culling", true)
    // upstream: `path.type !== 'image' && path.setStyle('strokeNoScale', true)`. useStyle in updateCommon
    //   replaces the style, so strokeNoScale is (re)applied there; set here too for faithfulness. An image
    //   symbol (ZRImage) has no stroke, so this is skipped for it.
    if let path = el as? Path {
        path.pathStyle.strokeNoScale = true
    }
    return el
}

// upstream: function createOrUpdateRepeatSymbols(bar, opt, symbolMeta, isUpdate?)
private func pbCreateOrUpdateRepeatSymbols(
    _ bar: PictorialBarElement, _ opt: PBCreateOpts, _ symbolMeta: PBSymbolMeta, _ isUpdate: Bool
) {
    let bundle = bar.__pictorialBundle!
    let symbolSize = symbolMeta.symbolSize
    let valueLineWidth = symbolMeta.valueLineWidth
    let pathPosition = symbolMeta.pathPosition
    let valueDim = opt.valueDim
    let repeatTimes = Int(symbolMeta.repeatTimes.rounded(.towardZero) < 0 ? 0 : symbolMeta.repeatTimes)

    let unit = symbolSize[valueDim.index] + valueLineWidth + symbolMeta.symbolMargin * 2

    // makeTarget(index) — the per-repeat position + scale + rotation.
    func makeTarget(_ index: Int) -> [String: Any] {
        var position = pathPosition
        let pxSign = symbolMeta.pxSign
        var i = Double(index)
        if (symbolMeta.symbolRepeatDirection == "start") ? (pxSign > 0) : (pxSign < 0) {
            i = Double(repeatTimes) - 1 - Double(index)
        }
        position[valueDim.index] = unit * (i - Double(repeatTimes) / 2 + 0.5) + pathPosition[valueDim.index]
        return [
            "x": position[0],
            "y": position[1],
            "scaleX": symbolMeta.symbolScale[0],
            "scaleY": symbolMeta.symbolScale[1],
            "rotation": symbolMeta.rotation
        ]
    }

    var index = 0
    // Iterate existing symbol paths in the bundle. A symbol is a Displayable (Path shape or ZRImage).
    for el in bundle.children() {
        guard let path = el as? Displayable else { continue }
        // upstream: path.__pictorialAnimationIndex = index; path.__pictorialRepeatTimes = repeatTimes;
        let rec = pictorialAnimInner(path)
        rec.index = index
        rec.repeatTimes = repeatTimes
        if index < repeatTimes {
            pbUpdateAttr(path, nil, makeTarget(index), symbolMeta, isUpdate, nil)
        }
        else {
            let captured = path
            // weak captures — this closure is retained by an Animator owned by `captured`,
            //   which is a child of `bundle`, so strong captures would form a retain cycle for the
            //   lifetime of the shrink animation (leaking if it never completes, e.g. on dispose).
            pbUpdateAttr(path, nil, ["scaleX": 0.0, "scaleY": 0.0], symbolMeta, isUpdate,
                         { [weak bundle, weak captured] in
                guard let captured = captured else { return }
                _ = bundle?.remove(captured)
                // (No side-store eviction needed: `pictorialAnimInner` is a WeakMap-backed makeInner
                //  bag, so the record dies with the path just like upstream's per-path fields.)
            })
        }
        index += 1
    }

    while index < repeatTimes {
        let path = pbCreatePath(symbolMeta)
        // upstream: path.__pictorialAnimationIndex = index; path.__pictorialRepeatTimes = repeatTimes;
        let newRec = pictorialAnimInner(path)
        newRec.index = index
        newRec.repeatTimes = repeatTimes
        _ = bundle.add(path)

        let target = makeTarget(index)
        pbUpdateAttr(
            path,
            [
                "x": target["x"] as Any,
                "y": target["y"] as Any,
                "scaleX": 0.0,
                "scaleY": 0.0
            ],
            [
                "scaleX": target["scaleX"] as Any,
                "scaleY": target["scaleY"] as Any,
                "rotation": target["rotation"] as Any
            ],
            symbolMeta,
            isUpdate,
            nil
        )
        index += 1
    }
}

// upstream: function createOrUpdateSingleSymbol(bar, opt, symbolMeta, isUpdate?)
private func pbCreateOrUpdateSingleSymbol(
    _ bar: PictorialBarElement, _ opt: PBCreateOpts, _ symbolMeta: PBSymbolMeta, _ isUpdate: Bool
) {
    let bundle = bar.__pictorialBundle!

    if bar.__pictorialMainPath == nil {
        let mainPath = pbCreatePath(symbolMeta)
        bar.__pictorialMainPath = mainPath
        _ = bundle.add(mainPath)

        pbUpdateAttr(
            mainPath,
            [
                "x": symbolMeta.pathPosition[0],
                "y": symbolMeta.pathPosition[1],
                "scaleX": 0.0,
                "scaleY": 0.0,
                "rotation": symbolMeta.rotation
            ],
            [
                "scaleX": symbolMeta.symbolScale[0],
                "scaleY": symbolMeta.symbolScale[1]
            ],
            symbolMeta,
            isUpdate,
            nil
        )
    }
    else {
        let mainPath = bar.__pictorialMainPath!
        pbUpdateAttr(
            mainPath,
            nil,
            [
                "x": symbolMeta.pathPosition[0],
                "y": symbolMeta.pathPosition[1],
                "scaleX": symbolMeta.symbolScale[0],
                "scaleY": symbolMeta.symbolScale[1],
                "rotation": symbolMeta.rotation
            ],
            symbolMeta,
            isUpdate,
            nil
        )
    }
}

// bar rect is used for label.
// upstream: function createOrUpdateBarRect(bar, symbolMeta, isUpdate?)
private func pbCreateOrUpdateBarRect(
    _ bar: PictorialBarElement, _ symbolMeta: PBSymbolMeta, _ isUpdate: Bool
) {
    let rectShape = symbolMeta.barRectShape

    if bar.__pictorialBarRect == nil {
        let barRect = Rect([
            "z2": Double(2),
            "shape": rectShape as PathShape,
            "silent": true
        ])
        var s = PathStyleProps()
        s.stroke = .string("transparent")
        s.fill = .string("transparent")
        s.lineWidth = 0
        barRect.useStyle(s)
        // (barRect as ECElement).disableMorphing = true;
        //   `ECElement` is an augmentation interface that Swift cannot add stored props for;
        //   the flag lives in the `makeInner` side store (animation/morphTransitionHelper.swift), which
        //   `getPathList` reads — so this invisible layout rect is excluded from universalTransition
        //   morph endpoints, exactly as upstream.
        getMorphInner(barRect).disableMorphing = true
        bar.__pictorialBarRect = barRect
        _ = bar.add(barRect)
    }
    else {
        pbUpdateAttr(bar.__pictorialBarRect!, nil, ["shape": pbRectShapeAnimShape(rectShape)], symbolMeta, isUpdate, nil)
    }
}

// upstream: function createOrUpdateClip(bar, opt, symbolMeta, isUpdate?)
private func pbCreateOrUpdateClip(
    _ bar: PictorialBarElement, _ opt: PBCreateOpts, _ symbolMeta: PBSymbolMeta, _ isUpdate: Bool
) {
    // If not clip, symbol will be removed and rebuilt.
    guard symbolMeta.symbolClip else { return }

    let valueDim = opt.valueDim
    let animationModel = symbolMeta.animationModel
    let dataIndex = symbolMeta.dataIndex

    if let clipPath = bar.__pictorialClipPath {
        updateProps(clipPath, ["shape": pbClipShapeAnim(symbolMeta.clipShape)], animationModel, dataIndex)
    }
    else {
        // Build the clip rect starting collapsed on the value dim, then grow it.
        var startClip = symbolMeta.clipShape
        startClip[valueDim.wh] = 0
        let clipPath = Rect(["shape": pbClipShapeToRect(startClip) as PathShape])
        bar.__pictorialBundle.setClipPath(clipPath)
        bar.__pictorialClipPath = clipPath

        var target: [String: Any] = [:]
        target[valueDim.wh] = symbolMeta.clipShape[valueDim.wh] ?? 0

        if isUpdate {
            updateProps(clipPath, ["shape": target], animationModel, dataIndex)
        }
        else {
            initProps(clipPath, ["shape": target], animationModel, dataIndex)
        }
    }
}

// clipShape ([String: Double]) → RectShape.
private func pbClipShapeToRect(_ shape: [String: Double]) -> RectShape {
    var r = RectShape()
    r.x = shape["x"] ?? 0
    r.y = shape["y"] ?? 0
    r.width = shape["width"] ?? 0
    r.height = shape["height"] ?? 0
    return r
}

// clipShape → animatable [String: Any] shape dict (per-field tween; see rectShapeAnimShape trap).
private func pbClipShapeAnim(_ shape: [String: Double]) -> [String: Any] {
    return [
        "x": shape["x"] ?? 0,
        "y": shape["y"] ?? 0,
        "width": shape["width"] ?? 0,
        "height": shape["height"] ?? 0
    ]
}

// RectShape → animatable [String: Any] shape dict (see BarView.rectShapeAnimShape — a typed struct passed
//   to initProps/updateProps snaps to final; a partial dict restores per-field tween).
private func pbRectShapeAnimShape(_ s: RectShape) -> [String: Any] {
    return ["x": s.x, "y": s.y, "width": s.width, "height": s.height]
}

// upstream `PictorialSymbol` carries `__pictorialAnimationIndex` / `__pictorialRepeatTimes` stored on
//   the path. Swift can not add stored props to `Displayable`, so a side-store holds them. It uses the
//   canonical `model.makeInner` bag (CONVENTIONS §8) — a `WeakMap` keyed by object identity — so an
//   entry shares its path's lifetime exactly as upstream's per-path fields do: no manual eviction on
//   any removal path, and no chance of a freed address being re-matched by a later allocation.
//   Read by `getAnimationDelayParams`.
final class PictorialAnimRecord {
    var index: Int = 0
    var repeatTimes: Int = 0
    init() {}
}
private let pictorialAnimInner: (Element) -> PictorialAnimRecord = model.makeInner { PictorialAnimRecord() }

// upstream: function getItemModel(data, dataIndex) — monkeypatches getAnimationDelayParams /
//   isAnimationEnabled onto the item model. isAnimationEnabled is computed inline in pbGetSymbolMeta;
//   getAnimationDelayParams is assigned here as the optional stored closure on Model, read structurally
//   by basicTransition's animateOrSetProps as `model.getAnimationDelayParams?(el, dataIndex)`.
private func pbGetItemModel(_ data: SeriesData, _ dataIndex: Int) -> Model {
    let itemModel = data.getItemModel(dataIndex)
    weak let weakItemModel = itemModel
    weak let weakHostModel = data.hostModel
    itemModel.isAnimationEnabledOverride = {
        guard let itemModel = weakItemModel else { return false }
        return (weakHostModel?.isAnimationEnabled() ?? false)
            && pbTruthy(itemModel.getShallow("animation"))
    }
    // upstream getAnimationDelayParams(this, path):
    //   { index: path.__pictorialAnimationIndex, count: path.__pictorialRepeatTimes }
    //   The order is the same as the z-order, see `symbolRepeatDiretion`.
    // animationModel is also passed to non-symbol elements (the clip path, barRect), which
    //   are never registered in the anim side store. Upstream reads the un-set fields off such a path
    //   as `undefined` (→ NaN when a function-valued animationDelay reads params.index/count); the port
    //   substitutes 0/0 here (the record's defaults). Divergence only surfaces for a user-supplied
    //   function-valued animationDelay that reads those params on a non-symbol element; no built-in
    //   producer does.
    itemModel.getAnimationDelayParams = { path, _ in
        let params = pictorialAnimInner(path)
        return AnimationDelayCallbackParam(
            count: Double(params.repeatTimes),
            index: Double(params.index)
        )
    }
    return itemModel
}

// upstream: function createBar(data, opt, symbolMeta, isUpdate?)
private func pbCreateBar(
    _ data: SeriesData, _ opt: PBCreateOpts, _ symbolMeta: PBSymbolMeta, _ isUpdate: Bool
) -> PictorialBarElement {
    // bar is the main element for each data item.
    let bar = PictorialBarElement()
    // bundle is used for location and clip.
    let bundle = Group()
    _ = bar.add(bundle)
    bar.__pictorialBundle = bundle

    bundle.x = symbolMeta.bundlePosition[0]
    bundle.y = symbolMeta.bundlePosition[1]

    if pbTruthy(symbolMeta.symbolRepeat) {
        pbCreateOrUpdateRepeatSymbols(bar, opt, symbolMeta, false)
    }
    else {
        pbCreateOrUpdateSingleSymbol(bar, opt, symbolMeta, false)
    }

    pbCreateOrUpdateBarRect(bar, symbolMeta, isUpdate)

    pbCreateOrUpdateClip(bar, opt, symbolMeta, isUpdate)

    bar.__pictorialShapeStr = pbGetShapeStr(data, symbolMeta)
    bar.__pictorialSymbolMeta = symbolMeta
    return bar
}

// upstream: function updateBar(bar, opt, symbolMeta)
private func pbUpdateBar(_ bar: PictorialBarElement, _ opt: PBCreateOpts, _ symbolMeta: PBSymbolMeta) {
    let animationModel = symbolMeta.animationModel
    let dataIndex = symbolMeta.dataIndex
    let bundle = bar.__pictorialBundle!

    updateProps(
        bundle,
        ["x": symbolMeta.bundlePosition[0], "y": symbolMeta.bundlePosition[1]],
        animationModel, dataIndex
    )

    if pbTruthy(symbolMeta.symbolRepeat) {
        pbCreateOrUpdateRepeatSymbols(bar, opt, symbolMeta, true)
    }
    else {
        pbCreateOrUpdateSingleSymbol(bar, opt, symbolMeta, true)
    }

    pbCreateOrUpdateBarRect(bar, symbolMeta, true)

    pbCreateOrUpdateClip(bar, opt, symbolMeta, true)
}

// upstream: function removeBar(data, dataIndex, animationModel, bar)
private func pbRemoveBar(
    _ data: SeriesData, _ dataIndex: Int, _ animationModelIn: Model?, _ bar: PictorialBarElement
) {
    // Not show text when animating.
    let labelRect = bar.__pictorialBarRect
    labelRect?.removeTextContent()

    // upstream: `eachPath(bar, path => paths.push(path))` — walks the bundle's children, skipping
    //   `__pictorialBarRect` — then `bar.__pictorialMainPath && paths.push(bar.__pictorialMainPath)`.
    //   (The single-symbol main path is itself a bundle child, so it lands in `paths` twice, exactly
    //   as upstream; the second `removeElement` is a no-op thanks to its `isElementRemoved` guard.)
    var paths: [Element] = []
    if let bundle = bar.__pictorialBundle {
        for el in bundle.children() {
            if el === labelRect { continue }
            paths.append(el)
        }
    }
    if let mainPath = bar.__pictorialMainPath { paths.append(mainPath) }

    // I do not find proper remove animation for clip yet.
    var animationModel = animationModelIn
    if bar.__pictorialClipPath != nil { animationModel = nil }

    // upstream: graphic.removeElement(path, {scaleX: 0, scaleY: 0}, animationModel, dataIndex,
    //             function () { bar.parent && bar.parent.remove(bar); });
    for path in paths {
        // `[weak bar]` — the closure is retained by an Animator owned by `path`, and
        //   `path` is a descendant of `bar` (bar -> __pictorialBundle -> path), so a strong capture
        //   is a retain cycle that only breaks when the leave animation completes. Upstream relies
        //   on GC; under ARC a disposed zr (animation never completing) would leak the subtree.
        removeElement(path, ["scaleX": 0.0, "scaleY": 0.0], animationModel, dataIndex, { [weak bar] in
            guard let bar = bar, let parent = bar.parent as? Group else { return }
            _ = parent.remove(bar)
        })
        // (No side-store eviction needed: `pictorialAnimInner` is WeakMap-backed, so a path's record
        //  is released with the path — matching upstream's per-path fields.)
    }

    // PORT-DEVIATION (no upstream counterpart, PictorialBarView.ts:833-840): upstream detaches `bar`
    //   only from inside the per-path `removeElement` completion, so with ZERO paths (symbolRepeat
    //   resolving to 0 repeats and no main path) it leaks the bar — it stays attached to the view
    //   group forever once `setItemGraphicEl(dataIndex, nil)` drops the handle. The port detaches it
    //   immediately (un-animated) in that degenerate case only. Flagged explicitly so a diff-vs-
    //   upstream audit reads this as an intentional divergence rather than ported code.
    if paths.isEmpty, let parent = bar.parent as? Group {
        _ = parent.remove(bar)
    }

    data.setItemGraphicEl(dataIndex, nil)
}

// upstream: function getShapeStr(data, symbolMeta)
private func pbGetShapeStr(_ data: SeriesData, _ symbolMeta: PBSymbolMeta) -> String {
    let sym = (data.getItemVisual(symbolMeta.dataIndex, "symbol") as? String) ?? "none"
    return [sym, String(pbTruthy(symbolMeta.symbolRepeat)), String(symbolMeta.symbolClip)].joined(separator: ":")
}

// upstream: function updateAttr<T>(el, immediateAttrs, animationAttrs, symbolMeta, isUpdate?, cb?)
private func pbUpdateAttr(
    _ el: Element, _ immediateAttrs: [String: Any]?, _ animationAttrs: [String: Any]?,
    _ symbolMeta: PBSymbolMeta, _ isUpdate: Bool, _ cb: (() -> Void)?
) {
    if let immediateAttrs = immediateAttrs {
        _ = el.attr(immediateAttrs)
    }
    // When symbolClip is used, only clip path has init animation, otherwise it would look weird.
    if symbolMeta.symbolClip && !isUpdate {
        if let animationAttrs = animationAttrs {
            _ = el.attr(animationAttrs)
        }
    }
    else if let animationAttrs = animationAttrs {
        if isUpdate {
            updateProps(el, animationAttrs, symbolMeta.animationModel, symbolMeta.dataIndex, cb)
        }
        else {
            initProps(el, animationAttrs, symbolMeta.animationModel, symbolMeta.dataIndex, cb)
        }
    }
}

// the `extend({image, x, y, width, height}, style)` bridge that used to live here as
//   `pbImageStyleFromDict` is the SAME upstream expression as Symbol._updateCommon's image branch;
//   the single definition now lives next to it as `symbolImageStyleFromDict`
//   (chart/helper/SymbolElement.swift) and is used by both call sites.

// upstream: function updateCommon(bar, opt, symbolMeta)
private func pbUpdateCommon(_ bar: PictorialBarElement, _ opt: PBCreateOpts, _ symbolMeta: PBSymbolMeta) {
    let dataIndex = symbolMeta.dataIndex
    let itemModel = symbolMeta.itemModel!
    // Color must be excluded (symbol provides setColor individually for fill/stroke).
    let emphasisModel = itemModel.getModel("emphasis")
    let emphasisStyle = emphasisModel.getModel("itemStyle").getItemStyle()
    let blurStyle = itemModel.getModel(["blur", "itemStyle"]).getItemStyle()
    let selectStyle = itemModel.getModel(["select", "itemStyle"]).getItemStyle()
    let cursorStyle = itemModel.getShallow("cursor") as? String

    let focus: InnerFocus? = emphasisModel.get("focus")
    let blurScope = (emphasisModel.get("blurScope") as? String).flatMap { BlurScope(rawValue: $0) }
    let hoverScale = (emphasisModel.get("scale") as? Bool) ?? false

    let styleDict = symbolMeta.style as? [String: Any]

    for el in bar.__pictorialBundle.children() {
        guard let path = el as? Displayable else { continue }
        // upstream:
        //   if (path instanceof ZRImage) {
        //       const pathStyle = path.style;
        //       path.useStyle(zrUtil.extend({
        //           image: pathStyle.image, x: pathStyle.x, y: pathStyle.y,
        //           width: pathStyle.width, height: pathStyle.height
        //       }, symbolMeta.style));
        //   } else { path.useStyle(symbolMeta.style); }
        //   An `image://` symbol IS created now (symbol.createSymbol's image branch → ZRImage), so the
        //   image branch is live: keep the image + its geometry, overlay the item visual style.
        if let imagePath = path as? ZRImage {
            imagePath.useStyle(symbolImageStyleFromDict(imagePath.imageStyle, symbolMeta.style))
            // TODO [ZRenderKit/Image.ZRImage.stateStyleSync]: the emphasis / blur / select state styles set below write the inherited
            //   `Displayable.style` (CommonStyleProps), but ZRImage renders from its own
            //   `imageStyle` and `_syncCommonStyle` is one-way (imageStyle -> style). State styles
            //   applied to a ZRImage are therefore inert (hover opacity on an `image://` pictorial
            //   symbol is silently dropped). The real fix — syncing the applied state style back
            //   into `imageStyle`, or a ZRImage override of the state-style apply — belongs in
            //   ZRenderKit (Sources/ZRenderKit/Graphic/Image.swift) and is out of scope here.
            //   Tracked as `ZRenderKit/Image.ZRImage.stateStyleSync`: a ZRImage override of the
            //   state-style apply that mirrors the applied CommonStyleProps subset back into
            //   `imageStyle` before `dirtyStyle()`. Grep that id for the other end of the gap.
        }
        else if let shapePath = path as? Path {
            shapePath.useStyle(barStyleFromDict(symbolMeta.style))
            shapePath.pathStyle.strokeNoScale = true
        }

        let emphasisState = path.ensureState("emphasis")
        emphasisState.style = emphasisStyle

        if hoverScale {
            // NOTE: must be after scale is set by updateAttr.
            emphasisState.scaleX = path.scaleX * 1.1
            emphasisState.scaleY = path.scaleY * 1.1
        }

        path.ensureState("blur").style = blurStyle
        path.ensureState("select").style = selectStyle

        if let cursorStyle = cursorStyle { path.cursor = cursorStyle }
        path.z2 = symbolMeta.z2
    }

    let barPositionOutside = opt.valueDim.posDesc[symbolMeta.boundingLength > 0 ? 1 : 0]
    guard let barRect = bar.__pictorialBarRect else {
        states.toggleHoverEmphasis(bar, focus, blurScope, (emphasisModel.get("disabled") as? Bool) ?? false)
        return
    }
    barRect.ignoreClip = true

    func inheritColorString(_ v: Any?) -> ColorString? {
        if let s = v as? String { return s }
        if let zr = v as? EChartsKit.ZRColor, case let .color(str) = zr { return str }
        return nil
    }

    let labelStatesModels = labelStyle.getLabelStatesModels(itemModel)
    var labelOpt = SetLabelStyleOpt()
    labelOpt.labelFetcher = opt.seriesModel
    labelOpt.labelDataIndex = Double(dataIndex)
    labelOpt.defaultText = labelHelper.getDefaultLabel(opt.seriesModel.getData(), Double(dataIndex))
    labelOpt.inheritColor = inheritColorString(styleDict?["fill"])
    // `pbDouble`, not `as? Double` — the visual style can box opacity as an Int, which
    //   `as? Double` silently drops (upstream passes `symbolMeta.style.opacity` through unconditionally).
    labelOpt.defaultOpacity = pbDouble(styleDict?["opacity"])
    labelOpt.defaultOutsidePosition = barPositionOutside
    labelStyle.setLabelStyle(barRect, labelStatesModels, labelOpt)

    states.toggleHoverEmphasis(bar, focus, blurScope, (emphasisModel.get("disabled") as? Bool) ?? false)
}

// upstream: function toIntTimes(times)
private func pbToIntTimes(_ times: Double) -> Double {
    let roundedTimes = times.rounded()
    // Escape accuracy error.
    return Swift.abs(times - roundedTimes) < 1e-4 ? roundedTimes : times.rounded(.up)
}

// export default PictorialBarView;  -> `open class PictorialBarView` above.
