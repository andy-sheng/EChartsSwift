// Ported from echarts/src/coord/matrix/MatrixModel.ts — keep in sync with upstream
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

// import OrdinalMeta from '../../data/OrdinalMeta';                    -> OrdinalMeta (data/OrdinalMeta.swift)
// import ComponentModel from '../../model/Component';                  -> ComponentModel (model/Component.swift)
// import Model from '../../model/Model';                              -> Model (model/Model.swift)
// import {
//     BoxLayoutOptionMixin, CommonTooltipOption, ComponentOption, ItemStyleOption, LabelOption,
//     LineStyleOption, NullUndefined, OrdinalNumber, OrdinalRawValue, PositionSizeOption
// } from '../../util/types';                                          -> option interfaces dropped (dynamic option bag, CONVENTIONS §2)
// import Matrix from './Matrix';                                       -> Matrix (coord/matrix/Matrix.swift — coord-sys master; sibling in a later phase)
// import { MatrixDim, MatrixXYLocator } from './MatrixDim';            -> MatrixDim (coord/matrix/MatrixDim.swift — sibling in a later phase)
// import { MatrixBodyCorner } from './MatrixBodyCorner';               -> MatrixBodyCorner (coord/matrix/MatrixBodyCorner.swift — sibling in a later phase)
// import { CoordinateSystemHostModel } from '../CoordinateSystem';     -> CoordinateSystemHostModel (coord/CoordinateSystem.swift)
// import tokens from '../../visual/tokens';                            -> tokens.* (visual/tokens.ts not ported yet; values inlined below, see NOTE)

// `Matrix` / `MatrixDim` / `MatrixBodyCorner` (coord/matrix/{Matrix,MatrixDim,MatrixBodyCorner}.swift)
//   are ported siblings. This file references those types:
//   - `Matrix` is the coordinate-system master, registered via
//     CoordinateSystemManager.register("matrix", <creator>) (matrix is a nonSeriesBox coord sys; see the
//     hardcode in CoordinateSystemManager.register).
//   - `MatrixDim(dim, dimModel)` builds the x/y header dimension tree; exposes `getOrdinalMeta()`.
//   - `MatrixBodyCorner(kind, model, dims)` resolves body / corner cell options.
//   Re-narrow once these land.

// upstream:
// export interface MatrixOption extends ComponentOption, BoxLayoutOptionMixin { ... }
// interface MatrixBodyCornerBaseOption extends MatrixCellStyleOption { data?: MatrixBodyCornerCellOption[]; }
// export interface MatrixBodyOption / MatrixCornerOption / MatrixBaseCellOption / MatrixBodyCornerCellOption
// interface MatrixDimensionOption / MatrixDimensionCellOption / MatrixDimensionLevelOption
// export type MatrixCoordRangeOption / MatrixCoordValueOption / MatrixDimensionCellLooseOption
// export interface MatrixDimensionModel extends Model<MatrixDimensionOption> {}
// export interface MatrixLabelOption / MatrixLabelFormatterParams / MatrixCellStyleOption / MatrixTooltipFormatterParams
//   all of the above are TypeScript option/param interfaces describing the dynamic option
//   shape; per CONVENTIONS §2 they are modeled as the dynamic option bag ([String: Any]) and NOT emitted
//   as standalone Swift structs. The rich `data[i].coord` cell-locating documentation (see upstream
//   MatrixBodyCornerBaseOption) is consumed by Matrix / MatrixBodyCorner (later-phase siblings).

// NOTE: visual/tokens.ts is not ported yet (visual/ lands in a later phase). The individual `tokens.*`
// values consumed by the defaults are inlined verbatim as their resolved constants (mirrors
// coord/calendar/CalendarModel.swift). Re-wire to the real `tokens` namespace once visual/tokens.swift lands:
//   tokens.color.secondary  = color.neutral70 = '#54555a'
//   tokens.color.borderTint = color.neutral20 = '#cfd2d7'
//   tokens.color.border     = color.neutral30 = '#b7b9be'
//   tokens.color.axisLine   = color.neutral70 = '#54555a'

// upstream: const defaultLabelOption: LabelOption = { ... }
//   Numbers -> Double (CONVENTIONS §1) so a bare `as? Double` read does not silently drop them
//   (INT-vs-DOUBLE option-read trap).
private let defaultLabelOption: [String: Any] = [
    "show": true,
    "color": "#54555a",           // tokens.color.secondary
    // overflow: 'truncate',
    "overflow": "break",
    "lineOverflow": "truncate",
    "padding": [2.0, 3.0, 2.0, 3.0],
    // Prefer to use `padding`, rather than distance.
    "distance": 0.0
]

