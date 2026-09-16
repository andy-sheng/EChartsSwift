// Ported from echarts/src/chart/sankey/SankeySeries.ts — keep in sync with upstream
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
//   import SeriesModel from '../../model/Series';                     -> SeriesModel (model/Series.swift).
//   import createGraphFromNodeEdge from '../helper/createGraphFromNodeEdge';
//       -> the sibling free function `createGraphFromNodeEdge` (chart/helper/createGraphFromNodeEdge.swift) —
//          ALREADY PORTED; reused exactly like GraphSeries.getInitialData does.
//   import Model from '../../model/Model';                            -> Model (model/Model.swift).
//   import { ... } from '../../util/types';                           -> type-only; the dynamic option tree is
//       the `[String: Any]` bag per CONVENTIONS §2. The interface/type declarations (SankeyNodeStateOption,
//       SankeyEdgeStateOption, SankeyBothStateOption, SankeyEdgeStyleOption, ExtraStateOption,
//       SankeyNodeItemOption, SankeyEdgeItemOption, SankeyLevelOption, SankeySeriesOption, …) describe the
//       option tree — kept as documentation only, no Swift types emitted.
//   import GlobalModel from '../../model/Global';                     -> GlobalModel (model/Global.swift).
//   import SeriesData from '../../data/SeriesData';                   -> SeriesData (data/SeriesData.swift).
//   import { LayoutRect } from '../../util/layout';                   -> `LayoutRect` (== BoundingRect alias,
//       coord/cartesian/cartesianAxisHelper.swift; real util/layout.swift LayoutRect deferred).
//   import { createTooltipMarkup } from '../../component/tooltip/tooltipMarkup';
//       -> createTooltipMarkup (component/tooltip/tooltipMarkup.swift); used by formatTooltip below.
//   import type View from '../../coord/View';                         -> TODO: requires coord/View.ts
//       (the box `View` coordinate system + roam are not ported); `coordinateSystem` uses the inherited `Any?`.
//   import tokens from '../../visual/tokens';
//       -> note: visual/tokens.swift IS ported, but the consumed values are inlined verbatim in
//          `defaultOption` (tokens.color.neutral50 = '#86878c', tokens.color.primary = neutral80 = '#3c3c41').

// export const SERIES_TYPE_SANKEY = 'sankey';
public let SERIES_TYPE_SANKEY = "sankey"

// upstream: class SankeySeriesModel extends SeriesModel<SankeySeriesOption> implements RoamHostModel
open class SankeySeriesModel: SeriesModel {

    // static readonly type = 'series.' + SERIES_TYPE_SANKEY;
    // readonly type = SankeySeriesModel.type;
    //   The static drives the instance `type` (inherited `var type { Self.type }` from ComponentModel).
    public override class var type: ComponentFullType { return "series." + SERIES_TYPE_SANKEY }

    // static layoutMode = 'box' as const;
    open override class var layoutMode: Any? { return "box" }

    // coordinateSystem: View;
    //   TODO: upstream types `coordinateSystem: View`; requires coord/View.ts (not ported),
    //   so the inherited `open var coordinateSystem: Any?` slot (model/Series.swift) is used unchanged.

    // levelModels: Model<SankeyLevelOption>[];
    //   upstream is a SPARSE array indexed by node depth (`levelModels[levels[i].depth] = …`,
    //   read back as `levelModels[nodeDepth]` with an `if (levelModel)` presence guard). A sparse JS array
    //   with gaps behaves like a keyed map, so it is modeled as `[Int: Model]` (missing depth == undefined),
    //   which reproduces the index-by-depth semantics exactly.
    public var levelModels: [Int: Model] = [:]

    // layoutInfo: LayoutRect;
    //   Written by sankeyLayout (separate stage); typed optional here (unset until layout runs).
    public var layoutInfo: LayoutRect?

