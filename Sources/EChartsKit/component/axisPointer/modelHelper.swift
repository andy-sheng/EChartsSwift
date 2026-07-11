// Ported from echarts/src/component/axisPointer/modelHelper.ts — keep in sync with upstream
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

// import Model from '../../model/Model';                          -> Model (model/Model.swift)
// import GlobalModel from '../../model/Global';                   -> GlobalModel (model/Global.swift)
// import ExtensionAPI from '../../core/ExtensionAPI';             -> ExtensionAPI (core/ExtensionAPI.swift)
// import { each, curry, clone, defaults, isArray, indexOf } from 'zrender/src/core/util';
//   -> `util.each` / `util.clone` / `util.defaults` / `util.isArray`. `curry(fn, a, b)` (partial
//      application) has no Swift equivalent — inlined as trailing closures at the call sites.
// import AxisPointerModel, { AxisPointerOption } from './AxisPointerModel';  -> sibling (same module)
// import Axis from '../../coord/Axis';                            -> Axis (coord/Axis.swift)
// import { TooltipOption } from '../tooltip/TooltipModel';        -> tooltip/TooltipModel.swift
// import SeriesModel from '../../model/Series';                   -> SeriesModel (model/Series.swift)
// import { AxisBaseModel } from '../../coord/AxisBaseModel';      -> AxisBaseModel (coord/AxisBaseModel.swift)
// import ComponentModel from '../../model/Component';             -> ComponentModel (model/Component.swift)
// import { CoordinateSystemMaster } from '../../coord/CoordinateSystem';
//   -> CoordinateSystemMaster (master) + CoordinateSystem (executive), coord/CoordinateSystem.swift.
// (Types `SeriesOption`/`SeriesTooltipOption`/`CommonAxisPointerOption`/`Dictionary`/`ComponentOption`
//  are consumed dynamically via the `[String: Any]` bag, CONVENTIONS §2.)

// interface LinkGroup { mapper; axesInfo: Dictionary<AxisInfo> }
//   -> reference type: `linkGroup.axesInfo[axisKey] = axisInfo` and `.mapper` are mutated in place and
//      shared with `axisInfo.linkGroup`, so it must be a class (JS object semantics).
public final class LinkGroup {
    // mapper: AxisPointerOption['link'][number]['mapper']
    //   -> the user link `mapper` callback. PORT-TODO: link-group value mapping (`axisTrigger`'s
    //      cross-axis linking) is deferred; the callback is stored opaquely as `Any?`.
    public var mapper: Any?
    // { [axisKey]: AxisInfo }
    public var axesInfo: [String: AxisInfo] = [:]
    public init() {}
}

// interface AxisInfo { ... }
//   -> reference type: mutated after insertion (`seriesModels.push`, `seriesDataCount`, `linkGroup`)
//      and shared across `result.axesInfo` / `coordSysAxesInfo` / `linkGroup.axesInfo` dicts.
public final class AxisInfo {
    public let axis: Axis
    public let key: String
    public let coordSys: CoordinateSystemMaster
    public let axisPointerModel: Model
    public let triggerTooltip: Bool
    public let triggerEmphasis: Bool
    public let involveSeries: Bool
    public let snap: Bool
    public let useHandle: Bool
    public var seriesModels: [SeriesModel]

    public var linkGroup: LinkGroup?
    public var seriesDataCount: Int?

    public init(
        axis: Axis,
        key: String,
        coordSys: CoordinateSystemMaster,
        axisPointerModel: Model,
        triggerTooltip: Bool,
        triggerEmphasis: Bool,
        involveSeries: Bool,
        snap: Bool,
        useHandle: Bool,
        seriesModels: [SeriesModel],
        linkGroup: LinkGroup?
    ) {
        self.axis = axis
        self.key = key
        self.coordSys = coordSys
        self.axisPointerModel = axisPointerModel
        self.triggerTooltip = triggerTooltip
        self.triggerEmphasis = triggerEmphasis
        self.involveSeries = involveSeries
        self.snap = snap
        self.useHandle = useHandle
        self.seriesModels = seriesModels
        self.linkGroup = linkGroup
    }
}

// interface CollectionResult { ... }
//   -> reference type: populated across `collect` / `collectAxesInfo` / `collectSeriesInfo` by
//      mutating its nested dictionaries in place (JS object aliasing).
public final class CollectionResult {
    // { [coordSysKey]: { [axisKey]: AxisInfo } }
    public var coordSysAxesInfo: [String: [String: AxisInfo]] = [:]
    // { [axisKey]: AxisInfo }
    public var axesInfo: [String: AxisInfo] = [:]
    // { [coordSysKey]: CoordinateSystemMaster }
    public var coordSysMap: [String: CoordinateSystemMaster] = [:]
    public var seriesInvolved: Bool = false
    public init() {}
}

