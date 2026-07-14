// Ported from echarts/src/coord/matrix/MatrixDim.ts — keep in sync with upstream
//
// MatrixDim models one axis ('x' = columns, 'y' = rows) of the matrix coordinate
// system as a TREE of header cells. A cell may span/merge its children; the leaves of
// the tree are the layout units (one leaf == one column/row of the body). Leaves are
// packed at the front of `_cells` and their index doubles as the `MatrixXYLocator`
// (== `OrdinalNumber`) used to locate body cells. Off-by-one here mislays every cell,
// so the leaf-indexing / ordinal-sorting logic is ported verbatim.
//
// This file OWNS (upstream declares them in MatrixDim.ts; the sibling matrixCoordHelper.swift /
// MatrixBodyCorner.swift / MatrixModel.swift / MatrixView.swift reference them as forward types):
//   typealias MatrixXYLocator, class MatrixXYLocatorRange, protocol MatrixCellLayoutInfo,
//   class MatrixDimensionCell, class MatrixDimensionLevelInfo, struct MatrixDimPair, class MatrixDim.
//
// It USES (defined by sibling matrixCoordHelper.swift — do NOT redeclare):
//   MatrixCellLayoutInfoType (Int constants .level/.leaf/.nonLeaf), setDimXYValue, createNaNRectLike.
// And by sibling MatrixModel.swift: MatrixDimensionModel.
//
// upstream imports:
//   import { createHashMap, defaults, each, eqNaN, isArray, isObject, isString }
//                                                    from 'zrender/src/core/util'; -> `util.*` (ZRenderKit)
//     - createHashMap<true, string> (a string set) -> Swift `Set<String>`.
//   import Point from 'zrender/src/core/Point';       -> Point (ZRenderKit)
//   import OrdinalMeta from '../../data/OrdinalMeta';  -> OrdinalMeta
//   import { NullUndefined, OrdinalNumber } from '../../util/types'; -> Optional / OrdinalNumber (Double)
//   import Ordinal from '../../scale/Ordinal';         -> OrdinalScale / OrdinalScaleSetting
//   import { ..., MatrixCoordValueOption } from './MatrixModel'; -> dynamic value, modeled as `Any?`
//   import { WH, XY } from '../../util/graphic';       -> dimension-indexed setters (0=x/width, 1=y/height)
//   import { ListIterator } from '../../util/model';   -> ListIterator (util/modelUtil.swift)
//   import { RectLike } from 'zrender/src/core/BoundingRect'; -> RectLike (ZRenderKit)
//   import { createNaNRectLike, setDimXYValue, MatrixCellLayoutInfoType } from './matrixCoordHelper';
//   import { error } from '../../util/log';            -> log.error
//   import { mathMax } from '../../util/number';       -> Swift.max (Int/Double)

import Foundation
import ZRenderKit

// upstream: export type MatrixXYLocator = MatrixCellLayoutInfo['id']['x' | 'y'];
// A locator is an integer stored in a Point component (Double); >= 0 locates body cells,
// negative locates corner/level cells.
public typealias MatrixXYLocator = Double

/**
 * upstream: type MatrixXYLocatorRange = MatrixXYLocator[][] & {__brand: 'MatrixXYLocatorRange'};
 *   [[xmin, xmax], [ymin, ymax]]. Modeled as a VALUE type `[[MatrixXYLocator]]` (== `[[Double]]`), matching
 *   the sibling matrixCoordHelper / MatrixBodyCorner / Matrix code, which mutate it via `inout` + subscript
 *   (`rg[dim][0/1]`). Fresh 2x2-NaN instances come from `resetXYLocatorRange(nil)` (matrixCoordHelper).
 *   The nominal `__brand` is dropped (not expressible / not needed).
 */
public typealias MatrixXYLocatorRange = [[MatrixXYLocator]]

/**
 * upstream: interface MatrixCellLayoutInfo { type; id; xy; wh; dim; }
 * Class-bound protocol: `getUnitLayoutInfo` / `resetLayoutIterator` yield either a
 * `MatrixDimensionCell` or a `MatrixDimensionLevelInfo` through this existential, and
 * matrixCoordHelper downcasts it (`as? MatrixDimensionCell`).
 */
