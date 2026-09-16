// Ported from echarts/src/chart/custom/CustomSeries.ts — keep in sync with upstream
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
//   import Displayable from 'zrender/src/graphic/Displayable';           -> ZRenderKit.Displayable (type-only here).
//   import { ImageProps, ImageStyleProps } from 'zrender/src/graphic/Image';   -> ZRenderKit (type-only; element option
//       shapes are the `[String: Any]` bag per CONVENTIONS §2).
//   import { PathProps, PathStyleProps } from 'zrender/src/graphic/Path';      -> ZRenderKit (type-only).
//   import { ZRenderType } from 'zrender/src/zrender';                   -> `Any?` (getZr() return; ZRenderType facade).
//   import { BarGridLayoutOptionForCustomSeries, BarGridLayoutResultForCustomSeries } from '../../layout/barGrid';
//       -> note: layout/barGrid.swift is ported (BarGridLayoutOptionForCustomSeries / ...Result); the `barLayout` API here is still typed `Any`.
//   import { ...many... } from '../../util/types';                        -> util/types.swift (type-only; the dynamic
//       option tree is the `[String: Any]` bag per CONVENTIONS §2).
//   import Element from 'zrender/src/Element';                            -> ZRenderKit.Element.
//   import SeriesData, { DefaultDataVisual } from '../../data/SeriesData';  -> SeriesData (data/SeriesData.swift).
//   import GlobalModel from '../../model/Global';                         -> GlobalModel (model/Global.swift).
//   import createSeriesData from '../helper/createSeriesData';            -> `createSeriesData` (chart/helper/createSeriesData.swift).
//   import { makeInner } from '../../util/model';                         -> model.makeInner (util/modelUtil.swift).
//   import { CoordinateSystem } from '../../coord/CoordinateSystem';      -> coord/CoordinateSystem.swift (type-only).
//   import SeriesModel from '../../model/Series';                         -> SeriesModel (model/Series.swift).
//   import { Arc, BezierCurve, Circle, CompoundPath, Ellipse, Line, Polygon, Polyline, Rect, Ring, Sector }
//       from '../../util/graphic';                                        -> ZRenderKit shapes (used only in the
//       type-only `BuiltinShapes` interface below; no Swift types emitted for it).
//   import { TextProps, TextStyleProps } from 'zrender/src/graphic/Text';  -> ZRenderKit (type-only).
//   import { GroupProps } from 'zrender/src/graphic/Group';               -> ZRenderKit (type-only).
//   import { TransitionOptionMixin, TransitionBaseDuringAPI, TransitionDuringAPI }
//       from '../../animation/customGraphicTransition';
//       -> TODO: requires animation/customGraphicTransition (NOT ported — enter/update/leave
//          transition, per the CUSTOM port brief). The `during` / transition option shapes are documentation-only.
//   import { TransformProp } from 'zrender/src/core/Transformable';       -> ZRenderKit (type-only).
//   import { ElementKeyframeAnimationOption } from '../../animation/customGraphicKeyframeAnimation';
//       -> TODO: requires animation/customGraphicKeyframeAnimation (keyframe animation NOT ported).

// export type CustomExtraElementInfo = Dictionary<unknown>;
public typealias CustomExtraElementInfo = [String: Any]

// Also compat with ec4, where
// `visual('color') visual('borderColor')` is supported.
// export const STYLE_VISUAL_TYPE = { color: 'fill', borderColor: 'stroke' } as const;
public let STYLE_VISUAL_TYPE: [String: String] = [
    "color": "fill",
    "borderColor": "stroke"
]
// export type StyleVisualProps = keyof typeof STYLE_VISUAL_TYPE;  -> "color" | "borderColor" (type-only).

// export const NON_STYLE_VISUAL_PROPS = { symbol, symbolSize, symbolKeepAspect, legendIcon, visualMeta,
//     liftZ, decal } as const;
public let NON_STYLE_VISUAL_PROPS: [String: Double] = [
    "symbol": 1,
    "symbolSize": 1,
    "symbolKeepAspect": 1,
    "legendIcon": 1,
    "visualMeta": 1,
    "liftZ": 1,
    "decal": 1
]
// export type NonStyleVisualProps = keyof typeof NON_STYLE_VISUAL_PROPS;  -> the keys above (type-only).

