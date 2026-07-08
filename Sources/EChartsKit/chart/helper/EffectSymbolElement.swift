// Ported from echarts/src/chart/helper/EffectSymbol.ts — keep in sync with upstream.
// FILE NAMED EffectSymbolElement.swift (mirrors SymbolElement.swift): the class is still `EffectSymbol`
//   (identifiers are case-sensitive); the distinctive basename avoids any object-file collision on
//   case-insensitive APFS — see the swiftpm-port-mechanical-traps note.
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
//   createSymbol -> `symbol.createSymbol`
//   graphic (Group) -> ZRenderKit.Group; enterEmphasis/leaveEmphasis -> `states.*`
//   Symbol (the base per-point Group) -> chart/helper/SymbolElement.swift (class Symbol).
//   ScatterSeriesModel/EffectScatterSeriesModel -> read via the generic SeriesModel option bag.

// upstream: interface EffectCfg — the ripple config computed once per updateData and cached as `_effectCfg`.
struct EffectSymbolCfg: Equatable {
    var showEffectOn: String
    var rippleScale: Double
    var brushType: String
    var period: Double       // upstream stores period * 1000 (seconds → ms)
    var effectOffset: Double
    var z: Double
    var zlevel: Double
    var symbolType: String
    var color: String?
    var rippleEffectColor: String?
    var rippleNumber: Int
}

// upstream: function updateRipplePath(rippleGroup, effectCfg) — re-apply z/zlevel + fill/stroke to every
//   ripple ring already in the group (used by both start- and update-EffectAnimation).
private func updateRipplePath(_ rippleGroup: Group, _ effectCfg: EffectSymbolCfg) {
    _ = rippleGroup.eachChild { child, _ in
        guard let ripplePath = child as? Path else { return }
        ripplePath.z = effectCfg.z
        ripplePath.zlevel = effectCfg.zlevel
        let c = effectCfg.color.map { ZRenderKit.ZRColor.string($0) }
        // upstream: style.stroke = brushType === 'stroke' ? color : null; fill = 'fill' ? color : null.
        ripplePath.pathStyle.stroke = effectCfg.brushType == "stroke" ? c : nil
        ripplePath.pathStyle.fill = effectCfg.brushType == "fill" ? c : nil
        // Prior port: a stroke ripple needs a visible line width (createSymbol leaves it defaulted); keep
        //   the lineWidth the earlier inline ripple used so the stroke variant stays visible.
        if effectCfg.brushType == "stroke" { ripplePath.pathStyle.lineWidth = 1 }
    }
}

/// upstream: class EffectSymbol extends Symbol — the base symbol Group (childAt 0 = the symbol Path)
///   PLUS a second child Group (childAt 1) holding `rippleEffect.number` animated expanding rings.
open class EffectSymbol: Symbol {

    // upstream instance field `_effectCfg: EffectCfg` — nil until the first ripple is built.
    private var _effectCfg: EffectSymbolCfg?

    // upstream: constructor(data, idx) { super(data, idx); const rippleGroup = new Group(); this.add(
    //   rippleGroup); this.updateData(data, idx); }
    //   NOTE: super.init (Symbol.init) calls self.updateData, which dynamically dispatches to
    //   EffectSymbol.updateData BEFORE the rippleGroup child exists — the `childAt(1)` guard there makes
    //   that first pass a no-op (only the base symbol is built). The rippleGroup is added afterwards and a
    //   second updateData builds the rings — faithful to the upstream constructor ordering.
    public override init(_ data: SeriesData, _ idx: Int,
                         _ seriesScope: SymbolDrawSeriesScope? = nil, _ opts: SymbolOpts? = nil) {
        super.init(data, idx, seriesScope, opts)
        let rippleGroup = Group()
        _ = self.add(rippleGroup)
        self.updateData(data, idx, seriesScope, opts)
    }

    // upstream: stopEffectAnimation() { (this.childAt(1) as graphic.Group).removeAll(); }
    func stopEffectAnimation() {
        _ = (self.childAt(1) as? Group)?.removeAll()
    }

    // upstream: startEffectAnimation(effectCfg) — build `rippleNumber` unit (2x2) ripple rings, each at
    //   scale 0.5, LOOPING-animated to rippleScale/2 with a staggered negative delay while opacity → 0.
    func startEffectAnimation(_ effectCfg: EffectSymbolCfg) {
        guard let rippleGroup = self.childAt(1) as? Group else { return }
        let symbolType = effectCfg.symbolType
        let color = effectCfg.color.map { ZRenderKit.ZRColor.string($0) }
        let rippleNumber = effectCfg.rippleNumber

        for i in 0..<rippleNumber {
            // 2x2 unit symbol centered at local origin (upstream createSymbol(symbolType, -1, -1, 2, 2)).
            guard let ripplePath = symbol.createSymbol(symbolType, -1, -1, 2, 2, color) as? Path else { continue }
            ripplePath.name = "ripple"

            // upstream: ripplePath.attr({ style: { strokeNoScale: true }, z2: 99, silent: true,
            //   scaleX: 0.5, scaleY: 0.5 }).
            var style = PathStyleProps()
            style.strokeNoScale = true   // keep lineWidth constant as the transform scale grows
            style.opacity = 1
            ripplePath.useStyle(style)
            ripplePath.z2 = 99
            ripplePath.silent = true     // don't intercept hover/hit-testing meant for the base symbol
            ripplePath.scaleX = 0.5
            ripplePath.scaleY = 0.5

            // upstream: delay = -i / rippleNumber * period (a per-ring NEGATIVE stagger); effectOffset
            //   staggers whole points against each other.
            let delay = -Double(i) / Double(rippleNumber) * effectCfg.period + effectCfg.effectOffset
            _ = ripplePath.animate("", true)
                .when(effectCfg.period, ["scaleX": effectCfg.rippleScale / 2,
                                         "scaleY": effectCfg.rippleScale / 2])
                .delay(delay)
                .start()
            _ = ripplePath.animate("style", true)
                .when(effectCfg.period, ["opacity": 0.0])
                .delay(delay)
                .start()

            _ = rippleGroup.add(ripplePath)
        }

        updateRipplePath(rippleGroup, effectCfg)
    }

