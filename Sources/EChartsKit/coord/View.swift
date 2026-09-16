// Ported from echarts/src/coord/View.ts — keep in sync with upstream
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

// upstream imports mapped:
//   import BoundingRect, { boundingRectApplyTransform, boundingRectCalculateTransform,
//       boundingRectContain, boundingRectCopy, boundingRectCreate } from 'zrender/src/core/BoundingRect';
//       -> ZRenderKit (all present).
//   import Transformable, { copyTransform, transformableCreate, transformableGetLocalTransform }
//       from 'zrender/src/core/Transformable';                          -> ZRenderKit.
//   import Element from 'zrender/src/Element';                          -> ZRenderKit (roam/animation only, DEFERRED).
//   import { CoordinateSystemMaster, CoordinateSystem } from './CoordinateSystem';
//       -> coord/CoordinateSystem.swift. See CONFORMANCE note on the class below.
//   import GlobalModel from '../model/Global';                          -> GlobalModel.
//   import { ParsedModelFinder, ParsedModelFinderKnown } from '../util/model';  -> `[String: Any]`.
//   import { isPositionSizeOptionPercent, mathAbs, parsePercent } from '../util/number';
//       -> number.swift (`number.parsePercent` / `number.isPositionSizeOptionPercent` / `number.mathAbs`).
//   import { AnimationOptionMixin, ChartComponentRoamHostView, NullUndefined, RoamHostComponentOrSeries,
//       RoamOptionMixin, RoamPayload } from '../util/types';            -> util/types.swift (roam types DEFERRED).
//   import { assert, each } from 'zrender/src/core/util';               -> ZRenderKit.util.
//   import ExtensionAPI, { getViewOfComponentOrSeries } from '../core/ExtensionAPI';  -> core/ExtensionAPI.swift.
//   import { decomposeTransform, payloadDisableAnimation, updateProps, WH, XY } from '../util/graphic';
//       -> `decomposeTransform` reproduced privately below (util/graphic.swift has not landed it yet;
//          reproducing here avoids a cross-file basename dependency). `updateProps` IS ported and IS
//          used here (animation/basicTransition.swift:174, called from applyViewCoordSysTransToElement
//          below). `payloadDisableAnimation` is roam-only (DEFERRED). `WH`/`XY` used only by roam
//          sync-back (DEFERRED).
//   import type ComponentModel from '../model/Component';               -> ComponentModel.
//   import type Model from '../model/Model';                            -> Model.
//   import { MatrixArray, invert, mul, create, copy } from 'zrender/src/core/matrix';  -> ZRenderKit.matrix.
//   import { applyTransform, copy, set } from 'zrender/src/core/vector';                -> ZRenderKit.vector.

// -----------------------------------------------------------------------------------------------------
// PORT SCOPE (CONVENTIONS §5): only the STATIC transform machinery of View is ported here —
//   the VIEW_COORD_SYS_TRANS_RAW / _ROAM / _OVERALL transform chain and the raw-rect -> view-rect
//   linear map that `dataToPoint`/`pointToData` rely on. ROAM interaction (pan/zoom actions), the
//   sync-back to model, and roaming animation are DEFERRED. See note markers below.
// -----------------------------------------------------------------------------------------------------

// upstream: VIEW_COORD_SYS_TRANS_RAW / _ROAM / _OVERALL — index into `ViewInner['trans']`.
public let VIEW_COORD_SYS_TRANS_RAW = 0
public let VIEW_COORD_SYS_TRANS_ROAM = 1
public let VIEW_COORD_SYS_TRANS_OVERALL = 2

// upstream: export const VIEW_COORD_SYS_TYPE = 'view';
public let VIEW_COORD_SYS_TYPE = "view"

// upstream: `interface ViewInner extends View { lgCt?: {w; h} }` — the `{w, h}` legacy center base.
//   @see useLegacyViewCoordSysCenterBase.
public struct ViewCoordSysLegacyCenterBase {
    public var w: Double
    public var h: Double
    public init(w: Double, h: Double) {
        self.w = w
        self.h = h
    }
}

/**
 * [VIEW_COORD_SYS]
 *
 * @final [NOTICE] Inheritance of this class is not recommended. Use composition instead.
 *
 * CONFORMANCE note (CONVENTIONS §2): upstream `class View extends Transformable implements
 *   CoordinateSystemMaster, CoordinateSystem`. The protocol conformances are DROPPED here (as for
 *   Polar/Radar): View's `dataToPoint(data, noRoam?, out?)` / `pointToData(point, reserved?, out?)`
 *   carry View-specific signatures that do NOT match the `CoordinateSystem` protocol requirements
 *   (`dataToPoint(data, opt?)` / `pointToData(point, opt?)`), and Geo (the only consumer in this phase)
 *   holds the concrete `View` type and calls the concrete methods. `Transformable` subclassing is
 *   preserved because VIEW_COORD_SYS_TRANS_OVERALL is copied onto the View/Geo instance itself for
 *   backward compatibility (see legacyCopyOverallTrans).
 *   re-add `CoordinateSystem`/`CoordinateSystemMaster` conformance when graph/tree/sankey
 *   (which use View as their `coordinateSystem`) are ported.
 *
 * ViewInner state: upstream stashes private props on the instance via `inner(this)` casting. Here they
 *   are real (internal) stored properties on `View`, accessed directly by the free functions below.
 */
open class View: Transformable {

    // upstream: static dimensions = ['x', 'y'];
    public static let dimensions: [DimensionName] = ["x", "y"]

    // upstream: readonly type: string = VIEW_COORD_SYS_TYPE;
    public let type: String = VIEW_COORD_SYS_TYPE

