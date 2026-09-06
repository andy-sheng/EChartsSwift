// Ported from echarts/src/extension.ts — keep in sync with upstream
import Foundation
import ZRenderKit

// PORT-NOTE: Swift metatype identity replaces identity of the JS extension object.
public protocol EChartsExtension {
    static func install(_ registers: EChartsExtensionInstallRegisters)
}

private var extensions: [ObjectIdentifier] = []
private let extensionRegisters = EChartsExtensionInstallRegisters()

extension EChartsExtensionInstallRegisters {
    public func registerPainter(_ painterType: String, _ PainterCtor: @escaping PainterBaseCtor) {
        ZRenderKit.registerPainter(painterType, PainterCtor)
    }
}

extension echarts {
    public static func use(_ ext: [EChartsExtension.Type]) {
        for singleExt in ext { use(singleExt) }
    }

    public static func use(_ ext: EChartsExtension.Type) {
        precondition(Thread.isMainThread, "Install ECharts extensions on the main thread")
        let identity = ObjectIdentifier(ext)
        if extensions.contains(identity) { return }
        extensions.append(identity)
        ext.install(extensionRegisters)
    }
    // PORT-TODO: JS function installers and registrars other than the existing processor
    // registrar and registerPainter are not yet exposed by this native extension entry point.
}
