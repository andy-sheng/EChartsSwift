// Ported from echarts/src/chart/graph/GraphSeries.ts — keep in sync with upstream
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
//   import SeriesData from '../../data/SeriesData';                  -> SeriesData (data/SeriesData.swift).
//   import * as zrUtil from 'zrender/src/core/util';                 -> ZRenderKit `util`.
//   import {defaultEmphasis} from '../../util/model';                -> modelUtil.defaultEmphasis (typed;
//       see mergeDefaultAndTheme PORT-NOTE below).
//   import Model from '../../model/Model';                           -> Model (model/Model.swift).
//   import createGraphFromNodeEdge from '../helper/createGraphFromNodeEdge';
//       -> the sibling free function `createGraphFromNodeEdge` (chart/helper/createGraphFromNodeEdge.swift).
//   import LegendVisualProvider from '../../visual/LegendVisualProvider';
//       -> LegendVisualProvider (visual/LegendVisualProvider.swift); wired in `init` (base SeriesModel
//          types the slot `legendVisualProvider: Any?`).
//   import { ... } from '../../util/types';                          -> type-only; the dynamic option tree is
//       the `[String: Any]` bag per CONVENTIONS §2. The interface/type declarations
//       (GraphEdgeLineStyleOption, GraphNodeStateOption, GraphNodeItemOption, GraphEdgeItemOption,
//       GraphCategoryItemOption, GraphSeriesOption, …) describe the option tree — kept as documentation
//       only, no Swift types emitted.
//   import SeriesModel from '../../model/Series';                    -> SeriesModel (model/Series.swift).
//   import Graph from '../../data/Graph';                            -> Graph / GraphNode / GraphEdge
//       (data/Graph.swift — the sibling graph-data track).
//   import GlobalModel from '../../model/Global';                    -> GlobalModel (model/Global.swift).
//   import { VectorArray } from 'zrender/src/core/vector';           -> `[Double]`.
//   import { ForceLayoutInstance } from './forceLayout';
//       -> forceLayout (iterative physics) IS ported (chart/graph/forceLayout.swift, returning the concrete
//          `ForceLayoutInstance`); the `forceLayout` slot stays `Any?` (that concrete type isn't bound here).
//   import { LineDataVisual } from '../../visual/commonVisualTypes';  -> type-only.
//   import { createTooltipMarkup } from '../../component/tooltip/tooltipMarkup';
//       -> createTooltipMarkup (component/tooltip/tooltipMarkup.swift).
//   import { defaultSeriesFormatTooltip } from '../../component/tooltip/seriesFormatTooltip';
//       -> defaultSeriesFormatTooltip (component/tooltip/seriesFormatTooltip.swift).
//   import {initCurvenessList, createEdgeMapForCurveness} from '../helper/multipleGraphEdgeHelper';
//       -> multipleGraphEdgeHelper IS ported (chart/helper/multipleGraphEdgeHelper.swift — auto-curveness
//          for multiple edges); the two calls in `getInitialData` are commented out below.
//   import tokens from '../../visual/tokens';
//       -> visual/tokens.ts IS ported (visual/tokens.swift); the consumed values are still inlined verbatim in
//          `defaultOption` (tokens.color.neutral50 = '#86878c', tokens.color.primary = neutral80 = '#3c3c41').
//   import { isViewCoordSys } from '../../coord/View';
//       -> PORT-NOTE (deferred): isViewCoordSys IS ported (coord/View.swift), but View's CoordinateSystem
//          protocol conformance is dropped there, so it cannot be applied to filter the `Any?` slot; the
//          graph's roam is deferred anyway, so `__ownRoamView` returns the slot unfiltered (harmless).

// export const SERIES_TYPE_GRAPH = 'graph';
public let SERIES_TYPE_GRAPH = "graph"

