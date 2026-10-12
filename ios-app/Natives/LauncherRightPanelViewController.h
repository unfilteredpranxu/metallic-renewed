#import <UIKit/UIKit.h>

// FCL-style right panel - displays account information, version selection, and the launch button.
//
// ★ [NORIGHT] The right-panel card has been removed (decision: remove the card and relocate its contents).
//   This controller is **retained** as a "hidden controller": its container is pinned at 0×0 and hidden, while
//   norightCollapsePanelLayout: disables all internal constraints (otherwise 0×0 conflicts with required constraints).
//   The full launch flow (account validation/JIT/download interception/version resolution), JAR execution,
//   version selection, Download Center, and JIT monitoring all continue to run in this class unchanged;
//   only their UI entry points have moved:
//
//     · Avatar + username + version → Home page's "Welcome Back" card (LauncherNewsViewController)
//        (Avatar remains tappable / long-pressable: tap = account management, long press = custom-avatar menu; both forward to this class's original methods.)
//     · Launch game             → "Compact Capsule" at the bottom of the Home page (LauncherNewsViewController)
//     · JIT status              → Pill at the upper-right of the Home page, beside "⚙ Customize"
//     · Execute JAR / select version → Toolbar at the top of the Instances page (VersionManagerViewController)
//     · Downloading/paused      → Not moved (the Downloads tab already has the Download Center); notification logic is retained.
//
//   The new UI only posts action names; the notifications below forward them to **this class's original methods** — no logic is duplicated.
//
// ★ [FIX511] When rebasing to 5.1.0, this header was mistakenly replaced with the upstream 5.1.0 13-line stub, dropping
//   the entire block of fork-specific declarations below (3 notification constants + 3 noright methods), causing:
//     AccountListViewController.m:165  [LauncherRightPanelViewController norightPostAction:]
//       → error: no known class method for selector 'norightPostAction:'
//     LauncherRootViewController.m:597 [rightPanelVC norightCollapsePanelLayout:YES]
//     LauncherNewsViewController.m    AmeRightPanelStateNotification / …RequestStateNotification
//   Restored from the fork (the fork's .h matches the rest of this file and is a strict superset).

/// New UI entry point → original right-panel implementation.
/// userInfo: @{@"action": @"launch" | @"executeJar" | @"versionPicker" | @"downloadCenter"}
extern NSString * const AmeRightPanelActionNotification;
/// Right-panel state broadcast (version / JIT text and color / username / launch-button title and enabled state). See .m for userInfo.
extern NSString * const AmeRightPanelStateNotification;
/// Request the current state externally (the right panel recalculates JIT and broadcasts the result upon receiving the request).
extern NSString * const AmeRightPanelRequestStateNotification;

@interface LauncherRightPanelViewController : UIViewController

// Update the displayed account information.
- (void)updateAccountInfo;

// Update the displayed version information.
- (void)updateVersionInfo;

// ★ [NORIGHT] Collapse (collapsed=YES) / restore all internal panel constraints and hide its subviews. Idempotent.
- (void)norightCollapsePanelLayout:(BOOL)collapsed;

// ★ [UI-ADAPT] Compact avatar-only layout (for CardLayout / Bento: the right-panel card is fixed as a 56 pt-high small card,
//   permanently in the upper-right and displaying only the avatar). Disable the full-height constraint group and keep only the avatar. Idempotent.
- (void)norightAvatarOnlyLayout:(BOOL)on;

// ★ [NORIGHT] Broadcast the current state once (also broadcast automatically on internal updates).
- (void)norightBroadcastState;

// ★ [NORIGHT] The sole entry point for actions from the new UI (internally posts AmeRightPanelActionNotification).
+ (void)norightPostAction:(NSString *)action;

@end
