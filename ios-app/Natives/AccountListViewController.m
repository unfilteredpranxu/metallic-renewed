#import <AuthenticationServices/AuthenticationServices.h>

#import "authenticator/BaseAuthenticator.h"
#import "authenticator/ThirdPartyAuthenticator.h"
#import "AccountListViewController.h"
#import "AccountLoginViewController.h"
#import "ThirdPartyLoginViewController.h"
#import "AFNetworking.h"
#import "LauncherPreferences.h"
#import "UIImageView+AFNetworking.h"
#import "BackgroundManager.h"
// ★ [ACCT-AUDIT] Delete the account's custom avatar file when removing the account (Documents/avatars/<accountId>.png).
#import "AvatarManager.h"
#import "ios_uikit_bridge.h"
#import "utils.h"
// ★ [EDIT3] Avatar-settings entry point: reuse the existing notification action
// (LauncherRightPanelViewController norightPostAction:).
#import "LauncherRightPanelViewController.h"

@interface AccountListViewController()<ASWebAuthenticationPresentationContextProviding>

@property(nonatomic, strong) NSMutableArray *accountList;
@property(nonatomic) ASWebAuthenticationSession *authVC;
// ★ [ADDBTN-INSET] Keep the bottom constraint for the floating "Add Account" button separately so
// layout can adjust it according to the actual overlap.
@property(nonatomic, strong) NSLayoutConstraint *ameAddAccountBottomConstraint;
// ★ [ACCT-DUP] Sign-in/account-selection re-entry guard: allow only one sign-in flow at a time.
@property(nonatomic) BOOL ameLoginInFlight;
// ★ [ACCT-DUP] Sign-in "generation": increment for each new sign-in; discard callbacks carrying an
//   old generation as stale, preventing a late callback from a previous sign-in from changing the
//   current UI (generation counter for callback-side deduplication).
@property(nonatomic) NSUInteger ameAuthGeneration;
// ★ [ACCT-DUP] "Add Account" entry re-entry guard: prevent rapid taps from pushing two sign-in method pages.
@property(nonatomic) BOOL ameAddAccountInFlight;
// ★ [ACCT-DONE] In-flight lock "token": increment every time it is set/unlocked; the watchdog's
//   delayed block unlocks only if the token is unchanged and a sign-in is still in flight, preventing
//   it from accidentally unlocking a later sign-in.
@property(nonatomic) NSUInteger ameLoginInFlightToken;

@end

@implementation AccountListViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    // Adapt to the custom launcher background: make this view controller transparent so the global wallpaper shows through.
    [[BackgroundManager sharedManager] makeViewControllerTransparent:self];

    self.title = localize(@"login.title", @"Account Management");
    self.view.backgroundColor = [UIColor clearColor];

    if (self.accountList == nil) {
        self.accountList = [NSMutableArray array];
    } else {
        [self.accountList removeAllObjects];
    }

    // List accounts (★ [ACCT-DUP] merge existing duplicates before loading, then filter corrupt files).
    [self ameLoadAccountListFromDisk];

    // Inspired by FCL: card-style account list; remove default separators because rounded cards provide visual separation.
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    self.tableView.backgroundColor = [UIColor clearColor];
    self.tableView.estimatedRowHeight = 88;
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    // Bottom inset prevents the last cell from being covered by the floating button.
    self.tableView.contentInset = UIEdgeInsetsMake(8, 0, 80, 0);
    self.tableView.scrollIndicatorInsets = self.tableView.contentInset;
    // Register the card cell.
    [self.tableView registerClass:UITableViewCell.class forCellReuseIdentifier:@"accountCardCell"];

    // Add the floating "Add Account" button at the bottom (FCL style).
    [self setupAddAccountButton];

    // Apply the background.
    [[BackgroundManager sharedManager] applyBackgroundToView:self.view];

    // Listen for background UI-effect changes and reapply transparency when the user switches
    // background effects (translucent/frosted glass).
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(reapplyBackgroundEffect)
                                                 name:@"BackgroundUIEffectChanged"
                                               object:nil];
}

/// Reapply transparency when the background effect changes (triggered by the BackgroundUIEffectChanged notification).
- (void)reapplyBackgroundEffect {
    [[BackgroundManager sharedManager] makeViewControllerTransparent:self];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

#pragma mark - ★ [ACCOUNTBACK] Back button (fix for account flow that could be entered but not exited)

/// ★ [ACCOUNTBACK] Ensure this page has a **working way back** every time it appears.
///
/// Root cause (verified; see _EDITMODE_REPORT.md ①):
///   showAccountManager(LauncherRootViewController.m:848 / LauncherCardLayoutViewController.m:989)
///   This page is placed in the middle content area as the root of a **new UINavigationController**
///   (initWithRootViewController:). The root view controller has no parent to pop to ⇒ UIKit does not
///   provide a back button, leaving a visible but empty navigation bar ⇒ users can enter from Home
///   but cannot leave.
///
/// Fix (adds only an exit; changes no account business logic):
///   ① If this page is the navigation-stack root and has no system back button, inject a "Back"
///      left button. Tapping it sends the existing ShowHomePage notification — RootVC (:602) /
///      CardLayoutVC (:752) already listen for it and return to Home, so this does not depend on
///      the specific host class or duplicate any navigation code.
///   ② Also show the navigation bar for the nav containing this page (navigationBarHidden = NO).
///      ★ Deliberately do not restore it in viewWillDisappear: this nav is a private container
///      temporarily created by showAccountManager for this account flow only. Hiding it on
///      disappearance would remove the system back button from the sign-in page
///      (AccountLoginViewController) pushed immediately afterward — the exact bug this fixes.
///      This affects only that private nav and no other pages.
///   ③ Trigger in viewWillAppear, when the navigationController relationship is established.
- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    // ★ [ACCT-DUP] Clear the "Add Account" re-entry lock when returning from the sign-in method
    // page (the lock is set before pushing it).
    self.ameAddAccountInFlight = NO;
    // ★ [ACCT-DONE] Unconditionally clear the in-flight sign-in lock every time this page appears:
    //   even if a lost callback/network hang left the lock set (disabling the table/button), returning
    //   here restores interaction. This is idempotent: the page remains visible during sign-in, so
    //   viewWillAppear does not fire again and cannot interrupt an active sign-in.
    [self ameSetLoginInFlight:NO];
    [self ameAccountEnsureBackItemIfNeeded];
}

#pragma mark - ★ [ADDBTN-INSET] Keep the bottom "Add Account" button above the tab bar

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    [self ame_updateAddAccountButtonInset];
}

- (void)viewSafeAreaInsetsDidChange {
    [super viewSafeAreaInsetsDidChange];
    [self ame_updateAddAccountButtonInset];
}

