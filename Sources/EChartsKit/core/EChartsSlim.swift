// Ported (SLIM SUBSET) from echarts/src/core/echarts.ts — keep in sync with upstream.
//
// ============================================================================
// WHAT THIS FILE IS
// ============================================================================
// `echarts/src/core/echarts.ts` is a 3400-line module. This file is a DELIBERATELY MINIMAL,
// heavily-documented subset that renders ONE vertical slice — a cartesian **bar** chart (grid +
// x/y axis + bar series) — end-to-end through the already-ported model → coord → view pipeline,
// emitting a ZRenderKit `Group` of bar `Rect`s + axis line/tick/label elements.
//
// It faithfully mirrors the STAGE ORDER of upstream `updateMethods.update` (see §UPDATE below),
// but every stage that a bar chart does not strictly need is a documented `PORT-TODO` skip. The
// heavy `ECharts` machinery that is intentionally NOT reproduced here:
//   - The `Scheduler` task/pipeline graph. Upstream runs each stage as a `Task` (`performXxxTasks`
//     / `renderTask.perform`). Here the stages are invoked DIRECTLY (documented deviation) — the
//     scheduler's progressive/stream/incremental machinery is out of the bar scope.
//   - `prepare()` + `restorePipelines`/`prepareStageTasks`/`plan` (Scheduler pipeline building).
//   - `updateTransform`/`updateView`/`updateLayout`/`updateVisual` fast-path update methods.
//   - Actions / events / lifecycle triggers / connect / loading / SSR / theme / media query.
//   - `allocateZlevels`, `clearStates`/`updateStates`/`updateZ`/`updateBlend`, hover/emphasis.
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
// two concrete stand-in subclasses (`SlimXAxisModel` / `SlimYAxisModel`) that add the
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

/// Merge the per-type `axisDefault` (show:true + axisLine/axisTick/axisLabel/splitLine sub-defaults)
/// UNDER the model's own option, so `axisModel.get("show")` / the AxisBuilder's sub-option reads resolve.
/// This stands in for the deferred `AxisModel.mergeDefaultAndTheme` default-merge (the real
/// axisModelCreator path injects `getDefaultOption()`; the slim stand-in models never run through it).
/// Overwrite=false → user option wins; nested dicts deep-merge (util.merge).
private func slimMergeAxisDefaults(_ model: CartesianAxisModel, _ defaultType: String) {
    guard var opt = model.option as? [String: Any] else { return }
    let axisType = (opt["type"] as? String) ?? defaultType
    guard let def = axisDefault.option[axisType] as? [String: Any] else { return }
    _ = util.merge(&opt, def, false)
    model.option = opt
}

