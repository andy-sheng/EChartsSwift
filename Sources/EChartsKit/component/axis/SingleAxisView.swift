// Ported from echarts/src/component/axis/SingleAxisView.ts — keep in sync with upstream
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
//   import * as zrUtil from 'zrender/src/core/util';               → `util.*` (ZRenderKit; each/defaults/isArray).
//   import AxisBuilder from './AxisBuilder';                       → `AxisBuilder` (component/axis/AxisBuilder.swift).
//   import * as graphic from '../../util/graphic';
//     → `util/graphic` is NOT ported as a namespace. `graphic.Group` / `graphic.Line` are the ZRenderKit
//       scene-graph types (used directly — the sanctioned DRAWING deviation, cf. CartesianAxisView /
//       RadiusAxisView). `graphic.mergePath` → ZRenderKit `mergePath` (Tool/ToolPath).
//       `graphic.subPixelOptimizeLine` → the file-private value-returning wrapper below (delegates to
//       `subPixelOptimizeNS.subPixelOptimizeLine`, mirroring CartesianAxisView). `graphic.groupTransition`
//       (anid-matched transition animation) is deferred (see the PORT-TODO in `render`).
//   import * as singleAxisHelper from '../../coord/single/singleAxisHelper';
//     → PORT-TODO: `coord/single/singleAxisHelper` is a sibling landing this SINGLE-coord phase. Assumed
//       API (free-function module → caseless enum, CONVENTIONS §2): `enum singleAxisHelper { static func
//       layout(_ axisModel: SingleAxisModel, _ opt: SingleAxisLayoutOpt? = nil) -> AxisBuilderCfg }`.
//       Upstream `layout` returns a `LayoutResult` (position/rotation/labelRotate/labelDirection/
//       tickDirection/nameDirection + `z2`) that is structurally an `AxisBuilderCfg` (the `z2:1` field is
//       dropped, same deviation as CartesianAxisLayout / RadiusAxisView.layoutAxis → AxisBuilderCfg).
//   import AxisView from './AxisView';                             → `AxisView` (component/axis/AxisView.swift).
//   import {rectCoordAxisBuildSplitArea, rectCoordAxisHandleRemove} from './axisSplitHelper';
//     → PORT-TODO: `component/axis/axisSplitHelper` NOT ported (splitArea alternating colors + inner-store
//       cache). `rectCoordAxisBuildSplitArea` (splitArea builder) and `rectCoordAxisHandleRemove` (remove)
//       are deferred with documented PORT-TODOs below (same deviation as CartesianAxisView).
//   import SingleAxisModel from '../../coord/single/AxisModel';
//     → PORT-TODO: `coord/single/AxisModel` (SingleAxisModel) is a sibling landing this SINGLE-coord phase.
//       Named `SingleAxisModel.swift` (NOT `AxisModel.swift`) to avoid the SwiftPM object-name collision
//       with the cartesian/polar `AxisModel`. Assumed API (mirrors CartesianAxisModel / RadiusAxisModel):
//         open class SingleAxisModel: AxisBaseModel   // → so AxisBuilder(singleAxisModel, …) type-checks
//           var axis: Any                             // inherited AxisBaseModel.axis, downcast to SingleAxis
//           var coordinateSystem: Single!             // the coord-sys host (upstream `coordinateSystem: Single`)
//       Registered component view `type` is 'singleAxis'.
//   import GlobalModel from '../../model/Global';                  → `GlobalModel`.
//   import ExtensionAPI from '../../core/ExtensionAPI';            → `ExtensionAPI`.
//   import { Payload } from '../../util/types';                    → `Payload` (util/types.swift).
//   import { getAxisBreakHelper } from './axisBreakHelper';        → PORT-TODO: `component/axis/axisBreakHelper`
//     NOT ported (axis break feature); `getAxisBreakHelper()` returns nil, so `breakArea` is a no-op.
//
//   The sibling `Single` (SingleAxisModel.coordinateSystem) is a PORT-TODO SINGLE-coord sibling — the 4th
//   coordinate system (one axis), analogue of Grid/Polar. Assumed API:
//     final class Single: CoordinateSystemMaster { func getRect() -> LayoutRect }
//   The sibling `SingleAxis` (SingleAxisModel.axis) is a PORT-TODO SINGLE-coord sibling — a 1D cartesian-
//   like axis extending the ported `open class Axis`. Assumed API:
//     open class SingleAxis: Axis {
//         var position: String            // SingleAxisPosition: 'top'|'bottom'|'left'|'right'
//         var orient: String              // LayoutOrient: 'horizontal'|'vertical'
//         var toGlobalCoord: ((Double) -> Double)!   // injected by Single (cf. Axis2D.toGlobalCoord)
//         func isHorizontal() -> Bool
//     }
//   (inherits `scale` / `getTicksCoords()` / `getExtent()` from the ported `open class Axis`).

