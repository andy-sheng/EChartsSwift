// Ported from echarts/src/core/ExtensionAPI.ts — keep in sync with upstream

import Foundation
import ZRenderKit

// import * as zrUtil from 'zrender/src/core/util';            -> `util` (ZRenderKit)
// import {EChartsType} from './echarts';                      -> PORT-NOTE stub below
//
// import type {CoordinateSystemMaster} from '../coord/CoordinateSystem';  -> PORT-NOTE below (now ported)
// import type Element from 'zrender/src/Element';             -> ZRenderKit.Element
// import type ComponentModel from '../model/Component';       -> ComponentModel
// import type ComponentView from '../view/Component';         -> ComponentView (util/types.swift stub)
// import type ChartView from '../view/Chart';                 -> ChartView (util/types.swift stub)
// import type SeriesModel from '../model/Series';             -> SeriesModel
// import type GlobalModel from '../model/Global';             -> GlobalModel
// import { COMPONENT_MAIN_TYPE_SERIES } from '../util/types'; -> COMPONENT_MAIN_TYPE_SERIES (util/types.swift)

// PORT-NOTE: EChartsType is the public ECharts instance facade; the concrete `ECharts` (core/ECharts.swift)
//   is ported and conforms to it. This protocol is kept as a minimal seam so the `ecInstance` back-pointer
//   and `availableMethods` binding type-check without depending on the full instance API.
public protocol EChartsType: AnyObject {}

// CoordinateSystemMaster (coord/CoordinateSystem.ts) is now ported — see coord/CoordinateSystem.swift.
//   The placeholder protocol previously stubbed here is replaced by the real one there.

private let availableMethods: [String] = [
    "getDom",
    "getZr",
    "getWidth",
    "getHeight",
    "getDevicePixelRatio",
    "dispatchAction",
    "isSSR",
    "isDisposed",
    "on",
    "off",
    "getDataURL",
    "getConnectedDataURL",
    // "getModel",
    "getOption",
    // "getViewOfComponentModel",
    // "getViewOfSeriesModel",
    "getId",
    "updateLabelLayout"
]

// upstream: interface ExtensionAPI extends Pick<EChartsType, (typeof availableMethods)[number]> {}
//   The picked methods (getDom/getZr/getWidth/getHeight/getDevicePixelRatio/dispatchAction/isSSR/
//   isDisposed/on/off/getDataURL/getConnectedDataURL/getOption/getId/updateLabelLayout) are added to
//   each instance dynamically in the constructor via `zrUtil.bind`. See the PORT-NOTE in `init`.

// upstream: abstract class ExtensionAPI
//   `abstract class` → an open (non-final) class whose abstract members `fatalError`
//   (CONVENTIONS §2: TS class → Swift class; abstract base cannot be `final`).
open class ExtensionAPI {

    public init(ecInstance: EChartsType) {
        // zrUtil.each(availableMethods, function (methodName: string) {
        //     (this as any)[methodName] = zrUtil.bind((ecInstance as any)[methodName], ecInstance);
        // }, this);
        // PORT-NOTE: dynamic method binding. Swift cannot copy methods onto an instance at runtime;
        //   the `availableMethods` forwarding to `ecInstance` (getDom/getZr/getWidth/... — see the
        //   interface note above) is replicated as explicit forwarding methods when EChartsType lands
        //   in Phase 6b. `ecInstance` is intentionally not retained here yet.
        _ = ecInstance
        _ = availableMethods
    }

