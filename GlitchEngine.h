#import <Foundation/Foundation.h>

// Moteur de glitch stochastique. Thread principal uniquement.
@interface GlitchEngine : NSObject
+ (instancetype)shared;

// Démarre si enabled && active, sinon arrête tout (fenêtre retirée, buffers libérés,
// synchrone dans le même tour de runloop).
- (void)updateWithEnabled:(BOOL)enabled active:(BOOL)active;
@end
