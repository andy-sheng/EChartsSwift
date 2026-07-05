// Ported from echarts/src/coord/matrix/Matrix.ts — keep in sync with upstream
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
//   import { RectLike } from 'zrender/src/core/BoundingRect';                 -> RectLike (ZRenderKit).
//   import type { CoordinateSystemDataLayout, NullUndefined, OrdinalNumber } from '../../util/types';
//       -> CoordinateSystemDataLayout / Optional / Double (util/types.swift).
//   import { CoordinateSystem, CoordinateSystemMaster } from '../CoordinateSystem';
//       -> coord/CoordinateSystem.swift. See the CoordinateSystem-drop note on the class below.
//   import GlobalModel from '../../model/Global';                             -> GlobalModel.
//   import ExtensionAPI from '../../core/ExtensionAPI';                       -> ExtensionAPI.
//   import MatrixModel, {...} from './MatrixModel';                          -> MatrixModel (sibling, see PORT-TODO).
//   import { LayoutRect, getLayoutRect } from '../../util/layout';           -> LayoutRect / layout.getLayoutRect.
//   import { ListIterator, ParsedModelFinder, ParsedModelFinderKnown } from '../../util/model';
//       -> ListIterator / ParsedModelFinder(Known) (util/modelUtil.swift).
//   import { eqNaN, isArray, retrieve2 } from 'zrender/src/core/util';       -> util.* (ZRenderKit).
//   import Point from 'zrender/src/core/Point';                              -> Point (ZRenderKit).
//   import { WH, XY } from '../../util/graphic';                             -> see the XY/WH dim-accessor note.
//   import Model from '../../model/Model';                                   -> Model.
//   import type { MatrixCellLayoutInfo, MatrixDimensionCell, MatrixDimPair, MatrixXYLocator } from './MatrixDim';
//       -> siblings (see PORT-TODO).
//   import { mathMax, mathMin, parsePositionSizeOption } from '../../util/number';  -> number.* (util/number.swift).
//   import { createNaNRectLike, MatrixClampOption, MatrixCellLayoutInfoType, parseCoordRangeOption,
//       resetXYLocatorRange, xyLocatorRangeToRectOneDim } from './matrixCoordHelper';
//       -> matrixCoordHelper.* + top-level MatrixClampOption / MatrixCellLayoutInfoType (sibling).
//   import type { MatrixBodyCorner, MatrixBodyOrCornerKind } from './MatrixBodyCorner';  -> sibling.
//   import { error } from '../../util/log';                                  -> log.error (util/log.swift).
//   import { injectCoordSysByOption, simpleCoordSysInjectionProvider } from '../../core/CoordinateSystem';
//       -> injectCoordSysByOption / simpleCoordSysInjectionProvider (core/CoordinateSystemManager.swift).
//
// Sibling matrix-module contracts this keystone relies on (all landed in coord/matrix/):
//     - `MatrixDim` (final class): `let dim: String`, `let dimIdx: Int`, `func shouldShow() -> Bool`,
//         `func getLocatorCount(_ dimIdx: Int) -> Int`,
//         `func getUnitLayoutInfo(_ dimIdx: Int, _ locator: Double) -> MatrixCellLayoutInfo?`,
//         `resetCellIterator`/`resetLevelIterator`/`resetLayoutIterator` returning the matching `ListIterator`.
//     - `MatrixCellLayoutInfo` is a class-bound **protocol** (`type: Int`, `id: Point`, `var xy/wh: Double`,
//         `dim: MatrixDim`); `MatrixDimensionCell` and `MatrixDimensionLevelInfo` are the two final-class
//         conformers ([Concrete] upcasts to [any MatrixCellLayoutInfo] for the base-typed iterator).
//         `MatrixDimensionCell` adds `span: Point`, `level: Int`, `firstLeafLocator: Double`,
//         `ordinal: Double`, `option: [String: Any]`, `rect: RectLike`.
//     - `MatrixDimPair` (struct `{ var x: MatrixDim; var y: MatrixDim }`), `MatrixXYLocator` (= Double),
//         `MatrixXYLocatorRange` (= `[[Double]]`).
//     - `MatrixModel` (ComponentModel + CoordinateSystemHostModel): `getDimensionModel(_:) -> MatrixDimensionModel`,
//         `getBody()/getCorner() -> MatrixBodyCorner`, `var coordinateSystem: CoordinateSystemMaster?`.
//         `MatrixDimensionModel: Model` with `var dim: MatrixDim!`.
//     - `MatrixBodyCorner` (non-generic): `func travelExistingCells(_ cb: (MatrixBodyCornerCell) -> Void)`,
//         `func expandRangeByCellMerge(_ locatorRange: inout MatrixXYLocatorRange)`; `MatrixBodyCornerCell`
//         with `id: Point`, `span: Point?`, `spanRect: RectLike?`.
//     - matrixCoordHelper.swift exposes TOP-LEVEL funcs (no namespace): `resetXYLocatorRange`,
//         `parseCoordRangeOption`, `xyLocatorRangeToRectOneDim`; plus the caseless-enum Int namespaces
//         `MatrixClampOption` (none=0, all=1, body=2, corner=3) and `MatrixCellLayoutInfoType`
//         (level=1, leaf=2, nonLeaf=3).
//
// PORT-TODO (XY/WH): upstream `graphic.ts` exports `XY = ['x','y']` and `WH = ['width','height']`, used to
//   index a `RectLike`/`Point` by dynamic string key. Swift `RectLike`/`Point` have named members, so the
//   string-key indexing `obj[XY[i]]` / `obj[WH[i]]` is realized via the `rectGetXY`/`rectSetXY`/
//   `rectGetWH`/`rectSetWH`/`pointGetXY` dim-accessors at the bottom of this file (should be hoisted to
//   util/graphic.swift once the rest of the matrix module lands).

// upstream: class Matrix implements CoordinateSystem, CoordinateSystemMaster { ... }
//   Reference type → `public final class`. Conforms to `CoordinateSystemMaster` only (dropping the
//   `CoordinateSystem` conformance) for the same reason as Calendar/Single/Polar/Radar: Matrix's
//   `dataToPoint(data, opt?)` / `dataToLayout(data, opt?)` / `pointToData(point, opt?)` carry
//   matrix-specific `opt`/return signatures that do NOT match the `CoordinateSystem` protocol
//   requirements. Those converters are therefore plain concrete methods; `CoordinateSystemMaster` is
//   what the coord-sys registry / convert* pipeline need.
public final class Matrix: CoordinateSystemMaster {

