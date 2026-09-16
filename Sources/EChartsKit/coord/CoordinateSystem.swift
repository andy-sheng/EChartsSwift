// Ported from echarts/src/coord/CoordinateSystem.ts — keep in sync with upstream

import Foundation
import ZRenderKit

// import GlobalModel from '../model/Global';                          -> GlobalModel (this module)
// import {ParsedModelFinder} from '../util/model';                    -> ParsedModelFinder (util/modelUtil.swift)
// import ExtensionAPI from '../core/ExtensionAPI';                    -> ExtensionAPI (core/ExtensionAPI.swift)
// import {
//     DimensionDefinitionLoose, ScaleDataValue, DimensionName, NullUndefined, CoordinateSystemDataLayout,
//     CoordinateSystemDataCoord
// } from '../util/types';                                             -> util/types.swift
//   NullUndefined collapses to Optional (CONVENTIONS §6).
// import Axis from './Axis';                                          -> Axis (coord/Axis.swift, sibling this phase; type-only here)
// import { BoundingRect } from '../util/graphic';                    -> BoundingRect (ZRenderKit)
// import { MatrixArray } from 'zrender/src/core/matrix';             -> MatrixArray (ZRenderKit)
// import ComponentModel from '../model/Component';                   -> ComponentModel (this module)
// import { RectLike } from 'zrender/src/core/BoundingRect';          -> RectLike (ZRenderKit)
// import type { PrepareCustomInfo } from '../chart/custom/CustomSeries';

// PrepareCustomInfo (chart/custom/CustomSeries.ts) is a chart-view function type. The real typealias
//   now lives in chart/custom/CustomSeries.swift (Phase 26). The `prepareCustoms` property below is
//   typed against that function type.


public protocol CoordinateSystemCreator {

    // create: (ecModel: GlobalModel, api: ExtensionAPI) => CoordinateSystemMaster[];
    func create(_ ecModel: GlobalModel, _ api: ExtensionAPI) -> [CoordinateSystemMaster]

    // FIXME current dimensions must be string[].
    // check and unify the definition.
    // FIXME:TS check where used (seams only HeatmapSeries used?)
    // Some coordinate system do not have static dimensions (like parallel)
    // dimensions?: DimensionName[];
    var dimensions: [DimensionName]? { get }

    // dimensionsInfo like [{name: ..., type: ...}, 'xxx', ...]
    // getDimensionsInfo?: () => DimensionDefinitionLoose[];
    func getDimensionsInfo() -> [DimensionDefinitionLoose]?
}
// `dimensions` / `getDimensionsInfo` are upstream-optional (`?`). Modeled as protocol
//   requirements with nil-returning defaults so conformers may omit them (see extension below).
public extension CoordinateSystemCreator {
    var dimensions: [DimensionName]? { nil }
    func getDimensionsInfo() -> [DimensionDefinitionLoose]? { nil }
}

/**
 * The instance get from `CoordinateSystemManger` is `CoordinateSystemMaster`.
 * Consider a typical case: `grid` is a `CoordinateSystemMaster`, and it contains
 * one or multiple `cartesian2d`s, which are `CoordinateSystem`s.
 */
public protocol CoordinateSystemMaster: AnyObject {

    // FIXME current dimensions must be string[].
    // check and unify the definition.
    // Should be the same as its coordinateSystemCreator.
    // dimensions: DimensionName[];
    var dimensions: [DimensionName] { get set }

    // model?: ComponentModel;
    var model: ComponentModel? { get set }

    // Injected if required.
    // boxCoordinateSystem?: CoordinateSystem;
    var boxCoordinateSystem: CoordinateSystem? { get set }

    // update?: (ecModel: GlobalModel, api: ExtensionAPI) => void;
    func update(_ ecModel: GlobalModel, _ api: ExtensionAPI)

    // This methods is also responsible for determining whether this
    // coordinate system is applicable to the given `finder`.
    // Each coordinate system will be tried, until one returns non-
    // null/undefined value.
    // Aslo support
    //  const resultNumber = convertToPixel({someAxis: 0}, number);
    // convertToPixel?(
    //     ecModel: GlobalModel,
    //     finder: ParsedModelFinder,
    //     value: Parameters<CoordinateSystem['dataToPoint']>[0],
    //     opt?: unknown
    // ): ReturnType<CoordinateSystem['dataToPoint']> | number | NullUndefined;
    // return `number[] | number | NullUndefined` erased to `Any?` (no Swift union).
    func convertToPixel(
        _ ecModel: GlobalModel,
        _ finder: ParsedModelFinder,
        _ value: CoordinateSystemDataCoord,
        _ opt: Any?
    ) -> Any?

