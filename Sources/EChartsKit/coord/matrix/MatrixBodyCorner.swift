// Ported from echarts/src/coord/matrix/MatrixBodyCorner.ts — keep in sync with upstream
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

// import { HashMap, createHashMap, each, extend, isArray, isObject } from 'zrender/src/core/util';
//   -> HashMap / createHashMap (util/modelUtil.swift shim); each/extend/isArray/isObject (util.*)
// import type { NullUndefined } from '../../util/types';                   -> modeled as Swift Optional
// import type { MatrixXYLocator, MatrixDimPair, MatrixXYLocatorRange } from './MatrixDim';
//   -> MatrixDim.swift (sibling; see PORT-NOTE in matrixCoordHelper.swift for the referenced shapes)
// import { error } from '../../util/log';                                  -> log.error
// import Point from 'zrender/src/core/Point';                             -> Point (ZRenderKit)
// import { RectLike } from 'zrender/src/core/BoundingRect';               -> RectLike (ZRenderKit)
// import type { MatrixBodyCornerCellOption, MatrixBodyOption, MatrixCornerOption } from './MatrixModel';
//   -> dynamic option bags ([String: Any])
// import { resolveXYLocatorRangeByCellMerge, MatrixClampOption, parseCoordRangeOption,
//   fillIdSpanFromLocatorRange, createNaNRectLike, isXYLocatorRangeInvalidOnDim,
//   resetXYLocatorRange, cloneXYLocatorRange } from './matrixCoordHelper';  -> SIBLING (matrixCoordHelper.swift)
// import type Model from '../../model/Model';                             -> Model (model/Model.swift; dynamic [String: Any] bag)
//
// PORT-NOTE: `MatrixDim` (and `MatrixDimPair`, `MatrixXYLocator`, `MatrixXYLocatorRange`) are ported by a
//   sibling agent in this same phase; this file references them forward and does not compile standalone.

/**
 * Key: @see `makeCellMapKey`
 */
// upstream: type MatrixModelBodyCornerCellMap = HashMap<MatrixBodyCornerCell, string>;
typealias MatrixModelBodyCornerCellMap = HashMap<MatrixBodyCornerCell>

// upstream: export type MatrixBodyOrCornerKind = 'body' | 'corner';
//   The TS phantom generic `MatrixBodyCorner<TKind>` only selects the option type; since the port's
//   `Model` is a dynamic `[String: Any]` bag, the generic is collapsed to a stored `_kind: String`.
public typealias MatrixBodyOrCornerKind = String

public final class MatrixBodyCornerCell: MatrixCellMergeDef {
    // Represents col/row, serves as both id and locator.
    // Actually its `x` is `xDimCell.id.x`; its `y` is `yDimCell.id.y`
    public var id: Point
    // raw option in `matrix.body/corner.data[i]`.
    public var option: [String: Any]?     // MatrixBodyCornerCellOption | NullUndefined
    // `matrix.body/corner.data[i].coord` can locate a rect of cells (say, area).
    // `inSpanOf` refers to the top-left cell, which represents that area.
    // The top-left cell has `inSpanOf` refering to itself.
    public var inSpanOf: MatrixBodyCornerCell?
    // If existing, it indicates cell merging, and this cell is the top-left cell
    // of the merging area.
    public var cellMergeOwner: Bool
    // Exist only if `cellMergeOwner: true`.
    // In this case, it enusres that x > 1 and y > 1 and never out of boundary;
    // othewise it is null/undefined.
    public var span: Point?
    // Exist only if `cellMergeOwner: true`.
    // Convey the same info with `id`+`span`, but be used in different calculation.
    public var locatorRange: MatrixXYLocatorRange?
    // Exist only if `cellMergeOwner: true`.
    public var spanRect: RectLike?

    init(id: Point) {
        self.id = id
        self.option = nil
        self.inSpanOf = nil
        self.cellMergeOwner = false
        self.span = nil
        self.locatorRange = nil
        self.spanRect = nil
    }
}

