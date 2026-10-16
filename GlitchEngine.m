#import "GlitchEngine.h"
#import "GlitchCompositor.h"
#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#include <math.h>

// Seul réglage : amplitude et probabilité des types lourds. Ne définit aucune période.
static const float kIntensity = 0.85f;

static const int   kSnapshotMaxWidth  = 900;
static const float kIdleMean          = 2.4f;
static const float kIdleMin           = 0.25f;
static const float kIdleMax           = 12.0f;
static const float kAftershockChance  = 0.12f;
static const float kMicroChance       = 0.08f;

// Même ordre que GFEventType (0..6). Les 4 premiers sont les types « lourds ».
static const float kBaseWeights[GF_WEIGHTED_EVENT_COUNT] = { 30, 22, 14, 10, 8, 8, 8 };

#pragma mark - Fenêtre overlay

@interface GFGlitchWindow : UIWindow
@property (nonatomic, strong) UIView *glitchView;
@end

@implementation GFGlitchWindow
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event { return nil; }
- (BOOL)pointInside:(CGPoint)point withEvent:(UIEvent *)event { return NO; }
- (BOOL)canBecomeKeyWindow { return NO; }
- (void)layoutSubviews {
    [super layoutSubviews];
    self.glitchView.frame = self.bounds;
}
@end

#pragma mark - Moteur

@interface GlitchEngine () {
    BOOL _running;
    GFRng _rng;
    GFGlitchWindow *_window;
    GlitchCompositor *_comp;
    CADisplayLink *_link;
    NSTimer *_timer;
    BOOL _burstActive;
    GFEventType _type;
    int _framesLeft;
    int _holdLeft;
}
@end

@implementation GlitchEngine

+ (instancetype)shared {
    static GlitchEngine *e;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ e = [GlitchEngine new]; });
    return e;
}

- (void)updateWithEnabled:(BOOL)enabled active:(BOOL)active {
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{ [self updateWithEnabled:enabled active:active]; });
        return;
    }
    if (enabled && active) [self start]; else [self stop];
}

#pragma mark Cycle de vie

- (void)start {
    if (_running) return;
    _running = YES;
    GFRngSeed(&_rng, ((uint64_t)arc4random() << 32) | (uint64_t)arc4random());

    _link = [CADisplayLink displayLinkWithTarget:self selector:@selector(tick:)];
    _link.preferredFramesPerSecond = 60;
    _link.paused = YES;   // idle : aucun réveil
    [_link addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];

    [self ensureWindowForScene:[self foregroundScene]];
    [self scheduleAfter:[self idleWait]];
}

- (void)stop {
    if (!_running && !_window && !_comp) return;
    _running = NO;
    _burstActive = NO;
    [_timer invalidate]; _timer = nil;
    [_link invalidate];  _link = nil;
    if (_window) {
        [self clearOverlay];
        [_window.glitchView removeFromSuperview];
        _window.glitchView = nil;
        _window.windowScene = nil;
        _window = nil;
    }
    _comp = nil;   // free des buffers
}

#pragma mark Fenêtre

- (UIWindowScene *)foregroundScene {
    UIWindowScene *fallback = nil;
    for (UIScene *s in UIApplication.sharedApplication.connectedScenes) {
        if (![s isKindOfClass:UIWindowScene.class]) continue;
        if (s.activationState == UISceneActivationStateForegroundActive) return (UIWindowScene *)s;
        if (!fallback && s.activationState == UISceneActivationStateForegroundInactive)
            fallback = (UIWindowScene *)s;
    }
    return fallback;
}

- (BOOL)ensureWindowForScene:(UIWindowScene *)scene {
    if (!scene) return NO;
    if (!_window) {
        _window = [[GFGlitchWindow alloc] initWithWindowScene:scene];
        _window.backgroundColor = UIColor.clearColor;
        _window.opaque = NO;
        _window.userInteractionEnabled = NO;
        _window.windowLevel = UIWindowLevelAlert + 1000;

        UIView *v = [[UIView alloc] initWithFrame:_window.bounds];
        v.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        v.userInteractionEnabled = NO;
        v.backgroundColor = UIColor.clearColor;
        v.opaque = NO;
        v.hidden = YES;
        v.layer.contentsGravity = kCAGravityResize;
        v.layer.magnificationFilter = kCAFilterNearest;
        v.layer.minificationFilter = kCAFilterNearest;
        [_window addSubview:v];
        _window.glitchView = v;
        _window.hidden = YES;
    } else if (_window.windowScene != scene) {
        _window.windowScene = scene;
    }
    return YES;
}

- (void)clearOverlay {
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    _window.glitchView.layer.contents = nil;
    _window.glitchView.hidden = YES;
    _window.hidden = YES;
    [CATransaction commit];
}

#pragma mark Temps

- (NSTimeInterval)idleWait {
    float u = GFRngFloat(&_rng);                       // [0,1)
    float t = -kIdleMean * logf(1.0f - u);             // exponentielle
    return (NSTimeInterval)fminf(fmaxf(t, kIdleMin), kIdleMax);
}

- (void)scheduleAfter:(NSTimeInterval)delay {
    [_timer invalidate];
    __weak GlitchEngine *wself = self;
    _timer = [NSTimer timerWithTimeInterval:delay repeats:NO block:^(NSTimer *t) {
        [wself beginBurst];
    }];
    [[NSRunLoop mainRunLoop] addTimer:_timer forMode:NSRunLoopCommonModes];
}

