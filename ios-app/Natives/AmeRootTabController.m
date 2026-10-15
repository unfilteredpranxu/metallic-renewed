//
//  AmeRootTabController.m
//  ★ [ROOTTAB] See the header comments.
//
//  ★ Version 3 (proper structure, matching Music / LiveContainer / SideStore):
//    Root = UITabBarController, with five tabs that are each **real pages**, all managed by UIKit:
//      · Touches: handled by UIKit (no manually inserted views or disabled interaction — problems in v2)
//      · Lifecycle: real child controllers ⇒ viewWillAppear and other callbacks work (fixes "JIT keeps checking")
//      · Orientation / safe area: calculated by UIKit
//    Version 2 manually inserted Home as a "backdrop" subview ⇒ the container swallowed touches,
//    lifecycle callbacks did not run, and JIT did not refresh; users reported all three bugs at once.
//    That approach has been abandoned.
//
#import "AmeRootTabController.h"
#import "utils.h"   // ★ [I18N] localize()
#import "ios_uikit_bridge.h"   // ★ [GAME-LANDSCAPE] Query game-orientation lock state (AmeGameLandscapeLockActive).
#import "DownloadViewController.h"
#import "VersionManagerViewController.h"
// ★ [TAB-INST-REVERT] The "Instances" tab is back to a single page ⇒ this file no longer needs
// LauncherCardLayoutViewController.h (E1InstancesPanelView is not instantiated here; the class
// remains in LauncherCardLayoutViewController.{h,m}).
#import "LauncherPreferencesViewController.h"
#import "AI/AISessionListViewController.h"
// ★ [MP-RESTORE] Multiplayer entry point.
#import "TerracottaViewController.h"
#import "HomeTopNavView.h"
#import "BottomActionBarView.h"   // AmePinkGlassButton
#import <objc/message.h>

NSString * const AmeTabTappedNotification = @"AmeTabTapped";   // ★ [ROOTTAB]

@interface AmeRootTabController () <UITabBarControllerDelegate, UINavigationControllerDelegate>   // ★ Declare the protocol to eliminate the delegate-assignment warning.
@property (nonatomic, strong) HomeTopNavView *topNav;
@property (nonatomic, strong) AmePinkGlassButton *floatingDoneButton;   // bottom-right "Done" shown on pushed pages
@end

// ★ [TAB-INST-REVERT] Removed the segmented InstancesTabViewController container: the "Instances"
//   tab (index 3) is restored to a single VersionManagerViewController page (same as before
//   [TAB-CROSSTALK], with its own navigation stack/back-button behavior).
//   The E1 instance grid E1InstancesPanelView remains in LauncherCardLayoutViewController.{h,m},
//   but currently has no active host (nothing in the repo calls e1ShowInstancesPage) ⇒ it is not
//   shown under either the "Home" or "Instances" tab.

#pragma mark - ★ [TAB-OVERLAP] Zero-duration tab transition (ensure only one page view exists at a time)

/// ★ [TAB-OVERLAP] Make UIKit's tab switch instantaneous, without a cross-fade.
/// Background: the system's default tab transition cross-fades container snapshots, so the source
/// and destination pages coexist during the transition.
/// If users rapidly tap different bottom-bar buttons, a new transition can begin before the prior
/// one ends, leaving two page snapshots in the container ⇒ visible "overlap / ghosting".
/// Return a zero-duration animator: remove the old page, attach the new page, then immediately call
/// completeTransition. Structurally, there is only one page view at a time ⇒ rapid taps cannot overlap.
/// Uses only public APIs; does not change selection state or page lifecycle and does not disable taps.
@interface AmeTabInstantAnimator : NSObject <UIViewControllerAnimatedTransitioning>
@end

@implementation AmeTabInstantAnimator

- (NSTimeInterval)transitionDuration:(nullable id<UIViewControllerContextTransitioning>)transitionContext {
    return 0.0;
}

