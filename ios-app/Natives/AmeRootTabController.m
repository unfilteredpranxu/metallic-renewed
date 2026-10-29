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
#import "HomeActionPanelView.h"
#import "LauncherNewsViewController.h"
#import "BackgroundSettingsViewController.h"
#import "UIKit+GlassSurface.h"
#import "BottomActionBarView.h"   // AmePinkGlassButton


NSString * const AmeTabTappedNotification = @"AmeTabTapped";   // ★ [ROOTTAB]

@interface AmeRootTabController () <UITabBarControllerDelegate, UINavigationControllerDelegate, UIContextMenuInteractionDelegate>   // ★ Declare the protocol to eliminate the delegate-assignment warning.
@property (nonatomic, strong) HomeTopNavView *topNav;
@property (nonatomic, strong) UIView *navigationGroup;
@property (nonatomic, strong) UIView *brandView;
@property (nonatomic, strong) UIButton *themeButton;
@property (nonatomic, strong) UILabel *brandLabel;
@property (nonatomic, strong) UIImageView *brandLogo;
@property (nonatomic, strong) NSDictionary<NSString *,NSLayoutConstraint *> *headerMetrics;
@property (nonatomic, assign) NSUInteger pendingSelection;
@property (nonatomic, assign) BOOL waitingForTransition;
@property (nonatomic, strong) UILayoutGuide *profileSlot;
@property (nonatomic, strong) HomeActionPanelView *navigationProfilePanel;
@property (nonatomic, strong) NSLayoutConstraint *profileSlotWidth;
@property (nonatomic, strong) NSLayoutConstraint *profileSlotHeight;
@property (nonatomic, strong) UIMenu *toolsMenu;
@property (nonatomic, strong) UIButton *profileToolsButton;
@property (nonatomic, strong) UIAction *aiAction;
@property (nonatomic, strong) AmePinkGlassButton *floatingDoneButton;   // bottom-right "Done" shown on pushed pages
@end

// ★ [TAB-INST-REVERT] Removed the segmented InstancesTabViewController container: the "Instances"
//   tab (index 3) is restored to a single VersionManagerViewController page (same as before
//   [TAB-CROSSTALK], with its own navigation stack/back-button behavior).
//   The E1 instance grid E1InstancesPanelView remains in LauncherCardLayoutViewController.{h,m},
//   but currently has no active host (nothing in the repo calls e1ShowInstancesPage) ⇒ it is not
//   shown under either the "Home" or "Instances" tab.

