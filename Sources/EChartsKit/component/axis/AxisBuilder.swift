// Ported from echarts/src/component/axis/AxisBuilder.ts — keep in sync with upstream
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
//   import { retrieve, defaults, extend, each, isObject, isString, isNumber, isFunction, retrieve2,
//       assert, map, retrieve3, filter } from 'zrender/src/core/util';    → `util.*` (ZRenderKit)
//   import * as graphic from '../../util/graphic';
//     → PORT-NOTE: `graphic.Group/Line/Text/Rect` are the ZRenderKit scene-graph types used directly
//       (`Group`, `Line`, `ZRText`, `Rect`); `graphic.subPixelOptimizeLine`
//       → `subPixelOptimizeNS.subPixelOptimizeLine`; `graphic.setTooltipConfig` → deferred to the
//       SYMBOLS.tsv row-37 lane (see the setTooltipConfig PORT-NOTEs at the axisName / axisLabel
//       call sites).
//   import {getECData} from '../../util/innerStore';                    → `innerStore.getECData` (deferred; event wiring)
//   import {createTextStyle} from '../../label/labelStyle';
//     → `label/labelStyle.swift` IS ported (`LabelStyle.createTextStyle`, labelStyle.swift:417). AxisBuilder
//       still uses a local keyword-arg convenience shim `createTextStyle` (bottom of file) whose fields map
//       1:1 to the two AxisLabel call sites. Deferred cleanup: rewire those to the ported `opt`-dict signature.
//   import Model from '../../model/Model';                              → `Model`
//   import {isRadianAroundZero, remRadian} from '../../util/number';    → `number.isRadianAroundZero` / `number.remRadian`
//   import {createSymbol, normalizeSymbolOffset} from '../../util/symbol';
//     → `symbol.createSymbol` / `symbol.normalizeSymbolOffset` (util/symbol.swift). Wired for the
//       axisLine arrow symbols (see the `axisLine` builder).
//   import * as matrixUtil from 'zrender/src/core/matrix';              → `matrix.*` (ZRenderKit)
//   import {applyTransform as v2ApplyTransform} from 'zrender/src/core/vector';  → `vector.applyTransform`
//   import { getTickValueOutermost, isNameLocationCenter, shouldShowAllLabels } from '../../coord/axisHelper';
//                                                                       → `axisHelper.*`
//   import { AxisBaseModel } from '../../coord/AxisBaseModel';          → `AxisBaseModel`
//   import { ZRTextVerticalAlign, ZRTextAlign, ECElement, ColorString, VisualAxisBreak, ParsedAxisBreak,
//       NullUndefined, DimensionName } from '../../util/types';         → `util/types` (ZRTextAlign == TextAlign, ...)
//   import { AxisBaseOption, ... } from '../../coord/axisCommonTypes';  → option interfaces collapsed to dynamic Any bag
//   import type Element from 'zrender/src/Element';                     → `Element` (ZRenderKit)
//   import { PathProps, PathStyleProps } from 'zrender/src/graphic/Path';  → `PathProps` / `PathStyleProps` (ZRenderKit)
//   import { hideOverlap, LabelLayoutWithGeometry, labelIntersect, LabelGeometry, computeLabelGeometry2,
//       ensureLabelLayoutWithGeometry, labelLayoutApplyTranslation, setLabelLayoutDirty,
//       newLabelLayoutWithGeometry, LabelLayoutData } from '../../label/labelLayoutHelper';
//     → PORT-NOTE: `label/labelLayoutHelper` is ported (labelLayoutHelper.swift). The real OBB-carrying
//       `LabelLayoutData` + `ensureLabelLayoutWithGeometry` landed in the L2c pass; the axis label path
//       now calls the real sibling directly (see the bottom-of-file note). `LabelGeometry` /
//       `LabelLayoutWithGeometry` both collapse to `LabelLayoutData` in this port.
//   import ExtensionAPI from '../../core/ExtensionAPI';                 → `ExtensionAPI`
//   import { makeInner } from '../../util/model';                       → `model.makeInner` (util/modelUtil.swift)
//   import { getAxisBreakHelper } from './axisBreakHelper';             → `getAxisBreakHelper()`
//     (axisModelCreator.swift): the optional break-helper module is not installed, so it returns nil.
//   import { AXIS_BREAK_EXPAND_ACTION_TYPE, BaseAxisBreakPayload } from './axisAction';
//     → PORT-NOTE (deferred): requires the `axisAction` module (break-expand action), not ported.
//   import { getScaleBreakHelper, hasBreaks } from '../../scale/break';  → `scale/break.swift`
//     (getScaleBreakHelper / hasBreaks are ported; `hasBreaks` gates the break-marker glyph below).
//   import BoundingRect from 'zrender/src/core/BoundingRect';           → `BoundingRect` (ZRenderKit; the
//     `stOccupiedRect` label-rect union in `resetOverlapRecordToShared`)
//   import Point from 'zrender/src/core/Point';                        → `Point` (ZRenderKit)
//   import { copyTransform } from 'zrender/src/core/Transformable';     → `copyTransform` (free func, ZRenderKit)
//   import { AxisLabelInfoDetermined, AxisLabelsComputingContext, AxisTickLabelComputingKind,
//       createAxisLabelsComputingContext } from '../../coord/axisTickLabelBuilder';  → `coord/axisTickLabelBuilder`
//   import { AxisTickCoord } from '../../coord/Axis';                   → `AxisTickCoord`
//   import { isOrdinalScale, isTimeScale } from '../../scale/helper';   → `helper.isOrdinalScale` /
//     `helper.isTimeScale` (scale/helper.swift, ported); used by the tick-label "notNice/offInterval" gate.

private let PI = Double.pi

// This tune is also for backward compat, since nameMoveOverlap is set as default,
// in compact layout (multiple charts in one canvas), name should be more close to the axis line and labels.
// upstream: DefaultCenterAxisNameMarginLevels = Record<nameMarginLevel, [n,n,n,n]>
private let DEFAULT_CENTER_NAME_MARGIN_LEVELS: [[Double]] =
    [[1, 2, 1, 2], [5, 3, 5, 3], [8, 3, 8, 3]]
private let DEFAULT_ENDS_NAME_MARGIN_LEVELS: [[Double]] =
    [[0, 1, 0, 1], [0, 3, 0, 3], [0, 3, 0, 3]]

// type AxisIndexKey = 'xAxisIndex' | 'yAxisIndex' | 'radiusAxisIndex' | 'angleAxisIndex' | 'singleAxisIndex';
//   PORT-NOTE: string-literal union → plain String at use sites (no Swift enum needed).

// upstream: type AxisEventData = { componentType, componentIndex, targetType, name?, value?,
//   dataIndex?, tickIndex? } & { break? } & { [key in AxisIndexKey]?: number }
//   Modeled as a dynamic bag ([String: Any]) since it is only consumed by the (deferred) event/tooltip wiring.
public typealias AxisEventData = [String: Any]

// type AxisLabelText = graphic.Text & { __fullText, __truncatedText } & ECElement;
//   PORT-NOTE (deferred): the `__fullText`/`__truncatedText`/ECElement decorations are used only by
//   tooltip/truncation wiring (not ported). Use `ZRText` directly.
public typealias AxisLabelText = ZRText

// upstream: export const getLabelInner = makeInner<{ labelInfo; layoutRotation }, graphic.Text>();
public final class AxisLabelInnerStore {
    public var labelInfo: AxisLabelInfoDetermined!   // Never be null/undefined.
    public var layoutRotation: Double = 0
    public init() {}
}
public let getLabelInner: (ZRText) -> AxisLabelInnerStore = model.makeInner { AxisLabelInnerStore() }

// upstream: const getTickInner = makeInner<{ onBand; tickValue }, graphic.Line>();
final class AxisTickInnerStore {
    var onBand: Bool?
    var tickValue: Double?
    init() {}
}
let getTickInner: (Line) -> AxisTickInnerStore = model.makeInner { AxisTickInnerStore() }


/**
 * @see {AxisBuilder}
 */
// upstream: export interface AxisBuilderCfg — a plain config bag → `struct` (CONVENTIONS §4).
public struct AxisBuilderCfg {
    /// @mandatory The origin of the axis, in the global pixel coords.
    public var position: [Double]
    /**
     * @mandatory
     * The rotation of the axis from the "standard axis". In radian.
     * (See upstream comment for the sign/direction convention.)
     */
    public var rotation: Double
    /**
     * `nameDirection` / `tickDirection` / `labelDirection`:
     *  - `1` means ticks or labels are below the "standard axis".
     *  - `-1` means they are above the "standard axis".
     */
    public var nameDirection: Double?   // upstream: -1 | 1
    public var tickDirection: Double?   // upstream: -1 | 1
    public var labelDirection: Double?  // upstream: -1 | 1
    /// Offset between labels and the axis line (useful when onZero: true).
    public var labelOffset: Double?
    /// If not specified, get from axisModel.
    public var axisLabelShow: Bool?
    /// Works on axisLine.show: 'auto'. true by default.
    public var axisLineAutoShow: Bool?
    /// Works on axisTick.show: 'auto'. true by default.
    public var axisTickAutoShow: Bool?
    /// default get from axisModel.
    public var axisName: String?
    public var axisNameAvailableWidth: Double?
    /// by degree, default get from axisModel.
    public var labelRotate: Double?
    public var strokeContainThreshold: Double?
    public var nameTruncateMaxWidth: Double?
    public var silent: Bool?
    public var defaultNameMoveOverlap: Bool?

    public init(
        position: [Double],
        rotation: Double,
        nameDirection: Double? = nil,
        tickDirection: Double? = nil,
        labelDirection: Double? = nil,
        labelOffset: Double? = nil,
        axisLabelShow: Bool? = nil,
        axisLineAutoShow: Bool? = nil,
        axisTickAutoShow: Bool? = nil,
        axisName: String? = nil,
        axisNameAvailableWidth: Double? = nil,
        labelRotate: Double? = nil,
        strokeContainThreshold: Double? = nil,
        nameTruncateMaxWidth: Double? = nil,
        silent: Bool? = nil,
        defaultNameMoveOverlap: Bool? = nil
    ) {
        self.position = position
        self.rotation = rotation
        self.nameDirection = nameDirection
        self.tickDirection = tickDirection
        self.labelDirection = labelDirection
        self.labelOffset = labelOffset
        self.axisLabelShow = axisLabelShow
        self.axisLineAutoShow = axisLineAutoShow
        self.axisTickAutoShow = axisTickAutoShow
        self.axisName = axisName
        self.axisNameAvailableWidth = axisNameAvailableWidth
        self.labelRotate = labelRotate
        self.strokeContainThreshold = strokeContainThreshold
        self.nameTruncateMaxWidth = nameTruncateMaxWidth
        self.silent = silent
        self.defaultNameMoveOverlap = defaultNameMoveOverlap
    }