// upstream (hoisted inside beforeLink):
//   function resolveParentPath(this: Model, pathArr: readonly string[]): string[] {
//       if (pathArr && (pathArr[0] === 'label' || pathArr[1] === 'label')) {
//           const newPathArr = pathArr.slice();
//           if (pathArr[0] === 'label') { newPathArr[0] = 'edgeLabel'; }
//           else if (pathArr[1] === 'label') { newPathArr[1] = 'edgeLabel'; }
//           return newPathArr;
//       }
//       return pathArr as string[];
//   }
// Shared by the two edge-label Model wrappers below (an edge's `label` option path resolves against
//   the series-level `edgeLabel` instead of `label`).
private func graphResolveEdgeLabelPath(_ path: [String]?) -> [String]? {
    guard let pathArr = path else { return path }
    if pathArr.first == "label" || (pathArr.count > 1 && pathArr[1] == "label") {
        var newPathArr = pathArr
        if pathArr.first == "label" {
            newPathArr[0] = "edgeLabel"
        }
        else if pathArr.count > 1 && pathArr[1] == "label" {
            newPathArr[1] = "edgeLabel"
        }
        return newPathArr
    }
    return pathArr
}

// upstream `newGetModel` produces each child model carrying `resolveParentPath` but WITHOUT the
//   `getModel` swap, so grandchildren fall back to the original `getModel` (no further redirect).
//   Mirrored here as a Model subclass that overrides only `resolveParentPath`.
private final class GraphEdgeLabelChildModel: Model {
    override func resolveParentPath(_ path: [String]?) -> [String]? {
        return graphResolveEdgeLabelPath(path)
    }
}

// upstream wraps the edge item model so BOTH `resolveParentPath` redirects label->edgeLabel AND
//   `getModel` is replaced by `newGetModel` (which stamps `resolveParentPath` onto every produced
//   child model). Swift cannot reassign an instance method by name, so the swap is a Model subclass:
//   `resolveParentPath` is overridden, and `getModel` re-wraps each produced child into
//   `GraphEdgeLabelChildModel` (== `oldGetModel.call(...)` then `model.resolveParentPath = ...`).
// PORT-NOTE (two documented divergences of subclass-vs-own-property, both unreachable today):
//   1. `Model.clone()` (Model.swift) reconstructs via `type(of: self).init(...)`, so a clone of one of
//      these wrappers KEEPS the redirect; upstream's `clone()` is `new (this.constructor)(...)` with
//      `constructor === Model`, and the per-instance `resolveParentPath`/`getModel` assignments are
//      dropped by the clone. Nothing on the graph/chord paths clones an edge item/child model, so this
//      is not reachable. If it ever becomes reachable, override `clone()` here to return a plain `Model`.
//   2. Re-wrapping (rather than mutating in place) is only safe while the incoming model is a BASE
//      `Model`: if some prior `getItemModel` injection ever returns a `Model` SUBCLASS, this re-wrap
//      silently downgrades its dynamic type and drops any state it carries. `edgeData` carries exactly
//      one `getItemModel` injection today, so there is no prior wrapper to lose.
private final class GraphEdgeLabelItemModel: Model {
    // function resolveParentPath(this: Model, pathArr) { ... redirect label -> edgeLabel ... }
    override func resolveParentPath(_ path: [String]?) -> [String]? {
        return graphResolveEdgeLabelPath(path)
    }

    // function newGetModel(this: Model, path, parentModel?) {
    //     const model = oldGetModel.call(this, path, parentModel);
    //     model.resolveParentPath = resolveParentPath;
    //     return model;
    // }
    override func getModel(_ path: [String]? = nil, _ parentModel: Model? = nil) -> Model {
        let model = super.getModel(path, parentModel)
        // `super.getModel` freshly constructs a base `Model` (Model.swift, no clone), so re-wrapping it
        //   loses nothing — see the divergence PORT-NOTE above.
        return GraphEdgeLabelChildModel(model.option, model.parentModel, model.ecModel)
    }
}

// upstream: class GraphSeriesModel extends SeriesModel<GraphSeriesOption> implements RoamHostModel
open class GraphSeriesModel: SeriesModel {

    // static readonly type = 'series.' + SERIES_TYPE_GRAPH;
    // readonly type = GraphSeriesModel.type;
    //   The static drives the instance `type` (inherited `var type { Self.type }` from ComponentModel).
    public override class var type: ComponentFullType { return "series." + SERIES_TYPE_GRAPH }

    // static readonly dependencies = ['grid', 'polar', 'geo', 'singleAxis', 'calendar'];
    open override class var dependencies: [String] {
        return ["grid", "polar", "geo", "singleAxis", "calendar"]
    }

