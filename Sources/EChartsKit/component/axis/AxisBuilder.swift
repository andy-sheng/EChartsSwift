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
//     → PORT-TODO: `util/graphic` NOT ported yet. `graphic.Group/Line/Text/Rect` are the ZRenderKit
//       scene-graph types used directly (`Group`, `Line`, `ZRText`, `Rect`); `graphic.subPixelOptimizeLine`
//       → `subPixelOptimizeNS.subPixelOptimizeLine`; `graphic.setTooltipConfig` → deferred (see PORT-TODO).
//   import {getECData} from '../../util/innerStore';                    → `innerStore.getECData` (deferred; event wiring)
//   import {createTextStyle} from '../../label/labelStyle';
//     → `label/labelStyle.swift` IS ported (`LabelStyle.createTextStyle`, labelStyle.swift:417). AxisBuilder
//       still uses a local keyword-arg convenience shim `createTextStyle` (bottom of file) whose fields map
//       1:1 to the two AxisLabel call sites. Deferred cleanup: rewire those to the ported `opt`-dict signature.
//   import Model from '../../model/Model';                              → `Model`
//   import {isRadianAroundZero, remRadian} from '../../util/number';    → `number.isRadianAroundZero` / `number.remRadian`
//   import {createSymbol, normalizeSymbolOffset} from '../../util/symbol';
//     → PORT-TODO: `util/symbol` NOT ported. axisLine arrow symbols deferred.
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
//       now calls the real sibling directly (see the bottom-of-file note).
//   import ExtensionAPI from '../../core/ExtensionAPI';                 → `ExtensionAPI`
//   import { makeInner } from '../../util/model';                       → `model.makeInner` (util/modelUtil.swift)
//   import { getAxisBreakHelper } from './axisBreakHelper';             → PORT-TODO: axisBreak deferred
//   import { AXIS_BREAK_EXPAND_ACTION_TYPE, BaseAxisBreakPayload } from './axisAction';  → PORT-TODO: deferred
//   import { getScaleBreakHelper, hasBreaks } from '../../scale/break';  → PORT-TODO: scale break deferred
//   import BoundingRect from 'zrender/src/core/BoundingRect';           → `BoundingRect` (ZRenderKit; used by overlap → deferred)
//   import Point from 'zrender/src/core/Point';                        → `Point` (ZRenderKit)
//   import { copyTransform } from 'zrender/src/core/Transformable';     → `copyTransform` (free func, ZRenderKit)
//   import { AxisLabelInfoDetermined, AxisLabelsComputingContext, AxisTickLabelComputingKind,
//       createAxisLabelsComputingContext } from '../../coord/axisTickLabelBuilder';  → `coord/axisTickLabelBuilder`
//   import { AxisTickCoord } from '../../coord/Axis';                   → `AxisTickCoord`
//   import { isOrdinalScale, isTimeScale } from '../../scale/helper';   → PORT-TODO: used only in fixMinMaxLabelShow (deferred)

private let PI = Double.pi

// This tune is also for backward compat, since nameMoveOverlap is set as default,
// in compact layout (multiple charts in one canvas), name should be more close to the axis line and labels.
// upstream: DefaultCenterAxisNameMarginLevels = Record<nameMarginLevel, [n,n,n,n]>
private let DEFAULT_CENTER_NAME_MARGIN_LEVELS: [[Double]] =
    [[1, 2, 1, 2], [5, 3, 5, 3], [8, 3, 8, 3]]
private let DEFAULT_ENDS_NAME_MARGIN_LEVELS: [[Double]] =
    [[0, 1, 0, 1], [0, 3, 0, 3], [0, 3, 0, 3]]

// type AxisIndexKey = 'xAxisIndex' | 'yAxisIndex' | 'radiusAxisIndex' | 'angleAxisIndex' | 'singleAxisIndex';
//   PORT-TODO: string-literal union → plain String at use sites.

// upstream: type AxisEventData = { componentType, componentIndex, targetType, name?, value?,
//   dataIndex?, tickIndex? } & { break? } & { [key in AxisIndexKey]?: number }
//   Modeled as a dynamic bag ([String: Any]) since it is only consumed by the (deferred) event/tooltip wiring.
public typealias AxisEventData = [String: Any]

// type AxisLabelText = graphic.Text & { __fullText, __truncatedText } & ECElement;
//   PORT-TODO: the `__fullText`/`__truncatedText`/ECElement decorations are used only by tooltip/truncation
//   (deferred). Use `ZRText` directly.
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
final class AxisBuilderCfgDetermined {
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
    // PORT-TODO: `labelInfoList` / `stOccupiedRect` / `nameLayout` / `nameLocation` are used by the
    //   cross-axis overlap resolution (labelLayoutHelper) which is deferred per task scope.
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
        _ cfg: Any,        // AxisBuilderCfgDetermined
        _ ctx: AxisBuilderSharedContext?,
        _ axisModel: AxisBaseModel,
        _ nameLayoutInfo: Any,  // LabelLayoutWithGeometry — deferred
        _ nameMoveDirVec: Point,
        _ thisRecord: AxisBuilderSharedContextRecord
    ) -> Void
    public let resolveAxisNameOverlap: ResolveAxisNameOverlap
}

