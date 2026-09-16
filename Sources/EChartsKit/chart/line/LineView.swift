// Ported from echarts/src/chart/line/LineView.ts — keep in sync with upstream

// FIXME step not support polar

import Foundation
import ZRenderKit

// upstream imports:
// import * as zrUtil from 'zrender/src/core/util';                        -> `util`
// import SymbolDraw from '../helper/SymbolDraw';                          -> `SymbolDraw`
// import SymbolClz from '../helper/Symbol';                               -> `Symbol` (chart/helper/SymbolElement.swift)
// import lineAnimationDiff from './lineAnimationDiff';                    -> `lineAnimationDiff` (chart/line/lineAnimationDiff.swift)
// import * as graphic from '../../util/graphic';                          -> ZRenderKit shapes / `initProps` / `updateProps`
// import * as modelUtil from '../../util/model';                         -> `modelUtil`
// import { ECPolyline, ECPolygon } from './poly';                        -> chart/line/poly.swift
// import ChartView from '../../view/Chart';                              -> `ChartView`
// import { prepareDataCoordInfo, getStackedOnPoint, isPointIllegal } from './helper';  -> chart/line/lineHelper.swift
// import { createGridClipPath, createPolarClipPath } from '../helper/createClipPathFromCoordSys';
// import LineSeriesModel, { LineSeriesOption } from './LineSeries';       -> `LineSeriesModel`
// import Cartesian2D / Polar / SeriesData ...                            -> coord/* + data/SeriesData
// import { setStatesStylesFromModel, setStatesFlag, toggleHoverEmphasis, SPECIAL_STATES } from '../../util/states';
// import Model from '../../model/Model';                                 -> `Model`
// import { setLabelStyle, getLabelStatesModels, labelInner } from '../../label/labelStyle';
// import { getDefaultLabel, getDefaultInterpolatedLabel } from '../helper/labelHelper';
// import { getECData } from '../../util/innerStore';                     -> `innerStore.getECData`
// import { createFloat32Array } from '../../util/vendor';                -> `vendor.createFloat32Array`
// import { convertToColorString } from '../../util/format';              -> local `lineVisualColorToString`
// import { lerp } from 'zrender/src/tool/color';                         -> `color.lerp`
// import { getTickValueOutermost } from '../../coord/axisHelper';        -> `axisHelper.getTickValueOutermost`

// type PolarArea = ReturnType<Polar['getArea']>;         -> `PolarArea`
// type Cartesian2DArea = ReturnType<Cartesian2D['getArea']>; -> `Cartesian2DArea`
// interface SymbolExtended extends SymbolClz { __temp: boolean }
//   -> the `__temp` flag lives on `Symbol` (see chart/helper/SymbolElement.swift `__temp`).

// upstream: interface ColorStop { offset: number; coord?: number; color: ColorString }
private struct ColorStop {
    var offset: Double = 0
    var coord: Double = Double.nan   // upstream optional; only used before `offset` is assigned.
    var color: ColorString
}

// upstream: function isPointsSame(points1, points2)  — returns `true` or `undefined`
private func isPointsSame(_ points1: [Double], _ points2: [Double]) -> Bool {
    if points1.count != points2.count {
        return false
    }
    for i in 0..<points1.count {
        if points1[i] != points2[i] {
            return false
        }
    }
    return true
}

// upstream: function xyExtentFromPoints(points): [xExtent, yExtent]
private func xyExtentFromPoints(_ points: [Double]) -> [[Double]] {
    var xExtent = model.initExtentForUnion()
    var yExtent = model.initExtentForUnion()

    var i = 0
    while i < points.count {
        let x = points[i]; i += 1
        // `points[i++]` may run off the end (odd length) — mirror JS `undefined`→NaN.
        let y = i < points.count ? points[i] : Double.nan; i += 1
        if !isPointIllegal(x, y) {
            model.unionExtentFromNumber(&xExtent, x)
            model.unionExtentFromNumber(&yExtent, y)
        }
    }
    return [xExtent, yExtent]
}

// upstream: function getBoundingDiff(points1, points2): number
private func getBoundingDiff(_ points1: [Double], _ points2: [Double]) -> Double {
    let e1 = xyExtentFromPoints(points1)
    let e2 = xyExtentFromPoints(points2)
    let xExtent1 = e1[0], yExtent1 = e1[1]
    let xExtent2 = e2[0], yExtent2 = e2[1]

    // Get a max value from each corner of two boundings.
    return Swift.max(
        Swift.abs(xExtent1[0] - xExtent2[0]),
        Swift.abs(yExtent1[0] - yExtent2[0]),

        Swift.abs(xExtent1[1] - xExtent2[1]),
        Swift.abs(yExtent1[1] - yExtent2[1])
    )
}

// upstream: function getSmooth(smooth: number | boolean): number
//   return isNumber(smooth) ? smooth : (smooth ? 0.5 : 0);
private func getSmooth(_ smooth: Any?) -> Double {
    // A JS boolean is NOT a number, so `isNumber(smooth)` is false for `true`/`false` and the
    // `smooth ? 0.5 : 0` branch runs. In Swift a `Bool` bridges to `NSNumber`, so the numeric
    // coercion must be checked AFTER the Bool branch — otherwise `smooth: true` yields 1.0 (control
    // points twice as far out → the smoothed curve overshoots). A genuine Double never casts to Bool.
    if let b = smooth as? Bool { return b ? 0.5 : 0 }
    if let n = lineHelperToNumberOpt(smooth) { return n }
    return 0
}

// upstream: function getStackedOnPoints(coordSys, data, dataCoordInfo): Float32Array | []
private func getStackedOnPoints(
    _ coordSys: LineCoordSys,
    _ data: SeriesData,
    _ dataCoordInfo: CoordInfo
) -> [Double] {
    if dataCoordInfo.valueDim == nil {
        return []
    }

    let len = data.count()
    var points = vendor.createFloat32Array(Double(len * 2))
    for idx in 0..<len {
        let pt = getStackedOnPoint(dataCoordInfo, coordSys, data, idx)
        points[idx * 2] = pt.count > 0 ? pt[0] : Double.nan
        points[idx * 2 + 1] = pt.count > 1 ? pt[1] : Double.nan
    }

    return points
}

/**
 * Filter the null data and extend data for step considering `stepTurnAt`
 */
// upstream: function turnPointsIntoStep(points, basePoints, coordSys, stepTurnAt, connectNulls): number[]
private func turnPointsIntoStep(
    _ pointsIn: [Double],
    _ basePoints: [Double]?,
    _ coordSys: LineCoordSys,
    _ stepTurnAt: String,
    _ connectNulls: Bool
) -> [Double] {
    let baseAxis = coordSys.getBaseAxis()
    let baseIndex = (baseAxis.dim == "x" || baseAxis.dim == "radius") ? 0 : 1

    var points = pointsIn
    var stepPoints: [Double] = []
    var i = 0
    var stepPt: [Double] = [0, 0]
    var pt0 = Double.nan; var pt1 = Double.nan
    var nextPt: [Double] = [0, 0]
    var filteredPoints: [Double] = []
    // PORT-LOCAL out-of-range → NaN reader (see poly.swift `polyAt`).
    func at(_ arr: [Double], _ j: Int) -> Double { (j >= 0 && j < arr.count) ? arr[j] : Double.nan }

    if connectNulls {
        i = 0
        while i < points.count {
            /**
             * For areaStyle of stepped lines, `stackedOnPoints` should be
             * filtered the same as `points` so that the base axis values
             * should stay the same as the lines above. See #20021
             */
            let reference = basePoints ?? points
            if !isPointIllegal(at(reference, i), at(reference, i + 1)) {
                filteredPoints.append(points[i]); filteredPoints.append(points[i + 1])
            }
            i += 2
        }
        points = filteredPoints
    }
    i = 0
    while i < points.count - 2 {
        nextPt[0] = points[i + 2]
        nextPt[1] = points[i + 3]
        pt0 = points[i]
        pt1 = points[i + 1]
        stepPoints.append(pt0); stepPoints.append(pt1)

        switch stepTurnAt {
        case "end":
            stepPt[baseIndex] = nextPt[baseIndex]
            stepPt[1 - baseIndex] = (baseIndex == 0 ? pt1 : pt0)
            stepPoints.append(stepPt[0]); stepPoints.append(stepPt[1])
        case "middle":
            let middle = (( baseIndex == 0 ? pt0 : pt1 ) + nextPt[baseIndex]) / 2
            var stepPt2: [Double] = [0, 0]
            stepPt[baseIndex] = middle; stepPt2[baseIndex] = middle
            stepPt[1 - baseIndex] = (baseIndex == 0 ? pt1 : pt0)
            stepPt2[1 - baseIndex] = nextPt[1 - baseIndex]
            stepPoints.append(stepPt[0]); stepPoints.append(stepPt[1])
            stepPoints.append(stepPt2[0]); stepPoints.append(stepPt2[1])
        default:
            // default is start
            stepPt[baseIndex] = (baseIndex == 0 ? pt0 : pt1)
            stepPt[1 - baseIndex] = nextPt[1 - baseIndex]
            stepPoints.append(stepPt[0]); stepPoints.append(stepPt[1])
        }
        i += 2
    }
    // Last points
    stepPoints.append(at(points, i)); i += 1
    stepPoints.append(at(points, i)); i += 1
    return stepPoints
}