public protocol MatrixCellLayoutInfo: AnyObject {
    // One of MatrixCellLayoutInfoType.{level, leaf, nonLeaf} (Int; see matrixCoordHelper).
    var type: Int { get }
    // Represents col/row, serves as both id and locator. If negative, corner; otherwise body.
    var id: Point { get }
    // By pixel. Computed left-top x (x dim) or y (y dim). Used to locate.
    var xy: Double { get set }
    // By pixel. Computed height (x dim) or width (y dim). Used to locate.
    var wh: Double { get set }
    // Back-reference to the owning dim.
    var dim: MatrixDim { get }
}

/**
 * upstream: interface MatrixDimensionCell extends MatrixCellLayoutInfo { ... }
 */
public final class MatrixDimensionCell: MatrixCellLayoutInfo {
    public var type: Int
    public let id: Point
    public var xy: Double
    public var wh: Double
    // `unowned`: MatrixDim strongly owns `_cells`; the cell co-dies with the dim. Breaks the cycle.
    public unowned let dim: MatrixDim
    // Computed col/row span. Always exists and >= 1.
    // `span[XY[dimIdx]]` is actually the leaves count of this subtree.
    public var span: Point
    // Start from 0, tree depth. (An array index into `_levels` -> Int.)
    public var level: Int
    // It is both `MatrixXYLocator` and `OrdinalNumber` and `_cells[index]`.
    public var firstLeafLocator: MatrixXYLocator
    // Fetch raw value by `getOrdinalMeta().categories[ordinal]`, or the cell by `_cells[ordinal]`.
    // Same as `id.getOnDim(0)` for leaves only.
    public var ordinal: OrdinalNumber
    // Normalized raw option of `matrix.x/y.data[i]`, no parent option. Never nil (a `{value: null}`
    // cell is an empty bag; a missing "value" key reads as null).
    public var option: [String: Any]
    // The layout rect for rendering. Available after matrix coordinate system resizing.
    public var rect: RectLike

    init(
        type: Int,
        ordinal: OrdinalNumber,
        level: Int,
        firstLeafLocator: MatrixXYLocator,
        id: Point,
        span: Point,
        option: [String: Any],
        xy: Double,
        wh: Double,
        dim: MatrixDim,
        rect: RectLike
    ) {
        self.type = type
        self.ordinal = ordinal
        self.level = level
        self.firstLeafLocator = firstLeafLocator
        self.id = id
        self.span = span
        self.option = option
        self.xy = xy
        self.wh = wh
        self.dim = dim
        self.rect = rect
    }
}

/**
 * upstream: interface MatrixDimensionLevelInfo extends MatrixCellLayoutInfo { option; }
 * Computed properties of a certain tree level (level size / corner-cell locating).
 */
public final class MatrixDimensionLevelInfo: MatrixCellLayoutInfo {
    public var type: Int
    public let id: Point
    public var xy: Double
    public var wh: Double
    public unowned let dim: MatrixDim
    // The raw option of `matrix.levels[i]` (or nil).
    public var option: [String: Any]?

    init(
        type: Int,
        xy: Double,
        wh: Double,
        option: [String: Any]?,
        id: Point,
        dim: MatrixDim
    ) {
        self.type = type
        self.xy = xy
        self.wh = wh
        self.option = option
        self.id = id
        self.dim = dim
    }
}

/**
 * upstream: type MatrixDimPair = { x: MatrixDim; y: MatrixDim; };
 */
public struct MatrixDimPair {
    public var x: MatrixDim
    public var y: MatrixDim
    public init(x: MatrixDim, y: MatrixDim) {
        self.x = x
        self.y = y
    }
}

/**
 * Lifetime: the same as `MatrixModel`, but different from `coord/Matrix`.
 */
public final class MatrixDim {
    // Use it to visit `cell.id` and `cell.span`.
    public let dim: String            // 'x' | 'y'
    // Must be `0 | 1`, corresponding to 'x' | 'y'.
    public let dimIdx: Int

