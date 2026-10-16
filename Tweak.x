#import <UIKit/UIKit.h>
#import <notify.h>
#import "GlitchEngine.h"

#define GF_DOMAIN CFSTR("com.glitchframe.glitchframe")
#define GF_NOTIFY "com.glitchframe.enabled"

static int  gToken  = -1;
static BOOL gActive = NO;

// Priorité à l'état Darwin (lisible depuis les apps sandboxées), sinon la pref.
// État : 0 = inconnu, 1 = off, 2 = on.
static BOOL GFReadEnabled(void) {
    if (gToken != -1) {
        uint64_t st = 0;
        if (notify_get_state(gToken, &st) == NOTIFY_STATUS_OK && st != 0) return st == 2;
    }
    CFPreferencesAppSynchronize(GF_DOMAIN);
    BOOL on = NO;
    CFPropertyListRef v = CFPreferencesCopyAppValue(CFSTR("enabled"), GF_DOMAIN);
    if (v) {
        if (CFGetTypeID(v) == CFBooleanGetTypeID()) on = CFBooleanGetValue((CFBooleanRef)v);
        CFRelease(v);
    }
    return on;
}

static void GFApply(void) {
    [[GlitchEngine shared] updateWithEnabled:GFReadEnabled() active:gActive];
}

%ctor {
    @autoreleasepool {
        if (!NSClassFromString(@"UIApplication")) return;
        // Pas d'extensions ni de daemons : seulement les bundles .app (apps + SpringBoard).
        if (![[[NSBundle mainBundle] bundlePath].pathExtension isEqualToString:@"app"]) return;

        if (notify_register_dispatch(GF_NOTIFY, &gToken, dispatch_get_main_queue(), ^(int t) {
                UIApplication *app = [UIApplication sharedApplication];
                if (app) gActive = (app.applicationState == UIApplicationStateActive);
                GFApply();
            }) != NOTIFY_STATUS_OK) {
            gToken = -1;
        }

        NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
        NSOperationQueue *main = [NSOperationQueue mainQueue];
        [nc addObserverForName:UIApplicationDidBecomeActiveNotification object:nil queue:main
                    usingBlock:^(NSNotification *n) { gActive = YES; GFApply(); }];
        [nc addObserverForName:UIApplicationWillResignActiveNotification object:nil queue:main
                    usingBlock:^(NSNotification *n) { gActive = NO; GFApply(); }];
        [nc addObserverForName:UIApplicationDidEnterBackgroundNotification object:nil queue:main
                    usingBlock:^(NSNotification *n) { gActive = NO; GFApply(); }];
    }
}
