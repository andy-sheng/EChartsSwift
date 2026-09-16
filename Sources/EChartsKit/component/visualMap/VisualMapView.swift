// Ported from echarts/src/component/visualMap/VisualMapView.ts — keep in sync with upstream
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
//   import * as zrUtil from 'zrender/src/core/util';                 → `util.*` (ZRenderKit; `util.each`).
//   import {Group, Rect} from '../../util/graphic';
//     → `util/graphic` is NOT ported as a namespace. `Group` / `Rect` are the ZRenderKit scene-graph
//        types (used directly).
//   import * as formatUtil from '../../util/format';                 → `format.*` (util/format.swift);
//        `formatUtil.normalizeCssArray` via the local `normalizeCssArrayAny` bridge (see bottom).
//   import * as layout from '../../util/layout';
//     → `layout.createBoxLayoutReference` / `layout.positionElement` (util/layout.swift).
//   import VisualMapping from '../../visual/VisualMapping';
//     → `visual/VisualMapping` -> VisualMapping.swift (`class VisualMapping`). `VisualMapping.prepareVisualTypes`
//        / `VisualMapping.dependsOn` (statics) and `applyVisual` (instance) are referenced as the value→visual
//        ENCODING path this view queries.
//   import ComponentView from '../../view/Component';                → `ComponentView` (view/ComponentView.swift).
//   import GlobalModel from '../../model/Global';                    → `GlobalModel` (model/Global.swift).
//   import ExtensionAPI from '../../core/ExtensionAPI';              → `ExtensionAPI` (core/ExtensionAPI.swift).
//   import VisualMapModel from './VisualMapModel';
//     → `VisualMapModel` (component/visualMap/VisualMapModel.swift). Surface consumed here:
//        `get(...)`, `controllerVisuals` ([String: Any]), `getValueState(_) -> VisualState?`,
//        `getBoxLayoutParams()` (inherited). `VisualState` (typealias String) is declared there.
//   import { VisualOptionUnit, ColorString } from '../../util/types';  → type-only (dropped; dynamic `Any`).

// upstream: class VisualMapView extends ComponentView
// CONVENTIONS §2/§4: reference type subclassed by ContinuousView / PiecewiseVisualMapView → `open class`.
open class VisualMapView: ComponentView {

    // static type = 'visualMap';
    public static let type = "visualMap"
    // type = VisualMapView.type;
    open var type: String { return VisualMapView.type }

    // autoPositionValues = {left: 1, right: 1, top: 1, bottom: 1} as const;
    public let autoPositionValues: [String: Int] = ["left": 1, "right": 1, "top": 1, "bottom": 1]

    // ecModel: GlobalModel;  (injected by init)
    // IUO-bound var (NOT a `let` — CONVENTIONS §trap 2 concerns `let x = foo.bar` only); assigned in `init`.
    public var ecModel: GlobalModel!

    // api: ExtensionAPI;
    public var api: ExtensionAPI!

    // visualMapModel: VisualMapModel;
    public var visualMapModel: VisualMapModel!

    // init(ecModel: GlobalModel, api: ExtensionAPI) { this.ecModel = ecModel; this.api = api; }
    //   The overridable base hook is `init(_ ecModel:, _ api:)` (ComponentView).
    open override func `init`(_ ecModel: GlobalModel, _ api: ExtensionAPI) {
        self.ecModel = ecModel
        self.api = api
    }

    /**
     * @protected
     */
    // upstream: render(visualMapModel, ecModel, api, payload)
    //   Matches the full base `ComponentView.render` signature; narrows `model` to `VisualMapModel`.
    open override func render(
        _ model: ComponentModel, _ ecModel: GlobalModel, _ api: ExtensionAPI, _ payload: Payload
    ) {
        let visualMapModel = model as! VisualMapModel
        self.visualMapModel = visualMapModel

        // the pipeline is expected to call `init(ecModel, api)` before `render`; guarantee the
        //   injected refs exist (same defensive init as LegendView).
        if self.ecModel == nil || self.api == nil {
            self.`init`(ecModel, api)
        }

        // if (visualMapModel.get('show') === false) { this.group.removeAll(); return; }
        if (visualMapModel.get("show") as? Bool) == false {
            _ = self.group.removeAll()
            return
        }

        self.doRender(visualMapModel, ecModel, api, payload)
    }

