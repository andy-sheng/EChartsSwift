// Ported from echarts/src/chart/custom/CustomView.ts — keep in sync with upstream
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

// ============================================================================================
// SCOPE — STATIC SUBSET per CONVENTIONS §5 + the custom-port brief.
//
// This file faithfully ports the STATIC core of CustomView.ts:
//   - `render` (the per-datum renderItem dispatch) — the enter/update/leave DIFF via `data.diff(oldData)`
//     is now ported (per-datum graphic els are reused across renders; see the render note), including
//     the real `applyLeaveTransition` leave path.
//   - `createEl` + the per-type graphic-element builders (group/rect/circle/ring/sector/arc/
//     polygon/polyline/line/bezierCurve/text/image/compoundPath; `path` SVG-data building deferred).
//   - `updateElNormal` STATIC parts — apply shape + style + transform (x/y/rotation/scale) + z2.
//   - `makeRenderItem` — the render-item `api` (value/coord/size/style/visual/font/getWidth/…) and
//     `params`, plus the coord-system dispatch via the ported `prepareCustoms`.
//   - `mergeChildren` group building.
//
// ALSO PORTED (was deferred in earlier waves — do NOT grep this file for a stale "deferred" claim):
//   - the transition machinery is WIRED: `applyUpdateTransition` / `applyLeaveTransition`
//     (animation/customGraphicTransition.swift) + `applyKeyframeAnimation` /
//     `stopPreviousKeyframeAnimationAndRestore` (animation/customGraphicKeyframeAnimation.swift).
//     The element's typed value-struct `shape` / `style` are re-applied right after
//     `applyUpdateTransition` (see `applyTypedShapeAndStyle`'s FRAMEWORK GAP note), since the generic
//     `attr(dict)` seam can only carry the animatable numeric/colour keys.
//   - the top-level enter/update/leave DIFF (`data.diff(oldData)`) is PORTED in `render` (per-datum
//     graphic els are reused across renders — the reset-on-update fix).
//   - emphasis/blur/select STATES: `updateElOnState` / `setDefaultStateProxy` / `toggleHoverEmphasis`
//     are ported (util/states is present) AND the per-state application loop that CALLS `updateElOnState`
//     (the `for (STATES)` walk + `retrieveStateOption` + `updateZForEachState` per-state z2) is WIRED.
//
// DEFERRED (each marked // PORT-NOTE at its site):
//   - MORPH (universalTransition / morphPath).
//   - the GROUP-CHILD by-name diff (`diffGroupChildren` / DataDiffer child-diff) — `mergeChildren`
//     still rebuilds a group's children by index each render.
//   - group-level `createClipPath` and the remaining Polar-specific clip nuances. Per-element
//     `doCreateOrUpdateClipPath`, including enter/update transitions and `during`, is wired.
//   - the complete legacy ec4 style compat remains deferred, but the normal-state `api.style()` label
//     bridge is wired (legacy text fields are converted to attached textContent/textConfig).
//   - `attachTextContent` / rich-label nuance — only basic `textContent` (a plain text child) is wired.
//   - decal pattern (`createOrUpdatePatternFromDecal`) is WIRED in `updateElNormal`; universal
//     transition and the incremental hover-layer stay deferred.
//
// upstream imports (Swift mapping / deferral):
//   import { hasOwn, assert, isString, retrieve2, retrieve3, defaults, each, indexOf, map }
//       from 'zrender/src/core/util';                                -> `util.*` (ZRenderKit).
//   import * as graphicUtil from '../../util/graphic';               -> concrete ZRenderKit shapes;
//       `graphicUtil.makePath` / `getShapeClass` NOT ported (see `createEl`).
//   import { setDefaultStateProxy, toggleHoverEmphasis } from '../../util/states';  -> `states.*`
//       (util/states.swift); both wired (updateElOnState + doCreateOrUpdateElOnDataIndex).
//   import * as labelStyleHelper from '../../label/labelStyle';      -> `labelStyle` (label/labelStyle.swift); getFont wired in `font`.
//   import { getDefaultLabel } from '../helper/labelHelper';         -> `labelHelper.getDefaultLabel` (label/labelHelper.swift).
//   import { ...computeBarLayoutForCustomSeries } from '../../layout/barGrid';  -> layout/barGrid.swift.
//   import DataDiffer from '../../data/DataDiffer';                  -> DEFERRED (child diff).
//   import Model from '../../model/Model';                           -> `Model`.
//   import ChartView from '../../view/Chart';                        -> `ChartView` (view/Chart.swift).
//   import { createClipPath } from '../helper/createClipPathFromCoordSys';  -> DEFERRED (group clip).
//   import ...types... from '../../util/types';                      -> util/types.swift.
//   import Element, { ElementTextConfig } from 'zrender/src/Element'; -> ZRenderKit `Element` / `ElementTextConfig`.
//   import prepareCartesian2d from '../../coord/cartesian/prepareCustom';  -> `cartesian2dPrepareCustom`.
//   import prepareGeo from '../../coord/geo/prepareCustom';          -> `geoPrepareCustom`.
//   import prepareSingleAxis from '../../coord/single/prepareCustom'; -> `singlePrepareCustom`.
//   import preparePolar from '../../coord/polar/prepareCustom';      -> `polarPrepareCustom`.
//   import prepareCalendar from '../../coord/calendar/prepareCustom'; -> `calendarPrepareCustom`.
//   import prepareMatrix from '../../coord/matrix/prepareCustom';    -> `matrixPrepareCustom`.
//   import SeriesData, { DefaultDataVisual } from '../../data/SeriesData';  -> `SeriesData`.
//   import GlobalModel from '../../model/Global';                    -> `GlobalModel`.
//   import ExtensionAPI from '../../core/ExtensionAPI';              -> `ExtensionAPI`.
//   import Displayable from 'zrender/src/graphic/Displayable';       -> ZRenderKit `Displayable`.
//   import Axis2D from '../../coord/cartesian/Axis2D';               -> `Axis2D`.
//   import { RectLike } from 'zrender/src/core/BoundingRect';        -> ZRenderKit `RectLike`.
//   import Path, { PathStyleProps } from 'zrender/src/graphic/Path'; -> ZRenderKit `Path` / `PathStyleProps`.
//   import { TextStyleProps } from 'zrender/src/graphic/Text';       -> ZRenderKit `TextStyleProps`.
//   import { ...styleCompat... } from '../../util/styleCompat';      -> DEFERRED (ec4 compat not ported).
//   import { ItemStyleProps } from '../../model/mixin/itemStyle';    -> DEFERRED (deprecated api.style).
//   import { throwError } from '../../util/log';                     -> `log.error` (util/log.swift).
//   import { createOrUpdatePatternFromDecal } from '../../util/decal';  -> `createOrUpdatePatternFromDecal`
//       (util/decal.swift) — a bare top-level func; wired in `updateElNormal`.
//   import CustomSeriesModel, { ...many types... } from './CustomSeries';
//       -> sibling `CustomSeries.swift` (CustomSeriesModel + the render-item api/param types +
//          `customInnerStore`). Referenced; see the integration contract note near `makeRenderItem`.
//   import { PatternObject } from 'zrender/src/graphic/Pattern';     -> ZRenderKit `Pattern`.
//   import { applyLeaveTransition, applyUpdateTransition, ElementRootTransitionProp }
//       from '../../animation/customGraphicTransition';              -> `applyLeaveTransition` /
//       `applyUpdateTransition` (animation/customGraphicTransition.swift), bare top-level funcs.
//   import { applyKeyframeAnimation, stopPreviousKeyframeAnimationAndRestore }
//       from '../../animation/customGraphicKeyframeAnimation';       -> `applyKeyframeAnimation` /
//       `stopPreviousKeyframeAnimationAndRestore` (animation/customGraphicKeyframeAnimation.swift),
//       bare top-level funcs; both wired in `updateElNormal`.
//   import type SeriesModel from '../../model/Series';               -> `SeriesModel`.
//   import { getCustomSeries } from './customSeriesRegister';        -> `getCustomSeries` (subType fallback in makeRenderItem).
//   import tokens from '../../visual/tokens';                        -> DEFERRED (used only in api.style).
//   import { getIncrementalId } from '../../util/model';             -> `model.getIncrementalId`.
// ============================================================================================

// upstream:
//   const EMPHASIS = 'emphasis' as const; const NORMAL = 'normal' as const;
//   const BLUR = 'blur' as const; const SELECT = 'select' as const;
//   const STATES = [NORMAL, EMPHASIS, BLUR, SELECT] as const;
private let EMPHASIS = "emphasis"
private let NORMAL = "normal"
private let BLUR = "blur"
private let SELECT = "select"
private let STATES = [NORMAL, EMPHASIS, BLUR, SELECT]
// upstream:
//   const PATH_ITEM_STYLE = { normal: ['itemStyle'], emphasis: [EMPHASIS, 'itemStyle'],
//       blur: [BLUR, 'itemStyle'], select: [SELECT, 'itemStyle'] } as const;
private let PATH_ITEM_STYLE: [String: [String]] = [
    "normal": ["itemStyle"],
    "emphasis": [EMPHASIS, "itemStyle"],
    "blur": [BLUR, "itemStyle"],
    "select": [SELECT, "itemStyle"]
]
// upstream:
//   const PATH_LABEL = { normal: ['label'], emphasis: [EMPHASIS, 'label'],
//       blur: [BLUR, 'label'], select: [SELECT, 'label'] } as const;
private let PATH_LABEL: [String: [String]] = [
    "normal": ["label"],
    "emphasis": [EMPHASIS, "label"],
    "blur": [BLUR, "label"],
    "select": [SELECT, "label"]
]
// upstream: const DEFAULT_TRANSITION: ElementRootTransitionProp[] = ['x', 'y'];
private let DEFAULT_TRANSITION: [String] = ["x", "y"]
// Use prefix to avoid index to be the same as el.name,
// which will cause weird update animation.
// upstream: const GROUP_DIFF_PREFIX = 'e\0\0';
private let GROUP_DIFF_PREFIX = "e\u{0}\u{0}"

// upstream: type AttachedTxInfo = { isLegacy; normal/emphasis/blur/select: { cfg; conOpt } }
//   Attached-text config carrier passed through the create/update pipeline. Basic-text subset only.
final class AttachedTxInfoState {
    var cfg: ElementTextConfig?
    var conOpt: Any?   // upstream: CustomElementOption | false | CustomElementOptionOnState
    init() {}
}
final class AttachedTxInfo {
    var isLegacy: Bool = false
    var normal = AttachedTxInfoState()
    var emphasis = AttachedTxInfoState()
    var blur = AttachedTxInfoState()
    var select = AttachedTxInfoState()
    init() {}
    // upstream indexes `attachedTxInfo[state]` by the state name.
    subscript(_ state: String) -> AttachedTxInfoState {
        switch state {
        case EMPHASIS: return emphasis
        case BLUR: return blur
        case SELECT: return select
        default: return normal
        }
    }
}
// upstream: const attachedTxInfoTmp = { normal: {}, emphasis: {}, blur: {}, select: {} } as AttachedTxInfo;
private let attachedTxInfoTmp = AttachedTxInfo()


/**
 * FIXME: register rather than import directly, for size.
 *
 * prepareInfoForCustomSeries {Function}: optional
 *     @return {Object} {coordSys: {...}, api: {
 *         coord: function (data, clamp) {}, // return point in global.
 *         size: function (dataSize, dataItem) {} // return size of each axis in coordSys.
 *     }}
 */
// upstream: const prepareCustoms: Dictionary<PrepareCustomInfo> = { cartesian2d, geo, single, polar, calendar, matrix }
//   Each ported `*PrepareCustom` takes a *concrete* coord-system type, so the JS `type`-keyed
//   dictionary is realized as a switch on the coord-system instance (returns `{coordSys, api}` bag).
//   cartesian2d's `prepareCustom` (coord/cartesian/cartesian2dPrepareCustom.swift) is now ported;
//     custom-on-cartesian supplies api.coord/api.size via `cartesian2dPrepareCustom`.
private func prepareCustoms(_ coordSys: Any?) -> [String: Any]? {
    if let cartesian = coordSys as? Cartesian2D {
        return cartesian2dPrepareCustom(cartesian)
    }
    if let polar = coordSys as? Polar {
        return polarPrepareCustom(polar)
    }
    if let geo = coordSys as? Geo {
        return geoPrepareCustom(geo)
    }
    if let single = coordSys as? Single {
        return singlePrepareCustom(single)
    }
    if let calendar = coordSys as? Calendar {
        return calendarPrepareCustom(calendar)
    }
    if let matrix = coordSys as? Matrix {
        return matrixPrepareCustom(matrix)
    }
    return nil
}


