// Ported from echarts/src/component/graphic/GraphicModel.ts — keep in sync with upstream
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

// upstream imports:
//   import * as zrUtil from 'zrender/src/core/util';               -> `util.*` (ZRenderKit).
//   import * as modelUtil from '../../util/model';                 -> `model.*` (util/modelUtil.swift).
//   import { ComponentOption, BoxLayoutOptionMixin, Dictionary, ZRStyleProps, OptionId,
//     CommonTooltipOption, AnimationOptionMixin, AnimationOption } from '../../util/types';
//     -> EChartsKit util/types.swift.
//   import ComponentModel from '../../model/Component';            -> `ComponentModel`.
//   import Element, { ElementTextConfig } from 'zrender/src/Element'; -> ZRenderKit `Element`.
//   import Displayable ...; import { PathProps, PathStyleProps } ...; import { ImageStyleProps,
//     ImageProps } ...; import { TextStyleProps, TextProps } ...;  -> ZRenderKit graphic props.
//   import GlobalModel from '../../model/Global';                  -> `GlobalModel`.
//   import { copyLayoutParams, mergeLayoutParam } from '../../util/layout';
//     -> `layout.copyLayoutParams` / `layout.mergeLayoutParam` (util/layout.swift; ported — see call
//        sites below).
//   import { TransitionOptionMixin } from '../../animation/customGraphicTransition';
//   import { ElementKeyframeAnimationOption } from '../../animation/customGraphicKeyframeAnimation';
//   import { GroupProps } from 'zrender/src/graphic/Group';
//   import { TransformProp } from 'zrender/src/core/Transformable';
//   import { ElementEventNameWithOn } from 'zrender/src/core/types';
//     -> DEFERRED (animation/transition/keyframe/event typings; static-render port).

// ------------------------------------------------------------------------------------------------
// upstream option interfaces:
//   GraphicComponentBaseElementOption / GraphicComponentDisplayableOption /
//   GraphicComponentGroupOption / GraphicComponentZRPathOption / GraphicComponentImageOption /
//   GraphicComponentTextOption / GraphicComponentElementOption (the union of the four).
//
// note (CONVENTIONS §2): the TS interface hierarchy + the `GraphicComponentElementOption`
//   discriminated union are collapsed to ONE dynamic option bag modeled as a reference class
//   (`GraphicComponentElementOption` below). Upstream `GraphicComponentElementOption` IS a plain JS
//   object flowing by identity (`option.parentOption = parentOption`, mutation through aliases,
//   `existList[index] = newElOptCopy`), so it MUST be a reference type (CONVENTIONS §4). Typed field
//   accessors are provided for exactly the keys the model/view touch; everything else lives in the
//   `.option` bag. `type GraphicExtraElementInfo = Dictionary<unknown>` -> `[String: Any]`.
// ------------------------------------------------------------------------------------------------

/// Reference bag for a single graphic element option (any of group/path/image/text). Conforms to
/// `MappingExistingItem` so it can flow through `model.mappingToExists` (see `optionUpdated`).
public final class GraphicComponentElementOption: MappingExistingItem {

    /// The raw dynamic option object (upstream: the JS option literal itself).
    public var option: [String: Any]

    public init(_ option: [String: Any] = [:]) {
        self.option = option
    }

    // Generic keyed access mirroring `elOption[key]` in upstream.
    public subscript(_ key: String) -> Any? {
        get { return option[key] }
        set {
            if newValue == nil { option[key] = nil }
            else { option[key] = newValue }
        }
    }

    // ---- MappingExistingItem / MappingComparable ----
    // upstream: `id?: OptionId; name?: string;`
    public var id: OptionId? {
        get { return option["id"] }
        set { option["id"] = newValue }
    }
    public var name: OptionName? {
        get { return option["name"] }
        set { option["name"] = newValue }
    }

