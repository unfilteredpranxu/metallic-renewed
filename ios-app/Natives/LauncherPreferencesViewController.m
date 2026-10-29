#import <Foundation/Foundation.h>

#import "DBNumberedSlider.h"
#import "HostManagerBridge.h"
#import "LauncherNavigationController.h"
#import "LauncherMenuViewController.h"
#import "LauncherPreferences.h"
#import "LauncherPreferencesViewController.h"
#import "LauncherNewsViewController.h"
#import "HomeTopNavView.h"
#import "LauncherPrefContCfgViewController.h"
#import "LauncherPrefManageJREViewController.h"
#import "UIKit+hook.h"

#import "config.h"
#import "ios_uikit_bridge.h"
#import "utils.h"

#import "ImageCropperViewController.h"
#import "CustomIconManager.h"
#import "BackgroundSettingsViewController.h"
// ★ [SETTINGS-VISIBLE] 界面风格(玻璃)单一真相源:主设置页直接读写 background_glass_* 键
#import "AMEGlassStyle.h"
#import "BackgroundManager.h"
#import "UIKit+GlassSurface.h"
#import "UpdateChecker.h"
#import "CurseForgeAPIKeyViewController.h"
#import "CustomControlsViewController.h"
#import "LauncherLanguageViewController.h"   // ★ [LANG-SWITCH] 语言选择子页
#import "AI/AIProviderConfigViewController.h"
#import "AI/AISessionListViewController.h"
#import "AI/AISystemPromptEditorViewController.h"
#import "AI/AiSettings.h"

// Footer text remains owned by the existing titleForFooter callback; only its layout changes.
@interface AMEPreferenceFooterView : UITableViewHeaderFooterView
@property(nonatomic, strong) UILabel *informationLabel;
@end
@implementation AMEPreferenceFooterView
- (instancetype)initWithReuseIdentifier:(NSString *)identifier {
    self = [super initWithReuseIdentifier:identifier];
    if (!self) return nil;
    self.backgroundView = [[UIView alloc] init];
    self.backgroundView.backgroundColor = UIColor.clearColor;
    UIView *surface = [[UIView alloc] init];
    surface.translatesAutoresizingMaskIntoConstraints = NO;
    surface.layer.cornerRadius = 12;
    surface.clipsToBounds = YES;
    [self.contentView addSubview:surface];
    [[BackgroundManager sharedManager] applyEffectToView:surface];
    self.informationLabel = [[UILabel alloc] init];
    self.informationLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.informationLabel.font = AmeUIFont(AmeUIFontRoleDescription);
    self.informationLabel.adjustsFontForContentSizeCategory = YES;
    self.informationLabel.textColor = AmeUISecondaryTextColor();
    self.informationLabel.numberOfLines = 0;
    [surface addSubview:self.informationLabel];
    UILayoutGuide *guide = self.contentView.layoutMarginsGuide;
    NSLayoutConstraint *width = [surface.widthAnchor constraintEqualToAnchor:guide.widthAnchor];
    width.priority = UILayoutPriorityDefaultHigh;
    [NSLayoutConstraint activateConstraints:@[
        [surface.leadingAnchor constraintGreaterThanOrEqualToAnchor:guide.leadingAnchor],
        [surface.trailingAnchor constraintLessThanOrEqualToAnchor:guide.trailingAnchor],
        [surface.centerXAnchor constraintEqualToAnchor:guide.centerXAnchor],
        [surface.widthAnchor constraintLessThanOrEqualToConstant:840], width,
        [surface.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:6],
        [surface.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-12],
        [self.informationLabel.topAnchor constraintEqualToAnchor:surface.topAnchor constant:10],
        [self.informationLabel.bottomAnchor constraintEqualToAnchor:surface.bottomAnchor constant:-10],
        [self.informationLabel.leadingAnchor constraintEqualToAnchor:surface.leadingAnchor constant:14],
        [self.informationLabel.trailingAnchor constraintEqualToAnchor:surface.trailingAnchor constant:-14]
    ]];
    return self;
}
@end

@interface LauncherPreferencesViewController()
@property(nonatomic) NSArray<NSString*> *rendererKeys, *rendererList;
@property(nonatomic) BOOL pickingMousePointer;
// 当前正在选择的颜色偏好键（general.text_color / general.card_color）
@property(nonatomic, copy, nullable) NSString *pickingColorPrefKey;
// 顶部 Hero 卡片视图（App 名 + 版本 + 设备信息），作为 tableHeaderView 的一部分
@property(nonatomic, strong, nullable) UIView *heroCard;
@property(nonatomic, strong) UIView *refinedHeader;
@property(nonatomic, strong) UISearchBar *refinedSearchBar;
- (void)layoutRefinedHeader;
@end

@implementation LauncherPreferencesViewController

- (BOOL)usesRefinedSettingsPresentation { return YES; }
- (BOOL)usesReferenceTableGeometry { return self.referenceContentMode; }

- (id)init {
    self = [super init];
    // 不设置 self.title，避免顶部导航栏出现"设置"标题黑条（参照 FCL 无 title 风格）
    return self;
}

- (NSString *)imageName {
    return @"MenuSettings";
}

- (void)openImagePicker {
    // 检查是否已经显示了图片选择器
    for (UIWindow *window in UIApplication.sharedApplication.windows) {
        for (UIWindowScene *scene in UIApplication.sharedApplication.connectedScenes) {
            if ([scene isKindOfClass:[UIWindowScene class]]) {
                for (UIWindow *window in scene.windows) {
                    for (UIView *view in window.subviews) {
                        if ([view isKindOfClass:[UIAlertController class]] || 
                            [view isKindOfClass:[UIImagePickerController class]]) {
                            // 如果已经显示了相关控制器，直接返回
                            return;
                        }
                    }
                }
            }
        }
    }
    
    UIImagePickerController *imagePicker = [[UIImagePickerController alloc] init];
    imagePicker.sourceType = UIImagePickerControllerSourceTypePhotoLibrary;
    imagePicker.delegate = self;
    
    // 延迟显示图片选择器，避免与UIAlertController冲突
    dispatch_async(dispatch_get_main_queue(), ^{
        [self presentViewController:imagePicker animated:YES completion:nil];
    });
}

- (void)openMousePointerPicker {
    self.pickingMousePointer = YES;
    UIImagePickerController *imagePicker = [[UIImagePickerController alloc] init];
    imagePicker.sourceType = UIImagePickerControllerSourceTypePhotoLibrary;
    imagePicker.delegate = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        [self presentViewController:imagePicker animated:YES completion:nil];
    });
}

#pragma mark - 自定义颜色选择（字体/卡片颜色）

- (void)openColorPickerForKey:(NSString *)fullKey title:(NSString *)title {
    if (@available(iOS 14.0, *)) {
        UIColorPickerViewController *picker = [[UIColorPickerViewController alloc] init];
        picker.title = title;
        picker.delegate = self;
        // 预选当前已保存的颜色
        NSString *hex = getPrefObject(fullKey);
        UIColor *current = [self colorFromHexString:hex];
        if (current) {
            picker.selectedColor = current;
        }
        self.pickingColorPrefKey = fullKey;
        dispatch_async(dispatch_get_main_queue(), ^{
            [self presentViewController:picker animated:YES completion:nil];
        });
    } else {
        [self showCustomIconError:localize(@"i18n_str_367", nil)];
    }
}

- (void)colorPickerViewControllerDidFinish:(UIColorPickerViewController *)viewController API_AVAILABLE(ios(14.0)) {
    NSString *key = self.pickingColorPrefKey;
    self.pickingColorPrefKey = nil;
    if (!key) return;
    UIColor *color = viewController.selectedColor;
    NSString *hex = [self hexStringFromColor:color];
    setPrefObject(key, hex);
    [[NSNotificationCenter defaultCenter] postNotificationName:@"LauncherAppearanceChanged" object:nil];
    [self.tableView reloadData];
}

- (nullable UIColor *)colorFromHexString:(id)hex {
    if (![hex isKindOfClass:[NSString class]] || [(NSString *)hex length] == 0) return nil;
    NSString *clean = [(NSString *)hex stringByReplacingOccurrencesOfString:@"#" withString:@""];
    unsigned int rgb = 0;
    NSScanner *scanner = [NSScanner scannerWithString:clean];
    if (![scanner scanHexInt:&rgb]) return nil;
    return [UIColor colorWithRed:((rgb >> 16) & 0xFF) / 255.0
                           green:((rgb >> 8) & 0xFF) / 255.0
                            blue:(rgb & 0xFF) / 255.0
                           alpha:1.0];
}

- (NSString *)hexStringFromColor:(UIColor *)color {
    CGFloat r = 0, g = 0, b = 0, a = 0;
    [color getRed:&r green:&g blue:&b alpha:&a];
    return [NSString stringWithFormat:@"%02X%02X%02X", (unsigned)(r * 255), (unsigned)(g * 255), (unsigned)(b * 255)];
}

#pragma mark - UIImagePickerControllerDelegate

- (void)imagePickerController:(UIImagePickerController *)picker didFinishPickingMediaWithInfo:(NSDictionary<UIImagePickerControllerInfoKey,id> *)info {
    [picker dismissViewControllerAnimated:YES completion:^{
        // 在图片选择器完全关闭后再处理图片
        dispatch_async(dispatch_get_main_queue(), ^{
            UIImage *selectedImage = info[UIImagePickerControllerOriginalImage];
            if (!selectedImage) {
                [self showCustomIconError:localize(@"i18n_str_368", nil)];
                return;
            }
            if (self.pickingMousePointer) {
                self.pickingMousePointer = NO;
                NSString *path = [NSString stringWithFormat:@"%s/controlmap/mouse_pointer.png", getenv("POJAV_HOME")];
                NSData *pngData = UIImagePNGRepresentation(selectedImage);
                [NSFileManager.defaultManager createDirectoryAtPath:[path stringByDeletingLastPathComponent] withIntermediateDirectories:YES attributes:nil error:nil];
                BOOL ok = [pngData writeToFile:path atomically:YES];
                if (ok) {
                    [NSNotificationCenter.defaultCenter postNotificationName:@"MousePointerUpdated" object:nil];
                    [self showSuccessMessage:localize(@"i18n_str_369", nil)];
                } else {
                    [self showCustomIconError:localize(@"i18n_str_370", nil)];
                }
                return;
            }
            // 显示处理中的提示
            [self showProcessingIndicator];
            
            // 检查图片是否为正方形
            if (selectedImage.size.width != selectedImage.size.height) {
                // 如果不是正方形，打开裁剪界面
                ImageCropperViewController *cropperVC = [[ImageCropperViewController alloc] initWithImage:selectedImage];
                __weak typeof(self) weakSelf = self;
                cropperVC.completionHandler = ^(UIImage * _Nullable croppedImage) {
                    if (croppedImage) {
                        // 保存裁剪后的图片
                        [[CustomIconManager sharedManager] saveCustomIcon:croppedImage withCompletion:^(BOOL success, NSError * _Nullable error) {
                            dispatch_async(dispatch_get_main_queue(), ^{
                                if (success) {
                                    [weakSelf showSuccessMessage:localize(@"i18n_str_371", nil)];
                                    // 更新应用图标选择器的显示
                                    [weakSelf.tableView reloadData];
                                } else {
                                    NSString *errorMessage = error.localizedDescription ?: localize(@"i18n_str_372", nil);
                                    [weakSelf showCustomIconError:errorMessage];
                                }
                            });
                        }];
                    } else {
                        dispatch_async(dispatch_get_main_queue(), ^{
                            [weakSelf showCustomIconError:localize(@"i18n_str_373", nil)];
                        });
                    }
                };
                [weakSelf.navigationController pushViewController:cropperVC animated:YES];
            } else {
                // 如果是正方形，直接保存
                [[CustomIconManager sharedManager] saveCustomIcon:selectedImage withCompletion:^(BOOL success, NSError * _Nullable error) {
                    dispatch_async(dispatch_get_main_queue(), ^{
                        if (success) {
                            [self showSuccessMessage:localize(@"i18n_str_371", nil)];
                            // 更新应用图标选择器的显示
                            [self.tableView reloadData];
                        } else {
                            NSString *errorMessage = error.localizedDescription ?: localize(@"i18n_str_372", nil);
                            [self showCustomIconError:errorMessage];
                        }
                    });
                }];
            }
        });
    }];
}

- (void)imagePickerControllerDidCancel:(UIImagePickerController *)picker {
    [picker dismissViewControllerAnimated:YES completion:^{
        dispatch_async(dispatch_get_main_queue(), ^{
            if (self.pickingMousePointer) {
                self.pickingMousePointer = NO;
            } else {
                [self showCustomIconError:localize(@"i18n_str_374", nil)];
            }
        });
    }];
}

#pragma mark - Custom Icon Helper Methods

- (void)showProcessingIndicator {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:localize(@"i18n_str_78", nil) message:localize(@"i18n_str_375", nil) preferredStyle:UIAlertControllerStyleAlert];
    [self presentViewController:alert animated:YES completion:nil];
    
    // 2秒后自动关闭提示
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [alert dismissViewControllerAnimated:YES completion:nil];
    });
}