// `fromTooltip: boolean | 'cross'` — the JS union. `.no` is the JS-falsy `false`; `.yes`/`.cross`
// are both truthy (`!fromTooltip` ⟺ `== .no`); the `'cross'` string check ⟺ `== .cross`.
private enum FromTooltip {
    case no, yes, cross
}

// Build axisPointerModel, mergin tooltip.axisPointer model for each axis.
// allAxesInfo should be updated when setOption performed.
public func collect(_ ecModel: GlobalModel, _ api: ExtensionAPI) -> CollectionResult {
    let result = CollectionResult()

    collectAxesInfo(result, ecModel, api)

    // Check seriesInvolved for performance, in case too many series in some chart.
    if result.seriesInvolved {
        collectSeriesInfo(result, ecModel)
    }

    return result
}

private func collectAxesInfo(_ result: CollectionResult, _ ecModel: GlobalModel, _ api: ExtensionAPI) {
    let globalTooltipModel = ecModel.getComponent("tooltip")
    // const globalAxisPointerModel = ecModel.getComponent('axisPointer') as AxisPointerModel;
    // PORT note: `axisPointer` is a dependency of `tooltip`, so upstream assumes the component exists.
    //   If it has not been installed/created, there is nothing to collect.
    guard let globalAxisPointerModel = ecModel.getComponent("axisPointer") as? AxisPointerModel else {
        return
    }
    // links can only be set on global.
    let linksOption = (globalAxisPointerModel.get("link", true) as? [Any]) ?? []
    var linkGroups: [Int: LinkGroup] = [:]

    // Collect axes info.
    util.each(api.getCoordinateSystems()) { coordSys, _ in
        // Some coordinate system do not support axes, like geo.
        if !(coordSys.axisPointerEnabled ?? false) {
            return
        }
        guard let coordSysModel = coordSys.model else {
            return
        }

        let coordSysKey = makeKey(coordSysModel)
        var axesInfoInCoordSys: [String: AxisInfo] = [:]
        result.coordSysMap[coordSysKey] = coordSys

        // Set tooltip (like 'cross') is a convenient way to show axisPointer
        // for user. So we enable setting tooltip on coordSys model.
        let baseTooltipModel = coordSysModel.getModel("tooltip", globalTooltipModel)

        // fromTooltip: true | false | 'cross'
        // triggerTooltip: true | false | null
        func saveTooltipAxisInfo(_ fromTooltip: FromTooltip, _ triggerTooltipIn: Bool?, _ axis: Axis) {
            var axisPointerModel: Model = axis.model.getModel("axisPointer", globalAxisPointerModel)

            let axisPointerShow = axisPointerModel.get("show")
            if !jsTruthy(axisPointerShow) || (
                (axisPointerShow as? String) == "auto"
                && fromTooltip == .no
                && !isHandleTrigger(axisPointerModel)
            ) {
                return
            }

            var triggerTooltip = triggerTooltipIn
            if triggerTooltip == nil {
                triggerTooltip = jsTruthy(axisPointerModel.get("triggerTooltip"))
            }

            axisPointerModel = (fromTooltip != .no)
                ? makeAxisPointerModel(
                    axis, baseTooltipModel, globalAxisPointerModel, ecModel,
                    fromTooltip, triggerTooltip ?? false
                )
                : axisPointerModel

            let snap = jsTruthy(axisPointerModel.get("snap"))
            let triggerEmphasis = jsTruthy(axisPointerModel.get("triggerEmphasis"))
            let axisKey = makeKey(axis.model)
            let involveSeries = (triggerTooltip ?? false) || snap || axis.type == "category"

            // If result.axesInfo[key] exist, override it (tooltip has higher priority).
            let axisInfo = AxisInfo(
                axis: axis,
                key: axisKey,
                coordSys: coordSys,
                axisPointerModel: axisPointerModel,
                triggerTooltip: triggerTooltip ?? false,
                triggerEmphasis: triggerEmphasis,
                involveSeries: involveSeries,
                snap: snap,
                useHandle: isHandleTrigger(axisPointerModel),
                seriesModels: [],
                linkGroup: nil
            )
            result.axesInfo[axisKey] = axisInfo
            axesInfoInCoordSys[axisKey] = axisInfo
            result.seriesInvolved = result.seriesInvolved || involveSeries

            if let groupIndex = getLinkGroupIndex(linksOption, axis) {
                let linkGroup: LinkGroup
                if let existing = linkGroups[groupIndex] {
                    linkGroup = existing
                } else {
                    linkGroup = LinkGroup()
                    linkGroups[groupIndex] = linkGroup
                }
                linkGroup.axesInfo[axisKey] = axisInfo
                linkGroup.mapper = (linksOption[groupIndex] as? [String: Any])?["mapper"]
                axisInfo.linkGroup = linkGroup
            }
        }

        // each(coordSys.getAxes(), curry(saveTooltipAxisInfo, false, null));
        util.each(coordSys.getAxes()) { axis, _ in
            saveTooltipAxisInfo(.no, nil, axis)
        }

        // If axis tooltip used, choose tooltip axis for each coordSys.
        // Notice this case: coordSys is `grid` but not `cartesian2D` here.
        // (`coordSys.getTooltipAxes` returning nil ⟺ the upstream `coordSys.getTooltipAxes` being
        //  undefined — i.e. this coord sys does not support tooltip axes; the block is skipped.)
        if globalTooltipModel != nil
            // If tooltip.showContent is set as false, tooltip will not
            // show but axisPointer will show as normal.
            && jsTruthy(baseTooltipModel.get("show")) {
            // Compatible with previous logic. But series.tooltip.trigger: 'axis'
            // or series.data[n].tooltip.trigger: 'axis' are not support any more.
            let triggerAxis = (baseTooltipModel.get("trigger") as? String) == "axis"
            let cross = (baseTooltipModel.get(["axisPointer", "type"]) as? String) == "cross"
            let dimOpt = (baseTooltipModel.get(["axisPointer", "axis"]) as? DimensionName) ?? "auto"
            if let tooltipAxes = coordSys.getTooltipAxes(dimOpt) {
                if triggerAxis || cross {
                    util.each(tooltipAxes.baseAxes) { axis, _ in
                        saveTooltipAxisInfo(cross ? .cross : .yes, triggerAxis, axis)
                    }
                }
                if cross {
                    util.each(tooltipAxes.otherAxes) { axis, _ in
                        saveTooltipAxisInfo(.cross, false, axis)
                    }
                }
            }
        }

        // Write the per-coordSys axis map back (upstream aliases `result.coordSysAxesInfo[key] = {}`
        // and mutates it by reference; Swift dicts are value types, so assign the populated copy —
        // always, so an axis-less coordSys still gets the empty-`{}` entry).
        result.coordSysAxesInfo[coordSysKey] = axesInfoInCoordSys
    }
}

