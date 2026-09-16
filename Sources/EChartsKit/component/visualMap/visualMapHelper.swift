// Ported from echarts/src/component/visualMap/helper.ts — keep in sync with upstream
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

// import * as zrUtil from 'zrender/src/core/util';        -> `util.each` (ZRenderKit).
// import {getLayoutRect} from '../../util/layout';        -> `layout.getLayoutRect` (util/layout.swift).
// import VisualMapModel from './VisualMapModel';
//   -> note: VisualMapModel is ported (component/visualMap/VisualMapModel.swift). BOTH
//      helpers below hard-depend on it (`visualMapModel.option`, `.padding`, `.componentIndex`); they are
//      reproduced (module-internal) in ContinuousView.swift and used live, so the copy here is reference source.
// import ExtensionAPI from '../../core/ExtensionAPI';      -> `ExtensionAPI` (core/ExtensionAPI.swift).
// import { Payload } from '../../util/types';              -> `Payload` (util/types.swift).

// const paramsSet = [
//     ['left', 'right', 'width'],
//     ['top', 'bottom', 'height']
// ] as const;
// consumed by `getItemAlign` (reproduced in ContinuousView.swift; the copy below is reference source).
let visualMapParamsSet: [[String]] = [
    ["left", "right", "width"],
    ["top", "bottom", "height"]
]
// export type ItemHorizontalAlign = typeof paramsSet[0][number];  -> 'left' | 'right' | 'width'
public typealias ItemHorizontalAlign = String
// export type ItemVerticalAlign = typeof paramsSet[1][number];    -> 'top' | 'bottom' | 'height'
public typealias ItemVerticalAlign = String
// export type ItemAlign = ItemVerticalAlign | ItemHorizontalAlign;
public typealias ItemAlign = String

/**
 * @param visualMapModel
 * @param api
 * @param itemSize always [short, long]
 * @return {string} 'left' or 'right' or 'top' or 'bottom'
 */
// getItemAlign is reproduced (module-internal) in ContinuousView.swift and used live; VisualMapModel
//   is ported. Faithful upstream source preserved here for reference. It reads
//   `modelOption.align`, `.orient`, the `paramsSet` position keys, and `.padding`, then runs
//   `layout.getLayoutRect(layoutInput, ecSize, modelOption.padding)` and compares the mid-point of the
//   laid-out rect against the container mid-point to auto-pick the side.
//
//   export function getItemAlign(
//       visualMapModel: VisualMapModel,
//       api: ExtensionAPI,
//       itemSize: number[]
//   ): ItemAlign {
//       const modelOption = visualMapModel.option;
//       const itemAlign = modelOption.align;
//
//       if (itemAlign != null && itemAlign !== 'auto') {
//           return itemAlign as ItemAlign;
//       }
//
//       // Auto decision align.
//       const ecSize = {width: api.getWidth(), height: api.getHeight()};
//       const realIndex = modelOption.orient === 'horizontal' ? 1 : 0;
//
//       const reals = paramsSet[realIndex];
//       const fakeValue = [0, null, 10];
//
//       const layoutInput = {} as Record<ItemAlign, number | string>;
//       for (let i = 0; i < 3; i++) {
//           layoutInput[paramsSet[1 - realIndex][i]] = fakeValue[i];
//           layoutInput[reals[i]] = i === 2 ? itemSize[0] : modelOption[reals[i]];
//       }
//
//       const rParam = ([['x', 'width', 3], ['y', 'height', 0]] as const)[realIndex];
//       const rect = getLayoutRect(layoutInput, ecSize, modelOption.padding);
//
//       return reals[
//           (rect.margin[rParam[2]] || 0) + rect[rParam[0]] + rect[rParam[1]] * 0.5
//               < ecSize[rParam[1]] * 0.5 ? 0 : 1
//       ];
//   }

/**
 * Prepare dataIndex for outside usage, where dataIndex means rawIndex, and
 * dataIndexInside means filtered index.
 */
// `makeHighDownBatch` is reproduced (module-internal) in ContinuousView.swift and used live;
//   VisualMapModel is ported. It rewrites a highlight/downplay `Payload['batch']`, moving `dataIndex` to
//   `dataIndexInside` and stamping a `highlightKey` derived from `visualMapModel.componentIndex`. It is
//   part of the hover-indicator interaction path (wired in ContinuousView.swift). In the Swift `Payload`/`PayloadItem` model
//   the `dataIndex`/`dataIndexInside`/`highlightKey` fields live in the dynamic `other` bag. Faithful
//   upstream source preserved:
//
//    // TODO: TYPE more specified payload types.
//    export function makeHighDownBatch(batch: Payload['batch'], visualMapModel: VisualMapModel): Payload['batch'] {
//        zrUtil.each(batch || [], function (batchItem) {
//            if (batchItem.dataIndex != null) {
//                batchItem.dataIndexInside = batchItem.dataIndex;
//                batchItem.dataIndex = null;
//            }
//            batchItem.highlightKey = 'visualMap' + (visualMapModel ? visualMapModel.componentIndex : '');
//        });
//        return batch;
//    }