    // upstream: readonly dimensions = ['x', 'y'];
    public var dimensions: [DimensionName] = ["x", "y"]

    // ===== ViewInner state (upstream: interface ViewInner extends View) =====

    // upstream: invertY: boolean;
    var invertY: Bool = false

    // upstream: lgCt?: {w; h} | NullUndefined;  @see useLegacyViewCoordSysCenterBase
    var lgCt: ViewCoordSysLegacyCenterBase?

    // upstream: lgGeo?: Transformable;
    //   weak to break the Geo<->View retain cycle (Geo owns `view` strongly and passes itself as
    //   legacyGeo → view.lgGeo = geo). note: upstream holds a plain (strong) reference.
    weak var lgGeo: Transformable?

    // upstream: centerOption: RoamOptionMixin['center'] | NullUndefined;  (ROAM input, DEFERRED — stays nil)
    var centerOption: [Any]?

    // upstream: zoom: RoamOptionMixin['zoom'];
    var zoom: Double = 1

    // upstream: zoomLimit: RoamOptionMixin['scaleLimit'] | NullUndefined;  (ROAM input, DEFERRED — stays nil)
    var zoomLimit: RoamOptionMixin.ScaleLimit?

    // upstream: trans: Transformable[];  (indexed by VIEW_COORD_SYS_TRANS_RAW/_ROAM/_OVERALL)
    var trans: [Transformable] = []

    // upstream: mtRaw / mtRawInv / mtOverall / mtOverallInv: MatrixArray;
    var mtRaw: MatrixArray = matrix.create()
    var mtRawInv: MatrixArray = matrix.create()
    var mtOverall: MatrixArray = matrix.create()
    var mtOverallInv: MatrixArray = matrix.create()

    // upstream: dataRect / viewRect: BoundingRect | NullUndefined;  @see VIEW_COORD_SYS_TRANS_RAW
    var dataRect: BoundingRect?
    var viewRect: BoundingRect?

    // upstream: syncBackEl: Element | NullUndefined;
    var syncBackEl: Element?

    // upstream: syncBackType: typeof VIEW_COORD_SYS_TRANS_ROAM | typeof VIEW_COORD_SYS_TRANS_OVERALL;
    // Optional so that "never assigned" stays distinguishable from ROAM. Upstream's
    //   `ViewInner` is a `makeInner` bag whose `syncBackType` is `undefined` until
    //   `applyViewCoordSysTransToElement` writes it, and upstream relies on that: `viewCoordSysSyncBack`
    //   asserts `viewInner.syncBackType != null` (View.ts:653). A defaulted non-Optional Int would let
    //   an unset view read as a plausible ROAM and make the deferred `calcOverallTransFromSyncBackEl`
    //   (View.ts:387-402) pick the wrong trans slot.
    var syncBackType: Int?

    // upstream: constructor(invertY?, legacyCenterBase?, legacyGeo?) { super(); ... }
    public init(
        _ invertY: Bool? = nil,
        _ legacyCenterBase: ViewCoordSysLegacyCenterBase? = nil,
        _ legacyGeo: Transformable? = nil
    ) {
        super.init()

        self.invertY = invertY ?? false

        self.lgCt = legacyCenterBase
        self.lgGeo = legacyGeo

        // upstream: trans[RAW/ROAM/OVERALL] = transformableCreate();
        self.trans = [
            transformableCreate(),
            transformableCreate(),
            transformableCreate()
        ]

        self.mtRaw = matrix.create()
        self.mtRawInv = matrix.create()
        self.mtOverall = matrix.create()
        self.mtOverallInv = matrix.create()

        self.zoom = 1
    }

    /**
     * @implements CoordinateSystem['getBoundingRect']
     * @see VIEW_COORD_SYS_TRANS_RAW
     *
     * This is a rect in data space.
     * For historicall reason, the name is `getBoundingRect` - preserve it for backward compatibility.
     */
    // upstream: getBoundingRect() { return viewCoordSysCopyBoundingRect(null, this); }
    public func getBoundingRect() -> BoundingRect {
        return viewCoordSysCopyBoundingRect(nil, self)
    }

    /**
     * @implements CoordinateSystem['getViewRect']
     * @see VIEW_COORD_SYS_TRANS_RAW
     */
    // upstream: getViewRect() { return viewCoordSysCopyViewRect(null, this); }
    public func getViewRect() -> BoundingRect {
        return viewCoordSysCopyViewRect(nil, self)
    }

    /**
     * @implements CoordinateSystem['getRoamTransform']
     */
    // upstream: getRoamTransform() { return transformableGetLocalTransform(inner(this).trans[ROAM]); }
    public func getRoamTransform() -> MatrixArray {
        return transformableGetLocalTransform(self.trans[VIEW_COORD_SYS_TRANS_ROAM])
    }

    // upstream: dataToPoint(data, noRoam?, out?) {
    //     const transform = noRoam ? inner(this).mtRaw : inner(this).mtOverall;
    //     out = out || [];
    //     return transform ? vectorApplyTransform(out, data, transform) : vectorCopy(out, data);
    // }
    //   `out?` perf out-param dropped, value-returning (CONVENTIONS §3). `mtRaw`/`mtOverall` are always
    //   present (initialized to identity), so the `transform ?` branch is always the applyTransform path.
    public func dataToPoint(_ data: [Double], _ noRoam: Bool? = nil) -> [Double] {
        let transform = (noRoam == true) ? self.mtRaw : self.mtOverall
        let v = vector.applyTransform(VectorArray(data[0], data[1]), transform)
        return [v[0], v[1]]
    }

