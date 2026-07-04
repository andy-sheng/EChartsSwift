// Ported from echarts/src/util/types.ts — keep in sync with upstream
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

/**
 * [Notice]:
 * Consider custom bundle on demand, chart specified
 * or component specified types and constants should
 * not put here. Only common types and constants can
 * be put in this file.
 */

import ZRenderKit

// upstream imports (reused from ZRenderKit where ported):
//   import Group from 'zrender/src/graphic/Group';                              → ZRenderKit.Group
//   import Element, {ElementEvent, ElementTextConfig} from 'zrender/src/Element'; → ZRenderKit.Element / ElementEvent / ElementTextConfig
//   import { createHashMap, HashMap } from 'zrender/src/core/util';             → PORT-TODO: not yet ported (see util.swift)
//   import { Dictionary, ElementEventName, ImageLike, TextAlign, TextVerticalAlign } from 'zrender/src/core/types'; → ZRenderKit
//   import { PatternObject } from 'zrender/src/graphic/Pattern';                → ZRenderKit (modeled as PatternObjectBase, see below)
//   import { AnimationEasing } from 'zrender/src/animation/easing';             → ZRenderKit.AnimationEasing
//   import { LinearGradientObject } from 'zrender/src/graphic/LinearGradient';  → ZRenderKit.LinearGradientObject
//   import { RadialGradientObject } from 'zrender/src/graphic/RadialGradient';  → ZRenderKit.RadialGradientObject
//   import { RectLike } from 'zrender/src/core/BoundingRect';                   → ZRenderKit.RectLike
//   import { TSpanStyleProps } from 'zrender/src/graphic/TSpan';                → ZRenderKit.TSpanStyleProps
//   import { PathStyleProps } from 'zrender/src/graphic/Path';                  → ZRenderKit.PathStyleProps
//   import { ImageStyleProps } from 'zrender/src/graphic/Image';                → ZRenderKit.ImageStyleProps
//   import ZRText, { TextStyleProps } from 'zrender/src/graphic/Text';          → ZRenderKit.ZRText / TextStyleProps

// ============================================================================
// PORT-TODO: FORWARD-REFERENCE PLACEHOLDERS
// Upstream `types.ts` `import type`s these from sibling echarts files that are
// NOT yet ported in this phase (handled by other agents). They are declared
// here as minimal placeholders so this spine file compiles. The agent that
// ports the corresponding source file MUST remove the placeholder here and
// replace it with the real, fully-ported type.
// ============================================================================

// '../model/mixin/dataFormat' — DataFormatMixin
//   Now ported: see `DataFormatMixin` (protocol + extension) in model/mixin/dataFormat.swift.
// '../model/Global' — GlobalModel
//   The real `GlobalModel` (`open class GlobalModel: Model, PaletteMixin`) is now ported in
//   model/Global.swift (this phase); the forward-reference placeholder protocol was removed to avoid
//   a redeclaration. Generics are dropped per CONVENTIONS (`Opt` -> the dynamic `ECUnitOption` bag).
//   Existing uses (`GlobalModel` as a param/return type, closure types) resolve against the class,
//   which is a subclass of `Model` and conforms to `AnyObject`.
// '../core/ExtensionAPI' — ExtensionAPI
//   Now the real `open class ExtensionAPI` (core/ExtensionAPI.swift); the placeholder protocol is
//   removed to avoid a redeclaration. Existing uses (param/return/closure types) resolve against the
//   class, which conforms to `AnyObject`.
// '../model/Series' — SeriesModel (upstream is generic SeriesModel<Opt>)
//   The real `SeriesModel` (`open class SeriesModel: ComponentModel, PaletteMixin, DataHost`) is now
//   ported in model/Series.swift (this phase); the forward-reference placeholder protocol was removed
//   to avoid a redeclaration. Generics are dropped per CONVENTIONS (`Opt` -> the dynamic `ModelOption`
//   = `Any` option bag). Existing uses (`[SeriesModel]`, params, closure types) continue to resolve
//   against the class.
//   PORT-TODO: the placeholder protocol exposed a *non-optional* `ecModel: GlobalModel`; the real
//   class inherits `Model.ecModel: GlobalModel?` (optional). Consumers that read `seriesModel.ecModel`
//   as non-optional (e.g. data/helper/sourceHelper) must unwrap once Model.ecModel optionality is
//   reconciled with Global.
// '../data/SeriesData' — SeriesData
//   The real `SeriesData` (`final class`) is now ported in data/SeriesData.swift; the
//   forward-reference placeholder protocol was removed to avoid a redeclaration (the class
//   provides `dimensions`/`getDimensionInfo`/`getDimensionIndex` consumed by dimensionHelper).
// '../data/Source' — Source
//   The real `Source` (typealias to `SourceImpl`) is now ported in data/Source.swift;
//   the forward-reference placeholder protocol was removed to avoid a redeclaration.
// '../model/Model' — Model (upstream is generic Model<Opt>)
//   The real `Model` (`open class`) is now ported in model/Model.swift (Phase 5c); the
//   forward-reference placeholder protocol was removed to avoid a redeclaration. Generics are
//   dropped per CONVENTIONS (`Opt` -> the dynamic `ModelOption` = `Any` option bag).
// '../model/Component' — ComponentModel (upstream is generic ComponentModel<Opt>)
//   The real `ComponentModel` (`open class ComponentModel: Model, ClassManageable`) is now ported in
//   model/Component.swift (this phase); the forward-reference placeholder protocol was removed to
//   avoid a redeclaration. Generics are dropped per CONVENTIONS (`Opt` -> the dynamic `ModelOption`
//   = `Any` option bag). Existing uses (`[ComponentModel]`, `ComponentModel & RoamHostModel`, params)
//   continue to resolve against the class.
// '../coord/View' — View
//   The real `View` (`open class View: Transformable`) is now ported in coord/View.swift (Phase 23);
//   the forward-reference placeholder protocol was removed to avoid a redeclaration (same pattern as
//   `ComponentModel`/`ChartView` above). Existing opaque uses continue to resolve against the class.
// '../view/Chart' — ChartView
//   The real `ChartView` (`open class ChartView`) is now ported in view/Chart.swift (this phase);
//   the forward-reference placeholder protocol was removed to avoid a redeclaration (same pattern
//   as `ComponentModel` above). Existing opaque uses (`ChartView?`, `-> ChartView`, params in
//   Scheduler/ExtensionAPI/modelUtil) continue to resolve against the class.
// '../view/Component' — ComponentView
//   Now ported: the real `open class ComponentView` lives in view/ComponentView.swift (this phase);
//   the forward-reference placeholder protocol was removed to avoid a redeclaration. Existing uses
//   (ExtensionAPI.getViewOfComponentModel return type, etc.) continue to resolve against the class.
// './format' — TooltipMarker = string | RichTextTooltipMarker.
//   Now ported: see `format.TooltipMarker` (enum) in util/format.swift.
public typealias TooltipMarker = format.TooltipMarker
// '../data/DataStore' — DataStoreDimensionType = keyof typeof dataCtors
public enum DataStoreDimensionType: String {                               // PORT-TODO: belongs to data/DataStore
    case float
    case int
    // Ordinal data type can be string or int
    case ordinal
    case number
    case time
}
// '../data/helper/dimensionHelper' — DimensionUserOuputEncode
public typealias DimensionUserOuputEncode = Dictionary<[Double]>           // PORT-TODO
// './time' — PrimaryTimeUnit = (typeof primaryTimeUnits)[number]
//   Now fully ported in util/time.swift (same module); the placeholder was removed.
// '../core/task' — TaskPlanCallbackReturn, TaskProgressParams
//   Now fully ported in core/task.swift (same module); the placeholders were removed.

// DOM lib types referenced by upstream (browser only / backend seam, CONVENTIONS §9):
public typealias HTMLElement = Any                                         // PORT-TODO: DOM type
public typealias HTMLDivElement = Any                                      // PORT-TODO: DOM type
// lib.dom CanvasLineCap = 'butt' | 'round' | 'square'
public typealias CanvasLineCap = String                                    // PORT-TODO: DOM union
// lib.dom CanvasLineJoin = 'round' | 'bevel' | 'miter'
public typealias CanvasLineJoin = String                                   // PORT-TODO: DOM union


// ---------------------------
// Common types and constants
// ---------------------------

// upstream: export {Dictionary}; — `Dictionary<T>` (= [String: T]) is re-exported from
//   ZRenderKit.Core.types and available here via `import ZRenderKit`.

public enum RendererType: String {
    case canvas
    case svg
}
/**
 * NOTICE: For historical reason, echarts and zrender have not enabled TS config
 * `strictNullChecks` yet. Therefore, a explicitly declared `NullUndefined` can
 * indicate a variable can be `null` or `undefined` without more investigation,
 * but a variable without `NullUndefined` may also be `null` or `undefined`,
 * which has to be determined by the implementation.
 */
// PORT-TODO: `NullUndefined = null | undefined` has no standalone Swift type; per
//   CONVENTIONS §6 both collapse to `nil` (`T?`) at use sites.
public let UNDEFINED_STR = "undefined"

public enum LayoutOrient: String {
    case vertical
    case horizontal
}
public enum HorizontalAlign: String {
    case left
    case center
    case right
}
public enum VerticalAlign: String {
    case top
    case middle
    case bottom
}

// Types from zrender
public typealias ColorString = String
// upstream: ColorString | LinearGradientObject | RadialGradientObject | PatternObject
//   modeled as a tagged enum (CONVENTIONS §2). PatternObject is the union
//   ImagePatternObject | SVGPatternObject in zrender, here the common base protocol.
public enum ZRColor {
    case color(ColorString)
    case linearGradient(LinearGradientObject)
    case radialGradient(RadialGradientObject)
    case pattern(PatternObjectBase)
}
// upstream: 'solid' | 'dotted' | 'dashed' | number | number[]
public enum ZRLineType {
    case solid
    case dotted
    case dashed
    case number(Double)
    case numbers([Double])
}

