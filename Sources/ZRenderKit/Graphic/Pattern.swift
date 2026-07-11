// Ported from zrender/src/graphic/Pattern.ts — keep in sync with upstream

// upstream: import { ImageLike } from '../core/types';
// upstream: import { SVGVNode } from '../svg/core';
// PORT-TODO: ImageLike is a browser image-source union (HTMLImageElement | ... ); it is
// still unported (see Core/types.swift) and routed through the Renderer/Painter seam
// (CONVENTIONS §9). String slots below stand in for the SSR/string arm; the ImageLike arm
// is deferred to Phase 2.
// PORT-TODO: SVGVNode — svg renderer virtual node; svg backend is not ported (CONVENTIONS §9).

public enum ImagePatternRepeat: String {
    case `repeat`
    case repeatX = "repeat-x"
    case repeatY = "repeat-y"
    case noRepeat = "no-repeat"
}

public protocol PatternObjectBase {
    var id: Double? { get set }
    // type is now unused, so make it optional
    var type: String? { get set } // 'pattern'

    var x: Double? { get set }
    var y: Double? { get set }
    var rotation: Double? { get set }
    var scaleX: Double? { get set }
    var scaleY: Double? { get set }
}

public protocol ImagePatternObject: PatternObjectBase {
    // PORT-TODO: image: ImageLike | string — only the `string` arm is typed for now.
    var image: String { get set }
    var `repeat`: ImagePatternRepeat? { get set }

    /**
     * Width and height of image.
     * `imageWidth` and `imageHeight` are only used in svg-ssr renderer.
     * Because we can't get the size of image in svg-ssr renderer.
     * They need to be give explictly.
     */
    var imageWidth: Double? { get set }
    var imageHeight: Double? { get set }
}

public protocol InnerImagePatternObject: ImagePatternObject {
    // PORT-TODO: __image?: ImageLike — cached image created in the canvas painter; backend
    // seam (CONVENTIONS §9). Deferred to Phase 2.
}

public protocol SVGPatternObject: PatternObjectBase {
    /**
     * svg vnode can only be used in svg renderer currently.
     * svgWidth, svgHeight defines width and height used for pattern.
     */
    // PORT-TODO: svgElement?: SVGVNode — svg backend not ported (CONVENTIONS §9).
    var svgWidth: Double? { get set }
    var svgHeight: Double? { get set }
}

// PORT-NOTE: PatternObject = ImagePatternObject | SVGPatternObject — a structural union;
// modeled in Swift as the two separate protocols above. A union enum (or a `fill` enum case)
// will be introduced where PathStyleProps consumes it.

public class Pattern {

    // upstream declares `type: 'pattern'` but the constructor never assigns it; the base
    // interface makes it optional, so we model it as `String?` (nil here, matching runtime).
    public var type: String?

    // PORT-TODO: image: ImageLike | string — only the `string` arm is typed for now.
    public var image: String
    /**
     * svg element can only be used in svg renderer currently.
     *
     * Will be string if using SSR rendering.
     */
    // PORT-TODO: svgElement: SVGElement | string — only the `string` arm is typed for now.
    public var svgElement: String?

    public var `repeat`: ImagePatternRepeat

    public var x: Double
    public var y: Double
    public var rotation: Double
    public var scaleX: Double
    public var scaleY: Double

    public init(_ image: String, _ repeat: ImagePatternRepeat) {
        // Should do nothing more in this constructor. Because gradient can be
        // declard by `color: {image: ...}`, where this constructor will not be called.
        self.image = image
        self.`repeat` = `repeat`

        self.x = 0
        self.y = 0
        self.rotation = 0
        self.scaleX = 1
        self.scaleY = 1
    }
}
