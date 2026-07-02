// Ported from echarts/src/coord/cartesian/cartesianAxisHelper.ts — keep in sync with upstream
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

// import * as zrUtil from 'zrender/src/core/util';                       -> util.* (ZRenderKit caseless enum)
// import CartesianAxisModel from './AxisModel';                          -> CartesianAxisModel (coord/cartesian/AxisModel.swift)
// import SeriesModel from '../../model/Series';                          -> SeriesModel (model/Series.swift)
// import { SINGLE_REFERRING } from '../../util/model';                   -> model.SINGLE_REFERRING (util/modelUtil.swift)
// import { LayoutRect } from '../../util/layout';                        -> LayoutRect (util/layout.swift — not yet ported; placeholder at bottom)
// import AxisBuilder, { AxisBuilderCfg, AxisBuilderSharedContext } from '../../component/axis/AxisBuilder';
//                                                                        -> AxisBuilder / AxisBuilderCfg / AxisBuilderSharedContext (component/axis, Phase 6b — placeholders at bottom)
// import { isIntervalOrLogScale } from '../../scale/helper';             -> helper.isIntervalOrLogScale (scale/helper.swift)
// import type Cartesian2D from './Cartesian2D';                          -> Cartesian2D (coord/cartesian/Cartesian2D.swift — not yet ported; placeholder at bottom)
// import ExtensionAPI from '../../core/ExtensionAPI';                    -> ExtensionAPI (core/ExtensionAPI.swift)
// import { NullUndefined } from 'zrender/src/core/types';                -> collapses to Optional (CONVENTIONS §6)
// import type Axis2D from './Axis2D';                                    -> Axis2D (coord/cartesian/Axis2D.swift)

// upstream: interface CartesianAxisLayout { position; rotation; labelOffset; labelDirection;
//   tickDirection; nameDirection; labelRotate; z2 }
//   Plain data bag (no identity) → `struct` (CONVENTIONS §2/§4). The direction / offset / rotate
//   fields are typed via `AxisBuilderCfg['...']` upstream (`-1 | 1 | undefined` / `number` etc.);
//   ported as `Double` where `layout` always assigns them and `Double?` for the `labelRotate` read
//   from the option bag.
public struct CartesianAxisLayout {
    public var position: [Double] = []
    public var rotation: Double = 0
    public var labelOffset: Double = 0
    public var labelDirection: Double = 0   // upstream: AxisBuilderCfg['labelDirection'] (-1 | 1)
    public var tickDirection: Double = 0    // upstream: AxisBuilderCfg['tickDirection'] (-1 | 1)
    public var nameDirection: Double = 0    // upstream: AxisBuilderCfg['nameDirection'] (-1 | 1)
    public var labelRotate: Double?         // upstream: AxisBuilderCfg['labelRotate'] (number)
    public var z2: Double = 0
    public init() {}
}

/**
 * [__CAUTION__]
 *  MUST guarantee: if only the input `rect` and `axis.extent` changed,
 *  only `layout.position` changes.
 *  This character is replied on `grid.contain` calculation in `AxisBuilder`.
 *  @see updateCartesianAxisViewCommonPartBuilder
 *
 * Can only be called after coordinate system creation stage.
 * (Can be called before coordinate system update stage).
 */
public enum cartesianAxisHelper {

    // upstream: opt?: {labelInside?: boolean}
    //   Object option bag with a single optional field → `struct` (Swift has no single-element
    //   labeled tuple).
    public struct LayoutOpt {
        public var labelInside: Bool?
        public init(labelInside: Bool? = nil) { self.labelInside = labelInside }
    }

