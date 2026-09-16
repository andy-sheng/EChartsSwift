// Ported from echarts/src/component/helper/cursorHelper.ts — keep in sync with upstream
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
//   import { ElementEvent } from 'zrender/src/Element';           -> ZRenderKit `ElementEvent`.
//   import ExtensionAPI from '../../core/ExtensionAPI';            -> `ExtensionAPI`.
//   import { CoordinateSystemHostModel } from '../../coord/CoordinateSystem'; -> the `coordinateSystem`
//       slot read off the resolved component (see below).
//   import type Component from '../../model/Component';            -> `ComponentModel`.
//   import { retrieveZInfo } from '../../util/graphic';            -> `retrieveZInfo` (RoamController.swift).

// upstream: const IRRELEVANT_EXCLUDES = {'axisPointer': 1, 'tooltip': 1, 'brush': 1};
private let IRRELEVANT_EXCLUDES: Set<String> = ["axisPointer", "tooltip", "brush"]

/**
 * Used on roam/brush triggering determination.
 * This is to avoid that: mouse clicking on an elements that is over geo or graph,
 * but roam is triggered unexpectedly.
 */
// upstream: export function onIrrelevantElement(e, api, targetComponent): boolean
public func onIrrelevantElement(
    _ e: ElementEvent,
    _ api: ExtensionAPI,
    _ targetComponent: ComponentModel
) -> Bool {
    // upstream: const eventElComponent = api.getComponentByElement(e.topTarget);
    //   `topTarget` can be nil for an event over empty canvas — upstream reads it off a real DOM hit,
    //   here guard it so `getComponentByElement` is never handed a nil (its Swift signature is non-optional).
    guard let topTarget = e.topTarget else {
        return false
    }
    let eventElComponent = api.getComponentByElement(topTarget)

    // upstream: if (!eventElComponent || eventElComponent === targetComponent
    //     || IRRELEVANT_EXCLUDES.hasOwnProperty(eventElComponent.mainType)) { return false; }
    //   A sentinel empty component (mainType "") returned by `getComponentByElement` for an unresolved
    //   element is `!== targetComponent` and not in EXCLUDES, so it flows to the coordinateSystem check
    //   below and returns false there (roam proceeds) — matching upstream's conservative default.
    if eventElComponent === targetComponent
        || IRRELEVANT_EXCLUDES.contains(eventElComponent.mainType) {
        return false
    }

    // upstream: const eventElCoordSys = (eventElComponent as CoordinateSystemHostModel).coordinateSystem;
    //   if (!eventElCoordSys || eventElCoordSys.model === targetComponent) { return false; }
    //   `coordinateSystem` is split across two slots in this port — a coord-sys HOST
    //   model (GridModel/PolarModel/…) declares it via `CoordinateSystemHostModel` (a
    //   `CoordinateSystemMaster`), while a SeriesModel stores its own (a `CoordinateSystem`).
    //   Read whichever slot the covering component carries (mirrors ECharts.containPixel) so an
    //   axis/grid model covering the target is not skipped and still hits the coordSys/z-order check.
    let eventElCoordSysModel: ComponentModel?
    let hasEventElCoordSys: Bool
    if let host = eventElComponent as? CoordinateSystemHostModel, let coordSys = host.coordinateSystem {
        hasEventElCoordSys = true
        eventElCoordSysModel = coordSys.model
    } else if let series = eventElComponent as? SeriesModel,
              let coordSys = series.coordinateSystem as? CoordinateSystem {
        hasEventElCoordSys = true
        eventElCoordSysModel = coordSys.model
    } else {
        hasEventElCoordSys = false
        eventElCoordSysModel = nil
    }
    if !hasEventElCoordSys || eventElCoordSysModel === targetComponent {
        return false
    }

    // upstream: z-order precedence. If the covering component is not strictly above the target, roam is
    //   still allowed on the target (return false).
    let eventElCmptZInfo = retrieveZInfo(eventElComponent)
    let targetCmptZInfo = retrieveZInfo(targetComponent)
    if ((eventElCmptZInfo.zlevel - targetCmptZInfo.zlevel) != 0
            ? (eventElCmptZInfo.zlevel - targetCmptZInfo.zlevel)
            : (eventElCmptZInfo.z - targetCmptZInfo.z)) <= 0 {
        return false
    }

    return true
}
