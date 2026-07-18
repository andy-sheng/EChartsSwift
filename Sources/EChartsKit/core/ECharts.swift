// Ported from echarts/src/core/echarts.ts — the `ECharts` driver. Keep in sync with upstream.
//
// ============================================================================
// WHAT THIS FILE IS
// ============================================================================
// A faithful port of the upstream `ECharts` instance/driver. It runs the full `updateMethods.update`
// pipeline (see §UPDATE) — preprocessors → restoreData → data/processor stages → coord create/update
// → visual stages → render — across ALL ported chart types (cartesian bar/line/scatter/candlestick/
// boxplot/pictorialBar, pie/funnel/gauge/radar, graph/tree/treemap/sankey/sunburst, heatmap/lines/
// themeRiver/parallel/map/custom, ...), emitting a ZRenderKit `Group` a host painter draws.
//
// Reproduced faithfully: setOption model reuse + incremental merge; `prepareView` view reuse
// (mark-and-sweep) enabling cross-setOption `data.diff` tween transitions; the update matrix
// (`updateView`/`updateVisual`/`updateLayout`/`updateTransform`) + `dispatchAction` routing;
// actions/events substrate; the emphasis/blur/select state engine + `clearStates`/`updateStates`/
// `updateZ`; coord systems, layout, visual (style/visualMap/aria/decal) and processor stages.
//
// Deliberate deviations from upstream (documented at each site):
//   - The `Scheduler` task/pipeline graph. Upstream runs each stage as a `Task` (`performXxxTasks` /
//     `renderTask.perform`); here the stages are invoked DIRECTLY. Its progressive/stream/incremental
//     machinery (large-mode framing) is not reproduced — `renderTask.perform` runs synchronously.
//   - `prepare()` + `restorePipelines`/`prepareStageTasks`/`plan` (Scheduler pipeline building).
//   - `lazyUpdate` / media-query re-resolve on resize; `universalTransition` (cross-series morphing).
//   - The DOM/zrender `init` facade + painter. EChartsKit depends only on ZRenderKit (NOT
//     NativePainter), so this driver owns a `Storage` + a root `Group` and exposes them; a host
//     with a painter (NativePainter's `CALayerPainter`) draws `getRoot()`.
//
// ============================================================================
// REGISTRATION (replaces the per-chart `install(registers)` boilerplate)
// ============================================================================
// Upstream, each feature ships an `install(registers)` (e.g. `component/grid/installSimple.ts`,
// `chart/bar/install.ts`) that calls `registerComponentModel` / `registerComponentView` /
// `registerChartView` / `registerSeriesModel` / `registerCoordinateSystem` / `registerLayout` /
// `registerVisual` / `registerProcessor`. Those registrars are Phase-6b wiring and are NOT bridged
// to `GlobalModel`'s instantiation path yet. So `installOnce()` below performs the equivalent
// registration explicitly:
//   - MODELS  → `ComponentModel.registerClass(...)` (the ONLY instantiation path `GlobalModel`
//               currently uses; see `Global.swift:537`).
//   - COORD   → `CoordinateSystemManager.register("cartesian2d", GridCoordinateSystemCreator())`.
//   - VIEWS   → explicit factory maps (`_componentViewFactories` / `_chartViewFactories`). Upstream
//               stores the view CLASS and does `new Clazz()`; Swift can not `new` a bare
//               `ClassManageable` metatype (the protocol has no `init` requirement), so the driver
//               holds `() -> View` factories instead (documented deviation).
//   - STAGES  → the visual (`visual/style.swift`) + layout (`layout/barGrid.swift`) + processor
//               (axis-statistics) handlers are captured/referenced directly (see the stage methods).
//
// NOTE on axis models: upstream `axisModelCreator` GENERATES a distinct `AxisModel` subclass per
// axis type at runtime and registers it. Swift can not synthesize classes at runtime AND the
// generated-factory registrar is not bridged to `GlobalModel` instantiation, so this file registers
// two concrete stand-in subclasses (`EChartsXAxisModel` / `EChartsYAxisModel`) that add the
// `AxisModelExtendedInCreator` surface (`getOrdinalMeta` etc.) a category axis needs. This mirrors
// exactly the working `CartesianCoordTests` doubles; it is the documented stand-in for
// `axisModelCreator(registers, 'x'/'y', CartesianAxisModel, ...)` until the registrar↔instantiation
// bridge lands (Phase 6b).

import Foundation
import ZRenderKit

// ============================================================================
// Coordinate-system creator for cartesian2d (wraps `Grid.create` / `Grid.dimensions`).
// Upstream registers the `Grid` CLASS itself as the creator; the ported registry wants a
// `CoordinateSystemCreator` value, so this thin struct forwards to the static `Grid.create`.
// ============================================================================
struct GridCoordinateSystemCreator: CoordinateSystemCreator {
    func create(_ ecModel: GlobalModel, _ api: ExtensionAPI) -> [CoordinateSystemMaster] {
        // Grid.create returns [Grid]; Grid conforms to CoordinateSystemMaster.
        return Grid.create(ecModel, api).map { $0 as CoordinateSystemMaster }
    }
    var dimensions: [DimensionName]? { Grid.dimensions }        // static dimensions = cartesian2DDimensions
    func getDimensionsInfo() -> [DimensionDefinitionLoose]? { nil } // Grid has no dimensionsInfo hook.
}

// ============================================================================
// Coordinate-system creator for radar (wraps `Radar.create` / `Radar.dimensions`). Radar is the FIRST
// non-cartesian coordinate system wired here; the shape mirrors GridCoordinateSystemCreator exactly.
// Upstream registers the `Radar` CLASS itself (`registerCoordinateSystem('radar', Radar)`); the ported
// registry wants a `CoordinateSystemCreator` value, so this thin struct forwards to the static
// `Radar.create`. Radar's static `dimensions` is `[]` (radar dimensions are data-derived per-indicator).
// ============================================================================
struct RadarCoordinateSystemCreator: CoordinateSystemCreator {
    func create(_ ecModel: GlobalModel, _ api: ExtensionAPI) -> [CoordinateSystemMaster] {
        // Radar.create returns [Radar]; Radar conforms to CoordinateSystemMaster.
        return Radar.create(ecModel, api).map { $0 as CoordinateSystemMaster }
    }
    var dimensions: [DimensionName]? { Radar.dimensions }        // static dimensions = [] (data-derived).
    func getDimensionsInfo() -> [DimensionDefinitionLoose]? { nil } // Radar has no dimensionsInfo hook.
}

// ============================================================================
// Coordinate-system creator for polar (wraps `polarCreator.create` / `polarCreator.dimensions`). The
// polar coord system is the SECOND non-cartesian coordinate system wired here (after radar); the shape
// mirrors GridCoordinateSystemCreator / RadarCoordinateSystemCreator exactly. Upstream registers the
// `Polar` CLASS itself (`registerCoordinateSystem('polar', Polar)`); the ported registry wants a
// `CoordinateSystemCreator` value, so this thin struct forwards to the caseless-namespace `polarCreator`.
// polarCreator.dimensions is the static `polarDimensions` (["radius", "angle"]).
// ============================================================================
struct PolarCoordinateSystemCreator: CoordinateSystemCreator {
    func create(_ ecModel: GlobalModel, _ api: ExtensionAPI) -> [CoordinateSystemMaster] {
        // polarCreator.create returns [Polar]; Polar conforms to CoordinateSystemMaster.
        return polarCreator.create(ecModel, api).map { $0 as CoordinateSystemMaster }
    }
    var dimensions: [DimensionName]? { polarCreator.dimensions }  // static dimensions = polarDimensions.
    func getDimensionsInfo() -> [DimensionDefinitionLoose]? { nil } // Polar has no dimensionsInfo hook.
}

// ============================================================================
// single coord system is the FOURTH coordinate system wired here (after cartesian2d / radar / polar);
// the shape mirrors PolarCoordinateSystemCreator exactly. Upstream registers the caseless-namespace
// `singleCreator` (`registerCoordinateSystem('single', singleCreator)`); the ported registry wants a
// `CoordinateSystemCreator` value, so this thin struct forwards to it.
// singleCreator.dimensions is the static `singleDimensions` (["single"]).
// ============================================================================
struct SingleCoordinateSystemCreator: CoordinateSystemCreator {
    func create(_ ecModel: GlobalModel, _ api: ExtensionAPI) -> [CoordinateSystemMaster] {
        // singleCreator.create returns [Single]; Single conforms to CoordinateSystemMaster.
        return singleCreator.create(ecModel, api).map { $0 as CoordinateSystemMaster }
    }
    var dimensions: [DimensionName]? { singleCreator.dimensions }  // static dimensions = singleDimensions.
    func getDimensionsInfo() -> [DimensionDefinitionLoose]? { nil } // Single has no dimensionsInfo hook.
}

// ============================================================================
// parallel coord system is the FIFTH coordinate system wired here (after cartesian2d / radar / polar /
// single); the shape mirrors SingleCoordinateSystemCreator exactly. Upstream registers the caseless
// `parallelCoordSysCreator` (`registerCoordinateSystem('parallel', parallelCoordSysCreator)`); the ported
// registry wants a `CoordinateSystemCreator` value, so this thin struct forwards to it.
// parallelCoordSysCreator has NO static `dimensions` (parallel has no fixed dims), so `dimensions` is nil.
// ============================================================================
struct ParallelCoordinateSystemCreator: CoordinateSystemCreator {
    func create(_ ecModel: GlobalModel, _ api: ExtensionAPI) -> [CoordinateSystemMaster] {
        // parallelCoordSysCreator.create already returns [CoordinateSystemMaster].
        return parallelCoordSysCreator.create(ecModel, api)
    }
    var dimensions: [DimensionName]? { nil }                       // parallel has no static dimensions.
    func getDimensionsInfo() -> [DimensionDefinitionLoose]? { nil } // Parallel has no dimensionsInfo hook.
}

// ============================================================================
// calendar coord system is the SIXTH coordinate system wired here. Upstream registers the `Calendar`
// class itself as the creator (`registerCoordinateSystem('calendar', Calendar)`); the ported registry
// wants a `CoordinateSystemCreator` value, so this thin struct forwards to `Calendar.create` /
// `Calendar.dimensions` (["time","value"]), mirroring GridCoordinateSystemCreator.
// ============================================================================
struct CalendarCoordinateSystemCreator: CoordinateSystemCreator {
    func create(_ ecModel: GlobalModel, _ api: ExtensionAPI) -> [CoordinateSystemMaster] {
        return EChartsKit.Calendar.create(ecModel, api).map { $0 as CoordinateSystemMaster }
    }
    var dimensions: [DimensionName]? { EChartsKit.Calendar.dimensions }        // static dimensions = ["time","value"].
    func getDimensionsInfo() -> [DimensionDefinitionLoose]? { nil } // Calendar has no dimensionsInfo hook.
}

// ============================================================================
// matrix coord system is the EIGHTH coordinate system wired here. Upstream registers the `Matrix`
// class itself as the creator (`registerCoordinateSystem('matrix', Matrix)`); the ported registry
// wants a `CoordinateSystemCreator` value, so this thin struct forwards to `Matrix.create` /
// `Matrix.dimensions` (["x","y","value"]) / `Matrix.getDimensionsInfo`, mirroring
// CalendarCoordinateSystemCreator.
// ============================================================================
struct MatrixCoordinateSystemCreator: CoordinateSystemCreator {
    func create(_ ecModel: GlobalModel, _ api: ExtensionAPI) -> [CoordinateSystemMaster] {
        return Matrix.create(ecModel, api).map { $0 as CoordinateSystemMaster }
    }
    var dimensions: [DimensionName]? { Matrix.dimensions }                     // static dimensions = ["x","y","value"].
    func getDimensionsInfo() -> [DimensionDefinitionLoose]? { Matrix.getDimensionsInfo() }
}

// ============================================================================
// Stand-in axis models (see the axisModelCreator NOTE in the file header).
// These are the documented equivalent of the classes `axisModelCreator` would generate for
// `xAxis.<type>` / `yAxis.<type>`. They read `axis.data` for category ordinal metadata.
// ============================================================================

/// Resolve the axis sub-type, then merge the per-type `axisDefault` (show:true + axisLine/axisTick/
/// axisLabel/splitLine sub-defaults) UNDER the model's own option, so `axisModel.get("show")` / the
/// AxisBuilder's sub-option reads resolve. This stands in for the deferred
/// `AxisModel.mergeDefaultAndTheme` (the real axisModelCreator path never runs for these models).
///
/// The `option.type = getAxisType(option)` WRITE-BACK is load-bearing, not bookkeeping: upstream an
/// axis carrying `data` but no explicit `type` IS a category axis, and that resolved type is what
/// `axisHelper.determineAxisType` (→ the scale) and `optionUpdated` (→ OrdinalMeta) read back off the
/// option. Without it every type-less axis degraded to `value`, so any option written the way the
/// official examples write them (`xAxis: { data: [...] }`) drew an empty value axis.
/// Overwrite=false → user option wins; nested dicts deep-merge (util.merge).
private func mergeAxisDefaults(_ model: CartesianAxisModel) {
    guard var opt = model.option as? [String: Any] else { return }
    let axisType = getAxisType(opt)   // option.type || (option.data ? 'category' : 'value')
    opt["type"] = axisType
    if let def = axisDefault.option[axisType] as? [String: Any] {
        _ = util.merge(&opt, def, false)
    }
    model.option = opt
}

/// `xAxis` model. `static type = 'xAxis'` so `ComponentModel.registerClass` keys it correctly.
final class EChartsXAxisModel: CartesianAxisModel, AxisModelExtendedInCreator {
    override class var type: ComponentFullType { return "xAxis" }
    private var __ordinalMeta: OrdinalMeta?
    override func optionUpdated(_ n: ModelOption?, _ isInit: Bool) {
        super.optionUpdated(n, isInit)
        mergeAxisDefaults(self)
        if (self.option as? [String: Any])?["type"] as? String == "category" {
            __ordinalMeta = OrdinalMeta.createByAxisModel(self)
        }
    }
    override func getCategories(_ rawData: Bool?) -> [OrdinalRawValue]? {
        return (self.option as? [String: Any])?["data"] as? [OrdinalRawValue]
    }
    // AxisModelExtendedInCreator: category axes always have their meta built in optionUpdated;
    //   value/time/log axes never call getOrdinalMeta (createScaleByModel only reads it for 'category').
    func getOrdinalMeta() -> OrdinalMeta { return __ordinalMeta ?? OrdinalMeta.createByAxisModel(self) }
    func updateAxisBreaks(_ payload: BaseAxisBreakPayload) -> AxisBreakUpdateResult {
        return AxisBreakUpdateResult(breaks: [])   // axis-break support is out of the bar scope.
    }
}

/// `yAxis` model (value axis in a vertical bar chart; symmetric to `EChartsXAxisModel`).
final class EChartsYAxisModel: CartesianAxisModel, AxisModelExtendedInCreator {
    override class var type: ComponentFullType { return "yAxis" }
    private var __ordinalMeta: OrdinalMeta?
    override func optionUpdated(_ n: ModelOption?, _ isInit: Bool) {
        super.optionUpdated(n, isInit)
        mergeAxisDefaults(self)
        if (self.option as? [String: Any])?["type"] as? String == "category" {
            __ordinalMeta = OrdinalMeta.createByAxisModel(self)
        }
    }
    override func getCategories(_ rawData: Bool?) -> [OrdinalRawValue]? {
        return (self.option as? [String: Any])?["data"] as? [OrdinalRawValue]
    }
    func getOrdinalMeta() -> OrdinalMeta { return __ordinalMeta ?? OrdinalMeta.createByAxisModel(self) }
    func updateAxisBreaks(_ payload: BaseAxisBreakPayload) -> AxisBreakUpdateResult {
        return AxisBreakUpdateResult(breaks: [])
    }
}

// ============================================================================
// Capturing registrar for the axis-statistics PROCESSOR.
// The bar cross-series layout (`layout/barGrid.swift`) reads <axis, series> statistics that are
// computed by a processor registered via `registerBarGridAxisHandlers(registers)`. The base
// `EChartsExtensionInstallRegisters.registerProcessor` is a no-op stub, so this subclass captures
// the registered `overallReset` closures; the driver runs them in the data-processor stage.
// (Calling `registerBarGridAxisHandlers` ALSO populates the module-global `clientsForLookup` in
// axisStatistics.swift — that side effect is what makes the statistics collect the bar client.)
// ============================================================================
final class EChartsInstallRegisters: EChartsExtensionInstallRegisters {
    var capturedProcessors: [(GlobalModel) -> Void] = []
    override func registerProcessor(_ priority: Double, _ processor: AxisStatProcessorRegistration) {
        capturedProcessors.append(processor.overallReset)
    }
}

// ============================================================================
// dispatchAction option. Upstream `dispatchAction(payload, opt?)` where
//   `opt?: boolean | { silent?: boolean, flush?: boolean | undefined }`.
//   Swift has no union type; the object form is modeled as this struct, and the bare-boolean
//   convenience (`dispatchAction(payload, DispatchActionOpt(true))`) mirrors upstream's
//   `if (!isObject(opt)) opt = {silent: !!opt}`.
// ============================================================================
public struct DispatchActionOpt {
    public var silent: Bool
    public var flush: Bool?
    public init(silent: Bool = false, flush: Bool? = nil) {
        self.silent = silent
        self.flush = flush
    }
    /// Convenience for the upstream bare-boolean form (`dispatchAction(payload, true)` == silent).
    public init(_ silent: Bool) {
        self.silent = silent
        self.flush = nil
    }
}

// Phase-30 note: the former `isHighDownPayloadSlim`/`isSelectChangePayloadSlim` stand-ins have been
// removed — `doDispatchAction` now uses the real `isHighDownPayload`/`isSelectChangePayload` from
// util/statesPayload.swift (which also drive the ported `updateDirectly` light update).

// ============================================================================
// The CHART EVENT BUS — ported from echarts.ts:328-353 + `class ECharts extends Eventful`.
//
// upstream:
//   type EventMethodName = 'on' | 'off';
//   function createRegisterEventWithLowercaseECharts(method) { ... }
//   function createRegisterEventWithLowercaseMessageCenter(method) { ... }
//   function toLowercaseNameAndCallEventful(host, method, args) {
//       // `args[0]` is event name. Event name is all lowercase.
//       args[0] = args[0] && args[0].toLowerCase();
//       return Eventful.prototype[method].apply(host, args);
//   }
//   class MessageCenter extends Eventful {}
//   messageCenterProto.on  = createRegisterEventWithLowercaseMessageCenter('on');
//   messageCenterProto.off = createRegisterEventWithLowercaseMessageCenter('off');
//
// The `on`/`off` prototype REWRITE is upstream's way of lowercasing the event name on the way in
// (registered event types are always lowercase — see `registerAction`'s `createEventType`). Here that
// is simply what `MessageCenter.on/off` and `ECharts.on/off` do inline.
//
// PORT-NOTE (CONVENTIONS §2): ZRenderKit's `Eventful` is a `final class` (upstream applies it as a
//   MIXIN to Element via `applyMixin`), so `extends Eventful` becomes COMPOSITION + forwarding — the
//   same shape `Element`/`Handler`/`ZRender` already use.
// ============================================================================

// upstream: `class MessageCenter extends Eventful {}` — the INTERNAL bus. Actions publish their event
//   here (`doDispatchAction`: `messageCenter.trigger(eventObj.type, eventObj)`), and `_initEvents`
//   re-publishes every registered public event type onto the USER-facing `ECharts` bus. The indirection
//   is what `connect` (cross-chart event mirroring) hooks into — see `connectionEventRevertMap`.
final class MessageCenter {

    private let _eventful = Eventful()

    // `args[0]` is event name. Event name is all lowercase.
    private static func toLowercaseName(_ event: String) -> String { return event.lowercased() }

    @discardableResult
    func on(_ event: String, _ handler: @escaping EventCallback, _ context: AnyObject? = nil) -> MessageCenter {
        _eventful.on(MessageCenter.toLowercaseName(event), handler, context)
        return self
    }

    @discardableResult
    func off(_ eventType: String? = nil, _ handler: EventCallback? = nil) -> MessageCenter {
        _eventful.off(eventType.map(MessageCenter.toLowercaseName), handler)
        return self
    }

    @discardableResult
    func trigger(_ eventType: String, _ args: Any?...) -> MessageCenter {
        // Forward by arg count (Swift cannot splat a variadic into another variadic). The message
        //   center only ever carries ONE packed event object, so 0/1 covers every upstream path.
        if args.isEmpty {
            _eventful.trigger(eventType)
        }
        else {
            _eventful.trigger(eventType, args[0])
        }
        return self
    }
}

// upstream echarts.ts:2864 — const MOUSE_EVENT_NAMES: ZRElementEventName[] = [...]
let MOUSE_EVENT_NAMES: [String] = [
    "click", "dblclick", "mouseover", "mouseout", "mousemove",
    "mousedown", "mouseup", "globalout", "contextmenu"
]

// ============================================================================
// The ECharts driver.
// ============================================================================
public final class ECharts: EChartsType {

    // ---- owned state (mirrors the private fields on upstream `ECharts`) ----
    private var _model: GlobalModel?                             // upstream: this._model
    private let _coordSysMgr = CoordinateSystemManager()         // upstream: this._coordSysMgr
    private var _api: ExtensionAPI!                              // upstream: this._api
    private var _width: Double
    private var _height: Double
    /// The ARIA label string generated during `update()` (upstream `visual/aria.ts` writes it to the
    /// container DOM's `aria-label`; captured here since there is no DOM). Exposed via `getAriaLabel()`.
    private var _ariaLabel: String?

    // ---- theme / locale (mirrors upstream `ECharts._theme` resolution in `echarts.init`) ----
    /// The theme passed to `init` — a `String` (a name registered via `registerTheme`) or a
    /// `[String: Any]` theme object. Resolved to a dict in `setOption` and handed to
    /// `GlobalModel.init`, which merges it into the option via `mergeTheme`. Upstream `echarts.init`.
    private let _userTheme: Any?
    /// The locale passed to `init` — a `String` lang name (registered via `registerLocale`) or a
    /// `[String: Any]` locale object. Defaults to `locale.SYSTEM_LANG` (EN). Upstream `echarts.init`.
    private let _userLocale: Any?

    /// The flattened, z-sorted display list (upstream: `zr.storage`). A host painter consumes this.
    public let storage = Storage()
    /// The ec root `Group` — all view groups are added here (upstream: elements added to `zr`).
    public let root = Group()

    // View registries. Upstream: `_componentsViews`/`_componentsMap`/`_chartsViews`/`_chartsMap`.
    // (`_componentsViews` internal — reachable from @testable tests to assert a rendered view's state.)
    var _componentsViews: [ComponentView] = []
    private var _chartsViews: [ChartView] = []
    // viewId → view (upstream keyed by `'_ec_' + model.id + '_' + model.type`).
    private var _componentsMap: [String: ComponentView] = [:]
    private var _chartsMap: [String: ChartView] = [:]
    // model-identity → view (for `api.getViewOfComponentModel`/`getViewOfSeriesModel`).
    private var _componentViewByModel: [ObjectIdentifier: ComponentView] = [:]
    private var _chartViewByModel: [ObjectIdentifier: ChartView] = [:]

    // The full-canvas background rect (upstream zr.setBackgroundColor). Removed/reused across renders
    // so it never accumulates now that render() no longer wipes root (L5 view reuse).
    private var _bgRect: Rect?

    // The Scheduler task/pipeline graph (upstream `this._scheduler`). Built lazily on the first
    //   setOption (after installOnce() has populated the registries); `restorePipelines` +
    //   `prepareStageTasks` run each setOption to (re)build the per-series pipelines. Sub-project C1
    //   routes update()'s perform-stages through it; C2 wires progressive render via prepareView.
    private var _scheduler: Scheduler!

    // Test-only accessors (assert reuse identity across setOption; assert no view duplication).
    var testModel: GlobalModel? { _model }
    var testChartViews: [ChartView] { _chartsViews }
    var testComponentViews: [ComponentView] { _componentsViews }
    // Sub-project C: assert the Scheduler pipelines are built on setOption (one per series).
    var testScheduler: Scheduler? { _scheduler }

    // ---- action-dispatch state (mirrors upstream `ECharts` action fields) ----
    /// Actions dispatched WHILE a render/update cycle is in progress are queued here and drained
    /// after it finishes (upstream: `private _pendingActions: Payload[] = []`).
    private var _pendingActions: [Payload] = []
    /// Re-entrancy guard: true while inside the update cycle (`doDispatchAction`). Upstream stores this
    /// under the symbol-ish key `IN_EC_CYCLE_KEY` (`'__flagInMainProcess'`).
    private var _inEcCycle = false
    /// Instance lifecycle flag (upstream: `private _disposed: boolean`). Set by `dispose()`; guards the
    /// public API entry points (upstream logs `disposedWarning` and early-returns when set).
    private var _disposed = false

    // ---- the chart event bus (upstream: `class ECharts extends Eventful<ECEventDefinition>`) ----
    /// upstream: `protected _$eventProcessor: never` — really an `ECEventProcessor`, whose `eventInfo`
    /// is written before each `trigger` so the query filter (`chart.on('click', {seriesIndex: 1}, …)`)
    /// can match the event against the source model/view.
    private let _$eventProcessor = ECEventProcessor()
    /// upstream: `super(new ECEventProcessor())` — the Eventful `ECharts` IS. Composed, not inherited
    /// (`Eventful` is final here; CONVENTIONS §2 — same shape as `Element`/`Handler`/`ZRender`).
    /// `lazy` only because it reads a sibling stored property (Swift forbids that in phase-1 init).
    private lazy var _eventful: Eventful = Eventful(self._$eventProcessor.asEventProcessor())
    /// upstream: `private _messageCenter: MessageCenter`.
    private let _messageCenter = MessageCenter()

    // upstream: echarts.init(dom, theme?, opts?) — `theme` is a registered name or a theme object,
    //   `opts.locale` a registered lang name or a locale object. Both are optional; nil theme merges
    //   nothing, nil locale resolves to `locale.SYSTEM_LANG` (EN).
    public init(width: Double, height: Double, theme: Any? = nil, locale: Any? = nil) {
        self._width = width
        self._height = height
        self._userTheme = theme
        self._userLocale = locale
        ECharts.installOnce()
        // `_api` needs `self`; all stored properties are initialized above, so it is safe now.
        self._api = EChartsExtensionAPI(ec: self)

        // Init mouse events. (upstream: `this._initEvents()` in the constructor — its zr half needs a
        //   live zrender, which this driver does not own; see `_initEvents` / `_initZrEvents`.)
        self._initEvents()
    }