    /**
     * Init a graph data structure from data in option series
     */
    // getInitialData(option: SankeySeriesOption, ecModel: GlobalModel) { ... }
    open override func getInitialData(_ option: ModelOption?, _ ecModel: GlobalModel?) -> SeriesData? {
        let opt = option as? [String: Any]

        // const links = option.edges || option.links || [];
        //   JS `||` — arrays (even empty) are truthy, only nil/undefined falls through, so `??` matches.
        let links: OptionSourceDataOriginal = (opt?["edges"] as? [Any]) ?? (opt?["links"] as? [Any]) ?? []
        // const nodes = option.data || option.nodes || [];
        let nodes: OptionSourceDataOriginal = (opt?["data"] as? [Any]) ?? (opt?["nodes"] as? [Any]) ?? []
        // const levels = option.levels || [];
        let levels: [Any] = (opt?["levels"] as? [Any]) ?? []
        // this.levelModels = [];
        self.levelModels = [:]
        // const levelModels = this.levelModels;

        // for (let i = 0; i < levels.length; i++) {
        for i in 0..<levels.count {
            let levelItem = levels[i] as? [String: Any]
            let depth = sankeyNum(levelItem?["depth"])
            // if (levels[i].depth != null && levels[i].depth >= 0) {
            if depth != nil && depth! >= 0 {
                // levelModels[levels[i].depth] = new Model(levels[i], this, ecModel);
                self.levelModels[Int(depth!)] = Model(levelItem, self, ecModel)
            }
            else {
                // if (__DEV__) { throw new Error('levels[i].depth is mandatory and should be natural number'); }
                // __DEV__ guard — the throw is dropped in release-equivalent builds.
            }
        }

        // const graph = createGraphFromNodeEdge(nodes, links, this, true, beforeLink);
        let graph = createGraphFromNodeEdge(nodes, links, self, true, self.beforeLink)
        // return graph.data;
        return graph.data
    }

    // function beforeLink(nodeData: SeriesData, edgeData: SeriesData) { ... }
    //   Hoisted in upstream; a stored closure here. Captures `self` for `levelModels` / `getGraph`.
    private func beforeLink(_ nodeData: SeriesData, _ edgeData: SeriesData) {
        // nodeData.wrapMethod('getItemModel', function (model: Model, idx: number) {
        //     const seriesModel = model.parentModel as SankeySeriesModel;
        //     const layout = seriesModel.getData().getItemLayout(idx);
        //     if (layout) {
        //         const nodeDepth = layout.depth;
        //         const levelModel = seriesModel.levelModels[nodeDepth];
        //         if (levelModel) { model.parentModel = levelModel; }
        //     }
        //     return model;
        // });
        //   SeriesData.getItemModel now fires these injections with `[model, idx]` and threads the returned
        //   Model, so reparenting a node's item model onto its per-depth `levelModels[depth]` entry takes
        //   effect (a node inherits its level's `itemStyle`). `idx` arrives as a Double (arg 1).
        nodeData.wrapMethod("getItemModel") { [weak self] args in
            guard let self = self, let model = args.first as? Model else { return args.first as Any? }
            let idx = Int((args.count > 1 ? (args[1] as? Double) : nil) ?? 0)
            // const layout = seriesModel.getData().getItemLayout(idx);
            if let layout = self.getData().getItemLayout(idx) as? [String: Any],
               let nodeDepth = sankeyNum(layout["depth"]) {
                // const levelModel = seriesModel.levelModels[nodeDepth];
                if let levelModel = self.levelModels[Int(nodeDepth)] {
                    model.parentModel = levelModel
                }
            }
            return model
        }

        // edgeData.wrapMethod('getItemModel', function (model: Model, idx: number) {
        //     const seriesModel = model.parentModel as SankeySeriesModel;
        //     const edge = seriesModel.getGraph().getEdgeByIndex(idx);
        //     const layout = edge.node1.getLayout();
        //     if (layout) {
        //         const depth = layout.depth;
        //         const levelModel = seriesModel.levelModels[depth];
        //         if (levelModel) { model.parentModel = levelModel; }
        //     }
        //     return model;
        // });
        //   An edge inherits the level of its SOURCE node (`edge.node1`), so `edge.getModel().get('lineStyle')`
        //   returns that level's `lineStyle` (e.g. `{color:'source', opacity:0.6}`) — read by sankeyVisual.
        edgeData.wrapMethod("getItemModel") { [weak self] args in
            guard let self = self, let model = args.first as? Model else { return args.first as Any? }
            let idx = Int((args.count > 1 ? (args[1] as? Double) : nil) ?? 0)
            // const edge = seriesModel.getGraph().getEdgeByIndex(idx);
            let edge = self.getGraph().getEdgeByIndex(idx)
            // const layout = edge.node1.getLayout();
            if let layout = edge?.node1.getLayout() as? [String: Any],
               let depth = sankeyNum(layout["depth"]) {
                if let levelModel = self.levelModels[Int(depth)] {
                    model.parentModel = levelModel
                }
            }
            return model
        }
    }

