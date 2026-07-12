// Ported from echarts/src/chart/helper/createClipPathFromCoordSys.ts — keep in sync with upstream
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

// upstream:
// import * as graphic from '../../util/graphic';
//   -> `graphic.Rect` / `graphic.Sector` / `graphic.Path` are re-exports of the zrender shapes, so
//      ZRenderKit `Rect` / `Sector` / `Path` are used directly. `graphic.initProps` (a re-export of
//      `animation/basicTransition.initProps`) is ported and is applied in `createGridClipPath`
//      below.
// import {round} from '../../util/number';                        -> `number.round` (util/number.swift)
// import SeriesModel from '../../model/Series';                   -> `SeriesModel` (this module)
// import { NullUndefined, SeriesOption } from '../../util/types';
//   -> `NullUndefined` collapses to Optional (CONVENTIONS §6); `SeriesOption` is only used to
//      parametrize `SeriesModel<...>`, which is non-generic here (see `SeriesModelWithLineWidth`).
// import type Cartesian2D from '../../coord/cartesian/Cartesian2D'; -> `Cartesian2D` (this module)
// import type Polar from '../../coord/polar/Polar';                 -> coord/polar/Polar.swift (ported; the polar branch here is still deferred — see below).
// import { CoordinateSystem, CoordinateSystemClipArea } from '../../coord/CoordinateSystem';
//   -> `CoordinateSystem` / `CoordinateSystemClipArea` (coord/CoordinateSystem.swift)
// import { assert, isFunction } from 'zrender/src/core/util';      -> `util.assert` / `util.isFunction`
// import type Element from 'zrender/src/Element';                  -> `Element` (ZRenderKit)

// upstream:
// type SeriesModelWithLineWidth = SeriesModel<SeriesOption & { lineStyle?: { width?: number } }>;
//   The generic parameter collapses (SeriesModel is a non-generic `open class`); the `lineStyle.width`
//   field is read dynamically via `get(['lineStyle', 'width'])` (see below). So the alias is just
//   `SeriesModel`.
public typealias SeriesModelWithLineWidth = SeriesModel

public func createGridClipPath(
    _ cartesian: Cartesian2D,
    _ hasAnimation: Bool,
    _ seriesModel: SeriesModelWithLineWidth,
    _ done: (() -> Void)? = nil,
    _ during: ((Double, Rect) -> Void)? = nil
) -> Rect {
    let rect = cartesian.getArea()

    var x = rect.x
    var y = rect.y
    var width = rect.width
    var height = rect.height

    // upstream: const lineWidth = seriesModel.get(['lineStyle', 'width']) || 0;
    let lineWidth = (seriesModel.get(["lineStyle", "width"]) as? Double) ?? 0
    // Expand the clip path a bit to avoid the border is clipped and looks thinner
    x -= lineWidth / 2
    y -= lineWidth / 2
    width += lineWidth
    height += lineWidth

    // fix: https://github.com/apache/incubator-echarts/issues/11369
    width = ceil(width)
    if x != floor(x) {
        x = floor(x)
        // if no extra 1px on `width`, it will still be clipped since `x` is floored
        width += 1
    }

    // upstream: new graphic.Rect({ shape: { x, y, width, height } })
    var initialShape = RectShape()
    initialShape.x = x
    initialShape.y = y
    initialShape.width = width
    initialShape.height = height
    let clipPath = Rect(["shape": initialShape])

    if hasAnimation {
        let baseAxis = cartesian.getBaseAxis()
        let isHorizontal = baseAxis.isHorizontal()
        let isAxisInversed = baseAxis.inverse

        // upstream mutates `clipPath.shape.x`/`.width`/... in place. Our `shape` is a value-typed
        //   `RectShape` behind `PathShape!`, so read-modify-write it wholesale.
        var shape = clipPath.shape as! RectShape
        if isHorizontal {
            if isAxisInversed {
                shape.x += width
            }
            shape.width = 0
        }
        else {
            if !isAxisInversed {
                shape.y += height
            }
            shape.height = 0
        }
        clipPath.shape = shape

        // upstream:
        //   const duringCb = isFunction(during) ? (percent) => { during(percent, clipPath); } : null;
        let duringCb: ((Double) -> Void)? = util.isFunction(during)
            ? { percent in during!(percent, clipPath) }
            : nil

        // upstream:
        //   graphic.initProps(clipPath, { shape: { width, height, x, y } }, seriesModel, null, done, duringCb);
        //
        // Shape props are passed as a DICT (not a RectShape struct) — initProps/animateTo diff against
        // arbitrary keyed prop bags, and a struct value is opaque to the animator (it would just snap
        // to the final value instead of interpolating each field).
        initProps(clipPath,
                  ["shape": ["width": width, "height": height, "x": x, "y": y] as [String: Any]],
                  seriesModel, nil,
                  done,
                  duringCb)
    }

    return clipPath
}