    // ------------------------------------------------------------------------
    // Theme registry. Upstream echarts.ts keeps a module-level `themeStorage` map and
    //   `registerTheme(name, theme)` writes to it; `init(dom, theme)` looks a string theme up there.
    //   The built-in `dark` theme is registered in `installOnce()`.
    // ------------------------------------------------------------------------
    private static var _themeStorage: [String: [String: Any]] = [:]

    // upstream: export function registerTheme(name: string, theme: ThemeOption)
    public static func registerTheme(_ name: String, _ theme: [String: Any]) {
        _themeStorage[name] = theme
    }

    // upstream (echarts.init): theme = isString(theme) ? themeStorage[theme] : theme
    private func resolveTheme() -> [String: Any] {
        if let name = _userTheme as? String {
            return ECharts._themeStorage[name] ?? [:]
        }
        return (_userTheme as? [String: Any]) ?? [:]
    }

    // upstream (echarts.init): createLocaleObject(opts.locale || SYSTEM_LANG)
    private func resolveLocale() -> [String: Any] {
        let arg: Any = _userLocale ?? EChartsKit.locale.SYSTEM_LANG
        return EChartsKit.locale.createLocaleObject(arg)
    }

    // ------------------------------------------------------------------------
    // Public map registration facade. Upstream echarts.ts re-exports
    //   `registerMap = mapDataStorage.registerMap` (the geo source manager). A GeoJSON must be
    //   registered under a name BEFORE any `geo: { map: <name> }` option is set. Forwards to
    //   `geoSourceManager.registerMap` (the reachable entry point).
    // ------------------------------------------------------------------------
    public static func registerMap(
        _ mapName: String,
        _ rawDef: Any?,
        _ rawSpecialAreas: GeoSpecialAreas? = nil
    ) {
        geoSourceManager.registerMap(mapName, rawDef, rawSpecialAreas)
    }

    // upstream: echarts.getMap = mapDataStorage.getMapForUser
    public static func getMap(_ mapName: String) -> GeoMapForUser? {
        return geoSourceManager.getMapForUser(mapName)
    }

    // ------------------------------------------------------------------------
    // Registration (idempotent). Replaces the deferred `install(registers)` boilerplate.
    // ------------------------------------------------------------------------
    private static var _installed = false
    private static let _registers = EChartsInstallRegisters()
    // The bar cross-series layout handler (created once; run each layout stage).
    private static let _barLayoutHandler: StageHandler = createCrossSeriesLayoutHandler(SERIES_TYPE_BAR)
    // The bar PER-ITEM layout handler (upstream `registerLayout(PROGRESSIVE_LAYOUT, ...)`). Despite the
    //   name, this is the layout that computes each bar's x/y/width/height and calls `data.setItemLayout`
    //   (barGrid.swift `createProgressiveLayout`'s progress executor) — it runs for EVERY bar series, not
    //   only large/progressive ones. `BarView.getLayoutCartesian2D` reads that item layout back, so
    //   without running this handler no bar has a shape and `BarView` emits zero Rects.
    private static let _barProgressiveLayoutHandler: StageHandler = createProgressiveLayout(SERIES_TYPE_BAR)
    // The pictorialBar cross-series + per-item layout handlers (upstream chart/bar/installPictorialBar.ts
    //   `registerLayout(VISUAL.LAYOUT, createCrossSeriesLayoutHandler(pictorialBar))` +
    //   `registerLayout(PROGRESSIVE_LAYOUT, createProgressiveLayout(pictorialBar))`). Same role as the two
    //   bar handlers above, but gated on the 'pictorialBar' series type — they set bandWidth/offset/size
    //   and then each item's rect x/y/width/height, which PictorialBarView reads via data.getItemLayout.
    private static let _pictorialBarLayoutHandler: StageHandler = createCrossSeriesLayoutHandler(SERIES_TYPE_PICTORIAL_BAR)
    private static let _pictorialBarProgressiveLayoutHandler: StageHandler = createProgressiveLayout(SERIES_TYPE_PICTORIAL_BAR)
    // The dataSample down-sampling processors (upstream bar `install.ts` + line `install.ts` each
    //   `registerProcessor(PRIORITY.PROCESSOR.STATISTIC, dataSample(seriesType))`). One per series type
    //   that supports sampling; created once and run per matching series in the data-processor stage.
    static let _dataSamplers: [StageHandler] = [
        dataSample(SERIES_TYPE_BAR),
        dataSample(SERIES_TYPE_LINE)
    ]
    // The negativeDataFilter processors (upstream pie `install.ts` `registerProcessor(negativeDataFilter('pie'))`).
    static let _negativeDataFilters: [StageHandler] = [
        negativeDataFilter(SERIES_TYPE_PIE)
    ]
    // The DATA-ITEM legend filter processors (upstream `registerProcessor(dataFilter(SERIES_TYPE))` in
    //   chart/{pie,funnel,radar,themeRiver,chord}/install.ts). Each drops the data items whose NAME is
    //   unselected in a legend — legend show/hide for charts whose legend entries are data-item names
    //   (pie slices / radar polygons / funnel items / streams), not the series name. Run per matching
    //   series in the data-processor stage (like negativeDataFilter), BEFORE the layout/visual/view stages.
    static let _dataFilters: [StageHandler] = [
        legendDataFilter(SERIES_TYPE_PIE),
        legendDataFilter(SERIES_TYPE_FUNNEL),
        legendDataFilter(SERIES_TYPE_RADAR),
        legendDataFilter(SERIES_TYPE_THEME_RIVER),
        legendDataFilter(SERIES_TYPE_CHORD)
    ]

    // ========================================================================
    // Sub-project C — Scheduler handler assembly.
    // Wraps every processor/visual handler that `update()` currently hand-calls into a
    //   `StageHandlerInternal` the Scheduler can run through its task/pipeline graph.
    //
    // C1 TEMPORARY ORDERING: the returned array order == the current `update()` hand-call SOURCE order,
    //   NOT upstream `PRIORITY.PROCESSOR.*`. The ported `_performStageTasks` iterates ARRAY order (it
    //   does not sort by `__prio`), so routing through the Scheduler reproduces today's output exactly.
    //   A later reorder task realigns `__prio` to the real upstream priorities (see the priority table in
    //   docs/superpowers/specs/2026-07-10-c-scheduler-wiring-design.md) and re-sorts the array, gated
    //   separately against the web oracle. Isolating "does the Scheduler machinery reproduce the
    //   hand-calls?" from "does upstream order differ?" keeps each landing debuggable.
    // ========================================================================

    private static func _mkOverallHandler(_ prio: Double,
                                          _ reset: @escaping StageHandlerOverallReset) -> StageHandlerInternal {
        var h = StageHandler()
        h.overallReset = reset
        return StageHandlerInternal(uid: component.getUID("stageHandler"), visualType: nil,
                                    __prio: prio, __raw: h, isVisual: nil, isLayout: nil, handler: h)
    }

    private static func _mkHandler(_ prio: Double, _ h: StageHandler) -> StageHandlerInternal {
        return StageHandlerInternal(uid: component.getUID("stageHandler"), visualType: nil,
                                    __prio: prio, __raw: h, isVisual: nil, isLayout: nil, handler: h)
    }

    /// The data-processor StageHandlers the Scheduler runs in `performDataProcessorTasks`, assembled in
    /// the current `update()` hand-call order (see the block header). Mirrors update() step (3)/(4).
    static func buildDataProcessorHandlers() -> [StageHandlerInternal] {
        var list: [StageHandlerInternal] = []
        var p = 0.0
        func nextPrio() -> Double { p += 100; return p }

        // 1. dataZoom (FILTER). StageHandler with getTargetSeries (the AxisProxy-creation side-effect,
        //    which now runs at prepareStageTasks/setOption time — safe: AxisProxy reads only models) +
        //    overallReset (window calc + filter, at performDataProcessorTasks/update time).
        list.append(_mkHandler(nextPrio(), dataZoomProcessor))
        // 2. legendFilter — series show/hide (SERIES_FILTER 800). Global overall. MUST run BEFORE
        //    dataStack: upstream orders SERIES_FILTER (800) < DATASTACK (900), and dataStack.ts itself
        //    notes it "Should be executed after series is filtered" — the stack series list changes with
        //    legend selection. If dataStack ran first it would stack EVERY series (incl. a series about
        //    to be legend-hidden), and legendFilter merely dropping it from the render set afterwards
        //    leaves the survivors with a stale stackResult (still stacked over the hidden one) → the
        //    y-axis never rescales and the chart "doesn't re-layout" on a legend click. (Only legendFilter
        //    is pulled up to its upstream slot here; the remaining handlers keep their C1 order — the full
        //    __prio realignment is the separate gated reorder, see the block header + scheduler design doc.)
        list.append(_mkOverallHandler(nextPrio(), { ecModel, _, _ in legendFilter(ecModel) }))
        // 3. dataStack (DATASTACK). Global overall.
        list.append(_mkOverallHandler(nextPrio(), { ecModel, _, _ in dataStack(ecModel) }))
        // 4. axis-statistics captured processors (AXIS_STATISTICS). Only the overallReset was captured by
        //    EChartsInstallRegisters.registerProcessor, so wrap each as a global overall (no seriesType).
        for cp in ECharts._registers.capturedProcessors {
            list.append(_mkOverallHandler(nextPrio(), { ecModel, _, _ in cp(ecModel) }))
        }
        // 5. negativeDataFilter (DEFAULT, per-series reset+seriesType).
        for h in ECharts._negativeDataFilters { list.append(_mkHandler(nextPrio(), h)) }
        // 6. dataFilter — data-item legend show/hide (DEFAULT, per-series).
        for h in ECharts._dataFilters { list.append(_mkHandler(nextPrio(), h)) }
        // 7. dataSample down-sampling (STATISTIC, per-series).
        for h in ECharts._dataSamplers { list.append(_mkHandler(nextPrio(), h)) }
        // 8. graph categoryFilter (FILTER). StageHandler (createSimpleOverallStageHandler).
        list.append(_mkHandler(nextPrio(), graphCategoryFilterStageHandler))
        // 9. map data statistic (STATISTIC). StageHandler.
        list.append(_mkHandler(nextPrio(), mapDataStatisticStageHandler))
        // 10. axisPointer coordSysAxesInfo (STATISTIC). Global overall; stashes the association tree.
        list.append(_mkOverallHandler(nextPrio(), { ecModel, api, _ in
            if let apModel = ecModel.getComponent("axisPointer") as? AxisPointerModel {
                apModel.coordSysAxesInfo = collect(ecModel, api)
            }
        }))
        return list
    }

    /// The visual StageHandlers the Scheduler would run in `performVisualTasks`. EMPTY: the visual stage
    /// stays a DIRECT call (performVisualStage/performVisualMapStage in update()) because the visual
    /// encoders do their work in the task PROGRESS callback over the pipeline-threaded `context.data`,
    /// and the overall-processor STUBs piped ahead of the visual tasks do not thread the series data
    /// through as outputData under the current dirty/perform ordering (a routed visual task pulled nil
    /// context.data and skipped encoding). Populating this + routing performVisualTasks is deferred to
    /// C2, together with the stub outputData passthrough fix (also required for progressive render).
    func buildVisualHandlers() -> [StageHandlerInternal] {
        return []
    }

