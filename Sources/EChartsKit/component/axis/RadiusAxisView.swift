// Ported from echarts/src/component/axis/RadiusAxisView.ts — keep in sync with upstream
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
//   import * as zrUtil from 'zrender/src/core/util';               → `util.*` (ZRenderKit; each/defaults).
//   import * as graphic from '../../util/graphic';
//     → `util/graphic` is NOT ported as a namespace. `graphic.Group` / `graphic.Circle` / `graphic.Arc`
//       / `graphic.Sector` are the ZRenderKit scene-graph shapes (used directly — the sanctioned DRAWING
//       deviation, cf. RadarComponentView). `graphic.mergePath` → ZRenderKit `mergePath` (Tool/ToolPath).
//       `graphic.groupTransition` (anid-matched transition animation) → the top-level free function
//       `groupTransition` in `util/graphic.swift` (called in `render`).
//       Note upstream indexes `graphic[shapeType]` with shapeType ∈ {'Circle','Arc'}; the
//       dynamic constructor lookup is replaced by an explicit branch (see the splitLine builder).
//   import AxisBuilder from './AxisBuilder';                       → `AxisBuilder` (component/axis/AxisBuilder.swift).
//   import AxisView from './AxisView';                             → `AxisView` (component/axis/AxisView.swift).
//   import { RadiusAxisModel } from '../../coord/polar/AxisModel';
//     → RadiusAxisModel IS ported (coord/polar/PolarAxisModel.swift — the whole polar coord system is
//       ported). API (mirrors CartesianAxisModel / RadarModel):
//         open class RadiusAxisModel: AxisBaseModel   // → so AxisBuilder(radiusAxisModel, …) type-checks
//           var axis: Any                              // inherited AxisBaseModel.axis, downcast to RadiusAxis
//       Registered component view `type` is 'radiusAxis'.
//   import Polar from '../../coord/polar/Polar';
//     → Polar IS ported (coord/polar/Polar.swift — a sibling angle/radius coord system,
//       the analogue of Radar). API:
//         final class Polar: CoordinateSystemMaster { var cx: Double; var cy: Double
//                                                      func getAngleAxis() -> AngleAxis
//                                                      func getRadiusAxis() -> RadiusAxis }
//   import RadiusAxis from '../../coord/polar/RadiusAxis';
//     → RadiusAxis IS ported (coord/polar/RadiusAxis.swift). API:
//         open class RadiusAxis: Axis { var polar: Polar
//                                       func getMinorTicksCoords() -> [[AxisTickCoord]] }
//       (inherits `getTicksCoords()` / `getExtent()` / `scale` from the ported `open class Axis`).
//   import GlobalModel from '../../model/Global';                  → `GlobalModel`.
//   import ExtensionAPI from '../../core/ExtensionAPI';            → `ExtensionAPI`.
//   The sibling `AngleAxis` (polar.getAngleAxis()) is likewise a ported polar sibling
//   (`public final class AngleAxis: Axis`), used here only for `getExtent()` and the inherited `inverse` flag.

// upstream: const selfBuilderAttrs = ['splitLine', 'splitArea', 'minorSplitLine'] as const;
private let selfBuilderAttrs: [String] = [
    "splitLine", "splitArea", "minorSplitLine"
]

// upstream: type TickCoord = ReturnType<RadiusAxis['getTicksCoords']>[number];  → `AxisTickCoord`.

// upstream: class RadiusAxisView extends AxisView { ... }
// CONVENTIONS §2: reference type, not subclassed upstream → `final class` (extending the reference
//   `open class AxisView`). `type` / `axisPointerClass` override the base `open var`s as computed
//   read-only properties (the upstream fields are `readonly`; cf. CartesianAxisView).
final class RadiusAxisView: AxisView {

    // upstream: static readonly type = 'radiusAxis';
    public static let radiusAxisType = "radiusAxis"
    // upstream: readonly type = RadiusAxisView.type;
    override var type: String {
        get { RadiusAxisView.radiusAxisType }
        set { /* readonly upstream */ }
    }

    // upstream: axisPointerClass = 'PolarAxisPointer';
    override var axisPointerClass: String? {
        get { "PolarAxisPointer" }
        set { /* readonly upstream */ }
    }

