// Ported from echarts/src/coord/matrix/matrixCoordHelper.ts — keep in sync with upstream
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

// import Point from 'zrender/src/core/Point';                              -> Point (ZRenderKit)
// import type { MatrixCellLayoutInfo, MatrixDimensionCell, MatrixDimPair,
//   MatrixXYLocator, MatrixXYLocatorRange } from './MatrixDim';            -> MatrixDim.swift (SIBLING)
// import type { NullUndefined } from '../../util/types';                   -> modeled as Swift Optional
// import { eqNaN, isArray, isNumber } from 'zrender/src/core/util';        -> util.* (ZRenderKit) / .isNaN
// import { WH, XY } from '../../util/graphic';                             -> dim-index helpers below (0=x/width, 1=y/height)
// import type { MatrixCoordRangeOption, MatrixCoordValueOption }
//   from './MatrixModel';                                                  -> declared here (see note); dynamic (Any)
// import type { RectLike } from 'zrender/src/core/BoundingRect';           -> RectLike (ZRenderKit)
// import { mathMax, mathMin } from '../../util/number';                    -> number.mathMax / number.mathMin
//
// Cross-file types (declared by the siblings ported in this phase):
//   MatrixDim / MatrixDimPair / MatrixDimensionCell / MatrixCellLayoutInfo / MatrixXYLocator /
//   MatrixXYLocatorRange           -> MatrixDim.swift
//   `MatrixXYLocatorRange` there is `typealias [[MatrixXYLocator]]` (== `[[Double]]`), a VALUE type; the
//   functions below therefore take it `inout` where upstream mutates the array reference in place.
//
// NOTE (declaration ownership): upstream declares `MatrixCoordValueOption` / `MatrixCoordRangeOption` in
//   MatrixModel.ts, but MatrixModel.swift deferred them (PORT-NOTE) and MatrixDim.swift references
//   `MatrixCoordValueOption` in `getCell`. They are the coord-parser's currency, so they are declared here
//   (one module-wide home, no redeclaration). Both are dynamic option values.
public typealias MatrixCoordValueOption = Any        // OrdinalRawValue | OrdinalNumber | MatrixXYLocator
public typealias MatrixCoordRangeOption = Any         // MatrixCoordValueOption | MatrixCoordValueOption[] | null

// ============================================================================
// Dimension-index helpers (upstream `const XY = ['x','y']`, `const WH = ['width','height']`).
// JS indexes Point/RectLike by these string keys; Swift indexes by dimension number
// (0 => x/width, 1 => y/height). See util/graphic.swift + ZRenderKit BoundingRect for the same idiom.
// ============================================================================

@inline(__always) private func dimOf(_ dims: MatrixDimPair, _ dimIdx: Int) -> MatrixDim {
    return dimIdx == 0 ? dims.x : dims.y   // dims[XY[dimIdx]]
}
@inline(__always) private func pointGetXY(_ p: Point, _ dim: Int) -> Double {
    return dim == 0 ? p.x : p.y            // p[XY[dim]]
}
@inline(__always) private func pointSetXY(_ p: Point, _ dim: Int, _ v: Double) {
    if dim == 0 { p.x = v } else { p.y = v }
}
@inline(__always) private func rectSetXY(_ r: RectLike, _ dim: Int, _ v: Double) {
    if dim == 0 { r.x = v } else { r.y = v }   // r[XY[dim]] = v
}
@inline(__always) private func rectSetWH(_ r: RectLike, _ dim: Int, _ v: Double) {
    if dim == 0 { r.width = v } else { r.height = v }   // r[WH[dim]] = v
}

// JS `isNumber(x) ? x : NaN` coercion. Returns the numeric value only for genuine number boxes
// (Int/Double); strings and everything else -> nil (matches upstream `isNumber`, which is false for
// strings). Guards the INT-vs-DOUBLE trap: Int-boxed defaults must not drop to nil.
@inline(__always) private func matrixCoordNumber(_ v: Any?) -> Double? {
    switch v {
    case let d as Double: return d
    case let i as Int: return Double(i)
    default: return nil
    }
}