private func makeAxisPointerModel(
    _ axis: Axis,
    _ baseTooltipModel: Model,
    _ globalAxisPointerModel: AxisPointerModel,
    _ ecModel: GlobalModel,
    _ fromTooltip: FromTooltip,
    _ triggerTooltip: Bool
) -> Model {
    let tooltipAxisPointerModel = baseTooltipModel.getModel("axisPointer")
    let fields = [
        "type", "snap", "lineStyle", "shadowStyle", "label",
        "animation", "animationDurationUpdate", "animationEasingUpdate", "z"
    ]
    var volatileOption: [String: Any] = [:]

    util.each(fields) { field, _ in
        // volatileOption[field] = clone(tooltipAxisPointerModel.get(field));
        if let v = tooltipAxisPointerModel.get(field), !(v is NSNull) {
            let cloned: Any = util.clone(v)
            volatileOption[field] = cloned
        }
    }

    // category axis do not auto snap, otherwise some tick that do not
    // has value can not be hovered. value/time/log axis default snap if
    // triggered from tooltip and trigger tooltip.
    volatileOption["snap"] = (axis.type != "category") && triggerTooltip

    // Compatible with previous behavior, tooltip axis does not show label by default.
    // Only these properties can be overridden from tooltip to axisPointer.
    if (tooltipAxisPointerModel.get("type") as? String) == "cross" {
        volatileOption["type"] = "line"
    }
    // const labelOption = volatileOption.label || (volatileOption.label = {});
    var labelOption = (volatileOption["label"] as? [String: Any]) ?? [:]
    // Follow the convention, do not show label when triggered by tooltip by default.
    // labelOption.show == null && (labelOption.show = false);
    if labelOption["show"] == nil || labelOption["show"] is NSNull {
        labelOption["show"] = false
    }

    if fromTooltip == .cross {
        // When 'cross', both axes show labels.
        let tooltipAxisPointerLabelShow = tooltipAxisPointerModel.get(["label", "show"])
        labelOption["show"] = (tooltipAxisPointerLabelShow != nil && !(tooltipAxisPointerLabelShow is NSNull))
            ? tooltipAxisPointerLabelShow! : true
        // If triggerTooltip, this is a base axis, which should better not use cross style
        // (cross style is dashed by default)
        if !triggerTooltip {
            // const crossStyle = volatileOption.lineStyle = tooltipAxisPointerModel.get('crossStyle');
            let crossStyle = tooltipAxisPointerModel.get("crossStyle")
            volatileOption["lineStyle"] = crossStyle   // nil ⟺ undefined (removes the key)
            // crossStyle && defaults(labelOption, crossStyle.textStyle);
            if let cs = crossStyle as? [String: Any], let textStyle = cs["textStyle"] as? [String: Any] {
                _ = util.defaults(&labelOption, textStyle)
            }
        }
    }
    volatileOption["label"] = labelOption

    return axis.model.getModel(
        "axisPointer",
        Model(volatileOption, globalAxisPointerModel, ecModel)
    )
}