    // upstream: private _axisGroup: graphic.Group;
    private var _axisGroup: Group!

    // upstream: render(radiusAxisModel: RadiusAxisModel, ecModel: GlobalModel, api: ExtensionAPI)
    //   The base `AxisView.render` signature is (model: ComponentModel, ecModel, api, payload); upstream
    //   RadiusAxisView.render declares only (radiusAxisModel, ecModel, api). The override matches the full
    //   base signature and narrows `model` to `RadiusAxisModel` by downcast (cf. CartesianAxisView.render).
    //   NOTE: upstream RadiusAxisView.render does NOT call `super.render` (unlike CartesianAxisView) — the
    //   axisPointer wiring is skipped here; preserved faithfully (no super call).
    override func render(
        _ radiusAxisModel: ComponentModel, _ ecModel: GlobalModel, _ api: ExtensionAPI, _ payload: Payload
    ) {
        let radiusAxisModel = radiusAxisModel as! RadiusAxisModel

        self.group.removeAll()
        // upstream: if (!radiusAxisModel.get('show')) { return; }
        if !jsTruthy(radiusAxisModel.get("show")) {
            return
        }

        let oldAxisGroup = self._axisGroup
        // upstream: const newAxisGroup = this._axisGroup = new graphic.Group();
        let newAxisGroup = Group()
        self._axisGroup = newAxisGroup
        _ = self.group.add(newAxisGroup)

        // upstream: const radiusAxis = radiusAxisModel.axis;
        //   `RadiusAxisModel.axis` is typed `Any` (AxisBaseModel.axis) → downcast to `RadiusAxis`.
        let radiusAxis = radiusAxisModel.axis as! RadiusAxis
        let polar: Polar = radiusAxis.polar
        let angleAxis = polar.getAngleAxis()
        let ticksCoords = radiusAxis.getTicksCoords()
        let minorTicksCoords = radiusAxis.getMinorTicksCoords()
        let axisAngle = angleAxis.getExtent()[0]
        let radiusExtent = radiusAxis.getExtent()

        let layout = layoutAxis(polar, radiusAxisModel, axisAngle)
        let axisBuilder = AxisBuilder(radiusAxisModel, api, layout)
        axisBuilder.build()
        _ = newAxisGroup.add(axisBuilder.group)

        // upstream: graphic.groupTransition(oldAxisGroup, newAxisGroup, radiusAxisModel);
        //   `groupTransition` is a top-level free function in `util/graphic.swift`: it matches old/new
        //   elements by `anid` (set by AxisBuilder on the axis line, name, ticks and labels) and
        //   animates the transition via `updateProps` (its `getAnimatableProps` flattens `shape` into the
        //   shape's animatable numeric keys, so the axis line and ticks — `Line`s whose whole geometry
        //   lives in `shape` — tween instead of snapping; see the PORT-NOTE there).
        //   `oldAxisGroup` is nil on the first render — the callee guards.
        groupTransition(oldAxisGroup, newAxisGroup, radiusAxisModel)

        // upstream: zrUtil.each(selfBuilderAttrs, function (name) { ... }, this);
        for name in selfBuilderAttrs {
            // upstream: if (radiusAxisModel.get([name, 'show']) && !radiusAxis.scale.isBlank())
            if jsTruthy(radiusAxisModel.get([name, "show"])) && !radiusAxis.scale.isBlank() {
                axisElementBuilders[name]!(
                    self.group,
                    radiusAxisModel,
                    polar,
                    axisAngle,
                    radiusExtent,
                    ticksCoords,
                    minorTicksCoords
                )
            }
        }
    }
}

// upstream: interface AxisElementBuilder {
//     (group, axisModel: RadiusAxisModel, polar: Polar, axisAngle: number, radiusExtent: number[],
//      ticksCoords: TickCoord[], minorTicksCoords?: TickCoord[][]): void
// }
//   Named `RadiusAxisElementBuilder` (not `AxisElementBuilder`) to avoid clashing with
//   CartesianAxisView.swift's same-module `AxisElementBuilder` typealias.
typealias RadiusAxisElementBuilder = (
    _ group: Group,
    _ axisModel: RadiusAxisModel,
    _ polar: Polar,
    _ axisAngle: Double,
    _ radiusExtent: [Double],
    _ ticksCoords: [AxisTickCoord],
    _ minorTicksCoords: [[AxisTickCoord]]?
) -> Void