/**
 * Lifetime: the same with `MatrixModel`, but different from `coord/Matrix`.
 */
public final class MatrixBodyCorner {

    /**
     * Be sparse, item exists only if needed.
     */
    private var _cellMap: MatrixModelBodyCornerCellMap?
    private var _cellMergeOwnerList: [MatrixBodyCornerCell]

    private var _model: Model
    private var _dims: MatrixDimPair
    private var _kind: MatrixBodyOrCornerKind

    public init(
        _ kind: MatrixBodyOrCornerKind,
        _ bodyOrCornerModel: Model,
        _ dims: MatrixDimPair
    ) {
        self._model = bodyOrCornerModel
        self._dims = dims
        self._kind = kind
        self._cellMergeOwnerList = []
    }

    /**
     * Can not be called before series models initialization finished, since the ordinalMeta may
     * use collect the values from `series.data` in series initialization.
     */
    private func _ensureCellMap() -> MatrixModelBodyCornerCellMap {
        if let existing = self._cellMap {
            return existing
        }
        let cellMap: MatrixModelBodyCornerCellMap = createHashMap()
        self._cellMap = cellMap

        // function ensureBodyOrCornerCell(x, y): MatrixBodyCornerCell
        func ensureBodyOrCornerCell(_ x: Double, _ y: Double) -> MatrixBodyCornerCell {
            let key = makeCellMapKey(x, y)
            if let cell = cellMap.get(key) {
                return cell
            }
            let cell = MatrixBodyCornerCell(id: Point(x, y))
            cellMap.set(key, cell)
            return cell
        }

        // ---- fillCellMap ----
        var parsedList: [MatrixBodyCornerParsed] = []

        // let cellOptionList = self._model.getShallow('data');
        var cellOptionList: [Any?]? = nil
        let rawData = self._model.getShallow("data")
        if let arr = rawData as? [Any?] {
            cellOptionList = arr
        }
        else if let arr = rawData as? [Any] {
            cellOptionList = arr.map { $0 as Any? }
        }
        else if rawData != nil {
            // if (cellOptionList && !isArray(cellOptionList)) { error; cellOptionList = null; }
            if __DEV__ {
                log.error("matrix.\(String(describing: rawData)).data must be an array if specified.")
            }
            cellOptionList = nil
        }

        util.each(cellOptionList) { option, idx in
            // if (!isObject(option) || !isArray(option.coord)) { error; return; }
            guard let optDict = option as? [String: Any], util.isArray(optDict["coord"]) else {
                if __DEV__ {
                    log.error("Illegal matrix.\(self._kind).data[\(idx)], must be a {coord: [...], ...}")
                }
                return
            }

            var locatorRange = resetXYLocatorRange(nil)
            var reasonArr: [String]? = __DEV__ ? [] : nil
            parseCoordRangeOption(
                &locatorRange, &reasonArr, coordToOptionals(optDict["coord"]), self._dims,
                jsTruthy(optDict["coordClamp"]) ? MatrixClampOption.byKind(self._kind) : MatrixClampOption.none
            )
            if isXYLocatorRangeInvalidOnDim(locatorRange, 0) || isXYLocatorRangeInvalidOnDim(locatorRange, 1) {
                if __DEV__ {
                    log.error("Can not determine cells by option matrix.\(self._kind).data[\(idx)]: "
                        + "\((reasonArr ?? []).joined(separator: " "))")
                }
                return
            }

            let cellMergeOwner = jsTruthy(optDict["mergeCells"])
            let parsed = MatrixBodyCornerParsed(
                id: Point(), span: Point(), locatorRange: locatorRange,
                option: optDict, cellMergeOwner: cellMergeOwner
            )
            fillIdSpanFromLocatorRange(parsed, locatorRange)

            // The order of the `parsedList` determines the precedence of the styles, if there
            // are overlaps between ranges specified in different items. Preserve the original
            // order of `matrix.body/corner/data` to make it predictable for users.
            parsedList.append(parsed)
        }

        // Resolve cell merging intersection - union to a larger rect.
        var mergedMarkList: [Bool]? = []
        var parsedIdx = 0
        while parsedIdx < parsedList.count {
            let parsed = parsedList[parsedIdx]
            if !parsed.cellMergeOwner {
                parsedIdx += 1
                continue
            }
            // `MatrixXYLocatorRange` is a value type `[[Double]]`; operate on a local `var` and write the
            // mutated range back into `parsed` (upstream aliases `parsed.locatorRange` by reference).
            var locatorRange = parsed.locatorRange!
            resolveXYLocatorRangeByCellMerge(
                &locatorRange, &mergedMarkList,
                parsedList.map { $0 as MatrixCellMergeDef }, parsedIdx
            )
            parsed.locatorRange = locatorRange
            for idx in 0..<parsedIdx {
                if mergedMarkList![idx] {
                    parsedList[idx].cellMergeOwner = false
                }
            }
            if locatorRange[0][0] != parsed.id.x || locatorRange[1][0] != parsed.id.y {
                // The top-left cell of the unioned locatorRange is not this cell any more.
                parsed.cellMergeOwner = false
                // Reconcile: simply use the last style and value option if multiple styles involved
                // in a merged area, since there might be no commonly used merge strategy.
                var newOption = parsed.option   // extend({}, parsed.option)
                newOption.removeValue(forKey: "coord")  // newOption.coord = null
                let newParsed = MatrixBodyCornerParsed(
                    id: Point(), span: Point(), locatorRange: locatorRange,
                    option: newOption, cellMergeOwner: true
                )
                fillIdSpanFromLocatorRange(newParsed, locatorRange)
                parsedList.append(newParsed)
            }
            parsedIdx += 1
        }

        // Assign options to cells.
        util.each(parsedList) { parsed, _ in
            let topLeftCell = ensureBodyOrCornerCell(parsed.id.x, parsed.id.y)
            if parsed.cellMergeOwner {
                topLeftCell.cellMergeOwner = true
                topLeftCell.span = parsed.span
                topLeftCell.locatorRange = parsed.locatorRange
                topLeftCell.spanRect = createNaNRectLike()
                self._cellMergeOwnerList.append(topLeftCell)
            }
            // upstream: if (!parsed.cellMergeOwner && !parsed.option) { return; }
            //   `parsed.option` is always a non-null object here (truthy even when empty {}), so this
            //   early-return is unreachable for a parsed item — omitted.
            let spanY = Int(parsed.span.y)
            let spanX = Int(parsed.span.x)
            var yidx = 0
            while yidx < spanY {
                var xidx = 0
                while xidx < spanX {
                    let cell = ensureBodyOrCornerCell(parsed.id.x + Double(xidx), parsed.id.y + Double(yidx))
                    // If multiple style options are defined on a cell, the later ones takes precedence.
                    cell.option = parsed.option
                    if parsed.cellMergeOwner {
                        cell.inSpanOf = topLeftCell
                    }
                    xidx += 1
                }
                yidx += 1
            }
        }
        // ---- End of fillCellMap ----

        return cellMap
    }

