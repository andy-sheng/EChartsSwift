// Ported from echarts/src/chart/helper/SymbolDraw.ts — keep in sync with upstream.
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

// PORT SCOPE (L2): SymbolDraw + Symbol (the shared per-point symbol renderer with data.diff
//   add/update/remove). DEFERRED: LargeSymbolDraw (large-mode incremental renderer) and the
//   incremental pipeline (incrementalPrepareUpdate/incrementalUpdate/eachRendered) — those wait on
//   the Scheduler task graph (sub-project C). `updateData` / `updateLayout` / `remove` are ported.

/// A clip shape gate for symbolNeedsDraw (upstream `opt.clipShape.contain(x, y)`).
public protocol SymbolClipShape {
    func contain(_ x: Double, _ y: Double) -> Bool
}

/// upstream: SymbolDrawUpdateOpt (subset — the fields SymbolDraw consumes).
public struct SymbolDrawUpdateOpt {
    public var disableAnimation: Bool?
    public var isIgnore: ((Int) -> Bool)?
    public var clipShape: SymbolClipShape?
    public var getSymbolPoint: ((Int) -> [Double]?)?
    public init(disableAnimation: Bool? = nil, isIgnore: ((Int) -> Bool)? = nil,
                clipShape: SymbolClipShape? = nil, getSymbolPoint: ((Int) -> [Double]?)? = nil) {
        self.disableAnimation = disableAnimation
        self.isIgnore = isIgnore
        self.clipShape = clipShape
        self.getSymbolPoint = getSymbolPoint
    }
}

/// upstream: interface SymbolDrawSeriesScope — the per-series style/state bag computed once per update.
public struct SymbolDrawSeriesScope {
    public var emphasisItemStyle: [String: Any]?
    public var blurItemStyle: [String: Any]?
    public var selectItemStyle: [String: Any]?
    public var focus: InnerFocus?
    public var blurScope: BlurScope?
    public var emphasisDisabled: Bool = false
    public var labelStatesModels: LabelStatesModels = [:]
    public var itemModel: Model?
    public var hoverScale: Any?
    public var cursorStyle: String?
    public var fadeIn: Bool?
    public init() {}
}

/// A factory for the symbol element (upstream `SymbolLikeCtor`, default `SymbolClz`).
public typealias SymbolLikeCtor = (SeriesData, Int, SymbolDrawSeriesScope?, SymbolOpts?) -> Symbol

// upstream: function symbolNeedsDraw(data, point, idx, opt)
func symbolNeedsDraw(_ data: SeriesData, _ point: [Double]?, _ idx: Int, _ opt: SymbolDrawUpdateOpt?) -> Bool {
    guard let point = point, point.count >= 2, !point[0].isNaN, !point[1].isNaN else {
        return false
    }
    if let isIgnore = opt?.isIgnore, isIgnore(idx) {
        return false
    }
    // We use the same clip shape as the line clip (do NOT set clipShape on the group — it would cut
    //   part of the symbol shape).
    if let clip = opt?.clipShape, !clip.contain(point[0], point[1]) {
        return false
    }
    return (data.getItemVisual(idx, "symbol") as? String) != "none"
}

// upstream: function makeSeriesScope(data)
func makeSeriesScope(_ data: SeriesData) -> SymbolDrawSeriesScope {
    let seriesModel = data.hostModel
    let emphasisModel = seriesModel?.getModel("emphasis")
    var scope = SymbolDrawSeriesScope()
    scope.emphasisItemStyle = emphasisModel?.getModel("itemStyle").getItemStyle()
    scope.blurItemStyle = seriesModel?.getModel(["blur", "itemStyle"]).getItemStyle()
    scope.selectItemStyle = seriesModel?.getModel(["select", "itemStyle"]).getItemStyle()
    scope.focus = emphasisModel?.get("focus")
    scope.blurScope = (emphasisModel?.get("blurScope") as? String).flatMap { BlurScope(rawValue: $0) }
    scope.emphasisDisabled = (emphasisModel?.get("disabled") as? Bool) ?? false
    scope.hoverScale = emphasisModel?.get("scale")
    if let seriesModel = seriesModel {
        scope.labelStatesModels = labelStyle.getLabelStatesModels(seriesModel)
    }
    scope.cursorStyle = seriesModel?.get("cursor") as? String
    return scope
}

// upstream: function createEl(SymbolCtor, data, newIdx, seriesScope, symbolUpdateOpt, point, group)
@discardableResult
func createEl(
    _ symbolCtor: SymbolLikeCtor, _ data: SeriesData, _ newIdx: Int,
    _ seriesScope: SymbolDrawSeriesScope?, _ symbolUpdateOpt: SymbolOpts?,
    _ point: [Double], _ group: Group
) -> Symbol {
    let symbolEl = symbolCtor(data, newIdx, seriesScope, symbolUpdateOpt)
    symbolEl.setPosition(point)
    data.setItemGraphicEl(newIdx, symbolEl)
    _ = group.add(symbolEl)
    return symbolEl
}