// upstream: function isPath(el: Element): el is graphicUtil.Path { return el instanceof graphicUtil.Path; }
private func isPath(_ el: Element) -> Bool {
    return el is Path
}
// upstream: function isDisplayable(el: Element): el is Displayable { return el instanceof Displayable; }
private func isDisplayable(_ el: Element) -> Bool {
    return el is Displayable
}
// upstream: function copyElement(sourceEl, targetEl) { ... }
//   Only reached on el-recreate (the DIFF path), which is DEFERRED here; retained faithfully for
//   the (rare) same-render recreate.
private func copyElement(_ sourceEl: Element, _ targetEl: Element) {
    targetEl.copyTransform(sourceEl)
    if let target = targetEl as? Displayable, let source = sourceEl as? Displayable {
        // upstream: targetEl.setStyle(sourceEl.style); z/z2/zlevel/invisible/ignore copied.
        // PORT-NOTE (language difference): `Displayable.style` is a typed struct; a generic
        //   `setStyle(source.style)` across Path/Text/Image variants is not uniformly typed here. Copy
        //   the scalar display props; the style copy is deferred (recreate path is off the static
        //   critical path).
        target.z = source.z
        target.z2 = source.z2
        target.zlevel = source.zlevel
        target.invisible = source.invisible
        target.ignore = source.ignore
        // if (isPath(targetEl) && isPath(sourceEl)) { targetEl.setShape(sourceEl.shape); }
        if let tp = targetEl as? Path, let sp = sourceEl as? Path {
            _ = tp.setShape(sp.shape)
        }
    }
}

// upstream: export default class CustomChartView extends ChartView
open class CustomChartView: ChartView {

    // upstream: static type = 'custom';  /  readonly type = CustomChartView.type;
    public static let customType = "custom"

    // upstream: private _data: SeriesData;
    private var _data: SeriesData?
    // upstream: private _progressiveEls: Element[];
    private var _progressiveEls: [Element]?

    public override init() {
        super.init()
        self.type = CustomChartView.customType
    }

    // upstream: render(customSeries, ecModel, api, payload): void
    open override func render(
        _ seriesModel: SeriesModel, _ ecModel: GlobalModel, _ api: ExtensionAPI, _ payload: Payload
    ) {
        // The base ChartView.render carries a SeriesModel; downcast to the custom series (same
        //   deviation as GraphicComponentView's `model as! GraphicComponentModel`).
        let customSeries = seriesModel as! CustomSeriesModel

        // Clear previously rendered progressive elements.
        self._progressiveEls = nil

        // upstream: const oldData = this._data;
        let oldData = self._data
        let data = customSeries.getData()
        let group = self.group
        let renderItem = makeRenderItem(customSeries, data, ecModel, api)

        // upstream: if (!oldData) { group.removeAll(); }
        if oldData == nil {
            // Previous render is incremental render or first render.
            // Needs remove the incremental rendered elements.
            group.removeAll()
        }

        // upstream: data.diff(oldData).add(...).remove(...).update(...).execute();
        //   The enter/update/leave DIFF — reuses per-datum graphic els across renders (keyed by data id).
        //   This is the fix for the reset-on-update bug: a merge-mode setOption now ROUTES matched data
        //   through the `.update` branch, which passes the EXISTING element to `createOrUpdateItem` so the
        //   same object is reused (its shape/style/transform re-applied) instead of destroyed + recreated.
        //   Element identity persists across renders (so any in-flight animation is not restarted, and
        //   downstream tween/morph machinery — where wired — sees the prior element).
        data.diff(oldData)
            .add { newIdx in
                // upstream: createOrUpdateItem(api, null, newIdx, renderItem(newIdx, payload), ...);
                _ = createOrUpdateItem(
                    api, nil, newIdx, renderItem(newIdx, payload), customSeries, group, data
                )
            }
            .remove { oldIdx in
                // upstream: const el = oldData.getItemGraphicEl(oldIdx);
                //   el && applyLeaveTransition(el, customInnerStore(el).option, customSeries);
                // `oldData` is non-nil in this branch (the diff emits removes only when there is old data).
                if let el = oldData?.getItemGraphicEl(oldIdx) {
                    applyLeaveTransition(el, customInnerStore(el).option ?? [:], customSeries)
                }
            }
            .update { newIdx, oldIdx in
                // upstream: const oldEl = oldData.getItemGraphicEl(oldIdx);
                //   createOrUpdateItem(api, oldEl, newIdx, renderItem(newIdx, payload), ...);
                let oldEl = oldData?.getItemGraphicEl(oldIdx)
                _ = createOrUpdateItem(
                    api, oldEl, newIdx, renderItem(newIdx, payload), customSeries, group, data
                )
            }
            .execute()

        // upstream:
        //   const clipPath = customSeries.get('clip', true)
        //       ? createClipPath(customSeries.coordinateSystem, false, customSeries) : null;
        //   if (clipPath) { group.setClipPath(clipPath); } else { group.removeClipPath(); }
        // PORT-NOTE (deferred): `createClipPath` IS ported (chart/helper/createClipPathFromCoordSys), but
        //   wiring the group-level clip for the custom series (its `coordinateSystem` access +
        //   SeriesModelWithLineWidth conformance, plus the still-deferred Polar clip branch) is not done.
        //   Static shape rendering does not require it.

        self._data = data
    }

    // upstream: incrementalPrepareRender(customSeries, ecModel, api): void
    open override func incrementalPrepareRender(
        _ seriesModel: SeriesModel, _ ecModel: GlobalModel, _ api: ExtensionAPI, _ payload: Payload
    ) {
        self.group.removeAll()
        self._data = nil
    }

    // upstream: incrementalRender(params, customSeries, ecModel, api, payload): void
    open override func incrementalRender(
        _ params: StageHandlerProgressParams, _ seriesModel: SeriesModel, _ ecModel: GlobalModel,
        _ api: ExtensionAPI, _ payload: Payload
    ) {
        let customSeries = seriesModel as! CustomSeriesModel
        let data = customSeries.getData()
        let renderItem = makeRenderItem(customSeries, data, ecModel, api)
        var progressiveEls: [Element] = []
        self._progressiveEls = progressiveEls

        // upstream: function setIncrementalAndHoverLayer(el) { ... el.incremental = getIncrementalId(...);
        //   el.ensureState('emphasis').hoverLayer = HOVER_LAYER_FOR_INCREMENTAL; }
        // PORT-NOTE (deferred): requires the incremental hover-layer (`el.incremental` +
        //   HOVER_LAYER_FOR_INCREMENTAL emphasis state), not ported. The elements are still built +
        //   collected below.

        // upstream: for (let idx = params.start; idx < params.end; idx++) { ... }
        let start = Int(params.start)
        let end = Int(params.end)
        for idx in start..<end {
            let el = createOrUpdateItem(
                nil, nil, idx, renderItem(idx, payload), customSeries, self.group, data
            )
            if let el = el {
                // el.traverse(setIncrementalAndHoverLayer)  — hover-layer wiring deferred (see above).
                progressiveEls.append(el)
            }
        }
        self._progressiveEls = progressiveEls
    }

    // upstream: eachRendered(cb) { graphicUtil.traverseElements(this._progressiveEls || this.group, cb); }
    open override func eachRendered(_ cb: (_ el: Element) -> Bool) {
        // PORT-NOTE (equivalent substitute): `graphicUtil.traverseElements` is not ported; the walk below
        //   reproduces it — traverse the progressive els or group.
        //   `traverseElements` invokes `cb` on each root element itself and then walks its descendants;
        //   `Element.traverse` is empty UPSTREAM TOO (zrender Element.ts) and only `Group` overrides it, so invoke `cb` on
        //   each root and recurse into groups.
        if let progressiveEls = self._progressiveEls {
            for el in progressiveEls {
                _ = cb(el)
                if let g = el as? Group {
                    _ = g.traverse(cb)
                }
            }
        }
        else {
            _ = self.group.traverse(cb)
        }
    }

    // upstream: filterForExposedEvent(eventType, query, targetEl, packedEvent): boolean
    open override func filterForExposedEvent(
        _ eventType: String, _ query: EventQueryItem, _ targetEl: Element, _ packedEvent: Any
    ) -> Bool {
        // `EventQueryItem` is `Dictionary<Any>` (a `[String: Any]` bag) in this port; read `element`.
        let elementName = query["element"] as? String
        if elementName == nil || targetEl.name == elementName {
            return true
        }

        // Enable to give a name on a group made by `renderItem`, and listen
        // events that are triggered by its descendents.
        // upstream: while ((targetEl = targetEl.__hostTarget || targetEl.parent) && targetEl !== this.group)
        //   `__hostTarget` (text-content host back-pointer) IS modeled on `Element`, so port faithfully:
        //   prefer the host target, else the parent.
        var cur: Element? = targetEl.__hostTarget ?? (targetEl.parent as? Element)
        while let c = cur, c !== self.group {
            if c.name == elementName {
                return true
            }
            cur = c.__hostTarget ?? (c.parent as? Element)
        }

        return false
    }
}


// upstream: function createEl(elOption: CustomElementOption): Element
//   NOTE: `CustomElementOption` is the dynamic element-spec bag; modeled as `[String: Any]` here
//   (the renderItem callback returns these). Builds the empty typed element; shape/style/transform
//   are applied later in `updateElNormal` (STATIC).
private func createEl(_ elOption: [String: Any]) -> Element {
    let graphicType = elOption["type"] as? String
    let el: Element

    // Those graphic elements are not shapes. They should not be
    // overwritten by users, so do them first.
    if graphicType == "path" {
        // upstream:
        //   const shape = (elOption as CustomPathOption).shape;
        //   const pathRect = (shape.width != null && shape.height != null)
        //       ? { x: shape.x || 0, y: shape.y || 0, width: shape.width, height: shape.height } : null;
        //   const pathData = getPathData(shape);
        //   el = makePath(pathData, null, pathRect, shape.layout || 'center');
        //   (el as CustomPathElement).__customPathData = pathData;
        // `graphicUtil.makePath` IS ported (ZRenderKit `makePath` in Tool/ToolPath) → SVG path-data
        //   parsing is wired. `SVGPath` is a `Path` subclass; the opts are applied later in updateElNormal.
        let shape = (elOption["shape"] as? [String: Any]) ?? [:]
        let pathData = getPathData(shape)
        var pathRect: RectLike? = nil
        if let w = customToDouble(shape["width"]), let h = customToDouble(shape["height"]) {
            pathRect = BoundingRect(
                customToDouble(shape["x"]) ?? 0, customToDouble(shape["y"]) ?? 0, w, h
            )
        }
        let layout = (shape["layout"] as? String) ?? "center"
        el = makePath(pathData, nil, pathRect, layout)
        customInnerStore(el).customPathData = pathData
    }
    else if graphicType == "image" {
        el = ZRImage()
        // customInnerStore(el).customImagePath = elOption.style.image
        let style = elOption["style"] as? [String: Any]
        customInnerStore(el).customImagePath = style?["image"]
    }
    else if graphicType == "text" {
        el = ZRText()
        // customInnerStore(el).customText = (elOption.style as TextStyleProps).text; (commented upstream)
    }
    else if graphicType == "group" {
        el = Group()
    }
    else if graphicType == "compoundPath" {
        // upstream: const shape = elOption.shape; assert shape.paths; map paths -> child Path els.
        let shape = elOption["shape"] as? [String: Any]
        let pathsOpt = shape?["paths"] as? [[String: Any]]
        if shape == nil || pathsOpt == nil {
            log.error("shape.paths must be specified in compoundPath")
        }
        let paths: [Path] = util.map(pathsOpt) { (pathOpt, _) -> Path in
            // if (path.type === 'path') { return makePath(path.shape.pathData, path, null); }
            // else { const Clz = getShapeClass(path.type); ... return new Clz(); }
            //   `makePath` IS ported; a `type: 'path'` sub-path parses its `shape.pathData`. The `path`
            //   opts bag is applied later (updateElNormal), so pass nil opts here (as the top-level
            //   `path` element does). Other sub-path `type`s use the shape switch (getShapeClass
            //   equivalent) below.
            let subType = pathOpt["type"] as? String
            if subType == "path" {
                let subShape = pathOpt["shape"] as? [String: Any]
                return makePath(getPathData(subShape), nil, nil)
            }
            let child = makeShapeElement(subType) ?? Path()
            return child
        }
        var cpShape = CompoundPathShape()
        cpShape.paths = paths
        let cp = CompoundPath()
        _ = cp.setShape(cpShape)
        el = cp
    }
    else {
        // upstream: const Clz = getShapeClass(graphicType); if (!Clz) throwError(...); el = new Clz();
        // PORT-NOTE (equivalent substitute): `graphicUtil.getShapeClass` (the extendShape string->class
        //   registry) is not ported; the built-in shapes are switched explicitly in `makeShapeElement`.
        if let shapeEl = makeShapeElement(graphicType) {
            el = shapeEl
        }
        else {
            log.error("graphic type \"\(graphicType ?? "")\" can not be found.")
            el = Path()
        }
    }

    customInnerStore(el).customGraphicType = graphicType
    el.name = (elOption["name"] as? String) ?? ""

    // Compat ec4: the default z2 lift is 1.
    // upstream: (el as ECElement).z2EmphasisLift = 1; (el as ECElement).z2SelectLift = 1;
    //   `ECElement` is an option-bag augmentation `Element` does not directly conform to, but the states
    //   z2-lift machinery reads `z2EmphasisLift`/`z2SelectLift` off the el's HighDownInner side-store
    //   (util/states.swift, applied at emphasis/select). Write the ec4-compat default lift of 1 there so
    //   a hovered/selected custom element bumps z2 by 1 (not the generic Z2_EMPHASIS_LIFT/Z2_SELECT_LIFT).
    states.getHighDownInner(el).z2EmphasisLift = 1
    states.getHighDownInner(el).z2SelectLift = 1

    return el
}

