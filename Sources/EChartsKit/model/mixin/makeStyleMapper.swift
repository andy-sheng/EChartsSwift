// Ported from echarts/src/model/mixin/makeStyleMapper.ts — keep in sync with upstream

// TODO Parse shadow style
// TODO Only shallow path support
import ZRenderKit
// import * as zrUtil from 'zrender/src/core/util';          -> util            (ZRenderKit)
// import {Dictionary} from 'zrender/src/core/types';        -> Dictionary<T>   (ZRenderKit, = [String: T])
// import {PathStyleProps} from 'zrender/src/graphic/Path';  -> PathStyleProps  (ZRenderKit)
// import Model from '../Model';                             -> Model           (sibling model/Model.swift: ref type with `getShallow`)

// upstream: export default function makeStyleMapper(properties, ignoreParent?)
//   -> top-level `public func makeStyleMapper(...)` so call sites stay identical
//      (e.g. `let getItemStyle = makeStyleMapper(ITEM_STYLE_KEY_MAP)`).
//
// The returned mapper closure type mirrors `(model, excludes?, includes?) => PathStyleProps`.
// upstream returns `style as PathStyleProps`; here we return the dynamic
//   `Dictionary<Any>` ([String: Any]) bag as-is, because `PathStyleProps` is a Swift struct
//   (value type, fixed fields) and cannot be produced from arbitrary string keys mechanically.
//   Swift closure types cannot carry defaulted/optional params, so callers pass `nil` explicitly
//   for `excludes`/`includes`.
public func makeStyleMapper(
    _ properties: [[String]],
    _ ignoreParent: Bool? = nil
) -> (Model, [String]?, [String]?) -> Dictionary<Any> {
    // Normalize
    // upstream mutates the (readonly-typed) input array in place; Swift arrays are
    //   value types, so we normalize a local mutable copy that the returned closure captures.
    var properties = properties
    for i in 0..<properties.count {
        // upstream: if (!properties[i][1]) properties[i][1] = properties[i][0];
        //   (`!properties[i][1]` is truthy-false for `undefined` (missing slot) or empty string)
        if properties[i].count < 2 {
            properties[i].append(properties[i][0])
        }
        else if properties[i][1].isEmpty {
            properties[i][1] = properties[i][0]
        }
    }

    let ignoreParent = ignoreParent ?? false

    return { (model: Model, excludes: [String]?, includes: [String]?) -> Dictionary<Any> in
        // upstream: const style: Dictionary<any> = {};  (mutated below -> `var` in Swift)
        var style: Dictionary<Any> = [:]
        for i in 0..<properties.count {
            let propName = properties[i][1]
            if (excludes != nil && util.indexOf(excludes, propName) >= 0)
                || (includes != nil && util.indexOf(includes, propName) < 0)
            {
                continue
            }
            let val = model.getShallow(propName, ignoreParent)
            if val != nil {
                style[properties[i][0]] = val
            }
        }
        // TODO Text or image?
        return style
    }
}