    // ---- Typed accessors for the keys the model/view read directly ----
    // upstream: `type?: string;`
    public var type: String? {
        get { return option["type"] as? String }
        set { option["type"] = newValue }
    }
    // upstream: `parentId?: OptionId;` (internal usage only)
    public var parentId: OptionId? {
        get { return option["parentId"] }
        set { option["parentId"] = newValue }
    }
    // upstream: `parentOption?: GraphicComponentElementOption;` (internal usage only)
    public var parentOption: GraphicComponentElementOption? {
        get { return option["parentOption"] as? GraphicComponentElementOption }
        set { option["parentOption"] = newValue }
    }
    // upstream: `children?: GraphicComponentElementOption[];`
    public var children: [GraphicComponentElementOption]? {
        get { return option["children"] as? [GraphicComponentElementOption] }
        set { option["children"] = newValue }
    }
    // upstream: `hv?: [boolean, boolean];`
    public var hv: [Bool]? {
        get { return option["hv"] as? [Bool] }
        set { option["hv"] = newValue }
    }
    // upstream: `bounding?: 'raw' | 'all';`
    public var bounding: String? {
        get { return option["bounding"] as? String }
        set { option["bounding"] = newValue }
    }
    // upstream: `$action?: 'merge' | 'replace' | 'remove';`
    public var action: String? {   // `$action`
        get { return option["$action"] as? String }
        set { option["$action"] = newValue }
    }
    // upstream: `clipPath?: ... | false;`
    public var clipPath: Any? {
        get { return option["clipPath"] }
        set { option["clipPath"] = newValue }
    }
    // upstream group: `width?: number; height?: number;`
    public var width: Any? {
        get { return option["width"] }
        set { option["width"] = newValue }
    }
    public var height: Any? {
        get { return option["height"] }
        set { option["height"] = newValue }
    }
    // upstream: `transition?` (root-level; consumed by the deferred transition system + `_relocate`).
    public var transition: Any? {
        get { return option["transition"] }
        set { option["transition"] = newValue }
    }
}

// upstream: `export type ElementMap = zrUtil.HashMap<Element, string>;`
public typealias ElementMap = HashMap<Element>

// ------------------------------------------------------------------------------------------------

// upstream:
//   export function setKeyInfoToNewElOption(
//       resultItem: ReturnType<typeof modelUtil.mappingToExists>[number],
//       newElOption: GraphicComponentElementOption
//   ): void
public func setKeyInfoToNewElOption(
    _ resultItem: MappingResultItem,
    _ newElOption: GraphicComponentElementOption
) {
    let existElOption = resultItem.existing as? GraphicComponentElementOption

    // Set id and type after id assigned.
    newElOption.id = resultItem.keyInfo!.id
    // !newElOption.type && existElOption && (newElOption.type = existElOption.type);
    if (newElOption.type == nil), let existElOption = existElOption {
        newElOption.type = existElOption.type
    }

    // Set parent id if not specified
    if newElOption.parentId == nil {
        let newElParentOption = newElOption.parentOption
        if let newElParentOption = newElParentOption {
            newElOption.parentId = newElParentOption.id
        }
        else if let existElOption = existElOption {
            newElOption.parentId = existElOption.parentId
        }
    }

    // Clear
    newElOption.parentOption = nil
}

// upstream:
//   function isSetLoc(obj, props: ('left' | 'right' | 'top' | 'bottom')[]): boolean
func isSetLoc(
    _ obj: GraphicComponentElementOption,
    _ props: [String]
) -> Bool {
    var isSet = false
    util.each(props) { prop, _ in
        // obj[prop] != null && obj[prop] !== 'auto' && (isSet = true);
        let v = obj[prop]
        if v != nil && !(v is NSNull) && (v as? String) != "auto" {
            isSet = true
        }
    }
    return isSet
}

// upstream:
//   function mergeNewElOptionToExist(existList, index, newElOption): void
func mergeNewElOptionToExist(
    _ existList: inout [GraphicComponentElementOption?],
    _ index: Int,
    _ newElOption: GraphicComponentElementOption
) {
    // Update existing options, for `getOption` feature.
    // const newElOptCopy = zrUtil.extend({}, newElOption);
    var copyBag: [String: Any] = [:]
    util.extend(&copyBag, newElOption.option)
    let newElOptCopy = GraphicComponentElementOption(copyBag)
    let existElOption = index < existList.count ? existList[index] : nil

    // const $action = newElOption.$action || 'merge';
    let action = newElOption.action ?? "merge"
    if action == "merge" {
        if let existElOption = existElOption {
            if __DEV__ {
                let newType = newElOption.type
                util.assert(
                    newType == nil || existElOption.type == newType,
                    "Please set $action: \"replace\" to change `type`"
                )
            }

            // We can ensure that newElOptCopy and existElOption are not
            // the same object, so `merge` will not change newElOptCopy.
            // zrUtil.merge(existElOption, newElOptCopy, true);
            var existBag = existElOption.option
            util.merge(&existBag, newElOptCopy.option, true)
            existElOption.option = existBag

            // Rigid body, use ignoreSize.
            // mergeLayoutParam(existElOption, newElOptCopy, { ignoreSize: true });
            // `layout.mergeLayoutParam` (util/layout.swift) is ported and called below;
            //   operates on the `.option` bags in place.
            var mergeTarget = existElOption.option
            layout.mergeLayoutParam(&mergeTarget, newElOptCopy.option, ["ignoreSize": true])
            existElOption.option = mergeTarget

            // Will be used in render.
            // copyLayoutParams(newElOption, existElOption);
            // `layout.copyLayoutParams` (util/layout.swift) is ported and called below;
            //   copies LOCATION_PARAMS from source bag onto target bag.
            newElOption.option = layout.copyLayoutParams(newElOption.option, existElOption.option)

            // Copy transition info to new option so it can be used in the transition.
            // DO IT AFTER merge
            copyTransitionInfo(newElOption, existElOption)
            copyTransitionInfo(newElOption, existElOption, "shape")
            copyTransitionInfo(newElOption, existElOption, "style")
            copyTransitionInfo(newElOption, existElOption, "extra")

            // Copy clipPath
            newElOption.clipPath = existElOption.clipPath
        }
        else {
            existList[index] = newElOptCopy
        }
    }
    else if action == "replace" {
        existList[index] = newElOptCopy
    }
    else if action == "remove" {
        // null will be cleaned later.
        if existElOption != nil {
            existList[index] = nil
        }
    }
}

