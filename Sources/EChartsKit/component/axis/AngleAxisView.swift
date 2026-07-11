// Ported from echarts/src/component/axis/AngleAxisView.ts — keep in sync with upstream
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
//   import * as zrUtil from 'zrender/src/core/util';           → `util.*` (ZRenderKit; map/each/isArray/defaults).
//   import * as graphic from '../../util/graphic';
//     → `util/graphic` is NOT ported as a namespace. `graphic.Circle` / `graphic.Arc` / `graphic.Ring` /
//       `graphic.Sector` / `graphic.Line` / `graphic.Text` are the ZRenderKit scene-graph shapes (used
//       directly — the sanctioned DRAWING deviation; cf. CartesianAxisView / RadarComponentView).
//       `graphic.mergePath` → ZRenderKit `mergePath` (Tool/ToolPath). `graphic.setTooltipConfig` is the
//       tooltip-config seam, deferred below (PORT-NOTE).
//   import {createTextStyle} from '../../label/labelStyle';
//     → PORT-NOTE: `label/labelStyle` is ported (createTextStyle); this view uses the module-internal `createTextStyle(_ textStyleModel,
//       text:, font:, overflow:, width:, ellipsis:, fill:, align:, verticalAlign:)` reproduction that lives
//       in AxisBuilder.swift (same module) — enough for the axis label (text/font/fill/align). Its `<T>`
//       nuance generic and the object-literal `x`/`y` fields are handled by assigning `style.x`/`style.y`
//       after the call (TextStyleProps carries x/y in this port).
//   import Model from '../../model/Model';                     → `Model`.
//   import AxisView from './AxisView';                         → `AxisView` (component/axis/AxisView.swift).
//   import AxisBuilder from './AxisBuilder';                   → `AxisBuilder` (component/axis/AxisBuilder.swift).
//   import { AngleAxisModel } from '../../coord/polar/AxisModel';
//     → PORT-NOTE: `AngleAxisModel` is ported (coord/polar/PolarAxisModel.swift; polar is a full coord system).
//       API: `open class AngleAxisModel: AxisBaseModel` (so `.axis: Any`, `.get`, `.getModel`,
//       `.getCategories`, `.getTextColor` Model surface). Registered component view `type` is 'angleAxis'.
//   import GlobalModel from '../../model/Global';              → `GlobalModel`.
//   import Polar from '../../coord/polar/Polar';
//     → PORT-NOTE: `Polar` (coord/polar/Polar.swift). API (mirrors upstream Polar):
//         var cx: Double ; var cy: Double
//         func getRadiusAxis() -> RadiusAxis      // (open class RadiusAxis: Axis)
//         func getAngleAxis() -> AngleAxis
//         func coordToPoint(_ coord: [Double]) -> [Double]   // upstream: coordToPoint([radius, angle]) -> number[]
//   import AngleAxis from '../../coord/polar/AngleAxis';
//     → PORT-NOTE: `AngleAxis` (coord/polar/AngleAxis.swift). API (open class AngleAxis: Axis):
//         var polar: Polar
//         inherits `scale`/`inverse`/`getExtent()`/`dataToCoord()`/`getTicksCoords()`/
//                  `getMinorTicksCoords()`/`getViewLabels()` from `Axis`.
//   import { ZRTextAlign, ZRTextVerticalAlign, ColorString } from '../../util/types';
//     → `TextAlign` / `TextVerticalAlign` (ZRenderKit enums) / `ColorString` (== String).
//   import { getECData } from '../../util/innerStore';         → PORT-TODO: inner-store ECData seam, deferred.
//   import { AxisLabelBaseOptionNuance } from '../../coord/axisCommonTypes';  → dropped (createTextStyle generic nuance).
//   import { getTickValueOutermost } from '../../coord/axisHelper';           → `axisHelper.getTickValueOutermost`.

// upstream: const elementList = ['axisLine','axisLabel','axisTick','minorTick','splitLine','minorSplitLine','splitArea'] as const;
private let elementList: [String] = [
    "axisLine",
    "axisLabel",
    "axisTick",
    "minorTick",
    "splitLine",
    "minorSplitLine",
    "splitArea"
]