    // private _categoriesData: SeriesData;
    // PORT-NOTE: upstream typed non-optional; set by `_updateCategoriesData` during `init`. Modeled
    //   implicitly-unwrapped so `getCategoriesData()` can return non-optional (language difference).
    private var _categoriesData: SeriesData!

    // private _categoriesModels: Model<GraphCategoryItemOption>[];
    private var _categoriesModels: [Model] = []

    /**
     * Preserved points during layouting
     */
    // preservedPoints?: Dictionary<VectorArray>;
    //   `Dictionary<VectorArray>` -> `[String: [Double]]`. Populated by the (deferred) force layout.
    open var preservedPoints: [String: [Double]]?

    // forceLayout?: ForceLayoutInstance;
    // PORT-NOTE: forceLayout (iterative physics) IS ported (chart/graph/forceLayout.swift); this slot
    //   stays typed `Any?` (the concrete `ForceLayoutInstance` type isn't bound here).
    open var forceLayout: Any?

    // hasSymbolVisual = true;
    //   The base `SeriesModel` declares `open var hasSymbolVisual = false` (a stored property, can't be
    //   re-defaulted by a subclass field), so it is flipped to `true` in the `init` override below —
    //   faithful to the upstream instance field. LOAD-BEARING: visual/symbol.ts reads it.

    // init(option: GraphSeriesOption) { super.init.apply(this, arguments); ... }
    open override func `init`(_ option: ModelOption?, _ parentModel: Model? = nil, _ ecModel: GlobalModel? = nil, _ rest: Any...) {
        super.`init`(option, parentModel, ecModel)

        self.hasSymbolVisual = true

        // Provide data for legend select — graph legend entries are CATEGORY names, so both the encoded
        //   and raw accessors resolve to the categories data (upstream passes getCategoriesData for both).
        self.legendVisualProvider = LegendVisualProvider(
            { [unowned self] in self.getCategoriesData() },
            { [unowned self] in self.getCategoriesData() }
        )

        // this.fillDataTextStyle(option.edges || option.links);
        let opt = option as? [String: Any]
        self.fillDataTextStyle(opt?["edges"] ?? opt?["links"])

        self._updateCategoriesData()
    }

    // mergeOption(option: GraphSeriesOption) { super.mergeOption.apply(this, arguments); ... }
    open override func mergeOption(_ newSeriesOption: ModelOption?, _ ecModel: GlobalModel?) {
        super.mergeOption(newSeriesOption, ecModel)

        // this.fillDataTextStyle(option.edges || option.links);
        let opt = newSeriesOption as? [String: Any]
        self.fillDataTextStyle(opt?["edges"] ?? opt?["links"])

        self._updateCategoriesData()
    }

    // mergeDefaultAndTheme(option: GraphSeriesOption) { super.mergeDefaultAndTheme.apply(this, arguments);
    //     defaultEmphasis(option, 'edgeLabel', ['show']); }
    open override func mergeDefaultAndTheme(_ option: ModelOption?, _ ecModel: GlobalModel?) {
        super.mergeDefaultAndTheme(option, ecModel)

        // defaultEmphasis(option, 'edgeLabel', ['show']);
        // PORT-NOTE: modelUtil.defaultEmphasis takes an `inout DisplayStateHostOption?` value struct
        //   (CONVENTIONS §4); the dynamic option tree here is the `[String: Any]` bag. Rather than bridge
        //   the bag to the typed struct (as super's own top-level `defaultEmphasis(option,'label',...)`
        //   still defers), the identical logic is inlined verbatim against the bag for this single
        //   `edgeLabel`/`['show']` call — mutating `self.option` in place (upstream mutates the passed
        //   `option`, which at call time IS `self.option`, matching super.mergeDefaultAndTheme's write-back).
        let key = "edgeLabel"
        let subOpts = ["show"]
        if var opt = self.option as? [String: Any] {
            // opt[key] = opt[key] || {};
            var optKey = (opt[key] as? [String: Any]) ?? [:]
            // opt.emphasis = opt.emphasis || {};
            var emphasis = (opt["emphasis"] as? [String: Any]) ?? [:]
            // opt.emphasis[key] = opt.emphasis[key] || {};
            var emphasisKey = (emphasis[key] as? [String: Any]) ?? [:]
            // Default emphasis option from normal
            for subOptName in subOpts {
                // !opt.emphasis[key].hasOwnProperty(subOptName) && opt[key].hasOwnProperty(subOptName)
                if emphasisKey[subOptName] == nil && optKey[subOptName] != nil {
                    emphasisKey[subOptName] = optKey[subOptName]
                }
            }
            emphasis[key] = emphasisKey
            opt[key] = optKey
            opt["emphasis"] = emphasis
            self.option = opt
        }
    }