- (void)animateTransition:(id<UIViewControllerContextTransitioning>)transitionContext {
    UIView *container = transitionContext.containerView;
    UIViewController *fromVC = [transitionContext viewControllerForKey:UITransitionContextFromViewControllerKey];
    UIViewController *toVC   = [transitionContext viewControllerForKey:UITransitionContextToViewControllerKey];

    UIView *toView   = [transitionContext viewForKey:UITransitionContextToViewKey]   ?: (toVC ? toVC.view : nil);
    UIView *fromView = [transitionContext viewForKey:UITransitionContextFromViewKey] ?: (fromVC ? fromVC.view : nil);

    if (toView) {
        toView.frame = [transitionContext finalFrameForViewController:toVC];
        toView.alpha = 1.0;
        [container addSubview:toView];
    }
    if (fromView && fromView.superview == container) {
        [fromView removeFromSuperview];    // ★ Key: remove the old page immediately, leaving no snapshot ⇒ no overlap.
    }
    // The tab bar is also a sibling of the container: after adding the new page on top, bring the bar
    // back to the front so content does not cover it.
    for (UIView *sv in container.subviews) {
        if ([sv isKindOfClass:[UITabBar class]]) {
            [container bringSubviewToFront:sv];
        }
    }
    [transitionContext completeTransition:YES];
}

@end

@implementation AmeRootTabController

/// Wrap each page in a navigation controller so pages can push/present their own flows.
static UIViewController *AmeWrapInNav(UIViewController *vc) {
    if (!vc) return [[UIViewController alloc] init];
    if ([vc isKindOfClass:[UINavigationController class]]) return vc;
    return [[UINavigationController alloc] initWithRootViewController:vc];
}

