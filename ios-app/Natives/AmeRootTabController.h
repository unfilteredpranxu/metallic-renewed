//
//  AmeRootTabController.h
//  ★ [ROOTTAB] Replace the app root with a real UITabBarController—Music / LiveContainer /
//  SideStore all use this structure: the root is the tab bar controller, with pages above it;
//  the system draws the bottom bar itself (glass / height / corner radius / portrait-landscape adaptation).
//
//  Why it must be the root (rather than being placed inside a small container):
//    On iOS 26, the tab bar uses its standard appearance only when its controller owns the full screen.
//    Putting it in a 68/92pt container is treated as a compact environment: titles move to the right
//    of the icons and the bar falls back to an opaque fill (the user's screenshot showed solid black).
//
#import <UIKit/UIKit.h>

/// Tab-tap notification: userInfo = @{@"index": @(0…4)}. LauncherMenuViewController listens
/// and calls the existing handleMenuSelection: directly, leaving navigation semantics unchanged.
extern NSString * const AmeTabTappedNotification;

@class HomeActionPanelView;

@interface AmeRootTabController : UITabBarController
/// Create a controller with the given home (content): five tabs = Home / Downloads / AI / Instances / Settings.
/// The home hosts the real content (LauncherRootViewController or CardLayout); the other four are shells.
/// Tapping one only broadcasts a notification and immediately selects Home again, so the content
/// remains on screen and the bottom bar always remains system-provided.
+ (instancetype)tabControllerWithHomeViewController:(UIViewController *)home;
/// Adopt the existing Home profile UI without changing its actions or data ownership.
- (void)installNavigationProfilePanel:(HomeActionPanelView *)panel;
- (CGFloat)launcherHeaderReservation;
@end