/// Keep the button above the tab bar: inset = max(this view's bottom safe area, the actual overlap
/// between the tab bar and this page's bottom).
///   This works with/without a tab bar, visible/hidden bars, either orientation, and translucent/
///   opaque bars; if no tab bar is found, fall back to safeAreaInsets.bottom (matching the system).
- (void)ame_updateAddAccountButtonInset {
    if (!self.ameAddAccountBottomConstraint) { return; }

    CGFloat inset = self.view.safeAreaInsets.bottom;

    UITabBarController *tbc = self.tabBarController;
    if (!tbc) {
        // This page is hosted in Home's "content container", not necessarily a direct child of the
        // tabBarController ⇒ look one level higher.
        UIViewController *root = self.view.window.rootViewController;
        if ([root isKindOfClass:[UITabBarController class]]) {
            tbc = (UITabBarController *)root;
        }
    }
    UIView *bar = tbc.tabBar;
    if (tbc && bar && !bar.hidden && bar.window) {
        CGRect barRect = [self.view convertRect:bar.bounds fromView:bar];
        CGFloat overlap = CGRectGetMaxY(self.view.bounds) - CGRectGetMinY(barRect);
        // Use this only if the view is actually overlapped and the value is reasonable (guard against anomalies).
        if (overlap > 0 && overlap < CGRectGetHeight(self.view.bounds) * 0.5) {
            inset = MAX(inset, overlap);
        }
    }
    self.ameAddAccountBottomConstraint.constant = -(inset + 16.0);
}

/// ★ [ACCOUNTBACK] See the viewWillAppear comment.
- (void)ameAccountEnsureBackItemIfNeeded {
    UINavigationController *nav = self.navigationController;
    if (!nav) return;                                       // Not in a navigation stack (no host nav) ⇒ nothing to inject.

    // ① Show the navigation bar: with nothing to pop from a root page, the system draws no back
    // button, so an empty navigation bar provides no way out.
    if (nav.navigationBarHidden) {
        [nav setNavigationBarHidden:NO animated:NO];
    }
    // Semantic color: adapts to light/dark appearance (same semantic color as the Home top bar);
    // do not hard-code black or white.
    nav.navigationBar.tintColor = [UIColor labelColor];
    // ★ [ACCT-DONE] Keep the navigation exit usable: whenever this page appears, restore interaction
    //   for the navigation bar and injected left button.
    //   "Done/Back" is the only exit from the account flow; never disable the navigation chrome because
    //   of an in-flight lock/spinner (user report: "Done can't be tapped ⇒ can get in but can't get out").
    //   The business lock should disable only controls that trigger sign-in.
    nav.navigationBar.userInteractionEnabled = YES;
    if (self.navigationItem.leftBarButtonItem) self.navigationItem.leftBarButtonItem.enabled = YES;

    // ★ [EDIT3] New entry point for the custom-avatar menu: this is the "Account Management" page
    //   opened by tapping the avatar.
    //   The custom-avatar menu (Import / Clear), previously shown by long-pressing the Home welcome-card
    //   avatar, lost that gesture to "long-press to enter edit mode" (see LauncherNewsViewController.m
    //   ★[EDIT3]). To preserve the feature, add a clearly visible "Custom Avatar" right button here.
    //   Tapping it only posts the existing action name avatarMenu ⇒ the original
    //   LauncherRightPanelViewController showAvatarMenu: displays the menu. Menu items/callbacks/
    //   account checks/crop-and-save flow remain unchanged; this page does not duplicate avatar logic.
    //   Idempotent: do not inject it twice. The button is attached to this VC's navigationItem, so it
    //   is visible only on this page; the pushed sign-in page uses its own navigationItem.
    if (!self.navigationItem.rightBarButtonItem) {
        UIBarButtonItem *avatarItem = [[UIBarButtonItem alloc] initWithTitle:localize(@"i18n_str_416", @"Custom Avatar")
                                                                      style:UIBarButtonItemStylePlain
                                                                     target:self
                                                                     action:@selector(ameAccountAvatarSettingsTapped)];
        avatarItem.tintColor = [UIColor labelColor];
        avatarItem.accessibilityLabel = localize(@"i18n_str_416", @"Custom Avatar");
        self.navigationItem.rightBarButtonItem = avatarItem;
    }

    // ② Inject only when there is no previous item in the stack (no system back button); preserve
    // the system back button unchanged on pages that were pushed.
    if (nav.viewControllers.count > 1) return;
    if (self.navigationItem.leftBarButtonItem) return;      // Idempotent: do not inject twice.

    UIBarButtonItem *backItem = [[UIBarButtonItem alloc] initWithTitle:localize(@"resman.common.done", nil)
                                                                style:UIBarButtonItemStylePlain
                                                               target:self
                                                               action:@selector(ameAccountBackToHomeTapped)];
    backItem.tintColor = [UIColor labelColor];
    backItem.accessibilityLabel = localize(@"resman.common.done", nil);
    self.navigationItem.leftBarButtonItem = backItem;

    // ③ In landscape, the Dynamic Island is on the side (≈59pt); the system navigation bar places
    // the left button within safeAreaLayoutGuide, so the Island cannot cover it.
}

/// ★ [ACCOUNTBACK] "Back" = return Home. Send only the existing notification; do not touch any
/// account behavior (sign-in/sign-out/avatar/username).
- (void)ameAccountBackToHomeTapped {
    [[NSNotificationCenter defaultCenter] postNotificationName:@"ShowHomePage" object:nil];
}

/// ★ [EDIT3] "Custom Avatar" = display the custom-avatar menu (Import / Clear).
///   Forward only the existing action name avatarMenu ⇒ the original
///   LauncherRightPanelViewController showAvatarMenu: implementation. Menu options, callbacks,
///   account checks, and crop/save flow are unchanged; this page does not duplicate avatar logic.
- (void)ameAccountAvatarSettingsTapped {
    [LauncherRightPanelViewController norightPostAction:@"avatarMenu"];
}