    /**
     * @protected
     */
    open func renderBackground(_ group: Group) {
        let visualMapModel = self.visualMapModel!
        // const padding = formatUtil.normalizeCssArray(visualMapModel.get('padding') || 0);
        let padding = normalizeCssArrayAny(visualMapModel.get("padding"))
        // const rect = group.getBoundingRect();
        let rect = group.getBoundingRect()!

        // group.add(new Rect({ z2: -1, silent: true, shape: {...}, style: {...} }));
        var shape = RectShape()
        shape.x = rect.x - padding[3]
        shape.y = rect.y - padding[0]
        shape.width = rect.width + padding[3] + padding[1]
        shape.height = rect.height + padding[0] + padding[2]

        // style: { fill, stroke, lineWidth }
        var styleBag: [String: Any] = [:]
        styleBag["fill"] = visualMapModel.get("backgroundColor")
        styleBag["stroke"] = visualMapModel.get("borderColor")
        styleBag["lineWidth"] = visualMapModel.get("borderWidth")

        _ = group.add(Rect([
            "z2": -1.0, // Lay background rect on the lowest layer.
            "silent": true,
            "shape": shape as PathShape,
            // bridge the dynamic style bag → typed `PathStyleProps` via the shared
            //   `barStyleFromDict` seam (BarView.swift).
            "style": barStyleFromDict(styleBag)
        ]))
    }

    /**
     * @protected
     * @param targetValue can be Infinity or -Infinity
     * @param visualCluster Only can be 'color' 'opacity' 'symbol' 'symbolSize'
     * @param opts
     * @param opts.forceState Specify state, instead of using getValueState method.
     * @param opts.convertOpacityToAlpha For color gradient in controller widget.
     * @return {*} Visual value.
     */
    // upstream: protected getControllerVisual(targetValue, visualCluster, opts?) → `internal`.
    //   The `opts` object literal is spread into two default params (`forceState`, `convertOpacityToAlpha`).
    // upstream types `targetValue: number`, but for a `categories` visualMap the represent
    //   value is the raw category (often a STRING). `getValueState` / `applyVisual` both accept the loose
    //   value, so `targetValue` is kept as `Any?` here (continuous callers still pass a Double, which is a
    //   valid `Any?`). Narrowing to Double coerced string categories to 0 → every piecewise-categories
    //   legend swatch resolved to the same (outOfRange) color instead of its group color.
    internal func getControllerVisual(
        _ targetValue: Any?,
        _ visualCluster: String,
        forceState: VisualState? = nil,
        convertOpacityToAlpha: Bool = false
    ) -> Any? {
        let visualMapModel = self.visualMapModel!
        // const visualObj: {[key]?: ...} = {};
        var visualObj: [String: Any] = [:]

        // Default values.
        if visualCluster == "color" {
            // const defaultColor = visualMapModel.get('contentColor');
            let defaultColor = visualMapModel.get("contentColor")
            visualObj["color"] = defaultColor
        }

        // function getter(key) { return visualObj[key]; }
        let getter: VisualValueGetter = { key in visualObj[key] }
        // function setter(key, value) { visualObj[key] = value; }
        let setter: VisualValueSetter = { key, value in visualObj[key] = value }

        // const mappings = visualMapModel.controllerVisuals[forceState || visualMapModel.getValueState(targetValue)];
        //   `controllerVisuals` is the dynamic `[String: Any]` per-state map (each value is the
        //   `createVisualMappings` result, i.e. `[String: VisualMapping]`); `getValueState` returns
        //   `VisualState?`, so the key resolves through a flatMap.
        let stateKey = forceState ?? visualMapModel.getValueState(targetValue)
        let mappings: Any? = stateKey.flatMap { visualMapModel.controllerVisuals[$0] }
        let mappingsDict = mappings as? [String: VisualMapping]
        // const visualTypes = VisualMapping.prepareVisualTypes(mappings);
        let visualTypes = VisualMapping.prepareVisualTypes(mappings)

        util.each(visualTypes) { typeIn, _ in
            var type = typeIn
            var visualMapping = mappingsDict?[type]
            // if (opts.convertOpacityToAlpha && type === 'opacity') { type = 'colorAlpha'; visualMapping = mappings.__alphaForOpacity; }
            if convertOpacityToAlpha && type == "opacity" {
                type = "colorAlpha"
                visualMapping = mappingsDict?["__alphaForOpacity"]
            }
            // if (VisualMapping.dependsOn(type, visualCluster)) { visualMapping && visualMapping.applyVisual(targetValue, getter, setter); }
            if VisualMapping.dependsOn(type, visualCluster), let targetValue = targetValue {
                visualMapping?.applyVisual(targetValue, getter, setter)
            }
        }

        return visualObj[visualCluster]
    }

