// Ported from echarts/src/renderer/installCanvasRenderer.ts — keep in sync with upstream
@_exported import NativePainter
import EChartsKit

public enum CanvasRenderer: EChartsExtension {
    public static func install(_ registers: EChartsExtensionInstallRegisters) {
        installNativePlatformAPI()
        installSVGPatternRasterizer()
        registers.registerPainter("canvas") { CALayerPainter($0, $1, $2, $3) }
    }
}