    // upstream: static readonly dimensions = ['x', 'y', 'value'];
    public static let dimensions: [DimensionName] = ["x", "y", "value"]
    /**
     * @see fetchers in `model/referHelper.ts`,
     * which is used to parse data in ordinal way.
     * In most series only 'x' and 'y' is required,
     * but some series, such as heatmap, can specify value.
     */
    // upstream: static getDimensionsInfo() { return [{name:'x',type:'ordinal'},{name:'y',type:'ordinal'},{name:'value'}]; }
    public static func getDimensionsInfo() -> [DimensionDefinitionLoose]? {
        return [
            ["name": "x", "type": "ordinal"] as [String: Any],
            ["name": "y", "type": "ordinal"] as [String: Any],
            ["name": "value"] as [String: Any]
        ]
    }

    // upstream: readonly dimensions = Matrix.dimensions;
    //   Upstream is readonly; `CoordinateSystemMaster.dimensions` requires `{ get set }`, so `var`.
    public var dimensions: [DimensionName] = Matrix.dimensions
    // upstream: readonly type = 'matrix';
    public let type = "matrix"

    // upstream: private _model: MatrixModel;
    private var _model: MatrixModel!
    // upstream: private _dimModels: { x: MatrixDimensionModel; y: MatrixDimensionModel };
    private var _dimModels: MatrixDimModelPair!
    // upstream: private _dims: MatrixDimPair;
    private var _dims: MatrixDimPair!

    // upstream: private _rect: LayoutRect;  (assigned in `_resize`, before any `getRect`) -> IUO.
    private var _rect: LayoutRect!

    // upstream: static create(ecModel: GlobalModel, api: ExtensionAPI) { ... }
    public static func create(_ ecModel: GlobalModel, _ api: ExtensionAPI) -> [Matrix] {
        // const matrixList: Matrix[] = [];
        var matrixList: [Matrix] = []

        // ecModel.eachComponent('matrix', function (matrixModel: MatrixModel) { ... });
        ecModel.eachComponent("matrix") { (matrixModelComp: ComponentModel, _: Double) in
            guard let matrixModel = matrixModelComp as? MatrixModel else { return }
            // const matrix = new Matrix(matrixModel, ecModel, api);
            let matrix = Matrix(matrixModel, ecModel, api)
            // matrixList.push(matrix);
            matrixList.append(matrix)
            // matrixModel.coordinateSystem = matrix;
            matrixModel.coordinateSystem = matrix
        }

        // Inject coordinate system
        // PENDING: optimize to not to travel all components?
        //  (collect relevant components in ecModel only when model update?)
        // ecModel.eachComponent((mainType, componentModel) => {
        //     injectCoordSysByOption({ targetModel: componentModel, coordSysType: 'matrix',
        //         coordSysProvider: simpleCoordSysInjectionProvider });
        // });
        ecModel.eachComponent { (_: String, componentModel: ComponentModel, _: Double) in
            _ = injectCoordSysByOption(InjectCoordSysByOptionOpt(
                targetModel: componentModel,
                coordSysType: "matrix",
                coordSysProvider: simpleCoordSysInjectionProvider
            ))
        }

        // return matrixList;
        return matrixList
    }

    // upstream: constructor(matrixModel: MatrixModel, ecModel: GlobalModel, api: ExtensionAPI) { ... }
    public init(_ matrixModel: MatrixModel, _ ecModel: GlobalModel, _ api: ExtensionAPI) {
        // this._model = matrixModel;
        self._model = matrixModel
        // const models = this._dimModels = { x: matrixModel.getDimensionModel('x'), y: matrixModel.getDimensionModel('y') };
        let models = MatrixDimModelPair(
            x: matrixModel.getDimensionModel("x"),
            y: matrixModel.getDimensionModel("y")
        )
        self._dimModels = models
        // this._dims = { x: models.x.dim, y: models.y.dim };
        self._dims = MatrixDimPair(x: models.x.dim, y: models.y.dim)

        // this._resize(matrixModel, api);
        self._resize(matrixModel, api)
    }

    // upstream: getRect(): LayoutRect { return this._rect; }
    //   PORT-TODO: upstream returns the concrete `LayoutRect`; the optional protocol requirement
    //   `CoordinateSystemMaster.getRect(): RectLike?` therefore resolves to its nil default when Matrix
    //   is held as the protocol (mirroring Calendar/Single/Grid.getRect). Concrete-typed holders get the real rect.
    public func getRect() -> LayoutRect {
        return self._rect
    }

    // upstream: private _resize(matrixModel: MatrixModel, api: ExtensionAPI) { ... }
    private func _resize(_ matrixModel: MatrixModel, _ api: ExtensionAPI) {
        // const dims = this._dims;
        let dims = self._dims!
        // const dimModels = this._dimModels;
        let dimModels = self._dimModels!

        // const rect = this._rect = getLayoutRect(matrixModel.getBoxLayoutParams(), { width: api.getWidth(), height: api.getHeight() });
        let rect = layout.getLayoutRect(
            matrixModel.getBoxLayoutParams(),
            BoundingRect(0, 0, api.getWidth(), api.getHeight())
        )
        self._rect = rect

        // layOutUnitsOnDimension(dimModels, dims, rect, 0);
        layOutUnitsOnDimension(dimModels, dims, rect, 0)
        // layOutUnitsOnDimension(dimModels, dims, rect, 1);
        layOutUnitsOnDimension(dimModels, dims, rect, 1)

        // layOutDimCellsRestInfoByUnit(0, dims);
        layOutDimCellsRestInfoByUnit(0, dims)
        // layOutDimCellsRestInfoByUnit(1, dims);
        layOutDimCellsRestInfoByUnit(1, dims)

        // layOutBodyCornerCellMerge(this._model.getBody(), dims);
        layOutBodyCornerCellMerge(self._model.getBody(), dims)
        // layOutBodyCornerCellMerge(this._model.getCorner(), dims);
        layOutBodyCornerCellMerge(self._model.getCorner(), dims)
    }

    /**
     * @implement
     * - The input is allowed to be `[NaN/null/undefined, xxx]`/`[xxx, NaN/null/undefined]`;
     *  the return is `[NaN, xxxresult]`/`[xxxresult, NaN]` or clamped boundary value if
     *  `clamp` passed. This is for the usage that only get coord on single x or y.
     * - Alwasy return an numeric array, but never be null/undefined.
     *  If it can not be located or invalid, return `[NaN, NaN]`.
     */
    // upstream: dataToPoint(data, opt?, out?): number[] { ... }
    //   `out?` perf out-param dropped, value-returning (CONVENTIONS §3).
    //   PORT-TODO: upstream reuses the module-scratch `_dtpOutDataToLayout` for perf; here we
    //   value-return a fresh `dataToLayout` result (same math, no shared scratch).
    public func dataToPoint(_ data: Any?, _ opt: MatrixDataToLayoutOpt? = nil) -> [Double] {
        // out = out || [];
        var out: [Double] = [0, 0]

        // this.dataToLayout(data, opt, _dtpOutDataToLayout);
        let layoutResult = self.dataToLayout(data, opt)
        let rect = layoutResult.rect!

        // out[0] = _dtpOutDataToLayout.rect.x + _dtpOutDataToLayout.rect.width / 2;
        out[0] = rect.x + rect.width / 2
        // out[1] = _dtpOutDataToLayout.rect.y + _dtpOutDataToLayout.rect.height / 2;
        out[1] = rect.y + rect.height / 2
        return out
    }

