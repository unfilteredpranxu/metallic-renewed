#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import "authenticator/BaseAuthenticator.h"
#import "AFNetworking.h"
#import "ALTServerConnection.h"
#import "CustomControlsViewController.h"
#import "DownloadTasksViewController.h"
#import "DownloadTaskManager.h"
#import "DownloadTaskItem.h"
#import "PLTaskProgressViewController.h"
#import "JavaGUIViewController.h"
#import "JavaLauncher.h"
#import "PLCrashView.h"
#import "LauncherMenuViewController.h"
#import "LauncherNavigationController.h"
#import "LauncherPreferences.h"
#import "MinecraftResourceDownloadTask.h"
#import "MinecraftResourceUtils.h"
#import "PickTextField.h"
#import "PLPickerView.h"
#import "PLProfiles.h"
#import "UIKit+AFNetworking.h"
#import "UIKit+hook.h"
#import "ios_uikit_bridge.h"
#import "utils.h"
#import "installer/modpack/ModrinthAPI.h"

#include <sys/time.h>

#define AUTORESIZE_MASKS UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin

static void *ProgressObserverContext = &ProgressObserverContext;

@interface LauncherNavigationController () <UIDocumentPickerDelegate, UIPickerViewDataSource, PLPickerViewDelegate, UIPopoverPresentationControllerDelegate> {
}

@property(nonatomic) MinecraftResourceDownloadTask* task;
@property(nonatomic) PLPickerView* versionPickerView;
@property(nonatomic) UITextField* versionTextField;
@property(nonatomic) int profileSelectedAt;

// ===== Download Center entry point (modeled on the FCL/ZL2/HMCL download progress dialog) =====
// Add a "Download Center" button to the toolbar; tapping it opens DownloadTasksViewController,
// which displays progress for all download tasks (Minecraft, mods, shaders, resource packs, data packs, worlds, modpacks).
// All tasks registered through DownloadTaskManager report progress in this dialog.
@property(nonatomic, strong) UIButton *downloadCenterButton;
@property(nonatomic, strong) UIActivityIndicatorView *downloadCenterActivityIndicator;
@property(nonatomic, strong) UILabel *downloadCenterProgressLabel;
// Active-task badge (redesign-download-ui Task 2.4): a small red circular badge
// overlaid on the upper-right of the download icon, showing the number of active (downloading/queued) tasks.
@property(nonatomic, strong) UILabel *downloadCenterBadgeLabel;
@property(nonatomic, weak) DownloadTasksViewController *presentedDownloadCenterVC;
// Tracks whether the user manually closed the Download Center (prevents it reopening automatically on every task update).
@property(nonatomic, assign) BOOL userDismissedDownloadCenter;

@end

@implementation LauncherNavigationController