- (void)setupAddAccountButton {
    UIButton *addBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    addBtn.translatesAutoresizingMaskIntoConstraints = NO;
    [addBtn setTitle:localize(@"login.option.add", @"Add Account") forState:UIControlStateNormal];
    addBtn.titleLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightSemibold];
    [addBtn setImage:[UIImage systemImageNamed:@"plus"] forState:UIControlStateNormal];
    addBtn.tintColor = [UIColor whiteColor];
    addBtn.backgroundColor = accentColor();
    addBtn.layer.cornerRadius = 24;
    addBtn.layer.cornerCurve = kCACornerCurveContinuous;
    addBtn.titleEdgeInsets = UIEdgeInsetsMake(0, 6, 0, 0);
    addBtn.imageEdgeInsets = UIEdgeInsetsMake(0, -6, 0, 0);
    // Shadow enhances the floating appearance (FCL style).
    addBtn.layer.shadowColor = [UIColor blackColor].CGColor;
    addBtn.layer.shadowOpacity = 0.35;
    addBtn.layer.shadowOffset = CGSizeMake(0, 4);
    addBtn.layer.shadowRadius = 10;
    [addBtn addTarget:self action:@selector(addAccountTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:addBtn];
    // Use frameLayoutGuide (the visible-area anchor for UITableView), not safeAreaLayoutGuide, so
    // the button floats with the bottom of the visible area instead of scrolling with cells.
    // ★ [ADDBTN-INSET] Keep the bottom constraint separately: the tab bar (UITabBarController's
    //   tabBar) floats translucently, and this page's content extends beneath it. A hard-coded -16
    //   lets the bar cover the button (confirmed on both old and new systems).
    //   Instead, let ame_updateAddAccountButtonInset set the constant from the actual overlap.
    self.ameAddAccountBottomConstraint =
        [addBtn.bottomAnchor constraintEqualToAnchor:self.tableView.frameLayoutGuide.bottomAnchor constant:-16];
    [NSLayoutConstraint activateConstraints:@[
        self.ameAddAccountBottomConstraint,
        [addBtn.centerXAnchor constraintEqualToAnchor:self.tableView.frameLayoutGuide.centerXAnchor],
        [addBtn.heightAnchor constraintEqualToConstant:48],
        [addBtn.widthAnchor constraintGreaterThanOrEqualToConstant:160]
    ]];
    self.addAccountButton = addBtn;
    [self ame_updateAddAccountButtonInset];
}

- (void)addAccountTapped {
    [self actionAddAccount:nil];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    // FCL style: show only existing accounts in the list; add accounts using the floating button at the bottom.
    return self.accountList.count;
}

/// Set the account-type badge text and color (following FCL: Microsoft=blue, third party=orange,
/// local=gray, Demo=purple).
- (void)applyAccountTypeBadgeForAccount:(NSDictionary *)accountData
                              badgeLabel:(UILabel *)badgeLabel {
    NSString *username = accountData[@"username"];
    if ([username hasPrefix:@"Demo."]) {
        badgeLabel.text = localize(@"login.option.demo", @"Demo");
        badgeLabel.backgroundColor = [UIColor colorWithRed:0.55 green:0.35 blue:0.85 alpha:1.0];
    } else if (accountData[@"clientToken"] != nil) {
        badgeLabel.text = localize(@"login.option.3rdparty", @"Third Party");
        badgeLabel.backgroundColor = [UIColor colorWithRed:0.92 green:0.55 blue:0.18 alpha:1.0];
    } else if (accountData[@"xboxGamertag"] == nil) {
        badgeLabel.text = localize(@"login.option.local", @"Local");
        badgeLabel.backgroundColor = [UIColor colorWithWhite:0.45 alpha:1.0];
    } else {
        // Microsoft account.
        badgeLabel.text = @"Microsoft";
        badgeLabel.backgroundColor = [UIColor colorWithRed:0.20 green:0.55 blue:0.95 alpha:1.0];
    }
}

