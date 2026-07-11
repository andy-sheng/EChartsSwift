// Ported from echarts/src/component/axis/CartesianAxisView.ts — keep in sync with upstream
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
//   import * as graphic from '../../util/graphic';                   -> `graphic.*` is NOT ported as a
//     namespace. `graphic.Group` / `graphic.Line` are the ZRenderKit `Group` / `Line`. The echarts
//     wrappers `graphic.subPixelOptimizeLine` (which delegates to the value-returning
//     `subPixelOptimizeNS.subPixelOptimizeLine`) and `graphic.groupTransition` are reproduced/deferred
//     below (see `subPixelOptimizeLine` free function + the `groupTransition` PORT-NOTE in `render`).
//   import AxisView from './AxisView';                               -> `AxisView` (component/axis/AxisView.swift).
//     PORT-TODO: `AxisView` is a sibling landing this phase (not yet ported). Conventional public API
//     referenced here: `open class AxisView: ComponentView` with an overridable `type: String`,
//     `axisPointerClass: String`, `open func render(_ model: ComponentModel, _ ecModel: GlobalModel,
//     _ api: ExtensionAPI, _ payload: Payload)`, and `open func remove(_ ecModel: GlobalModel,
//     _ api: ExtensionAPI)`.
//   import {rectCoordAxisBuildSplitArea, rectCoordAxisHandleRemove} from './axisSplitHelper';
//     -> PORT-TODO: `component/axis/axisSplitHelper` NOT ported (splitArea colors + inner-store PREREQ).
//        `rectCoordAxisBuildSplitArea` (splitArea builder) and `rectCoordAxisHandleRemove` (remove) are
//        deferred with documented PORT-NOTEs below.
//   import GlobalModel from '../../model/Global';                    -> `GlobalModel`.
//   import ExtensionAPI from '../../core/ExtensionAPI';              -> `ExtensionAPI`.
//   import CartesianAxisModel from '../../coord/cartesian/AxisModel'; -> `CartesianAxisModel`.
//   import GridModel from '../../coord/cartesian/GridModel';          -> `GridModel`.
//   import { Payload } from '../../util/types';                       -> `Payload` (util/types.swift).
//   import { getAxisBreakHelper } from './axisBreakHelper';           -> PORT-TODO: `component/axis/axisBreakHelper`
//     NOT ported (axis break feature). `breakArea` builder deferred below.
//   import { shouldAxisShow } from '../../coord/axisHelper';          -> `axisHelper.shouldAxisShow`.

// upstream: const selfBuilderAttrs = ['splitArea', 'splitLine', 'minorSplitLine', 'breakArea'] as const;
private let selfBuilderAttrs: [String] = [
    "splitArea", "splitLine", "minorSplitLine", "breakArea"
]

// upstream: class CartesianAxisView extends AxisView { ... }
// CONVENTIONS §2: reference type + subclassed (CartesianXAxisView / CartesianYAxisView) → `open class`.
open class CartesianAxisView: AxisView {

    // upstream: static type = 'cartesianAxis';
    public static let cartesianAxisType = "cartesianAxis"
    // upstream: type = CartesianAxisView.type;
    open override var type: String {
        get { CartesianAxisView.cartesianAxisType }
        set { /* readonly upstream */ }
    }

    // upstream: axisPointerClass = 'CartesianAxisPointer';
    open override var axisPointerClass: String? {
        get { "CartesianAxisPointer" }
        set { /* readonly upstream */ }
    }

    // upstream: private _axisGroup: graphic.Group;
    private var _axisGroup: Group!

