// Ported from echarts/src/util/layout.ts — keep in sync with upstream
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

// PORT-TODO: This is a PARTIAL port of util/layout.ts landing the surface needed by coord/cartesian
//   (Grid). The full module (positionElement / mergeLayoutParam / getCircleLayout / applyPreserveAspect
//   / fetchLayoutMode / getLayoutParams / copyLayoutParams, and the `boxCoordinateSystem` branch of
//   `createBoxLayoutReference`) lands with the layout/orchestrator phase. `LayoutRect` is currently the
//   `typealias LayoutRect = BoundingRect` declared in coord/cartesian/cartesianAxisHelper.swift.
//
// import * as formatUtil from './format';        -> `format.*` (util/format.swift)
// import { parsePercent } from './number';       -> `number.parsePercent` (util/number.swift)
// import BoundingRect from 'zrender/src/core/BoundingRect';  -> ZRenderKit BoundingRect
// import { error } from './log';                  -> `log.error`

// upstream: `const BoxLayoutReferenceType = { rect: 1, point: 2 } as const;`
public let BOX_LAYOUT_REFERENCE_TYPE_RECT: Double = 1
public let BOX_LAYOUT_REFERENCE_TYPE_POINT: Double = 2

// upstream union `BoxLayoutReferenceRectResult | BoxLayoutReferencePointResult` collapsed to one struct
//   (data bag, no identity → struct per CONVENTIONS §4). `refContainer` is present for the rect kind.
public struct BoxLayoutReferenceResult {
    // upstream: `type: BoxLayoutReferenceType`
    public var type: Double
    // upstream: `refContainer: LayoutRect` (rect kind). The center of rect in `refPoint`.
    public var refContainer: LayoutRect
    // upstream: `refPoint: number[]`
    public var refPoint: [Double]
    // upstream: `boxCoordFrom: BoxCoordinateSystemCoordFrom | NullUndefined`
    // PORT-TODO: `BoxCoordinateSystemCoordFrom` modeled as `Any?` until the box coord-sys layer lands.
    public var boxCoordFrom: Any?

    public init(type: Double, refContainer: LayoutRect, refPoint: [Double], boxCoordFrom: Any? = nil) {
        self.type = type
        self.refContainer = refContainer
        self.refPoint = refPoint
        self.boxCoordFrom = boxCoordFrom
    }
}

// upstream module `layout.ts` (free functions) -> caseless enum namespace `layout` (CONVENTIONS §2).
public enum layout {

    /**
     * Retrieve `left, right, top, bottom, width, height` from `Model`.
     */
    // upstream: getBoxLayoutParams(boxLayoutModel: Model<BoxLayoutOptionMixin>, ignoreParent: boolean)
    public static func getBoxLayoutParams(_ boxLayoutModel: Model, _ ignoreParent: Bool) -> BoxLayoutOptionMixin {
        var m = BoxLayoutOptionMixin()
        m.left = boxLayoutModel.getShallow("left", ignoreParent)
        m.top = boxLayoutModel.getShallow("top", ignoreParent)
        m.right = boxLayoutModel.getShallow("right", ignoreParent)
        m.bottom = boxLayoutModel.getShallow("bottom", ignoreParent)
        m.width = boxLayoutModel.getShallow("width", ignoreParent)
        m.height = boxLayoutModel.getShallow("height", ignoreParent)
        return m
    }

    /**
     * Uniformly calculate layout reference (rect or center) based on either viewport or coord sys.
     */
    public static func createBoxLayoutReference(
        _ model: ComponentModel,
        _ api: ExtensionAPI,
        _ opt: Any? = nil
    ) -> BoxLayoutReferenceResult {
        _ = model
        _ = opt
        // PORT-TODO: the `model.boxCoordinateSystem` branch (getCoordForCoordSysUsageKindBox +
        //   dataToLayout / dataToPoint) is Phase 6b; only the viewport reference is produced here,
        //   which is the default (`layoutRefType === rect`, no box coord sys) path upstream.
        let refContainer = BoundingRect(0, 0, api.getWidth(), api.getHeight())
        let refPoint = [
            refContainer.x + refContainer.width / 2,
            refContainer.y + refContainer.height / 2
        ]
        return BoxLayoutReferenceResult(
            type: BOX_LAYOUT_REFERENCE_TYPE_RECT,
            refContainer: refContainer,
            refPoint: refPoint,
            boxCoordFrom: nil
        )
    }

    /**
     * Parse position info.
     */
    public static func getLayoutRect(
        _ positionInfo: BoxLayoutOptionMixin,
        _ containerRect: LayoutRect,
        _ margin: Any? = nil
    ) -> LayoutRect {
        return getLayoutRectImpl({ key in
            switch key {
            case "left": return positionInfo.left
            case "right": return positionInfo.right
            case "top": return positionInfo.top
            case "bottom": return positionInfo.bottom
            case "width": return positionInfo.width
            case "height": return positionInfo.height
            // upstream `aspect` is not part of `BoxLayoutOptionMixin`.
            default: return nil
            }
        }, containerRect, margin)
    }