/// accountId of the currently selected account (used to show selection state on the card).
/// Use accountId rather than username so accounts with the same name remain distinguishable.
- (NSString *)currentSelectedAccountId {
    // BaseAuthenticator.current stores authData for the currently active account.
    BaseAuthenticator *currentAuth = BaseAuthenticator.current;
    return currentAuth.authData[@"accountId"];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    // FCL-style card cell: rounded corners + frosted glass + avatar on the left + username/subtitle
    // in the middle + type badge/selection checkmark on the right.
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"accountCardCell" forIndexPath:indexPath];

    // Reset the cell: remove contentView subviews left over from its previous reuse.
    for (UIView *sub in cell.contentView.subviews) {
        [sub removeFromSuperview];
    }
    cell.accessoryType = UITableViewCellAccessoryNone;
    cell.accessoryView = nil;
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    cell.backgroundColor = [UIColor clearColor];
    cell.contentView.backgroundColor = [UIColor clearColor];

    NSDictionary *accountData = self.accountList[indexPath.row];
    NSString *displayName = accountData[@"username"];
    NSString *subtitle = @"";

    // Subtitle: Demo accounts show "Demo Account", third-party accounts show their server name,
    // Microsoft accounts show the Xbox gamertag, and local accounts show "Offline Mode".
    if ([displayName hasPrefix:@"Demo."]) {
        displayName = [displayName substringFromIndex:5];
        subtitle = localize(@"login.option.demo", @"Demo Account");
    } else if (accountData[@"clientToken"] != nil) {
        // Third-party account: show its authserver address.
        subtitle = accountData[@"authserver"] ?: localize(@"login.option.3rdparty", @"Third-Party Account");
    } else if (accountData[@"xboxGamertag"] == nil) {
        subtitle = localize(@"login.option.local", @"Offline Mode");
    } else {
        subtitle = accountData[@"xboxGamertag"] ?: @"Microsoft";
    }

    // Card container (rounded corners + translucent background + frosted glass).
    UIView *cardView = [[UIView alloc] init];
    cardView.translatesAutoresizingMaskIntoConstraints = NO;
    cardView.backgroundColor = [[UIColor whiteColor] colorWithAlphaComponent:0.10];
    cardView.layer.cornerRadius = 16;
    cardView.layer.cornerCurve = kCACornerCurveContinuous;
    cardView.layer.borderWidth = 0.5;
    cardView.layer.borderColor = [[UIColor whiteColor] colorWithAlphaComponent:0.12].CGColor;
    cardView.layer.shadowColor = [UIColor blackColor].CGColor;
    cardView.layer.shadowOffset = CGSizeMake(0, 4);
    cardView.layer.shadowOpacity = 0.12;
    cardView.layer.shadowRadius = 10;
    [cell.contentView addSubview:cardView];
    [[BackgroundManager sharedManager] applyEffectToView:cardView];

    // Avatar on the left.
    UIImageView *avatarView = [[UIImageView alloc] init];
    avatarView.translatesAutoresizingMaskIntoConstraints = NO;
    avatarView.contentMode = UIViewContentModeScaleAspectFill;
    avatarView.clipsToBounds = YES;
    avatarView.layer.cornerRadius = 24;
    avatarView.layer.cornerCurve = kCACornerCurveContinuous;
    avatarView.backgroundColor = [UIColor colorWithWhite:0.18 alpha:1.0];
    avatarView.image = [UIImage imageNamed:@"DefaultAccount"];
    [cardView addSubview:avatarView];
    NSString *picURLStr = [accountData[@"profilePicURL"] stringByReplacingOccurrencesOfString:@"\\/" withString:@"/"];
    if (picURLStr.length > 0) {
        [avatarView setImageWithURL:[NSURL URLWithString:picURLStr] placeholderImage:[UIImage imageNamed:@"DefaultAccount"]];
    }

    // Username.
    UILabel *usernameLabel = [[UILabel alloc] init];
    usernameLabel.translatesAutoresizingMaskIntoConstraints = NO;
    usernameLabel.text = displayName;
    usernameLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightSemibold];
    usernameLabel.textColor = [UIColor labelColor];
    usernameLabel.adjustsFontSizeToFitWidth = YES;
    usernameLabel.minimumScaleFactor = 0.7;
    usernameLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    [cardView addSubview:usernameLabel];

    // Subtitle.
    UILabel *subtitleLabel = [[UILabel alloc] init];
    subtitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    subtitleLabel.text = subtitle;
    subtitleLabel.font = [UIFont systemFontOfSize:12];
    subtitleLabel.textColor = [UIColor secondaryLabelColor];
    subtitleLabel.adjustsFontSizeToFitWidth = YES;
    subtitleLabel.minimumScaleFactor = 0.7;
    subtitleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    [cardView addSubview:subtitleLabel];

    // Account-type badge on the right.
    UILabel *badgeLabel = [[UILabel alloc] init];
    badgeLabel.translatesAutoresizingMaskIntoConstraints = NO;
    badgeLabel.font = [UIFont systemFontOfSize:10 weight:UIFontWeightBold];
    badgeLabel.textColor = [UIColor whiteColor];
    badgeLabel.textAlignment = NSTextAlignmentCenter;
    badgeLabel.layer.cornerRadius = 8;
    badgeLabel.layer.cornerCurve = kCACornerCurveContinuous;
    badgeLabel.layer.masksToBounds = YES;
    [cardView addSubview:badgeLabel];
    [self applyAccountTypeBadgeForAccount:accountData badgeLabel:badgeLabel];

    // Selection-state indicator.
    UIImageView *checkmark = [[UIImageView alloc] init];
    checkmark.translatesAutoresizingMaskIntoConstraints = NO;
    checkmark.image = [UIImage systemImageNamed:@"checkmark.circle.fill"];
    checkmark.tintColor = [UIColor colorWithRed:0.20 green:0.65 blue:0.40 alpha:1.0];
    checkmark.contentMode = UIViewContentModeScaleAspectFit;
    [cardView addSubview:checkmark];

    NSString *selectedAccountId = [self currentSelectedAccountId];
    BOOL isCurrentSelected = (selectedAccountId.length > 0 &&
                              [selectedAccountId isEqualToString:accountData[@"accountId"]]);
    checkmark.hidden = !isCurrentSelected;

    // Card padding and subview layout constraints.
    [NSLayoutConstraint activateConstraints:@[
        [cardView.topAnchor constraintEqualToAnchor:cell.contentView.topAnchor constant:6],
        [cardView.leadingAnchor constraintEqualToAnchor:cell.contentView.leadingAnchor constant:16],
        [cardView.trailingAnchor constraintEqualToAnchor:cell.contentView.trailingAnchor constant:-16],
        [cardView.bottomAnchor constraintEqualToAnchor:cell.contentView.bottomAnchor constant:-6],

        [avatarView.leadingAnchor constraintEqualToAnchor:cardView.leadingAnchor constant:14],
        [avatarView.centerYAnchor constraintEqualToAnchor:cardView.centerYAnchor],
        [avatarView.widthAnchor constraintEqualToConstant:48],
        [avatarView.heightAnchor constraintEqualToConstant:48],

        [usernameLabel.leadingAnchor constraintEqualToAnchor:avatarView.trailingAnchor constant:14],
        [usernameLabel.topAnchor constraintEqualToAnchor:cardView.topAnchor constant:18],
        [usernameLabel.trailingAnchor constraintEqualToAnchor:badgeLabel.leadingAnchor constant:-8],

        [subtitleLabel.leadingAnchor constraintEqualToAnchor:usernameLabel.leadingAnchor],
        [subtitleLabel.topAnchor constraintEqualToAnchor:usernameLabel.bottomAnchor constant:3],
        [subtitleLabel.trailingAnchor constraintEqualToAnchor:usernameLabel.trailingAnchor],
        [subtitleLabel.bottomAnchor constraintEqualToAnchor:cardView.bottomAnchor constant:-18],

        [badgeLabel.trailingAnchor constraintEqualToAnchor:cardView.trailingAnchor constant:-14],
        [badgeLabel.topAnchor constraintEqualToAnchor:cardView.topAnchor constant:14],
        [badgeLabel.heightAnchor constraintEqualToConstant:20],
        [badgeLabel.widthAnchor constraintGreaterThanOrEqualToConstant:52],

        [checkmark.trailingAnchor constraintEqualToAnchor:cardView.trailingAnchor constant:-14],
        [checkmark.bottomAnchor constraintEqualToAnchor:cardView.bottomAnchor constant:-14],
        [checkmark.widthAnchor constraintEqualToConstant:20],
        [checkmark.heightAnchor constraintEqualToConstant:20],
    ]];

    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:NO];
    // ★ [ACCT-DUP] Re-entry guard: ignore repeated row selections (rapid taps/long press) while a
    // sign-in flow is active, preventing the same account from being signed in twice.
    if (self.ameLoginInFlight) return;
    [self ameSetLoginInFlight:YES];
    NSUInteger generation = ++self.ameAuthGeneration;

    UITableViewCell *cell = [self.tableView cellForRowAtIndexPath:indexPath];
    [self addActivityIndicatorTo:cell];

    id callback = ^(id status, BOOL success) {
        dispatch_async(dispatch_get_main_queue(), ^(){
            // ★ [ACCT-DUP] Callback-side deduplication: accept only callbacks for this sign-in generation;
            // discard late callbacks from the previous sign-in.
            if (generation != self.ameAuthGeneration) return;
            [self callbackMicrosoftAuth:status success:success forCell:cell];
        });
    };

    // Check if this is a third party account
    NSDictionary *accountData = self.accountList[indexPath.row];
    // Load by accountId first; if accountId is missing (legacy account has not been migrated), fall
    // back to username to trigger migration.
    NSString *loadKey = accountData[@"accountId"];
    if (loadKey.length == 0) {
        loadKey = accountData[@"username"];
    }
    BaseAuthenticator *auth = nil;
    if (accountData[@"clientToken"] != nil) {
        // This is a third party account
        auth = [ThirdPartyAuthenticator loadSavedName:loadKey];
    } else {
        // This is a Microsoft or local account
        auth = [BaseAuthenticator loadSavedName:loadKey];
    }
    // ★ [ACCT-AUDIT] State consistency: loadSavedName returns nil if the account file is missing/
    //   corrupt (or reading fails). In that case, refreshTokenWithCallback: never invokes a callback
    //   ⇒ the list remains stuck with modalInPresentation=YES + userInteractionEnabled=NO + spinner,
    //   and the user can only force-quit.
    //   Roll back here: restore interaction, stop the spinner, and show a message; keep accountList
    //   and on-disk state unchanged.
    if (auth == nil) {
        // ★ [ACCT-DUP] Compatible with the re-entry guard: use ameSetLoginInFlight:NO to restore
        //   interaction and the button, preserving the previous [ACCT-AUDIT] nil rollback behavior
        //   (restore interaction, stop spinner, show a message).
        [self ameSetLoginInFlight:NO];
        [self removeActivityIndicatorFrom:cell];
        // ★ [AUDIT-DECIDE] A-10/A-11: the account-data load failure message was hard-coded in English;
        // route it through localize.
        showDialog(localize(@"Error", nil), localize(@"login.error.account_load", nil));
        return;
    }
    [auth refreshTokenWithCallback:callback];
}

- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath *)indexPath {
    if (editingStyle == UITableViewCellEditingStyleDelete) {
        // ★ [AUDIT-DECIDE] E-1: account deletion no longer "only removes local credentials" — make a best
        //   effort to invalidate the **remote session**.
        //   Detection matches sign-in: clientToken present ⇒ third party (Yggdrasil/authlib-injector);
        //   otherwise Microsoft/local.
        //   · Third party: call the official Yggdrasil invalidation endpoint,
        //     POST <API Root>/authserver/invalidate (see helper below).
        //   · Microsoft: the identity platform has **no** public revocation endpoint for consumer refresh
        //     tokens (no RFC 7009 /revoke equivalent; end_session only ends the browser session) ⇒ local
        //     invalidation only: delete the account file + clear access/refresh tokens from keychain
        //     (clearTokenDataOfProfile:), and discard the account's token/refresh fields in memory along
        //     with its file ("invalidate" = no usable credentials remain locally).
        //   · Local accounts: no remote session.
        //   Remote calls are asynchronous and non-blocking; failures are logged only (never block deletion).
        //   ★ Never log tokens in clear text.
        NSDictionary *accountData = self.accountList[indexPath.row];

        // Use accountId as the filename (unique identifier), so deleting same-name accounts does not
        // affect one another.
        // If accountId is missing (legacy account not migrated), fall back to username.
        NSString *accountId = accountData[@"accountId"];
        if (accountId.length == 0) {
            accountId = accountData[@"username"];
        }
        NSFileManager *fm = [NSFileManager defaultManager];
        NSString *path = [NSString stringWithFormat:@"%s/accounts/%@.json", getenv("POJAV_HOME"), accountId];
        if (self.whenDelete != nil) {
            self.whenDelete(accountId);
        }
        NSString *xuid = accountData[@"xuid"];
        if (xuid) {
            [MicrosoftAuthenticator clearTokenDataOfProfile:xuid];
        }
        [fm removeItemAtPath:path error:nil];
        // ★ [AUDIT-DECIDE] E-1: local credentials have been cleared (account file + keychain token);
        // now make a best effort to invalidate the remote session.
        [self ameInvalidateRemoteSessionForAccountData:accountData accountId:accountId];
        // ★ [ACCT-AUDIT] Cleanup: also remove the account's custom avatar file
        //   (Documents/avatars/<accountId>.png) when deleting an account, so user images are not left
        //   on disk. AvatarManager stores by accountId; deletion is idempotent and safely skips missing files.
        [[AvatarManager sharedManager] removeAvatarForAccount:accountId];
        // If this is the currently selected account, clear selected_account so the next launch does not
        // attempt to load a deleted account.
        if ([getPrefObject(@"internal.selected_account") isEqualToString:accountId]) {
            setPrefObject(@"internal.selected_account", @"");
            [BaseAuthenticator setCurrent:nil];
        }
        [self.accountList removeObjectAtIndex:indexPath.row];
        [tableView deleteRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationFade];
    }
}

#pragma mark - ★ [AUDIT-DECIDE] E-1 Delete account → invalidate remote session

// Make a best effort to invalidate the deleted account's remote session. Requirement: "try the
// official invalidation/logout endpoint; if none is public, document that and invalidate locally only".
//   ① Third party (Yggdrasil / authlib-injector): call the official endpoint from the specification,
//      `POST <API Root>/authserver/invalidate`, body = { accessToken, clientToken }.
//      Use the same API Root as authenticate/refresh; ely.by retains the legacy `auth/*` path.
//   ② Microsoft: there is **no** public revocation endpoint for consumer refresh tokens (no RFC 7009
//      /revoke equivalent; identity-platform logout/end_session only ends the browser session and
//      does not revoke the refresh token) ⇒ no remote call; invalidate locally only (account file
//      deletion + keychain token clearing are already done at the call site).
//   ③ Non-blocking: issue the network request asynchronously; deletion flow/UI does not wait.
//      Log failures only; never block deletion.
//   ④ Privacy: log only accountId / endpoint / result (status code/host); ★ never include accessToken /
//      clientToken in clear text.
- (void)ameInvalidateRemoteSessionForAccountData:(NSDictionary *)data accountId:(NSString *)accountId {
    if (![data isKindOfClass:[NSDictionary class]]) return;
    NSString *tag = accountId.length > 0 ? accountId : @"(unknown)";

    NSString *clientToken = data[@"clientToken"];
    if (clientToken.length == 0) {
        NSLog(@"[ACCT-INVALIDATE] account=%@ kind=msa/local remote=unsupported local=cleared "
              @"(Microsoft exposes no public refresh-token revoke endpoint; account file + keychain token removed)",
              tag);
        return;
    }

    NSString *accessToken = data[@"accessToken"];
    if (accessToken.length == 0) {
        NSLog(@"[ACCT-INVALIDATE] account=%@ kind=3rdparty remote=skipped local=deleted (no access token on record)", tag);
        return;
    }

    NSString *serverURL = data[@"authserver"] ?: @"https://authserver.ely.by";
    if (![serverURL hasSuffix:@"/"]) serverURL = [serverURL stringByAppendingString:@"/"];
    NSString *invalidateURL = [serverURL isEqualToString:@"https://authserver.ely.by/"]
        ? [serverURL stringByAppendingString:@"auth/invalidate"]
        : [serverURL stringByAppendingString:@"authserver/invalidate"];

    NSDictionary *body = @{ @"accessToken": accessToken, @"clientToken": clientToken };
    AFHTTPSessionManager *manager = AFHTTPSessionManager.manager;
    manager.requestSerializer = AFJSONRequestSerializer.serializer;
    // Invalidation endpoints often respond with 204 and an empty body: explicitly allow empty
    // responses so they are not misclassified as "parse failures".
    manager.responseSerializer = [AFHTTPResponseSerializer serializer];
    [manager POST:invalidateURL parameters:body headers:nil progress:nil
          success:^(NSURLSessionDataTask *task, id responseObject) {
        NSLog(@"[ACCT-INVALIDATE] account=%@ kind=3rdparty remote=ok url=%@", tag, invalidateURL);
    } failure:^(NSURLSessionDataTask *task, NSError *error) {
        NSHTTPURLResponse *http = [task.response isKindOfClass:[NSHTTPURLResponse class]] ? (NSHTTPURLResponse *)task.response : nil;
        NSLog(@"[ACCT-INVALIDATE] account=%@ kind=3rdparty remote=failed status=%ld domain=%@ (local deletion kept)",
              tag, (long)http.statusCode, error.domain);
    }];
}

