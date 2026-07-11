// Ported from echarts/src/model/mixin/areaStyle.ts — keep in sync with upstream

import ZRenderKit
// import makeStyleMapper from './makeStyleMapper';            -> makeStyleMapper (sibling model/mixin/makeStyleMapper.swift)
// import Model from '../Model';                               -> Model           (sibling model/Model.swift: ref type with `getShallow`)
// import { AreaStyleOption } from '../../util/types';         -> AreaStyleOption (util/types: keyof used only as `String` key names here)
// import { PathStyleProps } from 'zrender/src/graphic/Path';  -> PathStyleProps  (ZRenderKit)

public let AREA_STYLE_KEY_MAP: [[String]] = [
    ["fill", "color"],
    ["shadowBlur"],
    ["shadowOffsetX"],
    ["shadowOffsetY"],
    ["opacity"],
    ["shadowColor"]
    // Option decal is in `DecalObject` but style.decal is in `PatternObject`.
    // So do not transfer decal directly.
]
private let getAreaStyle = makeStyleMapper(AREA_STYLE_KEY_MAP)

// upstream: type AreaStyleProps = Pick<PathStyleProps, 'fill' | 'shadowBlur'
//   | 'shadowOffsetX' | 'shadowOffsetY' | 'opacity' | 'shadowColor'>
// PORT-NOTE: `makeStyleMapper` returns the dynamic `Dictionary<Any>` bag (see its port note),
//   not a fixed-field struct, so we cannot reproduce the `Pick<PathStyleProps, ...>` value type
//   mechanically. The mapper output IS that subset of `PathStyleProps` keyed by string.
public typealias AreaStyleProps = Dictionary<Any>

// upstream: class AreaStyleMixin { getAreaStyle(this: Model, ...) { ... } }; export {AreaStyleMixin}
// PORT-NOTE: TS mixin (applied onto Model subclasses via `this: Model`). Per CONVENTIONS §2
//   we replicate the upstream method set as a protocol + protocol-extension constrained to
//   `Self: Model`. Conforming a Model-derived type to `AreaStyleMixin` grants `getAreaStyle`.
public protocol AreaStyleMixin: AnyObject {
    func getAreaStyle(
        _ excludes: [String]?,
        _ includes: [String]?
    ) -> AreaStyleProps
}

public extension AreaStyleMixin where Self: Model {
    func getAreaStyle(
        _ excludes: [String]? = nil,
        _ includes: [String]? = nil
    ) -> AreaStyleProps {
        // PORT-NOTE: module-qualify the file-private mapper closure to disambiguate it from
        //   this same-named method (upstream relies on JS module-vs-method scoping).
        return EChartsKit.getAreaStyle(self, excludes, includes)
    }
}