    // Build from a `CartesianAxisLayout` (upstream relies on structural typing:
    //   `const layoutResult: AxisBuilderCfg = layout(gridRect, axisModel)` in cartesianAxisHelper).
    //   The extra `z2` on `CartesianAxisLayout` is not part of `AxisBuilderCfg` upstream; dropped.
    public init(_ l: CartesianAxisLayout) {
        self.position = l.position
        self.rotation = l.rotation
        self.nameDirection = l.nameDirection
        self.tickDirection = l.tickDirection
        self.labelDirection = l.labelDirection
        self.labelOffset = l.labelOffset
        self.labelRotate = l.labelRotate
    }
}

/**
 * Use it prior to `AxisBuilderCfg`. If settings in `AxisBuilderCfg` need to be preprocessed
 * and shared by different methods, put them here.
 */
// upstream: interface AxisBuilderCfgDetermined. Held/mutated by reference (updateCfg rewrites `raw`),
//   so a `final class` (CONVENTIONS §4).
//   PORT-NOTE: upstream's interface is module-internal, but the exported `AxisBuilderSharedContext`
//     references it in `resolveAxisNameOverlap`; Swift requires the type itself to be `public` for that
//     public typealias. Deliberately public-but-OPAQUE: every member stays internal, so this widens the
//     shipped EChartsKit surface by a name only — external callers can neither construct nor read it.
public final class AxisBuilderCfgDetermined {
    var raw: AxisBuilderCfg
    var position: [Double]
    var rotation: Double
    var nameDirection: Double
    var tickDirection: Double
    var labelDirection: Double
    var silent: Bool
    var labelOffset: Double
    var axisName: String?
    var nameLocation: String
    var shouldNameMoveOverlap: Bool
    var showMinorTicks: Bool
    var optionHideOverlap: Any?  // AxisBaseOption['axisLabel']['hideOverlap']

    init(
        raw: AxisBuilderCfg, position: [Double], rotation: Double,
        nameDirection: Double, tickDirection: Double, labelDirection: Double,
        silent: Bool, labelOffset: Double, axisName: String?, nameLocation: String,
        shouldNameMoveOverlap: Bool, showMinorTicks: Bool, optionHideOverlap: Any?
    ) {
        self.raw = raw
        self.position = position
        self.rotation = rotation
        self.nameDirection = nameDirection
        self.tickDirection = tickDirection
        self.labelDirection = labelDirection
        self.silent = silent
        self.labelOffset = labelOffset
        self.axisName = axisName
        self.nameLocation = nameLocation
        self.shouldNameMoveOverlap = shouldNameMoveOverlap
        self.showMinorTicks = showMinorTicks
        self.optionHideOverlap = optionHideOverlap
    }
}

/**
 * The context of this axisBuilder instance, never shared between axisBuilder instances.
 * @see AxisBuilderSharedContext
 */
final class AxisBuilderLocalContext {
    var labelLayoutList: [LabelLayoutData]?
    var labelGroup: Group?
    var axisLabelsCreationContext: AxisLabelsComputingContext?
    var nameEl: ZRText?
    init() {}
}

// upstream: export type AxisBuilderSharedContextRecord = { dirVec?, transGroup?, labelInfoList?,
//   stOccupiedRect?, nameLayout?, nameLocation?, ready }
public final class AxisBuilderSharedContextRecord {
    // Represents axis rotation. The magnitude is 1.
    public var dirVec: Point?
    public var transGroup: Group?
    // - Used for overlap detection for both self and other axes.
    // - Sorted in ascending order of the distance to transformGroup.x/y.
    //  This sorting is for OBB intersection checking.
    // - No nil item, and ignored items has been removed.
    // upstream: labelInfoList?: LabelLayoutWithGeometry[]  (the Swift geometry-carrying type is LabelLayoutData)
    public var labelInfoList: [LabelLayoutData]?
    // `stOccupiedRect` is based on the "standard axis".
    // If no label, be `nil`.
    // - When `nameLocation` is 'center', `stOccupiedRect` is the union of labels, and is used for the case
    //   below, where even if the `name` does not intersect with `1,000,000`, it is still pulled left to avoid
    //   the overlap with `stOccupiedRect`.
    //        1,000,000 -
    //      n           |
    //      a     1,000 -
    //      m           |
    //      e         0 -----------
    // - When `nameLocaiton` is 'start'/'end', `stOccupiedRect` is not used, because they are not likely to
    //   overlap. Additionally, these cases need to be considered:
    //      If axis labels rotating, axis names should not be pulled by the union rect of labels.
    //          ----|-----|   axis name with
    //              1     5   big height
    //                0     0
    //                  0     0
    //      Axis line and axis labels should not be unioned to one rect for overlap detection, because of
    //      the most common case below (The axis name is inserted into the indentation to save space):
    //          ----|------------|  A axis name
    //          1,000,000   300,000,000
    public var stOccupiedRect: BoundingRect?
    // upstream: nameLayout?: LabelLayoutWithGeometry | NullUndefined
    public var nameLayout: LabelLayoutData?
    // upstream: nameLocation?: AxisBaseOption['nameLocation']  (string-literal union → String)
    public var nameLocation: String?
    // Only used in __DEV__ mode.
    public var ready: [String: Bool] = [:]
    public init() {}
}

/**
 * A context shared by difference axisBuilder instances. For cross-axes overlap resolving.
 *
 * Lifecycle constraint: should not over a pass of ec main process.
 *  If model is changed, the context must be disposed.
 *
 * @see AxisBuilderLocalContext
 */
public final class AxisBuilderSharedContext {
    /// [CAUTION] Do not modify this data structure outside this class.
    // upstream: recordMap: { [axisDimension]: AxisBuilderSharedContextRecord[] }  (list index: axisIndex)
    public var recordMap: [String: [AxisBuilderSharedContextRecord?]] = [:]

    // upstream: constructor(resolveAxisNameOverlap) { this.resolveAxisNameOverlap = resolveAxisNameOverlap; }
    public init(_ resolveAxisNameOverlap: @escaping ResolveAxisNameOverlap) {
        self.resolveAxisNameOverlap = resolveAxisNameOverlap
    }

    public func ensureRecord(_ axisModel: AxisBaseModel) -> AxisBuilderSharedContextRecord {
        let dim = (axisModel.axis as! Axis).dim
        let idx = Int(axisModel.componentIndex)
        if recordMap[dim] == nil {
            recordMap[dim] = []
        }
        // Grow the sparse list up to `idx` (upstream uses JS sparse arrays).
        while recordMap[dim]!.count <= idx {
            recordMap[dim]!.append(nil)
        }
        if recordMap[dim]![idx] == nil {
            recordMap[dim]![idx] = AxisBuilderSharedContextRecord()
        }
        return recordMap[dim]![idx]!
    }

    /**
     * Overlap resolution strategy. May vary for different coordinate systems.
     */
    // upstream: readonly resolveAxisNameOverlap: (cfg, ctx, axisModel, nameLayoutInfo, nameMoveDirVec, thisRecord) => void
    public typealias ResolveAxisNameOverlap = (
        _ cfg: AxisBuilderCfgDetermined,
        _ ctx: AxisBuilderSharedContext?,
        _ axisModel: AxisBaseModel,
        _ nameLayoutInfo: LabelLayoutData,  // The existing has been ensured.
        _ nameMoveDirVec: Point,
        _ thisRecord: AxisBuilderSharedContextRecord  // The existing has been ensured.
    ) -> Void
    public let resolveAxisNameOverlap: ResolveAxisNameOverlap
}

/**
 * [CAUTION]
 *  1. The call of this function must be after axisLabel overlap handlings
 *     (such as `hideOverlap`, `fixMinMaxLabelShow`) and after transform calculating.
 *  2. Can be called multiple times and should be idempotent.
 */
// upstream: function resetOverlapRecordToShared(cfg, shared, axisModel, labelLayoutList: LabelLayoutData[])
//   PORT-NOTE: upstream's module-level scratch `_stTransTmp` / `_stLabelRectTmp` are replaced by locals,
//     since the matrix module is value-return in this port (PORTING §10, no out-params).
func resetOverlapRecordToShared(
    _ cfg: AxisBuilderCfgDetermined,
    _ shared: AxisBuilderSharedContext,
    _ axisModel: AxisBaseModel,
    _ labelLayoutList: [LabelLayoutData]
) {
    let axis = axisModel.axis as! Axis
    let record = shared.ensureRecord(axisModel)
    var labelInfoList: [LabelLayoutData] = []
    var stOccupiedRect: BoundingRect?
    let useStOccupiedRect = hasAxisName(cfg.axisName) && axisHelper.isNameLocationCenter(cfg.nameLocation)

    util.each(labelLayoutList) { layout, _ in
        guard let layoutInfo = labelLayoutHelper.ensureLabelLayoutWithGeometry(layout),
              !layoutInfo.label.ignore else {
            return
        }
        labelInfoList.append(layoutInfo)

        let transGroup = record.transGroup
        if useStOccupiedRect {
            // Transform to "standard axis" for creating stOccupiedRect (the label rects union).
            var stTrans: MatrixArray
            if let groupTransform = transGroup?.transform {
                stTrans = matrix.invert(groupTransform) ?? matrix.identity()
            }
            else {
                stTrans = matrix.identity()
            }
            if let layoutTransform = layoutInfo.transform {
                stTrans = matrix.mul(stTrans, layoutTransform)
            }
            let stLabelRect = BoundingRect(0, 0, 0, 0)
            stLabelRect.copy(layoutInfo.localRect ?? BoundingRect(0, 0, 0, 0))
            stLabelRect.applyTransform(stTrans)
            if let existing = stOccupiedRect {
                existing.union(stLabelRect)
            }
            else {
                let created = BoundingRect(0, 0, 0, 0)
                created.copy(stLabelRect)
                stOccupiedRect = created
            }
        }
    }

    // upstream: sortByDim = Math.abs(record.dirVec.x) > 0.1 ? 'x' : 'y'
    let sortByX = Swift.abs(record.dirVec?.x ?? 0) > 0.1
    let sortByValue = (sortByX ? record.transGroup?.x : record.transGroup?.y) ?? 0
    func sortKey(_ info: LabelLayoutData) -> Double {
        let k = Swift.abs((sortByX ? info.label.x : info.label.y) - sortByValue)
        // PORT-NOTE: JS leaves the relative order of NaN keys arbitrary, but Swift's `sorted(by:)` TRAPS
        //   ("predicate is not a strict weak ordering") if the predicate is inconsistent. Map NaN to
        //   +inf so it sorts last deterministically instead of crashing.
        return k.isNaN ? Double.greatestFiniteMagnitude : k
    }
    // PORT-NOTE: `Array.sort` in JS is stable (ES2019) but Swift's `sort` is not; keep the original
    //   order for equal keys by carrying the index as a tiebreaker.
    labelInfoList = labelInfoList.enumerated()
        .sorted { lhs, rhs in
            let k1 = sortKey(lhs.element), k2 = sortKey(rhs.element)
            return k1 == k2 ? lhs.offset < rhs.offset : k1 < k2
        }
        .map { $0.element }

    if useStOccupiedRect, let stOccupiedRect = stOccupiedRect {
        let extent = axis.getExtent()
        let axisLineX = Swift.min(extent[0], extent[1])
        let axisLineWidth = Swift.max(extent[0], extent[1]) - axisLineX
        // If `nameLocation` is 'middle', enlarge axis labels boundingRect to axisLine to avoid bad
        //  case like that axis name is placed in the gap between axis labels and axis line.
        // If only one label exists, the entire band should be occupied for
        // visual consistency, so extent it to [0, canvas width].
        stOccupiedRect.union(BoundingRect(axisLineX, 0, axisLineWidth, 1))
    }

    record.stOccupiedRect = stOccupiedRect
    record.labelInfoList = labelInfoList
}
/**
 * The default resolver does not involve other axes within the same coordinate system.
 */
