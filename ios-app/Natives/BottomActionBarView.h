#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, AmeGlassButtonRole) {
    AmeGlassButtonRolePrimary = 0,
    AmeGlassButtonRoleSecondary,
    AmeGlassButtonRoleSubtle,
    AmeGlassButtonRoleNavigation,
    AmeGlassButtonRoleDestructive,
};

/// Existing glass button, with opt-in semantic roles. No action/selection/enabled state is owned here.
/// Default is primary; the legacy class name remains for source compatibility.
@interface AmePinkGlassButton : UIButton
@property (nonatomic, assign) AmeGlassButtonRole ameRole;
/// Presentation only: the action owner must keep its existing busy/disabled logic.
@property (nonatomic, assign) BOOL ameShowsActivityIndicator;
@end

/// The launcher's theme tint: the user's "theme color" from Settings (general.accent_color) when one
/// has been chosen, otherwise the default pink. Listen to "LauncherAppearanceChanged" to refresh.
FOUNDATION_EXPORT UIColor *AmeThemeTintColor(void);

/// Applies (or refreshes) the semantic glass look. Only does something for AmePinkGlassButton.
FOUNDATION_EXPORT void AmeApplyPinkGlassButtonStyle(UIButton *button);

@interface BottomActionBarView : UIView
@property (nonatomic, strong, readonly) UIButton *executeJarButton;
@property (nonatomic, strong, readonly) UIButton *chooseVersionButton;
@end

NS_ASSUME_NONNULL_END