/**
 * Clip color stops to edge. Avoid creating too large gradients.
 * Which may lead to blurry when GPU acceleration is enabled. See #15680
 *
 * The stops has been sorted from small to large.
 */
private func clipColorStops(_ colorStops: [ColorStop], _ maxSize: Double) -> [ColorStop] {
    var newColorStops: [ColorStop] = []
    let len = colorStops.count
    // coord will always < 0 in prevOutOfRangeColorStop.
    var prevOutOfRangeColorStop: ColorStop?
    var prevInRangeColorStop: ColorStop?

    func lerpStop(_ stop0: ColorStop, _ stop1: ColorStop, _ clippedCoord: Double) -> ColorStop {
        let coord0 = stop0.coord
        let p = (clippedCoord - coord0) / (stop1.coord - coord0)
        // lerp(p, [stop0.color, stop1.color]) as string
        let colorResult = color.lerp(p, [stop0.color, stop1.color])
        let colorStr: String
        if case let .color(s)? = colorResult { colorStr = s } else { colorStr = stop0.color }
        return ColorStop(offset: 0, coord: clippedCoord, color: colorStr)
    }

    for i in 0..<len {
        let stop = colorStops[i]
        let coord = stop.coord
        if coord < 0 {
            prevOutOfRangeColorStop = stop
        }
        else if coord > maxSize {
            if let prevIn = prevInRangeColorStop {
                newColorStops.append(lerpStop(prevIn, stop, maxSize))
            }
            else if let prevOut = prevOutOfRangeColorStop { // If there are two stops and coord range is between these two stops
                newColorStops.append(lerpStop(prevOut, stop, 0))
                newColorStops.append(lerpStop(prevOut, stop, maxSize))
            }
            // All following stop will be out of range. So just ignore them.
            break
        }
        else {
            if let prevOut = prevOutOfRangeColorStop {
                newColorStops.append(lerpStop(prevOut, stop, 0))
                // Reset
                prevOutOfRangeColorStop = nil
            }
            newColorStops.append(stop)
            prevInRangeColorStop = stop
        }
    }
    return newColorStops
}

// upstream: function getVisualGradient(data, coordSys, api): LinearGradient | string | undefined
//   PORT: the union return is modeled as `ZRenderKit.ZRColor?` — `.linearGradient` for the gradient,
//   `.string` for the flat-color / 'transparent' fast paths, `nil` when no visualMeta drives it.
private func getVisualGradient(
    _ data: SeriesData,
    _ coordSys: LineCoordSys,
    _ api: ExtensionAPI
) -> ZRenderKit.ZRColor? {
    let visualMetaList = data.getVisual("visualMeta") as? [VisualMeta]
    if visualMetaList == nil || visualMetaList!.isEmpty || data.count() == 0 {
        // When data.count() is 0, gradient range can not be calculated.
        return nil
    }
    let visualMetaListNN = visualMetaList!

    if coordSys.type != "cartesian2d" {
        if __DEV__ {
            log.warn("Visual map on line style is only supported on cartesian2d.")
        }
        return nil
    }

    var coordDim: String?
    var visualMeta: VisualMeta?

    var i = visualMetaListNN.count - 1
    while i >= 0 {
        let dimInfo = visualMetaListNN[i].dimension.map { data.getDimensionInfo($0 as Any) }
        coordDim = dimInfo?.coordDim
        // Can only be x or y
        if coordDim == "x" || coordDim == "y" {
            visualMeta = visualMetaListNN[i]
            break
        }
        i -= 1
    }

    guard let visualMeta = visualMeta, let coordDim = coordDim else {
        if __DEV__ {
            log.warn("Visual map on line style only support x or y dimension.")
        }
        return nil
    }

    // If the area to be rendered is bigger than area defined by LinearGradient,
    // the canvas spec prescribes that the color of the first stop and the last
    // stop should be used. But if two stops are added at offset 0, in effect
    // browsers use the color of the second stop to render area outside
    // LinearGradient. So we can only infinitesimally extend area defined in
    // LinearGradient to render `outerColors`.

    // coordSys is cartesian2d here.
    let cartesian = coordSys.asCartesian2D!
    let axis = cartesian.getAxis(coordDim)!

    // dataToCoord mapping may not be linear, but must be monotonic.
    var colorStops: [ColorStop] = util.map(visualMeta.stops) { stop, _ in
        // offset will be calculated later.
        return ColorStop(
            offset: 0,
            coord: axis.toGlobalCoord(axis.dataToCoord(stop.value)),
            color: stop.color
        )
    }
    let stopLen = colorStops.count
    var outerColors = visualMeta.outerColors   // .slice() — Array value copy

    if stopLen != 0 && colorStops[0].coord > colorStops[stopLen - 1].coord {
        colorStops.reverse()
        outerColors.reverse()
    }
    var colorStopsInRange = clipColorStops(
        colorStops, coordDim == "x" ? api.getWidth() : api.getHeight()
    )
    let inRangeStopLen = colorStopsInRange.count
    if inRangeStopLen == 0 && stopLen != 0 {
        // All stops are out of range. All will be the same color.
        if colorStops[0].coord < 0 {
            return .string(outerColors.count > 1 && !outerColors[1].isEmpty ? outerColors[1] : colorStops[stopLen - 1].color)
        }
        else {
            return .string(outerColors.count > 0 && !outerColors[0].isEmpty ? outerColors[0] : colorStops[0].color)
        }
    }

    let tinyExtent = 10.0 // Arbitrary value: 10px
    let minCoord = colorStopsInRange[0].coord - tinyExtent
    let maxCoord = colorStopsInRange[inRangeStopLen - 1].coord + tinyExtent
    let coordSpan = maxCoord - minCoord

    if coordSpan < 1e-3 {
        return .string("transparent")
    }

    for k in 0..<colorStopsInRange.count {
        colorStopsInRange[k].offset = (colorStopsInRange[k].coord - minCoord) / coordSpan
    }
    colorStopsInRange.append(ColorStop(
        // NOTE: inRangeStopLen may still be 0 if stoplen is zero.
        offset: inRangeStopLen != 0 ? colorStopsInRange[inRangeStopLen - 1].offset : 0.5,
        color: (outerColors.count > 1 && !outerColors[1].isEmpty) ? outerColors[1] : "transparent"
    ))
    colorStopsInRange.insert(ColorStop( // notice newColorStops.length have been changed.
        offset: inRangeStopLen != 0 ? colorStopsInRange[0].offset : 0.5,
        color: (outerColors.count > 0 && !outerColors[0].isEmpty) ? outerColors[0] : "transparent"
    ), at: 0)

    // new graphic.LinearGradient(0, 0, 0, 0, colorStopsInRange, true)
    let stops = colorStopsInRange.map { ZRenderKit.GradientColorStop(offset: $0.offset, color: $0.color) }
    let gradient = ZRenderKit.LinearGradient(0, 0, 0, 0, stops, true)
    // gradient[coordDim] = minCoord;  gradient[coordDim + '2'] = maxCoord;
    if coordDim == "x" {
        gradient.x = minCoord
        gradient.x2 = maxCoord
    }
    else {
        gradient.y = minCoord
        gradient.y2 = maxCoord
    }

    return .linearGradient(gradient)
}

