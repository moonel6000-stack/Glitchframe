#import "GlitchCompositor.h"
#include <stdlib.h>
#include <string.h>
#include <math.h>

#define GF_ALPHA 0xFF000000u

static inline uint32_t GFPx(uint32_t r, uint32_t g, uint32_t b) {
    return GF_ALPHA | (r << 16) | (g << 8) | b;
}
static inline int clampi(int v, int lo, int hi) { return v < lo ? lo : (v > hi ? hi : v); }
static inline int wrapi(int v, int n) {
    while (v < 0) v += n;
    while (v >= n) v -= n;
    return v;
}

typedef struct { uint32_t *src; uint32_t *dst; int w; int h; } GFBuf;
typedef struct { int x, y, w, h; } GFRectI;

static GFRectI randRect(GFRng *r, GFBuf b, int minW, int maxW, int minH, int maxH) {
    maxW = clampi(maxW, 1, b.w); minW = clampi(minW, 1, maxW);
    maxH = clampi(maxH, 1, b.h); minH = clampi(minH, 1, maxH);
    GFRectI q;
    q.w = GFRngRange(r, minW, maxW);
    q.h = GFRngRange(r, minH, maxH);
    q.x = GFRngRange(r, 0, b.w - q.w);
    q.y = GFRngRange(r, 0, b.h - q.h);
    return q;
}

static inline int signedRand(GFRng *r, int m) { return GFRngChance(r, 0.5f) ? -m : m; }

// --- Types d'event -----------------------------------------------------------

static void drawSlice(GFBuf b, int y, int bh, int dx) {
    for (int row = y; row < y + bh && row < b.h; row++) {
        uint32_t *d = b.dst + (size_t)row * b.w;
        const uint32_t *s = b.src + (size_t)row * b.w;
        for (int x = 0; x < b.w; x++) d[x] = s[wrapi(x - dx, b.w)] | GF_ALPHA;
    }
}

static void evSliceTear(GFBuf b, GFRng *r, float I) {
    int n = GFRngRange(r, 1, 7);
    for (int i = 0; i < n; i++) {
        int bh = GFRngRange(r, 1, 28);
        int y = GFRngRange(r, 0, b.h - bh);
        int dx = (int)lroundf((2.0f + GFRngFloat(r) * 46.0f) * I);
        if (dx < 1) dx = 1;
        drawSlice(b, y, bh, signedRand(r, dx));
    }
}

static void evMicro(GFBuf b, GFRng *r) {
    int n = GFRngRange(r, 1, 2);
    for (int i = 0; i < n; i++) {
        int bh = GFRngRange(r, 2, 10);
        drawSlice(b, GFRngRange(r, 0, b.h - bh), bh, signedRand(r, 1));
    }
}

static void evRGBSplit(GFBuf b, GFRng *r, float I) {
    GFRectI z = randRect(r, b, b.w / 6, b.w, 6, b.h / 4);
    int dxs[3], dys[3];
    bool any = false;
    for (int c = 0; c < 3; c++) {
        if (GFRngChance(r, 0.3f)) {
            dxs[c] = 0;
        } else {
            int m = (int)lroundf((1.0f + GFRngFloat(r) * 15.0f) * I);
            dxs[c] = signedRand(r, m < 1 ? 1 : m);
            any = true;
        }
        dys[c] = GFRngChance(r, 0.25f) ? GFRngRange(r, -2, 2) : 0;
    }
    if (!any) dxs[GFRngRange(r, 0, 2)] = signedRand(r, 3);
    for (int y = z.y; y < z.y + z.h; y++) {
        uint32_t *d = b.dst + (size_t)y * b.w;
        for (int x = z.x; x < z.x + z.w; x++) {
            uint32_t pr = b.src[(size_t)clampi(y - dys[0], 0, b.h - 1) * b.w + wrapi(x - dxs[0], b.w)];
            uint32_t pg = b.src[(size_t)clampi(y - dys[1], 0, b.h - 1) * b.w + wrapi(x - dxs[1], b.w)];
            uint32_t pb = b.src[(size_t)clampi(y - dys[2], 0, b.h - 1) * b.w + wrapi(x - dxs[2], b.w)];
            d[x] = GF_ALPHA | (pr & 0x00FF0000u) | (pg & 0x0000FF00u) | (pb & 0x000000FFu);
        }
    }
}