- (void)showSuccessMessage:(NSString *)message {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:localize(@"i18n_str_80", nil) message:message preferredStyle:UIAlertControllerStyleAlert];
    UIAlertAction *okAction = [UIAlertAction actionWithTitle:localize(@"i18n_str_44", nil) style:UIAlertActionStyleDefault handler:nil];
    [alert addAction:okAction];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)showCustomIconError:(NSString *)errorMessage {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:localize(@"i18n_str_42", nil) message:errorMessage preferredStyle:UIAlertControllerStyleAlert];
    UIAlertAction *okAction = [UIAlertAction actionWithTitle:localize(@"i18n_str_44", nil) style:UIAlertActionStyleDefault handler:nil];
    [alert addAction:okAction];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)viewDidLoad
{
    // 彻底隐藏导航栏黑条（仅当作为非 modal 根页面且是栈中唯一 VC 时）
    // 尽早设置，避免导航栏闪烁
    if (self.navigationController &&
        self.navigationController.viewControllers.firstObject == self &&
        self.navigationController.presentingViewController == nil &&
        self.navigationController.viewControllers.count == 1) {
        self.navigationController.navigationBarHidden = YES;
    }

    // 启用设置项搜索（必须在 super viewDidLoad 之前设置，父类据此创建 searchController）
    self.searchEnabled = YES;

    self.getPreference = ^id(NSString *section, NSString *key){
        // ★ [LANG-SWITCH] 语言项：显示名用 NSLocale 现取；实际值存 NSUserDefaults
        // 自定义键 (ame_launcher_language)，与通用偏好存储解耦。跟随系统时展示当前系统语言名。
        if ([section isEqualToString:@"general"] && [key isEqualToString:@"launcher_language"]) {
            // ★ [I18N] 显示"实际生效的语言"（用户选择 ?? 系统最佳匹配 ?? en），与界面
            // 实际渲染同一事实源；选择"跟随系统"时再标注，杜绝"系统英文却说中文"。
            NSString *override = AmeLauncherPreferredLanguageOverride();
            // ★ [I18N-PARTIAL] 实际生效语言若是"部分翻译"语言（如日语），设置页这一处
            // 显示为「日本語（部分翻译）」——与语言选单同一事实源、同一标注。
            NSString *name = AmeLauncherDisplayNameAnnotatedForLanguageCode(AmeLauncherEffectiveLanguageCode());
            if (override.length == 0) {
                return [NSString stringWithFormat:@"%@（%@）", name,
                        localize(@"preference.lang.follow_system", @"Follow System")];
            }
            return name;
        }
        // AI 助手分区：直接与 AiSettings 打通（AiSettings 读写 NSUserDefaults，不走通用偏好存储）
        if ([section isEqualToString:@"ai"]) {
            if ([key isEqualToString:@"safety_mode"]) {
                switch ([[AiSettings sharedSettings] safetyMode]) {
                    case AiSafetyModeSafe:  return @"Read-Only Auto-Execute (Safe)";
                    case AiSafetyModeAsk:   return @"Confirm Each Write (Ask)";
                    case AiSafetyModeYOLO:  return @"Auto-Approve (YOLO)";
                }
            }
            if ([key isEqualToString:@"markdown_enabled"]) {
                return @([[AiSettings sharedSettings] markdownEnabled]);
            }
            return nil;
        }
        // ★ [SETTINGS-VISIBLE] 界面风格(玻璃):读 NSUserDefaults 的 background_glass_* 键(与背景设置子页同源)
        if ([section isEqualToString:@"general"] && [key isEqualToString:@"glass_style"]) {
            return localize([NSString stringWithFormat:@"preference.style.%@", AMEGlassStyleStringFromEnum(AMEGlassStyleConfigured())], nil);
        }
        if ([section isEqualToString:@"general"] && [key isEqualToString:@"glass_handdrawn"]) {
            return @(AMEGlassStyleHandDrawnOverlayEnabled());
        }
        NSString *keyFull = [NSString stringWithFormat:@"%@.%@", section, key];
        return getPrefObject(keyFull);
    };
    self.setPreference = ^(NSString *section, NSString *key, id value){
        // ★ [LANG-SWITCH] 语言项由子页 LauncherLanguageViewController 直接写 NSUserDefaults，
        // 这里拦截，避免误写入通用偏好存储（保持单一数据源）。
        if ([section isEqualToString:@"general"] && [key isEqualToString:@"launcher_language"]) {
            return;
        }
        // AI 助手分区：回写到 AiSettings
        if ([section isEqualToString:@"ai"]) {
            if ([key isEqualToString:@"safety_mode"]) {
                AiSafetyMode mode = AiSafetyModeSafe;
                if ([value isKindOfClass:[NSNumber class]]) {
                    mode = (AiSafetyMode)[value integerValue];
                } else if ([value isKindOfClass:[NSString class]]) {
                    NSString *s = value;
                    if ([s containsString:@"Confirm Each Write"]) {
                        mode = AiSafetyModeAsk;
                    } else if ([s containsString:@"Auto-Approve"]) {
                        mode = AiSafetyModeYOLO;
                    }
                }
                [[AiSettings sharedSettings] setSafetyMode:mode];
            } else if ([key isEqualToString:@"markdown_enabled"]) {
                [[AiSettings sharedSettings] setMarkdownEnabled:[value boolValue]];
            }
            return;
        }
        // ★ [SETTINGS-VISIBLE] 界面风格(玻璃):写 NSUserDefaults 的 background_glass_* 键 + 广播即时生效
        if ([section isEqualToString:@"general"] && [key isEqualToString:@"glass_style"]) {
            AMEGlassStyle s = AMEGlassStyleEnumFromString([value isKindOfClass:[NSString class]] ? value : nil);
            if (s == AMEGlassStyleLiquid && !AMEGlassStyleSystemSupportsLiquid()) {
                s = AMEGlassStyleNative;   // ★ iOS<26 强制原生
            }
            AMEGlassStyleSetConfigured(s);
            return;
        }
        if ([section isEqualToString:@"general"] && [key isEqualToString:@"glass_handdrawn"]) {
            BOOL on = [value boolValue];
            if (on && !AMEGlassStyleSystemSupportsLiquid()) { on = NO; }
            [BackgroundManager sharedManager].glassRimEnabled = on;   // 兼容既有全局强度收敛
            AMEGlassStyleSetHandDrawnOverlayEnabled(on);
            return;
        }
        // ★ [ISSUE-152] 游戏内悬浮球（小齿轮）显示开关：写 control.menu_button_visible，
        //   并广播 AmeGameMenuButtonVisibilityChanged ⇒ 游戏内已存在的 GameMenuOverlayView
        //   立刻按新值显隐（无需重启游戏/重进世界）。
        if ([section isEqualToString:@"control"] && [key isEqualToString:@"menu_button_visible"]) {
            setPrefObject(@"control.menu_button_visible", value);
            [[NSNotificationCenter defaultCenter] postNotificationName:@"AmeGameMenuButtonVisibilityChanged"
                                                                object:value];
            return;
        }
        NSString *keyFull = [NSString stringWithFormat:@"%@.%@", section, key];
        setPrefObject(keyFull, value);
    };
    
    self.hasDetail = YES;
    self.prefDetailVisible = self.navigationController == nil;
    
    self.prefSections = @[@"general", @"download", @"video", @"mobileglues", @"control", @"java", @"debug"];

    self.rendererKeys = getRendererKeys(NO);
    self.rendererList = getRendererNames(NO);
    
    // 检查是否在游戏中：如果当前可见视图控制器是 SurfaceViewController，则在游戏中
    BOOL(^whenNotInGame)() = ^BOOL(){
        UIViewController *visibleVC = currentVC();
        return ![visibleVC isKindOfClass:NSClassFromString(@"SurfaceViewController")];
    };

    // --- 定义弹窗显示的 Block，防止循环引用使用 weakSelf ---
    __weak typeof(self) weakSelf = self;
    void (^showTouchInfoAlert)(BOOL) = ^(BOOL enabled) {
        // 这个 Block 仅用于显示说明，不再负责逻辑判断
        dispatch_async(dispatch_get_main_queue(), ^{
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:localize(@"preference.popup.touch_info.title", nil)
                                                                           message:localize(@"preference.popup.touch_info.message", nil)
                                                                    preferredStyle:UIAlertControllerStyleAlert];
            
            [alert addAction:[UIAlertAction actionWithTitle:localize(@"OK", nil) style:UIAlertActionStyleDefault handler:nil]];
            
            [alert addAction:[UIAlertAction actionWithTitle:@"GitHub" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
                [[UIApplication sharedApplication] openURL:[NSURL URLWithString:@"https://github.com/TouchController/TouchController"] options:@{} completionHandler:nil];
            }]];
            
            [weakSelf presentViewController:alert animated:YES completion:nil];
        });
    };
    
    
    // -----------------------------------------------------------

    self.prefContents = @[
        @[
            // General settings
            @{@"icon": @"cube"},
            @{@"key": @"check_sha",
              @"hasDetail": @YES,
              @"icon": @"lock.shield",
              @"type": self.typeSwitch,
              @"enableCondition": whenNotInGame
            },
            // 旧"下载源"行已移除：general.download_source 已由启动时的
            // migrateDownloadSourcePreferences 迁移到下方"下载镜像策略"分组的 4 个分类键
            @{@"key": @"mod_mirror",
              @"hasDetail": @YES,
              @"icon": @"network",
              @"type": self.typePickField,
              @"enableCondition": whenNotInGame,
              @"pickKeys": @[
                  @"official",
                  @"mcim"
              ],
              @"pickList": @[
                  localize(@"preference.title.mod_mirror-official", nil),
                  localize(@"preference.title.mod_mirror-mcim", nil)
              ]
            },
            // ★ [UI-LAYOUT] 「UI 布局」切换入口已移除（群主建议）：布局改为按设备自动判定
            //   （iPhone ⇒ 标准, iPad ⇒ 卡片, 见 SceneDelegate ameMakeLauncherHomeViewController）。
            //   原 ui_layout pick 字段（vs/card）在这里 —— 删掉后用户无法再把 iPhone 设成 card
            //   而卡进主页错乱态。旧 general.ui_layout 值仍被忽略（兼容读取见 SceneDelegate）。
            @{@"key": @"ui_theme",
              @"title": localize(@"i18n_str_379", nil),
              @"hasDetail": @YES,
              @"icon": @"circle.lefthalf.filled",
              @"type": self.typePickField,
              @"enableCondition": whenNotInGame,
              @"pickKeys": @[
                  @"dark",
                  @"light",
                  @"auto"
              ],
              @"pickList": @[
                  localize(@"i18n_str_380", nil),
                  localize(@"i18n_str_381", nil),
                  localize(@"i18n_str_382", nil)
              ],
              @"action": ^(NSString *value){
                  // 实时应用主题，发通知由 SceneDelegate 处理。
                  // 不调用 loadPreferences(YES) 等会重置账号偏好的操作，
                  // 仅设置 window.overrideUserInterfaceStyle，账号数据不受影响。
                  [[NSNotificationCenter defaultCenter] postNotificationName:@"UIThemeChanged" object:value];
              }
            },
            // ★ [SETTINGS-VISIBLE] 界面风格(玻璃):主设置页可见的一级入口 —— 用户抱怨「设置里看不到开关」,
            //   原先只在「启动器背景」子页里 ⇒ 这里补一行,直接可改、即时生效(写入 NSUserDefaults 的
            //   background_glass_style / background_glass_handdrawn,与子页同源)。iOS<26 时液态玻璃段不可选。
            @{@"key": @"glass_style",
              @"hasDetail": @NO,
              @"icon": @"circle.lefthalf.filled",
              @"type": self.typePickField,
              @"enableCondition": whenNotInGame,
              @"pickKeys": @[
                  @"auto",
                  @"native",
                  @"liquid"
              ],
              @"pickList": @[
                  localize(@"preference.style.auto", nil),
                  localize(@"preference.style.native", nil),
                  localize(@"preference.style.liquid", nil)
              ]
            },
            @{@"key": @"glass_handdrawn",
              @"hasDetail": @NO,
              @"icon": @"sparkles",
              @"type": self.typeSwitch,
              @"enableCondition": ^BOOL(){ return whenNotInGame() && AMEGlassStyleSystemSupportsLiquid(); }
            },
            // ★ [I18N] 启动器界面语言：跟随系统 + 白名单语言（AmeLauncherSupportedLanguageCodes）。
            // 不写 title（让父类在生成 cell 时按 preference.title.<key> 现取 localize，
            // 切换语言后 reloadData 即可即时刷新文案）；实际值由子页直接写
            // NSUserDefaults 自定义键 (ame_launcher_language)，不走通用偏好存储。
            @{@"key": @"launcher_language",
              @"hasDetail": @NO,
              @"icon": @"globe",
              @"type": self.typeChildPane,
              @"enableCondition": whenNotInGame,
              @"canDismissWithSwipe": @YES,
              @"class": LauncherLanguageViewController.class
            },
            @{@"key": @"custom_accent_color",
              @"title": localize(@"i18n_str_383", nil),
              @"hasDetail": @YES,
              @"icon": @"paintpalette.fill",
              @"type": self.typeButton,
              @"enableCondition": whenNotInGame,
              @"action": ^void(){
                  [self openColorPickerForKey:@"general.accent_color" title:localize(@"i18n_str_383", nil)];
              }
            },
            @{@"key": @"custom_text_color",
              @"title": localize(@"i18n_str_384", nil),
              @"hasDetail": @YES,
              @"icon": @"textformat",
              @"type": self.typeButton,
              @"enableCondition": whenNotInGame,
              @"action": ^void(){
                  [self openColorPickerForKey:@"general.text_color" title:localize(@"i18n_str_384", nil)];
              }
            },
            #if 0
            @{@"key": @"custom_card_color",
              @"title": localize(@"i18n_str_385", nil),
              @"hasDetail": @YES,
              @"icon": @"rectangle.fill",
              @"type": self.typeButton,
              @"enableCondition": whenNotInGame,
              @"action": ^void(){
                  [self openColorPickerForKey:@"general.card_color" title:localize(@"i18n_str_385", nil)];
              }
            },
            #endif
            @{@"key": @"reset_appearance_colors",
            #if 0
              @"title": localize(@"i18n_str_386", nil),
              #endif
              @"title": @"Reset Theme/Font Colors",
              @"icon": @"arrow.counterclockwise",
              @"type": self.typeButton,
              @"enableCondition": whenNotInGame,
              @"action": ^void(){
                  setPrefObject(@"general.accent_color", @"");
                  setPrefObject(@"general.text_color", @"");
                  setPrefObject(@"general.card_color", @"");
                  [[NSNotificationCenter defaultCenter] postNotificationName:@"LauncherAppearanceChanged" object:nil];
                  [self.tableView reloadData];
              }
            },
            @{@"key": @"multi_threaded",
              @"title": localize(@"i18n_str_387", nil),
              @"hasDetail": @YES,
              @"icon": @"bolt.fill",
              @"type": self.typeSwitch,
              @"enableCondition": whenNotInGame
            },
            @{@"key": @"curseforge_api_key",
              @"hasDetail": @YES,
              @"icon": @"key.fill",
              @"type": self.typeButton,
              @"enableCondition": whenNotInGame,
              @"action": ^void(){
                  CurseForgeAPIKeyViewController *vc = [[CurseForgeAPIKeyViewController alloc] init];
                  UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:vc];
                  nav.modalPresentationStyle = UIModalPresentationFormSheet;
                  [self presentViewController:nav animated:YES completion:nil];
              }
            },
            @{@"key": @"cosmetica",
              @"hasDetail": @YES,
              @"icon": @"eyeglasses",
              @"type": self.typeSwitch,
              @"enableCondition": whenNotInGame
            },
            @{@"key": @"debug_logging",
              @"hasDetail": @YES,
              @"icon": @"doc.badge.gearshape",
              @"type": self.typeSwitch,
              @"action": ^(BOOL enabled){
                  debugLogEnabled = enabled;
                  NSLog(@"[Debugging] Debug log enabled: %@", enabled ? @"YES" : @"NO");
              }
            },
            @{@"key": @"appicon",
              @"hasDetail": @YES,
              @"icon": @"paintbrush",
              @"type": self.typePickField,
              @"enableCondition": whenNotInGame,
              @"action": ^void(NSString *iconName) {
                  if ([iconName isEqualToString:@"AppIcon-Light"]) {
                      iconName = nil;
                      [[CustomIconManager sharedManager] removeCustomIcon];
                  } else if ([iconName isEqualToString:@"CustomIcon"]) {
                      if (![[CustomIconManager sharedManager] hasCustomIcon]) {
                          dispatch_async(dispatch_get_main_queue(), ^{
                              UIAlertController *alert = [UIAlertController alertControllerWithTitle:localize(@"i18n_str_388", nil) message:localize(@"i18n_str_389", nil) preferredStyle:UIAlertControllerStyleAlert];
                              UIAlertAction *okAction = [UIAlertAction actionWithTitle:localize(@"i18n_str_44", nil) style:UIAlertActionStyleDefault handler:nil];
                              [alert addAction:okAction];
                              [self presentViewController:alert animated:YES completion:nil];
                          });
                          dispatch_async(dispatch_get_main_queue(), ^{
                              [self.tableView reloadData];
                          });
                          return;
                      }
                      [[CustomIconManager sharedManager] setCustomIconWithCompletion:^(BOOL success, NSError * _Nullable error) {
                          if (!success) {
                              dispatch_async(dispatch_get_main_queue(), ^{
                                  NSLog(@"Error in appicon: %@", error);
                                  showDialog(localize(@"Error", nil), error.localizedDescription);
                              });
                          }
                      }];
                      return;
                  }
                  [UIApplication.sharedApplication setAlternateIconName:iconName completionHandler:^(NSError * _Nullable error) {
                      if (error == nil) return;
                      NSLog(@"Error in appicon: %@", error);
                      showDialog(localize(@"Error", nil), error.localizedDescription);
                  }];
              },
              @"pickKeys": @[
                  @"AppIcon-Light",
                  @"CustomIcon"
              ],
              @"pickList": @[
                  localize(@"preference.title.appicon-default", nil),
                  localize(@"preference.title.appicon-custom", nil)
              ]
            },
            @{@"key": @"custom_appicon",
              @"hasDetail": @YES,
              @"icon": @"photo",
              @"type": self.typeButton,
              @"enableCondition": ^BOOL(){
                  return NO;
              },
              @"action": ^void(){
                  [self openImagePicker];
              }
            },
            @{@"key": @"launcher_background",
              @"hasDetail": @YES,
              @"icon": @"photo.fill.on.rectangle.fill",
              @"type": self.typeButton,
              @"enableCondition": whenNotInGame,
              @"action": ^void(){
                  BackgroundSettingsViewController *bgVC = [[BackgroundSettingsViewController alloc] init];
                  UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:bgVC];
                  nav.modalPresentationStyle = UIModalPresentationFormSheet;
                  [self presentViewController:nav animated:YES completion:nil];
              }
            },
            @{@"key": @"hidden_sidebar",
              @"hasDetail": @YES,
              @"icon": @"sidebar.leading",
              @"type": self.typeSwitch,
              @"enableCondition": whenNotInGame
            },
            // ★ [VER-ISOLATE-PCL] 默认版本隔离（对齐 PCL-CE「默认实例隔离」LaunchArgumentIndieV2）：
            // 关闭（默认）= 实例内各版本共享 mods/config/saves（现状）；
            // 开启 = 新版本/未显式设置的版本默认隔离到 <实例根>/versions/<版本 id>/。
            // 单版本可在「编辑配置」页用 versionIsolation 开关覆盖（对应 PCL 的实例设置页）。
            @{@"key": @"version_isolation",
              @"hasDetail": @YES,
              @"icon": @"square.on.square.dashed",
              @"type": self.typeSwitch,
              @"enableCondition": whenNotInGame
            },
            @{@"key": @"announcement_preview_level",
              @"hasDetail": @YES,
              @"icon": @"megaphone",
              @"type": self.typePickField,
              @"enableCondition": whenNotInGame,
              @"pickKeys": @[
                  @"full",
                  @"summary",
                  @"title_only"
              ],
              @"pickList": @[
                  localize(@"i18n_str_390", nil),
                  localize(@"i18n_str_391", nil),
                  localize(@"i18n_str_392", nil)
              ]
            },
            @{@"key": @"reset_warnings",
              @"icon": @"exclamationmark.triangle",
              @"type": self.typeButton,
              @"enableCondition": whenNotInGame,
              @"action": ^void(){
                  resetWarnings();
              }
            },
            @{@"key": @"reset_settings",
              @"icon": @"trash",
              @"type": self.typeButton,
              @"enableCondition": whenNotInGame,
              @"requestReload": @YES,
              @"showConfirmPrompt": @YES,
              @"destructive": @YES,
              @"action": ^void(){
                  loadPreferences(YES);
                  [self.tableView reloadData];
              }
            },
            @{@"key": @"memory_limit_help",
              @"hasDetail": @YES,
              @"icon": @"memorychip",
              @"type": self.typeButton,
              @"enableCondition": whenNotInGame,
              @"action": ^void(){
                  [self showMemoryLimitHelp];
              }
            },
            @{@"key": @"erase_demo_data",
              @"icon": @"trash",
              @"type": self.typeButton,
              @"enableCondition": ^BOOL(){
                  NSString *demoPath = [NSString stringWithFormat:@"%s/.demo", getenv("POJAV_HOME")];
                  int count = [NSFileManager.defaultManager contentsOfDirectoryAtPath:demoPath error:nil].count;
                  return whenNotInGame() && count > 0;
              },
              @"showConfirmPrompt": @YES,
              @"destructive": @YES,
              @"action": ^void(){
                  NSString *demoPath = [NSString stringWithFormat:@"%s/.demo", getenv("POJAV_HOME")];
                  NSError *error;
                  if([NSFileManager.defaultManager removeItemAtPath:demoPath error:&error]) {
                      [NSFileManager.defaultManager createDirectoryAtPath:demoPath
                                              withIntermediateDirectories:YES attributes:nil error:nil];
                      [NSFileManager.defaultManager changeCurrentDirectoryPath:demoPath];
                      if (getenv("DEMO_LOCK")) {
                          [(LauncherNavigationController *)self.navigationController fetchLocalVersionList];
                      }
                  } else {
                      NSLog(@"Error in erase_demo_data: %@", error);
                      showDialog(localize(@"Error", nil), error.localizedDescription);
                  }
              }
            },
            @{@"key": @"check_update",
              @"hasDetail": @YES,
              @"icon": @"arrow.triangle.2.circlepath",
              @"type": self.typeButton,
              @"action": ^void(){
                  [self checkForUpdateFromSettings];
              }
            },
            @{@"key": @"auto_check_update",
              @"hasDetail": @YES,
              @"icon": @"arrow.triangle.2.circlepath",
              @"type": self.typeSwitch
            }
        ], @[
            // Download mirror policy settings（分类镜像策略，由 PLMirrorCenter 统一读取）
            @{@"icon": @"arrow.down.circle"},
            @{@"key": @"fileSource",
              @"hasDetail": @YES,
              @"icon": @"arrow.down.circle",
              @"type": self.typePickField,
              @"enableCondition": whenNotInGame,
              @"pickKeys": @[
                  @"auto",
                  @"official_first",
                  @"mirror_first"
              ],
              @"pickList": @[
                  localize(@"preference.title.mirror_policy-auto", nil),
                  localize(@"preference.title.mirror_policy-official_first", nil),
                  localize(@"preference.title.mirror_policy-mirror_first", nil)
              ]
            },
            @{@"key": @"assetSearchSource",
              @"hasDetail": @YES,
              @"icon": @"magnifyingglass",
              @"type": self.typePickField,
              @"enableCondition": whenNotInGame,
              @"pickKeys": @[
                  @"auto",
                  @"official_first",
                  @"mirror_first"
              ],
              @"pickList": @[
                  localize(@"preference.title.mirror_policy-auto", nil),
                  localize(@"preference.title.mirror_policy-official_first", nil),
                  localize(@"preference.title.mirror_policy-mirror_first", nil)
              ]
            },
            @{@"key": @"assetDownloadSource",
              @"hasDetail": @YES,
              @"icon": @"square.and.arrow.down",
              @"type": self.typePickField,
              @"enableCondition": whenNotInGame,
              @"pickKeys": @[
                  @"auto",
                  @"official_first",
                  @"mirror_first"
              ],
              @"pickList": @[
                  localize(@"preference.title.mirror_policy-auto", nil),
                  localize(@"preference.title.mirror_policy-official_first", nil),
                  localize(@"preference.title.mirror_policy-mirror_first", nil)
              ]
            },
            @{@"key": @"modLoaderSource",
              @"hasDetail": @YES,
              @"icon": @"wrench.and.screwdriver",
              @"type": self.typePickField,
              @"enableCondition": whenNotInGame,
              @"pickKeys": @[
                  @"auto",
                  @"official_first",
                  @"mirror_first"
              ],
              @"pickList": @[
                  localize(@"preference.title.mirror_policy-auto", nil),
                  localize(@"preference.title.mirror_policy-official_first", nil),
                  localize(@"preference.title.mirror_policy-mirror_first", nil)
              ]
            }
        ], @[
            // Video and renderer settings
            @{@"icon": @"video"},
            @{@"key": @"renderer",
              @"hasDetail": @YES,
              @"icon": @"cpu",
              @"type": self.typePickField,
              @"enableCondition": whenNotInGame,
              @"pickKeys": self.rendererKeys,
              @"pickList": self.rendererList
            },
            // SimpleFPEWrapper 固定管线 (GL 1.x) 仿真层，仅叠加在 GLES 后端之上
            // （MobileGlues / MobileGL-gles）；gl4es、zink、Vulkan 等不适用。
            @{@"key": @"sfpew_overlay",
              @"hasDetail": @YES,
              @"icon": @"square.stack.3d.down.right",
              @"type": self.typeSwitch,
              @"enableCondition": whenNotInGame
            },
            @{@"key": @"resolution",
              @"hasDetail": @YES,
              @"icon": @"viewfinder",
              @"type": self.typeSlider,
              @"min": @(25),
              @"max": @(150)
            },
            // 帧率限制选项已移除：CADisplayLink 始终采用 30-120Hz 自适应范围，
            // 由屏幕硬件能力决定实际帧率（60Hz 设备仍为 60，120Hz ProMotion 设备可达 120）。
            // 不再提供"最大帧率限制 60FPS"开关，避免用户误关闭导致帧率被人为锁死。
            // 解锁帧率（关闭垂直同步）：三层联动关闭 VSync，让游戏帧率可超过屏幕刷新率。
            // 不限制 ProMotion 设备：60Hz 设备同样会被 VSync 锁在 60，也需要解锁。
            @{@"key": @"disable_game_vsync",
              @"hasDetail": @YES,
              @"icon": @"hare",
              @"type": self.typeSwitch,
              @"enableCondition": whenNotInGame
            },
            @{@"key": @"performance_hud",
              @"hasDetail": @YES,
              @"icon": @"waveform.path.ecg",
              @"type": self.typeSwitch,
              @"enableCondition": ^BOOL(){
                  return [CAMetalLayer instancesRespondToSelector:@selector(developerHUDProperties)];
              }
            },
            @{@"key": @"fullscreen_airplay",
              @"hasDetail": @YES,
              @"icon": @"airplayvideo",
              @"type": self.typeSwitch,
              @"action": ^(BOOL enabled){
                  if (self.navigationController != nil) return;
                  if (UIApplication.sharedApplication.connectedScenes.count < 2) return;
                  if (enabled) {
                      [self.presentingViewController performSelector:@selector(switchToExternalDisplay)];
                  } else {
                      [self.presentingViewController performSelector:@selector(switchToInternalDisplay)];
                  }
              }
            },
            @{@"key": @"silence_other_audio",
              @"hasDetail": @YES,
              @"icon": @"speaker.slash",
              @"type": self.typeSwitch
            },
            @{@"key": @"silence_with_switch",
              @"hasDetail": @YES,
              @"icon": @"speaker.zzz",
              @"type": self.typeSwitch
            },
            @{@"key": @"allow_microphone",
              @"hasDetail": @YES,
              @"icon": @"mic",
              @"type": self.typeSwitch
            },
        ], @[
            // MobileGlues settings
            // 当渲染器选择为 MobileGlues 或 Vulkan 时，init_loadMobileGluesConfig()
            // 写入的 <POJAV_HOME>/MG/config.json 会被 MobileGlues 读取并生效。
            // Vulkan 渲染器的 OpenGL 回退使用 MobileGlues（对齐 Ynnyny 仓库）。
            // Auto 渲染器会被解析为 ANGLE，不会加载 MobileGlues。
            @{@"icon": @"cpu"},
            @{@"key": @"enable_angle",
              @"hasDetail": @YES,
              @"icon": @"triangle",
              @"type": self.typeSwitch,
              @"enableCondition": whenNotInGame
            },
            @{@"key": @"enable_no_error",
              @"hasDetail": @YES,
              @"icon": @"exclamationmark.triangle",
              @"type": self.typePickField,
              @"enableCondition": whenNotInGame,
              @"pickKeys": @[@"0", @"1", @"2"],
              @"pickList": @[
                  localize(@"preference.title.mg_enable_no_error-0", nil),
                  localize(@"preference.title.mg_enable_no_error-1", nil),
                  localize(@"preference.title.mg_enable_no_error-2", nil)
              ]
            },
            @{@"key": @"enable_ext_timer_query",
              @"hasDetail": @YES,
              @"icon": @"clock",
              @"type": self.typeSwitch,
              @"enableCondition": whenNotInGame
            },
            @{@"key": @"enable_ext_compute_shader",
              @"hasDetail": @YES,
              @"icon": @"cube.transparent",
              @"type": self.typeSwitch,
              @"enableCondition": whenNotInGame
            },
            @{@"key": @"enable_ext_direct_state_access",
              @"hasDetail": @YES,
              @"icon": @"directconnect",
              @"type": self.typeSwitch,
              @"enableCondition": whenNotInGame
            },
            @{@"key": @"max_glsl_cache_size",
              @"hasDetail": @YES,
              @"icon": @"memorychip",
              @"type": self.typeSlider,
              @"min": @(0),
              @"max": @(256),
              @"enableCondition": whenNotInGame
            },
            @{@"key": @"multidraw_mode",
              @"hasDetail": @YES,
              @"icon": @"square.stack.3d.down.dottedline",
              @"type": self.typePickField,
              @"enableCondition": whenNotInGame,
              @"pickKeys": @[@"0", @"1", @"2"],
              @"pickList": @[
                  localize(@"preference.title.mg_multidraw_mode-0", nil),
                  localize(@"preference.title.mg_multidraw_mode-1", nil),
                  localize(@"preference.title.mg_multidraw_mode-2", nil)
              ]
            },
            @{@"key": @"angle_depth_clear_fix_mode",
              @"hasDetail": @YES,
              @"icon": @"rectangle.3.group",
              @"type": self.typeSwitch,
              @"enableCondition": whenNotInGame
            },
            @{@"key": @"custom_gl_version",
              @"hasDetail": @YES,
              @"icon": @"number",
              @"type": self.typePickField,
              @"enableCondition": whenNotInGame,
              @"pickKeys": @[@"0", @"4.0", @"4.1", @"4.2", @"4.3", @"4.4", @"4.5", @"4.6"],
              @"pickList": @[
                  localize(@"preference.title.mg_custom_gl_version-0", nil),
                  localize(@"preference.title.mg_custom_gl_version-4.0", nil),
                  localize(@"preference.title.mg_custom_gl_version-4.1", nil),
                  localize(@"preference.title.mg_custom_gl_version-4.2", nil),
                  localize(@"preference.title.mg_custom_gl_version-4.3", nil),
                  localize(@"preference.title.mg_custom_gl_version-4.4", nil),
                  localize(@"preference.title.mg_custom_gl_version-4.5", nil),
                  localize(@"preference.title.mg_custom_gl_version-4.6", nil)
              ]
            },
            @{@"key": @"fsr1_setting",
              @"hasDetail": @YES,
              @"icon": @"square.grid.3x2",
              @"type": self.typePickField,
              @"enableCondition": whenNotInGame,
              @"pickKeys": @[@"0", @"1", @"2", @"3"],
              @"pickList": @[
                  localize(@"preference.title.mg_fsr1_setting-0", nil),
                  localize(@"preference.title.mg_fsr1_setting-1", nil),
                  localize(@"preference.title.mg_fsr1_setting-2", nil),
                  localize(@"preference.title.mg_fsr1_setting-3", nil)
              ]
            },
        ], @[
            // Control settings
            @{@"icon": @"gamecontroller"},
            
            // --- [修改] TouchController 模组支持 ---
            @{@"key": @"mod_touch_enable",
              @"icon": @"hand.point.up.left", // SF Symbols 图标
              @"hasDetail": @YES,
              @"type": self.typeChildPane,
              @"enableCondition": whenNotInGame,
              @"canDismissWithSwipe": @NO,
              @"class": NSClassFromString(@"TouchControllerPreferencesViewController")
            },
            // ------------------------------------------

            // --- [新增] 键位调整（从左侧菜单移到设置中） ---
            @{@"key": @"custom_controls",
              @"icon": @"gamecontroller.fill",
              @"hasDetail": @YES,
              @"type": self.typeChildPane,
              @"enableCondition": whenNotInGame,
              @"canDismissWithSwipe": @NO,
              @"class": CustomControlsViewController.class
            },
            // ---------------------------------------------

            @{@"key": @"default_gamepad_ctrl",
                @"icon": @"hammer",
                @"type": self.typeChildPane,
                @"enableCondition": whenNotInGame,
                @"canDismissWithSwipe": @NO,
                @"class": LauncherPrefContCfgViewController.class
            },
            @{@"key": @"custom_mouse_pointer",
                @"icon": @"cursorarrow",
                @"hasDetail": @YES,
                @"type": self.typeButton,
                @"enableCondition": whenNotInGame,
                @"action": ^void(){
                    [self openMousePointerPicker];
                }
            },
            @{@"key": @"hardware_hide",
                @"icon": @"eye.slash",
                @"hasDetail": @YES,
                @"type": self.typeSwitch,
            },
            @{@"key": @"reset_mouse_pointer",
                @"icon": @"arrow.counterclockwise",
                @"hasDetail": @YES,
                @"type": self.typeButton,
                @"enableCondition": whenNotInGame,
                @"action": ^void(){
                    NSString *path = [NSString stringWithFormat:@"%s/controlmap/mouse_pointer.png", getenv("POJAV_HOME")];
                    [NSFileManager.defaultManager removeItemAtPath:path error:nil];
                    [NSNotificationCenter.defaultCenter postNotificationName:@"MousePointerUpdated" object:nil];
                    [self showSuccessMessage:localize(@"i18n_str_393", nil)];
                }
            },
            @{@"key": @"recording_hide",
                @"icon": @"eye.slash",
                @"hasDetail": @YES,
                @"type": self.typeSwitch,
            },
            
            // --- [重构] 双指呼出键盘控制 ---
            // 同样改为按钮+弹窗模式，彻底解决开关回弹问题
            @{@"key": @"two_finger_keyboard", 
              @"icon": @"keyboard", // 键盘图标
              @"hasDetail": @YES,
              @"type": self.typeButton, // 关键：改为 Button 类型
              
              @"action": ^void() {
                  // 1. 获取当前状态
                  BOOL isOn = getPrefBool(@"control.two_finger_keyboard");
                  
                  // 2. 构建弹窗
                  NSString *title = localize(@"preference.title.two_finger_keyboard", nil);
                  // 如果没有 localization，设置默认标题
                  if (!title || [title isEqualToString:@"preference.title.two_finger_keyboard"]) {
                      title = localize(@"i18n_str_394", nil);
                  }
                  
                  NSString *statusMsg = isOn ? localize(@"i18n_str_2053", nil) : localize(@"i18n_str_396", nil);
                  NSString *msg = [NSString stringWithFormat:localize(@"i18n_str_397", nil), statusMsg];
                  
                  UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:msg preferredStyle:UIAlertControllerStyleAlert];
                  
                  // 3. 根据当前状态显示不同的按钮
                  if (!isOn) {
                      [alert addAction:[UIAlertAction actionWithTitle:localize(@"i18n_str_398", nil) style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
                          // 强制开启
                          setPrefBool(@"control.two_finger_keyboard", YES);
                          [weakSelf showSuccessMessage:localize(@"i18n_str_399", nil)];
                          // 刷新界面
                          [weakSelf.tableView reloadData];
                      }]];
                  } else {
                      [alert addAction:[UIAlertAction actionWithTitle:localize(@"i18n_str_400", nil) style:UIAlertActionStyleDestructive handler:^(UIAlertAction * _Nonnull action) {
                          // 强制关闭
                          setPrefBool(@"control.two_finger_keyboard", NO);
                          [weakSelf showSuccessMessage:localize(@"i18n_str_401", nil)];
                          // 刷新界面
                          [weakSelf.tableView reloadData];
                      }]];
                  }
                  
                  [alert addAction:[UIAlertAction actionWithTitle:localize(@"resman.common.cancel", nil) style:UIAlertActionStyleCancel handler:nil]];
                  
                  [weakSelf presentViewController:alert animated:YES completion:nil];
              }
            },
            // -----------------------------
            
            @{@"key": @"gesture_mouse",
                @"icon": @"cursorarrow.click",
                @"hasDetail": @YES,
                @"type": self.typeSwitch,
            },
            // ★ [BT-MOUSE] 蓝牙鼠标/触控板（间接指针）支持开关，默认开。
            @{@"key": @"bt_pointer_enable",
                @"icon": @"computermouse",
                @"hasDetail": @YES,
                @"type": self.typeSwitch,
            },
            @{@"key": @"gesture_hotbar",
                @"icon": @"hand.tap",
                @"hasDetail": @YES,
                @"type": self.typeSwitch,
            },
            @{@"key": @"disable_haptics",
                @"icon": @"wave.3.left",
                @"hasDetail": @YES,
                @"type": self.typeSwitch,
            },
            @{@"key": @"slideable_hotbar",
                @"hasDetail": @YES,
                @"icon": @"slider.horizontal.below.rectangle",
                @"type": self.typeSwitch,
                // --- [修改] 添加禁用条件 ---
                @"enableCondition": ^BOOL(){
                    // 当 TouchController 启用时，禁用此选项（返回 NO 表示禁用/变灰）
                    return ![self.getPreference(@"control", @"mod_touch_enable") boolValue];
                }
            },
            @{@"key": @"press_duration",
                @"hasDetail": @YES,
                @"icon": @"cursorarrow.click.badge.clock",
                @"type": self.typeSlider,
                @"min": @(100),
                @"max": @(1000),
            },
            // ★ [TAP-CLICK] 轻触即左键（默认开）：轻触一下 = 一次完整左键单击。
            // 关闭后回到旧行为（游戏内轻触=右键放置、菜单轻触=左键，长按=左键破坏）。
            @{@"key": @"tap_click_enable",
                @"hasDetail": @YES,
                @"icon": @"hand.tap",
                @"type": self.typeSwitch,
            },
            // ★ [TAP-UNIVERSAL] 单键通用：轻触发哪个键。
            //   auto  = 按准星目标自动判（方块可交互→右键打开；手持方块→右键放置；其余→左键）
            //   left  = 恒左键；right = 恒右键。
            @{@"key": @"tap_click_mode",
                @"hasDetail": @YES,
                @"icon": @"cursorarrow.click.badge.clock",
                @"type": self.typePickField,
                @"pickKeys": @[
                    @"auto",
                    @"left",
                    @"right"
                ],
                @"pickList": @[
                    localize(@"preference.title.tap_click_mode-auto", nil),
                    localize(@"preference.title.tap_click_mode-left", nil),
                    localize(@"preference.title.tap_click_mode-right", nil)
                ]
            },
            // 时长阈值(ms)：轻触按住时长小于它才判定为“轻触”
            @{@"key": @"tap_click_duration",
                @"hasDetail": @YES,
                @"icon": @"timer",
                @"type": self.typeSlider,
                @"min": @(100),
                @"max": @(1000),
            },
            // 位移阈值(pt)：按下→抬起的移动距离小于它才判定为“轻触”，避免误伤拖动视角
            @{@"key": @"tap_click_move",
                @"hasDetail": @YES,
                @"icon": @"arrow.up.and.down.and.arrow.left.and.right",
                @"type": self.typeSlider,
                @"min": @(2),
                @"max": @(40),
            },
            // 【兼容旧键】合成按键：YES 时强制"轻触=右键"（等同 tap_click_mode=right）。
            // 已由上方「轻触发键方式」取代；保留仅为不破坏老用户的既有设置。
            @{@"key": @"tap_click_button_right",
                @"hasDetail": @YES,
                @"icon": @"cursorarrow.click.2",
                @"type": self.typeSwitch,
            },
            // ★ [TAP-BTN] 「非按键区域轻触默认动作」开关（沿用本页既有 UISwitch 样式）：
            //   开 = 点非按键区域(游戏视野)的轻触恒发左键；关(默认) = 不改变现状，仍按
            //   tap_click_mode 智能判定(auto/单键通用)。仅当上方「轻触发键方式」为 auto 时生效
            //   （显式选了恒左/恒右则后者优先）。写入 control.tap_default_left，设置页
            //   setPreference 走通用路径 setPrefObject ⇒ 游戏内每次轻触实时 getPrefBool 读取，即时生效。
            @{@"key": @"tap_default_left",
                @"hasDetail": @YES,
                @"icon": @"hand.tap.fill",
                @"type": self.typeSwitch,
            },
            @{@"key": @"button_scale",
                @"hasDetail": @YES,
                @"icon": @"aspectratio",
                @"type": self.typeSlider,
                @"min": @(50), // 80?
                @"max": @(500)
            },
            @{@"key": @"mouse_scale",
                @"hasDetail": @YES,
                @"icon": @"arrow.up.left.and.arrow.down.right.circle",
                @"type": self.typeSlider,
                @"min": @(25),
                @"max": @(300)
            },
            @{@"key": @"mouse_speed",
                @"hasDetail": @YES,
                @"icon": @"cursorarrow.motionlines",
                @"type": self.typeSlider,
                @"min": @(25),
                @"max": @(300)
            },
            @{@"key": @"virtmouse_enable",
                @"hasDetail": @YES,
                @"icon": @"cursorarrow.rays",
                @"type": self.typeSwitch
            },
            // ★ [ISSUE-152] 隐藏游戏内悬浮球（小齿轮）：
            //   复用既有 UISwitch 开关样式（本页 typeSwitch），标题走 preference.title.menu_button_visible
            //   （四语言已同步）；写入 control.menu_button_visible，设置页 setPreference 里广播即时生效。
            //   默认关=显示（不改变现状）。
            @{@"key": @"menu_button_visible",
                @"hasDetail": @YES,
                @"icon": @"gearshape.fill",
                @"type": self.typeSwitch
            },
            @{@"key": @"gyroscope_enable",
                @"hasDetail": @YES,
                @"icon": @"gyroscope",
                @"type": self.typeSwitch,
                @"enableCondition": ^BOOL(){
                    return realUIIdiom != UIUserInterfaceIdiomTV;
                }
            },
            @{@"key": @"gyroscope_invert_x_axis",
                @"hasDetail": @YES,
                @"icon": @"arrow.left.and.right",
                @"type": self.typeSwitch,
                @"enableCondition": ^BOOL(){
                    return realUIIdiom != UIUserInterfaceIdiomTV;
                }
            },
            @{@"key": @"gyroscope_sensitivity",
                @"hasDetail": @YES,
                @"icon": @"move.3d",
                @"type": self.typeSlider,
                @"min": @(50),
                @"max": @(300),
                @"enableCondition": ^BOOL(){
                    return realUIIdiom != UIUserInterfaceIdiomTV;
                }
            }
        ], @[
        // Java tweaks
            @{@"icon": @"sparkles"},
            @{@"key": @"manage_runtime",
                @"hasDetail": @YES,
                @"icon": @"cube",
                @"type": self.typeChildPane,
                @"canDismissWithSwipe": @YES,
                @"class": LauncherPrefManageJREViewController.class,
                @"enableCondition": whenNotInGame
            },
            @{@"key": @"java_args",
                @"hasDetail": @YES,
                @"icon": @"slider.vertical.3",
                @"type": self.typeTextField,
                @"enableCondition": whenNotInGame
            },
            @{@"key": @"env_variables",
                @"hasDetail": @YES,
                @"icon": @"terminal",
                @"type": self.typeTextField,
                @"enableCondition": whenNotInGame
            },
            // ★ [DYLD-SWITCH] dyld 旁路总开关。真机 A/B 证实旁路是 MC 26.2 启动崩溃的元凶
            // （旁路开 → 卡死 dlopen(libjli)；关 → JVM 正常起来），故默认关闭。
            // 仅在确认本机确实需要时才开启；改动需完全重启 App 生效。
            // 来源 fork 分支 fix/dyld-bypass-default-off @ c26262a58b。
            @{@"key": @"dyld_bypass",
                @"hasDetail": @YES,
                @"icon": @"wrench.and.screwdriver",
                @"type": self.typeSwitch,
                @"enableCondition": whenNotInGame
            },
            @{@"key": @"auto_ram",
                @"hasDetail": @YES,
                @"icon": @"slider.horizontal.3",
                @"type": self.typeSwitch,
                @"enableCondition": whenNotInGame,
                @"warnCondition": ^BOOL(){
                    return !isJailbroken;
                },
                @"warnKey": @"auto_ram_warn",
                @"requestReload": @YES
            },
            @{@"key": @"allocated_memory",
                @"hasDetail": @YES,
                @"icon": @"memorychip",
                @"type": self.typeSlider,
                @"min": @(250),
                @"max": @((NSProcessInfo.processInfo.physicalMemory / 1048576) * 0.85),
                @"enableCondition": ^BOOL(){
                    return !getPrefBool(@"java.auto_ram") && whenNotInGame();
                },
                @"warnCondition": ^BOOL(DBNumberedSlider *view){
                    return view.value >= NSProcessInfo.processInfo.physicalMemory / 1048576 * 0.37;
                },
                @"warnKey": @"mem_warn"
            }
        ], @[
            // Debug settings - only recommended for developer use
            @{@"icon": @"ladybug"},
            @{@"key": @"debug_universal_script_jit",
                @"icon": @"scroll",
                @"type": self.typeSwitch,
                @"requestReload": @YES,
                @"enableCondition": ^BOOL(){
                    // 同步自 catsruledogs：用 DeviceNeedsDebugJITMapping() 替代旧的 TXM 标志组合
                    // 基于 JIT_FLAG_IS_IOS_26 | JIT_FLAG_FORCE_MIRRORED，确保 iOS 26+ 无 TXM 设备也显示此开关
                    return DeviceNeedsDebugJITMapping() && whenNotInGame();
                },
            },
            @{@"key": @"debug_always_attached_jit",
                @"hasDetail": @YES,
                @"icon": @"app.connected.to.app.below.fill",
                @"type": self.typeSwitch,
                @"enableCondition": ^BOOL(){
                    return getPrefBool(@"debug.debug_universal_script_jit") && whenNotInGame();
                },
            },
            @{@"key": @"debug_skip_wait_jit",
                @"hasDetail": @YES,
                @"icon": @"forward",
                @"type": self.typeSwitch,
                @"enableCondition": whenNotInGame
            },
            // --- [Task 134] JIT 开启工具（参照 Air，多工具方案） ---
            // 部分用户没有安装 StikDebug 而使用 SideStore/StosDebug/JITStreamer
            // 等其它工具——此前安装器只认 StikDebug（"点了没反应、JIT
            // 永远开不了"）。现提供工具选择：auto 沿用原自动判定，其余选项
            // 强制走对应工具的 URL scheme（Task139 消费）。
            @{@"key": @"jit_enabler",
                @"hasDetail": @YES,
                @"icon": @"bolt.badge.clock",
                @"type": self.typePickField,
                @"enableCondition": whenNotInGame,
                @"pickKeys": @[
                    @"auto",
                    @"stikjit",
                    // ★ [POCKETJ-JIT] 新增:只注册 stikdebug:// 的 StikDebug 版本
                    //   (PocketJ INTEGRATION.md 的 StikDebug 形式,带 script-name)。
                    //   pickKeys / pickList 必须一一对应,勿只改一边。
                    @"stikdebug",
                    @"sidestore",
                    @"stosdebug",
                    @"jitstreamer",
                    // ★ [JIT-ADAPT] 新增:逐工具适配「本机无 URL 可调、需用户手动开」的方式。
                    //   与 URL 类工具一样走统一可验证自检;仅引导文案/前置条件不同。
                    @"sidejitserver",
                    @"altstore",
                    @"sideloadly",
                    @"trollstore",
                    @"jailbreak",
                    @"manual"
                ],
                @"pickList": @[
                    localize(@"preference.debug.jit_enabler.auto", nil),
                    localize(@"preference.debug.jit_enabler.stikjit", nil),
                    localize(@"preference.debug.jit_enabler.stikdebug", nil),
                    localize(@"preference.debug.jit_enabler.sidestore", nil),
                    localize(@"preference.debug.jit_enabler.stosdebug", nil),
                    localize(@"preference.debug.jit_enabler.jitstreamer", nil),
                    localize(@"preference.debug.jit_enabler.sidejitserver", nil),
                    localize(@"preference.debug.jit_enabler.altstore", nil),
                    localize(@"preference.debug.jit_enabler.sideloadly", nil),
                    localize(@"preference.debug.jit_enabler.trollstore", nil),
                    localize(@"preference.debug.jit_enabler.jailbreak", nil),
                    localize(@"preference.debug.jit_enabler.manual", nil)
                ]
            },
            // --- [Task 134] iOS 26 JS 脚本 JIT 开关（参照 Air） ---
            // 关闭后 stikjit:// 请求不再附带 UniversalJIT26.js 的
            // script-data（纯调试器附加式 JIT）。注意：TXM 设备（系统级
            // 内存映射依赖脚本服务 brk）关闭后可能无法启动游戏。
            @{@"key": @"jit26_script_disable",
                @"hasDetail": @YES,
                @"icon": @"scroll",
                @"type": self.typeSwitch,
                @"enableCondition": whenNotInGame,
                @"requestReload": @YES
            },
            @{@"key": @"debug_hide_home_indicator",
                @"hasDetail": @YES,
                @"icon": @"iphone.and.arrow.forward",
                @"type": self.typeSwitch,
                @"enableCondition": ^BOOL(){
                    return
                        self.splitViewController.view.safeAreaInsets.bottom > 0 ||
                        self.view.safeAreaInsets.bottom > 0;
                }
            },
            @{@"key": @"debug_ipad_ui",
                @"hasDetail": @YES,
                @"icon": @"ipad",
                @"type": self.typeSwitch,
                @"enableCondition": whenNotInGame
            },
            @{@"key": @"debug_auto_correction",
                @"hasDetail": @YES,
                @"icon": @"textformat.abc.dottedunderline",
                @"type": self.typeSwitch
            }
        ]
    ];

    [super viewDidLoad];
    // 适配自定义启动器背景：通过 BackgroundManager 将当前视图控制器透明化，
    // 让全局背景容器（图片/视频）能够透出显示。必须在 super viewDidLoad 之后调用，
    // 以确保 view 与 tableView 均已就绪。
    [self refreshRefinedSettingsPresentation];

    // 顶部 Hero 卡片：App 名 + 版本 + 设备信息（参照 Air-Design v1.2 L3 大卡片规范）
    // 与搜索栏一起包装为 tableHeaderView，搜索栏在上、Hero 卡片在下
    [self setupHeroHeader];

    [self refreshRefinedSettingsPresentation];
    if (NSProcessInfo.processInfo.isMacCatalystApp) {
        UIButton *closeButton = [UIButton buttonWithType:UIButtonTypeClose];
        closeButton.frame = CGRectOffset(closeButton.frame, 10, 10);
        [closeButton addTarget:self action:@selector(actionClose) forControlEvents:UIControlEventTouchUpInside];
        [self.view addSubview:closeButton];
    }
    
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(handleBackgroundUIEffectChanged:)
                                                 name:@"BackgroundUIEffectChanged"
                                               object:nil];

    // 监听背景 UI 效果变化通知：当用户在背景设置中切换毛玻璃/半透明或调整透明度时，
    // 重新调用 makeViewControllerTransparent 以应用最新的视觉效果，保证背景始终正确透出。
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(reapplyBackgroundEffect)
                                                 name:@"BackgroundUIEffectChanged"
                                               object:nil];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(openCurseForgeAPIKeySettings)
                                                 name:@"OpenCurseForgeAPIKeySettings"
                                               object:nil];

    // ★ [LANG-SWITCH] Refresh this page's text after a language change (titles/details are
    // resolved through localize() at display time and take effect immediately).
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(handleLauncherLanguageChanged:)
                                                 name:@"AmeLauncherLanguageChanged"
                                               object:nil];
}