// upstream: const TRANSITION_PROPS_TO_COPY = ['transition', 'enterFrom', 'leaveTo'];
private let TRANSITION_PROPS_TO_COPY = ["transition", "enterFrom", "leaveTo"]
// upstream: const ROOT_TRANSITION_PROPS_TO_COPY = TRANSITION_PROPS_TO_COPY.concat([...]);
private let ROOT_TRANSITION_PROPS_TO_COPY =
    TRANSITION_PROPS_TO_COPY + ["enterAnimation", "updateAnimation", "leaveAnimation"]

// upstream:
//   function copyTransitionInfo(target, source, targetProp?): void
func copyTransitionInfo(
    _ targetIn: GraphicComponentElementOption,
    _ sourceIn: GraphicComponentElementOption,
    _ targetProp: String? = nil
) {
    // upstream reassigns the local `target`/`source` to the nested sub-object when `targetProp` is
    // given, then copies transition props between those sub-objects. Since our option is a `[String:
    // Any]` bag rather than nested reference objects, the nested case operates on nested bags and
    // writes the mutated sub-bag back onto the parent bag.
    if let targetProp = targetProp {
        // if (!target[targetProp] && source[targetProp]) { target[targetProp] = {}; }
        let sourceSub = sourceIn.option[targetProp] as? [String: Any]
        if targetIn.option[targetProp] == nil, sourceSub != nil {
            // TODO avoid creating this empty object when there is no transition configuration.
            targetIn.option[targetProp] = [String: Any]()
        }
        var targetSub = targetIn.option[targetProp] as? [String: Any]
        // if (!target || !source) return;
        guard targetSub != nil, let src = sourceSub else {
            return
        }

        let props = TRANSITION_PROPS_TO_COPY
        for i in 0..<props.count {
            let prop = props[i]
            if targetSub![prop] == nil && src[prop] != nil {
                targetSub![prop] = src[prop]
            }
        }
        targetIn.option[targetProp] = targetSub
        return
    }

    // Root-level copy.
    let props = ROOT_TRANSITION_PROPS_TO_COPY
    for i in 0..<props.count {
        let prop = props[i]
        if targetIn.option[prop] == nil && sourceIn.option[prop] != nil {
            targetIn.option[prop] = sourceIn.option[prop]
        }
    }
}

// upstream:
//   function setLayoutInfoToExist(existItem, newElOption)
func setLayoutInfoToExist(
    _ existItem: GraphicComponentElementOption?,
    _ newElOption: GraphicComponentElementOption
) {
    guard let existItem = existItem else {
        return
    }
    // existItem.hv = newElOption.hv = [ ... ]
    let hv: [Bool] = [
        // Rigid body, don't care about `width`.
        isSetLoc(newElOption, ["left", "right"]),
        // Rigid body, don't care about `height`.
        isSetLoc(newElOption, ["top", "bottom"])
    ]
    existItem.hv = hv
    newElOption.hv = hv
    // Give default group size. Otherwise layout error may occur.
    if existItem.type == "group" {
        let existingGroupOpt = existItem
        let newGroupOpt = newElOption
        // existingGroupOpt.width == null && (existingGroupOpt.width = newGroupOpt.width = 0);
        if existingGroupOpt.width == nil {
            existingGroupOpt.width = 0.0
            newGroupOpt.width = 0.0
        }
        if existingGroupOpt.height == nil {
            existingGroupOpt.height = 0.0
            newGroupOpt.height = 0.0
        }
    }
}