// upstream: function getAxisLineShape(polar, rExtent, angle) { ... returns {x1,y1,x2,y2} }
//   Returns a `LineShape` (the shape bag consumed by `new graphic.Line({shape})`).
private func getAxisLineShape(_ polar: Polar, _ rExtent: [Double], _ angle: Double) -> LineShape {
    // upstream: rExtent[1] > rExtent[0] && (rExtent = rExtent.slice().reverse());
    var rExtent = rExtent
    if rExtent[1] > rExtent[0] {
        rExtent = Array(rExtent.reversed())
    }
    let start = polar.coordToPoint([rExtent[0], angle])
    let end = polar.coordToPoint([rExtent[1], angle])

    var shape = LineShape()
    shape.x1 = start[0]
    shape.y1 = start[1]
    shape.x2 = end[0]
    shape.y2 = end[1]
    return shape
}

// upstream: function getRadiusIdx(polar) { const radiusAxis = polar.getRadiusAxis(); return radiusAxis.inverse ? 0 : 1; }
private func getRadiusIdx(_ polar: Polar) -> Int {
    let radiusAxis = polar.getRadiusAxis()
    return radiusAxis.inverse ? 0 : 1
}

// upstream: type TickCoord = Pick<...getTicksCoords()[number], 'coord'>;
//   Both `ticksAngles` items (AxisTickCoord) and the label items expose a `.coord`; `fixAngleOverlap`
//   is generic over that shared field (see `AngleCoordItem`).

// upstream: type TickLabel = ReturnType<AngleAxis['getViewLabels']>[number] & { coord: number };
//   The view-label item (AxisLabelInfoDetermined) augmented with an angle `coord` — modeled as a
//   struct wrapping the cloned label item (value-type copy) plus the computed `coord`.
private struct TickLabel {
    var labelItem: AxisLabelInfoDetermined
    var coord: Double
}

// Shared-`coord` protocol so `fixAngleOverlap` can operate on both `[AxisTickCoord]` and `[TickLabel]`
//   (upstream types both as `TickCoord[]` via structural `Pick<..., 'coord'>`).
private protocol AngleCoordItem {
    var coord: Double { get }
}
extension AxisTickCoord: AngleCoordItem {}
extension TickLabel: AngleCoordItem {}

// upstream: function fixAngleOverlap(list: TickCoord[]) — remove the last tick which overlaps the first.
//   Mutates the list in place (`list.pop()`) → `inout` (CONVENTIONS §3: JS mutates the array directly).
private func fixAngleOverlap<T: AngleCoordItem>(_ list: inout [T]) {
    let firstItem = list.first
    let lastItem = list.last
    if let firstItem = firstItem,
       let lastItem = lastItem,
       Swift.abs(Swift.abs(firstItem.coord - lastItem.coord) - 360) < 1e-4 {
        list.removeLast()   // upstream: list.pop();
    }
}

// upstream: class AngleAxisView extends AxisView
// CONVENTIONS §2: reference type extending the reference `AxisView` → `open class` (mirrors CartesianAxisView).
open class AngleAxisView: AxisView {

    // upstream: static readonly type = 'angleAxis';
    public static let angleAxisType = "angleAxis"
    // upstream: readonly type = AngleAxisView.type;
    open override var type: String {
        get { AngleAxisView.angleAxisType }
        set { /* readonly upstream */ }
    }

    // upstream: axisPointerClass = 'PolarAxisPointer';
    open override var axisPointerClass: String? {
        get { "PolarAxisPointer" }
        set { /* readonly upstream */ }
    }

    // upstream: render(angleAxisModel: AngleAxisModel, ecModel: GlobalModel)
    //   The base `AxisView.render` signature is typed `ComponentModel` (matching ComponentView); the
    //   concrete `AngleAxisModel` is recovered by downcast (same pattern as CartesianAxisView.render).
    open override func render(
        _ angleAxisModel: ComponentModel, _ ecModel: GlobalModel, _ api: ExtensionAPI, _ payload: Payload
    ) {
        let angleAxisModel = angleAxisModel as! AngleAxisModel

        self.group.removeAll()
        if !jsTruthy(angleAxisModel.get("show")) {
            return
        }

        let angleAxis = angleAxisModel.axis as! AngleAxis
        let polar: Polar = angleAxis.polar
        let radiusExtent = polar.getRadiusAxis().getExtent()

        var ticksAngles = angleAxis.getTicksCoords(GetTicksCoordsOpt(breakTicks: "none"))
        let minorTickAngles = angleAxis.getMinorTicksCoords()

        var labels: [TickLabel] = []
        util.each(angleAxis.getViewLabels(), { labelItemIn, _ in
            if labelItemIn.tick.offInterval == true {
                return
            }
            // upstream: labelItem = zrUtil.clone(labelItem);  (value-type copy)
            let labelItemCopy = labelItemIn
            let scale = angleAxis.scale
            let coord = angleAxis.dataToCoord(axisHelper.getTickValueOutermost(scale, labelItemCopy.tick))
            labels.append(TickLabel(labelItem: labelItemCopy, coord: coord))
        })

        fixAngleOverlap(&labels)
        fixAngleOverlap(&ticksAngles)

        util.each(elementList, { name, _ in
            // upstream: if (angleAxisModel.get([name,'show']) && (!angleAxis.scale.isBlank() || name === 'axisLine'))
            if jsTruthy(angleAxisModel.get([name, "show"]))
                && (!angleAxis.scale.isBlank() || name == "axisLine") {
                angelAxisElementsBuilders[name]!(
                    self.group, angleAxisModel, polar, ticksAngles, minorTickAngles, radiusExtent, labels
                )
            }
        })
    }

}