public let resolveAxisNameOverlapDefault: AxisBuilderSharedContext.ResolveAxisNameOverlap = {
    cfg, ctx, axisModel, nameLayoutInfo, nameMoveDirVec, thisRecord in
    if axisHelper.isNameLocationCenter(cfg.nameLocation) {
        if let stOccupiedRect = thisRecord.stOccupiedRect {
            // upstream: computeLabelGeometry2({}, stOccupiedRect, thisRecord.transGroup.transform)
            //   PORT-NOTE: `LabelLayoutData` requires a `label` element (upstream's `{}` is an untyped
            //     bag used purely as a geometry carrier), so a throwaway `ZRText` backs the rect.
            let basedLayoutInfo = LabelLayoutData(label: ZRText())
            labelLayoutHelper.computeLabelGeometry2(
                basedLayoutInfo, stOccupiedRect, thisRecord.transGroup?.transform
            )
            moveIfOverlap(basedLayoutInfo, nameLayoutInfo, nameMoveDirVec)
        }
    }
    else {
        moveIfOverlapByLinearLabels(
            thisRecord.labelInfoList ?? [], thisRecord.dirVec ?? Point(0, 0), nameLayoutInfo, nameMoveDirVec
        )
    }
    _ = (ctx, axisModel)
}

// [NOTICE] not consider ignore.
// upstream: function moveIfOverlap(basedLayoutInfo: LabelGeometry, movableLayoutInfo, moveDirVec)
private func moveIfOverlap(
    _ basedLayoutInfo: LabelLayoutData,
    _ movableLayoutInfo: LabelLayoutData,
    _ moveDirVec: Point
) {
    let mtv = Point()
    if labelLayoutHelper.labelIntersect(basedLayoutInfo, movableLayoutInfo, mtv, BoundingRectIntersectOpt(
        direction: atan2(moveDirVec.y, moveDirVec.x),
        bidirectional: false,
        touchThreshold: 0.05
    )) {
        labelLayoutHelper.labelLayoutApplyTranslation(movableLayoutInfo, mtv)
    }
}

// upstream: export function moveIfOverlapByLinearLabels(baseLayoutInfoList, baseDirVec, movableLayoutInfo, moveDirVec)
public func moveIfOverlapByLinearLabels(
    _ baseLayoutInfoList: [LabelLayoutData],
    _ baseDirVec: Point,
    _ movableLayoutInfo: LabelLayoutData,
    _ moveDirVec: Point
) {
    // Detect and move from far to close.
    let sameDir = Point.dot(moveDirVec, baseDirVec) >= 0
    let len = baseLayoutInfoList.count
    for idx in 0..<Swift.max(len, 0) {
        let labelInfo = baseLayoutInfoList[sameDir ? idx : len - 1 - idx]
        if !labelInfo.label.ignore {
            moveIfOverlap(labelInfo, movableLayoutInfo, moveDirVec)
        }
    }
}

/**
 * @caution
 * - Ensure it is called after the data processing stage finished.
 * - It might be called before `ChartView#render` ... thus ensure the result the same whenever it is called.
 *
 * A builder for a straight-line axis.
 *
 * A final axis is translated and rotated from a "standard axis".
 * So opt.position and opt.rotation is required.
 *
 * A "standard axis" is the axis [0,0]-->[abs(axisExtent[1]-axisExtent[0]),0]
 * for example: [0,0]-->[50,0]
 */
// upstream: class AxisBuilder — instantiated helper (not the scene graph), holds a `group`.
public final class AxisBuilder {

    private var _axisModel: AxisBaseModel

    private var _cfg: AxisBuilderCfgDetermined!
    private var _local: AxisBuilderLocalContext
    private var _shared: AxisBuilderSharedContext

    public let group = Group()

    /// `_transformGroup.transform` is ready to visit. (but be `nil` if no transform.)
    private var _transformGroup: Group!
    private var _api: ExtensionAPI

    /**
     * [CAUTION]: axisModel.axis.extent/scale must be ready to use.
     */
    public init(
        _ axisModel: AxisBaseModel,
        _ api: ExtensionAPI,
        _ opt: AxisBuilderCfg,
        _ shared: AxisBuilderSharedContext? = nil
    ) {
        self._axisModel = axisModel
        self._api = api
        self._local = AxisBuilderLocalContext()
        self._shared = shared ?? AxisBuilderSharedContext(resolveAxisNameOverlapDefault)

        self._resetCfgDetermined(opt)
    }

    /**
     * Regarding axis label related configurations, only the change of label.x/y is supported ...
     * (See upstream comment.)
     */
    public func updateCfg(_ opt: AxisBuilderCfg) {
        // PORT-NOTE: upstream takes Pick<AxisBuilderCfg, 'position' | 'labelOffset'>; the `__DEV__`
        //   readiness assertions (dev-only build guard) are dropped.
        let raw = self._cfg.raw
        var newRaw = raw
        newRaw.position = opt.position
        newRaw.labelOffset = opt.labelOffset
        self._resetCfgDetermined(newRaw)
    }

    /**
     * [CAUTION] For debug usage. Never change it outside!
     */
    func __getRawCfg() -> AxisBuilderCfg {
        return self._cfg.raw
    }

    private func _resetCfgDetermined(_ raw: AxisBuilderCfg) {
        let axisModel = self._axisModel

        // FIXME: (see upstream comment on defaulting null/undefined options).
        let axisModelDefaultOption = (axisModel.getDefaultOption() as? [String: Any]) ?? [:]

        // Default value
        let axisName = raw.axisName ?? (axisModel.get("name") as? String)

        var nameMoveOverlapOption = axisModel.get("nameMoveOverlap")
        if nameMoveOverlapOption == nil || (nameMoveOverlapOption as? String) == "auto" {
            nameMoveOverlapOption = raw.defaultNameMoveOverlap ?? true
        }

        let cfg = AxisBuilderCfgDetermined(
            raw: raw,
            position: raw.position,
            rotation: raw.rotation,
            nameDirection: raw.nameDirection ?? 1,
            tickDirection: raw.tickDirection ?? 1,
            labelDirection: raw.labelDirection ?? 1,
            silent: raw.silent ?? true,
            labelOffset: raw.labelOffset ?? 0,
            axisName: axisName,
            nameLocation: (axisModel.get("nameLocation") as? String)
                ?? (axisModelDefaultOption["nameLocation"] as? String) ?? "end",
            shouldNameMoveOverlap: hasAxisName(axisName) && truthy(nameMoveOverlapOption),
            showMinorTicks: truthy(axisModel.get(["minorTick", "show"])),
            optionHideOverlap: axisModel.get(["axisLabel", "hideOverlap"])
        )
        self._cfg = cfg

        // FIXME Not use a separate text group?
        let transformGroup = Group([
            "x": cfg.position[0],
            "y": cfg.position[1],
            "rotation": cfg.rotation
        ])
        transformGroup.updateTransform()
        self._transformGroup = transformGroup

        let record = self._shared.ensureRecord(axisModel)
        record.transGroup = self._transformGroup
        record.dirVec = Point(cos(-cfg.rotation), sin(-cfg.rotation))
    }

    @discardableResult
    public func build(_ axisPartNameMap: [String: Bool]? = nil, _ extraParams: AxisBuilderBuildExtraParams = AxisBuilderBuildExtraParams()) -> AxisBuilder {
        var partMap = axisPartNameMap
        if partMap == nil {
            partMap = [
                "axisLine": true,
                "axisTickLabelEstimate": false,
                "axisTickLabelDetermine": true,
                "axisName": true
            ]
        }

        for partName in AXIS_BUILDER_AXIS_PART_NAMES {
            if partMap?[partName] == true {
                builders[partName]!(
                    self._cfg, self._local, self._shared,
                    self._axisModel, self.group, self._transformGroup, self._api,
                    extraParams
                )
            }
        }
        return self
    }

    /**
     * Currently only get text align/verticalAlign by rotation.
     * NO `position` is involved ...
     */
    public static func innerTextLayout(_ axisRotation: Double, _ textRotation: Double, _ direction: Double)
        -> (rotation: Double, textAlign: ZRTextAlign, textVerticalAlign: ZRTextVerticalAlign) {
        let rotationDiff = number.remRadian(textRotation - axisRotation)
        var textAlign: ZRTextAlign
        var textVerticalAlign: ZRTextVerticalAlign

        if number.isRadianAroundZero(rotationDiff) { // Label is parallel with axis line.
            textVerticalAlign = direction > 0 ? .top : .bottom
            textAlign = .center
        }
        else if number.isRadianAroundZero(rotationDiff - PI) { // Label is inverse parallel with axis line.
            textVerticalAlign = direction > 0 ? .bottom : .top
            textAlign = .center
        }
        else {
            textVerticalAlign = .middle

            if rotationDiff > 0 && rotationDiff < PI {
                textAlign = direction > 0 ? .right : .left
            }
            else {
                textAlign = direction > 0 ? .left : .right
            }
        }

        return (rotation: rotationDiff, textAlign: textAlign, textVerticalAlign: textVerticalAlign)
    }

    public static func makeAxisEventDataBase(_ axisModel: AxisBaseModel) -> AxisEventData {
        var eventData: AxisEventData = [
            "componentType": axisModel.mainType,
            "componentIndex": axisModel.componentIndex
        ]
        eventData[axisModel.mainType + "Index"] = axisModel.componentIndex
        return eventData
    }

    public static func isLabelSilent(_ axisModel: AxisBaseModel) -> Bool {
        let tooltipOpt = axisModel.get("tooltip")
        // upstream: axisModel.get('silent') || !(axisModel.get('triggerEvent') || (tooltipOpt && tooltipOpt.show))
        return truthy(axisModel.get("silent"))
            || !(
                truthy(axisModel.get("triggerEvent"))
                    || truthy((tooltipOpt as? [String: Any])?["show"])
            )
    }
}

// upstream: interface AxisElementsBuilder — the per-part builder function signature.
typealias AxisElementsBuilder = (
    _ cfg: AxisBuilderCfgDetermined,
    _ local: AxisBuilderLocalContext,
    _ shared: AxisBuilderSharedContext,
    _ axisModel: AxisBaseModel,
    _ group: Group,
    _ transformGroup: Group,
    _ api: ExtensionAPI,
    _ extraParams: AxisBuilderBuildExtraParams
) -> Void