    // This methods is also responsible for determining whether this
    // coordinate system is applicable to the given `finder`.
    // Each coordinate system will be tried, until one returns non-
    // null/undefined value.
    // convertToLayout?(
    //     ecModel: GlobalModel,
    //     finder: ParsedModelFinder,
    //     value: Parameters<NonNullable<CoordinateSystem['dataToLayout']>>[0],
    //     opt?: unknown
    // ): ReturnType<NonNullable<CoordinateSystem['dataToLayout']>> | NullUndefined;
    func convertToLayout(
        _ ecModel: GlobalModel,
        _ finder: ParsedModelFinder,
        _ value: CoordinateSystemDataCoord,
        _ opt: Any?
    ) -> CoordinateSystemDataLayout?

    // This methods is also responsible for determining whether this
    // coordinate system is applicable to the given `finder`.
    // Each coordinate system will be tried, until one returns non-
    // null/undefined value.
    // convertFromPixel?(
    //     ecModel: GlobalModel,
    //     finder: ParsedModelFinder,
    //     pixelValue: Parameters<NonNullable<CoordinateSystem['pointToData']>>[0],
    //     opt?: unknown
    // ): ReturnType<NonNullable<CoordinateSystem['pointToData']>> | NullUndefined;
    // return `number | number[] | NullUndefined` erased to `Any?` (no Swift union).
    func convertFromPixel(
        _ ecModel: GlobalModel,
        _ finder: ParsedModelFinder,
        _ pixelValue: [Double],
        _ opt: Any?
    ) -> Any?

    // @param point Point in global pixel coordinate system.
    // The signature of this method should be the same as `CoordinateSystemExecutive`
    // containPoint(point: number[]): boolean;
    func containPoint(_ point: [Double]) -> Bool

    // Must be implemented when `axisPointerEnabled` is `true`.
    // getAxes?: () => Axis[];
    func getAxes() -> [Axis]?

    // axisPointerEnabled?: boolean;
    var axisPointerEnabled: Bool? { get }

    // getTooltipAxes?: (dim: DimensionName | 'auto') => {baseAxes: Axis[], otherAxes: Axis[]};
    // `dim: DimensionName | 'auto'` erased to String; anonymous object -> named tuple.
    func getTooltipAxes(_ dim: DimensionName) -> (baseAxes: [Axis], otherAxes: [Axis])?

    /**
     * Get layout rect or coordinate system
     */
    // getRect?: () => RectLike
    func getRect() -> RectLike?
}
// `model` / `boxCoordinateSystem` / `update` / `convert*` / `getAxes` / `axisPointerEnabled`
//   / `getTooltipAxes` / `getRect` are upstream-optional (`?`). Modeled as protocol requirements with
//   nil / no-op defaults so conformers may omit them (Swift has no optional protocol members).
public extension CoordinateSystemMaster {
    var model: ComponentModel? { get { nil } set {} }
    var boxCoordinateSystem: CoordinateSystem? { get { nil } set {} }
    func update(_ ecModel: GlobalModel, _ api: ExtensionAPI) {}
    func convertToPixel(
        _ ecModel: GlobalModel, _ finder: ParsedModelFinder, _ value: CoordinateSystemDataCoord, _ opt: Any?
    ) -> Any? { nil }
    func convertToLayout(
        _ ecModel: GlobalModel, _ finder: ParsedModelFinder, _ value: CoordinateSystemDataCoord, _ opt: Any?
    ) -> CoordinateSystemDataLayout? { nil }
    func convertFromPixel(
        _ ecModel: GlobalModel, _ finder: ParsedModelFinder, _ pixelValue: [Double], _ opt: Any?
    ) -> Any? { nil }
    func getAxes() -> [Axis]? { nil }
    var axisPointerEnabled: Bool? { nil }
    func getTooltipAxes(_ dim: DimensionName) -> (baseAxes: [Axis], otherAxes: [Axis])? { nil }
    func getRect() -> RectLike? { nil }
}

/**
 * For example: cartesian is CoordinateSystem.
 * series.coordinateSystem is CoordinateSystem.
 */
public protocol CoordinateSystem: AnyObject {

    // type: string
    var type: String { get }

    /**
     * Master of coordinate system. For example:
     * Grid is master of cartesian.
     */
    // master?: CoordinateSystemMaster
    var master: CoordinateSystemMaster? { get set }

    // Should be the same as its coordinateSystemCreator.
    // dimensions: DimensionName[];
    var dimensions: [DimensionName] { get set }

    // model?: ComponentModel;
    var model: ComponentModel? { get set }