- (void)viewDidLoad
{
    [super viewDidLoad];

    if ([self respondsToSelector:@selector(setNeedsUpdateOfScreenEdgesDeferringSystemGestures)]) {
        [self setNeedsUpdateOfScreenEdgesDeferringSystemGestures];
    }

    self.versionTextField = [[PickTextField alloc] initWithFrame:CGRectMake(4, 4, self.toolbar.frame.size.width * 0.8 - 8, self.toolbar.frame.size.height - 8)];
    [self.versionTextField addTarget:self.versionTextField action:@selector(resignFirstResponder) forControlEvents:UIControlEventEditingDidEndOnExit];
    self.versionTextField.autoresizingMask = AUTORESIZE_MASKS;
    self.versionTextField.placeholder = @"Specify version...";
    self.versionTextField.leftView = [[UIImageView alloc] initWithFrame:CGRectMake(0, 0, 40, 40)];
    self.versionTextField.rightView = [[UIImageView alloc] initWithImage:[[UIImage imageNamed:@"SpinnerArrow"] _imageWithSize:CGSizeMake(30, 30)]];
    self.versionTextField.rightView.frame = CGRectMake(0, 0, self.versionTextField.frame.size.height * 0.9, self.versionTextField.frame.size.height * 0.9);
    self.versionTextField.leftViewMode = UITextFieldViewModeAlways;
    self.versionTextField.rightViewMode = UITextFieldViewModeAlways;
    self.versionTextField.textAlignment = NSTextAlignmentCenter;

    self.versionPickerView = [[PLPickerView alloc] init];
    self.versionPickerView.delegate = self;
    self.versionPickerView.dataSource = self;
    UIToolbar *versionPickToolbar = [[UIToolbar alloc] initWithFrame:CGRectMake(0.0, 0.0, self.view.frame.size.width, 44.0)];

    [self reloadProfileList];

    // Listen for profile-list refresh notifications.
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(reloadProfileList)
                                                 name:@"ReloadProfileList"
                                               object:nil];

    UIBarButtonItem *versionFlexibleSpace = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:self action:nil];
    UIBarButtonItem *versionDoneButton = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:self action:@selector(versionClosePicker)];
    versionPickToolbar.items = @[versionFlexibleSpace, versionDoneButton];
    self.versionTextField.inputAccessoryView = versionPickToolbar;
    self.versionTextField.inputView = self.versionPickerView;

    UIView *targetToolbar = self.toolbar;
    [targetToolbar addSubview:self.versionTextField];

    self.buttonInstall = [UIButton buttonWithType:UIButtonTypeSystem];
    setButtonPointerInteraction(self.buttonInstall);
    [self.buttonInstall setTitle:localize(@"Play", nil) forState:UIControlStateNormal];
    self.buttonInstall.autoresizingMask = AUTORESIZE_MASKS;
    self.buttonInstall.backgroundColor = [UIColor colorWithRed:121/255.0 green:56/255.0 blue:162/255.0 alpha:1.0];
    self.buttonInstall.layer.cornerRadius = 5;
    self.buttonInstall.layer.cornerCurve = kCACornerCurveContinuous;   // ★ [CORNER-FIX] Continuous corners (matching system cards).
    self.buttonInstall.frame = CGRectMake(self.toolbar.frame.size.width * 0.8, 4, self.toolbar.frame.size.width * 0.2, self.toolbar.frame.size.height - 8);
    self.buttonInstall.tintColor = UIColor.whiteColor;
    self.buttonInstall.enabled = NO;
    [self.buttonInstall addTarget:self action:@selector(performInstallOrShowDetails:) forControlEvents:UIControlEventPrimaryActionTriggered];
    [targetToolbar addSubview:self.buttonInstall];

    // ===== Download Center button (modeled on the FCL/ZL2/HMCL download progress dialog) =====
    // Add a "Download Center" button to the left of the toolbar; show it when download tasks exist.
    // Tapping opens DownloadTasksViewController as a FormSheet to show progress for all download tasks.
    // Button layout: [icon] [progress percentage] [activity indicator]
    CGFloat dcBtnWidth = 72.0;
    CGFloat dcBtnHeight = self.toolbar.frame.size.height - 8;
    self.downloadCenterButton = [UIButton buttonWithType:UIButtonTypeSystem];
    // Use a separate progressLabel instead of the button title to avoid conflicting with the icon layout.
    self.downloadCenterButton.tintColor = [UIColor whiteColor];
    self.downloadCenterButton.backgroundColor = [UIColor colorWithRed:121/255.0 green:56/255.0 blue:162/255.0 alpha:0.85];
    self.downloadCenterButton.layer.cornerRadius = 5;
    self.downloadCenterButton.layer.cornerCurve = kCACornerCurveContinuous;   // ★ [CORNER-FIX] Continuous corners (matching system cards).
    self.downloadCenterButton.frame = CGRectMake(4, 4, dcBtnWidth, dcBtnHeight);
    self.downloadCenterButton.autoresizingMask = UIViewAutoresizingFlexibleRightMargin;
    [self.downloadCenterButton setImage:[UIImage systemImageNamed:@"arrow.down.circle"] forState:UIControlStateNormal];
    // Keep the icon fixed on the left side of the button.
    CGFloat iconSize = 22.0;
    [self.downloadCenterButton setImageEdgeInsets:UIEdgeInsetsMake(0, 4, 0, dcBtnWidth - iconSize - 4)];
    [self.downloadCenterButton addTarget:self action:@selector(openDownloadCenter) forControlEvents:UIControlEventTouchUpInside];
    self.downloadCenterButton.hidden = YES;
    [targetToolbar addSubview:self.downloadCenterButton];

    // Activity indicator (right side of the button; spins during downloads).
    self.downloadCenterActivityIndicator = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    self.downloadCenterActivityIndicator.color = [UIColor whiteColor];
    self.downloadCenterActivityIndicator.hidesWhenStopped = YES;
    CGFloat indicatorSize = 20.0;
    self.downloadCenterActivityIndicator.frame = CGRectMake(dcBtnWidth - indicatorSize - 4, (dcBtnHeight - indicatorSize) / 2.0, indicatorSize, indicatorSize);
    self.downloadCenterActivityIndicator.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
    [self.downloadCenterButton addSubview:self.downloadCenterActivityIndicator];

    // Progress percentage label (center of the button; shows aggregate progress).
    self.downloadCenterProgressLabel = [[UILabel alloc] init];
    self.downloadCenterProgressLabel.font = [UIFont monospacedDigitSystemFontOfSize:11 weight:UIFontWeightBold];
    self.downloadCenterProgressLabel.textColor = [UIColor whiteColor];
    self.downloadCenterProgressLabel.textAlignment = NSTextAlignmentCenter;
    self.downloadCenterProgressLabel.text = @"";
    self.downloadCenterProgressLabel.frame = CGRectMake(iconSize + 6, 0, dcBtnWidth - iconSize - indicatorSize - 12, dcBtnHeight);
    self.downloadCenterProgressLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [self.downloadCenterButton addSubview:self.downloadCenterProgressLabel];

    // Active-task badge (redesign-download-ui Task 2.4): a small red circular badge overlaid on
    // the upper-right of the download icon (like an app icon badge), hidden when no tasks are active.
    // The button is already full (icon + percentage + indicator), so overlaying the icon minimizes visual impact.
    self.downloadCenterBadgeLabel = [[UILabel alloc] init];
    self.downloadCenterBadgeLabel.font = [UIFont monospacedDigitSystemFontOfSize:10 weight:UIFontWeightBold];
    self.downloadCenterBadgeLabel.textColor = [UIColor whiteColor];
    self.downloadCenterBadgeLabel.backgroundColor = [UIColor systemRedColor];
    self.downloadCenterBadgeLabel.textAlignment = NSTextAlignmentCenter;
    self.downloadCenterBadgeLabel.layer.cornerRadius = 8.0;
    self.downloadCenterBadgeLabel.layer.cornerCurve = kCACornerCurveContinuous;   // ★ [CORNER-FIX] Continuous corners (matching system cards).
    self.downloadCenterBadgeLabel.layer.masksToBounds = YES;
    self.downloadCenterBadgeLabel.frame = CGRectMake(iconSize - 10, 0, 16, 16);
    self.downloadCenterBadgeLabel.autoresizingMask = UIViewAutoresizingFlexibleRightMargin;
    self.downloadCenterBadgeLabel.hidden = YES;
    [self.downloadCenterButton addSubview:self.downloadCenterBadgeLabel];

    [self fetchRemoteVersionList];
    [NSNotificationCenter.defaultCenter addObserver:self
        selector:@selector(receiveNotification:)
        name:@"InstallModpack"
        object:nil];

    // ===== Download Center notification observers =====
    // Listen for DownloadTaskManager notifications when a new download task is registered or its progress changes:
    // 1. Update the Download Center button's visibility and progress percentage.
    // 2. Automatically show the Download Center dialog (unless the user closed it or another modal view is present).
    // This lets downloads such as mods, shaders, and resource packs report progress in one place.
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(handleDownloadTaskUpdate:)
                                                 name:DownloadTaskManagerDidUpdateTaskNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(handleDownloadTaskCompleted:)
                                                 name:DownloadTaskManagerTaskCompletedNotification
                                               object:nil];
    // Listen for the notification that the user closed the Download Center and set a flag to prevent it reopening automatically.
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(handleDownloadCenterDismissed)
                                                 name:@"DownloadCenterDidDismiss"
                                               object:nil];

    if ([BaseAuthenticator.current isKindOfClass:MicrosoftAuthenticator.class]) {
        // Perform token refreshment on startup
        [self setInteractionEnabled:NO forDownloading:NO];
        id callback = ^(id status, BOOL success) {
            status = [status description];
            if (status == nil) {
                [self setInteractionEnabled:YES forDownloading:NO];
            } else if (!success) {
                showDialog(localize(@"Error", nil), status);
            }
        };
        [BaseAuthenticator.current refreshTokenWithCallback:callback];
    }
}

- (BOOL)isVersionInstalled:(NSString *)versionId {
    NSString *localPath = [NSString stringWithFormat:@"%s/versions/%@", getenv("POJAV_GAME_DIR"), versionId];
    BOOL isDirectory;
    [NSFileManager.defaultManager fileExistsAtPath:localPath isDirectory:&isDirectory];
    return isDirectory;
}