// upstream: export const MatrixCellLayoutInfoType = { level: 1, leaf: 2, nonLeaf: 3 } as const;
//   Both a numeric const object AND a type (the `type` field of MatrixCellLayoutInfo). Ported as an
//   Int-raw enum so it serves as a type (`var type: MatrixCellLayoutInfoType`) with symbolic members.
public enum MatrixCellLayoutInfoType: Int {
    case level = 1
    case leaf = 2
    case nonLeaf = 3
}

/**
 * @public Public to users in `chart.convertFromPixel`.
 */
// upstream: export const MatrixClampOption = { none: 0, all: 1, body: 2, corner: 3 };
//   Used numerically (compared, `!!clamp`), so ported as a caseless enum of Int constants.
public enum MatrixClampOption {
    // No clamp, be falsy, equals to null/undefined. It means if the input part is
    // null/undefined/NaN/outOfBoundary, the result part is NaN, rather than clamp to
    // the boundary of the matrix.
    public static let none = 0
    // Clamp, where null/undefined/NaN/outOfBoundary can be used to cover the entire row/column.
    public static let all = 1
    public static let body = 2
    public static let corner = 3

    // upstream: `MatrixClampOption[self._kind]` where `_kind` is 'body' | 'corner'.
    public static func byKind(_ kind: String) -> Int {
        return kind == "body" ? body : corner
    }
}

/**
 * For the x direction,
 *  - find dimension cell from `xMatrixDim`,
 *      - If `xDimCell` or `yDimCell` is not a leaf, return the non-leaf cell itself.
 *  - otherwise find level from `yMatrixDim`.
 *  - otherwise return `NullUndefined`.
 *
 * For the y direction, it's the opposite.
 */
public func coordDataToAllCellLevelLayout(
    _ coordValue: Any?,        // MatrixCoordValueOption (may be null/undefined)
    _ dims: MatrixDimPair,
    _ thisDimIdx: Int          // 0 | 1
) -> MatrixCellLayoutInfo? {
    // Find in body. (JS `getCell(undefined)` -> scale.parse -> NaN -> undefined; guard nil here.)
    var result: MatrixCellLayoutInfo? = coordValue == nil ? nil : dimOf(dims, thisDimIdx).getCell(coordValue!)
    // Find in corner or dimension area.
    if result == nil, let n = matrixCoordNumber(coordValue), n < 0 {
        result = dimOf(dims, 1 - thisDimIdx).getUnitLayoutInfo(thisDimIdx, number.mathRound(n))
    }
    return result
}

// upstream reuses `out` (a reference array); with a value-type `[[Double]]` we return a fresh 2x2 filled
// with NaN. Callers use the return value (not the `out` argument) — kept only for signature parity.
public func resetXYLocatorRange(_ out: MatrixXYLocatorRange?) -> MatrixXYLocatorRange {
    // rg[0][0] = rg[0][1] = rg[1][0] = rg[1][1] = NaN;
    return [[Double.nan, Double.nan], [Double.nan, Double.nan]]
}

/**
 * If illegal or out of boundary, set NaN to `locOut`. See `isXYLocatorRangeInvalidOnDim`.
 * x dimension and y dimension are calculated separately.
 */
public func parseCoordRangeOption(
    _ locOut: inout MatrixXYLocatorRange,
    // If illegal input or can not find any target, save reason to it.
    // Do nothing if `NullUndefined`.
    _ reasonOut: inout [String]?,
    _ data: [Any?],            // MatrixCoordRangeOption[]
    _ dims: MatrixDimPair,
    _ clamp: Int               // MatrixClampOption
) {
    // x and y are supported to be handled separately - if one dimension is invalid
    // (may be users do not need that), the other one should also be calculated.
    parseCoordRangeOptionOnOneDim(&locOut, &reasonOut, clamp, data, dims, 0)
    parseCoordRangeOptionOnOneDim(&locOut, &reasonOut, clamp, data, dims, 1)
}

