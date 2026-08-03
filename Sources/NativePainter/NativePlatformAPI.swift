// NativePainter — installs the native backing for ZRenderKit's `platform.loadImage` seam
// (upstream zrender/src/core/platform.ts `Platform.loadImage`). ZRenderKit has no pixel backend, so
// its `DefaultPlatformAPI.loadImage` returns nil (a stub) and the CoreGraphics decode may not live in
// ZRenderKit (CONVENTIONS §9). There is no `NativePlatformAPI` provider *type*: `installNativePlatformAPI()`
// installs only a partial `loadImage` override — a `PartialPlatformAPI(loadImage:)` closure backed by the
// synchronous ImageIO decode already implemented as `loadCGImage` (CGRenderer.swift), returning the
// decoded `CGImage` as the opaque `ImageLike` handle. It is merged onto the current `platformApi` via
// `setPlatformAPI` (upstream's `setPlatformAPI(Partial<Platform>)` per-key merge), so `createCanvas` /
// `measureText` / `getTime` keep their existing implementations untouched.
//
// PORT-NOTE (deferred): this covers only the string arm zrender handles synchronously (file / data
// URI). Remote-URL async loading + the `onload`/`onerror` dispatch onto `ZRImage.__image`
// (`globalImageCache` LRU + `createOrUpdateImage`/`imageOnLoad`/`isImageReady` in
// zrender/src/graphic/helper/image.ts) is a SEPARATE unported follow-up; the callbacks below fire
// synchronously and consumers use the returned handle directly.

import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
import ZRenderKit

// Install once; idempotent. Referenced (not re-run) on every call.
private let _installOnce: Void = {
    setPlatformAPI(PartialPlatformAPI(loadImage: { src, onload, onerror in
        if let cg = loadCGImage(src) {
            // Native realization of upstream's `img.onload = onload; img.src = src` — the decode is
            // synchronous, so signal completion immediately and hand back the CGImage as `ImageLike`.
            onload()
            return cg as ImageLike
        }
        onerror()
        return nil
    }))
}()

/// Install NativePainter's native backing for the `platform.loadImage` seam so ZRenderKit consumers
/// (e.g. `CALayerPainter`'s image resolution) can decode a `string` image source through
/// `platformApi.loadImage`. Idempotent. Called automatically the first time a `CALayerPainter` is
/// constructed (see `CALayerPainter.init`); call it directly if you need `loadImage` before any
/// painter exists.
public func installNativePlatformAPI() {
    _ = _installOnce
    // Real font metrics for the `measureText` seam too — see NativeTextMeasure.swift. Kept a separate
    // installer because the headless paths (oracle/tests) need measurement without a painter.
    installNativeTextMeasure()
}

#endif
