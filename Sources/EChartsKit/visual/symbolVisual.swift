// Ported from echarts/src/visual/symbol.ts — keep in sync with upstream.
// FILE NAMED symbolVisual.swift (not symbol.swift): its basename would collide with util/symbol.swift
//   at the object-file level on case-insensitive APFS — see the swiftpm-port-mechanical-traps note.
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

/// The two symbol-visual stages (upstream `seriesSymbolTask` / `dataSymbolTask`), which populate the
/// data-level and per-item `symbol` / `symbolSize` / `symbolRotate` / `symbolOffset` /
/// `symbolKeepAspect` visuals from the series option. SymbolDraw / Symbol read ONLY these visuals, so
/// this stage is what carries the series `symbolSize: N` (etc.) through to the drawn symbol.
///
/// PORT NOTE: run directly from the symbol views' render (the port invokes visual stages inline, see
///   the slim-visual-stage-ordering note) rather than as Scheduler StageHandlers (Scheduler = sub-project
///   C). Callback (function) symbol props are DEFERRED — only literal option values are encoded.
public enum symbolVisual {

    static let SYMBOL_PROPS_WITH_CB = ["symbol", "symbolSize", "symbolRotate", "symbolOffset"]
    static let SYMBOL_PROPS = ["symbol", "symbolSize", "symbolRotate", "symbolOffset", "symbolKeepAspect"]

    /// upstream: seriesSymbolTask.reset — set the DATA-level symbol visuals from the series option.
    public static func seriesSymbolTask(_ seriesModel: SeriesModel, _ ecModel: GlobalModel? = nil) {
        let data = seriesModel.getData()

        if !seriesModel.legendIcon.isEmpty {
            data.setVisual("legendIcon", seriesModel.legendIcon)
        }

        if !seriesModel.hasSymbolVisual {
            return
        }

        var symbolOptions: [String: Any] = [:]
        var symbolOptionsCb: [String: Any] = [:]
        var hasCallback = false
        for name in SYMBOL_PROPS_WITH_CB {
            let val = seriesModel.get(name)
            if util.isFunction(val) {
                hasCallback = true
                symbolOptionsCb[name] = val
            }
            else if let val = val, !(val is NSNull) {
                symbolOptions[name] = val
            }
        }
        symbolOptions["symbol"] = (symbolOptions["symbol"] as? String) ?? seriesModel.defaultSymbol

        var visualDict = symbolOptions
        visualDict["legendIcon"] = !seriesModel.legendIcon.isEmpty
            ? seriesModel.legendIcon
            : symbolOptions["symbol"]
        if let ka = seriesModel.get("symbolKeepAspect"), !(ka is NSNull) {
            visualDict["symbolKeepAspect"] = ka
        }
        data.setVisual(visualDict)

        // Only visible series has each data be visual encoded
        if let ecModel = ecModel, ecModel.isSeriesFiltered(seriesModel) {
            return
        }

        // upstream: return { dataEach: hasCallback ? dataEach : null };
        // The port runs the visual stage inline (see the slim-visual-stage-ordering note), so the
        //   per-item callback evaluation is executed here rather than returned as a StageHandler.
        if !hasCallback {
            return
        }

        let symbolPropsCb = Array(symbolOptionsCb.keys)
        for idx in 0..<data.count() {
            let rawValue = seriesModel.getRawValue(Double(idx)) ?? NSNull()
            let params = seriesModel.getDataParams(Double(idx))
            for name in symbolPropsCb {
                if let val = evalSymbolCallback(name, symbolOptionsCb[name]!, rawValue, params) {
                    data.setItemVisual(idx, name, val)
                }
            }
        }
    }

    /// Evaluate a function-valued symbol prop against a single data item. Each `SYMBOL_PROPS_WITH_CB`
    /// entry maps to a distinctly-typed callback (upstream `SymbolCallback` / `SymbolSizeCallback` /
    /// `SymbolRotateCallback` / `SymbolOffsetCallback`), so cast per prop name.
    private static func evalSymbolCallback(
        _ name: String, _ cb: Any, _ rawValue: Any, _ params: CallbackDataParams
    ) -> Any? {
        switch name {
        case "symbol":
            return (cb as? SymbolCallback<CallbackDataParams>)?(rawValue, params)
        case "symbolSize":
            return (cb as? SymbolSizeCallback<CallbackDataParams>)?(rawValue, params)
        case "symbolRotate":
            return (cb as? SymbolRotateCallback<CallbackDataParams>)?(rawValue, params)
        case "symbolOffset":
            return (cb as? SymbolOffsetCallback<CallbackDataParams>)?(rawValue, params)
        default:
            return nil
        }
    }

    /// upstream: dataSymbolTask.reset — set PER-ITEM symbol visuals from each item's option.
    public static func dataSymbolTask(_ seriesModel: SeriesModel, _ ecModel: GlobalModel? = nil) {
        if !seriesModel.hasSymbolVisual {
            return
        }
        // Only visible series has each data be visual encoded
        if let ecModel = ecModel, ecModel.isSeriesFiltered(seriesModel) {
            return
        }
        let data = seriesModel.getData()
        if !data.hasItemOption {
            return
        }
        for idx in 0..<data.count() {
            let itemModel = data.getItemModel(idx)
            for name in SYMBOL_PROPS {
                if let val = itemModel.getShallow(name, true), !(val is NSNull) {
                    data.setItemVisual(idx, name, val)
                }
            }
        }
    }
}