#pragma mark - ★ [LANG-SWITCH] 语言切换

- (void)handleLauncherLanguageChanged:(NSNotification *)notification {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.tableView reloadData];
    });
}

#pragma mark - Hero Header（顶部 App 信息卡片）

- (NSString *)appName {
    // Preserve the visible product name, with the Metallic fallback if metadata is absent.
    NSDictionary *info = NSBundle.mainBundle.infoDictionary;
    NSString *name = info[@"CFBundleDisplayName"];
    if (name.length == 0) {
        name = info[@"CFBundleName"];
    }
    return name.length ? name : @"Metallic";
}

- (void)setupHeroHeader {
    if (self.referenceContentMode) { self.tableView.tableHeaderView = nil; return; }
    UISearchBar *searchBar = [self.tableView.tableHeaderView isKindOfClass:UISearchBar.class]
        ? (UISearchBar *)self.tableView.tableHeaderView : self.refinedSearchBar;
    [searchBar removeFromSuperview];
    self.refinedSearchBar = searchBar;
    searchBar.searchBarStyle = UISearchBarStyleMinimal;
    searchBar.backgroundImage = [[UIImage alloc] init];
    searchBar.searchTextField.font = AmeUIFont(AmeUIFontRoleBody);
    searchBar.searchTextField.adjustsFontForContentSizeCategory = YES;
    searchBar.searchTextField.textColor = AmeUIPrimaryTextColor();

    UIView *container = [[UIView alloc] init];
    container.insetsLayoutMarginsFromSafeArea = NO; // The table owns vertical safe-area adjustment.
    UIView *card = [[UIView alloc] init];
    card.translatesAutoresizingMaskIntoConstraints = NO;
    card.layer.cornerRadius = 18;
    card.layer.cornerCurve = kCACornerCurveContinuous;
    card.clipsToBounds = YES;
    [[BackgroundManager sharedManager] applyEffectToView:card];
    self.heroCard = card;
    [container addSubview:card];
    [container addSubview:searchBar];
    searchBar.translatesAutoresizingMaskIntoConstraints = NO;
    UIImageView *icon = [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"AppLogo-Current"]
        ?: [UIImage imageNamed:@"AppIcon-Light60x60"] ?: [UIImage imageNamed:@"AppLogo-Vector"]
        ?: [UIImage systemImageNamed:@"app.fill"] ?: [UIImage systemImageNamed:@"square.grid.2x2.fill"]];
    icon.translatesAutoresizingMaskIntoConstraints = NO;
    icon.contentMode = UIViewContentModeScaleAspectFit;
    icon.layer.cornerRadius = 11;
    icon.clipsToBounds = YES;
    icon.isAccessibilityElement = NO;
    UILabel *name = [[UILabel alloc] init];
    name.text = [self appName];
    name.font = AmeUIFont(AmeUIFontRoleSectionHeading);
    name.textColor = AmeUIPrimaryTextColor();
    name.adjustsFontForContentSizeCategory = YES;
    name.numberOfLines = 0;
    UILabel *info = [[UILabel alloc] init];
    NSString *version = NSBundle.mainBundle.infoDictionary[@"CFBundleShortVersionString"];
    NSString *device = [HostManager GetModelName] ?: UIDevice.currentDevice.name ?: @"";
    info.text = [NSString stringWithFormat:@"%@\n%@ · iOS %@", version.length ? [@"v" stringByAppendingString:version] : @"Version not reported",
        device, UIDevice.currentDevice.systemVersion ?: @""];
    info.font = AmeUIFont(AmeUIFontRoleDescription);
    info.textColor = AmeUISecondaryTextColor();
    info.numberOfLines = 0;
    info.adjustsFontForContentSizeCategory = YES;
    UIStackView *identity = [[UIStackView alloc] initWithArrangedSubviews:@[name, info]];
    identity.axis = UILayoutConstraintAxisVertical;
    identity.spacing = 4;
    UIButton *help = [AmePinkGlassButton buttonWithType:UIButtonTypeSystem];
    ((AmePinkGlassButton *)help).ameRole = AmeGlassButtonRoleSubtle;
    [help setImage:[UIImage systemImageNamed:@"questionmark.circle"] forState:UIControlStateNormal];
    help.accessibilityLabel = @"Show or hide setting descriptions";
    UIBarButtonItem *originalHelp = [self drawHelpButton];
    [help addTarget:originalHelp.target action:originalHelp.action forControlEvents:UIControlEventTouchUpInside];
    help.translatesAutoresizingMaskIntoConstraints = NO;
    UIStackView *row = [[UIStackView alloc] initWithArrangedSubviews:@[icon, identity, help]];
    row.translatesAutoresizingMaskIntoConstraints = NO;
    row.alignment = UIStackViewAlignmentCenter;
    row.spacing = 12;
    [card addSubview:row];
    UILayoutGuide *guide = container.layoutMarginsGuide;
    container.directionalLayoutMargins = NSDirectionalEdgeInsetsMake(8, 16, 12, 16);
    NSLayoutConstraint *cardWidth = [card.widthAnchor constraintEqualToAnchor:guide.widthAnchor];
    cardWidth.priority = UILayoutPriorityDefaultHigh;
    [NSLayoutConstraint activateConstraints:@[
        [card.topAnchor constraintEqualToAnchor:guide.topAnchor],
        [card.centerXAnchor constraintEqualToAnchor:guide.centerXAnchor],
        [card.leadingAnchor constraintGreaterThanOrEqualToAnchor:guide.leadingAnchor],
        [card.trailingAnchor constraintLessThanOrEqualToAnchor:guide.trailingAnchor],
        [card.widthAnchor constraintLessThanOrEqualToConstant:840], cardWidth,
        [row.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:14],
        [row.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-14],
        [row.topAnchor constraintEqualToAnchor:card.topAnchor constant:12],
        [row.bottomAnchor constraintEqualToAnchor:card.bottomAnchor constant:-12],
        [icon.widthAnchor constraintEqualToConstant:44], [icon.heightAnchor constraintEqualToConstant:44],
        [help.widthAnchor constraintEqualToConstant:44], [help.heightAnchor constraintEqualToConstant:44],
        [searchBar.topAnchor constraintEqualToAnchor:card.bottomAnchor constant:8],
        [searchBar.leadingAnchor constraintEqualToAnchor:card.leadingAnchor],
        [searchBar.trailingAnchor constraintEqualToAnchor:card.trailingAnchor],
        [searchBar.heightAnchor constraintGreaterThanOrEqualToConstant:52],
        [searchBar.bottomAnchor constraintEqualToAnchor:guide.bottomAnchor]
    ]];
    self.refinedHeader = container;
    self.tableView.tableHeaderView = container;
    [self layoutRefinedHeader];
}