// upstream: function getIsIgnoreFunc(seriesModel, data, coordSys): ((dataIndex) => boolean) | undefined
private func getIsIgnoreFunc(
    _ seriesModel: SeriesModel, _ data: SeriesData, _ coordSys: Cartesian2D
) -> ((Int) -> Bool)? {
    let showAllSymbol = seriesModel.get("showAllSymbol")
    let isAuto = (showAllSymbol as? String) == "auto"

    if lineTruthyOpt(showAllSymbol) && !isAuto {
        return nil
    }

    guard let categoryAxis = coordSys.getAxesByScale("ordinal").first else {
        return nil
    }

    // Note that category label interval strategy might bring some weird effect in some scenario: users
    //   may wonder why some of the symbols are not displayed. So we show all symbols as possible as we can.
    if isAuto
        // Simplify the logic, do not determine label overlap here.
        && canShowAllSymbolForCategory(categoryAxis, data) {
        return nil
    }

    // Otherwise follow the label interval strategy on category axis.
    guard let categoryDataDim = data.mapDimension(categoryAxis.dim) else { return nil }
    var labelMap = Set<Double>()
    for labelItem in categoryAxis.getViewLabels() {
        if labelItem.tick.offInterval != true {
            labelMap.insert(axisHelper.getTickValueOutermost(categoryAxis.scale, labelItem.tick))
        }
    }

    return { dataIndex in
        return !labelMap.contains(lineHelperToNumber(data.get(categoryDataDim, dataIndex)))
    }
}

// upstream: function canShowAllSymbolForCategory(categoryAxis, data): boolean
private func canShowAllSymbolForCategory(_ categoryAxis: Axis2D, _ data: SeriesData) -> Bool {
    // In most cases, line is monotonous on category axis, and the label size is close with each other.
    //   So we check the symbol size and some of the label size alone with the category axis to estimate
    //   whether all symbol can be shown without overlap.
    let axisExtent = categoryAxis.getExtent()
    let count = (categoryAxis.scale as? OrdinalScale)?.count() ?? 0
    var availSize = abs(axisExtent[1] - axisExtent[0]) / count
    if availSize.isNaN { availSize = 0 }   // 0/0 is NaN.

    // Sampling some points, max 5.
    let dataLen = data.count()
    let step = Swift.max(1, Int((Double(dataLen) / 5).rounded()))
    let sizeIdx = categoryAxis.isHorizontal() ? 1 : 0
    var dataIndex = 0
    while dataIndex < dataLen {
        // Only for cartesian, where `isHorizontal` exists. Empirical number 1.5.
        if Symbol.getSymbolSize(data, dataIndex)[sizeIdx] * 1.5 > availSize {
            return false
        }
        dataIndex += step
    }

    return true
}

// upstream: function getLastIndexNotNull(points): number
private func getLastIndexNotNull(_ points: [Double]) -> Int {
    var len = points.count / 2
    while len > 0 {
        if !isPointIllegal(
            len * 2 - 2 < points.count ? points[len * 2 - 2] : Double.nan,
            len * 2 - 1 < points.count ? points[len * 2 - 1] : Double.nan
        ) {
            break
        }
        len -= 1
    }

    return len - 1
}

// upstream: function getPointAtIndex(points, idx): [x, y]
private func getPointAtIndex(_ points: [Double], _ idx: Int) -> [Double] {
    return [
        idx * 2 < points.count ? points[idx * 2] : Double.nan,
        idx * 2 + 1 < points.count ? points[idx * 2 + 1] : Double.nan
    ]
}

// upstream: function getIndexRange(points, xOrY, dim): { range: [number, number], t: number }
private func getIndexRange(_ points: [Double], _ xOrY: Double, _ dim: String) -> (range: [Int], t: Double) {
    let len = points.count / 2

    let dimIdx = dim == "x" ? 0 : 1
    var a = Double.nan
    var b = Double.nan
    var prevIndex = 0
    var nextIndex = -1
    func at(_ j: Int) -> Double { (j >= 0 && j < points.count) ? points[j] : Double.nan }
    for i in 0..<len {
        b = at(i * 2 + dimIdx)
        if isPointIllegal(b, at(i * 2 + 1 - dimIdx)) {
            continue
        }
        if i == 0 {
            a = b
            continue
        }
        if (a <= xOrY && b >= xOrY) || (a >= xOrY && b <= xOrY) {
            nextIndex = i
            break
        }

        prevIndex = i
        a = b
    }

    return (
        range: [prevIndex, nextIndex],
        t: (xOrY - a) / (b - a)
    )
}

// upstream: function anyStateShowEndLabel(seriesModel): boolean
private func anyStateShowEndLabel(_ seriesModel: SeriesModel) -> Bool {
    if lineTruthyOpt(seriesModel.get(["endLabel", "show"])) {
        return true
    }
    for i in 0..<states.SPECIAL_STATES.count {
        if lineTruthyOpt(seriesModel.get([states.SPECIAL_STATES[i], "endLabel", "show"])) {
            return true
        }
    }
    return false
}

// upstream: interface EndLabelAnimationRecord { lastFrameIndex; originalX?; originalY? }
final class EndLabelAnimationRecord {
    var lastFrameIndex: Int = 0
    var originalX: Double?
    var originalY: Double?
}

// upstream: function createLineClipPath(lineView, coordSys, hasAnimation, seriesModel): Rect | Sector
private func createLineClipPath(
    _ lineView: LineView,
    _ coordSys: LineCoordSys,
    _ hasAnimation: Bool,
    _ seriesModel: SeriesModel
) -> Path {
    if case let .cartesian2d(cartesian) = coordSys {
        let endLabelModel = seriesModel.getModel("endLabel")
        let valueAnimation = (endLabelModel.get("valueAnimation") as? Bool) ?? false
        let data = seriesModel.getData()

        let labelAnimationRecord = EndLabelAnimationRecord()

        let during: ((Double, Rect) -> Void)? = anyStateShowEndLabel(seriesModel)
            ? { percent, clipRect in
                lineView._endLabelOnDuring(
                    percent,
                    clipRect,
                    data,
                    labelAnimationRecord,
                    valueAnimation,
                    endLabelModel,
                    cartesian
                )
            }
            : nil

        let isHorizontal = coordSys.getBaseAxis().isHorizontal_()
        let clipPath = createGridClipPath(cartesian, hasAnimation, seriesModel, {
            let endLabel = lineView._endLabel
            if let endLabel = endLabel, hasAnimation {
                if labelAnimationRecord.originalX != nil {
                    _ = endLabel.attr(["x": labelAnimationRecord.originalX as Any,
                                       "y": labelAnimationRecord.originalY as Any])
                }
            }
        }, during)
        // Expand clip shape to avoid clipping when line value exceeds axis
        if !((seriesModel.get("clip", true) as? Bool) ?? true) {
            var rectShape = clipPath.shape as! RectShape
            let expandSize = Swift.max(rectShape.width, rectShape.height)
            if isHorizontal {
                rectShape.y -= expandSize
                rectShape.height += expandSize * 2
            }
            else {
                rectShape.x -= expandSize
                rectShape.width += expandSize * 2
            }
            clipPath.shape = rectShape
        }

        // Set to the final frame. To make sure label layout is right.
        if let during = during {
            during(1, clipPath)
        }
        return clipPath
    }
    else {
        if __DEV__ {
            if lineTruthyOpt(seriesModel.get(["endLabel", "show"])) {
                log.warn("endLabel is not supported for lines in polar systems.")
            }
        }
        return createPolarClipPath(coordSys.asPolar!, hasAnimation, seriesModel)
    }
}

// upstream: function getEndLabelStateSpecified(endLabelModel, coordSys): { normal: {...} }
private func getEndLabelStateSpecified(_ endLabelModel: Model, _ coordSys: Cartesian2D) -> [DisplayState: TextStyleProps] {
    let baseAxis = coordSys.getBaseAxis()
    let isHorizontal = baseAxis.isHorizontal()
    let isBaseInversed = baseAxis.inverse
    let align = isHorizontal
        ? (isBaseInversed ? "right" : "left")
        : "center"
    let verticalAlign = isHorizontal
        ? "middle"
        : (isBaseInversed ? "top" : "bottom")

    var normal = TextStyleProps()
    normal.align = TextAlign(rawValue: (endLabelModel.get("align") as? String) ?? align)
    normal.verticalAlign = TextVerticalAlign(rawValue: (endLabelModel.get("verticalAlign") as? String) ?? verticalAlign)
    return [.normal: normal]
}