    // Under the current definition, every leaf corresponds to a unit cell, and leaves can serve
    // as the locator of cells. Therefore:
    //  - The first `_leavesCount` elements in `_cells` are leaves.
    //  - `_cells[leaf.id[XY[this.dimIdx]]]` is the leaf itself.
    //  - Leaves of each subtree are placed together.
    private var _cells: [MatrixDimensionCell] = []

    // Can be visited by `_levels[cell.level]` or `_levels[cell.id[1 - dimIdx] + _levels.length]`.
    private var _levels: [MatrixDimensionLevelInfo] = []

    // upstream: number. It is a count (array size) -> Int.
    private var _leavesCount: Int = 0

    private let _model: MatrixDimensionModel   // sibling MatrixModel.swift
    private var _ordinalMeta: OrdinalMeta!
    // Only for uniformly parsing.
    private var _scale: OrdinalScale!

    private let _uniqueValueGen: MatrixDimUniqueValueGenerator

    public init(_ dim: String, _ dimModel: MatrixDimensionModel) {
        self.dim = dim
        self.dimIdx = dim == "x" ? 0 : 1
        self._model = dimModel

        self._uniqueValueGen = createUniqueValueGenerator(dim)

        var dimModelData: Any? = dimModel.get("data", true)
        let length: Any? = dimModel.get("length", true)
        if !matrixDimIsNullish(dimModelData) && !util.isArray(dimModelData) {
            if __DEV__ {
                log.error("Illegal echarts option - matrix.\(self.dim).data must be an array if specified.")
            }
            dimModelData = [Any?]()
        }
        if let data = matrixDimLooseArray(dimModelData) {
            // JS `if (dimModelData)`: a (possibly empty) array is truthy; null/undefined is falsy.
            self._initByDimModelData(data)
        }
        else if !matrixDimIsNullish(length), let n = matrixDimAsNumber(length) {
            let len = n.isNaN ? 0 : Int(n)
            var generated = [Any?](repeating: nil, count: max(0, len))
            for i in 0..<generated.count {
                generated[i] = nil
            }
            self._initByDimModelData(generated)
        }
        else {
            self._initBySeriesData()
        }
    }

