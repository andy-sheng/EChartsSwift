// Ported from echarts/src/chart/treemap/treemapVisual.ts — keep in sync with upstream
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
//   import VisualMapping, { VisualMappingOption } from '../../visual/VisualMapping';
//       -> PORT-TODO: visual/VisualMapping.ts NOT ported. The range-based per-child color mapping
//          (buildVisualMapping / mapVisual's `mapping.mapValueToVisual`) is DEFERRED — `buildVisualMapping`
//          returns nil, so children inherit the parent visuals unchanged. Wire once VisualMapping lands.
//   import { each, extend, isArray } from 'zrender/src/core/util';    -> `util.each` / `util.extend` / `util.isArray`.
//   import TreemapSeriesModel, { TreemapSeriesNodeItemOption } from './TreemapSeries';  -> sibling TreemapSeries.swift.
//   import { TreemapLayoutNode, TreemapItemLayout } from './treemapLayout';
//       -> sibling treemapLayout.swift. `TreemapLayoutNode` is the sibling `TreeNode`; the per-node
//          item layout is the dynamic `[String: Any]` bag stored by treemapLayout.
//   import Model from '../../model/Model';                            -> `Model` (model/Model.swift).
//   import { ColorString, ZRColor } from '../../util/types';          -> type-only (util/types.swift); erased to `Any?`/`String`.
//   import { modifyHSL, modifyAlpha } from 'zrender/src/tool/color';  -> `ZRenderKit.color.modifyHSL` / `.modifyAlpha`.
//   import { makeInner } from '../../util/model';                     -> `model.makeInner`.

// type NodeModel = Model<TreemapSeriesNodeItemOption>;              -> `Model`.
// type NodeItemStyleModel = Model<TreemapSeriesNodeItemOption['itemStyle']>;  -> `Model`.

// const ITEM_STYLE_NORMAL = 'itemStyle';
private let ITEM_STYLE_NORMAL = "itemStyle"

// const inner = makeInner<{ drColorMappingBy: ... }, VisualMapping>();
// PORT-TODO: `inner(mapping).drColorMappingBy` is part of the deferred VisualMapping subsystem; see the
//   VisualMapping import PORT-TODO. Not created here.

// interface TreemapVisual { color?: ZRColor; colorAlpha?: number; colorSaturation?: number }
// PORT-TODO: modeled as a dynamic `[String: Any]` bag to mirror upstream's `(visuals as any)[visualName]`
//   dynamic-key access in buildVisuals/mapVisual.
public typealias TreemapVisual = [String: Any]

// export default { seriesType: 'treemap', reset(seriesModel) {...} };
//   Modeled as a `StageHandler` (util/types.swift) with `seriesType` + `reset` (candlestickVisual pattern).
//   Upstream's `reset(seriesModel)` uses only `seriesModel` and returns void, so the extra
//   (ecModel, api, payload) args are ignored and the handler returns nil.
public let treemapVisual: StageHandler = {
    var handler = StageHandler()

    handler.seriesType = "treemap"

    handler.reset = { (seriesModelBase: SeriesModel, _ ecModel: GlobalModel, _ api: ExtensionAPI, _ payload: Payload?) -> Any? in
        // upstream typed `seriesModel: TreemapSeriesModel`.
        let seriesModel = seriesModelBase as! TreemapSeriesModel

        // const tree = seriesModel.getData().tree;
        // `data.tree` is `Tree?` on SeriesData; bail if absent.
        guard let tree = seriesModel.getData().tree else {
            return nil
        }
        // const root = tree.root;
        let root: TreeNode = tree.root   // annotate: `root` is IUO; a bare `let` infers Optional

        // if (root.isRemoved()) { return; }
        if root.isRemoved() {
            return nil
        }

        // The default level-0 `color` range is the global palette. `setDefault` (at series init) captured
        //   it from `ecModel.get('color')`, but the global default palette is not yet merged at that point,
        //   so the frozen range is empty. Pass the render-time palette as a fallback range so the children
        //   still get distributed the palette colors (matches echarts, whose level-0 color IS the palette).
        let fallbackPalette: [Any] = (ecModel.get("color", false) as? [Any]) ?? []
        travelTree(
            root, // Visual should calculate from tree root but not view root.
            [:],
            // seriesModel.getViewRoot().getAncestors() — `getViewRoot()` is `TreeNode?` in the sibling
            //   port (upstream is non-null); an absent view root yields no ancestors.
            seriesModel.getViewRoot()?.getAncestors() ?? [],
            seriesModel,
            fallbackPalette
        )
        return nil
    }

    return handler
}()