    /**
     * @override
     */
    // upstream: render(axisModel: CartesianAxisModel, ecModel, api, payload)
    //   The base `AxisView.render` signature is typed `ComponentModel` (matching ComponentView); the
    //   concrete `CartesianAxisModel` is recovered by downcast (same pattern as BarView.render).
    open override func render(
        _ axisModel: ComponentModel, _ ecModel: GlobalModel, _ api: ExtensionAPI, _ payload: Payload
    ) {
        let axisModel = axisModel as! CartesianAxisModel

        self.group.removeAll()

        let oldAxisGroup = self._axisGroup
        self._axisGroup = Group()

        _ = self.group.add(self._axisGroup)

        if !axisHelper.shouldAxisShow(axisModel) {
            return
        }

        // upstream: this._axisGroup.add(axisModel.axis.axisBuilder.group);
        //   `axisModel.axis` is typed `Any` (see AxisBaseModel.axis) → downcast to `Axis2D`.
        //   PORT-TODO: `Axis2D.axisBuilder` is the Tier4 `AxisBuilder` (component/axis/AxisBuilder,
        //   Phase 6b). Conventional public API referenced: `AxisBuilder.group: Group` (the built
        //   axisLine / ticks / labels group). Until AxisBuilder is ported this reads the injected
        //   builder's group.
        _ = self._axisGroup.add((axisModel.axis as! Axis2D).axisBuilder.group)

        // upstream: zrUtil.each(selfBuilderAttrs, function (name) { ... }, this);
        for name in selfBuilderAttrs {
            // upstream: if (axisModel.get([name, 'show']))
            //   PORT-NOTE: JS truthy check on the option value; coerced to Bool (all four `show`
            //   flags are booleans).
            if (axisModel.get([name, "show"]) as? Bool) == true {
                axisElementBuilders[name]!(
                    self, self._axisGroup, axisModel,
                    axisModel.getCoordSysModel() as! GridModel, api
                )
            }
        }

        // THIS is a special case for bar racing chart.
        // Update the axis label from the natural initial layout to
        // sorted layout should has no animation.
        // upstream: payload && payload.type === 'changeAxisOrder' && payload.isInitSort
        let isInitialSortFromBarRacing =
            payload.type == "changeAxisOrder" && ((payload.other["isInitSort"] as? Bool) ?? false)

        if !isInitialSortFromBarRacing {
            // upstream: graphic.groupTransition(oldAxisGroup, this._axisGroup, axisModel);
            // PORT-TODO: `graphic.groupTransition` (util/graphic.ts) is NOT ported. It matches
            //   old/new elements by `anid` and animates the transition (`updateProps`). Deferred with
            //   the animation seam; the final geometry (built fresh above) is correct without it.
            _ = oldAxisGroup
        }

        super.render(axisModel, ecModel, api, payload)
    }

    // upstream: remove() { rectCoordAxisHandleRemove(this); }
    //   The base `AxisView.remove(ecModel, api)` carries the two args (ignored upstream); the signature
    //   is matched here so it overrides. PORT-TODO: `rectCoordAxisHandleRemove` (axisSplitHelper) clears
    //   the cached splitArea colors from the inner store — deferred with splitArea.
    open override func remove(_ ecModel: GlobalModel, _ api: ExtensionAPI) {
        // PORT-TODO: rectCoordAxisHandleRemove(self) — axisSplitHelper not ported.
    }
}

// upstream: interface AxisElementBuilder { (axisView, axisGroup, axisModel, gridModel, api): void }
typealias AxisElementBuilder = (
    _ axisView: CartesianAxisView,
    _ axisGroup: Group,
    _ axisModel: CartesianAxisModel,
    _ gridModel: GridModel,
    _ api: ExtensionAPI
) -> Void