    private func _initByDimModelData(_ dimModelData: [Any?]) {
        // Save for sorting: `sameLocatorCellsLists[firstLeafLocator]` holds every cell (leaf and
        // non-leaf) whose subtree starts at that locator, deepest last (push order).
        var sameLocatorCellsLists: [[MatrixDimensionCell]] = []
        var _cellCount = 0

        // upstream nested `traverseInitCells` (recursive). Returns `totalSpan` (leaf count of the
        // passed sibling list). Captures & mutates `sameLocatorCellsLists`, `_cellCount`, `self`.
        func traverseInitCells(
            _ dimModelData: [Any?]?,
            _ firstLeafLocatorArg: MatrixXYLocator,
            _ level: Int
        ) -> Double {
            var totalSpan = 0.0
            guard let dimModelData = dimModelData else {
                return totalSpan
            }
            var firstLeafLocator = firstLeafLocatorArg

            util.each(dimModelData) { option, optionIdx in
                var invalidOption = false
                var cellOption: [String: Any]
                if util.isString(option) {
                    cellOption = ["value": option!]
                }
                else if util.isObject(option) {
                    if let dict = option as? [String: Any] {
                        cellOption = dict
                        let v = dict["value"]
                        if !matrixDimIsNullish(v) && !util.isString(v) {
                            invalidOption = true
                            cellOption = [:]   // {value: null}
                        }
                    }
                    else {
                        // Non-dictionary object (e.g. an array) -> treat as {value: null}.
                        cellOption = [:]
                    }
                }
                else {
                    cellOption = [:]   // {value: null}
                    if option != nil && !(option is NSNull) {
                        invalidOption = true
                    }
                }

                if invalidOption {
                    if __DEV__ {
                        log.error("Illegal echarts option - matrix.\(self.dim).data[\(optionIdx)]"
                            + " must be `string | {value: string}`.")
                    }
                }

                let cell = MatrixDimensionCell(
                    type: MatrixCellLayoutInfoType.nonLeaf.rawValue,  // Update to leaf later if it's a leaf.
                    ordinal: Double.nan,                     // Set it later.
                    level: level,
                    firstLeafLocator: firstLeafLocator,
                    id: Point(),                             // Set it in `_initCellsId`.
                    span: setDimXYValue(Point(), self.dimIdx, 1, 1),
                    option: cellOption,
                    xy: Double.nan,
                    wh: Double.nan,
                    dim: self,
                    rect: createNaNRectLike()
                )
                _cellCount += 1
                let flIdx = Int(firstLeafLocator)
                while sameLocatorCellsLists.count <= flIdx {
                    sameLocatorCellsLists.append([])
                }
                sameLocatorCellsLists[flIdx].append(cell)

                if level >= self._levels.count {
                    // Create a level only if at least one cell exists (created densely, in order).
                    while self._levels.count <= level {
                        self._levels.append(MatrixDimensionLevelInfo(
                            type: MatrixCellLayoutInfoType.level.rawValue,
                            xy: Double.nan, wh: Double.nan, option: nil, id: Point(), dim: self
                        ))
                    }
                }

                let childrenSpan = traverseInitCells(
                    matrixDimLooseArray(cellOption["children"]), firstLeafLocator, level + 1
                )
                let subSpan = Swift.max(1.0, childrenSpan)
                matrixDimSetPointOnDim(cell.span, self.dimIdx, subSpan)

                totalSpan += subSpan
                firstLeafLocator += subSpan
            }

            return totalSpan
        }

        self._leavesCount = Int(traverseInitCells(dimModelData, 0, 0))

        // postInitCells: sort so leaves are at the beginning (usable as body-cell locators).
        var categories: [String?] = []
        while self._cells.count < _cellCount {
            for locator in 0..<sameLocatorCellsLists.count {
                if let cell = sameLocatorCellsLists[locator].popLast() {
                    cell.ordinal = Double(categories.count)
                    let val = cell.option["value"] as? String
                    categories.append(val)
                    self._cells.append(cell)
                    self._uniqueValueGen.calcDupBase(val)
                }
            }
        }
        self._uniqueValueGen.ensureValueUnique(&categories, self._cells)

        // After `ensureValueUnique`, every category is a non-nil unique string.
        let ordinalCategories: [OrdinalRawValue] = categories.map { $0! as OrdinalRawValue }
        let ordinalMeta = OrdinalMeta(
            categories: ordinalCategories,
            needCollect: false,
            deduplication: false
        )
        self._ordinalMeta = ordinalMeta
        self._scale = OrdinalScale(OrdinalScaleSetting(ordinalMeta: ordinalMeta))

        for idx in 0..<self._leavesCount {
            let leaf = self._cells[idx]
            leaf.type = MatrixCellLayoutInfoType.leaf.rawValue
            // Handle the tree level variation: enlarge the span of the leaves to reach the body cells.
            matrixDimSetPointOnDim(leaf.span, 1 - self.dimIdx, Double(self._levels.count - leaf.level))
        }

        self._initCellsId()
        self._initLevelIdOptions()
    }