// getShapeClass(graphicType) substitute — the built-in shape registry. Returns an empty typed Path
//   subclass for the given type name (shape values applied later in `applyShape`).
private func makeShapeElement(_ graphicType: String?) -> Path? {
    switch graphicType {
    case "rect": return Rect()
    case "circle": return Circle()
    case "ellipse": return Ellipse()
    case "sector": return Sector()
    case "ring": return Ring()
    case "arc": return Arc()
    case "polygon": return Polygon()
    case "polyline": return Polyline()
    case "line": return Line()
    case "bezierCurve": return BezierCurve()
    default: return nil
    }
}


/**
 * ----------------------------------------------------------
 * [STRATEGY_MERGE] / [STRATEGY_NULL] / [STRATEGY_TRANSITION]
 * (Full upstream doc-block retained in CustomView.ts; the merge/transition subtleties are largely
 *  a property of `applyUpdateTransition`, which is DEFERRED. The static apply below writes the
 *  final shape/style/transform directly — the correct end state for a single frame.)
 * @return if `isMorphTo`, return `allPropsFinal`.
 */

// upstream: function updateElNormal(api, el, dataIndex, elOption, attachedTxInfo, seriesModel, isInit): void
private func updateElNormal(
    _ api: ExtensionAPI?,
    _ el: Element,
    _ dataIndex: Int,
    _ elOption: [String: Any],
    _ attachedTxInfo: AttachedTxInfo?,
    _ seriesModel: CustomSeriesModel,
    _ isInit: Bool
) {
    // upstream: stopPreviousKeyframeAnimationAndRestore(el);
    stopPreviousKeyframeAnimationAndRestore(el)

    // upstream: const txCfgOpt = attachedTxInfo && attachedTxInfo.normal.cfg; if (txCfgOpt) el.setTextConfig(txCfgOpt);
    let txCfgOpt = attachedTxInfo?.normal.cfg
    if let txCfgOpt = txCfgOpt {
        el.setTextConfig(txCfgOpt)
    }

    // upstream mutates the option object in place; `elOption` is a value dict here, so shadow it.
    // PORT-NOTE (divergence): upstream's normalizations below (the DEFAULT_TRANSITION default, the ec4
    //   text compat, `style.decal` / `style.__decalPattern`) are observable through the SHARED option
    //   object; here they are confined to this local copy. Currently benign only because
    //   `customInnerStore(el).option` is never assigned (upstream does not assign it either — only
    //   GraphicView.ts:262 does). If the option is ever stored on the el, it MUST be this NORMALIZED
    //   copy, not the caller's raw dict.
    var elOption = elOption

    // Default transition ['x', 'y']
    // upstream: if (elOption && elOption.transition == null) { elOption.transition = DEFAULT_TRANSITION; }
    if elOption["transition"] == nil {
        elOption["transition"] = DEFAULT_TRANSITION
    }

    // FRAMEWORK GAP (the Int-vs-Double option-read trap): `applyUpdateTransition` applies the transform
    //   props through `Element.attr`, whose `_setKnownKV` only accepts a `Double` — an Int-boxed literal
    //   (`["x": 10, "position": [0, 5]]` in a `renderItem` return) would be silently dropped. The
    //   ANIMATION payloads are hit even harder: `Animator.Track.addKeyframe` classifies a value with
    //   `util.isNumber` (`value is Double`), so an Int-boxed `enterFrom: ["style": ["opacity": 0]]`
    //   degrades the track to `discrete` and the from-frame is then dropped by `_setKnownKV` — the
    //   fade-in silently becomes a snap. So coerce EVERY numeric leaf that reaches
    //   `applyUpdateTransition` / `updateLeaveTo` / `applyKeyframeAnimation`: the root transform props
    //   (+ the legacy `position`/`scale`/`origin` array aliases), the `enterFrom`/`leaveTo` bags at the
    //   root and inside each `ELEMENT_ANIMATABLE_PROPS` sub-bag, and the `keyframeAnimation` keyframes.
    //   JS has a single number type, so upstream has no analog.
    // PORT-NOTE: ideally this lives in the PROVIDER (customGraphicTransition /
    //   customGraphicKeyframeAnimation) so the other consumer (GraphicComponentView) gets it too; kept
    //   consumer-side here because that file is owned by another migration row.
    for key in TRANSFORMABLE_PROPS where elOption[key] != nil {
        if let d = customToDouble(elOption[key]) { elOption[key] = d }
    }
    // The legacy transform aliases — mirrors `LEGACY_TRANSFORM_PROPS_MAP` in customGraphicTransition.swift.
    for legacyKey in ["position", "scale", "origin"] {
        if let (a, b) = customVec2(elOption[legacyKey]) { elOption[legacyKey] = [a, b] }
    }
    for animKey in ["enterFrom", "leaveTo"] {
        if let v = elOption[animKey] { elOption[animKey] = customCoerceNumericLeaves(v) }
    }
    if let kf = elOption["keyframeAnimation"] {
        elOption["keyframeAnimation"] = customCoerceNumericLeaves(kf)
    }
    for bagName in ELEMENT_ANIMATABLE_PROPS where !bagName.isEmpty {
        guard var bag = elOption[bagName] as? [String: Any] else { continue }
        var touched = false
        for animKey in ["enterFrom", "leaveTo"] {
            if let v = bag[animKey] {
                bag[animKey] = customCoerceNumericLeaves(v)
                touched = true
            }
        }
        if touched { elOption[bagName] = bag }
    }

    // Do some normalization on style.
    var styleOpt = elOption["style"] as? [String: Any]

    if styleOpt != nil {
        if el.type == "text" {
            // upstream:
            //   const textOptionStyle = styleOpt as TextStyleProps;
            //   hasOwn(textOptionStyle, 'textFill') && (textOptionStyle.fill = textOptionStyle.textFill);
            //   hasOwn(textOptionStyle, 'textStroke') && (textOptionStyle.stroke = textOptionStyle.textStroke);
            // Compatible with ec4: if `textFill`/`textStroke` exist they OVERWRITE fill/stroke — so the
            //   normalized bag (not just `bridgeTextStyle`) carries the colour, and the transition
            //   machinery (`applyPropsDirectly` / `prepareStyleTransitionFrom`) can see it too.
            if let textFill = styleOpt?["textFill"] { styleOpt?["fill"] = textFill }
            if let textStroke = styleOpt?["textStroke"] { styleOpt?["stroke"] = textStroke }
        }

        // upstream:
        //   let decalPattern;
        //   const decalObj = isPath(el) ? (styleOpt as ...).decal : null;
        //   if (api && decalObj) { (decalObj as InnerDecalObject).dirty = true;
        //       decalPattern = createOrUpdatePatternFromDecal(decalObj, api); }
        //   (styleOpt as InnerCustomZRPathOptionStyle).__decalPattern = decalPattern;
        // PORT-NOTE: the `decalObj.dirty = true` marker drives upstream's `decalMap` WeakMap cache; the
        //   Swift `decal.swift` dropped that identity cache for a value-keyed one, so the marker is moot.
        var decalPattern: Pattern?
        let decalObj: Any? = (el is Path) ? styleOpt?["decal"] : nil
        if let api = api, let decalObj = decalObj {
            decalPattern = createOrUpdatePatternFromDecal(decalObj, api)
        }
        // Always overwrite in case user specify this prop.
        styleOpt?["__decalPattern"] = decalPattern

        // upstream: if (isDisplayable(el)) { if (styleOpt) { const decalPattern = styleOpt.__decalPattern;
        //   if (decalPattern) { (styleOpt as PathStyleProps).decal = decalPattern; } } }
        if el is Displayable, let decalPattern = decalPattern {
            styleOpt?["decal"] = decalPattern
        }
        elOption["style"] = styleOpt
    }

    // upstream: applyUpdateTransition(el, elOption, seriesModel, { dataIndex, isInit, clearStyle: true });
    applyUpdateTransition(
        el, elOption, seriesModel,
        ApplyUpdateTransitionOpts(dataIndex: dataIndex, isInit: isInit, clearStyle: true)
    )
    // FRAMEWORK GAP (typed value-struct shape/style): `applyUpdateTransition` applies its final props
    //   through the generic `el.attr(["shape"/"style": dict])` seam, which can only MERGE the keys the
    //   element's `PathShape.animationSet` / `*StyleProps.animationSet` expose (numeric/colour fields of
    //   an ALREADY-typed shape). A custom `renderItem` return also carries keys that only the typed
    //   bridges below can express — `points`, `pathData`, a text `style.text`, an image `style.image`,
    //   a rect `r` array, and the shape's own `fill: null` default. So re-apply the typed final shape and
    //   style AFTER the transition (both accessors read/write the LIVE `path.shape` / `path.pathStyle`
    //   per key, so a running animator keeps tweening on top of this and is not clobbered).
    applyTypedShapeAndStyle(el, elOption)

    // upstream: applyKeyframeAnimation(el, elOption.keyframeAnimation, seriesModel);
    applyKeyframeAnimation(el, elOption["keyframeAnimation"], seriesModel)
}

// The typed-struct half of `applyUpdateTransition`'s `applyPropsDirectly` — see the FRAMEWORK GAP note
//   at the call site. Transform / legacy-transform / misc props are handled by `applyUpdateTransition`.
private func applyTypedShapeAndStyle(_ el: Element, _ elOption: [String: Any]) {
    // Shape (typed struct per element kind).
    if let shapeOpt = elOption["shape"] as? [String: Any], let path = el as? Path {
        applyShape(path, customInnerStore(el).customGraphicType, shapeOpt)
    }
    // Style (typed struct per Displayable kind).
    if let styleOpt = elOption["style"] as? [String: Any] {
        applyStyle(el, styleOpt)
    }
    // Transform props (x/y/rotation/scale*/origin*, incl. the legacy `position`/`scale`/`origin` array
    //   aliases) and the misc flags (ignore/silent/invisible/autoBatch) are applied by
    //   `applyUpdateTransition` (prepareTransformAllPropsFinal + applyMiscProps).
}

// Build the concrete `PathShape` for the element's type from a `[String: Any]` shape bag, then
//   `setShape`. Mirrors the per-type shape structs in ZRenderKit/Graphic/Shape. `x || 0` semantics
//   → `customToDouble(...) ?? 0`.
private func applyShape(_ path: Path, _ graphicType: String?, _ s: [String: Any]) {
    func num(_ k: String, _ dflt: Double = 0) -> Double { customToDouble(s[k]) ?? dflt }
    switch graphicType {
    case "rect":
        var shape = RectShape()
        shape.x = num("x"); shape.y = num("y")
        shape.width = num("width"); shape.height = num("height")
        shape.r = bridgeRectRadius(s["r"])
        _ = path.setShape(shape)
    case "circle":
        var shape = CircleShape()
        shape.cx = num("cx"); shape.cy = num("cy"); shape.r = num("r")
        _ = path.setShape(shape)
    case "ellipse":
        var shape = EllipseShape()
        shape.cx = num("cx"); shape.cy = num("cy")
        shape.rx = num("rx"); shape.ry = num("ry")
        _ = path.setShape(shape)
    case "sector":
        var shape = SectorShape()
        shape.cx = num("cx"); shape.cy = num("cy")
        shape.r0 = num("r0"); shape.r = num("r")
        shape.startAngle = num("startAngle"); shape.endAngle = num("endAngle", Double.pi * 2)
        if let cw = s["clockwise"] as? Bool { shape.clockwise = cw }
        _ = path.setShape(shape)
    case "ring":
        var shape = RingShape()
        shape.cx = num("cx"); shape.cy = num("cy"); shape.r = num("r"); shape.r0 = num("r0")
        _ = path.setShape(shape)
    case "arc":
        var shape = ArcShape()
        shape.cx = num("cx"); shape.cy = num("cy"); shape.r = num("r")
        shape.startAngle = num("startAngle"); shape.endAngle = num("endAngle", Double.pi * 2)
        if let cw = s["clockwise"] as? Bool { shape.clockwise = cw }
        _ = path.setShape(shape)
    case "line":
        var shape = LineShape()
        shape.x1 = num("x1"); shape.y1 = num("y1")
        shape.x2 = num("x2"); shape.y2 = num("y2")
        shape.percent = num("percent", 1)
        _ = path.setShape(shape)
    case "polygon":
        var shape = PolygonShape()
        shape.points = bridgePoints(s["points"])
        shape.smooth = customToDouble(s["smooth"])
        _ = path.setShape(shape)
    case "polyline":
        var shape = PolylineShape()
        shape.points = bridgePoints(s["points"])
        shape.smooth = customToDouble(s["smooth"])
        if let p = customToDouble(s["percent"]) { shape.percent = p }
        _ = path.setShape(shape)
    case "bezierCurve":
        var shape = BezierCurveShape()
        shape.x1 = num("x1"); shape.y1 = num("y1")
        shape.x2 = num("x2"); shape.y2 = num("y2")
        shape.cpx1 = num("cpx1"); shape.cpy1 = num("cpy1")
        shape.cpx2 = customToDouble(s["cpx2"]); shape.cpy2 = customToDouble(s["cpy2"])
        shape.percent = num("percent", 1)
        _ = path.setShape(shape)
    default:
        // path / compoundPath / unknown — shape building deferred (makePath / paths).
        break
    }
}

