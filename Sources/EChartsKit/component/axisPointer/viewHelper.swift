// Ported from echarts/src/component/axisPointer/viewHelper.ts — keep in sync with upstream
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

// import * as zrUtil from 'zrender/src/core/util';                 -> util.* (ZRenderKit caseless enum)
// import * as graphic from '../../util/graphic';                   -> graphic.applyTransform === vector.applyTransform (ZRenderKit core)
// import * as textContain from 'zrender/src/contain/text';         -> ZRenderKit `text.*` (Contain/ContainText.swift)
// import * as formatUtil from '../../util/format';                 -> format.* (util/format.swift)
// import * as matrix from 'zrender/src/core/matrix';               -> matrix.* (ZRenderKit Core/matrix.swift)
// import * as axisHelper from '../../coord/axisHelper';            -> axisHelper.* (coord/axisHelper.swift)
// import AxisBuilder from '../axis/AxisBuilder';                   -> AxisBuilder (component/axis/AxisBuilder.swift)
// import Axis from '../../coord/Axis';                             -> Axis (coord/Axis.swift)
// import GlobalModel from '../../model/Global';                    -> GlobalModel (model/Global.swift)
// import IntervalScale from '../../scale/Interval';                -> IntervalScale (scale/Interval.swift)
// import Axis2D from '../../coord/cartesian/Axis2D';               -> Axis2D (coord/cartesian/Axis2D.swift)
// import { AxisPointerElementOptions } from './BaseAxisPointer';   -> BaseAxisPointer.swift (sibling; defines
//   `AxisPointerElementOptions` + `PointerElementOption` + `LabelElementOption`).
// import { AxisBaseModel } from '../../coord/AxisBaseModel';       -> AxisBaseModel (coord/AxisBaseModel.swift)
// import ExtensionAPI from '../../core/ExtensionAPI';              -> ExtensionAPI (core/ExtensionAPI.swift)
// import type CartesianAxisModel from '../../coord/cartesian/AxisModel'; -> CartesianAxisModel
// import Model from '../../model/Model';                           -> Model (model/Model.swift)
// import { PathStyleProps } from 'zrender/src/graphic/Path';       -> PathStyleProps (ZRenderKit Graphic/Path.swift)
// import { createTextStyle } from '../../label/labelStyle';        -> label/labelStyle.swift is ported
//   (createTextStyle); the crosshair label TextStyleProps is now routed through it in buildLabelElOption.
// import { calcBandWidth } from '../../coord/axisBand';            -> calcBandWidth (coord/axisBand.swift)
// import { mathMax, mathMin } from '../../util/number';            -> number.mathMax / number.mathMin
//
// type AxisPointerModel = Model<CommonAxisPointerOption>  -> `Model` (non-generic in the port).

// upstream: interface AxisTransformedPositionLayoutInfo
//   `cartesianAxisHelper.layout` returns a `CartesianAxisLayout`; upstream passes it structurally as an
//   `AxisTransformedPositionLayoutInfo` (and dynamically tacks on `labelMargin`). Swift structs are fixed,
//   so this is a distinct struct with a convenience init from `CartesianAxisLayout`.
public struct AxisTransformedPositionLayoutInfo {
    public var position: [Double]
    public var rotation: Double
    public var labelOffset: Double?
    public var labelDirection: Double?   // -1 | 1
    public var labelMargin: Double?
    public init(
        position: [Double], rotation: Double,
        labelOffset: Double? = nil, labelDirection: Double? = nil, labelMargin: Double? = nil
    ) {
        self.position = position; self.rotation = rotation
        self.labelOffset = labelOffset; self.labelDirection = labelDirection; self.labelMargin = labelMargin
    }
    public init(_ layout: CartesianAxisLayout) {
        self.position = layout.position
        self.rotation = layout.rotation
        self.labelOffset = layout.labelOffset
        self.labelDirection = layout.labelDirection
        self.labelMargin = nil
    }
}

// ============================================================================
// viewHelper — upstream free functions -> caseless enum namespace (CONVENTIONS §2).
//   The `{pointer, label, graphicKey}` element-option types (`AxisPointerElementOptions` /
//   `PointerElementOption` / `LabelElementOption`) live in the sibling `BaseAxisPointer.swift`.
// ============================================================================
public enum viewHelper {