    /**
     * Body cells or corner cell are not commonly defined specifically, especially in a large
     * table, thus his is a sparse data structure - bodys or corner cells exist only if there
     * are options specified to it (in `matrix.body.data` or `matrix.corner.data`);
     * otherwise, return `NullUndefined`.
     */
    public func getCell(_ xy: [Double]) -> MatrixBodyCornerCell? {
        // Assert xy do not contain NaN
        return self._ensureCellMap().get(makeCellMapKey(xy[0], xy[1]))
    }

    /**
     * Only cell existing (has specific definition or props) will be travelled.
     */
    public func travelExistingCells(_ cb: (MatrixBodyCornerCell) -> Void) {
        self._ensureCellMap().each { cell, _ in cb(cell) }
    }

    /**
     * @param locatorRange Must be the return of `parseCoordRangeOption`.
     */
    // `MatrixXYLocatorRange` is a value type; taken `inout` since upstream mutates the passed range in place.
    public func expandRangeByCellMerge(_ locatorRange: inout MatrixXYLocatorRange) {
        if !isXYLocatorRangeInvalidOnDim(locatorRange, 0)
            && !isXYLocatorRangeInvalidOnDim(locatorRange, 1)
            && locatorRange[0][0] == locatorRange[0][1]
            && locatorRange[1][0] == locatorRange[1][1] {
            // If it locates to a single cell, use this quick path to avoid travelling.
            // It is based on the fact that any cell is not contained by more than one cell merging rect.
            let cell = self.getCell([locatorRange[0][0], locatorRange[1][0]])
            let inSpanOf = cell?.inSpanOf
            if let inSpanOf = inSpanOf, let inSpanRange = inSpanOf.locatorRange {
                cloneXYLocatorRange(&locatorRange, inSpanRange)
                return
            }
        }

        let list = self._cellMergeOwnerList
        var noMark: [Bool]? = nil
        resolveXYLocatorRangeByCellMerge(
            &locatorRange, &noMark,
            list.map { $0 as MatrixCellMergeDef }, list.count
        )
    }

}

