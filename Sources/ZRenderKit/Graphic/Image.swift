// Ported from zrender/src/graphic/Image.ts — keep in sync with upstream
//
// PHASE-1 (render-only) PORT. `ZRImage extends Displayable<ImageProps>` — a Displayable for raster
// images. The bounding rect (x/y/width/height, with width/height inferred from the image source's
// natural size when omitted) is translated faithfully. The image SOURCE is a backend seam.
//
// IMAGE SOURCE SEAM (TS `image?: string | ImageLike` → Swift):
//   Upstream `ImageLike` is `HTMLImageElement | HTMLCanvasElement | HTMLVideoElement` (browser
//   raster sources with `.width` / `.height`). The painter resolves a `string` URL into an
//   `HTMLImageElement` via `platform.loadImage` and caches it on `__image`. We model the union as a
//   tagged `ImageSource` enum (`.url(String)` | `.image(ImageLike)`) and `ImageLike` as a small
//   protocol exposing the natural `width` / `height` (the rest is the native image handle —
//   `CGImage` on the painter side). The actual decode/cache lives in the renderer seam.
//   PORT-NOTE (deferred): native image loading via platform.loadImage (CONVENTIONS §9). `core/types.ts`'s
//   `ImageLike` placeholder is realised here.
//
// STYLE DECISION (TS `ImageStyleProps extends CommonStyleProps` → Swift):
//   Swift structs cannot subclass and Swift cannot RE-TYPE the inherited `Displayable.style`
//   (`CommonStyleProps!`). Mirroring `Path` (see Path.swift STYLE DECISION), `ImageStyleProps`
//   FLATTENS the CommonStyleProps fields plus the image fields, and `ZRImage` stores it in its OWN
//   property `imageStyle` (upstream `this.style`). The common subset is mirrored into the inherited
//   `self.style` via `_syncCommonStyle()` so the inherited machinery (shouldBePainted / getPaintRect)
//   reads correct shadow / opacity / blend.
//
// INHERITED from Displayable/Element:
//   - the animation surface (getAnimationStyleProps returns the props bag; Animator landed in Phase 3).
//   - the states machinery (landed in Phase 2).
//   - PORT-NOTE: the `onload` callback (fired by the painter after `platform.loadImage` resolves) is
//     still the deferred renderer seam.

import Foundation

// upstream imports (resolved to ported modules):
// import Displayable, { DisplayableProps, CommonStyleProps, DEFAULT_COMMON_STYLE,
//   DisplayableStatePropNames, DEFAULT_COMMON_ANIMATION_PROPS } from './Displayable';
// import BoundingRect from '../core/BoundingRect';
// import { ImageLike, MapToType } from '../core/types';
// import { defaults, createObject } from '../core/util';
// import { ElementCommonState } from '../Element';

// PORT-NOTE: `ImageLike` (HTMLImageElement | HTMLCanvasElement | HTMLVideoElement) is already the
//   deferred opaque seam `typealias ImageLike = Any` in `core/platform.swift` (CONVENTIONS §9); the
//   decoded native handle (a `CGImage` on the painter side) flows through it. The only structural
//   shape Image.ts reads off an `ImageLike` is its natural pixel size (`source.width`/`.height` in
//   `isImageLike` / `_getSize`), so that subset is exposed here as a small seam protocol the painter
//   conforms its native image wrapper to. `image: string | ImageLike` is modeled as `ImageSource`.
public protocol ImageNaturalSize {
    var width: Double { get }
    var height: Double { get }
}

// PORT-NOTE: models the upstream union `string | ImageLike`. A `.url` is resolved to an `.image`
//   by the painter via `platform.loadImage` (native image loading — renderer seam).
public enum ImageSource {
    case url(String)
    case image(ImageLike)   // ImageLike == Any (platform.swift seam)
}

// upstream: interface ImageStyleProps extends CommonStyleProps { image?, x?, y?, width?, height?,
//   sx?, sy?, sWidth?, sHeight? } — FLATTENED into one struct (see the STYLE DECISION header note).
public struct ImageStyleProps {
    // ---- CommonStyleProps fields (upstream: `extends CommonStyleProps`) ----
    public var shadowBlur: Double?
    public var shadowOffsetX: Double?
    public var shadowOffsetY: Double?
    public var shadowColor: String?
    public var opacity: Double?
    /// https://developer.mozilla.org/en-US/docs/Web/API/CanvasRenderingContext2D/globalCompositeOperation
    public var blend: String?
    // PORT-NOTE: replaces upstream's dynamic STYLE_MAGIC_KEY stamp (see Displayable.swift). `true`
    //   iff produced by `createStyle`.
    public var zrStyleMagic: Bool = false

    // ---- ImageStyleProps own fields ----
    // upstream: image?: string | ImageLike
    public var image: ImageSource?
    public var x: Double?
    public var y: Double?
    public var width: Double?
    public var height: Double?
    public var sx: Double?
    public var sy: Double?
    public var sWidth: Double?
    public var sHeight: Double?