    static func installOnce() {
        if _installed { return }
        _installed = true

        // -- core/locale.ts module side-effects -- registerLocale('EN', langEN) + registerLocale('ZH',
        //   langZH). A Swift caseless enum has no module init slot, so the default registration is run
        //   here (idempotent). `GlobalModel.getLocaleModel()` returns the per-instance locale Model built
        //   from `locale.createLocaleObject(SYSTEM_LANG)` in setOption below.
        locale.registerDefaultLocales()

        // -- theme/dark.ts + echarts.ts `registerTheme('dark', darkTheme)` -- register the built-in dark
        //   theme so `ECharts(width:height:theme: "dark")` resolves it by name (mirrors the upstream
        //   `themeStorage` lookup in `echarts.init(dom, theme)`).
        registerTheme("dark", darkTheme.theme)
        // Broadened built-in theme spread (ported from upstream/echarts/theme/*.js extension themes).
        registerTheme("vintage", vintageTheme.theme)
        registerTheme("macarons", macaronsTheme.theme)

        // -- features/index.ts `use(install)` for the AxisBreak feature -- registers the concrete
        //   scale-break helper (scale/breakImpl.ts `installScaleBreakHelper`). Idempotent; enables the
        //   `xxxAxis.breaks` option. Non-broken axes stay byte-identical (empty breaks => brk stays nil).
        installScaleBreakHelper()

        // -- component/dataset/install.ts -- registerComponentModel(DatasetModel) +
        //   registerComponentView(DatasetView). Must be registered so a `dataset: [...]` option
        //   instantiates a `DatasetModelImpl` (its `init` builds a SourceManager); series then query
        //   it via `querySeriesUpstreamDatasetModel`. `datasetInstall` registers the model in the
        //   `ComponentModel` registry (the path GlobalModel reads) and the view in the `ComponentView`
        //   registry; the path resolves the (no-op) DatasetView via the `_componentViewFactories`
        //   entry below (upstream `DatasetView` renders nothing).
        datasetInstall(ECharts._registers)

        // -- component/grid/installSimple.ts + coord/cartesian --
        ComponentModel.registerClass(GridModel.self)                       // registerComponentModel(GridModel)
        ComponentModel.registerClass(EChartsXAxisModel.self)                  // axisModelCreator(..,'x',..)  (stand-in)
        ComponentModel.registerClass(EChartsYAxisModel.self)                  // axisModelCreator(..,'y',..)  (stand-in)
        CoordinateSystemManager.register("cartesian2d", GridCoordinateSystemCreator()) // registerCoordinateSystem('cartesian2d', Grid)

        // -- chart/bar/install.ts --
        ComponentModel.registerClass(BarSeriesModel.self)                  // registerSeriesModel(BarSeries)
        // registerLayout(VISUAL.LAYOUT, createCrossSeriesLayoutHandler(bar)) → `_barLayoutHandler`.
        // registerLayout(PROGRESSIVE_LAYOUT, createProgressiveLayout(bar)) → PORT-NOTE: `createProgressiveLayout`
        //   is ported (barGrid.swift) but not registered here — the non-large bar path recomputes per-item
        //   geometry inside `BarView.render`, so the progressive layout task is not needed for a basic render.
        // registerProcessor(PROCESSOR.STATISTIC, dataSample(bar)) — captured in `_dataSamplers` and run
        //   in the data-processor stage (see the `_dataSamplers` loop in the update pipeline).
        registerBarGridAxisHandlers(_registers)   // populates axisStatistics `clientsForLookup` +
                                                  //   captures the axis-statistics processor (see registrar).
                                                  //   NOTE: registers BOTH 'bar' and 'pictorialBar' axis
                                                  //   handlers, so pictorialBar needs no separate call.
        // upstream chart/bar/install.ts also `registerBarPolarAxisHandlers(registers, 'bar')`. This
        //   registers the polar-bar axis-statistics client (key "bar|&polar") so `associateSeriesWithAxis`
        //   (called by polarCreator) records each polar bar's BASE axis under that key — which the polar
        //   bar layout (`barLayoutPolar`, run in the layout stage below) reads back via `eachAxisOnKey`
        //   to compute each sector's r0/r/startAngle/endAngle (+ bar width/offset sharing + stacking).
        //   Without it, polar bars have no item layout and BarView emits zero Sectors (empty polar plot).
        registerBarPolarAxisHandlers(_registers, SERIES_TYPE_BAR)

        // -- chart/bar/installPictorialBar.ts -- registerSeriesModel(PictorialBarSeries) +
        //   registerChartView(PictorialBarView) (view keyed by subType 'pictorialBar' below) +
        //   registerLayout(VISUAL.LAYOUT, createCrossSeriesLayoutHandler(pictorialBar)) → `_pictorialBarLayoutHandler`
        //   + registerLayout(PROGRESSIVE_LAYOUT, createProgressiveLayout(pictorialBar)) →
        //   `_pictorialBarProgressiveLayoutHandler`. Both are run in the layout stage below. pictorialBar
        //   draws a repeated/stretched symbol per bar (symbolRepeat / symbolClip / symbolPosition) instead
        //   of a plain Rect, reusing the bar grid geometry.
        ComponentModel.registerClass(PictorialBarSeriesModel.self)

        // -- chart/line/install.ts (minimal) -- registerSeriesModel(LineSeries) + registerChartView(LineView).
        //   Line needs NO cross-series/progressive layout registrar (LineView computes points directly
        //   from `coord.dataToPoint`); the visual stage colors it like any series.
        //   registerProcessor(PROCESSOR.STATISTIC, dataSample(line)) — captured in `_dataSamplers`.
        ComponentModel.registerClass(LineSeriesModel.self)

        // -- chart/scatter/install.ts (minimal) -- registerSeriesModel(ScatterSeries) + registerChartView(ScatterView).
        //   Scatter (like line) computes point positions directly from `coord.dataToPoint`; no cross-series
        //   or progressive layout registrar is needed for the static render.
        ComponentModel.registerClass(ScatterSeriesModel.self)

        // -- chart/effectScatter/install.ts (minimal) -- registerChartView(EffectScatterView) +
        //   registerSeriesModel(EffectScatterSeries) + registerLayout(layoutPoints('effectScatter')) +
        //   registerVisual(...). Like scatter, EffectScatterView computes point positions directly from
        //   `coord.dataToPoint` (inlines pointsLayout), so no cross-series layout registrar is needed for the
        //   static render. The animated RIPPLE (helper/EffectSymbol) is DEFERRED (CONVENTIONS §5) — the view
        //   draws only the static base symbols. effectScatterInstall.swift is commented-only (diffable
        //   surface); actual wiring lives here per the boxplotInstall/parallelInstall convention.
        ComponentModel.registerClass(EffectScatterSeriesModel.self)

        // -- chart/heatmap/install.ts (minimal) -- registerSeriesModel(HeatmapSeriesModel) +
        //   registerChartView(HeatmapView) (view keyed by subType 'heatmap' below). Heatmap renders ONLY on
        //   cartesian2d in the port (one colored Rect per cell); geo/calendar/matrix coord paths are
        //   PORT-NOTE (deferred): those HeatmapView coord branches are not ported. Cell fill comes from the per-datum color the visualMap ENCODING wrote, so a
        //   `visualMap` component MUST be present for cells to be colored. heatmapInstall.swift is
        //   commented-only (diffable surface); actual wiring lives here per the effectScatterInstall convention.
        ComponentModel.registerClass(HeatmapSeriesModel.self)

        // -- chart/pie/install.ts (minimal) -- registerSeriesModel(PieSeries) + registerChartView(PieView) +
        //   registerLayout(pieLayout). Pie has NO cartesian coord (coordinateSystemUsage:"box"); PieView reads
        //   its geometry from `data.getItemLayout` populated by the pie layout stage (run in `render`).
        ComponentModel.registerClass(PieSeriesModel.self)
        // Trigger the lazy Swift-global that runs `registerLayOutOnCoordSysUsage` for pie's box coord-sys-usage
        //   (registerLayOutOnCoordSysUsage asserts uniqueness — reference EXACTLY once, here in installOnce).
        _ = pieLayOutOnCoordSysUsageRegistered

        // -- chart/funnel/install.ts (minimal) -- registerSeriesModel(FunnelSeries) + registerChartView(FunnelView) +
        //   registerLayout(funnelLayoutStageHandler). Funnel has NO cartesian coord (coordinateSystemUsage:"box",
        //   like pie); FunnelView reads its per-piece polygon `points` from `data.getItemLayout` populated by the
        //   funnel layout stage (run in `render`). Funnel needs no `registerLayOutOnCoordSysUsage` (it reads no
        //   `center`/`getCoord2`; the layout resolves its view rect purely from `createBoxLayoutReference`).
        ComponentModel.registerClass(FunnelSeriesModel.self)

        // -- chart/candlestick/install.ts (minimal) -- registerSeriesModel(CandlestickSeries) +
        //   registerChartView(CandlestickView) + registerLayout(candlestickLayout) + registerVisual(candlestickVisual)
        //   + registerCandlestickAxisHandlers(registers). Candlestick is a cartesian2d series (like bar): the axis
        //   handlers populate the axisStatistics `clientsForLookup` (bandWidth for candle width). The already-captured
        //   axis-statistics processor (registered once by the bar handlers) picks up the candlestick client too.
        ComponentModel.registerClass(CandlestickSeriesModel.self)
        registerCandlestickAxisHandlers(_registers)

        // -- chart/boxplot/install.ts (minimal) -- registerSeriesModel(BoxplotSeries) + registerChartView(BoxplotView)
        //   + registerLayout(boxplotLayoutStageHandler) + registerBoxplotAxisHandlers(registers). Boxplot is a
        //   cartesian2d series (like bar); its colors come from the generic visual stage (visualDrawType:'stroke'),
        //   so it needs NO dedicated visual handler — only the layout stage + axis statistics.
        ComponentModel.registerClass(BoxplotSeriesModel.self)
        registerBoxplotAxisHandlers(_registers)

        // -- chart/sunburst/install.ts (minimal) -- registerSeriesModel(SunburstSeries) +
        //   registerChartView(SunburstView) + registerLayout(sunburstLayoutStageHandler) +
        //   registerVisual(sunburstVisualStageHandler). Sunburst has NO cartesian coord (hierarchical,
        //   box-like usage like pie); SunburstView reads its per-node sector geometry from the tree
        //   layout populated by the sunburst layout stage (run in `render`). Its dedicated visual stage
        //   colors each node (installSunburstAction rollup/highlight is DEFERRED — see sunburstInstall.swift).
        ComponentModel.registerClass(SunburstSeriesModel.self)

        // -- chart/treemap/install.ts (minimal) -- registerSeriesModel(TreemapSeries) +
        //   registerChartView(TreemapView) + registerLayout(treemapLayout) + registerVisual(treemapVisual).
        //   Treemap is hierarchical/box-usage (no cartesian coord); TreemapView reads each node's rect from
        //   the treemap layout stage, and treemapVisual colors each node FROM that layout (isInView/invisible),
        //   so — like candlestick — the layout MUST run before the visual (both run in `render`).
        ComponentModel.registerClass(TreemapSeriesModel.self)

        // -- chart/tree/install.ts (minimal) -- registerSeriesModel(TreeSeries) +
        //   registerChartView(TreeView) + registerLayout(treeLayout) + registerVisual(treeVisualStageHandler).
        //   Tree is hierarchical/box-usage (no cartesian coord); TreeView reads each node's x/y from the tree
        //   layout stage. Its dedicated visual stage sets per-node symbol colors (independent of layout).
        ComponentModel.registerClass(TreeSeriesModel.self)

        // -- chart/graph/install.ts (minimal) -- registerSeriesModel(GraphSeries) +
        //   registerChartView(GraphView) + registerLayout(circular/simpleLayout stage handlers) +
        //   registerProcessor(categoryFilter) + registerVisual(categoryVisual/edgeVisual). Graph is a
        //   coordless network chart (box/view usage); GraphView reads each node's [x,y] and each edge's
        //   [[p1],[p2](,[cp])] from the layout stage (circular or simple, self-gated on the `layout`
        //   option). The category visual colors nodes; the edge visual MUST run AFTER it (edge
        //   source/target stroke reads node fill). categoryFilter (legend-gated processor) runs in the
        //   data-processor stage. All run in `render`/`update` below.
        ComponentModel.registerClass(GraphSeriesModel.self)

        // -- chart/sankey/install.ts (minimal) -- registerSeriesModel(SankeySeries) +
        //   registerChartView(SankeyView) + registerLayout(sankeyLayoutStageHandler) +
        //   registerVisual(sankeyVisualStageHandler). Sankey is a COORDLESS flow chart (box usage, no
        //   cartesian coord; reuses the ported Graph + createGraphFromNodeEdge exactly like GraphSeries).
        //   SankeyView reads each node's rect {x,y,dx,dy} + each edge's ribbon {sy,ty,dy} from the box
        //   layout stage (sankeyLayout), and each node's fill from the visual stage (sankeyVisual). The
        //   visual reads `node.getLayout().value` written by the layout, so the layout MUST run first;
        //   both run in `render`/`update` below. The `dragNode` action + roam are DEFERRED (roamHelper
        //   not ported); see chart/sankey/sankeyInstall.swift.
        ComponentModel.registerClass(SankeySeriesModel.self)

        // -- chart/chord/install.ts (minimal) -- registerSeriesModel(ChordSeriesModel) +
        //   registerChartView(ChordView) + registerLayout(PRIORITY.VISUAL.POST_CHART_LAYOUT,
        //   chordCircularLayoutStageHandler) + registerProcessor(dataFilter('chord')). Chord is a
        //   COORDLESS circular flow chart (box usage, no cartesian coord; reuses the ported Graph +
        //   createGraphFromNodeEdge exactly like Sankey/Graph). ChordView reads each node's arc
        //   {cx,cy,r0,r,startAngle,endAngle,clockwise} + each edge's ribbon (s1/s2/t1/t2/angles) from the
        //   circular layout stage (chordCircularLayout). getDataParams/formatTooltip read
        //   `node.getLayout().value` written by the layout, so the layout MUST run first; it runs in
        //   `render`/`update` below. The `dataFilter('chord')` processor (data-item legend show/hide) is
        //   wired via `legendDataFilter(SERIES_TYPE_CHORD)` in `_dataFilters`; see chart/chord/chordInstall.swift.
        ComponentModel.registerClass(ChordSeriesModel.self)

        // -- chart/lines/install.ts (minimal) -- registerChartView(LinesView) +
        //   registerSeriesModel(LinesSeries) + registerLayout(linesLayout) + registerVisual(linesVisual).
        //   Lines is a coord-space series (default coord 'geo'; ONLY cartesian2d is rendered by the ported
        //   static view — polar/geo/calendar are PORT-NOTE (deferred): unported in linesLayout/LinesView). `linesLayout` is a
        //   SERIES_STAGE_TASK (seriesType 'lines') whose reset→progress writes each line's per-item layout
        //   (`data.setItemLayout(i, pts)`), same wiring as candlestickLayout. LinesView also inlines the
        //   per-item dataToPoint + curveness control-point math (like ScatterView/LineView), so the layout
        //   stage is run here for fidelity but the view does not depend on it. The effect (moving-dot/trail)
        //   + large draw path are ANIMATED/DEFERRED; linesVisual (palette stroke) lands with a later phase —
        //   the shared visual/style stage supplies the lineStyle→stroke color meanwhile. linesInstall.swift
        //   is commented-only (diffable surface); actual wiring lives here.
        ComponentModel.registerClass(LinesSeriesModel.self)

        // -- chart/gauge/install.ts (minimal) -- registerSeriesModel(GaugeSeries) + registerChartView(GaugeView).
        //   Gauge is COORDLESS (no coordinate system, no layout/visual stage): center/radius/startAngle/endAngle
        //   drive geometry directly, and GaugeView computes the axis arc bands, ticks, split lines, pointer,
        //   anchor and title/detail text in `render`. Mirrors how pie/funnel register their series model here
        //   (view keyed by subType in `_chartViewFactories` below); no coord-sys and no separate layout stage.
        ComponentModel.registerClass(GaugeSeriesModel.self)

        // -- chart/themeRiver/install.ts (minimal) -- registerChartView(ThemeRiverView) +
        //   registerSeriesModel(ThemeRiverSeriesModel) + registerLayout(themeRiverLayout) +
        //   registerProcessor(dataFilter('themeRiver')). ThemeRiver is a streamgraph on the SINGLE
        //   coordinate system (dependencies ["singleAxis"]); its layout stage reads the Single coord rect +
        //   axis orient and writes each datum's {layerIndex,x,y0,y} band point, which ThemeRiverView reads
        //   back to draw one Polygon per layer. themeRiverLayout runs in render()/update() AFTER the coord
        //   create/update (it casts seriesModel.coordinateSystem to Single). The dataFilter processor
        //   (data-item legend show/hide) is wired via `legendDataFilter(SERIES_TYPE_THEME_RIVER)` in
        //   `_dataFilters`; see themeRiverInstall.swift.
        ComponentModel.registerClass(ThemeRiverSeriesModel.self)                   // registerSeriesModel(ThemeRiverSeries)

        // -- component/radar/install.ts + chart/radar/install.ts (radar coordinate system) --
        //   registerCoordinateSystem('radar', Radar) + registerComponentModel(RadarModel) +
        //   registerComponentView(RadarComponentView) + registerSeriesModel(RadarSeriesModel) +
        //   registerChartView(RadarView) + registerLayout(radarLayoutStageHandler) +
        //   registerPreprocessor(radarBackwardCompat) + registerVisual(legendIcon 'roundRect').
        //   Radar is the FIRST non-cartesian coordinate system wired: the coord-sys register mirrors the
        //   cartesian2d register above (a CoordinateSystemCreator forwarding to Radar.create). The
        //   RadarModel is the coord-sys HOST component (like GridModel); its per-indicator AxisBaseModels
        //   feed the IndicatorAxes the coord builds. `_coordSysMgr.create`/`.update` (update() stages 3/5)
        //   build + update each Radar; the radarLayout stage (run in render()) stores each datum's closed
        //   point ring, which RadarView reads back. The backwardCompat preprocessor runs in setOption.
        //   registerVisual(legendIcon 'roundRect') → PORT-NOTE (deferred): requires the component/radar/install.ts
        //     legendIcon visual stage (sets each datum's legendIcon='roundRect'); the visual-stage registry is not wired here.
        CoordinateSystemManager.register("radar", RadarCoordinateSystemCreator()) // registerCoordinateSystem('radar', Radar)
        ComponentModel.registerClass(RadarModel.self)                             // registerComponentModel(RadarModel)
        ComponentModel.registerClass(RadarSeriesModel.self)                       // registerSeriesModel(RadarSeries)

        // -- component/polar/install.ts (polar coordinate system) --
        //   registerCoordinateSystem('polar', Polar) + registerComponentModel(PolarModel) +
        //   axisModelCreator(registers, 'angle'/'radius', AngleAxisModel/RadiusAxisModel, extra) +
        //   registerComponentView(AngleAxisView) + registerComponentView(RadiusAxisView) +
        //   registerComponentView(PolarView) [+ PolarAxisPointer, deferred].
        //   Polar is the SECOND non-cartesian coordinate system wired: the coord-sys register mirrors the
        //   cartesian2d/radar registers above (a CoordinateSystemCreator forwarding to polarCreator.create).
        //   The PolarModel is the coord-sys HOST component (like GridModel/RadarModel); its angleAxis +
        //   radiusAxis component models feed the AngleAxis/RadiusAxis the coord builds. Unlike the cartesian
        //   x/y stand-ins (EChartsXAxisModel), the polar axis models are the REAL AngleAxisModel/RadiusAxisModel
        //   (concrete PolarAxisModel subclasses), registered directly here — so `PolarModel.findAxisModel`'s
        //   `as? PolarAxisModel` + `getCoordSysModel()` resolve end-to-end (the axisModelCreator dynamic-
        //   subclass gap that blocks the cartesian path does not apply). The polar axis models carry the
        //   angle/radius extra defaults (startAngle 90 / splitNumber) via `polarAxisExtraOption` (merged in
        //   mergeDefaultAndTheme). `_coordSysMgr.create`/`.update` (update() stages 3/5) build + update each
        //   Polar; the AngleAxisView/RadiusAxisView draw the angle rings + radius axis backdrop.
        CoordinateSystemManager.register("polar", PolarCoordinateSystemCreator()) // registerCoordinateSystem('polar', Polar)
        ComponentModel.registerClass(PolarModel.self)                             // registerComponentModel(PolarModel)
        ComponentModel.registerClass(AngleAxisModel.self)                         // axisModelCreator(..,'angle',..)
        ComponentModel.registerClass(RadiusAxisModel.self)                        // axisModelCreator(..,'radius',..)

        // -- coord/single/install.ts (single coordinate system) --
        //   registerComponentModel(SingleAxisModel) + axisModelCreator(registers, 'single', SingleAxisModel,
        //   SingleAxisModel.defaultOption) + registerCoordinateSystem('single', singleCreator) +
        //   registerComponentView(SingleAxisView) [in component/axis/install.ts].
        //   Single is the FOURTH coordinate system wired: the coord-sys register mirrors the polar register
        //   above (a CoordinateSystemCreator forwarding to singleCreator.create). SingleAxisModel is the
        //   coord-sys HOST component AND the axis model at once (getCoordSysModel() returns self); like the
        //   polar axis models it is registered directly (this port has no runtime axisModelCreator — the
        //   per-type value/category/time/log subclasses it would generate are collapsed into the one model,
        //   same deviation as the polar axis models). `_coordSysMgr.create`/`.update` build + update each
        //   Single; SingleAxisView draws the axis backdrop + splitLine grid.
        CoordinateSystemManager.register("single", SingleCoordinateSystemCreator()) // registerCoordinateSystem('single', singleCreator)
        ComponentModel.registerClass(SingleAxisModel.self)                          // registerComponentModel(SingleAxisModel)

        // -- coord/parallel/install.ts + component/parallel/install.ts + chart/parallel/install.ts --
        //   registerCoordinateSystem('parallel', parallelCoordSysCreator) + registerComponentModel(ParallelModel)
        //   + registerComponentModel(ParallelAxisModel) + axisModelCreator(registers, 'parallel', ParallelAxisModel,
        //   defaultAxisOption) + registerPreprocessor(parallelPreprocessor) + registerComponentView(ParallelView)
        //   + registerComponentView(ParallelAxisView) + registerSeriesModel(ParallelSeriesModel) +
        //   registerChartView(ParallelView[chart]) + registerVisual(PRIORITY.VISUAL.BRUSH, parallelVisual).
        //   Parallel is the FIFTH coordinate system wired: the coord-sys register mirrors the single register
        //   above. ParallelModel is the coord-sys HOST component (dependencies ["parallelAxis"], so parallelAxis
        //   models load first); ParallelAxisModel is registered DIRECTLY under mainType 'parallelAxis' (same
        //   direct-registration shortcut as SingleAxisModel/the polar axis models — no runtime axisModelCreator),
        //   so `getComponent('parallelAxis', …) as! ParallelAxisModel` in the coord + `axis.dim` /
        //   getAreaSelectStyle() in ParallelAxisView resolve end-to-end. `_coordSysMgr.create`/`.update`
        //   (update() stages 3/5) build + update each Parallel; ParallelAxisView draws each axis backdrop (N
        //   registered 'parallelAxis' component views), ParallelView[component] is interaction-only, and the
        //   chart-side ParallelView draws one Polyline per data item. The parallelPreprocessor (creates
        //   parallelAxis components from parallel.parallelAxisDefault) runs in setOption. The `axisAreaSelect`
        //   active-interval selection ACTION is now wired (installParallelActions below → sets
        //   ParallelAxisModel.activeIntervals → Parallel.eachActiveState dims out-of-interval lines via
        //   parallelVisual). The LIVE axis-drag BrushController that would EMIT axisAreaSelect (ParallelAxisView
        //   ._refreshBrushController/_onBrush) + the axis-expand pointer roam remain // PORT-NOTE (deferred): live brush/roam interaction unported.
        CoordinateSystemManager.register("parallel", ParallelCoordinateSystemCreator()) // registerCoordinateSystem('parallel', parallelCoordSysCreator)
        ComponentModel.registerClass(ParallelModel.self)                            // registerComponentModel(ParallelModel)
        ComponentModel.registerClass(ParallelAxisModel.self)                        // registerComponentModel(ParallelAxisModel) + axisModelCreator(..,'parallel',..)
        ComponentModel.registerClass(ParallelSeriesModel.self)                      // registerSeriesModel(ParallelSeries)

        // -- coord/calendar/install.ts (calendar coordinate system, the SIXTH) --
        //   registerCoordinateSystem('calendar', Calendar) + registerComponentModel(CalendarModel) +
        //   registerComponentView(CalendarView). The calendar coord maps a DATE to a day-cell; CalendarView
        //   draws the grid/split-line backdrop + day/week/month/year labels.
        CoordinateSystemManager.register("calendar", CalendarCoordinateSystemCreator()) // registerCoordinateSystem('calendar', Calendar)
        ComponentModel.registerClass(CalendarModel.self)                            // registerComponentModel(CalendarModel)

        // -- component/matrix/install.ts (matrix coordinate system, the EIGHTH) --
        //   registerCoordinateSystem('matrix', Matrix) + registerComponentModel(MatrixModel) +
        //   registerComponentView(MatrixView). The matrix coord maps an (x,y) header/body cell to a rect;
        //   MatrixView draws the table backdrop (header + body cell rects + header text labels).
        //   PORT-NOTE (deferred): matrixPrepareCustom (custom-series coord hook) is unregistered — same as
        //   calendarPrepareCustom (no prepareCustom registry yet). Cell interaction is deferred (unported) in MatrixView.
        CoordinateSystemManager.register("matrix", MatrixCoordinateSystemCreator()) // registerCoordinateSystem('matrix', Matrix)
        ComponentModel.registerClass(MatrixModel.self)                              // registerComponentModel(MatrixModel)

        // -- component/geo/install.ts (geo coordinate system, the SEVENTH) --
        //   registerCoordinateSystem('geo', geoCreator) + registerComponentModel(GeoModel) +
        //   registerComponentView(GeoView) (factory above) + registerMap/getMap (geoSourceManager).
        //   The geo coord projects [lng, lat] to a pixel via the `View` transform (+ optional projection);
        //   GeoView draws the static GeoJSON region outlines + labels backdrop.
        //   `geoCreator` is the ported singleton `GeoCreator()` (conforms to CoordinateSystemCreator directly).
        //   PORT-NOTE (deferred, with events/roam): geoToggleSelect/geoSelect/geoUnSelect/geoRoam actions;
        //   the geoPrepareCustom custom-series coord hook is unregistered (no prepareCustom registry yet —
        //   same as calendarPrepareCustom / polar prepareCustom, custom series is Phase 6b).
        CoordinateSystemManager.register("geo", geoCreator)                         // registerCoordinateSystem('geo', geoCreator)
        ComponentModel.registerClass(GeoModel.self)                                // registerComponentModel(GeoModel)

        // -- chart/map/install.ts (minimal) -- use(installGeo) [geo coord above] +
        //   registerSeriesModel(MapSeries) + registerChartView(MapView) + registerLayout(mapSymbolLayoutStageHandler)
        //   + registerProcessor(PRIORITY.PROCESSOR.STATISTIC, mapDataStatisticStageHandler). Map is a series on
        //   the GEO coordinate system (dependencies ["geo"]); geoCreator's map-series-group path builds an
        //   exclusive Geo for a `series.map` (with `map:<name>`) and injects it as `seriesModel.coordinateSystem`.
        //   The STATISTIC processor (mapDataStatistic) runs in the data-processor stage (stage 4) to merge
        //   multi-series region values + stamp each series' `originalData`/`seriesGroup`; the mapSymbolLayout
        //   stage (run in render) places the per-region legend symbols. MapView draws one CompoundPath per
        //   region, filled by the datum value (visualMap/itemStyle). createLegacyDataSelectAction('map', ...) is
        //   DEFERRED (legacy/dataSelectAction.ts not ported); roam/select actions DEFERRED. mapInstall.swift is
        //   commented-only (diffable surface); actual wiring lives here per the geo/heatmap install convention.
        ComponentModel.registerClass(MapSeriesModel.self)                          // registerSeriesModel(MapSeries)

        // -- chart/custom/install.ts (minimal) -- registerSeriesModel(CustomSeries) +
        //   registerChartView(CustomChartView) (view keyed by subType 'custom' below). The `renderItem`
        //   Swift closure is carried on the series option under key "renderItem" typed EXACTLY as
        //   CustomSeriesRenderItem (CustomSeriesModel.getRenderItem() casts it) OR registered globally via
        //   registerCustomSeries(subType, renderItem). CustomChartView resolves it as
        //   `series.getRenderItem() ?? getCustomSeries(subType)`. cartesian2d prepareCustom supplies
        //   api.coord/api.size. transitions/morph/states are PORT-NOTE (deferred): unported. customInstall.swift is commented-only
        //   (diffable surface); actual wiring lives here per the boxplot/heatmap install convention.
        ComponentModel.registerClass(CustomSeriesModel.self)                        // registerSeriesModel(CustomSeries)

        // -- component/title/install.ts -- registerComponentModel(TitleModel) + registerComponentView(TitleView).
        ComponentModel.registerClass(TitleModel.self)

        // -- component/aria/install.ts -- registerPreprocessor(ariaPreprocessor) +
        //   registerVisual(PRIORITY.VISUAL.ARIA, ariaVisualStageHandler). Aria has NO ComponentModel
        //   (it reads `ecModel.getModel('aria')` off the raw option; the "aria enabled" default is stamped
        //   in `initBase`, matching upstream GlobalModel.ts). The preprocessor (`ariaPreprocessor`) runs in
        //   `setOption` (see below); the visual stage handler generates the accessibility LABEL and is
        //   invoked directly in `update()` (`aria.ariaLabel(...)` → stored on the ec instance,
        //   `getAriaLabel()`) because a `StageHandler` returns Void and there is no DOM to write to.
        //   The `aria.decal.show` decal (SVG-pattern) generation is ported (decal palette infra: util/decal.swift,
        //   visual/decalVisual.swift). See Sources/EChartsKit/component/aria/ariaVisual.swift + ariaPreprocessor.swift.

        // -- component/timeline/install.ts -- registerComponentModel(SliderTimelineModel) +
        //   registerComponentView(SliderTimelineView) + registerSubTypeDefaulter('timeline', ()=>'slider')
        //   + installTimelineAction + registerPreprocessor(timelinePreprocessor). Like visualMap/dataZoom,
        //   the ABSTRACT base `TimelineModel` (type 'timeline') is NOT registered; only the concrete
        //   'timeline.slider' subtype is, and a subtype defaulter resolves a bare `timeline: {...}` to it.
        //   The baseOption+options[currentIndex] MERGE is driven by OptionManager (getTimelineOption reads
        //   the model's currentIndex). The play AUTO-ADVANCE is DEFERRED (needs the live host); the STATIC
        //   axis + tick symbols + control buttons + current-index checkpoint are what render here.
        ComponentModel.registerClass(SliderTimelineModel.self)
        ComponentModel.registerSubTypeDefaulter("timeline", { _ in "slider" })
        installTimelineAction(ECharts._registers)                      // registerAction('timelineChange'/'timelinePlayChange')

        // -- component/graphic/install.ts -- registerComponentModel(GraphicComponentModel) +
        //   registerComponentView(GraphicComponentView) + registerPreprocessor(graphicOptionPreprocessor).
        //   The preprocessor is invoked in `setOption` (see below).
        ComponentModel.registerClass(GraphicComponentModel.self)

        // -- component/legend/installLegendPlain.ts -- registerComponentModel(LegendModel) +
        //   registerComponentView(LegendView) + registerSubTypeDefaulter('legend', () => 'plain').
        //   LegendModel.type == 'legend.plain', so a subtype defaulter is required for the bare
        //   `legend: {...}` option (mainType 'legend', no subtype) to resolve to 'legend.plain'.
        ComponentModel.registerClass(LegendModel.self)
        ComponentModel.registerSubTypeDefaulter("legend", { _ in "plain" })

        // -- component/legend/installLegendScroll.ts -- registerComponentModel(ScrollableLegendModel) +
        //   registerComponentView(ScrollableLegendView) + legendScrollActions (page-flip action). The
        //   subtype defaulter above resolves a bare `legend: {...}` (no `type`) to 'plain'; an explicit
        //   `legend: {type: 'scroll'}` resolves via `option.type` → 'legend.scroll' → this model/view.
        //   The page-flip ACTION ('legendScroll') is DEFERRED (needs the live-view host); the STATIC
        //   pagination layout (first page + clip + page controls) is what renders here.
        ComponentModel.registerClass(ScrollableLegendModel.self)

        // -- component/visualMap/installCommon.ts + typeDefaulter.ts + preprocessor.ts + visualEncoding.ts --
        //   registerComponentModel(ContinuousModel/PiecewiseModel) + registerComponentView(ContinuousView/
        //   PiecewiseVisualMapView) + registerSubTypeDefaulter('visualMap', continuous|piecewise) +
        //   registerVisual(PRIORITY.VISUAL.COMPONENT, visualMapEncodingHandlers) + registerPreprocessor +
        //   registerAction('selectDataRange'). VisualMapModel is the ABSTRACT base and is NOT registered; the
        //   two concrete subtypes are. The subtype defaulter resolves a bare `visualMap: {...}` option
        //   (mainType 'visualMap', no subtype) to 'continuous' | 'piecewise' (ec2-compat splitNumber/pieces/
        //   calculable heuristic). The value->visual ENCODING runs in the visual stage (performVisualStage →
        //   performVisualMapStage) AFTER each series' own visual stage, so it overwrites the palette color.
        ComponentModel.registerClass(ContinuousModel.self)                 // registerComponentModel(ContinuousModel)
        ComponentModel.registerClass(PiecewiseModel.self)                  // registerComponentModel(PiecewiseModel)
        registerVisualMapSubTypeDefaulter()                                // registerSubTypeDefaulter('visualMap', ...)
        registerAction(visualMapActionInfo, visualMapActionHander)         // registerAction('selectDataRange', ...)

        // -- component/dataZoom/install.ts (installDataZoomInside + installDataZoomSlider + installCommon) --
        //   registerComponentModel(InsideZoomModel / SliderZoomModel) + registerComponentView(...) [DEFERRED
        //   view] + registerProcessor(PRIORITY.PROCESSOR.FILTER, dataZoomProcessor) + installDataZoomAction +
        //   registerSubTypeDefaulter('dataZoom', () => 'slider'). Like visualMap, the ABSTRACT base
        //   `DataZoomModel` is NOT registered; only the two concrete subtypes are. The subtype defaulter
        //   resolves a bare `dataZoom: [{start, end}]` (mainType 'dataZoom', no subtype) to 'slider'.
        //   The DATA core (window calc + axis reset + series-data filter) runs from `dataZoomProcessor` in
        //   `update()`; the slider/inside VIEWS + roam/drag are DEFERRED (need a live-view host).
        ComponentModel.registerClass(InsideZoomModel.self)                 // registerComponentModel(InsideZoomModel)
        ComponentModel.registerClass(SliderZoomModel.self)                 // registerComponentModel(SliderZoomModel)
        ComponentModel.registerSubTypeDefaulter("dataZoom", { _ in "slider" })
        installDataZoomAction(ECharts._registers)                      // registerAction('dataZoom', ...)

        // -- component/tooltip/install.ts -- registerComponentModel(TooltipModel) +
        //   registerComponentView(TooltipView) + ... . Phase 31 ports ONLY the host-independent
        //   tooltip CONTENT model (formatTooltip → markup → html/richText string). The on-screen
        //   TooltipView + the hover TRIGGER are DEFERRED (need the live-view host — a later phase),
        //   so ONLY the model is registered here (no view). `dependencies = ['axisPointer']`; AxisPointerModel
        //   is ported (AxisPointerModel.swift), but the tooltip's embedded `axisPointer` sub-option is kept as an
        //   untyped `[String: Any]` bag (see TooltipModel.swift PORT-NOTE).
        ComponentModel.registerClass(TooltipModel.self)                    // registerComponentModel(TooltipModel)
        installTooltipActions(ECharts._registers)                      // registerAction('showTip'/'hideTip', noop)

        // -- component/axisPointer/install.ts (Phase 35 + handle) -- registerComponentModel(AxisPointerModel) +
        //   registerPreprocessor (ensure a global axisPointer option always exists — done in setOption) +
        //   registerProcessor(PRIORITY.PROCESSOR.STATISTIC, { overallReset: coordSysAxesInfo = collect(...) })
        //   + registerAction('updateAxisPointer', axisTrigger). The axisPointer VIEW (the drawn crosshair)
        //   is driven by `EChartsView` (Phase 36), not a per-axis AxisView factory; only the DATA core
        //   (collect → coordSysAxesInfo, consumed by axisTrigger) is wired at model registration. The
        //   `collect` run itself lives in `update()` (statistic stage), see below.
        ComponentModel.registerClass(AxisPointerModel.self)                 // registerComponentModel(AxisPointerModel)

        // registers.registerAction({ type:'updateAxisPointer', event:'updateAxisPointer',
        //   update:':updateAxisPointer' }, axisTrigger);
        //   The draggable axisPointer HANDLE dispatches this action (BaseAxisPointer._doDispatchAxisPointer)
        //   while dragged; the `axisTrigger` handler recomputes the hovered/dragged axis value(s) and
        //   writes them onto each axisPointer model (updateModelActually), then fires showTip/hideTip.
        // PORT-NOTE (update method): upstream's `update:':updateAxisPointer'` broadcasts to every
        //   `AxisView.updateAxisPointer` to re-draw the crosshair+handle at the new value. In THIS port
        //   there is NO live per-axis `AxisView` (ECharts is zr-less; `EChartsView` owns the pointer
        //   managers — see EChartsView._updateAxisPointers), so that empty-mainType broadcast has no
        //   target and was elided (see updateDirectly). We therefore register `update:'none'` — the
        //   `axisTrigger` action handler still runs (model mutation + tooltip), and `EChartsView`
        //   re-renders the crosshairs by listening on the emitted `updateAxisPointer` event.
        var updateAxisPointerAction = ActionInfo(type: "updateAxisPointer")
        updateAxisPointerAction.event = "updateAxisPointer"
        updateAxisPointerAction.update = "none"
        registerAction(updateAxisPointerAction) { payload, ecModel, api in
            // upstream default export `axisTrigger(payload, ecModel, api)` — returns the outputPayload
            //   (ModelFinderObject + axesInfo) that becomes the event content for `echarts.connect`.
            let out = axisTrigger(payload, ecModel, api)
            var ev: ECEventData = [:]
            if let si = out.seriesIndex { ev["seriesIndex"] = si }
            if let di = out.dataIndex { ev["dataIndex"] = di }
            if let dii = out.dataIndexInside { ev["dataIndexInside"] = dii }
            ev["axesInfo"] = out.axesInfo
            return ev
        }

        // -- component/brush/install.ts (Phase 44, RECT core) -- registerComponentModel(BrushModel) +
        //   registerVisual(PRIORITY.VISUAL.BRUSH, { seriesTypes: '', reset: ...brushVisual }) +
        //   installBrushAction (registerAction 'brush'/'brushSelect'/'brushEnd'). The brush VIEW +
        //   toolbox button + BrushController (polygon/lineX/lineY drag UI) are DEFERRED; only the DATA
        //   core runs: `layoutCovers` (build per-area boundingRects) + `brushVisual` (in→inBrush /
        //   out→outOfBrush → dim unselected via blur) execute in `update()`'s visual stage below, and
        //   a minimal rect-drag in EChartsView dispatches `type:"brush"` with the dragged coordRange.
        ComponentModel.registerClass(BrushModel.self)                       // registerComponentModel(BrushModel)
        installBrushAction(ECharts._registers)                          // registerAction('brush'/'brushSelect'/'brushEnd')

        // -- component/toolbox/install.ts (Phase 49, ACTION core) -- registerComponentModel(ToolboxModel) +
        //   the `restore` (ecModel.resetOption('recreate')) + `changeMagicType` (ecModel.mergeOption) action
        //   handlers. The on-canvas icon VIEW + host-dependent features (saveAsImage/dataView/dataZoom-select/
        //   brush button) are DEFERRED; the option-expressible feature DATA cores are wired.
        ComponentModel.registerClass(ToolboxModel.self)                     // registerComponentModel(ToolboxModel)
        registerToolboxFeatures()                                           // registerFeature('saveAsImage'/'magicType'/'dataZoom'/'restore')
        installToolboxActions(ECharts._registers)                       // registerAction('restore'/'changeMagicType')

        // component/legend/legendAction.ts `installLegendAction` — registerAction('legendToggleSelect'/
        //   'legendSelect'/'legendUnSelect'/'legendAllSelect'/'legendInverseSelect', update:'update'). A
        //   legend item click dispatches legendToggleSelect (wired in LegendView._createItem); the handler
        //   toggles LegendModel.selected, and the driver's full update() re-runs legendFilter to show/hide.
        installLegendAction(ECharts._registers)

        // -- chart/sunburst/sunburstAction.ts `installSunburstAction` — registerAction('sunburstRootToNode',
        //   update:'updateView'). Clicking a sunburst sector dispatches sunburstRootToNode with the target
        //   node (wired per-piece in SunburstView._bindNodeClick); the handler re-roots the series' viewRoot
        //   (SunburstSeriesModel.resetViewRoot), and the driver's full update() re-runs the sunburst layout
        //   around the new root (drill-down / roll-up). sunburstHighlight/sunburstUnhighlight DEFERRED.
        installSunburstAction(ECharts._registers)

        // -- component/marker/installMark{Point,Line,Area}.ts (Phase 52) --
        //   registerComponentModel(MarkPointModel/MarkLineModel/MarkAreaModel) + the auto-enable
        //   preprocessors (called in setOption). Markers render statically & faithfully: the Phase-51 axis
        //   witnesses fixed `coordSys.getAxis/getOtherAxis` and `SeriesModel.indicesOfNearest` is now
        //   implemented, so both COORDINATE markers (`{yAxis:v}`/`{coord:[x,y]}`) and STATISTIC markers
        //   (type:'min'/'max'/'average'/'median') resolve. markPoint renders via the real SymbolDraw
        //   (symbol + value label); markLine via a static LineDraw stand-in (dashed lineStyle + end
        //   symbols + label); markArea via its Polygon band. PORT-NOTE (deferred): enter/leave animation + emphasis unported.
        ComponentModel.registerClass(MarkPointModel.self)                  // registerComponentModel(MarkPointModel)
        ComponentModel.registerClass(MarkLineModel.self)                   // registerComponentModel(MarkLineModel)
        ComponentModel.registerClass(MarkAreaModel.self)                   // registerComponentModel(MarkAreaModel)

        // -- src/animation/universalTransition.ts `installUniversalTransition(registers)` (upstream
        //   echarts.all.ts / features.ts `use(installUniversalTransition)`) -- registerUpdateLifecycle(
        //   'series:beforeupdate') + registerUpdateLifecycle('series:transition'). The two listeners are
        //   what turn a `universalTransition: true` series pair (same `id`/`seriesKey`) into a real
        //   cross-series MORPH: 'series:transition' diffs the previous update's saved SeriesData against
        //   the new one and hands each matched old/new element pair to zrender's morphPath/combineMorph/
        //   separateMorph. `renderSeries` emits both triggers (see its lifecycle.trigger calls).
        installUniversalTransition(ECharts._registers)

        // -- component/transform/install.ts -- registers.registerTransform(filterTransform) +
        //   registers.registerTransform(sortTransform). Built-in data transforms live in the Phase-27
        //   registry (data/helper/transform.swift); `transformInstall` registers both against it so a
        //   `dataset: { transform: { type: "filter" | "sort", config: {...} } }` resolves WITHOUT the
        //   user pre-registering. The "echarts:" namespace makes them callable via the bare "filter"/"sort".
        transformInstall(ECharts._registers)

        // -- component/grid/installLegacyGridContainLabel.ts `use(LegacyGridContainLabel)` -- registers the
        //   pre-outerBounds `grid.containLabel` layout (registerLayOutGridByContainLabelImpl). Upstream
        //   gates it behind an explicit `use(...)`; this port installs it by default so a `containLabel:true`
        //   grid reserves its axis-label band natively, matching the reference echarts.js pane.
        installLegacyGridContainLabel(ECharts._registers)

        // -- core/echarts.ts `Default actions` (echarts.ts:3373-3411) -- highlight/downplay/select/
        //   unselect/toggleSelect. Upstream registers these at module load; the driver has no
        //   module-load side effects, so it happens here (see core/actionRegister.swift).
        registerBuiltinActions()

        // -- chart/graph/install.ts `registerRoamActionSimply(registers, 'series', 'graph')` -- the
        //   `graphRoam` action (pan/zoom → the graph view coord sys). See roamHelperGraph.swift.
        //   Idempotent: `registerAction` early-returns on a duplicate type.
        registerGraphRoamAction()

        // -- component/geo/install.ts `registerAction({type:'geoRoam', ...})` +
        //   chart/map/install.ts `registerRoamActionSimply(registers, 'series', 'map')` (both resolve to
        //   action type 'geoRoam', "Historical setting") -- the geo/map pan/zoom action. See roamHelperGeo.
        registerGeoRoamAction()

        // -- chart/tree/install.ts + chart/sankey/install.ts `registerRoamActionSimply(registers,'series',
        //   <sub>)` (→ 'treeRoam' / 'sankeyRoam') + the port's 'treemapRoam' (upstream treemap re-lays-out
        //   via 'treemapMove'/'treemapRender'; the port applies a view-group TRANSFORM — see
        //   roamHelperViewGroup.swift). All three accumulate pan/zoom onto the per-series roam state.
        // -- chart/tree/install.ts `installTreeAction(registers)` — registerAction('treeExpandAndCollapse')
        //   (node click → toggle node.isExpand, update:'update' re-lays-out) + registerTreeRoamAction()
        //   (the 'treeRoam' view-group roam action). See chart/tree/treeAction.swift.
        installTreeAction(ECharts._registers)
        registerTreemapRoamAction()
        // -- chart/sankey/install.ts `installSankeyAction(registers)` — registerAction('dragNode',
        //   update:'update') (node drag → SankeySeriesModel.setNodePosition persists localX/localY, the
        //   full update() re-renders the moved node + re-routes its edge ribbons) + registerSankeyRoamAction()
        //   (the 'sankeyRoam' view-group roam action). See chart/sankey/sankeyAction.swift.
        installSankeyAction(ECharts._registers)

        // -- component/axis/parallelAxisAction.ts `installParallelActions(registers)` — registerAction(
        //   'axisAreaSelect', event 'axisAreaSelected') (sets each queried parallelAxis model's active
        //   intervals → Parallel.eachActiveState dims the out-of-interval lines via the visual stage on the
        //   full update) + registerAction('parallelAxisExpand') (the axis expand-window; the LIVE axis-drag
        //   BrushController that would emit these is still // PORT-NOTE (deferred): unported in ParallelAxisView). See
        //   component/axis/parallelAxisAction.swift.
        installParallelActions(ECharts._registers)

        // View factories (upstream: registerComponentView / registerChartView; see header deviation).
        // (component views keyed by mainType; chart views keyed by subType.)
        // These are file-scope closures, assigned lazily on first `install`.
    }