- (void)layoutRefinedHeader {
    if (self.referenceContentMode) return;
    CGFloat width = self.tableView.bounds.size.width;
    if (!self.refinedHeader || width <= 0) return;
    UIEdgeInsets safe = self.tableView.safeAreaInsets;
    NSDirectionalEdgeInsets margins = NSDirectionalEdgeInsetsMake(8, 16 + safe.left, 12, 16 + safe.right);
    if (!NSDirectionalEdgeInsetsEqualToDirectionalEdgeInsets(self.refinedHeader.directionalLayoutMargins, margins)) {
        self.refinedHeader.directionalLayoutMargins = margins;
    }
    CGSize size = [self.refinedHeader systemLayoutSizeFittingSize:CGSizeMake(width, UILayoutFittingCompressedSize.height)
        withHorizontalFittingPriority:UILayoutPriorityRequired verticalFittingPriority:UILayoutPriorityFittingSizeLevel];
    CGRect frame = CGRectMake(0, 0, width, ceil(size.height));
    if (!CGRectEqualToRect(self.refinedHeader.frame, frame)) {
        self.refinedHeader.frame = frame;
        self.tableView.tableHeaderView = self.refinedHeader;
    }
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    [self layoutRefinedHeader];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self name:@"BackgroundUIEffectChanged" object:nil];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:@"OpenCurseForgeAPIKeySettings" object:nil];
    // ★ [LANG-SWITCH]
    [[NSNotificationCenter defaultCenter] removeObserver:self name:@"AmeLauncherLanguageChanged" object:nil];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];

    // 重新隐藏导航栏黑条（pop 回根页面时 topViewController == self）
    if (self.navigationController &&
        self.navigationController.viewControllers.firstObject == self &&
        self.navigationController.presentingViewController == nil &&
        self.navigationController.topViewController == self) {
        self.navigationController.navigationBarHidden = YES;
    }

    // Re-apply transparency when appearing (in case background was just set)
    if ([[BackgroundManager sharedManager] hasBackground]) {
        self.view.backgroundColor = [UIColor clearColor];
        self.tableView.backgroundColor = [UIColor clearColor];
        self.tableView.backgroundView = nil;
        
        // Refresh cells to apply background styling
        [self.tableView reloadData];
    }
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    // push 子页面时显示导航栏（子页面需要返回按钮）
    if (self.navigationController &&
        self.navigationController.viewControllers.firstObject == self &&
        self.navigationController.presentingViewController == nil) {
        self.navigationController.navigationBarHidden = NO;
    }
    if (self.navigationController == nil) {
        [self.presentingViewController performSelector:@selector(updatePreferenceChanges)];
    }
}