// upstream: class LineView extends ChartView { static type = 'line'; ... }
open class LineView: ChartView {

    // upstream instance fields:
    private var _symbolDraw: SymbolDraw!

    private var _lineGroup: Group!
    private var _coordSys: LineCoordSys?

    var _endLabel: ZRText?    // upstream: graphic.Text (accessed by createLineClipPath's closures)

    private var _polyline: ECPolyline?
    private var _polygon: ECPolygon?

    private var _stackedOnPoints: [Double] = []
    private var _points: [Double] = []

    private var _step: Any?   // upstream: LineSeriesOption['step'] — String | Bool | nil
    private var _valueOrigin: Any?

    private var _clipShapeForSymbol: CoordinateSystemClipArea?

    private var _data: SeriesData?

    // upstream: init() { ... }
    open override func init_(_ ecModel: GlobalModel, _ api: ExtensionAPI) {
        let lineGroup = Group()

        let symbolDraw = SymbolDraw()
        _ = self.group.add(symbolDraw.group)

        self._symbolDraw = symbolDraw
        self._lineGroup = lineGroup

        // this._changePolyState = zrUtil.bind(this._changePolyState, this); — Swift methods bind self.
    }

    // Defensive lazy init for the render path (if `init_` was not called by the view manager).
    private func ensureInit() {
        if self._lineGroup == nil {
            self._lineGroup = Group()
        }
        if self._symbolDraw == nil {
            self._symbolDraw = SymbolDraw()
            _ = self.group.add(self._symbolDraw.group)
        }
    }