    // upstream: buildElStyle(axisPointerModel): PathStyleProps
    //   getLineStyle()/getAreaStyle() return the dynamic `[String: Any]` style bag (LINE/AREA_STYLE_KEY_MAP
    //   keyed); mapped onto the typed `PathStyleProps` the pointer Path consumes. `style.fill = null`
    //   (line) / `style.stroke = null` (shadow) are inert here — the mappers never populate the opposite
    //   paint (line has no `fill`, shadow has no `stroke`), so those fields are already nil.
    public static func buildElStyle(_ axisPointerModel: Model) -> PathStyleProps? {
        let axisPointerType = axisPointerModel.get("type") as? String
        // getModel(axisPointerType + 'Style')  -> 'lineStyle' | 'shadowStyle'
        let styleModel = axisPointerModel.getModel((axisPointerType ?? "") + "Style")
        if axisPointerType == "line" {
            // style = styleModel.getLineStyle(); style.fill = null;
            return pathStyleFromLineStyleDict(styleModel.getLineStyle())
        }
        else if axisPointerType == "shadow" {
            // style = styleModel.getAreaStyle(); style.stroke = null;
            return pathStyleFromAreaStyleDict(styleModel.getAreaStyle())
        }
        return nil
    }

    // upstream: labelPos: { align?, verticalAlign?, position: number[] }
    public struct LabelPos {
        public var align: ZRTextAlign?
        public var verticalAlign: ZRTextVerticalAlign?
        public var position: [Double]
        public init(align: ZRTextAlign? = nil, verticalAlign: ZRTextVerticalAlign? = nil, position: [Double]) {
            self.align = align; self.verticalAlign = verticalAlign; self.position = position
        }
    }

    /**
     * @param {Function} labelPos {align, verticalAlign, position}
     */
    public static func buildLabelElOption(
        _ elOption: inout AxisPointerElementOptions,
        _ axisModel: AxisBaseModel,
        _ axisPointerModel: Model,
        _ api: ExtensionAPI,
        _ labelPos: LabelPos
    ) {
        let value = axisPointerModel.get("value")
        let axis = axisModel.axis as! Axis
        let text = getValueLabel(
            value, axis, axisModel.ecModel!,
            axisPointerModel.get("seriesDataIndices") as? [AxisTriggerDataIndex],
            GetValueLabelOpt(
                precision: axisPointerModel.get(["label", "precision"]),
                formatter: axisPointerModel.get(["label", "formatter"])
            )
        )
        let labelModel = axisPointerModel.getModel("label")
        // formatUtil.normalizeCssArray(labelModel.get('padding') || 0)
        let paddings = normalizeCssArrayOpt(labelModel.get("padding"))

        let font = labelModel.getFont()
        let textRect = ZRenderKit.text.getBoundingRect(text, font)

        var position = labelPos.position
        let width = textRect.width + paddings[1] + paddings[3]
        let height = textRect.height + paddings[0] + paddings[2]

        // Adjust by align.
        let align = labelPos.align
        if align == .right { position[0] -= width }
        if align == .center { position[0] -= width / 2 }
        let verticalAlign = labelPos.verticalAlign
        if verticalAlign == .bottom { position[1] -= height }
        if verticalAlign == .middle { position[1] -= height / 2 }

        // Not overflow ec container
        confineInContainer(&position, width, height, api)

        // let bgColor = labelModel.get('backgroundColor');
        // if (!bgColor || bgColor === 'auto') bgColor = axisModel.get(['axisLine','lineStyle','color']);
        var bgColor = labelModel.get("backgroundColor")
        if !jsTruthy(bgColor) || (bgColor as? String) == "auto" {
            bgColor = axisModel.get(["axisLine", "lineStyle", "color"])
        }

        // style: createTextStyle(labelModel, { text, font, fill, padding, backgroundColor })
        //   labelStyle.createTextStyle merges the full text-style surface (rich text, textBorder, shadow)
        //   from `labelModel` via setTextStyleCommon, then `extend`s these specified fields over it.
        var specified = TextStyleProps()
        specified.text = text
        specified.font = font
        specified.fill = labelModel.getTextColor()
        specified.padding = .array(paddings)
        if let bg = bgColor as? String {
            specified.backgroundColor = .string(bg)
        }
        let style = labelStyle.createTextStyle(labelModel, specified, nil, nil, nil)

        elOption.label = LabelElementOption(
            // shape: {x: 0, y: 0, width, height, r: labelModel.get('borderRadius')},
            x: position[0],
            y: position[1],
            style: style,
            // Label should be over axisPointer.
            z2: 10
        )
    }

    // upstream: getValueLabel(value, axis, ecModel, seriesDataIndices, opt?): string
    public struct GetValueLabelOpt {
        public var precision: Any?   // number | 'auto'
        public var formatter: Any?   // string | Function
        public init(precision: Any? = nil, formatter: Any? = nil) {
            self.precision = precision; self.formatter = formatter
        }
    }

