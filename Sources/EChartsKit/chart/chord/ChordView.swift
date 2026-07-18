// Ported (STATIC SUBSET) from echarts/src/chart/chord/ChordView.ts — keep in sync with upstream.
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
//   import * as graphic from '../../util/graphic';
//       -> `initProps` (first-render grow-in scale animation) and `removeElementWithFadeOut` (fade-out of
//          removed pieces/edges on the data.diff remove path) — both from animation/basicTransition.swift.
//   import ChartView from '../../view/Chart';                      -> ChartView (view/Chart.swift).
//   import GlobalModel from '../../model/Global';                  -> GlobalModel.
//   import ExtensionAPI from '../../core/ExtensionAPI';            -> ExtensionAPI.
//   import SeriesData from '../../data/SeriesData';                -> SeriesData.
//   import ChordSeriesModel, { SERIES_TYPE_CHORD } from './ChordSeries';
//       -> sibling ChordSeries.swift (assumed ported alongside — provides `ChordSeriesModel` /
//          `SERIES_TYPE_CHORD` / `getData` / `getEdgeData`). ChordSeriesModel.getInitialData builds the
//          Graph via createGraphFromNodeEdge (like SankeySeries / GraphSeries).
//   import ChordPiece from './ChordPiece';                         -> sibling ChordPiece.swift (Sector arc).
//   import { ChordEdge } from './ChordEdge';                       -> sibling ChordEdge.swift (ribbon Path).
//   import { parsePercent } from '../../util/number';
//       -> number.parsePercent (util/number.swift) — first-render scale-animation center origin. See render().
//   import { getECData } from '../../util/innerStore';
//       -> innerStore.getECData (util/innerStore.swift); wired below to tag each piece/edge `dataIndex`.

// upstream: const RADIAN = Math.PI / 180;
private let RADIAN: Double = Double.pi / 180

// ================================================================================================
// upstream: class ChordView extends ChartView
//   A COORDLESS (coordinateSystem 'none') view. It renders one `ChordPiece` (a Sector arc) per graph
//   node and one `ChordEdge` (a bezier ribbon between two arcs) per graph edge, reading each element's
//   geometry from the layout stage (chordLayout) and its color from the node/edge visuals.
// ================================================================================================
open class ChordView: ChartView {

    // upstream: static readonly type = SERIES_TYPE_CHORD;  /  readonly type = SERIES_TYPE_CHORD;
    public static let chordType = SERIES_TYPE_CHORD
    open override var type: String {
        get { SERIES_TYPE_CHORD }
        set { /* readonly upstream */ }
    }

    // upstream: private _data: SeriesData;  private _edgeData: SeriesData;
    //   The previous render's node/edge data, retained so `data.diff(oldData)` can reuse element
    //   instances (enter/update/remove) and fade out removed pieces/edges. Also used to detect the
    //   first render (`if (!oldData)` — the grow-in scale animation below).
    private var _data: SeriesData?
    private var _edgeData: SeriesData?

    // upstream: init(ecModel: GlobalModel, api: ExtensionAPI) {}  — empty upstream.
    open override func init_(_ ecModel: GlobalModel, _ api: ExtensionAPI) {
    }