    open override func render(
        _ seriesModel: SeriesModel, _ ecModel: GlobalModel, _ api: ExtensionAPI, _ payload: Payload
    ) {
        self.ensureInit()

        // TODO: only cartesian2d + polar are handled here; geo/single/calendar line
        //   coordinate systems are not yet wired into this view's render path.
        guard let coordSys = LineCoordSys.from(seriesModel.coordinateSystem) else { return }
        let group = self.group
        let data = seriesModel.getData()

        // PORT-LOCAL: upstream runs the symbol visual (visual/symbol.ts) as a GLOBAL visual stage keyed
        //   on `hasSymbolVisual` series; this port invokes it from the view (same as ScatterView /
        //   EffectScatterView). It populates the per-item symbol / symbolSize / symbolRotate /
        //   symbolOffset / symbolKeepAspect visuals SymbolDraw/Symbol read — WITHOUT it a per-series
        //   `symbolSize` is dropped and symbols render at the default size.
        symbolVisual.seriesSymbolTask(seriesModel, ecModel)
        symbolVisual.dataSymbolTask(seriesModel)

        let lineStyleModel = seriesModel.getModel("lineStyle")
        let areaStyleModel = seriesModel.getModel("areaStyle")

        var points = (data.getLayout("points") as? [Double]) ?? []

        let isCoordSysPolar = coordSys.type == "polar"
        let prevCoordSys = self._coordSys

        let symbolDraw = self._symbolDraw!
        var polyline = self._polyline
        var polygon = self._polygon

        let lineGroup = self._lineGroup!

        // upstream: const hasAnimation = !ecModel.ssr && seriesModel.get('animation');
        //   The value is used in JS-boolean contexts (`if (hasAnimation)`, `hasAnimation && …`), and the
        //   GLOBAL default is the STRING `'auto'` (globalDefault.ts:107), which is truthy. A plain
        //   `as? Bool` cast returns nil for `'auto'` → symbols/labels never got their enter animation
        //   even though the line's clip reveal (hard-coded animation) ran — the "points appear instantly,
        //   line animates" bug. Apply JS truthiness so `'auto'`/`true` enable it and `false` disables it.
        let hasAnimation = !ecModel.ssr && lineTruthyOpt(seriesModel.get("animation"))

        let isAreaChart = !areaStyleModel.isEmpty()

        let valueOrigin = areaStyleModel.get("origin")
        let dataCoordInfo = prepareDataCoordInfo(coordSys, data, valueOrigin)

        var stackedOnPoints: [Double]? = isAreaChart ? getStackedOnPoints(coordSys, data, dataCoordInfo) : nil

        let showSymbol = lineTruthyOpt(seriesModel.get("showSymbol"))

        let connectNulls = (seriesModel.get("connectNulls") as? Bool) ?? false

        let isIgnoreFunc: ((Int) -> Bool)? = (showSymbol && !isCoordSysPolar)
            ? getIsIgnoreFunc(seriesModel, data, coordSys.asCartesian2D!)
            : nil

        // Remove temporary symbols
        let oldData = self._data
        oldData?.eachItemGraphicEl { el, idx in
            if (el as? Symbol)?.__temp == true {
                _ = group.remove(el)
                oldData?.setItemGraphicEl(Int(idx), nil)
            }
        }

        // Remove previous created symbols if showSymbol changed to false
        if !showSymbol {
            symbolDraw.remove()
        }

        _ = group.add(lineGroup)

        // FIXME step not support polar
        let step: Any? = !isCoordSysPolar ? seriesModel.get("step") : false
        var clipShapeForSymbol: CoordinateSystemClipArea?
        if (seriesModel.get("clip", true) as? Bool) ?? true {
            let area = coordSys.getArea()
            // Avoid float number rounding error for symbol on the edge of axis extent.
            // See #7913 and `test/dataZoom-clip.html`.
            // upstream branches on `.width != null` (Cartesian2DArea) vs `.r0` (PolarArea). Our
            //   `getArea()` returns a `CoordinateSystemClipArea` existential; mutation must go through
            //   the concrete reference class (BoundingRect / PolarArea), so cast.
            if let polarArea = area as? PolarArea {
                if polarArea.r0 != 0 {
                    polarArea.r0 -= 0.5
                    polarArea.r += 0.5
                }
                clipShapeForSymbol = polarArea
            }
            else if let rect = area as? BoundingRect {
                rect.x -= 0.1
                rect.y -= 0.1
                rect.width += 0.2
                rect.height += 0.2
                clipShapeForSymbol = rect
            }
            else {
                clipShapeForSymbol = area
            }
        }
        self._clipShapeForSymbol = clipShapeForSymbol
        let visualColor: ZRenderKit.ZRColor? = getVisualGradient(data, coordSys, api)
            ?? lineStyleDrawTypeColor(data)
        // Initialization animation or coordinate system changed
        if
            !(polyline != nil && prevCoordSys?.type == coordSys.type && lineStepEqual(step, self._step))
        {
            if showSymbol {
                var opt = SymbolDrawUpdateOpt()
                opt.isIgnore = isIgnoreFunc
                opt.clipShape = clipShapeForSymbol as? SymbolClipShape
                opt.disableAnimation = true
                opt.getSymbolPoint = { idx in
                    return [pointsAt(points, idx * 2), pointsAt(points, idx * 2 + 1)]
                }
                symbolDraw.updateData(data, opt)
            }

            if hasAnimation {
                self._initSymbolLabelAnimation(data, coordSys, clipShapeForSymbol)
            }

            if lineStepTruthy(step) {
                let stepStr = lineStepString(step)
                if var sop = stackedOnPoints {
                    sop = turnPointsIntoStep(sop, points, coordSys, stepStr, connectNulls)
                    stackedOnPoints = sop
                }
                // TODO If stacked series is not step
                points = turnPointsIntoStep(points, nil, coordSys, stepStr, connectNulls)
            }

            polyline = self._newPolyline(points)
            if isAreaChart {
                polygon = self._newPolygon(points, stackedOnPoints ?? [])
            }// If areaStyle is removed
            else if let poly = polygon {
                _ = lineGroup.remove(poly)
                polygon = nil
                self._polygon = nil
            }

            // NOTE: Must update _endLabel before setClipPath.
            if !isCoordSysPolar {
                self._initOrUpdateEndLabel(seriesModel, coordSys.asCartesian2D!, lineVisualColorToString(visualColor))
            }

            lineGroup.setClipPath(
                createLineClipPath(self, coordSys, true, seriesModel)
            )
        }
        else {
            if isAreaChart && polygon == nil {
                // If areaStyle is added
                polygon = self._newPolygon(points, stackedOnPoints ?? [])
            }
            else if let poly = polygon, !isAreaChart {
                // If areaStyle is removed
                _ = lineGroup.remove(poly)
                polygon = nil
                self._polygon = nil
            }

            // NOTE: Must update _endLabel before setClipPath.
            if !isCoordSysPolar {
                self._initOrUpdateEndLabel(seriesModel, coordSys.asCartesian2D!, lineVisualColorToString(visualColor))
            }

            // Update clipPath
            let oldClipPath = lineGroup.getClipPath()
            if let oldClipPath = oldClipPath {
                let newClipPath = createLineClipPath(self, coordSys, false, seriesModel)
                initProps(oldClipPath, ["shape": lineClipShapeDict(newClipPath)], seriesModel)
            }
            else {
                lineGroup.setClipPath(
                    createLineClipPath(self, coordSys, true, seriesModel)
                )
            }

            // Always update, or it is wrong in the case turning on legend
            // because points are not changed.
            if showSymbol {
                var opt = SymbolDrawUpdateOpt()
                opt.isIgnore = isIgnoreFunc
                opt.clipShape = clipShapeForSymbol as? SymbolClipShape
                opt.disableAnimation = true
                opt.getSymbolPoint = { idx in
                    return [pointsAt(points, idx * 2), pointsAt(points, idx * 2 + 1)]
                }
                symbolDraw.updateData(data, opt)
            }

            // In the case data zoom triggered refreshing frequently
            // Data may not change if line has a category axis. So it should animate nothing.
            if !isPointsSame(self._stackedOnPoints, stackedOnPoints ?? [])
                || !isPointsSame(self._points, points)
            {
                if hasAnimation {
                    self._doUpdateAnimation(
                        data, stackedOnPoints ?? [], coordSys, api, step, valueOrigin, connectNulls
                    )
                }
                else {
                    // Not do it in update with animation
                    if lineStepTruthy(step) {
                        let stepStr = lineStepString(step)
                        if var sop = stackedOnPoints {
                            sop = turnPointsIntoStep(sop, points, coordSys, stepStr, connectNulls)
                            stackedOnPoints = sop
                        }
                        // TODO If stacked series is not step
                        points = turnPointsIntoStep(points, nil, coordSys, stepStr, connectNulls)
                    }

                    _ = polyline?.setShape("points", points)
                    if let polygon = polygon {
                        _ = polygon.setShape("points", points)
                        _ = polygon.setShape("stackedOnPoints", stackedOnPoints ?? [])
                    }
                }
            }
        }

        let emphasisModel = seriesModel.getModel("emphasis")
        let focus: InnerFocus? = emphasisModel.get("focus")
        let blurScope = (emphasisModel.get("blurScope") as? String).flatMap { BlurScope(rawValue: $0) }
        let emphasisDisabled = (emphasisModel.get("disabled") as? Bool) ?? false

        // polyline.useStyle(defaults(lineStyleModel.getLineStyle(), {fill:'none', stroke: visualColor, lineJoin:'bevel'}))
        if let polyline = polyline {
            var st = barStyleFromDict(lineStyleModel.getLineStyle())
            if st.stroke == nil { st.stroke = visualColor }
            st.fill = .string("none")
            st.lineJoin = "bevel"
            polyline.useStyle(st)

            states.setStatesStylesFromModel(polyline, seriesModel, "lineStyle")

            if (polyline.pathStyle?.lineWidth ?? 0) > 0
                && (seriesModel.get(["emphasis", "lineStyle", "width"]) as? String) == "bolder" {
                let emphasisState = polyline.ensureState("emphasis")
                var stStyle = emphasisState.style ?? [:]
                stStyle["lineWidth"] = (polyline.pathStyle?.lineWidth ?? 0) + 1
                emphasisState.style = stStyle
            }

            // Needs seriesIndex for focus
            innerStore.getECData(polyline).seriesIndex = seriesModel.seriesIndex
            states.toggleHoverEmphasis(polyline, focus, blurScope, emphasisDisabled)
        }

        let smooth = getSmooth(seriesModel.get("smooth"))
        let smoothMonotone = seriesModel.get("smoothMonotone") as? String

        if let polyline = polyline {
            _ = polyline.setShape("smooth", smooth)
            _ = polyline.setShape("smoothMonotone", smoothMonotone)
            _ = polyline.setShape("connectNulls", connectNulls)
        }

        if let polygon = polygon {
            let stackedOnSeries = data.getCalculationInfo("stackedOnSeries") as? SeriesModel
            var stackedOnSmooth: Double = 0

            var aSt = barStyleFromDict(areaStyleModel.getAreaStyle())
            if aSt.fill == nil { aSt.fill = visualColor }
            if aSt.opacity == nil { aSt.opacity = 0.7 }
            aSt.lineJoin = "bevel"
            if let decal = (data.getVisual("style") as? [String: Any])?["decal"] as? ZRenderKit.Pattern {
                aSt.decal = decal
            }
            polygon.useStyle(aSt)

            if let stackedOnSeries = stackedOnSeries {
                stackedOnSmooth = getSmooth(stackedOnSeries.get("smooth"))
            }

            _ = polygon.setShape("smooth", smooth)
            _ = polygon.setShape("stackedOnSmooth", stackedOnSmooth)
            _ = polygon.setShape("smoothMonotone", smoothMonotone)
            _ = polygon.setShape("connectNulls", connectNulls)

            states.setStatesStylesFromModel(polygon, seriesModel, "areaStyle")
            // Needs seriesIndex for focus
            innerStore.getECData(polygon).seriesIndex = seriesModel.seriesIndex
            states.toggleHoverEmphasis(polygon, focus, blurScope, emphasisDisabled)
        }

        // Switch polyline / polygon state if element changed its state.
        data.eachItemGraphicEl { el, _ in
            states.getHighDownInner(el).onHoverStateChange = { [weak self] toState in
                self?._changePolyState(toState)
            }
        }

        if let polyline = polyline {
            states.getHighDownInner(polyline).onHoverStateChange = { [weak self] toState in
                self?._changePolyState(toState)
            }
        }

        self._data = data
        // Save the coordinate system for transition animation when data changed
        self._coordSys = coordSys
        self._stackedOnPoints = stackedOnPoints ?? []
        self._points = points
        self._step = step
        self._valueOrigin = valueOrigin
        self._polyline = polyline
        self._polygon = polygon

        let triggerEvent = seriesModel.get("triggerEvent")
        let triggerLineEvent = seriesModel.get("triggerLineEvent")

        // upstream warns via `warnDeprecated('triggerLineEvent', ...)` in __DEV__; the
        //   `warnDeprecated` helper is not ported, so the deprecation warning is omitted (behaviorally
        //   inert — the option is still honored below).

        let shouldTriggerLineEvent = (triggerLineEvent as? Bool) == true || (triggerEvent as? Bool) == true || (triggerEvent as? String) == "line"
        let shouldTriggerAreaEvent = (triggerLineEvent as? Bool) == true || (triggerEvent as? Bool) == true || (triggerEvent as? String) == "area"

        if let polyline = polyline {
            self.packEventData(seriesModel, polyline, shouldTriggerLineEvent)
        }
        if let polygon = polygon {
            self.packEventData(seriesModel, polygon, shouldTriggerAreaEvent)
        }
    }

    // upstream: private packEventData(seriesModel, el, enable)
    private func packEventData(_ seriesModel: SeriesModel, _ el: Element, _ enable: Bool) {
        innerStore.getECData(el).eventData = enable ? ([
            "componentType": "series",
            "componentSubType": "line",
            "componentIndex": seriesModel.componentIndex as Any,
            "seriesIndex": seriesModel.seriesIndex as Any,
            "seriesName": seriesModel.name as Any,
            "seriesType": "line",
            // for determining this event is triggered by area or line
            "selfType": (el === self._polygon) ? "area" : "line"
        ] as ECEventData) : nil
    }