    // getInitialData(option: GraphSeriesOption, ecModel: GlobalModel): SeriesData { ... }
    open override func getInitialData(_ option: ModelOption?, _ ecModel: GlobalModel?) -> SeriesData? {
        let opt = option as? [String: Any]

        // const edges = option.edges || option.links || [];
        //   JS `||` — arrays (even empty) are truthy, only nil/undefined falls through, so `??` matches.
        let edges: OptionSourceDataOriginal = (opt?["edges"] as? [Any]) ?? (opt?["links"] as? [Any]) ?? []
        // const nodes = option.data || option.nodes || [];
        let nodes: OptionSourceDataOriginal = (opt?["data"] as? [Any]) ?? (opt?["nodes"] as? [Any]) ?? []

        // const self = this;
        // if (nodes && edges) — arrays are always truthy in JS regardless of length, so this branch is
        //   always taken; the `beforeLink` hoisted below is passed to createGraphFromNodeEdge.

        // auto curveness
        // initCurvenessList(this);
        multipleGraphEdgeHelper.initCurvenessList(self)

        // const graph = createGraphFromNodeEdge(nodes, edges, this, true, beforeLink);
        let graph = createGraphFromNodeEdge(nodes, edges, self, true, self.beforeLink)

        // zrUtil.each(graph.edges, function (edge) {
        //     createEdgeMapForCurveness(edge.node1, edge.node2, this, edge.dataIndex);
        // }, this);
        graph.eachEdge { edge, _ in
            multipleGraphEdgeHelper.createEdgeMapForCurveness(edge.node1, edge.node2, self, Double(edge.dataIndex))
        }

        // return graph.data;
        return graph.data
    }

    // function beforeLink(nodeData: SeriesData, edgeData: SeriesData) { ... }
    //   Hoisted in upstream; a stored closure here. Captures `self` for `_categoriesModels`.
    private func beforeLink(_ nodeData: SeriesData, _ edgeData: SeriesData) {
        // Overwrite nodeData.getItemModel to
        // nodeData.wrapMethod('getItemModel', function (model) {
        //     const categoriesModels = self._categoriesModels;
        //     const categoryIdx = model.getShallow('category');
        //     const categoryModel = categoriesModels[categoryIdx];
        //     if (categoryModel) {
        //         categoryModel.parentModel = model.parentModel;
        //         model.parentModel = categoryModel;
        //     }
        //     return model;
        // });
        // PORT-NOTE: SeriesData.wrapMethod('getItemModel', …) IS live — the injection is stored in
        //   SeriesData._getItemModelInjections and threaded through every getItemModel() call (see
        //   data/SeriesData.swift), and it survives cloneShallow via transferProperties. So this
        //   per-category parentModel reparenting DOES take effect (category itemStyle/label inheritance).
        nodeData.wrapMethod("getItemModel") { [weak self] args in
            guard let self = self, let model = args.first as? Model else { return args.first as Any? }
            let categoriesModels = self._categoriesModels
            // const categoryIdx = model.getShallow('category');
            //   `category` is `number | string`; read it via a coercion that survives Int/Double/NSNumber
            //   boxing (a raw `as? Double` returns nil for an Int-literal option — the Int-vs-Double
            //   option-read trap — which would silently drop the reparenting).
            let categoryIdx = graphCategoryIndex(model.getShallow("category"))
            // const categoryModel = categoriesModels[categoryIdx];
            let categoryModel = (categoryIdx >= 0 && categoryIdx < categoriesModels.count)
                ? categoriesModels[categoryIdx] : nil
            if let categoryModel = categoryModel {
                categoryModel.parentModel = model.parentModel
                model.parentModel = categoryModel
            }
            return model
        }

        // TODO Inherit resolveParentPath by default in Model#getModel?
        // const oldGetModel = Model.prototype.getModel;
        // function newGetModel(this: Model, path, parentModel?) {
        //     const model = oldGetModel.call(this, path, parentModel);
        //     model.resolveParentPath = resolveParentPath;
        //     return model;
        // }
        // edgeData.wrapMethod('getItemModel', function (model: Model) {
        //     model.resolveParentPath = resolveParentPath;
        //     model.getModel = newGetModel;
        //     return model;
        // });
        // function resolveParentPath(pathArr) {
        //     if (pathArr && (pathArr[0] === 'label' || pathArr[1] === 'label')) {
        //         const newPathArr = pathArr.slice();
        //         if (pathArr[0] === 'label') { newPathArr[0] = 'edgeLabel'; }
        //         else if (pathArr[1] === 'label') { newPathArr[1] = 'edgeLabel'; }
        //         return newPathArr;
        //     }
        //     return pathArr;
        // }
        // PORT-NOTE: upstream reassigns `model.resolveParentPath` / `model.getModel` per instance (a JS
        //   prototype-method swap). Swift cannot rebind an instance method by name, so the swap is expressed
        //   as the two Model subclasses at file scope (`GraphEdgeLabelItemModel` / `GraphEdgeLabelChildModel`):
        //   the injection re-wraps the produced edge item model into `GraphEdgeLabelItemModel`, which redirects
        //   a `label` path to `edgeLabel` and stamps the redirect onto each child model it produces.
        //   `oldGetModel` / `newGetModel` are the base `Model.getModel` / `GraphEdgeLabelItemModel.getModel`.
        edgeData.wrapMethod("getItemModel") { args in
            // function (model: Model) {
            //     model.resolveParentPath = resolveParentPath;
            //     model.getModel = newGetModel;
            //     return model;
            // }
            guard let model = args.first as? Model else { return args.first as Any? }
            // Upstream MUTATES the model in place; Swift re-wraps it instead (see the divergence
            //   PORT-NOTE on `GraphEdgeLabelItemModel` for why that is equivalent here).
            return GraphEdgeLabelItemModel(model.option, model.parentModel, model.ecModel)
        }
    }