// UIKit owns all tab content and transitions. Never inspect or remove its internal containers.
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
            case AMELauncherTabHome: content = home ?: [[UIViewController alloc] init]; break;   // Home = all existing launcher screens.
            // ★ [ROOTTAB-FIX] Downloads = "Download Instances" (DownloadViewController: seven tabs for versions/mods/shaders/resource packs…).
            //   ★ Do not wrap it in a navigation controller — that adds another navigation bar and pushes the
            //   entire content down (user report: "the Download Instances screen is still a little too low").
            case AMELauncherTabDownloads: content = [[DownloadViewController alloc] init]; break;
            case AMELauncherTabAI: content = [[AISessionListViewController alloc] init]; break;
            case AMELauncherTabInstances: content = [[VersionManagerViewController alloc] init]; break;   // ★ [TAB-INST-REVERT] Instances tab = single Version Manager page (restored, no segments).
            case AMELauncherTabSettings: content = [[MetallicSettingsContainerViewController alloc] init]; break;
            default: content = [[UIViewController alloc] init]; break;
        }

        // Do not set title/image on content.tabBarItem — on iPadOS 18+, UITabBarController
        // automatically creates a floating top capsule tab bar from tabBarItem titles.
        // Metallic uses its own custom HomeTopNavView exclusively.
        content.tabBarItem = [[UITabBarItem alloc] initWithTitle:nil image:nil tag:i];
        content.hidesBottomBarWhenPushed = YES;

        UIViewController *vc = AmeWrapInNav(content);   // ★ Wrap all pages in nav controllers for nested flows (see RootVC:719 comment).
        vc.hidesBottomBarWhenPushed = YES;
        // Track the stack depth so the floating Done button knows when to appear.
        if ([vc isKindOfClass:[UINavigationController class]] && ((UINavigationController *)vc).delegate == nil) {
            ((UINavigationController *)vc).delegate = tbc;
        }
        [vcs addObject:vc];
    }
    tbc.viewControllers = vcs;
    tbc.selectedIndex = AMELauncherTabHome;
    tbc.delegate = tbc;

    // ★ Do not set UITabBarAppearance; doing so overrides the system glass on iOS 26.
    return tbc;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    // Keep the tab controller's own view transparent (otherwise it shows as a black area); the
    // window and individual pages handle the wallpaper.
    self.view.backgroundColor = [UIColor clearColor];
    
    [self ameSuppressSystemTabBar];

    self.topNav = [[HomeTopNavView alloc] init];
    self.topNav.translatesAutoresizingMaskIntoConstraints = NO;
    self.navigationGroup = [[UIView alloc] init];
    self.navigationGroup.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.navigationGroup];
    [self.navigationGroup addSubview:self.topNav];
    __weak typeof(self) toolsWeakSelf = self;
    UIAction *ai = [UIAction actionWithTitle:localize(@"tab.ai", @"AI")
        image:[UIImage systemImageNamed:@"sparkles"] identifier:nil handler:^(__kindof UIAction *action) {
        __strong typeof(toolsWeakSelf) strongSelf = toolsWeakSelf;
        [strongSelf ameOpenAI];
    }];
    self.aiAction = ai;
    self.toolsMenu = [UIMenu menuWithTitle:@"Tools" children:@[ai]];
    UIAction *jar=[UIAction actionWithTitle:@"Execute JAR" image:[UIImage systemImageNamed:@"doc"] identifier:nil handler:^(__kindof UIAction *action) { [toolsWeakSelf ameForwardHomeOverflow:6]; }];
    UIAction *downloads=[UIAction actionWithTitle:@"Download Center" image:[UIImage systemImageNamed:@"arrow.down.circle"] identifier:nil handler:^(__kindof UIAction *action) { [toolsWeakSelf ameForwardHomeOverflow:5]; }];
    self.topNav.moreMenu=[UIMenu menuWithTitle:@"More" children:@[jar,downloads,ai]];
    self.pendingSelection = NSNotFound;
    self.profileSlot = [[UILayoutGuide alloc] init];
    [self.navigationGroup addLayoutGuide:self.profileSlot];
    self.profileSlotWidth = [self.profileSlot.widthAnchor constraintEqualToConstant:56];
    self.profileSlotHeight = [self.profileSlot.heightAnchor constraintEqualToConstant:56];
    UIButton *theme = [UIButton buttonWithType:UIButtonTypeSystem]; self.themeButton=theme;
    theme.translatesAutoresizingMaskIntoConstraints = NO;
    theme.accessibilityLabel = @"Theme and appearance";
    [theme setImage:[UIImage systemImageNamed:@"moon.fill"] forState:UIControlStateNormal];
    theme.tintColor = AmeUIPrimaryTextColor();
    AmeApplyGlassChipStyle(theme, 26, YES);
    __weak typeof(self) themeOwner=self;
    theme.showsMenuAsPrimaryAction=YES;
    void (^themeProvider)(void (^)(NSArray<UIMenuElement *> *))=^(void (^completion)(NSArray<UIMenuElement *> *)) {
        AmeRootTabController *root=themeOwner;
        UINavigationController *nav=(UINavigationController *)root.viewControllers[AMELauncherTabSettings];
        MetallicSettingsContainerViewController *settings=(MetallicSettingsContainerViewController *)nav.viewControllers.firstObject;
        [settings loadViewIfNeeded];
        NSArray *keys=@[@"auto",@"light",@"dark"],*names=@[@"System",@"Light",@"Dark"];
        id current=settings.preferences.getPreference(@"general",@"ui_theme"); NSMutableArray *actions=[NSMutableArray array];
        for(NSUInteger i=0;i<keys.count;i++) {
            UIAction *action=[UIAction actionWithTitle:names[i] image:nil identifier:nil handler:^(__kindof UIAction *a) { [themeOwner ameApplyReferenceThemeIndex:i]; }];
            action.state=[current isEqual:keys[i]]?UIMenuElementStateOn:UIMenuElementStateOff; [actions addObject:action];
        }
        completion(actions);
    };
    UIDeferredMenuElement *themeChoices;
    if (@available(iOS 15.0, *)) themeChoices=[UIDeferredMenuElement elementWithUncachedProvider:themeProvider];
    else themeChoices=[UIDeferredMenuElement elementWithProvider:themeProvider];
    theme.menu=[UIMenu menuWithTitle:@"Theme" children:@[themeChoices]];
    [self.navigationGroup addSubview:theme];
    UIScrollView *navigationScroll = [[UIScrollView alloc] init];
    navigationScroll.translatesAutoresizingMaskIntoConstraints = NO;
    navigationScroll.showsHorizontalScrollIndicator = NO;
    navigationScroll.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;
    [self.navigationGroup addSubview:navigationScroll];
    [navigationScroll addSubview:self.topNav];
    UILayoutGuide *safe = self.view.safeAreaLayoutGuide;
    NSLayoutConstraint *preferredWidth = [navigationScroll.widthAnchor constraintEqualToConstant:938*.8];
    preferredWidth.priority = UILayoutPriorityDefaultHigh;
    NSLayoutConstraint *fillsViewport = [self.topNav.widthAnchor constraintEqualToAnchor:navigationScroll.frameLayoutGuide.widthAnchor];
    fillsViewport.priority = UILayoutPriorityDefaultHigh;
    NSLayoutConstraint *headerTop = [self.navigationGroup.topAnchor constraintEqualToAnchor:self.view.topAnchor constant:52*.8];
    NSLayoutConstraint *headerRight = [self.navigationGroup.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor constant:-20];
    NSLayoutConstraint *headerHeight = [self.navigationGroup.heightAnchor constraintEqualToConstant:60];
    NSLayoutConstraint *themeGap = [theme.leadingAnchor constraintEqualToAnchor:navigationScroll.trailingAnchor constant:16];
    NSLayoutConstraint *themeWidth = [theme.widthAnchor constraintEqualToConstant:52];
    NSLayoutConstraint *themeHeight = [theme.heightAnchor constraintEqualToConstant:52];
    NSLayoutConstraint *profileGap = [self.profileSlot.leadingAnchor constraintEqualToAnchor:theme.trailingAnchor constant:16];
    self.headerMetrics=@{@"top":headerTop,@"right":headerRight,@"height":headerHeight,@"bar":preferredWidth,@"themeGap":themeGap,@"themeW":themeWidth,@"themeH":themeHeight,@"profileGap":profileGap};
    [NSLayoutConstraint activateConstraints:@[
        headerTop,
        headerRight,
        [self.navigationGroup.leadingAnchor constraintGreaterThanOrEqualToAnchor:safe.leadingAnchor constant:8],
        headerHeight,
        [navigationScroll.leadingAnchor constraintEqualToAnchor:self.navigationGroup.leadingAnchor],
        [navigationScroll.topAnchor constraintEqualToAnchor:self.navigationGroup.topAnchor],
        [navigationScroll.bottomAnchor constraintEqualToAnchor:self.navigationGroup.bottomAnchor], preferredWidth,
        [self.topNav.leadingAnchor constraintEqualToAnchor:navigationScroll.contentLayoutGuide.leadingAnchor],
        [self.topNav.trailingAnchor constraintEqualToAnchor:navigationScroll.contentLayoutGuide.trailingAnchor],
        [self.topNav.topAnchor constraintEqualToAnchor:navigationScroll.contentLayoutGuide.topAnchor],
        [self.topNav.bottomAnchor constraintEqualToAnchor:navigationScroll.contentLayoutGuide.bottomAnchor],
        [self.topNav.heightAnchor constraintEqualToAnchor:navigationScroll.frameLayoutGuide.heightAnchor], fillsViewport,
        themeGap,
        [theme.centerYAnchor constraintEqualToAnchor:self.navigationGroup.centerYAnchor],
        themeWidth, themeHeight,
        profileGap,
        [self.profileSlot.trailingAnchor constraintEqualToAnchor:self.navigationGroup.trailingAnchor],
        [self.profileSlot.centerYAnchor constraintEqualToAnchor:self.navigationGroup.centerYAnchor constant:-8],
        self.profileSlotWidth, self.profileSlotHeight,
    ]];
    UIImageView *logo = [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"AppLogo-Current"] ?: [UIImage imageNamed:@"AppIcon-Light60x60"]];
    self.brandLogo=logo;
    logo.contentMode = UIViewContentModeScaleAspectFit;
    [logo.widthAnchor constraintEqualToConstant:40].active = YES;
    [logo.heightAnchor constraintEqualToConstant:40].active = YES;
    UILabel *wordmark = [[UILabel alloc] init]; self.brandLabel=wordmark;
    wordmark.attributedText = [[NSAttributedString alloc] initWithString:@"METALLIC" attributes:@{NSKernAttributeName:@3, NSFontAttributeName:[UIFont systemFontOfSize:18 weight:UIFontWeightSemibold], NSForegroundColorAttributeName:AmeUIPrimaryTextColor()}];
    UIStackView *brand = [[UIStackView alloc] initWithArrangedSubviews:@[logo,wordmark]];
    brand.spacing = 12; brand.alignment = UIStackViewAlignmentCenter; brand.translatesAutoresizingMaskIntoConstraints = NO;
    self.brandView = brand; [self.view addSubview:brand];
    [NSLayoutConstraint activateConstraints:@[[brand.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor constant:24], [brand.centerYAnchor constraintEqualToAnchor:self.navigationGroup.centerYAnchor]]];
    if (self.navigationProfilePanel) [self installNavigationProfilePanel:self.navigationProfilePanel];

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
        [self.floatingDoneButton.heightAnchor constraintGreaterThanOrEqualToConstant:44],
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
    self.topNav.selectedIndex = self.selectedIndex;
    self.aiAction.state = self.selectedIndex == AMELauncherTabAI ? UIMenuElementStateOn : UIMenuElementStateOff;
    self.topNav.onSelect = ^(AMEPrimaryDestination destination) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        if (destination == AMEPrimaryDestinationHome) { [strongSelf ameResetToHome]; return; }
        if (strongSelf.presentedViewController) return;
        if (destination == AMEPrimaryDestinationAppearance) {
            [strongSelf ameOpenAppearance];
            return;
        }
        NSInteger tab = AMETabForPrimaryDestination(destination);
        if (tab != NSNotFound && tab < (NSInteger)strongSelf.viewControllers.count) {
            if (destination == AMEPrimaryDestinationSettings) [(UINavigationController *)strongSelf.viewControllers[tab] popToRootViewControllerAnimated:NO];
            strongSelf.selectedIndex = tab;
        }
    };
}

