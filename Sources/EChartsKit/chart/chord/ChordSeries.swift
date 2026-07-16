// Ported from echarts/src/chart/chord/ChordSeries.ts — keep in sync with upstream
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
//   import { ... } from '../../util/types';                            -> type-only; the dynamic option tree is
//       the `[String: Any]` bag per CONVENTIONS §2. The interface/type declarations (ExtraEmphasisState,
//       ChordStatesMixin, ChordEdgeStatesMixin, ChordDataValue, ChordItemStyleOption, ChordNodeStateOption,
//       ChordNodeItemOption, ChordEdgeLineStyleOption, ChordNodeLabelOption, ChordEdgeStateOption,
//       ChordEdgeItemOption, ChordSeriesOption, …) describe the option tree — kept as documentation only,
//       no Swift types emitted.
//   import Model from '../../model/Model';                             -> Model (model/Model.swift).
//   import SeriesModel from '../../model/Series';                      -> SeriesModel (model/Series.swift).
//   import GlobalModel from '../../model/Global';                      -> GlobalModel (model/Global.swift).
//   import SeriesData from '../../data/SeriesData';                    -> SeriesData (data/SeriesData.swift).
//   import createGraphFromNodeEdge from '../helper/createGraphFromNodeEdge';
//       -> the sibling free function `createGraphFromNodeEdge` (chart/helper/createGraphFromNodeEdge.swift) —
//          ALREADY PORTED; reused exactly like SankeySeries/GraphSeries.getInitialData does.
//   import Graph from '../../data/Graph';                              -> data/Graph.swift (sibling port).
//   import { LineDataVisual } from '../../visual/commonVisualTypes';   -> type-only.
//   import { createTooltipMarkup } from '../../component/tooltip/tooltipMarkup';
//       -> component/tooltip/tooltipMarkup.swift (`createTooltipMarkup`, ported and wired below).
//   import LegendVisualProvider from '../../visual/LegendVisualProvider';
//       -> visual/LegendVisualProvider.swift (ported and wired below).
//   import * as zrUtil from 'zrender/src/core/util';                   -> ZRenderKit.util (bind — deferred with
//       LegendVisualProvider below).

// export const SERIES_TYPE_CHORD = 'chord';
public let SERIES_TYPE_CHORD = "chord"

// upstream: class ChordSeriesModel extends SeriesModel<ChordSeriesOption>
open class ChordSeriesModel: SeriesModel {

    // static readonly type = 'series.' + SERIES_TYPE_CHORD;
    // readonly type = ChordSeriesModel.type;
    //   The static drives the instance `type` (inherited `var type { Self.type }` from ComponentModel).
    public override class var type: ComponentFullType { return "series." + SERIES_TYPE_CHORD }

    // init(option: ChordSeriesOption) { super.init.apply(this, arguments); ... }
    open override func `init`(_ option: ModelOption?, _ parentModel: Model? = nil, _ ecModel: GlobalModel? = nil, _ rest: Any...) {
        super.`init`(option, parentModel, ecModel)

        // this.fillDataTextStyle(option.edges || option.links);
        let opt = option as? [String: Any]
        self.fillDataTextStyle(opt?["edges"] ?? opt?["links"])

        // Enable legend selection for each DATA ITEM (chord legend entries are node names).
        self.legendVisualProvider = LegendVisualProvider(
            { [unowned self] in self.getData() },
            { [unowned self] in self.getRawData() }
        )
    }

    // mergeOption(option: ChordSeriesOption) { super.mergeOption.apply(this, arguments); ... }
    open override func mergeOption(_ newSeriesOption: ModelOption?, _ ecModel: GlobalModel?) {
        super.mergeOption(newSeriesOption, ecModel)

        // this.fillDataTextStyle(option.edges || option.links);
        let opt = newSeriesOption as? [String: Any]
        self.fillDataTextStyle(opt?["edges"] ?? opt?["links"])
    }

    // getInitialData(option: ChordSeriesOption, ecModel: GlobalModel): SeriesData { ... }
    open override func getInitialData(_ option: ModelOption?, _ ecModel: GlobalModel?) -> SeriesData? {
        let opt = option as? [String: Any]

        // const edges = option.edges || option.links || [];
        //   JS `||` — arrays (even empty) are truthy, only nil/undefined falls through, so `??` matches.
        let edges: OptionSourceDataOriginal = (opt?["edges"] as? [Any]) ?? (opt?["links"] as? [Any]) ?? []
        // const nodes = option.data || option.nodes || [];
        let nodes: OptionSourceDataOriginal = (opt?["data"] as? [Any]) ?? (opt?["nodes"] as? [Any]) ?? []

        // if (nodes && edges) — arrays are always truthy in JS regardless of length, so this branch is
        //   always taken; the `beforeLink` hoisted below is passed to createGraphFromNodeEdge.

        // const graph = createGraphFromNodeEdge(nodes, edges, this, true, beforeLink);
        let graph = createGraphFromNodeEdge(nodes, edges, self, true, self.beforeLink)
        // return graph.data;
        return graph.data
    }