private func travelTree(
    _ node: TreeNode,
    _ designatedVisual: TreemapVisual,
    _ viewRootAncestors: [TreeNode],
    _ seriesModel: TreemapSeriesModel,
    _ fallbackPalette: [Any]
) {
    // const nodeModel = node.getModel<TreemapSeriesNodeItemOption>();
    //   PORT-TODO: `node.getModel()` is `Model?` (nil for dataIndex < 0); upstream assumes non-null.
    //   Bail defensively — a node with no item model can not be visually encoded.
    guard let nodeModel = node.getModel() else {
        return
    }
    // const nodeLayout = node.getLayout();
    let nodeLayout = node.getLayout() as? [String: Any]
    // const data = node.hostTree.data;
    let data = node.hostTree.data!

    // Optimize
    // if (!nodeLayout || nodeLayout.invisible || !nodeLayout.isInView) { return; }
    guard let nodeLayout = nodeLayout,
          !((nodeLayout["invisible"] as? Bool) ?? false),
          (nodeLayout["isInView"] as? Bool) ?? false else {
        return
    }
    // const nodeItemStyleModel = nodeModel.getModel(ITEM_STYLE_NORMAL);
    let nodeItemStyleModel = nodeModel.getModel(ITEM_STYLE_NORMAL)
    let visuals = buildVisuals(nodeItemStyleModel, designatedVisual, seriesModel)

    // const existsStyle = data.ensureUniqueItemVisual(node.dataIndex, 'style');
    //   Upstream mutates the stored visual `style` object in place; the ported store returns a value
    //   dict, so read → mutate → write back (CONVENTIONS §3).
    var existsStyle = (data.ensureUniqueItemVisual(node.dataIndex, "style") as? [String: Any]) ?? [:]
    // calculate border color
    // let borderColor = nodeItemStyleModel.get('borderColor');
    var borderColor: Any? = nodeItemStyleModel.get("borderColor")
    // const borderColorSaturation = nodeItemStyleModel.get('borderColorSaturation');
    let borderColorSaturation = nodeItemStyleModel.get("borderColorSaturation") as? Double
    // let thisNodeColor;
    var thisNodeColor: Any?
    // if (borderColorSaturation != null) { ... }
    if borderColorSaturation != nil {
        // For performance, do not always execute 'calculateColor'.
        thisNodeColor = calculateColor(visuals)
        borderColor = calculateBorderColor(borderColorSaturation!, thisNodeColor)
    }
    // existsStyle.stroke = borderColor;
    existsStyle["stroke"] = borderColor

    // const viewChildren = node.viewChildren;
    let viewChildren = node.viewChildren
    // if (!viewChildren || !viewChildren.length) { ... } else { ... }
    if viewChildren.isEmpty {
        thisNodeColor = calculateColor(visuals)
        // Apply visual to this node.
        // existsStyle.fill = thisNodeColor;
        existsStyle["fill"] = thisNodeColor
    }
    else {
        let mapping = buildVisualMapping(
            node, nodeModel, nodeLayout, nodeItemStyleModel, visuals, viewChildren, fallbackPalette
        )

        // Designate visual to children.
        util.each(viewChildren) { (child: TreeNode, index: Int) in
            // If higher than viewRoot, only ancestors of viewRoot is needed to visit.
            if Int(child.depth) >= viewRootAncestors.count
                || child === viewRootAncestors[Int(child.depth)]
            {
                let childVisual = mapVisual(
                    nodeModel, visuals, child, index, mapping, seriesModel
                )
                travelTree(child, childVisual, viewRootAncestors, seriesModel, fallbackPalette)
            }
        }
    }

    // Write the mutated `existsStyle` back (see the ensureUniqueItemVisual note above).
    data.setItemVisual(node.dataIndex, "style", existsStyle)
}

