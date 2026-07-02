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

    // upstream: export const LOCATION_PARAMS = ['left', 'right', 'top', 'bottom', 'width', 'height'] as const;
    public static let LOCATION_PARAMS: [String] = ["left", "right", "top", "bottom", "width", "height"]

    // upstream: export const HV_NAMES = [['width','left','right'], ['height','top','bottom']] as const;
    public static let HV_NAMES: [[String]] = [
        ["width", "left", "right"],
        ["height", "top", "bottom"]
    ]

    // upstream: function boxLayout(orient, group, gap, maxWidth?, maxHeight?)
    private static func boxLayout(
        _ orient: String,
        _ group: Group,
        _ gap: Double,
        _ maxWidthIn: Double? = nil,
        _ maxHeightIn: Double? = nil
    ) {
        var x: Double = 0
        var y: Double = 0

        // if (maxWidth == null) { maxWidth = Infinity; }
        let maxWidth = maxWidthIn ?? Double.infinity
        // if (maxHeight == null) { maxHeight = Infinity; }
        let maxHeight = maxHeightIn ?? Double.infinity
        var currentLineMaxSize: Double = 0

        _ = group.eachChild { child, idx in
            let rect = child.getBoundingRect()!
            let nextChild = group.childAt(idx + 1)
            let nextChildRect = nextChild?.getBoundingRect()
            var nextX: Double = 0
            var nextY: Double = 0

            if orient == "horizontal" {
                let moveX = rect.width + (nextChildRect != nil ? (-nextChildRect!.x + rect.x) : 0)
                nextX = x + moveX
                // Wrap when width exceeds maxWidth or meet a `newline` group
                // FIXME compare before adding gap?
                if nextX > maxWidth || isNewlineElement(child) {
                    x = 0
                    nextX = moveX
                    y += currentLineMaxSize + gap
                    currentLineMaxSize = rect.height
                }
                else {
                    // FIXME: consider rect.y is not `0`?
                    currentLineMaxSize = Swift.max(currentLineMaxSize, rect.height)
                }
            }
            else {
                let moveY = rect.height + (nextChildRect != nil ? (-nextChildRect!.y + rect.y) : 0)
                nextY = y + moveY
                // Wrap when width exceeds maxHeight or meet a `newline` group
                if nextY > maxHeight || isNewlineElement(child) {
                    x += currentLineMaxSize + gap
                    y = 0
                    nextY = moveY
                    currentLineMaxSize = rect.width
                }
                else {
                    currentLineMaxSize = Swift.max(currentLineMaxSize, rect.width)
                }
            }

            if isNewlineElement(child) {
                return
            }

            child.x = x
            child.y = y
            child.markRedraw()

            if orient == "horizontal" {
                x = nextX + gap
            }
            else {
                y = nextY + gap
            }
        }
    }

    /**
     * VBox or HBox layouting
     */
    // upstream: export const box = boxLayout;
    public static func box(
        _ orient: String,
        _ group: Group,
        _ gap: Double,
        _ width: Double? = nil,
        _ height: Double? = nil
    ) {
        boxLayout(orient, group, gap, width, height)
    }

    // upstream: export const vbox = zrUtil.curry(boxLayout, 'vertical');
    //           export const hbox = zrUtil.curry(boxLayout, 'horizontal');
    // PORT-TODO: `vbox`/`hbox` (curried `boxLayout`) have no current consumer in the ported surface;
    //   add the thin `box('vertical', ...)` / `box('horizontal', ...)` forwarders when one lands.

    // upstream: `interface NewlineElement extends Element { newline: boolean }` — LegendView tags a
    //   spacer `Group` with `g.newline = true`, which `boxLayout` reads as a hard line break. Element is
    //   not dynamically extensible in Swift, so the flag lives in an inner-store side table keyed by
    //   element identity. `layout.markNewline(el)` sets it; `boxLayout` reads it via `isNewlineElement`.
    public static func markNewline(_ el: Element) {
        _newlineInner(el).newline = true
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

    // upstream: `type CircleLayoutSeriesOption = SeriesOption & CircleLayoutOptionMixin<{...}>` — a
    //   type-only alias for the circle-layout-capable series option; dropped per CONVENTIONS §2.

    // upstream `getViewRectAndCenterForCircleLayout` is module-private; kept as a private static helper
    //   inside the `layout` namespace (same call shape: `getViewRectAndCenterForCircleLayout(seriesModel, api)`).
    //   Returns `{viewRect, center}`.
    private static func getViewRectAndCenterForCircleLayout(
        _ seriesModel: SeriesModel,
        _ api: ExtensionAPI
    ) -> (viewRect: LayoutRect, center: [Double]) {
        // const layoutRef = createBoxLayoutReference(seriesModel, api, { enableLayoutOnlyByCenter: true });
        let layoutRef = createBoxLayoutReference(seriesModel, api, ["enableLayoutOnlyByCenter": true])
        // const boxLayoutParams = seriesModel.getBoxLayoutParams();
        let boxLayoutParams = seriesModel.getBoxLayoutParams()

        let viewRect: LayoutRect
        let center: [Double]
        if layoutRef.type == BOX_LAYOUT_REFERENCE_TYPE_POINT {
            // PORT-TODO: the `point` reference kind is produced only when the box coord-sys branch of
            //   `createBoxLayoutReference` (with `enableLayoutOnlyByCenter: true` + `boxCoordSys.dataToPoint`)
            //   lands (Phase 6b). `createBoxLayoutReference` ignores `opt` today and always returns the
            //   `rect` kind, so this branch is currently unreachable. Kept faithful for when it lands.
            center = layoutRef.refPoint
            // `viewRect` is required in `pie/labelLayout.ts`.
            // upstream container is `{ width: api.getWidth(), height: api.getHeight() }` (x/y default 0).
            viewRect = getLayoutRect(
                boxLayoutParams, BoundingRect(0, 0, api.getWidth(), api.getHeight())
            )
        }
        else { // layoutRef.type === layout.BoxLayoutReferenceType.rect
            let centerOption = seriesModel.get("center")
            let centerOptionArr: [Any?]
            if util.isArray(centerOption) {
                centerOptionArr = (centerOption as? [Any])?.map { $0 as Any? } ?? []
            }
            else {
                centerOptionArr = [centerOption, centerOption]
            }
            viewRect = getLayoutRect(
                boxLayoutParams, layoutRef.refContainer
            )
            // upstream: `layoutRef.boxCoordFrom === BOX_COORD_SYS_COORD_FROM_PROP_COORD2`.
            //   `boxCoordFrom` is `nil` on the current viewport-only reference, so the else branch is taken.
            let usedAsCoord = (layoutRef.boxCoordFrom as? Double) == BOX_COORD_SYS_COORD_FROM_PROP_COORD2
            center = usedAsCoord
                ? layoutRef.refPoint // option `series.center` has been used as coord.
                : [
                    number.parsePercent(centerOptionArr[0], viewRect.width) + viewRect.x,
                    number.parsePercent(centerOptionArr[1], viewRect.height) + viewRect.y,
                ]
        }

        return (viewRect: viewRect, center: center)
    }

    // upstream: getCircleLayout<TOption extends CircleLayoutSeriesOption>(seriesModel, api)
    //   : Pick<SectorShape, 'cx' | 'cy' | 'r' | 'r0'> & { viewRect: LayoutRect }
    public static func getCircleLayout(
        _ seriesModel: SeriesModel,
        _ api: ExtensionAPI
    ) -> (cx: Double, cy: Double, r0: Double, r: Double, viewRect: LayoutRect) {

        // center can be string or number when coordinateSystem is specified
        let (viewRect, center) = getViewRectAndCenterForCircleLayout(seriesModel, api)

        let radius = seriesModel.get("radius")

        // if (!zrUtil.isArray(radius)) { radius = [0, radius]; }
        let radiusArr: [Any?]
        if !util.isArray(radius) {
            radiusArr = [0.0, radius]
        }
        else {
            radiusArr = (radius as? [Any])?.map { $0 as Any? } ?? []
        }

        let width = number.parsePercent(viewRect.width, api.getWidth())
        let height = number.parsePercent(viewRect.height, api.getHeight())
        let size = Swift.min(width, height)
        let r0 = number.parsePercent(radiusArr[0], size / 2)
        let r = number.parsePercent(radiusArr[1], size / 2)

        return (
            cx: center[0],
            cy: center[1],
            r0: r0,
            r: r,
            viewRect: viewRect
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

    // ------------------------------------------------------------------------
    // upstream: export function positionElement(el, positionInfo, containerRect, margin?, opt?, out?): boolean
    // Value-returning port (the `out` out-param is dropped per CONVENTIONS §3): returns
    // `(layouted, out)` where `out` carries the computed x/y. `opt` carries `hv:[Bool]` and
    // `boundingMode:String`.
    // ------------------------------------------------------------------------
    public static func positionElement(
        _ el: Element,
        _ positionInfo: [String: Any],
        _ containerRect: BoundingRect,
        _ margin: Any?,
        _ opt: [String: Any]?
    ) -> (layouted: Bool, out: [String: Double]) {
        let hvArr = opt?["hv"] as? [Bool]
        let h = (opt == nil) || (hvArr == nil) || (hvArr!.count > 0 && hvArr![0])
        let v = (opt == nil) || (hvArr == nil) || (hvArr!.count > 1 && hvArr![1])
        let boundingMode = (opt?["boundingMode"] as? String) ?? "all"

        var out: [String: Double] = [:]
        out["x"] = el.x
        out["y"] = el.y

        if !h && !v {
            return (false, out)
        }

        var rect: BoundingRect
        if boundingMode == "raw" {
            if el.type == "group" {
                let w = (positionInfo["width"] as? Double) ?? 0
                let ht = (positionInfo["height"] as? Double) ?? 0
                rect = BoundingRect(0, 0, w, ht)
            }
            else {
                rect = el.getBoundingRect() ?? BoundingRect(0, 0, 0, 0)
            }
        }
        else {
            rect = el.getBoundingRect() ?? BoundingRect(0, 0, 0, 0)
            if el.needLocalTransform() {
                let transform = el.getLocalTransform()
                // Notice: raw rect may be inner object of el, which should not be modified.
                rect = rect.clone()
                rect.applyTransform(transform)
            }
        }

        // getLayoutRect(defaults({width: rect.width, height: rect.height}, positionInfo), containerRect, margin)
        // `defaults` keeps the width/height from `rect` (target) and fills the rest from positionInfo.
        var merged = positionInfo
        merged["width"] = rect.width
        merged["height"] = rect.height
        let layoutRect = getLayoutRect(merged as Any?, containerRect, margin)

        let dx = h ? layoutRect.x - rect.x : 0
        let dy = v ? layoutRect.y - rect.y : 0

        if boundingMode == "raw" {
            out["x"] = dx
            out["y"] = dy
        }
        else {
            out["x"] = (out["x"] ?? 0) + dx
            out["y"] = (out["y"] ?? 0) + dy
        }
        return (true, out)
    }

    // ------------------------------------------------------------------------
    // upstream: export function mergeLayoutParam(targetOption, newOption, opt?) — operating on the
    // dynamic option bags (opt supports `ignoreSize`).
    // ------------------------------------------------------------------------
    public static func mergeLayoutParam(
        _ targetOption: inout [String: Any],
        _ newOption: [String: Any],
        _ opt: [String: Any]?
    ) {
        var ignoreSize: [Bool]
        let rawIgnore = opt?["ignoreSize"]
        if let arr = rawIgnore as? [Bool] {
            ignoreSize = arr.count >= 2 ? arr : [arr.first ?? false, arr.first ?? false]
        }
        else {
            let b = (rawIgnore as? Bool) ?? false
            ignoreSize = [b, b]
        }

        let hResult = mergeLayoutHV(HV_NAMES[0], 0, targetOption, newOption, ignoreSize)
        let vResult = mergeLayoutHV(HV_NAMES[1], 1, targetOption, newOption, ignoreSize)

        copyLayoutHV(HV_NAMES[0], &targetOption, hResult)
        copyLayoutHV(HV_NAMES[1], &targetOption, vResult)
    }

    private static func mergeLayoutHasValue(_ obj: [String: Any], _ name: String) -> Bool {
        guard let val = obj[name] else { return false }
        if val is NSNull { return false }
        if let s = val as? String, s == "auto" { return false }
        return true
    }

    private static func mergeLayoutHV(
        _ names: [String],
        _ hvIdx: Int,
        _ targetOption: [String: Any],
        _ newOption: [String: Any],
        _ ignoreSize: [Bool]
    ) -> [String: Any] {
        var newParams: [String: Any] = [:]
        var newValueCount = 0
        var merged: [String: Any] = [:]
        var mergedValueCount = 0
        let enoughParamNumber = 2

        // each(names): merged[name] = targetOption[name]
        for name in names {
            if let v = targetOption[name] { merged[name] = v }
        }
        for name in names {
            // hasOwn(newOption, name) — key present (even if NSNull).
            if let nv = newOption[name] {
                newParams[name] = nv
                merged[name] = nv
            }
            if mergeLayoutHasValue(newParams, name) { newValueCount += 1 }
            if mergeLayoutHasValue(merged, name) { mergedValueCount += 1 }
        }

        if ignoreSize[hvIdx] {
            // Only one of left/right is permitted to exist.
            if mergeLayoutHasValue(newOption, names[1]) {
                merged.removeValue(forKey: names[2])
            }
            else if mergeLayoutHasValue(newOption, names[2]) {
                merged.removeValue(forKey: names[1])
            }
            return merged
        }

        if mergedValueCount == enoughParamNumber || newValueCount == 0 {
            return merged
        }
        else if newValueCount >= enoughParamNumber {
            return newParams
        }
        else {
            for name in names {
                if newParams[name] == nil && targetOption[name] != nil {
                    newParams[name] = targetOption[name]
                    break
                }
            }
            return newParams
        }
    }

    private static func copyLayoutHV(_ names: [String], _ target: inout [String: Any], _ source: [String: Any]) {
        for name in names {
            if let v = source[name] {
                target[name] = v
            }
            else {
                target.removeValue(forKey: name)
            }
        }
    }

    // ------------------------------------------------------------------------
    // upstream: export function copyLayoutParams(target, source) — copies LOCATION_PARAMS keys, returns target.
    // ------------------------------------------------------------------------
    public static func copyLayoutParams(_ target: [String: Any], _ source: [String: Any]) -> [String: Any] {
        var result = target
        for name in LOCATION_PARAMS {
            if let v = source[name] {
                result[name] = v
            }
        }
        return result
    }
}

// upstream augmentation `interface NewlineElement extends Element { newline: boolean }` (LegendView).
//   The boolean is held per-element in an inner-store side table (see `layout.markNewline`).
private final class NewlineFlag { var newline: Bool = false }
private let _newlineInner: (Element) -> NewlineFlag = model.makeInner { NewlineFlag() }
private func isNewlineElement(_ el: Element) -> Bool {
    return _newlineInner(el).newline
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
