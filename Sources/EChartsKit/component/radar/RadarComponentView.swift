// Ported from echarts/src/component/radar/RadarView.ts — keep in sync with upstream
//
// NOTE: file/class renamed RadarView -> RadarComponentView to avoid a SwiftPM object-file basename
//   collision with the chart-side `chart/radar/RadarView.swift` (SwiftPM requires unique source
//   basenames per module; cf. ComponentView.swift's Component.swift rename). No upstream identifier
//   changes semantically — the component view's registered `type` is still `'radar'`.
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
//   import AxisBuilder from '../axis/AxisBuilder';             → `AxisBuilder` (component/axis/AxisBuilder.swift).
//   import * as graphic from '../../util/graphic';
//     → `util/graphic` is NOT ported as a namespace. `graphic.Circle` / `graphic.Ring` /
//       `graphic.Polyline` / `graphic.Polygon` are the ZRenderKit scene-graph shapes (used directly,
//       the sanctioned DRAWING deviation). `graphic.mergePath` → ZRenderKit `mergePath` (Tool/ToolPath).
//   import ComponentView from '../../view/Component';          → `ComponentView` (view/ComponentView.swift).
//   import RadarModel from '../../coord/radar/RadarModel';
//     → PORT-TODO: `coord/radar/RadarModel` is a sibling landing this phase (not yet ported).
//       Assumed API: `open class RadarModel: ComponentModel` with `var coordinateSystem: Radar?`
//       and the standard `get`/`getModel` Model surface. Registered component view `type` is 'radar'.
//   import GlobalModel from '../../model/Global';              → `GlobalModel`.
//   import ExtensionAPI from '../../core/ExtensionAPI';        → `ExtensionAPI`.
//   import { ZRColor } from '../../util/types';
//     → `ZRColor` in this port is the ZRenderKit paint enum; the split colors are read as `Any`
//       (String / gradient object) from the dynamic option bag and mapped to `ZRColor` on the fill/
//       stroke boundary (see `pathStyleFromDict`).
//
// Assumed sibling coord/radar API (from the task brief — Radar coord + IndicatorAxis):
//   Radar (CoordinateSystemMaster):
//     func getIndicatorAxes() -> [IndicatorAxis]
//     var cx: Double ; var cy: Double ; var r: Double
//     func coordToPoint(_ value: Double, _ indicatorIndex: Int) -> [Double]   // upstream: number[]
//   IndicatorAxis (open class IndicatorAxis: Axis):
//     var model: AxisBaseModel          // the per-indicator AxisModel (IndicatorModel)
//     var name: String
//     var angle: Double                 // radian rotation of this indicator axis
//     inherits `getTicksCoords() -> [AxisTickCoord]` from `Axis`.

// upstream: class RadarView extends ComponentView
// CONVENTIONS §2/§4: reference type extending the reference `ComponentView` → `final class`.
public final class RadarComponentView: ComponentView {

    // static type = 'radar';
    public static let type = "radar"
    // type = RadarView.type;
    public let type = "radar"

    // upstream: render(radarModel: RadarModel, ecModel: GlobalModel, api: ExtensionAPI)
    //   The base `ComponentView.render` signature is (model, ecModel, api, payload); upstream
    //   RadarView.render declares only (radarModel, ecModel, api) (payload optional in JS). The
    //   override matches the full base signature and narrows `model` to `RadarModel` (cf. TitleView.render).
    public override func render(
        _ model: ComponentModel, _ ecModel: GlobalModel, _ api: ExtensionAPI, _ payload: Payload
    ) {
        let radarModel = model as! RadarModel

        let group = self.group
        _ = group.removeAll()

        self._buildAxes(radarModel, api)
        self._buildSplitLineAndArea(radarModel)
    }

    func _buildAxes(_ radarModel: RadarModel, _ api: ExtensionAPI) {
        // upstream: const radar = radarModel.coordinateSystem;
        //   PORT seam: RadarModel.coordinateSystem is typed `CoordinateSystemMaster?` (the
        //   CoordinateSystemHostModel witness type; a settable property witness can not be narrowed to
        //   `Radar?`). Narrow to the concrete `Radar` here (upstream types it concrete `Radar`), which
        //   exposes the radar-specific `getIndicatorAxes()`/`cx`/`cy`/`coordToPoint`.
        let radar = radarModel.coordinateSystem as! Radar
        let indicatorAxes = radar.getIndicatorAxes()
        let axisBuilders = util.map(indicatorAxes, { indicatorAxis, _ -> AxisBuilder in
            // upstream: indicatorAxis.model.get('showName') ? indicatorAxis.name : ''  // hide name
            let axisName = jsTruthy(indicatorAxis.model.get("showName"))
                ? indicatorAxis.name
                : "" // hide name
            let axisBuilder = AxisBuilder(indicatorAxis.model, api, AxisBuilderCfg(
                position: [radar.cx, radar.cy],
                rotation: indicatorAxis.angle,
                nameDirection: 1,
                tickDirection: -1,
                labelDirection: -1,
                axisName: axisName
            ))
            return axisBuilder
        })

        util.each(axisBuilders, { axisBuilder, _ in
            axisBuilder.build()
            _ = self.group.add(axisBuilder.group)
        })
    }