    public static func getValueLabel(
        _ valueIn: Any?,
        _ axis: Axis,
        _ ecModel: GlobalModel,
        _ seriesDataIndices: [AxisTriggerDataIndex]?,
        _ opt: GetValueLabelOpt?
    ) -> String {
        // value = axis.scale.parse(value);
        let value = axis.scale.parse(valueIn ?? NSNull())   // ParsedValueNumeric (Double)
        let tick = ScaleTick(value: value)
        // (axis.scale as IntervalScale).getLabel({value}, { precision: opt.precision })
        //   Only IntervalScale (and its Log subclass) has the precision-aware overload in the port; other
        //   scales (Ordinal/Time) ignore `precision`, so fall back to the base getLabel(tick).
        var text: String
        if let intervalScale = axis.scale as? IntervalScale {
            var labelOpt = IntervalScaleGetLabelOpt()
            labelOpt.precision = opt?.precision
            text = intervalScale.getLabel(tick, labelOpt)
        }
        else {
            text = axis.scale.getLabel(tick)
        }

        let formatter = opt?.formatter
        if let formatter = formatter, !(formatter is NSNull) {
            var seriesData: [CallbackDataParams] = []
            util.each(seriesDataIndices) { idxItem, _ in
                let series = ecModel.getSeriesByIndex(idxItem.seriesIndex)
                let dataIndex = idxItem.dataIndexInside
                if let series = series {
                    seriesData.append(series.getDataParams(dataIndex, nil))
                }
            }
            let params: [String: Any] = [
                "value": axisHelper.getAxisRawValue(axis, tick),
                "axisDimension": axis.dim,
                // Only Cartesian axis has index
                "axisIndex": ((axis as? Axis2D)?.index).map { $0 as Any } ?? NSNull(),
                "seriesData": seriesData
            ]
            if let s = formatter as? String {
                // text = formatter.replace('{value}', text);
                text = replaceFirst(s, "{value}", text)
            }
            else if let f = formatter as? ([String: Any]) -> String {
                text = f(params)
            }
        }

        return text
    }

    // upstream: getTransformedPosition(axis, value, layoutInfo): number[]
    public static func getTransformedPosition(
        _ axis: Axis,
        _ value: Any?,
        _ layoutInfo: AxisTransformedPositionLayoutInfo
    ) -> [Double] {
        var transform = matrix.create()
        transform = matrix.rotate(transform, layoutInfo.rotation)
        transform = matrix.translate(transform, VectorArray(layoutInfo.position[0], layoutInfo.position[1]))

        let y = (layoutInfo.labelOffset ?? 0)
            + (layoutInfo.labelDirection ?? 1) * (layoutInfo.labelMargin ?? 0)
        let out = vector.applyTransform(VectorArray(axis.dataToCoord(value ?? NSNull()), y), transform)
        return [out[0], out[1]]
    }

    // upstream: buildCartesianSingleLabelElOption(value, elOption, layoutInfo, axisModel, axisPointerModel, api)
    public static func buildCartesianSingleLabelElOption(
        _ value: Any?,
        _ elOption: inout AxisPointerElementOptions,
        _ layoutInfoIn: AxisTransformedPositionLayoutInfo,
        _ axisModel: AxisBaseModel,
        _ axisPointerModel: Model,
        _ api: ExtensionAPI
    ) {
        var layoutInfo = layoutInfoIn
        let textLayout = AxisBuilder.innerTextLayout(
            layoutInfo.rotation, 0, layoutInfo.labelDirection ?? 1
        )
        layoutInfo.labelMargin = axisPointerModel.get(["label", "margin"]) as? Double
        buildLabelElOption(&elOption, axisModel, axisPointerModel, api, LabelPos(
            align: textLayout.textAlign,
            verticalAlign: textLayout.textVerticalAlign,
            position: getTransformedPosition(axisModel.axis as! Axis, value, layoutInfo)
        ))
    }

    // upstream: makeLineShape(p1, p2, xDimIndex?)  -> a `LineShape` (the typed pointer path shape).
    public static func makeLineShape(_ p1: [Double], _ p2: [Double], _ xDimIndex: Int? = nil) -> LineShape {
        let xDimIndex = xDimIndex ?? 0
        return lineShapeOf(p1[xDimIndex], p1[1 - xDimIndex], p2[xDimIndex], p2[1 - xDimIndex])
    }

    // upstream: makeRectShape(xy, wh, xDimIndex?)  -> a `RectShape`.
    public static func makeRectShape(_ xy: [Double], _ wh: [Double], _ xDimIndex: Int? = nil) -> RectShape {
        let xDimIndex = xDimIndex ?? 0
        var r = RectShape()
        r.x = xy[xDimIndex]
        r.y = xy[1 - xDimIndex]
        r.width = wh[xDimIndex]
        r.height = wh[1 - xDimIndex]
        return r
    }