    /**
     * @implement
     * - The input is allowed to be `[NaN/null/undefined, xxx]`/`[xxx, NaN/null/undefined]`;
     *  the return is `{x: NaN, width: NaN, y: xxxresulty, height: xxxresulth}`/
     *  `{y: NaN, height: NaN, x: xxxresultx, width: xxxresultw}` or clamped boundary value
     *  if `clamp` passed. This is for the usage that only get coord on single x or y.
     * - The returned `out.rect` and `out.matrixXYLocatorRange` is always an object or an 2d-array,
     *  but never be null/undefined. If it cannot be located or invalid, `NaN` is in their
     *  corresponding number props.
     * - Do not provide `out.contentRect`, because it's allowed to input non-leaf dimension x/y or
     *  a range of x/y, which determines a rect covering multiple cells (even not merged), in which
     *  case the padding and borderWidth can not be determined to make a contentRect. Therefore only
     *  return `out.rect` in any case for consistency. The caller is responsible for adding space to
     *  avoid covering cell borders, if necessary.
     */
    // upstream: dataToLayout(data, opt?, out?): CoordinateSystemDataLayout { ... }
    //   `out?` perf out-param dropped, value-returning (CONVENTIONS §3).
    public func dataToLayout(_ data: Any?, _ opt: MatrixDataToLayoutOpt? = nil) -> CoordinateSystemDataLayout {
        // const dims = this._dims;
        let dims = self._dims!

        // out = out || {} as CoordinateSystemDataLayout;
        var out = CoordinateSystemDataLayout()
        // const outRect = out.rect = out.rect || {} as RectLike;
        let outRect: RectLike = BoundingRect(0, 0, 0, 0)
        out.rect = outRect
        // outRect.x = outRect.y = outRect.width = outRect.height = NaN;
        outRect.x = Double.nan
        outRect.y = Double.nan
        outRect.width = Double.nan
        outRect.height = Double.nan
        // const outLocRange = out.matrixXYLocatorRange = resetXYLocatorRange(out.matrixXYLocatorRange);
        //   `resetXYLocatorRange` / `parseCoordRangeOption` / `xyLocatorRangeToRectOneDim` are top-level
        //   funcs in matrixCoordHelper.swift (not namespaced); `MatrixXYLocatorRange` is `[[Double]]`.
        var outLocRange = resetXYLocatorRange(out.matrixXYLocatorRange)
        out.matrixXYLocatorRange = outLocRange

        // if (!isArray(data)) { error(...); return out; }
        if !util.isArray(data) {
            if __DEV__ {
                log.error("Input data must be an array in `convertToLayout`, `convertToPixel`")
            }
            return out
        }
        let dataArr: [Any?] = matrixToAnyOptArray(data)

        // parseCoordRangeOption(outLocRange, null, data, dims, retrieve2(opt && opt.clamp, MatrixClampOption.none));
        //   PORT-TODO / INTEGRATION: `MatrixXYLocatorRange` is a value-type `[[Double]]`, and upstream
        //   mutates `locOut` in place — so the faithful Swift form is `inout` (as `expandRangeByCellMerge`
        //   already is). The sibling currently declares `parseCoordRangeOption(_ locOut: MatrixXYLocatorRange,
        //   ...)` NON-inout (which cannot propagate its writes, and cannot even mutate a `let` `[[Double]]`
        //   param internally). It must be reconciled to `_ locOut: inout MatrixXYLocatorRange`; this call
        //   passes `&outLocRange` accordingly.
        var reasonOut: [String]? = nil
        parseCoordRangeOption(
            &outLocRange,
            &reasonOut,
            dataArr,
            dims,
            util.retrieve2(opt?.clamp, MatrixClampOption.none) ?? MatrixClampOption.none
        )

        // if (!opt || !opt.ignoreMergeCells) { ... }
        if opt == nil || !(opt!.ignoreMergeCells ?? false) {
            // if (!opt || opt.clamp !== MatrixClampOption.corner) this._model.getBody().expandRangeByCellMerge(outLocRange);
            if opt == nil || opt!.clamp != MatrixClampOption.corner {
                self._model.getBody().expandRangeByCellMerge(&outLocRange)
            }
            // if (!opt || opt.clamp !== MatrixClampOption.body) this._model.getCorner().expandRangeByCellMerge(outLocRange);
            if opt == nil || opt!.clamp != MatrixClampOption.body {
                self._model.getCorner().expandRangeByCellMerge(&outLocRange)
            }
        }

        // xyLocatorRangeToRectOneDim(outRect, outLocRange, dims, 0);
        xyLocatorRangeToRectOneDim(outRect, outLocRange, dims, 0)
        // xyLocatorRangeToRectOneDim(outRect, outLocRange, dims, 1);
        xyLocatorRangeToRectOneDim(outRect, outLocRange, dims, 1)

        // Persist the (value-type) locator range mutated above back onto `out`.
        out.matrixXYLocatorRange = outLocRange

        return out
    }