    open override func highlight(
        _ seriesModel: SeriesModel, _ ecModel: GlobalModel, _ api: ExtensionAPI, _ payload: Payload
    ) {
        let data = seriesModel.getData()
        let dataIndex = model.queryDataIndex(data, payload)

        self._changePolyState(.emphasis)

        if !(dataIndex is [Any]), let dataIndexNum = lineHelperToNumberOpt(dataIndex), dataIndexNum >= 0 {
            let idx = Int(dataIndexNum)
            let points = data.getLayout("points") as? [Double] ?? []
            var symbolEl = data.getItemGraphicEl(idx) as? Symbol
            if symbolEl == nil {
                // Create a temporary symbol if it is not exists
                let x = pointsAt(points, idx * 2)
                let y = pointsAt(points, idx * 2 + 1)
                if isPointIllegal(x, y) {
                    // Null data
                    return
                }
                // fix #11360: shouldn't draw symbol outside clipShapeForSymbol
                if let clip = self._clipShapeForSymbol, !clip.contain(x, y) {
                    return
                }
                let zlevel = (seriesModel.get("zlevel") as? Double) ?? 0
                let z = (seriesModel.get("z") as? Double) ?? 0
                let sym = Symbol(data, idx)
                sym.x = x
                sym.y = y
                sym.setZ(zlevel, z)

                // ensure label text of the temporary symbol is in front of line and area polygon
                if let symbolLabel = sym.getSymbolPath()?.getTextContent() {
                    symbolLabel.zlevel = zlevel
                    symbolLabel.z = z
                    symbolLabel.z2 = (self._polyline?.z2 ?? 0) + 1
                }

                sym.__temp = true
                data.setItemGraphicEl(idx, sym)

                // Stop scale animation
                sym.stopSymbolAnimation(true)

                _ = self.group.add(sym)
                symbolEl = sym
            }
            symbolEl?.highlight()
        }
        else {
            // Highlight whole series
            super.highlight(seriesModel, ecModel, api, payload)
        }
    }

    open override func downplay(
        _ seriesModel: SeriesModel, _ ecModel: GlobalModel, _ api: ExtensionAPI, _ payload: Payload
    ) {
        let data = seriesModel.getData()
        let dataIndex = model.queryDataIndex(data, payload)

        self._changePolyState(.normal)

        if let dataIndexNum = lineHelperToNumberOpt(dataIndex), dataIndexNum >= 0 {
            let idx = Int(dataIndexNum)
            if let symbolEl = data.getItemGraphicEl(idx) as? Symbol {
                if symbolEl.__temp {
                    data.setItemGraphicEl(idx, nil)
                    _ = self.group.remove(symbolEl)
                }
                else {
                    symbolEl.downplay()
                }
            }
        }
        else {
            // FIXME
            // can not downplay completely.
            // Downplay whole series
            super.downplay(seriesModel, ecModel, api, payload)
        }
    }

    // upstream: _changePolyState(toState)
    func _changePolyState(_ toState: DisplayState) {
        let polygon = self._polygon
        if let polyline = self._polyline {
            states.setStatesFlag(polyline, toState)
            // upstream is flag-only (applyChangedStates runs next frame); this port applies states
            //   eagerly (see the states.swift doChangeHoverState deviation), so apply here too.
            states.applyElementStates(polyline)
        }
        if let polygon = polygon {
            states.setStatesFlag(polygon, toState)
            states.applyElementStates(polygon)
        }
    }

    // upstream: _newPolyline(points)
    private func _newPolyline(_ points: [Double]) -> ECPolyline {
        let old = self._polyline
        // Remove previous created polyline
        if let old = old {
            _ = self._lineGroup.remove(old)
        }

        var shape = ECPolylineShape()
        shape.points = points
        let polyline = ECPolyline([
            "shape": shape as PathShape,
            "segmentIgnoreThreshold": 2.0,
            "z2": 10.0
        ])
        polyline.name = "line"

        _ = self._lineGroup.add(polyline)

        self._polyline = polyline

        return polyline
    }

    // upstream: _newPolygon(points, stackedOnPoints)
    private func _newPolygon(_ points: [Double], _ stackedOnPoints: [Double]) -> ECPolygon {
        let old = self._polygon
        // Remove previous created polygon
        if let old = old {
            _ = self._lineGroup.remove(old)
        }

        var shape = ECPolygonShape()
        shape.points = points
        shape.stackedOnPoints = stackedOnPoints
        let polygon = ECPolygon([
            "shape": shape as PathShape,
            "segmentIgnoreThreshold": 2.0
        ])
        polygon.name = "area"

        _ = self._lineGroup.add(polygon)

        self._polygon = polygon
        return polygon
    }

    // upstream: _initSymbolLabelAnimation(data, coordSys, clipShape)
    private func _initSymbolLabelAnimation(
        _ data: SeriesData,
        _ coordSys: LineCoordSys,
        _ clipShape: CoordinateSystemClipArea?
    ) {
        var isHorizontalOrRadial = false
        var isCoordSysPolar = false
        let baseAxis = coordSys.getBaseAxis()
        let isAxisInverse = baseAxis.inverse
        if coordSys.type == "cartesian2d" {
            isHorizontalOrRadial = (baseAxis as! Axis2D).isHorizontal()
            isCoordSysPolar = false
        }
        else if coordSys.type == "polar" {
            isHorizontalOrRadial = baseAxis.dim == "angle"
            isCoordSysPolar = true
        }

        let seriesModel = data.hostModel
        // upstream:
        //   let seriesDuration = seriesModel.get('animationDuration');
        //   if (isFunction(seriesDuration)) { seriesDuration = seriesDuration(null); }
        // The option may be a per-index callback (AnimationDurationCallback = (Double) -> Double). The
        //   series-level resolution passes `null` for the dataIndex, modeled here as Double.nan.
        let seriesDurationRaw = seriesModel?.get("animationDuration")
        let seriesDurationVal: Double
        if let f = seriesDurationRaw as? AnimationDurationCallback {
            seriesDurationVal = f(Double.nan)   // seriesDuration(null)
        } else {
            seriesDurationVal = lineHelperToNumberOpt(seriesDurationRaw) ?? 0
        }
        // upstream:
        //   const seriesDelay = seriesModel.get('animationDelay') || 0;
        //   const seriesDelayValue = isFunction(seriesDelay) ? seriesDelay(null) : seriesDelay;
        let seriesDelayRaw = seriesModel?.get("animationDelay")
        let seriesDelayCallback = seriesDelayRaw as? AnimationDelayCallback
        let seriesDelayValue: Double = seriesDelayCallback != nil
            ? seriesDelayCallback!(Double.nan, nil)   // seriesDelay(null)
            : (lineHelperToNumberOpt(seriesDelayRaw) ?? 0)

        data.eachItemGraphicEl { el, idx in
            guard let symbol = el as? Symbol else { return }
            let point = [symbol.x, symbol.y]
            var start = Double.nan
            var end = Double.nan
            var current = Double.nan
            if let clipShape = clipShape {
                if isCoordSysPolar {
                    let polarClip = clipShape as! PolarArea
                    let coord = coordSys.asPolar!.pointToCoord(point)
                    if isHorizontalOrRadial {
                        start = polarClip.startAngle
                        end = polarClip.endAngle
                        current = -coord[1] / 180 * Double.pi
                    }
                    else {
                        start = polarClip.r0
                        end = polarClip.r
                        current = coord[0]
                    }
                }
                else {
                    let gridClip = clipShape
                    if isHorizontalOrRadial {
                        start = gridClip.x
                        end = gridClip.x + gridClip.width
                        current = symbol.x
                    }
                    else {
                        start = gridClip.y + gridClip.height
                        end = gridClip.y
                        current = symbol.y
                    }
                }
            }
            var ratio = end == start ? 0 : (current - start) / (end - start)
            if isAxisInverse {
                ratio = 1 - ratio
            }

            // upstream: const delay = isFunction(seriesDelay) ? seriesDelay(idx)
            //             : (seriesDuration * ratio) + seriesDelayValue;
            let delay: Double
            if let cb = seriesDelayCallback {
                delay = cb(Double(idx), nil)
            } else {
                delay = (seriesDurationVal * ratio) + seriesDelayValue
            }

            let symbolPath = symbol.getSymbolPath()
            let text = symbolPath?.getTextContent()

            _ = symbol.attr(["scaleX": 0.0, "scaleY": 0.0])
            var toCfg = ElementAnimateConfig()
            toCfg.duration = 200
            toCfg.setToFinal = true
            toCfg.delay = delay
            symbol.animateTo(["scaleX": 1.0, "scaleY": 1.0], toCfg)

            if let text = text {
                var fromCfg = ElementAnimateConfig()
                fromCfg.duration = 300
                fromCfg.delay = delay
                text.animateFrom(["style": ["opacity": 0.0]], fromCfg)
            }

            // upstream: (symbolPath as ECElement).disableLabelAnimation = true;
            if let symbolPath = symbolPath {
                innerStore.getECElementProps(symbolPath).disableLabelAnimation = true
            }
            _ = symbolPath
        }
    }