// upstream: const axisElementBuilders: Record<typeof selfBuilderAttrs[number], AxisElementBuilder> = { ... }
private let axisElementBuilders: [String: AxisElementBuilder] = [

    "splitLine": { axisView, axisGroup, axisModel, gridModel, api in
        let axis = axisModel.axis as! Axis2D

        if axis.scale.isBlank() {
            return
        }

        let splitLineModel = axisModel.getModel("splitLine")
        let lineStyleModel = splitLineModel.getModel("lineStyle")
        // upstream: let lineColors = lineStyleModel.get('color');
        let lineColorsRaw = lineStyleModel.get("color")
        // upstream: splitLineModel.get('showMinLine') !== false
        let showMinLine = (splitLineModel.get("showMinLine") as? Bool) != false
        let showMaxLine = (splitLineModel.get("showMaxLine") as? Bool) != false

        // upstream: lineColors = zrUtil.isArray(lineColors) ? lineColors : [lineColors];
        let lineColors: [Any?]
        if util.isArray(lineColorsRaw) {
            lineColors = (lineColorsRaw as? [Any])?.map { $0 as Any? } ?? [lineColorsRaw]
        }
        else {
            lineColors = [lineColorsRaw]
        }

        // upstream: const gridRect = gridModel.coordinateSystem.getRect();
        //   `GridModel.coordinateSystem` is `CoordinateSystemMaster?`; `getRect()` lives on the concrete
        //   `Grid` (the master protocol's `getRect` resolves to nil), so downcast to `Grid`.
        let gridRect = (gridModel.coordinateSystem as! Grid).getRect()
        let isHorizontal = axis.isHorizontal()

        var lineCount = 0

        let ticksCoords = axis.getTicksCoords(GetTicksCoordsOpt(
            tickModel: splitLineModel,
            breakTicks: "none",
            pruneByBreak: "preserve_extent_bound"
        ))

        var p1 = [Double](repeating: 0, count: 2)
        var p2 = [Double](repeating: 0, count: 2)

        let lineStyle = lineStyleModel.getLineStyle()
        for i in 0..<ticksCoords.count {
            let tickCoord = axis.toGlobalCoord(ticksCoords[i].coord)

            if (i == 0 && !showMinLine) || (i == ticksCoords.count - 1 && !showMaxLine) {
                continue
            }

            let tickValue = ticksCoords[i].tickValue

            if isHorizontal {
                p1[0] = tickCoord
                p1[1] = gridRect.y
                p2[0] = tickCoord
                p2[1] = gridRect.y + gridRect.height
            }
            else {
                p1[0] = gridRect.x
                p1[1] = tickCoord
                p2[0] = gridRect.x + gridRect.width
                p2[1] = tickCoord
            }

            let colorIndex = (lineCount) % lineColors.count
            lineCount += 1   // upstream: (lineCount++)

            // upstream: style: zrUtil.defaults({ stroke: lineColors[colorIndex] }, lineStyle)
            //   `defaults(target, source)` keeps `target.stroke` and fills the rest from `lineStyle`.
            var style = lineStylePropsFromDict(lineStyle)
            if let c = lineColors[colorIndex] as? String {
                style.stroke = .string(c)
            }

            var lineShape = LineShape()
            lineShape.x1 = p1[0]
            lineShape.y1 = p1[1]
            lineShape.x2 = p2[0]
            lineShape.y2 = p2[1]

            let line = Line([
                "shape": lineShape as PathShape,
                "style": style
            ])
            // upstream: anid: tickValue != null ? 'line_' + tickValue : null
            //   PORT-NOTE: `AxisTickCoord.tickValue` is a non-optional `Double`, so the `!= null` guard
            //   is always true; `anid` is only consumed by the deferred `groupTransition`.
            line.anid = "line_\(tickValue)"
            line.autoBatch = true
            line.silent = true

            // upstream: graphic.subPixelOptimizeLine(line.shape, lineStyle.lineWidth);
            var optimized = line.shape as! LineShape
            optimized = subPixelOptimizeLine(optimized, lineStyle["lineWidth"] as? Double)
            line.shape = optimized

            _ = axisGroup.add(line)
        }
    },

    "minorSplitLine": { axisView, axisGroup, axisModel, gridModel, api in
        let axis = axisModel.axis as! Axis2D

        let minorSplitLineModel = axisModel.getModel("minorSplitLine")
        let lineStyleModel = minorSplitLineModel.getModel("lineStyle")

        let gridRect = (gridModel.coordinateSystem as! Grid).getRect()
        let isHorizontal = axis.isHorizontal()

        let minorTicksCoords = axis.getMinorTicksCoords()
        if minorTicksCoords.isEmpty {
            return
        }
        var p1 = [Double](repeating: 0, count: 2)
        var p2 = [Double](repeating: 0, count: 2)

        let lineStyle = lineStyleModel.getLineStyle()

        for i in 0..<minorTicksCoords.count {
            for k in 0..<minorTicksCoords[i].count {
                let tickCoord = axis.toGlobalCoord(minorTicksCoords[i][k].coord)

                if isHorizontal {
                    p1[0] = tickCoord
                    p1[1] = gridRect.y
                    p2[0] = tickCoord
                    p2[1] = gridRect.y + gridRect.height
                }
                else {
                    p1[0] = gridRect.x
                    p1[1] = tickCoord
                    p2[0] = gridRect.x + gridRect.width
                    p2[1] = tickCoord
                }

                var lineShape = LineShape()
                lineShape.x1 = p1[0]
                lineShape.y1 = p1[1]
                lineShape.x2 = p2[0]
                lineShape.y2 = p2[1]

                let line = Line([
                    "shape": lineShape as PathShape,
                    "style": lineStylePropsFromDict(lineStyle)
                ])
                // upstream: anid: 'minor_line_' + minorTicksCoords[i][k].tickValue
                line.anid = "minor_line_\(minorTicksCoords[i][k].tickValue)"
                line.autoBatch = true
                line.silent = true

                // upstream: graphic.subPixelOptimizeLine(line.shape, lineStyle.lineWidth);
                var optimized = line.shape as! LineShape
                optimized = subPixelOptimizeLine(optimized, lineStyle["lineWidth"] as? Double)
                line.shape = optimized

                _ = axisGroup.add(line)
            }
        }
    },

    "splitArea": { axisView, axisGroup, axisModel, gridModel, api in
        // upstream: rectCoordAxisBuildSplitArea(axisView, axisGroup, axisModel, gridModel);
        // PORT-TODO: `component/axis/axisSplitHelper.rectCoordAxisBuildSplitArea` is NOT ported (it caches
        //   alternating splitArea colors in the inner store and builds `graphic.Rect` bands across the
        //   grid rect). Deferred per the bar+axis milestone scope (splitLine is the axis grid deliverable).
        _ = (axisView, axisGroup, axisModel, gridModel, api)
    },

    "breakArea": { axisView, axisGroup, axisModel, gridModel, api in
        // upstream:
        //   const axisBreakHelper = getAxisBreakHelper();
        //   const scale = axisModel.axis.scale;
        //   if (axisBreakHelper && scale.type !== 'ordinal') {
        //       axisBreakHelper.rectCoordBuildBreakAxis(
        //           axisGroup, axisView, axisModel, gridModel.coordinateSystem.getRect(), api);
        //   }
        // PORT-TODO: `component/axis/axisBreakHelper` (the axis-break feature) is NOT ported;
        //   `getAxisBreakHelper()` returns nil, so this builder is a no-op (matches upstream when the
        //   feature is not `use()`-d). Deferred per the bar+axis milestone scope.
        _ = (axisView, axisGroup, axisModel, gridModel, api)
    }
]

