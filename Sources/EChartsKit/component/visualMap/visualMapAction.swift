// Ported from echarts/src/component/visualMap/visualMapAction.ts — keep in sync with upstream
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

// import VisualMapModel from './VisualMapModel';
//   -> PORT-TODO: component/visualMap/VisualMapModel.swift is a SEPARATE (later) port phase; the
//      `setSelected` mutation below is deferred with it.
// import { Payload } from '../../util/types';   -> `Payload` (util/types.swift).
// import GlobalModel from '../../model/Global';  -> `GlobalModel` (model/Global.swift).

// upstream:
//   export const visualMapActionInfo = {
//       type: 'selectDataRange',
//       event: 'dataRangeSelected',
//       // FIXME use updateView appears wrong
//       update: 'update'
//   };
public let visualMapActionInfo: ActionInfo = {
    var info = ActionInfo(type: "selectDataRange")
    info.event = "dataRangeSelected"
    // FIXME use updateView appears wrong
    info.update = "update"
    return info
}()

// upstream:
//   export const visualMapActionHander = function (payload: Payload, ecModel: GlobalModel) {
//       ecModel.eachComponent({mainType: 'visualMap', query: payload}, function (model) {
//           (model as VisualMapModel).setSelected(payload.selected);
//       });
//   };
//
// PORT-TODO (CONVENTIONS §5 — INTERACTION is render-static-only / DEFERRED): `selectDataRange` is the
//   dataZoom-style range-selection action of the visualMap control widget. Its model mutation
//   (`VisualMapModel.setSelected(payload.selected)`) is deferred behind the VisualMapModel port. The
//   `refineEvent`-free handler is kept as the faithful shell so the driver can register the action once
//   VisualMapModel lands. `ecModel.eachComponent({mainType:'visualMap', query: payload}, …)` uses the
//   `QueryConditionKindA` form (mainType + query); `payload.selected` lives in `Payload.other["selected"]`
//   (the dynamic remainder, since `Payload` has no typed `selected` field).
public let visualMapActionHander: ActionHandler = { payload, ecModel, _ in
    ecModel.eachComponent(QueryConditionKindA(mainType: "visualMap", query: payload.other)) { model, _ in
        // (model as VisualMapModel).setSelected(payload.selected);
        // PORT-TODO: VisualMapModel.setSelected DEFERRED (interaction — see the top-of-const PORT-TODO).
        _ = model
    }
    return nil   // upstream returns void
}