    /**
     * The returned locator pair can be the input of `dataToPoint` or `dataToLayout`.
     *
     * If point[0] is out of the matrix rect,
     *  the out[0] is NaN;
     * else if it is on the right of top-left corner of body,
     *  the out[0] is the oridinal number (>= 0).
     * else
     *  out[0] is the locator for corner or header (<= 0).
     *
     * The same rule goes for point[1] and out[1].
     *
     * But point[0] and point[1] are calculated separately, i.e.,
     * the reuslt can be `[1, NaN]` or `[NaN, 1]` if only one dimension is out of boundary.
     *
     * @implement
     */
    // upstream: pointToData(point, opt?, out?): MatrixXYLocator[] { ... }
    //   `out?` perf out-param dropped, value-returning (CONVENTIONS §3). PORT-TODO: upstream reuses the
    //   module-scratch `_tmpCtxPointToData`; here a fresh `CtxPointToData` is allocated per call.
    public func pointToData(_ point: [Double], _ opt: MatrixPointToDataOpt? = nil) -> [Double] {
        // const dims = this._dims;
        let dims = self._dims!
        let ctx = CtxPointToData()
        // pointToDataOneDimPrepareCtx(_tmpCtxPointToData, 0, dims, point, opt && opt.clamp);
        pointToDataOneDimPrepareCtx(ctx, 0, dims, point, opt?.clamp)
        // pointToDataOneDimPrepareCtx(_tmpCtxPointToData, 1, dims, point, opt && opt.clamp);
        pointToDataOneDimPrepareCtx(ctx, 1, dims, point, opt?.clamp)

        // out = out || [];
        // out[0] = out[1] = NaN;
        var out: [Double] = [Double.nan, Double.nan]

        // if (ctx.y === inCorner && ctx.x === inBody) { pointToDataOnlyHeaderFillOut(ctx, out, 0, dims); }
        if ctx.y == CtxPointToDataAreaType.inCorner && ctx.x == CtxPointToDataAreaType.inBody {
            pointToDataOnlyHeaderFillOut(ctx, &out, 0, dims)
        }
        // else if (ctx.x === inCorner && ctx.y === inBody) { pointToDataOnlyHeaderFillOut(ctx, out, 1, dims); }
        else if ctx.x == CtxPointToDataAreaType.inCorner && ctx.y == CtxPointToDataAreaType.inBody {
            pointToDataOnlyHeaderFillOut(ctx, &out, 1, dims)
        }
        // else { pointToDataBodyCornerFillOut(ctx, out, 0, dims); pointToDataBodyCornerFillOut(ctx, out, 1, dims); }
        else {
            pointToDataBodyCornerFillOut(ctx, &out, 0, dims)
            pointToDataBodyCornerFillOut(ctx, &out, 1, dims)
        }

        return out
    }

    // upstream: convertToPixel(ecModel, finder, value, opt?) {
    //     const coordSys = getCoordSys(finder);
    //     return coordSys === this ? coordSys.dataToPoint(value, opt) : undefined;
    // }
    public func convertToPixel(
        _ ecModel: GlobalModel,
        _ finder: ParsedModelFinder,
        _ value: CoordinateSystemDataCoord,
        _ opt: Any?
    ) -> Any? {
        let coordSys = getCoordSys(finder)
        return coordSys === self ? coordSys!.dataToPoint(value, opt as? MatrixDataToLayoutOpt) : nil
    }

    // upstream: convertToLayout(ecModel, finder, value, opt?) {
    //     const coordSys = getCoordSys(finder);
    //     return coordSys === this ? coordSys.dataToLayout(value, opt) : undefined;
    // }
    public func convertToLayout(
        _ ecModel: GlobalModel,
        _ finder: ParsedModelFinder,
        _ value: CoordinateSystemDataCoord,
        _ opt: Any?
    ) -> CoordinateSystemDataLayout? {
        let coordSys = getCoordSys(finder)
        return coordSys === self ? coordSys!.dataToLayout(value, opt as? MatrixDataToLayoutOpt) : nil
    }

    // upstream: convertFromPixel(ecModel, finder, pixel, opt?) {
    //     const coordSys = getCoordSys(finder);
    //     return coordSys === this ? coordSys.pointToData(pixel, opt) : undefined;
    // }
    public func convertFromPixel(
        _ ecModel: GlobalModel,
        _ finder: ParsedModelFinder,
        _ pixelValue: [Double],
        _ opt: Any?
    ) -> Any? {
        let coordSys = getCoordSys(finder)
        return coordSys === self ? coordSys!.pointToData(pixelValue, opt as? MatrixPointToDataOpt) : nil
    }

    // upstream: containPoint(point: number[]): boolean { return this._rect.contain(point[0], point[1]); }
    public func containPoint(_ point: [Double]) -> Bool {
        return self._rect.contain(point[0], point[1])
    }

}

// upstream: const _dtpOutDataToLayout = {rect: createNaNRectLike()};
//   Dropped: `dataToPoint` value-returns a fresh `dataToLayout` result instead of a shared scratch.
// upstream: const _ptdLevelIt = new ListIterator<MatrixCellLayoutInfo>();
// upstream: const _ptdDimCellIt = new ListIterator<MatrixDimensionCell>();
//   Dropped module-scratch iterators: fresh `ListIterator`s are allocated inside the fill-out helpers.