private func buildVisuals(
    _ nodeItemStyleModel: Model,
    _ designatedVisual: TreemapVisual,
    _ seriesModel: TreemapSeriesModel
) -> TreemapVisual {
    // const visuals = extend({}, designatedVisual);
    var visuals: TreemapVisual = [:]
    _ = util.extend(&visuals, designatedVisual)
    // const designatedVisualItemStyle = seriesModel.designatedVisualItemStyle;
    // PORT-TODO: `seriesModel.designatedVisualItemStyle` is a scratch bag on TreemapSeriesModel that the
    //   node itemStyle resolution consults (parent-designated visual). Mutated in place below; assumed
    //   present on the sibling model as a `var designatedVisualItemStyle: [String: Any]`.

    // each(['color', 'colorAlpha', 'colorSaturation'] as const, function (visualName) {
    for visualName in ["color", "colorAlpha", "colorSaturation"] {
        // Priority: thisNode > thisLevel > parentNodeDesignated > seriesModel
        // designatedVisualItemStyle[visualName] = designatedVisual[visualName];
        seriesModel.designatedVisualItemStyle[visualName] = designatedVisual[visualName]
        // const val = nodeItemStyleModel.get(visualName);
        let val = nodeItemStyleModel.get(visualName)
        // designatedVisualItemStyle[visualName] = null;
        seriesModel.designatedVisualItemStyle[visualName] = nil

        // val != null && (visuals[visualName] = val);
        //   JS `!= null` is false for both `null` and `undefined`. The ported option bag represents an
        //   unset itemStyle color as `NSNull()` (see TreemapSeries defaults `itemStyle.color: NSNull()`),
        //   which is NOT Swift-`nil`, so a bare `val != nil` check spuriously OVERWRITES the palette color
        //   designated by the parent's mapping with NSNull → every tile fell to the black default fill.
        if val != nil && !(val is NSNull) {
            visuals[visualName] = val
        }
    }

    return visuals
}

private func calculateColor(_ visuals: TreemapVisual) -> Any? {
    // let color = getValueVisualDefine(visuals, 'color') as ColorString;
    var color = getValueVisualDefine(visuals, "color") as? String

    // if (color) {
    if let colorStr = color, treemapVisualJsTruthy(colorStr) {
        // const colorAlpha = getValueVisualDefine(visuals, 'colorAlpha') as number;
        let colorAlpha = getValueVisualDefine(visuals, "colorAlpha") as? Double
        // const colorSaturation = getValueVisualDefine(visuals, 'colorSaturation') as number;
        let colorSaturation = getValueVisualDefine(visuals, "colorSaturation") as? Double
        var mutColor = colorStr
        // if (colorSaturation) { color = modifyHSL(color, null, null, colorSaturation); }
        if let colorSaturation = colorSaturation, colorSaturation != 0, !colorSaturation.isNaN {
            mutColor = ZRenderKit.color.modifyHSL(mutColor, nil, nil, .number(colorSaturation)) ?? mutColor
        }
        // if (colorAlpha) { color = modifyAlpha(color, colorAlpha); }
        if let colorAlpha = colorAlpha, colorAlpha != 0, !colorAlpha.isNaN {
            mutColor = ZRenderKit.color.modifyAlpha(mutColor, colorAlpha) ?? mutColor
        }
        color = mutColor
        return color
    }
    return nil
}

private func calculateBorderColor(
    _ borderColorSaturation: Double,
    _ thisNodeColor: Any?
) -> Any? {
    // return thisNodeColor != null ? modifyHSL(thisNodeColor, null, null, borderColorSaturation) : null;
    if let thisNodeColor = thisNodeColor as? String {
        // Can only be string
        return ZRenderKit.color.modifyHSL(thisNodeColor, nil, nil, .number(borderColorSaturation))
    }
    return nil
}

// True when the node's inherited `visuals` already carry an explicit (non-'none') color, in which case
//   the palette fallback must NOT override the user/level-specified color range.
private func visualsHasExplicitColor(_ visuals: TreemapVisual) -> Bool {
    let c = visuals["color"]
    if c == nil || c is NSNull { return false }
    if let s = c as? String { return !s.isEmpty && s != "none" }
    return true
}

private func getValueVisualDefine(_ visuals: TreemapVisual, _ name: String) -> Any? {
    // const value = visuals[name];
    let value = visuals[name]
    // if (value != null && value !== 'none') { return value; }
    if value != nil, !(value is NSNull), (value as? String) != "none" {
        return value
    }
    return nil
}