// upstream: const selfBuilderAttrs = ['splitArea', 'splitLine', 'breakArea'] as const;
private let selfBuilderAttrs: [String] = [
    "splitArea", "splitLine", "breakArea"
]

// upstream: class SingleAxisView extends AxisView { ... }
// CONVENTIONS §2: reference type, not subclassed upstream → `final class` (extending the reference
//   `open class AxisView`). `type` / `axisPointerClass` override the base `open var`s as computed
//   read-only properties (the upstream fields are `readonly`; cf. CartesianAxisView / RadiusAxisView).
final class SingleAxisView: AxisView {

    // upstream: static readonly type = 'singleAxis';
    public static let singleAxisType = "singleAxis"
    // upstream: readonly type = SingleAxisView.type;
    override var type: String {
        get { SingleAxisView.singleAxisType }
        set { /* readonly upstream */ }
    }

    // upstream: private _axisGroup: graphic.Group;
    private var _axisGroup: Group!

    // upstream: axisPointerClass = 'SingleAxisPointer';
    override var axisPointerClass: String? {
        get { "SingleAxisPointer" }
        set { /* readonly upstream */ }
    }

    // upstream: render(axisModel: SingleAxisModel, ecModel: GlobalModel, api: ExtensionAPI, payload: Payload)
    //   The base `AxisView.render` signature is (model: ComponentModel, ecModel, api, payload); the concrete
    //   `SingleAxisModel` is recovered by downcast (cf. CartesianAxisView.render).
    override func render(
        _ axisModel: ComponentModel, _ ecModel: GlobalModel, _ api: ExtensionAPI, _ payload: Payload
    ) {
        let axisModel = axisModel as! SingleAxisModel

        // upstream: const group = this.group;
        let group = self.group

        group.removeAll()

        // upstream: const oldAxisGroup = this._axisGroup; this._axisGroup = new graphic.Group();
        let oldAxisGroup = self._axisGroup
        self._axisGroup = Group()

        // upstream: const layout = singleAxisHelper.layout(axisModel);
        let layout = singleAxisHelper.layout(axisModel)

        // upstream: const axisBuilder = new AxisBuilder(axisModel, api, layout);
        let axisBuilder = AxisBuilder(axisModel, api, layout)

        axisBuilder.build()

        _ = group.add(self._axisGroup)
        _ = group.add(axisBuilder.group)

        // upstream: zrUtil.each(selfBuilderAttrs, function (name) {
        //     if (axisModel.get([name, 'show'])) {
        //         axisElementBuilders[name](this, this.group, this._axisGroup, axisModel, api);
        //     }
        // }, this);
        for name in selfBuilderAttrs {
            if jsTruthy(axisModel.get([name, "show"])) {
                axisElementBuilders[name]!(self, self.group, self._axisGroup, axisModel, api)
            }
        }

        // upstream: graphic.groupTransition(oldAxisGroup, this._axisGroup, axisModel);
        // PORT-TODO: `graphic.groupTransition` (util/graphic.ts) is NOT ported. It matches old/new elements
        //   by `anid` and animates the transition (`updateProps`). Deferred with the animation seam
        //   (CONVENTIONS §5); the freshly-built geometry above is correct without it.
        _ = oldAxisGroup

        super.render(axisModel, ecModel, api, payload)
    }

    // upstream: remove() { rectCoordAxisHandleRemove(this); }
    //   The base `AxisView.remove(ecModel, api)` carries the two args (ignored upstream); the signature is
    //   matched here so it overrides. PORT-TODO: `rectCoordAxisHandleRemove` (axisSplitHelper) clears the
    //   cached splitArea colors from the inner store — deferred with splitArea (cf. CartesianAxisView).
    override func remove(_ ecModel: GlobalModel, _ api: ExtensionAPI) {
        // PORT-TODO: rectCoordAxisHandleRemove(self) — axisSplitHelper not ported.
    }
}

// upstream: interface AxisElementBuilder {
//     (axisView: SingleAxisView, group: graphic.Group, axisGroup: graphic.Group,
//      axisModel: SingleAxisModel, api: ExtensionAPI): void
// }
//   Named `SingleAxisElementBuilder` (not `AxisElementBuilder`) to avoid clashing with
//   CartesianAxisView.swift's same-module `AxisElementBuilder` typealias.
typealias SingleAxisElementBuilder = (
    _ axisView: SingleAxisView,
    _ group: Group,
    _ axisGroup: Group,
    _ axisModel: SingleAxisModel,
    _ api: ExtensionAPI
) -> Void

