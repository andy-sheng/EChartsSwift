// Ported from echarts/src/chart/helper/Symbol.ts — keep in sync with upstream.
// FILE NAMED SymbolElement.swift (not Symbol.swift): its basename would collide with util/symbol.swift
//   at the object-file level on case-insensitive APFS (SwiftPM names .o by basename) — see the
//   swiftpm-port-mechanical-traps note. The class is still `Symbol` (identifiers are case-sensitive).
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

// upstream imports resolve to:
//   createSymbol/normalizeSymbolOffset/normalizeSymbolSize -> `symbol.*`
//   graphic (Group/updateProps/initProps/removeElement) -> ZRenderKit.Group + animation/basicTransition
//   getECData -> innerStore.getECData; states (enter/leave/toggleHoverEmphasis) -> `states.*`
//   getDefaultLabel -> labelHelper.getDefaultLabel; setLabelStyle/getLabelStatesModels -> `labelStyle.*`
//   ZRImage branch DEFERRED (image symbols not created by the port's createSymbol yet).

/// upstream: interface SymbolOpts
public struct SymbolOpts {
    public var disableAnimation: Bool?
    public var useNameLabel: Bool?
    public var symbolInnerColor: ZRenderKit.ZRColor?
    public init(disableAnimation: Bool? = nil, useNameLabel: Bool? = nil,
                symbolInnerColor: ZRenderKit.ZRColor? = nil) {
        self.disableAnimation = disableAnimation
        self.useNameLabel = useNameLabel
        self.symbolInnerColor = symbolInnerColor
    }
}

/// upstream: class Symbol extends graphic.Group — a Group wrapping a single symbol Path child.
open class Symbol: Group {

    // upstream `private _symbolType: string` starts undefined → the first updateData sees `isInit` true.
    //   "" is the never-a-real-symbol sentinel.
    private var _symbolType: String = ""

    /// Original (unscaled) half-size — the symbol path's scaleX/scaleY at rest.
    private var _sizeX: Double = 0
    private var _sizeY: Double = 0

    /// liftZ origin (upstream `_z2`): the symbol path's z2 before liftZ was added.
    private var _z2: Double?

    public init(_ data: SeriesData, _ idx: Int,
                _ seriesScope: SymbolDrawSeriesScope? = nil, _ opts: SymbolOpts? = nil) {
        super.init()
        self.updateData(data, idx, seriesScope, opts)
    }

    // upstream: _createSymbol(symbolType, data, idx, symbolSize, z2, keepAspect)
    private func _createSymbol(
        _ symbolType: String, _ data: SeriesData, _ idx: Int,
        _ symbolSize: [Double], _ z2: Double?, _ keepAspect: Bool?
    ) {
        // Remove paths created before.
        _ = self.removeAll()

        // width/height 2 (not 1) — see upstream #4150 (iOS10/Sierra stroke→rect at size 1).
        let symbolPathEc = symbol.createSymbol(symbolType, -1, -1, 2, 2, nil, keepAspect)
        guard let symbolPath = symbolPathEc as? Path else { return }

        symbolPath.z2 = z2 ?? 100          // retrieve2(z2, 100)
        // Port addition (harmless, non-load-bearing): name the symbol path "item" — matches the
        //   per-datum element name BarView/PieView use for hit-testing / debug / render-test lookup.
        symbolPath.name = "item"
        symbolPath.culling = true
        symbolPath.scaleX = symbolSize[0] / 2
        symbolPath.scaleY = symbolSize[1] / 2
        // Rewrite drift: dragging a symbol drifts the whole Symbol group (upstream `driftSymbol`).
        symbolPath.driftHandler = { [weak self] dx, dy, e in self?.drift(dx, dy, e) }

        self._symbolType = symbolType

        _ = self.add(symbolPath)
    }

    /// Stop the symbol path's animation.
    public func stopSymbolAnimation(_ toLastFrame: Bool) {
        _ = self.childAt(0)?.stopAnimation(nil, toLastFrame)
    }

    public func getSymbolType() -> String {
        return self._symbolType
    }

    /// Get the symbol path element (the Group's only child).
    public func getSymbolPath() -> Path? {
        return self.childAt(0) as? Path
    }

    public func highlight() {
        if let c = self.childAt(0) { EChartsKit.states.enterEmphasis(c) }
    }

    public func downplay() {
        if let c = self.childAt(0) { EChartsKit.states.leaveEmphasis(c) }
    }

    public func setZ(_ zlevel: Double, _ z: Double) {
        guard let symbolPath = self.childAt(0) as? Displayable else { return }
        symbolPath.zlevel = zlevel
        symbolPath.z = z
    }

    public func setDraggable(_ draggable: Bool, _ hasCursorOption: Bool = false) {
        guard let symbolPath = self.childAt(0) as? Path else { return }
        symbolPath.draggable = draggable ? .true : .false
        if !hasCursorOption && draggable { symbolPath.cursor = "move" }
    }