// upstream: function layOutUnitsOnDimension(dimModels, dims, matrixRect, dimIdx): void { ... }
private func layOutUnitsOnDimension(
    _ dimModels: MatrixDimModelPair,
    _ dims: MatrixDimPair,
    _ matrixRect: RectLike,
    _ dimIdx: Int
) {
    // const otherDimIdx = 1 - dimIdx;
    let otherDimIdx = 1 - dimIdx
    // const thisDim = dims[XY[dimIdx]];
    let thisDim = dimPairGet(dims, dimIdx)
    // const otherDim = dims[XY[otherDimIdx]];
    let otherDim = dimPairGet(dims, otherDimIdx)
    // Notice: If matrix.x/y.show is false, still lay out, to ensure the
    // consistent return of `dataToLayout`.
    // const otherDimShow = otherDim.shouldShow();
    let otherDimShow = otherDim.shouldShow()

    // Reset
    // for (const it = thisDim.resetCellIterator(); it.next();) { it.item.wh = it.item.xy = NaN; }
    do {
        let it = thisDim.resetCellIterator()
        while it.next() {
            it.item!.wh = Double.nan
            it.item!.xy = Double.nan
        }
    }
    // for (const it = otherDim.resetLayoutIterator(null, dimIdx); it.next();) { it.item.wh = it.item.xy = NaN; }
    do {
        let it = otherDim.resetLayoutIterator(nil, dimIdx)
        while it.next() {
            it.item!.wh = Double.nan
            it.item!.xy = Double.nan
        }
    }

    // Set specified size from option.
    // let restSize = matrixRect[WH[dimIdx]];
    var restSize = rectGetWH(matrixRect, dimIdx)
    // let restCellsCount = thisDim.getLocatorCount(dimIdx) + otherDim.getLocatorCount(dimIdx);
    //   `getLocatorCount` returns `Int`; kept as `Double` for the equal-allocation float math below.
    var restCellsCount = Double(thisDim.getLocatorCount(dimIdx) + otherDim.getLocatorCount(dimIdx))

    // function layOutSpecified(item, sizeOption): void { ... }  (hoisted before its call sites)
    func layOutSpecified(_ item: MatrixCellLayoutInfo, _ sizeOption: Any?) {
        // const size = parseSizeOption(sizeOption, dimIdx, matrixRect);
        let size = parseSizeOption(sizeOption, dimIdx, matrixRect)
        // if (!eqNaN(size)) {
        if !util.eqNaN(size) {
            // item.wh = confineSize(size, restSize);
            item.wh = confineSize(size, restSize)
            // restSize = confineSize(restSize - item.wh);
            restSize = confineSize(restSize - item.wh)
            // restCellsCount--;
            restCellsCount -= 1
        }
    }

    // const tmpLevelModel = new Model<MatrixDimensionLevelOption>();
    let tmpLevelModel = Model()
    // for (const it = otherDim.resetLevelIterator(); it.next();) { ... }
    do {
        let it = otherDim.resetLevelIterator()
        while it.next() {
            // Consider `matrix.x.levelSize` and `matrix.x.levels[i].levelSize`.
            // tmpLevelModel.option = it.item.option;
            tmpLevelModel.option = it.item!.option
            // tmpLevelModel.parentModel = dimModels[XY[otherDimIdx]];
            tmpLevelModel.parentModel = dimModelPairGet(dimModels, otherDimIdx)
            // layOutSpecified(it.item, otherDimShow ? tmpLevelModel.get('levelSize') : 0);
            layOutSpecified(it.item!, otherDimShow ? tmpLevelModel.get("levelSize") : (0 as Any?))
        }
    }
    // const tmpCellModel = new Model<MatrixDimensionCellOption>();
    let tmpCellModel = Model()
    // for (const it = thisDim.resetCellIterator(); it.next();) { ... }
    do {
        let it = thisDim.resetCellIterator()
        while it.next() {
            // Only leaf support size specification, to avoid unnecessary complexity.
            // if (it.item.type === MatrixCellLayoutInfoType.leaf) { ... }
            if it.item!.type == MatrixCellLayoutInfoType.leaf.rawValue {
                // tmpCellModel.option = it.item.option;
                tmpCellModel.option = it.item!.option
                // tmpCellModel.parentModel = undefined;
                tmpCellModel.parentModel = nil
                // layOutSpecified(it.item, tmpCellModel.get('size'));
                layOutSpecified(it.item!, tmpCellModel.get("size"))
            }
        }
    }

    // Set all sizes and positions to levels and leaf cells of which size is unspecified.
    // Contents lay out based on matrix, rather than inverse; therefore do not support
    // calculating size based on content, but allocate equally.
    // const computedCellWH = restCellsCount ? (restSize / restCellsCount) : 0;
    let computedCellWH: Double = jsTruthyNum(restCellsCount) ? (restSize / restCellsCount) : 0
    // If all size specified, but some space remain (may also caused by matrix.x/y.show: false)
    // do not align to the big most edge.
    // const notAlignToBigmost = !restCellsCount && restSize >= 1; // `1` for cumulative precision error.
    let notAlignToBigmost = !jsTruthyNum(restCellsCount) && restSize >= 1
    // let currXY = matrixRect[XY[dimIdx]];
    var currXY = rectGetXY(matrixRect, dimIdx)
    // const maxLocator = thisDim.getLocatorCount(dimIdx) - 1;
    let maxLocator = Double(thisDim.getLocatorCount(dimIdx)) - 1

    // function layOutUnspecified(item) { ... }  (hoisted before its call sites)
    func layOutUnspecified(_ item: MatrixCellLayoutInfo) {
        // if (eqNaN(item.wh)) { item.wh = computedCellWH; }
        if util.eqNaN(item.wh) {
            item.wh = computedCellWH
        }
        // item.xy = currXY;
        item.xy = currXY
        // if (item.id[XY[dimIdx]] === maxLocator && !notAlignToBigmost) {
        if pointGetXY(item.id, dimIdx) == maxLocator && !notAlignToBigmost {
            // Align to the rightmost border, consider cumulative precision error.
            // item.wh = matrixRect[XY[dimIdx]] + matrixRect[WH[dimIdx]] - item.xy;
            item.wh = rectGetXY(matrixRect, dimIdx) + rectGetWH(matrixRect, dimIdx) - item.xy
        }
        // currXY += item.wh;
        currXY += item.wh
    }

    // const it = new ListIterator<MatrixCellLayoutInfo>();
    let it = ListIterator<MatrixCellLayoutInfo>()

    // Lay out levels of the perpendicular dim.
    // for (otherDim.resetLayoutIterator(it, dimIdx); it.next();) { layOutUnspecified(it.item); }
    _ = otherDim.resetLayoutIterator(it, dimIdx)
    while it.next() {
        layOutUnspecified(it.item!)
    }
    // for (thisDim.resetLayoutIterator(it, dimIdx); it.next();) { layOutUnspecified(it.item); }
    _ = thisDim.resetLayoutIterator(it, dimIdx)
    while it.next() {
        layOutUnspecified(it.item!)
    }
}

// upstream: function layOutDimCellsRestInfoByUnit(dimIdx, dims): void { ... }
private func layOutDimCellsRestInfoByUnit(_ dimIdx: Int, _ dims: MatrixDimPair) {
    // Finally save layout info based on the unit leaves and levels.
    // for (const it = dims[XY[dimIdx]].resetCellIterator(); it.next();) { ... }
    let it = dimPairGet(dims, dimIdx).resetCellIterator()
    while it.next() {
        // const dimCell = it.item;
        let dimCell = it.item!
        // layOutRectOneDimBasedOnUnit(dimCell.rect, dimIdx, dimCell.id, dimCell.span, dims);
        layOutRectOneDimBasedOnUnit(dimCell.rect, dimIdx, dimCell.id, dimCell.span, dims)
        // Consider level varitation on tree leaves, should extend the size to touch matrix body
        // to avoid weird appearance.
        // layOutRectOneDimBasedOnUnit(dimCell.rect, 1 - dimIdx, dimCell.id, dimCell.span, dims);
        layOutRectOneDimBasedOnUnit(dimCell.rect, 1 - dimIdx, dimCell.id, dimCell.span, dims)

        // if (dimCell.type === MatrixCellLayoutInfoType.nonLeaf) { ... }
        if dimCell.type == MatrixCellLayoutInfoType.nonLeaf.rawValue {
            // `xy` and `wh` need to be saved in non-leaf since it supports locating by non-leaf
            // in `dataToPoint` or `dataToLayout`.
            // dimCell.xy = dimCell.rect[XY[dimIdx]];
            dimCell.xy = rectGetXY(dimCell.rect, dimIdx)
            // dimCell.wh = dimCell.rect[WH[dimIdx]];
            dimCell.wh = rectGetWH(dimCell.rect, dimIdx)
        }
    }
}

// upstream: function layOutBodyCornerCellMerge(bodyOrCorner, dims) { ... }
private func layOutBodyCornerCellMerge(_ bodyOrCorner: MatrixBodyCorner, _ dims: MatrixDimPair) {
    // bodyOrCorner.travelExistingCells(cell => { ... });
    bodyOrCorner.travelExistingCells { cell in
        // const computedSpan = cell.span;
        let computedSpan = cell.span
        // if (computedSpan) { ... }
        if let computedSpan = computedSpan {
            // const layoutRect = cell.spanRect;  (exists only if cellMergeOwner, guaranteed by `span`)
            let layoutRect = cell.spanRect!
            // const id = cell.id;
            let id = cell.id
            // layOutRectOneDimBasedOnUnit(layoutRect, 0, id, computedSpan, dims);
            layOutRectOneDimBasedOnUnit(layoutRect, 0, id, computedSpan, dims)
            // layOutRectOneDimBasedOnUnit(layoutRect, 1, id, computedSpan, dims);
            layOutRectOneDimBasedOnUnit(layoutRect, 1, id, computedSpan, dims)
        }
    }
}

