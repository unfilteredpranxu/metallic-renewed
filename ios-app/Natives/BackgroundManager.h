//
//  BackgroundManager.h
//  Amethyst
//
//  Background wallpaper manager - Global support for all view controllers
//

#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <AVKit/AVKit.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, BackgroundType) {
    BackgroundTypeNone = 0,
    BackgroundTypeImage,
    BackgroundTypeVideo
};

typedef NS_ENUM(NSInteger, BackgroundUIEffect) {
    BackgroundUIEffectTranslucent = 0,  // Translucent
    BackgroundUIEffectBlur              // Frosted-glass effect
};

@interface BackgroundManager : NSObject

+ (instancetype)sharedManager;

// Background type
@property (nonatomic, readonly) BackgroundType currentType;
@property (nonatomic, readonly, nullable) NSString *currentBackgroundPath;

// Launcher UI appearance and independent custom-wallpaper effects
@property (nonatomic, assign) BackgroundUIEffect uiEffect;
@property (nonatomic, assign) CGFloat uiOpacity;  // 0.1 ~ 1.0
@property (nonatomic, assign) CGFloat blurIntensity; // Legacy wallpaper blur, 0...1 (material alpha 0...0.5).
@property (nonatomic, assign) CGFloat interfaceBlurIntensity; // UI material visibility, 0...1; not blur radius.
@property (nonatomic, assign) CGFloat wallpaperDimming; // Wallpaper dimming, 0...1 (max alpha 0.2 dark / 0.08 light).
// Applies only to decoration; never changes host/content alpha or control state.
- (void)applyInterfaceAppearanceToMaterial:(UIVisualEffectView * _Nullable)material inView:(UIView *)host;
- (void)resetInterfaceAppearance; // Effect, UI intensity and panel opacity only; preserves wallpaper/theme.

// Global background container
@property (nonatomic, strong, readonly, nullable) UIView *globalBackgroundContainer;
@property (nonatomic, strong, nullable) AVPlayerLayer *videoPlayerLayer;

// Apply background globally
- (void)applyBackgroundToWindow:(UIWindow *)window;
- (void)applyBackgroundToSplitViewController:(UISplitViewController *)splitVC;
- (void)removeGlobalBackground;

// Legacy compatibility
- (void)applyBackgroundToView:(UIView *)view;
- (void)removeBackgroundFromView:(UIView *)view;

// Set background
- (void)setImageBackground:(UIImage *)image completion:(void (^)(BOOL success, NSError * _Nullable error))completion;
- (void)setVideoBackgroundWithURL:(NSURL *)videoURL completion:(void (^)(BOOL success, NSError * _Nullable error))completion;
- (void)clearBackground;

// Check if has background
- (BOOL)hasBackground;
- (BOOL)hasImageBackground;
- (BOOL)hasVideoBackground;

// Get background preview
- (nullable UIImage *)backgroundPreview;

// Pause/Resume video (for app lifecycle)
- (void)pauseVideo;
- (void)resumeVideo;

// Update background frame (call on rotation)
- (void)updateBackgroundFrame;

// Make view controllers transparent (for global background visibility)
- (void)makeViewControllerTransparent:(UIViewController *)viewController;
- (void)makeSplitViewControllerTransparent:(UISplitViewController *)splitVC;

// Apply UI effect to any UIView (blur or translucent based on settings)
/// ★ [RIM-UI] Highlight-stroke switch (on by default; can be turned off on the Background Settings screen).
@property(nonatomic, assign) BOOL glassRimEnabled;
/// ★ [RIM-UI] Highlight intensity 0…1 (1.0 by default; adjustable in Settings; 0 means off).
@property(nonatomic, assign) CGFloat glassRimStrength;

- (void)applyEffectToView:(UIView *)view;
- (void)applyEffectToCollectionViewCell:(UICollectionViewCell *)cell;
- (void)applyEffectToCell:(UITableViewCell *)cell;
// Adapt UISearchBar: remove its default opaque background so the custom launcher background shows through.
- (void)applyEffectToSearchBar:(UISearchBar *)searchBar;

// Apply UI effect to navigation bar and toolbar
- (void)applyEffectToNavigationBar:(UINavigationBar *)navigationBar;
- (void)applyEffectToToolbar:(UIToolbar *)toolbar;

// Apply UI effect settings to current split view controller
- (void)refreshUIEffect;

@end

NS_ASSUME_NONNULL_END