    func _buildSplitLineAndArea(_ radarModel: RadarModel) {
        let radar = radarModel.coordinateSystem as! Radar
        let indicatorAxes = radar.getIndicatorAxes()
        if indicatorAxes.isEmpty {
            return
        }
        let shape = radarModel.get("shape") as? String
        let splitLineModel = radarModel.getModel("splitLine")
        let splitAreaModel = radarModel.getModel("splitArea")
        let lineStyleModel = splitLineModel.getModel("lineStyle")
        let areaStyleModel = splitAreaModel.getModel("areaStyle")

        let showSplitLine = jsTruthy(splitLineModel.get("show"))
        let showSplitArea = jsTruthy(splitAreaModel.get("show"))
        let splitLineColors = lineStyleModel.get("color")
        let splitAreaColors = areaStyleModel.get("color")

        // upstream: zrUtil.isArray(splitLineColors) ? splitLineColors : [splitLineColors]
        let splitLineColorsArr: [Any] = util.isArray(splitLineColors)
            ? (splitLineColors as! [Any])
            : [splitLineColors as Any]
        let splitAreaColorsArr: [Any] = util.isArray(splitAreaColors)
            ? (splitAreaColors as! [Any])
            : [splitAreaColors as Any]

        // upstream: (graphic.Circle | graphic.Polyline)[][]  /  (graphic.Ring | graphic.Polygon)[][]
        //   Circle/Polyline/Ring/Polygon all subclass ZRenderKit `Path`; the shared element type is `Path`.
        var splitLines: [[Path]] = []
        var splitAreas: [[Path]] = []

        // upstream: function getColorIndex(areaOrLine, areaOrLineColorList, idx) {
        //     const colorIndex = idx % areaOrLineColorList.length;
        //     areaOrLine[colorIndex] = areaOrLine[colorIndex] || [];
        //     return colorIndex;
        //   }
        // PORT-TODO (JS sparse-index quirk): for the polygon-shape splitArea below, `idx` can be `-1`
        //   at the first ring (i-1 with i=0, since the empty `prevPoints` array is truthy in JS). JS
        //   `(-1) % n === -1`, and `areaOrLine[-1] = ...` writes a NON-enumerable "-1" key that the
        //   later `each(splitAreas)` (index-based) skips — i.e. that first area polygon is silently
        //   dropped. Swift `Int % n` also yields `-1` here; we reproduce the drop by only growing the
        //   bucket for `colorIndex >= 0` and having the caller skip the append when `colorIndex < 0`.
        func getColorIndex(_ areaOrLine: inout [[Path]], _ areaOrLineColorList: [Any], _ idx: Int) -> Int {
            let colorIndex = idx % areaOrLineColorList.count
            if colorIndex >= 0 {
                while areaOrLine.count <= colorIndex { areaOrLine.append([]) }
            }
            return colorIndex
        }

        if shape == "circle" {
            let ticksRadius = indicatorAxes[0].getTicksCoords()
            let cx = radar.cx
            let cy = radar.cy
            for i in 0..<ticksRadius.count {
                if showSplitLine {
                    let colorIndex = getColorIndex(&splitLines, splitLineColorsArr, i)
                    var circleShape = CircleShape()
                    circleShape.cx = cx
                    circleShape.cy = cy
                    circleShape.r = ticksRadius[i].coord
                    splitLines[colorIndex].append(Circle([
                        "shape": circleShape
                    ]))
                }
                if showSplitArea && i < ticksRadius.count - 1 {
                    let colorIndex = getColorIndex(&splitAreas, splitAreaColorsArr, i)
                    var ringShape = RingShape()
                    ringShape.cx = cx
                    ringShape.cy = cy
                    ringShape.r0 = ticksRadius[i].coord
                    ringShape.r = ticksRadius[i + 1].coord
                    splitAreas[colorIndex].append(Ring([
                        "shape": ringShape
                    ]))
                }
            }
        }
        // Polyyon
        else {
            var realSplitNumber: Double? = nil
            let axesTicksPoints = util.map(indicatorAxes, { indicatorAxis, idx -> [[Double]] in
                let ticksCoords = indicatorAxis.getTicksCoords()
                realSplitNumber = realSplitNumber == nil
                    ? Double(ticksCoords.count - 1)
                    : Swift.min(Double(ticksCoords.count - 1), realSplitNumber!)
                return util.map(ticksCoords, { tickCoord, _ -> [Double] in
                    return radar.coordToPoint(tickCoord.coord, Double(idx))
                })
            })

            var prevPoints: [[Double]] = []
            let rsn = Int(realSplitNumber!)
            for i in 0...rsn {
                var points: [[Double]] = []
                for j in 0..<indicatorAxes.count {
                    points.append(axesTicksPoints[j][i])
                }
                // Close
                if !points.isEmpty {
                    // upstream: points.push(points[0].slice());  (value-type copy)
                    points.append(points[0])
                }
                else {
                    // PORT-TODO: upstream `if (__DEV__) { console.error('Can\'t draw value axis ' + i); }`
                    //   — dev-only diagnostic dropped.
                }

                if showSplitLine {
                    let colorIndex = getColorIndex(&splitLines, splitLineColorsArr, i)
                    var polylineShape = PolylineShape()
                    polylineShape.points = points.map { VectorArray($0[0], $0[1]) }
                    splitLines[colorIndex].append(Polyline([
                        "shape": polylineShape
                    ]))
                }
                // upstream: `if (showSplitArea && prevPoints)` — an empty JS array is truthy, so this
                //   is entered even on the first ring (i=0, prevPoints=[]); see the getColorIndex
                //   PORT-TODO for how that first (colorIndex=-1) polygon is dropped.
                if showSplitArea {
                    let colorIndex = getColorIndex(&splitAreas, splitAreaColorsArr, i - 1)
                    if colorIndex >= 0 {
                        var polygonShape = PolygonShape()
                        // upstream: points.concat(prevPoints)
                        polygonShape.points = (points + prevPoints).map { VectorArray($0[0], $0[1]) }
                        splitAreas[colorIndex].append(Polygon([
                            "shape": polygonShape
                        ]))
                    }
                }
                // upstream: prevPoints = points.slice().reverse();
                prevPoints = Array(points.reversed())
            }
        }

        let lineStyle = lineStyleModel.getLineStyle()
        let areaStyle = areaStyleModel.getAreaStyle()
        // Add splitArea before splitLine
        util.each(splitAreas, { splitAreas, idx in
            // upstream: graphic.mergePath(splitAreas, { style: defaults({ stroke:'none', fill: ... }, areaStyle), silent: true })
            var styleDict: [String: Any] = [
                "stroke": "none",
                "fill": splitAreaColorsArr[idx % splitAreaColorsArr.count]
            ]
            _ = util.defaults(&styleDict, areaStyle)
            _ = self.group.add(mergePath(
                splitAreas, [
                    "style": pathStyleFromDict(styleDict),
                    "silent": true
                ]
            ))
        })

        util.each(splitLines, { splitLines, idx in
            // upstream: graphic.mergePath(splitLines, { style: defaults({ fill:'none', stroke: ... }, lineStyle), silent: true })
            var styleDict: [String: Any] = [
                "fill": "none",
                "stroke": splitLineColorsArr[idx % splitLineColorsArr.count]
            ]
            _ = util.defaults(&styleDict, lineStyle)
            _ = self.group.add(mergePath(
                splitLines, [
                    "style": pathStyleFromDict(styleDict),
                    "silent": true
                ]
            ))
        })
    }
}