    /**
     * @param data
     * @param reserved Defined by the coordinate system itself
     * @param out Fill it if passing, and return. For performance optimization.
     * @return Point in global pixel coordinate system.
     *  An invalid returned point should be represented by `[NaN, NaN]`,
     *  rather than `null/undefined`.
     */
    // dataToPoint(
    //     data: CoordinateSystemDataCoord,
    //     opt?: unknown,
    //     out?: number[]
    // ): number[];
    // `out?: number[]` perf out-param dropped, value-returning (CONVENTIONS §3).
    func dataToPoint(_ data: CoordinateSystemDataCoord, _ opt: Any?) -> [Double]

    /**
     * @param data See the meaning in `dataToPoint`.
     * @param reserved Defined by the coordinate system itself
     * @param out Fill it if passing, and return. For performance optimization. Vary by different coord sys.
     * @return Layout in global pixel coordinate system.
     *  An invalid returned rect should be represented by `{x: NaN, y: NaN, width: NaN, height: NaN}`,
     *  Never return `null/undefined`.
     */
    // dataToLayout?(
    //     data: CoordinateSystemDataCoord,
    //     opt?: unknown,
    //     out?: CoordinateSystemDataLayout
    // ): CoordinateSystemDataLayout;
    // `out?` perf out-param dropped, value-returning (CONVENTIONS §3).
    func dataToLayout(_ data: CoordinateSystemDataCoord, _ opt: Any?) -> CoordinateSystemDataLayout?

    /**
     * Some coord sys (like Parallel) might do not have `pointToData`,
     * or the meaning of this kind of features is not clear yet.
     * @param point point Point in global pixel coordinate system.
     * @param out Fill it if passing, and return. For performance optimization.
     * @return data
     *  An invalid returned data should be represented by `[NaN, NaN]` or `NaN`,
     *  rather than `null/undefined`, which represents not-applicable in `convertFromPixel`.
     *  Return `OrdinalNumber` in ordianal (category axis) case.
     *  Return timestamp in time axis.
     */
    // pointToData?(
    //     point: number[],
    //     opt?: unknown,
    //     out?: number | number[]
    // ): number | number[];
    // `out?`/return `number | number[]` erased to `Any?` (no Swift union); out-param dropped.
    func pointToData(_ point: [Double], _ opt: Any?) -> Any?

    // @param point Point in global pixel coordinate system.
    // containPoint(point: number[]): boolean;
    func containPoint(_ point: [Double]) -> Bool

    // getAxes?: () => Axis[];
    func getAxes() -> [Axis]?

    // getAxis?: (dim?: DimensionName) => Axis;
    func getAxis(_ dim: DimensionName?) -> Axis?

    /**
     * FIXME: Remove this method? See details in `Cartesian2D['getBaseAxis']`
     */
    // getBaseAxis?: () => Axis;
    func getBaseAxis() -> Axis?

    // getOtherAxis?: (baseAxis: Axis) => Axis;
    func getOtherAxis(_ baseAxis: Axis) -> Axis?

    // clampData?: (data: ScaleDataValue[], out?: number[]) => number[];
    // `out?` perf out-param dropped, value-returning (CONVENTIONS §3).
    func clampData(_ data: [ScaleDataValue]) -> [Double]?

    // getArea?: (tolerance?: number) => CoordinateSystemClipArea;
    func getArea(_ tolerance: Double?) -> CoordinateSystemClipArea?

    // shouldClip?: () => boolean;
    func shouldClip() -> Bool?

    /**
     * Optional; e.g. only for `GeoLikeCoordSys`.
     * External geo like extensions are required to implements it.
     * This is a rect in data space.
     * For historicall reason, the name is `getBoundingRect` - preserve it for backward compatibility.
     * @see VIEW_COORD_SYS_TRANS_RAW
     */
    // getBoundingRect?: () => BoundingRect;
    func getBoundingRect() -> BoundingRect?

    /**
     * Optional; e.g. only for `GeoLikeCoordSys`.
     * External geo like extensions are required to implements it.
     * @see VIEW_COORD_SYS_TRANS_RAW
     */
    // getViewRect?: () => BoundingRect;
    func getViewRect() -> BoundingRect?

    /**
     * Optional; e.g. only for `GeoLikeCoordSys`.
     * External geo like extensions are required to implements it.
     */
    // getRoamTransform?: () => MatrixArray;
    func getRoamTransform() -> MatrixArray?

    // Currently only Cartesian2D implements it.
    // But if other coordinate systems implement it, should follow this signature.
    // getAxesByScale?: (scaleType: string) => Axis[];
    func getAxesByScale(_ scaleType: String) -> [Axis]?