private func collectSeriesInfo(_ result: CollectionResult, _ ecModel: GlobalModel) {
    // Prepare data for axis trigger
    ecModel.eachSeries { seriesModel, _ in
        // Notice this case: this coordSys is `cartesian2D` but not `grid`.
        // `coordinateSystem` is the executive coord sys (Cartesian2D, ...); it carries both `.model`
        //  and `.getAxis(dim)`. CRITICAL: narrow to the concrete `Cartesian2D` (NOT the existential
        //  `CoordinateSystem`): `Cartesian2D.getAxis(_ dim: DimensionName)` (non-optional param) does NOT
        //  witness the protocol's `getAxis(_ dim: DimensionName?) -> Axis?` requirement, so an
        //  `as? CoordinateSystem` cast would bind `getAxis(axis.dim)` to the nil-returning protocol
        //  default → `nil === axis` is always false → `axisInfo.seriesModels` never populated → the axis
        //  tooltip never appears. The concrete cast pins the real `Cartesian2D.getAxis -> Axis2D`. Mirrors
        //  findPointFromSeries.swift:116. PORT-TODO: polar/single tooltip-axis series info is out of scope.
        let coordSys = seriesModel.coordinateSystem as? Cartesian2D
        let seriesTooltipTrigger = seriesModel.get(["tooltip", "trigger"], true)
        let seriesTooltipShow = seriesModel.get(["tooltip", "show"], true)
        guard let coordSys = coordSys, let coordSysModel = coordSys.model else {
            return   // !coordSys || !coordSys.model
        }
        if (seriesTooltipTrigger as? String) == "none"
            || (seriesTooltipTrigger as? Bool) == false
            || (seriesTooltipTrigger as? String) == "item"
            || (seriesTooltipShow as? Bool) == false
            || (seriesModel.get(["axisPointer", "show"], true) as? Bool) == false {
            return
        }

        // each(result.coordSysAxesInfo[makeKey(coordSys.model)], function (axisInfo) { ... });
        let axesInfoMap = result.coordSysAxesInfo[makeKey(coordSysModel)] ?? [:]
        for (_, axisInfo) in axesInfoMap {
            let axis = axisInfo.axis
            if coordSys.getAxis(axis.dim) === axis {
                axisInfo.seriesModels.append(seriesModel)
                if axisInfo.seriesDataCount == nil {
                    axisInfo.seriesDataCount = 0
                }
                axisInfo.seriesDataCount! += seriesModel.getData().count()
            }
        }
    }
}

/**
 * For example:
 * {
 *     axisPointer: {
 *         links: [{
 *             xAxisIndex: [2, 4],
 *             yAxisIndex: 'all'
 *         }, {
 *             xAxisId: ['a5', 'a7'],
 *             xAxisName: 'xxx'
 *         }]
 *     }
 * }
 */
private func getLinkGroupIndex(_ linksOption: [Any], _ axis: Axis) -> Int? {
    let axisModel: AxisBaseModel = axis.model
    let dim = axis.dim
    for i in 0..<linksOption.count {
        let linkOption = (linksOption[i] as? [String: Any]) ?? [:]
        if checkPropInLink(linkOption[dim + "AxisId"], axisModel.id)
            || checkPropInLink(linkOption[dim + "AxisIndex"], axisModel.componentIndex)
            || checkPropInLink(linkOption[dim + "AxisName"], axisModel.name) {
            return i
        }
    }
    return nil
}