- (void)fetchLocalVersionList {
    if (!localVersionList) {
        localVersionList = [NSMutableArray new];
    }
    [localVersionList removeAllObjects];

    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSString *versionPath = [NSString stringWithFormat:@"%s/versions/", getenv("POJAV_GAME_DIR")];
    NSArray *list = [fileManager contentsOfDirectoryAtPath:versionPath error:Nil];
    for (NSString *versionId in list) {
        if (![self isVersionInstalled:versionId]) continue;
        [localVersionList addObject:@{
            @"id": versionId,
            @"type": @"custom"
        }];
    }
}

- (void)fetchRemoteVersionList {
    self.buttonInstall.enabled = NO;
    remoteVersionList = @[
        @{@"id": @"latest-release", @"type": @"release"},
        @{@"id": @"latest-snapshot", @"type": @"snapshot"}
    ].mutableCopy;

    AFHTTPSessionManager *manager = [AFHTTPSessionManager manager];
    // Configure the response serializer to accept application/octet-stream.
    AFJSONResponseSerializer *serializer = [AFJSONResponseSerializer serializer];
    [serializer setAcceptableContentTypes:[NSSet setWithObjects:@"application/json", @"text/json", @"text/javascript", @"application/octet-stream", nil]];
    manager.responseSerializer = serializer;
    NSString *downloadSource = getPrefObject(@"general.download_source");
    NSString *versionManifestURL;
    
    if ([downloadSource isEqualToString:@"bmclapi"]) {
        versionManifestURL = @"https://bmclapi2.bangbang93.com/mc/game/version_manifest_v2.json";
    } else {
        versionManifestURL = @"https://piston-meta.mojang.com/mc/game/version_manifest_v2.json";
    }
    
    [manager GET:versionManifestURL parameters:nil headers:nil progress:nil success:^(NSURLSessionTask *task, NSDictionary *responseObject) {
        [remoteVersionList addObjectsFromArray:responseObject[@"versions"]];
        NSDebugLog(@"[VersionList] Got %d versions", remoteVersionList.count);
        setPrefObject(@"internal.latest_version", responseObject[@"latest"]);
        self.buttonInstall.enabled = YES;
    } failure:^(NSURLSessionTask *operation, NSError *error) {
        NSDebugLog(@"[VersionList] Warning: Unable to fetch version list: %@", error.localizedDescription);
        self.buttonInstall.enabled = YES;
    }];
}

- (void)fetchRemoteVersionListForce:(BOOL)force {
    // Call fetchRemoteVersionList directly; ignore the force parameter.
    [self fetchRemoteVersionList];
}

// Invoked by: startup, instance change event
- (void)reloadProfileList {
    // Reload local version list
    [self fetchLocalVersionList];
    // Reload launcher_profiles.json
    [PLProfiles updateCurrent];
    [self.versionPickerView reloadAllComponents];
    // Reload selected profile info
    self.profileSelectedAt = [PLProfiles.current.profiles.allKeys indexOfObject:PLProfiles.current.selectedProfileName];
    if (self.profileSelectedAt == -1) {
        // This instance has no profiles?
        return;
    }
    [self.versionPickerView selectRow:self.profileSelectedAt inComponent:0 animated:NO];
    [self pickerView:self.versionPickerView didSelectRow:self.profileSelectedAt inComponent:0];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    // Critical fix (KVO leak): remove the KVO observer as a fallback.
    // The normal flow removes it on download completion/error, but if the VC is released during a download (e.g. when leaving the launcher),
    // the observer would point to a deallocated object and cause a dangling-pointer crash.
    if (self.task && self.task.progress) {
        @try {
            [self.task.progress removeObserver:self
                                    forKeyPath:@"fractionCompleted"
                                       context:ProgressObserverContext];
        } @catch (NSException *e) {}
    }
}

#pragma mark - Download Center (modeled on the FCL/ZL2/HMCL download progress dialog)

/// Open the Download Center dialog.
/// Following FCL/ZL2/HMCL's download progress UI, present DownloadTasksViewController as a FormSheet
/// to show live progress for all tasks (Minecraft, mods, shaders, resource packs, data packs, worlds, modpacks).
/// All tasks registered through DownloadTaskManager appear here for unified progress tracking.
- (void)openDownloadCenter {
    // Return if the Download Center is already presented to avoid showing it twice.
    if (self.presentedDownloadCenterVC) {
        return;
    }

    // The user explicitly opened the Download Center, so reset the "user closed it" flag.
    self.userDismissedDownloadCenter = NO;

    DownloadTasksViewController *downloadCenterVC = [[DownloadTasksViewController alloc] init];
    downloadCenterVC.modalPresentationStyle = UIModalPresentationFormSheet;
    downloadCenterVC.preferredContentSize = CGSizeMake(500, 600);

    // Hold a weak reference to avoid a retain cycle.
    self.presentedDownloadCenterVC = downloadCenterVC;

    // Find the topmost view controller to present from.
    UIViewController *topVC = self;
    while (topVC.presentedViewController) {
        topVC = topVC.presentedViewController;
    }

    [topVC presentViewController:downloadCenterVC animated:YES completion:nil];
}

/// Handle download-task update notifications (progress changes, new task registration, etc.).
/// On notification, update only the Download Center button; do not automatically present the dialog.
///
/// redesign-download-ui Phase 3: individual task progress is handled by DownloadTaskManager,
/// which automatically presents the unified progress page (PLTaskProgressViewController) for DownloadTaskItems
/// registered with autoPresentDetail=YES. DownloadTasksViewController is now opened manually
/// through the Download Center button only.
- (void)handleDownloadTaskUpdate:(NSNotification *)notification {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self updateDownloadCenterButton];
    });
}

/// Handle download-task completion notifications.
- (void)handleDownloadTaskCompleted:(NSNotification *)notification {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self updateDownloadCenterButton];
    });
}

/// Handle the notification that the user manually closed the Download Center.
/// Set userDismissedDownloadCenter=YES to prevent subsequent task updates from reopening it automatically.
/// The user can reopen it by tapping the launcher's "Download Center" button (which resets this flag).
- (void)handleDownloadCenterDismissed {
    self.userDismissedDownloadCenter = YES;
    self.presentedDownloadCenterVC = nil;
}