    // prepareCustoms?: PrepareCustomInfo;
    var prepareCustoms: PrepareCustomInfo? { get }
}
// `master` / `model` and every `?`-marked method above are upstream-optional. Modeled as
//   protocol requirements with nil-returning defaults so conformers may omit them (Swift has no optional
//   protocol members).
public extension CoordinateSystem {
    var master: CoordinateSystemMaster? { get { nil } set {} }
    var model: ComponentModel? { get { nil } set {} }
    func dataToLayout(_ data: CoordinateSystemDataCoord, _ opt: Any?) -> CoordinateSystemDataLayout? { nil }
    func pointToData(_ point: [Double], _ opt: Any?) -> Any? { nil }
    func getAxes() -> [Axis]? { nil }
    func getAxis(_ dim: DimensionName?) -> Axis? { nil }
    func getBaseAxis() -> Axis? { nil }
    func getOtherAxis(_ baseAxis: Axis) -> Axis? { nil }
    func clampData(_ data: [ScaleDataValue]) -> [Double]? { nil }
    func getArea(_ tolerance: Double?) -> CoordinateSystemClipArea? { nil }
    func shouldClip() -> Bool? { nil }
    func getBoundingRect() -> BoundingRect? { nil }
    func getViewRect() -> BoundingRect? { nil }
    func getRoamTransform() -> MatrixArray? { nil }
    func getAxesByScale(_ scaleType: String) -> [Axis]? { nil }
    var prepareCustoms: PrepareCustomInfo? { nil }
}

/**
 * Like GridModel, PolarModel, ...
 */
// export interface CoordinateSystemHostModel extends ComponentModel {
//     coordinateSystem?: CoordinateSystemMaster
// }
// TS `interface extends class ComponentModel`; Swift protocol cannot inherit a class,
//   so constrain `Self: ComponentModel` instead (equivalent contract).
public protocol CoordinateSystemHostModel where Self: ComponentModel {
    var coordinateSystem: CoordinateSystemMaster? { get set }
}

/**
 * Clip area will be returned by getArea of CoordinateSystem.
 * It is used to clip the graphic elements with the contain methods.
 */
public protocol CoordinateSystemClipArea {
    var x: Double { get set }
    var y: Double { get set }
    var width: Double { get set }
    var height: Double { get set }
    func contain(_ x: Double, _ y: Double) -> Bool
}

// export function isCoordinateSystemType<T extends CoordinateSystem, S = T['type']>(
//     coordSys: CoordinateSystem, type: S
// ): coordSys is T {
//     return (coordSys.type as unknown as S) === type;
// }
// TS type-guard (`coordSys is T`) erased; Swift returns a plain Bool. Callers narrow via
//   `as?` at the call site. `type` union `T['type']` modeled as String.
public func isCoordinateSystemType(_ coordSys: CoordinateSystem, _ type: String) -> Bool {
    return coordSys.type == type
}

// Coord sys can be 'geo' 'bmap' 'amap' 'gmap' 'leaflet' ...
// export interface GeoLikeCoordSys extends CoordinateSystem {
//     dimensions: ['lng', 'lat']
//     getViewRect: CoordinateSystem['getViewRect'] // Mandatory (e.g., for heatmap)
//     // PENDING: also check `getBoundingRect` and `getRoamTransform`?
// }
// `dimensions: ['lng', 'lat']` tuple-literal type narrowed to `[DimensionName]`.
public protocol GeoLikeCoordSys: CoordinateSystem {
    // getViewRect: CoordinateSystem['getViewRect'] // Mandatory (e.g., for heatmap)
    func getViewRect() -> BoundingRect?
    // PENDING: also check `getBoundingRect` and `getRoamTransform`?
}

// export function isGeoLikeCoordSys(coordSys: CoordinateSystem): coordSys is GeoLikeCoordSys {
//     const dimensions = coordSys.dimensions;
//     // Not use coordSys.type === 'geo' because coordSys maybe extended
//     return dimensions[0] === 'lng' && dimensions[1] === 'lat' && !!coordSys.getViewRect;
// }
// TS type-guard erased to Bool; `!!coordSys.getViewRect` (method existence) checked via
//   the non-nil return of the optional `getViewRect()` default.
public func isGeoLikeCoordSys(_ coordSys: CoordinateSystem) -> Bool {
    let dimensions = coordSys.dimensions
    // Not use coordSys.type === 'geo' because coordSys maybe extended
    return dimensions[0] == "lng" && dimensions[1] == "lat" && coordSys.getViewRect() != nil
}