// ============================================================================
// The following upstream `interface`/`type` declarations describe the (dynamic) CUSTOM element option
// tree that a `renderItem` callback returns. Per CONVENTIONS §2 each element spec is the `[String: Any]`
// bag (the same bag the ported `GraphicComponentView` already turns into ZRenderKit elements), so these
// are kept as documentation only — no Swift types are emitted for them. The two public aliases below
// (`CustomElementOption`, `CustomRootElementOption`) name that bag so call sites read faithfully.
// ============================================================================
//
// type ShapeMorphingOption = { morph?: boolean };  // only available on path. TODO: shape morphing.
//
// interface CustomBaseElementOption extends Partial<Pick<Element,
//     TransformProp | 'silent' | 'ignore' | 'textConfig'>> {
//     type: string;              // element type, required.
//     id?: string;
//     name?: string;             // For animation diff.
//     info?: CustomExtraElementInfo;
//     textContent?: CustomTextOption | false;   // `false` means remove the textContent.
//     clipPath?: CustomBaseZRPathOption | false; // `false` means remove the clipPath
//     tooltipDisabled?: boolean; // `false` means not show tooltip
//     extra?: Dictionary<unknown> & TransitionOptionMixin;
//     during?(params: TransitionBaseDuringAPI): void;   // updateDuringAnimation. TODO: requires customGraphicTransition.
//     enterAnimation?: AnimationOption
//     updateAnimation?: AnimationOption
//     leaveAnimation?: AnimationOption
// }
// interface CustomDisplayableOption extends CustomBaseElementOption, Partial<Pick<Displayable,
//     'zlevel' | 'z' | 'z2' | 'invisible'>> {
//     style?: ZRStyleProps;
//     during?(params: TransitionDuringAPI): void;
//     styleEmphasis?: ZRStyleProps | false;   // @deprecated. `false` means remove emphasis trigger.
//     emphasis?: CustomDisplayableOptionOnState;
//     blur?: CustomDisplayableOptionOnState;
//     select?: CustomDisplayableOptionOnState;
// }
// interface CustomDisplayableOptionOnState extends Partial<Pick<Displayable,
//     TransformProp | 'textConfig' | 'z2'>> {
//     style?: ZRStyleProps | false;   // `false` means remove emphasis trigger.
// }
// interface CustomGroupOption extends CustomBaseElementOption, TransitionOptionMixin<GroupProps> {
//     type: 'group';
//     width?: number;
//     height?: number;
//     diffChildrenByName?: boolean;   // @deprecated
//     children: CustomElementOption[];
//     $mergeChildren?: false | 'byName' | 'byIndex';
//     keyframeAnimation?: ElementKeyframeAnimationOption<GroupProps> | ...[]
// }
// interface CustomBaseZRPathOption<T> extends CustomDisplayableOption, ShapeMorphingOption,
//     TransitionOptionMixin<PathProps & {shape: T}> {
//     autoBatch?: boolean;
//     shape?: T & TransitionOptionMixin<T>;
//     style?: PathProps['style'] & TransitionOptionMixin<PathStyleProps>
//     during?(params: TransitionDuringAPI<PathStyleProps, T>): void;
//     keyframeAnimation?: ...
// }
// interface BuiltinShapes {  // the built-in path shapes a custom path may name via `type`:
//     circle, rect, sector, polygon, polyline, line, arc, bezierCurve, ring, ellipse, compoundPath
// }   // each maps to the ZRenderKit shape of the same name (Circle/Rect/Sector/...).
// interface CustomSVGPathShapeOption {
//     pathData?: string;   // SVG Path, like 'M0,0 L0,-20 L70,-1 L70,0 Z'
//     d?: string;          // "d" is the alias of `pathData` follows the SVG convention.
//     layout?: 'center' | 'cover';
//     x?, y?, width?, height?: number;
// }
// interface CustomSVGPathOption extends CustomBaseZRPathOption<CustomSVGPathShapeOption> { type: 'path'; }
// type CustomPathOption = CreateCustomBuitinPathOption<keyof BuiltinShapes> | CustomSVGPathOption;
// interface CustomImageOption extends CustomDisplayableOption, TransitionOptionMixin<ImageProps> {
//     type: 'image'; style?: ImageStyleProps ...; emphasis/blur/select?: CustomImageOptionOnState;
// }
// interface CustomTextOption extends CustomDisplayableOption, TransitionOptionMixin<TextProps> {
//     type: 'text'; style?: TextStyleProps ...; emphasis/blur/select?: CustomTextOptionOnState;
// }
// interface CustomCompoundPathOption extends CustomDisplayableOption, TransitionOptionMixin<PathProps> {
//     type: 'compoundPath'; shape?: PathProps['shape']; style?: PathStyleProps ...;
// }