/// 更新下载中心按钮的显示状态和进度百分比
- (void)updateDownloadCenterButton {
    DownloadTaskManager *manager = [DownloadTaskManager sharedManager];
    NSArray<DownloadTaskItem *> *allTasks = [manager allTasks];

    if (allTasks.count == 0) {
        self.downloadCenterButton.hidden = YES;
        self.downloadCenterBadgeLabel.hidden = YES;
        [self.downloadCenterActivityIndicator stopAnimating];
        return;
    }

    self.downloadCenterButton.hidden = NO;

    BOOL hasActive = NO;
    BOOL allCompleted = YES;
    double totalProgress = 0.0;
    NSInteger activeCount = 0;

    for (DownloadTaskItem *task in allTasks) {
        if (task.state == DownloadTaskStateDownloading || task.state == DownloadTaskStatePending) {
            hasActive = YES;
            allCompleted = NO;
            totalProgress += task.progress;
            activeCount++;
        } else if (task.state != DownloadTaskStateCompleted) {
            allCompleted = NO;
        }
    }

    // 进行中任务数徽标（redesign-download-ui Task 2.4）：有进行中任务时显示数量
    if (hasActive) {
        self.downloadCenterBadgeLabel.text = activeCount > 99 ? @"99+" : [NSString stringWithFormat:@"%ld", (long)activeCount];
        self.downloadCenterBadgeLabel.hidden = NO;
    } else {
        self.downloadCenterBadgeLabel.hidden = YES;
    }

    if (hasActive) {
        double avgProgress = activeCount > 0 ? totalProgress / activeCount : 0.0;
        NSInteger percent = (NSInteger)(avgProgress * 100.0 + 0.5);
        percent = MAX(0, MIN(100, percent));
        self.downloadCenterProgressLabel.text = [NSString stringWithFormat:@"%ld%%", (long)percent];
        [self.downloadCenterActivityIndicator startAnimating];
    } else if (allCompleted) {
        self.downloadCenterProgressLabel.text = localize(@"i18n_str_323", nil);
        [self.downloadCenterActivityIndicator stopAnimating];
    } else {
        self.downloadCenterProgressLabel.text = localize(@"i18n_str_128", nil);
        [self.downloadCenterActivityIndicator stopAnimating];
    }
}

#pragma mark - Options
- (void)enterCustomControls {
    CustomControlsViewController *vc = [[CustomControlsViewController alloc] init];
    vc.modalPresentationStyle = UIModalPresentationOverFullScreen;
    vc.setDefaultCtrl = ^(NSString *name){
        setPrefObject(@"control.default_ctrl", name);
    };
    vc.getDefaultCtrl = ^{
        return getPrefObject(@"control.default_ctrl");
    };
    [self presentViewController:vc animated:YES completion:nil];
}

- (void)enterModInstaller {
    UIDocumentPickerViewController *documentPicker = [[UIDocumentPickerViewController alloc]
        initForOpeningContentTypes:@[[UTType typeWithMIMEType:@"application/java-archive"]]
        asCopy:YES];
    documentPicker.delegate = self;
    documentPicker.modalPresentationStyle = UIModalPresentationFormSheet;
    [self presentViewController:documentPicker animated:YES completion:nil];
}



- (void)enterModInstallerWithPath:(NSString *)path hitEnterAfterWindowShown:(BOOL)hitEnter {
    // 关键修复（二次执行 jar 卡死）：iOS 进程内 JVM 只能创建一次
    // （gJVMUsedInProcess，第二次 JLI_Launch 会崩溃）。首次执行 jar 已在本进程
    // 创建过 JVM，再次进入 JavaGUIViewController 会黑屏卡死。因此在此处提前拦截，
    // 提示用户重启启动器，而不是进入注定失败的界面。
    if (JVMUsedInProcess()) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:localize(@"i18n_str_214", nil)
                                                                       message:localize(@"i18n_str_1143", nil)
                                                                preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:localize(@"i18n_str_216", nil) style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            [PLCrashView restartLauncher];
        }]];
        [alert addAction:[UIAlertAction actionWithTitle:localize(@"i18n_str_217", nil) style:UIAlertActionStyleCancel handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
        return;
    }

    JavaGUIViewController *vc = [[JavaGUIViewController alloc] init];
    vc.filepath = path;
    vc.hitEnterAfterWindowShown = hitEnter;
    if (!vc.requiredJavaVersion) {
        // 解析失败（manifest 缺失/主类非法）时明确提示，避免静默 return 让用户以为安装器已启动
        showDialog(localize(@"Error", nil),
            [NSString stringWithFormat:localize(@"i18n_str_221", nil), path.lastPathComponent]);
        return;
    }
    // execute_jar 路径：Caciocavallo17 jar 现已统一为 Java 17 编译版本，
    // Java 17/21 均可加载，不再需要强制提升 requiredJavaVersion 到 25。
    // - Java 8 JAR（如 OptiFine 安装器）走 Caciocavallo（非 17）路径，用 Java 8
    // - Java 17+ JAR 走 Caciocavallo17 路径，用 Java 17/21 即可
    // 与 JavaLauncher.m launchJar 分支保持一致。
    int requiredJavaVersion = vc.requiredJavaVersion;
    // 预检 execute_jar 标签的 JRE 是否已配置，避免 present 后才发现没 JRE 导致黑屏
    // 与 LauncherRightPanelViewController.enterModInstallerWithPath: 行为一致
    NSString *javaHome = getSelectedJavaHome(@"execute_jar", requiredJavaVersion);
    if (!javaHome) {
        showDialog(localize(@"Error", nil),
            [NSString stringWithFormat:localize(@"i18n_str_222", nil), requiredJavaVersion, requiredJavaVersion]);
        return;
    }
    [self invokeAfterJITEnabled:^{
        vc.modalPresentationStyle = UIModalPresentationFullScreen;
        NSLog(@"[ModInstaller] launching %@", vc.filepath);
        [self presentViewController:vc animated:YES completion:nil];
    }];
}

- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentAtURL:(NSURL *)url {
    // Handle normal jar file import
    [self enterModInstallerWithPath:url.path hitEnterAfterWindowShown:NO];
}

- (void)setInteractionEnabled:(BOOL)enabled forDownloading:(BOOL)downloading {
    for (UIControl *view in self.toolbar.subviews) {
        if ([view isKindOfClass:UIControl.class]) {
            view.alpha = enabled ? 1 : 0.2;
            view.enabled = enabled;
        }
    }
    if (downloading) {
        [self.buttonInstall setTitle:localize(enabled ? @"Play" : @"Details", nil) forState:UIControlStateNormal];
        self.buttonInstall.alpha = 1;
        self.buttonInstall.enabled = YES;
    }
    UIApplication.sharedApplication.idleTimerDisabled = !enabled;
}