// Apply a `[String: Any]` style bag to a Displayable, bridging into the element-kind's typed style
//   struct. Minimal faithful key mapping (see per-kind bridges below).
private func applyStyle(_ el: Element, _ s: [String: Any]) {
    if let text = el as? ZRText {
        text.useStyle(bridgeTextStyle(s))
    }
    else if let image = el as? ZRImage {
        image.useStyle(bridgeImageStyle(s))
    }
    else if let path = el as? Path {
        let bridged = bridgePathStyle(s)
        path.useStyle(bridged)
        // `null` is an authored paint value in custom renderItem output: it means no paint, while an
        // omitted key inherits the shape/default style. Swift option bags preserve that distinction as
        // NSNull, but the optional ZRColor bridge cannot. Re-apply explicit null after useStyle so a
        // stroked ellipse/polygon does not inherit Path's generic black fill.
        if s["fill"] is NSNull { path.pathStyle.fill = nil }
        if s["stroke"] is NSNull { path.pathStyle.stroke = nil }
        // FRAMEWORK GAP (fill-less stroke shapes: polyline/line/bezierCurve/arc/rose/trochoid): upstream
        //   `useStyle` merges onto a PROTOTYPE (`Object.create(DEFAULT_PATH_STYLE)`), so a shape class's
        //   own `getDefaultStyle()` (these declare `fill: null`) keeps shadowing the generic `fill:'#000'`
        //   proto value as long as the caller's style bag never restates "fill". `PathStyleProps.fill` is a
        //   Swift `ZRColor?` that cannot distinguish "shadowed by prototype (intentional nil)" from "absent",
        //   so `Path.useStyle`/`createStyle` can only re-merge onto the GENERIC `DEFAULT_PATH_STYLE.fill`
        //   ('#000') — a custom `renderItem` returning e.g. `{type:'polyline', style:{stroke:'#aaa'}}` (no
        //   `fill` — official-custom-hexbin's court lines) would paint solid BLACK instead of unfilled.
        //   Re-assert the shape's OWN default when the bridged style resolved no real fill (mirrors the
        //   one-time correction Path._init() already does).
        if s["fill"] == nil, bridged.fill == nil, let ownDefault = path.getDefaultStyle() {
            path.pathStyle.fill = ownDefault.fill
        }
    }
}

// upstream: function updateElOnState(state, el, elStateOpt, styleOpt, attachedTxInfo): void
//   Ported from util/states (ensureState / getState / setDefaultStateProxy — all present in
//   ZRenderKit.Element + util/states.swift). `elStateOpt` mirrors upstream: it is not read here.
private func updateElOnState(
    _ state: String,
    _ el: Element,
    _ elStateOpt: Any?,
    _ styleOpt: Any?,
    _ attachedTxInfo: AttachedTxInfo?
) {
    // upstream: const elDisplayable = el.isGroup ? null : el as Displayable;
    let elDisplayable = el.isGroup ? nil : (el as? Displayable)
    // upstream: const txCfgOpt = attachedTxInfo && attachedTxInfo[state].cfg;
    let txCfgOpt = attachedTxInfo?[state].cfg

    if let elDisplayable = elDisplayable {
        // By default support auto lift color when hover whether `emphasis` specified.
        let stateObj = elDisplayable.ensureState(state)
        // upstream: if (styleOpt === false) { const existing = getState(state); existing && (existing.style = null) }
        //   else { stateObj.style = styleOpt || null }  — `styleOpt === false` removes the hover style.
        if let styleFalse = styleOpt as? Bool, styleFalse == false {
            if let existingEmphasisState = elDisplayable.getState(state) {
                existingEmphasisState.style = nil
                if elDisplayable is ZRText { existingEmphasisState.textStyle = nil }
            }
        }
        else {
            // style is needed to enable default emphasis.
            stateObj.style = styleOpt as? [String: Any]
            // Upstream ZRText uses the same untyped `state.style` bag as every Displayable. The Swift
            // port stores live text style in a typed side channel, so bridge the identical authored bag
            // there as well; ZRText.useState reads it back when emphasis/blur/select is applied.
            if elDisplayable is ZRText {
                stateObj.textStyle = (styleOpt as? [String: Any]).map(bridgeTextStyle)
            }
        }
        // upstream: if (txCfgOpt) stateObj.textConfig = txCfgOpt;
        if let txCfgOpt = txCfgOpt {
            stateObj.textConfig = txCfgOpt
        }
        states.setDefaultStateProxy(elDisplayable)
    }
    _ = elStateOpt
}

// upstream: function updateZ(el, elOption, seriesModel): void
private func updateZ(
    _ el: Element,
    _ elOption: [String: Any],
    _ seriesModel: CustomSeriesModel
) {
    // Group not support textContent and not support z yet.
    if el.isGroup {
        return
    }
    guard let elDisplayable = el as? Displayable else { return }

    // upstream: const currentZ = seriesModel.currentZ; const currentZLevel = seriesModel.currentZLevel;
    //   Always erase. (`currentZ`/`currentZLevel` are populated by CustomSeriesModel.optionUpdated.)
    let currentZ = seriesModel.currentZ
    let currentZLevel = seriesModel.currentZLevel
    elDisplayable.z = currentZ
    elDisplayable.zlevel = currentZLevel

    // z2 must not be null/undefined, otherwise sort error may occur.
    // upstream: const optZ2 = elOption.z2; optZ2 != null && (elDisplayable.z2 = optZ2 || 0);
    if let optZ2 = customToDouble(elOption["z2"]) {
        elDisplayable.z2 = optZ2   // `optZ2 || 0` — a present numeric is kept as-is.
    }

    // PORT bridge: the display list is z-sorted (zlevel → z → z2) and an attached `textContent` is a
    //   SEPARATE display-list entry. A custom `renderItem` text child is created bare (z2 defaults to 0),
    //   so on a series whose z2 varies per datum (e.g. circle-packing's `z2: depth*2`) the labels sort
    //   BELOW the deeper shapes and get painted over — invisible. zrender keeps an attached text adjacent
    //   to its host because `ZRText.update` copies the host's z/z2/zlevel down to its TSpans; mirror that
    //   at the host→text seam by giving the text the host's z-props (the stable-sort offset tiebreak then
    //   keeps it right AFTER the host). Deferred per-state z is unaffected.
    if let textEl = el.getTextContent() {
        textEl.z = elDisplayable.z
        textEl.zlevel = elDisplayable.zlevel
        textEl.z2 = elDisplayable.z2
    }

    // upstream: for (let i = 0; i < STATES.length; i++) updateZForEachState(elDisplayable, elOption, STATES[i]);
    for state in STATES {
        updateZForEachState(elDisplayable, elOption, state)
    }
}

// upstream: function updateZForEachState(elDisplayable, elOption, state): void
//   Per-state z2 override — a renderItem `{emphasis:{z2},…}` bumps the state object's z2 (normal writes
//   directly; non-normal writes onto `ensureState(state)`, which the state-apply path lifts on activate).
private func updateZForEachState(
    _ elDisplayable: Displayable,
    _ elOption: [String: Any],
    _ state: String
) {
    let isNormal = state == NORMAL
    // const elStateOpt = isNormal ? elOption : retrieveStateOption(elOption, state);
    let elStateOpt: [String: Any]? = isNormal
        ? elOption
        : (retrieveStateOption(elOption, state) as? [String: Any])
    // const optZ2 = elStateOpt ? elStateOpt.z2 : null;
    let optZ2 = elStateOpt.flatMap { customToDouble($0["z2"]) }
    // if (optZ2 != null) { stateObj = isNormal ? elDisplayable : ensureState(state); stateObj.z2 = optZ2 || 0; }
    if let optZ2 = optZ2 {
        if isNormal {
            elDisplayable.z2 = optZ2
        }
        else {
            // `ElementState` has no typed `z2` accessor; store into its generic prop bag (the state-apply
            //   path routes "z2" through Displayable.animationSet/attrKV onto el.z2 when the state activates).
            elDisplayable.ensureState(state).props["z2"] = optZ2
        }
    }
}

// upstream: function makeRenderItem(customSeries, data, ecModel, api)
//   Consumes the sibling `CustomSeries.swift` types: `CustomSeriesRenderItemAPI` (a protocol —
//   realized by the concrete `CustomRenderItemAPI` below), `CustomSeriesRenderItemParams` (a struct),
//   and the `CustomSeriesRenderItem` closure via `customSeries.getRenderItem()`.
private func makeRenderItem(
    _ customSeries: CustomSeriesModel,
    _ data: SeriesData,
    _ ecModel: GlobalModel,
    _ api: ExtensionAPI
) -> (_ dataIndexInside: Int, _ payload: Payload?) -> Any? {

    // upstream: let renderItem = customSeries.get('renderItem');
    //   if (typeof renderItem === 'string') { renderItem = getCustomSeries(renderItem) ... }
    //   The Swift option bag carries either the closure directly under "renderItem" (getRenderItem()) OR
    //   the closure is registered globally via registerCustomSeries(subType, ...); fall back to
    //   getCustomSeries(subType) so an option that cannot carry a Swift closure (e.g. a JSON-serialized
    //   demo option) still resolves. Mirrors `customSeries.get('renderItem') || getCustomSeries(subType)`.
    let renderItem = customSeries.getRenderItem() ?? getCustomSeries(customSeries.subType)

    let coordSys = customSeries.coordinateSystem
    // upstream: let prepareResult = {} as ReturnType<PrepareCustomInfo>;
    var prepareResult: [String: Any] = [:]

    if let coordSys = coordSys {
        // upstream DEV assert: renderItem present + coordSys supports custom.
        // upstream: prepareResult = coordSys.prepareCustoms ? coordSys.prepareCustoms(coordSys)
        //             : prepareCustoms[coordSys.type](coordSys);
        // PORT-NOTE: `coordSys.prepareCustoms` is modeled (a property on CoordinateSystem), but this
        //   call site still only uses the built-in dispatch and does not yet consult the coordSys
        //   override (relevant to external systems like bmap).
        if let r = prepareCustoms(coordSys) {
            prepareResult = r
        }
    }

    let prepareApi = prepareResult["api"] as? [String: Any]

    // upstream: const userAPI = defaults({ getWidth, getHeight, getZr, getDevicePixelRatio, value,
    //     style, ordinalRawValue, styleEmphasis, visual, barLayout, currentSeriesIndices, font },
    //     prepareResult.api || {}) as CustomSeriesRenderItemAPI;
    //   The sibling `CustomSeriesRenderItemAPI` is a *protocol* (not an object literal), so the api is a
    //   concrete `CustomRenderItemAPI` (below) that closes over data/ecModel/extApi/coordSys + the
    //   coord/size closures from `prepareResult.api`. `currDataIndexInside` lives on that instance
    //   (upstream's closure-captured mutable state).
    let userAPI = CustomRenderItemAPI(
        customSeries: customSeries, data: data,
        ecModel: ecModel,
        extApi: api,
        coordSys: coordSys,
        coordClosure: prepareApi?["coord"] as? ([Double]) -> [Double],
        sizeClosure: prepareApi?["size"] as? ([Double], [Double]?) -> [Double]
    )

    // upstream: const userParams: CustomSeriesRenderItemParams = { context: {}, seriesId, seriesName,
    //     seriesIndex, coordSys: prepareResult.coordSys, dataInsideLength: data.count(),
    //     encode: wrapEncodeDef(customSeries.getData()), itemPayload: customSeries.get('itemPayload') || {} }
    //   `CustomSeriesRenderItemParams` is a struct (value bag), while `context` is the one reference
    //   object shared by all datum calls made by this render round.
    let coordSysBag = prepareResult["coordSys"] as? [String: Any]
    let paramsCoordSys = CustomSeriesRenderItemParamsCoordSys(
        type: (coordSysBag?["type"] as? String) ?? "",
        extra: coordSysBag ?? [:]
    )
    let encode = wrapEncodeDef(customSeries.getData())
    let itemPayload = (customSeries.get("itemPayload", true) as? [String: Any]) ?? [:]
    let seriesId = customSeries.id
    let seriesName = customSeries.name
    let seriesIndex = customSeries.seriesIndex
    let dataInsideLength = Double(data.count())
    let renderContext = CustomSeriesRenderItemContext()

    // upstream: return function (dataIndexInside, payload): CustomElementOption { ... }
    return { (dataIndexInside: Int, payload: Payload?) -> Any? in
        userAPI.currDataIndexInside = dataIndexInside

        // upstream: renderItem && renderItem(defaults({ dataIndexInside, dataIndex, actionType }, userParams), userAPI)
        let userParams = CustomSeriesRenderItemParams(
            context: renderContext,
            dataIndex: Double(data.getRawIndex(dataIndexInside)),
            seriesId: seriesId,
            seriesName: seriesName,
            seriesIndex: seriesIndex,
            coordSys: paramsCoordSys,
            encode: encode,
            dataIndexInside: Double(dataIndexInside),
            dataInsideLength: dataInsideLength,
            itemPayload: itemPayload,
            actionType: payload?.type
        )

        return renderItem?(userParams, userAPI)
    }
}