    // upstream: pointToData(point, reserved?, out?) {
    //     out = out || [];
    //     const invTransform = inner(this).mtOverallInv;
    //     return invTransform ? vectorApplyTransform(out, point, invTransform) : vectorCopy(out, point);
    // }
    public func pointToData(_ point: [Double], _ reserved: Any? = nil) -> [Double] {
        let invTransform = self.mtOverallInv
        let v = vector.applyTransform(VectorArray(point[0], point[1]), invTransform)
        return [v[0], v[1]]
    }

    // upstream: convertToPixel(ecModel, finder, value) {
    //     const coordSys = getCoordSys(finder);
    //     return coordSys === this ? coordSys.dataToPoint(value) : null;
    // }
    public func convertToPixel(
        _ ecModel: GlobalModel, _ finder: ParsedModelFinder, _ value: [Double]
    ) -> [Double]? {
        let coordSys = getCoordSys(finder)
        return coordSys === self ? coordSys!.dataToPoint(value) : nil
    }

    // upstream: convertFromPixel(ecModel, finder, pixel) {
    //     const coordSys = getCoordSys(finder);
    //     return coordSys === this ? coordSys.pointToData(pixel) : null;
    // }
    public func convertFromPixel(
        _ ecModel: GlobalModel, _ finder: ParsedModelFinder, _ pixel: [Double]
    ) -> [Double]? {
        let coordSys = getCoordSys(finder)
        return coordSys === self ? coordSys!.pointToData(pixel) : nil
    }

    // upstream: containPoint(point) {
    //     const viewInner = inner(this);
    //     boundingRectCopy(tmpPixelRectForContain, viewInner.dataRect);
    //     boundingRectApplyTransform(tmpPixelRectForContain, tmpPixelRectForContain, viewInner.mtOverall);
    //     return boundingRectContain(tmpPixelRectForContain, point[0], point[1]);
    // }
    public func containPoint(_ point: [Double]) -> Bool {
        guard let dataRect = self.dataRect else {
            return false
        }
        boundingRectCopy(tmpPixelRectForContain, dataRect)
        boundingRectApplyTransform(tmpPixelRectForContain, tmpPixelRectForContain, self.mtOverall)
        return boundingRectContain(tmpPixelRectForContain, point[0], point[1])
    }
}
// upstream: const tmpPixelRectForContain = boundingRectCreate();
private let tmpPixelRectForContain = boundingRectCreate()


// upstream: export function viewCoordSysCopyOverallMatrix(out, viewCoordSys): MatrixArray
//   { return matrixCopy(out || [], inner(viewCoordSys).mtOverall); }
public func viewCoordSysCopyOverallMatrix(
    _ out: MatrixArray?, _ viewCoordSys: View
) -> MatrixArray {
    return matrix.copy(viewCoordSys.mtOverall)
}

// upstream: export function viewCoordSysGetZoomOption(viewCoordSys) { return inner(viewCoordSys).zoom; }
public func viewCoordSysGetZoomOption(_ viewCoordSys: View) -> Double {
    return viewCoordSys.zoom
}

// upstream: export function viewCoordSysCopyBoundingRect(out, viewCoordSys): BoundingRect
//   { return boundingRectCopy(out || boundingRectCreate(), inner(viewCoordSys).dataRect); }
public func viewCoordSysCopyBoundingRect(
    _ out: BoundingRect?, _ viewCoordSys: View
) -> BoundingRect {
    return boundingRectCopy(out ?? boundingRectCreate(), viewCoordSys.dataRect!)
}

// upstream: export function viewCoordSysCopyViewRect(out, viewCoordSys): BoundingRect
//   { return boundingRectCopy(out || boundingRectCreate(), inner(viewCoordSys).viewRect); }
public func viewCoordSysCopyViewRect(
    _ out: BoundingRect?, _ viewCoordSys: View
) -> BoundingRect {
    return boundingRectCopy(out ?? boundingRectCreate(), viewCoordSys.viewRect!)
}

/**
 * Copy from `ViewInner['trans']`.
 */
// upstream: export function viewCoordSysCopyTrans(out, viewCoordSys, transKind): Transformable
//   { return copyTransform(out || transformableCreate(), inner(viewCoordSys).trans[transKind]); }
@discardableResult
public func viewCoordSysCopyTrans(
    _ out: Transformable?, _ viewCoordSys: View, _ transKind: Int
) -> Transformable {
    return copyTransform(
        out ?? transformableCreate(),
        viewCoordSys.trans[transKind]
    )
}

// upstream: function viewCoordSysIsInputReady(viewInner) {
//     return !!(viewInner.dataRect && viewInner.viewRect);
// }
private func viewCoordSysIsInputReady(_ view: View) -> Bool {
    return view.dataRect != nil && view.viewRect != nil
}

/**
 * @see ViewInner['dataRect']
 */
// upstream: export function viewCoordSysSetBoundingRect(viewCoordSys, x, y, width, height) {
//     const viewInner = inner(viewCoordSys);
//     viewInner.dataRect = new BoundingRect(x, y, width, height);
//     if (viewCoordSysIsInputReady(viewInner)) { viewCoordSysUpdateTransform(viewInner); }
// }
public func viewCoordSysSetBoundingRect(
    _ viewCoordSys: View, _ x: Double, _ y: Double, _ width: Double, _ height: Double
) {
    viewCoordSys.dataRect = BoundingRect(x, y, width, height)
    if viewCoordSysIsInputReady(viewCoordSys) {
        viewCoordSysUpdateTransform(viewCoordSys)
    }
}

/**
 * @see ViewInner['viewRect']
 */
