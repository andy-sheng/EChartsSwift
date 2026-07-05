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
//   - `render` (the per-datum renderItem dispatch), rebuilding the group from scratch each render
//     (the enter/update/leave DIFF via `data.diff(oldData)` is DEFERRED — see the render note).
//   - `createEl` + the per-type graphic-element builders (group/rect/circle/ring/sector/arc/
//     polygon/polyline/line/bezierCurve/text/image/compoundPath; `path` SVG-data building deferred).
//   - `updateElNormal` STATIC parts — apply shape + style + transform (x/y/rotation/scale) + z2.
//   - `makeRenderItem` — the render-item `api` (value/coord/size/style/visual/font/getWidth/…) and
//     `params`, plus the coord-system dispatch via the ported `prepareCustoms`.
//   - `mergeChildren` group building.
//
// DEFERRED (each marked // PORT-TODO at its site):
//   - the transition/animation/morph machinery: `applyUpdateTransition` / `applyLeaveTransition` /
//     `applyKeyframeAnimation` / `stopPreviousKeyframeAnimationAndRestore` — replaced by a direct
//     static apply of the final shape/style/transform (mirrors GraphicComponentView's
//     `applyUpdateTransitionStatic`).
//   - the enter/update/leave group DIFF (`data.diff`) — the group is rebuilt from scratch each render
//     (same deviation as ScatterView/BarView), and `diffGroupChildren` / DataDiffer child-diff.
//   - emphasis/blur/select STATES: `updateElOnState` / `setDefaultStateProxy` / `toggleHoverEmphasis`
//     / `retrieveStateOption` state application (util/states not ported).
//   - the clipPath handling (`doCreateOrUpdateClipPath`, group `createClipPath`) — animation + Polar.
//   - the legacy ec4 style compat (`convertFromEC4CompatibleStyle` / `isEC4CompatibleStyle` /
//     `convertToEC4StyleForCustomSerise`) and the deprecated `api.style` / `api.styleEmphasis`.
//   - `attachTextContent` / rich-label nuance — only basic `textContent` (a plain text child) is wired.
//   - decal pattern (`createOrUpdatePatternFromDecal`), universal transition, incremental hover-layer.
//
// upstream imports (Swift mapping / deferral):
//   import { hasOwn, assert, isString, retrieve2, retrieve3, defaults, each, indexOf, map }
//       from 'zrender/src/core/util';                                -> `util.*` (ZRenderKit).
//   import * as graphicUtil from '../../util/graphic';               -> concrete ZRenderKit shapes;
//       `graphicUtil.makePath` / `getShapeClass` NOT ported (see `createEl`).
//   import { setDefaultStateProxy, toggleHoverEmphasis } from '../../util/states';  -> DEFERRED (states).
//   import * as labelStyleHelper from '../../label/labelStyle';      -> DEFERRED (label/labelStyle not ported).
//   import { getDefaultLabel } from '../helper/labelHelper';         -> DEFERRED (labelHelper not ported).
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
//   import { createOrUpdatePatternFromDecal } from '../../util/decal';  -> DEFERRED (decal not ported).
//   import CustomSeriesModel, { ...many types... } from './CustomSeries';
//       -> sibling `CustomSeries.swift` (CustomSeriesModel + the render-item api/param types +
//          `customInnerStore`). Referenced; see the integration contract note near `makeRenderItem`.
//   import { PatternObject } from 'zrender/src/graphic/Pattern';     -> DEFERRED (decal).
//   import { applyLeaveTransition, applyUpdateTransition, ElementRootTransitionProp }
//       from '../../animation/customGraphicTransition';              -> DEFERRED (transitions).
//   import { applyKeyframeAnimation, stopPreviousKeyframeAnimationAndRestore }
//       from '../../animation/customGraphicKeyframeAnimation';       -> DEFERRED (keyframes).
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
        // PORT-TODO: `Displayable.style` is a typed struct; a generic `setStyle(source.style)` across
        //   Path/Text/Image variants is not uniformly typed here. Copy the scalar display props;
        //   the style copy is deferred (recreate path is off the static critical path).
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
        // DEVIATION (STATIC): upstream then runs a `data.diff(oldData).add/remove/update(...).execute()`
        //   enter/update/leave DIFF, reusing per-datum graphic els across renders. That DIFF (and the
        //   leave transition) is DEFERRED; instead the group is rebuilt from scratch every render — the
        //   same static strategy as ScatterView/BarView. Functionally equivalent for a single static
        //   frame; loses cross-frame element reuse + transitions.
        _ = oldData
        group.removeAll()
        for newIdx in 0..<data.count() {
            _ = createOrUpdateItem(
                api, nil, newIdx, renderItem(newIdx, payload), customSeries, group, data
            )
        }

        // upstream:
        //   const clipPath = customSeries.get('clip', true)
        //       ? createClipPath(customSeries.coordinateSystem, false, customSeries) : null;
        //   if (clipPath) { group.setClipPath(clipPath); } else { group.removeClipPath(); }
        // PORT-TODO: the group-level clip (createClipPath — Polar clip + cartesian animation) is
        //   DEFERRED. Static shape rendering does not require it; wire once createClipPath/Polar land
        //   for the custom-series model surface.

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
        // PORT-TODO: `el.incremental` / hover-layer emphasis state DEFERRED (states + incremental layer
        //   not ported). The elements are still built + collected below.

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
        // PORT-TODO: `graphicUtil.traverseElements` not ported; traverse the progressive els or group.
        //   `traverseElements` invokes `cb` on each root element itself and then walks its descendants;
        //   `Element.traverse` is a no-op stub while `Group.traverse` walks children, so invoke `cb` on
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
        // PORT-TODO: `__hostTarget` (text-content host back-pointer) not modeled; walk `parent` only.
        var cur: Element? = targetEl.parent as? Element
        while let c = cur, c !== self.group {
            if c.name == elementName {
                return true
            }
            cur = c.parent as? Element
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
        // upstream: makePath(getPathData(shape), null, pathRect, shape.layout || 'center')
        // PORT-TODO: `graphicUtil.makePath` (SVG path-data parsing) is NOT ported (see util/symbol.swift
        //   note). A `path` custom element yields an empty `Path` until makePath lands; pathData/pathRect
        //   are ignored. customInnerStore(el).customPathData tracked for the (deferred) recreate check.
        let p = Path()
        el = p
        customInnerStore(el).customPathData = getPathData(elOption["shape"] as? [String: Any])
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
            // PORT-TODO: makePath deferred; sub-path `type` is built via the same shape switch as
            //   top-level elements (getShapeClass equivalent below).
            let subType = pathOpt["type"] as? String
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
        // PORT-TODO: `graphicUtil.getShapeClass` (extendShape string->class registry) not ported; the
        //   built-in shapes are switched explicitly in `makeShapeElement`.
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
    // PORT-TODO: `ECElement` is a not-yet-conformed protocol on `Element` (util/types.swift); the
    //   emphasis/select z2 lift is a states concern (DEFERRED) — skipped.

    return el
}

