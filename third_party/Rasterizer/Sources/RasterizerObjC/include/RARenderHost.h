//
//  RARenderHost.h — LOCAL ADDITION to the vendored mindbrix/Rasterizer package
//  (see README-VENDORED.md; NOT part of upstream).
//
//  A push-model render host: wraps the (private) RasterizerLayer CAMetalLayer so an
//  EXTERNAL frame clock can drive rendering. The upstream RasterizerView owns its own
//  CVDisplayLink/CADisplayLink and PULLS a scene list from its delegate every frame;
//  ZRenderKit already has an AnimationLoop that knows exactly when the scene changed,
//  so the painter PUSHES the freshly built RASceneList here instead and the layer
//  redraws once per push (no second clock, no redundant frames).
//
//  Underlying Rasterizer engine © Nigel Timothy Barber (personal-use zlib license).
//

#import <Foundation/Foundation.h>
#import <QuartzCore/QuartzCore.h>
#import <CoreGraphics/CoreGraphics.h>
#import "RasterizerAPI.h"

NS_ASSUME_NONNULL_BEGIN

@interface RARenderHost : NSObject

/// The Metal-backed layer the scene renders into. Add it to a view's layer tree.
@property(nonatomic, readonly) CALayer *layer;

- (instancetype)initWithScale:(CGFloat)scale;

/// Publish a new scene list (logical width/height in points) and schedule a redraw.
/// The Metal pipeline renders it on the layer's next display pass.
- (void)presentList:(RASceneList *)list width:(double)width height:(double)height;

/// Headless CPU reference render of `list` via RasterizerCG (the same interpreter the
/// engine's own useCG debug mode uses) into `ctx`. Verifies scene translation without
/// a display / drawable.
+ (void)renderList:(RASceneList *)list
             scale:(CGFloat)scale
             width:(double)width
            height:(double)height
       intoContext:(CGContextRef)ctx;

/// Benchmark the engine's CPU stage (Context::drawList fan-out into an Ra::Buffer — the
/// same work writeBuffer does per frame, minus the GPU encode). Returns avg ms/frame.
+ (double)benchList:(RASceneList *)list
              scale:(CGFloat)scale
              width:(double)width
             height:(double)height
             frames:(int)frames;

@end

NS_ASSUME_NONNULL_END