// upstream: interface AxisBuilderBuildExtraParams { noPxChange?, nameMarginLevel? }
public struct AxisBuilderBuildExtraParams {
    public var noPxChange: Bool?
    public var nameMarginLevel: Int?   // upstream: 0 | 1 | 2
    public init(noPxChange: Bool? = nil, nameMarginLevel: Int? = nil) {
        self.noPxChange = noPxChange
        self.nameMarginLevel = nameMarginLevel
    }
}

// Sorted by dependency order.
let AXIS_BUILDER_AXIS_PART_NAMES: [String] = [
    "axisLine",
    "axisTickLabelEstimate",
    "axisTickLabelDetermine",
    "axisName"
]

// upstream: const builders: Record<AxisBuilderAxisPartName, AxisElementsBuilder> = { ... }
let builders: [String: AxisElementsBuilder] = [

    "axisLine": { cfg, _, _, axisModel, group, transformGroup, _, _ in
        // PORT-NOTE: upstream `__DEV__` readiness assertion (dev-only build guard) dropped.

        var shown = axisModel.get(["axisLine", "show"])
        if (shown as? String) == "auto" {
            shown = true
            if cfg.raw.axisLineAutoShow != nil {
                shown = cfg.raw.axisLineAutoShow!
            }
        }
        if !truthy(shown) {
            return
        }

        let extent = (axisModel.axis as! Axis).getExtent()

        let matrixArr = transformGroup.transform
        var pt1 = VectorArray(extent[0], 0)
        var pt2 = VectorArray(extent[1], 0)
        // upstream: const inverse = pt1[0] > pt2[0];  (computed in the arrow-symbol block below)
        if let m = matrixArr {
            pt1 = vector.applyTransform(pt1, m)
            pt2 = vector.applyTransform(pt2, m)
        }

        // upstream: extend({ lineCap: 'round' }, axisModel.getModel(['axisLine', 'lineStyle']).getLineStyle())
        var lineStyleDict = axisModel.getModel(["axisLine", "lineStyle"]).getLineStyle()
        lineStyleDict["lineCap"] = "round"
        let lineStyle = pathStyleFromLineStyleDict(lineStyleDict)

        // upstream: pathBaseProp: PathProps = { strokeContainThreshold, silent: true, z2: 1, style: lineStyle }
        // upstream: if (axisModel.get(['axisLine', 'breakLine']) && hasBreaks(axisModel.axis.scale)) { ... }
        //   PORT-NOTE (deferred): the broken axis-line rendering needs the optional axisBreakHelper
        //   break-line builder (getAxisBreakHelper() is nil in this port), so the else branch (the
        //   plain axis Line) is always taken. The core break-marker glyph is drawn below.
        let line = Line([
            "shape": lineShapeOf(pt1[0], pt1[1], pt2[0], pt2[1]),
            "style": lineStyle,
            "strokeContainThreshold": cfg.raw.strokeContainThreshold ?? 5,
            "silent": true,
            "z2": Double(1)
        ])
        // upstream: graphic.subPixelOptimizeLine(line.shape, line.style.lineWidth)  (mutates line.shape)
        if let optimized = subPixelOptimizeNS.subPixelOptimizeLine(
            subPixelOptimizeNS.LineShape(x1: pt1[0], y1: pt1[1], x2: pt2[0], y2: pt2[1]),
            line.pathStyle
        ) {
            line.shape = lineShapeOf(optimized.x1, optimized.y1, optimized.x2, optimized.y2)
        }
        line.anid = "line"
        _ = group.add(line)

        // PORT-ADDITION (minimal, guarded by hasBreaks): draw the value-axis break marker glyph at
        //   each break position on the axis line. Upstream's full break-area zigzag rendering is
        //   deferred (see axisBreakMarker.swift); this is the CORE marker. Non-broken axes are
        //   unaffected (buildAxisBreakMarker early-returns when the scale has no breaks).
        let breakMarkerAmplitude = axisBreakStyleNumber(axisModel.get(["breakArea", "zigzagAmplitude"]))
            ?? AXIS_BREAK_MARKER_AMPLITUDE
        buildAxisBreakMarker(
            axisModel.axis as! Axis,
            group,
            transformGroup.transform,
            lineStyle,
            breakMarkerAmplitude
        )

        // upstream: let arrows = axisModel.get(['axisLine', 'symbol']); if (arrows != null) { ... createSymbol ... }
        let arrowsRaw = axisModel.get(["axisLine", "symbol"])
        if arrowsRaw != nil {
            // Use the same arrow for start and end point when a single string is given.
            var arrows: [Any?]
            if util.isString(arrowsRaw) {
                arrows = [arrowsRaw, arrowsRaw]
            }
            else if let a = arrowsRaw as? [Any?] {
                arrows = a
            }
            else if let a = arrowsRaw as? [Any] {
                arrows = a.map { $0 as Any? }
            }
            else {
                arrows = [arrowsRaw, arrowsRaw]
            }

            // Use the same size for width and height when a single string/number is given.
            let arrowSizeRaw = axisModel.get(["axisLine", "symbolSize"])
            var arrowSize: [Double]
            if util.isString(arrowSizeRaw) || util.isNumber(arrowSizeRaw) {
                let s = (arrowSizeRaw as? Double) ?? 0
                arrowSize = [s, s]
            }
            else if let arr = arrowSizeRaw as? [Any] {
                arrowSize = [
                    arr.count > 0 ? ((arr[0] as? Double) ?? 0) : 0,
                    arr.count > 1 ? ((arr[1] as? Double) ?? 0) : 0
                ]
            }
            else {
                arrowSize = [0, 0]
            }

            // upstream: normalizeSymbolOffset(axisModel.get(['axisLine','symbolOffset']) || 0, arrowSize)
            let arrowOffset = symbol.normalizeSymbolOffset(
                axisModel.get(["axisLine", "symbolOffset"]) ?? Double(0), arrowSize
            ) ?? (0, 0)
            let offsets = [arrowOffset.0, arrowOffset.1]

            let symbolWidth = arrowSize[0]
            let symbolHeight = arrowSize[1]
            let inverse = pt1[0] > pt2[0]

            let dx = pt1[0] - pt2[0]
            let dy = pt1[1] - pt2[1]
            let rLen = (dx * dx + dy * dy).squareRoot()

            let points: [(rotate: Double, offset: Double, r: Double)] = [
                (cfg.rotation + PI / 2, offsets[0], 0),
                (cfg.rotation - PI / 2, offsets[1], rLen)
            ]
            for (index, point) in points.enumerated() where index < arrows.count {
                if let arrowStr = arrows[index] as? String, arrowStr != "none" {
                    guard let sym = symbol.createSymbol(
                        arrowStr,
                        -symbolWidth / 2,
                        -symbolHeight / 2,
                        symbolWidth,
                        symbolHeight,
                        lineStyle.stroke,
                        true
                    ) as? Path else { continue }

                    // Calculate arrow position with offset.
                    let r = point.r + point.offset
                    let pt = inverse ? pt2 : pt1
                    sym.attr([
                        "rotation": point.rotate,
                        "x": pt[0] + r * cos(cfg.rotation),
                        "y": pt[1] - r * sin(cfg.rotation),
                        "silent": true,
                        "z2": Double(11)
                    ])
                    _ = group.add(sym)
                }
            }
        }
    },

    /**
     * [CAUTION] This method can be called multiple times ... Thus this method should be idempotent.
     */
    "axisTickLabelEstimate": { cfg, local, shared, axisModel, group, transformGroup, api, extraParams in
        // PORT-NOTE: upstream `__DEV__` readiness assertion (dev-only build guard) dropped.
        let needCallLayout = dealLastTickLabelResultReusable(local, group, extraParams)
        if needCallLayout {
            layOutAxisTickLabel(
                cfg, local, shared, axisModel, group, transformGroup, api, AxisTickLabelComputingKind.estimate
            )
        }
    },

    /**
     * Finish axis tick label build. Can be only called once.
     */
    "axisTickLabelDetermine": { cfg, local, shared, axisModel, group, transformGroup, api, extraParams in
        // PORT-NOTE: upstream `__DEV__` readiness assertion (dev-only build guard) dropped.
        let needCallLayout = dealLastTickLabelResultReusable(local, group, extraParams)
        if needCallLayout {
            layOutAxisTickLabel(
                cfg, local, shared, axisModel, group, transformGroup, api, AxisTickLabelComputingKind.determine
            )
        }
        let ticksEls = buildAxisMajorTicks(cfg, group, transformGroup, axisModel)
        syncLabelIgnoreToMajorTicks(cfg, local.labelLayoutList, ticksEls)

        buildAxisMinorTicks(cfg, group, transformGroup, axisModel, cfg.tickDirection)
    },

    /**
     * [CAUTION] This method can be called multiple times ... Thus this method should be idempotent.
     */
    "axisName": { cfg, local, shared, axisModel, group, transformGroup, _, extraParams in
        let sharedRecord = shared.ensureRecord(axisModel)
        // PORT-NOTE: upstream `__DEV__` readiness assertion (dev-only build guard) dropped.

        // Remove the existing name result created in estimation phase.
        if let nameEl = local.nameEl {
            _ = group.remove(nameEl)
            // upstream: local.nameEl = sharedRecord.nameLayout = sharedRecord.nameLocation = null;
            local.nameEl = nil
            sharedRecord.nameLayout = nil
            sharedRecord.nameLocation = nil
        }

        let name = cfg.axisName
        if !hasAxisName(name) {
            return
        }
        let nameStr = name!

        let nameLocation = cfg.nameLocation
        let nameDirection = cfg.nameDirection
        let textStyleModel = axisModel.getModel("nameTextStyle")
        let gap = axisOptionDouble(axisModel.get("nameGap")) ?? 0

        let axis = axisModel.axis as! Axis
        let extent = axis.getExtent()
        let gapStartEndSignal: Double = axis.inverse ? -1 : 1
        // upstream uses `Point` for both; `pos` is spread to posX/posY at the ZRText attrs below.
        var posX: Double = 0
        var posY: Double = 0
        let nameMoveDirVec = Point(0, 0)
        if nameLocation == "start" {
            posX = extent[0] - gapStartEndSignal * gap
            nameMoveDirVec.x = -gapStartEndSignal
        }
        else if nameLocation == "end" {
            posX = extent[1] + gapStartEndSignal * gap
            nameMoveDirVec.x = gapStartEndSignal
        }
        else { // 'middle' or 'center'
            posX = (extent[0] + extent[1]) / 2
            posY = cfg.labelOffset + nameDirection * gap
            nameMoveDirVec.y = nameDirection
        }
        // upstream: const mt = matrixUtil.create(); nameMoveDirVec.transform(matrixUtil.rotate(mt, mt, cfg.rotation));
        _ = nameMoveDirVec.transform(matrix.rotate(matrix.create(), cfg.rotation))

        var nameRotation = axisModel.get("nameRotate") as? Double
        if nameRotation != nil {
            nameRotation = nameRotation! * PI / 180 // To radian.
        }

        let labelLayout: (rotation: Double, textAlign: ZRTextAlign, textVerticalAlign: ZRTextVerticalAlign)
        var axisNameAvailableWidth: Double?

        if axisHelper.isNameLocationCenter(nameLocation) {
            labelLayout = AxisBuilder.innerTextLayout(
                cfg.rotation,
                nameRotation != nil ? nameRotation! : cfg.rotation, // Adapt to axis.
                nameDirection
            )
        }
        else {
            labelLayout = endTextLayout(
                cfg.rotation, nameLocation, nameRotation ?? 0, extent
            )

            axisNameAvailableWidth = cfg.raw.axisNameAvailableWidth
            if axisNameAvailableWidth != nil {
                axisNameAvailableWidth = Swift.abs(
                    axisNameAvailableWidth! / sin(labelLayout.rotation)
                )
                if !axisNameAvailableWidth!.isFinite { axisNameAvailableWidth = nil }
            }
        }

        let textFont = textStyleModel.getFont()

        let truncateOpt = (axisModel.get("nameTruncate", true) as? [String: Any]) ?? [:]
        let ellipsis = truncateOpt["ellipsis"] as? String
        let maxWidth = util.retrieve(
            cfg.raw.nameTruncateMaxWidth, truncateOpt["maxWidth"] as? Double, axisNameAvailableWidth
        )

        // upstream: const nameMarginLevel = extraParams.nameMarginLevel || 0;
        //   PORT-NOTE: upstream types this `0 | 1 | 2`, a literal union Swift cannot express, and JS would
        //     merely yield `undefined` (no marginDefault) for an out-of-range value. `Int` here indexes the
        //     3-row DEFAULT_*_NAME_MARGIN_LEVELS tables, so clamp instead of trapping on a bad caller.
        let nameMarginLevel = Swift.min(Swift.max(extraParams.nameMarginLevel ?? 0, 0), 2)

        let fill = textStyleModel.getTextColor()
            ?? (axisModel.get(["axisLine", "lineStyle", "color"]) as? ColorString)
        let align = (textStyleModel.get("align") as? String).flatMap { TextAlign(rawValue: $0) }
            ?? labelLayout.textAlign
        let verticalAlign = (textStyleModel.get("verticalAlign") as? String).flatMap { TextVerticalAlign(rawValue: $0) }
            ?? labelLayout.textVerticalAlign

        let textEl = ZRText([
            "x": posX,
            "y": posY,
            "rotation": labelLayout.rotation,
            "silent": AxisBuilder.isLabelSilent(axisModel),
            "style": createTextStyle(
                textStyleModel,
                text: nameStr,
                font: textFont,
                overflow: "truncate",
                width: maxWidth,
                ellipsis: ellipsis,
                fill: fill,
                align: align,
                verticalAlign: verticalAlign
            ),
            "z2": Double(1)
        ])

        // PORT-NOTE (deferred): graphic.setTooltipConfig (util/graphic.swift is ported, but the axis-name
        //   tooltip params/wiring are out of this render-focused scope).
        //   SCOPE: owned by SYMBOLS.tsv row 37 (`util/graphic.setTooltipConfig`), which enumerates this
        //   call site — left to that lane to avoid a two-lane edit of the same hunk.
        // PORT-NOTE (deferred): textEl.__fullText = name — the truncation-tooltip decoration is not wired.
        // Id for animation
        textEl.anid = "name"

        if truthy(axisModel.get("triggerEvent")) {
            var eventData = AxisBuilder.makeAxisEventDataBase(axisModel)
            eventData["targetType"] = "axisName"
            eventData["name"] = nameStr
            innerStore.getECData(textEl).eventData = eventData
        }

        _ = transformGroup.add(textEl)
        textEl.updateTransform()

        local.nameEl = textEl
        let nameLayoutSource = LabelLayoutData(
            label: textEl,
            priority: textEl.z2
        )
        nameLayoutSource.defaultAttr.ignore = textEl.ignore
        // Make axis name visually far from axis labels (but not too aggressive, consider multiple small
        //   charts) when nameLocation is center; top/bottom margin is `0` for 'start'/'end' so the xAxis
        //   name is inserted into the indention above the axis labels to save space.
        nameLayoutSource.marginDefault = axisHelper.isNameLocationCenter(nameLocation)
            ? DEFAULT_CENTER_NAME_MARGIN_LEVELS[nameMarginLevel]
            : DEFAULT_ENDS_NAME_MARGIN_LEVELS[nameMarginLevel]
        let nameLayout = labelLayoutHelper.ensureLabelLayoutWithGeometry(nameLayoutSource)
        sharedRecord.nameLayout = nameLayout
        sharedRecord.nameLocation = nameLocation
        _ = group.add(textEl)

        textEl.decomposeTransform()

        if cfg.shouldNameMoveOverlap, let nameLayout = nameLayout {
            let record = shared.ensureRecord(axisModel)
            // PORT-NOTE: upstream `__DEV__` assert(record.labelInfoList) dropped.
            shared.resolveAxisNameOverlap(cfg, shared, axisModel, nameLayout, nameMoveDirVec, record)
        }
    }
]

