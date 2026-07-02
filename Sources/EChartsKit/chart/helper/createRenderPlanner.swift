// Ported from echarts/src/chart/helper/createRenderPlanner.ts — keep in sync with upstream
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
// import {makeInner} from '../../util/model';                    -> EChartsKit `model.makeInner` (util/modelUtil.swift)
// import SeriesModel from '../../model/Series';                  -> SeriesModel (model/Series.swift)
// import { StageHandlerPlanReturn } from '../../util/types';     -> StageHandlerPlanReturn (util/types.swift; == TaskPlanCallbackReturn)

// const inner = makeInner<{ large: boolean, progressiveRender: boolean }, SeriesModel>();
//   The inline `{}` value bag becomes a `final class` (CONVENTIONS §2 / model.makeInner requires a
//   reference type). Both booleans default to `false` (upstream reads them via `!!`, so `undefined`
//   and `false` are equivalent).
private final class RenderPlannerInner {
    var large: Bool = false
    var progressiveRender: Bool = false
    init() {}
}

/**
 * @return {string} If large mode changed, return string 'reset';
 */
public func createRenderPlanner() -> (SeriesModel) -> StageHandlerPlanReturn? {
    let inner: (SeriesModel) -> RenderPlannerInner = model.makeInner { RenderPlannerInner() }

    return { (seriesModel: SeriesModel) -> StageHandlerPlanReturn? in
        let fields = inner(seriesModel)
        let pipelineContext = seriesModel.pipelineContext

        let originalLarge = fields.large
        let originalProgressive = fields.progressiveRender

        // FIXME: if the planner works on a filtered series, `pipelineContext` does not
        // exists. See #11611 . Probably we need to modify this structure, see the comment
        // on `performRawSeries` in `Schedular.js`.
        let large = (pipelineContext != nil && pipelineContext!.large)
        let progressive = (pipelineContext != nil && pipelineContext!.progressiveRender)
        fields.large = large
        fields.progressiveRender = progressive

        // return !!((originalLarge !== large) || (originalProgressive !== progressive)) && 'reset';
        //   The `&& 'reset'` idiom yields 'reset' when the condition holds, else `false`; the falsy
        //   branch maps to `nil` (see TaskPlanCallbackReturn: 'reset' | false | null | undefined).
        return ((originalLarge != large) || (originalProgressive != progressive)) ? .reset : nil
    }
}
