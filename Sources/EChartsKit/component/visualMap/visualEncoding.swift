// Ported from echarts/src/component/visualMap/visualEncoding.ts — keep in sync with upstream
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

// import * as zrUtil from 'zrender/src/core/util';        -> `util.bind` (ZRenderKit).
// import * as visualSolution from '../../visual/visualSolution';
//   -> visualSolution IS ported (visual/visualSolution.swift). Its
//      `incrementalApplyVisual(stateList, visualMappings, getValueState, dim)` builds the
//      per-data-point `StageHandlerProgressExecutor` that actually walks the store and
//      `setItemVisual`s the mapped visual.
// import VisualMapping from '../../visual/VisualMapping';
//   -> VisualMapping IS ported (visual/VisualMapping.swift). `prepareVisualTypes` and
//      `mapping.applyVisual(value, getVisual, setVisual)` (the value->color/opacity/symbol/... encoder)
//      are available — this is the color-math core (zrColor.parse / fastLerp / lift / stringify).
// import VisualMapModel, { VisualMeta } from './VisualMapModel';
//   -> VisualMapModel IS ported (component/visualMap/VisualMapModel.swift). The
//      component model that owns `stateList` / `targetVisuals` / `getValueState` / `isTargetSeries` /
//      `getDataDimensionIndex` / `getVisualMeta`.
// import { StageHandlerProgressExecutor, BuiltinVisualProperty, ParsedValue, StageHandler } from '../../util/types';
//   -> `StageHandler` / `StageHandlerProgressExecutor` / `BuiltinVisualProperty` / `ParsedValue` (util/types.swift).
// import SeriesModel from '../../model/Series';            -> `SeriesModel` (model/Series.swift).
// import { getVisualFromData } from '../../visual/helper';
//   -> visual/helper.ts not ported as a namespace; a minimal faithful `getVisualFromData` is inlined at
//      the bottom of this file (same convention as component/marker/MarkPointView.swift).

// export const visualMapEncodingHandlers: StageHandler[] = [ ... ];
//
// These are the visualMap VISUAL-STAGE handlers. Registered (installCommon.ts) via
//   `registers.registerVisual(registers.PRIORITY.VISUAL.COMPONENT, handler)` — i.e. AFTER each series'
//   own visual stage, so they overwrite the palette color with the value->visual encoding.
//
// PORT-NOTE: the reset bodies below run the real encoding, using the now-ported VisualMapModel +
//   visualSolution + VisualMapping subsystems (see imports). The `StageHandler`
//   objects are still produced so the Orchestrate driver can register them at
//   PRIORITY.VISUAL.COMPONENT once those land.
public let visualMapEncodingHandlers: [StageHandler] = [
    // Handler #1 — incremental value->visual encoding for every target series/data point.
    {
        var handler = StageHandler()
        handler.createOnAllSeries = true
        handler.reset = { (seriesModel: SeriesModel, ecModel: GlobalModel, _ api: ExtensionAPI, _ payload: Payload?) -> Any? in
            var resetDefines: [StageHandlerProgressExecutor] = []
            ecModel.eachComponent("visualMap") { (componentModel: ComponentModel, _ idx: Double) in
                guard let visualMapModel = componentModel as? VisualMapModel else { return }
                // const pipelineContext = seriesModel.pipelineContext;
                // if (!visualMapModel.isTargetSeries(seriesModel) || (pipelineContext && pipelineContext.large)) return;
                //   PORT-NOTE (deferred): requires pipelineContext.large (progressive/large mode), not
                //   modeled in the pipeline; the large-mode short-circuit is omitted (a basic render is
                //   never `large`).
                if !visualMapModel.isTargetSeries(seriesModel) {
                    return
                }

                // resetDefines.push(visualSolution.incrementalApplyVisual(
                //     visualMapModel.stateList,
                //     visualMapModel.targetVisuals,
                //     zrUtil.bind(visualMapModel.getValueState, visualMapModel),
                //     visualMapModel.getDataDimensionIndex(seriesModel.getData())
                // ));
                let targetVisuals = visualMapModel.targetVisuals.compactMapValues { $0 as? [String: VisualMapping] }
                let getValueState: (Any?) -> String = { value in
                    visualMapModel.getValueState(value) ?? ""
                }
                let dimIdx = visualMapModel.getDataDimensionIndex(seriesModel.getData())
                let dim: DimensionLoose? = dimIdx.map { $0 as DimensionLoose }
                let executor = visualSolution.incrementalApplyVisual(
                    visualMapModel.stateList,
                    targetVisuals,
                    getValueState,
                    dim
                )
                resetDefines.append(executor)
            }

            return resetDefines
        }
        return handler
    }(),

    // Handler #2 — Only support color. Emits `visualMeta` (the gradient stops used by heatmap/tooltip).
    {
        var handler = StageHandler()
        handler.createOnAllSeries = true
        handler.reset = { (seriesModel: SeriesModel, ecModel: GlobalModel, _ api: ExtensionAPI, _ payload: Payload?) -> Any? in
            let data = seriesModel.getData()
            // const visualMetaList: VisualMeta[] = [];
            var visualMetaList: [VisualMeta] = []

            ecModel.eachComponent("visualMap") { (componentModel: ComponentModel, _ idx: Double) in
                guard let visualMapModel = componentModel as? VisualMapModel else { return }
                // if (visualMapModel.isTargetSeries(seriesModel)) {
                if visualMapModel.isTargetSeries(seriesModel) {
                    // const visualMeta = visualMapModel.getVisualMeta(
                    //     zrUtil.bind(getColorVisual, null, seriesModel, visualMapModel)
                    // ) || { stops: [], outerColors: [] } as VisualMeta;
                    let getColor: (Double, String) -> String = { value, valueState in
                        getColorVisual(seriesModel, visualMapModel, value, valueState)
                    }
                    var visualMeta = visualMapModel.getVisualMeta(getColor)
                        ?? VisualMeta(stops: [], outerColors: [])

                    // const dimIdx = visualMapModel.getDataDimensionIndex(data);
                    if let dimIdx = visualMapModel.getDataDimensionIndex(data), dimIdx >= 0 {
                        // visualMeta.dimension should be dimension index, but not concrete dimension.
                        visualMeta.dimension = dimIdx
                        visualMetaList.append(visualMeta)
                    }
                }
            }

            // seriesModel.getData().setVisual('visualMeta', visualMetaList);
            data.setVisual("visualMeta", visualMetaList)
            return nil
        }
        return handler
    }()
]

