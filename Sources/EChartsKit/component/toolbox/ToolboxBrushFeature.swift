// Ported from echarts/src/component/toolbox/feature/Brush.ts — keep in sync with upstream.
// FILE NAME: upstream `feature/Brush.ts`; the port keeps every toolbox feature in
//   component/toolbox/* (see toolboxFeatures.swift, which holds SaveAsImage/Restore/MagicType/DataZoom).
//   This one lives in its own file only to keep the brush milestone's diff self-contained.
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

// import { ToolboxFeatureModel, ToolboxFeatureOption, ToolboxFeature } from '../featureManager';
// import BrushModel from '../../brush/BrushModel';
// import { BrushTypeUncertain } from '../../helper/BrushController';

// const ICON_TYPES = ['rect', 'polygon', 'lineX', 'lineY', 'keep', 'clear'] as const;
let BRUSH_ICON_TYPES: [String] = ["rect", "polygon", "lineX", "lineY", "keep", "clear"]

// export interface ToolboxBrushFeatureOption extends ToolboxFeatureOption { type?; icon?; title?; }
//   -> the `[String: Any]` option bag (CONVENTIONS §2).

// class BrushFeature extends ToolboxFeature<ToolboxBrushFeatureOption>
open class ToolboxBrushFeature: ToolboxFeature {

    // private _brushType: BrushTypeUncertain;
    private var _brushType: BrushTypeUncertain = nil
    // private _brushMode: string;
    private var _brushMode: String?

    // render(featureModel, ecModel, api)
    open override func render(
        _ featureModel: ToolboxFeatureModel, _ ecModel: GlobalModel, _ api: ExtensionAPI, _ payload: Payload
    ) {
        var brushType: BrushTypeUncertain = nil
        var brushMode: String?
        var isBrushed = false

        // ecModel.eachComponent({mainType: 'brush'}, function (brushModel: BrushModel) {
        //     brushType = brushModel.brushType;
        //     brushMode = brushModel.brushOption.brushMode || 'single';
        //     isBrushed = isBrushed || !!brushModel.areas.length;
        // });
        ecModel.eachComponent("brush") { brushModelIn, _ in
            guard let brushModel = brushModelIn as? BrushModel else { return }
            // See `applyTakeGlobalCursor`'s PORT-NOTE (stage order): upstream's brush VISUAL stage has
            //   already applied the `takeGlobalCursor` payload by the time any view renders, so the icon
            //   status below reflects the click that just happened. This driver renders components BEFORE
            //   the brush visual, so apply it here too (idempotent — brushVisual makes the identical call).
            //   Without this the button's emphasis state, and its click-again-to-disarm toggle, lag a frame.
            applyTakeGlobalCursor(brushModel, payload)

            brushType = brushModel.brushType
            brushMode = (brushModel.brushOption["brushMode"] as? String) ?? "single"
            isBrushed = isBrushed || !brushModel.areas.isEmpty
        }
        self._brushType = brushType
        self._brushMode = brushMode

        // zrUtil.each(featureModel.get('type', true), function (type) {
        //     featureModel.setIconStatus(type, (
        //         type === 'keep' ? brushMode === 'multiple'
        //         : type === 'clear' ? isBrushed
        //         : type === brushType
        //     ) ? 'emphasis' : 'normal');
        // });
        let types = (featureModel.get("type", true) as? [Any]) ?? []
        util.each(types) { t, _ in
            guard let type = t as? String else { return }
            let on: Bool
            if type == "keep" {
                on = brushMode == "multiple"
            }
            else if type == "clear" {
                on = isBrushed
            }
            else {
                on = (type == brushType)
            }
            toolboxSetIconStatus(featureModel, type, on ? "emphasis" : "normal")
        }
    }

    // updateView(featureModel, ecModel, api) { this.render(featureModel, ecModel, api); }
    open override func updateView(
        _ featureModel: ToolboxFeatureModel, _ ecModel: GlobalModel, _ api: ExtensionAPI, _ payload: Payload
    ) {
        self.render(featureModel, ecModel, api, payload)
    }

    // getIcons() — filter the icon group by the enabled `type`s.
    open override func getIcons() -> [String: String]? {
        let model = self.model
        let availableIcons = (model?.get("icon", true) as? [String: Any]) ?? [:]
        var icons: [String: String] = [:]
        let types = (model?.get("type", true) as? [Any]) ?? []
        util.each(types) { t, _ in
            guard let type = t as? String else { return }
            if let icon = availableIcons[type] as? String {
                icons[type] = icon
            }
        }
        return icons
    }