    // getGraph(): Graph { return this.getData().graph; }
    open func getGraph() -> Graph {
        // POTENTIAL-BUG: SeriesData.graph is typed `AnyObject?` (see data/SeriesData.swift); force-unwrap
        //   mirrors upstream optimistic typing — linkSeriesData is assumed to have set it for graph series,
        //   but a call before linking would SIGTRAP (latent crash hazard).
        return self.getData().graph!
    }

    // getEdgeData() { return this.getGraph().edgeData as SeriesData<GraphSeriesModel, LineDataVisual>; }
    open func getEdgeData() -> SeriesData {
        return self.getGraph().edgeData
    }

    // Phase 45: route `getData(.edge)` to the edge data (upstream `data.getLinkedData(dataType)`), so the
    //   states engine's object-focus branch (`{node:[…], edge:[…]}`) resolves edge dispatchers against the
    //   EDGE data, not the node data. The base `getData()` returns the node (main) data.
    open override func getData(_ dataType: SeriesDataType? = nil) -> SeriesData {
        if dataType == .edge { return getEdgeData() }
        return super.getData(dataType)
    }

    // getCategoriesData(): SeriesData { return this._categoriesData; }
    open func getCategoriesData() -> SeriesData {
        return self._categoriesData
    }

    // formatTooltip(dataIndex, multipleSeries, dataType) { ... }
    open override func formatTooltip(
        _ dataIndex: Double,
        _ multipleSeries: Bool? = nil,
        _ dataType: SeriesDataType? = nil
    ) -> TooltipFormatResult? {
        if dataType == .edge {
            // const nodeData = this.getData();
            let nodeData = self.getData()
            // const params = this.getDataParams(dataIndex, dataType);
            let params = self.getDataParams(dataIndex, dataType)

            // const edge = nodeData.graph.getEdgeByIndex(dataIndex);
            //   STALE-INDEX GUARD — same hazard as ChordSeries.formatTooltip (see the longer note there):
            //   an edge removed by legend filtering lingers, hit-testable, through its fade-out carrying
            //   its pre-filter index, and `getRawIndex` returns -1 for it. Upstream's TypeError aborts the
            //   handler; the ported force-unwrap would kill the process (PORTING.md §12).
            guard let edge = nodeData.graph?.getEdgeByIndex(Int(dataIndex)) else {
                return nil
            }
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

            // return createTooltipMarkup('nameValue', {
            //     name: nameArr.join(' > '),
            //     value: params.value,
            //     noValue: params.value == null
            // });
            let value = params.value
            // `params.value` is typed `Any`; `getDataParams` boxes a nil raw value as
            //   `Optional.none as Any` (or `NSNull`). Detect both to mirror `value == null`.
            let valueIsNull: Bool = {
                if value is NSNull { return true }
                let m = Mirror(reflecting: value)
                return m.displayStyle == .optional && m.children.isEmpty
            }()
            return createTooltipMarkup("nameValue", TooltipMarkupNameValueBlock(
                name: nameArr.joined(separator: " > "),
                value: value,
                noValue: valueIsNull
            ))
        }
        // dataType === 'node' or empty
        // const nodeMarkup = defaultSeriesFormatTooltip({ series: this, dataIndex, multipleSeries });
        // return nodeMarkup;
        let nodeMarkup = defaultSeriesFormatTooltip(series: self, dataIndex: dataIndex, multipleSeries: multipleSeries ?? false)
        return nodeMarkup
    }