// checkPropInLink(linkPropValue, axisPropValue):
//   linkPropValue === 'all' || (isArray && indexOf(linkPropValue, axisPropValue) >= 0)
//     || linkPropValue === axisPropValue
private func checkPropInLink(_ linkPropValue: Any?, _ axisPropValue: Any?) -> Bool {
    if (linkPropValue as? String) == "all" {
        return true
    }
    if util.isArray(linkPropValue) {
        // indexOf(linkPropValue, axisPropValue) >= 0  (arrays are never `=== axisPropValue`)
        if let arr = linkPropValue as? [Any] {
            for v in arr {
                if looseEq(v, axisPropValue) {
                    return true
                }
            }
        }
        return false
    }
    return looseEq(linkPropValue, axisPropValue)
}

public func fixValue(_ axisModel: AxisBaseModel) {
    guard let axisInfo = getAxisInfo(axisModel) else {
        return
    }

    let axisPointerModel = axisInfo.axisPointerModel
    let scale = axisInfo.axis.scale
    guard var option = axisPointerModel.option as? [String: Any] else {
        return
    }
    let status = axisPointerModel.get("status")
    let rawValue = axisPointerModel.get("value")

    // Parse init value for category and time axis.
    var value: Double? = nil
    if let rv = rawValue, !(rv is NSNull) {
        value = scale.parse(rv)   // ScaleDataValue
    }

    let useHandle = isHandleTrigger(axisPointerModel)
    // If `handle` used, `axisPointer` will always be displayed, so value
    // and status should be initialized.
    if status == nil || status is NSNull {
        option["status"] = useHandle ? "show" : "hide"
    }

    let extent = scale.getExtent()

    if // Pick a value on axis when initializing.
        value == nil
        // If both `handle` and `dataZoom` are used, value may be out of axis extent,
        // where we should re-pick a value to keep `handle` displaying normally.
        || value! > extent[1] {
        // Make handle displayed on the end of the axis when init, which looks better.
        value = extent[1]
    }
    if value! < extent[0] {
        value = extent[0]
    }

    option["value"] = value!

    if useHandle {
        option["status"] = axisInfo.axis.scale.isBlank() ? "hide" : "show"
    }

    axisPointerModel.option = option
}

public func getAxisInfo(_ axisModel: AxisBaseModel) -> AxisInfo? {
    // (axisModel.ecModel.getComponent('axisPointer') as AxisPointerModel || {}).coordSysAxesInfo
    let apModel = axisModel.ecModel?.getComponent("axisPointer") as? AxisPointerModel
    guard let coordSysAxesInfo = apModel?.coordSysAxesInfo as? CollectionResult else {
        return nil
    }
    return coordSysAxesInfo.axesInfo[makeKey(axisModel)]
}

public func getAxisPointerModel(_ axisModel: AxisBaseModel) -> Model? {
    let axisInfo = getAxisInfo(axisModel)
    return axisInfo?.axisPointerModel
}

private func isHandleTrigger(_ axisPointerModel: Model) -> Bool {
    return jsTruthy(axisPointerModel.get(["handle", "show"]))
}

/**
 * @param model
 * @return unique key
 */
public func makeKey(_ model: ComponentModel) -> String {
    return model.type + "||" + model.id
}

// PORT-NOTE: `viewHelper.buildLabelElOption` — the drawn crosshair label *element* build
//   (an `AxisPointerElementOption`) lives in `component/axisPointer/viewHelper.ts` and is ported in
//   the sibling `viewHelper.swift` (not here in modelHelper). `axisTrigger` (this phase) consumes only
//   the collected models (`collect` / `getAxisPointerModel` / `makeKey`) + their coordSys / value / status above.

// --- JS truthiness (shared local helper; mirrors the sibling `jsTruthy` in coord/View.swift etc.) ---
private func jsTruthy(_ v: Any?) -> Bool {
    switch v {
    case nil: return false
    case is NSNull: return false
    case let b as Bool: return b
    case let d as Double: return d != 0 && !d.isNaN
    case let i as Int: return i != 0
    case let s as String: return !s.isEmpty
    default: return true
    }
}

// Loose scalar equality for link matching: numbers compare numerically (guards the Int-vs-Double
// option-read trap — axis `componentIndex` is Double while option indices box as Int), strings by value.
private func looseEq(_ a: Any?, _ b: Any?) -> Bool {
    if let x = a as? String, let y = b as? String {
        return x == y
    }
    if let x = asDouble(a), let y = asDouble(b) {
        return x == y
    }
    return false
}

private func asDouble(_ v: Any?) -> Double? {
    switch v {
    case let d as Double: return d
    case let i as Int: return Double(i)
    default: return nil
    }
}
