// Ported from echarts/src/coord/cartesian/GridModel.ts — keep in sync with upstream
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

// import ComponentModel from '../../model/Component';               -> ComponentModel (model/Component.swift)
// import {
//     ComponentOption, BoxLayoutOptionMixin, ZRColor, ShadowOptionMixin, NullUndefined,
//     ComponentOnCalendarOptionMixin, ComponentOnMatrixOptionMixin
// } from '../../util/types';                                        -> util/types.swift (same module)
// import type Grid from './Grid';                                   -> Grid (coord/cartesian/Grid.swift, sibling this phase; type-only here)
// import { CoordinateSystemHostModel } from '../CoordinateSystem';  -> CoordinateSystemHostModel (coord/CoordinateSystem.swift)
// import type GlobalModel from '../../model/Global';                -> GlobalModel (model/Global.swift)
// import { getLayoutParams, mergeLayoutParam } from '../../util/layout';
//   -> PORT-TODO: util/layout.ts not yet ported (getLayoutParams / mergeLayoutParam land later);
//      the outerBounds layout-param merge below is deferred.
// import tokens from '../../visual/tokens';
//   -> PORT-TODO: visual/tokens.ts not ported yet. The `tokens.color.*` values consumed in
//      `defaultOption` are inlined verbatim as their resolved constants; re-wire to the real
//      `tokens` namespace once visual/tokens.swift lands.
//        tokens.color.transparent = 'rgba(0,0,0,0)'
//        tokens.color.neutral30   = '#b7b9be'

// For backward compatibility, do not use a margin. Although the labels might touch the edge of
// the canvas, the chart canvas probably does not have an border or a different background color within a page.
// PORT-TODO: upstream `{left, right, top, bottom}` object-literal modeled as the dynamic option bag
//   ([String: Any]); numbers -> Double per CONVENTIONS §1.
public let OUTER_BOUNDS_DEFAULT: [String: Any] = ["left": 0.0, "right": 0.0, "top": 0.0, "bottom": 0.0]
public let OUTER_BOUNDS_CLAMP_DEFAULT: [String] = ["25%", "25%"]

public let COORD_SYS_TYPE_CARTESIAN_2D = "cartesian2d"

// export interface GridOption extends ComponentOption,
//     ComponentOnCalendarOptionMixin, ComponentOnMatrixOptionMixin,
//     BoxLayoutOptionMixin, ShadowOptionMixin {
//
//     mainType?: 'grid';
//
//     show?: boolean;
//
//     /**
//      * @deprecated Use `grid.outerBounds` instead.
//      * Whether grid size contains axis labels. This approach estimates the size by sample labels.
//      * It works for most case but it does not strictly contain all labels in some cases.
//      */
//     containLabel?: boolean;
//     /**
//      * Define a constrains rect.
//      * Axis lines is firstly laid out based on the rect defined by `grid.left/right/top/bottom/width/height`.
//      * (for axis line alignment requirements between multiple grids)
//      * But if axisLabel and/or axisName overflow the outerBounds, shrink the layout to avoid that overflow.
//      *
//      * Options:
//      *  - 'none': outerBounds is infinity.
//      *  - 'same': outerBounds is the same as the layout rect defined by `grid.left/right/top/bottom/width/height`.
//      *  - 'auto'/null/undefined: Default. Use `outerBounds`, or 'same' if `containLabel:true`.
//      *
//      * Note:
//      *  `grid.containLabel` is equivalent to `{outerBoundsMode: 'same', outerBoundsContain: 'axisLabel'}`.
//      */
//     outerBoundsMode?: 'auto' | NullUndefined | 'same' | 'none';
//     /**
//      * {left, right, top, bottom, width, height}: Define a outerBounds rect, based on:
//      *  - the canvas by default.
//      *  - or the `dataToLayout` result if a `boxCoordinateSystem` is specified.
//      */
//     outerBounds?: BoxLayoutOptionMixin;
//     /**
//      * - 'all': Default. Contains the cartesian rect and axis labels and axis name.
//      * - 'axisLabel': Contains the cartesian rect and axis labels. This effect differs slightly from the
//      *  previous option `containLabel` but more precise.
//      * - 'auto'/null/undefined: Default. be 'axisLabel' if `containLabel:true`, otherwise 'all'.
//      */
//     outerBoundsContain?: 'all' | 'axisLabel' | 'auto' | NullUndefined;
//
//     /**
//      * Available only when `outerBoundsMode` is not 'none'.
//      * Offer a constraint to not to shrink the grid rect causing smaller that width/height.
//      * A string means percent, like '30%', based on the original rect size
//      *  determined by `grid.top/right/bottom/left/width/height`.
//      */
//     outerBoundsClampWidth?: number | string;
//     outerBoundsClampHeight?: number | string;
//
//     backgroundColor?: ZRColor;
//     borderWidth?: number;
//     borderColor?: ZRColor;
//
//     tooltip?: any; // FIXME:TS add this tooltip type
// }
//
// PORT-TODO: TS `interface GridOption` describes the dynamic option shape; per CONVENTIONS §2 the
//   option tree is modeled as the dynamic bag ([String: Any], keyed access via util.* / Model.get),
//   so no standalone Swift struct is emitted. Preserved above for the diffable surface.