// The Home controller continues owning account callbacks, avatar updates and status chips.
// Only the panel's presentation parent changes; no controller containment is changed.
- (void)installNavigationProfilePanel:(HomeActionPanelView *)panel {
    if (!panel || (panel == self.navigationProfilePanel && panel.superview == self.view)) return;
    self.navigationProfilePanel = panel;
    if (!self.profileSlot) return; // Home may load while UIKit is constructing the root.
    [panel setExpanded:NO animated:NO];
    CGSize collapsed = [panel systemLayoutSizeFittingSize:UILayoutFittingCompressedSize];
    self.profileSlotWidth.constant = MAX(44, collapsed.width);
    self.profileSlotHeight.constant = MAX(44, collapsed.height);
    [panel removeFromSuperview]; // Releases the old Home-only positioning constraints.
    [self.view addSubview:panel];
    NSLayoutConstraint *top = [panel.topAnchor constraintEqualToAnchor:self.profileSlot.topAnchor constant:8];
    panel.topOffsetConstraint = top;
    [NSLayoutConstraint activateConstraints:@[
        top, [panel.trailingAnchor constraintEqualToAnchor:self.profileSlot.trailingAnchor]
    ]];
    [panel constrainExpandedPresentationToSafeArea:self.view.safeAreaLayoutGuide];
    __weak typeof(self) weakSelf = self;
    panel.onWillExpand = ^{
        // Existing panel controls present through Home; keep that owner visible, even from another tab.
        AmeRootTabController *root = weakSelf;
        UINavigationController *home = [root.viewControllers.firstObject isKindOfClass:UINavigationController.class]
            ? (UINavigationController *)root.viewControllers.firstObject : nil;
        if (root && !root.presentedViewController &&
            (root.selectedIndex != AMELauncherTabHome || home.viewControllers.count > 1)) [root ameResetToHome];
    };
    // Keep the existing gesture and VoiceOver routes, and expose the same menu to ordinary touch.
    self.profileToolsButton = [AmePinkGlassButton buttonWithType:UIButtonTypeSystem];
    self.profileToolsButton.translatesAutoresizingMaskIntoConstraints = NO;
    ((AmePinkGlassButton *)self.profileToolsButton).ameRole = AmeGlassButtonRoleSubtle;
    [self.profileToolsButton setTitle:@"Tools" forState:UIControlStateNormal];
    self.profileToolsButton.titleLabel.font = AmeUIFont(AmeUIFontRoleStatus);
    self.profileToolsButton.titleLabel.adjustsFontSizeToFitWidth = YES;
    self.profileToolsButton.accessibilityLabel = @"Tools, including AI";
    self.profileToolsButton.showsMenuAsPrimaryAction = YES;
    self.profileToolsButton.menu = self.toolsMenu; // Same UIAction and native tab 2, no duplicate dispatch.
    [self.profileToolsButton.widthAnchor constraintEqualToConstant:56].active = YES;
    [self.profileToolsButton.heightAnchor constraintEqualToConstant:44].active = YES;
    [panel.chipRow addArrangedSubview:self.profileToolsButton];
    [panel.avatarView addInteraction:[[UIContextMenuInteraction alloc] initWithDelegate:self]];
    panel.avatarView.accessibilityHint = @"Opens the profile panel. Tools are available in the actions menu.";
    panel.avatarView.accessibilityCustomActions = @[
        [[UIAccessibilityCustomAction alloc] initWithName:@"Tools: AI" actionHandler:^BOOL(UIAccessibilityCustomAction *action) {
            return [weakSelf ameOpenAI];
        }]
    ];
}