    // Implemented in echarts.js
    open func getCoordinateSystems() -> [CoordinateSystemMaster] {
        fatalError("abstract method ExtensionAPI.getCoordinateSystems must be overridden") // PORT-NOTE: abstract
    }
    open func getComponentByElement(_ el: Element) -> ComponentModel {
        fatalError("abstract method ExtensionAPI.getComponentByElement must be overridden") // PORT-NOTE: abstract
    }
    open func enterEmphasis(_ el: Element, _ highlightDigit: Double? = nil) {
        fatalError("abstract method ExtensionAPI.enterEmphasis must be overridden") // PORT-NOTE: abstract
    }
    open func leaveEmphasis(_ el: Element, _ highlightDigit: Double? = nil) {
        fatalError("abstract method ExtensionAPI.leaveEmphasis must be overridden") // PORT-NOTE: abstract
    }
    open func enterSelect(_ el: Element) {
        fatalError("abstract method ExtensionAPI.enterSelect must be overridden") // PORT-NOTE: abstract
    }
    open func leaveSelect(_ el: Element) {
        fatalError("abstract method ExtensionAPI.leaveSelect must be overridden") // PORT-NOTE: abstract
    }
    open func enterBlur(_ el: Element) {
        fatalError("abstract method ExtensionAPI.enterBlur must be overridden") // PORT-NOTE: abstract
    }
    open func leaveBlur(_ el: Element) {
        fatalError("abstract method ExtensionAPI.leaveBlur must be overridden") // PORT-NOTE: abstract
    }
    // These methods are not planned to be exposed to outside.
    // Optional: upstream `getViewOfComponentModel` can return `undefined` for a component whose
    //   mainType has no registered ComponentView (e.g. `polar`). Callers (states.ts allLeaveBlur/
    //   blurSeries) guard with `if (view && view.toggleBlurSeries)`. Force-unwrapping here crashes on
    //   any such viewless component during a highlight/blur dispatch.
    open func getViewOfComponentModel(_ componentModel: ComponentModel) -> ComponentView? {
        fatalError("abstract method ExtensionAPI.getViewOfComponentModel must be overridden") // PORT-NOTE: abstract
    }
    // Returns nil for a series with no live view — e.g. a legend-filtered (toggled-off) series, whose
    //   view is not created/rendered. Upstream `getViewOfSeriesModel` likewise returns undefined then;
    //   callers (allLeaveBlur / blurSeries) must guard (a force-unwrap here crashed on legend hover after
    //   a series was hidden).
    open func getViewOfSeriesModel(_ seriesModel: SeriesModel) -> ChartView? {
        fatalError("abstract method ExtensionAPI.getViewOfSeriesModel must be overridden") // PORT-NOTE: abstract
    }
    open func getModel() -> GlobalModel {
        fatalError("abstract method ExtensionAPI.getModel must be overridden") // PORT-NOTE: abstract
    }
    // @return Never be null/undefined
    open func getECUpdateCycleVersion() -> Double {
        fatalError("abstract method ExtensionAPI.getECUpdateCycleVersion must be overridden") // PORT-NOTE: abstract
    }
    /**
     * PENDING: a temporary method - may be refactored.
     * Whether a "threshold hoverLayer" is used.
     * `true` means using hover layer due to over `hoverLayerThreshold`.
     * Otherwise, if `false`, hover layer may be still used due to progressive (incremental),
     * but this method does not need to cover this case.
     */
    open func usingTHL() -> Bool {
        fatalError("abstract method ExtensionAPI.usingTHL must be overridden") // PORT-NOTE: abstract
    }

    // PORT-NOTE: part of the `availableMethods` forwarding to `ecInstance` (see init note). Declared as
    //   faithful-signature abstract members so layout math (`layout.createBoxLayoutReference`) can read
    //   the viewport size; the real forwarding is wired when EChartsType lands (Phase 6b).
    open func getWidth() -> Double {
        fatalError("abstract method ExtensionAPI.getWidth must be overridden") // PORT-NOTE: abstract
    }
    open func getHeight() -> Double {
        fatalError("abstract method ExtensionAPI.getHeight must be overridden") // PORT-NOTE: abstract
    }

    // upstream: part of the `availableMethods` forwarding (`getZr`) — `ECharts` OWNS the ZRender
    //   (`this._zr = zrender.init(dom, ...)`), so every interaction controller reaches it through
    //   `api.getZr()` (BrushController, RoamController, MapDraw, tooltip …).
    //
    //   PORT SEAM: this port's `ECharts` driver is host-independent and owns NO ZRender — the live host
    //   (`EChartsView`) creates one and wires `ec.getRoot()` into it. `EChartsExtensionAPI` therefore
    //   resolves the zr through the root group's `__zr` back-pointer (set by `zr.add(root)`), which is
    //   live from the first `_syncRoot` onward. Returns nil in pure headless (no host zr): a consumer
    //   must then degrade gracefully — see BrushView's PORT-NOTE.
    open func getZr() -> ZRenderType? {
        return nil
    }