    // setNodePosition(dataIndex: number, localPosition: number[]) { ... }
    open func setNodePosition(_ dataIndex: Int, _ localPosition: [Double]) {
        // const nodes = this.option.data || this.option.nodes;
        let optionBag = (self.option as? [String: Any])
        // Upstream mutates the raw option node item in place; the dynamic bag stores the nodes array as
        //   `[Any]` of `[String: Any]` items. Read → mutate the item dict → write the array back
        //   (CONVENTIONS §3 value-type write-back).
        let key: String = (optionBag?["data"] != nil) ? "data" : "nodes"
        guard var nodes = optionBag?[key] as? [Any],
              dataIndex >= 0, dataIndex < nodes.count,
              var dataItem = nodes[dataIndex] as? [String: Any] else { return }
        // dataItem.localX = localPosition[0];
        dataItem["localX"] = localPosition[0]
        // dataItem.localY = localPosition[1];
        dataItem["localY"] = localPosition[1]
        nodes[dataIndex] = dataItem
        var newOption = optionBag ?? [:]
        newOption[key] = nodes
        self.option = newOption

        // PORT bridge: upstream's option write above is visible to the render because the raw data provider
        //   shares that SAME `option.data` array by reference. Swift value-type semantics break that link, so
        //   also write localX/localY THROUGH to the provider's raw item — otherwise `node.getModel().get(
        //   'localX')` (read by SankeyView.render for both the node rect AND its incident edge endpoints)
        //   still returns the pre-drag value and the node would not move. `dataIndex` is the raw option index.
        self.getData().setRawDataItemField(dataIndex, "localX", localPosition[0])
        self.getData().setRawDataItemField(dataIndex, "localY", localPosition[1])
    }

    /**
     * Return the graphic data structure
     *
     * @return graphic data structure
     */
    // getGraph() { return this.getData().graph; }
    open func getGraph() -> Graph {
        // SeriesData.graph is typed `AnyObject?` (see data/SeriesData.swift); force-unwrap to
        //   the ported Graph — faithful to upstream's non-optional `this.getData().graph` return. The
        //   invariant holds: createGraphFromNodeEdge (getInitialData) always sets graph for sankey.
        return self.getData().graph!
    }

    /**
     * Get edge data of graphic data structure
     *
     * @return data structure of list
     */
    // getEdgeData() { return this.getGraph().edgeData; }
    open func getEdgeData() -> SeriesData {
        return self.getGraph().edgeData
    }

    // Phase 45: route `getData(.edge)` to the edge data (upstream `data.getLinkedData(dataType)`), so the
    //   states engine's object-focus branch resolves edge dispatchers against the EDGE data.
    open override func getData(_ dataType: SeriesDataType? = nil) -> SeriesData {
        if dataType == .edge { return getEdgeData() }
        return super.getData(dataType)
    }

    // formatTooltip(dataIndex, multipleSeries, dataType: 'node' | 'edge') { ... }
    open override func formatTooltip(
        _ dataIndex: Double,
        _ multipleSeries: Bool? = nil,
        _ dataType: SeriesDataType? = nil
    ) -> TooltipFormatResult? {
        _ = multipleSeries
        // function noValue(val): boolean { return isNaN(val as number) || val == null; }
        func noValue(_ val: Any?) -> Bool {
            guard let val = val, !(val is NSNull) else { return true }
            let m = Mirror(reflecting: val)
            if m.displayStyle == .optional && m.children.isEmpty { return true }
            if let d = val as? Double { return d.isNaN }
            return false
        }
        // JS `'' + x` string coercion for the edge name-walk (source/target are names).
        func str(_ v: Any?) -> String {
            guard let v = v, !(v is NSNull) else { return "" }
            if let s = v as? String { return s }
            return "\(v)"
        }
        // dataType === 'node' or empty do not show tooltip by default
        if dataType == .edge {
            let params = self.getDataParams(dataIndex, dataType)
            let rawDataOpt = params.data as? [String: Any]
            let edgeValue = params.value
            // const edgeName = rawDataOpt.source + ' -- ' + rawDataOpt.target;
            let edgeName = str(rawDataOpt?["source"]) + " -- " + str(rawDataOpt?["target"])
            return createTooltipMarkup("nameValue", TooltipMarkupNameValueBlock(
                name: edgeName, value: edgeValue, noValue: noValue(edgeValue)))
        }
        // dataType === 'node'
        else {
            let node = self.getGraph().getNodeByIndex(Int(dataIndex))
            let value = (node?.getLayout() as? [String: Any])?["value"]
            // const name = (this.getDataParams(...).data as SankeyNodeItemOption).name;
            let nameRaw = (self.getDataParams(dataIndex, dataType).data as? [String: Any])?["name"]
            let name: String? = (nameRaw != nil && !(nameRaw is NSNull)) ? str(nameRaw) : nil
            return createTooltipMarkup("nameValue", TooltipMarkupNameValueBlock(
                name: name, value: value, noValue: noValue(value)))
        }
    }