- (void)launchMinecraft:(UIButton *)sender {
    if (!self.versionTextField.hasText) {
        [self.versionTextField becomeFirstResponder];
        return;
    }

    if (BaseAuthenticator.current == nil) {
        // Present the account selector if none selected
        UIViewController *view = [(UINavigationController *)self.splitViewController.viewControllers[0]
        viewControllers][0];
        [view performSelector:@selector(selectAccount:) withObject:sender];
        return;
    }

    // ★ [GAME-LANDSCAPE] 点启动（旧导航栏那条入口）⇒ 立刻锁横屏（幂等）。
    //   位置：账号校验已通过、进入启动流程之前；失败/取消分支会 Exit 恢复。
    AmeGameLandscapeLockEnter();

    [self setInteractionEnabled:NO forDownloading:YES];

    NSString *versionId = PLProfiles.current.profiles[self.versionTextField.text][@"lastVersionId"];
    NSDictionary *object = [remoteVersionList filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"(id == %@)", versionId]].firstObject;
    if (!object) {
        object = @{
            @"id": versionId,
            @"type": @"custom"
        };
    }

    self.task = [MinecraftResourceDownloadTask new];
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        __weak LauncherNavigationController *weakSelf = self;
        self.task.handleError = ^{
            dispatch_async(dispatch_get_main_queue(), ^{
                AmeGameLandscapeLockExit();   // ★ [GAME-LANDSCAPE] 启动/下载出错 ⇒ 恢复启动器方向（不把用户锁死在横屏）
                [weakSelf setInteractionEnabled:YES forDownloading:YES];
                // 关键修复（KVO 泄漏）：出错时必须先移除 KVO 再置 nil task，
                // 否则 task.progress 仍持有对 self 的 KVO 观察者，下次下载会重复添加。
                @try {
                    [weakSelf.task.progress removeObserver:weakSelf
                                                forKeyPath:@"fractionCompleted"
                                                   context:ProgressObserverContext];
                } @catch (NSException *e) {}
                weakSelf.task = nil;
            });
        };
        [self.task downloadVersion:object];
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.task.progress addObserver:self
                forKeyPath:@"fractionCompleted"
                options:NSKeyValueObservingOptionInitial
                context:ProgressObserverContext];

            // redesign-download-ui Phase 3 Task 3.4：启动下载的进度页已由任务内部
            // 阶段上报（MinecraftResourceDownloadTask.downloadVersion: 注册任务并
            // 置 autoPresentDetail=YES）自动弹出统一进度页，此处不再手动 present 旧进度 VC。
        });
    });
}

- (void)performInstallOrShowDetails:(UIButton *)sender {
    if (self.task) {
        // redesign-download-ui Phase 3 Task 3.4：Details 按钮改为打开统一进度页。
        // 任务由 MinecraftResourceDownloadTask 内部注册到 DownloadTaskManager，
        // 此处按 rawTask 反查 taskId 后呈现统一进度页。
        NSString *taskId = nil;
        for (DownloadTaskItem *item in [DownloadTaskManager sharedManager].allTasks) {
            if (item.rawTask == self.task) {
                taskId = item.taskId;
                break;
            }
        }
        if (taskId) {
            [PLTaskProgressViewController presentForTaskId:taskId];
        }
    } else {
        [self launchMinecraft:sender];
    }
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
    if (context != ProgressObserverContext) {
        [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
        return;
    }

    // Calculate download speed and ETA
    static CGFloat lastMsTime;
    static NSUInteger lastSecTime, lastCompletedUnitCount;
    NSProgress *progress = self.task.textProgress;
    struct timeval tv;
    gettimeofday(&tv, NULL); 
    NSInteger completedUnitCount = self.task.progress.totalUnitCount * self.task.progress.fractionCompleted;
    progress.completedUnitCount = completedUnitCount;
    if (lastSecTime < tv.tv_sec) {
        CGFloat currentTime = tv.tv_sec + tv.tv_usec / 1000000.0;
        NSInteger throughput = (completedUnitCount - lastCompletedUnitCount) / (currentTime - lastMsTime);
        progress.throughput = @(throughput);
        progress.estimatedTimeRemaining = @((progress.totalUnitCount - completedUnitCount) / throughput);
        lastCompletedUnitCount = completedUnitCount;
        lastSecTime = tv.tv_sec;
        lastMsTime = currentTime;
    }

    dispatch_async(dispatch_get_main_queue(), ^{
        if (!progress.finished) return;

        // 关键修复（KVO 泄漏）：下载完成时移除 KVO 观察者。
        // 之前不移除，导致每次下载都在 self.task.progress 上累积一个观察者，
        // 多次下载后 progress 变化会触发多次 observeValueForKeyPath，UI 异常。
        @try {
            [self.task.progress removeObserver:self
                                    forKeyPath:@"fractionCompleted"
                                       context:ProgressObserverContext];
        } @catch (NSException *e) {}
        if (self.task.metadata) {
            [self invokeAfterJITEnabled:^{
                UIKit_launchMinecraftSurfaceVC(self.view.window, self.task.metadata);
            }];
        } else {
            self.task = nil;
            AmeGameLandscapeLockExit();   // ★ [GAME-LANDSCAPE] 拿不到 metadata = 启动没成 ⇒ 恢复启动器方向
            [self setInteractionEnabled:YES forDownloading:YES];
            [self reloadProfileList];
        }
    });
}

- (void)receiveNotification:(NSNotification *)notification {
    if (![notification.name isEqualToString:@"InstallModpack"]) {
        return;
    }
    [self setInteractionEnabled:NO forDownloading:YES];
    self.task = [MinecraftResourceDownloadTask new];
    NSDictionary *userInfo = notification.userInfo;
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        __weak LauncherNavigationController *weakSelf = self;
        self.task.handleError = ^{
            dispatch_async(dispatch_get_main_queue(), ^{
                [weakSelf setInteractionEnabled:YES forDownloading:YES];
                // 关键修复（KVO 泄漏）：出错时移除 KVO，与 launchMinecraft 流程一致
                @try {
                    [weakSelf.task.progress removeObserver:weakSelf
                                                forKeyPath:@"fractionCompleted"
                                                   context:ProgressObserverContext];
                } @catch (NSException *e) {}
                weakSelf.task = nil;
            });
        };
        [self.task downloadModpackFromAPI:notification.object detail:userInfo[@"detail"] atIndex:[userInfo[@"index"] unsignedLongValue]];
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.task.progress addObserver:self
                forKeyPath:@"fractionCompleted"
                options:NSKeyValueObservingOptionInitial
                context:ProgressObserverContext];
        });
    });
}