/// `xAxis` model. `static type = 'xAxis'` so `ComponentModel.registerClass` keys it correctly.
final class SlimXAxisModel: CartesianAxisModel, AxisModelExtendedInCreator {
    override class var type: ComponentFullType { return "xAxis" }
    private var __ordinalMeta: OrdinalMeta?
    override func optionUpdated(_ n: ModelOption?, _ isInit: Bool) {
        super.optionUpdated(n, isInit)
        slimMergeAxisDefaults(self, "category")
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

/// `yAxis` model (value axis in a vertical bar chart; symmetric to `SlimXAxisModel`).
final class SlimYAxisModel: CartesianAxisModel, AxisModelExtendedInCreator {
    override class var type: ComponentFullType { return "yAxis" }
    private var __ordinalMeta: OrdinalMeta?
    override func optionUpdated(_ n: ModelOption?, _ isInit: Bool) {
        super.optionUpdated(n, isInit)
        slimMergeAxisDefaults(self, "value")
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
final class SlimInstallRegisters: EChartsExtensionInstallRegisters {
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
// The slim ECharts driver.
// ============================================================================
public final class EChartsSlim: EChartsType {

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

    // ---- action-dispatch state (mirrors upstream `ECharts` action fields) ----
    /// Actions dispatched WHILE a render/update cycle is in progress are queued here and drained
    /// after it finishes (upstream: `private _pendingActions: Payload[] = []`).
    private var _pendingActions: [Payload] = []
    /// Re-entrancy guard: true while inside the update cycle (`doDispatchAction`). Upstream stores this
    /// under the symbol-ish key `IN_EC_CYCLE_KEY` (`'__flagInMainProcess'`).
    private var _inEcCycle = false

    // upstream: echarts.init(dom, theme?, opts?) — `theme` is a registered name or a theme object,
    //   `opts.locale` a registered lang name or a locale object. Both are optional; nil theme merges
    //   nothing, nil locale resolves to `locale.SYSTEM_LANG` (EN).
    public init(width: Double, height: Double, theme: Any? = nil, locale: Any? = nil) {
        self._width = width
        self._height = height
        self._userTheme = theme
        self._userLocale = locale
        EChartsSlim.installOnce()
        // `_api` needs `self`; all stored properties are initialized above, so it is safe now.
        self._api = SlimExtensionAPI(ec: self)
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
            return EChartsSlim._themeStorage[name] ?? [:]
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
    private static let _registers = SlimInstallRegisters()
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

    static func installOnce() {
        if _installed { return }
        _installed = true

        // -- core/locale.ts module side-effects -- registerLocale('EN', langEN) + registerLocale('ZH',
        //   langZH). A Swift caseless enum has no module init slot, so the default registration is run
        //   here (idempotent). `GlobalModel.getLocaleModel()` returns the per-instance locale Model built
        //   from `locale.createLocaleObject(SYSTEM_LANG)` in setOption below.
        locale.registerDefaultLocales()

        // -- theme/dark.ts + echarts.ts `registerTheme('dark', darkTheme)` -- register the built-in dark
        //   theme so `EChartsSlim(width:height:theme: "dark")` resolves it by name (mirrors the upstream
        //   `themeStorage` lookup in `echarts.init(dom, theme)`).
        registerTheme("dark", darkTheme.theme)

        // -- features/index.ts `use(install)` for the AxisBreak feature -- registers the concrete
        //   scale-break helper (scale/breakImpl.ts `installScaleBreakHelper`). Idempotent; enables the
        //   `xxxAxis.breaks` option. Non-broken axes stay byte-identical (empty breaks => brk stays nil).
        installScaleBreakHelper()

        // -- component/dataset/install.ts -- registerComponentModel(DatasetModel) +
        //   registerComponentView(DatasetView). Must be registered so a `dataset: [...]` option
        //   instantiates a `DatasetModelImpl` (its `init` builds a SourceManager); series then query
        //   it via `querySeriesUpstreamDatasetModel`. `datasetInstall` registers the model in the
        //   `ComponentModel` registry (the path GlobalModel reads) and the view in the `ComponentView`
        //   registry; the slim path resolves the (no-op) DatasetView via the `_componentViewFactories`
        //   entry below (upstream `DatasetView` renders nothing).
        datasetInstall(EChartsSlim._registers)

        // -- component/grid/installSimple.ts + coord/cartesian --
        ComponentModel.registerClass(GridModel.self)                       // registerComponentModel(GridModel)
        ComponentModel.registerClass(SlimXAxisModel.self)                  // axisModelCreator(..,'x',..)  (stand-in)
        ComponentModel.registerClass(SlimYAxisModel.self)                  // axisModelCreator(..,'y',..)  (stand-in)
        CoordinateSystemManager.register("cartesian2d", GridCoordinateSystemCreator()) // registerCoordinateSystem('cartesian2d', Grid)

        // -- chart/bar/install.ts --
        ComponentModel.registerClass(BarSeriesModel.self)                  // registerSeriesModel(BarSeries)
        // registerLayout(VISUAL.LAYOUT, createCrossSeriesLayoutHandler(bar)) → `_barLayoutHandler`.
        // registerLayout(PROGRESSIVE_LAYOUT, createProgressiveLayout(bar)) → PORT-TODO: the non-large
        //   bar path recomputes per-item geometry inside `BarView.render`, so the progressive layout
        //   task is not needed for a basic render (see barGrid.swift `createProgressiveLayout` note).
        // registerProcessor(PROCESSOR.STATISTIC, dataSample) → PORT-TODO: down-sampling not needed.
        registerBarGridAxisHandlers(_registers)   // populates axisStatistics `clientsForLookup` +
                                                  //   captures the axis-statistics processor (see registrar).
                                                  //   NOTE: registers BOTH 'bar' and 'pictorialBar' axis
                                                  //   handlers, so pictorialBar needs no separate call.

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
        //   PORT-TODO. Cell fill comes from the per-datum color the visualMap ENCODING wrote, so a
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
        //   `render`/`update` below. The `dataFilter('chord')` processor is a no-op in this slim path
        //   (no legend-select provider ported) — PORT-TODO; see chart/chord/chordInstall.swift.
        ComponentModel.registerClass(ChordSeriesModel.self)

        // -- chart/lines/install.ts (minimal) -- registerChartView(LinesView) +
        //   registerSeriesModel(LinesSeries) + registerLayout(linesLayout) + registerVisual(linesVisual).
        //   Lines is a coord-space series (default coord 'geo'; ONLY cartesian2d is rendered by the ported
        //   static view — polar/geo/calendar are PORT-TODO in linesLayout/LinesView). `linesLayout` is a
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
        //   create/update (it casts seriesModel.coordinateSystem to Single). The dataFilter processor is a
        //   no-op in this slim path (no legend-select provider); see themeRiverInstall.swift.
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
        //   registerVisual(legendIcon 'roundRect') → PORT-TODO: deferred (legend-select provider not wired).
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
        //   x/y stand-ins (SlimXAxisModel), the polar axis models are the REAL AngleAxisModel/RadiusAxisModel
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
        //   parallelAxis components from parallel.parallelAxisDefault) runs in setOption. The brush/axis-drag/
        //   active-interval selection ACTIONS are DEFERRED (// PORT-TODO in ParallelComponentView/ParallelAxisModel).
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
        //   PORT-TODO: matrixPrepareCustom (custom-series coord hook) is unregistered — same as
        //   calendarPrepareCustom (no prepareCustom registry yet). Cell interaction is // PORT-TODO in MatrixView.
        CoordinateSystemManager.register("matrix", MatrixCoordinateSystemCreator()) // registerCoordinateSystem('matrix', Matrix)
        ComponentModel.registerClass(MatrixModel.self)                              // registerComponentModel(MatrixModel)

        // -- component/geo/install.ts (geo coordinate system, the SEVENTH) --
        //   registerCoordinateSystem('geo', geoCreator) + registerComponentModel(GeoModel) +
        //   registerComponentView(GeoView) (factory above) + registerMap/getMap (geoSourceManager).
        //   The geo coord projects [lng, lat] to a pixel via the `View` transform (+ optional projection);
        //   GeoView draws the static GeoJSON region outlines + labels backdrop.
        //   `geoCreator` is the ported singleton `GeoCreator()` (conforms to CoordinateSystemCreator directly).
        //   PORT-TODO (DEFERRED with events/roam): geoToggleSelect/geoSelect/geoUnSelect/geoRoam actions;
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
        //   api.coord/api.size. transitions/morph/states are PORT-TODO. customInstall.swift is commented-only
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
        //   The `aria.decal.show` decal (SVG-pattern) generation is a PORT-TODO (decal palette infra
        //   unported). See Sources/EChartsKit/component/aria/ariaVisual.swift + ariaPreprocessor.swift.

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
        installTimelineAction(EChartsSlim._registers)                      // registerAction('timelineChange'/'timelinePlayChange')

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
        installDataZoomAction(EChartsSlim._registers)                      // registerAction('dataZoom', ...)

        // -- component/tooltip/install.ts -- registerComponentModel(TooltipModel) +
        //   registerComponentView(TooltipView) + ... . Phase 31 ports ONLY the host-independent
        //   tooltip CONTENT model (formatTooltip → markup → html/richText string). The on-screen
        //   TooltipView + the hover TRIGGER are DEFERRED (need the live-view host — a later phase),
        //   so ONLY the model is registered here (no view). `dependencies = ['axisPointer']`; the
        //   axisPointer model itself is a `[String: Any]` stub (see TooltipModel.swift PORT-TODO).
        ComponentModel.registerClass(TooltipModel.self)                    // registerComponentModel(TooltipModel)
        installTooltipActions(EChartsSlim._registers)                      // registerAction('showTip'/'hideTip', noop)

        // -- component/axisPointer/install.ts (Phase 35) -- registerComponentModel(AxisPointerModel) +
        //   registerPreprocessor (ensure a global axisPointer option always exists — done in setOption) +
        //   registerProcessor(PRIORITY.PROCESSOR.STATISTIC, { overallReset: coordSysAxesInfo = collect(...) })
        //   + registerAction('updateAxisPointer', axisTrigger). The axisPointer VIEW (the drawn crosshair)
        //   is DEFERRED (Phase 36) — no view factory is registered, so the component renders nothing; only
        //   the DATA core (collect → coordSysAxesInfo, consumed by axisTrigger for the tooltip trigger:"axis"
        //   path) is wired. The `collect` run itself lives in `update()` (statistic stage), see below.
        ComponentModel.registerClass(AxisPointerModel.self)                 // registerComponentModel(AxisPointerModel)

        // -- component/brush/install.ts (Phase 44, RECT core) -- registerComponentModel(BrushModel) +
        //   registerVisual(PRIORITY.VISUAL.BRUSH, { seriesTypes: '', reset: ...brushVisual }) +
        //   installBrushAction (registerAction 'brush'/'brushSelect'/'brushEnd'). The brush VIEW +
        //   toolbox button + BrushController (polygon/lineX/lineY drag UI) are DEFERRED; only the DATA
        //   core runs: `layoutCovers` (build per-area boundingRects) + `brushVisual` (in→inBrush /
        //   out→outOfBrush → dim unselected via blur) execute in `update()`'s visual stage below, and
        //   a minimal rect-drag in EChartsView dispatches `type:"brush"` with the dragged coordRange.
        ComponentModel.registerClass(BrushModel.self)                       // registerComponentModel(BrushModel)
        installBrushAction(EChartsSlim._registers)                          // registerAction('brush'/'brushSelect'/'brushEnd')

        // -- component/toolbox/install.ts (Phase 49, ACTION core) -- registerComponentModel(ToolboxModel) +
        //   the `restore` (ecModel.resetOption('recreate')) + `changeMagicType` (ecModel.mergeOption) action
        //   handlers. The on-canvas icon VIEW + host-dependent features (saveAsImage/dataView/dataZoom-select/
        //   brush button) are DEFERRED; the option-expressible feature DATA cores are wired.
        ComponentModel.registerClass(ToolboxModel.self)                     // registerComponentModel(ToolboxModel)
        registerToolboxFeatures()                                           // registerFeature('saveAsImage'/'magicType'/'dataZoom'/'restore')
        installToolboxActions(EChartsSlim._registers)                       // registerAction('restore'/'changeMagicType')

        // -- component/marker/installMark{Point,Line,Area}.ts (Phase 52) --
        //   registerComponentModel(MarkPointModel/MarkLineModel/MarkAreaModel) + the auto-enable
        //   preprocessors (called in setOption). The COORDINATE markers now render: the Phase-51 axis
        //   witnesses fixed `coordSys.getAxis/getOtherAxis`, so the master marker model's per-series
        //   submodel creation + the MarkerView `dataTransform`/`dataToPoint` path resolve. The STATISTIC
        //   markers (type:'min'/'max'/'average'/'median') still depend on `SeriesModel.indicesOfNearest`
        //   (stubbed → dataIndex 0) — the value is computed by `numCalculate` but the anchor index is
        //   approximate; the coordinate-value markers (`{yAxis:v}` / `{xAxis:v}` / `{coord:[x,y]}`) are exact.
        ComponentModel.registerClass(MarkPointModel.self)                  // registerComponentModel(MarkPointModel)
        ComponentModel.registerClass(MarkLineModel.self)                   // registerComponentModel(MarkLineModel)
        ComponentModel.registerClass(MarkAreaModel.self)                   // registerComponentModel(MarkAreaModel)

        // -- component/transform/install.ts -- registers.registerTransform(filterTransform) +
        //   registers.registerTransform(sortTransform). Built-in data transforms live in the Phase-27
        //   registry (data/helper/transform.swift); `transformInstall` registers both against it so a
        //   `dataset: { transform: { type: "filter" | "sort", config: {...} } }` resolves WITHOUT the
        //   user pre-registering. The "echarts:" namespace makes them callable via the bare "filter"/"sort".
        transformInstall(EChartsSlim._registers)

        // -- core/echarts.ts `Default actions` (echarts.ts:3373-3411) -- highlight/downplay/select/
        //   unselect/toggleSelect. Upstream registers these at module load; the slim driver has no
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
        registerTreeRoamAction()
        registerTreemapRoamAction()
        registerSankeyRoamAction()

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
        "toolbox": { ToolboxView() }
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

        let ecModel = GlobalModel()
        let om = OptionManager(_api)
        // init(option, parentModel, ecModel, theme, locale, optionManager)
        //   theme: resolved from the `init(theme:)` arg (a registered name or a dict); merged into the
        //   option by GlobalModel.mergeTheme (backgroundColor / textStyle / axis colors / palette).
        //   locale: `createLocaleObject(opts.locale || SYSTEM_LANG)` — the default (EN) locale Model
        //   feeds getLocaleModel() reads (legend selector, time-axis month/day names, toolbox titles).
        ecModel.`init`(nil, nil, nil, resolveTheme(), resolveLocale(), om)
        ecModel.setOption(opt, nil, [])
        self._model = ecModel

        update()
    }

    // ------------------------------------------------------------------------
    // §UPDATE — faithful stage ORDER of `updateMethods.update` (echarts.ts:1880), minimal bodies.
    // ------------------------------------------------------------------------
    private func update() {
        guard let ecModel = _model else { return }          // upstream: if (!ecModel) return;
        let api = _api!

        // (0) resetCachePerECFullUpdate — upstream `updateMethods.update` (echarts.ts:1892) clears the
        //     per-full-update cache at the start of EVERY update cycle. Required for idempotency: a
        //     `dispatchAction`-driven re-render runs update() a 2nd time on the same GlobalModel, and
        //     without this the axis-statistics <axis,series> association maps (+ the DEV duplicate-pair
        //     check in associateSeriesWithAxis) carry stale state and trip an assert.
        resetCachePerECFullUpdate(ecModel)

        // (1) restoreData — re-derive component/series state (upstream: scheduler.restoreData).
        ecModel.restoreData()

        // (2) performSeriesTasks — perform each series' DATA task. Its reset (`dataTaskReset`) is
        //     `setData(getRawData().cloneShallow())`, which populates the `getData()` result (the inner
        //     data slot). Upstream drives this through the Scheduler pipeline (`renderTask.perform`);
        //     with the Scheduler unported (`getCurrentTask` returns nil), the task reset is invoked
        //     directly here — otherwise `getData()` force-unwraps a nil inner data (Series.swift:387).
        ecModel.eachSeries { seriesModel, _ in
            _ = dataTaskReset(seriesModel.dataTask.context)
        }

        // (3) coordSysMgr.create — build the Grid coordinate system(s), lay them out on the container
        //     rect, and inject `coordinateSystem` into each series (Grid.create → injectCoordSysByOption).
        _coordSysMgr.create(ecModel, api)
        // lifecycle.trigger('coordsys:aftercreate', ...) — PORT-TODO: lifecycle not ported (no listeners
        //     needed for a bar chart).

        // PROCESSOR (FILTER) — dataZoom (upstream `registerProcessor(PRIORITY.PROCESSOR.FILTER,
        //   dataZoomProcessor)`). Calculates each dataZoom's window, resets the target axes' raw-extent
        //   zoom bounds, and FILTERS each target series' data to the window. Runs at FILTER priority, i.e.
        //   BEFORE the STATISTIC processors below and BEFORE `coordSysMgr.update` reads the (now filtered)
        //   series-data extents, so the axes rescale to the zoomed subset. Self-gates to a no-op when there
        //   is no `dataZoom` component (it iterates `ecModel.eachComponent("dataZoom")`).
        //   `getTargetSeries` must run FIRST: upstream the scheduler calls it during pipeline setup, and it
        //   carries the side-effect of CREATING each `AxisProxy` and stashing it via `setAxisProxyToModel`
        //   (per-ec-prepare cache). `overallReset` then looks those proxies up via `getAxisProxy`. Without
        //   this call the proxies never exist and `overallReset` filters nothing.
        _ = dataZoomProcessor.getTargetSeries?(ecModel, api)
        dataZoomProcessor.overallReset?(ecModel, api, nil)

        // (4) performDataProcessorTasks — the processor subset a bar needs = axis STATISTICS (feeds the
        //     cross-series bar layout). Run the captured processor overallResets.
        // PROCESSOR (dataStack) — upstream `registerProcessor(PRIORITY.PROCESSOR.STATISTIC, dataStackStageHandler)`.
        //   Computes the cumulative `stackResultDimension` / `stackedOverDimension` values for `stack`-grouped
        //   series. MUST run BEFORE the axis-statistics processors + coord update (axis extent reads the
        //   stacked totals) and before the cross-series bar layout (reads the stacked base). Without this,
        //   stacked bar/line series render overlaid at the shared baseline instead of stacked.
        dataStack(ecModel)

        for processor in EChartsSlim._registers.capturedProcessors {
            processor(ecModel)
        }

        // PROCESSOR — graph categoryFilter (upstream `registerProcessor(PROCESSOR.FILTER, categoryFilter)`).
        //   Filters graph nodes by legend selection; self-gates to a no-op when no legend component is
        //   present. Must run BEFORE the graph layout stage (layout reads the filtered data), so it lives
        //   in the data-processor stage like upstream. OVERALL handler — invoke its overallReset directly.
        graphCategoryFilterStageHandler.overallReset?(ecModel, api, nil)

        // PROCESSOR (STATISTIC) — map data statistic (upstream `registerProcessor(PROCESSOR.STATISTIC,
        //   mapDataStatisticStageHandler)`). For each map-series group it merges the per-region values across
        //   the sibling series (sum/average/min/max per `mapValueCalculation`), stamps each series'
        //   `seriesGroup` + `originalData`, and replaces `getData()` with the shared/merged statistic data.
        //   MUST run in the data-processor stage (before coord update + visual), so mapSymbolLayout/MapView see
        //   the merged data + `originalData`. OVERALL handler — invoke its overallReset directly.
        mapDataStatisticStageHandler.overallReset?(ecModel, api, nil)

        // PROCESSOR (STATISTIC) — axisPointer coordSysAxesInfo (upstream component/axisPointer/install.ts
        //   `registerProcessor(PRIORITY.PROCESSOR.STATISTIC, { overallReset(ecModel, api) {
        //     (ecModel.getComponent('axisPointer')).coordSysAxesInfo = collect(ecModel, api); } })`).
        //   Builds the axisPointerModel/axis/coordSys/series association tree that axisTrigger consumes for
        //   the tooltip trigger:"axis" path. Must run after coord systems are created (stage 3) and series
        //   data processed (stage 2/4). Self-gates: `collect` returns an (empty) result when no axisPointer
        //   component exists; the stash is a no-op when the component is absent.
        if let apModel = ecModel.getComponent("axisPointer") as? AxisPointerModel {
            apModel.coordSysAxesInfo = collect(ecModel, api)
        }

        // updateStreamModes(...) — PORT-TODO skip (progressive/stream rendering out of scope).

        // (5) coordSysMgr.update — update axis pixel + data extents from the (now processed) series data,
        //     and build the axis tick/label geometry (Grid.update → resize → createAxisBiulders).
        _coordSysMgr.update(ecModel, api)

        // (6) VISUAL — resolve series/data styles (fill/stroke from palette + itemStyle).
        //     Upstream: clearColorPalette + scheduler.performVisualTasks. Here: run the ported visual
        //     stage handlers directly (visual/style.swift), in upstream registration order.
        performVisualStage(ecModel, api)

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

        // NOTE (brush): upstream runs the brush visual at PRIORITY.VISUAL.BRUSH (5000) — AFTER the LAYOUT
        //   stages (1000–4600). The brush rect selector reads each datum's `getItemLayout` (pixel geometry),
        //   which the slim driver only populates inside `render()`'s layout stages (bar/scatter/etc.). So the
        //   brush visual CANNOT run here (item layout is still nil at this point); it runs at the end of
        //   `render()`, right before `renderSeries` — see the `brushVisual(...)` call there.

        // background / darkMode (zr.setBackgroundColor / setDarkMode) — PORT-TODO: the driver exposes a
        //     bare Group; background is a host concern.

        // (7) LAYOUT + RENDER — `render(this, ecModel, api, ...)`.
        render(ecModel, api)
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
    }

    /// Run an OVERALL_STAGE_TASK handler (has `overallReset`).
    private func runOverallStageHandler(_ handler: StageHandler, _ ecModel: GlobalModel, _ api: ExtensionAPI) {
        handler.overallReset?(ecModel, api, nil)
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
    private func render(_ ecModel: GlobalModel, _ api: ExtensionAPI) {
        // allocateZlevels(ecModel) — PORT-TODO skip (single grid + one series; default z ordering).

        // Reset accumulated views + display before rebuilding. The slim driver rebuilds everything each
        //   render (no notMerge/replaceMerge reuse, no incremental transitions), and `setOption` installs
        //   a FRESH GlobalModel — but `root`, the view registries, and `storage` are instance state that
        //   persists across calls. When ONE instance is reused across successive setOption calls (the live
        //   EChartsHostView path — switching demos), the previous render's view groups otherwise linger in
        //   `root` (and `renderComponents` would even re-render a stale component from its old model),
        //   leaving the prior chart visible under the new one. `root.removeAll()` also unregisters each
        //   removed child from the live zr (storage + animation). This is the slim stand-in for upstream
        //   `prepareView`'s dead-view dispose pass (echarts.ts:1687); real view reuse/diff is deferred.
        _ = root.removeAll()
        storage.delAllRoots()
        _componentsViews.removeAll()
        _chartsViews.removeAll()
        _componentsMap.removeAll()
        _chartsMap.removeAll()
        _componentViewByModel.removeAll()
        _chartViewByModel.removeAll()

        // BACKGROUND — upstream `echarts._updateBackground` calls `zr.setBackgroundColor(backgroundColor)`
        //   (a painter-level clear color). The slim driver renders into a bare Group and has no painter clear
        //   hook (that is a host concern, e.g. CALayerPainter's white), so instead draw the resolved
        //   top-level `backgroundColor` as a full-canvas Rect BEHIND everything — added first so it paints
        //   under all component/series groups, and host-independent (native PNG + live view both show it).
        //   This is what makes the dark theme's dark ground actually visible. Transparent/absent → no rect
        //   (the host clear shows through, preserving the default white). Gradient backgrounds: PORT-TODO
        //   (only the string form is handled; the dark theme + explicit `backgroundColor` option are strings).
        if let bg = ecModel.get("backgroundColor", true) as? String,
           !bg.isEmpty, bg != "transparent", bg != "rgba(0,0,0,0)" {
            var shape = RectShape()
            shape.x = 0
            shape.y = 0
            shape.width = _width
            shape.height = _height
            let bgRect = Rect([
                "shape": shape as PathShape,
                "style": ["fill": bg] as [String: Any],
                "silent": true,
                "z2": -Double.greatestFiniteMagnitude
            ])
            _ = root.add(bgRect)
        }

        prepareView(isComponent: true, ecModel: ecModel, api: api)
        prepareView(isComponent: false, ecModel: ecModel, api: api)

        renderComponents(ecModel, api)

        // LAYOUT — bar cross-series layout (sets bandWidth/offset/size on each series' data layout).
        //   Depends on the axis statistics computed in stage (4).
        EChartsSlim._barLayoutHandler.overallReset?(ecModel, api, nil)
        // LAYOUT (per item) — the bar PROGRESSIVE_LAYOUT handler computes each bar's x/y/width/height
        //   from bandWidth/offset/size + the cartesian `dataToPoint`, and stores it via
        //   `data.setItemLayout`. This is a SERIES_STAGE_TASK (has `reset`), so drive it through the same
        //   `runSeriesStageHandler` used for the visual stages (the `next`-iterator fix above makes its
        //   `progress` executor actually iterate the data). `BarView.getLayoutCartesian2D` consumes it.
        runSeriesStageHandler(EChartsSlim._barProgressiveLayoutHandler, ecModel, api)

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
            EChartsSlim._pictorialBarLayoutHandler.overallReset?(ecModel, api, nil)
            runSeriesStageHandler(EChartsSlim._pictorialBarProgressiveLayoutHandler, ecModel, api)
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
        //   before visual); the slim driver reproduces that by running BOTH here (layout, then visual),
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
        sunburstLayoutStageHandler.overallReset?(ecModel, api, nil)
        sunburstVisualStageHandler.overallReset?(ecModel, api, nil)

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
        //   live per-frame tick is a PORT-TODO — see forceLayout.swift). Runs alongside the other two.
        graphForceLayoutStageHandler.overallReset?(ecModel, api, nil)
        graphCategoryVisualStageHandler.overallReset?(ecModel, api, nil)
        graphEdgeVisualStageHandler.overallReset?(ecModel, api, nil)

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
        //   but the slim driver invokes it directly (mirrors sankeyLayout).
        chordCircularLayout(ecModel, api)

        // LAYOUT — lines per-item point projection (upstream `registerLayout(linesLayout)`). A
        //   SERIES_STAGE_TASK (seriesType 'lines') whose `reset`→`progress` maps each line's data-space
        //   coords through the cartesian `dataToPoint` (plus the quadratic curveness control point) and
        //   stores it with `data.setItemLayout(i, pts)`. Same wiring as candlestickLayout. `LinesView.render`
        //   inlines the same math (like ScatterView/LineView), so the view does not strictly depend on this
        //   stage, but it is run here for fidelity to the upstream pipeline. Only cartesian2d is handled
        //   (polar/geo/calendar are PORT-TODO in linesLayout).
        runSeriesStageHandler(linesLayout, ecModel, api)

        // LAYOUT — radar point rings (upstream `registerLayout(radarLayoutStageHandler)`). Radar HAS a
        //   (non-cartesian) coordinate system, already built + updated by `_coordSysMgr.create`/`.update`
        //   (update() stages 3/5). This OVERALL stage maps each datum's per-indicator values through
        //   `coordSys.dataToPoint` into a CLOSED point ring (axes+1 points, last == copy of first) and
        //   stores it with `data.setItemLayout`, which `RadarView.render` reads back. Bare 1-arg handler
        //   (like boxplotLayout); the radarLayoutStageHandler wrapper exists for the upstream registrar,
        //   but the slim driver invokes `radarLayout(ecModel)` directly (mirrors pieLayout).
        radarLayout(ecModel)

        // LAYOUT — themeRiver stream bands (upstream `registerLayout(themeRiverLayoutStageHandler)`).
        //   ThemeRiver HAS a (non-cartesian) single coordinate system, already built + updated by
        //   `_coordSysMgr.create`/`.update` (update() stages 3/5). This OVERALL stage reads the Single coord
        //   rect + axis orient and writes each datum's {layerIndex,x,y0,y} band point (+ a "layoutInfo" rect/
        //   boundaryGap) via `data.setItemLayout`/`data.setLayout`, which `ThemeRiverView.render` reads back
        //   to draw one Polygon per layer. Run AFTER the coord update (it casts seriesModel.coordinateSystem
        //   to Single). `themeRiverLayoutStageHandler` wraps this for the upstream registrar, but the slim
        //   driver invokes `themeRiverLayout(ecModel, api)` directly (mirrors sankeyLayout / radarLayout).
        themeRiverLayout(ecModel, api)

        // LAYOUT — map region-center symbols (upstream `registerLayout(mapSymbolLayoutStageHandler)`). For
        //   each map-series group with its own geo, this OVERALL stage projects each region center through
        //   the injected Geo (`geo.dataToPoint(region.getCenter())`) and stores `{point, offset}` on the
        //   per-series `originalData` item layout (the legend symbol positions), then stamps `showLabel` on
        //   the main series' data so label-less regions still get a name label. Reads `originalData` (set by
        //   the mapDataStatistic processor in stage 4) + the Geo coord (set by geoCreator in stage 3), so it
        //   runs here after both. `mapSymbolLayoutStageHandler` wraps this for the upstream registrar, but the
        //   slim driver invokes `mapSymbolLayout(ecModel)` directly (mirrors sankeyLayout / radarLayout).
        mapSymbolLayout(ecModel)

        // VISUAL — parallel per-line opacity (upstream `registerVisual(PRIORITY.VISUAL.BRUSH, parallelVisual)`).
        //   Parallel HAS a coordinate system, already built + updated by `_coordSysMgr.create`/`.update`
        //   (update() stages 3/5). This SERIES_STAGE_TASK sets each line's item-visual `style.opacity` from
        //   the (deferred) active-state → in the static-render phase every row is 'normal', giving each
        //   polyline the `lineStyle.opacity`. ParallelView.render reads that item-visual style back. Run
        //   AFTER the generic performVisualStage (it only extends `opacity` onto the existing style bag).
        runSeriesStageHandler(parallelVisual, ecModel, api)

        // VISUAL (brush) — upstream PRIORITY.VISUAL.BRUSH (5000), the same priority as parallelVisual above,
        //   i.e. AFTER every layout stage (so each datum's `getItemLayout` pixel geometry exists for the rect
        //   selector) and BEFORE `renderSeries` draws (so the in/out-of-brush item-visual color the encoder
        //   writes is picked up by the draw). `brushVisual` self-gates (eachComponent("brush") → no-op when
        //   absent), rebuilds each area's pixel range from its coordRange (layoutCovers), tests every series
        //   datum against the rect selector, and marks inBrush/outOfBrush — recoloring the unselected to the
        //   `outOfBrush` color (dim). This is the Phase-44 KEY deliverable (rect select + dim unselected).
        brushVisual(ecModel, api, nil)

        renderSeries(ecModel, api)

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
        func doPrepare(_ model: ComponentModel) {
            let viewId = "_ec_\(model.componentIndex)_\(model.type)"
            if isComponent {
                let view = _componentsMap[viewId] ?? {
                    // getClass(classType.main, classType.sub) → factory keyed by FULL type first (subtype
                    //   dispatch, e.g. 'visualMap.continuous'), then by mainType (e.g. 'legend' whose full
                    //   type is 'legend.plain'). Most components have full type == mainType, so the fallback
                    //   is what they resolve through.
                    guard let factory = _componentViewFactories[model.type] ?? _componentViewFactories[model.mainType] else {
                        // PORT-TODO: no component view registered for this mainType (out of bar scope).
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
                componentView.__model = model
                _componentViewByModel[ObjectIdentifier(model)] = componentView
            }
            else {
                guard let seriesModel = model as? SeriesModel else { return }
                let view = _chartsMap[viewId] ?? {
                    // ChartView.getClass(classType.sub) → factory keyed by series subType.
                    guard let factory = _chartViewFactories[seriesModel.subType] else {
                        // PORT-TODO: no chart view registered for this subType (only 'bar' in scope).
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

    // renderComponents (echarts.ts:2452) — minimal: clearStates/updateZ/updateStates dropped (states
    // system deferred). Just `componentView.render(model, ecModel, api, payload)`.
    private func renderComponents(_ ecModel: GlobalModel, _ api: ExtensionAPI) {
        let payload = Payload(type: "")
        for componentView in _componentsViews {
            guard let model = componentView.__model else { continue }
            componentView.render(model, ecModel, api, payload)
            // upstream echarts.ts renderComponents runs `updateZ(model, view)` after each render — set
            //   every rendered element's z/zlevel from the model. Coordinate components default z:0.
            updateZ(model, componentView.group, 0)
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
    private func zSlimNum(_ v: Any?) -> Double? {
        if let d = v as? Double { return d }
        if let i = v as? Int { return Double(i) }
        if let n = v as? NSNumber { return n.doubleValue }
        return nil
    }

    private func updateZ(_ model: ComponentModel, _ group: Group, _ defaultZ: Double) {
        let z = zSlimNum(model.get("z")) ?? defaultZ
        let zlevel = zSlimNum(model.get("zlevel")) ?? 0
        // Set z/zlevel on every displayable, preserving z2 (intra-view order). This is the z-LEVEL part
        //   of upstream `doUpdateZ` — enough to lift series (z 2/3) above the coordinate grid (z 0).
        // PORT-NOTE: upstream also lifts each host's attached LABEL to `z2 = subtreeMaxZ2 + 2` (labels
        //   over glyphs). That is intentionally NOT replicated: it would expose treemap tile labels that
        //   the port creates but upstream hides (label overflow/visibility not ported), and the labels
        //   the port DOES want visible (sankey/tree/graph node names) are on hosts with z2 0 and already
        //   paint over the host via the painter's insertion-order tie-break.
        func apply(_ el: Element) {
            if let d = el as? Displayable {
                d.z = z
                d.zlevel = zlevel
            }
            if let tc = el.getTextContent() {   // ZRText is a Displayable — no downcast needed.
                tc.z = z
                tc.zlevel = zlevel
            }
        }
        apply(group)
        _ = group.traverse { el in apply(el); return false }
    }

    // renderSeries (echarts.ts:2472) — minimal: bypass the Scheduler `renderTask.perform` and call
    // `chartView.render(...)` directly (documented deviation; no progressive/incremental rendering).
    private func renderSeries(_ ecModel: GlobalModel, _ api: ExtensionAPI) {
        let payload = Payload(type: "")
        ecModel.eachSeries { seriesModel, _ in
            guard let chartView = self._chartViewByModel[ObjectIdentifier(seriesModel)] else { return }
            chartView.render(seriesModel, ecModel, api, payload)
            // upstream echarts.ts renderSeries runs `updateZ(seriesModel, view)` — lift the series' z above
            //   the coordinate components (default 2) so the data draws over the grid/axis/splitLine.
            self.updateZ(seriesModel, chartView.group, 2)
            // upstream (echarts.ts renderSeries): mark the rendered view alive so the `updateDirectly`
            //   light-update path (callView's `view.__alive` guard) can dispatch highlight/downplay to it.
            chartView.__alive = true
        }
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
        //   PORT-TODO: the slim driver has no `_disposed` flag / lifecycle (dispose is Phase 6b) — no guard.

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
            // PORT-TODO: forces a SYNCHRONOUS zrender repaint of the deferred frame. There is no live zr
            //   this phase, and the slim driver's `update()` ALREADY renders synchronously inside
            //   doDispatchAction, so there is no pending frame to flush → no-op.
        }
        else if flush != false {
            // upstream: `else if (flush !== false && env.browser.weChat) this._throttledZrFlush();`
            // PORT-TODO: the WeChat throttled-flush workaround is N/A (no browser env / live zr).
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
        //   PORT-TODO: no EC update-cycle version counter tracked in the slim driver (used only by the
        //   deferred emphasis/blur state machine — util/states, Phase 30).

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
            if let ar = actionResult { e.eventData = ar }
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
                // markStatusToUpdate(this); — PORT-TODO: no status-needs-update flag tracked in the slim
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
            //   PENDING_UPDATE (a still-dirty setOption awaiting flush) is not tracked in the slim driver,
            //   so there is only the else-branch.
            // PORT-TODO: partial-update — updateView/updateLayout/updateVisual/updateTransform/
            //   prepareAndUpdate (echarts.ts:1868 updateMethods) all COLLAPSE to the full update() this
            //   phase (the scheduler-driven fast paths are unported). 'update' & 'prepareAndUpdate' are
            //   already a full pipeline pass, so this is exact for them and an over-render for the rest.
            self.update()
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

        // if (!silent) { … messageCenter.trigger(eventObj.type, eventObj); … }
        //   PORT-TODO: the message center / user event listeners + refineEvent are not wired yet
        //   (Phase 30+). eventObj is fully built above to preserve the round-trip structure; emission
        //   is the documented no-op.
        _ = eventObj
        _ = silent
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
            // PORT-TODO: no event-listener registry / `trigger` wired yet (Phase 30+). Structure preserved.
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
        //   PORT-TODO: the empty-mainType broadcast branch (`:updateAxisPointer`) is unreachable from the
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
                    // Component (non-series) high-down dispatch.
                    // PORT-TODO (Phase 30, DEFERRED — needs the live pointer/dispatcher host):
                    //   `findComponentHighDownDispatchers` reads `ComponentView.findHighDownDispatchers`,
                    //   which is not wired yet, so the component enterEmphasis/blurComponent path is a
                    //   no-op. The upstream body is preserved here for the re-sync; the SERIES high-down
                    //   path (the primary target of this phase) is fully applied above.
                    //     const { focusSelf, dispatchers } = findComponentHighDownDispatchers(
                    //         m.mainType, m.componentIndex, payload.name, api);
                    //     if (type === HIGHLIGHT && focusSelf && !notBlur)
                    //         blurComponent(m.mainType, m.componentIndex, api);
                    //     if (dispatchers) each(dispatchers, d =>
                    //         type === HIGHLIGHT ? enterEmphasis(d) : leaveEmphasis(d));
                }
            }
            else if states.isSelectChangePayload(payload) {
                // TODO geo
                if let seriesModel = m as? SeriesModel {
                    states.toggleSelectionFromPayload(seriesModel, payload, api)
                    states.updateSeriesElementSelection(seriesModel)
                    // markStatusToUpdate(ecIns);  — PORT-TODO: no status-needs-update flag tracked in the
                    //   slim driver (upstream sets it so a later flush repaints; here the caller repaints).
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
// Concrete ExtensionAPI backed by the slim driver (upstream: the `availableMethods` forwarding to
// the `ECharts` instance). Only the members the bar path reads are implemented; the rest inherit
// the abstract `fatalError` (never reached in the bar slice).
// ============================================================================
final class SlimExtensionAPI: ExtensionAPI {
    private unowned let ec: EChartsSlim
    init(ec: EChartsSlim) {
        self.ec = ec
        super.init(ecInstance: ec)
    }
    override func getWidth() -> Double { ec.getWidth() }
    override func getHeight() -> Double { ec.getHeight() }
    override func getModel() -> GlobalModel { ec.getModel()! }
    override func getCoordinateSystems() -> [CoordinateSystemMaster] { ec.coordinateSystems() }
    override func getViewOfComponentModel(_ componentModel: ComponentModel) -> ComponentView? {
        return ec.viewOfComponentModel(componentModel)   // may be nil: viewless component (e.g. polar)
    }
    override func getViewOfSeriesModel(_ seriesModel: SeriesModel) -> ChartView {
        return ec.viewOfSeriesModel(seriesModel)!
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