// upstream: export function viewCoordSysSetViewRect(viewCoordSys, x, y, width, height) {
//     const viewInner = inner(viewCoordSys);
//     viewInner.viewRect = new BoundingRect(x, y, width, height);
//     if (viewCoordSysIsInputReady(viewInner)) { viewCoordSysUpdateTransform(viewInner); }
// }
public func viewCoordSysSetViewRect(
    _ viewCoordSys: View, _ x: Double, _ y: Double, _ width: Double, _ height: Double
) {
    viewCoordSys.viewRect = BoundingRect(x, y, width, height)
    if viewCoordSysIsInputReady(viewCoordSys) {
        viewCoordSysUpdateTransform(viewCoordSys)
    }
}

// upstream: function viewCoordSysUpdateTransform(viewInner) {
//     // The order matters.
//     viewCoordSysUpdateRawTrans(viewInner);
//     viewCoordSysUpdateRoamTrans(viewInner);
//     viewCoordSysUpdateOverallTrans(viewInner);
// }
private func viewCoordSysUpdateTransform(_ view: View) {
    // The order matters.
    viewCoordSysUpdateRawTrans(view)
    viewCoordSysUpdateRoamTrans(view)
    viewCoordSysUpdateOverallTrans(view)
}

// upstream: function viewCoordSysUpdateRawTrans(viewInner) { ... }
private func viewCoordSysUpdateRawTrans(_ view: View) {
    var dataRect = view.dataRect!
    let viewRect = view.viewRect!

    let rawTrans = view.trans[VIEW_COORD_SYS_TRANS_RAW]
    let invertY = view.invertY

    if invertY {
        // upstream: dataRect = boundingRectCopy(tmpRectURT, dataRect); dataRect.y = -dataRect.y - dataRect.height;
        let copied = boundingRectCopy(boundingRectCreate(), dataRect)
        copied.y = -copied.y - copied.height
        dataRect = copied
    }

    // upstream: boundingRectCalculateTransform(tmpMtURT, dataRect, viewRect);
    //           decomposeTransform(rawTrans, tmpMtURT);
    let mtURT = boundingRectCalculateTransform(nil, dataRect, viewRect)
    _ = decomposeTransform(rawTrans, mtURT)

    if invertY {
        rawTrans.scaleY = -rawTrans.scaleY
    }

    // upstream: const mtRaw = transformableGetLocalTransform(rawTrans, viewInner.mtRaw);
    //           matrixInvert(viewInner.mtRawInv, mtRaw);
    view.mtRaw = transformableGetLocalTransform(rawTrans, view.mtRaw)
    if let inv = matrix.invert(view.mtRaw) {
        view.mtRawInv = inv
    }
}

/**
 * NOTICE: It depends on `viewCoordSysUpdateRawTrans`.
 */
// upstream: function viewCoordSysUpdateRoamTrans(viewInner) { ... }
private func viewCoordSysUpdateRoamTrans(_ view: View) {
    let viewRectCenter = viewCoordSysGetViewRectCenter(view)
    // upstream: const roamViewCenter = parseCenterOption(tmpCenterURT, viewInner, viewInner.centerOption)
    //     ? vectorApplyTransform(tmpCenterURT, tmpCenterURT, viewInner.mtRaw)
    //     : viewRectCenter;
    var roamViewCenter: [Double]
    if let parsed = parseCenterOption(view, view.centerOption) {
        let v = vector.applyTransform(VectorArray(parsed[0], parsed[1]), view.mtRaw)
        roamViewCenter = [v[0], v[1]]
    }
    else {
        roamViewCenter = viewRectCenter
    }

    let zoom = view.zoom
    let roamTrans = view.trans[VIEW_COORD_SYS_TRANS_ROAM]
    roamTrans.x = viewRectCenter[0] - zoom * roamViewCenter[0]
    roamTrans.y = viewRectCenter[1] - zoom * roamViewCenter[1]
    roamTrans.scaleX = zoom
    roamTrans.scaleY = zoom
    // [VIEW_COORD_SYS_APPLY_ROAM_CENTER_AND_ZOOM] — see upstream comment for why originX/originY is not used.
}

/**
 * NOTICE: It depends on `viewCoordSysUpdateRoamTrans` and `viewCoordSysUpdateRawTrans`.
 */
// upstream: function viewCoordSysUpdateOverallTrans(viewInner) { ... }
private func viewCoordSysUpdateOverallTrans(_ view: View) {
    let trans = view.trans
    let roamTrans = trans[VIEW_COORD_SYS_TRANS_ROAM]
    let rawTrans = trans[VIEW_COORD_SYS_TRANS_RAW]
    let overallTrans = trans[VIEW_COORD_SYS_TRANS_OVERALL]

    calcOverallTrans(overallTrans, rawTrans, roamTrans)

    // upstream: const mtOverall = transformableGetLocalTransform(overallTrans, viewInner.mtOverall);
    //           const mtOverallInv = matrixInvert(viewInner.mtOverallInv, mtOverall);
    view.mtOverall = transformableGetLocalTransform(overallTrans, view.mtOverall)
    let mtOverall = view.mtOverall
    let mtOverallInv = matrix.invert(mtOverall)
    if let mtOverallInv = mtOverallInv {
        view.mtOverallInv = mtOverallInv
    }

    // upstream: legacyCopyOverallTrans(viewInner, overallTrans, mtOverall, mtOverallInv);
    //           legacyCopyOverallTrans(viewInner.lgGeo, overallTrans, mtOverall, mtOverallInv);
    legacyCopyOverallTrans(view, overallTrans, mtOverall, view.mtOverallInv)
    legacyCopyOverallTrans(view.lgGeo, overallTrans, mtOverall, view.mtOverallInv)
}

/**
 * [VIEW_COORD_SYS_TRANS_OVERALL_BACKWARD_COMPATIBILITY]
 *   VIEW_COORD_SYS_TRANS_OVERALL transformable has long been the View or Geo instance itself.
 *   We keep backward compatibility, since some users may have visited it directly.
 */