// PORT-TODO: `resetOverlapRecordToShared` + `_stTransTmp` + `_stLabelRectTmp` (label rect union for
//   cross-axis name-overlap detection) depend on `labelLayoutHelper` (ensureLabelLayoutWithGeometry,
//   LabelLayoutWithGeometry, BoundingRect union math). Deferred per task scope (line+ticks+labels only).

/**
 * The default resolver does not involve other axes within the same coordinate system.
 */
// PORT-TODO: `resolveAxisNameOverlapDefault` + `moveIfOverlap` + `moveIfOverlapByLinearLabels` implement
//   axis-name overlap avoidance via OBB intersection (labelLayoutHelper). Deferred; the default resolver
//   is a no-op so the axis name is placed at its computed `nameGap` position without overlap nudging.
public let resolveAxisNameOverlapDefault: AxisBuilderSharedContext.ResolveAxisNameOverlap = {
    _, _, _, _, _, _ in
    // PORT-TODO: no-op until labelLayoutHelper lands (see comment above).
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
        // PORT-TODO: upstream takes Pick<AxisBuilderCfg, 'position' | 'labelOffset'>; the __DEV__ readiness
        //   assertions are dropped.
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
        // PORT-TODO: __DEV__ readiness assertion dropped.

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
        // upstream: const inverse = pt1[0] > pt2[0];  (used for arrow placement — deferred)
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
        //   PORT-TODO: axis break line deferred; always take the else branch.
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
        buildAxisBreakMarker(axisModel.axis as! Axis, group, transformGroup.transform, lineStyle)

        // upstream: let arrows = axisModel.get(['axisLine', 'symbol']); if (arrows != null) { ... createSymbol ... }
        //   PORT-TODO: axisLine arrow symbols require `util/symbol` (createSymbol / normalizeSymbolOffset),
        //   which is NOT ported. Deferred.
    },

    /**
     * [CAUTION] This method can be called multiple times ... Thus this method should be idempotent.
     */
    "axisTickLabelEstimate": { cfg, local, shared, axisModel, group, transformGroup, api, extraParams in
        // PORT-TODO: __DEV__ readiness assertion dropped.
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
        // PORT-TODO: __DEV__ readiness assertion dropped.
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
        // PORT-TODO: __DEV__ readiness assertion dropped.

        // Remove the existing name result created in estimation phase.
        if let nameEl = local.nameEl {
            _ = group.remove(nameEl)
            local.nameEl = nil
        }

        let name = cfg.axisName
        if !hasAxisName(name) {
            return
        }
        let nameStr = name!

        let nameLocation = cfg.nameLocation
        let nameDirection = cfg.nameDirection
        let textStyleModel = axisModel.getModel("nameTextStyle")
        let gap = (axisModel.get("nameGap") as? Double) ?? 0

        let axis = axisModel.axis as! Axis
        let extent = axis.getExtent()
        let gapStartEndSignal: Double = axis.inverse ? -1 : 1
        // upstream uses `Point`; only pos.x/pos.y are needed here (nameMoveDirVec drives the deferred
        //   overlap resolution — see PORT-TODO below).
        var posX: Double = 0
        var posY: Double = 0
        if nameLocation == "start" {
            posX = extent[0] - gapStartEndSignal * gap
        }
        else if nameLocation == "end" {
            posX = extent[1] + gapStartEndSignal * gap
        }
        else { // 'middle' or 'center'
            posX = (extent[0] + extent[1]) / 2
            posY = cfg.labelOffset + nameDirection * gap
        }
        // PORT-TODO: `nameMoveDirVec` + `matrixUtil.rotate` transform is only consumed by
        //   `resolveAxisNameOverlap` (deferred). Dropped.

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

        // upstream: const nameMarginLevel = extraParams.nameMarginLevel || 0;  (drives margin defaults — deferred)
        _ = extraParams.nameMarginLevel

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

        // PORT-TODO: graphic.setTooltipConfig (tooltip wiring) deferred.
        // PORT-TODO: textEl.__fullText = name — the truncation-tooltip decoration is deferred.
        // Id for animation
        textEl.anid = "name"

        // PORT-TODO: axisModel.get('triggerEvent') → getECData(textEl).eventData = ...  (event wiring deferred)

        _ = transformGroup.add(textEl)
        textEl.updateTransform()

        local.nameEl = textEl
        // PORT-TODO: sharedRecord.nameLayout = ensureLabelLayoutWithGeometry({...}) and
        //   sharedRecord.nameLocation — used only by the (deferred) name-overlap resolver.
        _ = sharedRecord
        _ = group.add(textEl)

        textEl.decomposeTransform()

        // PORT-TODO: if (cfg.shouldNameMoveOverlap && nameLayout) { shared.resolveAxisNameOverlap(...) }
        //   Deferred (labelLayoutHelper). The default resolver is a no-op regardless.
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

    // PORT-TODO: `adjustBreakLabels` (axis break label nudging) deferred.

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

    // PORT-TODO: `resetOverlapRecordToShared` (cross-axis overlap record) deferred.
    _ = shared
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
            // upstream copies with `marginForce: [0, 0, 0, 0]`; the margin machinery is a no-op in this
            //   port (see `labelLayoutHelper.newLabelLayoutWithGeometry`), so this is an identity copy.
            outmostLabelLayout = labelLayoutHelper.newLabelLayoutWithGeometry(outmostLL)
            innerLabelLayout = labelLayoutHelper.newLabelLayoutWithGeometry(innerLL)
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
    let tickEndCoord = cfg.tickDirection * ((tickModel.get("length") as? Double) ?? 0)

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
    let tickEndCoord = tickDirection * ((minorTickModel.get("length") as? Double) ?? 0)

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
    // upstream: axisModel.getCategories && axisModel.getCategories(true)
    // PORT-TODO: per-category `textStyle` override (rawCategoryData[tickValue].textStyle → new Model)
    //   is deferred; `labelModel` is used for every label. (Category `OrdinalRawValue` is `Any` here.)
    _ = axisModel.getCategories(true)

    var labelEls: [ZRText] = []
    let triggerEvent = truthy(axisModel.get("triggerEvent"))
    var z2Min = Double.infinity
    var z2Max = -Double.infinity

    util.each(labels, { labelItem, index in
        let labelItemTick = labelItem.tick
        let formattedLabel = labelItem.formattedLabel
        // PORT-TODO: `labelItem.rawLabel` feeds the per-label custom formatter callback
        //   (`axisLabel.formatter` function form), which is deferred; read it back when that lands.
        _ = labelItem.rawLabel

        let itemLabelModel = labelModel
        let tickValue = axisHelper.getTickValueOutermost(axis.scale, labelItemTick)

        // upstream: itemLabelModel.getTextColor() || axisModel.get(['axisLine', 'lineStyle', 'color'])
        // PORT-TODO: upstream `textColor` may be a function (per-label color callback). `ColorString`
        //   is `String` in this port, so the `isFunction(textColor)` branch is not representable; the
        //   plain string color is used.
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

        // PORT-TODO: graphic.setTooltipConfig (tooltip + truncation params) deferred.
        // PORT-TODO: triggerEvent → getECData(textEl).eventData / addBreakEventHandler deferred.
        _ = triggerEvent

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
    let labelMargin = (axisModel.get(["axisLabel", "margin"]) as? Double) ?? 0
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

// PORT-TODO: `addBreakEventHandler` (click → dispatchAction AXIS_BREAK_EXPAND) requires `axisAction` /
//   scale break; deferred per task scope.

// PORT-TODO: `adjustBreakLabels` requires `scale/break` (getScaleBreakHelper) + `axisBreakHelper`
//   (adjustBreakLabelPair); deferred per task scope.

// upstream: export default AxisBuilder;  -> `public final class AxisBuilder` above.


// ============================================================================
// PORT-TODO helpers — NOT part of AxisBuilder.ts upstream. These reproduce the
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

/// Build the ZRenderKit `LineShape` (graphic shape) from x1/y1/x2/y2.
func lineShapeOf(_ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double) -> LineShape {
    var s = LineShape()
    s.x1 = x1; s.y1 = y1; s.x2 = x2; s.y2 = y2
    return s
}

/// PORT-TODO: `util/graphic` (and its `useStyle` dict bridge) is not ported. Map the dynamic
///   `getLineStyle()`/`defaults(...)` style bag ([String: Any], keys per LINE_STYLE_KEY_MAP) onto the
///   typed `PathStyleProps`. Delete when the graphic style bridge lands.
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
    // PORT-TODO: `lineDash` (number[] | false) mapping deferred (LineDash enum bridge).
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
    return style
}

// `LabelLayoutData` now lives in `label/labelLayoutHelper.swift` (the real OBB-carrying type landed
//   in the L2c pass). The axis label path now calls the REAL `labelLayoutHelper.ensureLabelLayoutWithGeometry`
//   directly (see `updateAxisLabelChangableProps` / `layOutAxisTickLabel`): geometry is computed with
//   the initial transform, then re-dirtied + recomputed after `copyTransform` sets the final transform,
//   so the `hideOverlap` overlap-resolution pass reads accurate global rects / OBBs. The old identity
//   shim was removed.
