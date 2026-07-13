//
//  RARenderHost.mm — LOCAL ADDITION to the vendored mindbrix/Rasterizer package
//  (see README-VENDORED.md; NOT part of upstream). Push-model host over the private
//  RasterizerLayer; mirrors RasterizerView's layer setup + writeBuffer plumbing minus
//  the display-link pull loop.
//
//  Underlying Rasterizer engine © Nigel Timothy Barber (personal-use zlib license).
//

#import "RARenderHost.h"
#import "RasterizerLayer.h"
#import "RasterizerAPI+Internal.h"
#import "RasterizerRenderer.hpp"

@interface RARenderHost () <LayerDelegate> {
    // Direct ivar, NEVER a property: an ObjC property getter returns this C++ value BY
    // COPY, and RasterizerRenderer's contexts hold refcounted Memory/Row pages whose
    // copies release the shared pages on destruction — every renderList call through a
    // getter-copy leaves the real renderer's allocators dangling (SIGSEGV in
    // Allocator::refill on the next frame). Upstream RasterizerView uses `_renderer` too.
    RasterizerRenderer _renderer;
}
@property(nonatomic, strong, nullable) RASceneList *list;
@property(nonatomic) double listWidth;
@property(nonatomic) double listHeight;
@end

@implementation RARenderHost

- (instancetype)initWithScale:(CGFloat)scale {
    self = [super init];
    if (!self)
        return nil;
    // Mirrors RasterizerView.setUseCG's Metal branch: RasterizerLayer + deviceRGB colorspace,
    // implicit animations disabled so per-frame contents swaps don't fade.
    RasterizerLayer *layer = [RasterizerLayer layer];
    layer.layerDelegate = self;
    CGColorSpaceRef rgb = CGColorSpaceCreateDeviceRGB();
    layer.colorspace = rgb;
    CGColorSpaceRelease(rgb);
    layer.contentsScale = scale;
    layer.opaque = YES;
    layer.needsDisplayOnBoundsChange = YES;
    layer.actions = @{ @"onOrderIn": [NSNull null], @"onOrderOut": [NSNull null],
                       @"sublayers": [NSNull null], @"contents": [NSNull null],
                       @"backgroundColor": [NSNull null], @"bounds": [NSNull null] };
    _layer = layer;
    return self;
}

- (void)presentList:(RASceneList *)list width:(double)width height:(double)height {
    self.list = list;
    self.listWidth = width;
    self.listHeight = height;
    [self.layer setNeedsDisplay];
}

#pragma mark - LayerDelegate (called from RasterizerLayer's display pass)

- (void)writeBuffer:(Ra::Buffer *)buffer forLayer:(CALayer *)layer {
    if (!self.list)
        return;   // nothing published yet — a fresh Ra::Buffer renders as an empty clear
    _renderer.renderList(self.list.list, self.layer.contentsScale,
                         self.listWidth, self.listHeight, buffer);
}

#pragma mark - Headless CPU reference (RasterizerCG)

+ (void)renderList:(RASceneList *)list
             scale:(CGFloat)scale
             width:(double)width
            height:(double)height
       intoContext:(CGContextRef)ctx {
    RasterizerCG::renderListToBitmap(list.list, scale, width, height, ctx);
}

+ (double)benchList:(RASceneList *)list
              scale:(CGFloat)scale
              width:(double)width
             height:(double)height
             frames:(int)frames {
    static RasterizerRenderer renderer;
    static Ra::Buffer buffer;
    // Warm-up frame (first frame pays one-time allocations).
    renderer.renderList(list.list, scale, width, height, & buffer);
    CFAbsoluteTime t0 = CFAbsoluteTimeGetCurrent();
    for (int i = 0; i < frames; i++)
        renderer.renderList(list.list, scale, width, height, & buffer);
    return (CFAbsoluteTimeGetCurrent() - t0) * 1000.0 / MAX(1, frames);
}

@end
