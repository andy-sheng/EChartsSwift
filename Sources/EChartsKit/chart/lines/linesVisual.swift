// Ported from echarts/src/chart/lines/linesVisual.ts — keep in sync with upstream
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
//   import { StageHandler } from '../../util/types';                     -> StageHandler (util/types.swift).
//   import SeriesData from '../../data/SeriesData';                      -> SeriesData (data/SeriesData.swift).
//   import LinesSeriesModel, { LinesDataItemOption } from './LinesSeries'; -> sibling LinesSeries.swift.
//   import Model from '../../model/Model';                               -> Model (model/Model.swift).
//   import { LineDataVisual } from '../../visual/commonVisualTypes';
//       -> the visual bag is untyped in the port (SeriesData visuals are `[String: Any]`), so the
//          `SeriesData<LinesSeriesModel, LineDataVisual>` generic collapses to plain `SeriesData`.

// function normalize(a: string | string[]): string[];
// function normalize(a: number | number[]): number[];
// function normalize(a: string | number | (string | number)[]): (string | number)[] {
//     if (!(a instanceof Array)) { a = [a, a]; }
//     return a;
// }
// PORT-NOTE: the two TS overloads are one dynamic implementation; the port keeps the single dynamic
//   form over `Any?` (the option bag is untyped). A non-array scalar (including nil) is duplicated,
//   exactly like `[a, a]`. Identical to the sibling port chart/graph/edgeVisual.swift `normalize`
//   (`as? [Any?]` already matches EVERY Swift/NS array — casts are elementwise and `Any?` accepts any
//   element — so no second array arm is needed).
private func normalize(_ a: Any?) -> [Any?] {
    if let arr = a as? [Any?] {
        return arr
    }
    return [a, a]
}

// const linesVisual: StageHandler = { seriesType, reset }
public let linesVisual: StageHandler = {
    var handler = StageHandler()

    // seriesType: 'lines',
    handler.seriesType = "lines"

    // reset(seriesModel: LinesSeriesModel) { ... }
    handler.reset = { (seriesModelBase: SeriesModel, _ ecModel: GlobalModel, _ api: ExtensionAPI, _ payload: Payload?) -> Any? in
        // upstream typed `seriesModel: LinesSeriesModel`.
        let seriesModel = seriesModelBase

        // const symbolType = normalize(seriesModel.get('symbol'));
        let symbolType = normalize(seriesModel.get("symbol"))
        // const symbolSize = normalize(seriesModel.get('symbolSize'));
        let symbolSize = normalize(seriesModel.get("symbolSize"))
        // const data = seriesModel.getData() as SeriesData<LinesSeriesModel, LineDataVisual>;
        let data = seriesModel.getData()

        // data.setVisual('fromSymbol', symbolType && symbolType[0]);
        // (`symbolType` is always a non-empty array here — `normalize` guarantees 2 entries for a
        //  scalar — so the `&&` guard degenerates to the element read.)
        data.setVisual("fromSymbol", symbolType.count > 0 ? symbolType[0] : nil)
        // data.setVisual('toSymbol', symbolType && symbolType[1]);
        data.setVisual("toSymbol", symbolType.count > 1 ? symbolType[1] : nil)
        // data.setVisual('fromSymbolSize', symbolSize && symbolSize[0]);
        data.setVisual("fromSymbolSize", symbolSize.count > 0 ? symbolSize[0] : nil)
        // data.setVisual('toSymbolSize', symbolSize && symbolSize[1]);
        data.setVisual("toSymbolSize", symbolSize.count > 1 ? symbolSize[1] : nil)

        // function dataEach(data, idx) { ... }
        let dataEach: (SeriesData, Double) -> Void = { (data: SeriesData, idxD: Double) in
            let idx = Int(idxD)
            // const itemModel = data.getItemModel(idx) as Model<LinesDataItemOption>;
            let itemModel = data.getItemModel(idx)
            // const symbolType = normalize(itemModel.getShallow('symbol', true));
            let symbolType = normalize(itemModel.getShallow("symbol", true))
            // const symbolSize = normalize(itemModel.getShallow('symbolSize', true));
            let symbolSize = normalize(itemModel.getShallow("symbolSize", true))

            // symbolType[0] && data.setItemVisual(idx, 'fromSymbol', symbolType[0]);
            if symbolType.count > 0, isTruthy(symbolType[0]) {
                data.setItemVisual(idx, "fromSymbol", symbolType[0])
            }
            // symbolType[1] && data.setItemVisual(idx, 'toSymbol', symbolType[1]);
            if symbolType.count > 1, isTruthy(symbolType[1]) {
                data.setItemVisual(idx, "toSymbol", symbolType[1])
            }
            // symbolSize[0] && data.setItemVisual(idx, 'fromSymbolSize', symbolSize[0]);
            if symbolSize.count > 0, isTruthy(symbolSize[0]) {
                data.setItemVisual(idx, "fromSymbolSize", symbolSize[0])
            }
            // symbolSize[1] && data.setItemVisual(idx, 'toSymbolSize', symbolSize[1]);
            if symbolSize.count > 1, isTruthy(symbolSize[1]) {
                data.setItemVisual(idx, "toSymbolSize", symbolSize[1])
            }
        }

        // return { dataEach: data.hasItemOption ? dataEach : null };
        var executor = StageHandlerProgressExecutor()
        executor.dataEach = data.hasItemOption ? dataEach : nil
        return executor
    }

    return handler
}()

// export default linesVisual;  -> `public let linesVisual` above.

// ─── JS coercion shims (not upstream symbols) ─────────────────────────────────────────────────────

// JS falsy semantics (nil/0/""/false/NaN) for the guarded per-item `x && ...` short-circuits.
// Byte-identical to the sibling shim in chart/graph/edgeVisual.swift (same upstream three lines) —
// same name + same switch form on purpose, so the two symbol-visual ports read identically.
private func isTruthy(_ value: Any?) -> Bool {
    switch value {
    case nil: return false
    case is NSNull: return false
    case let b as Bool: return b
    case let d as Double: return d != 0 && !d.isNaN
    case let i as Int: return i != 0
    case let s as String: return !s.isEmpty
    default: return true
    }
}