// class GridModel extends ComponentModel<GridOption> implements CoordinateSystemHostModel
public final class GridModel: ComponentModel, CoordinateSystemHostModel {

    // static type = 'grid';
    public override class var type: ComponentFullType { return "grid" }

    // static dependencies = ['xAxis', 'yAxis'];
    public override class var dependencies: [String] { return ["xAxis", "yAxis"] }

    // static layoutMode = 'box' as const;
    public override class var layoutMode: Any? { return "box" }

    // coordinateSystem: Grid;
    // PORT-TODO: upstream types this as the concrete `Grid` (a `CoordinateSystemMaster`), injected and
    //   non-null once the coordinate system is built. `Grid` is a sibling this phase; typed here as the
    //   `CoordinateSystemMaster?` required by `CoordinateSystemHostModel` (narrow via `as? Grid` at use).
    public var coordinateSystem: CoordinateSystemMaster?

    // mergeDefaultAndTheme(option: GridOption, ecModel: GlobalModel): void
    public override func mergeDefaultAndTheme(_ option: ModelOption?, _ ecModel: GlobalModel?) {
        // const outerBoundsCp = getLayoutParams(option.outerBounds);
        // PORT-TODO: util/layout.ts (getLayoutParams / mergeLayoutParam) not yet ported; the
        //   outerBounds layout-param snapshot + re-merge is deferred until layout.swift lands.

        // super.mergeDefaultAndTheme.apply(this, arguments as any);
        super.mergeDefaultAndTheme(option, ecModel)

        // if (outerBoundsCp && option.outerBounds) {
        //     mergeLayoutParam(option.outerBounds, outerBoundsCp);
        // }
    }

    // mergeOption(newOption: GridOption, ecModel: GlobalModel)
    public override func mergeOption(_ newOption: ModelOption?, _ ecModel: GlobalModel?) {
        // super.mergeOption.apply(this, arguments as any);
        super.mergeOption(newOption, ecModel)

        // if (this.option.outerBounds && newOption.outerBounds) {
        //     mergeLayoutParam(this.option.outerBounds, newOption.outerBounds);
        // }
        // PORT-TODO: util/layout.ts (mergeLayoutParam) not yet ported — deferred.
    }

    // static defaultOption: GridOption = { ... }
    public override class var defaultOption: ModelOption? {
        return [
            "show": false,
            // zlevel: 0,
            "z": 0.0,
            "left": "15%",
            "top": 65.0,
            "right": "10%",
            "bottom": 80.0,
            // If grid size contain label
            "containLabel": false,
            "outerBoundsMode": "auto",
            "outerBounds": OUTER_BOUNDS_DEFAULT,
            "outerBoundsContain": "all",
            "outerBoundsClampWidth": OUTER_BOUNDS_CLAMP_DEFAULT[0],
            "outerBoundsClampHeight": OUTER_BOUNDS_CLAMP_DEFAULT[1],

            // width: {totalWidth} - left - right,
            // height: {totalHeight} - top - bottom,
            "backgroundColor": "rgba(0,0,0,0)",  // tokens.color.transparent
            "borderWidth": 1.0,
            "borderColor": "#b7b9be"             // tokens.color.neutral30
        ] as [String: Any]
    }
}

// export default GridModel;  -> `public final class GridModel` above.