// upstream: function legacyCopyOverallTrans(target, overallTrans, mtOverall, mtOverallInv) {
//     if (target) {
//         copyTransform(target, overallTrans);
//         matrixCopy(target.transform || (target.transform = []), mtOverall);
//         matrixCopy(target.invTransform || (target.invTransform = []), mtOverallInv);
//     }
// }
private func legacyCopyOverallTrans(
    _ target: Transformable?,
    _ overallTrans: Transformable,
    _ mtOverall: MatrixArray,
    _ mtOverallInv: MatrixArray
) {
    if let target = target {
        copyTransform(target, overallTrans)
        target.transform = matrix.copy(mtOverall)
        target.invTransform = matrix.copy(mtOverallInv)
    }
}

// upstream: function calcOverallTrans(out, rawTrans, roamTrans) {
//     transformableGetLocalTransform(rawTrans, tmpMtCOT1);
//     transformableGetLocalTransform(roamTrans, tmpMtCOT2);
//     matrixMul(tmpMtCOT2, tmpMtCOT2, tmpMtCOT1);   // tmp2 = roam * raw
//     decomposeTransform(out, tmpMtCOT2);
// }
private func calcOverallTrans(
    _ out: Transformable, _ rawTrans: Transformable, _ roamTrans: Transformable
) {
    let mtRaw = transformableGetLocalTransform(rawTrans)
    let mtRoam = transformableGetLocalTransform(roamTrans)
    let m = matrix.mul(mtRoam, mtRaw)
    _ = decomposeTransform(out, m)
}

// upstream: function getCoordSys(finder: ParsedModelFinderKnown): View {
//     const seriesModel = finder.seriesModel;
//     return seriesModel ? seriesModel.coordinateSystem as View : null; // e.g., graph.
// }
private func getCoordSys(_ finder: ParsedModelFinderKnown) -> View? {
    let seriesModel = finder["seriesModel"] as? SeriesModel
    return seriesModel?.coordinateSystem as? View
}

// upstream: function viewCoordSysGetViewRectCenter(viewInner): number[] {
//     const viewRect = viewInner.viewRect;
//     tmpViewRectCenter[0] = viewRect.x + viewRect.width / 2;
//     tmpViewRectCenter[1] = viewRect.y + viewRect.height / 2;
//     return tmpViewRectCenter;
// }
private func viewCoordSysGetViewRectCenter(_ view: View) -> [Double] {
    let viewRect = view.viewRect!
    return [
        viewRect.x + viewRect.width / 2,
        viewRect.y + viewRect.height / 2
    ]
}

// upstream: export function isViewCoordSys(coordSys): coordSys is View {
//     return coordSys && coordSys.type === 'view';
// }
public func isViewCoordSys(_ coordSys: CoordinateSystem?) -> Bool {
    return coordSys != nil && coordSys!.type == VIEW_COORD_SYS_TYPE
}

/**
 * NOTICE:
 *  - `syncBackEl` should be in the pixel space without any other transformation
 *    in its accesters, otherwise the roaming may incorrect.
 *  - `syncBackEl` can be a `Group`, having its own descendants and transformation.
 *    But in this case, `dataToPoint` can only reach the space of `syncBackEl` itself.
 */
// upstream: export function applyViewCoordSysTransToElement(syncBackEl, syncBackType, viewCoordSys, animatableModel)
//   viewInner.syncBackEl = syncBackEl; viewInner.syncBackType = syncBackType;
//   if (!animatableModel) { viewCoordSysCopyTrans(syncBackEl, viewCoordSys, syncBackType); syncBackEl.dirty(); }
//   else { updateProps(syncBackEl, viewCoordSysCopyTrans(null, viewCoordSys, syncBackType), animatableModel); }
//   `animatableModel == nil` => no animation (first render / __updateOnOwnRoam). Upstream types
//   syncBackEl as nullable and calls dirty()/updateProps optimistically; per PORTING.md §12 we port
//   the force-deref as optional-chaining (`syncBackEl?.dirty()`) / an `if let` guard rather than `!`.
//   Upstream hands the whole copied `Transformable` to `updateProps`, and zrender's `copyTransform`
//   writes all 11 TRANSFORMABLE_PROPS as own properties, so upstream animates all 11. The Swift
//   `updateProps` takes a `[String: Any]`, so marshal the SAME 11 keys via
//   `transformablePropsDict` — both branches must propagate an identical prop set (a
//   VIEW_COORD_SYS_TRANS_OVERALL trans for `invertY` decomposes to `skewX = .pi` with a negated
//   `scaleY`, which a narrowed x/y/scaleX/scaleY dict would silently drop).
public func applyViewCoordSysTransToElement(
    _ syncBackEl: Element?, _ syncBackType: Int, _ viewCoordSys: View, _ animatableModel: Model?
) {
    viewCoordSys.syncBackEl = syncBackEl
    viewCoordSys.syncBackType = syncBackType

    if animatableModel == nil {
        viewCoordSysCopyTrans(syncBackEl, viewCoordSys, syncBackType)
        syncBackEl?.dirty()
    }
    else if let syncBackEl = syncBackEl {
        let trans = viewCoordSysCopyTrans(nil, viewCoordSys, syncBackType)
        updateProps(syncBackEl, transformablePropsDict(trans), animatableModel)
    }
}

