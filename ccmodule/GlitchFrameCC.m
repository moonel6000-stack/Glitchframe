#import "GlitchFrameCC.h"
#import <notify.h>

#define GF_DOMAIN CFSTR("com.glitchframe.glitchframe")
#define GF_NOTIFY "com.glitchframe.enabled"

static BOOL GFPrefEnabled(void) {
    CFPreferencesAppSynchronize(GF_DOMAIN);
    BOOL on = NO;
    CFPropertyListRef v = CFPreferencesCopyAppValue(CFSTR("enabled"), GF_DOMAIN);
    if (v) {
        if (CFGetTypeID(v) == CFBooleanGetTypeID()) on = CFBooleanGetValue((CFBooleanRef)v);
        CFRelease(v);
    }
    return on;
}

static void GFWritePref(BOOL on) {
    CFPreferencesSetAppValue(CFSTR("enabled"), on ? kCFBooleanTrue : kCFBooleanFalse, GF_DOMAIN);
    CFPreferencesAppSynchronize(GF_DOMAIN);
}

// Le module ne dessine rien : il publie l'état (1 = off, 2 = on) puis notifie.
static void GFPostEnabled(BOOL on) {
    static int token = -1;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        if (notify_register_check(GF_NOTIFY, &token) != NOTIFY_STATUS_OK) token = -1;
    });
    if (token != -1) notify_set_state(token, on ? 2 : 1);
    notify_post(GF_NOTIFY);
}

@implementation GlitchFrameCC

- (UIImage *)iconGlyph {
    UIImage *img = [UIImage systemImageNamed:@"waveform.path.ecg"];
    return [img imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
}

- (UIColor *)selectedColor {
    return [UIColor colorWithRed:0.91 green:1.0 blue:0.96 alpha:1.0];
}

- (BOOL)isSelected {
    return GFPrefEnabled();
}

- (void)setSelected:(BOOL)selected {
    GFWritePref(selected);
    GFPostEnabled(selected);
    [self refreshState];
}

@end