    // upstream: render(seriesModel: ChordSeriesModel, ecModel: GlobalModel, api: ExtensionAPI)
    open override func render(
        _ seriesModelBase: SeriesModel, _ ecModel: GlobalModel, _ api: ExtensionAPI, _ payload: Payload
    ) {
        // upstream typed `seriesModel: ChordSeriesModel`; the base override is typed `SeriesModel`.
        let seriesModel = seriesModelBase as! ChordSeriesModel

        // const data = seriesModel.getData();
        let data: SeriesData = seriesModel.getData()
        // const oldData = this._data;
        let oldData = self._data
        // const group = this.group;
        let group = self.group

        // const startAngle = -seriesModel.get('startAngle') * RADIAN;
        //   TRAP #1: the `startAngle` option is stored as a bare Int/Double/NSNumber in the `[String: Any]`
        //   default bag; a bare `as? Double` would silently drop an Int. Coerce all three (default 90 per
        //   ChordSeries.defaultOption → 90 * RADIAN when genuinely absent).
        let startAngle = -(chordNum(seriesModel.get("startAngle", false)) ?? 90) * RADIAN

        // ------------------------------------------------------------------------------------------
        // STATIC render deviation: upstream drives `data.diff(oldData).add/update/remove(...).execute()`
        //   to enter/update/remove `ChordPiece`s (reusing element instances + fade-out on removal). The
        //   diff + `removeElementWithFadeOut` + `updateData` reuse are DEFERRED (CONVENTIONS §5), so the
        //   group is rebuilt from scratch each render: one `ChordPiece` per node that HAS a layout.
        //
        //   The `if (layout)` guard is faithful (and load-bearing): upstream only creates a piece when the
        //   node has a layout. Consider two nodes A, B with one link: if a node is deselected from the
        //   legend there is nothing to display for it, so chordLayout leaves its layout undefined and the
        //   piece must be skipped (upstream comment on `.add` / `.update`).
        // ------------------------------------------------------------------------------------------
        // data.diff(oldData).add(...).update(...).remove(...).execute();
        //   Enter/update/remove `ChordPiece`s, REUSING element instances across renders and FADING OUT
        //   removed pieces (`removeElementWithFadeOut`). `ChordPiece.updateData` registers the reused
        //   element via `data.setItemGraphicEl`, so the next render's diff recovers it through
        //   `oldData.getItemGraphicEl`.
        data.diff(oldData)
            .add { newIdx in
                // Consider the case when there are only two nodes A and B, and there is a link between A
                // and B. At first, they are both disselected from legend. And then when A is selected, A
                // will go into `add`. But since there are no edges to be displayed, A should not be added.
                // So we should only add A when layout is defined.
                // const layout = data.getItemLayout(newIdx);
                let layout = data.getItemLayout(newIdx)
                // if (layout) { const el = new ChordPiece(data, newIdx, startAngle); ... group.add(el); }
                if chordTruthy(layout) {
                    let el = ChordPiece(data, newIdx, startAngle)
                    // getECData(el).dataIndex = newIdx;
                    //   (ChordPiece.updateData already tags the same value; set it here too to mirror
                    //   upstream's view-level tagging so hover/tooltip/highlight resolve the chord datum.)
                    innerStore.getECData(el).dataIndex = Double(newIdx)
                    _ = group.add(el)
                }
            }
            .update { newIdx, oldIdx in
                // let el = oldData.getItemGraphicEl(oldIdx) as ChordPiece;
                var el = oldData?.getItemGraphicEl(oldIdx) as? ChordPiece
                // const layout = data.getItemLayout(newIdx);
                let layout = data.getItemLayout(newIdx)
                // Consider the case when there are only two nodes A and B, and there is a link between A
                // and B, and when A is disselected from legend, there should be nothing to display. But in
                // `data.diff`, B will go into `update` having no layout. In this case, we need to remove B.
                // if (!layout) { el && graphic.removeElementWithFadeOut(el, seriesModel, oldIdx); return; }
                if !chordTruthy(layout) {
                    if let el = el {
                        removeElementWithFadeOut(el, seriesModel, oldIdx)
                    }
                    return
                }
                // if (!el) { el = new ChordPiece(data, newIdx, startAngle); }
                // else { el.updateData(data, newIdx, startAngle); }
                if el == nil {
                    el = ChordPiece(data, newIdx, startAngle)
                }
                else {
                    el!.updateData(data, newIdx, startAngle)
                }
                // group.add(el);
                if let el = el {
                    _ = group.add(el)
                }
            }
            .remove { oldIdx in
                // const el = oldData.getItemGraphicEl(oldIdx) as ChordPiece;
                // el && graphic.removeElementWithFadeOut(el, seriesModel, oldIdx);
                if let el = oldData?.getItemGraphicEl(oldIdx) {
                    removeElementWithFadeOut(el, seriesModel, oldIdx)
                }
            }
            .execute()

        // if (!oldData) { ... first-render grow-in scale animation ... }
        //   On the first render the whole group grows in from a near-zero scale about the chord center.
        //   `initProps` tweens scaleX/scaleY 0.01 -> 1 (and settles to the final scale immediately when the
        //   series' animation is disabled / in the static frame, so no visual regression there).
        if oldData == nil {
            // const center = seriesModel.get('center');
            let center = (seriesModel.get("center") as? [Any]) ?? []
            // this.group.scaleX = 0.01; this.group.scaleY = 0.01;
            self.group.scaleX = 0.01
            self.group.scaleY = 0.01
            // this.group.originX = parsePercent(center[0], api.getWidth());
            self.group.originX = number.parsePercent(center.count > 0 ? center[0] : nil, api.getWidth())
            // this.group.originY = parsePercent(center[1], api.getHeight());
            self.group.originY = number.parsePercent(center.count > 1 ? center[1] : nil, api.getHeight())
            // graphic.initProps(this.group, { scaleX: 1, scaleY: 1 }, seriesModel);
            initProps(self.group, ["scaleX": 1.0, "scaleY": 1.0], seriesModel)
        }

        // this._data = data;
        self._data = data

        // this.renderEdges(seriesModel, startAngle);
        self.renderEdges(seriesModel, startAngle)
    }