// PORT-NOTE: upstream passes the inner one-dim array `locOut[dimIdx]` (a reference) and mutates it in
//   place. `MatrixXYLocatorRange` is `[[Double]]` (value type), so we pass the whole range `inout` +
//   `dimIdx` and write through `locRange[dimIdx][k]`. Same logic; only the inner-array aliasing is dropped.
private func parseCoordRangeOptionOnOneDim(
    _ locRange: inout MatrixXYLocatorRange,   // upstream `locDimOut` == locRange[dimIdx]
    _ reasonOut: inout [String]?,
    _ clamp: Int,
    _ data: [Any?],
    _ dims: MatrixDimPair,
    _ dimIdx: Int
) {
    locRange[dimIdx][0] = Double.infinity
    locRange[dimIdx][1] = -Double.infinity

    let dataOnDim: Any? = dimIdx < data.count ? data[dimIdx] : nil
    // const coordValArr = isArray(dataOnDim) ? dataOnDim : [dataOnDim];
    let coordValArr: [Any?] = util.isArray(dataOnDim) ? anyArrayToOptionals(dataOnDim) : [dataOnDim]
    let len = coordValArr.count
    let hasClamp = clamp != 0   // !!clamp

    if len >= 1 {
        parseCoordRangeOptionOnOneDimOnePart(
            &locRange, &reasonOut, coordValArr, hasClamp, dims, dimIdx, 0
        )
        if len > 1 {
            // Users may intuitively input the coords like `[[x1, x2, x3], ...]`;
            // consider the range as `[x1, x3]` in this case.
            parseCoordRangeOptionOnOneDimOnePart(
                &locRange, &reasonOut, coordValArr, hasClamp, dims, dimIdx, len - 1
            )
        }
    }
    else {
        if __DEV__ {
            if reasonOut != nil {
                reasonOut!.append("Should be like [[\"x1\", \"x2\"], [\"y1\", \"y2\"]], or [\"x1\", \"y1\"], rather than empty.")
            }
        }
        locRange[dimIdx][0] = Double.nan
        locRange[dimIdx][1] = Double.nan
    }

    if hasClamp {
        // null/undefined/NaN or illegal data represents the entire row/column;
        // Cover the entire locator regardless of body or corner, and confine it later.
        var locLowerBound = -Double(dimOf(dims, 1 - dimIdx).getLocatorCount(dimIdx))
        var locUpperBound = Double(dimOf(dims, dimIdx).getLocatorCount(dimIdx)) - 1

        if clamp == MatrixClampOption.body {
            locLowerBound = number.mathMax(0, locLowerBound)
        }
        else if clamp == MatrixClampOption.corner {
            locUpperBound = number.mathMin(-1, locUpperBound)
        }

        if locUpperBound < locLowerBound { // Also considered that both x and y has no cell.
            locLowerBound = Double.nan
            locUpperBound = Double.nan
        }

        if locRange[dimIdx][0].isNaN {
            locRange[dimIdx][0] = locLowerBound
        }
        if locRange[dimIdx][1].isNaN {
            locRange[dimIdx][1] = locUpperBound
        }
        locRange[dimIdx][0] = number.mathMax(number.mathMin(locRange[dimIdx][0], locUpperBound), locLowerBound)
        locRange[dimIdx][1] = number.mathMax(number.mathMin(locRange[dimIdx][1], locUpperBound), locLowerBound)
    }
}

// The return val must be finite or NaN.
private func parseCoordRangeOptionOnOneDimOnePart(
    _ locRange: inout MatrixXYLocatorRange,   // upstream `locDimOut` == locRange[dimIdx]
    _ reasonOut: inout [String]?,
    _ coordValArr: [Any?],
    _ hasClamp: Bool,
    _ dims: MatrixDimPair,
    _ dimIdx: Int,
    _ partIdx: Int
) {
    let layout = coordDataToAllCellLevelLayout(coordValArr[partIdx], dims, dimIdx)
    guard let layout = layout else {
        if __DEV__ {
            if !hasClamp, reasonOut != nil {
                reasonOut!.append("Can not find cell by coord[\(dimIdx)][\(partIdx)].")
            }
        }
        locRange[dimIdx][0] = Double.nan
        locRange[dimIdx][1] = Double.nan
        return
    }
    let locatorA = pointGetXY(layout.id, dimIdx)
    var locatorB = locatorA
    let dimCell = cellLayoutInfoToDimCell(layout)
    if let dimCell = dimCell { // Handle non-leaf
        locatorB += pointGetXY(dimCell.span, dimIdx) - 1
    }
    locRange[dimIdx][0] = number.mathMin(number.mathMin(locRange[dimIdx][0], locatorA), locatorB)
    locRange[dimIdx][1] = number.mathMax(number.mathMax(locRange[dimIdx][1], locatorA), locatorB)
}