+ (instancetype)tabControllerWithHomeViewController:(UIViewController *)home {
    AmeRootTabController *tbc = [[AmeRootTabController alloc] init];

    // ★ [I18N] Five tabs: Home · Downloads · AI · Instances · Settings (★ "Multiplayer" removed as requested).
    // Titles are resolved through localize() from the tab.* keys in Localizable.strings.
    // SceneDelegate rebuilds the root UI when the language changes, refreshing these titles.
    NSArray<NSDictionary *> *items = @[
        @{@"t": localize(@"tab.home", @"Home"),      @"i": @"house.fill"},
        @{@"t": localize(@"tab.download", @"Downloads"),  @"i": @"arrow.down.circle.fill"},
        @{@"t": localize(@"tab.ai", @"AI"),          @"i": @"sparkles"},
        @{@"t": localize(@"tab.instances", @"Instances"), @"i": @"square.stack.3d.up.fill"},
        @{@"t": localize(@"tab.settings", @"Settings"),  @"i": @"gearshape.fill"},
    ];

    NSMutableArray<UIViewController *> *vcs = [NSMutableArray arrayWithCapacity:items.count];
    for (NSInteger i = 0; i < (NSInteger)items.count; i++) {
        UIViewController *content = nil;
        switch (i) {
            case 0: content = home ?: [[UIViewController alloc] init]; break;   // Home = all existing launcher screens.
            // ★ [ROOTTAB-FIX] Downloads = "Download Instances" (DownloadViewController: seven tabs for versions/mods/shaders/resource packs…).
            //   ★ Do not wrap it in a navigation controller — that adds another navigation bar and pushes the
            //   entire content down (user report: "the Download Instances screen is still a little too low").
            case 1: content = [[DownloadViewController alloc] init]; break;
            case 2: content = [[AISessionListViewController alloc] init]; break;
            case 3: content = [[VersionManagerViewController alloc] init]; break;   // ★ [TAB-INST-REVERT] Instances tab = single Version Manager page (restored, no segments).
            case 4: content = [[LauncherPreferencesViewController alloc] init]; break;
            default: content = [[UIViewController alloc] init]; break;
        }

        // ★ [ROOTTAB-FIX] tabBarItem must be set on the content VC: a navigation controller replaces
        //   its own item with the top page's item — in the previous version it was set on the nav,
        //   so the third tab appeared as "Session List".
        content.tabBarItem = [[UITabBarItem alloc] initWithTitle:items[i][@"t"]
                                                          image:[UIImage systemImageNamed:items[i][@"i"]]
                                                  selectedImage:nil];
        content.tabBarItem.tag = i;

        UIViewController *vc = AmeWrapInNav(content);   // ★ Wrap all pages in nav controllers for nested flows (see RootVC:719 comment).
        // Track the stack depth so the floating Done button knows when to appear.
        if ([vc isKindOfClass:[UINavigationController class]] && ((UINavigationController *)vc).delegate == nil) {
            ((UINavigationController *)vc).delegate = tbc;
        }
        [vcs addObject:vc];
    }
    tbc.viewControllers = vcs;
    tbc.selectedIndex = 0;
    tbc.delegate = tbc;

    // ★ Do not set UITabBarAppearance; doing so overrides the system glass on iOS 26.
    return tbc;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    // Keep the tab controller's own view transparent (otherwise it shows as a black area); the
    // window and individual pages handle the wallpaper.
    self.view.backgroundColor = [UIColor clearColor];
    
    self.tabBar.hidden = YES; // hide the bottom system bar

    self.topNav = [[HomeTopNavView alloc] init];
    self.topNav.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.topNav];
    UILayoutGuide *safe = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [self.topNav.topAnchor constraintEqualToAnchor:safe.topAnchor constant:8],
        [self.topNav.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor constant:16],
        [self.topNav.trailingAnchor constraintLessThanOrEqualToAnchor:safe.trailingAnchor constant:-16],
    ]];

    // Pages below the bar start under it: bar height 60 + 8 top margin + 8 gap = 76.
    // Home (index 0) reserves its own space in LauncherNewsViewController (kHomeNavReserve),
    // so it is skipped here to avoid a double offset.
    for (NSUInteger i = 1; i < self.viewControllers.count; i++) {
        self.viewControllers[i].additionalSafeAreaInsets = UIEdgeInsetsMake(76, 0, 0, 0);
    }

    // Floating "Done" (bottom-right): the pages' own Done buttons sit in a navigation bar that ends up
    // under the top nav, so on every pushed page this one is always reachable.
    self.floatingDoneButton = [AmePinkGlassButton buttonWithType:UIButtonTypeSystem];
    self.floatingDoneButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.floatingDoneButton setTitle:localize(@"resman.common.done", @"Done") forState:UIControlStateNormal];
    [self.floatingDoneButton setTitleColor:[UIColor labelColor] forState:UIControlStateNormal];
    self.floatingDoneButton.titleLabel.font = [UIFont systemFontOfSize:15.0 weight:UIFontWeightSemibold];
    UIImage *doneImage = [[UIImage systemImageNamed:@"checkmark"] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    if (doneImage) [self.floatingDoneButton setImage:doneImage forState:UIControlStateNormal];
    self.floatingDoneButton.contentEdgeInsets = UIEdgeInsetsMake(0, 18, 0, 18);
    self.floatingDoneButton.imageEdgeInsets = UIEdgeInsetsMake(0, -4, 0, 4);
    self.floatingDoneButton.titleEdgeInsets = UIEdgeInsetsMake(0, 4, 0, -4);
    AmeApplyPinkGlassButtonStyle(self.floatingDoneButton);
    self.floatingDoneButton.hidden = YES;
    [self.floatingDoneButton addTarget:self action:@selector(ameFloatingDoneTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.floatingDoneButton];
    [NSLayoutConstraint activateConstraints:@[
        [self.floatingDoneButton.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor constant:-16],
        [self.floatingDoneButton.bottomAnchor constraintEqualToAnchor:safe.bottomAnchor constant:-12],
        [self.floatingDoneButton.heightAnchor constraintEqualToConstant:40],
        [self.floatingDoneButton.widthAnchor constraintGreaterThanOrEqualToConstant:104],
    ]];

    // Pages that swap their content without a navigation push (Accounts, ...) post this so the floating
    // Done can appear / disappear.
    __weak typeof(self) refreshWeakSelf = self;
    [[NSNotificationCenter defaultCenter] addObserverForName:@"AmeFloatingDoneRefresh" object:nil queue:[NSOperationQueue mainQueue]
                                                  usingBlock:^(NSNotification *note) {
        __strong typeof(refreshWeakSelf) strongSelf = refreshWeakSelf;
        if (!strongSelf) return;
        [strongSelf ameUpdateFloatingDoneButton];
        dispatch_async(dispatch_get_main_queue(), ^{ [strongSelf ameUpdateFloatingDoneButton]; });
    }];

    __weak typeof(self) weakSelf = self;
    self.topNav.onSelect = ^(NSInteger index) {
        // Home always resets: close anything presented, pop back to the home page, scroll to top.
        if (index == 0) { [weakSelf ameResetToHome]; return; }
        if (index < (NSInteger)weakSelf.viewControllers.count) weakSelf.selectedIndex = index;
    };
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    [self.view bringSubviewToFront:self.topNav];
    [self.view bringSubviewToFront:self.floatingDoneButton];
}

#pragma mark - Floating Done button

/// Finds the deepest navigation controller currently on screen inside `vc` (pages such as Accounts are
/// hosted in a nested navigation controller that lives inside a container page).
- (UINavigationController *)ameDeepestNavigationControllerIn:(UIViewController *)vc {
    UINavigationController *found = [vc isKindOfClass:[UINavigationController class]] ? (UINavigationController *)vc : nil;
    UIViewController *probe = found ? found.topViewController : vc;
    for (NSInteger depth = 0; probe && depth < 8; depth++) {
        UINavigationController *inner = nil;
        for (UIViewController *child in probe.childViewControllers) {
            if ([child isKindOfClass:[UINavigationController class]] && child.isViewLoaded && child.view.window && !child.view.hidden) {
                inner = (UINavigationController *)child;
            }
        }
        if (!inner) break;
        found = inner;
        probe = inner.topViewController;
    }
    return found;
}

/// A page's own Done / Close / Back bar button (these sit in the navigation bar, which ends up under
/// the top nav pill, so they cannot be pressed).
- (UIBarButtonItem *)ameOwnExitItemOfNav:(UINavigationController *)nav {
    UINavigationItem *item = nav.topViewController.navigationItem;
    NSMutableArray<UIBarButtonItem *> *candidates = [NSMutableArray array];
    if (item.leftBarButtonItems) [candidates addObjectsFromArray:item.leftBarButtonItems];
    if (item.rightBarButtonItems) [candidates addObjectsFromArray:item.rightBarButtonItems];
    NSString *doneTitle = localize(@"resman.common.done", @"Done");
    for (UIBarButtonItem *bar in candidates) {
        NSString *name = bar.action ? NSStringFromSelector(bar.action) : nil;
        if (!name || !bar.target) continue;
        NSString *lower = name.lowercaseString;
        BOOL byName = [lower containsString:@"done"] || [lower containsString:@"close"]
                   || [lower containsString:@"back"] || [lower containsString:@"dismiss"]
                   || [lower containsString:@"finish"];
        BOOL byTitle = bar.title.length && [bar.title isEqualToString:doneTitle];
        if ((byName || byTitle) && [bar.target respondsToSelector:bar.action]) return bar;
    }
    return nil;
}

/// Shown whenever the selected tab has a page pushed on top of its root, or the visible page has its
/// own Done / Back button (e.g. Accounts).
- (void)ameUpdateFloatingDoneButton {
    UIViewController *selected = self.selectedViewController;
    BOOL deep = [selected isKindOfClass:[UINavigationController class]]
             && ((UINavigationController *)selected).viewControllers.count > 1;
    UINavigationController *inner = [self ameDeepestNavigationControllerIn:selected];
    BOOL hasOwnExit = inner && [self ameOwnExitItemOfNav:inner] != nil;
    BOOL show = deep || hasOwnExit;
    self.floatingDoneButton.hidden = !show;
    if (show) [self.view bringSubviewToFront:self.floatingDoneButton];
}

/// Runs the page's own Done / Close / Back bar button (so it can save before closing); falls back to
/// going back to the tab's root page.
- (void)ameFloatingDoneTapped {
    UIViewController *selected = self.selectedViewController;
    UINavigationController *inner = [self ameDeepestNavigationControllerIn:selected];
    UIBarButtonItem *bar = inner ? [self ameOwnExitItemOfNav:inner] : nil;
    if (bar) {
        void (*send)(id, SEL, id) = (void (*)(id, SEL, id))objc_msgSend;
        send(bar.target, bar.action, bar);
        [self ameUpdateFloatingDoneButton];
        dispatch_async(dispatch_get_main_queue(), ^{ [self ameUpdateFloatingDoneButton]; });
        return;
    }
    if ([selected isKindOfClass:[UINavigationController class]]) {
        [(UINavigationController *)selected popToRootViewControllerAnimated:YES];
    }
    [self ameUpdateFloatingDoneButton];
}

#pragma mark - UINavigationControllerDelegate

- (void)navigationController:(UINavigationController *)navigationController
       didShowViewController:(UIViewController *)viewController
                    animated:(BOOL)animated {
    [self ameUpdateFloatingDoneButton];
}

/// Pressing Home: dismiss any sheet/modal, pop the home stack to its root, switch to the Home tab
/// and tell the home page to reset itself (scroll to top, close the profile panel, leave edit mode).
- (void)ameResetToHome {
    __weak typeof(self) weakSelf = self;
    void (^reset)(void) = ^{
        __strong typeof(weakSelf) self_ = weakSelf;
        if (!self_) return;
        UIViewController *homeVC = self_.viewControllers.firstObject;
        if ([homeVC isKindOfClass:[UINavigationController class]]) {
            [(UINavigationController *)homeVC popToRootViewControllerAnimated:NO];
        }
        self_.selectedIndex = 0;
        [[NSNotificationCenter defaultCenter] postNotificationName:@"AmeHomeTabReset" object:nil];
    };
    UIViewController *presented = self.presentedViewController ?: self.selectedViewController.presentedViewController;
    if (presented) {
        [presented dismissViewControllerAnimated:YES completion:reset];
    } else {
        reset();
    }
}

- (void)setSelectedIndex:(NSUInteger)selectedIndex {
    [super setSelectedIndex:selectedIndex];
    self.topNav.selectedIndex = selectedIndex;
    [self ameUpdateFloatingDoneButton];
}

#pragma mark - ★ [GAME-LANDSCAPE] Lock landscape during launch/gameplay (root-controller layer)

// This is the app's window.rootViewController (installed by SceneDelegate); all launcher pages live below it.
// Window-scene orientation = intersection of the root-controller chain ⇒ narrowing here is the
// **decisive** layer for locking landscape during launch.
// When unlocked, return [super ...] (byte-for-byte the same as before: iPhone=allButUpsideDown /
// iPad=all), preserving existing behavior.
- (BOOL)shouldAutorotate {
    if (AmeGameLandscapeLockActive()) return NO;   // ★ [GAME-LANDSCAPE]
    return [super shouldAutorotate];
}

- (UIInterfaceOrientationMask)supportedInterfaceOrientations {
    if (AmeGameLandscapeLockActive()) return UIInterfaceOrientationMaskLandscape;   // ★ [GAME-LANDSCAPE]
    return UIInterfaceOrientationMaskLandscape;   // landscape only
}

#pragma mark - UITabBarControllerDelegate

- (void)tabBarController:(UITabBarController *)tabBarController
 didSelectViewController:(UIViewController *)viewController {
    NSInteger idx = [tabBarController.viewControllers indexOfObject:viewController];
    if (idx == NSNotFound) return;
    NSLog(@"[ROOTTAB] tap index=%ld", (long)idx);
    // Broadcast to legacy code that cares about navigation (LauncherMenuViewController, etc.);
    // UIKit handles switching the page itself.
    [[NSNotificationCenter defaultCenter] postNotificationName:AmeTabTappedNotification
                                                       object:nil
                                                     userInfo:@{@"index": @(idx)}];
}

#pragma mark - ★ [TAB-OVERLAP] Bottom-bar tab transition

/// ★ [TAB-OVERLAP] Use a zero-duration transition for tab switches (see AmeTabInstantAnimator):
/// rapid taps on different bottom-bar buttons can no longer leave a window where the previous
/// snapshot remains while the next one appears ⇒ no overlap.
- (id<UIViewControllerAnimatedTransitioning>)tabBarController:(UITabBarController *)tabBarController
        animationControllerForTransitionFromViewController:(UIViewController *)fromViewController
                                          toViewController:(UIViewController *)toViewController {
    return [[AmeTabInstantAnimator alloc] init];
}

@end
