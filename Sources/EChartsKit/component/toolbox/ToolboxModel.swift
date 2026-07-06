// Ported (MODEL + a subset of features) from echarts/src/component/toolbox/ToolboxModel.ts — keep in
// sync with upstream.
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

// class ToolboxModel extends ComponentModel<ToolboxOption>
//   The toolbox component. Its `feature` sub-option enables per-feature buttons (restore / magicType /
//   dataZoom / saveAsImage / dataView / brush). This port wires the DATA/ACTION core of the option-
//   expressible features (`restore`, `magicType`) via `toolboxAction.swift`; the on-canvas icon VIEW +
//   the host-dependent features (saveAsImage → canvas export, dataView → HTML overlay) are DEFERRED.
public typealias ToolboxOption = [String: Any]

open class ToolboxModel: ComponentModel {

    // static type = 'toolbox' as const;
    public override class var type: ComponentFullType { return "toolbox" }

    // The layout/box fields are `mergeLayoutParam`-consumed upstream; the slim port keeps the raw bag.
    // static defaultOption: ToolboxOption = { ... }
    public override class var defaultOption: ModelOption? {
        return [
            "show": true,
            // z / zlevel
            "z": 6.0,
            // 'horizontal' | 'vertical'
            "orient": "horizontal",
            "left": "right",
            "top": "top",
            // "right" / "bottom" resolved by layout
            "backgroundColor": "transparent",
            "borderColor": tokens.color.border,
            "borderRadius": 0.0,
            "borderWidth": 0.0,
            "padding": 5.0,
            "itemSize": 15.0,
            "itemGap": 8.0,
            "showTitle": true,
            // feature: { saveAsImage, restore, dataView, dataZoom, magicType, brush } — user-supplied.
            "feature": [String: Any]()
        ]
    }
}