func layOutAxisTickLabel(
    _ cfg: AxisBuilderCfgDetermined,
    _ local: AxisBuilderLocalContext,
    _ shared: AxisBuilderSharedContext,
    _ axisModel: AxisBaseModel,
    _ group: Group,
    _ transformGroup: Group,
    _ api: ExtensionAPI,
    _ kind: Double
) {
    if !axisLabelBuildResultExists(local) {
        buildAxisLabel(cfg, local, group, kind, axisModel, api)
    }

    let labelLayoutList = local.labelLayoutList

    updateAxisLabelChangableProps(cfg, axisModel, labelLayoutList, transformGroup)

    // upstream: adjustBreakLabels(axisModel, cfg.rotation, labelLayoutList). A break contributes TWO
    //   boundary tick labels (the `vmin` at the break's start and the `vmax` at its end) that map to
    //   nearly the same pixel; both are forced highest-priority so `hideOverlap` keeps both. Without this
    //   de-overlap pass they render stacked → garbled. Runs BEFORE fixMinMaxLabelShow / hideOverlap.
    adjustBreakLabels(axisModel, cfg.rotation, labelLayoutList)

    let optionHideOverlap = cfg.optionHideOverlap

    // Runs UNCONDITIONALLY (independent of `optionHideOverlap`): force-shows / hides the first & last
    //   tick labels per `axisLabel.showMinLabel` / `showMaxLabel`, and resolves their overlap with the
    //   inner neighbour. Must run before `hideOverlap` so the latter filters the labels it ignores.
    fixMinMaxLabelShow(axisModel, labelLayoutList, optionHideOverlap)

    if truthy(optionHideOverlap) {
        // This bit fixes the label overlap issue for the time chart and dense category axes.
        // See https://github.com/apache/echarts/issues/14266 for more.
        labelLayoutHelper.hideOverlap(
            // Filter the already ignored labels by the previous overlap resolving methods.
            util.filter(labelLayoutList, { layout, _ in !layout.label.ignore })
        )
    }

    // Always call it even this axis has no name, since it serves in overlapping detection
    // and grid outerBounds on other axis.
    // PORT-NOTE: `local.labelLayoutList` is optional here (upstream's is always an array by this point).
    resetOverlapRecordToShared(cfg, shared, axisModel, labelLayoutList ?? [])
}

// upstream: function adjustBreakLabels(axisModel, axisRotation, labelLayoutList)  (AxisBuilder.ts)
//   Pair up each break's two boundary labels (`retrieveAxisBreakPairs`, matching a `vmin` tick to its
//   `vmax` tick by break option), then, unless `breakLabelLayout.moveOverlap` is turned off, spread each
//   overlapping pair apart via `adjustBreakLabelPair`.
func adjustBreakLabels(
    _ axisModel: AxisBaseModel,
    _ axisRotation: Double,
    _ labelLayoutList: [LabelLayoutData]?
) {
    guard let labelLayoutList = labelLayoutList else { return }
    guard let scaleBreakHelper = getScaleBreakHelper() else { return }

    // getVisualAxisBreak: `layoutInfo && getLabelInner(layoutInfo.label).labelInfo.tick.break`.
    let breakLabelIndexPairs = scaleBreakHelper.retrieveAxisBreakPairs(
        labelLayoutList,
        { (layoutInfo: LabelLayoutData) -> VisualAxisBreak? in
            return getLabelInner(layoutInfo.label).labelInfo?.tick.break
        },
        true
    )

    // axisModel.get(['breakLabelLayout', 'moveOverlap'], true) — default `true`; move on `true`|'auto'.
    let moveOverlapRaw = axisModel.get(["breakLabelLayout", "moveOverlap"])
    let moveOverlap: Bool
    if let b = moveOverlapRaw as? Bool { moveOverlap = b }
    else if let s = moveOverlapRaw as? String { moveOverlap = (s == "auto") }
    else if moveOverlapRaw == nil || moveOverlapRaw is NSNull { moveOverlap = true }   // default
    else { moveOverlap = false }

    if moveOverlap {
        let axisInverse = (axisModel.axis as? Axis)?.inverse ?? false
        for idxPairAny in breakLabelIndexPairs {
            guard idxPairAny.count == 2,
                  let i0 = idxPairAny[0] as? Int, let i1 = idxPairAny[1] as? Int,
                  i0 >= 0, i0 < labelLayoutList.count, i1 >= 0, i1 < labelLayoutList.count else { continue }
            adjustBreakLabelPair(axisInverse, axisRotation, [
                labelLayoutHelper.ensureLabelLayoutWithGeometry(labelLayoutList[i0]),
                labelLayoutHelper.ensureLabelLayoutWithGeometry(labelLayoutList[i1])
            ])
        }
    }
}