// ------------------------------------------------------------------------------------------------
// upstream: export class GraphicComponentModel extends ComponentModel<GraphicComponentOption>
// ------------------------------------------------------------------------------------------------
open class GraphicComponentModel: ComponentModel {

    // static type = 'graphic';
    public static let graphicType = "graphic"
    open override class var type: ComponentFullType { return GraphicComponentModel.graphicType }
    // type = GraphicComponentModel.type; (instance mirrors static via base `type` computed prop.)

    // preventAutoZ = true;  (set in init — base leaves the stored `preventAutoZ` at its default.)

    // static defaultOption: GraphicComponentOption = { elements: [] };
    open override class var defaultOption: ModelOption? {
        return ["elements": [Any]()]
    }

    /**
     * Save el options for the sake of the performance (only update modified graphics).
     * The order is the same as those in option. (ancesters -> descendants)
     */
    // upstream: private _elOptionsToUpdate: GraphicComponentElementOption[];
    private var _elOptionsToUpdate: [GraphicComponentElementOption]?

    public required init(_ option: ModelOption?, _ parentModel: Model?, _ ecModel: GlobalModel?) {
        super.init(option, parentModel, ecModel)
        // upstream instance field: `preventAutoZ = true;`
        self.preventAutoZ = true
    }

    // Convenience accessor for `this.option.elements` (the model option bag holds `elements`).
    private var optionElements: [GraphicComponentElementOption]? {
        get { return (self.option as? [String: Any])?["elements"] as? [GraphicComponentElementOption] }
        set {
            var bag = (self.option as? [String: Any]) ?? [:]
            if let newValue = newValue { bag["elements"] = newValue }
            else { bag["elements"] = nil }   // upstream: `this.option.elements = null`
            self.option = bag
        }
    }

    // upstream: mergeOption(option: GraphicComponentOption, ecModel: GlobalModel): void
    open override func mergeOption(_ option: ModelOption?, _ ecModel: GlobalModel?) {
        // Prevent default merge to elements
        let elements = self.optionElements
        self.optionElements = nil

        super.mergeOption(option, ecModel)

        self.optionElements = elements
    }

    // upstream: optionUpdated(newOption: GraphicComponentOption, isInit: boolean): void
    open override func optionUpdated(_ newCptOption: ModelOption?, _ isInit: Bool) {
        let newOption = newCptOption as? [String: Any]
        // const newList = (isInit ? thisOption : newOption).elements;
        // note (normalization): on first `setOption` the element options arrive as raw
        //   `[[String: Any]]` dicts (upstream treats them structurally); we wrap each into the
        //   reference `GraphicComponentElementOption` (recursively wrapping `children`) so the rest of
        //   the model can flow them by identity. After the first `optionUpdated` they are already
        //   wrapped (stored back into `option.elements`), so `normalizeElementOptions` passes through.
        let newList: [GraphicComponentElementOption]? = normalizeElementOptions(
            isInit
                ? (self.option as? [String: Any])?["elements"]
                : newOption?["elements"]
        )
        // const existList = thisOption.elements = isInit ? [] : thisOption.elements;
        var existList: [GraphicComponentElementOption?]
        if isInit {
            self.optionElements = []
            existList = []
        }
        else {
            existList = (self.optionElements ?? []).map { $0 }
        }

        // const flattenedList = [] as GraphicComponentElementOption[];
        var flattenedList: [GraphicComponentElementOption] = []
        self._flatten(newList, &flattenedList, nil)

        // const mappingResult = modelUtil.mappingToExists(existList, flattenedList, 'normalMerge');
        //
        // note (bridge): the ported `model.mappingToExists` is specialized to
        //   `(MappingExistingItem, ComponentOption)`; upstream is generic over the element option
        //   objects (returned by identity). We (a) pass the existing elements as `MappingExistingItem`
        //   (they conform), and (b) project each new element into a `ComponentOption` carrying its
        //   `id`/`name` plus the element reference in `rawOption[GRAPHIC_EL_KEY]`, then recover the
        //   element from the result. This reproduces upstream identity flow.
        // `existList` is genuinely sparse (holes left by removed elements) and the loop below indexes
        //   `existList[index]` against `mappingResult[index]`, so the holes MUST be preserved: `map`,
        //   not `compactMap` (which would collapse them and shift every subsequent index).
        let existings: [MappingExistingItem?] = existList.map { $0 as MappingExistingItem? }
        let newCmptOptions: [ComponentOption] = flattenedList.map { el in
            var c = ComponentOption()
            c.id = el.id
            c.name = el.name
            c.rawOption = [GRAPHIC_EL_KEY: el]
            return c
        }
        let mappingResult = model.mappingToExists(existings, newCmptOptions, .normalMerge)

        // JS arrays auto-extend on out-of-range assignment; `mappingResult` may contain more items
        // than `existList` (brand-new elements appended by `mappingByIndex`). Pre-grow `existList`
        // with nils so `existList[index]` is always valid inside the loop below.
        while existList.count < mappingResult.count {
            existList.append(nil)
        }

        // Clear elOptionsToUpdate
        var elOptionsToUpdate: [GraphicComponentElementOption] = []
        self._elOptionsToUpdate = elOptionsToUpdate

        util.each(mappingResult) { resultItem, index in
            // const newElOption = resultItem.newOption as GraphicComponentElementOption;
            let newElOption = resultItem.newOption?.rawOption?[GRAPHIC_EL_KEY] as? GraphicComponentElementOption

            if __DEV__ {
                util.assert(
                    newElOption != nil || resultItem.existing != nil,
                    "Empty graphic option definition"
                )
            }

            guard let newElOption = newElOption else {
                return
            }

            elOptionsToUpdate.append(newElOption)

            setKeyInfoToNewElOption(resultItem, newElOption)

            mergeNewElOptionToExist(&existList, index, newElOption)

            setLayoutInfoToExist(index < existList.count ? existList[index] : nil, newElOption)
        }
        self._elOptionsToUpdate = elOptionsToUpdate

        // Clean
        // thisOption.elements = zrUtil.filter(existList, (item) => { item && delete item.$action; return item != null; });
        let cleaned: [GraphicComponentElementOption] = existList.compactMap { item in
            // $action should be volatile, otherwise option gotten from
            // `getOption` will contain unexpected $action.
            if let item = item {
                item.action = nil   // delete item.$action
                return item
            }
            return nil
        }
        self.optionElements = cleaned
    }