    private func _initBySeriesData() {
        self._leavesCount = 0
        self._levels = [MatrixDimensionLevelInfo(
            type: MatrixCellLayoutInfoType.level.rawValue,
            xy: Double.nan, wh: Double.nan, option: nil, id: Point(), dim: self
        )]
        self._initLevelIdOptions()

        let ordinalMeta = OrdinalMeta(
            needCollect: true,
            deduplication: true,
            // `onCollect` fires in ascending `ordinalNumber` order (0, 1, 2, ...), so a plain
            // append preserves `_cells[ordinalNumber] === cell`.
            // `[unowned self]`: OrdinalMeta co-dies with this dim (dim owns the meta), so the
            // back-reference is safe and breaks the retain cycle.
            onCollect: { [unowned self] value, ordinalNumber in
                let cell = MatrixDimensionCell(
                    type: MatrixCellLayoutInfoType.leaf.rawValue,
                    ordinal: ordinalNumber,
                    level: 0,
                    firstLeafLocator: ordinalNumber,
                    id: Point(),   // Set it in `_setCellId`.
                    span: setDimXYValue(Point(), self.dimIdx, 1, 1),
                    // `value` may be any type (from dataset / series.data); convert to string for display.
                    option: ["value": "\(value)"],
                    xy: Double.nan,
                    wh: Double.nan,
                    dim: self,
                    rect: createNaNRectLike()
                )
                // upstream: self._cells[ordinalNumber] = cell;
                self._cells.append(cell)
                self._leavesCount += 1
                self._setCellId(cell)
            }
        )
        self._ordinalMeta = ordinalMeta
        self._scale = OrdinalScale(OrdinalScaleSetting(ordinalMeta: ordinalMeta))
    }

    private func _setCellId(_ cell: MatrixDimensionCell) {
        let levelsLen = self._levels.count
        let dimIdx = self.dimIdx
        setDimXYValue(cell.id, dimIdx, cell.firstLeafLocator, Double(cell.level - levelsLen))
    }

    private func _initCellsId() {
        let levelsLen = self._levels.count
        let dimIdx = self.dimIdx
        util.each(self._cells) { cell, _ in
            setDimXYValue(cell.id, dimIdx, cell.firstLeafLocator, Double(cell.level - levelsLen))
        }
    }

    private func _initLevelIdOptions() {
        let levelsLen = self._levels.count
        let dimIdx = self.dimIdx
        let levelOptionRaw = self._model.get("levels", true)
        let levelOptionList: [Any?] = util.isArray(levelOptionRaw)
            ? (matrixDimLooseArray(levelOptionRaw) ?? [])
            : []

        util.each(self._levels) { levelCfg, level in
            setDimXYValue(levelCfg.id, dimIdx, 0, Double(level - levelsLen))
            levelCfg.option = (level < levelOptionList.count ? levelOptionList[level] : nil) as? [String: Any]
        }
    }

    public func shouldShow() -> Bool {
        return matrixDimJsTruthy(self._model.getShallow("show", true))
    }

    /**
     * Iterate leaves (they are layout units) if dimIdx === this.dimIdx.
     * Iterate levels if dimIdx !== this.dimIdx.
     */
    @discardableResult
    public func resetLayoutIterator(
        _ it: ListIterator<MatrixCellLayoutInfo>?,
        _ dimIdx: Int,
        _ startLocator: MatrixXYLocator? = nil,
        _ count: Double? = nil
    ) -> ListIterator<MatrixCellLayoutInfo> {
        let it = it ?? ListIterator<MatrixCellLayoutInfo>()
        if dimIdx == self.dimIdx {
            let len = self._leavesCount
            let startIdx = startLocator != nil ? Swift.max(0, Int(startLocator!)) : 0
            let cnt = count != nil ? Swift.min(Int(count!), len) : len
            // Upcast the concrete leaf array to the `any MatrixCellLayoutInfo` existential element type.
            it.reset(self._cells.map { $0 as MatrixCellLayoutInfo }, startIdx, startIdx + cnt)
        }
        else {
            let len = self._levels.count
            // Corner locator is from `-this._levels.length` to `-1`.
            let startIdx = startLocator != nil ? Swift.max(0, Int(startLocator!) + len) : 0
            let cnt = count != nil ? Swift.min(Int(count!), len) : len
            it.reset(self._levels.map { $0 as MatrixCellLayoutInfo }, startIdx, startIdx + cnt)
        }
        return it
    }

    @discardableResult
    public func resetCellIterator(
        _ it: ListIterator<MatrixDimensionCell>? = nil
    ) -> ListIterator<MatrixDimensionCell> {
        return (it ?? ListIterator<MatrixDimensionCell>()).reset(self._cells, 0)
    }