- (void)invokeAfterJITEnabled:(void(^)(void))handler {
    // 注意：不要在此清空 localVersionList/remoteVersionList
    // 该方法既被 JAR 执行调用，也被正常启动游戏调用；清空会导致用户返回后版本列表为空、
    // buttonInstall 短暂不可用。版本列表的生命周期应由 reloadProfileList 统一管理。
    // ★ [JIT-FLOW] 原为 getEntitlementValue(@"jb.pmap_cs.custom_trust")：侧载模板
    //   预写了该 entitlement，会导致每个侧载包都走 apple-magnifier:// 静默失败分支。
    BOOL hasTrollStoreJIT = isTrollStoreInstall();
    NSLog(@"[JIT-FLOW] [NavCtrl] invokeAfterJITEnabled: isJITEnabled=%d trollstore=%d keepAttached=%d ppid=%d jb=%@",
          isJITEnabled(false), hasTrollStoreJIT, JIT26IsLikelyDebuggerKeepAttached(), getppid(), AMEJailbreakEnvSummary());

    // ★ [JB-ADAPT] 越狱环境：JIT 原生可用（无需调试器 attach，也不需要外部 JIT 工具）。
    //   先用**真能力自检**（本进程能否直接把匿名页置 RX；AMEJailbreakNativeJITReady 内部
    //   即 DeviceCanCreateRXMap）确认，就绪 ⇒ 直接启动，**不再等待/调起外部 JIT 工具**。
    //   不就绪 ⇒ 不加拦截，落回下方既有链路（TrollStore → 外部使能器 → stikjit://），
    //   不把"越狱但本 App 未开 JIT"的用户挡死。
    //   ⚠ 绝不因"检测到越狱"就放行：isJITEnabled 已不看 isJailbroken（[JB-ADAPT] 收紧）。
    if (!isJITEnabled(false) && AMEJailbreakNativeJITPathApplies()) {
        NSLog(@"[JB-ADAPT] [NavCtrl] jailbreak env=%@ -- attempting native JIT (skipping external enabler)",
              AMEJailbreakEnvSummary());
        if (AMEJailbreakNativeJITReady()) {
            NSLog(@"[JB-ADAPT] [NavCtrl] native JIT verified -- launching directly without any external JIT tool");
            handler();
            return;
        }
        NSLog(@"[JB-ADAPT] [NavCtrl] native JIT not ready -- falling back to configured enabler path");
    }

    if (isJITEnabled(false)) {
        [ALTServerManager.sharedManager stopDiscovering];
        // TXM 机型（议题 #133）：CS_DEBUGGED 置位只证明"曾经启用过"，调试器脱离后
        // 直接启动会在 launchJVM 的 brk #0x69 上闪退。探针全无时先重附加脚本。
        if (DeviceHasJITFlags(JIT_FLAG_FORCE_MIRRORED | JIT_FLAG_HAS_TXM) &&
            !JIT26IsLikelyDebuggerKeepAttached() &&
            !getPrefBool(@"debug.jit26_script_disable")) {
            NSLog(@"[JIT] [NavCtrl] CS_DEBUGGED set but no live JIT26 debugger (ppid=%d traced=%d exn=%d) -- re-attaching",
                  getppid(), JIT26DebuggerAttachedViaPtrace(), JIT26DebuggerViaExceptionPorts());
            [self jit_reattachJIT26ThenLaunch:handler];
            return;
        }
        // ★ [JIT-FLOW] #115/#129/#151：快路径（越狱 / entitlement / 粘滞 CS_DEBUGGED）是
        //   「能力声明」而非实测，直启会在 HotSpot 首个 brk #0x69 处闪退/卡死。
        //   Universal 设备上先做一次真能力自检；不过就改走重挂。
        if (DeviceNeedsDebugJITMapping() &&
            !getPrefBool(@"debug.jit26_script_disable") &&
            !AMEJITVerifyWritableJITRegion()) {
            NSLog(@"[JIT-FLOW] [NavCtrl] isJITEnabled=1 but self-check failed (entitlement/jailbreak/sticky CS_DEBUGGED) -- re-attaching instead of launching");
            [self jit_reattachJIT26ThenLaunch:handler];
            return;
        }
        // ★ [JIT-FLOW] 三态可见化：isJITEnabled=1 但探针全灭 ⇒ CS_DEBUGGED 粘滞、
        //   调试器很可能已脱离。非 (TXM+FORCE_MIRRORED) 机型不走上面的重挂闸门，
        //   直启会在首个 brk 处 EXC_BREAKPOINT。只打可辨识日志，不改行为。
        if (!JIT26IsLikelyDebuggerKeepAttached()) {
            NSLog(@"[JIT-FLOW] [NavCtrl] WARNING: isJITEnabled=1 but no live JIT26 debugger (ppid=%d traced=%d exn=%d); device gate not (TXM+FORCE_MIRRORED) -- launch may hit brk #0x69",
                  getppid(), JIT26DebuggerAttachedViaPtrace(), JIT26DebuggerViaExceptionPorts());
        }
        NSLog(@"[JIT] [NavCtrl] JIT enabled with live JIT26 debugger, launching directly");
        handler();
        return;
    } else if (hasTrollStoreJIT) {
        // ★ [JIT-FLOW] 原为 completionHandler:nil：apple-magnifier:// 无人处理时
        //   iOS 静默失败，UI 却照样弹「正在等待」。现在拿 urlOK + 明确提示。
        NSURL *jitURL = [NSURL URLWithString:[NSString stringWithFormat:@"apple-magnifier://enable-jit?bundle-id=%@", NSBundle.mainBundle.bundleIdentifier]];
        [UIApplication.sharedApplication openURL:jitURL options:@{} completionHandler:^(BOOL urlOK) {
            NSLog(@"[JIT-FLOW] [NavCtrl] openURL apple-magnifier:// (TrollStore) -> %d", urlOK);
            if (!urlOK) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    showDialog(localize(@"Error", nil), @"apple-magnifier:// 无响应（TrollStore / StikDebug 未处理该 URL Scheme？）。请在 TrollStore 设置里启用 URL Scheme，或改用其它 JIT 开启方式。\napple-magnifier:// was not handled (TrollStore URL Scheme disabled?). Enable it in TrollStore settings, or use another JIT enabler.");
                });
            }
        }];
        // Do not return, wait for TrollStore to enable JIT and jump back
    } else if (getPrefBool(@"debug.debug_skip_wait_jit")) {
        NSLog(@"Debug option skipped waiting for JIT. Java might not work.");
        handler();
        return;
    } else if (AMEJITConfiguredExternalEnablerIsActive()) {
        // ★ [JIT-ADAPT] 用户在设置里显式选了“非 stikjit”的 JIT 获取方式
        //   (StikDebug(stikdebug://)/StosDebug/JitStreamer/SideJITServer/SideStore/
        //    TrollStore/AltStore/Sideloadly/越狱/manual)。原 UI 路径完全忽略该偏好、
        //   永远走 stikjit:// ⇒ 只装了这些工具的用户“点了没反应”。这里按偏好调起或引导；
        //   判定「已开」仍只认下方统一的可验证自检(AMEJITWaitReadyVerified → 真拿可写 JIT 区)。
        AMEJITEnablerActionResult jitAdaptAct = AMEJITOpenConfiguredExternalEnabler();
        NSLog(@"[JIT-ADAPT] [NavCtrl] configured enabler=%@ action=%ld",
              AMEJITConfiguredEnablerKey(), (long)jitAdaptAct);
        if (jitAdaptAct == AMEJITEnablerActionResultMissingTool) {
            // 工具没装 / URL 无人处理 ⇒ 立刻给可辨识提示 + 安装建议，并走既有「重试/取消」
            // 出路（取消时的方向与交互恢复同超时路径），不再白等一整个超时窗口。
            showDialog(localize(@"jit.wait.abort.title", nil),
                       [NSString stringWithFormat:localize(@"jit.wait.missing.tool", nil),
                        AMEJITConfiguredEnablerDisplayName() ?: AMEJITConfiguredEnablerKey()]);
            [self jit_showTimeoutRetryAlert:handler];
            return;
        }
        // Opened / Manual ⇒ 落到下方统一「可验证等待 + 超时重试」；外部-attach 类
        // (AltStore/Sideloadly/SideJITServer/越狱/manual)顺带给一次「怎么做」的引导。
        NSString *jitAdaptGuideKey = AMEJITConfiguredEnablerGuidanceKey();
        if (jitAdaptGuideKey.length > 0) {
            showDialog(localize(@"jit.guide.title", nil), localize(jitAdaptGuideKey, nil));
        }
    } else if (@available(iOS 17.4, *)) {
        NSString *scriptDataString = @"";
        if (DeviceNeedsDebugJITMapping()) {
            NSData *scriptData = [NSData dataWithContentsOfFile:[NSBundle.mainBundle.bundlePath stringByAppendingPathComponent:@"UniversalJIT26.js"]];
            scriptDataString = [@"&script-data=" stringByAppendingString:[scriptData base64EncodedStringWithOptions:0]];
        }
        [UIApplication.sharedApplication openURL:[NSURL URLWithString:[NSString stringWithFormat:@"stikjit://enable-jit?bundle-id=%@&pid=%d%@", NSBundle.mainBundle.bundleIdentifier, getpid(), scriptDataString]] options:@{} completionHandler:^(BOOL urlOK) {
            NSLog(@"[JIT] [NavCtrl] openURL stikjit:// -> %d", urlOK);
            if (!urlOK) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    showDialog(localize(@"Error", nil), @"stikjit:// 无响应（未安装 StikDebug？）。请安装 StikDebug 后重试，或换用其它 JIT 开启方式。\nstikjit:// was not handled (StikDebug not installed?). Install StikDebug and retry.");
                });
            }
        }];
    } else {
        // Assuming 16.7-17.3.1. SideStore still lacks this URL scheme at the time of writing, so it only jumps to SideStore.
        [UIApplication.sharedApplication openURL:[NSURL URLWithString:[NSString stringWithFormat:@"sidestore://sidejit-enable?pid=%d", getpid()]] options:@{} completionHandler:nil];
    }

    UIAlertController* alert = [UIAlertController alertControllerWithTitle:localize(@"launcher.wait_jit.title", nil)
        message:hasTrollStoreJIT ? localize(@"launcher.wait_jit_trollstore.message", nil) : localize(@"launcher.wait_jit.message", nil)
        preferredStyle:UIAlertControllerStyleAlert];