    public static func layout(
        _ rect: LayoutRect, _ axisModel: CartesianAxisModel, _ opt: LayoutOpt? = nil
    ) -> CartesianAxisLayout {
        let opt = opt ?? LayoutOpt()
        // PORT-TODO: `CartesianAxisModel.axis` is typed `Any` (Swift cannot narrow the mixin's
        //   `axis` getter to `Axis2D`); downcast to `Axis2D` here to match upstream's typed member.
        let axis = axisModel.axis as! Axis2D
        var layout = CartesianAxisLayout()
        let otherAxisOnZeroOf = axis.getAxesOnZeroOf().first

        let rawAxisPosition = axis.position
        let axisPosition: CartesianAxisPosition = otherAxisOnZeroOf != nil ? "onZero" : rawAxisPosition
        let axisDim = axis.dim

        let rectBound = [rect.x, rect.x + rect.width, rect.y, rect.y + rect.height]
        let idx: [String: Int] = ["left": 0, "right": 1, "top": 0, "bottom": 1, "onZero": 2]
        let axisOffset = (axisModel.get("offset") as? Double) ?? 0

        var posBound = axisDim == "x"
            ? [rectBound[2] - axisOffset, rectBound[3] + axisOffset]
            : [rectBound[0] - axisOffset, rectBound[1] + axisOffset]

        if let otherAxisOnZeroOf = otherAxisOnZeroOf {
            let onZeroCoord = otherAxisOnZeroOf.toGlobalCoord(otherAxisOnZeroOf.dataToCoord(0))
            // upstream: posBound[idx.onZero] = Math.max(Math.min(onZeroCoord, posBound[1]), posBound[0]);
            //   `posBound` starts length 2; the JS assignment at index 2 extends it -> append here.
            posBound.append(Swift.max(Swift.min(onZeroCoord, posBound[1]), posBound[0]))
        }

        // Axis position
        layout.position = [
            axisDim == "y" ? posBound[idx[axisPosition]!] : rectBound[0],
            axisDim == "x" ? posBound[idx[axisPosition]!] : rectBound[3]
        ]

        // Axis rotation
        layout.rotation = Double.pi / 2 * (axisDim == "x" ? 0 : 1)

        // Tick and label direction, x y is axisDim
        let dirMap: [String: Double] = ["top": -1, "bottom": 1, "left": -1, "right": 1]

        // upstream: layout.labelDirection = layout.tickDirection = layout.nameDirection = dirMap[rawAxisPosition];
        layout.nameDirection = dirMap[rawAxisPosition]!
        layout.tickDirection = dirMap[rawAxisPosition]!
        layout.labelDirection = dirMap[rawAxisPosition]!
        layout.labelOffset = otherAxisOnZeroOf != nil ? posBound[idx[rawAxisPosition]!] - posBound[idx["onZero"]!] : 0

        // PORT-TODO: upstream truthiness on the option value; a boolean option is expected here, so
        //   `(... as? Bool) == true` reproduces `undefined -> false`, `true -> true`.
        if (axisModel.get(["axisTick", "inside"]) as? Bool) == true {
            layout.tickDirection = -layout.tickDirection
        }
        if (util.retrieve(opt.labelInside as Any?, axisModel.get(["axisLabel", "inside"])) as? Bool) == true {
            layout.labelDirection = -layout.labelDirection
        }

        // Special label rotation
        let labelRotate = axisModel.get(["axisLabel", "rotate"]) as? Double
        // PORT-TODO: upstream `-labelRotate` on `undefined` yields NaN; here a nil `labelRotate`
        //   stays nil (negation only applied when present).
        layout.labelRotate = axisPosition == "top" ? labelRotate.map { -$0 } : labelRotate

        // Over splitLine and splitArea
        layout.z2 = 1

        return layout
    }

    public static func isCartesian2DDeclaredSeries(_ seriesModel: SeriesModel) -> Bool {
        return (seriesModel.get("coordinateSystem") as? String) == "cartesian2d"
    }

    /**
     * Note: If pie (or other similar series) use cartesian2d, here
     *  option `seriesModel.get('coordinateSystem') === 'cartesian2d'`
     *  and `seriesModel.coordinateSystem !== cartesian2dCoordSysInstance`
     *  and `seriesModel.boxCoordinateSystem === cartesian2dCoordSysInstance`,
     *  the logic below is probably wrong, therefore skip it temporarily.
     */
    public static func isCartesian2DInjectedAsDataCoordSys(_ seriesModel: SeriesModel) -> Bool {
        return seriesModel.coordinateSystem != nil
            && (seriesModel.coordinateSystem as? CoordinateSystem)?.type == "cartesian2d"
    }