    @discardableResult
    public func resetLevelIterator(
        _ it: ListIterator<MatrixDimensionLevelInfo>? = nil
    ) -> ListIterator<MatrixDimensionLevelInfo> {
        return (it ?? ListIterator<MatrixDimensionLevelInfo>()).reset(self._levels, 0)
    }

    public func getLayout(_ outRect: RectLike, _ dimIdx: Int, _ locator: MatrixXYLocator) {
        let layout = self.getUnitLayoutInfo(dimIdx, locator)
        matrixDimRectSetXY(outRect, dimIdx, layout != nil ? layout!.xy : Double.nan)
        matrixDimRectSetWH(outRect, dimIdx, layout != nil ? layout!.wh : Double.nan)
    }

    /**
     * Get leaf cell or get level info.
     * Should be able to return nil if not found on x or y, thus input `dimIdx` is needed.
     */
    public func getUnitLayoutInfo(_ dimIdx: Int, _ locator: MatrixXYLocator) -> MatrixCellLayoutInfo? {
        if dimIdx == self.dimIdx {
            // upstream: locator < _leavesCount ? _cells[locator] : undefined.
            // JS `_cells[-n]` is undefined; guard the lower bound to avoid an out-of-range trap.
            let i = Int(locator)
            return (i >= 0 && i < self._leavesCount) ? self._cells[i] : nil
        }
        else {
            // upstream: _levels[locator + _levels.length]. Out-of-range -> undefined (nil).
            let i = Int(locator) + self._levels.count
            return (i >= 0 && i < self._levels.count) ? self._levels[i] : nil
        }
    }

    /**
     * Get dimension cell by data, including leaves and non-leaves.
     * `value` is `MatrixCoordValueOption` (OrdinalRawValue | number | MatrixXYLocator) — dynamic (Any?).
     */
    public func getCell(_ value: Any?) -> MatrixDimensionCell? {
        // Route Swift nil through NSNull so OrdinalScale.parse treats it as JS null (-> NaN),
        // rather than a double-wrapped Optional that would defeat the null check.
        let raw: Any = value ?? NSNull()
        let ordinal = self._scale.parse(raw)
        // upstream: `isNaN(ordinal) ? null : this._cells[ordinal]`. `OrdinalScale.parse` passes a
        // numeric coord straight through (`Math.round(val)`), so a value beyond the cell count yields
        // an in-bounds-looking ordinal that JS reads as `undefined` but Swift traps on. Guard the
        // subscript (mirrors `getUnitLayoutInfo`); the caller (`coordDataToAllCellLevelLayout`)
        // already treats a nil cell as "not found in body".
        if util.eqNaN(ordinal) { return nil }
        let i = Int(ordinal)
        return (i >= 0 && i < self._cells.count) ? self._cells[i] : nil
    }

    /**
     * Get leaf count or get level count.
     */
    public func getLocatorCount(_ dimIdx: Int) -> Int {
        return dimIdx == self.dimIdx ? self._leavesCount : self._levels.count
    }

    public func getOrdinalMeta() -> OrdinalMeta {
        return self._ordinalMeta
    }
}

// ============================================================================
// upstream: function createUniqueValueGenerator(dim: 'x' | 'y') { ... }
// A closure factory returning `{ calcDupBase, ensureValueUnique }`. Modeled as a small
// reference type so `dupBase` is shared mutable state.
//
// Duplicated values are allowed (a tree may have leaves with the same text in different
// subtrees); only the first is queryable by text, the rest only by index. `data: [null, null]`
// is allowed too. A default value `X0`, `X1`, ... (or `Y0`, ...) is minted for null/duplicate
// entries; `dupBase` tracks the next free suffix so a minted value never collides with a
// user-supplied `X<number>` value.
// ============================================================================
final class MatrixDimUniqueValueGenerator {
    private let dimUpper: String
    private let defaultValReg: NSRegularExpression
    private var dupBase: Int = 0

    init(_ dim: String) {
        self.dimUpper = dim.uppercased()
        // new RegExp(`^${dimUpper}([0-9]+)$`)
        self.defaultValReg = try! NSRegularExpression(pattern: "^\(self.dimUpper)([0-9]+)$")
    }