public enum ZRFontStyle: String {
    case normal
    case italic
    case oblique
}
// upstream: 'normal' | 'bold' | 'bolder' | 'lighter' | number
public enum ZRFontWeight {
    case normal
    case bold
    case bolder
    case lighter
    case number(Double)
}

public typealias ZREasing = AnimationEasing

public typealias ZRTextAlign = TextAlign
public typealias ZRTextVerticalAlign = TextVerticalAlign

public typealias ZRElementEvent = ElementEvent

public typealias ZRRectLike = RectLike

// upstream: PathStyleProps | ImageStyleProps | TSpanStyleProps | TextStyleProps
public enum ZRStyleProps {
    case path(PathStyleProps)
    case image(ImageStyleProps)
    case tspan(TSpanStyleProps)
    case text(TextStyleProps)
}

// upstream: ElementEventName | 'globalout'. The ported `ElementEventName` enum already
//   carries a `.globalout` case, so this aliases it directly.
public typealias ZRElementEventName = ElementEventName

// ComponentFullType can be:
//     'a.b': means ComponentMainType.ComponentSubType.
//     'a': means ComponentMainType.
// See `checkClassType` check the restict definition.
public typealias ComponentFullType = String
// upstream: keyof ECUnitOption & string
public typealias ComponentMainType = String                               // PORT-TODO: keyof ECUnitOption
// upstream: Exclude<ComponentOption['type'], undefined>
public typealias ComponentSubType = String                                // PORT-TODO: Exclude<...>
/**
 * Use `parseClassType` to parse componentType declaration to componentTypeInfo.
 * For example:
 * componentType declaration: 'a.b', get componentTypeInfo {main: 'a', sub: 'b'}.
 * componentType declaration: '', get componentTypeInfo {main: '', sub: ''}.
 */
public struct ComponentTypeInfo {
    public var main: ComponentMainType // Never null/undefined. `''` represents absence.
    public var sub: ComponentSubType   // Never null/undefined. `''` represents absence.
    public init(main: ComponentMainType, sub: ComponentSubType) {
        self.main = main
        self.sub = sub
    }
}

public let COMPONENT_MAIN_TYPE_SERIES = "series"

// upstream: interface ECElement extends Element { ... } — augments the scene-graph class with
//   optional echarts-internal props. Modeled as a protocol (Swift cannot add stored props to the
//   `Element` class via an interface). PORT-TODO: confirm augmentation strategy when consumed.
public protocol ECElement: AnyObject {
    var highDownSilentOnTouch: Bool? { get set }
    var onHoverStateChange: ((DisplayState) -> Void)? { get set }

    // 0: normal
    // 1: blur
    // 2: emphasis
    var hoverState: Double? { get set } // upstream: 0 | 1 | 2
    var selected: Bool? { get set }

    var z2EmphasisLift: Double? { get set }
    var z2SelectLift: Double? { get set }

    /**
     * Force enable animation.
     * This property is useful when an ignored/invisible/removed element
     * should have label animation, like the case in the bar-racing charts.
     * `forceLabelAnimation` has higher priority than `disableLabelAnimation`.
     */
    var forceLabelAnimation: Bool? { get set }
    /**
     * Force disable animation.
     * `forceLabelAnimation` has higher priority than `disableLabelAnimation`.
     */
    var disableLabelAnimation: Bool? { get set }
    /**
     * Force disable overall layout
     */
    var disableLabelLayout: Bool? { get set }
    /**
     * Force disable morphing
     */
    var disableMorphing: Bool? { get set }
    /**
     * Force disable triggering tooltip
     */
    var tooltipDisabled: Bool? { get set }
}

public protocol DataHost {
    func getData(_ dataType: SeriesDataType?) -> SeriesData
}

// upstream: interface DataModel extends Model<unknown>, DataHost, DataFormatMixin { ... }
// PORT-TODO: `Model` is now a concrete `open class` (model/Model.swift); a Swift protocol cannot
//   refine a class, so the `extends Model<unknown>` arm is dropped here. A `DataModel` is, in
//   upstream, also a `Model` — conforming types are `ComponentModel`/`SeriesModel` subclasses of
//   `Model` — but that IS-A relationship is no longer expressible through this protocol.
public protocol DataModel: DataHost, DataFormatMixin {
    func getDataParams(_ dataIndex: Double, _ dataType: SeriesDataType?, _ el: Element?) -> CallbackDataParams
}
    // Pick<DataHost, 'getData'>,
    // Pick<DataFormatMixin, 'getDataParams' | 'formatTooltip'> {}

// upstream: interface PayloadItem { excludeSeriesId?, animation?, [other: string]: any; }
//   The `[other: string]: any` index signature is not representable on a Swift struct; the
//   dynamic remainder is carried in `other` (CONVENTIONS dynamic-bag = [String: Any]).
public struct PayloadItem {
    public var excludeSeriesId: Any? // OptionId | OptionId[]
    public var animation: PayloadAnimationPart?
    // TODO use unknown
    public var other: Dictionary<Any> = [:]   // PORT-TODO: upstream `[other: string]: any`
    public init() {}
}

public struct Payload {
    public var type: String
    public var escapeConnect: Bool?
    public var batch: [PayloadItem]?
    // ---- inherited from PayloadItem ----
    public var excludeSeriesId: Any? // OptionId | OptionId[]
    public var animation: PayloadAnimationPart?
    public var other: Dictionary<Any> = [:]   // PORT-TODO: upstream `[other: string]: any`
    public init(type: String) { self.type = type }
}

public struct HighlightPayload {
    public var type: String = "highlight"
    public var notBlur: Bool?
    // ---- inherited from Payload ----
    public var escapeConnect: Bool?
    public var batch: [PayloadItem]?
    public var excludeSeriesId: Any?
    public var animation: PayloadAnimationPart?
    public var other: Dictionary<Any> = [:]
    public init() {}
}

public struct DownplayPayload {
    public var type: String = "downplay"
    public var notBlur: Bool?
    // ---- inherited from Payload ----
    public var escapeConnect: Bool?
    public var batch: [PayloadItem]?
    public var excludeSeriesId: Any?
    public var animation: PayloadAnimationPart?
    public var other: Dictionary<Any> = [:]
    public init() {}
}

// Payload includes override animation info
public struct PayloadAnimationPart {
    public var duration: Double?
    public var easing: AnimationEasing?
    public var delay: Double?
    public init() {}
}

public struct SelectedItem {
    public var seriesIndex: Double
    public var dataType: SeriesDataType?
    public var dataIndex: [Double]
}
public struct SelectChangedEvent {
    public var type: String = "selectchanged"
    public var isFromClick: Bool = false
    public var fromAction: String = "select" // 'select' | 'unselect' | 'toggleSelected'
    public var fromActionPayload: Payload?
    public var selected: [SelectedItem] = []
    public init() {}
}
/**
 * @deprecated Backward compat.
 */
public struct SelectChangedPayload {
    public var type: String = "selectchanged"
    public var isFromClick: Bool = false
    public var fromAction: String = "select" // 'select' | 'unselect' | 'toggleSelected'
    public var fromActionPayload: Payload?
    public var selected: [SelectedItem] = []
    public init() {}
}

// upstream: interface ViewRootGroup extends Group { __ecComponentInfo?: {...} } — augments
//   the `Group` instance. Modeled as a protocol (PORT-TODO: confirm augmentation strategy).
public struct ViewRootGroupComponentInfo {
    public var mainType: String
    public var index: Double
}
public protocol ViewRootGroup: AnyObject {
    var __ecComponentInfo: ViewRootGroupComponentInfo? { get set }
}

// upstream: interface ECElementEvent extends ECEventData, CallbackDataParams { type, event? }
//   Multiple data-bag inheritance is not representable; modeled with the explicit own fields plus
//   an embedded `CallbackDataParams` and the dynamic `ECEventData` remainder.
public struct ECElementEvent {
    public var type: ZRElementEventName
    public var event: ElementEvent?
    public var dataParams: CallbackDataParams                              // PORT-TODO: extends CallbackDataParams
    public var eventData: ECEventData = [:]                               // PORT-TODO: extends ECEventData
}
/**
 * The echarts event type to user.
 * Also known as packedEvent.
 */
public struct ECActionEvent {
    // event type
    public var type: String
    public var componentType: String?
    public var componentIndex: Double?
    public var seriesIndex: Double?
    public var escapeConnect: Bool?
    public var batch: [ECEventData]?
    public var eventData: ECEventData = [:]                               // PORT-TODO: extends ECEventData
    public init(type: String) { self.type = type }
}
/**
 * TODO: not applicable in `ECEventProcessor` yet.
 */
public struct ECActionRefinedEvent {
    // event type
    public var type: String
    // action types.
    public var fromAction: String
    public var fromActionPayload: Payload?
    // ---- inherited from ECActionEvent ----
    public var componentType: String?
    public var componentIndex: Double?
    public var seriesIndex: Double?
    public var escapeConnect: Bool?
    public var batch: [ECEventData]?
    public var eventData: ECEventData = [:]
    public init(type: String, fromAction: String) {
        self.type = type
        self.fromAction = fromAction
    }
}
// upstream: type ECActionRefinedEventContent<T> = Omit<T, 'type' | 'fromAction' | 'fromActionPayload'>
public typealias ECActionRefinedEventContent = Dictionary<Any>            // PORT-TODO: Omit<...>

// upstream: interface ECEventData { [key: string]: any; }
public typealias ECEventData = Dictionary<Any>

// upstream: interface EventQueryItem { [key: string]: any; }
public typealias EventQueryItem = Dictionary<Any>
public struct NormalizedEventQuery {
    public var cptQuery: EventQueryItem
    public var dataQuery: EventQueryItem
    public var otherQuery: EventQueryItem
}