// upstream: class SymbolDraw implements ISymbolDraw
public final class SymbolDraw {
    public let group = Group()

    private var _data: SeriesData?
    private let _symbolCtor: SymbolLikeCtor
    private var _seriesScope: SymbolDrawSeriesScope?
    private var _getSymbolPoint: ((Int) -> [Double]?)?

    /// upstream `constructor(SymbolCtor?)` — default factory is `Symbol`.
    public init(_ symbolCtor: SymbolLikeCtor? = nil) {
        self._symbolCtor = symbolCtor ?? { data, idx, scope, opts in Symbol(data, idx, scope, opts) }
    }

    /// upstream: updateData(data, opt?) — diff old→new and add/update/remove symbols.
    public func updateData(_ data: SeriesData, _ opt: SymbolDrawUpdateOpt? = nil) {
        let opt = opt ?? SymbolDrawUpdateOpt()

        let group = self.group
        let seriesModel = data.hostModel as? SeriesModel
        let oldData = self._data
        let symbolCtor = self._symbolCtor
        let disableAnimation = opt.disableAnimation

        let seriesScope = makeSeriesScope(data)
        self._seriesScope = seriesScope

        let symbolUpdateOpt = SymbolOpts(disableAnimation: disableAnimation)

        let getSymbolPoint: (Int) -> [Double]? = opt.getSymbolPoint ?? { idx in
            data.getItemLayout(idx) as? [Double]
        }

        // No oldData only on first render (or stream→normal switch): drop previous elements.
        if oldData == nil {
            _ = group.removeAll()
        }

        data.diff(oldData)
            .add({ newIdx in
                let point = getSymbolPoint(newIdx)
                if let point = point, symbolNeedsDraw(data, point, newIdx, opt) {
                    createEl(symbolCtor, data, newIdx, seriesScope, symbolUpdateOpt, point, group)
                }
            })
            .update({ newIdx, oldIdx in
                var symbolEl = oldData?.getItemGraphicEl(oldIdx) as? Symbol

                let point = getSymbolPoint(newIdx)
                if !symbolNeedsDraw(data, point, newIdx, opt) {
                    if let symbolEl = symbolEl { _ = group.remove(symbolEl) }
                    return
                }
                let point2 = point!
                let newSymbolType = (data.getItemVisual(newIdx, "symbol") as? String) ?? "circle"
                let oldSymbolType = symbolEl?.getSymbolType()

                if symbolEl == nil || (oldSymbolType != nil && oldSymbolType != newSymbolType) {
                    // Create a new one if the symbol type changed.
                    if let symbolEl = symbolEl { _ = group.remove(symbolEl) }
                    let newEl = symbolCtor(data, newIdx, seriesScope, symbolUpdateOpt)
                    newEl.setPosition(point2)
                    symbolEl = newEl
                }
                else {
                    symbolEl!.updateData(data, newIdx, seriesScope, symbolUpdateOpt)
                    let target: [String: Any] = ["x": point2[0], "y": point2[1]]
                    if disableAnimation == true {
                        _ = symbolEl!.attr(target)
                    }
                    else {
                        updateProps(symbolEl!, target, seriesModel)
                    }
                }

                // Add back.
                if let symbolEl = symbolEl {
                    _ = group.add(symbolEl)
                    data.setItemGraphicEl(newIdx, symbolEl)
                }
            })
            .remove({ oldIdx in
                if let el = oldData?.getItemGraphicEl(oldIdx) as? Symbol {
                    el.fadeOut({ _ = group.remove(el) }, seriesModel)
                }
            })
            .execute()

        self._getSymbolPoint = getSymbolPoint
        self._data = data
    }

    /// upstream: updateLayout(opt?) — reposition existing symbols (create/remove for clip changes).
    public func updateLayout(_ opt: SymbolDrawUpdateOpt? = nil) {
        guard let data = self._data else { return }
        let store = data.getStore()
        for idx in 0..<store.count() {
            var el = data.getItemGraphicEl(idx) as? Symbol
            let point = self._getSymbolPoint?(idx)

            if let point = point, symbolNeedsDraw(data, point, idx, opt) {
                if el == nil {
                    el = createEl(self._symbolCtor, data, idx, self._seriesScope,
                                  SymbolOpts(disableAnimation: true), point, self.group)
                }
                _ = el?.stopAnimation()
                el?.setPosition(point)
                el?.markRedraw()
            }
            else if let el = el {
                _ = self.group.remove(el)
                data.setItemGraphicEl(idx, nil)
            }
        }
    }

    /// upstream: remove(enableAnimation?)
    public func remove(_ enableAnimation: Bool = false) {
        let group = self.group
        let data = self._data
        if let data = data, enableAnimation {
            let seriesModel = data.hostModel as? SeriesModel
            data.eachItemGraphicEl({ el, _ in
                if let sym = el as? Symbol {
                    sym.fadeOut({ _ = group.remove(sym) }, seriesModel)
                }
            })
        }
        else {
            _ = group.removeAll()
        }
    }
}