    // function beforeLink(nodeData: SeriesData, edgeData: SeriesData) { ... }
    //   Hoisted in upstream; a stored closure here.
    private func beforeLink(_ nodeData: SeriesData, _ edgeData: SeriesData) {
        // TODO Inherit resolveParentPath by default in Model#getModel?
        // const oldGetModel = Model.prototype.getModel;
        // function newGetModel(this: Model, path: any, parentModel?: Model) {
        //     const model = oldGetModel.call(this, path, parentModel);
        //     model.resolveParentPath = resolveParentPath;
        //     return model;
        // }
        //
        // edgeData.wrapMethod('getItemModel', function (model: Model) {
        //     model.resolveParentPath = resolveParentPath;
        //     model.getModel = newGetModel;
        //     return model;
        // });
        //
        // function resolveParentPath(this: Model, pathArr: readonly string[]): string[] {
        //     if (pathArr && (pathArr[0] === 'label' || pathArr[1] === 'label')) {
        //         const newPathArr = pathArr.slice();
        //         if (pathArr[0] === 'label') { newPathArr[0] = 'edgeLabel'; }
        //         else if (pathArr[1] === 'label') { newPathArr[1] = 'edgeLabel'; }
        //         return newPathArr;
        //     }
        //     return pathArr as string[];
        // }
        // PORT-NOTE (deferred): requires a settable `Model.resolveParentPath` hook and a functional
        //   `SeriesData.wrapMethod`. This dynamically rebinds `model.resolveParentPath` / `model.getModel` per-instance
        //   (JS prototype-method swap) so an edge's `label` path resolves against `edgeLabel`. Swift
        //   cannot swap instance methods by assignment, and `SeriesData.wrapMethod` is a bookkeeping-only
        //   stub (it cannot rebind a method by name — see data/SeriesData.swift), so the `edgeLabel`
        //   path-redirect is NOT applied. Preserved faithfully for the diffable surface and for when Model
        //   gains a settable `resolveParentPath` hook. (upstream mirrors GraphSeries.beforeLink's edge path.)
        _ = nodeData
        edgeData.wrapMethod("getItemModel") { args in
            return args.first as Any?
        }
    }

    // getGraph(): Graph { return this.getData().graph; }
    open func getGraph() -> Graph {
        // POTENTIAL-BUG: force-unwrap mirrors upstream optimistic typing — linkSeriesData
        //   (createGraphFromNodeEdge) is assumed to have set `graph` for chord series, but a call before
        //   linking would SIGTRAP (latent crash hazard).
        return self.getData().graph!
    }

    // getEdgeData() { return this.getGraph().edgeData as SeriesData<ChordSeriesModel, LineDataVisual>; }
    open func getEdgeData() -> SeriesData {
        return self.getGraph().edgeData
    }

    // Phase 46: route `getData(.edge)` to the edge data (upstream `data.getLinkedData(dataType)`), so the
    //   states engine's object-focus branch resolves edge dispatchers against the EDGE data (see [[getdata
    //   -datatype-ignored-trap]] — the base ignores dataType). Matches Graph/SankeySeriesModel.
    open override func getData(_ dataType: SeriesDataType? = nil) -> SeriesData {
        if dataType == .edge { return getEdgeData() }
        return super.getData(dataType)
    }