/**
 * The rule of creating "public event" and "event for connect":
 *  - If `refineEvent` provided,
 *      `refineEvent` creates the "public event",
 *      and "event for connect" is created internally by replicating the payload.
 *      This is because `makeActionFromEvent` requires the content of event to be
 *      the same as the original payload, while `refineEvent` creates a user-friend
 *      event that differs from the original payload.
 *  - Else if `ActionHandler` returns an object,
 *      it is both the "public event" and the "event for connect".
 *      (@deprecated, but keep this mechanism for backward compatibility).
 *  - Else,
 *      replicate the payload as both the "public event" and "event for connect".
 */
public struct ActionInfo {
    // action type
    public var type: String
    // If not provided, use the same string of `type`.
    public var event: String?
    // Update method. (See upstream comment block for the full semantics.)
    // By default 'update' (i.e., EC_FULL_UPDATE).
    public var update: String?
    // `ActionHandler` is designed to do nothing other than modify models.
    public var action: ActionHandler?
    // `refineEvent` is intended to create a user-friend event that differs from the original payload.
    public var refineEvent: ActionRefineEvent?
    // When `refineEvent` is provided, still publish the auto generated "event for connect" to users.
    public var publishNonRefinedEvent: Bool?
    // Experimental - may change in future; only internal usage is allowed.
    public var componentQuery: Bool?
    public init(type: String) { self.type = type }
}
// upstream: (payload, ecModel, api): void | ECEventData
public typealias ActionHandler = (Payload, GlobalModel, ExtensionAPI) -> ECEventData?
public struct ActionRefineEventResult {
    public var eventContent: ECActionRefinedEventContent
}
// upstream: (actionResultBatch, payload, ecModel, api): { eventContent }
public typealias ActionRefineEvent =
    ([ECEventData], Payload, GlobalModel, ExtensionAPI) -> ActionRefineEventResult
// upstream: { mainType: ComponentMainType, indexList: number[] }[]
public struct ActionUpdateComponentQueryItem {
    public var mainType: ComponentMainType
    public var indexList: [Double]
}
public typealias ActionUpdateComponentQuery = [ActionUpdateComponentQueryItem]

// upstream: (option: ECUnitOption, isTheme: boolean): void
public typealias OptionPreprocessor = (ECUnitOption, Bool) -> Void

// upstream: (ecModel: GlobalModel, api: ExtensionAPI): void
public typealias PostUpdater = (GlobalModel, ExtensionAPI) -> Void

// upstream: (seriesModel, ecModel, api, payload?): StageHandlerProgressExecutor | [...] | void
public typealias StageHandlerReset =
    (SeriesModel, GlobalModel, ExtensionAPI, Payload?) -> Any?            // PORT-TODO: return union
// upstream: (ecModel, api, payload?): void
public typealias StageHandlerOverallReset = (GlobalModel, ExtensionAPI, Payload?) -> Void
public struct StageHandler {
    /**
     * Indicate that the "series stage task" will be piped for all series
     * (filtered series is included iff `performRawSeries: true`).
     *
     * OVERALL_STAGE_TASK (See `overallReset`) can not set `createOnAllSeries: true`.
     */
    public var createOnAllSeries: Bool?
    /**
     * Indicate that the task will only be piped in the pipeline of this type of series.
     * (filtered series is included iff `performRawSeries: true`).
     * It is available for both `reset` and `overallReset`.
     */
    public var seriesType: String?
    /**
     * Indicate that the task will only be piped in the pipeline of the returned series.
     * It is called in EC_PREPARE, before `CoordinateSystem['create']`.
     * It is available for both `reset` and `overallReset`.
     */
    public var getTargetSeries: ((GlobalModel, ExtensionAPI) -> [String: SeriesModel])?  // PORT-TODO: HashMap<SeriesModel>
    /**
     * If `true`, filtered series will also be "performed".
     */
    public var performRawSeries: Bool?
    /**
     * Called only when this task in a pipeline.
     */
    public var plan: StageHandlerPlan?
    /**
     * If `overallReset` is specified, an OVERALL_STAGE_TASK will be created.
     * (See upstream comment for the OVERALL_STAGE_TASK tutorial.)
     */
    public var overallReset: StageHandlerOverallReset?
    /**
     * If `reset` is specified, a SERIES_STAGE_TASK will be created.
     * (See upstream comment for the SERIES_STAGE_TASK tutorial.)
     */
    public var reset: StageHandlerReset?
    /**
     * This is a temporary mechanism primarily for a dataZoom case in `appendData`.
     * (See upstream comment for the full semantics.)
     */
    public var dirtyOnOverallProgress: Bool?
    public init() {}
}

public struct StageHandlerInternal {
    public var uid: String
    public var visualType: String? // 'layout' | 'visual'
    // modifyOutputEnd?: boolean;
    public var __prio: Double
    public var __raw: Any // StageHandler | StageHandlerOverallReset
    public var isVisual: Bool? // PENDING: not used
    public var isLayout: Bool? // PENDING: not used
    // ---- inherited from StageHandler ----
    public var handler: StageHandler
}


public typealias StageHandlerProgressParams = TaskProgressParams
public struct StageHandlerProgressExecutor {
    public var dataEach: ((SeriesData, Double) -> Void)?
    public var progress: ((StageHandlerProgressParams, SeriesData) -> Void)?
    public init() {}
}
public typealias StageHandlerPlanReturn = TaskPlanCallbackReturn
// upstream: (seriesModel, ecModel, api, payload?): StageHandlerPlanReturn
public typealias StageHandlerPlan =
    (SeriesModel, GlobalModel, ExtensionAPI, Payload?) -> StageHandlerPlanReturn

// upstream: (api: ExtensionAPI, cfg: object): LoadingEffect
public typealias LoadingEffectCreator = (ExtensionAPI, Any) -> LoadingEffect
// upstream: interface LoadingEffect extends Element { resize: () => void; }
public protocol LoadingEffect: AnyObject {                                 // PORT-TODO: extends Element
    var resize: () -> Void { get }
}

/**
 * 'html' is used for rendering tooltip in extra DOM form, and the result
 * string is used as DOM HTML content.
 * 'richText' is used for rendering tooltip in rich text form, for those where
 * DOM operation is not supported.
 */
public enum TooltipRenderMode: String {
    case html
    case richText
}

public enum TooltipOrderMode: String {
    case valueAsc
    case valueDesc
    case seriesAsc
    case seriesDesc
}


// ---------------------------------
// Data and dimension related types
// ---------------------------------

// Represents the values in series.data that need to be treated in a non-numeric way.
// Can be used by axis.type 'category' (i.e. scale.type 'ordinal').
// Finally the user data will be parsed and stored in `list._storage`.
// `NaN` represents "no data" (raw data `null`/`undefined`/`NaN`/`'-'`).
// Ordinal/category data will be parsed to its index if possible, otherwise
// keep its original string in list._storage.
// Check `convertValue` for more details.
// upstream: OrdinalRawValue = string | number
public typealias OrdinalRawValue = Any                                     // PORT-TODO: string | number
public typealias OrdinalNumber = Double // The number mapped from each OrdinalRawValue.

/**
 * @usage
 * For example, `{ ordinalNumbers: [2, 5, 3, 4] }` (see upstream for full semantics).
 */
public struct OrdinalSortInfo {
    public var ordinalNumbers: [OrdinalNumber]
}

/**
 * `OptionDataValue` is the primitive value in `series.data` or `dataset.source`.
 * (See upstream comment for the parse pipeline details.)
 */
// upstream: ParsedValue = ParsedValueNumeric | OrdinalRawValue
public typealias ParsedValue = Any                                         // PORT-TODO: ParsedValueNumeric | OrdinalRawValue
// upstream: ParsedValueNumeric = number | OrdinalNumber
public typealias ParsedValueNumeric = Double

/**
 * `ScaleDataValue` represents the user input axis value in echarts API.
 * (See upstream comment for the nuances vs `OptionDataValue`.)
 */
// upstream: ParsedValueNumeric | OrdinalRawValue | Date
public typealias ScaleDataValue = Any                                      // PORT-TODO: number | OrdinalRawValue | Date


/**
 * - `ScaleDataValue`: e.g. geo accept that primitive input, like `convertToPixel('some_place')`.
 * - `ScaleDataValue[]`: each array item represent each data in every dimension.
 * - `(ScaleDataValue[])[]`: represents `[data_range_x, data_range_y]`.
 */
// upstream: (ScaleDataValue | NullUndefined) | (...)[]| (...)[]
public typealias CoordinateSystemDataCoord = Any                          // PORT-TODO: nested union

public struct AxisBreakOption {
    public var start: ScaleDataValue
    public var end: ScaleDataValue
    // - `number`: same unit as data value (not pixel).
    // - `string`: like '35%' (percent over axis extent), or numeric string like `'123'`.
    // - If omitted, means 0.
    public var gap: Any? // number | string
    // undefined means false
    public var isExpanded: Bool?
}
// Within an axis, this is the identifier among multiple breaks.
// upstream: Pick<AxisBreakOption, 'start' | 'end'>
public struct AxisBreakOptionIdentifierInAxis {
    public var start: ScaleDataValue
    public var end: ScaleDataValue
}

// - Parsed from the breaks in axis model.
// - Never be null/undefined.
// - Contain only unexpanded breaks.
public typealias ParsedAxisBreakList = [ParsedAxisBreak]
public struct ParsedAxisBreakGapParsed {
    public var type: String // 'tpAbs' | 'tpPrct'
    // If 'tpPrct', means percent, val is in 0~1.
    // If 'tpAbs', means absolute value, val is numeric gap value from option.
    public var val: Double
}
public struct ParsedAxisBreak {
    // Keep breakOption.start/breakOption.end to identify the target break item in echarts action.
    public var breakOption: AxisBreakOption
    // - Parsed start/end value (e.g. data string '2021-12-12' -> timestamp number).
    // - `vmin <= vmax` is ensured in parsing.
    public var vmin: Double
    public var vmax: Double
    // Parsed from `AxisBreakOption['gap']`. Need to save this intermediate value
    // because LogScale need to logarithmically transform to them.
    public var gapParsed: ParsedAxisBreakGapParsed
    // Final calculated gap.
    public var gapReal: Double? // number | NullUndefined
}
public struct VisualAxisBreak {
    public var type: String // 'vmin' | 'vmax'
    public var parsedBreak: ParsedAxisBreak
}
public struct AxisLabelFormatterExtraBreakPartBreak {
    public var type: String // 'start' | 'end'
    public var start: Double // ParsedAxisBreak['vmin']
    public var end: Double   // ParsedAxisBreak['vmax']
}
public struct AxisLabelFormatterExtraBreakPart {
    public var `break`: AxisLabelFormatterExtraBreakPartBreak?
}

