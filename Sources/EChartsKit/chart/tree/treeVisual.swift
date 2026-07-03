// Ported from echarts/src/chart/tree/treeVisual.ts — keep in sync with upstream
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
//   import GlobalModel from '../../model/Global';                            -> GlobalModel (model/Global.swift).
//   import { createSimpleOverallStageHandler } from '../../util/model';      -> `model.createSimpleOverallStageHandler`.
//   import TreeSeriesModel, { SERIES_TYPE_TREE, TreeSeriesNodeItemOption } from './TreeSeries';
//       -> sibling TreeSeries.swift (SERIES_TYPE_TREE / TreeSeriesModel). TreeSeriesNodeItemOption is
//          the node option type only used for `getModel<T>()` generics — dropped (getModel() is untyped).
//   import { extend } from 'zrender/src/core/util';                          -> `util.extend`.

// upstream:
//   export const treeVisualStageHandler = createSimpleOverallStageHandler(SERIES_TYPE_TREE, treeVisual);
// `treeVisual` is `(ecModel)` (1-arg); the handler expects `(GlobalModel, ExtensionAPI, Payload?)`.
// Adapt with a thin wrapper that drops the extra args, keeping `treeVisual` byte-faithful (1-arg)
// (same deviation as sunburstVisualStageHandler).
public let treeVisualStageHandler = model.createSimpleOverallStageHandler(
    SERIES_TYPE_TREE,
    { ecModel, _, _ in treeVisual(ecModel) }
)

func treeVisual(_ ecModel: GlobalModel) {

    ecModel.eachSeriesByType(SERIES_TYPE_TREE) { seriesModelBase, _ in
        let seriesModel = seriesModelBase as! TreeSeriesModel
        let data = seriesModel.getData()
        // `data.tree` is `Tree?` on SeriesData; present once initTree has run.
        guard let tree = data.tree else { return }
        tree.eachNode({ (node: TreeNode) -> Any? in
            // `getModel()` is nil for the virtual root (dataIndex < 0); skip it, keep descending
            // (return nil = don't suppress children).
            guard let model = node.getModel() else { return nil }
            // TODO Optimize
            let style = model.getModel("itemStyle").getItemStyle()
            // const existsStyle = data.ensureUniqueItemVisual(node.dataIndex, 'style');
            // extend(existsStyle, style);
            //   Upstream mutates the stored visual `style` object in place; the ported store returns a
            //   value dict, so read → extend → write back (CONVENTIONS §3), mirroring sunburstVisual.
            var existsStyle = (data.ensureUniqueItemVisual(node.dataIndex, "style") as? [String: Any]) ?? [:]
            _ = util.extend(&existsStyle, style)
            data.setItemVisual(node.dataIndex, "style", existsStyle)
            return nil
        })
    }
}