    // Upstream stores the view CLASS; we store factories (see header). Keyed as upstream `getClass`
    // resolves: component views by mainType (grid/xAxis/yAxis), chart views by series subType (bar).
    private let _componentViewFactories: [String: () -> ComponentView] = [
        "grid": { GridView() },
        "xAxis": { CartesianXAxisView() },
        "yAxis": { CartesianYAxisView() },
        // dataset component view — a no-op backdrop (upstream `DatasetView` has no render/lifecycle
        //   overrides; it exists only so `getClass('dataset')` succeeds). Registered under mainType
        //   'dataset' (upstream component/dataset/install.ts `registerComponentView(DatasetView)`).
        "dataset": { DatasetView() },
        // Phase 7 static components (keyed by mainType; legend's subtype 'plain' is resolved by the
        //   registerSubTypeDefaulter above, but the VIEW is still looked up by mainType 'legend').
        "title": { TitleView() },
        // Timeline slider widget — the bottom playhead: axis line + per-index tick symbols + the
        //   current-index checkpoint symbol + prev/next/play control buttons. Keyed by FULL type
        //   'timeline.slider' (subtype dispatch — the base 'timeline' is abstract).
        "timeline.slider": { SliderTimelineView() },
        "graphic": { GraphicComponentView() },
        "legend": { LegendView() },
        // Scrollable legend view — resolved by FULL type 'legend.scroll' (subtype dispatch) so
        //   `legend: {type: 'scroll'}` gets the paginating view while a plain `legend: {...}` (full
        //   type 'legend.plain') still falls through to the mainType 'legend' → LegendView above.
        "legend.scroll": { ScrollableLegendView() },
        // Radar coord-sys component view (draws the axis lines/ticks/names + split rings/areas backdrop);
        //   registered under mainType 'radar' (upstream install.ts `registerComponentView(RadarView)`).
        "radar": { RadarComponentView() },
        // Polar coord-sys component views: the angleAxis view draws the angle rings (axisLine circle/arc +
        //   split lines + split areas + tick labels around the ring); the radiusAxis view draws the radial
        //   axis line + ticks + split lines. Registered under mainType 'angleAxis'/'radiusAxis' (upstream
        //   install.ts `registerComponentView(AngleAxisView)` / `registerComponentView(RadiusAxisView)`).
        "angleAxis": { AngleAxisView() },
        "radiusAxis": { RadiusAxisView() },
        // Single coord-sys component view (draws the single axis line + ticks + labels + splitLine grid
        //   across the coord rect). Registered under mainType 'singleAxis' (upstream component/axis/install.ts
        //   `registerComponentView(SingleAxisView)`).
        "singleAxis": { SingleAxisView() },
        // Parallel coord-sys component views. `parallelAxis` -> ParallelAxisView draws each axis backdrop
        //   (one registered view per parallelAxis component, via AxisBuilder → the N-axis backdrop is the
        //   composition of them). `parallel` -> ParallelComponentView (upstream component ParallelView) is
        //   interaction-only (axis-expand) and draws nothing. Registered under mainType 'parallelAxis' /
        //   'parallel' (upstream component/parallel/install.ts registerComponentView(ParallelAxisView) /
        //   registerComponentView(ParallelView)).
        "parallelAxis": { ParallelAxisView() },
        "parallel": { ParallelComponentView() },
        // calendar coord backdrop (grid + split lines + day/week/month/year labels).
        "calendar": { CalendarView() },
        // matrix coord backdrop (header + body cell rects + header text labels). Registered under mainType
        //   'matrix' (upstream component/matrix/install.ts `registerComponentView(MatrixView)`).
        "matrix": { MatrixView() },
        // geo coord-sys component view (draws the static GeoJSON region outlines + labels backdrop).
        //   Registered under mainType 'geo' (upstream component/geo/install.ts `registerComponentView(GeoView)`).
        "geo": { GeoView() },
        // visualMap control widget. Keyed by FULL type (subtype dispatch) — the doPrepare lookup tries
        //   `model.type` before `model.mainType`, so continuous vs piecewise resolve to distinct views.
        //   ContinuousView draws the static gradient bar; PiecewiseVisualMapView draws the per-piece swatch
        //   list. The value->visual ENCODING is independent of these views (it is a visual STAGE); the
        //   widget is the secondary deliverable (upstream `registerComponentView(ContinuousView/PiecewiseView)`).
        "visualMap.continuous": { ContinuousView() },
        "visualMap.piecewise": { PiecewiseVisualMapView() },
        // dataZoom slider widget (the on-screen bar with two draggable handles + the selected band).
        //   Keyed by FULL type 'dataZoom.slider' (subtype dispatch — the inside dataZoom has no view).
        //   Registered under upstream `registerComponentView(SliderZoomView)`.
        "dataZoom.slider": { SliderZoomView() },
        // Phase 52: the per-series marker component views (keyed by mainType). Each iterates the series,
        //   looks up its per-series marker submodel, and draws the points/lines/areas.
        "markPoint": { MarkPointView() },
        "markLine": { MarkLineView() },
        "markArea": { MarkAreaView() },
        // toolbox icon row (component/toolbox/install.ts `registerComponentView(ToolboxView)`). Renders
        //   the feature icon buttons (saveAsImage/restore/dataZoom/magicType) via makePath in a box row.
        "toolbox": { ToolboxView() },
        // brush component view (component/brush/install.ts `registerComponentView(BrushView)`). Owns the
        //   BrushController: it paints the COVER (the draggable selection rect / polygon / line band) into
        //   the zr, and turns a user drag into a `brush` / `brushEnd` action. Keyed by mainType 'brush'.
        "brush": { BrushView() }
    ]
    private let _chartViewFactories: [String: () -> ChartView] = [
        "bar": { BarView() },
        // PictorialBar chart view (repeated/stretched symbol per bar). Registered under series subType
        //   'pictorialBar' (upstream chart/bar/installPictorialBar.ts `registerChartView(PictorialBarView)`).
        "pictorialBar": { PictorialBarView() },
        "line": { LineView() },
        "scatter": { ScatterView() },
        // EffectScatter chart view (static base symbols; ripple DEFERRED). Registered under series subType
        //   'effectScatter' (upstream chart/effectScatter/install.ts `registerChartView(EffectScatterView)`).
        "effectScatter": { EffectScatterView() },
        // Heatmap chart view (cartesian2d colored-Rect path; geo/calendar/matrix DEFERRED). Registered under
        //   series subType 'heatmap' (upstream chart/heatmap/install.ts `registerChartView(HeatmapView)`).
        "heatmap": { HeatmapView() },
        "pie": { PieView() },
        "funnel": { FunnelView() },
        "candlestick": { CandlestickView() },
        "boxplot": { BoxplotView() },
        "sunburst": { SunburstView() },
        "treemap": { TreemapView() },
        "tree": { TreeView() },
        "graph": { GraphView() },
        // Sankey chart view (coordless flow): node Rects + edge ribbon SankeyPaths + node/edge labels;
        //   geometry from the sankey box layout stage. Registered under series subType 'sankey'
        //   (upstream chart/sankey/install.ts `registerChartView(SankeyView)`).
        "sankey": { SankeyView() },
        // Chord chart view (coordless circular flow): node arc Sectors + edge ribbon ChordPaths + node
        //   labels; geometry from the chord circular layout stage. Registered under series subType 'chord'
        //   (upstream chart/chord/install.ts `registerChartView(ChordView)`).
        "chord": { ChordView() },
        // Lines chart view (one Line/BezierCurve per two-point line, or one Polyline per polyline line);
        //   geometry inlined via coord.dataToPoint + the curveness control-point formula (the layout STAGE
        //   is registered/run but the view projects coords itself, like ScatterView/LineView). Registered
        //   under series subType 'lines' (upstream chart/lines/install.ts `registerChartView(LinesView)`).
        "lines": { LinesView() },
        // Gauge chart view (coordless): axis arc color bands, split lines + ticks, tick labels, pointer
        //   needle, anchor, and title/detail text — all computed in render. Registered under series subType
        //   'gauge' (upstream chart/gauge/install.ts `registerChartView(GaugeView)`).
        "gauge": { GaugeView() },
        // Radar chart view (per-item polyline outline + polygon area + vertex symbols); registered under
        //   series subType 'radar' (upstream install.ts `registerChartView(RadarView)`).
        "radar": { RadarView() },
        // ThemeRiver streamgraph view (one Polygon band per layer, on the single coord); geometry from the
        //   themeRiverLayout stage. Registered under series subType 'themeRiver'
        //   (upstream chart/themeRiver/install.ts `registerChartView(ThemeRiverView)`).
        "themeRiver": { ThemeRiverView() },
        // Parallel chart view (one Polyline per data item across the N axes); geometry from
        //   coord.dataToPoint per dimension. Registered under series subType 'parallel'
        //   (upstream chart/parallel/install.ts `registerChartView(ParallelView)`).
        "parallel": { ParallelView() },
        // Map chart view (one CompoundPath per GeoJSON region, filled by the datum value + per-region
        //   legend symbols/labels); geometry from the injected Geo coord + the mapSymbolLayout stage.
        //   Registered under series subType 'map' (upstream chart/map/install.ts `registerChartView(MapView)`).
        "map": { MapView() },
        // Custom chart view (renderItem-driven): builds the scene graph from the user's renderItem closure
        //   return specs (rect/circle/sector/polygon/polyline/line/text/group). Registered under series
        //   subType 'custom' (upstream chart/custom/install.ts `registerChartView(CustomChartView)`).
        "custom": { CustomChartView() }
    ]

    // ------------------------------------------------------------------------
    // setOption — build the GlobalModel, then run the update cycle.
    // Mirrors `ECharts.setOption` → `prepare` + `updateMethods.prepareAndUpdate` in the minimal case:
    //   build a fresh `GlobalModel` via `OptionManager` (the ported option → model pipeline), then
    //   `update()`. Re-`setOption` merge/notMerge semantics are out of scope (each call rebuilds).
    // ------------------------------------------------------------------------
    public func setOption(_ option: [String: Any]) {
        setOption(option, notMerge: false)
    }

    // upstream echarts.ts:770-777 — reuse `this._model` and MERGE unless first call or notMerge.
    //   The default (notMerge:false) merge preserves each SeriesModel instance, so its prior
    //   getData() survives for `data.diff`-driven cross-setOption tween transitions (L5). The
    //   demo-switch host path passes notMerge:true to rebuild a fresh chart per demo.
    public func setOption(_ option: [String: Any], notMerge: Bool) {
        var opt = option
        // Preprocessor from `installSimple.ts`: inject an (empty) grid if x+y axes are present but no
        //   grid was declared, so the axis models can resolve their coord-sys (`getCoordSysModel`).
        if opt["xAxis"] != nil && opt["yAxis"] != nil && opt["grid"] == nil {
            opt["grid"] = [String: Any]()
        }
        // Preprocessor from component/graphic/install.ts: normalize the `graphic` option into its
        //   canonical `[{ elements: [...] }]` shape so GraphicComponentModel can consume it.
        graphicOptionPreprocessor(&opt)
        // Preprocessor from chart/radar/backwardCompat.ts (registerPreprocessor(radarBackwardCompat)):
        //   migrate ec2's `polar` radar option (a `polar` with an `indicator`) into `radar`, and map a
        //   series' `polarIndex` → `radarIndex`. Mutates option.polar/option.radar/option.series in place
        //   (inout write-back, value-type semantics, per the candlestick preprocessor precedent).
        radarBackwardCompat(&opt)
        // Preprocessor from coord/parallel/install.ts (registerPreprocessor(parallelPreprocessor)):
        //   create the `parallelAxis` components from `parallel.parallelAxisDefault` when absent, and merge
        //   the per-axis option from the parallel component. Mutates option.parallel/option.parallelAxis in
        //   place (inout write-back; ECUnitOption == [String: Any], so `&opt` binds directly — the bespoke
        //   `inout ECUnitOption` signature is the same value type, no adapter needed).
        parallelPreprocessor(&opt)
        // Preprocessor from component/visualMap/preprocessor.ts (registerPreprocessor(visualMapPreprocessor)):
        //   array-normalize the `visualMap` option, split ec2 `splitList` into `pieces`, and migrate each
        //   piece's `start`/`end` → `min`/`max`. Mutates option.visualMap in place (inout ECUnitOption).
        visualMapPreprocessor(&opt)
        // Preprocessors from component/marker/installMark{Point,Line,Area}.ts (Phase 52): auto-enable the
        //   master marker component when ANY series declares markPoint/markLine/markArea, so the per-series
        //   inner submodels get instantiated during component build.
        markPointPreprocessor(&opt)
        markLinePreprocessor(&opt)
        markAreaPreprocessor(&opt)
        // Preprocessor from component/brush/install.ts (registerPreprocessor(brushPreprocessor)): turn a
        //   brush component's `toolbox: ['rect','polygon',…]` list into `toolbox.feature.brush.type`, i.e.
        //   put the brush BUTTONS in the toolbar. Those buttons dispatch `takeGlobalCursor` — the way a
        //   user arms the brush paint cursor in the official examples. Self-gates on `option.brush`.
        brushPreprocessor(&opt)
        // Preprocessor from component/timeline/preprocessor.ts (registerPreprocessor(timelinePreprocessor)):
        //   normalize the `timeline` option (ec2-compat: type→axisType, controlPosition→controlStyle.position,
        //   transfer label/itemStyle on each data item). Mutates option.timeline in place (inout ECUnitOption).
        //   NOTE: the baseOption+options[currentIndex] MERGE is NOT done here — it is driven by OptionManager
        //   (parseRawOption splits `{baseOption, options, timeline}`; getTimelineOption merges options[
        //   timelineModel.getCurrentIndex()] over baseOption). This preprocessor only normalizes the timeline
        //   COMPONENT option itself.
        timelinePreprocessor(&opt)
        // Preprocessor from component/aria/preprocessor.ts (registerPreprocessor(ariaPreprocessor)):
        //   migrate the deprecated `aria.show` → `aria.enabled`, and move top-level
        //   `description`/`general`/`series`/`data` under `aria.label`. Mutates option.aria in place.
        //   Must run BEFORE `initBase` stamps the `aria.enabled` default (so `show:false` is honored).
        ariaPreprocessor(&opt)
        // Preprocessor from component/axisPointer/install.ts (registerPreprocessor): always ensure a
        //   global axisPointer option exists (for default settings). tooltip `dependencies:['axisPointer']`
        //   and the axis-tooltip DATA core (modelHelper.collect) both need the AxisPointerModel component
        //   to be instantiated. Upstream forces `option.axisPointer = {}` unconditionally; mirror that.
        //   (The `link` normalization to array is out of the bar/tooltip scope — link-groups are DEFERRED.)
        if opt["axisPointer"] == nil
            || ((opt["axisPointer"] as? [Any])?.isEmpty ?? false) {
            opt["axisPointer"] = [String: Any]()
        }

        // First call or notMerge → fresh GlobalModel + init (upstream `new GlobalModel()`); else
        //   reuse the persistent model and MERGE the new option into it (upstream
        //   `this._model.setOption(option, {replaceMerge})`). GlobalModel.setOption already routes
        //   first-vs-merge internally via its OptionManager (_resetOption → _mergeOption reuses each
        //   component by id and sets __requireNewView on a type change), so reusing the same model
        //   and calling setOption again performs the incremental merge that keeps SeriesModel
        //   instances (and their getData()) alive for transitions.
        if _model == nil || notMerge {
            let ecModel = GlobalModel()
            let om = OptionManager(_api)
            // init(option, parentModel, ecModel, theme, locale, optionManager)
            //   theme: resolved from the `init(theme:)` arg (a registered name or a dict); merged into
            //   the option by GlobalModel.mergeTheme (backgroundColor / textStyle / axis colors /
            //   palette). locale: `createLocaleObject(opts.locale || SYSTEM_LANG)` — the default (EN)
            //   locale Model feeds getLocaleModel() (legend selector, time-axis names, toolbox titles).
            ecModel.`init`(nil, nil, nil, resolveTheme(), resolveLocale(), om)
            ecModel.setOption(opt, nil, [])
            self._model = ecModel
        }
        else {
            self._model!.setOption(opt, nil, [])
        }

        // Sub-project C — build the Scheduler pipelines (upstream `prepare()`, echarts.ts:1675-1676:
        //   `scheduler.restorePipelines(zr, model); scheduler.prepareStageTasks();`). Built lazily on
        //   the first setOption (installOnce() has run in init, so the registries are populated) and
        //   re-primed each setOption. `restorePipelines` rebuilds a per-series pipeline (head = the
        //   series dataTask); `prepareStageTasks` creates the overall/series stage tasks + stubs and
        //   pipes them. `prepareView` (the series RENDER task) is deferred to C2 (ChartView.renderTask
        //   is still a stub). No update() routing yet in C1-T2 — the scheduler is built but unused, so
        //   this is a pure additive change (getTargetSeries's AxisProxy side-effect now runs here at
        //   setOption instead of in update(), where update()'s own getTargetSeries call then no-ops
        //   via the `getAxisProxyFromModel == nil` guard).
        if _scheduler == nil {
            _scheduler = Scheduler(self, _api, ECharts.buildDataProcessorHandlers(), buildVisualHandlers())
        }
        _scheduler.restorePipelines(nil, _model!)
        _scheduler.prepareStageTasks()

        // upstream echarts.ts:779 —
        //   const updateParams = { seriesTransition: transitionOpt, optionChanged: true } as UpdateLifecycleParams;
        //   ... updateMethods.update.call(this, null, updateParams);
        // `optionChanged: true` is exactly what gates universalTransition's 'series:transition' handler
        // (a dispatchAction-driven update leaves it unset → no cross-series morph). `seriesTransition`
        // comes from `setOption`'s `transition` opt, which the port's setOption signature does not carry
        // (PORT-NOTE: `SetOptionOpts.transition` unported — the option-driven finder form; the seriesKey/
        // id-driven form, which is what every ported demo uses, is fully wired).
        update(UpdateLifecycleParams(optionChanged: true))
    }

