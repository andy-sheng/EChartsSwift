// Ported from echarts/src/chart/helper/LineDraw.ts — keep in sync with upstream.
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
//   import * as graphic from '../../util/graphic';   -> `Group`.
//   import LineGroup from './Line';                   -> `ECLine` (chart/helper/ECLine.swift).
//   import { getLabelStatesModels } from '../../label/labelStyle';   -> `labelStyle.getLabelStatesModels`.
//   import { ILineDraw, ListForLineDraw } from './baseDraw';         -> PORT-NOTE: `baseDraw` NOT ported;
//       `ListForLineDraw` is just `SeriesData` here, and `ILineDraw` collapses onto the concrete class.
//   PORT-NOTE: incremental/progressive mode (incrementalPrepareUpdate / incrementalUpdate /
//       eachRendered / _progressiveEls) is ported (mirroring SymbolDraw). `updateData` /
//       `updateLayout` / `remove` (the merge-mode enter/update/leave DIFF that reuses + tweens each
//       ECLine across a setOption) are ported faithfully.

/// upstream `LineLikeCtor` — the per-edge element factory (default `ECLine`).
public typealias LineLikeCtor = (SeriesData, Int, LineDrawSeriesScope?) -> ECLine

// upstream: class LineDraw implements ILineDraw
//   Conforms to `MarkerDraw` (component/marker/MarkerView.swift) so MarkLineView can host it in the
//   inherited `markerGroupMap: HashMap<MarkerDraw>` (it only needs `var group: Group`).
public final class LineDraw: MarkerDraw {

    // group = new graphic.Group();
    public let group = Group()

    private let _LineCtor: LineLikeCtor
    private var _lineData: SeriesData?
    private var _seriesScope: LineDrawSeriesScope?
    private var _progressiveEls: [ECLine]?

    // upstream: constructor(LineCtor?) { this._LineCtor = LineCtor || LineGroup; }
    public init(_ lineCtor: LineLikeCtor? = nil) {
        self._LineCtor = lineCtor ?? { data, idx, scope in ECLine(data, idx, scope) }
    }

    // upstream: updateData(lineData)
    public func updateData(_ lineData: SeriesData) {
        // Remove progressive els.
        self._progressiveEls = nil

        let group = self.group

        let oldLineData = self._lineData
        self._lineData = lineData

        // There is no oldLineData only when first rendering (or switching stream→normal), where
        //   previous elements should be removed.
        if oldLineData == nil {
            _ = group.removeAll()
        }

        let seriesScope = makeLineDrawSeriesScope(lineData)

        lineData.diff(oldLineData)
            .add({ [weak self] idx in
                self?._doAdd(lineData, idx, seriesScope)
            })
            .update({ [weak self] newIdx, oldIdx in
                self?._doUpdate(oldLineData, lineData, oldIdx, newIdx, seriesScope)
            })
            .remove({ oldIdx in
                if let el = oldLineData?.getItemGraphicEl(oldIdx) {
                    _ = group.remove(el)
                }
            })
            .execute()
    }

    // upstream: updateLayout()
    public func updateLayout() {
        guard let lineData = self._lineData else { return }
        lineData.eachItemGraphicEl({ el, idx in
            (el as? ECLine)?.updateLayout(lineData, idx)
        })
    }

    // upstream: incrementalPrepareUpdate(lineData)
    public func incrementalPrepareUpdate(_ lineData: SeriesData) {
        self._seriesScope = makeLineDrawSeriesScope(lineData)
        self._lineData = nil
        _ = self.group.removeAll()
    }

    // upstream: incrementalUpdate(taskParams, lineData, incrementalId)
    public func incrementalUpdate(
        _ taskParams: StageHandlerProgressParams, _ lineData: SeriesData,
        _ incrementalId: Double
    ) {
        self._progressiveEls = []

        // upstream: function updateIncrementalAndHover(el)
        // PORT-NOTE: HOVER_LAYER_FOR_INCREMENTAL === 2 (util/graphic.ts) is not ported as a named
        //   constant; inlined here (same substitute as SymbolDraw). `isEffectObject` (el has
        //   animators) is unused for the default ECLine and follows SymbolDraw's reduction.
        func updateIncrementalAndHover(_ el: Element) -> Bool {
            if !el.isGroup {
                (el as? Displayable)?.incremental = incrementalId
                el.ensureState("emphasis").hoverLayer = 2
            }
            return false
        }

        let start = Int(taskParams.start)
        let end = Int(taskParams.end)
        for idx in start..<end {
            let itemLayout = lineData.getItemLayout(idx)
            if lineNeedsDraw(itemLayout) {
                let el = self._LineCtor(lineData, idx, self._seriesScope)
                _ = el.traverse(updateIncrementalAndHover)
                _ = self.group.add(el)
                lineData.setItemGraphicEl(idx, el)
                self._progressiveEls?.append(el)
            }
        }
    }

