// Ported from echarts/src/model/mixin/itemStyle.ts — keep in sync with upstream

import ZRenderKit
// import makeStyleMapper from './makeStyleMapper';        -> makeStyleMapper  (sibling model/mixin/makeStyleMapper.swift)
// import Model from '../Model';                           -> Model           (sibling model/Model.swift: ref type with `getShallow`)
// import { ItemStyleOption } from '../../util/types';     -> ItemStyleOption (EChartsKit util/types.swift)
// import { PathStyleProps } from 'zrender/src/graphic/Path'; -> PathStyleProps (ZRenderKit)

public let ITEM_STYLE_KEY_MAP: [[String]] = [
    ["fill", "color"],
    ["stroke", "borderColor"],
    ["lineWidth", "borderWidth"],
    ["opacity"],
    ["shadowBlur"],
    ["shadowOffsetX"],
    ["shadowOffsetY"],
    ["shadowColor"],
    ["lineDash", "borderType"],
    ["lineDashOffset", "borderDashOffset"],
    ["lineCap", "borderCap"],
    ["lineJoin", "borderJoin"],
    ["miterLimit", "borderMiterLimit"]
    // Option decal is in `DecalObject` but style.decal is in `PatternObject`.
    // So do not transfer decal directly.
]

private let getItemStyle = makeStyleMapper(ITEM_STYLE_KEY_MAP)

// upstream `type ItemStyleKeys = 'fill' | 'stroke' | 'decal' | 'lineWidth'
//   | 'opacity' | 'shadowBlur' | 'shadowOffsetX' | 'shadowOffsetY' | 'shadowColor'
//   | 'lineDash' | 'lineDashOffset' | 'lineCap' | 'lineJoin' | 'miterLimit';`
//   Swift has no string-literal union type; the key set is captured by ITEM_STYLE_KEY_MAP above.

// upstream: export type ItemStyleProps = Pick<PathStyleProps, ItemStyleKeys>;
// makeStyleMapper builds a dynamic `Dictionary<Any>` ([String: Any]) bag rather than a
//   typed `PathStyleProps` struct (see makeStyleMapper.swift), so ItemStyleProps aliases that bag.
public typealias ItemStyleProps = Dictionary<Any>

// upstream: `class ItemStyleMixin { getItemStyle(this: Model, ...) }` mixed into Model via
//   `mixin(Model, ItemStyleMixin)`. Ported as a protocol + constrained extension (CONVENTIONS §2):
//   Model conforms to `ItemStyleMixin`, and the method body sees `self` typed as Model via the
//   `where Self: Model` constraint (mirroring upstream's `this: Model`).
public protocol ItemStyleMixin {}

extension ItemStyleMixin where Self: Model {

    public func getItemStyle(
        _ excludes: [String]? = nil,
        _ includes: [String]? = nil
    ) -> ItemStyleProps {
        // module-qualify the file-scope `let getItemStyle` (mapper closure) over this same-named
        // instance method (matches sibling lineStyle.swift/areaStyle.swift) now that `Model`
        // conforms to `ItemStyleMixin` and the instance method would otherwise shadow it.
        return EChartsKit.getItemStyle(self, excludes, includes)
    }

}

// export {ItemStyleMixin};