- (void)actionClose {
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)handleBackgroundUIEffectChanged:(NSNotification *)notification {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.tableView reloadData];
    });
}

/// 重新应用背景效果：当 BackgroundUIEffectChanged 通知到达时调用，
/// 通过 BackgroundManager 重新设置当前视图控制器的透明度/毛玻璃效果，
/// 并将 tableView 背景置为透明、移除默认 backgroundView，确保全局背景能够正常透出。
- (void)reapplyBackgroundEffect {
    [self refreshRefinedSettingsPresentation];
    self.tableView.backgroundColor = [UIColor clearColor];
    self.tableView.backgroundView = nil;
}

#pragma mark - Check For Update

/// 设置页"检查更新"入口（参照 ZL2 手动检查）：
/// 走 UpdateDialogViewController 弹窗 —— 顶部版本号、中间完整可滚动的更新日志、
/// 底部"忽略此版本 / 稍后 / 更新"，点更新跳转到本次查到的那个 release 页面。
- (void)checkForUpdateFromSettings {
    [UpdateChecker performManualCheckFromPresenter:self showUpToDate:YES];
}

- (void)showUpdateAlertWithTitle:(NSString *)title
                         message:(NSString *)message
                       hasUpdate:(BOOL)hasUpdate
                          info:(nullable UpdateInfo *)info {
    UIAlertController *alert = [UIAlertController
        alertControllerWithTitle:title
                         message:message
                  preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:localize(@"OK", @"OK")
                                              style:UIAlertActionStyleDefault
                                            handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

/// 发现新版本时显示更新详情弹窗（参考 FCL/ZL2 风格）
- (void)showUpdateAvailableAlert:(UpdateInfo *)info {
    NSString *title = [NSString stringWithFormat:localize(@"check_update.new_version_title",
                                                          localize(@"i18n_str_407", nil)), info.latestVersion];
    /* 更新日志截断显示，太长的话只显示前 500 字符 + 省略号 */
    NSString *notes = info.releaseNotes ?: @"";
    if (notes.length > 500) {
        notes = [[notes substringToIndex:500] stringByAppendingString:@"…"];
    }
    NSString *message = [NSString stringWithFormat:@"%@\n\n%@",
                         localize(@"check_update.new_version_message",
                                  localize(@"i18n_str_408", nil)),
                         notes];

    UIAlertController *alert = [UIAlertController
        alertControllerWithTitle:title
                         message:message
                  preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:localize(@"check_update.download", @"Go to Download")
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction *action) {
        [UpdateChecker openReleasePage];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:localize(@"Cancel", @"Cancel")
                                              style:UIAlertActionStyleCancel
                                            handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

#pragma mark - Memory Limit Help

- (void)showMemoryLimitHelp {
    UIAlertController *alert = [UIAlertController
        alertControllerWithTitle:localize(@"mem_help.title", @"About Memory Limits")
                         message:localize(@"mem_help.message",
                             @"On iOS 18 / iOS 26, the per-instance memory limit is about 1440 MB. Large modpacks may crash due to insufficient memory.\n\n"
                              "Solution:\n"
                              "Use GetMoreRam (a LiveContainer plugin) to remove the memory limit.\n"
                              "GetMoreRam repository: github.com/hugeBlack/GetMoreRam\n\n"
                              "Restart the launcher after installation for the change to take effect.\n\n"
                              "If you do not use LiveContainer, try reducing the memory allocation (Settings > Java > Memory Allocation), "
                              "but some modpacks may not run properly under the memory limit.")
                  preferredStyle:UIAlertControllerStyleAlert];

    [alert addAction:[UIAlertAction actionWithTitle:@"GetMoreRam"
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction *action) {
        NSURL *url = [NSURL URLWithString:@"https://github.com/hugeBlack/GetMoreRam"];
        if (@available(iOS 10.0, *)) {
            [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil];
        }
    }]];

    [alert addAction:[UIAlertAction actionWithTitle:localize(@"OK", nil)
                                              style:UIAlertActionStyleCancel
                                            handler:nil]];

    [self presentViewController:alert animated:YES completion:nil];
}

#pragma mark - CurseForge API Key Settings

- (void)openCurseForgeAPIKeySettings {
    dispatch_async(dispatch_get_main_queue(), ^{
        // 通过 UIScene 获取顶层 VC（不使用 keyWindow）
        UIViewController *topVC = nil;
        for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
            if ([scene isKindOfClass:[UIWindowScene class]] && scene.activationState == UISceneActivationStateForegroundActive) {
                UIWindowScene *windowScene = (UIWindowScene *)scene;
                topVC = windowScene.windows.firstObject.rootViewController;
                if (topVC) {
                    break;
                }
            }
        }
        if (!topVC) {
            // 退而求其次：取任意一个 UIWindowScene
            for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
                if ([scene isKindOfClass:[UIWindowScene class]]) {
                    UIWindowScene *windowScene = (UIWindowScene *)scene;
                    topVC = windowScene.windows.firstObject.rootViewController;
                    if (topVC) {
                        break;
                    }
                }
            }
        }
        if (!topVC) {
            return;
        }

        while (topVC.presentedViewController) {
            topVC = topVC.presentedViewController;
        }

        CurseForgeAPIKeyViewController *vc = [[CurseForgeAPIKeyViewController alloc] init];
        UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:vc];
        nav.modalPresentationStyle = UIModalPresentationFormSheet;
        [topVC presentViewController:nav animated:YES completion:nil];
    });
}