// no upstream counterpart — upstream passes the `Transformable` object straight to
//   `updateProps`, which reads the keys off it. The Swift `updateProps` is dict-based, so this
//   adapter enumerates the same key list as `ZRenderKit.copyTransform`
//   (Sources/ZRenderKit/Core/Transformable.swift TRANSFORMABLE_PROPS). Keep the two in sync;
//   every property is a non-Optional `Double`, matching `Element.attrKV`'s `value as? Double`.
func transformablePropsDict(_ t: Transformable) -> [String: Any] {
    return [
        "x": t.x,
        "y": t.y,
        "originX": t.originX,
        "originY": t.originY,
        "anchorX": t.anchorX,
        "anchorY": t.anchorY,
        "rotation": t.rotation,
        "scaleX": t.scaleX,
        "scaleY": t.scaleY,
        "skewX": t.skewX,
        "skewY": t.skewY
    ]
}

// upstream: function parseCenterOption(out, viewInner, centerOption): boolean { ... }
//   Returns the parsed center in `dataRect` space, or nil when no valid center (upstream `false`).
//   The `out`-param + boolean-return pattern collapses to an `Optional` (nil == false).
//   ROAM path: `centerOption` is nil in the static render, so this returns nil.
private func parseCenterOption(_ view: View, _ centerOption: [Any]?) -> [Double]? {
    let dataRect = view.dataRect
    guard let centerOption = centerOption else {
        // upstream: if (!centerOption) { return false; }
        return nil
    }
    // #16904 percentage is based on `ViewInner['dataRect'].width/height` since v6.
    if let lgCt = view.lgCt {
        return [
            number.parsePercent(centerOption[0], lgCt.w),
            number.parsePercent(centerOption[1], lgCt.h)
        ]
    }
    else if let dataRect = dataRect {
        return [
            number.parsePercent(centerOption[0], dataRect.width, dataRect.x),
            number.parsePercent(centerOption[1], dataRect.height, dataRect.y)
        ]
    }
    // upstream reaches `return true` even without lgCt/dataRect, but `out` would be unset.
    // In practice `dataRect` is always present when this is called (viewCoordSysIsInputReady).
    return []
}

// upstream: function invertBackToCenterOption(viewInner, center): RoamOptionMixin['center'] {
//     const lastCenterOption = viewInner.centerOption;
//     const dataRect = viewInner.dataRect;
//     return (!lastCenterOption || viewInner.lgCt)
//         ? center.slice()
//         : [
//             invertToPercentPerCenterDim(0, center, lastCenterOption, dataRect),
//             invertToPercentPerCenterDim(1, center, lastCenterOption, dataRect),
//         ];
// }
//   An inverse operation to `parseCenterOption` — mainly for a percentage center option. Returns `[Any]`
//   because a dim may round-trip to a "xx%" String (percent center) or stay a Double.
private func invertBackToCenterOption(_ view: View, _ center: [Double]) -> [Any] {
    let lastCenterOption = view.centerOption
    let dataRect = view.dataRect
    if lastCenterOption == nil || view.lgCt != nil {
        // upstream: center.slice()
        return [center[0], center[1]]
    }
    return [
        invertToPercentPerCenterDim(0, center, lastCenterOption!, dataRect),
        invertToPercentPerCenterDim(1, center, lastCenterOption!, dataRect)
    ]
}

// upstream: function invertToPercentPerCenterDim(dimIdx, center, lastCenterOption, dataRect) {
//     return (lastCenterOption && dataRect && dataRect[WH[dimIdx]]
//             && isPositionSizeOptionPercent(lastCenterOption[dimIdx]))
//         ? ((center[dimIdx] - dataRect[XY[dimIdx]]) / dataRect[WH[dimIdx]] * 100) + '%'
//         : center[dimIdx];
// }
//   WH = ['width','height'], XY = ['x','y'] (util/graphic) -> BoundingRect accessors below.
private func invertToPercentPerCenterDim(
    _ dimIdx: Int, _ center: [Double], _ lastCenterOption: [Any], _ dataRect: BoundingRect?
) -> Any {
    let wh = dataRect.map { dimIdx == 0 ? $0.width : $0.height }   // dataRect[WH[dimIdx]]
    let xy = dataRect.map { dimIdx == 0 ? $0.x : $0.y }            // dataRect[XY[dimIdx]]
    if let wh = wh, let xy = xy, wh != 0,
       dimIdx < lastCenterOption.count,
       number.isPositionSizeOptionPercent(lastCenterOption[dimIdx]) {
        // upstream: ((center - dataRect.xy) / dataRect.wh * 100) + '%'
        return jsNumberToString((center[dimIdx] - xy) / wh * 100) + "%"
    }
    return center[dimIdx]
}

// upstream: export function useLegacyViewCoordSysCenterBase(ecModel, api): ViewInner['lgCt'] {
//     return (api && ecModel && ecModel.getShallow('legacyViewCoordSysCenterBase'))
//         ? {w: api.getWidth(), h: api.getHeight()}
//         : null;
// }
public func useLegacyViewCoordSysCenterBase(
    _ ecModel: GlobalModel?, _ api: ExtensionAPI?
) -> ViewCoordSysLegacyCenterBase? {
    if let api = api, let ecModel = ecModel,
       jsTruthy(ecModel.getShallow("legacyViewCoordSysCenterBase")) {
        return ViewCoordSysLegacyCenterBase(w: api.getWidth(), h: api.getHeight())
    }
    return nil
}

// upstream: export function clampByZoomLimit(zoom, zoomLimit): number {
//     if (zoomLimit) {
//         const zoomMin = zoomLimit.min || 0;
//         const zoomMax = zoomLimit.max || Infinity;
//         zoom = Math.max(Math.min(zoomMax, zoom), zoomMin);
//     }
//     return zoom;
// }
public func clampByZoomLimit(
    _ zoom: Double, _ zoomLimit: RoamOptionMixin.ScaleLimit?
) -> Double {
    var zoom = zoom
    if let zoomLimit = zoomLimit {
        let zoomMin = jsNumOr(zoomLimit.min, 0)              // upstream: zoomLimit.min || 0
        let zoomMax = jsNumOr(zoomLimit.max, Double.infinity) // upstream: zoomLimit.max || Infinity
        zoom = Swift.max(Swift.min(zoomMax, zoom), zoomMin)
    }
    return zoom
}