// upstream: export class CartesianXAxisView extends CartesianAxisView {
//     static type = 'xAxis';
//     type = CartesianXAxisView.type;
// }
open class CartesianXAxisView: CartesianAxisView {
    public static let xAxisType = "xAxis"
    open override var type: String {
        get { CartesianXAxisView.xAxisType }
        set { }
    }
}

// upstream: export class CartesianYAxisView extends CartesianAxisView {
//     static type = 'yAxis';
//     type = CartesianXAxisView.type;    // <- NOTE: upstream assigns CartesianXAxisView.type (='xAxis')
// }
//   The instance `type` is set from `CartesianXAxisView.type` upstream (a known upstream quirk — the
//   static `type` is 'yAxis' but the instance `type` reads 'xAxis'). Preserved faithfully.
open class CartesianYAxisView: CartesianAxisView {
    public static let yAxisType = "yAxis"
    open override var type: String {
        get { CartesianXAxisView.xAxisType }  // upstream: CartesianXAxisView.type (preserved verbatim)
        set { }
    }
}

// export default CartesianAxisView;  -> `open class CartesianAxisView` above.

// ================================================================================================
// upstream: echarts/src/util/graphic.ts `subPixelOptimizeLine(shape, lineWidth)` — a thin wrapper over
//   zrender's `subPixelOptimizeUtil.subPixelOptimizeLine(shape, shape, {lineWidth})` that mutates
//   `shape` in place and returns it. Per CONVENTIONS §3 the ZRenderKit variant
//   (`subPixelOptimizeNS.subPixelOptimizeLine`) is value-returning, so this wrapper is value-returning
//   too: it optimizes and returns a fresh `LineShape` (call sites assign it back to `line.shape`).
// ================================================================================================
private func subPixelOptimizeLine(_ shape: LineShape, _ lineWidth: Double?) -> LineShape {
    var style = PathStyleProps()
    style.lineWidth = lineWidth
    let out = subPixelOptimizeNS.subPixelOptimizeLine(
        subPixelOptimizeNS.LineShape(x1: shape.x1, y1: shape.y1, x2: shape.x2, y2: shape.y2),
        style
    )!
    var s = shape
    s.x1 = out.x1
    s.y1 = out.y1
    s.x2 = out.x2
    s.y2 = out.y2
    return s
}

// PORT-TODO: `util/graphic`-level style-bag bridge. `Model.getLineStyle()` returns the dynamic
//   `LineStyleProps` == `[String: Any]` bag (makeStyleMapper output, keyed by PathStyleProps field
//   names); ZRenderKit `Line`'s `style` prop is a typed `PathStyleProps`. This maps the common line
//   paint keys so the splitLine/minorSplitLine strokes are actually drawn. `lineDash`
//   (`number | number[]`) is not bridged yet (see LineDash). Same deviation as BarView.barStyleFromDict.
private func lineStylePropsFromDict(_ style: [String: Any]) -> PathStyleProps {
    var s = PathStyleProps()
    if let v = style["stroke"] as? String { s.stroke = .string(v) }
    if let v = style["lineWidth"] as? Double { s.lineWidth = v }
    if let v = style["opacity"] as? Double { s.opacity = v }
    if let v = style["shadowBlur"] as? Double { s.shadowBlur = v }
    if let v = style["shadowColor"] as? String { s.shadowColor = v }
    if let v = style["shadowOffsetX"] as? Double { s.shadowOffsetX = v }
    if let v = style["shadowOffsetY"] as? Double { s.shadowOffsetY = v }
    if let v = style["lineCap"] as? String { s.lineCap = v }
    if let v = style["lineJoin"] as? String { s.lineJoin = v }
    if let v = style["miterLimit"] as? Double { s.miterLimit = v }
    if let v = style["lineDashOffset"] as? Double { s.lineDashOffset = v }
    // PORT-TODO: `lineDash` (number | number[]) not bridged to ZRColor.LineDash yet.
    return s
}