// upstream: const axisElementBuilders: Record<typeof selfBuilderAttrs[number], AxisElementBuilder> = { ... }
private let axisElementBuilders: [String: RadiusAxisElementBuilder] = [

    "splitLine": { group, radiusAxisModel, polar, axisAngle, radiusExtent, ticksCoords, minorTicksCoords in
        let splitLineModel = radiusAxisModel.getModel("splitLine")
        let lineStyleModel = splitLineModel.getModel("lineStyle")
        // upstream: let lineColors = lineStyleModel.get('color');
        let lineColorsRaw = lineStyleModel.get("color")
        var lineCount = 0

        let angleAxis = polar.getAngleAxis()
        let RADIAN = Double.pi / 180
        let angleExtent = angleAxis.getExtent()
        // upstream: Math.abs(angleExtent[1] - angleExtent[0]) === 360 ? 'Circle' : 'Arc'
        let shapeType = abs(angleExtent[1] - angleExtent[0]) == 360 ? "Circle" : "Arc"

        // upstream: lineColors = lineColors instanceof Array ? lineColors : [lineColors];
        let lineColors: [Any?] = util.isArray(lineColorsRaw)
            ? ((lineColorsRaw as? [Any])?.map { $0 as Any? } ?? [lineColorsRaw])
            : [lineColorsRaw]

        // Guard `lineCount % lineColors.count` against an explicit empty `color: []` — Swift `%` by
        // zero traps, whereas upstream's NaN bucket draws nothing.
        if lineColors.isEmpty { return }

        // upstream: const splitLines: graphic.Circle[][] = [];
        //   Circle / Arc both subclass ZRenderKit `Path`; the shared bucket type is `Path`.
        var splitLines: [[Path]] = []

        for i in 0..<ticksCoords.count {
            // upstream: const colorIndex = (lineCount++) % lineColors.length;
            let colorIndex = lineCount % lineColors.count
            lineCount += 1
            // upstream: splitLines[colorIndex] = splitLines[colorIndex] || [];
            while splitLines.count <= colorIndex { splitLines.append([]) }
            // upstream: splitLines[colorIndex].push(new graphic[shapeType]({ shape: {...} }));
            //   `graphic[shapeType]` is a dynamic Circle/Arc constructor lookup → explicit branch. The
            //   extra `startAngle`/`endAngle`/`clockwise` shape props are only meaningful on Arc; on the
            //   Circle branch upstream passes them too but `CircleShape` ignores them (only cx/cy/r).
            // ensure circle radius >= 0
            let r = Swift.max(ticksCoords[i].coord, 0)
            let el: Path
            if shapeType == "Circle" {
                var s = CircleShape()
                s.cx = polar.cx
                s.cy = polar.cy
                s.r = r
                el = Circle(["shape": s])
            }
            else {
                var s = ArcShape()
                s.cx = polar.cx
                s.cy = polar.cy
                s.r = r
                s.startAngle = -angleExtent[0] * RADIAN
                s.endAngle = -angleExtent[1] * RADIAN
                s.clockwise = angleAxis.inverse
                el = Arc(["shape": s])
            }
            splitLines[colorIndex].append(el)
        }

        // Simple optimization
        // Batching the lines if color are the same
        for i in 0..<splitLines.count {
            // upstream: style: zrUtil.defaults({ stroke: lineColors[i % lineColors.length], fill: null },
            //   lineStyleModel.getLineStyle())
            var styleDict: [String: Any] = [:]
            if let c = lineColors[i % lineColors.count] { styleDict["stroke"] = c }
            styleDict["fill"] = NSNull()   // upstream: fill: null
            let lineStyle = lineStyleModel.getLineStyle()
            _ = util.defaults(&styleDict, lineStyle)
            let mp = mergePath(
                splitLines[i], [
                    "style": pathStyleFromDict(styleDict),
                    "silent": true
                ]
            )
            // BUGFIX: the concentric split-line Circles/Arcs default to the '#000' Path fill; the `fill:null`
            //   in the style is dropped by extendPathStyle (nil-skip) → rings rendered as solid black disks.
            //   Clear the fill directly on the merged path (stroke-only line).
            mp.pathStyle.fill = nil
            _ = group.add(mp)
        }
    },

    "minorSplitLine": { group, radiusAxisModel, polar, axisAngle, radiusExtent, ticksCoords, minorTicksCoords in
        // upstream: if (!minorTicksCoords.length) { return; }
        guard let minorTicksCoords = minorTicksCoords, !minorTicksCoords.isEmpty else {
            return
        }

        let minorSplitLineModel = radiusAxisModel.getModel("minorSplitLine")
        let lineStyleModel = minorSplitLineModel.getModel("lineStyle")

        // upstream: const lines: graphic.Circle[] = [];
        var lines: [Path] = []

        for i in 0..<minorTicksCoords.count {
            for k in 0..<minorTicksCoords[i].count {
                var s = CircleShape()
                s.cx = polar.cx
                s.cy = polar.cy
                s.r = minorTicksCoords[i][k].coord
                lines.append(Circle(["shape": s]))
            }
        }

        // upstream: style: zrUtil.defaults({ fill: null }, lineStyleModel.getLineStyle())
        var styleDict: [String: Any] = [:]
        styleDict["fill"] = NSNull()   // upstream: fill: null
        let lineStyle = lineStyleModel.getLineStyle()
        _ = util.defaults(&styleDict, lineStyle)
        let mp = mergePath(
            lines, [
                "style": pathStyleFromDict(styleDict),
                "silent": true
            ]
        )
        mp.pathStyle.fill = nil   // BUGFIX: clear the '#000' default on the stroke-only minor split circles
        _ = group.add(mp)
    },

    "splitArea": { group, radiusAxisModel, polar, axisAngle, radiusExtent, ticksCoords, minorTicksCoords in
        // upstream: if (!ticksCoords.length) { return; }
        if ticksCoords.isEmpty {
            return
        }

        let splitAreaModel = radiusAxisModel.getModel("splitArea")
        let areaStyleModel = splitAreaModel.getModel("areaStyle")
        // upstream: let areaColors = areaStyleModel.get('color');
        let areaColorsRaw = areaStyleModel.get("color")
        var lineCount = 0

        // upstream: areaColors = areaColors instanceof Array ? areaColors : [areaColors];
        let areaColors: [Any?] = util.isArray(areaColorsRaw)
            ? ((areaColorsRaw as? [Any])?.map { $0 as Any? } ?? [areaColorsRaw])
            : [areaColorsRaw]

        // Guard `lineCount % areaColors.count` against an explicit empty `color: []` (Swift `%` by
        // zero traps; upstream's NaN bucket draws nothing).
        if areaColors.isEmpty { return }

        // upstream: const splitAreas: graphic.Sector[][] = [];
        var splitAreas: [[Path]] = []

        // upstream: let prevRadius = ticksCoords[0].coord;
        var prevRadius = ticksCoords[0].coord
        for i in 1..<ticksCoords.count {
            // upstream: const colorIndex = (lineCount++) % areaColors.length;
            let colorIndex = lineCount % areaColors.count
            lineCount += 1
            // upstream: splitAreas[colorIndex] = splitAreas[colorIndex] || [];
            while splitAreas.count <= colorIndex { splitAreas.append([]) }
            var s = SectorShape()
            s.cx = polar.cx
            s.cy = polar.cy
            s.r0 = prevRadius
            s.r = ticksCoords[i].coord
            s.startAngle = 0
            s.endAngle = Double.pi * 2
            let sector = Sector([
                "shape": s,
                "silent": true
            ])
            splitAreas[colorIndex].append(sector)
            prevRadius = ticksCoords[i].coord
        }

        // Simple optimization
        // Batching the lines if color are the same
        for i in 0..<splitAreas.count {
            // upstream: style: zrUtil.defaults({ fill: areaColors[i % areaColors.length] },
            //   areaStyleModel.getAreaStyle())
            var styleDict: [String: Any] = [:]
            if let c = areaColors[i % areaColors.count] { styleDict["fill"] = c }
            let areaStyle = areaStyleModel.getAreaStyle()
            _ = util.defaults(&styleDict, areaStyle)
            _ = group.add(mergePath(
                splitAreas[i], [
                    "style": pathStyleFromDict(styleDict),
                    "silent": true
                ]
            ))
        }
    }
]