    // upstream: remove() { this.group.removeAll(); }
    public func remove() {
        _ = self.group.removeAll()
    }

    // upstream: eachRendered(cb)
    public func eachRendered(_ cb: (_ el: Element) -> Bool) {
        // upstream: graphic.traverseElements(this._progressiveEls || this.group, cb);
        // PORT-NOTE: `util/graphic.traverseElements` not ported. When `_progressiveEls` exists,
        //   traverse each (progressive mode); otherwise traverse the group via `Group.traverse`
        //   (same substitute as SymbolDraw.eachRendered).
        if let progressiveEls = self._progressiveEls {
            for el in progressiveEls {
                _ = cb(el)
            }
        }
        else {
            _ = self.group.traverse(cb)
        }
    }

    // upstream: _doAdd(lineData, idx, seriesScope)
    private func _doAdd(_ lineData: SeriesData, _ idx: Int, _ seriesScope: LineDrawSeriesScope) {
        let itemLayout = lineData.getItemLayout(idx)
        if !lineNeedsDraw(itemLayout) {
            return
        }
        let el = self._LineCtor(lineData, idx, seriesScope)
        lineData.setItemGraphicEl(idx, el)
        _ = self.group.add(el)
    }

    // upstream: _doUpdate(oldLineData, newLineData, oldIdx, newIdx, seriesScope)
    private func _doUpdate(
        _ oldLineData: SeriesData?, _ newLineData: SeriesData,
        _ oldIdx: Int, _ newIdx: Int, _ seriesScope: LineDrawSeriesScope
    ) {
        var itemEl = oldLineData?.getItemGraphicEl(oldIdx) as? ECLine

        if !lineNeedsDraw(newLineData.getItemLayout(newIdx)) {
            if let itemEl = itemEl { _ = self.group.remove(itemEl) }
            return
        }

        if itemEl == nil {
            itemEl = self._LineCtor(newLineData, newIdx, seriesScope)
        } else {
            itemEl!.updateData(newLineData, newIdx, seriesScope)
        }

        newLineData.setItemGraphicEl(newIdx, itemEl)
        _ = self.group.add(itemEl)
    }
}

// upstream: function makeSeriesScope(lineData): LineDrawSeriesScope
//   Renamed (SymbolDraw already owns a file-scope `makeSeriesScope(SeriesData) -> SymbolDrawSeriesScope`
//   in the same module; overloading a free function by return type alone is ambiguous in Swift).
func makeLineDrawSeriesScope(_ lineData: SeriesData) -> LineDrawSeriesScope {
    var scope = LineDrawSeriesScope()
    guard let hostModel = lineData.hostModel else { return scope }
    let emphasisModel = hostModel.getModel("emphasis")
    scope.lineStyle = hostModel.getModel("lineStyle").getLineStyle()
    scope.emphasisLineStyle = emphasisModel.getModel(["lineStyle"]).getLineStyle()
    scope.blurLineStyle = hostModel.getModel(["blur", "lineStyle"]).getLineStyle()
    scope.selectLineStyle = hostModel.getModel(["select", "lineStyle"]).getLineStyle()
    scope.emphasisDisabled = (emphasisModel.get("disabled") as? Bool) ?? false
    scope.blurScope = (emphasisModel.get("blurScope") as? String).flatMap { BlurScope(rawValue: $0) }
    scope.focus = emphasisModel.get("focus")
    scope.labelStatesModels = labelStyle.getLabelStatesModels(hostModel)
    return scope
}

// upstream: function isPointNaN(pt) / function lineNeedsDraw(pts) — a line is drawable iff its first two
//   endpoints are finite (a curved line's third control point may be absent/NaN).
func lineNeedsDraw(_ ptsIn: Any?) -> Bool {
    guard let outer = ptsIn as? [Any], outer.count >= 2 else {
        if let dd = ptsIn as? [[Double]], dd.count >= 2 {
            return isFinitePoint(dd[0]) && isFinitePoint(dd[1])
        }
        return false
    }
    return isFinitePoint(lineDrawNumArray(outer[0])) && isFinitePoint(lineDrawNumArray(outer[1]))
}

private func isFinitePoint(_ p: [Double]) -> Bool {
    return p.count >= 2 && p[0].isFinite && p[1].isFinite
}

private func lineDrawNumArray(_ v: Any?) -> [Double] {
    if let d = v as? [Double] { return d }
    if let arr = v as? [Any] {
        return arr.map {
            if let d = $0 as? Double { return d }
            if let i = $0 as? Int { return Double(i) }
            if let n = $0 as? NSNumber { return n.doubleValue }
            return Double.nan
        }
    }
    return []
}