static void evBlockSteal(GFBuf b, GFRng *r, float I) {
    int n = GFRngRange(r, 1, 4);
    int maxW = (int)((float)b.w * 0.5f * (0.4f + 0.6f * I));
    for (int i = 0; i < n; i++) {
        GFRectI d = randRect(r, b, b.w / 10, maxW, 6, b.h / 6);
        int sx = GFRngRange(r, 0, b.w - 1);
        int sy = GFRngRange(r, 0, b.h - 1);
        if (abs(sx - d.x) < 4 && abs(sy - d.y) < 4) sy = wrapi(sy + b.h / 3, b.h);
        for (int j = 0; j < d.h; j++) {
            uint32_t *dr = b.dst + (size_t)(d.y + j) * b.w;
            const uint32_t *sr = b.src + (size_t)wrapi(sy + j, b.h) * b.w;
            for (int k = 0; k < d.w; k++) dr[d.x + k] = sr[wrapi(sx + k, b.w)] | GF_ALPHA;
        }
    }
}

static void evVerticalRoll(GFBuf b, GFRng *r, float I) {
    int colW = GFRngRange(r, 4, b.w / 5 > 5 ? b.w / 5 : 5);
    colW = clampi(colW, 1, b.w);
    int x0 = GFRngRange(r, 0, b.w - colW);
    int y0 = 0, y1 = b.h;
    if (GFRngChance(r, 0.4f)) {
        int sh = GFRngRange(r, b.h / 4, b.h);
        y0 = GFRngRange(r, 0, b.h - sh);
        y1 = y0 + sh;
    }
    float base = (float)(b.h / 20) + GFRngFloat(r) * (float)(b.h / 3 - b.h / 20);
    int roll = (int)lroundf(base * I);
    if (roll < 1) roll = 1;
    roll = signedRand(r, roll);
    for (int y = y0; y < y1; y++) {
        const uint32_t *sr = b.src + (size_t)wrapi(y - roll, b.h) * b.w;
        uint32_t *dr = b.dst + (size_t)y * b.w;
        for (int k = 0; k < colW; k++) dr[x0 + k] = sr[x0 + k] | GF_ALPHA;
    }
    // tear line 1 px
    int ty = GFRngRange(r, 0, b.h - 1);
    int lx0 = GFRngRange(r, 0, b.w / 2);
    int lx1 = clampi(lx0 + GFRngRange(r, b.w / 4, b.w), 0, b.w);
    uint32_t c = GFRngChance(r, 0.5f) ? GFPx(0, 255, 255) : GFPx(255, 255, 255);
    for (int x = lx0; x < lx1; x++) b.dst[(size_t)ty * b.w + x] = c;
}

static void evChannelDrop(GFBuf b, GFRng *r) {
    GFRectI q = randRect(r, b, b.w / 8, b.w, 10, b.h / 4);
    int shift = (int[]){16, 8, 0}[GFRngRange(r, 0, 2)];
    uint32_t keep = ~(0xFFu << shift);
    for (int y = q.y; y < q.y + q.h; y++)
        for (int x = q.x; x < q.x + q.w; x++) {
            size_t i = (size_t)y * b.w + x;
            b.dst[i] = (b.src[i] & keep) | GF_ALPHA;
        }
}

static void evInvertSpeckle(GFBuf b, GFRng *r) {
    GFRectI q = randRect(r, b, b.w / 8, (int)(b.w * 0.8f), 6, b.h / 5);
    for (int y = q.y; y < q.y + q.h; y++)
        for (int x = q.x; x < q.x + q.w; x++) {
            size_t i = (size_t)y * b.w + x;
            b.dst[i] = (~b.src[i] & 0x00FFFFFFu) | GF_ALPHA;
        }
    int n = GFRngRange(r, 5, 40);
    for (int i = 0; i < n; i++) {
        int sw = GFRngRange(r, 1, 3), sh = GFRngRange(r, 1, 2);
        int sx = GFRngRange(r, 0, b.w - sw), sy = GFRngRange(r, 0, b.h - sh);
        for (int y = sy; y < sy + sh; y++)
            for (int x = sx; x < sx + sw; x++) {
                size_t k = (size_t)y * b.w + x;
                b.dst[k] = (~b.src[k] & 0x00FFFFFFu) | GF_ALPHA;
            }
    }
}