// =====================================================================================================
// ROAM (pan/zoom) — the value-based subset of upstream's roam interaction flow (geo/map roam, Phase 40).
//   Upstream stores roam center/zoom on the host MODEL option (`syncBackRoamOptionToRoamHostModel`) and
//   re-reads them via `viewCoordSysSetRoamOptionFromModel`. The port keeps roam state in a per-host-model
//   inner store (see roamHelperGeo) — same lifetime — so these two entry points take VALUES rather than a
//   model: `viewCoordSysSetRoamOption` (re-apply center/zoom, mirrors viewCoordSysSetRoamOptionFromModel)
//   and `viewCoordSysApplyRoamPayloadSyncBack` (apply a pan/zoom payload to the OVERALL trans, then invert
//   back to a data-space center + zoom, mirrors viewCoordSysSyncBack minus the roaming-animation syncBackEl).
// =====================================================================================================

// upstream: viewCoordSysSetRoamOptionFromModel(viewCoordSys, hostModel) — but reading VALUES (the port's
//   roam state store) instead of `hostModel.getShallow('center'|'zoom'|'scaleLimit')`.
//     viewInner.centerOption = center; viewInner.zoomLimit = zoomLimit;
//     viewInner.zoom = clampByZoomLimit(zoomOption || 1, zoomLimit) || 1;
//     if (viewCoordSysIsInputReady(viewInner)) { viewCoordSysUpdateTransform(viewInner); }
public func viewCoordSysSetRoamOption(
    _ viewCoordSys: View, _ centerOption: [Any]?, _ zoomOption: Double?, _ zoomLimit: RoamOptionMixin.ScaleLimit?
) {
    viewCoordSys.centerOption = centerOption
    viewCoordSys.zoomLimit = zoomLimit
    viewCoordSys.zoom = jsNumOr(clampByZoomLimit(jsNumOr(zoomOption, 1), zoomLimit), 1)
    if viewCoordSysIsInputReady(viewCoordSys) {
        viewCoordSysUpdateTransform(viewCoordSys)
    }
}

// upstream: getZoomFromRoamTrans(trans) { return trans.scaleX; }
//   (scaleX == scaleY, see VIEW_COORD_SYS_APPLY_ROAM_CENTER_AND_ZOOM.)
private func getZoomFromRoamTrans(_ trans: Transformable) -> Double {
    return trans.scaleX
}

// upstream: calcRoamTransFromOverallTrans(out, viewInner, overallTrans) {
//     transformableGetLocalTransform(overallTrans, tmpMtRTO);
//     matrixMul(tmpMtRTO, tmpMtRTO, viewInner.mtRawInv);   // roamTrans = overallTrans * invert(rawTrans)
//     decomposeTransform(out, tmpMtRTO);
// }
private func calcRoamTransFromOverallTrans(_ out: Transformable, _ view: View, _ overallTrans: Transformable) {
    let mt = transformableGetLocalTransform(overallTrans)
    let m = matrix.mul(mt, view.mtRawInv)   // matrix.mul(a, b) == a * b (see calcOverallTrans)
    _ = decomposeTransform(out, m)
}

// upstream: applyRoamPayloadToOverallTrans(targetOverallTrans, roamTrans, viewInner, payload)
//   NOTE: payload.dx/dy are always applied in pixel space (i.e., to overallTrans).
private func applyRoamPayloadToOverallTrans(
    _ targetOverallTrans: Transformable,
    _ roamTrans: Transformable,
    _ view: View,
    _ dx: Double?, _ dy: Double?, _ zoom: Double?, _ originX: Double, _ originY: Double
) {
    if let dx = dx, let dy = dy {
        targetOverallTrans.x += dx
        targetOverallTrans.y += dy
    }
    if let deltaZoom = zoom {
        let oldZoom = getZoomFromRoamTrans(roamTrans)
        let newZoom = clampByZoomLimit(oldZoom * deltaZoom, view.zoomLimit)
        let deltaZoom2 = oldZoom != 0 ? newZoom / oldZoom : 1
        // Keep the mouse center when scaling.
        targetOverallTrans.x -= (originX - targetOverallTrans.x) * (deltaZoom2 - 1)
        targetOverallTrans.y -= (originY - targetOverallTrans.y) * (deltaZoom2 - 1)
        targetOverallTrans.scaleX *= deltaZoom2
        targetOverallTrans.scaleY *= deltaZoom2
    }
}