- (UITableViewCellEditingStyle)tableView:(UITableView *)tableView editingStyleForRowAtIndexPath:(NSIndexPath *)indexPath
{
    // All account rows can be swiped to delete.
    return UITableViewCellEditingStyleDelete;
}

- (NSDictionary *)parseQueryItems:(NSString *)url {
    NSMutableDictionary *result = [NSMutableDictionary new];
    NSArray<NSURLQueryItem *> *queryItems = [NSURLComponents componentsWithString:url].queryItems;
    for (NSURLQueryItem *item in queryItems) {
        result[item.name] = item.value;
    }
    return result;
}

- (void)actionAddAccount:(UIView *)sender {
    // ★ [ACCT-DUP] Re-entry guard: prevent rapid taps from pushing two sign-in method pages
    // ("unlock" is in viewWillAppear).
    if (self.ameAddAccountInFlight) return;
    self.ameAddAccountInFlight = YES;
    // Following FCL, push the card-style sign-in method selection page (replacing the original ActionSheet).
    AccountLoginViewController *loginVC = [[AccountLoginViewController alloc] init];
    loginVC.onSelectLoginType = ^(AccountLoginType type) {
        // After a sign-in method is selected, pop back to the account list and then start the corresponding sign-in flow.
        [self.navigationController popViewControllerAnimated:YES];
        dispatch_async(dispatch_get_main_queue(), ^{
            switch (type) {
                case AccountLoginTypeMicrosoft:
                    [self actionLoginMicrosoft:sender];
                    break;
                case AccountLoginTypeLittleSkin:
                    [self actionLoginLittleSkin:sender];
                    break;
                case AccountLoginTypeThirdParty:
                    [self actionLoginThirdParty:sender];
                    break;
                case AccountLoginTypeLocal:
                    [self actionLoginLocal:sender];
                    break;
            }
        });
    };
    [self.navigationController pushViewController:loginVC animated:YES];
}

- (void)actionLoginLocal:(UIView *)sender {
    if (getPrefBool(@"warnings.local_warn")) {
        setPrefBool(@"warnings.local_warn", NO);
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:localize(@"login.warn.title.localmode", nil) message:localize(@"login.warn.message.localmode", nil) preferredStyle:UIAlertControllerStyleActionSheet];
        // Fix: when sender is nil (entered through addAccountTapped -> actionAddAccount:nil),
        // ActionSheet requires a sourceView in popover contexts such as iPad/LiveContainer; otherwise
        // popoverPresentationController.sourceView being nil causes a crash.
        // Fallback order: sender -> addAccountButton -> center of self.view.
        UIView *sourceView = sender ?: self.addAccountButton;
        if (sourceView) {
            alert.popoverPresentationController.sourceView = sourceView;
            alert.popoverPresentationController.sourceRect = sourceView.bounds;
        } else {
            alert.popoverPresentationController.sourceView = self.view;
            alert.popoverPresentationController.sourceRect = CGRectMake(CGRectGetMidX(self.view.bounds), CGRectGetMidY(self.view.bounds), 1, 1);
            alert.popoverPresentationController.permittedArrowDirections = 0;
        }
        UIAlertAction *ok = [UIAlertAction actionWithTitle:localize(@"OK", nil) style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {[self actionLoginLocal:sender];}];
        [alert addAction:ok];
        [self presentViewController:alert animated:YES completion:nil];
        return;
    }
    // ★ [AUDIT-DECIDE] A-11: an English literal was used as the key (no such key in .strings) →
    // add the login.sign_in key.
    UIAlertController *controller = [UIAlertController alertControllerWithTitle:localize(@"login.sign_in", nil) message:localize(@"login.option.local", nil) preferredStyle:UIAlertControllerStyleAlert];
    [controller addTextFieldWithConfigurationHandler:^(UITextField *textField) {
        textField.placeholder = localize(@"login.alert.field.username", nil);
        textField.clearButtonMode = UITextFieldViewModeWhileEditing;
        textField.borderStyle = UITextBorderStyleRoundedRect;
    }];
    [controller addAction:[UIAlertAction actionWithTitle:localize(@"OK", nil) style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        NSArray *textFields = controller.textFields;
        UITextField *usernameField = textFields[0];
        if (usernameField.text.length < 3 || usernameField.text.length > 16) {
            controller.message = localize(@"login.error.username.outOfRange", nil);
            [self presentViewController:controller animated:YES completion:nil];
        } else {
            id callback = ^(id status, BOOL success) {
                if (self.whenItemSelected) self.whenItemSelected();
                // ★ [ACCT-DUP] Refresh the list after local sign-in too (consistent with Microsoft/third-party
                // paths), immediately reflecting storage's idempotent deduplication (duplicate usernames yield
                // only one entry).
                [self reloadAccountList];
                [self dismissViewControllerAnimated:YES completion:nil];
            };
            [[[LocalAuthenticator alloc] initWithInput:usernameField.text] loginWithCallback:callback];
        }
    }]];
    [controller addAction:[UIAlertAction actionWithTitle:localize(@"Cancel", nil) style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:controller animated:YES completion:nil];
}

- (void)actionLoginThirdParty:(UIView *)sender {
    // Following FCL, push the card-style third-party sign-in form (replacing the original three-field UIAlertController input).
    ThirdPartyLoginViewController *vc = [[ThirdPartyLoginViewController alloc] init];
    vc.mode = ThirdPartyLoginModeCustom;
    __weak typeof(self) weakSelf = self;
    vc.onLoginComplete = ^(BOOL success, NSString *errorMessage) {
        if (success) {
            [weakSelf.navigationController popViewControllerAnimated:YES];
            if (weakSelf.whenItemSelected) weakSelf.whenItemSelected();
        }
    };
    [self.navigationController pushViewController:vc animated:YES];
}

- (void)actionLoginLittleSkin:(UIView *)sender {
    // Following FCL, push the card-style LittleSkin sign-in form (replacing the original two-field UIAlertController input).
    // The LittleSkin endpoint is fixed at https://littleskin.cn/api/yggdrasil and preset in the VC.
    ThirdPartyLoginViewController *vc = [[ThirdPartyLoginViewController alloc] init];
    vc.mode = ThirdPartyLoginModeLittleSkin;
    __weak typeof(self) weakSelf = self;
    vc.onLoginComplete = ^(BOOL success, NSString *errorMessage) {
        if (success) {
            [weakSelf.navigationController popViewControllerAnimated:YES];
            if (weakSelf.whenItemSelected) weakSelf.whenItemSelected();
        }
    };
    [self.navigationController pushViewController:vc animated:YES];
}