    public static func findAxisModels(_ seriesModel: SeriesModel) -> (
        xAxisModel: CartesianAxisModel,
        yAxisModel: CartesianAxisModel
    ) {
        var axisModelMap: [String: CartesianAxisModel?] = [
            "xAxisModel": nil,
            "yAxisModel": nil
        ]
        // upstream: zrUtil.each(axisModelMap, function (v, key) { ... });
        //   Swift `util.each` has no object-iteration overload; iterate the fixed key set instead.
        let axisModelMapKeys: [String] = ["xAxisModel", "yAxisModel"]
        util.each(axisModelMapKeys) { key, _ in
            // upstream: const axisType = key.replace(/Model$/, '');
            let axisType = key.replacingOccurrences(of: "Model", with: "")
            let axisModel = seriesModel.getReferringComponents(
                axisType, model.SINGLE_REFERRING
            ).models.first as? CartesianAxisModel

            if __DEV__ {
                if axisModel == nil {
                    // PORT-TODO: upstream `throw new Error(...)`; surfaced as fatalError (no throwing signature).
                    let axisIndexOrId = util.retrieve3(
                        seriesModel.get(axisType + "Index"),
                        seriesModel.get(axisType + "Id"),
                        0 as Any?
                    ) ?? 0
                    fatalError(axisType + " \"" + "\(axisIndexOrId)" + "\" not found")
                }
            }

            axisModelMap[key] = axisModel
        }

        return (
            xAxisModel: axisModelMap["xAxisModel"]!!,
            yAxisModel: axisModelMap["yAxisModel"]!!
        )
    }

    public static func createCartesianAxisViewCommonPartBuilder(
        _ gridRect: LayoutRect,
        _ cartesians: [Cartesian2D],
        _ axisModel: CartesianAxisModel,
        _ api: ExtensionAPI,
        _ ctx: AxisBuilderSharedContext?,
        _ defaultNameMoveOverlap: Bool?
    ) -> AxisBuilder {
        var layoutResult: AxisBuilderCfg = AxisBuilderCfg(layout(gridRect, axisModel))

        var axisLineAutoShow = false
        var axisTickAutoShow = false
        // Not show axisTick or axisLine if other axis is category / time
        for i in 0..<cartesians.count {
            // PORT-TODO: `axisModel.axis` is typed `Any` (see `layout`); downcast to `Axis2D`.
            if helper.isIntervalOrLogScale(cartesians[i].getOtherAxis(axisModel.axis as! Axis2D).scale) {
                // Still show axis tick or axisLine if other axis is value / log
                axisLineAutoShow = true
                axisTickAutoShow = true
                if (axisModel.axis as! Axis2D).type == "category" && (axisModel.axis as! Axis2D).onBand {
                    axisTickAutoShow = false
                }
            }
        }
        layoutResult.axisLineAutoShow = axisLineAutoShow
        layoutResult.axisTickAutoShow = axisTickAutoShow
        layoutResult.defaultNameMoveOverlap = defaultNameMoveOverlap

        return AxisBuilder(axisModel, api, layoutResult, ctx)
    }

    public static func updateCartesianAxisViewCommonPartBuilder(
        _ axisBuilder: AxisBuilder,
        _ gridRect: LayoutRect,
        _ axisModel: CartesianAxisModel
    ) {
        let newRaw: AxisBuilderCfg = AxisBuilderCfg(layout(gridRect, axisModel))

        if __DEV__ {
            let oldRaw = axisBuilder.__getRawCfg()
            // PORT-TODO: upstream iterates `zrUtil.keys(newRaw)` and asserts each prop (except
            //   'position'/'labelOffset') equals `oldRaw[prop]`. The dynamic per-key comparison
            //   depends on the real `AxisBuilderCfg` shape / storage (component/axis/AxisBuilder,
            //   Phase 6b); deferred with that stub.
            _ = oldRaw
        }

        axisBuilder.updateCfg(newRaw)
    }

    public static func getCartesianAxisHashKey(_ axis: Axis2D) -> CartesianAxisHashKey {
        // upstream: return axis.dim + '_' + axis.index;
        //   `axis.index` is a `Double` (number) but is an integer-valued key; format as `Int`
        //   so the string matches JS integer output (`x_0`, not `x_0.0`).
        return axis.dim + "_" + "\(Int(axis.index))"
    }
}

public typealias CartesianAxisHashKey = String