    // _updateCategoriesData() { ... }
    open func _updateCategoriesData() {
        // const categories = zrUtil.map(this.option.categories || [], function (category) {
        //     // Data must has value
        //     return category.value != null ? category : zrUtil.extend({ value: 0 }, category);
        // });
        let rawCategories = (self.option as? [String: Any])?["categories"] as? [Any] ?? []
        let categories: [Any] = util.map(rawCategories) { category, _ -> Any in
            let dict = category as? [String: Any] ?? [:]
            // category.value != null ? category : extend({value: 0}, category)
            if let v = dict["value"], !(v is NSNull) {
                return dict
            }
            var base: [String: Any] = ["value": 0]
            _ = util.extend(&base, dict)
            return base
        }

        // const categoriesData = new SeriesData(['value'], this);
        let categoriesData = SeriesData(["value"], self)
        // categoriesData.initData(categories);
        categoriesData.initData(categories)

        self._categoriesData = categoriesData

        // this._categoriesModels = categoriesData.mapArray(function (idx) {
        //     return categoriesData.getItemModel(idx);
        // });
        self._categoriesModels = categoriesData.mapArray { args in
            // `each` (empty dims) passes `[idx]`; idx is the dataIndex.
            let idx = Int((args.last as? Double) ?? 0)
            return categoriesData.getItemModel(idx)
        }.compactMap { $0 as? Model }
    }

    // isAnimationEnabled() {
    //     return super.isAnimationEnabled()
    //         && !(this.get('layout') === 'force' && this.get(['force', 'layoutAnimation']));
    // }
    open override func isAnimationEnabled() -> Bool? {
        let base = super.isAnimationEnabled() ?? false
        let isForce = (self.get("layout") as? String) == "force"
        // Not enable animation when do force layout
        let layoutAnimation = jsTruthy(self.get(["force", "layoutAnimation"]))
        return base && !(isForce && layoutAnimation)
    }

    // __ownRoamView() {
    //     const coordSys = this.coordinateSystem;
    //     return isViewCoordSys(coordSys) && coordSys;
    // }
    open func __ownRoamView() -> Any? {
        // Be an exclusive coord sys of graph series iff it is a `View` coord sys.
        // Otherwise graph series is based on an external geo or Cartesian.
        let coordSys = self.coordinateSystem
        // PORT-NOTE (deferred): isViewCoordSys IS ported, but View's CoordinateSystem conformance is
        //   dropped (coord/View.swift) so the `View`-ness filter cannot be applied here; the
        //   `coordinateSystem` slot is returned unfiltered (roam is deferred anyway).
        return coordSys
    }

