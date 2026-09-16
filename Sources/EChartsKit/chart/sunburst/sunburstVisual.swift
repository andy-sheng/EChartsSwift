// Ported from echarts/src/chart/sunburst/sunburstVisual.ts — keep in sync with upstream
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
//   import { lift } from 'zrender/src/tool/color';                  -> `ZRenderKit.color.lift` (Tool/color.swift).
//   import { extend, isString } from 'zrender/src/core/util';       -> `util.extend` / `util.isString`.
//   import GlobalModel from '../../model/Global';                   -> GlobalModel (model/Global.swift).
//   import SunburstSeriesModel, { SERIES_TYPE_SUNBURST, SunburstSeriesNodeItemOption } from './SunburstSeries';
//       -> sibling SunburstSeries.swift.
//   import { Dictionary, ColorString } from '../../util/types';     -> util/types.swift (type-only).
//   import { TreeNode } from '../../data/Tree';                     -> TreeNode (data/Tree.swift, sibling track).
//   import tokens from '../../visual/tokens';
//       -> visual/tokens.swift is ported. Only `tokens.color.neutral50` is used; still inlined below
//          as its upstream literal (`#86878c`).
//   import { createSimpleOverallStageHandler } from '../../util/model'; -> `model.createSimpleOverallStageHandler`.

// `tokens.color.neutral50` (visual/tokens.swift). Inlined as the upstream literal value.
private let tokens_color_neutral50 = "#86878c"

// upstream:
//   export const sunburstVisualStageHandler = createSimpleOverallStageHandler(SERIES_TYPE_SUNBURST, sunburstVisual);
// `sunburstVisual` is `(ecModel)` (1-arg); the handler expects `(GlobalModel, ExtensionAPI, Payload?)`.
// Adapt with a thin wrapper that drops the extra args, keeping `sunburstVisual` byte-faithful (1-arg).
public let sunburstVisualStageHandler = model.createSimpleOverallStageHandler(
    SERIES_TYPE_SUNBURST,
    { ecModel, _, _ in sunburstVisual(ecModel) }
)

// upstream palette `scope` is the object literal `{}` (`Dictionary<ColorString>`), used only
//   as a WeakMap identity key by getColorFromPalette (see model/mixin/palette.swift). Modeled as an
//   empty reference type so it can key the per-scope palette store.
private final class SunburstPaletteScope {}

public func sunburstVisual(_ ecModel: GlobalModel) {

    // const paletteScope: Dictionary<ColorString> = {};
    let paletteScope = SunburstPaletteScope()

    // Default color strategy
    func pickColor(_ node: TreeNode, _ seriesModel: SunburstSeriesModel, _ treeHeight: Double) -> Any? {
        if Double(node.depth) == 0 {
            // Don't use palette color for the root node, because it's displayed only when drilling down.
            return tokens_color_neutral50
        }

        // Choose color from palette based on the first level.
        var current = node
        while Double(current.depth) > 1 {
            // depth > 1 guarantees a parent (root is depth 0/1); force-unwrap is safe.
            current = current.parentNode!
        }
        // let color = seriesModel.getColorFromPalette((current.name || current.dataIndex + ''), paletteScope);
        let name = current.name.isEmpty ? String(Int(current.dataIndex)) : current.name
        var color = seriesModel.getColorFromPalette(name, paletteScope)
        // if (node.depth > 1 && isString(color)) { color = lift(color, (node.depth - 1) / (treeHeight - 1) * 0.5); }
        if Double(node.depth) > 1, case let .color(s)? = color {
            // Lighter on the deeper level.  (`ZRenderKit.color` qualifies the namespace enum, which the
            //   local `color` var would otherwise shadow.)
            if let lifted = ZRenderKit.color.lift(s, (Double(node.depth) - 1) / (treeHeight - 1) * 0.5) {
                color = .color(lifted)
            }
        }
        return color
    }

    ecModel.eachSeriesByType(SERIES_TYPE_SUNBURST) { seriesModelBase, _ in
        let seriesModel = seriesModelBase as! SunburstSeriesModel
        let data = seriesModel.getData()
        // `data.tree` is `Tree?` on SeriesData; present once initTree has run.
        guard let tree = data.tree else { return }

        tree.eachNode({ (node: TreeNode) -> Any? in
            // `getModel()` is nil for the virtual root (dataIndex < 0); skip it, keep descending
            // (return nil = don't suppress children).
            guard let model = node.getModel() else { return nil }
            var style = model.getModel("itemStyle").getItemStyle()

            // if (!style.fill) { style.fill = pickColor(node, seriesModel, tree.root.height); }
            if style["fill"] == nil {
                style["fill"] = pickColor(node, seriesModel, Double(tree.root.height))
            }

            // const existsStyle = data.ensureUniqueItemVisual(node.dataIndex, 'style');
            // zrUtil.extend(existsStyle, style);
            //   Upstream mutates the stored visual `style` object in place; the ported store returns a
            //   value dict, so read → extend → write back (CONVENTIONS §3).
            let dataIndex = Int(node.dataIndex)
            var existsStyle = (data.ensureUniqueItemVisual(dataIndex, "style") as? [String: Any]) ?? [:]
            _ = util.extend(&existsStyle, style)
            data.setItemVisual(dataIndex, "style", existsStyle)
            return nil
        })
    }
}