// export type CustomElementOption = CustomPathOption | CustomImageOption | CustomTextOption
//     | CustomCompoundPathOption | CustomGroupOption;
//   -> the dynamic element-spec bag (CONVENTIONS §2).
public typealias CustomElementOption = [String: Any]

// export type CustomRootElementOption = CustomElementOption & {
//     focus?: 'none' | 'self' | 'series' | ArrayLike<number>
//     blurScope?: BlurScope
//     emphasisDisabled?: boolean
// };   // Can only set focus, blur on the root element.
//   -> same dynamic bag; `focus`/`blurScope`/`emphasisDisabled` are extra keys (emphasis states DEFERRED).
public typealias CustomRootElementOption = [String: Any]

// export type CustomElementOptionOnState = CustomDisplayableOptionOnState | CustomImageOptionOnState;
//   -> the dynamic per-state bag (type-only).
public typealias CustomElementOptionOnState = [String: Any]

// -----------------------------------------------------------------------------
// The renderItem API. Upstream declares these as `interface`s that the CustomView constructs a concrete
// object for. Ported as protocols so the (DEFERRED) `CustomView` can implement them and the user's
// `renderItem` closure can call through them. Optional TS methods (`size`, `layout`) get protocol-
// extension defaults, documenting that upstream marks them optional.
// -----------------------------------------------------------------------------

// export interface CustomSeriesRenderItemParamsCoordSys { type: string; /* + extra params per coord sys */ }
//   Data bag (no identity) -> struct. `extra` carries the per-coord-system params (e.g. cartesian2d
//   `x/y/width/height`, polar `cx/cy/r/r0`).
public struct CustomSeriesRenderItemParamsCoordSys {
    public var type: String
    // And extra params for each coordinate systems.
    public var extra: [String: Any]
    public init(type: String, extra: [String: Any] = [:]) {
        self.type = type
        self.extra = extra
    }
}

// export interface CustomSeriesRenderItemCoordinateSystemAPI {
//     coord(data, opt?): number[];
//     size?(dataSize, dataItem?): number | number[];
//     layout?(data, opt?): CoordinateSystemDataLayout;
// }
public protocol CustomSeriesRenderItemCoordinateSystemAPI: AnyObject {
    // coord(
    //     data: (OptionDataValue | NullUndefined) | (...)[] | ...,   // @see CoordinateSystemDataCoord
    //     opt?: unknown   // Some coord sys may support `clamp?: boolean`. Can also be an `{xxx?: ...}`.
    // ): number[];
    func coord(_ data: Any?, _ opt: Any?) -> [Double]

    // size?(
    //     dataSize: OptionDataValue | OptionDataValue[],  // a range, rather than an absolute value.
    //     dataItem?: OptionDataValue | OptionDataValue[]  // a data point, based on which to calc size.
    // ): number | number[];
    //   Optional in TS -> protocol-extension default returns nil (see below).
    func size(_ dataSize: Any?, _ dataItem: Any?) -> Any?

    // layout?(data, opt?): CoordinateSystemDataLayout;   Optional in TS -> default returns nil.
    func layout(_ data: Any?, _ opt: Any?) -> CoordinateSystemDataLayout?
}
public extension CustomSeriesRenderItemCoordinateSystemAPI {
    // Upstream marks `size` / `layout` optional (`size?` / `layout?`); a coord sys that does not
    // support them omits the method. Modeled as defaulting to nil (the JS `undefined` slot).
    func size(_ dataSize: Any?, _ dataItem: Any?) -> Any? { return nil }
    func layout(_ data: Any?, _ opt: Any?) -> CoordinateSystemDataLayout? { return nil }
}