private func buildVisualMapping(
    _ node: TreeNode,
    _ nodeModel: Model,
    _ nodeLayout: [String: Any],
    _ nodeItemStyleModel: Model,
    _ visuals: TreemapVisual,
    _ viewChildren: [TreeNode],
    _ fallbackPalette: [Any]
) -> Any? {
    // if (!viewChildren || !viewChildren.length) { return; }
    if viewChildren.isEmpty {
        return nil
    }

    // const rangeVisual = getRangeVisual(nodeModel, 'color')
    //     || (visuals.color != null && visuals.color !== 'none'
    //         && (getRangeVisual(nodeModel, 'colorAlpha') || getRangeVisual(nodeModel, 'colorSaturation')));
    var rangeVisual = getRangeVisual(nodeModel, "color")
    if rangeVisual == nil {
        let colorVisual = visuals["color"]
        if colorVisual != nil, !(colorVisual is NSNull), (colorVisual as? String) != "none" {
            rangeVisual = getRangeVisual(nodeModel, "colorAlpha") ?? getRangeVisual(nodeModel, "colorSaturation")
        }
    }

    // Fallback: the frozen level-0 color range came up empty (see travelTree note), so use the
    //   render-time palette as the color range for this node's children. Only applies when no explicit
    //   color range/visual was configured (the common auto-palette case).
    if rangeVisual == nil && !fallbackPalette.isEmpty && !visualsHasExplicitColor(visuals) {
        rangeVisual = ["name": "color", "range": fallbackPalette as Any]
    }

    // if (!rangeVisual) { return; }
    if rangeVisual == nil {
        return nil
    }

    // PORT-TODO: the full VisualMapping subsystem is DEFERRED. The upstream body builds a
    //   `VisualMapping` (category for color-by-index/id, linear otherwise). We port ONLY the common
    //   category color-by-index/id case (the treemap default `colorMappingBy: 'index'`), which is what
    //   distributes the palette across the children — without it every tile fell to the default black
    //   fill. The linear value-mapping (colorAlpha/colorSaturation ranges, colorMappingBy 'value') stays
    //   deferred and returns nil (children then inherit the parent visual unmapped, as before).
    //
    //   const opt = { type: rangeVisual.name, dataExtent, visual: rangeVisual.range };
    //   if (opt.type === 'color' && (colorMappingBy === 'index' || 'id')) { mappingMethod = 'category'; }
    let colorMappingBy = (nodeModel.get("colorMappingBy") as? String) ?? "index"
    if let rv = rangeVisual,
       (rv["name"] as? String) == "color",
       (colorMappingBy == "index" || colorMappingBy == "id"),
       let range = rv["range"] as? [Any], !range.isEmpty {
        _ = nodeLayout
        return ["type": "color", "range": range, "mappingBy": colorMappingBy] as [String: Any]
    }
    _ = node
    return nil
}

// Notice: If we don't have the attribute 'colorRange', but only use
// attribute 'color' to represent both concepts of 'colorRange' and 'color',
// (It means 'colorRange' when 'color' is Array, means 'color' when not array),
// this problem will be encountered:
// If a level-1 node doesn't have children, and its siblings have children,
// and colorRange is set on level-1, then the node cannot be colored.
// So we separate 'colorRange' and 'color' to different attributes.
private func getRangeVisual(_ nodeModel: Model, _ name: String) -> [String: Any]? {
    // 'colorRange', 'colorARange', 'colorSRange'.
    // If not exists on this node, fetch from levels and series.
    // const range = nodeModel.get(name);
    let range = nodeModel.get(name)
    // return (isArray(range) && range.length) ? { name, range } : null;
    if util.isArray(range), let arr = range as? [Any], !arr.isEmpty {
        return ["name": name, "range": range as Any]
    }
    return nil
}

private func mapVisual(
    _ nodeModel: Model,
    _ visuals: TreemapVisual,
    _ child: TreeNode,
    _ index: Int,
    _ mapping: Any?,
    _ seriesModel: TreemapSeriesModel
) -> TreemapVisual {
    // const childVisuals = extend({}, visuals);
    var childVisuals: TreemapVisual = [:]
    _ = util.extend(&childVisuals, visuals)

    // if (mapping) { ... childVisuals[mappingType] = mapping.mapValueToVisual(value); }
    //   Only the ported category color-by-index/id mapping (see buildVisualMapping) is handled; the
    //   deferred linear value mapping never produces a `mapping` bag. `mapValueToVisual` for a 'category'
    //   mapping with `loop: true` is `range[value % range.length]`.
    if let mapping = mapping as? [String: Any],
       let type = mapping["type"] as? String,
       let range = mapping["range"] as? [Any], !range.isEmpty {
        let mappingBy = (mapping["mappingBy"] as? String) ?? "index"
        // colorMappingBy 'id' would use seriesModel.mapIdToIndex(child.getId()); that id table is not
        //   ported, so fall back to the child ordinal (identical for the common auto-id case).
        _ = mappingBy
        let value = index
        let count = range.count
        let colorIdx = ((value % count) + count) % count
        childVisuals[type] = range[colorIdx]
    }
    _ = (nodeModel, child, seriesModel)

    return childVisuals
}

// JS truthiness of a color value (a non-empty string is truthy; nil / NSNull / "" are falsy). Mirrors
// the `if (color)` / `if (colorSaturation)` guards. Not an upstream symbol.
private func treemapVisualJsTruthy(_ v: Any?) -> Bool {
    switch v {
    case nil: return false
    case is NSNull: return false
    case let b as Bool: return b
    case let s as String: return !s.isEmpty
    case let d as Double: return d != 0 && !d.isNaN
    default: return true
    }
}