    // upstream: _initOrUpdateEndLabel(seriesModel, coordSys, inheritColor)
    private func _initOrUpdateEndLabel(
        _ seriesModel: SeriesModel,
        _ coordSys: Cartesian2D,
        _ inheritColor: String
    ) {
        let endLabelModel = seriesModel.getModel("endLabel")

        if anyStateShowEndLabel(seriesModel) {
            let data = seriesModel.getData()
            let polyline = self._polyline
            // series may be filtered.
            let pointsOpt = data.getLayout("points") as? [Double]
            guard let points = pointsOpt else {
                polyline?.removeTextContent()
                self._endLabel = nil
                return
            }
            var endLabel = self._endLabel
            if endLabel == nil {
                let created = ZRText(["z2": 200.0]) // should be higher than item symbol
                created.ignoreClip = true
                polyline?.setTextContent(created)
                // upstream: (polyline as ECElement).disableLabelAnimation = true;
                if let polyline = polyline {
                    innerStore.getECElementProps(polyline).disableLabelAnimation = true
                }
                self._endLabel = created
                endLabel = created
            }

            // Find last non-NaN data to display data
            let dataIndex = getLastIndexNotNull(points)
            if dataIndex >= 0, let polyline = polyline {
                var opt = SetLabelStyleOpt()
                opt.inheritColor = inheritColor
                opt.labelFetcher = seriesModel
                opt.labelDataIndex = Double(dataIndex)
                opt.defaultText = ({ (dIdx: Double?, _ opt: SetLabelStyleOpt, interpolatedValue: InterpolatableValue?) -> String in
                    if let interpolatedValue = interpolatedValue {
                        return labelHelper.getDefaultInterpolatedLabel(data, interpolatedValue)
                    }
                    return labelHelper.getDefaultLabel(data, dIdx ?? 0) ?? ""
                } as DefaultTextFn)
                opt.enableTextSetter = true
                labelStyle.setLabelStyle(
                    polyline,
                    labelStyle.getLabelStatesModels(seriesModel, "endLabel"),
                    opt,
                    getEndLabelStateSpecified(endLabelModel, coordSys)
                )
                var tc = polyline.textConfig ?? ElementTextConfig()
                tc.position = nil
                polyline.textConfig = tc
            }
        }
        else if self._endLabel != nil {
            self._polyline?.removeTextContent()
            self._endLabel = nil
        }
    }

    // upstream: _endLabelOnDuring(percent, clipRect, data, animationRecord, valueAnimation, endLabelModel, coordSys)
    func _endLabelOnDuring(
        _ percent: Double,
        _ clipRect: Rect,
        _ data: SeriesData,
        _ animationRecord: EndLabelAnimationRecord,
        _ valueAnimation: Bool,
        _ endLabelModel: Model,
        _ coordSys: Cartesian2D
    ) {
        let endLabel = self._endLabel
        let polyline = self._polyline

        if let endLabel = endLabel {
            // NOTE: Don't remove percent < 1. percent === 1 means the first frame during render.
            // The label is not prepared at this time.
            if percent < 1 && animationRecord.originalX == nil {
                animationRecord.originalX = endLabel.x
                animationRecord.originalY = endLabel.y
            }

            let points = (data.getLayout("points") as? [Double]) ?? []

            // upstream: `data.hostModel as LineSeriesModel` — narrow so `getRawValue` (a SeriesModel
            //   member via the DataFormatMixin) resolves.
            let seriesModel = data.hostModel as? SeriesModel
            let connectNulls = (seriesModel?.get("connectNulls") as? Bool) ?? false
            let precision = endLabelModel.get("precision")
            let distance = (endLabelModel.get("distance") as? Double) ?? 0

            let baseAxis = coordSys.getBaseAxis()
            let isHorizontal = baseAxis.isHorizontal()
            let isBaseInversed = baseAxis.inverse
            let clipShape = clipRect.shape as! RectShape

            let xOrY = isBaseInversed
                ? (isHorizontal ? clipShape.x : (clipShape.y + clipShape.height))
                : (isHorizontal ? (clipShape.x + clipShape.width) : clipShape.y)
            let distanceX = (isHorizontal ? distance : 0) * (isBaseInversed ? -1 : 1)
            let distanceY = (isHorizontal ? 0 : -distance) * (isBaseInversed ? -1 : 1)
            let dim = isHorizontal ? "x" : "y"

            let dataIndexRange = getIndexRange(points, xOrY, dim)
            let indices = dataIndexRange.range

            let diff = indices[1] - indices[0]
            var value: Any?
            if diff >= 1 {
                // diff > 1 && connectNulls, which is on the null data.
                if diff > 1 && !connectNulls {
                    let pt = getPointAtIndex(points, indices[0])
                    _ = endLabel.attr(["x": pt[0] + distanceX, "y": pt[1] + distanceY])
                    if valueAnimation { value = seriesModel?.getRawValue(Double(indices[0])) }
                }
                else {
                    let pt = polyline?.getPointOn(xOrY, dim)
                    if let pt = pt {
                        _ = endLabel.attr(["x": pt[0] + distanceX, "y": pt[1] + distanceY])
                    }

                    let startValue = seriesModel?.getRawValue(Double(indices[0]))
                    let endValue = seriesModel?.getRawValue(Double(indices[1]))
                    if valueAnimation {
                        value = model.interpolateRawValues(
                            data, precision, startValue, endValue, dataIndexRange.t
                        )
                    }
                }
                animationRecord.lastFrameIndex = indices[0]
            }
            else {
                // If diff <= 0, which is the range is not found(Include NaN)
                // Choose the first point or last point.
                let idx = (percent == 1 || animationRecord.lastFrameIndex > 0) ? indices[0] : 0
                let pt = getPointAtIndex(points, idx)
                if valueAnimation { value = seriesModel?.getRawValue(Double(idx)) }
                _ = endLabel.attr(["x": pt[0] + distanceX, "y": pt[1] + distanceY])
            }
            if valueAnimation {
                let inner = labelStyle.labelInner(endLabel)
                if let setLabelText = inner.setLabelText {
                    setLabelText(value)
                }
            }
        }
    }

