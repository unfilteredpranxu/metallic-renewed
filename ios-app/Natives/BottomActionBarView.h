#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// A full-pill glass button: blurred glass base, a pink gradient that fills the WHOLE pill, a pink
/// hairline border and a soft top highlight. The corner radius always follows the height (pill),
/// so it can never turn into a rectangle. Use +buttonWithType: as for any UIButton.
@interface AmePinkGlassButton : UIButton
@end

/// Applies (or refreshes) the pink glass look. Only does something for AmePinkGlassButton.
FOUNDATION_EXPORT void AmeApplyPinkGlassButtonStyle(UIButton *button);

@interface BottomActionBarView : UIView
@property (nonatomic, strong, readonly) UIButton *executeJarButton;
@property (nonatomic, strong, readonly) UIButton *chooseVersionButton;
@end

NS_ASSUME_NONNULL_END