    // ------------------------------------------------------------------------
    // §UPDATE — faithful stage ORDER of `updateMethods.update` (echarts.ts:1880), minimal bodies.
    // ------------------------------------------------------------------------
    private func update(_ updateParams: UpdateLifecycleParams = UpdateLifecycleParams()) {
        guard let ecModel = _model else { return }          // upstream: if (!ecModel) return;
        let api = _api!

        // (0) resetCachePerECFullUpdate — upstream `updateMethods.update` (echarts.ts:1892) clears the
        //     per-full-update cache at the start of EVERY update cycle. Required for idempotency: a
        //     `dispatchAction`-driven re-render runs update() a 2nd time on the same GlobalModel, and
        //     without this the axis-statistics <axis,series> association maps (+ the DEV duplicate-pair
        //     check in associateSeriesWithAxis) carry stale state and trip an assert.
        resetCachePerECFullUpdate(ecModel)

        // (1) restoreData — re-derive component/series state (upstream echarts.ts:1896
        //   `scheduler.restoreData(ecModel, payload)`). Route through the Scheduler (not bare
        //   `ecModel.restoreData()`): besides `ecModel.restoreData(payload)` (which dirties the PIPELINE
        //   tasks), the scheduler ALSO marks every OVERALL stage task dirty. This is REQUIRED now that
        //   `performDataProcessorTasks` runs the overall tasks (dataZoom filter / legendFilter / map
        //   statistic / axisPointer collect): a dispatchAction-driven 2nd update() does not re-run
        //   prepareStageTasks, so without re-dirtying, the overall tasks would be clean and skip — the
        //   dataZoom/legend/toolbox interactions would silently stop re-filtering. The empty payload
        //   restores ALL series (isNotTargetSeries is false with no seriesIndex/Id/Name), == the old
        //   `ecModel.restoreData()`.
        _scheduler.restoreData(ecModel, Payload(type: ""))

        // (2) performSeriesTasks — perform each series' DATA task through the Scheduler (upstream
        //   echarts.ts:1897 `scheduler.performSeriesTasks(ecModel)` = `seriesModel.dataTask.perform()`).
        //   The dataTask is the HEAD of each series pipeline (restorePipelines pipes it), so `perform()`
        //   runs its reset (`dataTaskReset` — `setData(getRawData().cloneShallow())`) AND threads its
        //   output DOWN the pipeline to the per-series data-processor stage tasks (negativeDataFilter /
        //   data-item legendDataFilter / dataSample). The old hand-called `dataTaskReset(context)` ran
        //   the reset but skipped that threading, so downstream per-series filter tasks received stale/
        //   disconnected input and a legend data-item toggle failed to re-filter on the 2nd update().
        _scheduler.performSeriesTasks(ecModel)

        // (3) coordSysMgr.create — build the Grid coordinate system(s), lay them out on the container
        //     rect, and inject `coordinateSystem` into each series (Grid.create → injectCoordSysByOption).
        _coordSysMgr.create(ecModel, api)
        // upstream echarts.ts:1907 — lifecycle.trigger('coordsys:aftercreate', ecModel, api);
        lifecycle.trigger("coordsys:aftercreate", ecModel, api)

        // (4) performDataProcessorTasks — run every data-processor stage task through the Scheduler
        //   (upstream echarts.ts:1909 `scheduler.performDataProcessorTasks(ecModel, payload)`). The
        //   handlers are assembled in `buildDataProcessorHandlers()` in the SAME order this block used to
        //   hand-call them — dataZoom (FILTER; window calc + filter) → dataStack → axis-statistics captured
        //   processors → negativeDataFilter → data-item legend filters → dataSample → legendFilter (series
        //   show/hide) → graph categoryFilter → map data statistic → axisPointer coordSysAxesInfo — so the
        //   output is unchanged (the ported `_performStageTasks` iterates array order, not `__prio`; a
        //   later task realigns to the real upstream PRIORITY and gates that reorder separately). dataZoom's
        //   AxisProxy was already created by prepareStageTasks' getTargetSeries at setOption, so this only
        //   runs its overallReset. Runs BETWEEN coordSysMgr.create (3) and coordSysMgr.update (5), faithful.
        // updateStreamModes(...) — PORT-NOTE (deferred): skipped (progressive/stream rendering out of scope).
        _scheduler.performDataProcessorTasks(ecModel)

        // (5) coordSysMgr.update — update axis pixel + data extents from the (now processed) series data,
        //     and build the axis tick/label geometry (Grid.update → resize → createAxisBiulders).
        _coordSysMgr.update(ecModel, api)

        // (6) VISUAL — resolve series/data styles (fill/stroke from palette + itemStyle).
        //   KEPT DIRECT (not routed through _scheduler.performVisualTasks): the visual encoders do their
        //   per-datum work in the task PROGRESS callback over `context.data`, which the pipeline threads
        //   from the immediate upstream task's outputData. For visual tasks that upstream is an overall-
        //   processor STUB (dataZoom/dataStack/legendFilter/… stubs are piped into every series pipeline
        //   ahead of the visual tasks), and the ported stub does not thread the series data through as its
        //   outputData under the current dirty/perform ordering, so a routed visual task pulled nil
        //   context.data and skipped encoding (visualMap slices lost their colors). The data-processor and
        //   series stages route fine because their work is in the RESET (reading getData() directly), not
        //   the progress callback. Fixing the stub outputData passthrough end-to-end is C2-level pipeline
        //   work (also required for real progressive render); until then the visual stage stays direct.
        //   See docs/superpowers/specs/2026-07-10-c-scheduler-wiring-design.md (C2 prerequisite).
        performVisualStage(ecModel, api)

        // VISUAL (coordless series own color) — a few coordless series (sunburst) color their data in an
        //   OVERALL visual stage that upstream registers at PRIORITY.VISUAL.CHART (3000), i.e. BEFORE the
        //   visualMap component encoding (PRIORITY.VISUAL.COMPONENT, 4000). These color-only stages need no
        //   pixel layout (only the tree structure / palette), so they run here in the visual stage rather
        //   than bundled with their pixel layout inside render(). Running them BEFORE performVisualMapStage
        //   is REQUIRED for visualMap to win: sunburstVisual `extend`s a fresh palette fill onto the stored
        //   item-visual style, which would otherwise clobber the visualMap-mapped color. See render() (the
        //   matching sunburst LAYOUT stage still runs there — it does need the canvas geometry).
        performCoordlessSeriesVisualStage(ecModel, api)

        // VISUAL (component) — visualMap value->visual encoding. Registered upstream at
        //   PRIORITY.VISUAL.COMPONENT (registerVisual(visualMapEncodingHandlers)), i.e. AFTER each series'
        //   own visual stage above, so the per-datum encoded color OVERWRITES the palette color. Handler #1
        //   walks each target series' data and `setItemVisual`s the mapped color/opacity/symbol; handler #2
        //   emits the `visualMeta` gradient stops (consumed by heatmap/tooltip). This is the KEY deliverable.
        performVisualMapStage(ecModel, api)

        // VISUAL (aria) — accessibility label. Upstream registers `ariaVisualStageHandler` at
        //   PRIORITY.VISUAL.ARIA (component/aria/install.ts) and it sets the container DOM's `aria-label`.
        //   There is no DOM here, so the ported `aria.ariaLabel(...)` RETURNS the generated string and the
        //   driver stores it on the ec instance (exposed via `getAriaLabel()`). Self-gates to `nil` when
        //   aria is disabled (default) / has no series. Pure data + locale — no item layout needed, so it
        //   runs in the visual stage like upstream. See Sources/EChartsKit/component/aria/ariaVisual.swift.
        _ariaLabel = aria.ariaLabel(ecModel, api)

        // VISUAL (aria decal) — upstream `ariaVisual`'s `setDecal()` runs alongside `setLabel()` at
        //   PRIORITY.VISUAL.ARIA (6000). When `aria.decal.show` is enabled it assigns a palette decal to
        //   each series/datum's `decal` visual (getDecalFromPalette). Self-gates when aria/decal disabled.
        aria.setDecal(ecModel, api)

        // VISUAL (decal) — upstream registers `decalVisualStageHandler` at PRIORITY.VISUAL.DECAL (7000),
        //   AFTER the style tasks + aria. It converts each `decal` visual (from itemStyle.decal OR the aria
        //   palette above) into a tiling `Pattern` stored on the datum's `style` visual, which the chart
        //   view bridges onto the element's `pathStyle.decal` (→ Path._decalEl → renderer pattern fill).
        decalVisualStageHandler.overallReset?(ecModel, api, nil)

        // NOTE (brush): upstream runs the brush visual at PRIORITY.VISUAL.BRUSH (5000) — AFTER the LAYOUT
        //   stages (1000–4600). The brush rect selector reads each datum's `getItemLayout` (pixel geometry),
        //   which the driver only populates inside `render()`'s layout stages (bar/scatter/etc.). So the
        //   brush visual CANNOT run here (item layout is still nil at this point); it runs at the end of
        //   `render()`, right before `renderSeries` — see the `brushVisual(...)` call there.

        // background / darkMode (zr.setBackgroundColor / setDarkMode) — PORT-NOTE (platform): the driver exposes a
        //     bare Group; background is a host concern, handled by the native host, not this layer.

        // (7) LAYOUT + RENDER — `render(this, ecModel, api, payload, updateParams)`.
        render(ecModel, api, updateParams)

        // upstream echarts.ts:1937 — lifecycle.trigger('afterupdate', ecModel, api);
        lifecycle.trigger("afterupdate", ecModel, api)
    }

    // ------------------------------------------------------------------------
    // §UPDATE MATRIX (L6) — the lighter update methods `dispatchAction` routes to, per an action's
    //   `update` field, instead of always re-running the full `update()`. Faithful to
    //   `updateMethods.{updateView,updateVisual,updateLayout,updateTransform}` (echarts.ts:2011-2110).
    //   All reuse the persistent views (L5); none re-derive series data (no restoreData /
    //   performSeriesTasks), so the DataStore + coord systems from the last full update() are kept.
    // ------------------------------------------------------------------------

    /// upstream `updateMethods.updateView` (echarts.ts:2011): re-render series/components from the
    /// current (already-processed) data, reusing views, without reprocessing data. In the the
    /// per-series layout runs inside `render()`, so a bare `render()` is the faithful view-only refresh.
    public func updateView() {
        guard let ecModel = _model else { return }
        render(ecModel, _api!)
    }

    /// upstream `updateMethods.updateVisual` (echarts.ts:2033): re-run the visual stages (style /
    /// visualMap / aria / decal) then re-render, reusing views. No data reprocessing.
    public func updateVisual() {
        guard let ecModel = _model else { return }
        let api = _api!
        performVisualStage(ecModel, api)
        performCoordlessSeriesVisualStage(ecModel, api)
        performVisualMapStage(ecModel, api)
        _ariaLabel = aria.ariaLabel(ecModel, api)
        aria.setDecal(ecModel, api)
        decalVisualStageHandler.overallReset?(ecModel, api, nil)
        render(ecModel, api)
    }

    /// upstream `updateMethods.updateLayout` (echarts.ts:2080): re-run layout then re-render. In the
    /// every layout stage runs inside `render()`, so this is the same view-only refresh as
    /// updateView (which is exactly what upstream's updateLayout reduces to once the Scheduler-driven
    /// layout tasks are folded into the render pass).
    public func updateLayout() {
        updateView()
    }

    /// upstream `updateMethods.updateTransform` (echarts.ts:1943): a coordinate-transform-only refresh
    /// (roam / inside-dataZoom pan). Each component/chart view gets its `updateTransform` hook; a view
    /// that returns `false` handled it in place and needs nothing more, otherwise it is re-rendered.
    /// The base hook returns nil (no transform-only path), so a view without a real implementation
    /// falls back to a full render — always correct output, matching upstream's "no hook -> dirty".
    public func updateTransform() {
        guard let ecModel = _model else { return }
        let api = _api!
        let payload = Payload(type: "")
        var needRender = false
        for cv in _componentsViews {
            guard let m = cv.__model else { continue }
            if cv.updateTransform(m, ecModel, api, payload) != false { needRender = true }
        }
        for sv in _chartsViews {
            guard let m = sv.__model else { continue }
            if sv.updateTransform(m, ecModel, api, payload) != false { needRender = true }
        }
        if needRender { render(ecModel, api) }
    }

    // ------------------------------------------------------------------------
    // VISUAL stage — run the ported `visual/style.swift` handlers.
    // ------------------------------------------------------------------------
    private func performVisualStage(_ ecModel: GlobalModel, _ api: ExtensionAPI) {
        // Order mirrors upstream registration (core/echarts.ts:3360-3362): seriesStyleTask (GLOBAL),
        //   then dataStyleTask, then dataColorPaletteTask (both CHART_DATA_CUSTOM). The palette task
        //   MUST run LAST: it reads the `colorFromPalette` item visual that seriesStyleTask sets, and
        //   assigns per-item palette colors for `colorBy:'data'` series (e.g. pie slices). Running it
        //   first (as before) left `colorFromPalette` unset → every pie slice collapsed to one color.
        runSeriesStageHandler(seriesStyleTask, ecModel, api)
        runSeriesStageHandler(dataStyleTask, ecModel, api)
        runOverallStageHandler(dataColorPaletteTask, ecModel, api)

        // VISUAL — graph node/edge colours. Upstream registers `categoryVisual` + `edgeVisual` as normal
        //   VISUAL stage handlers (chart/graph/install.ts), so they run in the visual phase BEFORE any
        //   component/chart view is drawn. They MUST run here — not in the per-series-type block inside
        //   `render()` — because the legend component (renderComponents) resolves each graph CATEGORY's
        //   swatch colour from `categoriesData`'s `style` visual, which `categoryVisual` writes. When these
        //   ran late (after renderComponents), every graph legend swatch fell back to the default black.
        //   Order matters: edgeVisual reads each node's fill, so category must precede edge.
        graphCategoryVisualStageHandler.overallReset?(ecModel, api, nil)
        graphEdgeVisualStageHandler.overallReset?(ecModel, api, nil)
    }

    /// Run an OVERALL_STAGE_TASK handler (has `overallReset`).
    private func runOverallStageHandler(_ handler: StageHandler, _ ecModel: GlobalModel, _ api: ExtensionAPI) {
        handler.overallReset?(ecModel, api, nil)
    }

    // ------------------------------------------------------------------------
    // VISUAL (coordless series own color) — the color-only OVERALL visual stages that upstream registers
    // at PRIORITY.VISUAL.CHART (3000), so they run BEFORE the visualMap component encoding (COMPONENT,
    // 4000). Unlike the layout-coupled series visuals (treemap/graph/sankey, which READ their pixel layout
    // and therefore stay inside render()), these depend only on the series' own data structure (the tree)
    // and the palette, so they run in the visual stage. Ordering them before performVisualMapStage lets the
    // visualMap-mapped color win: sunburstVisual `extend`s a fresh palette fill onto the item-visual style,
    // which would otherwise overwrite the visualMap color if it ran afterwards.
    // ------------------------------------------------------------------------
    private func performCoordlessSeriesVisualStage(_ ecModel: GlobalModel, _ api: ExtensionAPI) {
        // sunburstVisualStageHandler (upstream registerVisual(sunburstVisualStageHandler) — CHART priority).
        //   Colors each tree node from the palette (or its own itemStyle). The matching sunburst LAYOUT stage
        //   still runs in render() (it needs the canvas center/radius geometry). Gated on presence to avoid
        //   walking series data on charts with no sunburst.
        if !ecModel.getSeriesByType(SERIES_TYPE_SUNBURST).isEmpty {
            sunburstVisualStageHandler.overallReset?(ecModel, api, nil)
        }
    }

    // ------------------------------------------------------------------------
    // VISUAL (component) stage — run the `visualMapEncodingHandlers`. Each is a `createOnAllSeries` reset
    // task whose reset returns EITHER a single `StageHandlerProgressExecutor` OR an ARRAY of them
    // (handler #1 pushes one executor per matching visualMap component). Upstream the Scheduler pipes each
    // returned executor's `progress` over the data chunks; here it is a single synchronous full-range pass.
    // Handler #2's reset does its work inline (setVisual('visualMeta', ...)) and returns nil.
    // ------------------------------------------------------------------------
    private func performVisualMapStage(_ ecModel: GlobalModel, _ api: ExtensionAPI) {
        for handler in visualMapEncodingHandlers {
            guard let reset = handler.reset else { continue }
            ecModel.eachSeries { seriesModel, _ in
                let result = reset(seriesModel, ecModel, api, nil)
                // Normalize the reset result to a list of executors.
                var executors: [StageHandlerProgressExecutor] = []
                if let one = result as? StageHandlerProgressExecutor {
                    executors = [one]
                }
                else if let many = result as? [StageHandlerProgressExecutor] {
                    executors = many
                }
                guard !executors.isEmpty else { return }

                let data = seriesModel.getData()
                let count = data.count()
                for executor in executors {
                    if let dataEach = executor.dataEach {
                        for i in 0..<count { dataEach(data, Double(i)) }
                    }
                    else if let progress = executor.progress {
                        var cursor = 0
                        let next: TaskDataIteratorNext = {
                            if cursor < count {
                                let v = Double(cursor); cursor += 1; return v
                            }
                            return nil
                        }
                        let params = StageHandlerProgressParams(
                            start: 0, end: Double(count), count: Double(count), next: next
                        )
                        progress(params, data)
                    }
                }
            }
        }
    }

    /// Run a SERIES_STAGE_TASK handler (`reset` per series, then drive its returned executor over the
    /// data range). Upstream the Scheduler drives `progress`/`dataEach` over data chunks; here it is a
    /// single synchronous pass over `[0, data.count())` (no progressive chunking — documented).
    private func runSeriesStageHandler(_ handler: StageHandler, _ ecModel: GlobalModel, _ api: ExtensionAPI) {
        guard let reset = handler.reset else { return }
        ecModel.eachSeries { seriesModel, _ in
            // seriesType gate (handler.seriesType) — only run for matching series.
            if let st = handler.seriesType, seriesModel.subType != st {
                return
            }
            guard let executor = reset(seriesModel, ecModel, api, nil) as? StageHandlerProgressExecutor else {
                return
            }
            let data = seriesModel.getData()
            let count = data.count()
            if let dataEach = executor.dataEach {
                for i in 0..<count {
                    dataEach(data, Double(i))
                }
            }
            else if let progress = executor.progress {
                // Build a single full-range params (upstream `TaskProgressParams` has start/end/count/next).
                // Upstream the Scheduler supplies `params.next` (a data-index iterator); handlers such as
                // the bar per-item layout (`createProgressiveLayout`'s progress) loop `while (dataIndex =
                // params.next())`. Without a `next` iterator that loop never runs and the handler is a
                // silent no-op — so provide a full-range [0, count) iterator here.
                var cursor = 0
                let next: TaskDataIteratorNext = {
                    if cursor < count {
                        let v = Double(cursor)
                        cursor += 1
                        return v
                    }
                    return nil
                }
                let params = StageHandlerProgressParams(start: 0, end: Double(count), count: Double(count), next: next)
                progress(params, data)
            }
        }
    }

    // ------------------------------------------------------------------------
    // render — `render` (echarts.ts:2430): allocateZlevels (skip) → renderComponents → renderSeries.
    // LAYOUT runs just before series render (upstream layout tasks are part of the visual-task pipe;
    // here the bar cross-series layout is invoked explicitly right before `renderSeries`).
    // ------------------------------------------------------------------------
    private func render(_ ecModel: GlobalModel, _ api: ExtensionAPI,
                        _ updateParams: UpdateLifecycleParams = UpdateLifecycleParams()) {
        // allocateZlevels(ecModel) — PORT-NOTE skip (single grid + one series; default z ordering).

        // View REUSE (L5): the driver no longer wipes root + the view registries each render.
        //   `prepareView` now performs upstream's mark-and-sweep (echarts.ts:1687-1770): every view
        //   is marked not-alive, re-marked alive if its model still resolves it (reused by
        //   `_ec_<id>_<type>`), and `sweepDeadViews` disposes any left dead. This keeps a reused
        //   view's prior element tree + `_data` so its `data.diff`/`updateProps` can tween across a
        //   merge-mode `setOption`. The demo-switch host path passes `notMerge:true`, which installs
        //   a fresh GlobalModel whose brand-new models force fresh views (old ones swept) — so a
        //   demo switch still rebuilds cleanly with no stale-view bleed.

        // BACKGROUND — upstream `echarts._updateBackground` calls `zr.setBackgroundColor(backgroundColor)`
        //   (a painter-level clear color). The driver renders into a bare Group and has no painter clear
        //   hook (that is a host concern, e.g. CALayerPainter's white), so instead draw the resolved
        //   top-level `backgroundColor` as a full-canvas Rect BEHIND everything. Now that render() no longer
        //   wipes `root`, the prior bg rect must be removed/reused each render so it never accumulates.
        //   Transparent/absent → no rect (the host clear shows through, preserving the default white).
        if let old = _bgRect { _ = root.remove(old); _bgRect = nil }
        // upstream `backgroundColor` is a full `ZRColor`: a string, OR a gradient/pattern OBJECT
        //   (`{image, repeat}` / `{type:'linear'|'radial', …}`). The string arm is bridged to
        //   `.string`; the object arm goes through `zrPaintFromStyleValue` (the same option→ZRColor
        //   bridge the series fills use — now pattern-aware), so a textured page background (pie-pattern's
        //   repeated PNG tile) or a gradient background is honored instead of falling through to white.
        let bgRaw = ecModel.get("backgroundColor", true)
        var bgFill: ZRenderKit.ZRColor? = nil
        if let bg = bgRaw as? String {
            if !bg.isEmpty, bg != "transparent", bg != "rgba(0,0,0,0)" {
                bgFill = .string(bg)
            }
        } else if bgRaw != nil {
            bgFill = zrPaintFromStyleValue(bgRaw)
        }
        if let bgFill = bgFill {
            var shape = RectShape()
            shape.x = 0
            shape.y = 0
            shape.width = _width
            shape.height = _height
            // The style MUST be a typed `PathStyleProps`. `Path`'s prop init does
            // `(value as? PathStyleProps) ?? PathStyleProps()` — a `[String: Any]` casts to nil there,
            // silently yielding an EMPTY style, which then falls back to zrender's DEFAULT_PATH_STYLE
            // whose fill is `#000`. So the background rect was painted BLACK no matter what the option
            // said: `backgroundColor: '#fff'` came out black (sankey-itemstyle), and the maps'
            // `'#404a59'` came out black too. It was the single biggest source of native-vs-echarts.js
            // divergence in the official-examples sweep.
            var bgStyle = PathStyleProps()
            bgStyle.fill = bgFill
            let bgRect = Rect([
                "shape": shape as PathShape,
                "style": bgStyle,
                "silent": true,
                "z2": -Double.greatestFiniteMagnitude
            ])
            _ = root.add(bgRect)
            _bgRect = bgRect
        }

        prepareView(isComponent: true, ecModel: ecModel, api: api)
        prepareView(isComponent: false, ecModel: ecModel, api: api)
        sweepDeadViews(ecModel, api)

        // updateStreamModes (echarts.ts:680 — run after performDataProcessorTasks, before the layout
        //   stage and renderSeries): compute each series' `pipelineContext` (large / progressiveRender)
        //   off the now-populated data. MUST precede the bar layout below — barGrid's `isInLargeMode`
        //   reads `pipelineContext.large` to decide whether to pack `largePoints` (which
        //   BarView._renderLarge / LargeBarPath then draw), and every series' render reads
        //   `pipelineContext.large` for its large-draw branch. The port had DEFERRED this pass, so
        //   pipelineContext.large stayed at its default `false` and no `large: true` series ever took its
        //   large path. Views are resolved (prepareView above), data is ready (update() ran the data +
        //   processor tasks) — both invariants updateStreamModes needs.
        ecModel.eachSeries { seriesModel, _ in
            if let chartView = self._chartViewByModel[ObjectIdentifier(seriesModel)] {
                self._scheduler.updateStreamModes(seriesModel, chartView)
            }
        }

        renderComponents(ecModel, api)

        // LAYOUT — bar cross-series layout (sets bandWidth/offset/size on each series' data layout).
        //   Depends on the axis statistics computed in stage (4).
        ECharts._barLayoutHandler.overallReset?(ecModel, api, nil)
        // LAYOUT (per item) — the bar PROGRESSIVE_LAYOUT handler computes each bar's x/y/width/height
        //   from bandWidth/offset/size + the cartesian `dataToPoint`, and stores it via
        //   `data.setItemLayout`. This is a SERIES_STAGE_TASK (has `reset`), so drive it through the same
        //   `runSeriesStageHandler` used for the visual stages (the `next`-iterator fix above makes its
        //   `progress` executor actually iterate the data). `BarView.getLayoutCartesian2D` consumes it.
        runSeriesStageHandler(ECharts._barProgressiveLayoutHandler, ecModel, api)

        // LAYOUT — polar bar sector layout (upstream `registerLayout(barLayoutPolarStageHandler)`). An
        //   OVERALL stage: for each polar axis carrying bar series it computes bar width/offset sharing +
        //   stacking, then each datum's Sector geometry (cx/cy/r0/r/startAngle/endAngle/clockwise) via the
        //   polar `dataToCoord`, storing it with `data.setItemLayout`. `BarView.getLayoutPolar` reads it
        //   back. Runs unconditionally (a no-op when no polar bar series exist — `eachAxisOnKey` yields
        //   nothing). Mirrors the two-arg overall handlers above (pie/funnel).
        barLayoutPolar(ecModel)

        // LAYOUT — pictorialBar cross-series + per-item layout (upstream chart/bar/installPictorialBar.ts).
        //   Same two stages as bar (bandWidth/offset/size, then each item's rect x/y/width/height), gated on
        //   the 'pictorialBar' series type. PictorialBarView.render reads the per-item rect via
        //   data.getItemLayout to size each symbol to its bar.
        //   GUARD: only run when a pictorialBar series is actually present. The cross-series bar-grid
        //   overallReset re-divides the axis band across bar-ish series and rewrites their layout; running
        //   it a SECOND time (after the plain-bar handler above) corrupts plain bar rects on a chart that
        //   has no pictorialBar at all. Gating on presence keeps plain bar charts intact while still laying
        //   out pictorialBar when it is used.
        if !ecModel.getSeriesByType(SERIES_TYPE_PICTORIAL_BAR).isEmpty {
            ECharts._pictorialBarLayoutHandler.overallReset?(ecModel, api, nil)
            runSeriesStageHandler(ECharts._pictorialBarProgressiveLayoutHandler, ecModel, api)
        }

        // LAYOUT — pie angle/radius layout (upstream `registerLayout(pieLayout)`). Pie has no cartesian
        //   coord, so `_coordSysMgr` never injects geometry; this OVERALL stage computes each datum's
        //   start/end angle + r0/r via `getCircleLayout` and stores it with `data.setItemLayout`, which
        //   `PieView.render` reads back. Bare 2-arg handler (like the bar layout handlers above).
        pieLayout(ecModel, api)

        // LAYOUT — funnel piece polygons (upstream `registerLayout(funnelLayoutStageHandler)`). Like pie,
        //   funnel is box-usage with no cartesian coord; this OVERALL stage computes each piece's 4-corner
        //   `points` (via createBoxLayoutReference + linearMap) and stores it with `data.setItemLayout`,
        //   which `FunnelView.render` reads back.
        funnelLayout(ecModel, api)

        // LAYOUT + VISUAL — candlestick. Upstream registers `candlestickLayout` (a SERIES_STAGE_TASK that
        //   computes each candle's 8-point `ends` + `sign` from the cartesian `dataToPoint`) and
        //   `candlestickVisual` (colors body/whiskers bull/bear FROM `itemLayout.sign`). candlestickVisual
        //   READS the sign written by candlestickLayout, so — unlike the generic visual stage, which runs
        //   before layout — the layout MUST run first. Upstream orders them by pipeline priority (layout
        //   before visual); the driver reproduces that by running BOTH here (layout, then visual),
        //   after the generic performVisualStage (candlestickVisual only extends fill/stroke onto the
        //   existing item-visual style, so running it last is correct). Both are SERIES_STAGE_TASKs.
        runSeriesStageHandler(candlestickLayout, ecModel, api)
        runSeriesStageHandler(candlestickVisual, ecModel, api)

        // LAYOUT — boxplot box/whisker geometry (upstream `registerLayout(boxplotLayoutStageHandler)`).
        //   An OVERALL stage (cross-series offset/width from the axis bandWidth statistics); computes each
        //   datum's `ends` + `initBaseline` via `dataToPoint` and stores it with `data.setItemLayout`,
        //   which `BoxplotView.render` reads back. Colors come from the generic visual stage
        //   (visualDrawType:'stroke'), so no dedicated boxplot visual handler is needed. Bare 1-arg handler.
        boxplotLayout(ecModel)

        // LAYOUT + VISUAL — sunburst. Upstream registers `sunburstLayoutStageHandler` (an OVERALL stage
        //   that computes each tree node's sector angle/radius from `center`/`radius`) and
        //   `sunburstVisualStageHandler` (an OVERALL stage that colors each node). Sunburst is coordless
        //   (hierarchical, box-like usage like pie); SunburstView reads the per-node layout back. Both are
        //   OVERALL stage handlers — invoke their `overallReset` directly (like the pie layout stage).
        //   sunburstVisualStageHandler (the color stage) is NOT run here: it must precede the visualMap
        //   component encoding (or its palette fill would clobber the visualMap-mapped color), so it runs in
        //   performCoordlessSeriesVisualStage — BEFORE performVisualMapStage — instead. Only the geometry
        //   LAYOUT stage (which needs the canvas center/radius) stays in render().
        sunburstLayoutStageHandler.overallReset?(ecModel, api, nil)

        // LAYOUT + VISUAL — treemap. Upstream registers `treemapLayout` (a SERIES_STAGE_TASK whose `reset`
        //   computes each node's rect + area/isInView/invisible) and `treemapVisual` (a SERIES_STAGE_TASK
        //   whose `reset` colors each node FROM that layout). Like candlestick, treemapVisual READS the
        //   layout, so the layout MUST run first; both are SERIES_STAGE_TASKs (reset does the full work and
        //   returns nil), so drive them through `runSeriesStageHandler` (layout, then visual).
        runSeriesStageHandler(treemapLayout, ecModel, api)
        runSeriesStageHandler(treemapVisual, ecModel, api)

        // LAYOUT + VISUAL — tree. Upstream registers `treeLayout` (a 2-arg OVERALL layout fn that computes
        //   each node's x/y via the non-layered tidy-tree walk) and `treeVisualStageHandler` (an OVERALL
        //   stage that sets per-node symbol colors). Tree is coordless (hierarchical, box-usage); TreeView
        //   reads the per-node layout back. `treeLayout` is a bare 2-arg fn (like pie/sunburst layout); the
        //   visual is an OVERALL stage handler.
        treeLayout(ecModel, api)
        treeVisualStageHandler.overallReset?(ecModel, api, nil)

        // LAYOUT + VISUAL — graph. Upstream registers two layout stage handlers
        //   (graphCircularLayoutStageHandler for `layout:'circular'`, graphSimpleLayoutStageHandler for
        //   `layout:'none'`/coord-sys), and two visual stage handlers (graphCategoryVisualStageHandler
        //   colors nodes, graphEdgeVisualStageHandler colors edges FROM the node fill). Each layout
        //   handler self-gates on the series `layout` option, so both run every render (only the matching
        //   one does work). GraphView reads each node's [x,y] + each edge's point list from the layout.
        //   The edge visual MUST run AFTER the category visual (edge source/target stroke reads node
        //   fill). All four are OVERALL stage handlers (like sunburst/tree visual).
        // COORD SYS — upstream registers the graph's roam `View` coordinate system via a coord-sys creator
        //   (`registerCoordinateSystem('view', View)` + `createViewCoordSys`) that runs before layout. That
        //   full `View` is deferred (roam §5); `createViewCoordSys` here assigns a stand-in view coord sys
        //   (GraphViewCoordSys) onto each graph series so the layout stages can read its bounding rect.
        //   MUST run before the layout handlers below (circularLayout force-derefs the coord sys).
        createViewCoordSys(ecModel, api)
        graphCircularLayoutStageHandler.overallReset?(ecModel, api, nil)
        graphSimpleLayoutStageHandler.overallReset?(ecModel, api, nil)
        // `layout:'force'` — iterative physics simulation (graphForceLayoutStageHandler). Self-gates on
        //   the series `layout` option; for a static frame it settles the simulation synchronously (the
        //   live per-frame tick is a PORT-NOTE (deferred): unported — see forceLayout.swift). Runs alongside the other two.
        graphForceLayoutStageHandler.overallReset?(ecModel, api, nil)
        // graphCategoryVisualStageHandler / graphEdgeVisualStageHandler are now run in `performVisualStage`
        //   (the visual phase, before renderComponents) so the legend can read the category swatch colours.
        //   See the note there. They are intentionally NOT re-run here (a second pass would re-walk the
        //   palette; keeping a single authoritative pass in the visual phase matches upstream).

        // LAYOUT + VISUAL — sankey. Upstream registers `sankeyLayoutStageHandler` (an OVERALL box-layout
        //   stage that computes each node's {x,y,dx,dy} column/height + each edge's {sy,ty,dy} ribbon
        //   offsets, and sets `seriesModel.layoutInfo`) and `sankeyVisualStageHandler` (an OVERALL stage
        //   that colors each node FROM `node.getLayout().value`, and each edge from its lineStyle). Sankey
        //   is coordless (box usage, no cartesian coord); SankeyView reads the per-node/per-edge layout
        //   back. The visual READS the value written by the layout, so — like candlestick/treemap — the
        //   layout MUST run first. `sankeyLayout` is a bare 2-arg fn (like graph/funnel layout); the
        //   visual is an OVERALL stage handler.
        sankeyLayout(ecModel, api)
        sankeyVisualStageHandler.overallReset?(ecModel, api, nil)

        // LAYOUT — chord circular arc layout (upstream `registerLayout(PRIORITY.VISUAL.POST_CHART_LAYOUT,
        //   chordCircularLayoutStageHandler)`). Chord is coordless (box usage, no cartesian coord; reuses
        //   the ported Graph + createGraphFromNodeEdge like Sankey/Graph). This OVERALL stage computes each
        //   node's arc {cx,cy,r0,r,startAngle,endAngle,clockwise,value,ratio,angle} + each edge's ribbon
        //   {s1,s2,t1,t2,sStartAngle,sEndAngle,tStartAngle,tEndAngle,cx,cy,r,clockwise,value} via
        //   getCircleLayout, storing them on node/edge getLayout(). ChordView reads the per-node/per-edge
        //   layout back; getDataParams reads `node.getLayout().value`. `chordCircularLayout` is a bare
        //   2-arg fn (like graph/sankey layout); the stage-handler wrapper exists for the upstream registrar
        //   but the driver invokes it directly (mirrors sankeyLayout).
        chordCircularLayout(ecModel, api)

        // LAYOUT — lines per-item point projection (upstream `registerLayout(linesLayout)`). A
        //   SERIES_STAGE_TASK (seriesType 'lines') whose `reset`→`progress` maps each line's data-space
        //   coords through the cartesian `dataToPoint` (plus the quadratic curveness control point) and
        //   stores it with `data.setItemLayout(i, pts)`. Same wiring as candlestickLayout. `LinesView.render`
        //   inlines the same math (like ScatterView/LineView), so the view does not strictly depend on this
        //   stage, but it is run here for fidelity to the upstream pipeline. Only cartesian2d is handled
        //   (polar/geo/calendar are PORT-NOTE (deferred): unported in linesLayout).
        runSeriesStageHandler(linesLayout, ecModel, api)

        // LAYOUT — radar point rings (upstream `registerLayout(radarLayoutStageHandler)`). Radar HAS a
        //   (non-cartesian) coordinate system, already built + updated by `_coordSysMgr.create`/`.update`
        //   (update() stages 3/5). This OVERALL stage maps each datum's per-indicator values through
        //   `coordSys.dataToPoint` into a CLOSED point ring (axes+1 points, last == copy of first) and
        //   stores it with `data.setItemLayout`, which `RadarView.render` reads back. Bare 1-arg handler
        //   (like boxplotLayout); the radarLayoutStageHandler wrapper exists for the upstream registrar,
        //   but the driver invokes `radarLayout(ecModel)` directly (mirrors pieLayout).
        radarLayout(ecModel)

        // LAYOUT — themeRiver stream bands (upstream `registerLayout(themeRiverLayoutStageHandler)`).
        //   ThemeRiver HAS a (non-cartesian) single coordinate system, already built + updated by
        //   `_coordSysMgr.create`/`.update` (update() stages 3/5). This OVERALL stage reads the Single coord
        //   rect + axis orient and writes each datum's {layerIndex,x,y0,y} band point (+ a "layoutInfo" rect/
        //   boundaryGap) via `data.setItemLayout`/`data.setLayout`, which `ThemeRiverView.render` reads back
        //   to draw one Polygon per layer. Run AFTER the coord update (it casts seriesModel.coordinateSystem
        //   to Single). `themeRiverLayoutStageHandler` wraps this for the upstream registrar, but the
        //   driver invokes `themeRiverLayout(ecModel, api)` directly (mirrors sankeyLayout / radarLayout).
        themeRiverLayout(ecModel, api)

        // LAYOUT — map region-center symbols (upstream `registerLayout(mapSymbolLayoutStageHandler)`). For
        //   each map-series group with its own geo, this OVERALL stage projects each region center through
        //   the injected Geo (`geo.dataToPoint(region.getCenter())`) and stores `{point, offset}` on the
        //   per-series `originalData` item layout (the legend symbol positions), then stamps `showLabel` on
        //   the main series' data so label-less regions still get a name label. Reads `originalData` (set by
        //   the mapDataStatistic processor in stage 4) + the Geo coord (set by geoCreator in stage 3), so it
        //   runs here after both. `mapSymbolLayoutStageHandler` wraps this for the upstream registrar, but the
        //   driver invokes `mapSymbolLayout(ecModel)` directly (mirrors sankeyLayout / radarLayout).
        mapSymbolLayout(ecModel)

        // VISUAL — parallel per-line opacity (upstream `registerVisual(PRIORITY.VISUAL.BRUSH, parallelVisual)`).
        //   Parallel HAS a coordinate system, already built + updated by `_coordSysMgr.create`/`.update`
        //   (update() stages 3/5). This SERIES_STAGE_TASK sets each line's item-visual `style.opacity` from
        //   the (deferred) active-state → in the static-render phase every row is 'normal', giving each
        //   polyline the `lineStyle.opacity`. ParallelView.render reads that item-visual style back. Run
        //   AFTER the generic performVisualStage (it only extends `opacity` onto the existing style bag).
        runSeriesStageHandler(parallelVisual, ecModel, api)

        // LAYOUT — point-series pixel projection (upstream `registerLayout(layoutPoints('scatter'))` in
        //   chart/scatter/install.ts and `layoutPoints('effectScatter')` in chart/effectScatter/install.ts).
        //   A SERIES_STAGE_TASK whose `progress` runs each datum through `coordSys.dataToPoint` and stores
        //   the pixel point with `data.setItemLayout(i, point)`. ScatterView/EffectScatterView inline the
        //   same math for drawing, but `SeriesModel#brushSelector` reads `data.getItemLayout(dataIndex)` —
        //   so WITHOUT this stage a brush over a scatter selects nothing at all.
        //   Upstream also registers `layoutPoints('line', true)` (chart/line/install.ts), whose
        //   `forceStoreInTypedArray` branch writes the flat `data.setLayout('points')` buffer. LineView's
        //   faithful render path (getVisualGradient / _initSymbolLabelAnimation / lineAnimationDiff /
        //   _doUpdateAnimation / endLabel / clip) all read `data.getLayout('points')`, so the line stage
        //   IS wired here now (write-only `setLayout('points')`; line is not brushable, so no selector
        //   depends on it). The polar branch is handled by `pointsLayoutCoordSys` (see layout/points.swift).
        runSeriesStageHandler(pointsLayout("line", true), ecModel, api)
        runSeriesStageHandler(pointsLayout("scatter"), ecModel, api)
        runSeriesStageHandler(pointsLayout("effectScatter"), ecModel, api)

        // VISUAL (brush) — upstream PRIORITY.VISUAL.BRUSH (5000), the same priority as parallelVisual above,
        //   i.e. AFTER every layout stage (so each datum's `getItemLayout` pixel geometry exists for the rect
        //   selector) and BEFORE `renderSeries` draws (so the in/out-of-brush item-visual color the encoder
        //   writes is picked up by the draw). `brushVisual` self-gates (eachComponent("brush") → no-op when
        //   absent), rebuilds each area's pixel range from its coordRange (layoutCovers), tests every series
        //   datum against the rect selector, and marks inBrush/outOfBrush — recoloring the unselected to the
        //   `outOfBrush` color (dim).
        //   The PAYLOAD is threaded through (upstream `visualEncoding.brushVisual(ecModel, api, payload)`):
        //   it is what arms the paint cursor (`takeGlobalCursor` -> `brushModel.setBrushOption`) and what
        //   gates the `brushSelect` dispatch (upstream never fires `brushselected` for a plain setOption).
        brushVisual(ecModel, api, _payload)

        renderSeries(ecModel, api, updateParams)

        // LABEL LAYOUT — upstream registers `installLabelLayout`, which runs the
        //   `series:layoutlabels` lifecycle stage AFTER `renderSeries` (once every series view has
        //   attached its label textContents). `LabelManager.runLabelLayoutStage` applies each series'
        //   user `labelLayout` option (x / y / rotate / align / moveOverlap / hideOverlap) and resolves
        //   cross-label overlap globally (rotated-rect OBB `hideOverlap`). It self-gates: a chart whose
        //   series set no `labelLayout` option collects zero labels and the stage is a no-op, so charts
        //   without overlapping labels are unaffected (existing pie/bar/scatter label PNGs unchanged).
        LabelManager.runLabelLayoutStage(_chartsViews, api)
    }