// upstream: interface AngleAxisElementBuilder { (group, angleAxisModel, polar, ticksAngles, minorTickAngles, radiusExtent, labels?): void }
private typealias AngleAxisElementBuilder = (
    _ group: Group,
    _ angleAxisModel: AngleAxisModel,
    _ polar: Polar,
    _ ticksAngles: [AxisTickCoord],
    _ minorTickAngles: [[AxisTickCoord]],
    _ radiusExtent: [Double],
    _ labels: [TickLabel]?
) -> Void

// upstream: const angelAxisElementsBuilders: Record<typeof elementList[number], AngleAxisElementBuilder> = { ... }
//   (NOTE: upstream mis-spells the identifier `angelAxisElementsBuilders` — preserved verbatim.)
private let angelAxisElementsBuilders: [String: AngleAxisElementBuilder] = [

    "axisLine": { group, angleAxisModel, polar, ticksAngles, minorTickAngles, radiusExtent, labels in
        let lineStyleModel = angleAxisModel.getModel(["axisLine", "lineStyle"])
        let angleAxis = polar.getAngleAxis()
        let RADIAN = Double.pi / 180
        let angleExtent = angleAxis.getExtent()

        // extent id of the axis radius (r0 and r)
        let rId = getRadiusIdx(polar)
        let r0Id = rId != 0 ? 0 : 1
        // upstream: const shapeType = Math.abs(angleExtent[1] - angleExtent[0]) === 360 ? 'Circle' : 'Arc';
        let isCircle = Swift.abs(angleExtent[1] - angleExtent[0]) == 360

        // upstream: shape.style.fill = null; — override the '#000' Circle/Arc/Ring default fill.
        var style = pathStyleFromDict(lineStyleModel.getLineStyle())
        style.fill = nil

        let shape: Path
        if radiusExtent[r0Id] == 0 {
            if isCircle {
                var circleShape = CircleShape()
                circleShape.cx = polar.cx
                circleShape.cy = polar.cy
                circleShape.r = radiusExtent[rId]
                shape = Circle([
                    "shape": circleShape as PathShape,
                    "style": style,
                    "z2": 1.0,
                    "silent": true
                ])
            }
            else {
                var arcShape = ArcShape()
                arcShape.cx = polar.cx
                arcShape.cy = polar.cy
                arcShape.r = radiusExtent[rId]
                arcShape.startAngle = -angleExtent[0] * RADIAN
                arcShape.endAngle = -angleExtent[1] * RADIAN
                arcShape.clockwise = angleAxis.inverse
                shape = Arc([
                    "shape": arcShape as PathShape,
                    "style": style,
                    "z2": 1.0,
                    "silent": true
                ])
            }
        }
        else {
            var ringShape = RingShape()
            ringShape.cx = polar.cx
            ringShape.cy = polar.cy
            ringShape.r = radiusExtent[rId]
            ringShape.r0 = radiusExtent[r0Id]
            shape = Ring([
                "shape": ringShape as PathShape,
                "style": style,
                "z2": 1.0,
                "silent": true
            ])
        }
        // BUGFIX (visual-parity): upstream sets `shape.style.fill = null` to unset the '#000' Path default,
        //   but `extendPathStyle` (applied when the shape's `style` prop merges) SKIPS a nil `fill`, so the
        //   Circle/Arc/Ring kept the default BLACK fill → the whole polar disk rendered solid black. Assign
        //   the fill directly on the built shape to actually clear it (bypassing the nil-skipping merge).
        shape.pathStyle.fill = nil
        _ = group.add(shape)
    },

    "axisTick": { group, angleAxisModel, polar, ticksAngles, minorTickAngles, radiusExtent, labels in
        let tickModel = angleAxisModel.getModel("axisTick")

        // upstream: (tickModel.get('inside') ? -1 : 1) * tickModel.get('length')
        let tickLen = (jsTruthy(tickModel.get("inside")) ? -1.0 : 1.0) * (asNumberOpt(tickModel.get("length")) ?? 0)
        let radius = radiusExtent[getRadiusIdx(polar)]

        let lines = util.map(ticksAngles, { tickAngleItem, _ -> Path in
            return Line([
                "shape": getAxisLineShape(polar, [radius, radius + tickLen], tickAngleItem.coord) as PathShape
            ])
        })
        // upstream: style: zrUtil.defaults(tickModel.getModel('lineStyle').getLineStyle(),
        //                                  { stroke: angleAxisModel.get(['axisLine','lineStyle','color']) })
        var styleDict = tickModel.getModel("lineStyle").getLineStyle()
        _ = util.defaults(&styleDict, ["stroke": angleAxisModel.get(["axisLine", "lineStyle", "color"]) as Any])
        _ = group.add(mergePath(lines, [
            "style": pathStyleFromDict(styleDict)
        ]))
    },

    "minorTick": { group, angleAxisModel, polar, tickAngles, minorTickAngles, radiusExtent, labels in
        if minorTickAngles.isEmpty {
            return
        }

        let tickModel = angleAxisModel.getModel("axisTick")
        let minorTickModel = angleAxisModel.getModel("minorTick")

        let tickLen = (jsTruthy(tickModel.get("inside")) ? -1.0 : 1.0) * (asNumberOpt(minorTickModel.get("length")) ?? 0)
        let radius = radiusExtent[getRadiusIdx(polar)]

        var lines: [Path] = []

        for i in 0..<minorTickAngles.count {
            for k in 0..<minorTickAngles[i].count {
                lines.append(Line([
                    "shape": getAxisLineShape(polar, [radius, radius + tickLen], minorTickAngles[i][k].coord) as PathShape
                ]))
            }
        }

        // upstream: style: defaults(minorTickModel.getModel('lineStyle').getLineStyle(),
        //                           defaults(tickModel.getLineStyle(), { stroke: angleAxisModel.get([...]) }))
        var innerDict = tickModel.getLineStyle()
        _ = util.defaults(&innerDict, ["stroke": angleAxisModel.get(["axisLine", "lineStyle", "color"]) as Any])
        var styleDict = minorTickModel.getModel("lineStyle").getLineStyle()
        _ = util.defaults(&styleDict, innerDict)
        _ = group.add(mergePath(lines, [
            "style": pathStyleFromDict(styleDict)
        ]))
    },

    "axisLabel": { group, angleAxisModel, polar, ticksAngles, minorTickAngles, radiusExtent, labels in
        let rawCategoryData = angleAxisModel.getCategories(true)

        let commonLabelModel = angleAxisModel.getModel("axisLabel")

        let labelMargin = asNumberOpt(commonLabelModel.get("margin")) ?? 0
        let triggerEvent = jsTruthy(angleAxisModel.get("triggerEvent"))

        // Use length of ticksAngles because it may remove the last tick to avoid overlapping
        util.each(labels, { labelItem, idx in
            let labelModel = commonLabelModel
            let tickValue = labelItem.labelItem.tick.value

            let r = radiusExtent[getRadiusIdx(polar)]
            let p = polar.coordToPoint([r + labelMargin, labelItem.coord])
            let cx = polar.cx
            let cy = polar.cy

            // upstream: const labelTextAlign = Math.abs(p[0]-cx)/r < 0.3 ? 'center' : (p[0] > cx ? 'left' : 'right');
            let labelTextAlign: TextAlign = Swift.abs(p[0] - cx) / r < 0.3
                ? .center : (p[0] > cx ? .left : .right)
            // upstream: const labelTextVerticalAlign = Math.abs(p[1]-cy)/r < 0.3 ? 'middle' : (p[1] > cy ? 'top' : 'bottom');
            let labelTextVerticalAlign: TextVerticalAlign = Swift.abs(p[1] - cy) / r < 0.3
                ? .middle : (p[1] > cy ? .top : .bottom)

            // upstream:
            //   if (rawCategoryData && rawCategoryData[tickValue]) {
            //       const rawCategoryItem = rawCategoryData[tickValue];
            //       if (zrUtil.isObject(rawCategoryItem) && rawCategoryItem.textStyle) {
            //           labelModel = new Model(rawCategoryItem.textStyle, commonLabelModel, commonLabelModel.ecModel);
            //       }
            //   }
            // PORT-TODO: per-category `textStyle` override. `getCategories(true)` here yields `[OrdinalRawValue]`
            //   (== [Any]); the raw category-item OBJECT form ({ value, textStyle }) that carries `textStyle`
            //   is not modeled by OrdinalRawValue, so the per-label `Model` override is deferred and
            //   `labelModel` stays `commonLabelModel`. Restore when the raw category-object option lands.
            _ = rawCategoryData
            _ = tickValue

            // upstream: fill: labelModel.getTextColor() || angleAxisModel.get(['axisLine','lineStyle','color'])
            let fill = labelModel.getTextColor()
                ?? (angleAxisModel.get(["axisLine", "lineStyle", "color"]) as? ColorString)

            var textStyle = createTextStyle(
                labelModel,
                text: labelItem.labelItem.formattedLabel,
                fill: fill,
                align: labelTextAlign,
                verticalAlign: labelTextVerticalAlign
            )
            // upstream: createTextStyle's opt sets `x`/`y` on the style (TextStyleProps carries x/y here).
            textStyle.x = p[0]
            textStyle.y = p[1]

            let textEl = ZRText([
                "silent": AxisBuilder.isLabelSilent(angleAxisModel),
                "style": textStyle
            ])
            _ = group.add(textEl)

            // upstream: graphic.setTooltipConfig({ el: textEl, componentModel: angleAxisModel,
            //   itemName: labelItem.formattedLabel, formatterParamsExtra: { isTruncated, value, tickIndex } });
            // PORT-TODO: `graphic.setTooltipConfig` (util/graphic tooltip-config seam) NOT ported;
            //   tooltip wiring is deferred (static render scope, CONVENTIONS §5).

            // Pack data for mouse event
            if triggerEvent {
                // upstream:
                //   const eventData = AxisBuilder.makeAxisEventDataBase(angleAxisModel);
                //   eventData.targetType = 'axisLabel';
                //   eventData.value = labelItem.rawLabel;
                //   getECData(textEl).eventData = eventData;
                var eventData = AxisBuilder.makeAxisEventDataBase(angleAxisModel)
                eventData["targetType"] = "axisLabel"
                eventData["value"] = labelItem.labelItem.rawLabel
                // PORT-TODO: `getECData(textEl).eventData = eventData` — inner-store ECData seam NOT ported;
                //   the packed `eventData` is computed but not attached (event dispatch is out of scope).
                _ = eventData
            }
        })
    },

    "splitLine": { group, angleAxisModel, polar, ticksAngles, minorTickAngles, radiusExtent, labels in
        let splitLineModel = angleAxisModel.getModel("splitLine")
        let lineStyleModel = splitLineModel.getModel("lineStyle")
        let lineColorsRaw = lineStyleModel.get("color")
        var lineCount = 0

        // upstream: lineColors = lineColors instanceof Array ? lineColors : [lineColors];
        let lineColors: [Any?] = util.isArray(lineColorsRaw)
            ? ((lineColorsRaw as? [Any])?.map { $0 as Any? } ?? [lineColorsRaw])
            : [lineColorsRaw]

        // Guard the JS `lineCount % lineColors.length` — an explicit empty `color: []` makes the
        // count 0; JS `n % 0` is NaN (undefined bucket, skipped by the length-based batch loop → nothing
        // drawn), but Swift `%` by zero TRAPS. Match upstream's effective no-op.
        if lineColors.isEmpty { return }

        var splitLines: [[Path]] = []

        for i in 0..<ticksAngles.count {
            let colorIndex = (lineCount) % lineColors.count
            lineCount += 1   // upstream: (lineCount++)
            while splitLines.count <= colorIndex { splitLines.append([]) }
            splitLines[colorIndex].append(Line([
                "shape": getAxisLineShape(polar, radiusExtent, ticksAngles[i].coord) as PathShape
            ]))
        }

        // Simple optimization: batch the lines if color are the same
        let z = asNumberOpt(angleAxisModel.get("z"))
        for i in 0..<splitLines.count {
            // upstream: style: zrUtil.defaults({ stroke: lineColors[i % lineColors.length] }, lineStyleModel.getLineStyle())
            var styleDict: [String: Any] = ["stroke": lineColors[i % lineColors.count] as Any]
            _ = util.defaults(&styleDict, lineStyleModel.getLineStyle())
            var opts: [String: Any] = [
                "style": pathStyleFromDict(styleDict),
                "silent": true
            ]
            if let z = z { opts["z"] = z }
            _ = group.add(mergePath(splitLines[i], opts))
        }
    },

    "minorSplitLine": { group, angleAxisModel, polar, ticksAngles, minorTickAngles, radiusExtent, labels in
        if minorTickAngles.isEmpty {
            return
        }

        let minorSplitLineModel = angleAxisModel.getModel("minorSplitLine")
        let lineStyleModel = minorSplitLineModel.getModel("lineStyle")

        var lines: [Path] = []

        for i in 0..<minorTickAngles.count {
            for k in 0..<minorTickAngles[i].count {
                lines.append(Line([
                    "shape": getAxisLineShape(polar, radiusExtent, minorTickAngles[i][k].coord) as PathShape
                ]))
            }
        }

        var opts: [String: Any] = [
            "style": pathStyleFromDict(lineStyleModel.getLineStyle()),
            "silent": true
        ]
        if let z = asNumberOpt(angleAxisModel.get("z")) { opts["z"] = z }
        _ = group.add(mergePath(lines, opts))
    },

    "splitArea": { group, angleAxisModel, polar, ticksAngles, minorTickAngles, radiusExtent, labels in
        if ticksAngles.isEmpty {
            return
        }

        let splitAreaModel = angleAxisModel.getModel("splitArea")
        let areaStyleModel = splitAreaModel.getModel("areaStyle")
        let areaColorsRaw = areaStyleModel.get("color")
        var lineCount = 0

        // upstream: areaColors = areaColors instanceof Array ? areaColors : [areaColors];
        let areaColors: [Any?] = util.isArray(areaColorsRaw)
            ? ((areaColorsRaw as? [Any])?.map { $0 as Any? } ?? [areaColorsRaw])
            : [areaColorsRaw]

        // See splitLine: guard `lineCount % areaColors.count` against an explicit empty `color: []`
        // (Swift `%` by zero traps; upstream's NaN bucket draws nothing).
        if areaColors.isEmpty { return }

        var splitAreas: [[Path]] = []

        let RADIAN = Double.pi / 180
        var prevAngle = -ticksAngles[0].coord * RADIAN
        let r0 = Swift.min(radiusExtent[0], radiusExtent[1])
        let r1 = Swift.max(radiusExtent[0], radiusExtent[1])

        let clockwise = jsTruthy(angleAxisModel.get("clockwise"))

        // upstream: for (let i = 1, len = ticksAngles.length; i <= len; i++)
        let len = ticksAngles.count
        var i = 1
        while i <= len {
            let coord = i == len ? ticksAngles[0].coord : ticksAngles[i].coord
            let colorIndex = (lineCount) % areaColors.count
            lineCount += 1   // upstream: (lineCount++)
            while splitAreas.count <= colorIndex { splitAreas.append([]) }

            var sectorShape = SectorShape()
            sectorShape.cx = polar.cx
            sectorShape.cy = polar.cy
            sectorShape.r0 = r0
            sectorShape.r = r1
            sectorShape.startAngle = prevAngle
            sectorShape.endAngle = -coord * RADIAN
            sectorShape.clockwise = clockwise
            splitAreas[colorIndex].append(Sector([
                "shape": sectorShape as PathShape,
                "silent": true
            ]))
            prevAngle = -coord * RADIAN
            i += 1
        }

        // Simple optimization: batch the lines if color are the same
        for i in 0..<splitAreas.count {
            // upstream: style: zrUtil.defaults({ fill: areaColors[i % areaColors.length] }, areaStyleModel.getAreaStyle())
            var styleDict: [String: Any] = ["fill": areaColors[i % areaColors.count] as Any]
            _ = util.defaults(&styleDict, areaStyleModel.getAreaStyle())
            _ = group.add(mergePath(splitAreas[i], [
                "style": pathStyleFromDict(styleDict),
                "silent": true
            ]))
        }
    }
]