    func calcDupBase(_ val: String?) {
        guard let val = val else { return }
        let range = NSRange(val.startIndex..., in: val)
        if let m = defaultValReg.firstMatch(in: val, options: [], range: range),
           let r = Range(m.range(at: 1), in: val),
           let num = Int(val[r]) {
            dupBase = Swift.max(dupBase, num + 1)   // mathMax(dupBase, +matchResult[1] + 1)
        }
    }

    private func makeUniqueValue() -> String {
        let s = "\(dimUpper)\(dupBase)"
        dupBase += 1   // `${dimUpper}${dupBase++}`
        return s
    }

    func ensureValueUnique(_ categories: inout [String?], _ cells: [MatrixDimensionCell]) {
        var cateMap = Set<String>()   // createHashMap<true, string>()
        for idx in 0..<categories.count {
            var value = categories[idx]
            // value may be nil (unset/illegal) or a duplicate.
            if value == nil || cateMap.contains(value!) {
                let uniqueValue = makeUniqueValue()
                categories[idx] = uniqueValue
                value = uniqueValue
                // defaults({value}, cells[idx].option): keep the original option, overriding value.
                var merged: [String: Any] = ["value": uniqueValue]
                util.defaults(&merged, cells[idx].option)
                cells[idx].option = merged
            }
            cateMap.insert(value!)
        }
    }
}

func createUniqueValueGenerator(_ dim: String) -> MatrixDimUniqueValueGenerator {
    return MatrixDimUniqueValueGenerator(dim)
}

// ============================================================================
// File-private helpers.
//   XY = ['x','y'], WH = ['width','height']: Swift has no string-keyed stored-property access,
//   so index Point/RectLike by dimension number (0 => x/width, 1 => y/height). (matrixCoordHelper's
//   own such helpers are private, so MatrixDim keeps its own uniquely-named copies.)
// ============================================================================

private func matrixDimSetPointOnDim(_ p: Point, _ dimIdx: Int, _ v: Double) {
    if dimIdx == 0 { p.x = v } else { p.y = v }
}
private func matrixDimRectSetXY(_ r: RectLike, _ dimIdx: Int, _ v: Double) {
    if dimIdx == 0 { r.x = v } else { r.y = v }
}
private func matrixDimRectSetWH(_ r: RectLike, _ dimIdx: Int, _ v: Double) {
    if dimIdx == 0 { r.width = v } else { r.height = v }
}

// JS `value == null` (null | undefined). Option bags may carry NSNull for an explicit null.
private func matrixDimIsNullish(_ v: Any?) -> Bool {
    return v == nil || v is NSNull
}

// Normalize a loose option value to `[Any?]` iff it is an array (JS `isArray`), else nil.
// NSNull elements collapse to nil so downstream `isString`/`isObject` checks see a JS-like null.
private func matrixDimLooseArray(_ any: Any?) -> [Any?]? {
    guard let any = any, !(any is NSNull) else { return nil }
    if let a = any as? [Any?] { return a }
    if let a = any as? [Any] { return a.map { ($0 is NSNull) ? nil : $0 } }
    return nil
}

// Coerce a dynamic option value to Double when numeric (tolerates the Int / NSNumber boxing that
// option-bag literals use — the recurring Int-vs-Double numeric-read trap). nil if not numeric.
private func matrixDimAsNumber(_ v: Any?) -> Double? {
    if let d = v as? Double { return d }
    if let i = v as? Int { return Double(i) }
    if let n = v as? NSNumber, !(n === kCFBooleanTrue || n === kCFBooleanFalse) { return n.doubleValue }
    if let s = v as? String { return Double(s) }
    return nil
}

// JS `!!x` truthiness for a dynamic option value.
private func matrixDimJsTruthy(_ v: Any?) -> Bool {
    guard let v = v, !(v is NSNull) else { return false }
    if let b = v as? Bool { return b }
    if let d = v as? Double { return d != 0 && !d.isNaN }
    if let i = v as? Int { return i != 0 }
    if let s = v as? String { return !s.isEmpty }
    return true
}