    // PORT-NOTE: part of the `availableMethods` forwarding to `ecInstance` (`isDisposed`). Upstream binds
    //   `ECharts.prototype.isDisposed`. Consumers guard a DEFERRED (throttled/timer) dispatch with it —
    //   e.g. brush's `doDispatch` (`if (!api.isDisposed()) {...}`, visualEncoding.ts). Defaults to `false`
    //   (a bare/headless api has no dispose lifecycle); `EChartsExtensionAPI` forwards to the driver.
    open func isDisposed() -> Bool {
        return false
    }

    // PORT-NOTE: part of the `availableMethods` forwarding to `ecInstance` (`getDevicePixelRatio`).
    //   Upstream returns `zr.painter.dpr` (the device pixel ratio). Used by `util/decal`'s tile
    //   rasterization (createOrUpdatePatternFromDecal). Defaults to 1 (the headless/test dpr); the
    //   host painter overrides via this open method when a real dpr is wired.
    open func getDevicePixelRatio() -> Double {
        return 1
    }

    // PORT-NOTE: part of the `availableMethods` forwarding to `ecInstance` (see init note). Upstream
    //   `ExtensionAPI.dispatchAction` is `zrUtil.bind(ecInstance.dispatchAction, ecInstance)`. Declared
    //   here as a faithful-signature abstract member so the action round-trip (a view/action handler
    //   calling `api.dispatchAction(...)`) type-checks; the concrete `EChartsExtensionAPI` forwards it to
    //   the driver's `ECharts.dispatchAction`. `opt` models the upstream `boolean | {silent,flush}`
    //   (see `DispatchActionOpt` in core/ECharts.swift).
    open func dispatchAction(_ payload: Payload, _ opt: DispatchActionOpt? = nil) {
        fatalError("abstract method ExtensionAPI.dispatchAction must be overridden") // PORT-NOTE: abstract
    }

    // PORT-NOTE: part of the `availableMethods` forwarding to `ecInstance` (`getConnectedDataURL` /
    //   `getDataURL`). Upstream returns a DATA-URL STRING of the rendered chart (a `<canvas>.toDataURL`).
    //   The headless port returns the ENCODED image `Data` (PNG/JPEG bytes) produced by the host-injected
    //   rasterizer (see ECharts `getRenderedImage`); nil when no host renderer is wired. Only the
    //   toolbox SaveAsImage feature reads this in the ported slice. `opts` = { type, backgroundColor,
    //   connectedBackgroundColor, excludeComponents, pixelRatio } (the upstream option bag).
    open func getConnectedDataURL(_ opts: [String: Any]) -> Data? { return nil }

    // PORT SEAM (no upstream analog on ExtensionAPI): the toolbox SaveAsImage `onclick` downloads the
    //   data URL via a DOM `<a download>` in the browser. Headless has no download, so the encoded bytes
    //   are handed to the host via this seam (forwarded to `ECharts.onSaveImage`). Default no-op.
    open func saveAsImage(_ data: Data, _ filename: String) { }
}

// upstream return type: `ChartView | ComponentView`. Swift has no union types; the two view
//   protocols share no common supertype, so return `AnyObject`. PORT-NOTE: tighten to a shared
//   `View`-like protocol if the view layer introduces one.
public func getViewOfComponentOrSeries(
    _ api: ExtensionAPI,
    _ componentOrSeries: ComponentModel
) -> AnyObject? { // upstream: ChartView | ComponentView (may be undefined for a viewless component)
    return componentOrSeries.mainType == COMPONENT_MAIN_TYPE_SERIES
        ? api.getViewOfSeriesModel(componentOrSeries as! SeriesModel)
        : api.getViewOfComponentModel(componentOrSeries)
}

// export default ExtensionAPI;  -> `open class ExtensionAPI` above.
