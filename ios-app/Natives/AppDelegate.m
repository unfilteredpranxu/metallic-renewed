#import "AppDelegate.h"
#import "SceneDelegate.h"
#import "ios_uikit_bridge.h"
#import "utils.h"
#import "AFNetworking.h"
#import "MinecraftResourceDownloadTask.h"
#import "LauncherPreferences.h"

// SurfaceViewController
extern dispatch_group_t fatalExitGroup;

@interface AppDelegate ()
@property (nonatomic, copy) void (^backgroundURLSessionCompletionHandler)(void);
@end

@implementation AppDelegate

#pragma mark - UISceneSession lifecycle

- (UISceneConfiguration *)application:(UIApplication *)application configurationForConnectingSceneSession:(UISceneSession *)connectingSceneSession options:(UISceneConnectionOptions *)options {
    // ★ [I18N-ORDER] Earliest entry point for the app: resolve and cache the "effective language"
    // before building any UI (idempotent).
    AmeLauncherPrimeLanguage();
    // One-time migration of the legacy global download-source preference to category-specific mirror
    // strategy keys (idempotent; happens before any UI reads preferences).
    migrateDownloadSourcePreferences();
    // Called when a new scene session is being created.
    return [[UISceneConfiguration alloc] initWithName:@"Default Configuration" sessionRole:connectingSceneSession.role];
}

- (void)application:(UIApplication *)application didDiscardSceneSessions:(NSSet<UISceneSession *> *)sceneSessions {
    // Called when the user discards a scene session.
}

- (void)applicationWillTerminate:(UIApplication *)application {
    if (fatalExitGroup != nil) {
        dispatch_group_leave(fatalExitGroup);
        fatalExitGroup = nil;
    }
}

#pragma mark - Background URL Session

- (void)application:(UIApplication *)application handleEventsForBackgroundURLSession:(NSString *)identifier completionHandler:(void (^)(void))completionHandler {
    if (![identifier isEqualToString:kMinecraftResourceDownloadBackgroundSessionIdentifier]) {
        if (completionHandler) {
            completionHandler();
        }
        return;
    }

    self.backgroundURLSessionCompletionHandler = completionHandler;

    AFURLSessionManager *manager = [MinecraftResourceDownloadTask sharedBackgroundSessionManager];
    __weak typeof(self) weakSelf = self;
    [manager setDidFinishEventsForBackgroundURLSessionBlock:^(NSURLSession *session) {
        if (weakSelf.backgroundURLSessionCompletionHandler) {
            weakSelf.backgroundURLSessionCompletionHandler();
            weakSelf.backgroundURLSessionCompletionHandler = nil;
        }
    }];
}

#pragma mark - Orientation Support

- (UIInterfaceOrientationMask)application:(UIApplication *)application supportedInterfaceOrientationsForWindow:(UIWindow *)window {
    // ★ [GAME-LANDSCAPE] Also restrict this layer to landscape during launch/in-game (intersection with
    //   the root VC layer provides a second safeguard; when not locked, the returned value is byte-for-byte
    //   identical to the pre-change value).
    if (AmeGameLandscapeLockActive()) return UIInterfaceOrientationMaskLandscape;
    // Force landscape only
    return UIInterfaceOrientationMaskAllButUpsideDown;   // ★ [PORTRAIT] Allow all orientations at the window level (the game page locks landscape separately).
}

@end