// upstream: function adjustBreakLabelPair(axisInverse, axisRotation, layoutPair)  (axisBreakHelperImpl.ts)
//   `layoutPair` is `[break_min_label, break_max_label]`. If they overlap (OBB test with the minimum
//   translation vector `mtv` along the axis), distribute `mtv` between them by a ratio `k` chosen to keep
//   the text gap centered on the break, then translate each label. PORT-NOTE: upstream reaches this via
//   `getAxisBreakHelper()!.adjustBreakLabelPair`; that registry accessor is a nil stub in this port
//   (component-side axisBreakHelper is otherwise unported), so it is called directly.
private func adjustBreakLabelPair(
    _ axisInverse: Bool,
    _ axisRotation: Double,
    _ layoutPair: [LabelLayoutData?]
) {
    // if (find(layoutPair, item => !item)) return;
    guard let pair0 = layoutPair[0], let pair1 = layoutPair[1] else { return }

    let mtv = Point()
    // The axisRotation indicates mtv direction of OBB intersecting.
    let direction = -(axisInverse ? axisRotation + Double.pi : axisRotation)
    if !labelLayoutHelper.labelIntersect(
        pair0, pair1, mtv,
        BoundingRectIntersectOpt(direction: direction, bidirectional: false, touchThreshold: 0)
    ) {
        return
    }

    // Rotate axis back to (1, 0) direction, to be a standard axis.
    let axisStTrans = matrix.rotate(matrix.create(), -axisRotation)

    // map(layoutPair, layout => layout.transform ? mul(create(), axisStTrans, layout.transform) : axisStTrans)
    func stTrans(_ layout: LabelLayoutData) -> MatrixArray {
        if let t = layout.transform { return matrix.mul(axisStTrans, t) }
        return axisStTrans
    }
    let labelPairStTrans = [stTrans(pair0), stTrans(pair1)]

    // WH = ['width', 'height']; localRect[WH[whIdx]] → width (0) / height (1).
    func localRectWH(_ rect: BoundingRect, _ whIdx: Int) -> Double {
        return whIdx == 0 ? rect.width : rect.height
    }
    func isParallelToAxis(_ whIdx: Int) -> Bool {
        // Assert label[0] and label[1] has the same rotation, so only use [0].
        let localRect = pair0.localRect ?? BoundingRect(0, 0, 0, 0)
        let wh = localRectWH(localRect, whIdx)
        let labelVec0 = Point(wh * labelPairStTrans[0][0], wh * labelPairStTrans[0][1])
        return abs(labelVec0.y) < 1e-5
    }

    // If overlapping, move pair[0]/pair[1] apart. `k` distributes mtv so the gap sits centered on the break.
    var k = 0.5

    if isParallelToAxis(0) || isParallelToAxis(1) {
        // rectSt = map(layoutPair, (layout, idx) => layout.localRect.clone().applyTransform(labelPairStTrans[idx]))
        let rectSt: [BoundingRect] = [pair0, pair1].enumerated().map { idx, layout in
            let rect = (layout.localRect ?? BoundingRect(0, 0, 0, 0)).clone()
            rect.applyTransform(labelPairStTrans[idx])
            return rect
        }

        // brkCenterSt = ((pair0.label + pair1.label) * 0.5).transform(axisStTrans)
        let brkCenterSt = Point(
            (pair0.label.x + pair1.label.x) * 0.5,
            (pair0.label.y + pair1.label.y) * 0.5
        )
        brkCenterSt.transform(axisStTrans)

        let mtvSt = mtv.clone()
        mtvSt.transform(axisStTrans)

        let insidePtSum = rectSt[0].x + rectSt[1].x
            + (mtvSt.x >= 0 ? rectSt[0].width : rectSt[1].width)
        let qval = (insidePtSum + mtvSt.x) / 2 - brkCenterSt.x
        let uvalMin = Swift.min(qval, qval - mtvSt.x)
        let uvalMax = Swift.max(qval, qval - mtvSt.x)
        let uval = uvalMax < 0 ? uvalMax : (uvalMin > 0 ? uvalMin : 0)
        k = (qval - uval) / mtvSt.x
    }

    let delta0 = Point()
    let delta1 = Point()
    Point.scale(delta0, mtv, -k)
    Point.scale(delta1, mtv, 1 - k)
    labelLayoutHelper.labelLayoutApplyTranslation(pair0, delta0)
    labelLayoutHelper.labelLayoutApplyTranslation(pair1, delta1)
}

func endTextLayout(
    _ rotation: Double, _ textPosition: String?, _ textRotate: Double, _ extent: [Double]
) -> (rotation: Double, textAlign: ZRTextAlign, textVerticalAlign: ZRTextVerticalAlign) {
    let rotationDiff = number.remRadian(textRotate - rotation)
    var textAlign: ZRTextAlign
    var textVerticalAlign: ZRTextVerticalAlign
    let inverse = extent[0] > extent[1]
    let onLeft = (textPosition == "start" && !inverse)
        || (textPosition != "start" && inverse)

    if number.isRadianAroundZero(rotationDiff - PI / 2) {
        textVerticalAlign = onLeft ? .bottom : .top
        textAlign = .center
    }
    else if number.isRadianAroundZero(rotationDiff - PI * 1.5) {
        textVerticalAlign = onLeft ? .top : .bottom
        textAlign = .center
    }
    else {
        textVerticalAlign = .middle
        if rotationDiff < PI * 1.5 && rotationDiff > PI / 2 {
            textAlign = onLeft ? .left : .right
        }
        else {
            textAlign = onLeft ? .right : .left
        }
    }

    return (rotation: rotationDiff, textAlign: textAlign, textVerticalAlign: textVerticalAlign)
}

/// Assume `labelLayoutList` has no `label.ignore: true`.
/// Assume `labelLayoutList` have been sorted by value ascending order.
func fixMinMaxLabelShow(
    _ axisModel: AxisBaseModel,
    _ labelLayoutList: [LabelLayoutData]?,
    _ optionHideOverlap: Any?  // AxisBaseOption['axisLabel']['hideOverlap']
) {
    guard let labelLayoutList = labelLayoutList else { return }
    let axis = axisModel.axis as! Axis
    let customValuesOption = axisModel.get(["axisLabel", "customValues"])

    if axisHelper.shouldShowAllLabels(axis) {
        return
    }

    // FIXME
    // Have not consider onBand yet, where tick els is more than label els.
    // Assert no ignore in labels.

    func deal(
        _ showMinMaxLabelOption: Any?,  // AxisShowMinMaxLabelOption (boolean | NullUndefined)
        _ outmostLabelIdx: Int,
        _ innerLabelIdx: Int
    ) {
        // upstream indexes with `labelsLen - 1` / `labelsLen - 2`, which can go out of range (an empty
        //   or single-label list). JS yields `undefined` there → `ensureLabelLayoutWithGeometry` returns
        //   `undefined` → the guard below returns. Mirror that with a bounds-checked lookup.
        let outmostSrc = (outmostLabelIdx >= 0 && outmostLabelIdx < labelLayoutList.count)
            ? labelLayoutList[outmostLabelIdx] : nil
        let innerSrc = (innerLabelIdx >= 0 && innerLabelIdx < labelLayoutList.count)
            ? labelLayoutList[innerLabelIdx] : nil
        var outmostLabelLayout = labelLayoutHelper.ensureLabelLayoutWithGeometry(outmostSrc)
        var innerLabelLayout = labelLayoutHelper.ensureLabelLayoutWithGeometry(innerSrc)
        let scale = axis.scale
        guard let outmostLL = outmostLabelLayout, let innerLL = innerLabelLayout else {
            return
        }
        if showMinMaxLabelOption == nil || showMinMaxLabelOption is NSNull {
            if !truthy(optionHideOverlap) && truthy(customValuesOption) {
                // In this case, users are unlikely to expect labels to be hidden.
                return
            }
            let tick = getLabelInner(outmostLL.label).labelInfo.tick
            if // TimeScale does not expand extent to "nice", so eliminate labels that are not nice.
                (helper.isTimeScale(scale) && (tick.notNice ?? false))
                // Category axis does not expect tick that out of axisLabel.internal to be displayed
                // unless required.
                || (helper.isOrdinalScale(scale) && (tick.offInterval ?? false)) {
                ignoreEl(outmostLL.label)
                return
            }
        }

        if (showMinMaxLabelOption as? Bool) == false || outmostLL.suggestIgnore {
            ignoreEl(outmostLL.label)
            return
        }
        if innerLL.suggestIgnore {
            ignoreEl(innerLL.label)
            return
        }
        // PENDING: Originally we thought `optionHideOverlap === false` means do not hide anything,
        //  since currently the bounding rect of text might not accurate enough and might slightly bigger,
        //  which causes false positive. But `optionHideOverlap: null/undfined` is falsy and likely
        //  be treated as false.

        // In most fonts the glyph does not reach the boundary of the bounding rect.
        // This is needed to avoid too aggressive to hide two elements that meet at the edge
        // due to compact layout by the same bounding rect or OBB.
        let touchThreshold = 0.1
        // This treatment is for backward compatibility. And `!optionHideOverlap` implies that
        // the user accepts the visual touch between adjacent labels, thus "hide min/max label"
        // should be conservative, since the space might be sufficient in this case.
        if !truthy(optionHideOverlap) {
            let marginForce: [Double?] = [0, 0, 0, 0]
            // Make a copy to apply `ignoreMargin`.
            outmostLabelLayout = labelLayoutHelper.newLabelLayoutWithGeometry(
                labelLayoutHelper.ComputeLabelGeometryOpt(marginForce: marginForce), outmostLL
            )
            innerLabelLayout = labelLayoutHelper.newLabelLayoutWithGeometry(
                labelLayoutHelper.ComputeLabelGeometryOpt(marginForce: marginForce), innerLL
            )
        }
        if labelLayoutHelper.labelIntersect(
            outmostLabelLayout, innerLabelLayout, nil,
            BoundingRectIntersectOpt(touchThreshold: touchThreshold)
        ) {
            if truthy(showMinMaxLabelOption) {
                ignoreEl(innerLabelLayout?.label)
            }
            else {
                ignoreEl(outmostLabelLayout?.label)
            }
        }
    }

    // If min or max are user set, we need to check
    // If the tick on min(max) are overlap on their neighbour tick
    // If they are overlapped, we need to hide the min(max) tick label
    let showMinLabelOption = axisModel.get(["axisLabel", "showMinLabel"])
    let showMaxLabelOption = axisModel.get(["axisLabel", "showMaxLabel"])
    let labelsLen = labelLayoutList.count
    deal(showMinLabelOption, 0, 1)
    deal(showMaxLabelOption, labelsLen - 1, labelsLen - 2)
}

// Under default settings, it is visually odd to display a tick without its label ...
func syncLabelIgnoreToMajorTicks(
    _ cfg: AxisBuilderCfgDetermined,
    _ labelLayoutList: [LabelLayoutData]?,
    _ tickEls: [Line]
) {
    if cfg.showMinorTicks {
        // It probably unreasonable to hide major ticks when show minor ticks.
        return
    }
    util.each(labelLayoutList, { labelLayout, _ in
        if labelLayout.label.ignore {
            for idx in 0..<tickEls.count {
                let tickEl = tickEls[idx]
                // Assume small array, linear search is fine for performance.
                let tickInner = getTickInner(tickEl)
                let labelInner = getLabelInner(labelLayout.label)
                if tickInner.tickValue != nil
                    && !(tickInner.onBand ?? false)
                    && tickInner.tickValue == labelInner.labelInfo.tick.value {
                    ignoreEl(tickEl)
                    return
                }
            }
        }
    })
}

func ignoreEl(_ el: Element?) {
    if let el = el { el.ignore = true }
}

func createTicks(
    _ ticksCoords: [AxisTickCoord],
    _ tickTransform: MatrixArray?,
    _ tickEndCoord: Double,
    _ tickLineStyle: PathStyleProps,
    _ anidPrefix: String
) -> [Line] {
    var tickEls: [Line] = []
    var pt1 = VectorArray(0, 0)
    var pt2 = VectorArray(0, 0)
    for i in 0..<ticksCoords.count {
        let tickCoord = ticksCoords[i].coord

        pt1[0] = tickCoord
        pt1[1] = 0
        pt2[0] = tickCoord
        pt2[1] = tickEndCoord

        if let tickTransform = tickTransform {
            pt1 = vector.applyTransform(pt1, tickTransform)
            pt2 = vector.applyTransform(pt2, tickTransform)
        }
        // Tick line, Not use group transform to have better line draw
        let tickEl = Line([
            "shape": lineShapeOf(pt1[0], pt1[1], pt2[0], pt2[1]),
            "style": tickLineStyle,
            "z2": Double(2),
            "autoBatch": true,
            "silent": true
        ])
        // upstream: graphic.subPixelOptimizeLine(tickEl.shape, tickEl.style.lineWidth)
        if let optimized = subPixelOptimizeNS.subPixelOptimizeLine(
            subPixelOptimizeNS.LineShape(x1: pt1[0], y1: pt1[1], x2: pt2[0], y2: pt2[1]),
            tickEl.pathStyle
        ) {
            tickEl.shape = lineShapeOf(optimized.x1, optimized.y1, optimized.x2, optimized.y2)
        }
        tickEl.anid = anidPrefix + "_" + String(ticksCoords[i].tickValue)
        tickEls.append(tickEl)

        let inner = getTickInner(tickEl)
        inner.onBand = ticksCoords[i].onBand ?? false
        inner.tickValue = ticksCoords[i].tickValue
    }
    return tickEls
}