- (LauncherNewsViewController *)ameHomePresentationIn:(UIViewController *)owner {
    if([owner isKindOfClass:LauncherNewsViewController.class])return (LauncherNewsViewController *)owner;
    for(UIViewController *child in owner.childViewControllers) { LauncherNewsViewController *home=[self ameHomePresentationIn:child]; if(home)return home; }
    return nil;
}
- (void)ameForwardHomeOverflow:(NSInteger)action {
    if(self.presentedViewController)return;
    __weak typeof(self) weakSelf=self;
    void (^open)(void)=^{
        AmeRootTabController *root=weakSelf; if(!root)return;
        UINavigationController *nav=(UINavigationController *)root.viewControllers[AMELauncherTabHome];
        [nav popToRootViewControllerAnimated:NO]; root.selectedIndex=AMELauncherTabHome; [nav.topViewController loadViewIfNeeded];
        dispatch_async(dispatch_get_main_queue(), ^{
            if(root.selectedIndex==AMELauncherTabHome) [[root ameHomePresentationIn:nav] performExistingHomeAction:action];
        });
    };
    if(self.transitionCoordinator.isAnimated) [self.transitionCoordinator animateAlongsideTransition:nil completion:^(id<UIViewControllerTransitionCoordinatorContext> context) { open(); }]; else open();
}