// upstream: export function createPolarClipPath(polar, hasAnimation, seriesModel): graphic.Sector
public func createPolarClipPath(
    _ polar: Polar,
    _ hasAnimation: Bool,
    _ seriesModel: SeriesModelWithLineWidth
) -> Sector {
    let sectorArea = polar.getArea()
    // Avoid float number rounding error for symbol on the edge of axis extent.
    let r0 = number.round(sectorArea.r0, 1)
    let r = number.round(sectorArea.r, 1)

    // upstream: new graphic.Sector({ shape: { cx, cy, r0, r, startAngle, endAngle, clockwise } })
    var initialShape = SectorShape()
    initialShape.cx = number.round(polar.cx, 1)
    initialShape.cy = number.round(polar.cy, 1)
    initialShape.r0 = r0
    initialShape.r = r
    initialShape.startAngle = sectorArea.startAngle
    initialShape.endAngle = sectorArea.endAngle
    initialShape.clockwise = sectorArea.clockwise
    let clipPath = Sector(["shape": initialShape])

    if hasAnimation {
        let isRadial = polar.getBaseAxis().dim == "angle"
        // upstream mutates `clipPath.shape.endAngle`/`.r` in place; our `shape` is a value-typed
        //   `SectorShape` behind `PathShape!`, so read-modify-write it wholesale (see createGridClipPath).
        var shape = clipPath.shape as! SectorShape
        if isRadial {
            shape.endAngle = sectorArea.startAngle
        }
        else {
            shape.r = r0
        }
        clipPath.shape = shape

        // upstream: graphic.initProps(clipPath, { shape: { endAngle, r } }, seriesModel);
        //   Shape props are passed as a DICT (not a SectorShape struct) so the animator diffs per-field.
        initProps(clipPath,
                  ["shape": ["endAngle": sectorArea.endAngle, "r": r] as [String: Any]],
                  seriesModel)
    }

    return clipPath
}

public func createClipPath(
    _ coordSys: CoordinateSystem?,
    _ hasAnimation: Bool,
    _ seriesModel: SeriesModelWithLineWidth,
    _ done: (() -> Void)? = nil,
    _ during: ((Double) -> Void)? = nil
) -> Path? {
    if coordSys == nil {
        return nil
    }
    else if coordSys!.type == "polar" {
        // upstream: return createPolarClipPath(coordSys as Polar, hasAnimation, seriesModel);
        guard let polar = coordSys as? Polar else {
            return nil
        }
        return createPolarClipPath(polar, hasAnimation, seriesModel)
    }
    else if coordSys!.type == "cartesian2d" {
        guard let cartesian = coordSys as? Cartesian2D else {
            return nil
        }
        // upstream `createGridClipPath`'s `during` is `(percent, clipRect) => void`; `createClipPath`'s
        //   `during` is `(percent) => void`. TS silently drops the extra argument — adapt the arity by
        //   wrapping into a 2-arg closure that ignores `clipRect`.
        let gridDuring: ((Double, Rect) -> Void)? = during.map { d in { percent, _ in d(percent) } }
        return createGridClipPath(cartesian, hasAnimation, seriesModel, done, gridDuring)
    }
    return nil
}

// upstream:
//   export type ShapeClipKind = typeof SHAPE_CLIP_KIND_NOT_CLIPPED | ...;
//   export const SHAPE_CLIP_KIND_NOT_CLIPPED = 0; (etc.)
// PORT-NOTE: the union-of-literal-types `ShapeClipKind` is erased to `Int` (the constants' runtime
//   type); callers compare against the `SHAPE_CLIP_KIND_*` constants below.
public typealias ShapeClipKind = Int
public let SHAPE_CLIP_KIND_NOT_CLIPPED = 0
public let SHAPE_CLIP_KIND_PARTIALLY_CLIPPED = 1
public let SHAPE_CLIP_KIND_FULLY_CLIPPED = 2

public func updateClipPath(
    _ clip: Bool,
    _ symbolEl: Element,
    _ clipPath: Path?
) {
    if clip {
        if __DEV__ {
            util.assert(clipPath != nil)
        }
        // upstream: symbolEl.setClipPath(clipPath) — `setClipPath` takes a non-optional Path, so unwrap
        //   (guarded by the DEV assert above; matches upstream's non-null contract in `clip` mode).
        if let clipPath = clipPath {
            symbolEl.setClipPath(clipPath)
        }
    }
    else {
        symbolEl.removeClipPath()
    }
}

// upstream:
//   export function createCoordSysClipAreaSimply(
//       seriesModel: SeriesModel<SeriesOption & {clip?: boolean}>
//   ): CoordinateSystemClipArea | NullUndefined
public func createCoordSysClipAreaSimply(
    _ seriesModel: SeriesModel
) -> CoordinateSystemClipArea? {
    // upstream: const coordSys = seriesModel.coordinateSystem;
    //   `coordinateSystem` is `Any?` on SeriesModel; narrow to the coord-sys protocol.
    let coordSys = seriesModel.coordinateSystem as? CoordinateSystem

    // upstream: seriesModel.get('clip', true) — default `clip: true`; used in a boolean `&&`.
    let clip = (seriesModel.get("clip", true) as? Bool) ?? false

    // upstream: (!coordSys.shouldClip || coordSys.shouldClip())
    //   `shouldClip` is optional; our protocol default returns nil. `!coordSys.shouldClip` (method
    //   absent) is emulated by `shouldClip() == nil`, in which case the condition is `true`; otherwise
    //   the method's Bool result is used. => `shouldClip() ?? true`.
    if clip,
       let coordSys = coordSys,
       (coordSys.shouldClip() ?? true) {
        // PENDING make `0.1` configurable, for example, `clipTolerance`?
        // upstream: return coordSys.getArea && coordSys.getArea(.1);
        // POTENTIAL-BUG: `getArea` is an optional coord-sys method whose default returns nil, and (per the
        //   note in Cartesian2D.getArea) the concrete `Cartesian2D.getArea` does NOT satisfy the
        //   protocol witness (covariant `Cartesian2DArea` return vs the protocol's `CoordinateSystemClipArea?`
        //   existential — Swift does not accept a covariant return as a witness), so this protocol-dispatched
        //   call currently yields `nil` for cartesian2d. Fix requires unifying the `getArea` witness in
        //   coord/cartesian/Cartesian2D.swift (out of this file's scope).
        return coordSys.getArea(0.1)
    }
    return nil
}