    // static defaultOption: GraphSeriesOption = { ... }
    open override class var defaultOption: ModelOption? {
        return [
            // zlevel: 0,
            "z": 2.0,

            "coordinateSystem": "view",

            // Default option for all coordinate systems
            // xAxisIndex: 0,
            // yAxisIndex: 0,
            // polarIndex: 0,
            // geoIndex: 0,

            "legendHoverLink": true,

            // POTENTIAL-BUG: upstream value is `null` (key present, null value); NSNull() matches the
            //   key-present semantics but a read returns NSNull() not nil — code doing `dict["layout"] != nil`
            //   (rather than jsTruthy) would diverge from JS falsy-null.
            "layout": NSNull(),

            // Configuration of circular layout
            "circular": [
                "rotateLabel": false
            ] as [String: Any],
            // Configuration of force directed layout
            "force": [
                // POTENTIAL-BUG: upstream `initLayout: null`; NSNull() retains the key (key-present matches
                //   upstream) but reads yield NSNull() not nil — hazard for `!= nil` checks vs jsTruthy.
                "initLayout": NSNull(),
                // Node repulsion. Can be an array to represent range.
                "repulsion": [0.0, 50.0],
                "gravity": 0.1,
                // Initial friction
                "friction": 0.6,
                // Edge length. Can be an array to represent range.
                "edgeLength": 30.0,
                "layoutAnimation": true
            ] as [String: Any],

            "left": "center",
            "top": "center",
            // right: null,
            // bottom: null,
            // The graph view rect is inset to 80% of the container (centered) so the node symbols keep a
            //   margin from the canvas edge after the bounding-box→viewRect fit (GraphViewCoordSys); an
            //   un-inset full-canvas rect would clip the extreme nodes.
            "width": "80%",
            "height": "80%",

            "symbol": "circle",
            "symbolSize": 10.0,

            "edgeSymbol": ["none", "none"],
            "edgeSymbolSize": 10.0,
            "edgeLabel": [
                "position": "middle",
                "distance": 5.0
            ] as [String: Any],

            "draggable": false,

            "roam": false,

            // Default on center of graph
            // POTENTIAL-BUG: upstream value is `null`; NSNull() retains the key (key-present matches
            //   upstream) but reads yield NSNull() not nil — hazard for `!= nil` checks vs jsTruthy.
            "center": NSNull(),

            "zoom": 1.0,
            // Symbol size scale ratio in roam
            "nodeScaleRatio": 0.6,

            // cursor: null,
            // categories: [],
            // data: []  // Or nodes: []
            // links: [] // Or edges: []

            "label": [
                "show": false,
                "formatter": "{b}"
            ] as [String: Any],

            "itemStyle": [String: Any](),

            "lineStyle": [
                // Don't use tokens.color.border because of the opacity
                "color": "#86878c",  // upstream: tokens.color.neutral50
                "width": 1.0,
                "opacity": 0.5
            ] as [String: Any],
            "emphasis": [
                "scale": true,
                "label": [
                    "show": true
                ] as [String: Any]
            ] as [String: Any],

            "select": [
                "itemStyle": [
                    "borderColor": "#3c3c41"  // upstream: tokens.color.primary (= color.neutral80)
                ] as [String: Any]
            ] as [String: Any]
        ] as [String: Any]
    }
}

// export default GraphSeriesModel;  -> `open class GraphSeriesModel` above.

// Mirrors JavaScript `||`/`&&` truthiness for a dynamic `Any?` value (nil / NSNull / false / 0 / NaN /
// "" are falsy). Used by `isAnimationEnabled` for `this.get(['force', 'layoutAnimation'])`. File-private
// per port convention.
private func jsTruthy(_ v: Any?) -> Bool {
    guard let v = v else { return false }
    if v is NSNull { return false }
    if let b = v as? Bool { return b }
    if let n = v as? Double { return n != 0 && !n.isNaN }
    if let i = v as? Int { return i != 0 }
    if let s = v as? String { return !s.isEmpty }
    return true
}

// Coerce a node's `category` option (typed `number | string` upstream) to an array index for
// `categoriesModels[categoryIdx]`. Mirrors JS array indexing: a number (Int/Double/NSNumber boxing) or
// an all-numeric string ('0') indexes the array; any other value yields no match. Returns -1 when the
// value is absent or non-indexable (so the caller's `>= 0 && < count` guard skips reparenting).
// File-private per port convention.
private func graphCategoryIndex(_ v: Any?) -> Int {
    guard let v = v, !(v is NSNull) else { return -1 }
    if let i = v as? Int { return i }
    if let d = v as? Double, d.isFinite { return Int(d) }
    if let s = v as? String, let i = Int(s) { return i }
    return -1
}