func buildAxisMajorTicks(
    _ cfg: AxisBuilderCfgDetermined,
    _ group: Group,
    _ transformGroup: Group,
    _ axisModel: AxisBaseModel
) -> [Line] {
    let axis = axisModel.axis as! Axis

    let tickModel = axisModel.getModel("axisTick")

    var shown = tickModel.get("show")
    if (shown as? String) == "auto" {
        shown = true
        if cfg.raw.axisTickAutoShow != nil {
            shown = cfg.raw.axisTickAutoShow!
        }
    }
    if !truthy(shown) || axis.scale.isBlank() {
        return []
    }

    let lineStyleModel = tickModel.getModel("lineStyle")
    let tickEndCoord = cfg.tickDirection * (axisOptionDouble(tickModel.get("length")) ?? 0)

    let ticksCoords = axis.getTicksCoords()

    // upstream: defaults(lineStyleModel.getLineStyle(), { stroke: axisModel.get(['axisLine','lineStyle','color']) })
    var tickLineStyleDict = lineStyleModel.getLineStyle()
    if tickLineStyleDict["stroke"] == nil {
        tickLineStyleDict["stroke"] = axisModel.get(["axisLine", "lineStyle", "color"])
    }
    let ticksEls = createTicks(ticksCoords, transformGroup.transform, tickEndCoord,
        pathStyleFromLineStyleDict(tickLineStyleDict), "ticks")

    for i in 0..<ticksEls.count {
        _ = group.add(ticksEls[i])
    }

    return ticksEls
}

func buildAxisMinorTicks(
    _ cfg: AxisBuilderCfgDetermined,
    _ group: Group,
    _ transformGroup: Group,
    _ axisModel: AxisBaseModel,
    _ tickDirection: Double
) {
    let axis = axisModel.axis as! Axis

    let minorTickModel = axisModel.getModel("minorTick")

    if !cfg.showMinorTicks || axis.scale.isBlank() {
        return
    }

    let minorTicksCoords = axis.getMinorTicksCoords()
    if minorTicksCoords.isEmpty {
        return
    }

    let lineStyleModel = minorTickModel.getModel("lineStyle")
    let tickEndCoord = tickDirection * (axisOptionDouble(minorTickModel.get("length")) ?? 0)

    // upstream: defaults(lineStyleModel.getLineStyle(), defaults(axisModel.getModel('axisTick').getLineStyle(),
    //   { stroke: axisModel.get(['axisLine','lineStyle','color']) }))
    var minorTickLineStyleDict = lineStyleModel.getLineStyle()
    let axisTickLineStyle = axisModel.getModel("axisTick").getLineStyle()
    for (k, v) in axisTickLineStyle where minorTickLineStyleDict[k] == nil {
        minorTickLineStyleDict[k] = v
    }
    if minorTickLineStyleDict["stroke"] == nil {
        minorTickLineStyleDict["stroke"] = axisModel.get(["axisLine", "lineStyle", "color"])
    }
    let minorTickLineStyle = pathStyleFromLineStyleDict(minorTickLineStyleDict)

    for i in 0..<minorTicksCoords.count {
        let minorTicksEls = createTicks(
            minorTicksCoords[i], transformGroup.transform, tickEndCoord, minorTickLineStyle, "minorticks_" + String(i)
        )
        for k in 0..<minorTicksEls.count {
            _ = group.add(minorTicksEls[k])
        }
    }
}

// Return whether need to call `layOutAxisTickLabel` again.
func dealLastTickLabelResultReusable(
    _ local: AxisBuilderLocalContext,
    _ group: Group,
    _ extraParams: AxisBuilderBuildExtraParams
) -> Bool {
    if axisLabelBuildResultExists(local) {
        let axisLabelsCreationContext = local.axisLabelsCreationContext!
        let noPxChangeTryDetermine = axisLabelsCreationContext.out.noPxChangeTryDetermine
        if extraParams.noPxChange == true {
            var canDetermine = true
            for idx in 0..<noPxChangeTryDetermine.count {
                canDetermine = canDetermine && noPxChangeTryDetermine[idx]()
            }
            if canDetermine {
                return false
            }
        }
        if !noPxChangeTryDetermine.isEmpty {
            // Remove the result of `buildAxisLabel`
            if let labelGroup = local.labelGroup {
                _ = group.remove(labelGroup)
            }
            axisLabelBuildResultSet(local, nil, nil, nil)
        }
    }
    return true
}

func buildAxisLabel(
    _ cfg: AxisBuilderCfgDetermined,
    _ local: AxisBuilderLocalContext,
    _ group: Group,
    _ kind: Double,
    _ axisModel: AxisBaseModel,
    _ api: ExtensionAPI
) {
    let axis = axisModel.axis as! Axis
    // upstream: retrieve(cfg.raw.axisLabelShow, axisModel.get(['axisLabel', 'show']))
    let showAny: Any? = cfg.raw.axisLabelShow ?? axisModel.get(["axisLabel", "show"])
    let labelGroup = Group()
    _ = group.add(labelGroup)
    let axisLabelCreationCtx = createAxisLabelsComputingContext(kind)

    if !truthy(showAny) || axis.scale.isBlank() {
        axisLabelBuildResultSet(local, [], labelGroup, axisLabelCreationCtx)
        return
    }

    let labelModel = axisModel.getModel("axisLabel")
    let labels = axis.getViewLabels(axisLabelCreationCtx)

    // Special label rotate.
    let labelRotation = (
        (cfg.raw.labelRotate ?? (labelModel.get("rotate") as? Double)) ?? 0
    ) * PI / 180

    let labelLayout = AxisBuilder.innerTextLayout(cfg.rotation, labelRotation, cfg.labelDirection)
    // upstream: const rawCategoryData = axisModel.getCategories && axisModel.getCategories(true);
    let rawCategoryData = axisModel.getCategories(true)

    var labelEls: [ZRText] = []
    let triggerEvent = truthy(axisModel.get("triggerEvent"))
    var z2Min = Double.infinity
    var z2Max = -Double.infinity

    util.each(labels, { labelItem, index in
        let labelItemTick = labelItem.tick
        let formattedLabel = labelItem.formattedLabel
        let rawLabel = labelItem.rawLabel

        var itemLabelModel = labelModel
        let tickValue = axisHelper.getTickValueOutermost(axis.scale, labelItemTick)
        // upstream: if (rawCategoryData && rawCategoryData[tickValue]) {
        //   const rawCategoryItem = rawCategoryData[tickValue];
        //   if (isObject(rawCategoryItem) && rawCategoryItem.textStyle) {
        //     itemLabelModel = new Model(rawCategoryItem.textStyle, labelModel, axisModel.ecModel);
        //   }
        // }
        if let rawCategoryData = rawCategoryData {
            let tvIdx = Int(tickValue)
            if tvIdx >= 0 && tvIdx < rawCategoryData.count {
                let rawCategoryItem = rawCategoryData[tvIdx]
                if util.isObject(rawCategoryItem),
                   let textStyle = (rawCategoryItem as? [String: Any])?["textStyle"] {
                    itemLabelModel = Model(textStyle, labelModel, axisModel.ecModel)
                }
            }
        }

        // upstream: itemLabelModel.getTextColor() || axisModel.get(['axisLine', 'lineStyle', 'color'])
        // POTENTIAL-BUG: upstream `textColor` may be a function (per-label color callback). `ColorString`
        //   is `String` in this port, so the `isFunction(textColor)` branch is not representable — a
        //   function-form color is silently dropped and the plain string color is used.
        let textColor = itemLabelModel.getTextColor()
            ?? (axisModel.get(["axisLine", "lineStyle", "color"]) as? ColorString)

        let align = (itemLabelModel.getShallow("align", true) as? String).flatMap { TextAlign(rawValue: $0) }
            ?? labelLayout.textAlign
        let alignMin = (itemLabelModel.getShallow("alignMinLabel", true) as? String).flatMap { TextAlign(rawValue: $0) }
            ?? align
        let alignMax = (itemLabelModel.getShallow("alignMaxLabel", true) as? String).flatMap { TextAlign(rawValue: $0) }
            ?? align

        let verticalAlign = (itemLabelModel.getShallow("verticalAlign", true) as? String).flatMap { TextVerticalAlign(rawValue: $0) }
            ?? (itemLabelModel.getShallow("baseline", true) as? String).flatMap { TextVerticalAlign(rawValue: $0) }
            ?? labelLayout.textVerticalAlign
        let verticalAlignMin = (itemLabelModel.getShallow("verticalAlignMinLabel", true) as? String).flatMap { TextVerticalAlign(rawValue: $0) }
            ?? verticalAlign
        let verticalAlignMax = (itemLabelModel.getShallow("verticalAlignMaxLabel", true) as? String).flatMap { TextVerticalAlign(rawValue: $0) }
            ?? verticalAlign
        let z2 = 10 + (labelItemTick.time?.level ?? 0)
        z2Min = Swift.min(z2Min, z2)
        z2Max = Swift.max(z2Max, z2)

        let textEl = ZRText([
            // --- transform props start ---
            // All of the transform props MUST not be set here, but should be set in
            // `updateAxisLabelChangableProps` (see upstream comment).
            "x": Double(0),
            "y": Double(0),
            "rotation": Double(0),
            // --- transform props end ---

            "silent": AxisBuilder.isLabelSilent(axisModel),
            "z2": z2,
            "style": createTextStyle(
                itemLabelModel,
                text: formattedLabel,
                fill: textColor,
                align: index == 0
                    ? alignMin
                    : index == labels.count - 1 ? alignMax : align,
                verticalAlign: index == 0
                    ? verticalAlignMin
                    : index == labels.count - 1 ? verticalAlignMax : verticalAlign
            )
        ])

        textEl.anid = "label_" + String(tickValue)

        let inner = getLabelInner(textEl)
        inner.labelInfo = labelItem
        inner.layoutRotation = labelLayout.rotation

        // PORT-NOTE (deferred): graphic.setTooltipConfig (tooltip + truncation params) not wired on axis labels.
        //   SCOPE: owned by SYMBOLS.tsv row 37 (`util/graphic.setTooltipConfig`), which enumerates this
        //   call site — left to that lane to avoid a two-lane edit of the same hunk.

        // Pack data for mouse event
        if triggerEvent {
            var eventData = AxisBuilder.makeAxisEventDataBase(axisModel)
            eventData["targetType"] = "axisLabel"
            eventData["value"] = rawLabel
            eventData["tickIndex"] = index
            if let labelItemTickBreak = labelItemTick.break {
                let parsedBreak = labelItemTickBreak.parsedBreak
                eventData["break"] = [
                    "start": parsedBreak.vmin,
                    "end": parsedBreak.vmax
                ]
            }
            if axis.type == "category" {
                eventData["dataIndex"] = tickValue
            }
            innerStore.getECData(textEl).eventData = eventData
            // PORT-NOTE (deferred): addBreakEventHandler (break-expand click → dispatchAction
            //   AXIS_BREAK_EXPAND) requires the unported `axisAction` module.
        }

        labelEls.append(textEl)
        _ = labelGroup.add(textEl)
    })

    let labelLayoutList = util.map(labelEls, { label, _ -> LabelLayoutData in
        // upstream: priority = tick.break ? label.z2 + (z2Max - z2Min + 1) : label.z2
        let priority = getLabelInner(label).labelInfo.tick.break != nil
            ? label.z2 + (z2Max - z2Min + 1) // Make break labels be highest priority.
            : label.z2
        let d = LabelLayoutData(label: label, priority: priority)
        d.defaultAttr.ignore = label.ignore
        return d
    })

    axisLabelBuildResultSet(local, labelLayoutList, labelGroup, axisLabelCreationCtx)
}