// upstream: const axisElementBuilders: Record<typeof selfBuilderAttrs[number], AxisElementBuilder> = { ... }
private let axisElementBuilders: [String: SingleAxisElementBuilder] = [

    "splitLine": { axisView, group, axisGroup, axisModel, api in
        // upstream: const axis = axisModel.axis;
        //   `SingleAxisModel.axis` is typed `Any` (AxisBaseModel.axis) → downcast to `SingleAxis`.
        let axis = axisModel.axis as! SingleAxis

        if axis.scale.isBlank() {
            return
        }

        let splitLineModel = axisModel.getModel("splitLine")
        let lineStyleModel = splitLineModel.getModel("lineStyle")
        // upstream: let lineColors = lineStyleModel.get('color');
        let lineColorsRaw = lineStyleModel.get("color")
        // upstream: lineColors = lineColors instanceof Array ? lineColors : [lineColors];
        let lineColors: [Any?] = util.isArray(lineColorsRaw)
            ? ((lineColorsRaw as? [Any])?.map { $0 as Any? } ?? [lineColorsRaw])
            : [lineColorsRaw]

        // Guard `lineCount % lineColors.count` against an explicit empty `color: []` — Swift `%` by zero
        // traps, whereas upstream's NaN bucket draws nothing (cf. RadiusAxisView.splitLine).
        if lineColors.isEmpty {
            return
        }

        // upstream: const lineWidth = lineStyleModel.get('width');
        //   Read with `numOpt` (NOT a bare `as? Double`) — the Int-vs-Double option-read trap (CONVENTIONS
        //   trap #1): a bare `"width": 1` default literal boxes as Int and would silently drop.
        let lineWidth = numOpt(lineStyleModel.get("width"))

        // upstream: const gridRect = axisModel.coordinateSystem.getRect();
        //   `SingleAxisModel.coordinateSystem` is the concrete `Single` (assumed sibling API); `getRect()`
        //   returns a `LayoutRect` with x/y/width/height.
        let gridRect = (axisModel.coordinateSystem as! Single).getRect()
        let isHorizontal = axis.isHorizontal()

        // upstream: const splitLines: graphic.Line[][] = [];
        var splitLines: [[Line]] = []
        var lineCount = 0

        let ticksCoords = axis.getTicksCoords(GetTicksCoordsOpt(
            tickModel: splitLineModel,
            breakTicks: "none",
            pruneByBreak: "preserve_extent_bound"
        ))

        var p1 = [Double](repeating: 0, count: 2)
        var p2 = [Double](repeating: 0, count: 2)

        for i in 0..<ticksCoords.count {
            let tickCoord = axis.toGlobalCoord(ticksCoords[i].coord)
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

            // upstream: const line = new graphic.Line({ shape: {x1,y1,x2,y2}, silent: true });
            let lineShape = lineShapeOf(p1[0], p1[1], p2[0], p2[1])
            let line = Line([
                "shape": lineShape as PathShape,
                "silent": true
            ])
            // upstream: graphic.subPixelOptimizeLine(line.shape, lineWidth);  (mutates line.shape in place)
            line.shape = subPixelOptimizeLine(lineShape, lineWidth)

            // upstream: const colorIndex = (lineCount++) % lineColors.length;
            let colorIndex = lineCount % lineColors.count
            lineCount += 1
            // upstream: splitLines[colorIndex] = splitLines[colorIndex] || [];
            while splitLines.count <= colorIndex { splitLines.append([]) }
            splitLines[colorIndex].append(line)
        }

        // upstream: const lineStyle = lineStyleModel.getLineStyle(['color']);
        let lineStyle = lineStyleModel.getLineStyle(["color"])
        for i in 0..<splitLines.count {
            // upstream: style: zrUtil.defaults({ stroke: lineColors[i % lineColors.length] }, lineStyle)
            //   `defaults(target, source)` keeps `target.stroke` and fills the rest from `lineStyle`.
            var styleDict: [String: Any] = [:]
            if let c = lineColors[i % lineColors.count] { styleDict["stroke"] = c }
            _ = util.defaults(&styleDict, lineStyle)

            // upstream: group.add(graphic.mergePath(splitLines[i], { style: ..., silent: true }));
            _ = group.add(mergePath(
                splitLines[i], [
                    "style": pathStyleFromDict(styleDict),
                    "silent": true
                ]
            ))
        }
    },

    "splitArea": { axisView, group, axisGroup, axisModel, api in
        // upstream: rectCoordAxisBuildSplitArea(axisView, axisGroup, axisModel, axisModel);
        // PORT-TODO: `component/axis/axisSplitHelper.rectCoordAxisBuildSplitArea` is NOT ported (it caches
        //   alternating splitArea colors in the inner store and builds `graphic.Rect` bands across the
        //   coord rect). Deferred per task scope (splitLine is the axis-grid deliverable); same deviation
        //   as CartesianAxisView.splitArea.
        _ = (axisView, group, axisGroup, axisModel, api)
    },

    "breakArea": { axisView, group, axisGroup, axisModel, api in
        // upstream:
        //   const axisBreakHelper = getAxisBreakHelper();
        //   const scale = axisModel.axis.scale;
        //   if (axisBreakHelper && scale.type !== 'ordinal') {
        //       axisBreakHelper.rectCoordBuildBreakAxis(
        //           group, axisView, axisModel, axisModel.coordinateSystem.getRect(), api);
        //   }
        // PORT-TODO: `component/axis/axisBreakHelper` (the axis-break feature) is NOT ported;
        //   `getAxisBreakHelper()` returns nil, so this builder is a no-op (matches upstream when the
        //   feature is not `use()`-d). Deferred per task scope; same deviation as CartesianAxisView.breakArea.
        _ = (axisView, group, axisGroup, axisModel, api)
    }
]

