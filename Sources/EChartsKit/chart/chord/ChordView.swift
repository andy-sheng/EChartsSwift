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
//       -> only used for the first-render grow-in scale animation (initProps) — DEFERRED. See render().
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
//       -> only used by the DEFERRED first-render scale animation (center origin). See render().
//   import { getECData } from '../../util/innerStore';
//       -> PORT-NOTE: innerStore (getECData/ECData) is ported; the ECData `dataIndex` tagging is not wired in this view yet.

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
    //   Kept for parity with upstream's diff bookkeeping. The `data.diff(oldData)` incremental
    //   enter/update/remove is DEFERRED (CONVENTIONS §5 — static render); the group is rebuilt from
    //   scratch each pass, so these are only used to detect the first render (see below).
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
        _ = group.removeAll()

        for newIdx in 0..<data.count() {
            // const layout = data.getItemLayout(newIdx);
            let layout = data.getItemLayout(newIdx)
            // if (layout) { const el = new ChordPiece(data, newIdx, startAngle); ... group.add(el); }
            if chordTruthy(layout) {
                let el = ChordPiece(data, newIdx, startAngle)
                // getECData(el).dataIndex = newIdx;  — PORT-NOTE: innerStore (ECData) is ported; tagging not wired here yet.
                _ = group.add(el)
            }
        }

        // if (!oldData) { ... first-render grow-in scale animation ... }
        //   PORT-TODO: the first-render scale-up animation is DEFERRED (CONVENTIONS §5 — animation).
        //   Upstream sets group.scaleX/scaleY = 0.01, origin = parsePercent(center[0/1], api.width/height),
        //   then `graphic.initProps(group, { scaleX: 1, scaleY: 1 }, seriesModel)` tweens it to full size.
        //   util/graphic.initProps + parsePercent-driven origin are not wired here; the group renders at
        //   its final scale immediately. Reinstate with the animation system + initProps.
        _ = oldData

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
        // const group = this.group;
        let group = self.group

        // ------------------------------------------------------------------------------------------
        // STATIC render deviation (same as render above): upstream drives `edgeData.diff(oldData)
        //   .add/update/remove(...).execute()`. The diff + `removeElementWithFadeOut` + `updateData`
        //   reuse are DEFERRED — one `ChordEdge` (ribbon) is rebuilt per edge each pass. The node pieces
        //   were already re-added by render(); the edges are added after them (upstream adds edges last,
        //   so they paint over — matching z-order via `ChordPiece.z2 = 2`).
        // ------------------------------------------------------------------------------------------
        for newIdx in 0..<edgeData.count() {
            // const el = new ChordEdge(nodeData, edgeData, newIdx, startAngle);
            let el = ChordEdge(nodeData, edgeData, newIdx, startAngle)
            // getECData(el).dataIndex = newIdx;  — PORT-NOTE: innerStore (ECData) is ported; tagging not wired here yet.
            _ = group.add(el)
        }

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