/* TODO:
    UIAlertAction *cancel = [UIAlertAction actionWithTitle:localize(@"Cancel", nil) style:UIAlertActionStyleCancel handler:^{

    }];
    [alert addAction:cancel];
*/
    [self presentViewController:alert animated:YES completion:nil];

    // 后台任务断言：stikjit:// 切后台后防 iOS 立即挂起冻结等待循环。
    __block UIBackgroundTaskIdentifier jit_bgt = [UIApplication.sharedApplication beginBackgroundTaskWithName:@"jit-wait" expirationHandler:^{}];

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        // 有界等待 120s + 心跳日志，超时走重试弹窗。
        // ★ [JIT-FLOW] 等待条件由裸 isJITEnabled(false)（CS_DEBUGGED 粘滞 ⇒ attach
        //   即 <2s 假阳性）改为 AMEJITWaitReadyVerified()：Universal 路径下必须真的
        //   发 brk #0x69 拿到可写 JIT 区才算就绪，独立于外部工具的「完成」提示。
        BOOL ok = ame169_waitForJITCondition(^{ return AMEJITWaitReadyVerified(); }, 120.0, @"JIT-FLOW verify");
        // 自愈式派发：防后台楔死主队列吞掉续接块。
        ame185_dispatchToMainSelfHealing(^{
            if (jit_bgt != UIBackgroundTaskInvalid) {
                [UIApplication.sharedApplication endBackgroundTask:jit_bgt];
                jit_bgt = UIBackgroundTaskInvalid;
            }
            if (ok) {
                NSLog(@"[JIT-FLOW] [NavCtrl] verified before launch (writable JIT region=%p)",
                      AMEJITVerifiedRegionPtr());
                [alert dismissViewControllerAnimated:YES completion:nil];
                if (DeviceHasJITFlags(JIT_FLAG_FORCE_MIRRORED | JIT_FLAG_HAS_TXM) &&
                    !JIT26IsLikelyDebuggerKeepAttached() &&
                    !getPrefBool(@"debug.jit26_script_disable")) {
                    NSLog(@"[JIT] [NavCtrl] wait satisfied but JIT26 debugger is gone -- re-attaching before launch");
                    [self jit_reattachJIT26ThenLaunch:handler];
                } else {
                    handler();
                }
            } else {
                // ★ [JIT-FLOW] 外部工具可能已弹自己的「jit complete」，但独立自检
                //   （brk #0x69 -> 可写 JIT 区）未过 ⇒ 明确告知，不静默继续。
                NSLog(@"[JIT-FLOW] [NavCtrl] stikdebug reported complete but self-check failed (brk #0x69 not serviced) -- NOT launching");
                [alert dismissViewControllerAnimated:YES completion:nil];
                [self jit_showTimeoutRetryAlert:handler];
            }
        }, @"NavCtrl main wait");
    });
}