- (void)ameApplyReferenceThemeIndex:(NSInteger)index {
    UINavigationController *nav=(UINavigationController *)self.viewControllers[AMELauncherTabSettings];
    MetallicSettingsContainerViewController *settings=(MetallicSettingsContainerViewController *)nav.viewControllers.firstObject;
    [settings loadViewIfNeeded];
    LauncherPreferencesViewController *prefs=settings.preferences;
    NSDictionary *item=nil;
    for(NSDictionary *row in prefs.prefContents.firstObject) if([row[@"key"] isEqual:@"ui_theme"]) {item=row;break;}
    NSArray *keys=@[@"auto",@"light",@"dark"];
    if(!item || index<0 || index>=(NSInteger)keys.count)return;
    BOOL (^enabled)(void)=item[@"enableCondition"]; if(enabled&&!enabled())return;
    prefs.setPreference(@"general",@"ui_theme",keys[index]);
    void (^action)(NSString *)=item[@"action"]; if(action)action(keys[index]);
}

- (void)ameOpenAppearance {
    if (self.presentedViewController) return;
    UINavigationController *nav = (UINavigationController *)self.viewControllers[AMELauncherTabSettings];
    if (![nav.topViewController isKindOfClass:MetallicAppearanceContainerViewController.class]) {
        MetallicSettingsContainerViewController *settings = (MetallicSettingsContainerViewController *)nav.viewControllers.firstObject;
        [settings loadViewIfNeeded];
        BackgroundSettingsViewController *appearance = [[BackgroundSettingsViewController alloc] initWithStyle:UITableViewStyleInsetGrouped];
        appearance.launcherPresentation = YES;
        __weak typeof(self) themeOwner=self;
        appearance.themeSelection=^(NSInteger index) { [themeOwner ameApplyReferenceThemeIndex:index]; };
        NSString *value = settings.preferences.getPreference(@"general", @"ui_theme");
        appearance.themeIndex = [@[@"auto", @"light", @"dark"] indexOfObject:value];
        MetallicAppearanceContainerViewController *page = [[MetallicAppearanceContainerViewController alloc] init];
        page.appearance = appearance;
        [nav pushViewController:page animated:NO];
    }
    self.selectedIndex = AMELauncherTabSettings;
    self.topNav.appearanceActive = YES; self.topNav.selectedIndex = self.selectedIndex;
}