// upstream: function makeDefaultCellItemStyleOption(isCorner: boolean) { ... }
private func makeDefaultCellItemStyleOption(_ isCorner: Bool) -> [String: Any] {
    return [
        "color": "none",
        "borderWidth": 1.0,
        "borderColor": isCorner ? "none" : "#cfd2d7"   // tokens.color.borderTint
    ]
}

// upstream: const defaultDimOption: MatrixDimensionOption = { ... }
private let defaultDimOption: [String: Any] = [
    "show": true,
    "label": defaultLabelOption,
    "itemStyle": makeDefaultCellItemStyleOption(false),
    "silent": NSNull(),           // upstream: silent: undefined
    "dividerLineStyle": [
        "width": 1.0,
        "color": "#b7b9be"        // tokens.color.border
    ] as [String: Any]
]

// upstream: const defaultBodyOption: MatrixBodyOption = { ... }
private let defaultBodyOption: [String: Any] = [
    "label": defaultLabelOption,
    "itemStyle": makeDefaultCellItemStyleOption(false),
    "silent": NSNull()            // upstream: silent: undefined
]

// upstream: const defaultCornerOption: MatrixCornerOption = { ... }
private let defaultCornerOption: [String: Any] = [
    "label": defaultLabelOption,
    "itemStyle": makeDefaultCellItemStyleOption(true),
    "silent": NSNull()            // upstream: silent: undefined
]

// upstream: const defaultMatrixOption: MatrixOption = { ... }
private let defaultMatrixOption: [String: Any] = [
    // As a most basic coord sys, `z` should be lower than
    // other series and coord sys, such as, grid.
    "z": -50.0,
    "left": "10%",
    "top": "10%",
    "right": "10%",
    "bottom": "10%",
    "x": defaultDimOption,
    "y": defaultDimOption,
    "body": defaultBodyOption,
    "corner": defaultCornerOption,
    "backgroundStyle": [
        "color": "none",
        "borderColor": "#54555a", // tokens.color.axisLine
        "borderWidth": 1.0
    ] as [String: Any],
    "triggerEvent": false
]

// upstream: class MatrixModel extends ComponentModel<MatrixOption> implements CoordinateSystemHostModel
//   Component reference type -> `final class : ComponentModel, CoordinateSystemHostModel` (mirrors PolarModel).
public final class MatrixModel: ComponentModel, CoordinateSystemHostModel {

    // static type = 'matrix';
    // type = MatrixModel.type;   (the instance `type` mirrors the static via ComponentModel's `type`.)
    public override class var type: ComponentFullType { return "matrix" }

    // coordinateSystem: Matrix;
    //   upstream types this the concrete `Matrix` (a `CoordinateSystemMaster`), injected once
    //   the coordinate system is built. `Matrix` (coord/matrix/Matrix.swift) is a sibling in a later phase;
    //   typed here as the `CoordinateSystemMaster?` required by `CoordinateSystemHostModel`
    //   (narrow via `as? Matrix` at use), mirroring PolarModel / CalendarModel.
    public var coordinateSystem: CoordinateSystemMaster?

    // static layoutMode = 'box' as const;
    public override class var layoutMode: Any? { return "box" }

    // private _dimModels: { x: MatrixDimensionModel; y: MatrixDimensionModel };
    //   TS object literal keyed by 'x' | 'y' -> a small file-scope struct with an `x`/`y` subscript so
    //   `getDimensionModel(dim)` indexes it exactly like upstream. Optional (IUO-style var) because it is
    //   assigned only in `optionUpdated`, after construction.
    private var _dimModels: MatrixDimModels?

    // private _body: MatrixBodyCorner<'body'>;
    // private _corner: MatrixBodyCorner<'corner'>;
    //   upstream parameterizes `MatrixBodyCorner` by the string-literal kind ('body' / 'corner').
    //   Swift has no string-literal generic param; the forward `MatrixBodyCorner` type is referenced
    //   non-generically here (the kind is also passed as the ctor's first arg). Re-narrow once the sibling
    //   lands (it may become an enum-parameterized or non-generic type).
    private var _body: MatrixBodyCorner?
    private var _corner: MatrixBodyCorner?

    // static defaultOption: MatrixOption = defaultMatrixOption;
    public override class var defaultOption: ModelOption? {
        return defaultMatrixOption
    }