// JIT26 调试器重挂统一助手：stikjit://（附 UniversalJIT26.js）+ 前台等待 +
// 后台断言 + 有界等调试器存活，超时走重试弹窗。
- (void)jit_reattachJIT26ThenLaunch:(void(^)(void))handler {
    UIAlertController* alert = [UIAlertController alertControllerWithTitle:localize(@"launcher.wait_jit.title", nil)
        message:localize(@"launcher.wait_jit.message", nil)
        preferredStyle:UIAlertControllerStyleAlert];
    [self presentViewController:alert animated:YES completion:nil];

    __block UIBackgroundTaskIdentifier jit_bgt = [UIApplication.sharedApplication beginBackgroundTaskWithName:@"jit26-reattach" expirationHandler:^{}];

    void (^fireURL)(void) = ^{
        NSString *scriptDataString = @"";
        NSData *scriptData = [NSData dataWithContentsOfFile:[NSBundle.mainBundle.bundlePath stringByAppendingPathComponent:@"UniversalJIT26.js"]];
        if (scriptData) {
            scriptDataString = [@"&script-data=" stringByAppendingString:[scriptData base64EncodedStringWithOptions:0]];
        }
        [UIApplication.sharedApplication openURL:[NSURL URLWithString:[NSString stringWithFormat:@"stikjit://enable-jit?bundle-id=%@&pid=%d%@", NSBundle.mainBundle.bundleIdentifier, getpid(), scriptDataString]] options:@{} completionHandler:^(BOOL urlOK) {
            NSLog(@"[JIT] [NavCtrl] re-attach stikjit:// -> %d (script=%lu bytes)", urlOK, (unsigned long)scriptData.length);
        }];
    };

    if (UIApplication.sharedApplication.applicationState != UIApplicationStateActive) {
        __block id obs = nil;
        obs = [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidBecomeActiveNotification object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *n) {
            [[NSNotificationCenter defaultCenter] removeObserver:obs];
            obs = nil;
            fireURL();
        }];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(10 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            if (obs) {
                [[NSNotificationCenter defaultCenter] removeObserver:obs];
                obs = nil;
                fireURL();
            }
        });
    } else {
        fireURL();
    }

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        BOOL ok = ame169_waitForJITCondition(^{ return AMEJITWaitReadyVerified(); }, 120.0, @"JIT26 debugger attach");
        ame185_dispatchToMainSelfHealing(^{
            if (jit_bgt != UIBackgroundTaskInvalid) {
                [UIApplication.sharedApplication endBackgroundTask:jit_bgt];
                jit_bgt = UIBackgroundTaskInvalid;
            }
            [alert dismissViewControllerAnimated:YES completion:nil];
            if (ok) {
                if (handler) handler();
            } else {
                [self jit_showTimeoutRetryAlert:handler];
            }
        }, @"NavCtrl reattach wait");
    });
}

// JIT 等待超时后的出路弹窗：重试 = 重走一轮 invokeAfterJITEnabled。
- (void)jit_showTimeoutRetryAlert:(void(^)(void))handler {
    NSLog(@"[JIT] [NavCtrl] JIT wait timed out, showing retry alert");
    UIAlertController *retry = [UIAlertController alertControllerWithTitle:localize(@"launcher.wait_jit.title", nil)
                                                                   message:localize(@"jit.timeout_retry_msg", nil)
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [retry addAction:[UIAlertAction actionWithTitle:localize(@"resman.common.cancel", nil) style:UIAlertActionStyleCancel handler:^(UIAlertAction * _Nonnull action) {
        // ★ [GAME-LANDSCAPE] 取消启动 ⇒ 恢复启动器方向（与 launchMinecraft: 的 Enter 成对）
        AmeGameLandscapeLockExit();
    }]];
    [retry addAction:[UIAlertAction actionWithTitle:localize(@"jit.retry", nil) style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        [self invokeAfterJITEnabled:handler];
    }]];
    if (UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPad) {
        retry.popoverPresentationController.sourceView = self.view;
        retry.popoverPresentationController.sourceRect = CGRectMake(CGRectGetMidX(self.view.bounds), CGRectGetMidY(self.view.bounds), 0, 0);
    }
    [self presentViewController:retry animated:YES completion:nil];
}

#pragma mark - UIPopoverPresentationControllerDelegate
- (UIModalPresentationStyle)adaptivePresentationStyleForPresentationController:(UIPresentationController *)controller traitCollection:(UITraitCollection *)traitCollection {
    return UIModalPresentationNone;
}

#pragma mark - UIPickerView stuff
- (void)pickerView:(PLPickerView *)pickerView didSelectRow:(NSInteger)row inComponent:(NSInteger)component {
    self.profileSelectedAt = row;
    //((UIImageView *)self.versionTextField.leftView).image = [pickerView imageAtRow:row column:component];
    ((UIImageView *)self.versionTextField.leftView).image = [pickerView imageAtRow:row column:component];
    self.versionTextField.text = [self pickerView:pickerView titleForRow:row forComponent:component];
    PLProfiles.current.selectedProfileName = self.versionTextField.text;
}

- (NSInteger)numberOfComponentsInPickerView:(UIPickerView *)pickerView {
    return 1;
}

- (NSInteger)pickerView:(UIPickerView *)pickerView numberOfRowsInComponent:(NSInteger)component {
    return PLProfiles.current.profiles.count;
}

- (NSString *)pickerView:(UIPickerView *)pickerView titleForRow:(NSInteger)row forComponent:(NSInteger)component {
    return PLProfiles.current.profiles.allValues[row][@"name"];
}

- (void)pickerView:(UIPickerView *)pickerView enumerateImageView:(UIImageView *)imageView forRow:(NSInteger)row forComponent:(NSInteger)component {
    UIImage *fallbackImage = [[UIImage imageNamed:@"DefaultProfile"] _imageWithSize:CGSizeMake(40, 40)];
    NSString *urlString = PLProfiles.current.profiles.allValues[row][@"icon"];
    [imageView setImageWithURL:[NSURL URLWithString:urlString] placeholderImage:fallbackImage];
}

- (void)versionClosePicker {
    [self.versionTextField endEditing:YES];
    [self pickerView:self.versionPickerView didSelectRow:[self.versionPickerView selectedRowInComponent:0] inComponent:0];
}

#pragma mark - View controller UI mode

- (BOOL)prefersHomeIndicatorAutoHidden {
    return YES;
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    // 发送通知更新账户信息
    [[NSNotificationCenter defaultCenter] postNotificationName:@"UpdateAccountInfo" object:nil];
}

@end