    // upstream: updateData(data, idx, seriesScope?, opts?)
    public func updateData(
        _ data: SeriesData, _ idx: Int,
        _ seriesScope: SymbolDrawSeriesScope? = nil, _ opts: SymbolOpts? = nil
    ) {
        self.silent = false

        let symbolType = (data.getItemVisual(idx, "symbol") as? String) ?? "circle"
        let seriesModel = data.hostModel as? SeriesModel
        let symbolSize = Symbol.getSymbolSize(data, idx)
        let z2 = Symbol.getSymbolZ2(data, idx)
        let isInit = symbolType != self._symbolType
        let disableAnimation = opts?.disableAnimation ?? false

        if isInit {
            let keepAspect = data.getItemVisual(idx, "symbolKeepAspect") as? Bool
            self._createSymbol(symbolType, data, idx, symbolSize, z2, keepAspect)
        }
        else if let symbolPath = self.childAt(0) as? Path {
            symbolPath.silent = false
            let target: [String: Any] = ["scaleX": symbolSize[0] / 2, "scaleY": symbolSize[1] / 2]
            if disableAnimation {
                _ = symbolPath.attr(target)
            }
            else {
                updateProps(symbolPath, target, seriesModel, idx)
            }
            saveOldStyle(symbolPath)
        }

        self._updateCommon(data, idx, symbolSize, seriesScope, opts)

        if isInit, let symbolPath = self.childAt(0) as? Path {
            if !disableAnimation {
                // Always fade in (there is a fadeOut when the symbol is removed).
                let opacity = symbolPath.pathStyle.opacity ?? 1
                let target: [String: Any] = [
                    "scaleX": self._sizeX,
                    "scaleY": self._sizeY,
                    "style": ["opacity": opacity] as [String: Any]
                ]
                symbolPath.scaleX = 0
                symbolPath.scaleY = 0
                symbolPath.pathStyle.opacity = 0
                initProps(symbolPath, target, seriesModel, idx)
            }
        }

        if disableAnimation {
            // Must stop the leave transition manually if we don't call initProps/updateProps.
            _ = self.childAt(0)?.stopAnimation("leave")
        }
    }

    // upstream: _updateCommon(data, idx, symbolSize, seriesScope?, opts?)
    private func _updateCommon(
        _ data: SeriesData, _ idx: Int, _ symbolSize: [Double],
        _ seriesScope: SymbolDrawSeriesScope? = nil, _ opts: SymbolOpts? = nil
    ) {
        guard let symbolPath = self.childAt(0) as? Path else { return }
        let seriesModel = data.hostModel as? SeriesModel

        var emphasisItemStyle: [String: Any]?
        var blurItemStyle: [String: Any]?
        var selectItemStyle: [String: Any]?
        var focus: InnerFocus?
        var blurScope: BlurScope?
        var emphasisDisabled = false
        var labelStatesModels: LabelStatesModels = [:]
        var hoverScale: Any?
        var cursorStyle: String?

        if let scope = seriesScope {
            emphasisItemStyle = scope.emphasisItemStyle
            blurItemStyle = scope.blurItemStyle
            selectItemStyle = scope.selectItemStyle
            focus = scope.focus
            blurScope = scope.blurScope
            labelStatesModels = scope.labelStatesModels
            hoverScale = scope.hoverScale
            cursorStyle = scope.cursorStyle
            emphasisDisabled = scope.emphasisDisabled
        }

        if seriesScope == nil || data.hasItemOption {
            let itemModel = (seriesScope?.itemModel) ?? data.getItemModel(idx)
            let emphasisModel = itemModel.getModel("emphasis")

            emphasisItemStyle = emphasisModel.getModel("itemStyle").getItemStyle()
            selectItemStyle = itemModel.getModel(["select", "itemStyle"]).getItemStyle()
            blurItemStyle = itemModel.getModel(["blur", "itemStyle"]).getItemStyle()

            focus = emphasisModel.get("focus")
            blurScope = (emphasisModel.get("blurScope") as? String).flatMap { BlurScope(rawValue: $0) }
            emphasisDisabled = (emphasisModel.get("disabled") as? Bool) ?? false

            labelStatesModels = labelStyle.getLabelStatesModels(itemModel)

            hoverScale = emphasisModel.getShallow("scale")
            cursorStyle = itemModel.getShallow("cursor") as? String
        }

        let symbolRotate = symbolAsDouble(data.getItemVisual(idx, "symbolRotate"))
        symbolPath.rotation = (symbolRotate ?? 0) * Double.pi / 180

        let symbolOffset = symbol.normalizeSymbolOffset(data.getItemVisual(idx, "symbolOffset"), symbolSize)
        if let off = symbolOffset {
            symbolPath.x = off.0
            symbolPath.y = off.1
        }

        if let cursorStyle = cursorStyle {
            symbolPath.cursor = cursorStyle
        }

        let symbolStyle = data.getItemVisual(idx, "style") as? [String: Any]
        let visualColor = symbolColorString(symbolStyle?["fill"])

        // ZRImage branch DEFERRED (createSymbol does not produce images yet). Non-image path:
        symbolPath.useStyle(barStyleFromDict(symbolStyle))
        // Disable decal because the symbol scale would be applied on the decal.
        symbolPath.pathStyle.decal = nil
        if let ec = symbolPath as? ECSymbol, let vc = visualColor {
            ec.setColor(.string(vc), opts?.symbolInnerColor)
        }
        symbolPath.pathStyle.strokeNoScale = true

        let liftZ = symbolAsDouble(data.getItemVisual(idx, "liftZ"))
        let z2Origin = self._z2
        if let liftZ = liftZ {
            if z2Origin == nil {
                self._z2 = symbolPath.z2
                symbolPath.z2 += liftZ
            }
        }
        else if let z2Origin = z2Origin {
            symbolPath.z2 = z2Origin
            self._z2 = nil
        }

        let useNameLabel = opts?.useNameLabel ?? false

        var labelOpt = SetLabelStyleOpt()
        labelOpt.labelFetcher = seriesModel
        labelOpt.labelDataIndex = Double(idx)
        labelOpt.defaultText = useNameLabel
            ? data.getName(idx)
            : labelHelper.getDefaultLabel(data, Double(idx))
        labelOpt.inheritColor = visualColor
        labelOpt.defaultOpacity = symbolStyle?["opacity"] as? Double
        labelStyle.setLabelStyle(symbolPath, labelStatesModels, labelOpt)

        self._sizeX = symbolSize[0] / 2
        self._sizeY = symbolSize[1] / 2

        let emphasisState = symbolPath.ensureState("emphasis")
        emphasisState.style = emphasisItemStyle
        symbolPath.ensureState("select").style = selectItemStyle
        symbolPath.ensureState("blur").style = blurItemStyle

        // null / undefined / true → default strategy; 0 / false / negative / NaN / Infinity → no scale.
        let scaleRatio: Double
        if hoverScale == nil || (hoverScale as? Bool) == true {
            scaleRatio = Swift.max(1.1, 3 / self._sizeY)
        }
        else if let n = symbolAsDouble(hoverScale), n.isFinite, n > 0 {
            scaleRatio = n
        }
        else {
            scaleRatio = 1
        }
        // Always set scale to allow resetting.
        emphasisState.scaleX = self._sizeX * scaleRatio
        emphasisState.scaleY = self._sizeY * scaleRatio

        self.setSymbolScale(1)

        EChartsKit.states.toggleHoverEmphasis(self, focus, blurScope, emphasisDisabled)
    }

