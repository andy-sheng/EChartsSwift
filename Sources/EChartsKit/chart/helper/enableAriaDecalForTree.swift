// Ported from echarts/src/chart/helper/enableAriaDecalForTree.ts — keep in sync with upstream.
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
//   import SeriesModel from '../../model/Series';
//   import {Dictionary, DecalObject} from '../../util/types';
//   import { getDecalFromPalette } from '../../model/mixin/palette';   -> `getDecalFromPalette`.
//
// The palette scope is an anonymous `{}` used purely as the palette WeakMap identity key
//   (upstream `const decalPaletteScope: Dictionary<DecalObject> = {}`). Swift needs a reference type
//   for the identity key — a fresh empty class instance per invocation (see ariaVisual's AriaDecalScope).
private final class AriaDecalTreeScope {}

/// upstream: export default function enableAriaDecalForTree(seriesModel: SeriesModel)
///
/// Assigns a palette decal to every node of a tree-structured series (treemap/sunburst): each node
/// inherits the decal of its depth-1 ancestor (so a whole top-level branch shares one texture). Wired
/// from the series' `enableAriaDecal()` override, which the aria decal stage (`aria.setDecal`) calls in
/// place of the flat-data palette assignment when `aria.decal.show` is enabled.
public func enableAriaDecalForTree(_ seriesModel: SeriesModel) {
    let data = seriesModel.getData()
    // upstream: const tree = data.tree;
    guard let tree = data.tree, let ecModel = seriesModel.ecModel else {
        return
    }
    // upstream: const decalPaletteScope: Dictionary<DecalObject> = {};
    let decalPaletteScope = AriaDecalTreeScope()

    // upstream: tree.eachNode(node => { ... });  (a bare callback → default preorder traversal)
    tree.eachNode({ (node: TreeNode) -> Any? in
        // upstream:
        //   // Use decal of level 1 node
        //   let current = node;
        //   while (current && current.depth > 1) { current = current.parentNode; }
        var current: TreeNode? = node
        while let c = current, c.depth > 1 {
            current = c.parentNode
        }
        guard let cur = current else {
            return nil
        }

        // upstream: getDecalFromPalette(seriesModel.ecModel, current.name || current.dataIndex + '', decalPaletteScope);
        let name = !cur.name.isEmpty ? cur.name : String(cur.dataIndex)
        let decal = getDecalFromPalette(ecModel, name, decalPaletteScope)
        // upstream: node.setVisual('decal', decal);
        node.setVisual("decal", decal)
        return nil
    })
}