// upstream inner `TmpParsed` object literal in `fillCellMap` — a class so it can be shared by reference
// across `parsedList` (mutating `cellMergeOwner`) and conform to the helper protocols.
private final class MatrixBodyCornerParsed: MatrixCellMergeDef, MatrixIdSpanHolder {
    let id: Point
    let span: Point
    // Always assigned; optional only to satisfy `MatrixCellMergeDef.locatorRange` (cells hold it optional).
    var locatorRange: MatrixXYLocatorRange?
    var option: [String: Any]
    var cellMergeOwner: Bool

    init(id: Point, span: Point, locatorRange: MatrixXYLocatorRange, option: [String: Any], cellMergeOwner: Bool) {
        self.id = id
        self.span = span
        self.locatorRange = locatorRange
        self.option = option
        self.cellMergeOwner = cellMergeOwner
    }
}

// The upstream `_tmpERBCMLocator` reusable buffer is inlined at the call site as a fresh 2-element array.

// upstream: function makeCellMapKey(x, y) { return `${x}|${y}`; }
private func makeCellMapKey(_ x: Double, _ y: Double) -> String {
    return "\(matrixNumStr(x))|\(matrixNumStr(y))"
}

// JS template-literal number stringify (`${x}`): integer-valued doubles print without a decimal point
// (`1` not `1.0`), matching how the JS `HashMap` keys are formed. Mirrors modelUtil's private jsNumberStr.
private func matrixNumStr(_ x: Double) -> String {
    if x.isNaN { return "NaN" }
    if x.isInfinite { return x > 0 ? "Infinity" : "-Infinity" }
    if x == x.rounded() && Swift.abs(x) < 1e21 {
        return String(Int64(x))
    }
    return String(x)
}

// JS `option.coord` (MatrixCoordRangeOption[]) -> `[Any?]` for parseCoordRangeOption.
private func coordToOptionals(_ v: Any?) -> [Any?] {
    if let arr = v as? [Any?] { return arr }
    if let arr = v as? [Any] { return arr.map { $0 as Any? } }
    return []
}

// Faithful port of JS truthiness (`!!x`): 0, NaN, '', null/undefined, false are falsy.
private func jsTruthy(_ v: Any?) -> Bool {
    switch v {
    case nil: return false
    case let b as Bool: return b
    case let d as Double: return d != 0 && !d.isNaN
    case let i as Int: return i != 0
    case let s as String: return !s.isEmpty
    default: return true
    }
}