// Save to rect for rendering.
// upstream: function layOutRectOneDimBasedOnUnit(outRect, dimIdx, id, span, dims): void { ... }
private func layOutRectOneDimBasedOnUnit(
    _ outRect: RectLike, _ dimIdx: Int, _ id: Point, _ span: Point, _ dims: MatrixDimPair
) {
    // outRect[WH[dimIdx]] = 0;
    rectSetWH(outRect, dimIdx, 0)
    // const locator = id[XY[dimIdx]];
    let locator = pointGetXY(id, dimIdx)
    // const dim = locator < 0 ? dims[XY[1 - dimIdx]] : dims[XY[dimIdx]];
    let dim = locator < 0 ? dimPairGet(dims, 1 - dimIdx) : dimPairGet(dims, dimIdx)
    // const layoutUnit = dim.getUnitLayoutInfo(dimIdx, id[XY[dimIdx]]);  (upstream assumes non-null)
    let layoutUnit = dim.getUnitLayoutInfo(dimIdx, pointGetXY(id, dimIdx))!
    // outRect[XY[dimIdx]] = layoutUnit.xy;
    rectSetXY(outRect, dimIdx, layoutUnit.xy)
    // outRect[WH[dimIdx]] = layoutUnit.wh;
    rectSetWH(outRect, dimIdx, layoutUnit.wh)

    // if (span[XY[dimIdx]] > 1) { ... }
    if pointGetXY(span, dimIdx) > 1 {
        // const layoutUnit2 = dim.getUnitLayoutInfo(dimIdx, id[XY[dimIdx]] + span[XY[dimIdx]] - 1);
        let layoutUnit2 = dim.getUnitLayoutInfo(dimIdx, pointGetXY(id, dimIdx) + pointGetXY(span, dimIdx) - 1)!
        // Be careful the cumulative error - cell must be aligned.
        // outRect[WH[dimIdx]] = layoutUnit2.xy + layoutUnit2.wh - layoutUnit.xy;
        rectSetWH(outRect, dimIdx, layoutUnit2.xy + layoutUnit2.wh - layoutUnit.xy)
    }
}

/**
 * Return NaN if not defined or invalid.
 */
// upstream: function parseSizeOption(sizeOption, dimIdx, matrixRect): number { ... }
private func parseSizeOption(_ sizeOption: Any?, _ dimIdx: Int, _ matrixRect: RectLike) -> Double {
    // const sizeNum = parsePositionSizeOption(sizeOption, matrixRect[WH[dimIdx]]);
    let sizeNum = number.parsePositionSizeOption(sizeOption, rectGetWH(matrixRect, dimIdx))
    // return confineSize(sizeNum, matrixRect[WH[dimIdx]]);
    return confineSize(sizeNum, rectGetWH(matrixRect, dimIdx))
}

// upstream: function confineSize(sizeNum, sizeLimit?): number {
//     return Math.max(Math.min(sizeNum, retrieve2(sizeLimit, Infinity)), 0);
// }
private func confineSize(_ sizeNum: Double, _ sizeLimit: Double? = nil) -> Double {
    return Swift.max(Swift.min(sizeNum, util.retrieve2(sizeLimit, Double.infinity)!), 0)
}

// upstream: function getCoordSys(finder: ParsedModelFinderKnown): Matrix {
//     const matrixModel = finder.matrixModel as MatrixModel;
//     const seriesModel = finder.seriesModel;
//     const coordSys = matrixModel ? matrixModel.coordinateSystem
//         : seriesModel ? seriesModel.coordinateSystem : null;
//     return coordSys as Matrix;
// }
//   `finder` is `[String: Any]` -> field access via subscript.
private func getCoordSys(_ finder: ParsedModelFinderKnown) -> Matrix? {
    let matrixModel = finder["matrixModel"] as? MatrixModel
    let seriesModel = finder["seriesModel"] as? SeriesModel

    // `matrixModel.coordinateSystem` is `CoordinateSystemMaster?` (CoordinateSystemHostModel) and
    // `seriesModel.coordinateSystem` is `Any?` (Series.swift); box both as `Any?` and narrow at the end.
    let coordSys: Any?
    if let matrixModel = matrixModel {
        coordSys = matrixModel.coordinateSystem
    }
    else if let seriesModel = seriesModel {
        coordSys = seriesModel.coordinateSystem
    }
    else {
        coordSys = nil
    }

    return coordSys as? Matrix
}

// upstream: const CtxPointToDataAreaType = {inBody: 1, inCorner: 2, outside: 3};
//   File-local const-object enum -> Swift enum (raw Int values matched).
private enum CtxPointToDataAreaType: Int {
    case inBody = 1
    case inCorner = 2
    case outside = 3
}

// upstream: type CtxPointToData = { x; y: CtxPointToDataAreaType | NullUndefined; point: number[] };
//   Mutated through helpers -> reference type (final class).
private final class CtxPointToData {
    // x/y: If clamp required, this point is clamped after prepared.
    var x: CtxPointToDataAreaType?
    var y: CtxPointToDataAreaType?
    var point: [Double] = [0, 0]
}
// upstream: const _tmpCtxPointToData: CtxPointToData = {x: null, y: null, point: []};
//   Dropped module-scratch (see `pointToData`); a fresh `CtxPointToData` is used per call.