- (void)actionLoginMicrosoft:(UIView *)sender {
    NSURL *url = [NSURL URLWithString:@"https://login.live.com/oauth20_authorize.srf?client_id=00000000402b5328&response_type=code&scope=service%3A%3Auser.auth.xboxlive.com%3A%3AMBI_SSL&redirect_url=https%3A%2F%2Flogin.live.com%2Foauth20_desktop.srf"];

    self.authVC =
        [[ASWebAuthenticationSession alloc] initWithURL:url
        callbackURLScheme:@"ms-xal-00000000402b5328"
        completionHandler:^(NSURL * _Nullable callbackURL, NSError * _Nullable error)
    {
        if (callbackURL == nil) {
            if (error.code != ASWebAuthenticationSessionErrorCodeCanceledLogin) {
                showDialog(localize(@"Error", nil), error.localizedDescription);
            }
            return;
        }
        // NSLog(@"URL returned = %@", [callbackURL absoluteString]);

        NSDictionary *queryItems = [self parseQueryItems:callbackURL.absoluteString];
        if (queryItems[@"code"]) {
            dispatch_async(dispatch_get_main_queue(), ^(){
                // ★ [ACCT-DONE] Use the shared in-flight lock (locks only the list + "Add Account" button, never
                //   the navigation-bar exit). The old implementation separately changed modalInPresentation/
                //   tableView here; modalInPresentation has no effect on this page (a child VC in a content
                //   container) and is now handled together by ameSetLoginInFlight:.
                [self ameSetLoginInFlight:YES];
                // Show a loading indicator only when sender is a UITableViewCell.
                if ([sender isKindOfClass:[UITableViewCell class]]) {
                    [self addActivityIndicatorTo:(UITableViewCell *)sender];
                }
            });
            id callback = ^(id status, BOOL success) {
                if ([status isKindOfClass:NSString.class] && [status isEqualToString:@"DEMO"] && success) {
                    showDialog(localize(@"login.warn.title.demomode", nil), localize(@"login.warn.message.demomode", nil));
                }
                dispatch_async(dispatch_get_main_queue(), ^(){
                    UITableViewCell *cell = [sender isKindOfClass:[UITableViewCell class]] ? (UITableViewCell *)sender : nil;
                    [self callbackMicrosoftAuth:status success:success forCell:cell];
                });
            };
            [[[MicrosoftAuthenticator alloc] initWithInput:queryItems[@"code"]] loginWithCallback:callback];
        } else {
            if ([queryItems[@"error"] hasPrefix:@"access_denied"]) {
                // Ignore access denial responses
                return;
            }
            showDialog(localize(@"Error", nil), queryItems[@"error_description"]);
        }
    }];

    self.authVC.prefersEphemeralWebBrowserSession = YES;
    self.authVC.presentationContextProvider = self;

    if ([self.authVC start] == NO) {
        showDialog(localize(@"Error", nil), @"Unable to open Safari");
    }
}

- (void)addActivityIndicatorTo:(UITableViewCell *)cell {
    UIActivityIndicatorViewStyle indicatorStyle = UIActivityIndicatorViewStyleMedium;
    UIActivityIndicatorView *indicator = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:indicatorStyle];
    cell.accessoryView = indicator;
    [indicator sizeToFit];
    [indicator startAnimating];
}

- (void)removeActivityIndicatorFrom:(UITableViewCell *)cell {
    UIActivityIndicatorView *indicator = (id)cell.accessoryView;
    [indicator stopAnimating];
    cell.accessoryView = nil;
}

/// ★ [AUTH-FIX] Convert an authentication-failure object into a **recognizable**, user-readable
///   message (instead of only a generic AFNetworking string such as
///   "Request failed: unauthorized (401)"):
///   · NSString → return as-is;
///   · NSError  → first parse XErr / Message / errorMessage / error_description / error from the
///                response body; if unavailable, fall back to the HTTP status code +
///                localizedDescription.
///   Security: the response body contains only error codes and explanatory text, **not tokens or
///   credentials**; this method never echoes credentials.
- (NSString *)ameReadableAuthError:(id)status {
    if ([status isKindOfClass:[NSString class]]) {
        return status;
    }
    if (![status isKindOfClass:[NSError class]]) {
        return localize(@"login.error.invalid_response", nil);
    }
    NSError *error = (NSError *)status;
    NSHTTPURLResponse *http = error.userInfo[AFNetworkingOperationFailingURLResponseErrorKey];
    NSInteger code = ([http isKindOfClass:[NSHTTPURLResponse class]]) ? http.statusCode : 0;

    NSString *detail = nil;
    NSData *errorData = error.userInfo[AFNetworkingOperationFailingURLResponseDataErrorKey];
    if (errorData.length > 0) {
        id json = [NSJSONSerialization JSONObjectWithData:errorData options:kNilOptions error:nil];
        if ([json isKindOfClass:[NSDictionary class]]) {
            NSDictionary *d = json;
            id xerr = d[@"XErr"];
            id msg = d[@"Message"] ?: d[@"errorMessage"] ?: d[@"error_description"] ?: d[@"error"];
            if (xerr != nil || msg != nil) {
                NSMutableArray *parts = [NSMutableArray array];
                if (msg != nil) [parts addObject:[msg description]];
                if (xerr != nil) [parts addObject:[NSString stringWithFormat:@"XErr=%@", xerr]];
                detail = [parts componentsJoinedByString:@" "];
            }
        } else {
            NSString *raw = [[NSString alloc] initWithData:errorData encoding:NSUTF8StringEncoding];
            if (raw.length > 0 && raw.length < 512) detail = raw;   // Include short non-JSON response bodies too.
        }
    }

    if (detail.length > 0) {
        return (code > 0) ? [NSString stringWithFormat:@"HTTP %ld — %@", (long)code, detail] : detail;
    }
    if (code > 0) {
        return [NSString stringWithFormat:@"HTTP %ld — %@", (long)code, error.localizedDescription ?: @""];
    }
    return error.localizedDescription ?: localize(@"login.error.invalid_response", nil);
}