    // upstream: protected positionGroup(group) → `internal`.
    internal func positionGroup(_ group: Group) {
        let model = self.visualMapModel!
        let api = self.api!

        // const refContainer = layout.createBoxLayoutReference(model, api).refContainer;
        let refContainer = layout.createBoxLayoutReference(model, api).refContainer
        // layout.positionElement(group, model.getBoxLayoutParams(), refContainer);
        //   Value-returning port (CONVENTIONS §3): apply the computed x/y back to the group.
        let posResult = layout.positionElement(
            group, boxLayoutParamsToDict(model.getBoxLayoutParams()), refContainer, nil, nil
        )
        group.x = posResult.out["x"] ?? group.x
        group.y = posResult.out["y"] ?? group.y
    }

    // upstream: protected doRender(visualMapModel, ecModel, api, payload) {} — overridden by subclasses.
    open func doRender(
        _ visualMapModel: VisualMapModel,
        _ ecModel: GlobalModel,
        _ api: ExtensionAPI,
        _ payload: Payload
    ) {}
}

// export default VisualMapView;  → `open class VisualMapView` above.

// ============================================================================
// note helpers — NOT part of visualMap/VisualMapView.ts upstream. These reproduce out-of-phase
// sibling APIs / JS idioms so the static visualMap render compiles. Delete each when its real sibling
// lands and call the sibling directly. (Kept `internal` so the two subclass files can reuse them.)
// ============================================================================

/// JS truthiness for the dynamic option bag (`if (x)` / `!x`). (CONVENTIONS §6.)
internal func visualMapJsTruthy(_ v: Any?) -> Bool {
    guard let v = v else { return false }
    if let b = v as? Bool { return b }
    if let d = v as? Double { return d != 0 && !d.isNaN }
    if let i = v as? Int { return i != 0 }
    if let s = v as? String { return !s.isEmpty }
    return true
}

/// Int|Double|NSNumber → Double coercion for the dynamic option bag (CONVENTIONS §trap 1 — never
/// read a numeric option with a bare `as? Double`).
internal func visualMapAsDouble(_ v: Any?) -> Double? {
    if let d = v as? Double { return d }
    if let i = v as? Int { return Double(i) }
    if let n = v as? NSNumber { return n.doubleValue }
    return nil
}

/// `formatUtil.normalizeCssArray(padding || 0)` on the dynamic `number | number[]` option value.
private func normalizeCssArrayAny(_ v: Any?) -> [Double] {
    if let arr = v as? [Double] {
        return format.normalizeCssArray(arr)
    }
    if let arr = v as? [Any] {
        return format.normalizeCssArray(arr.map { visualMapAsDouble($0) ?? 0 })
    }
    if let d = visualMapAsDouble(v) {
        return format.normalizeCssArray(d)
    }
    return format.normalizeCssArray(0.0)
}

/// `model.getBoxLayoutParams()` returns the typed `BoxLayoutOptionMixin` struct; `layout.positionElement`
/// consumes the dynamic `[String: Any]` bag. Bridge the six box fields.
internal func boxLayoutParamsToDict(_ p: BoxLayoutOptionMixin) -> [String: Any] {
    var d: [String: Any] = [:]
    if let v = p.left { d["left"] = v }
    if let v = p.right { d["right"] = v }
    if let v = p.top { d["top"] = v }
    if let v = p.bottom { d["bottom"] = v }
    if let v = p.width { d["width"] = v }
    if let v = p.height { d["height"] = v }
    return d
}