    // upstream: makeSectorShape(cx, cy, r0, r, startAngle, endAngle)
    //   PORT-NOTE: polar-only (Circle/Sector pointer). CartesianAxisPointer never calls this; kept faithful
    //   as a plain object for when PolarAxisPointer lands (no `SectorShape` bridge needed yet).
    public static func makeSectorShape(
        _ cx: Double, _ cy: Double, _ r0: Double, _ r: Double,
        _ startAngle: Double, _ endAngle: Double
    ) -> [String: Any] {
        return [
            "cx": cx, "cy": cy, "r0": r0, "r": r,
            "startAngle": startAngle, "endAngle": endAngle, "clockwise": true
        ]
    }

    // upstream: calcAxisPointerShadowBandWidth(axis, seriesDataIndices, ecModel): number
    public static func calcAxisPointerShadowBandWidth(
        _ axis: Axis,
        _ seriesDataIndices: [AxisTriggerDataIndex]?,
        _ ecModel: GlobalModel
    ) -> Double {
        let sers: [SeriesModel?] = util.map(seriesDataIndices) { item, _ in
            ecModel.getSeriesByIndex(item.seriesIndex)
        }
        return calcBandWidth(axis, CalculateBandWidthOpt(
            fromStat: CalculateBandWidthOpt.FromStat(sers: sers),
            min: 1
        )).w
    }

    /**
     * Return a [min, max] in pixel clampped by `axisExtent`.
     */
    // upstream: calcAxisPointerShadowEnds(val, axisExtent, bandWidth): number[]
    public static func calcAxisPointerShadowEnds(
        _ val: Double,
        _ axisExtent: [Double],
        _ bandWidth: Double
    ) -> [Double] {
        return [
            number.mathMax(
                number.mathMin(axisExtent[0], axisExtent[1]),
                val - bandWidth / 2
            ),
            number.mathMin(
                val + bandWidth / 2,
                number.mathMax(axisExtent[0], axisExtent[1])
            )
        ]
    }
}

// Do not overflow ec container
// upstream: confineInContainer(position, width, height, api)  (out-param mutation -> inout)
private func confineInContainer(_ position: inout [Double], _ width: Double, _ height: Double, _ api: ExtensionAPI) {
    let viewWidth = api.getWidth()
    let viewHeight = api.getHeight()
    position[0] = Swift.min(position[0] + width, viewWidth) - width
    position[1] = Swift.min(position[1] + height, viewHeight) - height
    position[0] = Swift.max(position[0], 0)
    position[1] = Swift.max(position[1], 0)
}

// getAreaStyle() dynamic bag ([String: Any], keys per AREA_STYLE_KEY_MAP) -> typed PathStyleProps.
//   Mirrors the sibling `pathStyleFromLineStyleDict` (AxisBuilder.swift). `stroke` is intentionally left
//   nil (upstream `style.stroke = null` for the shadow pointer).
private func pathStyleFromAreaStyleDict(_ dict: [String: Any]) -> PathStyleProps {
    var s = PathStyleProps()
    if let fill = dict["fill"] as? String { s.fill = .string(fill) }
    if let opacity = dict["opacity"] as? Double { s.opacity = opacity }
    if let shadowBlur = dict["shadowBlur"] as? Double { s.shadowBlur = shadowBlur }
    if let shadowOffsetX = dict["shadowOffsetX"] as? Double { s.shadowOffsetX = shadowOffsetX }
    if let shadowOffsetY = dict["shadowOffsetY"] as? Double { s.shadowOffsetY = shadowOffsetY }
    if let shadowColor = dict["shadowColor"] as? String { s.shadowColor = shadowColor }
    return s
}

// formatUtil.normalizeCssArray(val || 0) — coerce the dynamic `padding` option (number | number[] | nil)
//   and reproduce JS `|| 0` (falsy -> 0).
private func normalizeCssArrayOpt(_ val: Any?) -> [Double] {
    if let arr = val as? [Double] { return format.normalizeCssArray(arr) }
    if let arr = val as? [Int] { return format.normalizeCssArray(arr.map(Double.init)) }
    if let d = val as? Double, jsTruthy(d) { return format.normalizeCssArray(d) }
    if let i = val as? Int, i != 0 { return format.normalizeCssArray(Double(i)) }
    return format.normalizeCssArray(0.0)
}

// String.replace('{value}', text) — replaces the FIRST occurrence only (JS String.prototype.replace
//   with a string pattern), unlike replacingOccurrences which is global.
private func replaceFirst(_ s: String, _ target: String, _ replacement: String) -> String {
    guard let range = s.range(of: target) else { return s }
    return s.replacingCharacters(in: range, with: replacement)
}

// --- JS truthiness (shared local helper; mirrors sibling modelHelper.swift / coord/View.swift) ---
private func jsTruthy(_ v: Any?) -> Bool {
    switch v {
    case nil: return false
    case is NSNull: return false
    case let b as Bool: return b
    case let d as Double: return d != 0 && !d.isNaN
    case let i as Int: return i != 0
    case let s as String: return !s.isEmpty
    default: return true
    }
}