- (GFEventType)pickEventType {
    if (GFRngChance(&_rng, kMicroChance)) return GFEventMicro;
    float w[GF_WEIGHTED_EVENT_COUNT], total = 0;
    for (int i = 0; i < GF_WEIGHTED_EVENT_COUNT; i++) {
        w[i] = kBaseWeights[i] * (0.7f + 0.6f * GFRngFloat(&_rng));   // re-roll léger à chaque event
        if (i <= (int)GFEventVerticalRoll) w[i] *= (0.5f + kIntensity);
        total += w[i];
    }
    float pick = GFRngFloat(&_rng) * total;
    for (int i = 0; i < GF_WEIGHTED_EVENT_COUNT; i++) {
        pick -= w[i];
        if (pick < 0) return (GFEventType)i;
    }
    return GFEventSliceTear;
}

- (int)pickFrameCount:(GFEventType)type {
    if (type == GFEventInvertSpeckle && GFRngChance(&_rng, 0.6f)) return 1;
    if (type == GFEventMicro) return GFRngRange(&_rng, 1, 3);
    float u = GFRngFloat(&_rng);
    int n = 1 + (int)(u * u * 9.0f);    // biaisé vers les bursts courts, sparks d'une frame fréquents
    return n < 1 ? 1 : (n > 9 ? 9 : n);
}

#pragma mark Burst

- (UIWindow *)captureTargetInScene:(UIWindowScene *)scene {
    UIWindow *key = scene.keyWindow;
    if (key && key != _window && !key.hidden) return key;
    UIWindow *best = nil;
    for (UIWindow *w in scene.windows) {
        if (w == _window || w.hidden) continue;
        if (w.windowLevel == UIWindowLevelNormal) return w;
        if (!best || w.windowLevel > best.windowLevel) best = w;
    }
    return best;
}

- (BOOL)capture:(UIWindow *)target into:(GlitchCompositor *)comp {
    CGSize bs = target.bounds.size;
    if (bs.width < 1 || bs.height < 1) return NO;
    CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
    CGContextRef ctx = CGBitmapContextCreate(comp.source, comp.width, comp.height, 8,
                                             (size_t)comp.width * 4, cs,
                                             kCGBitmapByteOrder32Little | kCGImageAlphaPremultipliedFirst);
    CGColorSpaceRelease(cs);
    if (!ctx) return NO;
    CGContextTranslateCTM(ctx, 0, comp.height);
    CGContextScaleCTM(ctx, (CGFloat)comp.width / bs.width, -(CGFloat)comp.height / bs.height);
    UIGraphicsPushContext(ctx);
    BOOL ok = [target drawViewHierarchyInRect:target.bounds afterScreenUpdates:NO];
    UIGraphicsPopContext();
    CGContextRelease(ctx);
    if (!ok) return NO;

    // Capture vide (surface hors processus) : on traite comme un échec.
    BOOL anyVisible = NO;
    size_t total = (size_t)comp.width * comp.height;
    for (int i = 0; i < 64 && !anyVisible; i++) {
        size_t idx = (size_t)(GFRngFloat(&_rng) * (float)total);
        if (idx >= total) idx = total - 1;
        if ((comp.source[idx] >> 24) != 0) anyVisible = YES;
    }
    return anyVisible;
}

- (void)beginBurst {
    _timer = nil;
    if (!_running) return;

    UIWindowScene *scene = [self foregroundScene];
    if (![self ensureWindowForScene:scene]) { [self scheduleAfter:[self idleWait]]; return; }

    // Cacher l'overlay avant la capture (sinon feedback).
    _window.glitchView.hidden = YES;
    _window.hidden = YES;

    UIWindow *target = [self captureTargetInScene:scene];
    CGSize size = target ? target.bounds.size : scene.coordinateSpace.bounds.size;
    if (size.width < 8 || size.height < 8) { [self scheduleAfter:[self idleWait]]; return; }

    int w = (int)lround(size.width);          // scale = 1
    if (w > kSnapshotMaxWidth) w = kSnapshotMaxWidth;
    int h = (int)lround(size.height * (CGFloat)w / size.width);
    GlitchCompositor *comp = [[GlitchCompositor alloc] initWithWidth:w height:h];
    if (!comp) { [self scheduleAfter:[self idleWait]]; return; }

    BOOL ok = target ? [self capture:target into:comp] : NO;
    if (!ok) [comp fillSourceWithAbstractBands:&_rng];   // ce burst uniquement

    _type = [self pickEventType];
    _framesLeft = [self pickFrameCount:_type];
    _holdLeft = 0;
    _comp = comp;
    _burstActive = YES;

    _window.glitchView.hidden = NO;
    _window.hidden = NO;
    _link.paused = NO;
}

- (void)tick:(CADisplayLink *)link {
    if (!_burstActive || !_comp) { link.paused = YES; return; }   // early-out
    if (_holdLeft > 0) { _holdLeft--; return; }
    if (_framesLeft <= 0) { [self endBurst]; return; }
    [self presentFrame];
    _framesLeft--;
    _holdLeft = GFRngRange(&_rng, 0, 1);   // durée de frame irrégulière
}

- (void)presentFrame {
    [_comp renderEvent:_type intensity:kIntensity rng:&_rng];   // tout est re-tiré
    CGImageRef img = [_comp copyOverlayImage];
    if (!img) return;
    [CATransaction begin];
    [CATransaction setDisableActions:YES];   // pas d'interpolation entre frames
    _window.glitchView.layer.contents = (__bridge id)img;
    [CATransaction commit];
    CGImageRelease(img);
}

- (void)endBurst {
    _burstActive = NO;
    _link.paused = YES;
    [self clearOverlay];
    _comp = nil;   // bitmap libéré
    if (!_running) return;
    NSTimeInterval d = GFRngChance(&_rng, kAftershockChance)
        ? 0.03 + 0.09 * (double)GFRngFloat(&_rng)
        : [self idleWait];
    [self scheduleAfter:d];
}

@end