// The concrete `CustomSeriesRenderItemAPI` (a protocol on the sibling `CustomSeries.swift`). Upstream
//   builds this as an object literal of closures; here it is a `final class` holding the render-round
//   state (`currDataIndexInside`) + the coord-system `coord`/`size` closures produced by `prepareCustoms`.
private final class CustomRenderItemAPI: CustomSeriesRenderItemAPI {
    let customSeries: CustomSeriesModel
    let data: SeriesData
    let ecModel: GlobalModel
    let extApi: ExtensionAPI
    let coordSys: Any?
    let coordClosure: (([Double]) -> [Double])?
    let sizeClosure: (([Double], [Double]?) -> [Double])?
    // upstream: closure-captured `let currDataIndexInside: number;`
    var currDataIndexInside: Int = 0

    init(
        customSeries: CustomSeriesModel, data: SeriesData, ecModel: GlobalModel, extApi: ExtensionAPI, coordSys: Any?,
        coordClosure: (([Double]) -> [Double])?, sizeClosure: (([Double], [Double]?) -> [Double])?
    ) {
        self.customSeries = customSeries
        self.data = data
        self.ecModel = ecModel
        self.extApi = extApi
        self.coordSys = coordSys
        self.coordClosure = coordClosure
        self.sizeClosure = sizeClosure
    }

    // ---- CustomSeriesRenderItemCoordinateSystemAPI (coord/size from prepareResult.api) ----

    func coord(_ data: Any?, _ opt: Any?) -> [Double] {
        if let coordClosure = coordClosure {
            return coordClosure(toDoubleArray(data))
        }
        // Fallback: the prepareCustom `coord` closure just wraps `coordSys.dataToPoint`. For coord systems
        // whose prepareCustom closure has a different Swift signature than the cartesian one the caller
        // hard-casts to (single/calendar/matrix), that cast yields nil — call `dataToPoint` generically
        // (api.coord is coord-system-agnostic upstream) so custom still projects instead of returning [].
        if let cs = coordSys as? CoordinateSystem {
            // Pass `data` RAW (not toDoubleArray): calendar's dataToPoint needs the raw date string
            //   (e.g. "2017-03-01"), which toDoubleArray drops to [] → [NaN, NaN]. Every real
            //   prepareCustom.coord closure forwards data verbatim upstream; matches that. (Numeric
            //   coords — polar/geo/single — are unaffected: a [Double] passes through unchanged.)
            return cs.dataToPoint(data as Any, opt)
        }
        return []
    }
    func size(_ dataSize: Any?, _ dataItem: Any?) -> Any? {
        guard let sizeClosure = sizeClosure else { return nil }
        let item: [Double]? = dataItem == nil ? nil : toDoubleArray(dataItem)
        return sizeClosure(toDoubleArray(dataSize), item)
    }
    // upstream: layout(data, opt?) { return coordSys.dataToLayout ? coordSys.dataToLayout(data, opt) : ...; }
    //   Only `calendar`/`matrix` implement `dataToLayout` upstream (cartesian2d/geo/polar/single don't), and
    //   each prepareCustom's "layout" closure has its own Swift signature — no single hard-cast type would
    //   match both (same reason `coord` above falls back for those coord systems). Call `dataToLayout`
    //   through the generic `CoordinateSystem` protocol, passing `data` through RAW (unlike `coord`'s
    //   `toDoubleArray`): matrix's `dataToLayout` resolves category-string locators (e.g. 'Positive') via
    //   its own ordinalMeta, so coercing to `[Double]` first would lose that information.
    func layout(_ data: Any?, _ opt: Any?) -> CoordinateSystemDataLayout? {
        if let cs = coordSys as? CoordinateSystem {
            return cs.dataToLayout(data as Any, opt)
        }
        return nil
    }

    // ---- ExtensionAPI-forwarded ----

    func getWidth() -> Double { return extApi.getWidth() }
    func getHeight() -> Double { return extApi.getHeight() }
    // upstream: getZr: api.getZr, getDevicePixelRatio: api.getDevicePixelRatio — forwarded to
    //   ExtensionAPI, which now exposes both (`getZr` returns the host `ZRenderType?`, nil in pure
    //   headless; `getDevicePixelRatio` returns the painter dpr, 1 by default).
    func getZr() -> Any? { return extApi.getZr() }
    func getDevicePixelRatio() -> Double { return extApi.getDevicePixelRatio() }

    // ---- data accessors ----

    private func resolveIdx(_ dataIndexInside: Double?) -> Int {
        // dataIndexInside == null && (dataIndexInside = currDataIndexInside)
        return dataIndexInside.map { Int($0) } ?? currDataIndexInside
    }

    // upstream: function value(dim?, dataIndexInside?): ParsedValue
    func value(_ dim: DimensionLoose, _ dataIndexInside: Double?) -> ParsedValue {
        let idx = resolveIdx(dataIndexInside)
        // data.getStore().get(data.getDimensionIndex(dim || 0), dataIndexInside)
        let dimIndex = data.getDimensionIndex(dim)
        return data.getStore().get(dimIndex, idx)
    }

    // upstream: function ordinalRawValue(dim?, dataIndexInside?): ParsedValue | OrdinalRawValue
    func ordinalRawValue(_ dim: DimensionLoose, _ dataIndexInside: Double?) -> Any? {
        let idx = resolveIdx(dataIndexInside)
        // PORT-NOTE (language difference): `data.getDimensionInfo` returns a non-Optional
        //   `SeriesDimensionDefine` in this port (a missing dim can not be signalled), so upstream's
        //   `if (!dimInfo) { getDimensionIndex fallback }` branch is unreachable; the ordinalMeta path
        //   below covers the common case.
        let dimInfo = data.getDimensionInfo(dim)
        let val = data.get(dimInfo.name, idx)
        // upstream: const ordinalMeta = dimInfo && dimInfo.ordinalMeta;
        //           return ordinalMeta ? ordinalMeta.categories[val as number] : val;
        //   `SeriesDimensionDefine.ordinalMeta` IS modeled → wired. Numeric coercion of the ordinal
        //   index mirrors SeriesData._getCategory (CONVENTIONS INT-vs-DOUBLE trap).
        if let ordinalMeta = dimInfo.ordinalMeta {
            let oi = (val as? Double) ?? Double.nan
            if oi.isFinite {
                let i = Int(oi)
                if i >= 0 && i < ordinalMeta.categories.count {
                    return ordinalMeta.categories[i]
                }
            }
        }
        return val
    }

    // upstream (deprecated): function style(userProps?, dataIndexInside?): ZRStyleProps
    //   The normal label compatibility path is intentionally kept because official ECharts 4-era
    //   custom examples use `api.style()` to materialize `series.label` on the returned host shape.
    func style(_ userProps: [String: Any]?, _ dataIndexInside: Double?) -> [String: Any] {
        let idx = resolveIdx(dataIndexInside)
        var out = (data.getItemVisual(idx, "style") as? [String: Any]) ?? [:]

        let itemModel = data.getItemModel(idx)
        let labelModel = itemModel.getModel("label")
        if (labelModel.getShallow("show") as? Bool) == true {
            let visualColor = out["fill"] as? String
            let common = TextCommonParams(inheritColor: visualColor ?? "#000")
            let textStyle = labelStyle.createTextStyle(labelModel, nil, common, false, false)
            let textConfig = labelStyle.createTextConfig(labelModel, common, false)
            let text = customSeries.getFormattedLabel(Double(idx), .normal, nil, nil, nil, nil)
                ?? labelHelper.getDefaultLabel(data, Double(idx))

            if let text { out["text"] = text }
            out["textPosition"] = textConfig.position ?? "inside"
            if let offset = textConfig.offset { out["textOffset"] = offset }
            if let rotation = textConfig.rotation { out["textRotation"] = rotation }
            if let distance = textConfig.distance { out["textDistance"] = distance }

            let position = (out["textPosition"] as? String) ?? "inside"
            let isInside = position.contains("inside")
            out["textFill"] = textStyle.fill
                ?? (isInside ? (textConfig.insideFill ?? "#fff") : (visualColor ?? textConfig.outsideFill ?? "#000"))
            if let stroke = textStyle.stroke { out["textStroke"] = stroke }
            if let width = textStyle.lineWidth { out["textStrokeWidth"] = width }
            if let font = textStyle.font { out["font"] = font }
            if let align = textStyle.align { out["textAlign"] = align.rawValue }
            if let verticalAlign = textStyle.verticalAlign { out["textVerticalAlign"] = verticalAlign.rawValue }
            out["legacy"] = true
        }
        if let userProps = userProps {
            for (k, v) in userProps { out[k] = v }
        }
        return out
    }

    // upstream (deprecated): function styleEmphasis(userProps?, dataIndexInside?): ZRStyleProps  — DEFERRED.
    func styleEmphasis(_ userProps: [String: Any]?, _ dataIndexInside: Double?) -> [String: Any] {
        // PORT-NOTE (deferred): the full (deprecated) api.styleEmphasis requires the same label/styleCompat
        //   surface as api.style (not ported); returns userProps as a best effort.
        return userProps ?? [:]
    }

    // upstream: function visual(visualType, dataIndexInside?)
    func visual(_ visualType: String, _ dataIndexInside: Double?) -> Any? {
        let idx = resolveIdx(dataIndexInside)
        // upstream STYLE_VISUAL_TYPE = { color: 'fill', borderColor: 'stroke' }.
        let styleVisualType: [String: String] = ["color": "fill", "borderColor": "stroke"]
        if let styleKey = styleVisualType[visualType] {
            let style = data.getItemVisual(idx, "style") as? [String: Any]
            return style?[styleKey]
        }
        // upstream NON_STYLE_VISUAL_PROPS = { symbol, symbolSize, symbolKeepAspect, legendIcon, visualMeta,
        //   liftZ, decal }.
        let nonStyleVisualProps: Set<String> = [
            "symbol", "symbolSize", "symbolKeepAspect", "legendIcon", "visualMeta", "liftZ", "decal"
        ]
        if nonStyleVisualProps.contains(visualType) {
            return data.getItemVisual(idx, visualType)
        }
        return nil
    }

    // upstream: function barLayout(opt): BarGridLayoutResultForCustomSeries
    func barLayout(_ opt: Any?) -> Any? {
        if let cartesian = coordSys as? Cartesian2D {
            let optBag = (opt as? [String: Any]) ?? [:]
            let baseAxis = cartesian.getBaseAxis()
            // computeBarLayoutForCustomSeries(defaults({axis: baseAxis}, opt))
            let layoutOpt = BarGridLayoutOption(
                count: customToDouble(optBag["count"]) ?? 0,
                axis: baseAxis,
                barWidth: optBag["barWidth"],
                barMaxWidth: optBag["barMaxWidth"],
                barMinWidth: optBag["barMinWidth"],
                barGap: optBag["barGap"],
                barCategoryGap: optBag["barCategoryGap"]
            )
            return computeBarLayoutForCustomSeries(layoutOpt)
        }
        return nil
    }

    // upstream: function currentSeriesIndices() { return ecModel.getCurrentSeriesIndices(); }
    func currentSeriesIndices() -> [Double] {
        return ecModel.getCurrentSeriesIndices()
    }