    // prepareView — get-or-create a view per component/series, add its group to the root + storage.
    // Faithful reduction of `prepareView` (echarts.ts:1687): no reuse across notMerge/replaceMerge
    // (each setOption rebuilds), no dispose of dead views (fresh model each call).
    private func prepareView(isComponent: Bool, ecModel: GlobalModel, api: ExtensionAPI) {
        // (a) Mark every existing view of this kind not-alive (upstream prepareView 1695-1697).
        //     doPrepare re-marks the reused/created ones alive; sweepDeadViews disposes the rest.
        if isComponent { for v in _componentsViews { v.__alive = false } }
        else { for v in _chartsViews { v.__alive = false } }

        func doPrepare(_ model: ComponentModel) {
            // By default a view is reused if possible (same id + type) so a merge-mode setOption can
            //   transition. `__requireNewView` (set by _mergeOption on a brand-new/replaced model)
            //   forces a fresh view. The flag must not work twice (upstream 1712-1714).
            let requireNewView = model.__requireNewView ?? false
            model.__requireNewView = false
            let viewId = "_ec_\(model.id)_\(model.type)"   // upstream 1716: keyed by model.id (+type)
            if isComponent {
                let existing = requireNewView ? nil : _componentsMap[viewId]
                let view = existing ?? {
                    // getClass(classType.main, classType.sub) → factory keyed by FULL type first (subtype
                    //   dispatch, e.g. 'visualMap.continuous'), then by mainType (e.g. 'legend' whose full
                    //   type is 'legend.plain'). Most components have full type == mainType, so the fallback
                    //   is what they resolve through.
                    guard let factory = _componentViewFactories[model.type] ?? _componentViewFactories[model.mainType] else {
                        // PORT-NOTE: no component view registered for this mainType — skip (a general fallback guard).
                        return nil as ComponentView?
                    }
                    let v = factory()
                    v.`init`(ecModel, api)
                    _componentsMap[viewId] = v
                    _componentsViews.append(v)
                    _ = root.add(v.group)
                    storage.addRoot(v.group)
                    return v
                }()
                guard let componentView = view else { return }
                model.__viewId = viewId
                componentView.__alive = true
                componentView.__model = model
                _componentViewByModel[ObjectIdentifier(model)] = componentView
            }
            else {
                guard let seriesModel = model as? SeriesModel else { return }
                let existing = requireNewView ? nil : _chartsMap[viewId]
                let view = existing ?? {
                    // ChartView.getClass(classType.sub) → factory keyed by series subType.
                    guard let factory = _chartViewFactories[seriesModel.subType] else {
                        // PORT-NOTE: no chart view registered for this subType — skip (a general fallback guard).
                        return nil as ChartView?
                    }
                    let v = factory()
                    v.init_(ecModel, api)
                    _chartsMap[viewId] = v
                    _chartsViews.append(v)
                    _ = root.add(v.group)
                    storage.addRoot(v.group)
                    return v
                }()
                guard let chartView = view else { return }
                model.__viewId = viewId
                chartView.__alive = true
                chartView.__model = seriesModel
                _chartViewByModel[ObjectIdentifier(seriesModel)] = chartView
                // upstream: `scheduler.prepareView(view, model, ...)` builds the series pipeline and sets
                //   `seriesModel.pipelineContext` (progressive/large flags read by `BarView._updateDrawMode`
                //   at BarView.swift:221). With the Scheduler unported, set a minimal non-progressive,
                //   non-large context directly.
                seriesModel.pipelineContext = PipelineContext(progressiveRender: false, large: false, modDataCount: nil)
            }
        }

        if isComponent {
            ecModel.eachComponent({ (mainType, model, _) in
                if mainType != "series" { doPrepare(model) }
            })
        }
        else {
            ecModel.eachSeries { seriesModel, _ in doPrepare(seriesModel) }
        }
    }

    // Dispose views left __alive == false after both prepareView passes: their model was removed or
    // replaced by a different-type/brand-new model, so the old view instance is orphaned. Faithful to
    // prepareView's tail sweep (echarts.ts:1754-1769) + renderSeries' dead-chart remove (2445-2449).
    private func sweepDeadViews(_ ecModel: GlobalModel, _ api: ExtensionAPI) {
        var i = 0
        while i < _componentsViews.count {
            let v = _componentsViews[i]
            if v.__alive != true {
                _ = root.remove(v.group)
                storage.delRoot(v.group)
                v.dispose(ecModel, api)
                _componentsViews.remove(at: i)
                for (k, vv) in _componentsMap where vv === v { _componentsMap.removeValue(forKey: k) }
                for (k, vv) in _componentViewByModel where vv === v { _componentViewByModel.removeValue(forKey: k) }
            } else {
                i += 1
            }
        }
        i = 0
        while i < _chartsViews.count {
            let v = _chartsViews[i]
            if !v.__alive {
                v.remove(ecModel, api)          // upstream renderSeries also calls chart.remove for a dead view
                _ = root.remove(v.group)
                storage.delRoot(v.group)
                v.dispose(ecModel, api)
                _chartsViews.remove(at: i)
                for (k, vv) in _chartsMap where vv === v { _chartsMap.removeValue(forKey: k) }
                for (k, vv) in _chartViewByModel where vv === v { _chartViewByModel.removeValue(forKey: k) }
            } else {
                i += 1
            }
        }
    }

    // renderComponents (echarts.ts:2452) — minimal: clearStates/updateZ/updateStates dropped (states
    // system deferred). Just `componentView.render(model, ecModel, api, payload)`.
    // upstream `clearStates(model, view)` (echarts.ts:2667): before a (possibly reused) view re-renders,
    //   reset its rendered elements to the normal state so a lingering emphasis/select from before a
    //   merge-mode setOption does not survive into the new render. Runs BEFORE render (walks the OLD
    //   element tree). Skips elements fading out (a leave-scoped animator) so their fade is not
    //   interrupted — the port's `isElementRemoved` also keys off `__zr == nil`, but in the headless
    //   driver every element has a nil `__zr`, so only the leave-animator branch is meaningful here.
    private func clearRenderedStates(_ eachRendered: (@escaping (Element) -> Bool) -> Void) {
        eachRendered { el in
            if el.animators.contains(where: { $0.scope == "leave" }) { return false }
            if let tc = el.getTextContent() { tc.stateTransition = nil }
            if let tg = el.getTextGuideLine() { tg.stateTransition = nil }
            el.stateTransition = nil
            if el.hasState() {
                el.prevStates = el.currentStates
                el.clearStates()
            } else if el.prevStates != nil {
                el.prevStates = nil
            }
            return false
        }
    }

    // upstream `updateStates(model, view)` (echarts.ts:2697): AFTER render, for each rendered element that
    //   has an emphasis state, save its NORMAL fill/stroke via `savePathStates`. This is the seam that
    //   makes hover-emphasis VISIBLE: the default-emphasis stateProxy (`createEmphasisDefaultState`) LIFTS
    //   (brightens) the saved normal fill when a datum has no explicit `emphasis.itemStyle`. Without this
    //   save, `getSavedStates(el).normalFill` is nil, the lift is skipped, the emphasis style stays empty,
    //   and hovering enters the emphasis state but the element is visually unchanged (the "no hover effect"
    //   bug). Runs after `clearRenderedStates` reset each element to normal, so `pathStyle.fill` is the
    //   normal (un-lifted) colour here. Skips elements fading out (a leave-scoped animator).
    private func updateRenderedStates(_ eachRendered: (@escaping (Element) -> Bool) -> Void) {
        eachRendered { el in
            guard el.states["emphasis"] != nil else { return false }
            if el.animators.contains(where: { $0.scope == "leave" }) { return false }
            if let p = el as? Path { states.savePathStates(p) }
            return false
        }
    }

    private func renderComponents(_ ecModel: GlobalModel, _ api: ExtensionAPI) {
        // upstream: `renderComponents(ecModel, api, payload)` — the in-flight action payload is handed to
        //   every component view's `render`. Views read it to skip work they themselves caused: BrushView
        //   compares `payload.$from` with its own model id so a cover being DRAGGED is not rebuilt underneath
        //   the drag. The driver stashes it in `_payload` for the duration of a dispatch (see doDispatchAction).
        let payload = _payload ?? Payload(type: "")
        for componentView in _componentsViews {
            guard let model = componentView.__model else { continue }
            // upstream renderComponents wraps render with clearStates (before) — reset a reused view.
            clearRenderedStates(componentView.eachRendered)
            componentView.render(model, ecModel, api, payload)
            // upstream echarts.ts renderComponents runs `updateZ(model, view)` after each render — set
            //   every rendered element's z/zlevel from the model. Coordinate components default z:0.
            updateZ(model, componentView.group, 0)
            // upstream renderComponents `updateStates(model, view)` (echarts.ts:2464) — save each
            //   emphasis-capable element's normal fill so hover lifts it (see updateRenderedStates).
            updateRenderedStates(componentView.eachRendered)
            // upstream (echarts.ts renderComponents): a rendered view is marked alive so the
            //   `updateDirectly` light-update path (callView's `view.__alive` guard) can dispatch
            //   highlight/downplay/updateView to it. Without this, all light-update dispatch no-ops.
            componentView.__alive = true
        }
    }

    // upstream: echarts.ts `updateZ(model, view)` → `graphic.retrieveZInfo(model)` +
    //   `traverseUpdateZ(el, z, zlevel)`. Set every rendered element's `z`/`zlevel` from the model. The
    //   painter sorts by (zlevel, z, z2), so this is what lifts SERIES (z 2/3) above the coordinate
    //   COMPONENTS (z 0) — without it, a coordinate axis/splitLine (z2 1‑2) renders OVER the series data
    //   (radar spokes over vertices, polar grid over the line). `z2` is preserved (intra-view order).
    //   `defaultZ` fills a model with no explicit `z`: series default to 2 (echarts gives line 3,
    //   scatter/radar/pie/candlestick 2, and bar relies on z2 — a 2 floor keeps every series above the
    //   z:0 coordinate grid), components to 0.
    private func zNum(_ v: Any?) -> Double? {
        if let d = v as? Double { return d }
        if let i = v as? Int { return Double(i) }
        if let n = v as? NSNumber { return n.doubleValue }
        return nil
    }

    private func updateZ(_ model: ComponentModel, _ group: Group, _ defaultZ: Double) {
        let z = zNum(model.get("z")) ?? defaultZ
        let zlevel = zNum(model.get("zlevel")) ?? 0
        // upstream `updateZ` does `view.eachRendered(el => { traverseUpdateZ(el, z, zlevel); return true })`
        //   — `return true` stops descent, so `traverseUpdateZ` runs once per TOP-LEVEL rendered element
        //   (each with a fresh `maxZ2 = -Infinity`). Mirror that: run `doUpdateZ` on each direct child of
        //   the view group. The container `group` itself is a `Group` (not a Displayable) → nothing to set.
        //
        // SCOPED z2-lift: upstream `doUpdateZ` ALWAYS lifts each host's attached label to `z2 =
        //   subtreeMaxZ2 + 2` (labels over glyphs). The port applies that lift ONLY for the graph series.
        //   Reason: several ported views (notably treemap) create tile labels that upstream HIDES via the
        //   label overflow/visibility engine (NOT ported); the port relied on those labels sorting BEHIND
        //   the tile (tile `z2` > label `z2` 0) to stay invisible. Lifting them everywhere re-exposes
        //   them — a visual-parity regression vs real echarts (which shows no treemap labels here). Graph
        //   node symbols carry `z2 = 100` (Symbol._createSymbol's `retrieve2(z2, 100)`), so WITHOUT the
        //   lift their name label (default `z2 = 0`) sorts behind the node and is invisible — the bug this
        //   fixes. Scoping to graph fixes that without perturbing treemap/other views. See util/graphic.ts
        //   `doUpdateZ` for the general form.
        let liftLabelZ2 = model is GraphSeriesModel
        for child in group.children() {
            _ = doUpdateZ(child, z, zlevel, -Double.infinity, liftLabelZ2)
        }
    }

    // upstream: util/graphic.ts `doUpdateZ(el, z, zlevel, maxZ2)`. Sets `z`/`zlevel` on every displayable
    //   (preserving `z2`, the intra-view order the painter tie-breaks on) and on each host's attached
    //   label. When `liftLabelZ2` is set (graph only — see `updateZ`), also threads the running max `z2`
    //   through the DFS and LIFTS each label to `z2 = subtreeMaxZ2 + 2` (and the text guide line to
    //   `maxZ2 ± 1`) so it paints over the glyph it annotates. When `liftLabelZ2` is off, only z/zlevel is
    //   set (label z2 left at its authored value) — the port's historical behavior for non-graph views.
    //   PORT-NOTE: `ignoreModelZ` (an ExtendedElement flag used to intentionally pin lifted elements) is
    //   not ported → not checked here.
    @discardableResult
    private func doUpdateZ(
        _ el: Element, _ z: Double, _ zlevel: Double, _ maxZ2In: Double, _ liftLabelZ2: Bool
    ) -> Double {
        var maxZ2 = maxZ2In

        // Group may also have textContent.
        let label = el.getTextContent()
        let labelLine = el.getTextGuideLine()

        if el.isGroup {
            if let g = el as? Group {
                for child in g.children() {
                    maxZ2 = Swift.max(doUpdateZ(child, z, zlevel, maxZ2, liftLabelZ2), maxZ2)
                }
            }
        }
        else if let d = el as? Displayable {
            d.z = z
            d.zlevel = zlevel
            // upstream `el.z2 || 0` — treat a NaN z2 as 0.
            maxZ2 = Swift.max(d.z2.isNaN ? 0 : d.z2, maxZ2)
        }

        // Always set z/zlevel if label/labelLine exists; lift z2 above the subtree glyphs (graph only).
        if let label = label {   // ZRText is a Displayable — no downcast needed.
            label.z = z
            label.zlevel = zlevel
            if liftLabelZ2, maxZ2.isFinite { label.z2 = maxZ2 + 2 }
        }
        // labelLine (text guide line) z-handling is gated on the lift too: graph has no label lines, so
        //   this is a graph-only no-op, and non-graph views keep their historical labelLine z (untouched
        //   here — set only if the line is also a traversed group child, exactly as before).
        if liftLabelZ2, let labelLine = labelLine {
            labelLine.z = z
            labelLine.zlevel = zlevel
            if maxZ2.isFinite {
                let showAbove = el.textGuideLineConfig?.showAbove ?? false
                labelLine.z2 = maxZ2 + (showAbove ? 1 : -1)
            }
        }
        return maxZ2
    }