// getShapeClass(graphicType) substitute — the built-in shape registry. Returns an empty typed Path
//   subclass for the given type name (shape values applied later in `applyShape`).
private func makeShapeElement(_ graphicType: String?) -> Path? {
    switch graphicType {
    case "rect": return Rect()
    case "circle": return Circle()
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
    // upstream: stopPreviousKeyframeAnimationAndRestore(el);  — DEFERRED (keyframe animation).

    // upstream: const txCfgOpt = attachedTxInfo && attachedTxInfo.normal.cfg; if (txCfgOpt) el.setTextConfig(txCfgOpt);
    let txCfgOpt = attachedTxInfo?.normal.cfg
    if let txCfgOpt = txCfgOpt {
        el.setTextConfig(txCfgOpt)
    }

    // Default transition ['x', 'y'] — upstream mutates elOption.transition; transition is DEFERRED so
    //   this is a no-op here (kept as a comment for provenance).
    //   if (elOption && elOption.transition == null) { elOption.transition = DEFAULT_TRANSITION; }
    _ = DEFAULT_TRANSITION

    // Do some normalization on style.
    let styleOpt = elOption["style"] as? [String: Any]

    if let styleOpt = styleOpt {
        if el.type == "text" {
            // Compatible with ec4: if `textFill`/`textStroke` exist use them as fill/stroke.
            // PORT-TODO: handled inside the text-style bridge (`bridgeTextStyle`).
            _ = styleOpt
        }
        // upstream: decal pattern resolution (createOrUpdatePatternFromDecal) — DEFERRED (decal).
    }

    // upstream: applyUpdateTransition(el, elOption, seriesModel, { dataIndex, isInit, clearStyle: true });
    // PORT-TODO: DEFERRED. Static substitute — apply the final shape / style / transform directly.
    applyUpdateTransitionStatic(el, elOption)

    // upstream: applyKeyframeAnimation(el, elOption.keyframeAnimation, seriesModel);  — DEFERRED.
    _ = (api, dataIndex, isInit, seriesModel)
}

// STATIC substitute for `applyUpdateTransition` — apply the element's final shape/style/transform.
private func applyUpdateTransitionStatic(_ el: Element, _ elOption: [String: Any]) {
    // Shape (typed struct per element kind).
    if let shapeOpt = elOption["shape"] as? [String: Any], let path = el as? Path {
        applyShape(path, customInnerStore(el).customGraphicType, shapeOpt)
    }
    // Style (typed struct per Displayable kind).
    if let styleOpt = elOption["style"] as? [String: Any] {
        applyStyle(el, styleOpt)
    }
    // Transform props (x / y / rotation / scaleX / scaleY / originX / originY).
    for key in ["x", "y", "rotation", "scaleX", "scaleY", "originX", "originY"] {
        if let v = customToDouble(elOption[key]) {
            _ = el.attr(key, v)
        }
    }
    // Common display flags.
    if let ignore = elOption["ignore"] as? Bool {
        el.ignore = ignore
    }
    if let silent = elOption["silent"] as? Bool {
        el.silent = silent
    }
    if let invisible = elOption["invisible"] as? Bool, let disp = el as? Displayable {
        disp.invisible = invisible
    }
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
        path.useStyle(bridgePathStyle(s))
    }
}