    // upstream: function font(opt) { return labelStyleHelper.getFont(opt, ecModel); }
    func font(_ opt: [String: Any]?) -> String {
        let fontOpt = labelStyle.GetFontOpt(
            fontStyle: opt?["fontStyle"],
            fontWeight: opt?["fontWeight"],
            fontSize: opt?["fontSize"],
            fontFamily: opt?["fontFamily"]
        )
        return labelStyle.getFont(fontOpt, ecModel)
    }
}

// `data`/`dataSize`/`dataItem` bags for `coord`/`size` may be `[Double]` or `[Any]` (Int|Double) —
//   coerce to `[Double]` (the coord-sys closures consume `[Double]`).
private func toDoubleArray(_ v: Any?) -> [Double] {
    if let arr = v as? [Double] { return arr }
    if let arr = v as? [Any] { return arr.map { customToDouble($0) ?? Double.nan } }
    if let d = customToDouble(v) { return [d] }
    return []
}

// upstream: function wrapEncodeDef(data): WrapEncodeDefRet
//   Builds `{ [coordDim]: dataDimIndex[] }` from the data's dimensions.
private func wrapEncodeDef(_ data: SeriesData) -> [String: [DimensionIndex]] {
    var encodeDef: [String: [DimensionIndex]] = [:]
    util.each(data.dimensions) { (dimName: String, _) in
        let dimInfo = data.getDimensionInfo(dimName)
        if !(dimInfo.isExtraCoord ?? false) {
            let coordDim = dimInfo.coordDim ?? ""
            var dataDims = encodeDef[coordDim] ?? []
            let coordDimIndex = Int(dimInfo.coordDimIndex ?? 0)
            // dataDims[dimInfo.coordDimIndex] = data.getDimensionIndex(dimName);
            while dataDims.count <= coordDimIndex { dataDims.append(0) }
            dataDims[coordDimIndex] = data.getDimensionIndex(dimName)
            encodeDef[coordDim] = dataDims
        }
    }
    return encodeDef
}

// upstream: function createOrUpdateItem(api, existsEl, dataIndex, elOption, seriesModel, group, data): Element
private func createOrUpdateItem(
    _ api: ExtensionAPI?,
    _ existsEl: Element?,
    _ dataIndex: Int,
    _ elOptionAny: Any?,
    _ seriesModel: CustomSeriesModel,
    _ group: Group,
    _ data: SeriesData
) -> Element? {
    // [Rule] If `renderItem` returns null/undefined/false, remove the previous el if existing.
    //   In the Swift port the returned spec is `Any?` (a `[String: Any]` element bag, or nil/false).
    let elOption = normalizeElOption(elOptionAny)
    if elOption == nil {
        // upstream: group.remove(existsEl); return;
        if let existsEl = existsEl {
            _ = group.remove(existsEl)
        }
        return nil
    }
    let el = doCreateOrUpdateEl(api, existsEl, dataIndex, elOption!, seriesModel, group)
    if let el = el {
        data.setItemGraphicEl(dataIndex, el)

        // upstream: el && toggleHoverEmphasis(el, elOption.focus, elOption.blurScope, elOption.emphasisDisabled);
        //   Ported (util/states.toggleHoverEmphasis); mirrors BarView's coercion of the option-bag
        //   entries to the states API types. `elOption` is guaranteed non-nil past the guard above.
        let focus: InnerFocus? = elOption!["focus"]
        let blurScope = (elOption!["blurScope"] as? String).flatMap { BlurScope(rawValue: $0) }
        let isDisabled = (elOption!["emphasisDisabled"] as? Bool) ?? false
        states.toggleHoverEmphasis(el, focus, blurScope, isDisabled)
    }

    return el
}

// upstream: function doCreateOrUpdateEl(api, existsEl, dataIndex, elOption, seriesModel, group): Element
private func doCreateOrUpdateEl(
    _ api: ExtensionAPI?,
    _ existsElIn: Element?,
    _ dataIndex: Int,
    _ elOptionIn: [String: Any],
    _ seriesModel: CustomSeriesModel,
    _ group: Group
) -> Element? {

    let elOption = customNormalizeLegacyText(elOptionIn)

    // upstream DEV assert: elOption not null.

    var toBeReplacedIdx = -1
    let oldEl = existsElIn
    var existsEl = existsElIn
    if let e = existsEl,
       doesElNeedRecreate(e, elOption, seriesModel) {
        // Should keep at the original index, otherwise "merge by index" will be incorrect.
        // upstream: indexOf(group.childrenRef(), existsEl) — `Element` is not `Equatable`, so match by
        //   identity (`===`) rather than `util.indexOf`.
        toBeReplacedIdx = group.childrenRef().firstIndex(where: { $0 === e }) ?? -1
        existsEl = nil
    }

    let isInit = existsEl == nil
    var el = existsEl

    if el == nil {
        el = createEl(elOption)
        if let oldEl = oldEl {
            copyElement(oldEl, el!)
        }
    }
    else {
        // upstream: el.clearStates(). A custom-series update frequently reuses the same graphic
        // element for a different data index/layout. Keeping its previous hover emphasis here leaks
        // the old stroke/text state into the newly rendered frame (notably flame-graph drill-down).
        el?.clearStates()
    }
    let elUnwrapped = el!

    // upstream:
    //   // Need to set morph: false explictly to disable automatically morphing.
    //   if ((elOption as CustomBaseZRPathOption).morph === false) { (el as ECElement).disableMorphing = true; }
    //   else if ((el as ECElement).disableMorphing) { (el as ECElement).disableMorphing = false; }
    //   morph — still DEFERRED (path morphing is not wired into the custom series' transition path).
    //
    // upstream: if (elOption.tooltipDisabled) { (el as ECElement).tooltipDisabled = true; }
    //   NO LONGER DEFERRED. The stale reason ("ECElement not conformed") was only half the story:
    //   `Element` still does not conform to `ECElement`, but the flag now has a real home — the
    //   per-element side store `innerStore.getECElementProps` (util/innerStore.swift) — and a real
    //   READER: `TooltipView._tryShow`'s `findEventDispatcher` walk (upstream TooltipView.ts:483) bails
    //   out of the tooltip entirely when the hovered element or ANY ancestor carries it. Without this
    //   assignment `renderItem`'s documented `tooltipDisabled: true` silently did nothing.
    if (elOption["tooltipDisabled"] as? Bool) == true {
        innerStore.getECElementProps(elUnwrapped).tooltipDisabled = true
    }

    // Reset the per-render attached-text scratch.
    attachedTxInfoTmp.normal.cfg = nil; attachedTxInfoTmp.normal.conOpt = nil
    attachedTxInfoTmp.emphasis.cfg = nil; attachedTxInfoTmp.emphasis.conOpt = nil
    attachedTxInfoTmp.blur.cfg = nil; attachedTxInfoTmp.blur.conOpt = nil
    attachedTxInfoTmp.select.cfg = nil; attachedTxInfoTmp.select.conOpt = nil
    attachedTxInfoTmp.isLegacy = false

    doCreateOrUpdateAttachedTx(
        elUnwrapped, dataIndex, elOption, seriesModel, isInit, attachedTxInfoTmp
    )

    // upstream: doCreateOrUpdateClipPath(el, dataIndex, elOption, seriesModel, isInit);
    // PORT-NOTE: per-element clip paths use the same normal update path as ordinary custom elements,
    // including `applyUpdateTransition` and `during`. Without this call a sector/polygon clip (such as
    // custom-gauge's arc and pointer) would either render unclipped or snap to its final geometry.
    doCreateOrUpdateClipPath(elUnwrapped, dataIndex, elOption, seriesModel, isInit)

    updateElNormal(
        api, elUnwrapped, dataIndex, elOption, attachedTxInfoTmp, seriesModel, isInit
    )

    // `elOption.info` enables user to mount some info on elements and use them in event handlers.
    // upstream: hasOwn(elOption, 'info') && (customInnerStore(el).info = elOption.info);
    if elOption["info"] != nil {
        // customInnerStore(el).info : CustomExtraElementInfo? (== [String: Any]?)
        customInnerStore(elUnwrapped).info = elOption["info"] as? [String: Any]
    }

    // upstream: for (let i = 0; i < STATES.length; i++) { const stateName = STATES[i];
    //   if (stateName !== NORMAL) {
    //     const otherStateOpt = retrieveStateOption(elOption, stateName);
    //     const otherStyleOpt = retrieveStyleOptionOnState(elOption, otherStateOpt, stateName);
    //     updateElOnState(stateName, el, otherStateOpt, otherStyleOpt, attachedTxInfoTmp); } }
    //   Now WIRED (util/states machinery ported): applies the renderItem emphasis/blur/select `style`
    //   overrides onto the element's per-state objects (+ setDefaultStateProxy for auto color lift on
    //   hover). The state-apply path (useState → animateTo) picks these up when the state activates.
    for stateName in STATES {
        if stateName != NORMAL {
            let otherStateOpt = retrieveStateOption(elOption, stateName)
            let otherStyleOpt = retrieveStyleOptionOnState(elOption, otherStateOpt, stateName)
            updateElOnState(stateName, elUnwrapped, otherStateOpt, otherStyleOpt, attachedTxInfoTmp)
        }
    }

    updateZ(elUnwrapped, elOption, seriesModel)

    // upstream: if (elOption.type === 'group') mergeChildren(api, el, dataIndex, elOption, seriesModel);
    if (elOption["type"] as? String) == "group", let g = elUnwrapped as? Group {
        mergeChildren(api, g, dataIndex, elOption, seriesModel)
    }

    // upstream: if (toBeReplacedIdx >= 0) group.replaceAt(el, toBeReplacedIdx); else group.add(el);
    if toBeReplacedIdx >= 0 {
        // upstream: group.replaceAt(el, toBeReplacedIdx);  — `Group.replaceAt` IS ported → wired.
        _ = group.replaceAt(elUnwrapped, toBeReplacedIdx)
    }
    else {
        _ = group.add(elUnwrapped)
    }

    return elUnwrapped
}

// upstream: function doesElNeedRecreate(el, elOption, seriesModel): boolean
private func doesElNeedRecreate(_ el: Element, _ elOption: [String: Any], _ seriesModel: CustomSeriesModel) -> Bool {
    let elInner = customInnerStore(el)
    let elOptionType = elOption["type"] as? String
    let elOptionShape = elOption["shape"] as? [String: Any]
    let elOptionStyle = elOption["style"] as? [String: Any]
    return (
        // Always create new if universal transition is enabled.
        seriesModel.isUniversalTransitionEnabled()
        // If `elOptionType` is null, follow the merge principle.
        || (elOptionType != nil && elOptionType != elInner.customGraphicType)
        || (elOptionType == "path"
            && hasOwnPathData(elOptionShape)
            && !samePathData(getPathData(elOptionShape), elInner.customPathData))
        || (elOptionType == "image"
            && elOptionStyle?["image"] != nil
            && !sameImage(elOptionStyle?["image"], elInner.customImagePath))
    )
}

// upstream: function doCreateOrUpdateClipPath(el, dataIndex, elOption, seriesModel, isInit): void
//   Reuses `createEl` / `updateElNormal` / `doesElNeedRecreate`; `updateElNormal` supplies the same
//   enter/update transition and `during` support used by ordinary custom elements. Also uses
//   `Element.getClipPath`/`setClipPath`/`removeClipPath` (already used by bar/candlestick/geo/line clip).
private func doCreateOrUpdateClipPath(
    _ el: Element,
    _ dataIndex: Int,
    _ elOption: [String: Any],
    _ seriesModel: CustomSeriesModel,
    _ isInit: Bool
) {
    // Based on the "merge" principle: no clipPath → do nothing; `clipPath: false` → remove any existing.
    let clipPathOptRaw = elOption["clipPath"]
    if let isFalse = clipPathOptRaw as? Bool, isFalse == false {
        if el.getClipPath() != nil { el.removeClipPath() }
        return
    }
    guard let clipPathOpt = clipPathOptRaw as? [String: Any] else { return }

    var clipPath = el.getClipPath()
    if let cp = clipPath, doesElNeedRecreate(cp, clipPathOpt, seriesModel) {
        clipPath = nil
    }
    if clipPath == nil {
        let created = createEl(clipPathOpt)
        guard let createdPath = created as? Path else {
            log.error("Only any type of `path` can be used in `clipPath`, rather than \(created.type).")
            return
        }
        clipPath = createdPath
        el.setClipPath(createdPath)
    }
    updateElNormal(nil, clipPath!, dataIndex, clipPathOpt, nil, seriesModel, isInit)
}

