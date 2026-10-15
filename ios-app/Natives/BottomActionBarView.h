#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// Styles a capsule button as pink liquid glass (translucent glass material, soft pink wash,
/// pink hairline border, pink icon). Safe to call repeatedly, e.g. when the theme refreshes.
FOUNDATION_EXPORT void AmeApplyPinkGlassButtonStyle(UIButton *button);

@interface BottomActionBarView : UIView
@property (nonatomic, strong, readonly) UIButton *executeJarButton;
@property (nonatomic, strong, readonly) UIButton *chooseVersionButton;
@end

NS_ASSUME_NONNULL_END
