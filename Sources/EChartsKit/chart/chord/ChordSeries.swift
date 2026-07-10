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
//       -> PORT-TODO: component/tooltip/tooltipMarkup.ts NOT ported (tooltip component deferred).
//   import LegendVisualProvider from '../../visual/LegendVisualProvider';
//       -> PORT-TODO: visual/LegendVisualProvider.ts NOT ported (legend-select provider deferred).
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
        // PORT-TODO: this dynamically rebinds `model.resolveParentPath` / `model.getModel` per-instance
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
        // PORT-TODO: SeriesData.graph is typed `AnyObject?` (see data/SeriesData.swift); force-unwrap to
        //   the ported Graph. linkSeriesData guarantees it is a Graph for chord (createGraphFromNodeEdge).
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
        // const params = this.getDataParams(dataIndex, dataType as 'node' | 'edge');
        // PORT-TODO: SeriesModel does not yet conform to DataFormatMixin (see model/Series.swift), so
        //   `getDataParams` / `params.value` / `params.name` are unavailable — the `value`/`noValue`/`name`
        //   fields of the markup are deferred with the markup construction below (same deferral as
        //   GraphSeries.formatTooltip). The edge name-walk logic is preserved faithfully.

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

            // const nameArr = [];
            // sourceName != null && nameArr.push(sourceName);
            // targetName != null && nameArr.push(targetName);
            //   getName never returns nil in this port (falls back to ""), so both are pushed.
            var nameArr: [String] = []
            nameArr.append(sourceName)
            nameArr.append(targetName)
            _ = nameArr.joined(separator: " > ")

            // return createTooltipMarkup('nameValue', {
            //     name: nameArr.join(' > '),
            //     value: params.value,
            //     noValue: params.value == null
            // });
            // PORT-TODO: component/tooltip/tooltipMarkup.ts NOT ported — the markup return is deferred
            //   (returns nil, matching the base stub). The name walk above is faithful.
            return nil
        }
        // dataType === 'node' or empty
        // return createTooltipMarkup('nameValue', {
        //     name: params.name,
        //     value: params.value,
        //     noValue: params.value == null
        // });
        // PORT-TODO: component/tooltip/tooltipMarkup.ts NOT ported — defers to the base stub (nil).
        _ = multipleSeries
        return nil
    }

    // getDataParams(dataIndex: number, dataType: 'node' | 'edge') {
    //     const params = super.getDataParams(dataIndex, dataType);
    //     if (dataType === 'node') {
    //         const nodeData = this.getData();
    //         const node = this.getGraph().getNodeByIndex(dataIndex);
    //         // Set name if not already set
    //         if (params.name == null) { params.name = nodeData.getName(dataIndex); }
    //         // Set value if not already set
    //         if (params.value == null) {
    //             const nodeValue = node.getLayout().value;
    //             params.value = nodeValue;
    //         }
    //     }
    //     return params;
    // }
    // PORT-TODO: SeriesModel does not yet conform to DataFormatMixin (see model/Series.swift), so
    //   `super.getDataParams` / `CallbackDataParams.name` / `.value` are unavailable — the node
    //   name/value fill-in is deferred with the tooltip subsystem above (same deferral as
    //   SankeySeries.getDataParams). `node.getLayout().value` (the layout value, written by the chord
    //   circular layout stage) fires once getDataParams lands on the base.

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
            // PORT-TODO: upstream `width: null` / `height: null`; NSNull() retains the key in the bag.
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