// upstream: function updateElOnState(state, el, elStateOpt, styleOpt, attachedTxInfo): void
//   DEFERRED — emphasis/blur/select STATES (ensureState / setDefaultStateProxy) not ported.
private func updateElOnState(
    _ state: String,
    _ el: Element,
    _ elStateOpt: Any?,
    _ styleOpt: Any?,
    _ attachedTxInfo: AttachedTxInfo?
) {
    // PORT-TODO: states (util/states) not ported — the whole per-state style/textConfig application
    //   and `setDefaultStateProxy` is deferred. No-op.
    _ = (state, el, elStateOpt, styleOpt, attachedTxInfo)
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

    // upstream: for (STATES) updateZForEachState(...)  — per-state z2 is a states concern (DEFERRED).
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
        // PORT-TODO: `coordSys.prepareCustoms` (external coord systems like bmap) not modeled; the
        //   built-in dispatch is used.
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
        data: data,
        ecModel: ecModel,
        extApi: api,
        coordSys: coordSys,
        coordClosure: prepareApi?["coord"] as? ([Double]) -> [Double],
        sizeClosure: prepareApi?["size"] as? ([Double], [Double]?) -> [Double]
    )

    // upstream: const userParams: CustomSeriesRenderItemParams = { context: {}, seriesId, seriesName,
    //     seriesIndex, coordSys: prepareResult.coordSys, dataInsideLength: data.count(),
    //     encode: wrapEncodeDef(customSeries.getData()), itemPayload: customSeries.get('itemPayload') || {} }
    //   `CustomSeriesRenderItemParams` is a struct (value bag); build it fresh per datum below.
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

    // upstream: return function (dataIndexInside, payload): CustomElementOption { ... }
    return { (dataIndexInside: Int, payload: Payload?) -> Any? in
        userAPI.currDataIndexInside = dataIndexInside

        // upstream: renderItem && renderItem(defaults({ dataIndexInside, dataIndex, actionType }, userParams), userAPI)
        // PORT-TODO: `context` — upstream shares one `{}` across the render round so a user can stash
        //   cross-datum state; the value-type struct copies it per datum, so that sharing is lost (fresh
        //   `[:]` here). Wire a reference-typed context if a demo needs it.
        let userParams = CustomSeriesRenderItemParams(
            context: [:],
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
    let data: SeriesData
    let ecModel: GlobalModel
    let extApi: ExtensionAPI
    let coordSys: Any?
    let coordClosure: (([Double]) -> [Double])?
    let sizeClosure: (([Double], [Double]?) -> [Double])?
    // upstream: closure-captured `let currDataIndexInside: number;`
    var currDataIndexInside: Int = 0

    init(
        data: SeriesData, ecModel: GlobalModel, extApi: ExtensionAPI, coordSys: Any?,
        coordClosure: (([Double]) -> [Double])?, sizeClosure: (([Double], [Double]?) -> [Double])?
    ) {
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
            return cs.dataToPoint(toDoubleArray(data), opt)
        }
        return []
    }
    func size(_ dataSize: Any?, _ dataItem: Any?) -> Any? {
        guard let sizeClosure = sizeClosure else { return nil }
        let item: [Double]? = dataItem == nil ? nil : toDoubleArray(dataItem)
        return sizeClosure(toDoubleArray(dataSize), item)
    }
    // layout — protocol-extension default (nil). Not implemented (no coord sys exposes it yet).

    // ---- ExtensionAPI-forwarded ----

    func getWidth() -> Double { return extApi.getWidth() }
    func getHeight() -> Double { return extApi.getHeight() }
    // PORT-TODO: `api.getZr` / `api.getDevicePixelRatio` are on ExtensionAPI's dynamic
    //   `availableMethods` forwarding list but not exposed as Swift methods yet — stubbed.
    func getZr() -> Any? { return nil }
    func getDevicePixelRatio() -> Double { return 1.0 }

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
        // PORT-TODO: `data.getDimensionInfo` returns a non-Optional `SeriesDimensionDefine` in this port
        //   (a missing dim can not be signalled), so upstream's `if (!dimInfo) { getDimensionIndex
        //   fallback }` branch is unreachable; the ordinalMeta path below covers the common case.
        let dimInfo = data.getDimensionInfo(dim)
        let val = data.get(dimInfo.name, idx)
        // const ordinalMeta = dimInfo && dimInfo.ordinalMeta;
        // PORT-TODO: `ordinalMeta.categories[val]` — OrdinalMeta lookup deferred; return the raw val.
        return val
    }

    // upstream (deprecated): function style(userProps?, dataIndexInside?): ZRStyleProps
    //   DEFERRED — depends on label/labelStyle + styleCompat (createTextStyle / convertToEC4...),
    //   neither ported. Returns the raw item visual style bag as a best effort.
    func style(_ userProps: [String: Any]?, _ dataIndexInside: Double?) -> [String: Any] {
        // PORT-TODO: full api.style (itemStyle + label + ec4 compat) not ported.
        let idx = resolveIdx(dataIndexInside)
        var out = (data.getItemVisual(idx, "style") as? [String: Any]) ?? [:]
        if let userProps = userProps {
            for (k, v) in userProps { out[k] = v }
        }
        return out
    }

    // upstream (deprecated): function styleEmphasis(userProps?, dataIndexInside?): ZRStyleProps  — DEFERRED.
    func styleEmphasis(_ userProps: [String: Any]?, _ dataIndexInside: Double?) -> [String: Any] {
        // PORT-TODO: full api.styleEmphasis not ported.
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
    //   DEFERRED — label/labelStyle.getFont (the free helper) not ported.
    func font(_ opt: [String: Any]?) -> String {
        // PORT-TODO: labelStyleHelper.getFont(opt, ecModel) not ported.
        return ""
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
    }

    // upstream: el && toggleHoverEmphasis(el, elOption.focus, elOption.blurScope, elOption.emphasisDisabled);
    // PORT-TODO: `toggleHoverEmphasis` (util/states) DEFERRED — emphasis/blur wiring skipped.

    return el
}

