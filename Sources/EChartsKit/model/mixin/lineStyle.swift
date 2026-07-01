// Ported from echarts/src/model/mixin/lineStyle.ts — keep in sync with upstream

import ZRenderKit
// import makeStyleMapper from './makeStyleMapper';                 -> makeStyleMapper (sibling model/mixin/makeStyleMapper.swift)
// import Model from '../Model';                                    -> Model           (sibling model/Model.swift: ref type with `getShallow`)
// import { LineStyleOption } from '../../util/types';              -> LineStyleOption (util/types.swift)
// import { PathStyleProps } from 'zrender/src/graphic/Path';       -> PathStyleProps  (ZRenderKit)

public let LINE_STYLE_KEY_MAP: [[String]] = [
    ["lineWidth", "width"],
    ["stroke", "color"],
    ["opacity"],
    ["shadowBlur"],
    ["shadowOffsetX"],
    ["shadowOffsetY"],
    ["shadowColor"],
    ["lineDash", "type"],
    ["lineDashOffset", "dashOffset"],
    ["lineCap", "cap"],
    ["lineJoin", "join"],
    ["miterLimit"]
    // Option decal is in `DecalObject` but style.decal is in `PatternObject`.
    // So do not transfer decal directly.
]

private let getLineStyle = makeStyleMapper(LINE_STYLE_KEY_MAP)

// type LineStyleKeys = 'lineWidth' | 'stroke' | 'opacity' | 'shadowBlur'
//     | 'shadowOffsetX' | 'shadowOffsetY' | 'shadowColor' | 'lineDash'
//     | 'lineDashOffset' | 'lineCap' | 'lineJoin' | 'miterLimit';
// PORT-TODO: this TS string-literal union has no faithful Swift analogue; it only narrows
//   the `Pick<PathStyleProps, LineStyleKeys>` below, which we collapse to the dynamic bag.

// export type LineStyleProps = Pick<PathStyleProps, LineStyleKeys>;
// PORT-TODO: `PathStyleProps` is a Swift struct (value type, fixed fields) and cannot be
//   produced from arbitrary string keys mechanically; mirror makeStyleMapper's decision and
//   surface the dynamic `Dictionary<Any>` ([String: Any]) bag it returns.
public typealias LineStyleProps = Dictionary<Any>

// upstream: `class LineStyleMixin { getLineStyle(this: Model, ...) }` applied onto `Model`
//   via `util.mixin`/declaration merging. Per CONVENTIONS §2, a TS mixin whose methods are
//   bound to `Model` (`this: Model`) is ported as a Swift extension on `Model`, preserving
//   the method set/name. (The `class LineStyleMixin` wrapper itself is structural noise once
//   the `this: Model` binding is expressed directly as an extension.)
extension Model {

    public func getLineStyle(
        _ excludes: [String]? = nil
        // PORT-TODO: upstream excludes is `readonly (keyof LineStyleOption)[]`; keyof narrowing
        //   has no Swift analogue, so it is the plain `[String]?` key list here.
    ) -> LineStyleProps {
        // upstream: `return getLineStyle(this, excludes);` — module-qualify to select the
        //   file-scope `let getLineStyle` (mapper closure) over this same-named instance method.
        return EChartsKit.getLineStyle(self, excludes, nil)
    }

}