- (BOOL)ameOpenAI {
    if (self.presentedViewController) return NO;
    [self.navigationProfilePanel setExpanded:NO animated:!UIAccessibilityIsReduceMotionEnabled()];
    self.selectedIndex = AMELauncherTabAI;
    return YES;
}

- (UIContextMenuConfiguration *)contextMenuInteraction:(UIContextMenuInteraction *)interaction
                      configurationForMenuAtLocation:(CGPoint)location {
    return [UIContextMenuConfiguration configurationWithIdentifier:nil previewProvider:nil
        actionProvider:^UIMenu *(NSArray<UIMenuElement *> *suggestedActions) {
            return self.toolsMenu;
        }];
}

- (void)ameSuppressSystemTabBar {
    if (@available(iOS 18.0, *)) {
        self.mode = UITabBarControllerModeTabBar;
        [self setTabBarHidden:YES animated:NO];
    } else {
        self.tabBar.hidden = YES;
    }
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self ameSuppressSystemTabBar];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    [self ameSuppressSystemTabBar];
}


- (CGFloat)launcherHeaderReservation {
    CGFloat width=self.view.bounds.size.width,scale=width>=900 ? width/1536.0 : .72;
    return MAX(76,MAX(self.view.safeAreaInsets.top+8,52*scale)+MAX(MAX(48,68*scale),self.topNav.intrinsicContentSize.height)-self.view.safeAreaInsets.top+8);
}
- (void)ameLayoutReferenceHeader {
    CGFloat width=self.view.bounds.size.width,scale=width>=900 ? width/1536.0 : .72;
    self.topNav.referenceScale=scale;
    NSDictionary *values=@{@"top":@(MAX(self.view.safeAreaInsets.top+8,52*scale)),@"right":@(-38*scale),@"height":@(MAX(MAX(48,68*scale),self.topNav.intrinsicContentSize.height)),@"bar":@(938*scale),@"themeGap":@(16*scale),@"themeW":@(MAX(44,58*scale)),@"themeH":@(MAX(44,58*scale)),@"profileGap":@(24*scale)};
    for (NSString *key in values) { NSLayoutConstraint *c=self.headerMetrics[key]; CGFloat value=[values[key] doubleValue]; if (fabs(c.constant-value)>.1)c.constant=value; }
    self.profileSlotWidth.constant=51*scale;
    for(NSLayoutConstraint *c in self.view.constraints) if(c.firstItem==self.brandView && c.firstAttribute==NSLayoutAttributeLeading) c.constant=38*scale;
    ((UIStackView *)self.brandView).spacing=12*scale;
    for(NSLayoutConstraint *c in self.brandLogo.constraints) if(c.firstAttribute==NSLayoutAttributeWidth || c.firstAttribute==NSLayoutAttributeHeight)c.constant=46*scale;

    NSAttributedString *brand=[[NSAttributedString alloc] initWithString:@"METALLIC" attributes:@{NSKernAttributeName:@(4*scale),NSFontAttributeName:[UIFont systemFontOfSize:22*scale weight:UIFontWeightSemibold],NSForegroundColorAttributeName:AmeUIPrimaryTextColor()}];
    if (![self.brandLabel.attributedText isEqualToAttributedString:brand]) self.brandLabel.attributedText=brand;
    for (NSUInteger i=1;i<self.viewControllers.count;i++) {
        UIViewController *page=self.viewControllers[i]; UIEdgeInsets inset=page.additionalSafeAreaInsets; CGFloat top=[self launcherHeaderReservation];
        if (fabs(inset.top-top)>.1) { inset.top=top; page.additionalSafeAreaInsets=inset; }
    }
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    self.brandView.hidden = CGRectGetMaxX(self.brandView.frame) + 16 > CGRectGetMinX(self.navigationGroup.frame);
    [self ameLayoutReferenceHeader];
    [self.view bringSubviewToFront:self.brandView];
    [self.view bringSubviewToFront:self.navigationGroup];
    if (self.navigationProfilePanel.superview == self.view) [self.view bringSubviewToFront:self.navigationProfilePanel];
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
        [UIApplication.sharedApplication sendAction:bar.action to:bar.target from:bar forEvent:nil];
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
    NSLog(@"[MetallicNavigation] didShow %@ in %@", NSStringFromClass(viewController.class), NSStringFromClass(navigationController.class));
    if (navigationController == self.selectedViewController) {
        self.topNav.appearanceActive = [viewController isKindOfClass:MetallicAppearanceContainerViewController.class];
        self.topNav.selectedIndex = self.selectedIndex;
    }
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
    if (selectedIndex >= self.viewControllers.count) return;
    id<UIViewControllerTransitionCoordinator> coordinator = self.transitionCoordinator;
    if (coordinator && coordinator.isAnimated && self.selectedIndex != selectedIndex) {
        self.pendingSelection = selectedIndex;
        if (!self.waitingForTransition) {
            self.waitingForTransition = YES;
            __weak typeof(self) weakSelf = self;
            BOOL registered=[coordinator animateAlongsideTransition:nil completion:^(id<UIViewControllerTransitionCoordinatorContext> context) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    AmeRootTabController *root = weakSelf;
                    root.waitingForTransition = NO;
                    NSUInteger next = root.pendingSelection; root.pendingSelection = NSNotFound;
                    if (next != NSNotFound) root.selectedIndex = next;
                });
            }];
            if(registered)return;
            self.waitingForTransition=NO; self.pendingSelection=NSNotFound;
        } else return;
    }
    NSLog(@"[MetallicNavigation] selection %lu -> %lu", (unsigned long)self.selectedIndex, (unsigned long)selectedIndex);
    [super setSelectedIndex:selectedIndex];
    self.topNav.appearanceActive = selectedIndex == AMELauncherTabSettings && [[(UINavigationController *)self.selectedViewController topViewController] isKindOfClass:MetallicAppearanceContainerViewController.class];
    self.topNav.selectedIndex = selectedIndex;
    // Home's editor disables its local chrome. That must not lock the shared profile on other tabs.
    if (selectedIndex != AMELauncherTabHome) self.navigationProfilePanel.userInteractionEnabled = YES;
    self.aiAction.state = selectedIndex == AMELauncherTabAI ? UIMenuElementStateOn : UIMenuElementStateOff;
    [self ameUpdateFloatingDoneButton];
}