// export default SingleAxisView;  → `final class SingleAxisView` above.


// ============================================================================
// PORT-TODO helpers — NOT part of SingleAxisView.ts upstream. They reproduce the
// dynamic-option-read coercions, the `util/graphic` style-bag bridge, and the
// value-returning `subPixelOptimizeLine` wrapper referenced above so the split
// lines are actually drawn. Delete each when its real sibling lands and call the
// sibling directly. (Mirrors the file-private helpers in CartesianAxisView /
// RadiusAxisView.)
// ============================================================================

/// Coerce a dynamic option value to Double, tolerating the Int boxing that `[String: Any]` defaultOption
/// literals use (e.g. a bare `"width": 1`). A bare `as? Double` returns nil on an Int, silently dropping
/// the value — the recurring Int-vs-Double option-read trap (CONVENTIONS trap #1).
private func numOpt(_ v: Any?) -> Double? {
    if let d = v as? Double { return d }
    if let i = v as? Int { return Double(i) }
    if let n = v as? NSNumber, !(n === kCFBooleanTrue || n === kCFBooleanFalse) { return n.doubleValue }
    return nil
}

/// JS truthiness for the dynamic option bag (`if (x)` on `get(...)` results); mirrors the same file-private
/// helper in CartesianAxisView/RadiusAxisView (CONVENTIONS §6).
private func jsTruthy(_ v: Any?) -> Bool {
    guard let v = v else { return false }
    if let b = v as? Bool { return b }
    if let d = v as? Double { return d != 0 && !d.isNaN }
    if let i = v as? Int { return i != 0 }
    if let s = v as? String { return !s.isEmpty }
    return true
}

/// PORT-TODO: `util/graphic` (and its `useStyle` dict bridge) is not ported. Map the dynamic style bag
///   ([String: Any] — the `defaults(...)` merge of the split color over `getLineStyle(['color'])`) onto the
///   typed `PathStyleProps`. Same deviation as RadiusAxisView.pathStyleFromDict. Numbers are read with
///   `styleNum` (Int|Double|NSNumber) to avoid the Int-drop trap. Delete when the graphic bridge lands.
private func styleNum(_ v: Any?) -> Double? {
    if let d = v as? Double { return d }
    if let i = v as? Int { return Double(i) }
    if let n = v as? NSNumber, !(n === kCFBooleanTrue || n === kCFBooleanFalse) { return n.doubleValue }
    return nil
}

private func pathStyleFromDict(_ dict: [String: Any]) -> PathStyleProps {
    var s = PathStyleProps()
    // PORT-TODO: `stroke` may be a gradient/pattern object (ZRColor non-string); only the String form
    //   (incl. the sentinel 'none') is mapped here.
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

// upstream: echarts/src/util/graphic.ts `subPixelOptimizeLine(shape, lineWidth)` — a thin wrapper over
//   zrender's `subPixelOptimizeUtil.subPixelOptimizeLine(shape, shape, {lineWidth})` that mutates `shape`
//   in place and returns it. Per CONVENTIONS §3 the ZRenderKit variant is value-returning, so this wrapper
//   is value-returning too: it optimizes and returns a fresh `LineShape` (assigned back to `line.shape`).
//   Mirrors CartesianAxisView.subPixelOptimizeLine.
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
