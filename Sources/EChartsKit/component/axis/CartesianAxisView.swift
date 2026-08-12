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
//     `subPixelOptimizeNS.subPixelOptimizeLine`) is reproduced below (see the `subPixelOptimizeLine`
//     free function); `graphic.groupTransition` is the ported top-level `groupTransition`
//     (util/graphic.swift), called in `render`.
//   import AxisView from './AxisView';                               -> `AxisView` (component/axis/AxisView.swift).
//     PORT-NOTE: `AxisView` is ported (base class of this view). Public API used here:
//     `open class AxisView: ComponentView` with an overridable `type: String`,
//     `axisPointerClass: String`, `open func render(_ model: ComponentModel, _ ecModel: GlobalModel,
//     _ api: ExtensionAPI, _ payload: Payload)`, and `open func remove(_ ecModel: GlobalModel,
//     _ api: ExtensionAPI)`.
//   import {rectCoordAxisBuildSplitArea, rectCoordAxisHandleRemove} from './axisSplitHelper';
//     -> PORT-NOTE: `axisSplitHelper` is not ported as a standalone module; `rectCoordAxisBuildSplitArea`
//        and `rectCoordAxisHandleRemove` are ported inline in this file (see the splitArea builder and
//        `rectCoordAxisHandleRemove` below).
//   import GlobalModel from '../../model/Global';                    -> `GlobalModel`.
//   import ExtensionAPI from '../../core/ExtensionAPI';              -> `ExtensionAPI`.
//   import CartesianAxisModel from '../../coord/cartesian/AxisModel'; -> `CartesianAxisModel`.
//   import GridModel from '../../coord/cartesian/GridModel';          -> `GridModel`.
//   import { Payload } from '../../util/types';                       -> `Payload` (util/types.swift).
//   import { getAxisBreakHelper } from './axisBreakHelper';           -> PORT-NOTE (deferred): requires
//     `component/axis/axisBreakHelper` (axis break feature), not ported. `breakArea` builder deferred below.
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

    // upstream: axisSplitHelper `const inner = makeInner<{ splitAreaColors: HashMap<number> }, AxisView>()`
    //   — the makeInner inner store keyed on the axis view. Ported as a stored property (same observable
    //   effect): the splitArea builder reads it for color/anid continuity across re-renders and writes it
    //   back; `remove()` clears it (`rectCoordAxisHandleRemove`). Delete when `axisSplitHelper.swift` lands.
    fileprivate var _splitAreaColors: [Double: Int]?

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
        //   PORT-NOTE: `Axis2D.axisBuilder` is the `AxisBuilder` (component/axis/AxisBuilder.swift, ported).
        //   `AxisBuilder.group: Group` is the built axisLine / ticks / labels group read here.
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
            //   `graphic.groupTransition` is ported as the top-level free func `groupTransition`
            //   (util/graphic.swift): it matches old/new elements by `anid` and animates the
            //   transition (`updateProps`). `oldAxisGroup` is nil on the first render — the
            //   nil-guard lives inside `groupTransition`, matching upstream's `if (!g1 || !g2)`.
            //   PORT-NOTE: only the `x` / `y` / `rotation` props actually interpolate today (axis
            //   labels — the bar-racing case). The `shape` leg does NOT tween: `getAnimatableProps`
            //   puts a whole `PathShape` STRUCT under the "shape" key, and `animateToShallow`'s
            //   recursion guard is `util.isObject`, which is false for a struct — so the track is
            //   classified VALUE_TYPE_UNKOWN / `discrete` and `Animator.start()` sets it straight to
            //   the final value (correct final geometry, instant instead of tweened). Shape-carrying
            //   axis elements (splitLine `line_*`, minorSplitLine `minor_line_*`, splitArea `area_*`,
            //   AxisBuilder's axisLine / ticks) therefore snap.
            // PORT-TODO: shape transition is discrete — the nested `getAnimatableProps` declared
            //   inside the body of the top-level `groupTransition` (util/graphic.swift, ~line 337;
            //   there is no file-scope `getAnimatableProps` symbol) must emit `shape` as a scalar
            //   `[String: Any]` sub-bag (the TreeView `bezierShapeDict` / ParallelView / SankeyView
            //   precedent) so `animateToShallow` recurses into `ShapeAnimationAccessor`; that needs
            //   a key-enumeration hook on
            //   `protocol PathShape` (ZRenderKit/Graphic/Path.swift). Provider-side fix, tracked
            //   separately; drop this marker once it lands.
            groupTransition(oldAxisGroup, self._axisGroup, axisModel)
        }

        super.render(axisModel, ecModel, api, payload)
    }

    // upstream: remove() { rectCoordAxisHandleRemove(this); }
    //   The base `AxisView.remove(ecModel, api)` carries the two args (ignored upstream); the signature
    //   is matched here so it overrides. `rectCoordAxisHandleRemove` clears the cached splitArea colors —
    //   ported inline against the `_splitAreaColors` store (see the store note above).
    open override func remove(_ ecModel: GlobalModel, _ api: ExtensionAPI) {
        rectCoordAxisHandleRemove(self)
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
            //   is always true; `anid` is consumed by `groupTransition` (called in `render`) — which
            //   matches this element to its previous-render twin, but transitions its `shape`
            //   discretely (see the PORT-TODO on the `groupTransition` call).
            //   PORT-NOTE: interpolating a Swift `Double` formats "line_5.0" where upstream JS yields
            //   "line_5". Harmless: `anid` has a single consumer (`groupTransition`'s elMap lookup)
            //   and both the old and the new group are built by this same code, so the values are
            //   symmetric across renders. The same drift applies to `minor_line_*` / `area_*` here
            //   and to `AxisBuilder`'s ids — fix all of them together or none.
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
        //   Ported inline (`rectCoordAxisBuildSplitArea` free function below), since the shared
        //   `axisSplitHelper` module is not ported as its own file. Mirrors SingleAxisView's port.
        rectCoordAxisBuildSplitArea(axisView, axisGroup, axisModel, gridModel)
    },

    "breakArea": { axisView, axisGroup, axisModel, gridModel, api in
        // upstream:
        //   const axisBreakHelper = getAxisBreakHelper();
        //   const scale = axisModel.axis.scale;
        //   if (axisBreakHelper && scale.type !== 'ordinal') {
        //       axisBreakHelper.rectCoordBuildBreakAxis(
        //           axisGroup, axisView, axisModel, gridModel.coordinateSystem.getRect(), api);
        //   }
        // Cartesian break-area pass. This mirrors axisBreakHelperImpl's two irregular zigzag borders
        // plus the polygon between them. At a zero-gap break only the first border is drawn, which is
        // also the straight plot-spanning line used by the intraday demos when zigzagAmplitude is zero.
        _ = (axisView, api)
        let axis = axisModel.axis as! Axis2D
        guard hasBreaks(axis.scale) else { return }
        let breakAreaModel = axisModel.getModel("breakArea")
        guard (breakAreaModel.get("show") as? Bool) != false else { return }

        let styleDict = breakAreaModel.getModel("itemStyle").getItemStyle()
        let itemStyle = lineStylePropsFromDict(styleDict)
        var borderStyle = itemStyle
        borderStyle.fill = nil

        let amplitude = styleNum(breakAreaModel.get("zigzagAmplitude")) ?? 4
        let minSpan = max(2, styleNum(breakAreaModel.get("zigzagMinSpan")) ?? 0)
        let maxSpan = max(minSpan, styleNum(breakAreaModel.get("zigzagMaxSpan")) ?? 0)
        let zigzagZ = styleNum(breakAreaModel.get("zigzagZ")) ?? 100

        let gridRect = (gridModel.coordinateSystem as! Grid).getRect()
        let breakAreaGroup = Group(["ignoreModelZ": true])
        _ = axisGroup.add(breakAreaGroup)
        for brk in getBreaksUnsafe(axis.scale) {
            var startCoord = axis.toGlobalCoord(axis.dataToCoord(brk.vmin, true))
            var endCoord = axis.toGlobalCoord(axis.dataToCoord(brk.vmax, true))
            if endCoord < startCoord { swap(&startCoord, &endCoord) }

            let traverseStart = axis.isHorizontal() ? gridRect.y : gridRect.x
            let traverseEnd = axis.isHorizontal()
                ? gridRect.y + gridRect.height
                : gridRect.x + gridRect.width
            var pointsA: [VectorArray] = []
            var pointsB: [VectorArray] = []
            var current = traverseStart
            var swapSide = true
            var randomState = UInt64(brk.vmin.bitPattern ^ brk.vmax.bitPattern) | 1

            while true {
                let first = pointsA.isEmpty
                let last = current >= traverseEnd
                if last { current = traverseEnd }

                var a = startCoord
                var b = endCoord
                if !first && !last {
                    let offset = swapSide ? -amplitude : amplitude
                    a += offset
                    b += offset
                }
                if axis.isHorizontal() {
                    pointsA.append(VectorArray(a, current))
                    pointsB.append(VectorArray(b, current))
                }
                else {
                    pointsA.append(VectorArray(current, a))
                    pointsB.append(VectorArray(current, b))
                }
                if last { break }

                // Upstream caches Math.random() values so the irregular outline remains stable.
                // Use a deterministic LCG here for the same visual character and stable snapshots.
                randomState = randomState &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
                let unit = Double(randomState >> 11) / Double(UInt64.max >> 11)
                current += minSpan + unit * (maxSpan - minSpan)
                swapSide.toggle()
            }

            let suffix = "\(brk.vmin)_\(brk.vmax)"
            func addBorder(_ points: [VectorArray], _ name: String) {
                var shape = PolylineShape()
                shape.points = points
                let line = Polyline(["shape": shape as PathShape, "style": borderStyle])
                line.anid = "break_\(name)_\(suffix)"
                line.silent = true
                line.z = zigzagZ
                // Axis component z propagation resets descendant `z` later in the render pass.
                // Keep the upstream zigzagZ ordering in z2 as well so both borders stay above bars.
                line.z2 = zigzagZ + 1
                _ = breakAreaGroup.add(line)
            }

            addBorder(pointsA, "a")
            if brk.gapReal != 0 {
                addBorder(pointsB, "b")
                var polygonShape = PolygonShape()
                polygonShape.points = pointsA + pointsB.reversed()
                var polygonStyle = PathStyleProps()
                polygonStyle.fill = itemStyle.fill
                polygonStyle.opacity = itemStyle.opacity
                let polygon = Polygon(["shape": polygonShape as PathShape, "style": polygonStyle])
                polygon.anid = "break_c_\(suffix)"
                polygon.silent = true
                polygon.z = zigzagZ
                polygon.z2 = zigzagZ
                _ = breakAreaGroup.add(polygon)
            }
        }
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

// PORT-NOTE: `util/graphic`-level style-bag bridge (JS dynamic dict -> typed Swift struct). `Model.getLineStyle()` returns the dynamic
//   `LineStyleProps` == `[String: Any]` bag (makeStyleMapper output, keyed by PathStyleProps field
//   names); ZRenderKit `Line`'s `style` prop is a typed `PathStyleProps`. This maps the common line
//   paint keys so the splitLine/minorSplitLine strokes are actually drawn. `lineDash`
//   (`number | number[]`) is not bridged yet (see LineDash). Same deviation as BarView.barStyleFromDict.
private func lineStylePropsFromDict(_ style: [String: Any]) -> PathStyleProps {
    var s = PathStyleProps()
    if let v = style["fill"] as? String { s.fill = .string(v) }
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
    // upstream `lineDash?: false | number[] | 'solid' | 'dashed' | 'dotted'` (getLineStyle maps the
    //   `type` option to `lineDash`) → the `LineDash` enum, so dashed/dotted split lines render as dashes
    //   (mirrors SingleAxisView.pathStyleFromDict / AxisBuilder.pathStyleFromLineStyleDict).
    if let dash = style["lineDash"] {
        if let arr = dash as? [Double] {
            s.lineDash = .values(arr)
        }
        else if let arr = dash as? [Any] {
            s.lineDash = .values(arr.compactMap { styleNum($0) })
        }
        else if let b = dash as? Bool, b == false {
            s.lineDash = .`false`
        }
        else if let str = dash as? String {
            switch str {
            case "solid": s.lineDash = .solid
            case "dashed": s.lineDash = .dashed
            case "dotted": s.lineDash = .dotted
            default: break
            }
        }
    }
    return s
}

// PORT-NOTE: number coercion for the dynamic style bag (Int|Double|NSNumber) — avoids the Int-drop trap
//   when a `lineDash` array element is an Int literal. Mirrors SingleAxisView.styleNum.
private func styleNum(_ v: Any?) -> Double? {
    if let d = v as? Double { return d }
    if let i = v as? Int { return Double(i) }
    if let n = v as? NSNumber, !(n === kCFBooleanTrue || n === kCFBooleanFalse) { return n.doubleValue }
    return nil
}

// ================================================================================================
// upstream: echarts/src/component/axis/axisSplitHelper.ts — the SHARED splitArea helper (also consumed by
//   SingleAxisView). Its sibling file is not ported as a standalone module; the CartesianAxisView path is
//   reproduced here so the alternating splitArea background bands actually render. The `makeInner` inner
//   store keyed on the axis view is ported as `CartesianAxisView._splitAreaColors` (same observable effect).
//   Delete when `axisSplitHelper.swift` lands and call the sibling directly. Mirrors SingleAxisView's port.
// ================================================================================================
private func rectCoordAxisBuildSplitArea(
    _ axisView: CartesianAxisView,
    _ axisGroup: Group,
    _ axisModel: CartesianAxisModel,
    _ gridModel: GridModel
) {
    // upstream: const axis = axisModel.axis;  (`AxisBaseModel.axis` is `Any` → downcast to `Axis2D`.)
    let axis = axisModel.axis as! Axis2D

    if axis.scale.isBlank() {
        return
    }

    let splitAreaModel = axisModel.getModel("splitArea")
    let areaStyleModel = splitAreaModel.getModel("areaStyle")
    // upstream: let areaColors = areaStyleModel.get('color');
    let areaColorsRaw = areaStyleModel.get("color")

    // upstream: const gridRect = gridModel.coordinateSystem.getRect();
    //   `GridModel.coordinateSystem` is `CoordinateSystemMaster?`; `getRect()` lives on the concrete `Grid`.
    let gridRect = (gridModel.coordinateSystem as! Grid).getRect()

    let ticksCoords = axis.getTicksCoords(GetTicksCoordsOpt(
        tickModel: splitAreaModel,
        breakTicks: "none",
        pruneByBreak: "preserve_extent_bound"
    ))

    // upstream: if (!ticksCoords.length) { return; }
    if ticksCoords.isEmpty {
        return
    }

    // upstream: areaColors = zrUtil.isArray(areaColors) ? areaColors : [areaColors];
    let areaColors: [Any?] = util.isArray(areaColorsRaw)
        ? ((areaColorsRaw as? [Any])?.map { $0 as Any? } ?? [areaColorsRaw])
        : [areaColorsRaw]
    // upstream: const areaColorsLen = areaColors.length;
    //   Guard `% areaColorsLen` against an explicit empty `color: []` (Swift `%` by zero traps; cf. SingleAxisView).
    let areaColorsLen = areaColors.count
    if areaColorsLen == 0 {
        return
    }

    // For Making appropriate splitArea animation, the color and anid should be corresponding to previous one.
    let lastSplitAreaColors = axisView._splitAreaColors
    var newSplitAreaColors: [Double: Int] = [:]
    var colorIndex = 0
    if let lastSplitAreaColors = lastSplitAreaColors {
        for i in 0..<ticksCoords.count {
            // upstream: const cIndex = lastSplitAreaColors.get(ticksCoords[i].tickValue);
            if let cIndex = lastSplitAreaColors[ticksCoords[i].tickValue] {
                colorIndex = (cIndex + (areaColorsLen - 1) * i) % areaColorsLen
                break
            }
        }
    }

    var prev = axis.toGlobalCoord(ticksCoords[0].coord)

    // upstream: const areaStyle = areaStyleModel.getAreaStyle();
    let areaStyle = areaStyleModel.getAreaStyle()

    for i in 1..<ticksCoords.count {
        let tickCoord = axis.toGlobalCoord(ticksCoords[i].coord)

        let x: Double
        let y: Double
        let width: Double
        let height: Double
        if axis.isHorizontal() {
            x = prev
            y = gridRect.y
            width = tickCoord - x
            height = gridRect.height
            prev = x + width
        }
        else {
            x = gridRect.x
            y = prev
            width = gridRect.width
            height = tickCoord - y
            prev = y + height
        }

        // upstream: const tickValue = ticksCoords[i - 1].tickValue;
        //   `tickValue != null && newSplitAreaColors.set(...)` — always non-null in this port (`Double`).
        let tickValue = ticksCoords[i - 1].tickValue
        newSplitAreaColors[tickValue] = colorIndex

        // upstream: style: zrUtil.defaults({ fill: areaColors[colorIndex] }, areaStyle)
        //   the explicit per-band `fill` wins; the rest (opacity/shadow) fills from areaStyle.
        var style = lineStylePropsFromDict(areaStyle)
        if let c = areaColors[colorIndex] as? String {
            style.fill = .string(c)
        }

        var rectShape = RectShape()
        rectShape.x = x
        rectShape.y = y
        rectShape.width = width
        rectShape.height = height

        let rect = Rect([
            "shape": rectShape as PathShape,
            "style": style
        ])
        // upstream: anid: tickValue != null ? 'area_' + tickValue : null
        rect.anid = "area_\(tickValue)"
        rect.autoBatch = true
        rect.silent = true
        _ = axisGroup.add(rect)

        colorIndex = (colorIndex + 1) % areaColorsLen
    }

    // upstream: inner(axisView).splitAreaColors = newSplitAreaColors;
    axisView._splitAreaColors = newSplitAreaColors
}

// upstream: export function rectCoordAxisHandleRemove(axisView) { inner(axisView).splitAreaColors = null; }
private func rectCoordAxisHandleRemove(_ axisView: CartesianAxisView) {
    axisView._splitAreaColors = nil
}