/**
 * @inner
 */
// upstream: function layoutAxis(polar, radiusAxisModel, axisAngle) {
//     return { position, rotation, labelDirection: -1, tickDirection: -1, nameDirection: 1,
//              labelRotate: ..., z2: 1 };
// }
//   Return type is structurally an `AxisBuilderCfg` (consumed by `new AxisBuilder(..., layout)`), so it
//   is built as one here. The `z2: 1` field ("Over splitLine and splitArea") is NOT part of
//   `AxisBuilderCfg` upstream and is dropped — same deviation as CartesianAxisLayout → AxisBuilderCfg.
//   PORT-NOTE: the axis-line/ticks/labels z2 ordering (draw above split lines/areas) is not reproduced
//   (z2 is not part of AxisBuilderCfg; same deviation as CartesianAxisLayout → AxisBuilderCfg).
private func layoutAxis(_ polar: Polar, _ radiusAxisModel: RadiusAxisModel, _ axisAngle: Double) -> AxisBuilderCfg {
    return AxisBuilderCfg(
        position: [polar.cx, polar.cy],
        rotation: axisAngle / 180 * Double.pi,
        nameDirection: 1,
        tickDirection: -1,
        labelDirection: -1,
        // upstream: labelRotate: radiusAxisModel.getModel('axisLabel').get('rotate')
        labelRotate: numOpt(radiusAxisModel.getModel("axisLabel").get("rotate"))
    )
}