public struct ScaleTick {
    /**
     * This is a number corresponding to the the original business value,
     * that is, a value in the "outmost" space, the result of `Scale['parse']`.
     * (See upstream comment for the per-scale semantics and sorted/unsorted nuances.)
     */
    public var value: Double

    public var `break`: VisualAxisBreak?
    public var time: TimeScaleTickTime? // upstream: TimeScaleTick['time']
    // NOTICE: null/undefined mean it is unknown whether this tick is "nice".
    public var notNice: Bool? // boolean | NullUndefined
    // Only works on category axis.
    // Be `true` if this tick is out of category interval.
    public var offInterval: Bool? // boolean | NullUndefined
    public init(value: Double) { self.value = value }
}
public struct TimeScaleTickTime {
    /**
     * Level information is used for label formatting.
     * `level` is 0 or undefined by default, higher value = greater significance.
     * (See upstream comment for the leveled label formatting details.)
     */
    public var level: Double
    /**
     * An upper and lower time unit that is suggested to be displayed.
     * Terms upper/lower means, such as 'year' is "upper" and 'month' is "lower".
     * This is just suggestion. Time units that are out of this range can also be displayed.
     */
    public var upperTimeUnit: PrimaryTimeUnit
    public var lowerTimeUnit: PrimaryTimeUnit
}
public struct TimeScaleTick {
    // ---- inherited from ScaleTick ----
    public var value: Double
    public var `break`: VisualAxisBreak?
    public var notNice: Bool?
    public var offInterval: Bool?
    // ---- own (non-optional) ----
    public var time: TimeScaleTickTime
}

/**
 * Return type of API `CoordinateSystem['dataToLayout']`, expose to users.
 */
public struct CoordinateSystemDataLayout {
    // Base layout rect for a data item.
    public var rect: RectLike?
    // Commonly equals or shrinked from `rect, may considered padding and border
    // (depends on every coordinate system).
    public var contentRect: RectLike?
    // Only available in matrix coordinate system.
    public var matrixXYLocatorRange: [[Double]]?

    // May extend.
    public init() {}
}


// Can only be string or index, because it is used in object key in some code.
// Making the type alias here just intending to show the meaning clearly in code.
public typealias DimensionIndex = Double
// If being a number-like string but not being defined a dimension name.
// See `List.js#getDimension` for more details.
// upstream: DimensionIndex | string
public typealias DimensionIndexLoose = Any                                // PORT-TODO: number | string
public typealias DimensionName = String
// upstream: DimensionName | DimensionIndexLoose
public typealias DimensionLoose = Any                                     // PORT-TODO: string | number
public typealias DimensionType = DataStoreDimensionType

// PORT-TODO: createHashMap/HashMap not yet ported (zrender util). Modeled here as the key list.
//   upstream: createHashMap<number, keyof DataVisualDimensions>([...]).
public let VISUAL_DIMENSIONS: [String] = [
    "tooltip", "label", "itemName", "itemId", "itemGroupId", "itemChildGroupId", "seriesName"
]
// The key is VISUAL_DIMENSIONS
public struct DataVisualDimensions {
    // can be set as false to directly to prevent this data
    // dimension from displaying in the default tooltip.
    // see `Series.ts#formatTooltip`.
    public var tooltip: Any? // DimensionIndex | false
    public var label: DimensionIndex?
    public var itemName: DimensionIndex?
    public var itemId: DimensionIndex?
    public var itemGroupId: DimensionIndex?
    public var itemChildGroupId: DimensionIndex?
    public var seriesName: DimensionIndex?
    public init() {}
}

public struct DimensionDefinition {
    public var type: DataStoreDimensionType?
    public var name: DimensionName?
    public var displayName: String?
    public init() {}
}
// upstream: DimensionDefinition['name'] | DimensionDefinition
public typealias DimensionDefinitionLoose = Any                           // PORT-TODO: string | DimensionDefinition

public let SOURCE_FORMAT_ORIGINAL = "original"
public let SOURCE_FORMAT_ARRAY_ROWS = "arrayRows"
public let SOURCE_FORMAT_OBJECT_ROWS = "objectRows"
public let SOURCE_FORMAT_KEYED_COLUMNS = "keyedColumns"
public let SOURCE_FORMAT_TYPED_ARRAY = "typedArray"
public let SOURCE_FORMAT_UNKNOWN = "unknown"

// upstream: union of the typeof SOURCE_FORMAT_* literals
public typealias SourceFormat = String

public let SERIES_LAYOUT_BY_COLUMN = "column"
public let SERIES_LAYOUT_BY_ROW = "row"

// upstream: typeof SERIES_LAYOUT_BY_COLUMN | typeof SERIES_LAYOUT_BY_ROW
public typealias SeriesLayoutBy = String
// null/undefined/'auto': auto detect header, see "src/data/helper/sourceHelper".
// If number, means header lines count, or say, `startIndex`.
// Like `sourceHeader: 2`, means line 0 and line 1 are header, data start from line 2.
public typealias OptionSourceHeader = Any                                 // PORT-TODO: boolean | 'auto' | number

public enum SeriesDataType: String {
    case main
    case node
    case edge
}


// --------------------------------------------
// echarts option types (base and common part)
// --------------------------------------------

/**
 * [ECUnitOption]:
 * An object that contains definitions of components and other properties.
 * (See upstream comment for the example option shape.)
 *
 * upstream is an intersection of an index-signature object literal with
 * `AnimationOptionMixin & ColorPaletteOptionMixin`. The dynamic component map
 * (`[key: string]: ComponentOption | ComponentOption[] | Dictionary<unknown> | unknown`)
 * is modeled as a dynamic container per the project convention.
 */
public typealias ECUnitOption = Dictionary<Any>                          // PORT-TODO: typed mixin fields flattened into dynamic bag

/**
 * [ECOption]:
 * An object input to echarts.setOption(option).
 * May be an 'option: ECUnitOption', or may be an object contains multi-options.
 * (See upstream comment for the example option shape.)
 */
public struct ECBasicOption {
    public var baseOption: ECUnitOption?
    public var timeline: Any? // ComponentOption | ComponentOption[]
    public var options: [ECUnitOption]?
    public var media: [MediaUnit]?
    // ---- inherited from ECUnitOption (dynamic bag) ----
    public var unit: ECUnitOption = [:]
    public init() {}
}

// series.data or dataset.source
// upstream: union of original/objectRows/arrayRows/keyedColumns/typedArray source shapes.
public typealias OptionSourceData = Any                                   // PORT-TODO: source-shape union
// upstream: VAL | VAL[] | OptionDataItemObject<VAL>
public typealias OptionDataItemOriginal = Any                            // PORT-TODO: union
public typealias OptionSourceDataOriginal = [OptionDataItemOriginal]      // ArrayLike<ORIITEM>
public typealias OptionSourceDataObjectRows = [Dictionary<OptionDataValue>]
public typealias OptionSourceDataArrayRows = [[OptionDataValue]]
public typealias OptionSourceDataKeyedColumns = Dictionary<[OptionDataValue]>
public typealias OptionSourceDataTypedArray = [Double]                    // ArrayLike<number>

// See also `model.js#getDataItemValue`.
// upstream: OptionDataValue | Dictionary<OptionDataValue> | OptionDataValue[] | OptionDataItemObject<OptionDataValue>
public typealias OptionDataItem = Any                                     // PORT-TODO: union
// Only for `SOURCE_FORMAT_KEYED_ORIGINAL`
public struct OptionDataItemObject<T> {
    public var id: OptionId?
    public var name: OptionName?
    public var groupId: OptionId?
    public var childGroupId: OptionId?
    public var value: Any? // T[] | T
    public var selected: Bool?
    public init() {}
}
// Compat number because it is usually used and not easy to restrict it in practise.
// upstream: string | number
public typealias OptionId = Any                                           // PORT-TODO: string | number
// upstream: string | number
public typealias OptionName = Any                                         // PORT-TODO: string | number
public struct GraphEdgeItemObject<VAL> {
    // ---- inherited from OptionDataItemObject<VAL> ----
    public var id: OptionId?
    public var name: OptionName?
    public var groupId: OptionId?
    public var childGroupId: OptionId?
    public var value: Any?
    public var selected: Bool?
    /**
     * Name or index of source node.
     */
    public var source: Any? // string | number
    /**
     * Name or index of target node.
     */
    public var target: Any? // string | number
    public init() {}
}
// upstream: string | number | Date | null | undefined
public typealias OptionDataValue = Any?                                   // PORT-TODO: string | number | Date | null

// upstream: number | '-'
public typealias OptionDataValueNumeric = Any                            // PORT-TODO: number | '-'
public typealias OptionDataValueCategory = String
// upstream: Date | string | number
public typealias OptionDataValueDate = Any                                // PORT-TODO: Date | string | number

// export type ModelOption = Dictionary<any> | any[] | string | number | boolean | ((...args: any) => any);
public typealias ModelOption = Any
public typealias ThemeOption = Dictionary<Any>

public enum DisplayState: String {
    case normal
    case emphasis
    case blur
    case select
}
// upstream: Exclude<DisplayState, 'normal'>
public typealias DisplayStateNonNormal = DisplayState                     // PORT-TODO: Exclude<'normal'>
public struct DisplayStateHostOption {
    public var emphasis: Dictionary<Any>?
    public var other: Dictionary<Any> = [:]                              // PORT-TODO: upstream `[key: string]: any`
    public init() {}
}

