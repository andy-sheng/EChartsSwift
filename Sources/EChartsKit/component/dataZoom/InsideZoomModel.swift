// Ported from echarts/src/component/dataZoom/InsideZoomModel.ts — keep in sync with upstream
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

import ZRenderKit

// import DataZoomModel, {DataZoomOption} from './DataZoomModel';   -> DataZoomModel (sibling)
// import { inheritDefaultOption } from '../../util/component';       -> component.inheritDefaultOption (util/componentUtil.swift)
//
// The `InsideDataZoomOption` interface (disabled/zoomLock/zoomOnMouseWheel/moveOnMouseMove/
// moveOnMouseWheel/preventDefaultMouseMove/cursorGrab/cursorGrabbing) is modeled by the `[String: Any]`
// bag (CONVENTIONS §2); only the defaultOption is emitted. The VIEW/roam logic is DEFERRED.

// class InsideZoomModel extends DataZoomModel<InsideDataZoomOption>
open class InsideZoomModel: DataZoomModel {

    // static readonly type = 'dataZoom.inside'; type = InsideZoomModel.type;
    public override class var type: ComponentFullType { return "dataZoom.inside" }

    // static defaultOption = inheritDefaultOption(DataZoomModel.defaultOption, { ... });
    public override class var defaultOption: ModelOption? {
        let base = (DataZoomModel.defaultOption as? [String: Any]) ?? [:]
        return component.inheritDefaultOption(base, [
            "disabled": false,           // Whether disable this inside zoom.
            "zoomLock": false,           // Whether disable zoom but only pan.
            "zoomOnMouseWheel": true,
            "moveOnMouseMove": true,
            "moveOnMouseWheel": false,
            "preventDefaultMouseMove": true
        ])
    }
}

// export default InsideZoomModel; -> `open class InsideZoomModel` above.
