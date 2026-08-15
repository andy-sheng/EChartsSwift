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
//   ZRImage -> ZRenderKit.ZRImage (an `image://` symbol; `symbol.createSymbol` builds one via
//     ZRenderKit.makeImage, so the child of this Group is `Path | ZRImage` — upstream `ECSymbol`).
//     Everything that must accept BOTH is typed `Displayable` here; the style pass branches on
//     `is ZRImage` exactly like upstream's `symbolPath instanceof ZRImage`.

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

/// upstream: the inline `opt?: { fadeLabel: boolean, animation?: AnimationOption }` of `fadeOut`.
public struct SymbolFadeOutOpt {
    public var fadeLabel: Bool
    public var animation: AnimationOption?
    public init(fadeLabel: Bool = false, animation: AnimationOption? = nil) {
        self.fadeLabel = fadeLabel
        self.animation = animation
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

    /// upstream: `interface SymbolExtended extends SymbolClz { __temp: boolean }` — LineView tags
    ///   symbols it creates ad-hoc for series highlight (LineView.highlight #11360) so `render`/`remove`
    ///   can strip them. Defaults false (a normal SymbolDraw symbol is not temporary).
    public var __temp: Bool = false

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
        // upstream `ECSymbol` = `SymbolPath | SVGPath | ZRImage`; all are Displayables and the props
        //   set below (z2/culling/scale/drift) live on Element/Displayable, so no Path cast here —
        //   an `image://` symbol must reach `add()` too.
        guard let symbolPath = symbolPathEc as? Displayable else { return }

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
    /// PORT-TODO [EChartsKit/SymbolElement.getSymbolPath.ecSymbol]: upstream returns `ECSymbol`
    ///   (`Path | ZRImage`); this accessor keeps its `Path?` return type because every call site wants
    ///   the path style/shape, so it yields nil for an `image://` symbol. Consequence: the Element-level
    ///   consumers (LineView's symbol label fade in/out, circularLayoutHelper's label
    ///   setTextConfig/emphasis, TreeView) silently skip image symbols. The faithful fix is widening
    ///   this to `Displayable?` and adding `as? Path` at the few shape/style consumers; that requires
    ///   a coordinated signature change across four other files, so it is tracked rather than done here.
    ///   No regression: before the ZRImage branch was enabled an `image://` symbol produced no child
    ///   at all, so these call sites already saw nil.
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
        guard let symbolPath = self.childAt(0) as? Displayable else { return }
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
        else if let symbolPath = self.childAt(0) as? Displayable {
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

        if isInit, let symbolPath = self.childAt(0) as? Displayable {
            if !disableAnimation {
                // Always fade in (there is a fadeOut when the symbol is removed).
                var target: [String: Any] = [
                    "scaleX": self._sizeX,
                    "scaleY": self._sizeY
                ]
                if let path = symbolPath as? Path {
                    let opacity = path.pathStyle.opacity ?? 1
                    target["style"] = ["opacity": opacity] as [String: Any]
                    path.pathStyle.opacity = 0
                }
                // PORT-TODO (ZRImage enter fade): upstream also tweens `style.opacity` 0 -> opacity for
                //   an image symbol. ZRenderKit animates `style` through `StyleAnimationAccessor`, which
                //   writes the inherited `Displayable.style` (CommonStyleProps) mirror — the painter reads
                //   `ZRImage.imageStyle.opacity`, so an animated opacity would never reach the pixels and
                //   the image would stay at 0 (invisible). Until ZRImage exposes an imageStyle animation
                //   accessor, image symbols scale in without the opacity tween.
                symbolPath.scaleX = 0
                symbolPath.scaleY = 0
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
        guard let symbolPath = self.childAt(0) as? Displayable else { return }
        // Marker data is hosted by MarkerModel rather than SeriesModel. Both models implement
        // DataFormatMixin/LabelFetcher, and markPoint rich formatter templates need the marker
        // model's name/value/series parameters. Keep SeriesModel for animation, but use the
        // structurally correct label fetcher for label formatting.
        let labelFetcher = data.hostModel as? LabelFetcher

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

        // upstream: `if (symbolPath instanceof ZRImage) { ... } else { ... }`
        if let imagePath = symbolPath as? ZRenderKit.ZRImage {
            // upstream: useStyle(extend({image, x, y, width, height}, symbolStyle)) — the image's own
            //   geometry overlaid with the item visual style bag.
            imagePath.useStyle(symbolImageStyleFromDict(imagePath.imageStyle, symbolStyle))
            // PORT-TODO [ZRenderKit/Image.ZRImage.stateStyleSync]: the emphasis/select/blur state styles
            //   set below (and `toggleHoverEmphasis`) write the inherited `Displayable.style`
            //   (CommonStyleProps), but ZRImage renders from its own `imageStyle` and `_syncCommonStyle`
            //   is one-way (imageStyle -> style), so every state style applied to an image symbol is
            //   silently inert (hover/select on an `image://` symbol renders no change). Same gap
            //   PictorialBarView tracks under this id; the fix belongs in
            //   Sources/ZRenderKit/Graphic/Image.swift (mirror the applied CommonStyleProps subset back
            //   into `imageStyle` before `dirtyStyle()`).
        }
        else if let symbolPath = symbolPath as? Path {
            // upstream branches `__isEmptyBrush` to CLONE symbolStyle before useStyle (an empty symbol
            //   swaps fill/stroke in place, which would corrupt the shared visual-storage object).
            //   `barStyleFromDict` already builds a FRESH `PathStyleProps` value on every call, so the
            //   clone is inherent here and both upstream branches collapse to one.
            symbolPath.useStyle(barStyleFromDict(symbolStyle))
            // upstream (Symbol.ts:296-297): `symbolPath.style.decal = null;`
            //   "Disable decal because symbol scale will been applied on the decal."
            //   FAITHFUL: scatter/symbol series intentionally do NOT texture with a decal (the symbol's
            //   transform scale would distort the tile) — `barStyleFromDict` bridged style.decal above, so
            //   this clears it back to match upstream. Do not remove: it is not a deferral.
            symbolPath.pathStyle.decal = nil
            if let ec = symbolPath as? ECSymbol, let vc = visualColor {
                ec.setColor(.string(vc), opts?.symbolInnerColor)
            }
            symbolPath.pathStyle.strokeNoScale = true
        }

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
        labelOpt.labelFetcher = labelFetcher
        labelOpt.labelDataIndex = Double(idx)
        labelOpt.defaultText = useNameLabel
            ? data.getName(idx)
            : labelHelper.getDefaultLabel(data, Double(idx))
        labelOpt.inheritColor = visualColor
        // `as? Double` alone would silently drop an Int-boxed opacity (the Int-vs-Double option trap).
        labelOpt.defaultOpacity = symbolAsDouble(symbolStyle?["opacity"])
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

    // upstream: fadeOut(cb, seriesModel, opt?: {fadeLabel, animation?}) — remove the symbol with a fade.
    public func fadeOut(_ cb: (() -> Void)? = nil, _ seriesModel: SeriesModel?,
                        _ opt: SymbolFadeOutOpt? = nil) {
        guard let symbolPath = self.childAt(0) as? Displayable else { cb?(); return }
        let dataIndex = innerStore.getECData(self).dataIndex.map { Int($0) } ?? -1
        let animationOpt = opt?.animation
        // Avoid mistaken hover while fading out.
        self.silent = true
        symbolPath.silent = true

        // Not show text when animating.
        if opt?.fadeLabel == true, let textContent = symbolPath.getTextContent() {
            removeElement(
                textContent,
                ["style": ["opacity": 0.0] as [String: Any]],
                seriesModel,
                AnimateOrSetPropsOption(
                    dataIndex: dataIndex,
                    // weak: this closure is stored as the textContent animator's `done`, and the
                    //   textContent is owned by symbolPath — a strong capture would retain the whole
                    //   subtree if the leave animation is ever interrupted (CONVENTIONS §8).
                    cb: { [weak symbolPath] in symbolPath?.removeTextContent() },
                    removeOpt: animationOpt
                )
            )
        }
        else {
            symbolPath.removeTextContent()
        }

        // PORT-TODO [ZRenderKit/Image.ZRImage.stateStyleSync]: for a ZRImage symbol the `style.opacity`
        //   half of these leave props is inert (ZRImage renders from `imageStyle`, and only
        //   Path/Text style animation accessors exist), so an image symbol leaves by scaleX/scaleY -> 0
        //   only. Same tracked gap as the state styles in `_updateCommon` and the enter fade above.
        removeElement(
            symbolPath,
            [
                "style": ["opacity": 0.0] as [String: Any],
                "scaleX": 0.0,
                "scaleY": 0.0
            ],
            seriesModel,
            AnimateOrSetPropsOption(dataIndex: dataIndex, cb: cb, removeOpt: animationOpt)
        )
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

// upstream (Symbol._updateCommon, image branch): `extend({image, x, y, width, height}, symbolStyle)` —
//   the ZRImage's own geometry overlaid with the item visual `style` bag. `symbolStyle` is the untyped
//   visual dict (visual/style.swift) while `ZRImage.useStyle` takes a typed `ImageStyleProps`, so bridge
//   the keys it actually carries. `fill`/`stroke`/`decal` have no counterpart on `ImageStyleProps` (an
//   image symbol is not tinted by the item style — `ZRImage.setColor` is a no-op); upstream copies them
//   onto the style object where the image renderer ignores them, so dropping them is faithful.
//   THE single definition of this bridge: PictorialBarView's `updateCommon` (same upstream expression)
//   calls it too — its private `pbImageStyleFromDict` copy was deleted in favour of this one.
func symbolImageStyleFromDict(_ base: ImageStyleProps?, _ style: Any?) -> ImageStyleProps {
    // Upstream builds a FRESH object literal carrying only the five geometry keys plus whatever
    //   `symbolStyle` supplies and hands it to `useStyle` (which, lacking STYLE_MAGIC_KEY, routes
    //   through `createStyle` -> DEFAULT_IMAGE_STYLE merge), so every prop absent from the new style
    //   resets to its default. Start from a blank `ImageStyleProps` to reproduce that — forwarding only
    //   the geometry, NOT the element's previous common style (which would otherwise stick across
    //   re-renders, e.g. an `opacity: 0.5` never resetting to 1).
    var s = ImageStyleProps()
    s.image = base?.image
    s.x = base?.x
    s.y = base?.y
    s.width = base?.width
    s.height = base?.height
    guard let d = style as? [String: Any] else { return s }
    if let v = symbolAsDouble(d["opacity"]) { s.opacity = v }
    if let v = symbolAsDouble(d["shadowBlur"]) { s.shadowBlur = v }
    if let v = symbolAsDouble(d["shadowOffsetX"]) { s.shadowOffsetX = v }
    if let v = symbolAsDouble(d["shadowOffsetY"]) { s.shadowOffsetY = v }
    if let v = d["shadowColor"] as? String { s.shadowColor = v }
    if let v = d["blend"] as? String { s.blend = v }
    return s
}

// Numeric coercion (defaultOptions box numbers as Int OR Double — the Int-vs-Double trap).
func symbolAsDouble(_ v: Any?) -> Double? {
    if let d = v as? Double { return d }
    if let i = v as? Int { return Double(i) }
    if let n = v as? NSNumber { return n.doubleValue }
    return nil
}
