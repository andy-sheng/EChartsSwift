// Ported from echarts/src/chart/helper/createSeriesDataSimply.ts — keep in sync with upstream
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
//   import prepareSeriesDataSchema, {PrepareSeriesDataSchemaParams} from '../../data/helper/createDimensions';
//       -> `createDimensions.prepareSeriesDataSchema` + `PrepareSeriesDataSchemaParams`
//          (data/helper/createDimensions.swift).
//   import SeriesData from '../../data/SeriesData';                 -> SeriesData (data/SeriesData.swift).
//   import {extend, isArray} from 'zrender/src/core/util';          -> `util.extend` / `util.isArray` (ZRenderKit).
//   import SeriesModel from '../../model/Series';                   -> SeriesModel (model/Series.swift).

/**
 * [Usage]:
 * (1)
 * createListSimply(seriesModel, ['value']);
 * (2)
 * createListSimply(seriesModel, {
 *     coordDimensions: ['value'],
 *     dimensionsCount: 5
 * });
 */
// upstream default export `createSeriesDataSimply` -> free function (CONVENTIONS §2).
//
// upstream `opt` is the union `PrepareSeriesDataSchemaParams | PrepareSeriesDataSchemaParams['coordDimensions']`
// (i.e. either the schema-params object or the bare `coordDimensions` array). Swift can not express a
// value union in one parameter, so it is split into two overloads that reproduce the two branches of the
// original `isArray(opt) && {...} || extend({...}, opt)` normalization. Both funnel into the shared tail
// `createSeriesDataSimplyImpl`.

// Branch: `opt` is the schema-params object (`isArray(opt)` is false) ->
//   `opt = extend({ encodeDefine: seriesModel.getEncode() }, opt)`.
//   `extend` seeds `encodeDefine` from `getEncode()` and then lets the caller's own keys win; the only
//   key the seed contributes is `encodeDefine` (when the caller did not set it). Modeled by defaulting
//   `encodeDefine` on a copy of `opt` when it is absent (nil).
@discardableResult
public func createSeriesDataSimply(
    _ seriesModel: SeriesModel,
    _ opt: PrepareSeriesDataSchemaParams,
    _ nameList: [String]? = nil
) -> SeriesData {
    var opt = opt
    if opt.encodeDefine == nil {
        opt.encodeDefine = seriesModel.getEncode()
    }
    return createSeriesDataSimplyImpl(seriesModel, opt, nameList)
}

// Branch: `opt` is the bare `coordDimensions` array (`isArray(opt)` is true) ->
//   `opt = { coordDimensions: opt }`. This branch short-circuits before the `extend`, so `encodeDefine`
//   is left unset here (faithful to `isArray(opt) && {coordDimensions: opt}`).
@discardableResult
public func createSeriesDataSimply(
    _ seriesModel: SeriesModel,
    _ opt: [CoordDimensionDefinitionLoose],
    _ nameList: [String]? = nil
) -> SeriesData {
    let params = PrepareSeriesDataSchemaParams(coordDimensions: opt)
    return createSeriesDataSimplyImpl(seriesModel, params, nameList)
}

private func createSeriesDataSimplyImpl(
    _ seriesModel: SeriesModel,
    _ opt: PrepareSeriesDataSchemaParams,
    _ nameList: [String]?
) -> SeriesData {
    let source = seriesModel.getSource()

    // const { dimensions } = prepareSeriesDataSchema(source, opt as PrepareSeriesDataSchemaParams);
    let dimensions = createDimensions.prepareSeriesDataSchema(source, opt).dimensions

    let list = SeriesData(dimensions, seriesModel)
    // upstream `nameList?: string[]` -> the ported `initData` takes `[String?]?`.
    list.initData(source, nameList?.map { $0 as String? })

    return list
}

// export default createSeriesDataSimply;  -> the `createSeriesDataSimply(...)` overloads above.