    // optionUpdated() {}
    open func optionUpdated() {}

    // Override Series.getDataParams() — node branch fills value from the graph layout.
    //   Base (DataFormatMixin) 2-arg getDataParams reached via `(self as DataFormatMixin)` to avoid
    //   re-dispatching into this concrete override.
    open override func getDataParams(_ dataIndex: Double, _ dataType: SeriesDataType? = nil) -> CallbackDataParams {
        // const params = super.getDataParams(dataIndex, dataType);
        var params = (self as DataFormatMixin).getDataParams(dataIndex, dataType)
        // if (params.value == null && dataType === 'node') {
        let valueIsNull: Bool = {
            if params.value is NSNull { return true }
            let m = Mirror(reflecting: params.value)
            return m.displayStyle == .optional && m.children.isEmpty
        }()
        if valueIsNull && dataType == .node {
            let node = self.getGraph().getNodeByIndex(Int(dataIndex))
            if let nodeValue = (node?.getLayout() as? [String: Any])?["value"] {
                params.value = nodeValue
            }
        }
        return params
    }

    // __ownRoamView() { return this.coordinateSystem; }
    open func __ownRoamView() -> Any? {
        return self.coordinateSystem
    }

    // static defaultOption: SankeySeriesOption = { ... }
    open override class var defaultOption: ModelOption? {
        return [
            // zlevel: 0,
            "z": 2.0,

            // `coordinateSystem` can be declared as 'matrix', 'calendar',
            //  which provides box layout container.
            "coordinateSystemUsage": "box",

            "left": "5%",
            "top": "5%",
            "right": "20%",
            "bottom": "5%",

            "orient": "horizontal",

            "nodeWidth": 20.0,

            "nodeGap": 8.0,
            "draggable": true,

            "layoutIterations": 32.0,
            "sort": "desc",

            // true | false | 'move' | 'scale', see module:component/helper/RoamController.
            "roam": false,
            "roamTrigger": "global",
            // POTENTIAL-BUG: upstream `center: null`; NSNull() faithfully retains the key in the
            //   [String: Any] bag, but a reader doing `bag["center"] != nil` sees NSNull as present
            //   (JS `center == null` would be true). Readers must `as?`-cast (NSNull fails the cast → absent).
            "center": NSNull(),
            "zoom": 1.0,

            "label": [
                "show": true,
                "position": "right",
                "fontSize": 12.0
            ] as [String: Any],

            "edgeLabel": [
                "show": false,
                "fontSize": 12.0
            ] as [String: Any],

            "levels": [] as [Any],

            "nodeAlign": "justify",

            "lineStyle": [
                "color": "#86878c",  // upstream: tokens.color.neutral50
                "opacity": 0.2,
                "curveness": 0.5
            ] as [String: Any],

            "emphasis": [
                "label": [
                    "show": true
                ] as [String: Any],
                "lineStyle": [
                    "opacity": 0.5
                ] as [String: Any]
            ] as [String: Any],

            "select": [
                "itemStyle": [
                    "borderColor": "#3c3c41"  // upstream: tokens.color.primary (= color.neutral80)
                ] as [String: Any]
            ] as [String: Any],

            "animationEasing": "linear",

            "animationDuration": 1000.0
        ] as [String: Any]
    }
}

// export default SankeySeriesModel;  -> `open class SankeySeriesModel` above.

// Reads a numeric option that the `[String: Any]` bag may store as Int / Double / NSNumber and returns
//   a `Double?` — a bare `as? Double` returns nil on an Int literal and SILENTLY DROPS it (CONVENTIONS
//   INT-vs-DOUBLE trap). Used for `levels[i].depth`. Returns nil for missing / NSNull. File-private.
private func sankeyNum(_ v: Any?) -> Double? {
    switch v {
    case nil: return nil
    case is NSNull: return nil
    case let d as Double: return d
    case let i as Int: return Double(i)
    case let n as NSNumber: return n.doubleValue
    default: return nil
    }
}