    // renderSeries (echarts.ts:2472) — minimal: bypass the Scheduler `renderTask.perform` and call
    // `chartView.render(...)` directly (documented deviation; no progressive/incremental rendering).
    // The four `lifecycle.trigger(...)`s and their `updateParams` ARE faithful (echarts.ts:2483-2538) —
    // they are what drives `universalTransition` (animation/universalTransition.swift), which listens on
    // 'series:beforeupdate' + 'series:transition'.
    private func renderSeries(_ ecModel: GlobalModel, _ api: ExtensionAPI,
                              _ updateParams: UpdateLifecycleParams = UpdateLifecycleParams()) {
        let payload = Payload(type: "")

        // updateParams = extend(updateParams || {}, { updatedSeries: ecModel.getSeries() });
        var updateParams = updateParams
        updateParams.updatedSeries = ecModel.getSeries()

        // TODO progressive?
        lifecycle.trigger("series:beforeupdate", ecModel, api, updateParams)

        ecModel.eachSeries { seriesModel, _ in
            guard let chartView = self._chartViewByModel[ObjectIdentifier(seriesModel)] else { return }
            // upstream (echarts.ts renderSeries): mark the rendered view alive so the `updateDirectly`
            //   light-update path (callView's `view.__alive` guard) can dispatch highlight/downplay to it.
            chartView.__alive = true
            // upstream renderSeries clearStates (echarts.ts:2499) — reset a reused view's elements to
            //   normal before re-render so emphasis/select from before a merge-mode setOption is gone.
            self.clearRenderedStates(chartView.eachRendered)
            chartView.render(seriesModel, ecModel, api, payload)
            // upstream renderSeries `updateSeriesElementSelection(seriesModel)` (echarts.ts:2515) —
            //   re-apply the select state from the model's selectedMap after render, so a selected
            //   pie sector / bar stays selected across a merge-mode setOption re-render.
            states.updateSeriesElementSelection(seriesModel)
        }

        // upstream echarts.ts:2520 — lifecycle.trigger('series:layoutlabels', ...).
        //   PORT-NOTE: nothing listens on it here. The port hand-calls the label-layout stage
        //   (`LabelManager.runLabelLayoutStage`) at the end of `render()` instead of registering
        //   `installLabelLayout` as a listener, so the label layout currently runs AFTER 'series:transition'
        //   rather than before it. Harmless for the morph (labels are `ZRText` textContents, never
        //   `getPathList` morph endpoints), but the trigger is emitted at the faithful position so a real
        //   `installLabelLayout` listener can land here later without moving anything.
        lifecycle.trigger("series:layoutlabels", ecModel, api, updateParams)

        // transition after label is layouted.
        lifecycle.trigger("series:transition", ecModel, api, updateParams)

        ecModel.eachSeries { seriesModel, _ in
            guard let chartView = self._chartViewByModel[ObjectIdentifier(seriesModel)] else { return }
            // Update Z after labels updated. Before applying states.
            // upstream echarts.ts renderSeries runs `updateZ(seriesModel, view)` — lift the series' z above
            //   the coordinate components (default 2) so the data draws over the grid/axis/splitLine.
            self.updateZ(seriesModel, chartView.group, 2)

            // NOTE: Update states after label is updated.
            // label should be in normal status when layouting.
            // upstream renderSeries `updateStates(seriesModel, view)` (echarts.ts:2532) — save each
            //   emphasis-capable element's normal fill so a hover LIFTS it (see updateRenderedStates).
            //   THIS is what makes hover-emphasis visible for a datum with no explicit emphasis.itemStyle.
            //   It runs AFTER 'series:transition' on purpose: applyMorphAnimation animates with
            //   `setToFinal: true`, so the morph target's style is already final and the saved
            //   normal fill is the correct one.
            self.updateRenderedStates(chartView.eachRendered)
        }

        // updateHoverLayerStatus(ecIns, ecModel) — PORT-NOTE (deferred): hover layer not ported.

        lifecycle.trigger("series:afterupdate", ecModel, api, updateParams)
    }

    // ========================================================================
    // ACTION DISPATCH ROUND-TRIP — ported from echarts.ts `dispatchAction` (1574) +
    // `doDispatchAction` (2148) + `flushPendingActions`/`triggerUpdatedEvent` (2274).
    // Phase 29 substrate: run an action programmatically and drive a re-render through the EXISTING
    // update() pipeline. HEADLESS — no live zrender, no pointer/gesture events, no message center yet.
    // ========================================================================

    /// Ported from `ECharts.dispatchAction` (echarts.ts:1574-1624).
    public func dispatchAction(_ payload: Payload, _ opt: DispatchActionOpt? = nil) {
        // if (this._disposed) { disposedWarning(this.id); return; }
        //   PORT-NOTE: the driver has no `_disposed` flag / lifecycle (dispose is Phase 6b) — no guard.

        // if (!isObject(opt)) { opt = {silent: !!opt}; }
        //   The `boolean | {silent,flush}` normalization is absorbed by `DispatchActionOpt` (nil → silent:false;
        //   the bare-boolean form is `DispatchActionOpt(true)`).
        let opt = opt ?? DispatchActionOpt(silent: false)

        // if (!actions[payload.type]) { return; }  — unregistered action type is a silent no-op.
        //   `lookupAction` is the action-registry accessor from TASK 1 (integrator reconciles the name).
        guard lookupAction(payload.type) != nil else {
            return
        }

        // Avoid dispatch action before setOption. Especially in `connect`.
        // if (!this._model) { return; }
        guard _model != nil else {
            return
        }

        // May dispatchAction in rendering procedure → queue it and drain after the cycle.
        // if (this[IN_EC_CYCLE_KEY]) { this._pendingActions.push(payload); return; }
        if _inEcCycle {
            _pendingActions.append(payload)
            return
        }

        let silent = opt.silent
        doDispatchAction(payload, silent)

        let flush = opt.flush
        if flush == true {
            // upstream: this._zr.flush();
            // PORT-NOTE (platform): forces a SYNCHRONOUS zrender repaint of the deferred frame. There is no live zr
            //   this phase, and the driver's `update()` ALREADY renders synchronously inside
            //   doDispatchAction, so there is no pending frame to flush → no-op.
        }
        else if flush != false {
            // upstream: `else if (flush !== false && env.browser.weChat) this._throttledZrFlush();`
            // PORT-NOTE (platform): the WeChat throttled-flush workaround is N/A (no browser env / live zr).
        }

        flushPendingActions(silent)

        triggerUpdatedEvent(silent)
    }

    /// Ported from `doDispatchAction` (echarts.ts:2148-2272).
    private func doDispatchAction(_ payload: Payload, _ silent: Bool) {
        let ecModel = getModel()!                 // guarded non-nil by dispatchAction (`_model` check).
        let api = _api!
        let payloadType = payload.type
        let escapeConnect = payload.escapeConnect
        let actionInfo = lookupAction(payloadType)!   // guaranteed by the dispatchAction registry guard.

        // const cptTypeTmp = (actionInfo.update || 'update').split(':');
        // const updateMethod = cptTypeTmp.pop();
        // const cptType = cptTypeTmp[0] != null && parseClassType(cptTypeTmp[0]);
        var cptTypeTmp = (actionInfo.update ?? "update").components(separatedBy: ":")
        let updateMethod = cptTypeTmp.removeLast()     // pop() — the trailing update-method name.
        let cptType: ComponentTypeInfo? = cptTypeTmp.first != nil
            ? clazz.parseClassType(cptTypeTmp[0]) : nil   // only set when the update spec had a "cpt:method" prefix.

        _inEcCycle = true
        // updateECUpdateCycleVersion(this);
        //   PORT-NOTE: util/states (the emphasis/blur state machine) is ported and wired; the EC update-cycle
        //   version counter it uses as a staleness guard is simply not tracked in this driver.

        // Batch action → one payload per batch item (`defaults(extend({}, item), payload); item.batch = null`).
        var payloads: [Payload] = [payload]
        var batched = false
        if let batch = payload.batch {
            batched = true
            payloads = batch.map { item in
                // extend({}, item) then defaults(..., payload): item's fields win, payload fills the gaps.
                var p = Payload(type: payload.type)         // type comes from payload (PayloadItem has none).
                p.escapeConnect = payload.escapeConnect     // escapeConnect only on payload.
                p.animation = item.animation ?? payload.animation
                p.excludeSeriesId = item.excludeSeriesId ?? payload.excludeSeriesId
                var bag = payload.other                     // payload defaults …
                for (k, v) in item.other { bag[k] = v }     // … overlaid by the item (item wins).
                p.other = bag
                p.batch = nil                               // item.batch = null
                return p
            }
        }

        var eventObjBatch: [ECActionEvent] = []
        var eventObj: ECActionEvent?
        // actionInfo.nonRefinedEventType is computed by registerAction (TASK 1).
        let nonRefinedEventType = actionInfo.nonRefinedEventType

        let isSelectChange = states.isSelectChangePayload(payload)
        let isHighDown = states.isHighDownPayload(payload)

        // Only leave blur once if there are multiple batches.
        // if (isHighDown) { allLeaveBlur(this._api); }
        if isHighDown {
            states.allLeaveBlur(_api)
        }

        for batchItem in payloads {
            // The ONE thing an ActionHandler is designed to do: modify the models. Runs for every payload.
            let actionResult: ECEventData? = actionInfo.action?(batchItem, ecModel, api)
            // refineEvent path (actionInfo.refineEvent) is DEFERRED (Phase 30). Non-refined event replicates
            //   the payload: eventObj = actionResult || extend({}, batchItem); eventObj.type = nonRefinedEventType.
            var e = ECActionEvent(type: nonRefinedEventType)
            // upstream: `eventObj = eventObj || extend({} as ECActionEvent, batchItem)` — when the action
            //   handler returns nothing, the event IS a copy of the payload (that is how a user's
            //   `legendselectchanged` handler reads `params.name` / `params.selected`). The payload's
            //   dynamic bag is `batchItem.other`; the action's returned bag wins when present.
            e.eventData = actionResult ?? batchItem.other
            e.componentType = e.eventData["componentType"] as? String
            e.componentIndex = ecEventNumber(e.eventData["componentIndex"])
            e.seriesIndex = ecEventNumber(e.eventData["seriesIndex"])
            e.escapeConnect = batchItem.escapeConnect
            eventObj = e
            eventObjBatch.append(e)

            // light update does not perform data process, layout and visual.
            if isHighDown {
                // const { queryOptionMap, mainTypeSpecified } = modelUtil.preParseFinder(payload);
                // const componentMainType = mainTypeSpecified ? queryOptionMap.keys()[0] : 'series';
                //   Upstream inspects the OUTER `payload` (not the batch item). The finder keys
                //   (seriesIndex/xAxisIndex/…) live in `payload.other` in this port, so the dynamic bag IS
                //   the ModelFinderObject preParseFinder inspects.
                let pre = model.preParseFinder(payload.other as ModelFinder)
                let componentMainType = pre.mainTypeSpecified
                    ? (pre.queryOptionMap.keys().first ?? "series")
                    : "series"
                updateDirectly(updateMethod, batchItem, componentMainType)
                // markStatusToUpdate(this); — PORT-NOTE: no status-needs-update flag tracked in the
                //   driver; the dispatch caller repaints via the full `update()` when needed.
            }
            else if isSelectChange {
                // At present `dispatchAction({ type: 'select', ... })` is not supported on components.
                // geo still uses 'geoselect'.
                updateDirectly(updateMethod, batchItem, "series")
            }
            else if cptType != nil {
                updateDirectly(updateMethod, batchItem, cptType!.main, cptType!.sub)
            }
        }

        if updateMethod != "none" && !isHighDown && !isSelectChange && cptType == nil {
            // upstream: if (this[PENDING_UPDATE]) { prepare(this); updateMethods.update…; } else
            //   updateMethods[updateMethod].call(this, payload);
            //   PENDING_UPDATE (a still-dirty setOption awaiting flush) is not tracked in the driver,
            //   so there is only the else-branch.
            // Route to the update method the action declares (L6). The light methods (updateView/
            //   updateVisual/updateLayout/updateTransform) reuse the persistent views and skip data
            //   reprocessing; 'update'/'prepareAndUpdate' run the full pipeline. (In the every
            //   layout stage lives inside render(), so updateView/updateLayout re-lay-out too.)
            //
            // The update methods take no payload argument here (upstream: `updateMethods[m].call(this,
            //   payload)`), so park it on the driver for the duration — `render()` hands it to the
            //   component views + the brush visual stage. Restored (not just cleared) so a nested
            //   dispatch — e.g. brushVisual's own `brushSelect` — cannot strand the outer payload.
            let prevPayload = _payload
            _payload = payload
            defer { _payload = prevPayload }
            switch updateMethod {
            case "updateView":      updateView()
            case "updateVisual":    updateVisual()
            case "updateLayout":    updateLayout()
            case "updateTransform": updateTransform()
            default:                update()   // 'update' / 'prepareAndUpdate'
            }
        }

        // Follow the rule of action batch (build the outer event object; kept for structural fidelity).
        if batched {
            var e = ECActionEvent(type: nonRefinedEventType)
            e.escapeConnect = escapeConnect
            e.batch = eventObjBatch.map { $0.eventData }
            eventObj = e
        }
        // else: eventObj is the single per-item event built above (upstream: eventObjBatch[0]).

        _inEcCycle = false

        if !silent {
            // let refinedEvent: ECActionEvent;
            // if (actionInfo.refineEvent) { ... refinedEvent = defaults({type: actionInfo.refinedEventType}, eventContent); ... }
            //   PORT-NOTE (gap): `refineEvent` is not ported (it needs `makeSelectChangedEvent` →
            //   `getAllSelectedIndices`; see core/actionRegister.swift, which registers select/unselect/
            //   toggleSelect WITHOUT it). Consequence: the REFINED 'selectchanged' event is not emitted;
            //   the non-refined per-action event ('select'/'unselect'/'toggleselect') IS — those are the
            //   `nonRefinedEventType`s `registerAction` computed, and they carry the payload's fields.
            let messageCenter = self._messageCenter
            // - If `refineEvent` created a `refinedEvent`, `eventObj` (replicated from the original payload)
            //  is still needed to be triggered for the feature `connect`. But it will not be triggered to
            //  users in this case.
            // - If no `refineEvent` used, `eventObj` will be triggered for both `connect` and users.
            if let eventObj = eventObj {
                messageCenter.trigger(eventObj.type, eventObj)
            }
        }
    }

    /// Ported from `flushPendingActions` (echarts.ts:2274-2280). Drain + re-dispatch queued actions.
    private func flushPendingActions(_ silent: Bool) {
        while !_pendingActions.isEmpty {
            let payload = _pendingActions.removeFirst()   // pendingActions.shift()
            doDispatchAction(payload, silent)
        }
    }

    /// Ported from `triggerUpdatedEvent` (echarts.ts:2282-2284).
    private func triggerUpdatedEvent(_ silent: Bool) {
        // upstream: !silent && this.trigger('updated');
        if !silent {
            self.trigger("updated")
        }
    }

    // ------------------------------------------------------------------------
    // updateDirectly — ported from the module-local `updateDirectly` (echarts.ts:1772-1866).
    //   The LIGHT UPDATE: resolve the payload-targeted series/component models, apply the
    //   blur/emphasis/select state in pass 1, then call the view's `method` (highlight/downplay/
    //   updateView/…) in pass 2. Performs NO data-process / layout / visual pass.
    // Upstream is a closure over the `ECharts` instance; here it is a private method (has `_model`,
    //   `_api`, and the view maps in scope).
    // ------------------------------------------------------------------------
    private func updateDirectly(
        _ method: String,
        _ payload: Payload,
        _ mainType: ComponentMainType,
        _ subType: ComponentSubType? = nil
    ) {
        guard let ecModel = _model else { return }   // upstream: `ecModel && ecModel.eachComponent(...)`
        let api = _api!

        ecModel.setUpdatePayload(payload)

        // if (!mainType) { broadcast to all views; return; }
        //   PORT-NOTE: the empty-mainType broadcast branch (`:updateAxisPointer`) is unreachable from the
        //   ported call sites (doDispatchAction always passes a concrete mainType), so it is elided.

        let condition = model.makeQueryConditionKindA(payload, mainType, subType)

        // const excludeSeriesId = payload.excludeSeriesId; → Set<String> of resolved ids.
        var excludeSeriesIdSet: Set<String>? = nil
        if let excludeSeriesId = payload.excludeSeriesId {
            var set = Set<String>()
            let ids: [Any] = model.normalizeToArray(excludeSeriesId)
            for id in ids {
                if let modelId = model.convertOptionIdName(id, nil) {
                    set.insert(modelId)
                }
            }
            excludeSeriesIdSet = set
        }
        func isExcluded(_ m: ComponentModel) -> Bool {
            return excludeSeriesIdSet?.contains(m.id) ?? false
        }

        // ---- pass 1: mutate models / apply blur + emphasis + select state ----
        ecModel.eachComponent(condition, { m, _ in
            if isExcluded(m) { return }

            if states.isHighDownPayload(payload) {
                if let seriesModel = m as? SeriesModel {
                    let notBlur = (payload.other["notBlur"] as? Bool) ?? false
                    // `!model.get(['emphasis','disabled'])` — `disabled` is a boolean option (JS truthiness
                    //   reduces to the bool here).
                    let disabled = (seriesModel.get(["emphasis", "disabled"]) as? Bool) ?? false
                    if payload.type == states.HIGHLIGHT_ACTION_TYPE && !notBlur && !disabled {
                        states.blurSeriesFromHighlightPayload(seriesModel, payload, api)
                    }
                }
                else {
                    // Component (non-series) high-down dispatch (upstream echarts.ts:1820-1834).
                    let notBlur = (payload.other["notBlur"] as? Bool) ?? false
                    let found = states.findComponentHighDownDispatchers(
                        m.mainType, m.componentIndex, payload.other["name"] as? String, api
                    )
                    if payload.type == states.HIGHLIGHT_ACTION_TYPE && found.focusSelf && !notBlur {
                        states.blurComponent(m.mainType, m.componentIndex, api)
                    }
                    if let dispatchers = found.dispatchers {
                        util.each(dispatchers) { d, _ in
                            payload.type == states.HIGHLIGHT_ACTION_TYPE
                                ? states.enterEmphasis(d) : states.leaveEmphasis(d)
                        }
                    }
                }
            }
            else if states.isSelectChangePayload(payload) {
                // TODO geo
                if let seriesModel = m as? SeriesModel {
                    states.toggleSelectionFromPayload(seriesModel, payload, api)
                    states.updateSeriesElementSelection(seriesModel)
                    // markStatusToUpdate(ecIns);  — PORT-NOTE: no status-needs-update flag tracked in the
                    //   driver (upstream sets it so a later flush repaints; here the caller repaints).
                }
            }
        })

        // ---- pass 2: light update on each affected view (upstream `callView(ecIns[map][__viewId])`) ----
        ecModel.eachComponent(condition, { m, _ in
            if isExcluded(m) { return }
            self.callViewMethod(m, method, payload, ecModel, api)
        })
    }

    // Upstream `callView(view)` = `view && view.__alive && view[method] && view[method](model, ecModel,
    //   api, payload)`. Swift has no string-keyed method dispatch, so the `view[method]` lookup is a switch
    //   over the ported view methods; an unmapped `method` (e.g. 'select'/'unselect'/'toggleSelect', which
    //   no view implements) is a no-op — exactly matching the upstream `view[method] &&` short-circuit.
    private func callViewMethod(
        _ m: ComponentModel, _ method: String, _ payload: Payload, _ ecModel: GlobalModel, _ api: ExtensionAPI
    ) {
        if let seriesModel = m as? SeriesModel {
            guard let view = viewOfSeriesModel(seriesModel), view.__alive else { return }
            switch method {
            case "highlight":    view.highlight(seriesModel, ecModel, api, payload)
            case "downplay":     view.downplay(seriesModel, ecModel, api, payload)
            case "updateView":   view.updateView(seriesModel, ecModel, api, payload)
            case "updateVisual": view.updateVisual(seriesModel, ecModel, api, payload)
            case "render":       view.render(seriesModel, ecModel, api, payload)
            default: break
            }
        }
        else {
            guard let view = viewOfComponentModel(m), (view.__alive ?? false) else { return }
            switch method {
            case "updateView":   view.updateView(m, ecModel, api, payload)
            case "updateLayout": view.updateLayout(m, ecModel, api, payload)
            case "updateVisual": view.updateVisual(m, ecModel, api, payload)
            case "render":       view.render(m, ecModel, api, payload)
            default: break
            }
        }
    }

    // ========================================================================
    // THE PUBLIC CHART EVENT BUS — `chart.on('click', handler)`.
    //
    // upstream `class ECharts extends Eventful<ECEventDefinition>` + the prototype rewrite at
    //   echarts.ts:329-336:
    //     function createRegisterEventWithLowercaseECharts(method) {
    //         return function (this: ECharts, ...args: any): ECharts {
    //             if (this.isDisposed()) { disposedWarning(this.id); return; }
    //             return toLowercaseNameAndCallEventful<ECharts>(this, method, args);
    //         };
    //     }
    //   i.e. `on`/`off` lowercase the event name and forward to `Eventful`. `trigger` is Eventful's own.
    //
    // The handler param: upstream hands ONE object — an `ECElementEvent` for the mouse events, an
    //   `ECActionEvent` for the action events. Both conform to `ECEventParams` (util/types.swift).
    // ========================================================================

    /// upstream: `chart.on(eventName, handler)`.
    @discardableResult
    public func on(_ eventName: String, _ handler: @escaping (ECEventParams) -> Void) -> ECharts {
        return self.on(eventName, nil, handler)
    }

    /// upstream: `chart.on(eventName, query, handler)` — `query` is a component-type string
    /// ('series', 'xAxis.category') or a query object (`["seriesIndex": 1]`, `["dataIndex": 3]`).
    /// See `ECEventProcessor` for the full query grammar.
    @discardableResult
    public func on(
        _ eventName: String,
        _ query: EventQuery?,
        _ handler: @escaping (ECEventParams) -> Void
    ) -> ECharts {
        // PORT-NOTE: `if (this.isDisposed()) { disposedWarning(this.id); return; }` — the driver has no
        //   `_disposed` flag / dispose lifecycle (see `dispatchAction`), so there is no guard to port.
        // `args[0]` is event name. Event name is all lowercase.
        let lowerName = eventName.lowercased()
        _eventful.on(lowerName, query, { _, args in
            // Eventful's callback is the raw `(thisCtx, [Any?])`; unwrap the single packed event.
            if let params = (args.first ?? nil) as? ECEventParams {
                handler(params)
            }
            else {
                // PORT-NOTE: upstream triggers the LIFECYCLE events with NO param object
                //   (`this.trigger('updated')`, `trigger('finished')`), so the JS handler's `params` is
                //   `undefined`. The Swift handler takes a non-optional `ECEventParams`, so a param-less
                //   trigger is delivered as an otherwise-EMPTY packed event carrying only `type`. No field
                //   is invented — every other property is nil.
                handler(ECActionEvent(type: lowerName))
            }
            return nil   // `boolean | void` — we never cancel the bubble.
        })
        return self
    }

    /// upstream: `chart.off(eventName)`.
    ///
    /// PORT-NOTE (closure identity): upstream also supports `off(eventName, handler)` — removing ONE
    ///   handler. Swift closures have no identity, so `Eventful.off(event, handler)` cannot filter a
    ///   specific handler out (documented in ZRenderKit/Core/Eventful.swift) and is not exposed here.
    ///   Consequence: you can unbind ALL handlers of an event, not a single one.
    @discardableResult
    public func off(_ eventName: String? = nil) -> ECharts {
        _eventful.off(eventName?.lowercased())
        return self
    }

    /// upstream: `Eventful.prototype.trigger` — used internally (`_initEvents` re-publishes the message
    /// center onto this bus) and available to a host that wants to inject an event.
    @discardableResult
    public func trigger(_ eventType: String, _ params: ECEventParams? = nil) -> ECharts {
        if let params = params {
            _eventful.trigger(eventType, params)
        }
        else {
            _eventful.trigger(eventType)
        }
        return self
    }

    /// upstream: `Eventful.prototype.isSilent` — whether any handler is bound.
    public func isSilent(_ eventName: String) -> Bool {
        return _eventful.isSilent(eventName.lowercased())
    }

    // ------------------------------------------------------------------------
    // _initEvents — ported from `ECharts.prototype._initEvents` (echarts.ts:1290).
    //
    // SPLIT (documented deviation): upstream, one `_initEvents()` does BOTH halves —
    //   (a) the `MOUSE_EVENT_NAMES` fan-out, which binds `this._zr.on(eveName, handler)`, and
    //   (b) the message-center fan-out, which re-publishes every registered public event type
    //       (`publicEventTypeMap`) from the internal bus onto the public `ECharts` bus.
    //   This driver is deliberately ZR-LESS (it owns a bare `Storage`, so it can be driven headlessly);
    //   the live zrender lives on the host-binding `EChartsView`. So (b) runs here, at construction —
    //   it needs no zr — and (a) is exposed as `_initZrEvents(zr)`, which `EChartsView.init` calls with
    //   its live zr. Same handlers, same order, just a seam where upstream has none.
    // ------------------------------------------------------------------------
    private func _initEvents() {
        // const messageCenter = this._messageCenter;
        // each(publicEventTypeMap, (_, eventType) => {
        //     messageCenter.on(eventType, event => { this.trigger(eventType, event); });
        // });
        //
        // `publicEventTypeMap` is populated by `registerAction` — `installOnce()` (run just above in
        //   `init`) has registered every built-in + component action by now, exactly as upstream's
        //   module-load registration has by the time an `ECharts` is constructed.
        let messageCenter = self._messageCenter
        for (eventType, _) in publicEventTypeMap {
            messageCenter.on(eventType, { [weak self] _, args in
                guard let self = self else { return nil }
                self.trigger(eventType, (args.first ?? nil) as? ECEventParams)
                return nil
            })
        }

        // handleLegacySelectEvents(messageCenter, this, this._api);
        //   PORT-NOTE (gap): `legacy/dataSelectAction.ts` is NOT ported (the deprecated
        //   'pieselectchanged' / 'mapselectchanged' / 'selected' back-compat events, which re-emit the
        //   modern 'selectchanged' under the pre-v5 names). Consequence: a listener bound to one of the
        //   DEPRECATED event names never fires. The modern events are unaffected.
    }