static void evSaltNoise(GFBuf b, GFRng *r, float I) {
    GFRectI q = randRect(r, b, b.w / 4, b.w, b.h / 8, b.h);
    float density = (0.002f + GFRngFloat(r) * 0.03f) * (0.5f + 0.5f * I);
    int count = (int)((float)q.w * (float)q.h * density);
    for (int i = 0; i < count; i++) {
        int x = q.x + GFRngRange(r, 0, q.w - 1);
        int y = q.y + GFRngRange(r, 0, q.h - 1);
        b.dst[(size_t)y * b.w + x] = GFRngChance(r, 0.5f) ? GFPx(0, 0, 0) : GFPx(255, 255, 255);
    }
}

// --- Classe ------------------------------------------------------------------

@implementation GlitchCompositor {
    uint32_t *_src;
    uint32_t *_dst;
    CGContextRef _ctx;
    int _w, _h;
}

- (instancetype)initWithWidth:(int)width height:(int)height {
    if (width < 8 || height < 8) return nil;
    if ((self = [super init])) {
        _w = width; _h = height;
        size_t bytes = (size_t)width * height * 4;
        _src = calloc(1, bytes);
        _dst = calloc(1, bytes);
        if (!_src || !_dst) return nil;
        CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
        _ctx = CGBitmapContextCreate(_dst, width, height, 8, (size_t)width * 4, cs,
                                     kCGBitmapByteOrder32Little | kCGImageAlphaPremultipliedFirst);
        CGColorSpaceRelease(cs);
        if (!_ctx) return nil;
    }
    return self;
}

- (void)dealloc {
    if (_ctx) CGContextRelease(_ctx);
    free(_src);
    free(_dst);
}

- (int)width { return _w; }
- (int)height { return _h; }
- (uint32_t *)source { return _src; }

- (void)fillSourceWithAbstractBands:(GFRng *)r {
    static const uint32_t pal[6] = {
        GF_ALPHA | 0x0000FFFFu, GF_ALPHA | 0x00FF00C8u, GF_ALPHA | 0x00FF2828u,
        GF_ALPHA | 0x00FFFFFFu, GF_ALPHA | 0x00000000u, GF_ALPHA | 0x003CFF78u
    };
    int y = 0;
    while (y < _h) {
        int end = y + GFRngRange(r, 2, 40);
        if (end > _h) end = _h;
        float kind = GFRngFloat(r);
        uint32_t flat = 0;
        bool noisy = false;
        if (kind < 0.45f) { uint32_t g = (uint32_t)GFRngRange(r, 0, 255); flat = GFPx(g, g, g); }
        else if (kind < 0.75f) { flat = pal[GFRngRange(r, 0, 5)]; }
        else { noisy = true; }
        for (int row = y; row < end; row++) {
            uint32_t *d = _src + (size_t)row * _w;
            for (int x = 0; x < _w; x++) {
                if (noisy) { uint32_t g = (uint32_t)GFRngRange(r, 0, 255); d[x] = GFPx(g, g, g); }
                else d[x] = flat;
            }
        }
        y = end;
    }
}

- (void)renderEvent:(GFEventType)type intensity:(float)I rng:(GFRng *)r {
    memset(_dst, 0, (size_t)_w * _h * 4);
    GFBuf b = { _src, _dst, _w, _h };
    switch (type) {
        case GFEventSliceTear:     evSliceTear(b, r, I); break;
        case GFEventRGBSplit:      evRGBSplit(b, r, I); break;
        case GFEventBlockSteal:    evBlockSteal(b, r, I); break;
        case GFEventVerticalRoll:  evVerticalRoll(b, r, I); break;
        case GFEventChannelDrop:   evChannelDrop(b, r); break;
        case GFEventInvertSpeckle: evInvertSpeckle(b, r); break;
        case GFEventSaltNoise:     evSaltNoise(b, r, I); break;
        case GFEventMicro:         evMicro(b, r); break;
    }
}

- (CGImageRef)copyOverlayImage {
    return CGBitmapContextCreateImage(_ctx);
}

@end
