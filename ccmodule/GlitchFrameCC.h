#import <UIKit/UIKit.h>

// Déclaration minimale : la classe réelle vit dans ControlCenterUIKit (framework privé).
@interface CCUIToggleModule : NSObject
- (UIImage *)iconGlyph;
- (UIColor *)selectedColor;
- (BOOL)isSelected;
- (void)setSelected:(BOOL)selected;
- (void)refreshState;
@end

@interface GlitchFrameCC : CCUIToggleModule
@end