#pragma mark - UITableView Data Source Override

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    // Bind and validate through the unchanged base factories before applying opt-in presentation.
    return [super tableView:tableView cellForRowAtIndexPath:indexPath];
}

/// iOS 设置 App 风格图标背景：给 cell.imageView 加圆角彩色背景 + 白色图标
/// 参照 iOS 设置应用（General=灰、Display=蓝、Privacy=蓝 等彩色圆角图标）
/// 在 cellForRow 中调用，仅做视觉装饰，不改变 cell 数据或交互逻辑
- (void)applySettingsAppStyleToCell:(UITableViewCell *)cell indexPath:(NSIndexPath *)indexPath {
    UIImageView *iconView = cell.imageView;
    if (!iconView) return;

    // 判断是否为 section header 行（row 0 且有 prefSections）
    // section header 行不加彩色背景，保持原始样式（避免与组内项视觉混淆）
    BOOL isSectionHeader = (!self.presentationRows && indexPath.row == 0 && self.prefSections && !self.filteredItems);
    if (isSectionHeader) {
        // section header：恢复默认 tint（不加背景），让图标保持系统默认外观
        iconView.backgroundColor = [UIColor clearColor];
        iconView.layer.cornerRadius = 0;
        iconView.layer.masksToBounds = NO;
        // section header 图标用主题强调色（accentColor），与启动按钮/菜单选中态统一
        iconView.tintColor = accentColor();
        return;
    }

    // 获取当前项的数据
    NSDictionary *item = nil;
    if (self.filteredItems) {
        // 搜索结果模式
        item = self.filteredItems[indexPath.row];
    } else if (self.prefSections && indexPath.section < (NSInteger)self.prefContents.count) {
        item = [self preferenceItemAtDisplayIndexPath:indexPath];
    }

    // 判断是否为危险操作项
    BOOL destructive = [item[@"destructive"] boolValue];

    // 获取图标名，用 UIImageSymbolConfiguration 重新渲染为白色、合适大小的 SF Symbol
    NSString *iconName = item[@"icon"];
    UIImage *styledIcon = nil;
    if (iconName.length > 0) {
        // 用 UIImageSymbolConfiguration 控制图标大小和颜色
        // pointSize 16 适配默认 UITableViewCell imageView 的 29pt 尺寸（留出内边距）
        UIImageSymbolConfiguration *config = [UIImageSymbolConfiguration configurationWithPointSize:16
                                                                                            weight:UIFontWeightMedium];
        styledIcon = [UIImage systemImageNamed:iconName withConfiguration:config];
        if (!styledIcon) {
            styledIcon = [UIImage systemImageNamed:iconName];
        }
    }

    // 设置图标：白色模板渲染，在彩色背景上显示
    if (styledIcon) {
        // withTintColor 让 SF Symbol 以白色渲染（模板模式），与背景色搭配
        UIImage *whiteIcon = [styledIcon imageWithTintColor:[UIColor whiteColor]
                                               renderingMode:UIImageRenderingModeAlwaysOriginal];
        iconView.image = whiteIcon;
    }
    iconView.tintColor = [UIColor whiteColor];
    iconView.contentMode = UIViewContentModeCenter;

    // 设置彩色圆角背景
    UIColor *bgColor = [self iconBackgroundColorForItem:item indexPath:indexPath destructive:destructive];
    iconView.backgroundColor = bgColor;
    iconView.layer.cornerRadius = 7;
    iconView.layer.cornerCurve = kCACornerCurveContinuous;
    iconView.layer.masksToBounds = YES;
}

/// 根据设置项所属 section 与图标名返回 iOS 设置 App 风格的彩色背景
/// 参照 iOS 设置应用：不同功能模块用不同颜色区分，一眼可辨识归属
- (UIColor *)iconBackgroundColorForItem:(NSDictionary *)item
                              indexPath:(NSIndexPath *)indexPath
                             destructive:(BOOL)destructive {
    // 危险操作项统一红色背景
    if (destructive) {
        return [UIColor systemRedColor];
    }

    // 搜索结果模式：统一用蓝灰色背景
    if (self.filteredItems) {
        NSNumber *origSection = item[@"__origSection"];
        if (origSection) {
            return [self colorForPreferenceSection:origSection.intValue];
        }
        return [UIColor systemBlueColor];
    }

    // 正常模式：按 section 着色
    return [self colorForPreferenceSection:indexPath.section];
}

/// section 索引 → 配色映射（参照 iOS 设置应用的模块色系）
/// general=蓝（通用设置）/ video=紫（显示）/ control=绿（控制）/ java=橙（运行时）/ debug=红（调试）
- (UIColor *)colorForPreferenceSection:(NSInteger)section {
    if (!self.prefSections || section >= (NSInteger)self.prefSections.count) {
        return [UIColor systemGrayColor];
    }
    NSString *sectionKey = self.prefSections[section];
    if ([sectionKey isEqualToString:@"general"]) {
        return [UIColor systemBlueColor];
    } else if ([sectionKey isEqualToString:@"video"]) {
        return [UIColor systemPurpleColor];
    } else if ([sectionKey isEqualToString:@"mobileglues"]) {
        return [UIColor systemIndigoColor];
    } else if ([sectionKey isEqualToString:@"control"]) {
        return [UIColor systemGreenColor];
    } else if ([sectionKey isEqualToString:@"java"]) {
        return [UIColor systemOrangeColor];
    } else if ([sectionKey isEqualToString:@"debug"]) {
        return [UIColor systemRedColor];
    }
    return [UIColor systemGrayColor];
}

#pragma mark - UITableView Delegate

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (self.presentationRows) return nil;
    if (section == 0) { // Add to general section
        NSString *versionString = [NSString stringWithFormat:@"Metallic Launcher %@\n%@ on %@ (%s)\nPID: %d",
            NSBundle.mainBundle.infoDictionary[@"CFBundleShortVersionString"],
            UIDevice.currentDevice.completeOSVersion, [HostManager GetModelName], getenv("POJAV_DETECTEDINST"), getpid()];
        
        // Style footer for background if needed
        if ([[BackgroundManager sharedManager] hasBackground]) {
            // Footer text is handled by the table view, but we can ensure visibility
            // by making sure the section has appropriate styling
        }
        
        return versionString;
    }

    // ★ [I18N-ORDER] Use the shared localize() entry point: use a translation when available,
    // otherwise retain the original default (" ").
    NSString *footerKey = [NSString stringWithFormat:@"preference.section.footer.%@", self.prefSections[section]];
    NSString *footer = localize(footerKey, nil);
    if ([footer isEqualToString:footerKey]) footer = @" ";
    if ([footer isEqualToString:@" "]) {
        return nil;
    }
    return footer;
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section {
    return self.presentationRows ? 0.01 : UITableViewAutomaticDimension;
}

- (UIView *)tableView:(UITableView *)tableView viewForFooterInSection:(NSInteger)section {
    NSString *text = [self tableView:tableView titleForFooterInSection:section];
    if (!text.length) return nil;
    AMEPreferenceFooterView *footer = [tableView dequeueReusableHeaderFooterViewWithIdentifier:@"RefinedPreferenceFooter"];
    if (!footer) footer = [[AMEPreferenceFooterView alloc] initWithReuseIdentifier:@"RefinedPreferenceFooter"];
    footer.informationLabel.text = text;
    return footer;
}

- (CGFloat)tableView:(UITableView *)tableView heightForFooterInSection:(NSInteger)section {
    NSString *text = [self tableView:tableView titleForFooterInSection:section];
    if (!text.length) return self.presentationRows ? 0.01 : 8;
    CGFloat available = tableView.safeAreaLayoutGuide.layoutFrame.size.width;
    if (available <= 0) return UITableViewAutomaticDimension;
    CGFloat width = MAX(1, MIN(840, available - 64) - 28);
    CGRect bounds = [text boundingRectWithSize:CGSizeMake(width, CGFLOAT_MAX)
        options:NSStringDrawingUsesLineFragmentOrigin | NSStringDrawingUsesFontLeading
        attributes:@{NSFontAttributeName: AmeUIFont(AmeUIFontRoleDescription)} context:nil];
    return ceil(bounds.size.height) + 38;
}

- (void)tableView:(UITableView *)tableView willDisplayHeaderView:(UIView *)view forSection:(NSInteger)section {
    if ([view isKindOfClass:UITableViewHeaderFooterView.class]) {
        UITableViewHeaderFooterView *textView = (UITableViewHeaderFooterView *)view;
        textView.textLabel.textColor = AmeUISecondaryTextColor();
        textView.textLabel.shadowColor = nil;
        textView.textLabel.font = AmeUIFont(AmeUIFontRoleDescription);
        textView.textLabel.numberOfLines = 0;
    }
}

/// 重写子页面跳转：为 CustomControlsViewController 设置必需的回调块
- (void)tableView:(UITableView *)tableView openChildPaneAtIndexPath:(NSIndexPath *)indexPath {
    NSDictionary *item = [self preferenceItemAtDisplayIndexPath:indexPath];

    // 特殊处理：键位调整界面需要 setDefaultCtrl / getDefaultCtrl 回调
    if ([item[@"key"] isEqualToString:@"custom_controls"]) {
        CustomControlsViewController *vc = [[CustomControlsViewController alloc] init];
        vc.modalPresentationStyle = UIModalPresentationOverFullScreen;
        vc.setDefaultCtrl = ^(NSString *name){
            setPrefObject(@"control.default_ctrl", name);
        };
        vc.getDefaultCtrl = ^{
            return getPrefObject(@"control.default_ctrl");
        };
        // CCVC 是自成一体的全屏编辑器：长按空白处唤出 退出/保存/加载 菜单，
        // 不需要 UINavigationController。旧代码把它包进 nav 再 present，带来两个
        // 问题：① 样式只设在 vc 上、真正被 present 的 nav 走默认 pageSheet，
        // 全屏编辑器于是缩成屏幕中央的一张方形卡片；② CCVC 被包进 nav 后，
        // 它的子面板 CCMenuViewController 的 presentingViewController 会指向
        // nav，「完成」向 nav 发 doUpdateButton:from:to: 即闪退。
        // 这里与游戏内一致：直接 present CCVC，样式设在真正被 present 的对象上。
        vc.modalInPresentation = YES;
        [self.navigationController presentViewController:vc animated:YES completion:nil];
        return;
    }

    // 其他设置项走父类默认逻辑
    [super tableView:tableView openChildPaneAtIndexPath:indexPath];
}