// The key is VISUAL_DIMENSIONS
public struct OptionEncodeVisualDimensions {
    public var tooltip: OptionEncodeValue?
    public var label: OptionEncodeValue?
    public var itemName: OptionEncodeValue?
    public var itemId: OptionEncodeValue?
    public var seriesName: OptionEncodeValue?
    // Notice: `value` is coordDim, not nonCoordDim.

    // Group id is used for linking the aggregate relationship between two set of data.
    public var itemGroupId: OptionEncodeValue?
    public var childGroupdId: OptionEncodeValue?
    public init() {}
}
// upstream: interface OptionEncode extends OptionEncodeVisualDimensions { [coordDim: string]: OptionEncodeValue | undefined }
public typealias OptionEncode = Dictionary<OptionEncodeValue>            // PORT-TODO: extends OptionEncodeVisualDimensions
// upstream: DimensionLoose | DimensionLoose[]
public typealias OptionEncodeValue = Any                                  // PORT-TODO: DimensionLoose | DimensionLoose[]
public typealias EncodeDefaulter = (Source, Double) -> OptionEncode

// TODO: TYPE Different callback param for different series
public struct CallbackDataParams {
    // component main type
    public var componentType: String
    // component sub type
    public var componentSubType: String
    public var componentIndex: Double
    // series component sub type
    public var seriesType: String?
    // series component index (the alias of `componentIndex` for series)
    public var seriesIndex: Double?
    public var seriesId: String?
    public var seriesName: String?
    public var name: String
    public var dataIndex: Double
    public var data: OptionDataItem
    public var dataType: SeriesDataType?
    public var value: Any // OptionDataItem | OptionDataValue
    public var color: ZRColor?
    public var borderColor: String?
    public var dimensionNames: [DimensionName]?
    public var encode: DimensionUserOuputEncode?
    public var marker: TooltipMarker?
    public var status: DisplayState?
    public var dimensionIndex: Double?
    public var percent: Double? // Only for chart like 'pie'

    // Param name list for mapping `a`, `b`, `c`, `d`, `e`
    public var vars: [String]   // upstream: `$vars` ('$' prefix is reserved in Swift)
}
// upstream: ParsedValue | ParsedValue[]
public typealias InterpolatableValue = Any                                // PORT-TODO: ParsedValue | ParsedValue[]

// upstream: number | (number | number[])[]
public typealias DecalDashArrayX = Any                                    // PORT-TODO: number | (number | number[])[]
// upstream: number | number[]
public typealias DecalDashArrayY = Any                                    // PORT-TODO: number | number[]
public struct DecalObject {
    // 'image', 'triangle', 'diamond', 'pin', 'arrow', 'line', 'rect', 'roundRect', 'square', 'circle'
    public var symbol: Any? // string | string[]

    // size relative to the dash bounding box; valued from 0 to 1
    public var symbolSize: Double?
    // keep the aspect ratio and use the smaller one of width and height as bounding box size
    public var symbolKeepAspect: Bool?

    // foreground color of the pattern
    public var color: String?
    // background color of the pattern; default 'none' (transparent) so the underlying series color shows
    public var backgroundColor: String?

    // dash-gap pattern on x
    public var dashArrayX: DecalDashArrayX?
    // dash-gap pattern on y
    public var dashArrayY: DecalDashArrayY?

    // in radians; valued from -Math.PI to Math.PI
    public var rotation: Double?

    // boundary of largest tile width
    public var maxTileWidth: Double?
    // boundary of largest tile height
    public var maxTileHeight: Double?
    public init() {}
}

public struct InnerDecalObject {
    // ---- inherited from DecalObject ----
    public var decal: DecalObject
    // Mark dirty when object may be changed.
    // The record in WeakMap will be deleted.
    public var dirty: Bool?
}

public struct MediaQuery {
    public var minWidth: Double?
    public var maxWidth: Double?
    public var minHeight: Double?
    public var maxHeight: Double?
    public var minAspectRatio: Double?
    public var maxAspectRatio: Double?
    public init() {}
}
public struct MediaUnit {
    public var query: MediaQuery?
    public var option: ECUnitOption
}

public struct ComponentLayoutMode {
    // Only support 'box' now.
    public var type: String? // 'box'
    public var ignoreSize: Any? // boolean | boolean[]
    public init() {}
}

// ------------------ Mixins for Common Option Properties ------------------
public typealias PaletteOptionMixin = ColorPaletteOptionMixin

public struct ColorPaletteOptionMixin {
    public var color: Any? // ZRColor | ZRColor[]
    public var colorLayer: [[ZRColor]]?
    public init() {}
}

/**
 * Mixin of option set to control the box layout of each component.
 */
public struct BoxLayoutOptionMixin {
    public var width: PositionSizeOption?
    public var height: PositionSizeOption?
    public var top: PositionSizeOption?
    public var right: PositionSizeOption?
    public var bottom: PositionSizeOption?
    public var left: PositionSizeOption?
    public init() {}
}
/**
 * Need to be parsed by `parsePositionOption` or `parsePositionSizeOption`.
 * Accept number, or numeric string (`'123'`), or percentage ('100%'), as x/y/width/height pixel number.
 * If null/undefined or invalid, return NaN.
 */
// upstream: number | string
public typealias PositionSizeOption = Any                                 // PORT-TODO: number | string

public struct CircleLayoutOptionMixin {                                   // PORT-TODO: generic <TNuance>
    // Can be percent
    public var center: Any? // (number | string)[] | TNuance['centerExtra']
    // Can specify [innerRadius, outerRadius]
    public var radius: Any? // (number | string)[] | number | string
    public init() {}
}

public struct ShadowOptionMixin {
    public var shadowBlur: Double?
    public var shadowColor: ColorString?
    public var shadowOffsetX: Double?
    public var shadowOffsetY: Double?
    public init() {}
}

public struct BorderOptionMixin {
    public var borderColor: ZRColor?
    public var borderWidth: Double?
    public var borderType: ZRLineType?
    public var borderCap: CanvasLineCap?
    public var borderJoin: CanvasLineJoin?
    public var borderDashOffset: Double?
    public var borderMiterLimit: Double?
    public init() {}
}

public enum ColorBy: String {
    case series
    case data
}

public struct SunburstColorByMixin {
    public var colorBy: ColorBy?
    public init() {}
}

public struct AnimationDelayCallbackParam {
    public var count: Double
    public var index: Double
}
public typealias AnimationDurationCallback = (Double) -> Double
public typealias AnimationDelayCallback = (Double, AnimationDelayCallbackParam?) -> Double

public struct AnimationOption {
    public var duration: Double?
    public var easing: AnimationEasing?
    public var delay: Double?
    // additive?: boolean
    public init() {}
}

/**
 * Mixin of option set to control the animation of series.
 */
public struct AnimationOptionMixin {
    /**
     * If enable animation
     */
    public var animation: Bool?
    /**
     * Disable animation when the number of elements exceeds the threshold
     */
    public var animationThreshold: Double?
    // For init animation
    /**
     * Duration of initialize animation. Can be a callback to specify duration of each element
     */
    public var animationDuration: Any? // number | AnimationDurationCallback
    /**
     * Easing of initialize animation
     */
    public var animationEasing: AnimationEasing?
    /**
     * Delay of initialize animation. Can be a callback to specify duration of each element
     */
    public var animationDelay: Any? // number | AnimationDelayCallback
    // For update animation
    /**
     * Delay of data update animation. Can be a callback to specify duration of each element
     */
    public var animationDurationUpdate: Any? // number | AnimationDurationCallback
    /**
     * Easing of data update animation.
     */
    public var animationEasingUpdate: AnimationEasing?
    /**
     * Delay of data update animation. Can be a callback to specify duration of each element
     */
    public var animationDelayUpdate: Any? // number | AnimationDelayCallback
    public init() {}
}

public struct RoamOptionMixin {
    /**
     * If enable roam. can be specified 'scale' or 'move'
     */
    public var roam: Any? // boolean | 'pan' | 'move' | 'zoom' | 'scale'
    /**
     * Hover over an area where roaming is triggered. (See upstream comment for full semantics.)
     */
    public var roamTrigger: String? // 'global' | 'selfRect' | NullUndefined
    /**
     * @see VIEW_COORD_SYS_CENTER_ZOOM_DEFINITION
     */
    public var center: [Any]? // (number | string)[]
    /**
     * Current transformation scale. Default is 1.
     * @see VIEW_COORD_SYS_CENTER_ZOOM_DEFINITION
     */
    public var zoom: Double?
    /**
     * Limit of `zoom`. The name is inconsistent for historical reason.
     */
    public var scaleLimit: ScaleLimit?

    /**
     * Symbol size scale ratio on roaming.
     */
    public var nodeScaleRatio: Double?
    public init() {}

    public struct ScaleLimit {
        public var min: Double?
        public var max: Double?
        public init() {}
    }
}

public struct PreserveAspectMixin {
    // (See upstream comment for the preserveAspect semantics.)
    public var preserveAspect: Any? // boolean | 'contain' | 'cover'
    // By default 'center'
    public var preserveAspectAlign: String? // 'left' | 'right' | 'center'
    // By default 'middle'
    public var preserveAspectVerticalAlign: String? // 'top' | 'bottom' | 'middle'
    public init() {}
}

// TODO: TYPE value type?
// upstream: (rawValue: any, params: T) => number | number[]
public typealias SymbolSizeCallback<T> = (Any, T) -> Any                  // PORT-TODO: return number | number[]
public typealias SymbolCallback<T> = (Any, T) -> String
public typealias SymbolRotateCallback<T> = (Any, T) -> Double
// upstream: (rawValue: any, params: T) => string | number | (string | number)[]
public typealias SymbolOffsetCallback<T> = (Any, T) -> Any               // PORT-TODO: return union
/**
 * Mixin of option set to control the element symbol.
 * Include type of symbol, and size of symbol.
 */