// export interface CustomSeriesRenderItemAPI extends CustomSeriesRenderItemCoordinateSystemAPI { ... }
public protocol CustomSeriesRenderItemAPI: CustomSeriesRenderItemCoordinateSystemAPI {
    // Methods from ExtensionAPI.
    // NOTE: Not using Pick<ExtensionAPI> here because we don't want to bundle ExtensionAPI into the d.ts
    func getWidth() -> Double
    func getHeight() -> Double
    // getZr(): ZRenderType  -> note: ZRenderType facade typed `Any?`.
    func getZr() -> Any?
    func getDevicePixelRatio() -> Double

    // value(dim, dataIndexInside?): ParsedValue;
    func value(_ dim: DimensionLoose, _ dataIndexInside: Double?) -> ParsedValue
    // ordinalRawValue(dim, dataIndexInside?): ParsedValue | OrdinalRawValue;
    func ordinalRawValue(_ dim: DimensionLoose, _ dataIndexInside: Double?) -> Any?

    // @deprecated  style(userProps?, dataIndexInside?): ZRStyleProps;
    func style(_ userProps: [String: Any]?, _ dataIndexInside: Double?) -> [String: Any]
    // @deprecated  styleEmphasis(userProps?, dataIndexInside?): ZRStyleProps;
    func styleEmphasis(_ userProps: [String: Any]?, _ dataIndexInside: Double?) -> [String: Any]

    // visual<VT>(visualType, dataIndexInside?): ...   (NonStyleVisualProps | StyleVisualProps)
    func visual(_ visualType: String, _ dataIndexInside: Double?) -> Any?

    // barLayout(opt: BarGridLayoutOptionForCustomSeries): BarGridLayoutResultForCustomSeries;
    //   layout/barGrid custom types are ported (barGrid.swift); opt/result kept `Any` here.
    func barLayout(_ opt: Any?) -> Any?

    // currentSeriesIndices(): number[];
    func currentSeriesIndices() -> [Double]

    // font(opt: Pick<TextCommonOption, 'fontStyle' | 'fontWeight' | 'fontSize' | 'fontFamily'>): string;
    func font(_ opt: [String: Any]?) -> String
}

// export type WrapEncodeDefRet = Dictionary<number[]>;
public typealias WrapEncodeDefRet = [String: [Double]]

// `params.context` is one mutable object shared by every `renderItem` invocation in a render round.
// A reference type is required here: a Swift Dictionary is copy-on-write, so carrying it directly on
// the value-typed params bag silently gave each datum an isolated context.
public final class CustomSeriesRenderItemContext {
    private var storage: [String: Any]

    public init(_ storage: [String: Any] = [:]) {
        self.storage = storage
    }

    public subscript(_ key: String) -> Any? {
        get { storage[key] }
        set { storage[key] = newValue }
    }

    public var dictionary: [String: Any] { storage }
}

// export interface CustomSeriesRenderItemParams { ... }
//   The params bag itself has value semantics; its `context` deliberately has identity semantics.
public struct CustomSeriesRenderItemParams {
    // context: Dictionary<unknown>;
    public var context: CustomSeriesRenderItemContext
    public var dataIndex: Double
    public var seriesId: String
    public var seriesName: String
    public var seriesIndex: Double
    public var coordSys: CustomSeriesRenderItemParamsCoordSys
    public var encode: WrapEncodeDefRet

    public var dataIndexInside: Double
    public var dataInsideLength: Double
    // itemPayload: Dictionary<unknown>;
    public var itemPayload: [String: Any]

    public var actionType: String?

    public init(
        context: CustomSeriesRenderItemContext = CustomSeriesRenderItemContext(),
        dataIndex: Double = 0,
        seriesId: String = "",
        seriesName: String = "",
        seriesIndex: Double = 0,
        coordSys: CustomSeriesRenderItemParamsCoordSys,
        encode: WrapEncodeDefRet = [:],
        dataIndexInside: Double = 0,
        dataInsideLength: Double = 0,
        itemPayload: [String: Any] = [:],
        actionType: String? = nil
    ) {
        self.context = context
        self.dataIndex = dataIndex
        self.seriesId = seriesId
        self.seriesName = seriesName
        self.seriesIndex = seriesIndex
        self.coordSys = coordSys
        self.encode = encode
        self.dataIndexInside = dataIndexInside
        self.dataInsideLength = dataInsideLength
        self.itemPayload = itemPayload
        self.actionType = actionType
    }
}