    // optionUpdated(): void { ... }
    //   upstream overrides with a param-less `optionUpdated(): void`, narrowing the base
    //   `ComponentModel.optionUpdated(newCptOption, isInit)`. Swift overrides must match the base
    //   signature, so the two params are accepted and ignored here.
    public override func optionUpdated(_ newCptOption: ModelOption?, _ isInit: Bool) {
        // Simply re-create all to follow model changes.

        // const dimModels = this._dimModels = {
        //     // Do not use matrixModel as the parent model, for preventing from cascade-fetching options to it.
        //     x: new MatrixDimensionModel(this.get('x', true) || {}),
        //     y: new MatrixDimensionModel(this.get('y', true) || {}),
        // };
        //   `this.get('x', true) || {}` — objects are truthy in JS, so only null/undefined trigger the
        //   `{}` fallback (jsTruthy on an object == non-nil); `?? [:]` matches.
        let dimModels = MatrixDimModels(
            x: MatrixDimensionModel((self.get("x", true) as? [String: Any]) ?? [:]),
            y: MatrixDimensionModel((self.get("y", true) as? [String: Any]) ?? [:])
        )
        self._dimModels = dimModels

        // dimModels.x.option.type = dimModels.y.option.type = 'category';
        if var xOpt = dimModels.x.option as? [String: Any] {
            xOpt["type"] = "category"
            dimModels.x.option = xOpt
        }
        if var yOpt = dimModels.y.option as? [String: Any] {
            yOpt["type"] = "category"
            dimModels.y.option = yOpt
        }

        // const xDim = dimModels.x.dim = new MatrixDim('x', dimModels.x);
        // const yDim = dimModels.y.dim = new MatrixDim('y', dimModels.y);
        let xDim = MatrixDim("x", dimModels.x)
        dimModels.x.dim = xDim
        let yDim = MatrixDim("y", dimModels.y)
        dimModels.y.dim = yDim

        // const dims = {x: xDim, y: yDim};  -> the ported MatrixDimPair struct (MatrixDim.swift).
        let dims = MatrixDimPair(x: xDim, y: yDim)

        // this._body = new MatrixBodyCorner('body', new Model(this.getShallow('body')), dims);
        self._body = MatrixBodyCorner(
            "body", Model(self.getShallow("body")), dims
        )
        // this._corner = new MatrixBodyCorner('corner', new Model(this.getShallow('corner')), dims);
        self._corner = MatrixBodyCorner(
            "corner", Model(self.getShallow("corner")), dims
        )
    }

    // getDimensionModel(dim: 'x' | 'y'): MatrixDimensionModel { return this._dimModels[dim]; }
    public func getDimensionModel(_ dim: String) -> MatrixDimensionModel {
        return self._dimModels![dim]
    }

    // getBody(): MatrixBodyCorner<'body'> { return this._body; }
    public func getBody() -> MatrixBodyCorner {
        return self._body!
    }

    // getCorner(): MatrixBodyCorner<'corner'> { return this._corner; }
    public func getCorner() -> MatrixBodyCorner {
        return self._corner!
    }

}

// upstream: private _dimModels: { x: MatrixDimensionModel; y: MatrixDimensionModel };
//   The TS object-literal type for `_dimModels`. Modeled as a small struct with an 'x'/'y' subscript so
//   `getDimensionModel(dim)` indexes by the string dim exactly as upstream `this._dimModels[dim]`.
private struct MatrixDimModels {
    var x: MatrixDimensionModel
    var y: MatrixDimensionModel
    subscript(_ dim: String) -> MatrixDimensionModel {
        return dim == "x" ? x : y
    }
}

// upstream: export class MatrixDimensionModel extends Model<MatrixDimensionOption> {
//     dim: MatrixDim;
//     getOrdinalMeta(): OrdinalMeta { return this.dim.getOrdinalMeta(); }
// }
public final class MatrixDimensionModel: Model {
    // dim: MatrixDim;
    //   Assigned by MatrixModel.optionUpdated after construction (upstream: `dimModels.x.dim = new MatrixDim(...)`);
    //   IUO var so the deferred assignment mirrors upstream. Annotated type per the IUO-bound-to-`let` trap.
    public var dim: MatrixDim!

    public func getOrdinalMeta() -> OrdinalMeta {
        return self.dim.getOrdinalMeta()
    }
}

// export default MatrixModel;  -> `public final class MatrixModel` above.