public struct SymbolOptionMixin {                                         // PORT-TODO: generic <T = never> callback arms
    /**
     * type of symbol, like `cirlce`, `rect`, or custom path and image.
     */
    public var symbol: Any? // string | SymbolCallback<T>
    /**
     * Size of symbol.
     */
    public var symbolSize: Any? // number | number[] | SymbolSizeCallback<T>

    public var symbolRotate: Any? // number | SymbolRotateCallback<T>

    public var symbolKeepAspect: Bool?

    public var symbolOffset: Any? // string | number | (string | number)[] | SymbolOffsetCallback<T>
    public init() {}
}

/**
 * ItemStyleOption is a most common used set to config element styles.
 * It includes both fill and stroke style.
 */
public struct ItemStyleOption {                                           // PORT-TODO: generic <TCbParams = never>
    // ---- inherited from ShadowOptionMixin, BorderOptionMixin ----
    public var shadow = ShadowOptionMixin()
    public var border = BorderOptionMixin()
    public var color: Any? // ZRColor | ((params: TCbParams) => ZRColor)
    public var opacity: Double?
    public var decal: Any? // DecalObject | 'none'
    public var borderRadius: Any? // (number | string)[] | number | string
    public init() {}
}

/**
 * ItemStyleOption is a option set to control styles on lines.
 * Used in the components or series like `line`, `axis`. It includes stroke style.
 */
public struct LineStyleOption {                                           // PORT-TODO: generic <Clr = ZRColor>
    // ---- inherited from ShadowOptionMixin ----
    public var shadow = ShadowOptionMixin()
    public var width: Double?
    public var color: ZRColor? // upstream: Clr (defaults to ZRColor)
    public var opacity: Double?
    public var type: ZRLineType?
    public var cap: CanvasLineCap?
    public var join: CanvasLineJoin?
    public var dashOffset: Double?
    public var miterLimit: Double?
    public init() {}
}

/**
 * ItemStyleOption is a option set to control styles on an area, like polygon, rectangle.
 * It only include fill style.
 */
public struct AreaStyleOption {                                           // PORT-TODO: generic <Clr = ZRColor>
    // ---- inherited from ShadowOptionMixin ----
    public var shadow = ShadowOptionMixin()
    public var color: ZRColor? // upstream: Clr (defaults to ZRColor)
    public var opacity: Double?
    public init() {}
}

// upstream: type Arrayable<T> = { [key in keyof T]: T[key] | T[key][] };
// upstream: type Dictionaryable<T> = { [key in keyof T]: T[key] | Dictionary<T[key]> };
// PORT-TODO: TS homomorphic mapped types; modeled below where used as the VisualOption* aliases.

public struct VisualOptionUnit {
    public var symbol: String?
    // TODO Support [number, number]?
    public var symbolSize: Double?
    public var color: ColorString?
    public var colorAlpha: Double?
    public var opacity: Double?
    public var colorLightness: Double?
    public var colorSaturation: Double?
    public var colorHue: Double?
    public var decal: DecalObject?

    // Not exposed?
    public var liftZ: Double?
    public init() {}
}
public typealias VisualOptionFixed = VisualOptionUnit
/**
 * Option about visual properties used in piecewise mapping. Used in each piece.
 */
public typealias VisualOptionPiecewise = VisualOptionUnit
/**
 * Option about visual properties used in linear mapping
 */
// upstream: Arrayable<VisualOptionUnit>
public typealias VisualOptionLinear = Dictionary<Any>                    // PORT-TODO: Arrayable<VisualOptionUnit>

/**
 * Option about visual properties can be encoded from ordinal categories.
 * (See upstream comment for the per-property dictionary/array lookup semantics.)
 */
// upstream: Arrayable<VisualOptionUnit> | Dictionaryable<VisualOptionUnit>
public typealias VisualOptionCategory = Dictionary<Any>                  // PORT-TODO: Arrayable | Dictionaryable

/**
 * All visual properties can be encoded.
 */
// upstream: keyof VisualOptionUnit
public typealias BuiltinVisualProperty = String                          // PORT-TODO: keyof VisualOptionUnit

public typealias TextCommonOptionNuanceBase = Dictionary<Any>           // Record<string, unknown>
public typealias TextCommonOptionNuanceDefault = Dictionary<Any>        // {}
// 'auto' has been deprecated.
// upstream: ColorString | 'inherit' | 'auto'
public typealias LabelStyleColorString = String                         // Nominal as a comment.
public struct TextCommonOption {                                         // PORT-TODO: generic <TNuance>
    // ---- inherited from ShadowOptionMixin ----
    public var shadow = ShadowOptionMixin()
    public var color: Any? // LabelStyleColorString (+ optional TNuance['color'])
    public var fontStyle: ZRFontStyle?
    public var fontWeight: ZRFontWeight?
    public var fontFamily: String?
    public var fontSize: Any? // number | string
    public var align: HorizontalAlign?
    public var verticalAlign: VerticalAlign?
    // @deprecated
    public var baseline: VerticalAlign?

    public var opacity: Double?

    public var lineHeight: Double?
    public var backgroundColor: Any? // ColorString | { image: ImageLike | string }
    public var borderColor: String?
    public var borderWidth: Double?
    public var borderType: ZRLineType?
    public var borderDashOffset: Double?
    public var borderRadius: Any? // number | number[]
    public var padding: Any? // number | number[]
    /**
     * Currently margin related options are not declared here. They are not supported in rich text.
     * @see {LabelCommonOption}
     */

    public var width: Any? // number | string // Percent
    public var height: Double?
    public var textBorderColor: String?
    public var textBorderWidth: Double?
    public var textBorderType: ZRLineType?
    public var textBorderDashOffset: Double?

    public var textShadowBlur: Double?
    public var textShadowColor: String?
    public var textShadowOffsetX: Double?
    public var textShadowOffsetY: Double?

    public var tag: String?
    public init() {}
}

// upstream: Pick<TextCommonOption, 'color' | 'opacity' | 'fontStyle' | ...>
public typealias GlobalTextStyleOption = TextCommonOption                // PORT-TODO: Pick<...>

// upstream: interface RichTextOption extends Dictionary<TextCommonOption> {}
public typealias RichTextOption = Dictionary<TextCommonOption>

// upstream: (params: T) => string
public typealias LabelFormatterCallback<T> = (T) -> String
/**
 * LabelOption is an option set to control the style of labels.
 * Include color, background, shadow, truncate, rotation, distance, etc..
 */
public struct LabelOption {                                              // PORT-TODO: generic <TNuance>
    // ---- inherited from LabelCommonOption ----
    public var common = LabelCommonOption()
    /**
     * If show label
     */
    public var show: Bool?
    // TODO: TYPE More specified 'inside', 'insideTop'....
    // x, y can be both percent string or number px.
    public var position: Any? // ElementTextConfig['position'] | TNuance['positionExtra']
    public var distance: Double?
    public var rotate: Double?
    public var offset: [Double]?

    public var silent: Bool?
    public var precision: Any? // number | 'auto'
    public var valueAnimation: Bool?

    // TODO: TYPE not all label support formatter
    // formatter?: string | ((params: CallbackDataParams) => string)
    public init() {}
}

/**
 * Common options for both `axis.axisLabel`, `axis.nameTextStyle and other `label`s.
 * Historically, they have had some nuances in options.
 */
public struct LabelCommonOption {                                        // PORT-TODO: generic <TNuanceOption>
    // ---- inherited from TextCommonOption ----
    public var textCommon = TextCommonOption()

    /**
     * Min margin between labels. Used when label has layout.
     * (See upstream comment for the `minMargin` vs `margin` history and caution.)
     */
    public var minMargin: Double?
    /**
     * The space around the label to escape from overlapping.
     * (See upstream comment for the `textMargin` vs `margin`/`minMargin` nuances.)
     */
    public var textMargin: Any? // number | number[]

    public var overflow: String? // TextStyleProps['overflow']
    public var lineOverflow: String? // TextStyleProps['lineOverflow']
    public var ellipsis: String? // TextStyleProps['ellipsis']
    public var rich: RichTextOption?
    public init() {}
}

public struct SeriesLabelOption {                                        // PORT-TODO: generic <TCallbackDataParams, TNuance>
    // ---- inherited from LabelOption ----
    public var label = LabelOption()
    public var formatter: Any? // string | LabelFormatterCallback<TCallbackDataParams>
    public init() {}
}

/**
 * Option for labels on line, like markLine, lines
 */
public struct LineLabelOption {                                          // upstream: Omit<LabelOption, 'distance' | 'position'>
    // ---- inherited from LabelOption (minus distance/position) ----
    public var label = LabelOption()
    public var position: String? // 'start' | 'middle' | 'end' | 'insideStart' | ... (see upstream)
    /**
     * Distance can be an array. Which will specify horizontal and vertical distance respectively
     */
    public var distance: Any? // number | number[]
    public init() {}
}

public struct LabelLineOption {
    public var show: Bool?
    /**
     * If displayed above other elements
     */
    public var showAbove: Bool?
    public var length: Double?
    public var length2: Double?
    public var smooth: Any? // boolean | number
    public var minTurnAngle: Double?
    public var lineStyle: LineStyleOption?
    public init() {}
}

public struct SeriesLineLabelOption {
    // ---- inherited from LineLabelOption ----
    public var lineLabel = LineLabelOption()
    public var formatter: Any? // string | LabelFormatterCallback<CallbackDataParams>
    public init() {}
}



public struct LabelLayoutOptionCallbackParams {
    /**
     * Index of data which the label represents. Can be null if label doesn't represent any data.
     */
    public var dataIndex: Double?
    /**
     * Type of data which the label represents. Can be null if label doesn't represent any data.
     */
    public var dataType: SeriesDataType?
    public var seriesIndex: Double
    public var text: String
    public var align: ZRTextAlign
    public var verticalAlign: ZRTextVerticalAlign
    public var rect: RectLike
    public var labelRect: RectLike
    // Points of label line in pie/funnel
    public var labelLinePoints: [[Double]]?
    // x: number
    // y: number
}