// export type CustomSeriesRenderItemReturn = CustomRootElementOption | undefined | null;
//   -> the returned element spec, or nil. Modeled as `Any?` so the closure may also return an array of
//      specs / a group bag (CONVENTIONS §2 dynamic union), matching the CUSTOM port brief.
public typealias CustomSeriesRenderItemReturn = Any?

// export type CustomSeriesRenderItem = (params, api) => CustomSeriesRenderItemReturn;
//   The user-supplied Swift closure stored on the series option under key "renderItem".
public typealias CustomSeriesRenderItem = (
    _ params: CustomSeriesRenderItemParams,
    _ api: CustomSeriesRenderItemAPI
) -> CustomSeriesRenderItemReturn

// ============================================================================
// export interface CustomSeriesOption extends SeriesOption<unknown>, ...mixins... { ... }
// Per CONVENTIONS §2 the option tree is the `[String: Any]` bag; kept as documentation only:
//     type?: 'custom'
//     coordinateSystem?: string | 'none'   // If set as 'none', do not depend on coord sys.
//     renderItem?: CustomSeriesRenderItem;
//     itemPayload?: Dictionary<unknown>;
//     itemStyle?: ItemStyleOption;   // @deprecated
//     label?: LabelOption;           // @deprecated
//     emphasis?: { itemStyle?; label? } // @deprecated
//     clip?: boolean;   // Only works on polar and cartesian2d coordinate system.
// ============================================================================

// export const customInnerStore = makeInner<{
//     info; customPathData; customGraphicType; customImagePath; txConZ2Set; option;
// }, Element>();
//   The anonymous inner-store record is modeled as a small class (`makeInner` requires a class Host/value
//   per CONVENTIONS §2 + innerStore.swift). Upstream reads/writes `customInnerStore(el).info` etc.
public final class CustomInnerStore {
    public var info: CustomExtraElementInfo?
    public var customPathData: String?
    public var customGraphicType: String?
    // customImagePath: CustomImageOption['style']['image'];  -> the image source (string | HTMLImageElement).
    public var customImagePath: Any?
    // customText: string;   (commented out upstream)
    public var txConZ2Set: Double?
    // option: CustomElementOption;
    public var option: CustomElementOption?
    public init() {}
}
public let customInnerStore: (Element) -> CustomInnerStore =
    model.makeInner { CustomInnerStore() }

// upstream: getDataParams returns `CallbackDataParams & { info: CustomExtraElementInfo }`.
//   `CallbackDataParams` is a struct with a fixed field set (no `info`), so the intersection is modeled
//   as a small wrapper carrying both (CONVENTIONS §4 — data bag).
public struct CustomCallbackDataParams {
    public var params: CallbackDataParams
    public var info: CustomExtraElementInfo?
    public init(_ params: CallbackDataParams, info: CustomExtraElementInfo? = nil) {
        self.params = params
        self.info = info
    }
}

// export default class CustomSeriesModel extends SeriesModel<CustomSeriesOption>
open class CustomSeriesModel: SeriesModel {

    // static type = 'series.custom';  /  readonly type = CustomSeriesModel.type;
    //   The static drives the instance `type` (inherited `var type { Self.type }` from ComponentModel).
    public override class var type: ComponentFullType { return "series.custom" }

    // static dependencies = ['grid', 'polar', 'geo', 'singleAxis', 'calendar', 'matrix'];
    //   TODO: only grid/cartesian2d + polar coord systems are renderable now (geo/singleAxis/
    //   calendar/matrix not ported); the list is kept verbatim so registration/topo order matches upstream.
    public override class var dependencies: [String] {
        return ["grid", "polar", "geo", "singleAxis", "calendar", "matrix"]
    }

    // preventAutoZ = true;   (commented out upstream)

    // currentZLevel: number;  /  currentZ: number;
    //   Populated by `optionUpdated` from `get('zlevel', true)` / `get('z', true)`.
    public var currentZLevel: Double = 0
    public var currentZ: Double = 0