// upstream: function pointToDataOneDimPrepareCtx(ctx, dimIdx, dims, point, clamp) { ... }
private func pointToDataOneDimPrepareCtx(
    _ ctx: CtxPointToData,
    _ dimIdx: Int,
    _ dims: MatrixDimPair,
    _ point: [Double],
    _ clamp: Int?
) {
    // const thisDim = dims[XY[dimIdx]];
    let thisDim = dimPairGet(dims, dimIdx)
    // const otherDim = dims[XY[1 - dimIdx]];
    let otherDim = dimPairGet(dims, 1 - dimIdx)

    // Notice: considered cases: `matrix.x/y.show: false`, `matrix.x/y.data` is empty.
    // In this cases the `layout.xy` is on the edge and `layout.wh` is `0`; they still can be
    // use to calculate clampping.

    // const bodyMaxUnit = thisDim.getUnitLayoutInfo(dimIdx, thisDim.getLocatorCount(dimIdx) - 1);
    //   `getLocatorCount` returns `Int`; the locator arg is `Double` (MatrixXYLocator).
    let bodyMaxUnit = thisDim.getUnitLayoutInfo(dimIdx, Double(thisDim.getLocatorCount(dimIdx) - 1))
    // const body0Unit = thisDim.getUnitLayoutInfo(dimIdx, 0);
    let body0Unit = thisDim.getUnitLayoutInfo(dimIdx, 0)
    // const cornerMinUnit = otherDim.getUnitLayoutInfo(dimIdx, -otherDim.getLocatorCount(dimIdx));
    let cornerMinUnit = otherDim.getUnitLayoutInfo(dimIdx, Double(-otherDim.getLocatorCount(dimIdx)))
    // const cornerMinus1Unit = otherDim.shouldShow() ? otherDim.getUnitLayoutInfo(dimIdx, -1) : null;
    let cornerMinus1Unit: MatrixCellLayoutInfo? = otherDim.shouldShow() ? otherDim.getUnitLayoutInfo(dimIdx, -1) : nil

    // let coord = ctx.point[dimIdx] = point[dimIdx]; // Transfer the oridinal coord.
    var coord = point[dimIdx]
    ctx.point[dimIdx] = coord

    // if (!body0Unit && !cornerMinus1Unit) { ctx[XY[dimIdx]] = outside; return; }
    if body0Unit == nil && cornerMinus1Unit == nil {
        ctxSetArea(ctx, dimIdx, .outside)
        return
    }

    // if (clamp === MatrixClampOption.body) { ... }
    if clamp == MatrixClampOption.body {
        if body0Unit != nil {
            ctxSetArea(ctx, dimIdx, .inBody)
            // coord = mathMin(bodyMaxUnit.xy + bodyMaxUnit.wh, mathMax(body0Unit.xy, coord));
            coord = number.mathMin(bodyMaxUnit!.xy + bodyMaxUnit!.wh, number.mathMax(body0Unit!.xy, coord))
            ctx.point[dimIdx] = coord
        }
        else {
            // If clamp to body, the result must not be in header.
            ctxSetArea(ctx, dimIdx, .outside)
        }
        return
    }
    // else if (clamp === MatrixClampOption.corner) { ... }
    else if clamp == MatrixClampOption.corner {
        if cornerMinus1Unit != nil {
            ctxSetArea(ctx, dimIdx, .inCorner)
            // coord = mathMin(cornerMinus1Unit.xy + cornerMinus1Unit.wh, mathMax(cornerMinUnit.xy, coord));
            coord = number.mathMin(cornerMinus1Unit!.xy + cornerMinus1Unit!.wh, number.mathMax(cornerMinUnit!.xy, coord))
            ctx.point[dimIdx] = coord
        }
        else {
            // If clamp to corner, the result must not be in body.
            ctxSetArea(ctx, dimIdx, .outside)
        }
        return
    }

    // const pxLoc0 = body0Unit ? body0Unit.xy : cornerMinus1Unit ? cornerMinus1Unit.xy + cornerMinus1Unit.wh : NaN;
    let pxLoc0: Double = body0Unit != nil
        ? body0Unit!.xy
        : (cornerMinus1Unit != nil ? cornerMinus1Unit!.xy + cornerMinus1Unit!.wh : Double.nan)
    // const pxMin = cornerMinUnit ? cornerMinUnit.xy : pxLoc0;
    let pxMin: Double = cornerMinUnit != nil ? cornerMinUnit!.xy : pxLoc0
    // const pxMax = bodyMaxUnit ? bodyMaxUnit.xy + bodyMaxUnit.wh : pxLoc0;
    let pxMax: Double = bodyMaxUnit != nil ? bodyMaxUnit!.xy + bodyMaxUnit!.wh : pxLoc0

    // if (coord < pxMin) { if (!clamp) { ctx = outside; return; } coord = pxMin; }
    if coord < pxMin {
        if matrixClampFalsy(clamp) {
            // Quick pass for later calc, since mouse event on any place will enter this method if use `pointToData`.
            ctxSetArea(ctx, dimIdx, .outside)
            return
        }
        coord = pxMin
    }
    // else if (coord > pxMax) { if (!clamp) { ctx = outside; return; } coord = pxMax; }
    else if coord > pxMax {
        if matrixClampFalsy(clamp) {
            ctxSetArea(ctx, dimIdx, .outside)
            return
        }
        coord = pxMax
    }
    // ctx.point[dimIdx] = coord; // Save the updated coord.
    ctx.point[dimIdx] = coord

    // ctx[XY[dimIdx]] = pxLoc0 <= coord && coord <= pxMax ? inBody
    //     : pxMin <= coord && coord <= pxLoc0 ? inCorner : outside;
    ctxSetArea(ctx, dimIdx,
        (pxLoc0 <= coord && coord <= pxMax) ? CtxPointToDataAreaType.inBody
        : (pxMin <= coord && coord <= pxLoc0) ? CtxPointToDataAreaType.inCorner
        : CtxPointToDataAreaType.outside)

    // Every props in ctx must be set in every branch of this method.
}

// Assume partialOut has been set to NaN outside.
// This method may fill out[0] and out[1] in one call.
// upstream: function pointToDataOnlyHeaderFillOut(ctx, partialOut, dimIdx, dims): void { ... }
private func pointToDataOnlyHeaderFillOut(
    _ ctx: CtxPointToData,
    _ partialOut: inout [Double],
    _ dimIdx: Int,
    _ dims: MatrixDimPair
) {
    // const otherDimIdx = 1 - dimIdx;
    let otherDimIdx = 1 - dimIdx

    // if (ctx[XY[dimIdx]] === outside) { return; }
    if ctxGetArea(ctx, dimIdx) == CtxPointToDataAreaType.outside {
        return
    }
    // for (dims[XY[dimIdx]].resetCellIterator(_ptdDimCellIt); _ptdDimCellIt.next();) { ... }
    let it = dimPairGet(dims, dimIdx).resetCellIterator()
    while it.next() {
        // const cell = _ptdDimCellIt.item;
        let cell = it.item!
        // if (isCoordInRect(ctx.point[dimIdx], cell.rect, dimIdx) && isCoordInRect(ctx.point[otherDimIdx], cell.rect, otherDimIdx)) {
        if isCoordInRect(ctx.point[dimIdx], cell.rect, dimIdx)
            && isCoordInRect(ctx.point[otherDimIdx], cell.rect, otherDimIdx) {
            // non-leaves are also allowed to be located.
            // If the point is in x or y dimension cell area, should check both x and y coord to
            // determine a cell; in this way a non-leaf cell can be determined.
            // partialOut[dimIdx] = cell.ordinal;
            partialOut[dimIdx] = cell.ordinal
            // partialOut[otherDimIdx] = cell.id[XY[otherDimIdx]];
            partialOut[otherDimIdx] = pointGetXY(cell.id, otherDimIdx)
            return
        }
    }
}