// ============================================================================
// PORT-TODO: FORWARD-REFERENCE PLACEHOLDERS
// Upstream `coord/cartesian/cartesianAxisHelper.ts` imports these from sibling files that are not
// yet present in the port (`util/layout`, `coord/cartesian/Cartesian2D`, `component/axis/AxisBuilder`
// — the last is Phase 6b). They are declared here as minimal placeholders so this file compiles.
// The agent that ports the corresponding source file MUST remove the placeholder here and replace it
// with the real, fully-ported type/API (mirrors the contract in scale/helper.swift).
// NOTE: `AxisBuilder` itself already has an (empty) placeholder `final class AxisBuilder {}` in
//   coord/cartesian/Axis2D.swift; the members it needs here are grafted via an extension below.
// ============================================================================

// '../../util/layout' — LayoutRect: upstream `interface LayoutRect extends BoundingRect`.
//   Only `.x` / `.y` / `.width` / `.height` are read here, all provided by ZRenderKit's BoundingRect.
public typealias LayoutRect = BoundingRect  // PORT-TODO: replace with real util/layout.swift LayoutRect

// './Cartesian2D' — Cartesian2D: upstream `class Cartesian2D extends Cartesian<Axis2D> implements
//   CoordinateSystem`. Now provided by the real `coord/cartesian/Cartesian2D.swift`; the former
//   placeholder class was removed to avoid an invalid redeclaration.

// '../../component/axis/AxisBuilder' — AxisBuilderCfg: upstream interface (component/axis, Phase 6b).
//   Superset of `CartesianAxisLayout` plus the auto-show / move-overlap flags set below.
public struct AxisBuilderCfg {  // PORT-TODO: replace with real component/axis/AxisBuilder.swift
    public var position: [Double]
    public var rotation: Double
    public var nameDirection: Double?       // upstream: -1 | 1
    public var tickDirection: Double?       // upstream: -1 | 1
    public var labelDirection: Double?      // upstream: -1 | 1
    public var labelOffset: Double?
    public var axisLineAutoShow: Bool?
    public var axisTickAutoShow: Bool?
    public var labelRotate: Double?
    public var defaultNameMoveOverlap: Bool?
    public var z2: Double?

    // Build from a `CartesianAxisLayout` (upstream relies on structural typing:
    //   `const layoutResult: AxisBuilderCfg = layout(...)`).
    public init(_ l: CartesianAxisLayout) {
        self.position = l.position
        self.rotation = l.rotation
        self.nameDirection = l.nameDirection
        self.tickDirection = l.tickDirection
        self.labelDirection = l.labelDirection
        self.labelOffset = l.labelOffset
        self.labelRotate = l.labelRotate
        self.z2 = l.z2
    }
}

// '../../component/axis/AxisBuilder' — AxisBuilderSharedContext: upstream `class` (component/axis, Phase 6b).
public final class AxisBuilderSharedContext {}  // PORT-TODO: replace with real component/axis/AxisBuilder.swift

// '../../component/axis/AxisBuilder' — AxisBuilder members needed here (Phase 6b). The empty
//   `final class AxisBuilder {}` placeholder lives in coord/cartesian/Axis2D.swift; graft the
//   constructor / `__getRawCfg` / `updateCfg` used by this file via an extension.
extension AxisBuilder {  // PORT-TODO: replace with real component/axis/AxisBuilder.swift
    // upstream: constructor(axisModel: AxisBaseModel, api: ExtensionAPI, opt: AxisBuilderCfg, ctx?)
    public convenience init(
        _ axisModel: CartesianAxisModel,
        _ api: ExtensionAPI,
        _ opt: AxisBuilderCfg,
        _ ctx: AxisBuilderSharedContext?
    ) {
        self.init()
        // PORT-TODO: real construction deferred to component/axis/AxisBuilder.swift (Phase 6b).
    }

    public func __getRawCfg() -> AxisBuilderCfg {
        fatalError("PORT-TODO: AxisBuilder.__getRawCfg not yet ported (Phase 6b)")
    }

    public func updateCfg(_ opt: AxisBuilderCfg) {
        // PORT-TODO: real updateCfg deferred to component/axis/AxisBuilder.swift (Phase 6b).
    }
}