    /**
     * Convert
     * [{ type: 'group', id: 'xx', children: [{type: 'circle'}, {type: 'polygon'}] }]
     * to
     * [ {type: 'group', id: 'xx'}, {type: 'circle', parentId: 'xx'}, {type: 'polygon', parentId: 'xx'} ]
     */
    // upstream: private _flatten(optionList, result, parentOption): void
    private func _flatten(
        _ optionList: [GraphicComponentElementOption]?,
        _ result: inout [GraphicComponentElementOption],
        _ parentOption: GraphicComponentElementOption?
    ) {
        util.each(optionList) { option, _ in
            // if (!option) return;  — a nil element is skipped (guaranteed non-nil by the [T] element type).

            if let parentOption = parentOption {
                option.parentOption = parentOption
            }

            result.append(option)

            let children = option.children
            // here we don't judge if option.type is `group`
            // when new option doesn't provide `type`, it will cause that the children can't be updated.
            if let children = children, children.count > 0 {
                self._flatten(children, &result, option)
            }
            // Deleting for JSON output, and for not affecting group creation.
            option.children = nil   // delete option.children
        }
    }

    // FIXME
    // Pass to view using payload? setOption has a payload?
    // upstream: useElOptionsToUpdate(): GraphicComponentElementOption[]
    open func useElOptionsToUpdate() -> [GraphicComponentElementOption]? {
        let els = self._elOptionsToUpdate
        // Clear to avoid render duplicately when zooming.
        self._elOptionsToUpdate = nil
        return els
    }
}

// Private key under which the element reference is smuggled through `ComponentOption.rawOption` for
// the `mappingToExists` bridge above (uses a NUL-prefixed key to avoid clashing with real options).
let GRAPHIC_EL_KEY = "\u{0}__graphicElOption"

// Wrap raw element-option dicts into `GraphicComponentElementOption` reference bags (pass through
// already-wrapped instances). Recurses into `children` so nested groups wrap too. See the
// note in `optionUpdated`.
func normalizeElementOptions(_ raw: Any?) -> [GraphicComponentElementOption]? {
    guard let arr = raw as? [Any] else {
        return raw as? [GraphicComponentElementOption]
    }
    return arr.map { normalizeElementOption($0) }
}

func normalizeElementOption(_ raw: Any) -> GraphicComponentElementOption {
    if let el = raw as? GraphicComponentElementOption {
        return el
    }
    if var bag = raw as? [String: Any] {
        // Wrap nested children first, then store them back so `.children` reads wrapped instances.
        if let childrenRaw = bag["children"] as? [Any] {
            bag["children"] = childrenRaw.map { normalizeElementOption($0) }
        }
        return GraphicComponentElementOption(bag)
    }
    return GraphicComponentElementOption([:])
}