// upstream: viewCoordSysSyncBack(viewCoordSys, hostModel, otherModelsToSync, payload) +
//   syncBackToRoamOptionFromRoamTrans — but RETURNING (center, zoom) instead of writing the model option
//   (the port stores roam state in an inner store). The roaming-animation `syncBackEl` branch is DEFERRED,
//   so the OVERALL trans is read directly (upstream's `else` branch: copyTransform(sb1, trans[OVERALL])).
//   `center` is returned via `invertBackToCenterOption` — i.e. in DATA space (numeric) unless the last
//   `centerOption` was a percent string, in which case the matching dim round-trips back to a "xx%" String
//   (hence the `[Any]` element type). The roaming-animation `syncBackEl` branch stays DEFERRED.
public func viewCoordSysApplyRoamPayloadSyncBack(
    _ viewCoordSys: View, _ dx: Double?, _ dy: Double?, _ zoom: Double?, _ originX: Double, _ originY: Double
) -> (center: [Any], zoom: Double) {
    // sb1 = current overall trans; sb2 = roamTrans derived from it (for the old zoom).
    let sb1 = copyTransform(transformableCreate(), viewCoordSys.trans[VIEW_COORD_SYS_TRANS_OVERALL])
    let sb2 = transformableCreate()
    calcRoamTransFromOverallTrans(sb2, viewCoordSys, sb1)
    // Apply the payload to the OVERALL trans, then re-derive roamTrans into sb1.
    applyRoamPayloadToOverallTrans(sb1, sb2, viewCoordSys, dx, dy, zoom, originX, originY)
    calcRoamTransFromOverallTrans(sb1, viewCoordSys, sb1)

    // syncBackToRoamOptionFromRoamTrans: invert roamTrans → (center in data space, zoom).
    let viewRectCenter = viewCoordSysGetViewRectCenter(viewCoordSys)
    let z = getZoomFromRoamTrans(sb1)
    let notZoomNearZero = abs(z) > 1e-6
    let cvx = notZoomNearZero ? (viewRectCenter[0] - sb1.x) / z : viewRectCenter[0]
    let cvy = notZoomNearZero ? (viewRectCenter[1] - sb1.y) / z : viewRectCenter[1]
    let cData = vector.applyTransform(VectorArray(cvx, cvy), viewCoordSys.mtRawInv)
    // upstream: const centerOption = invertBackToCenterOption(viewInner, tmpCenterITR);
    //   Preserve a percent centerOption round-trip when the last center was a percent string.
    let centerOption = invertBackToCenterOption(viewCoordSys, [cData[0], cData[1]])
    return (centerOption, z)
}

// upstream: export function calcCompensationScaleToPreserveNodeSize(viewCoordSys, model) {
//     const nodeScaleRatio = (model.getShallow('nodeScaleRatio', true) || 1);
//     const viewInner = inner(viewCoordSys);
//     // Scale node when zoom changes
//     return ((viewInner.zoom - 1) * nodeScaleRatio + 1)
//         / (viewInner.trans[VIEW_COORD_SYS_TRANS_OVERALL].scaleX || 1);
// }
//   Standalone transform read (no roam-interaction module needed): graph/tree/sankey use it to keep
//   node symbol size constant while the view is zoomed. `nodeScaleRatio` is boxed as Int/Double in the
//   option bag (see Int-vs-Double option-read trap) → coerce via anyToDouble before the JS `|| 1`.
public func calcCompensationScaleToPreserveNodeSize(
    _ viewCoordSys: View, _ model: Model
) -> Double {
    let nodeScaleRatio = jsNumOr(anyToDouble(model.getShallow("nodeScaleRatio", true)), 1)
    // Scale node when zoom changes
    return ((viewCoordSys.zoom - 1) * nodeScaleRatio + 1)
        / jsNumOr(viewCoordSys.trans[VIEW_COORD_SYS_TRANS_OVERALL].scaleX, 1)
}

// TODO: requires the ROAM interaction module. The following upstream exports are part of the roam interaction /
//   roaming-animation / sync-back flow and are NOT ported in this phase (CONVENTIONS §5):
//     ownRoamModelCoordSysUpdateInAction, getOwnRoamViewCoordSys,
//     ownRoamViewUpdateDirectlyInAction, calcOverallTransFromSyncBackEl,
//     syncBackToRoamOptionFromRoamTrans (model write-back), syncBackRoamOptionToRoamHostModel.

// ===== Private helpers =====

// upstream: import { decomposeTransform } from '../util/graphic';
//   Reproduced here (util/graphic.swift has not landed this export yet). Decomposes an affine matrix
//   into x/y/scaleX/scaleY/rotation/skewX/skewY on `out`, using a parent-less tmp Transformable to
//   avoid parent effects (upstream `tmpDTR`). note: dedupe once util/graphic.decomposeTransform lands.
private let tmpDTR: Transformable = {
    let t = Transformable()
    t.transform = matrix.create()
    return t
}()
@discardableResult
private func decomposeTransform(_ out: Transformable, _ mt: MatrixArray?) -> Transformable {
    if let mt = mt {
        tmpDTR.transform = matrix.copy(mt)
    }
    else {
        tmpDTR.transform = matrix.identity()
    }
    // Use a tmp transformable to avoid effects from parent.
    tmpDTR.decomposeTransform()
    copyTransform(out, tmpDTR)
    return out
}

// Coerce an option-bag value (ModelOption = Any) to a Double, or nil when non-numeric.
//   Numbers are boxed as Int or Double in the option bag (see Int-vs-Double option-read trap).
private func anyToDouble(_ v: Any?) -> Double? {
    switch v {
    case let d as Double: return d
    case let i as Int: return Double(i)
    case let f as Float: return Double(f)
    default: return nil
    }
}

// JS `value + ''` for a number (used by invertToPercentPerCenterDim's `... + '%'`). Integers render
//   without a decimal point (`50` → "50"); non-integers keep their shortest decimal form.
//   not a full ECMAScript Number→String (no exponent form).
private func jsNumberToString(_ v: Double) -> String {
    if v.isNaN { return "NaN" }
    if v == v.rounded() && Swift.abs(v) < 1e15 {
        return String(Int(v))
    }
    return String(v)
}

// JS `x || fallback` for a numeric optional (undefined/0/NaN are falsy → fallback).
private func jsNumOr(_ x: Double?, _ fallback: Double) -> Double {
    guard let x = x, x != 0, !x.isNaN else {
        return fallback
    }
    return x
}

// JS truthiness for an `Any?` option value (util/graphic-style; see other ported call sites).
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

// export default View;  -> `open class View` above.