// export default AngleAxisView;  -> `open class AngleAxisView` above.


// ============================================================================
// PORT-NOTE helpers — NOT part of AngleAxisView.ts upstream. These reproduce the
// dynamic-option coercion + the `util/graphic` style-bag bridge referenced above.
// Delete each when its real sibling lands and call the sibling directly.
// ============================================================================

/// Int|Double|NSNumber → Double coercion for the `[String: Any]` option bag. The default-option store
/// keeps numbers as bare `Int` literals (e.g. `length: 5`, `margin: 8`, `z: 0`), so a bare `as? Double`
/// SILENTLY DROPS them (CONVENTIONS: INT-vs-DOUBLE trap). Mirrors the `asNumberOpt` helpers used across
/// the polar/graph layout ports.
private func asNumberOpt(_ v: Any?) -> Double? {
    if let d = v as? Double { return d }
    if let i = v as? Int { return Double(i) }
    if let n = v as? NSNumber { return n.doubleValue }
    return nil
}

/// JS truthiness for the dynamic option bag (`if (x)` / `angleAxisModel.get('show')`), replicating
/// JS-falsy semantics for numbers/strings (CONVENTIONS §6 — do NOT use Swift `??`). Mirrors the same
/// file-private helper in RadarComponentView/TitleView/AxisBuilder.
private func jsTruthy(_ v: Any?) -> Bool {
    guard let v = v else { return false }
    if let b = v as? Bool { return b }
    if let d = v as? Double { return d != 0 && !d.isNaN }
    if let i = v as? Int { return i != 0 }
    if let s = v as? String { return !s.isEmpty }
    return true
}