// Indicate that `layOutAxisTickLabel` has been called.
func axisLabelBuildResultExists(_ local: AxisBuilderLocalContext) -> Bool {
    return local.labelLayoutList != nil
}
func axisLabelBuildResultSet(
    _ local: AxisBuilderLocalContext,
    _ labelLayoutList: [LabelLayoutData]?,
    _ labelGroup: Group?,
    _ axisLabelsCreationContext: AxisLabelsComputingContext?
) {
    // Ensure the same lifetime.
    local.labelLayoutList = labelLayoutList
    local.labelGroup = labelGroup
    local.axisLabelsCreationContext = axisLabelsCreationContext
}

func updateAxisLabelChangableProps(
    _ cfg: AxisBuilderCfgDetermined,
    _ axisModel: AxisBaseModel,
    _ labelLayoutList: [LabelLayoutData]?,
    _ transformGroup: Group
) {
    // Dynamic option numbers may be boxed as either Int or Double. The default axis option uses
    // the integer literal `margin: 8`, so a Double-only cast silently collapsed the default margin
    // to zero and placed every cartesian axis label directly against its axis line.
    let labelMargin = axisOptionDouble(axisModel.get(["axisLabel", "margin"])) ?? 0
    util.each(labelLayoutList, { layout, _ in
        guard let geometry = labelLayoutHelper.ensureLabelLayoutWithGeometry(layout) else {
            return
        }
        let labelEl = geometry.label
        let inner = getLabelInner(labelEl)

        // See the comment in `suggestIgnore`.
        geometry.suggestIgnore = labelEl.ignore
        // Currently no `ignore:true` is set in `buildAxisLabel`
        // But `ignore:true` may be set subsequently for overlap handling, thus reset it here.
        labelEl.ignore = false

        _ = copyTransform(_tmpLayoutEl, _tmpLayoutElReset)
        let axis = axisModel.axis as! Axis
        _tmpLayoutEl.x = axis.dataToCoord(axisHelper.getTickValueOutermost(axis.scale, inner.labelInfo.tick))
        _tmpLayoutEl.y = cfg.labelOffset + cfg.labelDirection * labelMargin
        _tmpLayoutEl.rotation = inner.layoutRotation

        _ = transformGroup.add(_tmpLayoutEl)
        _tmpLayoutEl.updateTransform()
        _ = transformGroup.remove(_tmpLayoutEl)
        _tmpLayoutEl.decomposeTransform()

        _ = copyTransform(labelEl, _tmpLayoutEl)
        labelEl.markRedraw()

        // Re-dirty and recompute the geometry now that the label carries its final transform, so the
        //   subsequent `hideOverlap` pass reads up-to-date global rects / OBBs.
        labelLayoutHelper.setLabelLayoutDirty(geometry, true)
        labelLayoutHelper.ensureLabelLayoutWithGeometry(geometry)
    })
}
let _tmpLayoutEl = Rect()
let _tmpLayoutElReset = Rect()

func hasAxisName(_ axisName: String?) -> Bool {
    // upstream: return !!axisName;
    return axisName != nil && !axisName!.isEmpty
}

// PORT-NOTE (deferred): `addBreakEventHandler` (click → dispatchAction AXIS_BREAK_EXPAND) requires the
//   `axisAction` module (break-expand action, not ported).

// PORT-NOTE (deferred): `adjustBreakLabels` requires the optional `axisBreakHelper` break renderer
//   (adjustBreakLabelPair; getAxisBreakHelper() is nil in this port), atop the ported `scale/break`.

// upstream: export default AxisBuilder;  -> `public final class AxisBuilder` above.


// ============================================================================
// PORT-NOTE helpers — NOT part of AxisBuilder.ts upstream. These reproduce the
// out-of-phase sibling APIs referenced above so line+ticks+labels compile and
// render. Delete each when its real sibling lands and call the sibling directly.
// ============================================================================

/// JS truthiness for the dynamic option bag (`if (x)` / `!x` on `get(...)` results).
/// (CONVENTIONS §6: replicate JS truthiness explicitly for numbers/strings.)
private func truthy(_ v: Any?) -> Bool {
    guard let v = v else { return false }
    if v is NSNull { return false }   // JS `null` is falsy (option defaults box null as NSNull).
    if let b = v as? Bool { return b }
    if let d = v as? Double { return d != 0 && !d.isNaN }
    if let i = v as? Int { return i != 0 }
    if let s = v as? String { return !s.isEmpty }
    return true
}

/// Numeric coercion for values read from the dynamic option bag.
///
/// Swift preserves the concrete type of numeric literals stored in `[String: Any]`, unlike
/// JavaScript's single Number type. Accept the representations produced by defaults, callers and
/// JSON deserialization so layout values do not disappear solely because of their boxing.
private func axisOptionDouble(_ value: Any?) -> Double? {
    if let value = value as? Double { return value }
    if let value = value as? Int { return Double(value) }
    if let value = value as? NSNumber { return value.doubleValue }
    return nil
}

/// Build the ZRenderKit `LineShape` (graphic shape) from x1/y1/x2/y2.
func lineShapeOf(_ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double) -> LineShape {
    var s = LineShape()
    s.x1 = x1; s.y1 = y1; s.x2 = x2; s.y2 = y2
    return s
}

/// PORT-NOTE (deferred cleanup): the generic `util/graphic` `useStyle` dict→style bridge is not used
///   here. Maps the dynamic `getLineStyle()`/`defaults(...)` style bag ([String: Any], keys per
///   LINE_STYLE_KEY_MAP) onto the typed `PathStyleProps`. Delete when the graphic style bridge lands.
func pathStyleFromLineStyleDict(_ dict: [String: Any]) -> PathStyleProps {
    var s = PathStyleProps()
    if let stroke = dict["stroke"] as? String { s.stroke = .string(stroke) }
    if let lineWidth = dict["lineWidth"] as? Double { s.lineWidth = lineWidth }
    if let lineCap = dict["lineCap"] as? String { s.lineCap = lineCap }
    if let lineJoin = dict["lineJoin"] as? String { s.lineJoin = lineJoin }
    if let opacity = dict["opacity"] as? Double { s.opacity = opacity }
    if let shadowBlur = dict["shadowBlur"] as? Double { s.shadowBlur = shadowBlur }
    if let shadowOffsetX = dict["shadowOffsetX"] as? Double { s.shadowOffsetX = shadowOffsetX }
    if let shadowOffsetY = dict["shadowOffsetY"] as? Double { s.shadowOffsetY = shadowOffsetY }
    if let shadowColor = dict["shadowColor"] as? String { s.shadowColor = shadowColor }
    if let lineDashOffset = dict["lineDashOffset"] as? Double { s.lineDashOffset = lineDashOffset }
    if let miterLimit = dict["miterLimit"] as? Double { s.miterLimit = miterLimit }
    // upstream `lineDash?: false | number[] | 'solid' | 'dashed' | 'dotted'` → the `LineDash` enum.
    if let dash = dict["lineDash"] {
        if let arr = dash as? [Double] {
            s.lineDash = .values(arr)
        }
        else if let arr = dash as? [Any] {
            s.lineDash = .values(arr.compactMap { $0 as? Double })
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

/// Local keyword-arg convenience shim mirroring the subset of `label/labelStyle.createTextStyle` AxisBuilder
///   needs. Only text/font/align/verticalAlign/fill/overflow/width/ellipsis are populated; the full
///   rich-text / state / ecModel-driven behavior lives in `LabelStyle.createTextStyle` (labelStyle.swift:417,
///   now ported). Deferred cleanup: rewire the two axis call sites to the ported `opt`-dict signature and drop
///   this shim.
func createTextStyle(
    _ textStyleModel: Model,
    text: String? = nil,
    font: String? = nil,
    overflow: String? = nil,
    width: Double? = nil,
    ellipsis: String? = nil,
    fill: String? = nil,
    align: TextAlign? = nil,
    verticalAlign: TextVerticalAlign? = nil
) -> TextStyleProps {
    var style = TextStyleProps()
    style.text = text
    style.font = font ?? textStyleModel.getFont()
    style.fill = fill
    style.align = align
    style.verticalAlign = verticalAlign
    style.overflow = overflow
    style.width = width   // TextStyleProps.width is narrowed to Double? in this port
    style.ellipsis = ellipsis
    // Rich-text token styles (e.g. `axisLabel.rich`). This convenience shim otherwise drops `rich`, so a
    //   `{tag|…}` formatter (the bar-race flag emoji: `value + '{flag|' + emoji + '}'`) rendered its
    //   markup LITERALLY. Reuse the fully-ported rich builder (`LabelStyle.setTextStyleCommon` →
    //   getRichItemNames + setTokenTextStyle) on a throwaway probe and copy just `.rich` across, so the
    //   `{flag|…}` tag parses into the `rich.flag` style. Gated on `rich` being present, so a plain
    //   axisLabel keeps the untouched plain-text fast path (probe.rich stays nil → style.rich stays nil).
    if textStyleModel.get("rich") != nil {
        var probe = TextStyleProps()
        labelStyle.setTextStyleCommon(&probe, textStyleModel)
        style.rich = probe.rich
    }
    return style
}

// `LabelLayoutData` now lives in `label/labelLayoutHelper.swift` (the real OBB-carrying type landed
//   in the L2c pass). The axis label path now calls the REAL `labelLayoutHelper.ensureLabelLayoutWithGeometry`
//   directly (see `updateAxisLabelChangableProps` / `layOutAxisTickLabel`): geometry is computed with
//   the initial transform, then re-dirtied + recomputed after `copyTransform` sets the final transform,
//   so the `hideOverlap` overlap-resolution pass reads accurate global rects / OBBs. The old identity
//   shim was removed.