    // upstream: renderEdges(seriesModel: ChordSeriesModel, startAngle: number)
    open func renderEdges(_ seriesModel: ChordSeriesModel, _ startAngle: Double) {
        // const nodeData = seriesModel.getData();
        let nodeData: SeriesData = seriesModel.getData()
        // const edgeData = seriesModel.getEdgeData();
        let edgeData: SeriesData = seriesModel.getEdgeData()
        // const oldData = this._edgeData;
        let oldData = self._edgeData
        // const group = this.group;
        let group = self.group

        // edgeData.diff(oldData).add(...).update(...).remove(...).execute();
        //   Enter/update/remove `ChordEdge` ribbons, REUSING element instances and FADING OUT removed
        //   edges. `ChordEdge.updateData` registers the reused element via `edgeData.setItemGraphicEl`,
        //   so the next render's diff recovers it through `oldData.getItemGraphicEl`. Edges are added
        //   after the node pieces so they paint over (matching z-order via `ChordPiece.z2 = 2`).
        edgeData.diff(oldData)
            .add { newIdx in
                // const el = new ChordEdge(nodeData, edgeData, newIdx, startAngle);
                let el = ChordEdge(nodeData, edgeData, newIdx, startAngle)
                // getECData(el).dataIndex = newIdx;
                //   (ChordEdge already tags the same value; set it here too to mirror upstream's
                //   view-level tagging so hover/tooltip/highlight resolve the chord edge datum.)
                innerStore.getECData(el).dataIndex = Double(newIdx)
                _ = group.add(el)
            }
            .update { newIdx, oldIdx in
                // const el = oldData.getItemGraphicEl(oldIdx) as ChordEdge;
                // el.updateData(nodeData, edgeData, newIdx, startAngle); group.add(el);
                if let el = oldData?.getItemGraphicEl(oldIdx) as? ChordEdge {
                    el.updateData(nodeData, edgeData, newIdx, startAngle)
                    _ = group.add(el)
                }
            }
            .remove { oldIdx in
                // const el = oldData.getItemGraphicEl(oldIdx) as ChordEdge;
                // el && graphic.removeElementWithFadeOut(el, seriesModel, oldIdx);
                if let el = oldData?.getItemGraphicEl(oldIdx) {
                    removeElementWithFadeOut(el, seriesModel, oldIdx)
                }
            }
            .execute()

        // this._edgeData = edgeData;
        self._edgeData = edgeData
    }

    // upstream: dispose() {}  — empty upstream.
    open override func dispose(_ ecModel: GlobalModel, _ api: ExtensionAPI) {
    }

    // The base `ChartView.remove(ecModel, api)` clears the group; chord has no bespoke `remove` upstream,
    //   but the static render owns `this.group` directly (no _mainGroup), so clear it + reset the diff
    //   bookkeeping so the next render is treated as a first render.
    open override func remove(_ ecModel: GlobalModel, _ api: ExtensionAPI) {
        _ = self.group.removeAll()
        self._data = nil
        self._edgeData = nil
    }
}

// export default ChordView;  -> `open class ChordView` above.

// ---- STATIC-port helpers (not upstream functions) --------------------------------------------------

// TRAP #1 GUARD: numeric option coercion (`Int|Double|NSNumber -> Double?`) is provided by the shared
//   module-scope `chordNum` in ChordPiece.swift (reused here to avoid an identical redeclaration).

// JS truthiness for the `if (layout)` guard: a layout is present when `getItemLayout` returns a non-nil,
//   non-NSNull value (upstream `if (layout)` — `undefined`/`null` are the only falsy cases the layout
//   stage produces; a `[String: Any]` shape dict is always truthy).
private func chordTruthy(_ v: Any?) -> Bool {
    switch v {
    case nil: return false
    case is NSNull: return false
    default: return true
    }
}