- (void)tableView:(UITableView *)tableView willDisplayFooterView:(UIView *)view forSection:(NSInteger)section {
    if ([view isKindOfClass:UITableViewHeaderFooterView.class]) {
        UITableViewHeaderFooterView *textView = (UITableViewHeaderFooterView *)view;
        textView.textLabel.textColor = AmeUISecondaryTextColor();
        textView.textLabel.shadowColor = nil;
        textView.textLabel.font = AmeUIFont(AmeUIFontRoleDescription);
        textView.textLabel.numberOfLines = 0;
    }
}

@end
static LauncherNewsViewController *MetallicFindHome(UIViewController *controller) {
    if ([controller isKindOfClass:LauncherNewsViewController.class]) return (LauncherNewsViewController *)controller;
    for (UIViewController *child in controller.childViewControllers) {
        LauncherNewsViewController *home = MetallicFindHome(child); if (home) return home;
    }
    return nil;
}

// Screenshot composition hosts the existing preference controller as a real child.
// Category buttons scroll its ORIGINAL index paths; no options, bindings or stores are copied.
@interface MetallicSettingsContainerViewController ()
@property(nonatomic, strong, readwrite) LauncherPreferencesViewController *preferences;
@property(nonatomic, strong) UIStackView *categoryStack;
@property(nonatomic, strong) UIScrollView *categoryScroll;
@property(nonatomic, strong) UIButton *categoryMenu;
@property(nonatomic, strong) UILabel *sectionTitle;
@property(nonatomic,strong) UIScrollView *referencePageScroll;
@property(nonatomic,strong) UIView *referenceContent;
@property(nonatomic,strong) UIStackView *referenceHeading;
@property(nonatomic,strong) UISearchBar *referenceSearch;
@property(nonatomic, strong) UILabel *identity;
@property(nonatomic, strong) NSArray<NSString *> *categoryTitles;
@property(nonatomic, strong) NSLayoutConstraint *sidebarWidth;
@property(nonatomic, strong) NSLayoutConstraint *headingTop;
@property(nonatomic, strong) UIButton *soundButton;
@property(nonatomic, strong) NSLayoutConstraint *soundHeight;
@property(nonatomic,strong) NSLayoutConstraint *soundCollapsedHeight;
@property(nonatomic, strong) NSLayoutConstraint *paneRight;
@end
@implementation MetallicSettingsContainerViewController
- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.clearColor;
    // Keep the reference composition at normal heights. On short windows the whole header can
    // scroll above a usable preference-list viewport instead of forcing a negative table height.
    self.referencePageScroll=[[UIScrollView alloc] init];
    self.referencePageScroll.translatesAutoresizingMaskIntoConstraints=NO;
    self.referencePageScroll.contentInsetAdjustmentBehavior=UIScrollViewContentInsetAdjustmentNever;
    self.referencePageScroll.scrollsToTop=NO;
    self.referencePageScroll.keyboardDismissMode=UIScrollViewKeyboardDismissModeInteractive;
    [self.view addSubview:self.referencePageScroll];
    self.referenceContent=[[UIView alloc] init]; self.referenceContent.translatesAutoresizingMaskIntoConstraints=NO;
    [self.referencePageScroll addSubview:self.referenceContent];
    UILayoutGuide *viewport=self.view.safeAreaLayoutGuide;
    NSLayoutConstraint *preferredHeight=[self.referenceContent.heightAnchor constraintEqualToAnchor:self.referencePageScroll.frameLayoutGuide.heightAnchor];
    preferredHeight.priority=UILayoutPriorityDefaultLow;
    [NSLayoutConstraint activateConstraints:@[
        [self.referencePageScroll.leadingAnchor constraintEqualToAnchor:viewport.leadingAnchor],
        [self.referencePageScroll.trailingAnchor constraintEqualToAnchor:viewport.trailingAnchor],
        [self.referencePageScroll.topAnchor constraintEqualToAnchor:viewport.topAnchor],
        [self.referencePageScroll.bottomAnchor constraintEqualToAnchor:viewport.bottomAnchor],
        [self.referenceContent.leadingAnchor constraintEqualToAnchor:self.referencePageScroll.contentLayoutGuide.leadingAnchor],
        [self.referenceContent.trailingAnchor constraintEqualToAnchor:self.referencePageScroll.contentLayoutGuide.trailingAnchor],
        [self.referenceContent.topAnchor constraintEqualToAnchor:self.referencePageScroll.contentLayoutGuide.topAnchor],
        [self.referenceContent.bottomAnchor constraintEqualToAnchor:self.referencePageScroll.contentLayoutGuide.bottomAnchor],
        [self.referenceContent.widthAnchor constraintEqualToAnchor:self.referencePageScroll.frameLayoutGuide.widthAnchor],
        [self.referenceContent.heightAnchor constraintGreaterThanOrEqualToAnchor:self.referencePageScroll.frameLayoutGuide.heightAnchor], preferredHeight
    ]];

    self.preferences = [[LauncherPreferencesViewController alloc] init];
    self.preferences.referenceContentMode = YES;
    self.preferences.prefSectionsVisible = YES;
    [self addChildViewController:self.preferences];
    [self.preferences loadViewIfNeeded];
    self.preferences.prefDetailVisible = YES;
    self.preferences.tableView.contentInsetAdjustmentBehavior=UIScrollViewContentInsetAdjustmentNever;
    self.preferences.tableView.contentInset=UIEdgeInsetsZero;
    UIView *content = self.preferences.view;
    content.translatesAutoresizingMaskIntoConstraints = NO;
    [self.referenceContent addSubview:content];
    [self.preferences didMoveToParentViewController:self];
    UILabel *eyebrow = [[UILabel alloc] init];
    eyebrow.text = @"METALLIC / PREFERENCES"; eyebrow.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
    eyebrow.textColor = AmeUISecondaryTextColor();
    UILabel *title = [[UILabel alloc] init]; title.text = @"Settings";
    title.font = [UIFont preferredFontForTextStyle:UIFontTextStyleLargeTitle]; title.textColor = AmeUIPrimaryTextColor();
    title.adjustsFontForContentSizeCategory = YES;
    UIStackView *heading = [[UIStackView alloc] initWithArrangedSubviews:@[eyebrow,title]];
    heading.axis = UILayoutConstraintAxisVertical; heading.spacing = 8; heading.translatesAutoresizingMaskIntoConstraints = NO;
    self.referenceHeading=heading;
    [self.referenceContent addSubview:heading];
    UIButton *help = [UIButton buttonWithType:UIButtonTypeSystem]; help.translatesAutoresizingMaskIntoConstraints = NO;
    [help setImage:[UIImage systemImageNamed:@"questionmark.circle"] forState:UIControlStateNormal];
    help.accessibilityLabel = @"Show or hide setting descriptions";
    UIBarButtonItem *helpItem = [self.preferences drawHelpButton];
    [help addTarget:helpItem.target action:helpItem.action forControlEvents:UIControlEventTouchUpInside];
    [self.referenceContent addSubview:help];
    [NSLayoutConstraint activateConstraints:@[[help.trailingAnchor constraintEqualToAnchor:self.referenceContent.trailingAnchor constant:-24], [help.centerYAnchor constraintEqualToAnchor:title.centerYAnchor], [help.widthAnchor constraintEqualToConstant:44], [help.heightAnchor constraintEqualToConstant:44]]];
    UISearchBar *search = [self.preferences presentationSearchBar]; self.referenceSearch=search;
    self.preferences.tableView.tableHeaderView=nil; // One owner for the visible search field.
    [search removeFromSuperview]; search.translatesAutoresizingMaskIntoConstraints = NO;
    search.placeholder = @"Search settings and tools"; search.searchBarStyle = UISearchBarStyleMinimal;
    search.backgroundImage=[[UIImage alloc] init]; search.searchTextField.backgroundColor=UIColor.clearColor;
    search.searchTextField.borderStyle=UITextBorderStyleNone;
    [self.referenceContent addSubview:search];
    self.categoryTitles = @[@"General & Appearance", @"Minecraft & Memory", @"Video & Audio", @"Controls & Input", @"Downloads & Network", @"Accounts & Online", @"Files & Storage", @"Diagnostics & Advanced", @"About & Support", @"Home Customization"];
    NSArray *symbols = @[@"paintpalette",@"memorychip",@"display",@"gamecontroller",@"arrow.down.circle",@"person.2",@"folder",@"wrench.and.screwdriver",@"info.circle",@"rectangle.3.group"];
    self.categoryScroll = [[UIScrollView alloc] init]; self.categoryScroll.translatesAutoresizingMaskIntoConstraints = NO;
    [self.referenceContent addSubview:self.categoryScroll];
    self.categoryStack = [[UIStackView alloc] init]; self.categoryStack.axis = UILayoutConstraintAxisVertical; self.categoryStack.spacing = 4;
    self.categoryStack.translatesAutoresizingMaskIntoConstraints = NO; [self.categoryScroll addSubview:self.categoryStack];
    NSMutableArray *actions = [NSMutableArray array];
    __weak typeof(self) weakSelf = self;
    for (NSInteger i=0; i<10; i++) {
        UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem]; button.tag = i;
        [button setTitle:self.categoryTitles[i] forState:UIControlStateNormal];
        [button setImage:[UIImage systemImageNamed:symbols[i]] forState:UIControlStateNormal];
        button.titleLabel.numberOfLines = 0; button.titleLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
        button.titleLabel.adjustsFontForContentSizeCategory = YES; button.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
        button.contentEdgeInsets = UIEdgeInsetsMake(10,12,10,12); button.tintColor = AmeUIPrimaryTextColor();
        button.layer.cornerRadius = 12;
        [button.heightAnchor constraintGreaterThanOrEqualToConstant:44].active = YES;
        [button addTarget:self action:@selector(categoryTapped:) forControlEvents:UIControlEventTouchUpInside];
        [self.categoryStack addArrangedSubview:button];
        [actions addObject:[UIAction actionWithTitle:self.categoryTitles[i] image:[UIImage systemImageNamed:symbols[i]] identifier:nil handler:^(__kindof UIAction *action) { [weakSelf selectCategory:i]; }]];
    }
    self.categoryMenu = [UIButton buttonWithType:UIButtonTypeSystem]; self.categoryMenu.translatesAutoresizingMaskIntoConstraints = NO;
    [self.categoryMenu setTitle:@"Settings sections ▾" forState:UIControlStateNormal];
    self.categoryMenu.menu = [UIMenu menuWithTitle:@"" children:actions]; self.categoryMenu.showsMenuAsPrimaryAction = YES;
    [self.referenceContent addSubview:self.categoryMenu];
    self.sectionTitle = [[UILabel alloc] init]; self.sectionTitle.font = [UIFont preferredFontForTextStyle:UIFontTextStyleTitle2];
    self.sectionTitle.textColor = AmeUIPrimaryTextColor(); self.sectionTitle.numberOfLines = 0; self.sectionTitle.translatesAutoresizingMaskIntoConstraints = NO;
    [self.referenceContent addSubview:self.sectionTitle];
    self.soundButton = [UIButton buttonWithType:UIButtonTypeSystem]; self.soundButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.soundButton setTitle:@"Sound & Haptics" forState:UIControlStateNormal];
    [self.soundButton setImage:[UIImage systemImageNamed:@"speaker.wave.2"] forState:UIControlStateNormal];
    self.soundButton.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
    self.soundButton.contentEdgeInsets = UIEdgeInsetsMake(12,20,12,20);
    self.soundButton.tintColor = AmeUIPrimaryTextColor();
    self.soundButton.titleLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    self.soundButton.titleLabel.numberOfLines=0; self.soundButton.titleLabel.adjustsFontForContentSizeCategory=YES;
    [self.soundButton addTarget:self action:@selector(openSoundHaptics) forControlEvents:UIControlEventTouchUpInside];
    AmeApplyGlassChipStyle(self.soundButton,26,YES);
    [self.referenceContent addSubview:self.soundButton];
    self.identity = [[UILabel alloc] init]; self.identity.font = AmeUIFont(AmeUIFontRoleDescription); self.identity.textColor = AmeUISecondaryTextColor();
    self.identity.numberOfLines = 0; self.identity.translatesAutoresizingMaskIntoConstraints = NO; [self.referenceContent addSubview:self.identity];
    self.sidebarWidth = [self.categoryScroll.widthAnchor constraintEqualToConstant:224];
    self.headingTop = [self.sectionTitle.topAnchor constraintEqualToAnchor:search.bottomAnchor constant:24];
    UIView *g = self.referenceContent;
    self.soundHeight = [self.soundButton.heightAnchor constraintGreaterThanOrEqualToConstant:68];
    self.soundCollapsedHeight=[self.soundButton.heightAnchor constraintEqualToConstant:0];
    self.paneRight = [self.sectionTitle.trailingAnchor constraintEqualToAnchor:g.trailingAnchor constant:-24];
    [NSLayoutConstraint activateConstraints:@[
        [heading.topAnchor constraintEqualToAnchor:g.topAnchor constant:8], [heading.leadingAnchor constraintEqualToAnchor:g.leadingAnchor constant:24],
        [heading.trailingAnchor constraintLessThanOrEqualToAnchor:g.trailingAnchor constant:-24],
        [search.topAnchor constraintEqualToAnchor:heading.bottomAnchor constant:20], [search.leadingAnchor constraintEqualToAnchor:g.leadingAnchor constant:16], [search.trailingAnchor constraintEqualToAnchor:g.trailingAnchor constant:-16], [search.heightAnchor constraintGreaterThanOrEqualToConstant:52],
        [self.categoryScroll.topAnchor constraintEqualToAnchor:search.bottomAnchor constant:20], [self.categoryScroll.leadingAnchor constraintEqualToAnchor:g.leadingAnchor constant:24], self.sidebarWidth, [self.categoryScroll.bottomAnchor constraintEqualToAnchor:g.bottomAnchor],
        [self.categoryStack.leadingAnchor constraintEqualToAnchor:self.categoryScroll.contentLayoutGuide.leadingAnchor], [self.categoryStack.trailingAnchor constraintEqualToAnchor:self.categoryScroll.contentLayoutGuide.trailingAnchor], [self.categoryStack.topAnchor constraintEqualToAnchor:self.categoryScroll.contentLayoutGuide.topAnchor], [self.categoryStack.bottomAnchor constraintEqualToAnchor:self.categoryScroll.contentLayoutGuide.bottomAnchor], [self.categoryStack.widthAnchor constraintEqualToAnchor:self.categoryScroll.frameLayoutGuide.widthAnchor],
        [self.categoryMenu.topAnchor constraintEqualToAnchor:search.bottomAnchor], [self.categoryMenu.leadingAnchor constraintEqualToAnchor:g.leadingAnchor constant:24], [self.categoryMenu.heightAnchor constraintEqualToConstant:44],
        self.headingTop, [self.sectionTitle.leadingAnchor constraintEqualToAnchor:self.categoryScroll.trailingAnchor constant:24], self.paneRight,
        [self.identity.leadingAnchor constraintEqualToAnchor:self.sectionTitle.leadingAnchor], [self.identity.trailingAnchor constraintEqualToAnchor:self.sectionTitle.trailingAnchor], [self.identity.topAnchor constraintEqualToAnchor:self.sectionTitle.bottomAnchor constant:8],
        [self.soundButton.leadingAnchor constraintEqualToAnchor:self.sectionTitle.leadingAnchor], [self.soundButton.trailingAnchor constraintEqualToAnchor:self.sectionTitle.trailingAnchor], [self.soundButton.topAnchor constraintEqualToAnchor:self.identity.bottomAnchor constant:16], self.soundHeight,
        [content.leadingAnchor constraintEqualToAnchor:self.sectionTitle.leadingAnchor], [content.trailingAnchor constraintEqualToAnchor:self.sectionTitle.trailingAnchor], [content.topAnchor constraintEqualToAnchor:self.soundButton.bottomAnchor constant:24], [content.bottomAnchor constraintEqualToAnchor:g.bottomAnchor], [content.heightAnchor constraintGreaterThanOrEqualToConstant:220]
    ]];
    [self selectCategory:0];
}
- (void)viewWillAppear:(BOOL)animated { [super viewWillAppear:animated]; [self.navigationController setNavigationBarHidden:YES animated:NO]; }
- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    BOOL wide = self.view.safeAreaLayoutGuide.layoutFrame.size.width >= 700 && !UIContentSizeCategoryIsAccessibilityCategory(self.traitCollection.preferredContentSizeCategory);
    CGFloat scale = wide ? self.view.bounds.size.width/1536.0 : .72;
    self.referencePageScroll.scrollEnabled=!wide || self.view.safeAreaLayoutGuide.layoutFrame.size.height<460;
    CGFloat width = wide ? 252*scale : 0;
    if (self.sidebarWidth.constant != width) self.sidebarWidth.constant = width;
    self.headingTop.constant = wide ? 32*scale : 52;
    UILabel *eyebrow=(UILabel *)self.referenceHeading.arrangedSubviews.firstObject;
    UILabel *title=(UILabel *)self.referenceHeading.arrangedSubviews.lastObject;
    eyebrow.font=[UIFont systemFontOfSize:16*scale weight:UIFontWeightMedium];
    title.font=[[UIFontMetrics metricsForTextStyle:UIFontTextStyleLargeTitle] scaledFontForFont:[UIFont systemFontOfSize:44*scale weight:UIFontWeightBold]];
    self.referenceHeading.spacing=18*scale;
    NSArray *railTitles=@[@"General &\nAppearance",@"Minecraft & Memory",@"Video & Audio",@"Controls & Input",@"Downloads\n& Network",@"Accounts & Online",@"Files & Storage",@"Diagnostics\n& Advanced",@"About & Support",@"Home\nCustomization"];
    for (UIButton *button in self.categoryStack.arrangedSubviews) {
        [button setTitle:railTitles[button.tag] forState:UIControlStateNormal];
        BOOL selected=(button.accessibilityTraits & UIAccessibilityTraitSelected)!=0;
        button.titleLabel.font=[[UIFontMetrics metricsForTextStyle:UIFontTextStyleBody] scaledFontForFont:[UIFont systemFontOfSize:20*scale weight:selected?UIFontWeightSemibold:UIFontWeightRegular]];
        button.contentEdgeInsets=UIEdgeInsetsMake(6*scale,14*scale,6*scale,14*scale);
        [button setPreferredSymbolConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:22*scale weight:UIImageSymbolWeightRegular] forImageInState:UIControlStateNormal];
        button.accessibilityLabel=self.categoryTitles[button.tag];
    }

    self.sectionTitle.font=[[UIFontMetrics metricsForTextStyle:UIFontTextStyleTitle2] scaledFontForFont:[UIFont systemFontOfSize:28*scale weight:UIFontWeightSemibold]];
    for(NSLayoutConstraint *c in self.referenceContent.constraints) {
        CGFloat value=c.constant;
        if(c.firstItem==self.referenceHeading && c.firstAttribute==NSLayoutAttributeTop)value=20*scale;
        if(c.firstItem==self.referenceHeading && c.firstAttribute==NSLayoutAttributeLeading)value=38*scale;
        if(c.firstItem==self.referenceSearch) {
            if(c.firstAttribute==NSLayoutAttributeTop)value=34*scale;
            if(c.firstAttribute==NSLayoutAttributeLeading)value=38*scale;
            if(c.firstAttribute==NSLayoutAttributeTrailing)value=-38*scale;
            if(c.firstAttribute==NSLayoutAttributeHeight)value=MAX(44,62*scale);
        }
        if(c.firstItem==self.categoryScroll && c.firstAttribute==NSLayoutAttributeLeading)value=wide?48*scale:24;
        if(c.firstItem==self.categoryScroll && c.firstAttribute==NSLayoutAttributeTop)value=30*scale;
        if(c.firstItem==self.sectionTitle && c.firstAttribute==NSLayoutAttributeLeading)value=wide?52*scale:0;
        if(c.firstItem==self.identity && c.firstAttribute==NSLayoutAttributeTop)value=10*scale;
        if(c.firstItem==self.soundButton && c.firstAttribute==NSLayoutAttributeTop)value=self.soundButton.hidden?0:21*scale;
        if(c.firstItem==self.preferences.view && c.firstAttribute==NSLayoutAttributeTop)value=self.soundButton.hidden?20*scale:24*scale;
        if(fabs(c.constant-value)>.1)c.constant=value;
    }
    if(![self.referenceSearch viewWithTag:kAmeGlassBackdropTag]) AmeApplyGlassChipStyle(self.referenceSearch,31*scale,YES);
    self.paneRight.constant = wide ? -216*scale : -24;
    if(self.soundButton.hidden) { self.soundHeight.active=NO; self.soundCollapsedHeight.active=YES; }
    else { self.soundCollapsedHeight.active=NO; self.soundHeight.active=YES; }
    self.soundButton.titleLabel.font=[[UIFontMetrics metricsForTextStyle:UIFontTextStyleBody] scaledFontForFont:[UIFont systemFontOfSize:24*scale]];
    CGFloat soundMinimum=MAX(44,88*scale);
    if(self.soundButton.bounds.size.width>0) {
        UIEdgeInsets padding=self.soundButton.contentEdgeInsets;
        CGFloat titleWidth=MAX(1,self.soundButton.bounds.size.width-padding.left-padding.right-self.soundButton.currentImage.size.width-8);
        NSString *title=self.soundButton.currentTitle ?: @"";
        CGRect text=[title boundingRectWithSize:CGSizeMake(titleWidth,CGFLOAT_MAX) options:NSStringDrawingUsesLineFragmentOrigin|NSStringDrawingUsesFontLeading attributes:@{NSFontAttributeName:self.soundButton.titleLabel.font} context:nil];
        soundMinimum=MAX(soundMinimum,ceil(text.size.height)+padding.top+padding.bottom);
        if(fabs(self.soundButton.titleLabel.preferredMaxLayoutWidth-titleWidth)>.1)self.soundButton.titleLabel.preferredMaxLayoutWidth=titleWidth;
    }
    if(fabs(self.soundHeight.constant-soundMinimum)>.1)self.soundHeight.constant=soundMinimum;
    self.categoryScroll.hidden = !wide; self.categoryMenu.hidden = wide;
    // Compact sections use the same destinations; their menu remains above the content.
    self.categoryMenu.alpha = wide ? 0 : 1;
}
- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    if (self.navigationController.topViewController != self) [self.navigationController setNavigationBarHidden:NO animated:animated];
}
- (void)openMetallicLicenses {
    if (self.navigationController.topViewController!=self) return;
    UIViewController *page=[[UIViewController alloc] init]; page.title=@"Open Source & Licenses";
    UITextView *text=[[UITextView alloc] init]; text.editable=NO; text.dataDetectorTypes=UIDataDetectorTypeLink;
    text.font=[UIFont preferredFontForTextStyle:UIFontTextStyleBody]; text.adjustsFontForContentSizeCategory=YES;
    text.backgroundColor=UIColor.systemBackgroundColor; text.textColor=UIColor.labelColor;
    text.textContainerInset=UIEdgeInsetsMake(20,20,20,20);
    NSURL *license=[NSBundle.mainBundle URLForResource:@"Metallic-LICENSE" withExtension:@"txt"];
    text.text=[NSString stringWithContentsOfURL:license encoding:NSUTF8StringEncoding error:nil] ?: @"Metallic Launcher\nSource and license notices: https://github.com/unfilteredpranxu/metallic-renewed";
    page.view=text; [self.navigationController pushViewController:page animated:YES];
}
- (void)openSoundHaptics {
    for (UIButton *category in self.categoryStack.arrangedSubviews) {
        if (category.tag==8 && (category.accessibilityTraits & UIAccessibilityTraitSelected)) { [self openMetallicLicenses]; return; }
    }

    LauncherPreferencesViewController *sound = [[LauncherPreferencesViewController alloc] init];
    sound.referenceContentMode = YES; sound.prefSectionsVisible = YES;
    [sound loadViewIfNeeded]; sound.prefDetailVisible = YES;
    NSSet *keys=[NSSet setWithArray:@[@"disable_haptics",@"silence_other_audio",@"silence_with_switch",@"allow_microphone"]];
    NSMutableArray *paths=[NSMutableArray array];
    for (NSUInteger section=0;section<sound.prefContents.count;section++) {
        for (NSUInteger row=1;row<sound.prefContents[section].count;row++) {
            if ([keys containsObject:sound.prefContents[section][row][@"key"]]) [paths addObject:[NSIndexPath indexPathForRow:row inSection:section]];
        }
    }
    // Additive UI-only preference; the original90 descriptors and their stores stay intact.
    NSArray *originalGeneral=sound.prefContents.firstObject;
    NSMutableArray *general=[originalGeneral mutableCopy];
    [general addObject:@{@"key":@"metallic_interface_sounds",@"title":@"Interface Sounds",@"type":sound.typeSwitch}];
    NSMutableArray *contents=[sound.prefContents mutableCopy]; contents[0]=general; sound.prefContents=contents;
    GetPreferenceBlock originalGet=sound.getPreference; SetPreferenceBlock originalSet=sound.setPreference;
    sound.getPreference=^id(NSString *section,NSString *key) { return [key isEqualToString:@"metallic_interface_sounds"] ? @([NSUserDefaults.standardUserDefaults boolForKey:@"metallic.ui.interfaceSounds"]) : originalGet(section,key); };
    sound.setPreference=^(NSString *section,NSString *key,id value) { if([key isEqualToString:@"metallic_interface_sounds"]) [NSUserDefaults.standardUserDefaults setBool:[value boolValue] forKey:@"metallic.ui.interfaceSounds"]; else originalSet(section,key,value); };
    [paths insertObject:[NSIndexPath indexPathForRow:general.count-1 inSection:0] atIndex:0];
    sound.presentationRows = @[paths]; sound.title = @"Sound & Haptics";
    [self.navigationController pushViewController:sound animated:YES];
}
- (void)categoryTapped:(UIButton *)sender { [self selectCategory:sender.tag]; }
- (void)selectCategory:(NSInteger)index {
    if (index<0 || index>=10) return;
    if (index == 9) {
        UITabBarController *tabs = self.tabBarController;
        void (^open)(void) = ^{
            tabs.selectedIndex = AMELauncherTabHome;
            dispatch_async(dispatch_get_main_queue(), ^{
                if (tabs.selectedIndex != AMELauncherTabHome) return;
                LauncherNewsViewController *home = MetallicFindHome(tabs.viewControllers[AMELauncherTabHome]);
                [home openCustomize]; // Existing config editor, with its original saved-layout callbacks.
            });
        };
        id<UIViewControllerTransitionCoordinator> transition = tabs.transitionCoordinator;
        if (transition && [transition animateAlongsideTransition:nil completion:^(id<UIViewControllerTransitionCoordinatorContext> context) { open(); }]) return;
        open();
        return;
    }
    if (self.isViewLoaded && self.view.window) MetallicPlayUIFeedback(@"navigation");
    self.sectionTitle.text = self.categoryTitles[index];
    for (UIButton *button in self.categoryStack.arrangedSubviews) {
        button.backgroundColor = button.tag==index ? AmeUISelectedFillColor() : UIColor.clearColor;
        button.accessibilityTraits = UIAccessibilityTraitButton | (button.tag==index ? UIAccessibilityTraitSelected : 0);
    }
    self.identity.text = index==8 ? [NSString stringWithFormat:@"Metallic Launcher · %@ (build %@)\n%@ · iOS %@\nUpdates: not configured", NSBundle.mainBundle.infoDictionary[@"CFBundleShortVersionString"] ?: @"Version unavailable", NSBundle.mainBundle.infoDictionary[@"CFBundleVersion"] ?: @"unavailable", UIDevice.currentDevice.model, UIDevice.currentDevice.systemVersion] : @"";
    // Category content is an ordering of ORIGINAL identities, not a second preference model.
    [self.preferences endPresentationSearch];
    NSMutableArray<NSIndexPath *> *rows = [NSMutableArray array];
    NSArray *firstGeneral = @[@"custom_accent_color",@"announcement_preview_level",@"appicon",@"auto_check_update"];
    NSDictionary *generalMoves = @{@"check_sha":@4,@"multi_threaded":@4,@"curseforge_api_key":@4,@"cosmetica":@5,@"version_isolation":@6,@"erase_demo_data":@6,@"debug_logging":@7,@"memory_limit_help":@1,@"check_update":@8};
    for (NSUInteger section=0;section<self.preferences.prefContents.count;section++) {
        NSArray *items=self.preferences.prefContents[section];
        for (NSUInteger row=1;row<items.count;row++) {
            NSDictionary *item=items[row]; if (!item[@"type"]) continue;
            NSString *key=item[@"key"];
            NSInteger category=0;
            switch(section) { case 0: category=generalMoves[key] ? [generalMoves[key] integerValue] : 0; break;
                case 1: category=4; break; case 2: case 3: category=2; break; case 4: category=3; break; case 5: category=1; break; default: category=7; break; }
            if (category==index) [rows addObject:[NSIndexPath indexPathForRow:row inSection:section]];
        }
    }
    if (index==0) {
        [rows sortUsingComparator:^NSComparisonResult(NSIndexPath *a,NSIndexPath *b) {
            NSString *ka=self.preferences.prefContents[a.section][a.row][@"key"], *kb=self.preferences.prefContents[b.section][b.row][@"key"];
            NSUInteger ia=[firstGeneral indexOfObject:ka],ib=[firstGeneral indexOfObject:kb];
            if (ia!=ib) return ia<ib ? NSOrderedAscending : NSOrderedDescending;
            return [a compare:b];
        }];
    }
    self.soundButton.hidden = index!=0 && index!=8;
    [self.soundButton setTitle:index==8 ? @"Open Source & Licenses" : @"Sound & Haptics" forState:UIControlStateNormal];
    [self.soundButton setImage:[UIImage systemImageNamed:index==8 ? @"doc.text" : @"speaker.wave.2"] forState:UIControlStateNormal];
    self.preferences.presentationRows = rows.count ? @[rows] : @[];
    [self.preferences.tableView reloadData];
    [self.preferences.tableView layoutIfNeeded]; // Once per category, before its intentional top reset.
    [self.preferences.tableView setContentOffset:CGPointMake(0,-self.preferences.tableView.adjustedContentInset.top) animated:NO];
    [self.view setNeedsLayout];
}
@end