/**
 * @param locatorRange Must be the return of `parseCoordRangeOption`,
 *  where if not NaN, it must be a valid locator.
 */
public func isXYLocatorRangeInvalidOnDim(
    _ locatorRange: MatrixXYLocatorRange, _ dimIdx: Int
) -> Bool {
    return locatorRange[dimIdx][0].isNaN || locatorRange[dimIdx][1].isNaN
}

// A cell-merge definition — upstream inline object literal
// `{ locatorRange: MatrixXYLocatorRange | NullUndefined; cellMergeOwner: boolean; }`.
// Modeled as a class-bound protocol so `MatrixBodyCorner`'s parsed items / cells can conform.
public protocol MatrixCellMergeDef: AnyObject {
    var locatorRange: MatrixXYLocatorRange? { get }
    var cellMergeOwner: Bool { get set }
}

// `inOutLocatorRange` will be expanded (modified) if an intersection is encountered.
public func resolveXYLocatorRangeByCellMerge(
    _ inOutLocatorRange: inout MatrixXYLocatorRange,
    // Item indices coorespond to mergeDefList (len: mergeDefListTravelLen).
    // Indicating whether each item has be merged into the `locatorRange`
    _ outMergedMarkList: inout [Bool]?,
    _ mergeDefList: [MatrixCellMergeDef],
    _ mergeDefListTravelLen: Int
) {
    // outMergedMarkList = outMergedMarkList || _tmpOutMergedMarkList;
    if outMergedMarkList == nil {
        outMergedMarkList = _tmpOutMergedMarkList
    }
    for idx in 0..<mergeDefListTravelLen {
        setBoolAt(&outMergedMarkList!, idx, false)
    }
    // In most case, cell merging definition list length is smaller than the range extent,
    // therefore, to detection intersection, travelling cell merging definition list is probably
    // performant than traveling the four edges of the rect formed by the locator range.
    while true {
        var expanded = false
        for idx in 0..<mergeDefListTravelLen {
            let mergeDef = mergeDefList[idx]
            if outMergedMarkList![idx] == false
                && mergeDef.cellMergeOwner
                && expandXYLocatorRangeIfIntersect(&inOutLocatorRange, mergeDef.locatorRange) {
                outMergedMarkList![idx] = true
                expanded = true
            }
        }
        if !expanded {
            break
        }
    }
}
private var _tmpOutMergedMarkList: [Bool] = []

// JS sparse-array assignment `arr[idx] = v` grows the array; Swift arrays must be grown explicitly.
@inline(__always) private func setBoolAt(_ arr: inout [Bool], _ idx: Int, _ v: Bool) {
    while arr.count <= idx { arr.append(false) }
    arr[idx] = v
}

// Return whether intersect.
// `thisLocRange` will be expanded (modified) if an intersection is encountered.
private func expandXYLocatorRangeIfIntersect(
    _ thisLocRange: inout MatrixXYLocatorRange,
    _ otherLocRange: MatrixXYLocatorRange?
) -> Bool {
    guard let otherLocRange = otherLocRange else {
        return false
    }
    if !locatorRangeIntersectOneDim(thisLocRange[0], otherLocRange[0])
        || !locatorRangeIntersectOneDim(thisLocRange[1], otherLocRange[1]) {
        return false
    }

    thisLocRange[0][0] = number.mathMin(thisLocRange[0][0], otherLocRange[0][0])
    thisLocRange[0][1] = number.mathMax(thisLocRange[0][1], otherLocRange[0][1])
    thisLocRange[1][0] = number.mathMin(thisLocRange[1][0], otherLocRange[1][0])
    thisLocRange[1][1] = number.mathMax(thisLocRange[1][1], otherLocRange[1][1])

    return true
}

// Notice: If containing NaN, not intersect.
private func locatorRangeIntersectOneDim(
    _ locRange1OneDim: [Double],
    _ locRange2OneDim: [Double]
) -> Bool {
    return (
        locRange1OneDim[1] >= locRange2OneDim[0]
        && locRange1OneDim[0] <= locRange2OneDim[1]
    )
}