    // ------------------------------------------------------------------------
    // _initZrEvents — the `MOUSE_EVENT_NAMES` half of upstream `_initEvents` (echarts.ts:1291-1377),
    //   line-for-line. Called by the host-binding (`EChartsView`) with its live zr (see the SPLIT note
    //   on `_initEvents`). Turns a zrender ELEMENT event into a CHART event with the upstream param
    //   shape and publishes it on the public bus.
    // ------------------------------------------------------------------------
    func _initZrEvents(_ zr: ZRender) {
        // each(MOUSE_EVENT_NAMES, (eveName) => {
        for eveName in MOUSE_EVENT_NAMES {
            // const handler = (e: ElementEvent) => { ... }
            let handler: EventCallback = { [weak self] _, args in
                guard let self = self else { return nil }
                guard let ecModel = self.getModel() else { return nil }
                let e = (args.first ?? nil) as? ElementEvent
                let el = e?.target
                var params: ECElementEvent?
                let isGlobalOut = (eveName == "globalout")
                // no e.target when 'globalout'.
                if isGlobalOut {
                    params = ECElementEvent(type: eveName)   // upstream: `params = {} as ECElementEvent`
                }
                else {
                    // el && findEventDispatcher(el, (parent) => { ... }, true)
                    //   The `det` closure has a SIDE EFFECT upstream (it assigns `params`) — ported as-is.
                    _ = findEventDispatcher(el, { parent in
                        let ecData = innerStore.getECData(parent)
                        if let dataIndex = ecData.dataIndex {
                            // const dataModel = ecData.dataModel || ecModel.getSeriesByIndex(ecData.seriesIndex);
                            // params = dataModel && dataModel.getDataParams(ecData.dataIndex, ecData.dataType, el) || {};
                            //
                            // PORT-NOTE: `ecData.dataModel` is never populated in this port (the
                            //   markPoint/markLine/markArea views that set it are blocked on
                            //   `MarkerModel: DataModel` conformance — see MarkPointView.swift). So the
                            //   `|| ecModel.getSeriesByIndex(...)` arm always runs. Consequence: a click on a
                            //   MARKER element packs its params from the HOST SERIES, not the marker model.
                            // PORT-NOTE: `getDataParams(dataIndex, dataType, el)` — the 3rd argument (`el`)
                            //   exists only on the CustomSeries override (`DataFormatMixin.getDataParams` takes
                            //   two). Custom series' extra `el`-derived params are therefore not packed.
                            let dataModel: SeriesModel? = ecData.seriesIndex != nil
                                ? ecModel.getSeriesByIndex(ecData.seriesIndex!) : nil
                            if let dataModel = dataModel {
                                params = ECElementEvent(
                                    type: eveName,
                                    dataParams: dataModel.getDataParams(dataIndex, ecData.dataType)
                                )
                            }
                            else {
                                params = ECElementEvent(type: eveName)   // `|| {}`
                            }
                            return true
                        }
                        // If element has custom eventData of components
                        // else if (ecData.eventData) { params = extend({}, ecData.eventData); return true; }
                        else if let eventData = ecData.eventData {
                            params = ECElementEvent(type: eveName, eventData: eventData)
                            return true
                        }
                        return false
                    }, true)
                }

                // Contract: if params prepared in mouse event,
                // these properties must be specified:
                // {
                //    componentType: string (component main type)
                //    componentIndex: number
                // }
                // Otherwise event query can not work.

                if var params = params {
                    var componentType = params.componentType
                    var componentIndex = params.componentIndex
                    // Special handling for historic reason: when trigger by
                    // markLine/markPoint/markArea, the componentType is
                    // 'markLine'/'markPoint'/'markArea', but we should better
                    // enable them to be queried by seriesIndex, since their
                    // option is set in each series.
                    if componentType == "markLine"
                        || componentType == "markPoint"
                        || componentType == "markArea"
                    {
                        componentType = "series"
                        componentIndex = params.seriesIndex
                    }
                    let model: ComponentModel? = (componentType != nil && componentIndex != nil)
                        ? ecModel.getComponent(componentType!, componentIndex!) : nil
                    let view: AnyObject? = model.flatMap { m -> AnyObject? in
                        m.mainType == "series"
                            ? self._chartViewByModel[ObjectIdentifier(m)]
                            : self._componentViewByModel[ObjectIdentifier(m)]
                    }

                    // (__DEV__ warn 'model or view can not be found by params' — no dev logging path.)

                    params.componentType = componentType
                    params.componentIndex = componentIndex
                    params.event = e
                    params.type = eveName

                    self._$eventProcessor.eventInfo = ECEventProcessor.EventInfo(
                        targetEl: el,
                        packedEvent: params,
                        model: model,
                        view: view
                    )

                    self.trigger(eveName, params)
                }
                return nil
            }
            // Consider that some component (like tooltip, brush, ...)
            // register zr event handler, but user event handler might
            // do anything, such as call `setOption` or `dispatchAction`,
            // which probably update any of the content and probably
            // cause problem if it is called previous other inner handlers.
            // (handler as any).zrEventfulCallAtLast = true;   → the `callAtLast:` parameter (Eventful.on).
            // this._zr.on(eveName, handler, this);
            //   ctx is `nil`, NOT `self`: `Eventful` holds `ctx` STRONGLY and the zr→handler→eventful chain
            //   is owned by the host view, so passing `self` would leak the whole chart (same rule as every
            //   other binding in EChartsView; the closure already captures `[weak self]`).
            zr.on(eveName, handler, nil, callAtLast: true)
        }

        // upstream: `bindRenderedEvent(zr, this)` (echarts.ts:612 / 2298) — also a constructor-time zr
        //   binding, so it belongs to this half of the split.
        bindRenderedEvent(zr)
    }

    // ------------------------------------------------------------------------
    // bindRenderedEvent — ported from the module-local `bindRenderedEvent` (echarts.ts:2298-2324).
    //
    // Event `rendered` is triggered when zr rendered. It is useful for realtime snapshot (reflect animation).
    // Event `finished` is triggered when:
    // (1) zrender rendering finished.
    // (2) initial animation finished.
    // (3) progressive rendering finished.
    // (4) no pending action.
    // (5) no delayed setOption needs to be processed.
    // ------------------------------------------------------------------------
    private func bindRenderedEvent(_ zr: ZRender) {
        zr.on("rendered", { [weak self] _, args in
            guard let self = self else { return nil }

            // ecIns.trigger('rendered', params);
            //   PORT-NOTE: upstream's param is zrender's `RenderedEvent` ({elapsedTime}). The chart bus
            //   carries `ECEventParams`, which that struct is not, so 'rendered' is published with an
            //   otherwise-empty packed event whose `elapsedTime` is put in the dynamic bag — the one place
            //   the packed event is assembled from a zr event rather than a model.
            var params = ECActionEvent(type: "rendered")
            if let re = (args.first ?? nil) as? RenderedEvent {
                params.eventData["elapsedTime"] = re.elapsedTime
            }
            self.trigger("rendered", params)

            // The `finished` event should not be triggered repeatedly, so it should only be triggered
            // when rendering indeed happens in zrender.
            if zr.animation.isFinished()
                // !ecIns[PENDING_UPDATE] — PORT-NOTE: the driver has no lazy/pending setOption
                //   (`setOption` renders synchronously), so there is no pending-update flag to check.
                && !(self._scheduler?.unfinished ?? false)
                && self._pendingActions.isEmpty
            {
                self.trigger("finished")
            }
            else {
                // Make sure this method can be entered again in next frames.
                zr.refresh()
            }
            return nil
        }, nil)
    }

    // ------------------------------------------------------------------------
    // containPixel — ported from `ECharts.prototype.containPixel` (echarts.ts:1190-1230).
    //   "Is the specified coordinate systems or components contain the given pixel point."
    // ------------------------------------------------------------------------
    public func containPixel(_ finder: ModelFinder, _ value: [Double]) -> Bool {
        // if (this._disposed) { disposedWarning(this.id); return; }  — no dispose lifecycle (see above).
        guard let ecModel = self._model else { return false }
        var result: Bool = false

        let findResult = model.parseFinder(ecModel, finder)

        // each(findResult, function (models, key) {
        //     key.indexOf('Models') >= 0 && each(models, function (model) { ... });
        // });
        for (key, models) in findResult {
            guard key.contains("Models"), let models = models as? [ComponentModel] else { continue }
            for m in models {
                // const coordSys = (model as CoordinateSystemHostModel).coordinateSystem;
                // if (coordSys && coordSys.containPoint) { result = result || !!coordSys.containPoint(value); }
                //
                // PORT-NOTE: `model.coordinateSystem` is not one property in this port — a coord-sys HOST
                //   model (GridModel/PolarModel/…) declares it through `CoordinateSystemHostModel`
                //   (a `CoordinateSystemMaster`), while a SeriesModel stores its own as `Any?` (a
                //   `CoordinateSystem`). Both are checked; both protocols declare `containPoint`.
                if let host = m as? CoordinateSystemHostModel, let coordSys = host.coordinateSystem {
                    result = result || coordSys.containPoint(value)
                }
                else if let series = m as? SeriesModel, let coordSys = series.coordinateSystem as? CoordinateSystem {
                    result = result || coordSys.containPoint(value)
                }
                else if key == "seriesModels" {
                    // const view = this._chartsMap[model.__viewId];
                    // if (view && view.containPoint) { result = result || view.containPoint(value, model); }
                    if let series = m as? SeriesModel,
                       let view = self._chartViewByModel[ObjectIdentifier(series)] {
                        result = result || view.containPoint(value, series)
                    }
                    // (__DEV__ warn: 'The found component do not support containPoint.' — no dev logging.)
                }
                // (__DEV__ warn: key + ': containPoint is not supported' — no dev logging path.)
            }
        }

        return result
    }

    // ------------------------------------------------------------------------
    // getOption — ported from `ECharts.prototype.getOption` (echarts.ts:894-896).
    //   Returns the current merged option tree (`this._model.getOption()`).
    // ------------------------------------------------------------------------
    public func getOption() -> ECUnitOption? {
        return _model?.getOption()
    }

    // ------------------------------------------------------------------------
    // convertToPixel / convertFromPixel — ported from `ECharts.prototype.{convertToPixel,
    //   convertFromPixel}` (echarts.ts:1139-1183) + the module-internal `doConvertPixelImpl`
    //   (echarts.ts:2085-2137) assigned to `doConvertPixel`. Walks the coordinate systems and returns
    //   the first non-nil result of `coordSys[methodName](ecModel, parsedFinder, value, opt)`. Both
    //   `convertToPixel`/`convertFromPixel` are optional on `CoordinateSystemMaster` (nil-default), so a
    //   coord system that does not support the direction just returns nil and the walk continues.
    // ------------------------------------------------------------------------
    public func convertToPixel(_ finder: ModelFinder, _ value: CoordinateSystemDataCoord) -> Any? {
        return doConvertPixel("convertToPixel", finder, value, nil)
    }

    public func convertFromPixel(_ finder: ModelFinder, _ value: [Double]) -> Any? {
        return doConvertPixel("convertFromPixel", finder, value, nil)
    }

    // upstream: `doConvertPixelImpl(ecIns, methodName, finder, value, opt)`.
    private func doConvertPixel(_ methodName: String, _ finder: ModelFinder,
                                _ value: CoordinateSystemDataCoord, _ opt: Any?) -> Any? {
        // if (ecIns._disposed) { disposedWarning(ecIns.id); return; }
        if _disposed { return nil }
        guard let ecModel = _model else { return nil }
        let coordSysList = _coordSysMgr.getCoordinateSystems()
        let parsedFinder = model.parseFinder(ecModel, finder)

        // for (i) { if (coordSys[methodName] && (result = coordSys[methodName](...)) != null) return result; }
        for coordSys in coordSysList {
            let result: Any?
            switch methodName {
            case "convertToPixel":
                result = coordSys.convertToPixel(ecModel, parsedFinder, value, opt)
            case "convertFromPixel":
                result = coordSys.convertFromPixel(ecModel, parsedFinder, (value as? [Double]) ?? [], opt)
            default:
                result = nil
            }
            if let result = result { return result }
        }
        // (__DEV__ warn: 'No coordinate system that supports ' + methodName + ' found …' — no dev log.)
        return nil
    }

    // ------------------------------------------------------------------------
    // getVisual — ported from `ECharts.prototype.getVisual` (echarts.ts:1247-1273). Resolves the series
    //   (default main type 'series') from the finder and returns either the item-level visual (when a
    //   dataIndex/dataIndexInside is given) or the series-level visual.
    // ------------------------------------------------------------------------
    public func getVisual(_ finder: ModelFinder, _ visualType: String) -> Any? {
        guard let ecModel = _model else { return nil }
        let parsedFinder = model.parseFinder(ecModel, finder, ParseFinderOpt(defaultMainType: "series"))
        // if (__DEV__) { if (!seriesModel) warn('There is no specified series model'); }
        guard let seriesModel = parsedFinder["seriesModel"] as? SeriesModel else { return nil }
        let data = seriesModel.getData()

        // const dataIndexInside = parsedFinder.hasOwnProperty('dataIndexInside') ? …
        //     : parsedFinder.hasOwnProperty('dataIndex') ? data.indexOfRawIndex(parsedFinder.dataIndex) : null;
        let dataIndexInside: Int?
        if let dii = parsedFinder["dataIndexInside"] {
            dataIndexInside = ECharts._finderInt(dii)
        }
        else if let di = parsedFinder["dataIndex"], let raw = ECharts._finderInt(di) {
            dataIndexInside = data.indexOfRawIndex(raw)
        }
        else {
            dataIndexInside = nil
        }

        return dataIndexInside != nil
            ? getItemVisualFromData(data, dataIndexInside!, visualType)
            : ECharts._getVisualFromData(data, visualType)
    }

    // Minimal port of `visual/helper.ts#getVisualFromData` (series-level). Mirrors visualEncoding.swift's
    //   file-private copy; kept here because that one is not visible across files.
    private static func _getVisualFromData(_ data: SeriesData, _ key: String) -> Any? {
        switch key {
        case "color":
            let style = data.getVisual("style") as? [String: Any]
            let drawType = (data.getVisual("drawType") as? String) ?? "fill"
            return style?[drawType]
        case "opacity":
            return (data.getVisual("style") as? [String: Any])?["opacity"]
        case "symbol", "symbolSize", "liftZ":
            return data.getVisual(key)
        default:
            return nil
        }
    }

    // Coerce a finder's dataIndex value (may be boxed as Int or Double) to Int. See the Int-vs-Double
    //   option-read trap: defaultOptions box numbers as Int, but a finder built in code may pass Double.
    private static func _finderInt(_ v: Any?) -> Int? {
        if let i = v as? Int { return i }
        if let d = v as? Double { return Int(d) }
        return nil
    }

    // ------------------------------------------------------------------------
    // Instance lifecycle — ported from `ECharts.prototype.{isDisposed,clear,dispose}`
    //   (echarts.ts:1389-1444). The driver owns no zr/painter (see file header), so `dispose` disposes
    //   the views + clears the display list + releases the model/registries, but skips `this._zr.dispose()`
    //   (the host owns the zr) and the DOM-attribute / module `instances` bookkeeping.
    // ------------------------------------------------------------------------
    public func isDisposed() -> Bool { return _disposed }

    // upstream: `this.setOption({ series: [] }, true)`.
    public func clear() {
        if _disposed { return }
        setOption(["series": [Any]()], notMerge: true)
    }

    public func dispose() {
        if _disposed { return }
        _disposed = true

        let api = _api!
        let ecModel = _model
        if let ecModel = ecModel {
            for component in _componentsViews { component.dispose(ecModel, api) }
            for chart in _chartsViews { chart.dispose(ecModel, api) }
        }
        // upstream: `chart._zr.dispose()` — the driver owns no zr (host-owned); clear its display list.
        _ = root.removeAll()
        storage.delAllRoots()

        // Release references (upstream sets the fields to null to reduce retained memory).
        _model = nil
        _chartsMap = [:]
        _componentsMap = [:]
        _chartsViews = []
        _componentsViews = []
        _chartViewByModel = [:]
        _componentViewByModel = [:]
    }

    // ------------------------------------------------------------------------
    // resize — ported from `ECharts.prototype.resize` (echarts.ts:1449-1511). The driver takes an
    //   explicit width/height (there is no DOM to auto-measure — the same adaptation `init` makes), sets
    //   them, and re-runs the update pipeline so the coordinate systems re-layout at the new size.
    //   The media-query re-resolve (`ecModel.resetOption('media')`) + zr.resize are documented-deferred
    //   (see the file header); everything else mirrors upstream (main-process guard + flush + updated event).
    // ------------------------------------------------------------------------
    public func resize(width: Double, height: Double, silent: Bool = false) {
        // upstream: `if (this[IN_EC_CYCLE_KEY]) { error('`resize` should not be called during main process.'); return; }`
        if _inEcCycle { return }
        if _disposed { return }

        _width = width
        _height = height

        guard _model != nil else { return }

        _inEcCycle = true
        // upstream: `updateMethods.update.call(this, { type: 'resize', animation: { duration: 0, … } });`
        update()
        _inEcCycle = false

        flushPendingActions(silent)
        triggerUpdatedEvent(silent)
    }

    // ------------------------------------------------------------------------
    // appendData — ported from `ECharts.prototype.appendData` (echarts.ts:1634-1663). The streaming/
    //   incremental data API: resolves the target series by index and forwards the new data to
    //   `SeriesModel.appendData`, then marks the scheduler unfinished + wakes the zr so the next frame
    //   renders the appended points. Does NOT rescale coord extents (see the upstream NOTICE — the
    //   initial extent must be specified via `xxxAxis.data` / `xxxAxis.min/max`).
    // ------------------------------------------------------------------------
    public func appendData(seriesIndex: Int, data: ArrayLike<Any>) {
        // if (this._disposed) { disposedWarning(this.id); return; }
        if _disposed { return }
        // const ecModel = this.getModel(); const seriesModel = ecModel.getSeriesByIndex(seriesIndex);
        guard let ecModel = _model,
              let seriesModel = ecModel.getSeriesByIndex(Double(seriesIndex)) else { return }
        // if (__DEV__) { assert(params.data && seriesModel); } — no dev asserts.

        seriesModel.appendData(SeriesAppendDataParams(data: data))

        // `appendData` does not support updating axis scale extent of coordinate systems (see the
        //   upstream NOTICE). Mark the scheduler unfinished + wake the zr so the appended data paints.
        _scheduler?.unfinished = true
        getZr()?.wakeUp()
    }

    // makeActionFromEvent (echarts.ts:1559-1563) is DEFERRED: it consumes an `ECActionEvent` object and
    //   reverts it to a `Payload` via `connectionEventRevertMap`; `Payload` here is a struct (not a dict)
    //   and the method only feeds the unwired cross-chart `connect` mirroring, so a faithful port needs
    //   the `connect`/`ECActionEvent` machinery first (deferred with it).

    // ------------------------------------------------------------------------
    // Public accessors for the host / tests.
    // ------------------------------------------------------------------------
    public func getRoot() -> Group { return root }
    public func getStorage() -> Storage { return storage }
    public func getModel() -> GlobalModel? { return _model }
    /// The ARIA accessibility label generated for the current option (upstream `visual/aria.ts`
    /// sets it as the container's `aria-label` attribute; there is no DOM here, so it is stored on the
    /// ec instance and exposed via this accessor). `nil` when aria is disabled / has no series.
    public func getAriaLabel() -> String? { return _ariaLabel }
    /// The ExtensionAPI bound to this driver (upstream `this._api`). Exposed so the live-view host
    /// (`EChartsView`) can drive the ported axisPointer `axisTrigger(payload, ecModel, api)` on hover.
    public var api: ExtensionAPI { return _api }
    public func getWidth() -> Double { return _width }
    public func getHeight() -> Double { return _height }

    // ------------------------------------------------------------------------
    // Toolbox SaveAsImage host seams (component/toolbox/feature/SaveAsImage.ts). Upstream the feature's
    //   onclick calls `api.getConnectedDataURL(...)` (a DOM canvas → data URL) then triggers a browser
    //   `<a download>`. Headless has neither, so the HOST injects the rasterizer + receives the bytes:
    //     - `getRenderedImage(opts)` renders the current `getRoot()` to encoded PNG/JPEG `Data` (a live
    //        host wires this to NativePainter's `renderToImage` — EChartsKit cannot import NativePainter).
    //     - `onSaveImage(data, filename)` receives the encoded bytes (the "download" — a live host saves
    //        them to disk / shares them). Both nil in pure headless (the export is then a silent no-op).
    //   `EChartsExtensionAPI.getConnectedDataURL` / `.saveAsImage` forward to these, so the ported feature
    //   onclick stays faithful (build the URL via the api, hand the bytes to the host).
    public var getRenderedImage: ((_ opts: [String: Any]) -> Data?)?
    public var onSaveImage: ((_ data: Data, _ filename: String) -> Void)?

    // ------------------------------------------------------------------------
    // Toolbox DataZoom box-select arm state (component/toolbox/feature/DataZoom.ts). Upstream the feature
    //   stores `_isZoomActive` and enables its `BrushController` cover-drag; the host has no live
    //   feature-owned BrushController at drag time, so the arm flag lives on the driver: the
    //   `takeGlobalCursor` action (key 'dataZoomSelect') writes it, and the live host (`EChartsView`)
    //   reads it to switch its rect-drag from a `brush` action to a `dataZoom` box-select. Default off.
    // ------------------------------------------------------------------------
    public var dataZoomSelectActive: Bool = false

    // ------------------------------------------------------------------------
    // The in-flight action payload (upstream: `updateMethods.update(payload)` threads it down through
    //   `renderComponents(ecModel, api, payload)` and the visual stages). This port's update methods take
    //   no payload argument, so `doDispatchAction` parks it here for the duration of the dispatch and
    //   `render()` reads it back (component views' `render`; the brush visual's takeGlobalCursor +
    //   brushSelect gate). `nil` outside a dispatch — i.e. during a `setOption` — which is exactly the
    //   condition upstream's brush visual uses to NOT emit `brushselected` on setOption.
    // ------------------------------------------------------------------------
    fileprivate var _payload: Payload?

    // upstream: `getZr()` returns `this._zr`. This driver owns no ZRender (see ExtensionAPI.getZr's PORT
    //   SEAM note): the live host adds `getRoot()` to its zr, which stamps the `__zr` back-pointer on the
    //   group. Resolve it from there so `api.getZr()` works with zero host wiring. nil in pure headless.
    public func getZr() -> ZRenderType? {
        return root.__zr
    }

    // For `api.getViewOf*` forwarding.
    fileprivate func viewOfComponentModel(_ model: ComponentModel) -> ComponentView? {
        return _componentViewByModel[ObjectIdentifier(model)]
    }
    fileprivate func viewOfSeriesModel(_ model: SeriesModel) -> ChartView? {
        return _chartViewByModel[ObjectIdentifier(model)]
    }
    fileprivate func coordinateSystems() -> [CoordinateSystemMaster] {
        return _coordSysMgr.getCoordinateSystems()
    }
}

// ============================================================================
// Concrete ExtensionAPI backed by the driver (upstream: the `availableMethods` forwarding to
// the `ECharts` instance). Only the members the bar path reads are implemented; the rest inherit
// the abstract `fatalError` (never reached in the bar slice).
// ============================================================================
final class EChartsExtensionAPI: ExtensionAPI {
    private unowned let ec: ECharts
    init(ec: ECharts) {
        self.ec = ec
        super.init(ecInstance: ec)
    }
    override func getWidth() -> Double { ec.getWidth() }
    override func getHeight() -> Double { ec.getHeight() }
    // upstream `availableMethods` binds `getZr` to the ec instance. See ExtensionAPI.getZr's PORT SEAM.
    override func getZr() -> ZRenderType? { ec.getZr() }
    override func getModel() -> GlobalModel { ec.getModel()! }
    override func getCoordinateSystems() -> [CoordinateSystemMaster] { ec.coordinateSystems() }
    override func getViewOfComponentModel(_ componentModel: ComponentModel) -> ComponentView? {
        return ec.viewOfComponentModel(componentModel)   // may be nil: viewless component (e.g. polar)
    }
    override func getViewOfSeriesModel(_ seriesModel: SeriesModel) -> ChartView? {
        return ec.viewOfSeriesModel(seriesModel)   // nil for a legend-filtered / unrendered series
    }
    // upstream: `getComponentByElement(el)` — walk `el` up (via `__hostTarget ?? parent`) to the nearest
    //   element carrying ECData, and resolve the owning component/series model. Used by roam/brush
    //   `onIrrelevantElement`. Base is abstract (fatalError); provide a concrete resolver for the roam path.
    //   Returns a fresh EMPTY sentinel model (mainType "") when nothing resolves — `onIrrelevantElement`
    //   treats that conservatively (roam proceeds), matching upstream's null-ish default.
    override func getComponentByElement(_ el: Element) -> ComponentModel {
        var cur: Element? = el
        while let e = cur {
            let ecData = innerStore.getECData(e)
            if let si = ecData.seriesIndex, let sm = ec.getModel()?.getSeriesByIndex(si) {
                return sm
            }
            if let mt = ecData.componentMainType,
               let cm = ec.getModel()?.getComponent(mt, ecData.componentIndex) {
                return cm
            }
            cur = e.__hostTarget ?? (e.parent as? Element)
        }
        return ComponentModel(nil, nil, ec.getModel())
    }
    // upstream: `dispatchAction` is bound onto the api from `ecInstance` (availableMethods). Forward to
    //   the driver's ported round-trip (an action/view handler calls `api.dispatchAction(...)`).
    override func dispatchAction(_ payload: Payload, _ opt: DispatchActionOpt? = nil) {
        ec.dispatchAction(payload, opt)
    }

    // upstream: the api's emphasis seam (`availableMethods`) binds `enterEmphasis`/`leaveEmphasis`/
    //   `enterBlur`/`leaveBlur`/`enterSelect`/`leaveSelect` to the module-level `util/states` functions.
    //   These forward to the ported `states.*` element-state helpers (TASK 1). Views + the payload-driven
    //   `updateDirectly` reach element state through these methods (echarts.ts `availableMethods`).
    // upstream: `api.getConnectedDataURL(opts)` — a data-URL string of the rendered chart. The port
    //   returns the ENCODED PNG/JPEG bytes rendered by the host-injected `ECharts.getRenderedImage`
    //   (nil in pure headless). See the SaveAsImage host seam note on ECharts.
    override func getConnectedDataURL(_ opts: [String: Any]) -> Data? {
        return ec.getRenderedImage?(opts)
    }
    // PORT SEAM: upstream downloads the data URL via a DOM `<a download>`; the port hands the encoded
    //   bytes to the host's `ECharts.onSaveImage` callback.
    override func saveAsImage(_ data: Data, _ filename: String) {
        ec.onSaveImage?(data, filename)
    }
    // Toolbox DataZoom box-select arm state (see ECharts.dataZoomSelectActive). Read by the feature's
    //   `zoom` onclick (so the toggle survives the feature being rebuilt each render) + written by the
    //   `takeGlobalCursor` action handler.
    var dataZoomSelectActiveValue: Bool { ec.dataZoomSelectActive }
    func setDataZoomSelectActive(_ active: Bool) { ec.dataZoomSelectActive = active }

    override func enterEmphasis(_ el: Element, _ highlightDigit: Double? = nil) {
        states.enterEmphasis(el, highlightDigit)
    }
    override func leaveEmphasis(_ el: Element, _ highlightDigit: Double? = nil) {
        states.leaveEmphasis(el, highlightDigit)
    }
    override func enterBlur(_ el: Element) {
        states.enterBlur(el)
    }
    override func leaveBlur(_ el: Element) {
        states.leaveBlur(el)
    }
    override func enterSelect(_ el: Element) {
        states.enterSelect(el)
    }
    override func leaveSelect(_ el: Element) {
        states.leaveSelect(el)
    }
}