// export default RadiusAxisView;  → `final class RadiusAxisView` above.


// ============================================================================
// PORT-NOTE helpers — NOT part of RadiusAxisView.ts upstream. They reproduce the
// dynamic-option-read coercions and the `util/graphic` style-bag bridge referenced
// above. Delete each when its real sibling lands and call the sibling directly.
// (Mirrors the same file-private helpers in RadarComponentView / CartesianAxisView.)
// ============================================================================

/// Coerce a dynamic option value to Double, tolerating the Int boxing that `[String: Any]`
/// defaultOption literals use (e.g. a bare `"rotate": 0`). A bare `as? Double` returns nil on an Int,
/// which silently drops the value — the recurring Int-vs-Double option-read trap (CONVENTIONS trap #1).
private func numOpt(_ v: Any?) -> Double? {
    if let d = v as? Double { return d }
    if let i = v as? Int { return Double(i) }
    if let n = v as? NSNumber, !(n === kCFBooleanTrue || n === kCFBooleanFalse) { return n.doubleValue }
    return nil
}

/// JS truthiness for the dynamic option bag (`if (x)` on `get(...)` results); mirrors the same
/// file-private helper in RadarComponentView/TitleView (CONVENTIONS §6).
private func jsTruthy(_ v: Any?) -> Bool {
    guard let v = v else { return false }
    if let b = v as? Bool { return b }
    if let d = v as? Double { return d != 0 && !d.isNaN }
    if let i = v as? Int { return i != 0 }
    if let s = v as? String { return !s.isEmpty }
    return true
}

/// PORT-NOTE (deferred): requires `util/graphic`'s `useStyle` dict bridge, not ported. Map the dynamic style bag
///   ([String: Any] — the `defaults(...)` merge of split colors over getLineStyle()/getAreaStyle()) onto
///   the typed `PathStyleProps`. Same deviation as RadarComponentView.pathStyleFromDict; mirrored here for
///   both stroke (split/minor lines) and fill (split areas). The sentinel `NSNull()` (upstream `fill: null`)
///   maps to no fill. Delete when the graphic style bridge lands.
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
    // `fill`/`stroke` may be a String, a gradient (`{type:'linear'|'radial', colorStops, ...}`) or an
    //   image pattern (`{image, repeat, ...}`) option object — all preserved via `radiusPaintFromStyleValue`.
    //   `NSNull` (upstream null) → nil → the paint is left unset.
    if let fill = radiusPaintFromStyleValue(dict["fill"]) { s.fill = fill }
    if let stroke = radiusPaintFromStyleValue(dict["stroke"]) { s.stroke = stroke }
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
    // upstream: `lineDash?: false | number[] | 'solid' | 'dashed' | 'dotted'` → ZRenderKit `LineDash`.
    if let dash = dict["lineDash"] as? [Double] {
        s.lineDash = .values(dash)
    } else if let dashInt = dict["lineDash"] as? [Int] {
        s.lineDash = .values(dashInt.map(Double.init))
    } else if let b = dict["lineDash"] as? Bool, b == false {
        s.lineDash = .false
    } else if let dashStr = dict["lineDash"] as? String {
        switch dashStr {
        case "solid": s.lineDash = .solid
        case "dashed": s.lineDash = .dashed
        case "dotted": s.lineDash = .dotted
        default: break
        }
    }
    return s
}