    /**
     * @private
     */
    // FIXME Two value axis
    // upstream: _doUpdateAnimation(data, stackedOnPoints, coordSys, api, step, valueOrigin, connectNulls)
    private func _doUpdateAnimation(
        _ data: SeriesData,
        _ stackedOnPointsIn: [Double],
        _ coordSys: LineCoordSys,
        _ api: ExtensionAPI,
        _ step: Any?,
        _ valueOrigin: Any?,
        _ connectNulls: Bool
    ) {
        guard let polyline = self._polyline else { return }
        let polygon = self._polygon
        let seriesModel = data.hostModel

        let diffResult = lineAnimationDiff(
            self._data, data,
            self._stackedOnPoints, stackedOnPointsIn,
            self._coordSys ?? coordSys, coordSys,
            self._valueOrigin, valueOrigin
        )

        var current = diffResult.current
        var stackedOnCurrent = diffResult.stackedOnCurrent
        var next = diffResult.next
        var stackedOnNext = diffResult.stackedOnNext
        if lineStepTruthy(step) {
            let stepStr = lineStepString(step)
            // TODO If stacked series is not step
            stackedOnCurrent = turnPointsIntoStep(diffResult.stackedOnCurrent, diffResult.current, coordSys, stepStr, connectNulls)
            current = turnPointsIntoStep(diffResult.current, nil, coordSys, stepStr, connectNulls)
            stackedOnNext = turnPointsIntoStep(diffResult.stackedOnNext, diffResult.next, coordSys, stepStr, connectNulls)
            next = turnPointsIntoStep(diffResult.next, nil, coordSys, stepStr, connectNulls)
        }
        // Don't apply animation if diff is large.
        // For better result and avoid memory explosion problems like
        // https://github.com/apache/incubator-echarts/issues/12229
        if getBoundingDiff(current, next) > 3000
            || (polygon != nil && getBoundingDiff(stackedOnCurrent, stackedOnNext) > 3000)
        {
            _ = polyline.stopAnimation()
            _ = polyline.setShape("points", next)
            if let polygon = polygon {
                _ = polygon.stopAnimation()
                _ = polygon.setShape("points", next)
                _ = polygon.setShape("stackedOnPoints", stackedOnNext)
            }
            return
        }

        // (polyline.shape as any).__points = diff.current;
        // polyline.shape.points = current;
        if var sh = polyline.shape as? ECPolylineShape {
            sh.__points = diffResult.current
            sh.points = current
            polyline.shape = sh
        }

        var target: [String: Any] = ["shape": ["points": next] as [String: Any]]
        // Also animate the original (un-stepped) points that the symbol `during` reads.
        //
        // Upstream only re-adds `__points` here when the points reference changed (`diffResult.current
        // !== current`, i.e. a step line built a NEW array): for a NON-step line `points === __points`
        // (SAME Array reference), so animating `shape.points` mutates that shared array in place and
        // `__points` advances for free. Swift arrays are VALUE types (CONVENTIONS §3/§4) — `points` and
        // `__points` are INDEPENDENT copies with no shared backing — so `__points` would stay frozen at
        // `diffResult.current` (the PRE-morph positions) and the `during` callback would drag every
        // symbol back onto the old layout (e.g. a legend toggle rescales the axis, the line morphs to the
        // new scale, but the data points revert to their old positions — official-line-log). Animate it
        // explicitly in BOTH cases so the symbols follow the line.
        var shapeDict = target["shape"] as! [String: Any]
        shapeDict["__points"] = diffResult.next
        target["shape"] = shapeDict

        // Stop previous animation.
        _ = polyline.stopAnimation()
        updateProps(polyline, target, seriesModel)

        if let polygon = polygon {
            _ = polygon.setShape("points", current)
            _ = polygon.setShape("stackedOnPoints", stackedOnCurrent)
            _ = polygon.stopAnimation()
            updateProps(polygon, ["shape": ["stackedOnPoints": stackedOnNext] as [String: Any]], seriesModel)
            // If use attr directly in updateProps.
            // (polyline.shape.points !== polygon.shape.points) — always re-sync from polyline.
            if let plShape = polyline.shape as? ECPolylineShape, var pgShape = polygon.shape as? ECPolygonShape {
                pgShape.points = plShape.points
                polygon.shape = pgShape
            }
        }

        var updatedDataInfo: [(el: Symbol, ptIdx: Int)] = []
        let diffStatus = diffResult.status

        for i in 0..<diffStatus.count {
            let cmd = diffStatus[i].cmd
            if cmd == "=" {
                if let el = data.getItemGraphicEl(diffStatus[i].idx1 ?? 0) as? Symbol {
                    updatedDataInfo.append((el: el, ptIdx: i))  // Index of points
                }
            }
        }
        if let animator = polyline.animators.first {
            _ = animator.during { [weak polyline, weak polygon] _, _ in
                // upstream shares the array reference (`polygon.shape.points === polyline.shape.points`),
                //   so the polyline animator mutating `points` in place also moves the polygon's top edge,
                //   and `dirtyShape()` re-renders it. Swift arrays are value types (CONVENTIONS §3/§4), so
                //   the reference is NOT shared — copy the polyline's live animated points into the polygon
                //   each frame so the area band follows the line morph.
                if let polygon = polygon,
                   let plShape = polyline?.shape as? ECPolylineShape,
                   var pgShape = polygon.shape as? ECPolygonShape {
                    pgShape.points = plShape.points
                    polygon.shape = pgShape
                    polygon.dirtyShape()
                }
                let points = (polyline?.shape as? ECPolylineShape)?.__points ?? []
                for i in 0..<updatedDataInfo.count {
                    let el = updatedDataInfo[i].el
                    let offset = updatedDataInfo[i].ptIdx * 2
                    el.x = offset < points.count ? points[offset] : Double.nan
                    el.y = offset + 1 < points.count ? points[offset + 1] : Double.nan
                    el.markRedraw()
                }
            }
        }
    }

    open override func remove(_ ecModel: GlobalModel, _ api: ExtensionAPI) {
        let group = self.group
        let oldData = self._data
        self._lineGroup?.removeAll()
        self._symbolDraw?.remove(true)
        // Remove temporary created elements when highlighting
        oldData?.eachItemGraphicEl { el, idx in
            if (el as? Symbol)?.__temp == true {
                _ = group.remove(el)
                oldData?.setItemGraphicEl(Int(idx), nil)
            }
        }

        self._polyline = nil
        self._polygon = nil
        self._coordSys = nil
        self._points = []
        self._stackedOnPoints = []
        self._endLabel = nil
        self._data = nil
    }
}

// export default LineView;  -> `open class LineView` above.

// ---------------------------------------------------------------------------
// PORT-LOCAL helpers (not upstream symbols).
// ---------------------------------------------------------------------------

// Out-of-range → NaN reader for the flat point buffer (mirrors JS `Float32Array[i]` → undefined→NaN).
@inline(__always)
private func pointsAt(_ points: [Double], _ i: Int) -> Double {
    return (i >= 0 && i < points.count) ? points[i] : Double.nan
}

// JS truthiness for option values: a non-empty string / true / non-nil object. `false`/nil/''/0 falsy.
private func lineTruthyOpt(_ v: Any?) -> Bool {
    if v == nil || v is NSNull { return false }
    if let b = v as? Bool { return b }
    if let s = v as? String { return !s.isEmpty }
    if let d = lineHelperToNumberOpt(v) { return d != 0 && !d.isNaN }
    return true
}

// `step === this._step` — compare the raw step option value (String | Bool | nil) faithfully.
private func lineStepEqual(_ a: Any?, _ b: Any?) -> Bool {
    let an = (a == nil || a is NSNull)
    let bn = (b == nil || b is NSNull)
    if an || bn { return an && bn }
    if let sa = a as? String, let sb = b as? String { return sa == sb }
    if let ba = a as? Bool, let bb = b as? Bool { return ba == bb }
    // Mixed String vs Bool (e.g. 'start' vs false) — not equal.
    return false
}

// `if (step)` truthiness — a non-empty string or `true`.
private func lineStepTruthy(_ step: Any?) -> Bool {
    if let s = step as? String { return !s.isEmpty }
    if let b = step as? Bool { return b }
    return false
}

// The `stepTurnAt` string handed to turnPointsIntoStep: a String step passes through; `true` → "start".
private func lineStepString(_ step: Any?) -> String {
    if let s = step as? String { return s }
    return "start"   // `true` (and any truthy non-string) → default 'start'
}

// `data.getVisual('style')[data.getVisual('drawType')]` bridged to a ZRenderKit paint color.
private func lineStyleDrawTypeColor(_ data: SeriesData) -> ZRenderKit.ZRColor? {
    guard let style = data.getVisual("style") as? [String: Any] else { return nil }
    let drawType = (data.getVisual("drawType") as? String) ?? "fill"
    return zrPaintFromStyleValue(style[drawType])
}

// convertToColorString(visualColor) — gradient → first stop color; string → itself; nil → 'transparent'.
private func lineVisualColorToString(_ v: ZRenderKit.ZRColor?) -> String {
    switch v {
    case .string(let s)?: return s
    case .linearGradient(let g)?: return g.colorStops.first?.color ?? "transparent"
    case .radialGradient(let g)?: return g.colorStops.first?.color ?? "transparent"
    default: return "transparent"
    }
}

// The clip path's shape as an animatable `[String: Any]` dict for `initProps(oldClipPath, {shape})`.
private func lineClipShapeDict(_ clipPath: Path) -> [String: Any] {
    if let r = clipPath.shape as? RectShape {
        return ["x": r.x, "y": r.y, "width": r.width, "height": r.height]
    }
    if let s = clipPath.shape as? SectorShape {
        return ["cx": s.cx, "cy": s.cy, "r0": s.r0, "r": s.r,
                "startAngle": s.startAngle, "endAngle": s.endAngle]
    }
    return [:]
}

// upstream `diff.current !== current` reference-identity test. Our buffers are value types; the pair is
//   only distinct when `turnPointsIntoStep` produced a new array — a length change is the reliable
//   distinguisher (step insertion adds points), matching the upstream intent (was the array re-shaped?).
private func lineArraySameLength(_ a: [Double], _ b: [Double]) -> Bool {
    return a.count == b.count
}

// `baseAxis.isHorizontal()` — the base `Axis` has no `isHorizontal`; only `Axis2D` (cartesian) does.
//   A polar base axis is never horizontal in the createLineClipPath sense (the cartesian-only clip
//   expansion). PORT-LOCAL shim so createLineClipPath reads like upstream.
private extension Axis {
    func isHorizontal_() -> Bool {
        return (self as? Axis2D)?.isHorizontal() ?? false
    }
}