    // Overload for the dynamic option bag (e.g. `grid.outerBounds`, `OUTER_BOUNDS_DEFAULT`).
    public static func getLayoutRect(
        _ positionInfo: Any?,
        _ containerRect: LayoutRect,
        _ margin: Any? = nil
    ) -> LayoutRect {
        let dict = positionInfo as? [String: Any]
        return getLayoutRectImpl({ key in dict?[key] }, containerRect, margin)
    }

    private static func getLayoutRectImpl(
        _ get: (String) -> Any?,
        _ containerRect: LayoutRect,
        _ marginOpt: Any?
    ) -> LayoutRect {
        // margin = formatUtil.normalizeCssArray(margin || 0);
        let marginArr: [Double]
        if let m = marginOpt as? [Double] {
            marginArr = format.normalizeCssArray(m)
        }
        else if let m = marginOpt as? Double {
            marginArr = format.normalizeCssArray(m)
        }
        else {
            marginArr = format.normalizeCssArray(0.0)
        }

        let containerWidth = containerRect.width
        let containerHeight = containerRect.height

        var left = number.parsePercent(get("left"), containerWidth)
        var top = number.parsePercent(get("top"), containerHeight)
        let right = number.parsePercent(get("right"), containerWidth)
        let bottom = number.parsePercent(get("bottom"), containerHeight)
        var width = number.parsePercent(get("width"), containerWidth)
        var height = number.parsePercent(get("height"), containerHeight)

        let verticalMargin = marginArr[2] + marginArr[0]
        let horizontalMargin = marginArr[1] + marginArr[3]
        let aspect = get("aspect") as? Double

        // If width is not specified, calculate width from left and right
        if width.isNaN {
            width = containerWidth - right - horizontalMargin - left
        }
        if height.isNaN {
            height = containerHeight - bottom - verticalMargin - top
        }

        if let aspect = aspect {
            // If width and height are not given, keep aspect and take as much space as possible.
            if width.isNaN && height.isNaN {
                if aspect > containerWidth / containerHeight {
                    width = containerWidth * 0.8
                }
                else {
                    height = containerHeight * 0.8
                }
            }
            // Calculate width or height with given aspect
            if width.isNaN {
                width = aspect * height
            }
            if height.isNaN {
                height = width / aspect
            }
        }

        // If left is not specified, calculate left from right and width
        if left.isNaN {
            left = containerWidth - right - width - horizontalMargin
        }
        if top.isNaN {
            top = containerHeight - bottom - height - verticalMargin
        }

        // Align left and top
        // upstream: switch (positionInfo.left || positionInfo.right)
        let leftOrRight = layoutJsTruthy(get("left")) ? get("left") : get("right")
        switch leftOrRight as? String {
        case "center":
            left = containerWidth / 2 - width / 2 - marginArr[3]
        case "right":
            left = containerWidth - width - horizontalMargin
        default: break
        }
        // upstream: switch (positionInfo.top || positionInfo.bottom)
        let topOrBottom = layoutJsTruthy(get("top")) ? get("top") : get("bottom")
        switch topOrBottom as? String {
        case "middle", "center":
            top = containerHeight / 2 - height / 2 - marginArr[0]
        case "bottom":
            top = containerHeight - height - verticalMargin
        default: break
        }
        // If something is wrong and left, top, width, height are calculated as NaN
        // upstream: `left = left || 0;` (0/NaN are falsy → 0)
        left = (left.isNaN || left == 0) ? 0 : left
        top = (top.isNaN || top == 0) ? 0 : top
        if width.isNaN {
            // Width may be NaN if only one value is given except width
            width = containerWidth - horizontalMargin - left - ((right.isNaN || right == 0) ? 0 : right)
        }
        if height.isNaN {
            // Height may be NaN if only one value is given except height
            height = containerHeight - verticalMargin - top - ((bottom.isNaN || bottom == 0) ? 0 : bottom)
        }

        // PORT-TODO: upstream sets `rect.margin = margin` on the returned `LayoutRect`; `LayoutRect` is
        //   currently `typealias BoundingRect`, which has no `margin` slot, so it is dropped until the
        //   real `LayoutRect` (util/layout.ts) lands. No current consumer reads `.margin`.
        let rect = BoundingRect(
            ((containerRect.x.isNaN ? 0 : containerRect.x)) + left + marginArr[3],
            ((containerRect.y.isNaN ? 0 : containerRect.y)) + top + marginArr[0],
            width,
            height
        )
        return rect
    }
}

// PORT-TODO: JS truthiness shim (matches the per-file `jsTruthy` used across the port). Used only for
//   the `left || right` / `top || bottom` alignment branches above.
private func layoutJsTruthy(_ v: Any?) -> Bool {
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
