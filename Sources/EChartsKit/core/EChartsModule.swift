// Ported from echarts/src/core/echarts.ts — keep in sync with upstream
// filename avoids a case-insensitive collision with the existing ECharts.swift
// driver. Public module spelling remains `echarts`.
import Foundation
import ZRenderKit

public struct EChartsInitOpts {
    public var renderer: String?
    public var width: Double?
    public var height: Double?
    public var devicePixelRatio: Double?
    public var useDirtyRect: Bool?
    public var useCoarsePointer: Bool?
    public var pointerSize: Double?
    public var ssr: Bool?
    public var locale: Any?
    public init() {}
    // TODO: upstream number|string sizing and hoverLayerThreshold are not modeled.
}

public enum EChartsInitError: Error {
    case invalidSize
}

/// Public module namespace, corresponding to `import * as echarts`.
public enum echarts {
    // the existing EChartsView is the live chart driver. Preserve its event
    // wiring instead of creating another chart lifecycle beside it.
    @discardableResult
    public static func `init`(_ dom: ZRenderHost? = nil, _ theme: Any? = nil,
                              _ opts: EChartsInitOpts? = nil) throws -> EChartsView {
        if let dom, let existing = getInstanceByDom(dom) { return existing }
        let chart = try EChartsView(dom, theme, opts)
        if let dom { instances[ObjectIdentifier(dom)] = WeakChart(chart) }
        return chart
    }

    public static func getInstanceByDom(_ dom: ZRenderHost) -> EChartsView? {
        guard let chart = instances[ObjectIdentifier(dom)]?.value,
              !chart.isDisposed() else { return nil }
        return chart
    }

    public static func dispose(_ chart: EChartsView) { chart.dispose() }
    public static func registerTheme(_ name: String, _ theme: [String: Any]) {
        ECharts.registerTheme(name, theme)
    }

    // Weak values avoid retaining native views indefinitely through a process-wide registry.
    private final class WeakChart {
        weak var value: EChartsView?
        init(_ value: EChartsView) { self.value = value }
    }
    private static var instances: [ObjectIdentifier: WeakChart] = [:]
    static func removeInstance(_ dom: ZRenderHost?, _ chart: EChartsView) {
        guard let dom else { return }
        let current = instances[ObjectIdentifier(dom)]?.value
        guard current == nil || current === chart else { return }
        instances.removeValue(forKey: ObjectIdentifier(dom))
    }
}