// upstream: function doCreateOrUpdateEl(api, existsEl, dataIndex, elOption, seriesModel, group): Element
private func doCreateOrUpdateEl(
    _ api: ExtensionAPI?,
    _ existsElIn: Element?,
    _ dataIndex: Int,
    _ elOption: [String: Any],
    _ seriesModel: CustomSeriesModel,
    _ group: Group
) -> Element? {

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
        // upstream: el.clearStates();  — states DEFERRED, no-op.
    }
    let elUnwrapped = el!

    // upstream: morph / tooltipDisabled flags — DEFERRED (morph not ported; ECElement not conformed).

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
    // PORT-TODO: per-element clipPath (createEl for the clip + update) DEFERRED (clip animation + assert).

    updateElNormal(
        api, elUnwrapped, dataIndex, elOption, attachedTxInfoTmp, seriesModel, isInit
    )

    // `elOption.info` enables user to mount some info on elements and use them in event handlers.
    // upstream: hasOwn(elOption, 'info') && (customInnerStore(el).info = elOption.info);
    if elOption["info"] != nil {
        // customInnerStore(el).info : CustomExtraElementInfo? (== [String: Any]?)
        customInnerStore(elUnwrapped).info = elOption["info"] as? [String: Any]
    }

    // upstream: for (STATES) { if (!NORMAL) updateElOnState(...) }  — states DEFERRED.
    _ = updateElOnState  // keep referenced (faithful surface; no-op body).

    updateZ(elUnwrapped, elOption, seriesModel)

    // upstream: if (elOption.type === 'group') mergeChildren(api, el, dataIndex, elOption, seriesModel);
    if (elOption["type"] as? String) == "group", let g = elUnwrapped as? Group {
        mergeChildren(api, g, dataIndex, elOption, seriesModel)
    }

    // upstream: if (toBeReplacedIdx >= 0) group.replaceAt(el, toBeReplacedIdx); else group.add(el);
    if toBeReplacedIdx >= 0 {
        // PORT-TODO: `Group.replaceAt` not present on the ported Group; remove-old + add is used
        //   (loses the exact-index placement — acceptable in the static rebuild path).
        _ = group.add(elUnwrapped)
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

// upstream: function doCreateOrUpdateAttachedTx(el, dataIndex, elOption, seriesModel, isInit, attachedTxInfo)
//   BASIC subset — a `textContent` element spec becomes a plain text child. The legacy detection +
//   per-state text config + rich label are DEFERRED.
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

    // upstream: processTxInfo(normal) then processTxInfo(EMPHASIS); legacy ec4 conversion — DEFERRED.
    // PORT-TODO: legacy-style detection + emphasis text config DEFERRED. Only `elOption.textContent`
    //   (normal) is honored as a basic text child.
    var txConOptNormal = elOption["textContent"]

    // upstream: if (txConOptNormal != null || ...emphasis/blur/select...) { textContent handling }
    if txConOptNormal != nil {
        if txConOptNormal as? Bool == false {
            // upstream: txConOptNormal === false → remove textContent.
            if el.getTextContent() != nil {
                el.removeTextContent()
            }
        }
        else {
            // `textContent: {type:'text'}` — the type is easy to miss, tolerate it.
            var conOpt = (txConOptNormal as? [String: Any]) ?? ["type": "text"]
            if conOpt["type"] == nil { conOpt["type"] = "text" }
            txConOptNormal = conOpt

            var textContent = el.getTextContent()
            if textContent == nil {
                textContent = createEl(conOpt) as? ZRText
                if let tc = textContent { el.setTextContent(tc) }
            }
            else {
                // textContent.clearStates();  — states DEFERRED.
            }
            if let tc = textContent {
                updateElNormal(nil, tc, dataIndex, conOpt, nil, seriesModel, isInit)
                // per-state text config — DEFERRED.
                tc.markRedraw()
            }
        }
    }
    _ = attachedTxInfo
}

