// Ported from echarts/src/component/dataZoom/SliderZoomModel.ts — keep in sync with upstream
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

// import DataZoomModel, {DataZoomOption} from './DataZoomModel';   -> DataZoomModel (sibling)
// import { BoxLayoutOptionMixin, ZRColor, LineStyleOption, AreaStyleOption, ItemStyleOption,
//     LabelOption, ComponentOnMatrixOptionMixin, ComponentOnCalendarOptionMixin } from '../../util/types';
//   -> option interfaces (`SliderDataZoomOption`, `SliderHandleLabelOption`) modeled by the
//      `[String: Any]` bag (CONVENTIONS §2). Only the defaultOption is emitted; the VIEW logic is DEFERRED.
// import { inheritDefaultOption } from '../../util/component';       -> component.inheritDefaultOption
// import tokens from '../../visual/tokens';                          -> `tokens` (visual/tokens.swift)

// class SliderZoomModel extends DataZoomModel<SliderDataZoomOption>
open class SliderZoomModel: DataZoomModel {

    // static readonly type = 'dataZoom.slider'; type = SliderZoomModel.type;
    public override class var type: ComponentFullType { return "dataZoom.slider" }

    // static readonly layoutMode = 'box';
    public override class var layoutMode: Any? { return "box" }

    // static defaultOption = inheritDefaultOption(DataZoomModel.defaultOption, { ... });
    public override class var defaultOption: ModelOption? {
        let base = (DataZoomModel.defaultOption as? [String: Any]) ?? [:]
        return component.inheritDefaultOption(base, [
            "show": true,

            // deault value can only be drived in view stage.
            "right": "ph",   // Default align to grid rect.
            "top": "ph",     // Default align to grid rect.
            "width": "ph",   // Default align to grid rect.
            "height": "ph",  // Default align to grid rect.
            "left": NSNull(),   // Default align to grid rect. (null)
            "bottom": NSNull(), // Default align to grid rect. (null)

            "borderColor": tokens.color.accent10,
            "borderRadius": 0.0,

            "backgroundColor": tokens.color.transparent,   // Background of slider zoom component.

            // dataBackgroundColor: '#ddd',
            "dataBackground": [
                "lineStyle": [
                    "color": tokens.color.accent30,
                    "width": 0.5
                ] as [String: Any],
                "areaStyle": [
                    "color": tokens.color.accent20,
                    "opacity": 0.2
                ] as [String: Any]
            ] as [String: Any],

            "selectedDataBackground": [
                "lineStyle": [
                    "color": tokens.color.accent40,
                    "width": 0.5
                ] as [String: Any],
                "areaStyle": [
                    "color": tokens.color.accent20,
                    "opacity": 0.3
                ] as [String: Any]
            ] as [String: Any],

            // Color of selected window.
            "fillerColor": "rgba(135,175,274,0.2)",
            "handleIcon": "path://M-9.35,34.56V42m0-40V9.5m-2,0h4a2,2,0,0,1,2,2v21a2,2,0,0,1-2,2h-4a2,2,0,0,1-2-2v-21A2,2,0,0,1-11.35,9.5Z",
            // Percent of the slider height
            "handleSize": "100%",

            "handleStyle": [
                "color": tokens.color.neutral00,
                "borderColor": tokens.color.accent20
            ] as [String: Any],

            "moveHandleSize": 7.0,
            "moveHandleIcon": "path://M-320.9-50L-320.9-50c18.1,0,27.1,9,27.1,27.1V85.7c0,18.1-9,27.1-27.1,27.1l0,0c-18.1,0-27.1-9-27.1-27.1V-22.9C-348-41-339-50-320.9-50z M-212.3-50L-212.3-50c18.1,0,27.1,9,27.1,27.1V85.7c0,18.1-9,27.1-27.1,27.1l0,0c-18.1,0-27.1-9-27.1-27.1V-22.9C-239.4-41-230.4-50-212.3-50z M-103.7-50L-103.7-50c18.1,0,27.1,9,27.1,27.1V85.7c0,18.1-9,27.1-27.1,27.1l0,0c-18.1,0-27.1-9-27.1-27.1V-22.9C-130.9-41-121.8-50-103.7-50z",
            "moveHandleStyle": [
                "color": tokens.color.accent40,
                "opacity": 0.5
            ] as [String: Any],

            "showDetail": true,
            "showDataShadow": "auto",   // Default auto decision.
            "realtime": true,
            "zoomLock": false,          // Whether disable zoom.

            "textStyle": [
                "color": tokens.color.tertiary
            ] as [String: Any],

            "brushSelect": true,
            "brushStyle": [
                "color": tokens.color.accent30,
                "opacity": 0.3
            ] as [String: Any],

            "emphasis": [
                "handleLabel": [
                    "show": true
                ] as [String: Any],
                "handleStyle": [
                    "borderColor": tokens.color.accent40
                ] as [String: Any],
                "moveHandleStyle": [
                    "opacity": 0.8
                ] as [String: Any]
            ] as [String: Any],

            "defaultLocationEdgeGap": 15.0
        ])
    }
}

// export default SliderZoomModel; -> `open class SliderZoomModel` above.