// Assume partialOut has been set to NaN outside.
// This method may fill out[0] and out[1] in one call.
// upstream: function pointToDataBodyCornerFillOut(ctx, partialOut, dimIdx, dims): void { ... }
private func pointToDataBodyCornerFillOut(
    _ ctx: CtxPointToData,
    _ partialOut: inout [Double],
    _ dimIdx: Int,
    _ dims: MatrixDimPair
) {
    // if (ctx[XY[dimIdx]] === outside) { return; }
    if ctxGetArea(ctx, dimIdx) == CtxPointToDataAreaType.outside {
        return
    }
    // const dim = ctx[XY[dimIdx]] === inCorner ? dims[XY[1 - dimIdx]] : dims[XY[dimIdx]];
    let dim = ctxGetArea(ctx, dimIdx) == CtxPointToDataAreaType.inCorner
        ? dimPairGet(dims, 1 - dimIdx) : dimPairGet(dims, dimIdx)
    // for (dim.resetLayoutIterator(_ptdLevelIt, dimIdx); _ptdLevelIt.next();) { ... }
    let it = ListIterator<MatrixCellLayoutInfo>()
    _ = dim.resetLayoutIterator(it, dimIdx)
    while it.next() {
        // if (isCoordInLayoutInfo(ctx.point[dimIdx], _ptdLevelIt.item)) {
        if isCoordInLayoutInfo(ctx.point[dimIdx], it.item!) {
            // partialOut[dimIdx] = _ptdLevelIt.item.id[XY[dimIdx]];
            partialOut[dimIdx] = pointGetXY(it.item!.id, dimIdx)
            return
        }
    }
}

// upstream: function isCoordInLayoutInfo(coord, cell): boolean { return cell.xy <= coord && coord <= cell.xy + cell.wh; }
private func isCoordInLayoutInfo(_ coord: Double, _ cell: MatrixCellLayoutInfo) -> Bool {
    return cell.xy <= coord && coord <= cell.xy + cell.wh
}
// upstream: function isCoordInRect(coord, rect, dimIdx): boolean {
//     return rect[XY[dimIdx]] <= coord && coord <= rect[XY[dimIdx]] + rect[WH[dimIdx]];
// }
private func isCoordInRect(_ coord: Double, _ rect: RectLike, _ dimIdx: Int) -> Bool {
    return rectGetXY(rect, dimIdx) <= coord && coord <= rectGetXY(rect, dimIdx) + rectGetWH(rect, dimIdx)
}

// export default Matrix;  -> `public final class Matrix` above.


// MARK: - Port support

// upstream: this._dimModels: { x: MatrixDimensionModel; y: MatrixDimensionModel } inline type.
private struct MatrixDimModelPair {
    var x: MatrixDimensionModel
    var y: MatrixDimensionModel
}

// upstream `opt` of `dataToLayout` (also used by `dataToPoint`):
//   { clamp?: MatrixClampOption | NullUndefined; ignoreMergeCells?: boolean }
public struct MatrixDataToLayoutOpt {
    // No clamp by default, considering the possibility of supporting dataZoom (overflow/scroll).
    // `MatrixClampOption` is a caseless-enum namespace of Int constants, so a clamp value is an `Int`.
    public var clamp: Int?
    // Expand if cell merging is encountered.
    //  - `false`: If intersecting with a rect of merged cells, expand the result to cover it.
    //  - `true`: regardless of cell merging, even if the resulting rect spans accorss the merged cells.
    public var ignoreMergeCells: Bool?
    public init(clamp: Int? = nil, ignoreMergeCells: Bool? = nil) {
        self.clamp = clamp
        self.ignoreMergeCells = ignoreMergeCells
    }
}

// upstream `opt` of `pointToData`: { clamp?: MatrixClampOption | NullUndefined }
public struct MatrixPointToDataOpt {
    public var clamp: Int?
    public init(clamp: Int? = nil) {
        self.clamp = clamp
    }
}

// XY/WH dim-accessors realizing upstream `obj[XY[i]]` / `obj[WH[i]]` (see the top-of-file XY/WH note).
private func dimPairGet(_ dims: MatrixDimPair, _ dimIdx: Int) -> MatrixDim {
    return dimIdx == 0 ? dims.x : dims.y
}
private func dimModelPairGet(_ p: MatrixDimModelPair, _ dimIdx: Int) -> MatrixDimensionModel {
    return dimIdx == 0 ? p.x : p.y
}
private func rectGetXY(_ r: RectLike, _ dimIdx: Int) -> Double {
    return dimIdx == 0 ? r.x : r.y
}
private func rectSetXY(_ r: RectLike, _ dimIdx: Int, _ v: Double) {
    if dimIdx == 0 { r.x = v } else { r.y = v }
}
private func rectGetWH(_ r: RectLike, _ dimIdx: Int) -> Double {
    return dimIdx == 0 ? r.width : r.height
}
private func rectSetWH(_ r: RectLike, _ dimIdx: Int, _ v: Double) {
    if dimIdx == 0 { r.width = v } else { r.height = v }
}
private func pointGetXY(_ p: Point, _ dimIdx: Int) -> Double {
    return dimIdx == 0 ? p.x : p.y
}

// ctx[XY[dimIdx]] read/write (CtxPointToData.x / .y).
private func ctxSetArea(_ ctx: CtxPointToData, _ dimIdx: Int, _ v: CtxPointToDataAreaType?) {
    if dimIdx == 0 { ctx.x = v } else { ctx.y = v }
}
private func ctxGetArea(_ ctx: CtxPointToData, _ dimIdx: Int) -> CtxPointToDataAreaType? {
    return dimIdx == 0 ? ctx.x : ctx.y
}

// JS numeric truthiness: 0 and NaN are falsy (used for `restCellsCount ? ... : 0` and `!restCellsCount`).
private func jsTruthyNum(_ x: Double) -> Bool {
    return x != 0 && !x.isNaN
}

// JS `!clamp` where `clamp: MatrixClampOption | NullUndefined`. `MatrixClampOption.none` is 0,
// which is falsy in JS just like `undefined` — so both nil and `.none` are treated as "no clamp".
private func matrixClampFalsy(_ clamp: Int?) -> Bool {
    return clamp == nil || clamp == MatrixClampOption.none
}

// JS `MatrixCoordRangeOption[]` (element = value | value[] | NullUndefined) -> `[Any?]` for the sibling
// `matrixCoordHelper.parseCoordRangeOption`. Preserves array-of-arrays and null entries.
private func matrixToAnyOptArray(_ v: Any?) -> [Any?] {
    if let a = v as? [Any?] { return a }
    if let a = v as? [Any] { return a.map { Optional.some($0) } }
    return []
}