// Bridge a raw `textConfig` option bag (`elOption.textConfig`) into the typed `ElementTextConfig`
//   struct — the normal-state slice of upstream's `processTxInfo` (`txCfg = stateOpt.textConfig`).
//   Mirrors `GraphicView.swift`'s `bridgeElementTextConfig` (kept file-local: no shared export exists).
private func bridgeCustomElementTextConfig(_ bag: [String: Any]?) -> ElementTextConfig? {
    guard let bag = bag else { return nil }
    var cfg = ElementTextConfig()
    cfg.position = bag["position"]
    cfg.rotation = customToDouble(bag["rotation"])
    cfg.offset = bag["offset"] as? [Double]
    cfg.origin = bag["origin"]
    cfg.distance = customToDouble(bag["distance"])
    cfg.local = bag["local"] as? Bool
    cfg.insideFill = bag["insideFill"] as? String
    cfg.insideStroke = bag["insideStroke"] as? String
    cfg.outsideFill = bag["outsideFill"] as? String
    cfg.outsideStroke = bag["outsideStroke"] as? String
    cfg.inside = bag["inside"] as? Bool
    return cfg
}

// upstream: function doCreateOrUpdateAttachedTx(el, dataIndex, elOption, seriesModel, isInit, attachedTxInfo)
//   The normal-state textContent/textConfig path is wired, including rich text. Legacy ec4 detection
//   and per-state text config remain deferred.
private func doCreateOrUpdateAttachedTx(
    _ el: Element,
    _ dataIndex: Int,
    _ elOption: [String: Any],
    _ seriesModel: CustomSeriesModel,
    _ isInit: Bool,
    _ attachedTxInfo: AttachedTxInfo
) {
    // Group does not support textContent temporarily until necessary.
    if el.isGroup || el.type == "compoundPath" {
        return
    }

    // Upstream calls normal before emphasis for legacy-style detection. The explicit textContent /
    // textConfig path is kept verbatim here; EC4 style conversion remains in customNormalizeLegacyText.
    processTxInfo(elOption, nil, attachedTxInfo)
    processTxInfo(elOption, EMPHASIS, attachedTxInfo)

    var txConOptNormal = attachedTxInfo.normal.conOpt
    let txConOptEmphasis = attachedTxInfo.emphasis.conOpt
    let txConOptBlur = attachedTxInfo.blur.conOpt
    let txConOptSelect = attachedTxInfo.select.conOpt

    if txConOptNormal != nil || txConOptEmphasis != nil || txConOptBlur != nil || txConOptSelect != nil {
        if txConOptNormal as? Bool == false {
            if el.getTextContent() != nil {
                el.removeTextContent()
            }
        }
        else {
            var conOpt = (txConOptNormal as? [String: Any]) ?? ["type": "text"]
            if conOpt["type"] == nil { conOpt["type"] = "text" }
            txConOptNormal = conOpt
            attachedTxInfo.normal.conOpt = conOpt

            var textContent = el.getTextContent()
            if textContent == nil {
                textContent = createEl(conOpt) as? ZRText
                if let tc = textContent { el.setTextContent(tc) }
            }
            else {
                textContent?.clearStates()
            }
            if let tc = textContent {
                updateElNormal(nil, tc, dataIndex, conOpt, nil, seriesModel, isInit)
                for stateName in STATES where stateName != NORMAL {
                    let stateOption = attachedTxInfo[stateName].conOpt
                    updateElOnState(
                        stateName,
                        tc,
                        stateOption,
                        retrieveStyleOptionOnState(conOpt, stateOption, stateName),
                        nil
                    )
                }
                tc.markRedraw()
            }
        }
    }
}

// Explicit half of upstream processTxInfo. `customNormalizeLegacyText` runs before this function and
// performs this port's EC4-compatible style conversion, so the state extraction below can remain the
// same normal/emphasis lookup used by Web CustomView.
private func processTxInfo(
    _ elOption: [String: Any],
    _ state: String?,
    _ attachedTxInfo: AttachedTxInfo
) {
    let stateOption: [String: Any]?
    if let state {
        stateOption = retrieveStateOption(elOption, state) as? [String: Any]
    }
    else {
        stateOption = elOption
    }
    let normalTextContent = elOption["textContent"]
    let textContentOption: Any?
    if state == nil {
        textContentOption = normalTextContent
    }
    else if let normal = normalTextContent as? [String: Any], let state {
        textContentOption = retrieveStateOption(normal, state)
    }
    else {
        textContentOption = nil
    }

    let info = state.map { attachedTxInfo[$0] } ?? attachedTxInfo.normal
    info.cfg = bridgeCustomElementTextConfig(stateOption?["textConfig"] as? [String: Any])
    info.conOpt = textContentOption
}

// Bridge a renderItem `textConfig` bag (`[String: Any]`) → `ElementTextConfig`. Upstream passes the raw
//   object to `el.setTextConfig`; here it is mapped field-by-field onto the struct ZRenderKit consumes.
private func customBridgeTextConfig(_ dict: [String: Any]) -> ElementTextConfig {
    var cfg = ElementTextConfig()
    // position: BuiltinTextPosition string | (number|string)[] — passed through as `Any?`.
    if let pos = dict["position"], !(pos is NSNull) { cfg.position = pos }
    if let rotation = customNumOpt(dict["rotation"]) { cfg.rotation = rotation }
    if let distance = customNumOpt(dict["distance"]) { cfg.distance = distance }
    if let local = dict["local"] as? Bool { cfg.local = local }
    if let inside = dict["inside"] as? Bool { cfg.inside = inside }
    if let origin = dict["origin"], !(origin is NSNull) { cfg.origin = origin }
    if let offset = dict["offset"] as? [Any] {
        cfg.offset = offset.compactMap { customNumOpt($0) }
    }
    if let insideFill = dict["insideFill"] as? String { cfg.insideFill = insideFill }
    if let insideStroke = dict["insideStroke"] as? String { cfg.insideStroke = insideStroke }
    if let outsideFill = dict["outsideFill"] as? String { cfg.outsideFill = outsideFill }
    if let outsideStroke = dict["outsideStroke"] as? String { cfg.outsideStroke = outsideStroke }
    return cfg
}

// A dynamic numeric option (Int / Double / NSNumber) → Double?, nil for missing / NSNull / non-numeric.
private func customNumOpt(_ v: Any?) -> Double? {
    switch v {
    case let d as Double: return d
    case let i as Int: return Double(i)
    case let n as NSNumber: return n.doubleValue
    default: return nil
    }
}

// upstream: function retrieveStateOption(elOption, state): CustomElementOptionOnState
private func retrieveStateOption(_ elOption: [String: Any]?, _ state: String) -> Any? {
    // return !state ? elOption : elOption ? elOption[state] : null;
    guard let elOption = elOption else { return nil }
    return elOption[state]
}

// upstream: function retrieveStyleOptionOnState(stateOptionNormal, stateOption, state)
private func retrieveStyleOptionOnState(
    _ stateOptionNormal: [String: Any]?, _ stateOption: Any?, _ state: String
) -> Any? {
    let stateDict = stateOption as? [String: Any]
    var style = stateDict?["style"]
    if style == nil, state == EMPHASIS, let normal = stateOptionNormal {
        style = normal["styleEmphasis"]
    }
    return style
}

// ECharts 5 compatibility for ECharts 4 custom-series styles. `api.style()` historically returned
// `text`/`textFill`/`textPosition` on the host style; zrender 5 renders that text as an attached element.
// Keep the conversion deliberately scoped to normal-state text generated by api.style(). Explicit
// renderItem `textContent`/`textConfig` always wins.
private func customNormalizeLegacyText(_ input: [String: Any]) -> [String: Any] {
    guard input["textContent"] == nil, input["textConfig"] == nil,
          let style = input["style"] as? [String: Any],
          (style["legacy"] as? Bool) == true,
          let text = style["text"] as? String
    else { return input }

    var output = input
    var textStyle: [String: Any] = ["text": text]
    if let value = style["textFill"] { textStyle["fill"] = value }
    if let value = style["textStroke"] { textStyle["stroke"] = value }
    if let value = style["textStrokeWidth"] { textStyle["lineWidth"] = value }
    if let value = style["font"] { textStyle["font"] = value }
    if let value = style["fontSize"] { textStyle["fontSize"] = value }
    if let value = style["fontFamily"] { textStyle["fontFamily"] = value }
    if let value = style["fontStyle"] { textStyle["fontStyle"] = value }
    if let value = style["fontWeight"] { textStyle["fontWeight"] = value }
    if let value = style["textAlign"] { textStyle["align"] = value }
    if let value = style["textVerticalAlign"] { textStyle["verticalAlign"] = value }

    var textConfig: [String: Any] = ["position": style["textPosition"] ?? "inside"]
    if let value = style["textOffset"] { textConfig["offset"] = value }
    if let value = style["textRotation"] { textConfig["rotation"] = value }
    if let value = style["textDistance"] { textConfig["distance"] = value }

    output["textContent"] = ["type": "text", "silent": true, "style": textStyle] as [String: Any]
    output["textConfig"] = textConfig
    return output
}


// upstream: function mergeChildren(api, el, dataIndex, elOption, seriesModel): void
//   STATIC subset — build/replace children by index (or by name), rebuilding rather than diffing.
private func mergeChildren(
    _ api: ExtensionAPI?,
    _ el: Group,
    _ dataIndex: Int,
    _ elOption: [String: Any],
    _ seriesModel: CustomSeriesModel
) {
    let newChildren = elOption["children"] as? [Any]
    let newLen = newChildren?.count ?? 0
    let mergeChildrenOpt = elOption["$mergeChildren"]
    // `diffChildrenByName` has been deprecated.
    let byName = (mergeChildrenOpt as? String) == "byName" || (elOption["diffChildrenByName"] as? Bool) == true
    let notMerge = (mergeChildrenOpt as? Bool) == false

    // For better performance on roam update, only enter if necessary.
    if newLen == 0 && !byName && !notMerge {
        return
    }

    if byName {
        // upstream: diffGroupChildren({...}) — the DataDiffer by-name child diff.
        // PORT-NOTE (deferred): the by-name child DIFF (`diffGroupChildren` via DataDiffer) is deferred
        //   (needs data/DataDiffer + the leave transition, both in other files); fall through to the
        //   by-index merge below as a best-effort.
    }

    // upstream: notMerge && el.removeAll();
    if notMerge {
        el.removeAll()
    }

    // Mapping children of a group simply by index, reusing the existing child at each index (upstream
    //   passes `oldChild = el.childAt(index)` to `doCreateOrUpdateEl`, so per-child identity/animation
    //   persist across renders instead of being rebuilt from scratch).
    var index = 0
    while index < newLen {
        let newChildAny = newChildren?[index]
        var newChild = normalizeElOption(newChildAny)
        let oldChild = el.childAt(index)
        if newChild != nil {
            // The old child at this index is set to be ignored when its new option is null (see the
            //   `else` branch). So set `ignore` back to false when it is not explicitly specified.
            if newChild!["ignore"] == nil {
                newChild!["ignore"] = false
            }
            _ = doCreateOrUpdateEl(api, oldChild, dataIndex, newChild!, seriesModel, el)
        }
        else {
            // upstream DEV assert: oldChild must exist. A null new child means "remove" the old child,
            //   but we cannot really remove it (element order may not be stable when it is added back),
            //   so mark it ignored instead.
            oldChild?.ignore = true
        }
        index += 1
    }
    // upstream: for (let i = el.childCount() - 1; i >= index; i--) removeChildFromGroup(el, childAt(i), ...)
    var i = el.childCount() - 1
    while i >= index {
        if let child = el.childAt(i) {
            removeChildFromGroup(el, child, seriesModel)
        }
        i -= 1
    }
}

// upstream: function removeChildFromGroup(group, child, seriesModel) { child && applyLeaveTransition(...) }
//   Do not support leave elements that are not mentioned in the latest `renderItem` return. Otherwise
//   users may not have a clear and simple concept that how to control all of the elements.
private func removeChildFromGroup(
    _ group: Group, _ child: Element, _ seriesModel: CustomSeriesModel
) {
    applyLeaveTransition(child, customInnerStore(group).option ?? [:], seriesModel)
}

// upstream: function diffGroupChildren / getKey / processAddUpdate / processRemove
//   The by-NAME child DIFF machinery (DataDiffer + leave transition) is DEFERRED (see mergeChildren);
//   `removeChildFromGroup` (the by-index trailing-child removal) is ported above.
//   Retained here only as provenance markers.
//   - diffGroupChildren(context) -> new DataDiffer(...).add/update/remove.execute()   (DEFERRED)
//   - getKey(item, idx) -> item.name ?? GROUP_DIFF_PREFIX + idx
private func getKey(_ item: Element?, _ idx: Int) -> String {
    let name = item?.name
    if let name = name, !name.isEmpty { return name }
    return GROUP_DIFF_PREFIX + String(idx)
}