// upstream: `owner: {id: Point; span: Point;}`. Modeled as a class-bound protocol.
public protocol MatrixIdSpanHolder: AnyObject {
    var id: Point { get }
    var span: Point { get }
}

public func fillIdSpanFromLocatorRange(
    _ owner: MatrixIdSpanHolder,
    _ locatorRange: MatrixXYLocatorRange
) {
    owner.id.set(locatorRange[0][0], locatorRange[1][0])
    owner.span.set(locatorRange[0][1] - owner.id.x + 1, locatorRange[1][1] - owner.id.y + 1)
}

public func cloneXYLocatorRange(
    _ target: inout MatrixXYLocatorRange,
    _ source: MatrixXYLocatorRange
) {
    target[0][0] = source[0][0]
    target[0][1] = source[0][1]
    target[1][0] = source[1][0]
    target[1][1] = source[1][1]
}

/**
 * If illegal, the corresponding x/y/width/height is set to `NaN`.
 * `x/width` or `y/height` is supported to be calculated separately,
 * i.e., one side are NaN, the other side are normal.
 * @param oneDimOut only write to `x/width` or `y/height`, depending on `dimIdx`.
 */
public func xyLocatorRangeToRectOneDim(
    _ oneDimOut: RectLike,
    _ locRange: MatrixXYLocatorRange,
    _ dims: MatrixDimPair,
    _ dimIdx: Int
) {
    let layoutMin = coordDataToAllCellLevelLayout(locRange[dimIdx][0], dims, dimIdx)
    let layoutMax = coordDataToAllCellLevelLayout(locRange[dimIdx][1], dims, dimIdx)

    rectSetXY(oneDimOut, dimIdx, Double.nan)
    rectSetWH(oneDimOut, dimIdx, Double.nan)

    if let layoutMin = layoutMin, let layoutMax = layoutMax {
        rectSetXY(oneDimOut, dimIdx, layoutMin.xy)
        rectSetWH(oneDimOut, dimIdx, layoutMax.xy + layoutMax.wh - layoutMin.xy)
    }
}

// No need currently, since `span` is not allowed to be defined directly by users.
// (upstream `parseSpanOption` is commented out — omitted here to match.)

/**
 * @usage To get/set on dimension, use:
 *  `xyVal[XY[dim]] = val;` // set on this dimension.
 *  `xyVal[XY[1 - dim]] = val;` // set on the perpendicular dimension.
 */
@discardableResult
public func setDimXYValue(
    _ out: Point,
    _ dimIdx: Int,             // 0 | 1
    _ valueOnThisDim: Double,  // MatrixXYLocator
    _ valueOnOtherDim: Double  // MatrixXYLocator
) -> Point {
    pointSetXY(out, dimIdx, valueOnThisDim)
    pointSetXY(out, 1 - dimIdx, valueOnOtherDim)
    return out
}

/**
 * Return NullUndefined if not dimension cell.
 */
private func cellLayoutInfoToDimCell(
    _ cellLayoutInfo: MatrixCellLayoutInfo?
) -> MatrixDimensionCell? {
    guard let cellLayoutInfo = cellLayoutInfo,
          cellLayoutInfo.type == MatrixCellLayoutInfoType.leaf.rawValue
            || cellLayoutInfo.type == MatrixCellLayoutInfoType.nonLeaf.rawValue else {
        return nil
    }
    return cellLayoutInfo as? MatrixDimensionCell
}

public func createNaNRectLike() -> RectLike {
    // upstream: {x: NaN, y: NaN, width: NaN, height: NaN}.
    // BoundingRect.set leaves NaN untouched (its `width < 0` / `height < 0` normalization is false for NaN).
    return BoundingRect(Double.nan, Double.nan, Double.nan, Double.nan)
}

// JS `isArray(x) ? x : [x]` — narrow a heterogeneous array (e.g. `[Any]` / `[Any?]`) into `[Any?]`.
private func anyArrayToOptionals(_ v: Any?) -> [Any?] {
    if let arr = v as? [Any?] { return arr }
    if let arr = v as? [Any] { return arr.map { $0 as Any? } }
    return [v]
}