/// PORT-NOTE: `util/graphic` style-bag bridge. `Model.getLineStyle()` / `getAreaStyle()` return the
///   dynamic `[String: Any]` paint bag (makeStyleMapper output, keyed by PathStyleProps field names);
///   ZRenderKit `Path`'s `style` prop is a typed `PathStyleProps`. This maps the common line/area paint
///   keys (stroke + fill) so the axis-line / ticks / split-lines / split-areas are actually drawn.
///   Same deviation as CartesianAxisView.lineStylePropsFromDict / RadarComponentView.pathStyleFromDict.
///   `lineDash` (number | number[]) is not bridged yet (LineDash enum). Delete when the bridge lands.
// Coerce a dynamic style-bag number tolerating Int boxing (e.g. lineWidth: 2 as an Int literal);
// a bare `as? Double` drops the value (the recurring Int-vs-Double option-read trap).
private func styleNum(_ v: Any?) -> Double? {
    if let d = v as? Double { return d }
    if let i = v as? Int { return Double(i) }
    if let n = v as? NSNumber, !(n === kCFBooleanTrue || n === kCFBooleanFalse) { return n.doubleValue }
    return nil
}

private func pathStyleFromDict(_ dict: [String: Any]) -> PathStyleProps {
    var s = PathStyleProps()
    // PORT-TODO: `fill`/`stroke` may be a gradient/pattern object (ZRColor non-string); only the String
    //   form (incl. the sentinel 'none') is mapped here.
    if let fill = dict["fill"] as? String { s.fill = .string(fill) }
    if let stroke = dict["stroke"] as? String { s.stroke = .string(stroke) }
    if let lineWidth = styleNum(dict["lineWidth"]) { s.lineWidth = lineWidth }
    if let lineCap = dict["lineCap"] as? String { s.lineCap = lineCap }
    if let lineJoin = dict["lineJoin"] as? String { s.lineJoin = lineJoin }
    if let opacity = styleNum(dict["opacity"]) { s.opacity = opacity }
    if let shadowBlur = styleNum(dict["shadowBlur"]) { s.shadowBlur = shadowBlur }
    if let shadowOffsetX = styleNum(dict["shadowOffsetX"]) { s.shadowOffsetX = shadowOffsetX }
    if let shadowOffsetY = styleNum(dict["shadowOffsetY"]) { s.shadowOffsetY = shadowOffsetY }
    if let shadowColor = dict["shadowColor"] as? String { s.shadowColor = shadowColor }
    if let lineDashOffset = styleNum(dict["lineDashOffset"]) { s.lineDashOffset = lineDashOffset }
    if let miterLimit = styleNum(dict["miterLimit"]) { s.miterLimit = miterLimit }
    // PORT-TODO: `lineDash` (number[] | false) mapping deferred (LineDash enum bridge).
    return s
}