public struct LabelLayoutOption {
    /**
     * If move the overlapped label. (See upstream comment for shiftX/Y vs shuffleX/Y.)
     */
    public var moveOverlap: String? // 'shiftX' | 'shiftY' | 'shuffleX' | 'shuffleY'
    /**
     * If hide the overlapped label. It will be handled after move.
     * @default 'none'
     */
    public var hideOverlap: Bool?
    /**
     * If label is draggable.
     */
    public var draggable: Bool?
    /**
     * Can be absolute px number or percent string.
     */
    public var x: Any? // number | string
    public var y: Any? // number | string
    /**
     * offset on x based on the original position.
     */
    public var dx: Double?
    /**
     * offset on y based on the original position.
     */
    public var dy: Double?
    public var rotate: Double?

    public var align: ZRTextAlign?
    public var verticalAlign: ZRTextVerticalAlign?
    public var width: Double?
    public var height: Double?
    public var fontSize: Double?

    public var labelLinePoints: [[Double]]?
    public init() {}
}

public typealias LabelLayoutOptionCallback = (LabelLayoutOptionCallbackParams) -> LabelLayoutOption


// upstream: interface TooltipFormatterCallback<T> with sync + async overloads returning
//   string | HTMLElement | HTMLElement[]. Modeled as a single closure (PORT-TODO: overloads / return union).
public typealias TooltipFormatterCallback<T> = (T, String, ((String, Any) -> Void)?) -> Any  // PORT-TODO

// upstream: 'inside' | 'top' | 'left' | 'right' | 'bottom'
public typealias TooltipBuiltinPosition = String                         // PORT-TODO: literal union
// upstream: Pick<BoxLayoutOptionMixin, 'top' | 'left' | 'right' | 'bottom'>
public struct TooltipBoxLayoutOption {
    public var top: PositionSizeOption?
    public var left: PositionSizeOption?
    public var right: PositionSizeOption?
    public var bottom: PositionSizeOption?
}

// upstream: CallbackDataParams | CallbackDataParams[]
public typealias TooltipPositionCallbackParams = Any                     // PORT-TODO: single | array

/**
 * Position relative to the hoverred element. Only available when trigger is item.
 */
// upstream: (point, params, el, rect, size) => Array<number | string> | TooltipBuiltinPosition | TooltipBoxLayoutOption
public typealias TooltipPositionCallback =
    ((Double, Double), TooltipPositionCallbackParams, Any?, RectLike?, TooltipPositionCallbackSize) -> Any  // PORT-TODO: return union
public struct TooltipPositionCallbackSize {
    /**
     * Size of popup content
     */
    public var contentSize: (Double, Double)
    /**
     * Size of the chart view
     */
    public var viewSize: (Double, Double)
}
/**
 * Common tooltip option. Can be configured on series, graphic elements
 */
public struct CommonTooltipOption<FormatterParams> {

    public var show: Bool?

    /**
     * When to trigger.
     * NOTE: mousewheel may modify view by dataZoom.
     */
    public var triggerOn: String? // 'mousemove' | 'click' | 'none' | 'mousewheel' | 'mousemove|click|mousewheel'
    /**
     * Whether to not hide popup content automatically
     */
    public var alwaysShowContent: Bool?

    public var formatter: Any? // string | TooltipFormatterCallback<FormatterParams>

    /**
     * Formatter of value. Will be ignored if tooltip.formatter is specified.
     */
    public var valueFormatter: ((Any, Double) -> String)? // (value: OptionDataValue | OptionDataValue[], dataIndex) => string
    /**
     * Absolution pixel [x, y] array. Or relative percent string [x, y] array.
     * If trigger is 'item'. position can be set to 'inside'/'top'/'left'/'right'/'bottom'.
     * Support to be a callback
     */
    public var position: Any? // (number | string)[] | TooltipBuiltinPosition | TooltipPositionCallback | TooltipBoxLayoutOption

    public var confine: Bool?

    /**
     * Consider triggered from axisPointer handle, verticalAlign should be 'middle'
     */
    public var align: HorizontalAlign?

    public var verticalAlign: VerticalAlign?
    /**
     * Delay of show. milesecond.
     */
    public var showDelay: Double?

    /**
     * Delay of hide. milesecond.
     */
    public var hideDelay: Double?

    public var transitionDuration: Double?
    /**
     * Whether mouse is allowed to enter the floating layer of tooltip
     */
    public var enterable: Bool?

    /**
     * Whether enable display transition when show/hide tooltip.
     * @default true
     * @since v6.0.0
     */
    public var displayTransition: Bool?

    public var backgroundColor: ColorString?
    public var borderColor: ColorString?
    public var borderRadius: Double?
    public var borderWidth: Double?
    public var shadowBlur: Double?
    public var shadowColor: String?
    public var shadowOffsetX: Double?
    public var shadowOffsetY: Double?

    /**
     * Padding between tooltip content and tooltip border.
     */
    public var padding: Any? // number | number[]

    /**
     * Available when renderMode is 'html'
     */
    public var extraCssText: String?

    // upstream: Pick<LabelOption, 'color' | 'fontStyle' | ...> & { decoration?: string }
    public var textStyle: Dictionary<Any>?                              // PORT-TODO: Pick<LabelOption, ...> & { decoration }
    public init() {}
}

public struct ComponentItemTooltipOption<T> {
    // ---- inherited from CommonTooltipOption<T> ----
    public var common: CommonTooltipOption<T>
    // Default content HTML.
    public var content: String?
    /**
     * Whether to encode HTML content according to `tooltip.renderMode`.
     */
    public var encodeHTMLContent: Bool?
    public var formatterParams: ComponentItemTooltipLabelFormatterParams?
}
public struct ComponentItemTooltipLabelFormatterParams {
    public var componentType: String
    public var name: String
    // properties key array like ['name']
    public var vars: [String]   // upstream: `$vars` ('$' prefix is reserved in Swift)
    // Other properties
    public var other: Dictionary<Any> = [:]                             // PORT-TODO: upstream `[key in string]: unknown`
}


/**
 * Tooltip option configured on each series
 */
public struct SeriesTooltipOption {
    // ---- inherited from CommonTooltipOption<CallbackDataParams> ----
    public var common: CommonTooltipOption<CallbackDataParams>
    public var trigger: Any? // 'item' | 'axis' | boolean | 'none'
}




public struct LabelFormatterParams {
    public var value: ScaleDataValue
    public var axisDimension: String
    public var axisIndex: Double
    public var seriesData: [CallbackDataParams]
}
/**
 * Common axis option. can be configured on each axis
 */
public struct CommonAxisPointerOption {
    public var show: Any? // boolean | 'auto'

    public var z: Double?
    public var zlevel: Double?

    public var triggerOn: String? // 'click' | 'mousemove' | 'none' | 'mousemove|click'

    public var type: String? // 'line' | 'shadow' | 'none'

    public var snap: Bool?

    public var triggerTooltip: Bool?

    public var triggerEmphasis: Bool?

    /**
     * current value. When using axisPointer.handle, value can be set to define the initial position.
     */
    public var value: ScaleDataValue?

    public var status: String? // 'show' | 'hide'

    // [group0, group1, ...] (See upstream comment for the mapper/group semantics.)

    public var label: AxisPointerLabelOption?
    public var animation: Any? // boolean | 'auto'
    public var animationDurationUpdate: Double?
    public var animationEasingUpdate: ZREasing?

    /**
     * Available when type is 'line'
     */
    public var lineStyle: LineStyleOption?
    /**
     * Available when type is 'shadow'
     */
    public var shadowStyle: AreaStyleOption?

    public var handle: AxisPointerHandleOption?

    public var seriesDataIndices: [AxisPointerSeriesDataIndex]?
    public init() {}

    // upstream: LabelOption & { precision?, margin?, formatter? }
    public struct AxisPointerLabelOption {
        public var label = LabelOption()
        public var precision: Any? // 'auto' | number
        public var margin: Double?
        /**
         * String template include variable {value} or callback function
         */
        public var formatter: Any? // string | ((params: LabelFormatterParams) => string)
        public init() {}
    }
    // upstream: { show?, icon?, size?, margin?, color?, throttle? } & ShadowOptionMixin
    public struct AxisPointerHandleOption {
        public var show: Bool?
        public var icon: String?
        /**
         * The size of the handle
         */
        public var size: Any? // number | number[]
        /**
         * Distance from handle center to axis.
         */
        public var margin: Double?
        public var color: ColorString?
        /**
         * Throttle for mobile performance
         */
        public var throttle: Double?
        // ---- inherited from ShadowOptionMixin ----
        public var shadow = ShadowOptionMixin()
        public init() {}
    }
    public struct AxisPointerSeriesDataIndex {
        public var seriesIndex: Double
        public var dataIndex: Double
        public var dataIndexInside: Double
    }
}

public struct ComponentOption {
    public var mainType: String?

    public var type: String?

    public var id: OptionId?
    public var name: OptionName?

    public var z: Double?
    public var zlevel: Double?

    public var coordinateSystem: String?
    public var coordinateSystemUsage: CoordinateSystemUsageOption?
    public var coord: CoordinateSystemDataCoord?

    // PORT: the raw dynamic option bag ([String: Any]) this typed ComponentOption was projected
    //   from. Upstream `ComponentOption` IS the dynamic option object (a plain JS object flowing by
    //   identity from `newOption[mainType]` through `mappingToExists` into
    //   `new ComponentModelClass(newCmptOption, ...)`); the Swift struct is a lossy typed subset, so
    //   the full bag is carried here to reconstruct the option passed to component-model
    //   instantiation/merge in Global._mergeOption. `nil` for typed-only ComponentOptions (e.g.
    //   internal option creators that do not originate from the dynamic tree).
    public var rawOption: [String: Any]?
    public init() {}
}