#pragma mark - ★ [GAME-LANDSCAPE] Lock landscape during launch/gameplay (root-controller layer)

// This is the app's window.rootViewController (installed by SceneDelegate); all launcher pages live below it.
// Window-scene orientation = intersection of the root-controller chain ⇒ narrowing here is the
// **decisive** layer for locking landscape during launch.
// Keep the existing autorotation guard; unlocked launcher masks support portrait and landscape.
- (BOOL)shouldAutorotate {
    if (AmeGameLandscapeLockActive()) return NO;   // ★ [GAME-LANDSCAPE]
    return [super shouldAutorotate];
}

- (UIInterfaceOrientationMask)supportedInterfaceOrientations {
    if (AmeGameLandscapeLockActive()) return UIInterfaceOrientationMaskLandscape;
    // The existing bridge can request a landscape game transition on iOS 16+.
    // Keep older systems on the original policy; do not change their launch/rotation bridge.
    if (@available(iOS 16.0, *)) {
        return UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPad
            ? UIInterfaceOrientationMaskAll : UIInterfaceOrientationMaskAllButUpsideDown;
    }
    return UIInterfaceOrientationMaskLandscape;
}

#pragma mark - UITabBarControllerDelegate

- (void)tabBarController:(UITabBarController *)tabBarController
 didSelectViewController:(UIViewController *)viewController {
    NSInteger idx = [tabBarController.viewControllers indexOfObject:viewController];
    self.topNav.selectedIndex = self.selectedIndex;
    if (idx == NSNotFound) return;
    NSLog(@"[ROOTTAB] tap index=%ld", (long)idx);
    // Broadcast to legacy code that cares about navigation (LauncherMenuViewController, etc.);
    // UIKit handles switching the page itself.
    [[NSNotificationCenter defaultCenter] postNotificationName:AmeTabTappedNotification
                                                       object:nil
                                                     userInfo:@{@"index": @(idx)}];
}

@end