    // onclick(ecModel, api, type: IconType)
    open override func onclick(_ ecModel: GlobalModel, _ api: ExtensionAPI, _ type: String) {
        let brushType = self._brushType
        let brushMode = self._brushMode

        if type == "clear" {
            // Trigger parallel action firstly
            // api.dispatchAction({type: 'axisAreaSelect', intervals: []});
            var pa = Payload(type: "axisAreaSelect")
            pa.other["intervals"] = [Any]()
            api.dispatchAction(pa)

            // api.dispatchAction({type: 'brush', command: 'clear', areas: []});
            var pb = Payload(type: "brush")
            pb.other["command"] = "clear"
            // Clear all areas of all brush components.
            pb.other["areas"] = [[String: Any]]()
            api.dispatchAction(pb)
        }
        else {
            // api.dispatchAction({type: 'takeGlobalCursor', key: 'brush', brushOption: {
            //     brushType: type === 'keep' ? brushType : (brushType === type ? false : type),
            //     brushMode: type === 'keep' ? (brushMode === 'multiple' ? 'single' : 'multiple') : brushMode
            // }});
            var brushOption: [String: Any] = [:]
            // `false` (disable) -> NSNull(): the key must be PRESENT and falsy (see BrushModel's
            //   generateBrushOption, which merges this over the component option's `brushType` default).
            let nextBrushType: Any
            if type == "keep" {
                nextBrushType = brushType.map { $0 as Any } ?? NSNull()
            }
            else {
                // `brushType === type ? false : type` — clicking the ACTIVE tool toggles the brush off.
                nextBrushType = (brushType == type) ? NSNull() : (type as Any)
            }
            brushOption["brushType"] = nextBrushType
            brushOption["brushMode"] = (type == "keep")
                ? (brushMode == "multiple" ? "single" : "multiple")
                : (brushMode ?? "single")

            var p = Payload(type: "takeGlobalCursor")
            p.other["key"] = "brush"
            p.other["brushOption"] = brushOption
            api.dispatchAction(p)
        }
    }

    // static getDefaultOption(ecModel: GlobalModel)
    public static func getDefaultOption(_ ecModel: GlobalModel) -> [String: Any] {
        let defaultOption: [String: Any] = [
            "show": true,
            "type": BRUSH_ICON_TYPES,
            "icon": [
                /* eslint-disable */
                "rect": "M7.3,34.7 M0.4,10V-0.2h9.8 M89.6,10V-0.2h-9.8 M0.4,60v10.2h9.8 M89.6,60v10.2h-9.8 M12.3,22.4V10.5h13.1 M33.6,10.5h7.8 M49.1,10.5h7.8 M77.5,22.4V10.5h-13 M12.3,31.1v8.2 M77.7,31.1v8.2 M12.3,47.6v11.9h13.1 M33.6,59.5h7.6 M49.1,59.5 h7.7 M77.5,47.6v11.9h-13",
                "polygon": "M55.2,34.9c1.7,0,3.1,1.4,3.1,3.1s-1.4,3.1-3.1,3.1 s-3.1-1.4-3.1-3.1S53.5,34.9,55.2,34.9z M50.4,51c1.7,0,3.1,1.4,3.1,3.1c0,1.7-1.4,3.1-3.1,3.1c-1.7,0-3.1-1.4-3.1-3.1 C47.3,52.4,48.7,51,50.4,51z M55.6,37.1l1.5-7.8 M60.1,13.5l1.6-8.7l-7.8,4 M59,19l-1,5.3 M24,16.1l6.4,4.9l6.4-3.3 M48.5,11.6 l-5.9,3.1 M19.1,12.8L9.7,5.1l1.1,7.7 M13.4,29.8l1,7.3l6.6,1.6 M11.6,18.4l1,6.1 M32.8,41.9 M26.6,40.4 M27.3,40.2l6.1,1.6 M49.9,52.1l-5.6-7.6l-4.9-1.2",
                "lineX": "M15.2,30 M19.7,15.6V1.9H29 M34.8,1.9H40.4 M55.3,15.6V1.9H45.9 M19.7,44.4V58.1H29 M34.8,58.1H40.4 M55.3,44.4 V58.1H45.9 M12.5,20.3l-9.4,9.6l9.6,9.8 M3.1,29.9h16.5 M62.5,20.3l9.4,9.6L62.3,39.7 M71.9,29.9H55.4",
                "lineY": "M38.8,7.7 M52.7,12h13.2v9 M65.9,26.6V32 M52.7,46.3h13.2v-9 M24.9,12H11.8v9 M11.8,26.6V32 M24.9,46.3H11.8v-9 M48.2,5.1l-9.3-9l-9.4,9.2 M38.9-3.9V12 M48.2,53.3l-9.3,9l-9.4-9.2 M38.9,62.3V46.4",
                "keep": "M4,10.5V1h10.3 M20.7,1h6.1 M33,1h6.1 M55.4,10.5V1H45.2 M4,17.3v6.6 M55.6,17.3v6.6 M4,30.5V40h10.3 M20.7,40 h6.1 M33,40h6.1 M55.4,30.5V40H45.2 M21,18.9h62.9v48.6H21V18.9z",
                "clear": "M22,14.7l30.9,31 M52.9,14.7L22,45.7 M4.7,16.8V4.2h13.1 M26,4.2h7.8 M41.6,4.2h7.8 M70.3,16.8V4.2H57.2 M4.7,25.9v8.6 M70.3,25.9v8.6 M4.7,43.2v12.6h13.1 M26,55.8h7.8 M41.6,55.8h7.8 M70.3,43.2v12.6H57.2"
                /* eslint-enable */
            ] as [String: Any],
            // `rect`, `polygon`, `lineX`, `lineY`, `keep`, `clear`
            // title: ecModel.getLocaleModel().get(['toolbox', 'brush', 'title'])
            "title": ecModel.getLocaleModel().get(["toolbox", "brush", "title"]) ?? [String: Any]()
        ]

        return defaultOption
    }
}

// export default BrushFeature;  -> `open class ToolboxBrushFeature` above.