// upstream: function getPathData(shape): string { return shape && (shape.pathData || shape.d); }
private func getPathData(_ shape: [String: Any]?) -> String? {
    guard let shape = shape else { return nil }
    return (shape["pathData"] as? String) ?? (shape["d"] as? String)
}

// upstream: function hasOwnPathData(shape): boolean { return shape && (hasOwn(shape,'pathData') || hasOwn(shape,'d')); }
private func hasOwnPathData(_ shape: [String: Any]?) -> Bool {
    guard let shape = shape else { return false }
    return shape["pathData"] != nil || shape["d"] != nil
}


// ---------------------------------------------------------------------------------------------
// Per-file JS-semantics + bridging shims (mirror GraphicComponentView's approach).
// ---------------------------------------------------------------------------------------------

// The renderItem return spec → a `[String: Any]` element option, or nil for null/undefined/false.
private func normalizeElOption(_ any: Any?) -> [String: Any]? {
    if any == nil { return nil }
    if let b = any as? Bool, b == false { return nil }
    if any is NSNull { return nil }
    return any as? [String: Any]
}

// Int|Double coercion for numeric option keys (CONVENTIONS INT-vs-DOUBLE trap: never `as? Double`
//   on a possibly Int-boxed default).
private func customToDouble(_ v: Any?) -> Double? {
    if let d = v as? Double { return d }
    if let i = v as? Int { return Double(i) }
    if let n = v as? NSNumber { return n.doubleValue }
    return nil
}

// Deep Int→Double coercion for an animation payload (`enterFrom` / `leaveTo` / `keyframeAnimation`).
//   See the FRAMEWORK GAP note in `updateElNormal`: the animator classifies a keyframe value with
//   `util.isNumber` (`value is Double`) and `Element._setKnownKV` only accepts a `Double`, so an
//   Int-boxed option literal (`["opacity": 0]`) is silently dropped. Bools/Strings (and any other
//   value kind) pass through untouched; the walk is structural (dicts + arrays).
private func customCoerceNumericLeaves(_ value: Any?) -> Any? {
    guard let value = value else { return nil }
    if value is Bool || value is String || value is Double { return value }
    if let i = value as? Int { return Double(i) }
    if let f = value as? Float { return Double(f) }
    if let dict = value as? [String: Any] {
        var out = dict
        for (k, v) in dict { out[k] = customCoerceNumericLeaves(v) }
        return out
    }
    if let arr = value as? [Any] {
        return arr.map { customCoerceNumericLeaves($0) as Any }
    }
    if let n = value as? NSNumber { return n.doubleValue }
    return value
}

// A `[x, y]` legacy transform-alias array (`position`/`scale`/`origin`) → the two Doubles.
private func customVec2(_ v: Any?) -> (Double, Double)? {
    if let arr = v as? [Double], arr.count >= 2 { return (arr[0], arr[1]) }
    if let arr = v as? [Any], arr.count >= 2 {
        return (customToDouble(arr[0]) ?? 0, customToDouble(arr[1]) ?? 0)
    }
    return nil
}

// `[[x,y], ...]` (Double|Int) → `[VectorArray]` for polygon/polyline points.
private func bridgePoints(_ v: Any?) -> [VectorArray]? {
    guard let arr = v as? [Any] else { return nil }
    var out: [VectorArray] = []
    for p in arr {
        if let pair = p as? [Any], pair.count >= 2 {
            out.append(VectorArray(customToDouble(pair[0]) ?? 0, customToDouble(pair[1]) ?? 0))
        }
        else if let pair = p as? [Double], pair.count >= 2 {
            out.append(VectorArray(pair[0], pair[1]))
        }
    }
    return out
}

// rect `r` — number | number[] → RectRadius.
private func bridgeRectRadius(_ v: Any?) -> RectRadius? {
    if let n = customToDouble(v) { return .number(n) }
    if let arr = v as? [Any] {
        return .array(arr.map { customToDouble($0) ?? 0 })
    }
    if let arr = v as? [Double] { return .array(arr) }
    return nil
}

// color coercion — string | EChartsKit ZRColor | gradient dict | already-built ZRenderKit paint.
private func toZRColor(_ v: Any?) -> ZRenderKit.ZRColor? {
    if let z = v as? ZRenderKit.ZRColor { return z }   // renderItem may hand back a ZRenderKit paint directly
    return zrPaintFromStyleValue(v)                    // String | EChartsKit.ZRColor | {type:'linear'|'radial',…}
}

// `[String: Any]` style bag → PathStyleProps (fill/stroke/lineWidth/opacity/… subset).
private func bridgePathStyle(_ s: [String: Any]) -> PathStyleProps {
    var out = PathStyleProps()
    out.fill = toZRColor(s["fill"])
    out.stroke = toZRColor(s["stroke"])
    out.lineWidth = customToDouble(s["lineWidth"])
    out.opacity = customToDouble(s["opacity"])
    out.fillOpacity = customToDouble(s["fillOpacity"])
    out.strokeOpacity = customToDouble(s["strokeOpacity"])
    out.lineCap = s["lineCap"] as? String
    out.lineJoin = s["lineJoin"] as? String
    out.miterLimit = customToDouble(s["miterLimit"])
    out.lineDashOffset = customToDouble(s["lineDashOffset"])
    out.shadowBlur = customToDouble(s["shadowBlur"])
    out.shadowOffsetX = customToDouble(s["shadowOffsetX"])
    out.shadowOffsetY = customToDouble(s["shadowOffsetY"])
    out.shadowColor = s["shadowColor"] as? String
    out.strokeNoScale = s["strokeNoScale"] as? Bool
    out.strokeFirst = s["strokeFirst"] as? Bool
    if let dash = s["lineDash"] as? [Double] { out.lineDash = .values(dash) }
    // fill/stroke gradients now bridge via `toZRColor` → `zrPaintFromStyleValue`.
    // `decal` carries the tiling Pattern resolved by `createOrUpdatePatternFromDecal` in `updateElNormal`
    //   (a raw decal OPTION dict left here is not a Pattern and is correctly ignored).
    out.decal = s["decal"] as? Pattern
    // PORT-NOTE (deferred): the lineDash-string style-bridge case is still deferred.
    return out
}

// `[String: Any]` style bag → TextStyleProps. Includes the ec4 textFill/textStroke compat and
// the rich-token/background/border fields used by custom-series attached labels.
private func bridgeTextStyle(_ s: [String: Any]) -> TextStyleProps {
    var out = TextStyleProps()
    out.text = s["text"] as? String
    // Compatible with ec4: textFill/textStroke → fill/stroke. Upstream (CustomView.ts:508-515) lets
    //   textFill/textStroke WIN when present, so mirror that precedence here (this is a fallback — the
    //   normalization already happened on the style bag in `updateElNormal`).
    out.fill = (s["textFill"] as? String) ?? (s["fill"] as? String)
    out.stroke = (s["textStroke"] as? String) ?? (s["stroke"] as? String)
    out.opacity = customToDouble(s["opacity"])
    out.lineWidth = customToDouble(s["lineWidth"])
    out.font = s["font"] as? String
    out.fontFamily = s["fontFamily"] as? String
    out.textFont = s["textFont"] as? String   // a real TextStyleProps field api.font(...) writes through
    if let fs = customToDouble(s["fontSize"]) { out.fontSize = .number(fs) }
    else if let fs = s["fontSize"] as? String { out.fontSize = .string(fs) }
    if let align = s["align"] as? String { out.align = TextAlign(rawValue: align) }
    if let va = s["verticalAlign"] as? String { out.verticalAlign = TextVerticalAlign(rawValue: va) }
    out.lineHeight = customToDouble(s["lineHeight"])
    out.width = customToDouble(s["width"])
    out.height = customToDouble(s["height"])
    out.x = customToDouble(s["x"])
    out.y = customToDouble(s["y"])
    // `overflow`/`ellipsis`/`truncateMinChar` — `parseText.parsePlainText` (ZRenderKit/Graphic/Text.swift)
    //   already reads all three off `TextStyleProps`; only the bridge from the raw style bag was missing
    //   (caught porting official-flame-graph: a `width` + `overflow:'truncate'` textContent style with no
    //   bridge left every frame-name label full-width and overlapping its neighbors).
    out.overflow = s["overflow"] as? String
    out.ellipsis = s["ellipsis"] as? String
    out.truncateMinChar = customToDouble(s["truncateMinChar"])
    if let bg = s["backgroundColor"] as? String { out.backgroundColor = .string(bg) }
    out.padding = bridgeTextNumberArray(s["padding"])
    out.margin = bridgeTextNumberArray(s["margin"])
    out.borderColor = s["borderColor"] as? String
    out.borderWidth = customToDouble(s["borderWidth"])
    out.borderRadius = bridgeTextNumberArray(s["borderRadius"])
    out.fontStyle = (s["fontStyle"] as? String).flatMap(FontStyle.init(rawValue:))
    out.fontWeight = bridgeTextFontWeight(s["fontWeight"])
    if let rich = s["rich"] as? [String: Any] {
        var tokens: [String: TextStylePropsPart] = [:]
        for (name, rawToken) in rich {
            guard let tokenBag = rawToken as? [String: Any] else { continue }
            tokens[name] = bridgeTextStylePart(tokenBag)
        }
        out.rich = tokens
    }
    return out
}

private func bridgeTextNumberArray(_ value: Any?) -> NumberOrNumberArray? {
    if let number = customToDouble(value) { return .number(number) }
    if let values = value as? [Any] { return .array(values.compactMap(customToDouble)) }
    if let values = value as? [Double] { return .array(values) }
    return nil
}

private func bridgeTextFontWeight(_ value: Any?) -> FontWeight? {
    if let number = customToDouble(value) { return .number(number) }
    switch value as? String {
    case "normal": return .normal
    case "bold": return .bold
    case "bolder": return .bolder
    case "lighter": return .lighter
    default: return nil
    }
}

private func bridgeTextStylePart(_ s: [String: Any]) -> TextStylePropsPart {
    var out = TextStylePropsPart()
    out.fill = (s["fill"] as? String) ?? (s["color"] as? String)
    out.stroke = (s["stroke"] as? String) ?? (s["textBorderColor"] as? String)
    out.lineWidth = customToDouble(s["lineWidth"]) ?? customToDouble(s["textBorderWidth"])
    out.opacity = customToDouble(s["opacity"])
    out.font = s["font"] as? String
    out.fontFamily = s["fontFamily"] as? String
    if let fs = customToDouble(s["fontSize"]) { out.fontSize = .number(fs) }
    else if let fs = s["fontSize"] as? String { out.fontSize = .string(fs) }
    out.fontStyle = (s["fontStyle"] as? String).flatMap(FontStyle.init(rawValue:))
    out.fontWeight = bridgeTextFontWeight(s["fontWeight"])
    if let align = s["align"] as? String { out.align = TextAlign(rawValue: align) }
    if let verticalAlign = s["verticalAlign"] as? String {
        out.verticalAlign = TextVerticalAlign(rawValue: verticalAlign)
    }
    out.lineHeight = customToDouble(s["lineHeight"])
    if let width = customToDouble(s["width"]) { out.width = .number(width) }
    else if let width = s["width"] as? String { out.width = .string(width) }
    out.height = customToDouble(s["height"])
    if let bg = s["backgroundColor"] as? String { out.backgroundColor = .string(bg) }
    out.padding = bridgeTextNumberArray(s["padding"])
    out.margin = bridgeTextNumberArray(s["margin"])
    out.borderColor = s["borderColor"] as? String
    out.borderWidth = customToDouble(s["borderWidth"])
    out.borderRadius = bridgeTextNumberArray(s["borderRadius"])
    out.shadowColor = s["shadowColor"] as? String
    out.shadowBlur = customToDouble(s["shadowBlur"])
    out.shadowOffsetX = customToDouble(s["shadowOffsetX"])
    out.shadowOffsetY = customToDouble(s["shadowOffsetY"])
    return out
}

// `[String: Any]` style bag → ImageStyleProps.
private func bridgeImageStyle(_ s: [String: Any]) -> ImageStyleProps {
    var out = ImageStyleProps()
    if let url = s["image"] as? String { out.image = .url(url) }
    // PORT-NOTE (deferred): non-URL ImageLike sources (HTMLImageElement/HTMLCanvasElement) have no native
    //   analog in the string-URL bridge; deferred.
    out.x = customToDouble(s["x"])
    out.y = customToDouble(s["y"])
    out.width = customToDouble(s["width"])
    out.height = customToDouble(s["height"])
    out.opacity = customToDouble(s["opacity"])
    return out
}

// Path-data / image identity comparisons for `doesElNeedRecreate` (upstream `!==`).
private func samePathData(_ a: String?, _ b: Any?) -> Bool {
    return a == (b as? String)
}
private func sameImage(_ a: Any?, _ b: Any?) -> Bool {
    return (a as? String) == (b as? String)
}

// export default CustomChartView;  -> `open class CustomChartView` above.