// upstream: export default RadarView;  → `public final class RadarComponentView` above.


// ============================================================================
// PORT-TODO helpers — NOT part of RadarView.ts upstream. These reproduce the
// out-of-phase sibling APIs / the `util/graphic` style bridge referenced above.
// Delete each when its real sibling lands and call the sibling directly.
// ============================================================================

/// JS truthiness for the dynamic option bag (`if (x)` / ternary on `get(...)` results).
/// (CONVENTIONS §6: replicate JS truthiness explicitly for numbers/strings.) Mirrors the same
/// file-private helper in TitleView/AxisBuilder/etc.
private func jsTruthy(_ v: Any?) -> Bool {
    guard let v = v else { return false }
    if let b = v as? Bool { return b }
    if let d = v as? Double { return d != 0 && !d.isNaN }
    if let i = v as? Int { return i != 0 }
    if let s = v as? String { return !s.isEmpty }
    return true
}

/// PORT-TODO: `util/graphic` (and its `useStyle` dict bridge) is not ported. Map the dynamic style
///   bag ([String: Any] — the `defaults(...)` merge of split colors over getLineStyle()/getAreaStyle())
///   onto the typed `PathStyleProps`. Same deviation as AxisBuilder.swift's `pathStyleFromLineStyleDict`
///   (kept file-private there); mirrored here for both stroke (split lines) and fill (split areas).
///   Delete when the graphic style bridge lands.
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
    // PORT-TODO: `fill`/`stroke` may be a gradient/pattern object (ZRColor non-string); only the
    //   String form (incl. the sentinel 'none') is mapped here.
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