    public init() {}
}

// upstream: export const DEFAULT_IMAGE_STYLE = defaults({ x: 0, y: 0 }, DEFAULT_COMMON_STYLE);
//   Inlines the DEFAULT_COMMON_STYLE merge (CommonStyleProps defaults) + the image defaults.
public let DEFAULT_IMAGE_STYLE: ImageStyleProps = {
    var s = ImageStyleProps()
    // from DEFAULT_COMMON_STYLE:
    s.shadowBlur = 0
    s.shadowOffsetX = 0
    s.shadowOffsetY = 0
    s.shadowColor = "#000"
    s.opacity = 1
    s.blend = "source-over"
    s.zrStyleMagic = true
    // image defaults:
    s.x = 0
    s.y = 0
    return s
}()

// PORT-NOTE: upstream `MapToType<ImageProps, boolean>` — recursive mapped utility type. Collapsed to
//   a loose `[String: Any]` bag (matches Displayable's DEFAULT_COMMON_ANIMATION_PROPS). Only read by
//   `getAnimationStyleProps` (animation surface deferred, Phase 3).
public let DEFAULT_IMAGE_ANIMATION_PROPS: [String: Any] = [
    "style": [
        // from DEFAULT_COMMON_ANIMATION_PROPS.style:
        "shadowBlur": true,
        "shadowOffsetX": true,
        "shadowOffsetY": true,
        "shadowColor": true,
        "opacity": true,
        // image:
        "x": true,
        "y": true,
        "width": true,
        "height": true,
        "sx": true,
        "sy": true,
        "sWidth": true,
        "sHeight": true
    ]
]

// PORT-NOTE: interface ImageProps extends DisplayableProps { style?: ImageStyleProps,
//   onload?: (image: ImageLike) => void }. The `attr`/`attrKV` setter machinery uses the dynamic
//   `[String: Any]` prop bag (collapsed onto DisplayableProps == ElementProps). Typed-interface
//   fidelity dropped; `onload` is exposed as a stored property below.
public typealias ImageProps = DisplayableProps

// PORT-NOTE: ImageState = Pick<ImageProps, DisplayableStatePropNames> & ElementCommonState — the
//   states machinery is Phase 2; collapsed onto Displayable's ElementState-based stub.
public typealias ImageState = DisplayableState

// upstream: function isImageLike(source): source is HTMLImageElement
//   `!!(source && typeof source !== 'string' && source.width && source.height)`.
//   Adapted to the `ImageSource` enum: returns the image's natural size when the source is an
//   `.image` exposing a non-zero `width`/`height` (matching the JS-falsy `width && height` guard),
//   else nil. PORT-NOTE (deferred): relies on the native handle conforming to `ImageNaturalSize` (renderer seam).
private func isImageLike(_ source: ImageSource?) -> ImageNaturalSize? {
    if case .some(.image(let img)) = source,
       let sized = img as? ImageNaturalSize,
       sized.width != 0, sized.height != 0 {
        return sized
    }
    return nil
}

// upstream: class ZRImage extends Displayable<ImageProps>
public final class ZRImage: Displayable {

    // upstream: style: ImageStyleProps. Swift cannot re-type the inherited `Displayable.style`
    //   (CommonStyleProps), so the rich style lives here (upstream `this.style` → `self.imageStyle`).
    //   See the STYLE DECISION header note.
    public var imageStyle: ImageStyleProps!

    // FOR CANVAS RENDERER
    // PORT-NOTE (deferred): the decoded native image handle, populated by the painter after resolving a `.url`
    //   source via `platform.loadImage`. Renderer seam (CONVENTIONS §9).
    public var __image: ImageLike?
    // FOR SVG RENDERER
    public var __imageSrc: String?

    // PORT-NOTE (deferred): fired by the painter once a `string` source finishes loading. Renderer seam.
    public var onload: ((ImageLike) -> Void)?

    public override init(_ props: ElementProps? = nil) {
        super.init(props)
        // upstream: ZRImage.prototype.type = 'image'
        self.type = "image"
    }

    internal override func _init(_ props: ElementProps? = nil) {  // upstream: protected
        // Init default properties (mirrors Displayable._init, but routes `style` through the
        //   ImageStyleProps overload — see Path._init).
        let keysArr = util.keys(props ?? [:])
        for i in 0..<keysArr.count {
            let key = keysArr[i]
            let value = props?[key]
            if key == "style" {
                if let s = value as? ImageStyleProps {
                    self.useStyle(s)
                }
                else {
                    // PORT-NOTE: non-ImageStyleProps `style` value — fall back to empty style.
                    self.useStyle(ImageStyleProps())
                }
            }
            else if key == "onload" {
                self.onload = value as? ((ImageLike) -> Void)
            }
            else {
                super.attrKV(key, value)
            }
        }
        // Give a empty style
        if self.imageStyle == nil {
            self.useStyle(ImageStyleProps())
        }
    }