// upstream: function processTxInfo(...) — DEFERRED (legacy detection + per-state text config).
//   Retained as a documented no-op for provenance; the basic-text path is inlined above.

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
        // PORT-TODO: by-name child DIFF (DataDiffer) DEFERRED; rebuild by index below as a fallback.
    }

    // notMerge && el.removeAll();  — in the static rebuild the group child list starts empty anyway.
    el.removeAll()

    // Mapping children of a group simply by index.
    var index = 0
    while index < newLen {
        let newChildAny = newChildren?[index]
        let newChild = normalizeElOption(newChildAny)
        // In the rebuild path there is no oldChild to reuse.
        if let newChild = newChild {
            _ = doCreateOrUpdateEl(api, nil, dataIndex, newChild, seriesModel, el)
        }
        index += 1
    }
}

// upstream: function removeChildFromGroup / diffGroupChildren / getKey / processAddUpdate / processRemove
//   The by-name child DIFF machinery (DataDiffer + leave transition) is DEFERRED (see mergeChildren).
//   Retained here only as provenance markers.
//   - removeChildFromGroup(group, child, seriesModel) -> applyLeaveTransition(...)  (DEFERRED)
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

// color coercion — string | ZRColor → ZRenderKit.ZRColor (gradient/pattern out of static scope).
private func toZRColor(_ v: Any?) -> ZRenderKit.ZRColor? {
    if let s = v as? String { return .string(s) }
    if let z = v as? ZRenderKit.ZRColor { return z }
    return nil
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
    // PORT-TODO: decal / lineDash-string / gradient fill bridging deferred.
    return out
}