    // upstream: updateEffectAnimation(effectCfg) — reinitialize only if a "difficult" prop changed,
    //   otherwise just re-apply z/fill/stroke via updateRipplePath.
    func updateEffectAnimation(_ effectCfg: EffectSymbolCfg) {
        guard let old = self._effectCfg, let rippleGroup = self.childAt(1) as? Group else { return }
        // DIFFICULT_PROPS = ['symbolType', 'period', 'rippleScale', 'rippleNumber'].
        if old.symbolType != effectCfg.symbolType
            || old.period != effectCfg.period
            || old.rippleScale != effectCfg.rippleScale
            || old.rippleNumber != effectCfg.rippleNumber {
            self.stopEffectAnimation()
            self.startEffectAnimation(effectCfg)
            return
        }
        updateRipplePath(rippleGroup, effectCfg)
    }

    // upstream: highlight()/downplay() — enter/leave emphasis on the WHOLE group (not just childAt(0)),
    //   so the ripple rings dim with the base symbol.
    public override func highlight() {
        EChartsKit.states.enterEmphasis(self)
    }
    public override func downplay() {
        EChartsKit.states.leaveEmphasis(self)
    }

    // upstream: updateData(data, idx) {
    //     const seriesModel = data.hostModel;
    //     Symbol.prototype.updateData.call(this, data, idx);
    //     const rippleGroup = this.childAt(1);
    //     ... build effectCfg, set rippleGroup scale/offset ...
    //     if (effectCfg.showEffectOn === 'render') { _effectCfg ? updateEffectAnimation : startEffectAnimation }
    //     else { stopEffectAnimation(); onHoverStateChange = ... }
    // }
    public override func updateData(
        _ data: SeriesData, _ idx: Int,
        _ seriesScope: SymbolDrawSeriesScope? = nil, _ opts: SymbolOpts? = nil
    ) {
        // Base symbol (childAt 0) — colour/label/emphasis-hover-scale/rotate/offset all handled here.
        super.updateData(data, idx, seriesScope, opts)

        // During the super.init pass the rippleGroup child does not exist yet — bail (base symbol only).
        guard let rippleGroup = self.childAt(1) as? Group else { return }

        let seriesModel = data.hostModel as? SeriesModel
        let itemModel = data.getItemModel(idx)
        let symbolType = (data.getItemVisual(idx, "symbol") as? String) ?? "circle"
        let symbolSize = Symbol.getSymbolSize(data, idx)          // [w, h]
        let symbolStyle = data.getItemVisual(idx, "style") as? [String: Any]
        let color = symbolColorString(symbolStyle?["fill"])

        // upstream: rippleGroup.setScale(symbolSize) — the rings live in a group scaled to the symbol size.
        rippleGroup.scaleX = symbolSize[0]
        rippleGroup.scaleY = symbolSize[1]

        // upstream: if (symbolOffset) { rippleGroup.x/y = symbolOffset }.
        if let off = symbol.normalizeSymbolOffset(data.getItemVisual(idx, "symbolOffset"), symbolSize) {
            rippleGroup.x = off.0
            rippleGroup.y = off.1
        }

        let rippleEffectModel = itemModel.getModel("rippleEffect")
        // NOTE (int-vs-double option-read trap): rippleEffect numbers may box as Int OR Double — route
        //   through symbolAsDouble so an integer-literal user override (e.g. number: 5) is not dropped.
        let effectCfg = EffectSymbolCfg(
            showEffectOn: (seriesModel?.get("showEffectOn") as? String) ?? "render",
            rippleScale: symbolAsDouble(rippleEffectModel.get("scale")) ?? 2.5,
            brushType: (rippleEffectModel.get("brushType") as? String) ?? "fill",
            period: (symbolAsDouble(rippleEffectModel.get("period")) ?? 4) * 1000,   // seconds → ms
            effectOffset: Double(idx) / Double(Swift.max(1, data.count())),
            z: symbolAsDouble(seriesModel?.getShallow("z")) ?? 0,
            zlevel: symbolAsDouble(seriesModel?.getShallow("zlevel")) ?? 0,
            symbolType: symbolType,
            color: color,
            rippleEffectColor: rippleEffectModel.get("color") as? String,
            rippleNumber: Int(symbolAsDouble(rippleEffectModel.get("number")) ?? 3)
        )

        if effectCfg.showEffectOn == "render" {
            if self._effectCfg != nil {
                self.updateEffectAnimation(effectCfg)
            } else {
                self.startEffectAnimation(effectCfg)
            }
            self._effectCfg = effectCfg
        } else {
            // Not playing on render — clear cache and stop.
            self._effectCfg = nil
            self.stopEffectAnimation()
            // PORT-TODO: upstream also registers onHoverStateChange to start/stop the ripple on
            //   emphasis in/out when showEffectOn === 'emphasis'. The hover-triggered ripple is DEFERRED
            //   (matches the previous inline port, which only built ripples for the 'render' gate).
        }
    }
}

// export default EffectSymbol;  -> `open class EffectSymbol` above.