    /// Create an image style object with default values in it's prototype.
    /// @override
    // upstream: createStyle(obj?: ImageStyleProps) { return createObject(DEFAULT_IMAGE_STYLE, obj) }
    //   OVERLOAD (not override) of Displayable.createStyle(CommonStyleProps?) — different param /
    //   return type. Builds from DEFAULT_IMAGE_STYLE.
    public func createStyle(_ obj: ImageStyleProps? = nil) -> ImageStyleProps {
        var style = DEFAULT_IMAGE_STYLE
        if let obj = obj {
            extendImageStyle(&style, obj)
        }
        return style
    }

    /// Replace style property. OVERLOAD of Displayable.useStyle(CommonStyleProps).
    public func useStyle(_ obj: ImageStyleProps) {
        var obj = obj
        if !obj.zrStyleMagic {
            obj = self.createStyle(obj)
        }
        self.imageStyle = obj
        self._syncCommonStyle()
        self.dirtyStyle()
    }

    // Mirror the CommonStyleProps subset of `imageStyle` into the inherited `Displayable.style` so the
    // inherited machinery (shouldBePainted / getPaintRect) reads correct shadow / opacity / blend.
    // PORT-NOTE: a Swift-only bridge — upstream has a single `this.style` object.
    private func _syncCommonStyle() {
        var c = CommonStyleProps()
        c.shadowBlur = self.imageStyle.shadowBlur
        c.shadowOffsetX = self.imageStyle.shadowOffsetX
        c.shadowOffsetY = self.imageStyle.shadowOffsetY
        c.shadowColor = self.imageStyle.shadowColor
        c.opacity = self.imageStyle.opacity
        c.blend = self.imageStyle.blend
        c.zrStyleMagic = self.imageStyle.zrStyleMagic
        self.style = c
    }

    // upstream: private _getSize(dim: 'width' | 'height')
    private func _getSize(_ dim: String) -> Double {
        let style = self.imageStyle!

        let size = (dim == "width") ? style.width : style.height
        if let size = size {
            return size
        }

        // upstream: isImageLike(style.image) ? style.image : this.__image. PORT-NOTE: the cached
        //   `__image` (ImageLike == Any) is read for its natural size via the `ImageNaturalSize` seam.
        let imageSource = isImageLike(style.image) ?? (self.__image as? ImageNaturalSize)

        guard let imageSource = imageSource else {
            return 0
        }

        let otherDim = (dim == "width") ? "height" : "width"
        let otherDimSize = (otherDim == "width") ? style.width : style.height
        // upstream: imageSource[dim] / imageSource[otherDim]
        let dimSize = (dim == "width") ? imageSource.width : imageSource.height
        if otherDimSize == nil {
            return dimSize
        }
        else {
            let otherImageSize = (otherDim == "width") ? imageSource.width : imageSource.height
            return dimSize / otherImageSize * otherDimSize!
        }
    }

    public func getWidth() -> Double {
        return self._getSize("width")
    }

    public func getHeight() -> Double {
        return self._getSize("height")
    }

    public override func getAnimationStyleProps() -> [String: Any] {
        return DEFAULT_IMAGE_ANIMATION_PROPS
    }

    public override func getBoundingRect() -> BoundingRect? {
        let style = self.imageStyle!
        if self._rect == nil {
            self._rect = BoundingRect(
                style.x ?? 0, style.y ?? 0, self.getWidth(), self.getHeight()
            )
        }
        return self._rect
    }
}

// extend(target, source) over ImageStyleProps' known fields (value-copy of non-nil fields).
// PORT-NOTE: upstream `extend`/`createObject` copy all own enumerable keys (dynamic bag); here we
//   copy the known ImageStyleProps fields only.
private func extendImageStyle(_ target: inout ImageStyleProps, _ source: ImageStyleProps) {
    if source.shadowBlur != nil { target.shadowBlur = source.shadowBlur }
    if source.shadowOffsetX != nil { target.shadowOffsetX = source.shadowOffsetX }
    if source.shadowOffsetY != nil { target.shadowOffsetY = source.shadowOffsetY }
    if source.shadowColor != nil { target.shadowColor = source.shadowColor }
    if source.opacity != nil { target.opacity = source.opacity }
    if source.blend != nil { target.blend = source.blend }
    if source.image != nil { target.image = source.image }
    if source.x != nil { target.x = source.x }
    if source.y != nil { target.y = source.y }
    if source.width != nil { target.width = source.width }
    if source.height != nil { target.height = source.height }
    if source.sx != nil { target.sx = source.sx }
    if source.sy != nil { target.sy = source.sy }
    if source.sWidth != nil { target.sWidth = source.sWidth }
    if source.sHeight != nil { target.sHeight = source.sHeight }
}

// upstream: export default ZRImage;