/**
 * - "data": Each data item is laid out based on a coord sys. See `COORD_SYS_USAGE_KIND_DATA`.
 * - "box": The overall bounding rect or anchor point is calculated based on a coord sys.
 *   See `COORD_SYS_USAGE_KIND_BOX`.
 * (See upstream comment for the default value semantics.)
 */
public enum CoordinateSystemUsageOption: String {
    case data
    case box
}

public enum BlurScope: String {
    case coordinateSystem
    case series
    case global
}

/**
 * can be array of data indices.
 * Or may be an dictionary if have different types of data like in graph.
 */
// upstream: DefaultEmphasisFocus | ArrayLike<number> | Dictionary<ArrayLike<number>>
public typealias InnerFocus = Any                                        // PORT-TODO: union

public struct DefaultStatesMixin {
    // FIXME
    public var emphasis: Any?
    public var select: Any?
    public var blur: Any?
    public init() {}
}

public enum DefaultEmphasisFocus: String {
    case none
    case `self`
    case series
}

public struct DefaultStatesMixinEmphasis {
    /**
     * self: Focus self and blur all others.
     * series: Focus series and blur all other series.
     */
    public var focus: DefaultEmphasisFocus?
    public init() {}
}

public struct StatesMixinBase {
    public var emphasis: Any?
    public var select: Any?
    public var blur: Any?
    public init() {}
}

public struct StatesOptionMixin<StateOption, StatesMixin> {              // PORT-TODO: TS intersection arms dropped
    /**
     * Emphasis states. (upstream intersects StateOption & StatesMixin['emphasis'] & { blurScope, disabled })
     */
    public var emphasis: StateOption?
    public var emphasisBlurScope: BlurScope?
    public var emphasisDisabled: Bool?
    /**
     * Select states. (upstream intersects StateOption & StatesMixin['select'] & { disabled })
     */
    public var select: StateOption?
    public var selectDisabled: Bool?
    /**
     * Blur states. (upstream intersects StateOption & StatesMixin['blur'])
     */
    public var blur: StateOption?
    public init() {}
}

public struct UniversalTransitionOption {
    public var enabled: Bool?
    /**
     * Animation delay of each divided element
     */
    public var delay: ((Double, Double) -> Double)?
    /**
     * How to divide the shape in combine and split animation.
     */
    public var divideShape: String? // 'clone' | 'split'
    /**
     * Series will have transition between if they have same seriesKey. (See upstream comment.)
     */
    public var seriesKey: Any? // string | string[]
    public init() {}
}

public struct SeriesOption<StateOption, StatesMixin> {                   // PORT-TODO: TS mixins flattened
    // ---- inherited from ComponentOption, AnimationOptionMixin, ColorPaletteOptionMixin, StatesOptionMixin ----
    public var component = ComponentOption()
    public var animationMixin = AnimationOptionMixin()
    public var colorPalette = ColorPaletteOptionMixin()
    public var states: StatesOptionMixin<StateOption, StatesMixin>?

    public var mainType: String? // 'series'

    public var silent: Bool?

    public var blendMode: String?

    /**
     * Cursor when mouse on the elements
     */
    public var cursor: String?

    /**
     * groupId of data. can be used for doing drilldown / up animation. (See upstream comment.)
     */
    public var dataGroupId: OptionId?
    // Needs to be override
    public var data: Any?

    public var colorBy: ColorBy?

    public var legendHoverLink: Bool?

    /**
     * Configurations about progressive rendering
     */
    public var progressive: Any? // number | false
    public var progressiveThreshold: Double?
    public var progressiveChunkMode: String? // 'mod'

    public var hoverLayerThreshold: Double?

    /**
     * When dataset is used, seriesLayoutBy specifies whether the column or the row is mapped.
     * @default 'column'
     */
    public var seriesLayoutBy: String? // 'column' | 'row'

    public var labelLine: LabelLineOption?

    /**
     * Overall label layout option in label layout stage.
     */
    public var labelLayout: Any? // LabelLayoutOption | LabelLayoutOptionCallback

    /**
     * Animation config for state transition.
     */
    public var stateAnimation: AnimationOption?

    /**
     * If enabled universal transition cross series. (See upstream comment for examples.)
     */
    public var universalTransition: Any? // boolean | UniversalTransitionOption

    /**
     * Map of selected data. key is name or index of data.
     */
    public var selectedMap: Any? // Dictionary<boolean> | 'all'
    public var selectedMode: Any? // 'single' | 'multiple' | 'series' | boolean
    public init() {}
}

public struct SeriesOnCartesianOptionMixin {
    public var xAxisIndex: Double?
    public var yAxisIndex: Double?

    public var xAxisId: OptionId?
    public var yAxisId: OptionId?
    public init() {}
}

public struct SeriesOnPolarOptionMixin {
    public var polarIndex: Double?
    public var polarId: OptionId?
    public init() {}
}

public struct SeriesOnSingleOptionMixin {
    public var singleAxisIndex: Double?
    public var singleAxisId: OptionId?
    public init() {}
}

public struct SeriesOnGeoOptionMixin {
    public var geoIndex: Double?
    public var geoId: OptionId?
    public init() {}
}

public struct SeriesOnRadarOptionMixin {
    public var radarIndex: Double?
    public var radarId: OptionId?
    public init() {}
}

public struct ComponentOnCalendarOptionMixin {
    public var calendarIndex: Double?
    public var calendarId: OptionId?
    public init() {}
}

public struct ComponentOnMatrixOptionMixin {
    public var matrixIndex: Double?
    public var matrixId: OptionId?
    public init() {}
}

public struct SeriesLargeOptionMixin {
    public var large: Bool?
    public var largeThreshold: Double?
    public init() {}
}
public struct SeriesStackOptionMixin {
    public var stack: String?
    public var stackStrategy: String? // 'samesign' | 'all' | 'positive' | 'negative'
    public var stackOrder: String? // 'seriesAsc' | 'seriesDesc'; // default: seriesAsc
    public init() {}
}

// upstream: (frame: ArrayLike<number>) => number
public typealias SamplingFunc = ([Double]) -> Double

public struct SeriesSamplingOptionMixin {
    public var sampling: Any? // 'none' | 'average' | 'min' | 'max' | 'minmax' | 'sum' | 'lttb' | SamplingFunc
    public init() {}
}

public struct SeriesEncodeOptionMixin {
    public var datasetIndex: Double?
    public var datasetId: Any? // string | number
    public var seriesLayoutBy: SeriesLayoutBy?
    public var sourceHeader: OptionSourceHeader?
    public var dimensions: [DimensionDefinitionLoose]?
    public var encode: OptionEncode?
    public init() {}
}

// upstream: SeriesModel<SeriesOption & SeriesEncodeOptionMixin>
public typealias SeriesEncodableModel = SeriesModel                      // PORT-TODO: generic option arg dropped


// TODO Move to aria component
public struct AriaLabelOption {
    public var enabled: Bool?
    public var description: String?
    public var general: General?
    public var series: Series?
    public var data: Data?
    public init() {}

    public struct General {
        public var withTitle: String?
        public var withoutTitle: String?
        public init() {}
    }
    public struct Series {
        public var maxCount: Double?
        public var single: Single?
        public var multiple: Multiple?
        public init() {}

        public struct Single {
            public var prefix: String?
            public var withName: String?
            public var withoutName: String?
            public init() {}
        }
        public struct Multiple {
            public var prefix: String?
            public var withName: String?
            public var withoutName: String?
            public var separator: Separator?
            public init() {}

            public struct Separator {
                public var middle: String?
                public var end: String?
                public init() {}
            }
        }
    }
    public struct Data {
        public var maxCount: Double?
        public var allData: String?
        public var partialData: String?
        public var withName: String?
        public var withoutName: String?
        public var separator: Separator?
        public var excludeDimensionId: [Double]?
        public init() {}

        public struct Separator {
            public var middle: String?
            public var end: String?
            public init() {}
        }
    }
}

// Extending is for compating ECharts 4
public struct AriaOption {
    // ---- inherited from AriaLabelOption ----
    public var ariaLabel = AriaLabelOption()
    public var mainType: String? // 'aria'

    public var enabled: Bool?
    public var label: AriaLabelOption?
    public var decal: Decal?
    public init() {}

    public struct Decal {
        public var show: Bool?
        public var decals: Any? // DecalObject | DecalObject[]
        public init() {}
    }
}

public struct AriaOptionMixin {
    public var aria: AriaOption?
    public init() {}
}


public struct RoamPayload {
    // ---- inherited from Payload ----
    public var type: String // `${string}${typeof ROAM_ACTION_TYPE_SUFFIX}`
    public var dx: Double
    public var dy: Double
    // This is a delta zoom, not an absolute zoom.
    public var zoom: Double
    public var originX: Double
    public var originY: Double
    // ---- remaining Payload fields ----
    public var escapeConnect: Bool?
    public var batch: [PayloadItem]?
    public var excludeSeriesId: Any?
    public var animation: PayloadAnimationPart?
    public var other: Dictionary<Any> = [:]
}

public let ROAM_ACTION_TYPE_SUFFIX = "Roam"

/**
 * @usage class Xxx implements RoamHostModel {...}
 */
public protocol RoamHostModel {
    // Can return a VIEW_COORD_SYS only if the it is owned by this series or component.
    // (See upstream comment.)
    var __ownRoamView: () -> View? { get }
}
// upstream: ComponentModel<ComponentOption & RoamOptionMixin> & RoamHostModel
public typealias RoamHostComponentOrSeries = ComponentModel & RoamHostModel  // PORT-TODO: generic option arg dropped

public protocol RoamHostView {
    /**
     * A performance shortcut - called by action handler to update the view directly
     * without any data/visual processing. (See upstream comment.)
     */
    func __updateOnOwnRoam(_ payload: RoamPayload, _ componentOrSeries: ComponentModel, _ api: ExtensionAPI)
}
// upstream: (ChartView | ComponentView) & RoamHostView
public typealias ChartComponentRoamHostView = RoamHostView               // PORT-TODO: (ChartView | ComponentView) & RoamHostView