    // static defaultOption: CustomSeriesOption = { ... }
    open override class var defaultOption: ModelOption? {
        return [
            "coordinateSystem": "cartesian2d", // Can be set as 'none'
            // zlevel: 0,
            "z": 2.0,
            "legendHoverLink": true,

            // Custom series will not clip by default.
            // Some case will use custom series to draw label
            // For example https://echarts.apache.org/examples/en/editor.html?c=custom-gantt-flight
            "clip": false

            // Cartesian coordinate system
            // xAxisIndex: 0,
            // yAxisIndex: 0,

            // Polar coordinate system
            // polarIndex: 0,

            // Geo coordinate system
            // geoIndex: 0,
        ] as [String: Any]
    }

    // optionUpdated() {
    //     this.currentZLevel = this.get('zlevel', true);
    //     this.currentZ = this.get('z', true);
    // }
    //   Upstream overrides the param-less form; the ported base is
    //   `optionUpdated(_ newCptOption:, _ isInit:)` (from ComponentModel), so we override that signature
    //   and ignore the args, keeping the body faithful.
    open override func optionUpdated(_ newCptOption: ModelOption?, _ isInit: Bool) {
        self.currentZLevel = asDouble(self.get("zlevel", true))
        self.currentZ = asDouble(self.get("z", true))
    }

    // getInitialData(option, ecModel): SeriesData {
    //     return createSeriesData(null, this);
    // }
    open override func getInitialData(_ option: ModelOption?, _ ecModel: GlobalModel?) -> SeriesData? {
        return createSeriesData(nil, self)
    }

    // getDataParams(dataIndex, dataType?, el?): CallbackDataParams & { info: CustomExtraElementInfo } {
    //     const params = super.getDataParams(dataIndex, dataType) as ...;
    //     el && (params.info = customInnerStore(el).info);
    //     return params;
    // }
    //   Overloaded (extra `el` param + wrapper return type) rather than overriding the base
    //   DataFormatMixin.getDataParams (a protocol-extension member with a different return type).
    open func getDataParams(
        _ dataIndex: Double,
        _ dataType: SeriesDataType? = nil,
        _ el: Element? = nil
    ) -> CustomCallbackDataParams {
        // super.getDataParams(dataIndex, dataType) — the base impl is the DataFormatMixin protocol-
        //   extension method (not a class member), so it is reached through a protocol-typed self. This
        //   also disambiguates from this 3-arg overload (which is invisible through `DataFormatMixin`),
        //   avoiding a self-recursion in overload resolution.
        let params = (self as DataFormatMixin).getDataParams(dataIndex, dataType)
        var result = CustomCallbackDataParams(params)
        // el && (params.info = customInnerStore(el).info);
        if let el = el {
            result.info = customInnerStore(el).info
        }
        return result
    }

    // -----------------------------------------------------------------------------
    // The `renderItem` option accessor. Upstream has no method for this — CustomView reads
    // `customSeries.get('renderItem')`. Exposed here as a stored-closure accessor: the user sets the
    // Swift closure on the series option under key "renderItem"; this returns it (falling back to the
    // by-type registry is done by the DEFERRED CustomView via `getCustomSeries(self.subType)`).
    // -----------------------------------------------------------------------------
    open func getRenderItem() -> CustomSeriesRenderItem? {
        // this.get('renderItem') — the option bag stores the raw closure.
        return self.get("renderItem") as? CustomSeriesRenderItem
    }
}

// export default CustomSeriesModel;  -> `open class CustomSeriesModel` above.

// export type PrepareCustomInfo = (coordSys: CoordinateSystem) => {
//     coordSys: CustomSeriesRenderItemParamsCoordSys;
//     api: CustomSeriesRenderItemCoordinateSystemAPI
// };
//   The coord-sys → (params-coordSys, coord-API) preparer registered by each coordinate system.
//   Consumed by the DEFERRED CustomView.
public typealias PrepareCustomInfo = (_ coordSys: Any?) -> (
    coordSys: CustomSeriesRenderItemParamsCoordSys,
    api: CustomSeriesRenderItemCoordinateSystemAPI
)

// JS number coercion shim for the dynamic option bag (upstream reads `this.get('zlevel', true)` etc.
// as `number`; an Int-boxed default must not drop to nil — CONVENTIONS INT-vs-DOUBLE trap). Not an
// upstream symbol; file-private per port convention.
private func asDouble(_ v: Any?) -> Double {
    if let d = v as? Double { return d }
    if let i = v as? Int { return Double(i) }
    if let n = v as? NSNumber { return n.doubleValue }
    if let s = v as? String, let d = Double(s) { return d }
    return 0
}