    public func setSymbolScale(_ scale: Double) {
        self.scaleX = scale
        self.scaleY = scale
    }

    // upstream: fadeOut(cb, seriesModel, opt?) — remove the symbol with a fade.
    //   PORT NOTE: the port's shared leave helper `removeElementWithFadeOut` fades OPACITY only
    //   (upstream also animates scaleX/scaleY → 0). The scale-to-0 part is deferred with the broader
    //   removeElement port; under the current render-reset model the leave path is not reachable
    //   (SymbolDraw always hits the diff .add branch), so opacity-fade is sufficient for now.
    public func fadeOut(_ cb: @escaping () -> Void, _ seriesModel: SeriesModel?, _ fadeLabel: Bool = false) {
        guard let symbolPath = self.childAt(0) as? Path else { cb(); return }
        // Avoid mistaken hover while fading out.
        self.silent = true
        symbolPath.silent = true

        symbolPath.removeTextContent()

        let dataIndex = innerStore.getECData(self).dataIndex.map { Int($0) } ?? -1
        removeElementWithFadeOut(symbolPath, seriesModel, dataIndex)
        cb()
    }

    // upstream: static getSymbolSize(data, idx) -> normalizeSymbolSize(...) as [w, h]
    public static func getSymbolSize(_ data: SeriesData, _ idx: Int) -> [Double] {
        let (w, h) = symbol.normalizeSymbolSize(data.getItemVisual(idx, "symbolSize") ?? 10.0)
        return [w, h]
    }
    // upstream: static getSymbolZ2(data, idx) -> data.getItemVisual(idx, 'z2')
    public static func getSymbolZ2(_ data: SeriesData, _ idx: Int) -> Double? {
        return symbolAsDouble(data.getItemVisual(idx, "z2"))
    }
}

// Bridge an item-visual `fill` (String or EChartsKit `ZRColor.color`) to a solid colour string.
func symbolColorString(_ v: Any?) -> String? {
    if let str = v as? String { return str }
    if let zr = v as? EChartsKit.ZRColor, case let .color(str) = zr { return str }
    return nil
}

// Numeric coercion (defaultOptions box numbers as Int OR Double — the Int-vs-Double trap).
func symbolAsDouble(_ v: Any?) -> Double? {
    if let d = v as? Double { return d }
    if let i = v as? Int { return Double(i) }
    if let n = v as? NSNumber { return n.doubleValue }
    return nil
}
