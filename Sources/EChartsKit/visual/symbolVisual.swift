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
        for name in SYMBOL_PROPS_WITH_CB {
            // isFunction(val) → callback symbol prop, DEFERRED. Literal values are encoded below.
            if let val = seriesModel.get(name), !(val is NSNull) {
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
    }

    /// upstream: dataSymbolTask.reset — set PER-ITEM symbol visuals from each item's option.
    public static func dataSymbolTask(_ seriesModel: SeriesModel) {
        if !seriesModel.hasSymbolVisual {
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