// function getColorVisual(seriesModel, visualMapModel, value, valueState) — maps one parsed value in a
//   given valueState to a color, by running each of the mapping's visual types through
//   `mapping.applyVisual(value, getVisual, setVisual)` over a local `resultVisual` bag seeded with the
//   series' default color. It is the callback `getVisualMeta` uses to sample the gradient.
private func getColorVisual(
    _ seriesModel: SeriesModel,
    _ visualMapModel: VisualMapModel,
    _ value: Double,
    _ valueState: String
) -> String {
    // const mappings = visualMapModel.targetVisuals[valueState];
    let mappings = (visualMapModel.targetVisuals[valueState] as? [String: VisualMapping]) ?? [:]
    // const visualTypes = VisualMapping.prepareVisualTypes(mappings);
    let visualTypes = VisualMapping.prepareVisualTypes(mappings)
    // const resultVisual = { color: getVisualFromData(seriesModel.getData(), 'color') };
    var resultVisual: [String: Any] = [:]
    if let defColor = getVisualFromData(seriesModel.getData(), "color") {
        resultVisual["color"] = defColor
    }

    let getVisual: VisualValueGetter = { key in resultVisual[key] }
    let setVisual: VisualValueSetter = { key, value in resultVisual[key] = value }

    for type in visualTypes {
        // const mapping = mappings[type === 'opacity' ? '__alphaForOpacity' : type];
        let key = (type == "opacity") ? "__alphaForOpacity" : type
        // mapping && mapping.applyVisual(value, getVisual, setVisual);
        if let mapping = mappings[key] {
            mapping.applyVisual(value, getVisual, setVisual)
        }
    }

    // return resultVisual.color;
    return (resultVisual["color"] as? String) ?? ""
}

// FIXME
// performance and export for heatmap?
// value can be Infinity or -Infinity
//
// PORT-NOTE: `getColorVisual` (implemented above) maps one parsed value in a given
//   valueState to a color, by running each of the mapping's visual types through
//   `mapping.applyVisual(value, getVisual, setVisual)` over a local `resultVisual` bag seeded with the
//   series' default color (`getVisualFromData(data, 'color')`). It is the callback `getVisualMeta` uses
//   to sample the gradient. Faithful upstream source preserved below for reference.
//
//   function getColorVisual(
//       seriesModel: SeriesModel,
//       visualMapModel: VisualMapModel,
//       value: ParsedValue,
//       valueState: VisualMapModel['stateList'][number]
//   ) {
//       const mappings = visualMapModel.targetVisuals[valueState];
//       const visualTypes = VisualMapping.prepareVisualTypes(mappings);
//       const resultVisual: Partial<Record<BuiltinVisualProperty, any>> = {
//           color: getVisualFromData(seriesModel.getData(), 'color') // default color.
//       };
//
//       for (let i = 0, len = visualTypes.length; i < len; i++) {
//           const type = visualTypes[i];
//           const mapping = mappings[
//               (type === 'opacity' ? '__alphaForOpacity' : type) as BuiltinVisualProperty
//           ];
//           mapping && mapping.applyVisual(value, getVisual, setVisual);
//       }
//
//       return resultVisual.color;
//
//       function getVisual(key: BuiltinVisualProperty) {
//           return resultVisual[key];
//       }
//
//       function setVisual(key: BuiltinVisualProperty, value: any) {
//           resultVisual[key] = value;
//       }
//   }

// MARK: - Minimal faithful port of `visual/helper.ts#getVisualFromData` (the seed default color used by
//   the deferred `getColorVisual`). Same convention as component/marker/MarkPointView.swift.
private func getVisualFromData(_ data: SeriesData, _ key: String) -> Any? {
    switch key {
    case "color":
        // const style = data.getVisual('style'); return style[data.getVisual('drawType')];
        let style = data.getVisual("style") as? [String: Any]
        let drawType = (data.getVisual("drawType") as? String) ?? "fill"
        return style?[drawType]
    case "opacity":
        // return data.getVisual('style').opacity;
        return (data.getVisual("style") as? [String: Any])?["opacity"]
    case "symbol", "symbolSize", "liftZ":
        return data.getVisual(key)
    default:
        // if (__DEV__) { console.warn(`Unknown visual type ${key}`); }
        return nil
    }
}