/// Coerce a dynamic style-bag paint value (`fill`/`stroke`) to a ZRenderKit `ZRColor`, preserving the
///   gradient/pattern forms upstream carries through the `defaults(...)` merge (previously only the String
///   form was mapped, silently dropping split colors declared as gradients/patterns). Mirrors
///   BarView.zrPaintFromStyleValue (the file-private per-view paint bridge). Handled forms:
///     - `String`                                      → solid color
///     - a `ZRenderKit.ZRColor` / typed `EChartsKit.ZRColor.color` → passthrough
///     - `{type:'linear'|'radial', colorStops, x, y, ...}` option dict → gradient
///     - `{image, repeat, x, y, rotation, scaleX, scaleY}` option dict → image pattern
///   `NSNull` (upstream `fill: null`) and any other value → nil (paint left unset).
private func radiusPaintFromStyleValue(_ v: Any?) -> ZRenderKit.ZRColor? {
    if let str = v as? String { return .string(str) }
    if let zr = v as? ZRenderKit.ZRColor { return zr }
    if let zr = v as? EChartsKit.ZRColor, case let .color(str) = zr { return .string(str) }

    if let dict = v as? [String: Any] {
        // Image-pattern option object: `{image: <dataURI|url>, repeat, x, y, rotation, scaleX, scaleY}`.
        if let pat = radiusPatternFromDict(dict) {
            return .pattern(pat)
        }
        if let type = dict["type"] as? String {
            let stops = radiusGradientColorStopsFromAny(dict["colorStops"])
            let global = dict["global"] as? Bool
            if type == "linear" {
                return .linearGradient(ZRenderKit.LinearGradient(
                    styleNum(dict["x"]), styleNum(dict["y"]), styleNum(dict["x2"]), styleNum(dict["y2"]),
                    stops, global))
            }
            else if type == "radial" {
                return .radialGradient(ZRenderKit.RadialGradient(
                    styleNum(dict["x"]), styleNum(dict["y"]), styleNum(dict["r"]),
                    stops, global))
            }
        }
    }

    return nil
}

/// Build a ZRenderKit `Pattern` from an image-pattern option dict. Returns nil unless a usable image
///   string is present (the `image` arm — a `data:` URI or URL/path). Mirrors BarView.zrPatternFromDict.
private func radiusPatternFromDict(_ dict: [String: Any]) -> ZRenderKit.Pattern? {
    guard let image = dict["image"] as? String, !image.isEmpty else { return nil }
    let repeatMode = (dict["repeat"] as? String).flatMap { ImagePatternRepeat(rawValue: $0) } ?? .repeat
    let pat = ZRenderKit.Pattern(.url(image), repeatMode)
    if let x = styleNum(dict["x"]) { pat.x = x }
    if let y = styleNum(dict["y"]) { pat.y = y }
    if let r = styleNum(dict["rotation"]) { pat.rotation = r }
    if let sx = styleNum(dict["scaleX"]) { pat.scaleX = sx }
    if let sy = styleNum(dict["scaleY"]) { pat.scaleY = sy }
    return pat
}

/// Parse `colorStops: [{offset, color}, ...]` (the option-dict gradient form) into ZRenderKit stops.
///   Mirrors BarView.gradientColorStopsFromAny.
private func radiusGradientColorStopsFromAny(_ v: Any?) -> [ZRenderKit.GradientColorStop] {
    guard let arr = v as? [Any] else { return [] }
    var out: [ZRenderKit.GradientColorStop] = []
    for item in arr {
        guard let d = item as? [String: Any] else { continue }
        let offset = styleNum(d["offset"]) ?? 0
        let color = (d["color"] as? String) ?? ""
        out.append(ZRenderKit.GradientColorStop(offset: offset, color: color))
    }
    return out
}