- (void)callbackMicrosoftAuth:(id)status success:(BOOL)success forCell:(UITableViewCell *)cell {
    // ★ [AUTH-FIX] Distinguish "progress" from "completion" — fixes the false interpretation that
    //   Microsoft sign-in is stuck at "(2/6) Request Xbox Live token":
    //   The authenticator sends a **progress** callback at every step (status != nil, success = YES)
    //   (for example, localize(@"login.msa.progress.acquireXBLToken") == "(2/6) Request Xbox Live token").
    //   The old implementation treated this as "sign-in succeeded" and finalized (show "Account"
    //   dialog + reload + dismiss + unlock), so:
    //     ① A progress dialog appeared immediately after tapping Sign In, then finalized/unlocked early.
    //     ② If the next XBL step failed, the last progress text was "Request Xbox Live token", while
    //        the failure message was generic ⇒ users saw "Unable to request Xbox token".
    //   Upstream semantics: (status != nil, success = YES) = progress; (status == nil, success = YES) = completion.
    //   The only terminal exception: @"DEMO" (Demo account was saved), which finalizes normally.
    BOOL isDemo = (success && [status isKindOfClass:[NSString class]] && [status isEqualToString:@"DEMO"]);

    // ① Progress: update only the UI; never dismiss / reload / unlock / call whenItemSelected.
    if (status != nil && success && !isDemo) {
        NSString *progress = [status isKindOfClass:[NSError class]] ? [(NSError *)status localizedDescription]
                            : ([status isKindOfClass:[NSString class]] ? status : [status description]);
        NSLog(@"[MSA] progress: %@", progress);
        if (cell && cell.detailTextLabel) cell.detailTextLabel.text = progress;
        return;
    }

    // ② Authentication failure: restore interaction and show a **recognizable** error.
    if (status != nil && !success) {
        [self ameSetLoginInFlight:NO];
        if (cell) [self removeActivityIndicatorFrom:cell];
        NSString *message = [self ameReadableAuthError:status];
        NSLog(@"[MSA] Error: %@", message);
        showDialog(localize(@"Error", nil), message);
        return;
    }

    // ③ Completion: status == nil (or terminal DEMO state).
    if (success) {
        if (isDemo) {
            showDialog(localize(@"login.warn.title.demomode", nil), localize(@"login.warn.message.demomode", nil));
        }
        if (cell) [self removeActivityIndicatorFrom:cell];
        [self ameSetLoginInFlight:NO];
        [self reloadAccountList];
        if (self.whenItemSelected) self.whenItemSelected();
        [self dismissViewControllerAnimated:YES completion:nil];
        return;
    }

    // ④ status == nil and success == NO (cancelled/empty callback): must also unlock.
    // ★ [ACCT-DONE] The old implementation lacked this branch ⇒ in-flight remained set forever and
    // the list/"Add Account" button stayed disabled (force-quit was the only option).
    if (cell) [self removeActivityIndicatorFrom:cell];
    [self ameSetLoginInFlight:NO];
    showDialog(localize(@"Error", nil), localize(@"login.error.invalid_response", nil));
}

/// Reload the account list and refresh the table (FCL style: refresh the card view after sign-in/deletion).
- (void)reloadAccountList {
    [self ameLoadAccountListFromDisk];
    [self.tableView reloadData];
}

/// ★ [ACCT-DUP] Load the account list from disk (shared by viewDidLoad / reloadAccountList):
///   ① Before loading, call deduplicateAccountsDirectory to merge existing duplicates with the
///      **same identity** (idempotent; delete only truly duplicate files and preserve all legitimate
///      accounts with different username/xuid/profileId);
///   ② Skip corrupt files that fail parseJSONFromFile (returns @{NSErrorObject:…}) to avoid a
///      nameless "ghost account" appearing in the list.
- (void)ameLoadAccountListFromDisk {
    if (self.accountList == nil) {
        self.accountList = [NSMutableArray array];
    } else {
        [self.accountList removeAllObjects];
    }
    [BaseAuthenticator deduplicateAccountsDirectory];

    NSString *listPath = [NSString stringWithFormat:@"%s/accounts", getenv("POJAV_HOME")];
    NSFileManager *fm = [NSFileManager defaultManager];
    NSArray *files = [fm contentsOfDirectoryAtPath:listPath error:nil];
    for (NSString *file in files) {
        NSString *path = [listPath stringByAppendingPathComponent:file];
        BOOL isDir = NO;
        [fm fileExistsAtPath:path isDirectory:(&isDir)];
        if (isDir || ![file hasSuffix:@".json"]) continue;
        NSMutableDictionary *data = parseJSONFromFile(path);
        if (data == nil || data[@"NSErrorObject"] != nil) continue;
        [self.accountList addObject:data];
    }
}

/// ★ [ACCT-DUP] Shared "sign-in in progress" switch: setting it disables the list and "Add Account"
///   button in one place; restore them when finished (success/failure/cancel/nil rollback/page exit/
///   watchdog) so a sign-in flow cannot be triggered twice while in flight.
///
/// ★ [ACCT-DONE] Two corrections in this change:
///   ① Lock only controls that trigger sign-in (table rows + "Add Account" button). Previously
///      self.modalInPresentation was also set, but this page is a **child VC** in the content
///      container (setContentViewController: inserts it into Home's contentContainer), not a modal
///      presentation ⇒ that property has no effect and is a leftover from the FormSheet era.
///      The actual safeguard is to keep the "navigation-bar exit (left 'Done' button) tappable at all
///      times"; never lock navigation chrome (see ameAccountEnsureBackItemIfNeeded).
///   ② Add a **watchdog**: if the token is unchanged and sign-in is still in flight after 60s ⇒ force
///      unlock. Prevent a lost callback/network hang from locking the list forever (a second,
///      defer-style safeguard alongside the unconditional unlock in viewWillAppear).
- (void)ameSetLoginInFlight:(BOOL)inFlight {
    self.ameLoginInFlight = inFlight;
    self.tableView.userInteractionEnabled = !inFlight;
    self.addAccountButton.enabled = !inFlight;
    NSUInteger token = ++self.ameLoginInFlightToken;
    if (!inFlight) return;
    __weak typeof(self) weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(60.0 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        if (strongSelf.ameLoginInFlightToken != token) return;   // Already unlocked normally or replaced by a new attempt ⇒ do nothing.
        if (!strongSelf.ameLoginInFlight) return;
        NSLog(@"[ACCT-DONE] in-flight watchdog timed out (60s); force-unlocking to avoid a permanently locked list if a callback was lost.");
        [strongSelf ameSetLoginInFlight:NO];
    });
}

/// ★ [ACCT-DONE] Unlock when the page actually leaves the window (popped/replaced in the content
/// area). If only covered by web sign-in, self.view.window remains set ⇒ do not unlock or interrupt
/// the sign-in in progress.
- (void)viewDidDisappear:(BOOL)animated {
    [super viewDidDisappear:animated];
    if (self.view.window == nil) {
        [self ameSetLoginInFlight:NO];
    }
}

#pragma mark - UIPopoverPresentationControllerDelegate
- (UIModalPresentationStyle)adaptivePresentationStyleForPresentationController:(UIPresentationController *)controller traitCollection:(UITraitCollection *)traitCollection {
    return UIModalPresentationNone;
}

#pragma mark - ASWebAuthenticationPresentationContextProviding
- (ASPresentationAnchor)presentationAnchorForWebAuthenticationSession:(ASWebAuthenticationSession *)session {
    return UIApplication.sharedApplication.windows.firstObject;
}

@end