    // formatTooltip(dataIndex, multipleSeries, dataType) { ... }
    open override func formatTooltip(
        _ dataIndex: Double,
        _ multipleSeries: Bool? = nil,
        _ dataType: SeriesDataType? = nil
    ) -> TooltipFormatResult? {
        _ = multipleSeries
        // const params = this.getDataParams(dataIndex, dataType as 'node' | 'edge');
        let params = self.getDataParams(dataIndex, dataType)
        // `params.value` is typed `Any`; a nil raw value is boxed as `Optional.none as Any` (or NSNull).
        // Detect both to mirror the upstream `params.value == null` guard.
        let value = params.value
        let valueIsNull: Bool = {
            if value is NSNull { return true }
            let m = Mirror(reflecting: value)
            return m.displayStyle == .optional && m.children.isEmpty
        }()

        // if (dataType === 'edge') {
        if dataType == .edge {
            // const nodeData = this.getData();
            let nodeData = self.getData()
            // const edge = nodeData.graph.getEdgeByIndex(dataIndex);
            let edge = nodeData.graph!.getEdgeByIndex(Int(dataIndex))!
            // const sourceName = nodeData.getName(edge.node1.dataIndex);
            let sourceName = nodeData.getName(edge.node1.dataIndex)
            // const targetName = nodeData.getName(edge.node2.dataIndex);
            let targetName = nodeData.getName(edge.node2.dataIndex)

            // const nameArr = []; sourceName/targetName != null && push.
            //   getName never returns nil in this port (falls back to ""), so both are pushed.
            var nameArr: [String] = []
            nameArr.append(sourceName)
            nameArr.append(targetName)

            // return createTooltipMarkup('nameValue', {
            //     name: nameArr.join(' > '), value: params.value, noValue: params.value == null });
            return createTooltipMarkup("nameValue", TooltipMarkupNameValueBlock(
                name: nameArr.joined(separator: " > "), value: value, noValue: valueIsNull))
        }
        // dataType === 'node' or empty
        // return createTooltipMarkup('nameValue', {
        //     name: params.name, value: params.value, noValue: params.value == null });
        return createTooltipMarkup("nameValue", TooltipMarkupNameValueBlock(
            name: params.name, value: value, noValue: valueIsNull))
    }

    // getDataParams(dataIndex, dataType) — node branch fills name/value from the graph layout.
    //   The base (DataFormatMixin) 2-arg getDataParams is reached via `(self as DataFormatMixin)`
    //   to avoid re-dispatching into this concrete override (mirrors FunnelSeries/CustomSeries).
    open override func getDataParams(_ dataIndex: Double, _ dataType: SeriesDataType? = nil) -> CallbackDataParams {
        // const params = super.getDataParams(dataIndex, dataType);
        var params = (self as DataFormatMixin).getDataParams(dataIndex, dataType)
        // if (dataType === 'node') {
        if dataType == .node {
            let nodeData = self.getData()
            let node = self.getGraph().getNodeByIndex(Int(dataIndex))
            // Set name if not already set  (params.name is a non-optional String — empty == "not set")
            if params.name.isEmpty { params.name = nodeData.getName(Int(dataIndex)) }
            // Set value if not already set  (params.value is `Any`; a nil raw value boxes as Optional.none/NSNull)
            let valueIsNull: Bool = {
                if params.value is NSNull { return true }
                let m = Mirror(reflecting: params.value)
                return m.displayStyle == .optional && m.children.isEmpty
            }()
            if valueIsNull, let nodeValue = (node?.getLayout() as? [String: Any])?["value"] {
                // const nodeValue = node.getLayout().value; params.value = nodeValue;
                params.value = nodeValue
            }
        }
        return params
    }

    // static defaultOption: ChordSeriesOption = { ... }
    open override class var defaultOption: ModelOption? {
        return [
            // zlevel: 0,
            "z": 2.0,

            "coordinateSystem": "none",

            "legendHoverLink": true,
            "colorBy": "data",

            "left": 0.0,
            "top": 0.0,
            "right": 0.0,
            "bottom": 0.0,
            // PORT-NOTE: upstream `width: null` / `height: null`; NSNull() retains the key in the bag.
            "width": NSNull(),
            "height": NSNull(),

            "center": ["50%", "50%"] as [Any],
            "radius": ["70%", "80%"] as [Any],
            "clockwise": true,

            "startAngle": 90.0,
            "endAngle": "auto",
            "minAngle": 0.0,
            "padAngle": 3.0,

            "itemStyle": [
                "borderRadius": [0.0, 0.0, 5.0, 5.0] as [Any]
            ] as [String: Any],

            "lineStyle": [
                "width": 0.0,
                "color": "source",
                "opacity": 0.2
            ] as [String: Any],

            "label": [
                "show": true,
                "position": "outside",
                "distance": 5.0
            ] as [String: Any],

            "emphasis": [
                "focus": "adjacency",
                "lineStyle": [
                    "opacity": 0.5
                ] as [String: Any]
            ] as [String: Any]
        ] as [String: Any]
    }
}

// export default ChordSeriesModel;  -> `open class ChordSeriesModel` above.