// `[String: Any]` style bag → TextStyleProps (basic-text subset). Includes the ec4 textFill/textStroke compat.
private func bridgeTextStyle(_ s: [String: Any]) -> TextStyleProps {
    var out = TextStyleProps()
    out.text = s["text"] as? String
    // Compatible with ec4: textFill/textStroke → fill/stroke.
    out.fill = (s["fill"] as? String) ?? (s["textFill"] as? String)
    out.stroke = (s["stroke"] as? String) ?? (s["textStroke"] as? String)
    out.opacity = customToDouble(s["opacity"])
    out.lineWidth = customToDouble(s["lineWidth"])
    out.font = s["font"] as? String
    out.fontFamily = s["fontFamily"] as? String
    if let fs = customToDouble(s["fontSize"]) { out.fontSize = .number(fs) }
    else if let fs = s["fontSize"] as? String { out.fontSize = .string(fs) }
    if let align = s["align"] as? String { out.align = TextAlign(rawValue: align) }
    if let va = s["verticalAlign"] as? String { out.verticalAlign = TextVerticalAlign(rawValue: va) }
    out.lineHeight = customToDouble(s["lineHeight"])
    out.width = customToDouble(s["width"])
    out.height = customToDouble(s["height"])
    out.x = customToDouble(s["x"])
    out.y = customToDouble(s["y"])
    // PORT-TODO: fontStyle/fontWeight/rich/backgroundColor/padding bridging deferred.
    return out
}

// `[String: Any]` style bag → ImageStyleProps.
private func bridgeImageStyle(_ s: [String: Any]) -> ImageStyleProps {
    var out = ImageStyleProps()
    if let url = s["image"] as? String { out.image = .url(url) }
    // PORT-TODO: non-URL ImageLike source bridging deferred.
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
