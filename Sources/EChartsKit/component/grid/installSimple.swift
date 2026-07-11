// Ported from echarts/src/component/grid/installSimple.ts — keep in sync with upstream
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

// import { EChartsExtensionInstallRegisters } from '../../extension';   -> PORT-NOTE: registers/install
//   boilerplate deferred to the Orchestrate driver (see `install` note at the bottom).
// import ComponentView from '../../view/Component';                     -> `ComponentView` (view/ComponentView.swift).
// import GridModel from '../../coord/cartesian/GridModel';              -> `GridModel` (coord/cartesian/GridModel.swift).
// import GlobalModel from '../../model/Global';                         -> `GlobalModel` (model/Global.swift).
// import { Rect } from '../../util/graphic';                            -> ZRenderKit `Rect` (util/graphic.ts re-exports zrender's Rect).
// import { defaults } from 'zrender/src/core/util';                     -> `util.defaults` (ZRenderKit).
// import {CartesianAxisOption, CartesianAxisModel} from '../../coord/cartesian/AxisModel';
//   -> `CartesianAxisModel` (coord/cartesian/AxisModel.swift); CartesianAxisOption is the dynamic bag.
// import axisModelCreator from '../../coord/axisModelCreator';          -> `axisModelCreator` (coord/axisModelCreator.swift).
// import Grid from '../../coord/cartesian/Grid';                        -> `Grid` (coord/cartesian/Grid.swift).
// import {CartesianXAxisView, CartesianYAxisView} from '../axis/CartesianAxisView';
//   -> sibling `CartesianXAxisView` / `CartesianYAxisView` (component/axis/CartesianAxisView.swift).

// Grid view
// CONVENTIONS §2/§4: reference type extending the reference `ComponentView` -> `final class`.
public final class GridView: ComponentView {
    // static readonly type = 'grid';
    public static let type = "grid"
    // readonly type = 'grid';
    public let type = "grid"

    // upstream: render(gridModel: GridModel, ecModel: GlobalModel)
    // PORT-NOTE: the base `ComponentView.render` signature is (model, ecModel, api, payload); upstream
    //   GridView.render declares only (gridModel, ecModel) (the trailing args are optional in JS). The
    //   override matches the full base signature and narrows `model` to `GridModel` (cf. BarView.render).
    public override func render(
        _ model: ComponentModel, _ ecModel: GlobalModel, _ api: ExtensionAPI, _ payload: Payload
    ) {
        let gridModel = model as! GridModel

        self.group.removeAll()
        // if (gridModel.get('show')) {
        if truthy(gridModel.get("show")) {
            // style: defaults({ fill: gridModel.get('backgroundColor') }, gridModel.getItemStyle())
            // PORT-NOTE: upstream `defaults({fill}, ...)` merges into a dynamic style object which the
            //   Rect consumes directly. Here the merge is done on the `[String: Any]` bag, then bridged
            //   to the typed `PathStyleProps` via `barStyleFromDict` (the shared getItemStyle→style seam,
            //   BarView.swift). If `backgroundColor` is nil the `fill` key is omitted so `defaults` fills
            //   it from `getItemStyle()` (matches JS `{fill: undefined}` being treated as absent).
            var style: [String: Any] = [:]
            if let backgroundColor = gridModel.get("backgroundColor") {
                style["fill"] = backgroundColor
            }
            _ = util.defaults(&style, gridModel.getItemStyle())

            // shape: gridModel.coordinateSystem.getRect()
            // PORT-NOTE: `coordinateSystem` is typed `CoordinateSystemMaster?` (see GridModel); narrow to
            //   the concrete `Grid` whose `getRect(): LayoutRect` is available. Upstream passes the
            //   `RectLike` straight through; here it seeds a `RectShape` (x/y/width/height).
            var shape = RectShape()
            if let coordinateSystem = gridModel.coordinateSystem as? Grid {
                let rect = coordinateSystem.getRect()
                shape.x = rect.x
                shape.y = rect.y
                shape.width = rect.width
                shape.height = rect.height
            }

            self.group.add(Rect([
                "shape": shape,
                "style": barStyleFromDict(style),
                "silent": true,
                "z2": -1.0
            ]))
        }
    }

}

// JS truthiness of the dynamic `gridModel.get('show')` value (Any?): nil/false/0/""/NaN -> false,
// everything else -> true. Modeled explicitly per CONVENTIONS §6 (the `show` option is a Bool, but
// the getter is dynamically typed).
private func truthy(_ value: Any?) -> Bool {
    switch value {
    case .none:
        return false
    case .some(let v):
        if let b = v as? Bool { return b }
        if let d = v as? Double { return d != 0 && !d.isNaN }
        if let s = v as? String { return !s.isEmpty }
        return true
    }
}

// const extraOption: CartesianAxisOption = { /* gridIndex: 0, gridId: '', */ offset: 0 };
// PORT-NOTE: `extraOption` feeds `axisModelCreator` inside `install` below; both are registration
//   wiring, deferred to the Orchestrate driver. Preserved as commented source for the diffable
//   surface:
//     let extraOption: [String: Any] = ["offset": 0.0]

// export function install(registers: EChartsExtensionInstallRegisters) { ... }
// PORT-NOTE: registration boilerplate (registerComponentView/registerComponentModel/
//   registerCoordinateSystem('cartesian2d', Grid), axisModelCreator for 'x'/'y', the
//   CartesianXAxisView/CartesianYAxisView view registration, and the grid preprocessor that injects
//   `option.grid = {}` when xAxis+yAxis are present) lives in the driver (`core/ECharts.swift`), not
//   this render-layer file. Preserved as commented source for the diffable surface:
//
//     export function install(registers) {
//         registers.registerComponentView(GridView);
//         registers.registerComponentModel(GridModel);
//         registers.registerCoordinateSystem('cartesian2d', Grid);
//         axisModelCreator(registers, 'x', CartesianAxisModel, extraOption);
//         axisModelCreator(registers, 'y', CartesianAxisModel, extraOption);
//         registers.registerComponentView(CartesianXAxisView);
//         registers.registerComponentView(CartesianYAxisView);
//         registers.registerPreprocessor(function (option) {
//             if (option.xAxis && option.yAxis && !option.grid) { option.grid = {}; }
//         });
//     }
