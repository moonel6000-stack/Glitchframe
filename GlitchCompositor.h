#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#include <stdint.h>
#include <stdbool.h>

// --- RNG SplitMix64, seedé une seule fois à l'activation ---------------------
typedef struct { uint64_t state; } GFRng;

static inline void GFRngSeed(GFRng *r, uint64_t seed) { r->state = seed; }

static inline uint64_t GFRngNext(GFRng *r) {
    uint64_t z = (r->state += 0x9E3779B97F4A7C15ULL);
    z = (z ^ (z >> 30)) * 0xBF58476D1CE4E5B9ULL;
    z = (z ^ (z >> 27)) * 0x94D049BB133111EBULL;
    return z ^ (z >> 31);
}

// [0,1)
static inline float GFRngFloat(GFRng *r) {
    return (float)(GFRngNext(r) >> 40) * (1.0f / 16777216.0f);
}

// entier inclusif [lo,hi]
static inline int GFRngRange(GFRng *r, int lo, int hi) {
    if (hi <= lo) return lo;
    uint64_t span = (uint64_t)(hi - lo) + 1;
    return lo + (int)(((GFRngNext(r) >> 32) * span) >> 32);
}

static inline bool GFRngChance(GFRng *r, float p) { return GFRngFloat(r) < p; }

// --- Types d'event -----------------------------------------------------------
typedef NS_ENUM(NSInteger, GFEventType) {
    GFEventSliceTear = 0,
    GFEventRGBSplit,
    GFEventBlockSteal,
    GFEventVerticalRoll,
    GFEventChannelDrop,
    GFEventInvertSpeckle,
    GFEventSaltNoise,
    GFEventMicro,          // quasi invisible, hors tirage pondéré
};
#define GF_WEIGHTED_EVENT_COUNT 7

// Compositor CPU : buffers BGRA premultiplié en RAM. L'overlay reste transparent
// partout sauf dans les bandes / rects corrompus.
@interface GlitchCompositor : NSObject
@property (nonatomic, readonly) int width;
@property (nonatomic, readonly) int height;
@property (nonatomic, readonly) uint32_t *source;   // snapshot (ou bandes abstraites)

- (instancetype)initWithWidth:(int)width height:(int)height;

// Repli si la capture échoue : remplit la source de bandes / bruit abstraits.
- (void)fillSourceWithAbstractBands:(GFRng *)rng;

// Efface l'overlay puis redessine tout depuis zéro (paramètres re-tirés).
- (void)renderEvent:(GFEventType)type intensity:(float)intensity rng:(GFRng *)rng;

- (CGImageRef)copyOverlayImage CF_RETURNS_RETAINED;
@end
