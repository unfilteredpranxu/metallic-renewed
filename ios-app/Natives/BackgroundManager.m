#import "utils.h"
//
//  BackgroundManager.m
//  Amethyst
//
//  Background wallpaper manager implementation - Global Version with Transparency
//

#import "BackgroundManager.h"
#import "UIKit+GlassSurface.h"   // ★ Liquid Glass material + glass effect (highlight rim)
#import "AMEGlassStyle.h"        // ★ [GLASS-STYLE] UI style resolution layer (native / Liquid Glass)
#import "AMEAssetCrypto.h"
#import <Photos/Photos.h>
#import <math.h>

static NSString * const kBackgroundTypeKey = @"background_type";
static NSString * const kBackgroundPathKey = @"background_path";
static NSString * const kBackgroundUIEffectKey = @"background_ui_effect";
static NSString * const kBackgroundUIOpacityKey = @"background_ui_opacity";
static NSString * const kBackgroundBlurIntensityKey = @"background_blur_intensity";
// Split only the previously coupled responsibilities; the legacy wallpaper key is unchanged.
static NSString * const kInterfaceBlurKey = @"background_interface_blur_intensity_v1";
static NSString * const kWallpaperDimmingKey = @"background_wallpaper_dimming_v1";
static CGFloat AMEClampAppearance(CGFloat value, CGFloat minimum, CGFloat fallback) {
    return isfinite(value) ? MAX(minimum, MIN(1.0, value)) : fallback;
}
static NSString * const kGlassRimEnabledKey  = @"background_glass_rim_enabled";   // ★ [RIM-UI]
static NSString * const kGlassRimStrengthKey = @"background_glass_rim_strength";  // ★ [RIM-UI]
static NSString * const kBackgroundsFolder = @"backgrounds";
static const NSInteger kGlobalBackgroundTag = 99999;
static const NSInteger kBackgroundImageTag = 99998;
static const NSInteger kBackgroundBlurTag = 99997;
static const NSInteger kBackgroundDimTag = 99996;
static const NSInteger kDefaultBackgroundTag = 99995;
// ★ [GLASSUI] Coalesce repeated glass refreshes in the same run loop (avoid repeatedly traversing
// the view tree while the intensity slider is dragged).
static BOOL gAmeGlassRimApplyScheduled = NO;

#pragma mark - ★ [E3] Default background gradient view (SPEC §2.1: dark=purple-blue / light=white→pink-purple)
//
// Default background shown when no custom image/video is set. The original implementation used a
// flat systemBackgroundColor (black in dark mode / white in light mode), which did not match the
// E design ("dark = purple-blue gradient / light = white→pink-purple gradient").
// This view draws a gradient (linear base + three elliptical radial highlights) and is attached only
// when currentType == BackgroundTypeNone (no custom background), leaving custom image/video paths
// untouched and preserving the home screen's customization options.
@interface AmeGradientBackgroundView : UIView
@end

@implementation AmeGradientBackgroundView {
    CGSize _ameLastLayoutSize;
}

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        self.userInteractionEnabled = NO;
        self.opaque = YES;
        self.backgroundColor = [UIColor clearColor];
    }
    return self;
}

- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];
    if (@available(iOS 13.0, *)) {
        if (previousTraitCollection.userInterfaceStyle != self.traitCollection.userInterfaceStyle) {
            [self setNeedsDisplay];
        }
    }
}

- (void)layoutSubviews {
    [super layoutSubviews];
    // Redraw after a size change (rotation / split view) to keep the gradient covering the view.
    if (!CGSizeEqualToSize(_ameLastLayoutSize, self.bounds.size)) {
        _ameLastLayoutSize = self.bounds.size;
        [self setNeedsDisplay];
    }
    AVPlayerLayer *vl = [BackgroundManager sharedManager].videoPlayerLayer;
    if (vl && vl.superlayer == self.layer) {
        [CATransaction begin];
        [CATransaction setDisableActions:YES];
        vl.frame = self.bounds;
        [CATransaction commit];
    }
}

/// Default wallpaper bundled with the app (DefaultBackground.enc or DefaultBackground.png).
/// Loaded via AMEAssetCrypto in-memory decryption.
/// Returns nil when missing, in which case the procedural gradient is drawn instead.
+ (UIImage *)ame_defaultWallpaperImage {
    static UIImage *image = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        image = [AMEAssetCrypto imageForResource:@"DefaultBackground" ofType:@"png"];
    });
    return image;
}

- (void)drawRect:(CGRect)rect {
    // Default wallpaper: aspect-fill the bundled image (same in light and dark mode).
    UIImage *wallpaper = [AmeGradientBackgroundView ame_defaultWallpaperImage];
    if (wallpaper && wallpaper.size.width > 0.0 && wallpaper.size.height > 0.0
        && self.bounds.size.width > 0.0 && self.bounds.size.height > 0.0) {
        [AmeRGBA(0x05, 0x07, 0x07, 1.0) setFill];
        UIRectFill(self.bounds);
        CGFloat scale = MAX(self.bounds.size.width / wallpaper.size.width,
                            self.bounds.size.height / wallpaper.size.height);
        CGSize drawn = CGSizeMake(wallpaper.size.width * scale, wallpaper.size.height * scale);
        CGRect dest = CGRectMake((self.bounds.size.width - drawn.width) * 0.5,
                                 (self.bounds.size.height - drawn.height) * 0.5,
                                 drawn.width, drawn.height);
        CGContextRef wctx = UIGraphicsGetCurrentContext();
        if (wctx) CGContextSetInterpolationQuality(wctx, kCGInterpolationHigh);   // crisp downscale
        [wallpaper drawInRect:dest];
        return;
    }
    BOOL dark = YES;
    if (@available(iOS 13.0, *)) {
        dark = (self.traitCollection.userInterfaceStyle != UIUserInterfaceStyleLight);
    }
    [AmeGradientBackgroundView ame_drawDefaultBackgroundInRect:self.bounds dark:dark];
}

// An elliptical radial gradient (approximate CSS radial(rx ry at x y) by scaling the CTM:
// draw a circle, then squash it).
+ (void)ame_drawRadialInContext:(CGContextRef)ctx
                         center:(CGPoint)c
                             rx:(CGFloat)rx
                             ry:(CGFloat)ry
                          color:(UIColor *)color
                           stop:(CGFloat)stop {
    if (rx <= 0.0 || ry <= 0.0 || color == nil) { return; }
    CGFloat r = 0.0, g = 0.0, b = 0.0, a = 1.0;
    if (![color getRed:&r green:&g blue:&b alpha:&a]) {
        const CGFloat *cs = CGColorGetComponents(color.CGColor);
        size_t n = CGColorGetNumberOfComponents(color.CGColor);
        if (cs != NULL) {
            r = cs[0]; g = cs[1]; b = cs[2]; a = (n >= 4) ? cs[3] : 1.0;
        }
    }
    CGFloat comps[8] = { r, g, b, a, r, g, b, 0.0 };
    CGFloat locs[2]  = { 0.0, MAX(0.01, MIN(1.0, stop)) };
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGGradientRef grad = CGGradientCreateWithColorComponents(space, comps, locs, 2);
    CGContextSaveGState(ctx);
    CGContextTranslateCTM(ctx, c.x, c.y);
    CGContextScaleCTM(ctx, 1.0, ry / rx);            // Circle → ellipse
    CGContextDrawRadialGradient(ctx, grad, CGPointZero, 0.0, CGPointZero, rx,
                                kCGGradientDrawsBeforeStartLocation | kCGGradientDrawsAfterEndLocation);
    CGContextRestoreGState(ctx);
    CGGradientRelease(grad);
    CGColorSpaceRelease(space);
}

+ (void)ame_drawDefaultBackgroundInRect:(CGRect)b dark:(BOOL)dark {
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    if (ctx == NULL || b.size.width <= 0.0 || b.size.height <= 0.0) { return; }
    const CGFloat W = b.size.width, H = b.size.height;

    UIColor *base0 = nil, *base1 = nil, *r1 = nil, *r2 = nil, *r3 = nil;
    CGFloat r1x = 0.9 * W, r1y = 0.70 * H, r1s = 0.60;   // Blue highlight
    CGFloat r2x = 0.9 * W, r2y = 0.80 * H, r2s = 0.55;   // Magenta/pink highlight
    CGFloat r3x = 0.8 * W, r3y = 0.70 * H, r3s = 0.60;   // Cyan/mint highlight
    if (dark) {
        // Dark mode: purple-blue gradient, base #101322 → #05060c
        base0 = AmeRGBA(0x10, 0x13, 0x22, 1.0);
        base1 = AmeRGBA(0x05, 0x06, 0x0C, 1.0);
        r1 = AmeRGBA(90, 130, 255, 0.55);
        r2 = AmeRGBA(210, 90, 220, 0.50);
        r3 = AmeRGBA(0, 220, 200, 0.32);
    } else {
        // Light mode: white→pink-purple, base #eef3ff → #fdf8ff
        base0 = AmeRGBA(0xEE, 0xF3, 0xFF, 1.0);
        base1 = AmeRGBA(0xFD, 0xF8, 0xFF, 1.0);
        r1 = AmeRGBA(150, 185, 255, 0.90);
        r2 = AmeRGBA(255, 175, 235, 0.85);
        r3 = AmeRGBA(160, 240, 225, 0.70);
    }

    // Linear base (top → bottom)
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGGradientRef baseGrad = CGGradientCreateWithColors(space,
        (__bridge CFArrayRef)@[(id)base0.CGColor, (id)base1.CGColor], NULL);
    CGContextDrawLinearGradient(ctx, baseGrad,
                                CGPointMake(CGRectGetMinX(b), CGRectGetMinY(b)),
                                CGPointMake(CGRectGetMinX(b), CGRectGetMaxY(b)), 0);
    CGGradientRelease(baseGrad);
    CGColorSpaceRelease(space);

    // Three radial highlights (coordinates = CSS-style at x% y%).
    [self ame_drawRadialInContext:ctx
                           center:CGPointMake(CGRectGetMinX(b) + 0.12 * W, CGRectGetMinY(b) + 0.00 * H)
                               rx:r1x ry:r1y color:r1 stop:r1s];
    [self ame_drawRadialInContext:ctx
                           center:CGPointMake(CGRectGetMinX(b) + 0.92 * W, CGRectGetMinY(b) + 0.22 * H)
                               rx:r2x ry:r2y color:r2 stop:r2s];
    [self ame_drawRadialInContext:ctx
                           center:CGPointMake(CGRectGetMinX(b) + 0.40 * W, CGRectGetMinY(b) + 1.00 * H)
                               rx:r3x ry:r3y color:r3 stop:r3s];
}

@end

@interface BackgroundManager ()
@property (nonatomic, strong) AVPlayer *videoPlayer;
@property (nonatomic, strong) NSHashTable<UIView *> *appearanceHosts;
@property (nonatomic, assign) BOOL appearanceRefreshPending;
@property (nonatomic, copy) NSString *renderedBackgroundPath;
@property (nonatomic, strong) NSUUID *pendingWallpaperSelection;
@property (nonatomic, strong) UIImage *cachedBackgroundImage;
@property (nonatomic, copy) NSString *cachedImagePath;
- (void)addBlurEffectToContainer:(UIView *)container;
- (void)handleUIThemeChanged:(NSNotification *)notification;
@property (nonatomic, weak) UIView *currentBackgroundView;
@property (nonatomic, readwrite) BackgroundType currentType;
@property (nonatomic, readwrite, nullable) NSString *currentBackgroundPath;
@property (nonatomic, weak) UIWindow *currentWindow;
@property (nonatomic, weak) UISplitViewController *currentSplitVC;
@property (nonatomic, strong, readwrite, nullable) UIView *globalBackgroundContainer;
// ★ [E3] Keep a weak reference to the default-gradient host (removeGlobalBackground sets currentWindow
// to nil, so this is needed to clean it up separately).
@property (nonatomic, weak) UIView *ameDefaultGradientHost;
// ★ [E3] Private: attach the default gradient background to its host (window / splitVC.view).
- (void)ame_applyDefaultGradientToHost:(UIView *)host;
// ★ [GLASSUI] Private: apply glass-highlight settings immediately (for Settings integration).
- (void)applyGlassRimSettingsNow;
- (void)ameApplyGlassRimSettingsToViewTree:(UIView *)root;
// ★ [GLASS-STYLE] Private: apply UI style (native / Liquid Glass) immediately.
- (void)ameSyncGlassRimStrengthForCurrentStyle;
- (void)ameReapplyGlassStyleToViewTree:(UIView *)root;
- (void)ameGlassStyleChanged:(NSNotification *)note;
@end

@implementation BackgroundManager

+ (instancetype)sharedManager {
    static BackgroundManager *shared = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        shared = [[self alloc] init];
    });
    return shared;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        [self loadSavedBackground];
        [self loadUISettings];
        [self setupNotifications];
    }
    return self;
}

- (void)setupNotifications {
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(handleUIThemeChanged:)
                                                 name:@"UIThemeChanged" object:nil];
    // App lifecycle
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(appDidEnterBackground)
                                                 name:UIApplicationDidEnterBackgroundNotification
                                               object:nil];
    
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(appWillEnterForeground)
                                                 name:UIApplicationWillEnterForegroundNotification
                                               object:nil];
    
    // Video loop
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(playerItemDidReachEnd:)
                                                 name:AVPlayerItemDidPlayToEndTimeNotification
                                               object:nil];
    
    // Orientation changes
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(handleOrientationChange)
                                                 name:UIApplicationDidChangeStatusBarOrientationNotification
                                               object:nil];
    
    // Window size changes (iPad multitasking, rotation)
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(updateBackgroundFrame)
                                                 name:UIApplicationWillChangeStatusBarFrameNotification
                                               object:nil];

    // ★ [GLASS-STYLE] UI style changed (Settings calls AMEGlassStyleSetConfigured ⇒ broadcasts);
    // immediately refresh using the new style.
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(ameGlassStyleChanged:)
                                                 name:AMEGlassStyleChangedNotification
                                               object:nil];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [self cleanupVideoPlayer];
}

#pragma mark - Backgrounds Folder

- (NSString *)backgroundsFolderPath {
    NSString *docsDir = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
    NSString *folder = [docsDir stringByAppendingPathComponent:kBackgroundsFolder];
    
    NSFileManager *fm = [NSFileManager defaultManager];
    if (![fm fileExistsAtPath:folder]) {
        [fm createDirectoryAtPath:folder withIntermediateDirectories:YES attributes:nil error:nil];
    }
    
    return folder;
}

#pragma mark - Load/Save Background

- (void)loadSavedBackground {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    self.currentType = [defaults integerForKey:kBackgroundTypeKey];
    self.currentBackgroundPath = [defaults stringForKey:kBackgroundPathKey];
    
    // Validate path exists
    if ((self.currentType != BackgroundTypeNone &&
         (self.currentBackgroundPath.length == 0 || ![[NSFileManager defaultManager] fileExistsAtPath:self.currentBackgroundPath])) ||
        self.currentType < BackgroundTypeNone || self.currentType > BackgroundTypeVideo) {
        self.currentBackgroundPath = nil;
        self.currentType = BackgroundTypeNone;
        [self saveBackgroundSettings];
    }
}

- (void)saveBackgroundSettings {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults setInteger:self.currentType forKey:kBackgroundTypeKey];
    // ★ [AUDIT] currentBackgroundPath is nullable (see the header), and clearBackgroundInternal /
    //   loadSavedBackground both set it to nil. Passing nil to setObject:forKey: raises
    //   NSInvalidArgumentException (object cannot be nil) and crashes (the same class of bug as
    //   passing nil to the non-null parameter in setTitleTextAttributes:nil).
    //   Use removeObjectForKey: when nil to clear the key (the official NSUserDefaults approach).
    if (self.currentBackgroundPath.length > 0) {
        [defaults setObject:self.currentBackgroundPath forKey:kBackgroundPathKey];
    } else {
        [defaults removeObjectForKey:kBackgroundPathKey];
    }
    [defaults synchronize];
}

- (void)loadUISettings {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    // ★ [UI-B] Fix (2026-10-02): when a key is absent, integerForKey returns 0, and
    //   0 == BackgroundUIEffectTranslucent. The range check can never tell that it was never set;
    //   a fresh install therefore defaults to "Translucent", so the Blur branch in applyEffectToView:
    //   is never reached and the entire glass path is silently skipped (user report: "I can guarantee
    //   there is absolutely no glass on the main screen"). Use objectForKey to distinguish the cases.
    id ameEffObj = [defaults objectForKey:kBackgroundUIEffectKey];
    _uiEffect = ameEffObj ? [defaults integerForKey:kBackgroundUIEffectKey] : BackgroundUIEffectBlur;
    if (_uiEffect < BackgroundUIEffectTranslucent || _uiEffect > BackgroundUIEffectBlur) {
        _uiEffect = BackgroundUIEffectBlur; // Default frosted-glass effect
    }
    
    _uiOpacity = [defaults floatForKey:kBackgroundUIOpacityKey];
    if (!isfinite(_uiOpacity) || _uiOpacity < 0.1 || _uiOpacity > 1.0) {
        _uiOpacity = 0.7; // Default opacity
    }
    
    // ★ [UI-B] Same type of fix (2026-10-02): an absent key returns 0.0, which is within the valid
    //   [0,1] range ⇒ intensity is 0% ⇒ blurView.alpha = 0.3 + 0*0.7 = 0.3, making the effect nearly
    //   imperceptible. Use 0.7 as the default.
    id ameBlurObj = [defaults objectForKey:kBackgroundBlurIntensityKey];
    _blurIntensity = ameBlurObj ? [defaults floatForKey:kBackgroundBlurIntensityKey] : 0.7;
    if (!isfinite(_blurIntensity) || _blurIntensity < 0.0 || _blurIntensity > 1.0) {
        _blurIntensity = 0.7; // Default blur intensity
    }

    // ★ [GLASS-MIGRATE] One-time migration: in older versions, the bug "missing key => 0 => Translucent"
    //   caused the first run to save "Translucent". applyEffectToView: then always took the else branch,
    //   matching the user report "there is absolutely no glass on the main screen".
    //   Run this only once: if the current setting is Translucent and has not been migrated, switch to
    //   Blur and record the migration (the user can still switch it back in Settings).
    static NSString * const kGlassMigratedKey = @"background.glass_migrated_v1";
    if (_uiEffect == BackgroundUIEffectTranslucent && ![defaults boolForKey:kGlassMigratedKey]) {
        _uiEffect = BackgroundUIEffectBlur;
        [defaults setInteger:_uiEffect forKey:kBackgroundUIEffectKey];
        [defaults setBool:YES forKey:kGlassMigratedKey];
        [defaults synchronize];
        NSLog(@"[glass] migrated uiEffect: Translucent -> Blur (one-time; can be changed back in Settings)");
    }
    // ★ [RIM-UI] Highlight switch / intensity (defaults: on, 1.0).
    id ameRimObj  = [defaults objectForKey:kGlassRimEnabledKey];
    _glassRimEnabled  = ameRimObj ? [defaults boolForKey:kGlassRimEnabledKey] : YES;
    id ameRimSObj = [defaults objectForKey:kGlassRimStrengthKey];
    _glassRimStrength = ameRimSObj ? [defaults floatForKey:kGlassRimStrengthKey] : 1.0;
    if (!isfinite(_glassRimStrength) || _glassRimStrength < 0.0 || _glassRimStrength > 1.0) _glassRimStrength = 1.0;
    // ★ [GLASS-STYLE] Resolve the active UI style (single source of truth) and adjust the hand-drawn
    //   glass intensity accordingly. Native style (always on iOS<26; user-selectable on iOS>=26)
    //   forces intensity to 0 (the rim helper also short-circuits internally; this is a second safeguard).
    AMEGlassStyleLogResolvedOnce();
    [self ameSyncGlassRimStrengthForCurrentStyle];

    // One-time split: preserve old wallpaper blur and seed the previous panel/dimming appearance.
    id interfaceValue = [defaults objectForKey:kInterfaceBlurKey];
    _interfaceBlurIntensity = interfaceValue ? AMEClampAppearance(([interfaceValue respondsToSelector:@selector(doubleValue)] ? [interfaceValue doubleValue] : NAN), 0.0, 0.79)
        : MIN(1.0, 0.3 + _blurIntensity * 0.7 + ([self hasBackground] ? 0.0 : 0.2));
    id dimValue = [defaults objectForKey:kWallpaperDimmingKey];
    _wallpaperDimming = dimValue ? AMEClampAppearance(([dimValue respondsToSelector:@selector(doubleValue)] ? [dimValue doubleValue] : NAN), 0.0, 0.7) : _blurIntensity;
    [defaults setDouble:_interfaceBlurIntensity forKey:kInterfaceBlurKey];
    [defaults setDouble:_wallpaperDimming forKey:kWallpaperDimmingKey];

    NSLog(@"[glass] settings loaded: uiEffect=%ld (0=Translucent,1=Blur) blurIntensity=%.2f uiOpacity=%.2f",
          (long)_uiEffect, _blurIntensity, _uiOpacity);
    NSLog(@"[glass] rim: enabled=%d strength=%.2f", (int)self.glassRimEnabled, self.glassRimStrength);
    // ★ [GLASS-STYLE] Diagnostic to verify the style decision matrix (system capability / user setting / actual style).
    NSLog(@"[glass] style: configured=%@ · system supports Liquid Glass=%@ · actually in effect=%@",
          AMEGlassStyleStringFromEnum(AMEGlassStyleConfigured()),
          AMEGlassStyleSystemSupportsLiquid() ? @"yes" : @"no",
          AMEGlassStyleStringFromEnum(AMEGlassStyleResolved()));
}

- (void)saveUISettings {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults setInteger:self.uiEffect forKey:kBackgroundUIEffectKey];
    [defaults setFloat:self.uiOpacity forKey:kBackgroundUIOpacityKey];
    [defaults setFloat:self.blurIntensity forKey:kBackgroundBlurIntensityKey];
    [defaults setDouble:self.interfaceBlurIntensity forKey:kInterfaceBlurKey];
    [defaults setDouble:self.wallpaperDimming forKey:kWallpaperDimmingKey];
    [defaults setBool:self.glassRimEnabled forKey:kGlassRimEnabledKey];      // ★ [RIM-UI]
    [defaults setFloat:self.glassRimStrength forKey:kGlassRimStrengthKey];   // ★ [RIM-UI]
    // NSUserDefaults persists asynchronously; avoid synchronous disk flushes while tracking sliders.
}

- (void)setUiEffect:(BackgroundUIEffect)uiEffect {
    _uiEffect = uiEffect;
    [self saveUISettings];
}

- (void)setUiOpacity:(CGFloat)uiOpacity {
    _uiOpacity = AMEClampAppearance(uiOpacity, 0.1, 0.7);
    [self saveUISettings];
}

- (void)setBlurIntensity:(CGFloat)blurIntensity {
    _blurIntensity = AMEClampAppearance(blurIntensity, 0.0, 0.7);
    [self saveUISettings];
    if (self.globalBackgroundContainer) [self addBlurEffectToContainer:self.globalBackgroundContainer];
}

- (void)setInterfaceBlurIntensity:(CGFloat)value {
    _interfaceBlurIntensity = AMEClampAppearance(value, 0.0, 0.79);
    [self saveUISettings];
}

- (void)setWallpaperDimming:(CGFloat)value {
    _wallpaperDimming = AMEClampAppearance(value, 0.0, 0.7);
    [self saveUISettings];
    if (self.globalBackgroundContainer) [self addBlurEffectToContainer:self.globalBackgroundContainer];
}

- (void)resetInterfaceAppearance {
    _uiEffect = BackgroundUIEffectBlur;
    _uiOpacity = 0.7;
    _interfaceBlurIntensity = 0.3 + 0.7 * 0.7; // Existing recommended intensity mapped to material visibility.
    [self saveUISettings];
    [self refreshUIEffect];
}

#pragma mark - ★ [GLASSUI] Glass highlight switch / intensity (Settings integration: clamp + persist + apply immediately)
//
// Note: glassRimEnabled / glassRimStrength originally had only synthesized accessors. Assigning
// them externally did not write to NSUserDefaults or to the global intensity variable
// gAmeGlassRimStrength in UIKit+GlassSurface.h.
// Add explicit setters here, reusing the existing keys (background_glass_rim_enabled /
// background_glass_rim_strength; see the constants at the top of this file), without adding a second
// set of keys or another implementation:
//   ① Clamp to the valid range; ② persist via saveUISettings; ③ AmeSetGlassRimStrength writes the
//      global intensity (off ⇒ 0); ④ applyGlassRimSettingsNow immediately refreshes all on-screen
//      views that already have a highlight.
// The load path (directly writing _glassRimEnabled / _glassRimStrength in init) does not use the
// setters ⇒ startup does not trigger a refresh.
- (void)setGlassRimEnabled:(BOOL)glassRimEnabled {
    _glassRimEnabled = glassRimEnabled;
    [self saveUISettings];
    [self ameSyncGlassRimStrengthForCurrentStyle];   // ★ [GLASS-STYLE] Always 0 for native style
    [self applyGlassRimSettingsNow];
}

- (void)setGlassRimStrength:(CGFloat)glassRimStrength {
    _glassRimStrength = AMEClampAppearance(glassRimStrength, 0.0, 1.0);   // ★ Clamp to 0…1; ignore out-of-range values
    [self saveUISettings];
    [self ameSyncGlassRimStrengthForCurrentStyle];   // ★ [GLASS-STYLE] Always 0 for native style
    [self applyGlassRimSettingsNow];
}

#pragma mark - Global Background Application

- (void)applyBackgroundToWindow:(UIWindow *)window {
    if (!window) {
        [self removeGlobalBackground];
        return;
    }
    
    if (self.currentWindow == window && self.currentType == BackgroundTypeNone &&
        [window viewWithTag:kDefaultBackgroundTag]) { [self updateBackgroundFrame]; return; }
    if (self.currentWindow == window && self.currentType != BackgroundTypeNone &&
        [self.renderedBackgroundPath isEqualToString:self.currentBackgroundPath] && self.globalBackgroundContainer.superview == window) {
        [self updateBackgroundFrame];
        return;
    }
    [self removeGlobalBackground];
    self.currentWindow = window;
    self.currentSplitVC = nil;
    self.renderedBackgroundPath = self.currentBackgroundPath;
    
    // For default background, just set the window's background color
    // No need for container
    // Fix: use systemBackgroundColor to adapt to light and dark modes.
    // Previously, a hard-coded dark gray (0.08) caused "a black area in the middle" in light mode.
    // systemBackgroundColor is white in light mode and black in dark mode, adapting automatically.
    // Use systemBackground rather than pure black to avoid showing black through the status bar area.
    if (self.currentType == BackgroundTypeNone) {
        // ★ [E3] SPEC §2.1: use the default gradient (dark=purple-blue / light=white→pink-purple)
        //   when no custom background is set.
        //   Old: window.backgroundColor = systemBackgroundColor (flat, colorless black/white).
        //   New: attach AmeGradientBackgroundView — only active without a custom background; custom
        //   background paths are unaffected.
        [self ame_applyDefaultGradientToHost:window];
        return;
    }
    
    // Create container (for custom backgrounds)
    UIView *container = [[UIView alloc] initWithFrame:window.bounds];
    container.tag = kGlobalBackgroundTag;
    container.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    container.backgroundColor = [UIColor systemBackgroundColor];
    container.userInteractionEnabled = NO;
    
    // Insert at index 0 (behind everything)
    [window insertSubview:container atIndex:0];
    self.globalBackgroundContainer = container;
    
    // Apply content
    switch (self.currentType) {
        case BackgroundTypeImage:
            [self applyImageBackgroundToContainer:container];
            break;
        case BackgroundTypeVideo:
            [self applyVideoBackgroundToContainer:container];
            break;
        default:
            break;
    }
}

- (void)applyBackgroundToSplitViewController:(UISplitViewController *)splitVC {
    if (!splitVC || !splitVC.view) {
        [self removeGlobalBackground];
        return;
    }
    
    if (self.currentSplitVC == splitVC && self.currentType == BackgroundTypeNone &&
        [splitVC.view viewWithTag:kDefaultBackgroundTag]) { [self updateBackgroundFrame]; return; }
    if (self.currentSplitVC == splitVC && self.currentType != BackgroundTypeNone &&
        [self.renderedBackgroundPath isEqualToString:self.currentBackgroundPath] && self.globalBackgroundContainer.superview == splitVC.view) {
        [self updateBackgroundFrame];
        return;
    }
    [self removeGlobalBackground];
    self.currentSplitVC = splitVC;
    self.currentWindow = nil;
    self.renderedBackgroundPath = self.currentBackgroundPath;
    
    // For default background, just set the view's background color
    // No need for container or transparency
    // Fix: use systemBackgroundColor to adapt to light and dark modes.
    if (self.currentType == BackgroundTypeNone) {
        // ★ [E3] SPEC §2.1: use the default gradient (same as the window path; previously a flat systemBackgroundColor).
        [self ame_applyDefaultGradientToHost:splitVC.view];
        return;
    }
    
    // Create container that covers entire split view (for custom backgrounds)
    UIView *container = [[UIView alloc] initWithFrame:splitVC.view.bounds];
    container.tag = kGlobalBackgroundTag;
    container.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    container.backgroundColor = [UIColor systemBackgroundColor];
    container.userInteractionEnabled = NO;
    
    // Insert at the very bottom
    [splitVC.view insertSubview:container atIndex:0];
    self.globalBackgroundContainer = container;
    
    // Apply content
    switch (self.currentType) {
        case BackgroundTypeImage:
            [self applyImageBackgroundToContainer:container];
            break;
        case BackgroundTypeVideo:
            [self applyVideoBackgroundToContainer:container];
            break;
        default:
            break;
    }
    
    // Make all child controllers transparent (only for custom backgrounds)
    [self makeSplitViewControllerTransparent:splitVC];
}

- (void)removeGlobalBackground {
    // Remove from window
    if (self.currentWindow) {
        UIView *existing = [self.currentWindow viewWithTag:kGlobalBackgroundTag];
        if (existing) [existing removeFromSuperview];
    }
    
    // Remove from split VC
    if (self.currentSplitVC && self.currentSplitVC.view) {
        UIView *existing = [self.currentSplitVC.view viewWithTag:kGlobalBackgroundTag];
        if (existing) [existing removeFromSuperview];
    }
    
    // ★ [E3] Also remove the default gradient background when switching to a custom background or
    // clearing it; otherwise it would cover subsequent content.
    if (self.currentWindow) {
        UIView *dg = [self.currentWindow viewWithTag:kDefaultBackgroundTag];
        if (dg) [dg removeFromSuperview];
    }
    if (self.currentSplitVC && self.currentSplitVC.view) {
        UIView *dg = [self.currentSplitVC.view viewWithTag:kDefaultBackgroundTag];
        if (dg) [dg removeFromSuperview];
    }
    // ★ [E3] Fallback: clean up through the weakly held host (currentWindow/currentSplitVC may already
    // have been set to nil when the background changes).
    if (self.ameDefaultGradientHost) {
        UIView *dg = [self.ameDefaultGradientHost viewWithTag:kDefaultBackgroundTag];
        if (dg) [dg removeFromSuperview];
        self.ameDefaultGradientHost = nil;
    }
    
    // Cleanup
    [self cleanupVideoPlayer];
    self.globalBackgroundContainer = nil;
    self.renderedBackgroundPath = nil;
    self.currentWindow = nil;
    self.currentSplitVC = nil;
}

- (void)updateBackgroundFrame {
    if (self.globalBackgroundContainer) {
        UIView *parent = self.globalBackgroundContainer.superview;
        if (parent) {
            // Update container frame
            self.globalBackgroundContainer.frame = parent.bounds;
            
            // Update default background view
            UIView *defaultBg = [self.globalBackgroundContainer viewWithTag:kDefaultBackgroundTag];
            if (defaultBg) defaultBg.frame = self.globalBackgroundContainer.bounds;
            
            // Update image view
            UIView *imageView = [self.globalBackgroundContainer viewWithTag:kBackgroundImageTag];
            if (imageView) imageView.frame = self.globalBackgroundContainer.bounds;
            
            // Update blur view
            UIView *blurView = [self.globalBackgroundContainer viewWithTag:kBackgroundBlurTag];
            if (blurView) blurView.frame = self.globalBackgroundContainer.bounds;
            
            // Update dim view
            UIView *dimView = [self.globalBackgroundContainer viewWithTag:kBackgroundDimTag];
            if (dimView) dimView.frame = self.globalBackgroundContainer.bounds;
            
            // Update video layer
            if (self.videoPlayerLayer) self.videoPlayerLayer.frame = self.globalBackgroundContainer.bounds;
        }
    }

    if (self.ameDefaultGradientHost) {
        UIView *dg = [self.ameDefaultGradientHost viewWithTag:kDefaultBackgroundTag];
        if (dg) {
            dg.frame = self.ameDefaultGradientHost.bounds;
            if (self.videoPlayerLayer && self.videoPlayerLayer.superlayer == dg.layer) {
                [CATransaction begin];
                [CATransaction setDisableActions:YES];
                self.videoPlayerLayer.frame = dg.bounds;
                [CATransaction commit];
            }
        }
    }
}

- (void)handleOrientationChange {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self updateBackgroundFrame];
    });
}

#pragma mark - Background Content Application

// ★ [E3] Attach the default gradient background to its host (window / splitVC.view). Called only
// when there is no custom background.
- (void)ame_applyDefaultGradientToHost:(UIView *)host {
    if (!host) return;
    UIView *existing = [host viewWithTag:kDefaultBackgroundTag];
    if (existing) [existing removeFromSuperview];
    [self cleanupVideoPlayer];

    AmeGradientBackgroundView *g = [[AmeGradientBackgroundView alloc] initWithFrame:host.bounds];
    g.tag = kDefaultBackgroundTag;
    [host insertSubview:g atIndex:0];
    self.ameDefaultGradientHost = host;   // ★ [E3] Weakly held for cleanup.

    // Fallback base color (matches the gradient base and prevents black from showing through
    // on the first frame or outside the gradient).
    if ([AmeGradientBackgroundView ame_defaultWallpaperImage]) {
        host.backgroundColor = AmeRGBA(0x05, 0x07, 0x07, 1.0);   // matches the default wallpaper
    } else {
    host.backgroundColor = AmeDynamicColor(AmeRGBA(0x10, 0x13, 0x22, 1.0),
                                           AmeRGBA(0xEE, 0xF3, 0xFF, 1.0));
    }
}

- (void)applyDefaultBackgroundToContainer:(UIView *)container {
    // Remove existing default background
    UIView *existing = [container viewWithTag:kDefaultBackgroundTag];
    if (existing) [existing removeFromSuperview];

    // ★ [E3] SPEC §2.1: change the default background to a "dark=purple-blue / light=white→pink-purple" gradient.
    //   Old: flat systemBackgroundColor (black in dark mode / white in light mode; does not match the E design).
    //   New: AmeGradientBackgroundView (automatically switches with traitCollection).
    AmeGradientBackgroundView *defaultBackgroundView =
        [[AmeGradientBackgroundView alloc] initWithFrame:container.bounds];
    defaultBackgroundView.tag = kDefaultBackgroundTag;
    [container addSubview:defaultBackgroundView];
}

- (void)applyImageBackgroundToContainer:(UIView *)container {
    NSString *path = self.currentBackgroundPath;
    if (path.length == 0) { [self applyDefaultBackgroundToContainer:container]; return; }
    if (![self.cachedImagePath isEqualToString:path] || !self.cachedBackgroundImage) {
        // An established default fills the loading interval; no synchronous file read on navigation.
        [self applyDefaultBackgroundToContainer:container];
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
            UIImage *image = [UIImage imageWithContentsOfFile:path];
            dispatch_async(dispatch_get_main_queue(), ^{
                if (![self.currentBackgroundPath isEqualToString:path] || self.globalBackgroundContainer != container) return;
                if (!image) {
                    self.currentBackgroundPath = nil;
                    self.currentType = BackgroundTypeNone;
                    [self saveBackgroundSettings];
                    [[NSNotificationCenter defaultCenter] postNotificationName:@"BackgroundChanged" object:nil];
                    return;
                }
                self.cachedBackgroundImage = image;
                self.cachedImagePath = path;
                [self applyImageBackgroundToContainer:container];
                [[NSNotificationCenter defaultCenter] postNotificationName:@"BackgroundChanged" object:nil];
            });
        });
        return;
    }
    [[container viewWithTag:kDefaultBackgroundTag] removeFromSuperview];
    UIImageView *imageView = (UIImageView *)[container viewWithTag:kBackgroundImageTag];
    if (!imageView) {
        imageView = [[UIImageView alloc] initWithFrame:container.bounds];
        imageView.tag = kBackgroundImageTag;
        imageView.contentMode = UIViewContentModeScaleAspectFill;
        imageView.clipsToBounds = YES;
        imageView.userInteractionEnabled = NO;
        imageView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        [container insertSubview:imageView atIndex:0];
    }
    imageView.image = self.cachedBackgroundImage;
    [self addBlurEffectToContainer:container];
}

- (void)applyVideoBackgroundToContainer:(UIView *)container {
    if (!self.currentBackgroundPath) return;
    
    NSURL *videoURL = [NSURL fileURLWithPath:self.currentBackgroundPath];
    if (![[NSFileManager defaultManager] fileExistsAtPath:self.currentBackgroundPath]) {
        self.currentBackgroundPath = nil;
        self.currentType = BackgroundTypeNone;
        [self saveBackgroundSettings];
        [self applyDefaultBackgroundToContainer:container];
        return;
    }
    
    [self cleanupVideoPlayer];
    
    // Create player
    self.videoPlayer = [AVPlayer playerWithURL:videoURL];
    self.videoPlayer.actionAtItemEnd = AVPlayerActionAtItemEndNone;
    self.videoPlayer.muted = YES; // Mute to avoid interrupting other audio
    
    // Create player layer
    self.videoPlayerLayer = [AVPlayerLayer playerLayerWithPlayer:self.videoPlayer];
    self.videoPlayerLayer.videoGravity = AVLayerVideoGravityResizeAspectFill;
    self.videoPlayerLayer.frame = container.bounds;
    
    // Insert at bottom
    [container.layer insertSublayer:self.videoPlayerLayer atIndex:0];
    
    // Add blur effect
    [self addBlurEffectToContainer:container];
    
    // Start playing
    [self.videoPlayer play];
}

- (void)addBlurEffectToContainer:(UIView *)container {
    UIVisualEffectView *blurView = (UIVisualEffectView *)[container viewWithTag:kBackgroundBlurTag];
    if (!blurView) {
        // Wallpaper gets standard public UIKit material, independent of interface glass style.
        blurView = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemThinMaterial]];
        blurView.tag = kBackgroundBlurTag;
        blurView.userInteractionEnabled = NO;
        blurView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        [container addSubview:blurView];
    }
    blurView.frame = container.bounds;
    blurView.alpha = self.blurIntensity * 0.5;
    UIView *dimView = [container viewWithTag:kBackgroundDimTag];
    if (!dimView) {
        dimView = [[UIView alloc] initWithFrame:container.bounds];
        dimView.tag = kBackgroundDimTag;
        dimView.userInteractionEnabled = NO;
        dimView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        [container addSubview:dimView];
    }
    dimView.frame = container.bounds;
    // Dimming is black, never the white labelColor used in Dark mode. Keep Light mode gentler.
    dimView.backgroundColor = AmeDynamicColor(UIColor.blackColor, [UIColor.blackColor colorWithAlphaComponent:0.4]);
    dimView.alpha = self.wallpaperDimming * 0.2;
}

#pragma mark - Transparency Helpers with UI Effect Support

- (void)makeViewControllerTransparent:(UIViewController *)viewController {
    if (!viewController) return;
    
    // Launcher pages must not become full-screen opacity overlays. Keep the Java GUI's existing
    // presentation semantics, without changing that protected controller or its runtime behavior.
    Class javaGUIClass = NSClassFromString(@"JavaGUIViewController");
    if (javaGUIClass && [viewController isKindOfClass:javaGUIClass]) {
        viewController.view.backgroundColor = self.uiEffect == BackgroundUIEffectBlur ? UIColor.clearColor
            : [UIColor.systemBackgroundColor colorWithAlphaComponent:1.0 - self.uiOpacity];
    } else {
        viewController.view.backgroundColor = UIColor.clearColor;
    }

    // For UITableViewController
    if ([viewController isKindOfClass:[UITableViewController class]]) {
        UITableViewController *tableVC = (UITableViewController *)viewController;
        tableVC.tableView.backgroundColor = [UIColor clearColor];
        tableVC.tableView.backgroundView = nil;
        
        // Make cells semi-transparent or with blur effect
        tableVC.tableView.separatorStyle = UITableViewCellSeparatorStyleSingleLine;
        
        // Apply to all visible cells
        for (UITableViewCell *cell in tableVC.tableView.visibleCells) {
            [self applyEffectToCell:cell];
        }
    }
    
    // For UICollectionViewController
    if ([viewController isKindOfClass:[UICollectionViewController class]]) {
        UICollectionViewController *collectionVC = (UICollectionViewController *)viewController;
        collectionVC.collectionView.backgroundColor = [UIColor clearColor];
    }
    
    // Child view controllers
    for (UIViewController *childVC in viewController.childViewControllers) {
        [self makeViewControllerTransparent:childVC];
    }
}

- (void)applyEffectToCell:(UITableViewCell *)cell {
    if (!cell) return;
    UIView *background = cell.backgroundView;
    if (background.tag != kBackgroundBlurTag) {
        background = [[UIView alloc] initWithFrame:cell.bounds];
        background.tag = kBackgroundBlurTag;
        background.userInteractionEnabled = NO;
        background.layer.cornerRadius = 12.0;
        background.layer.cornerCurve = kCACornerCurveContinuous;
        background.clipsToBounds = YES;
        cell.backgroundView = background;
    }
    cell.backgroundColor = UIColor.clearColor;
    cell.contentView.backgroundColor = UIColor.clearColor;
    objc_setAssociatedObject(background, "ameNoPanelRim", @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [self applyEffectToView:background];
}

- (void)makeSplitViewControllerTransparent:(UISplitViewController *)splitVC {
    if (!splitVC) return;
    
    // Make split view itself transparent
    splitVC.view.backgroundColor = [UIColor clearColor];
    
    // Make all view controllers transparent
    for (UIViewController *vc in splitVC.viewControllers) {
        if ([vc isKindOfClass:[UINavigationController class]]) {
            UINavigationController *nav = (UINavigationController *)vc;
            
            // Navigation controller setup
            nav.view.backgroundColor = [UIColor clearColor];
            nav.navigationBar.translucent = YES;
            nav.toolbar.translucent = YES;
            
            // Apply effect to navigation bar
            [self applyEffectToNavigationBar:nav.navigationBar];
            [self applyEffectToToolbar:nav.toolbar];
            
            // Make all view controllers in stack transparent
            for (UIViewController *childVC in nav.viewControllers) {
                [self makeViewControllerTransparent:childVC];
            }
        } else {
            [self makeViewControllerTransparent:vc];
        }
    }
}

- (void)applyEffectToNavigationBar:(UINavigationBar *)navigationBar {
    // Key fix (prevents accumulated UI anomalies and recurring white lines):
    // 1. Previously, each call rebuilt UINavigationBarAppearance, causing iOS to generate new
    //    hairline UIImageViews that accumulated as "a thin white line at the top". Appearance is
    //    now a static singleton, built only once per effect to avoid repeatedly triggering internal
    //    hairline-view recreation.
    // 2. Previously, cleanup traversed only navigationBar.subviews (direct children), but iOS often
    //    nests hairlines inside private subviews such as _UINavigationBarBackground / _UIBarBackground.
    //    Recursively traverse all descendants to remove accumulated hairlines completely.
    static UIImage *emptyImage = nil;
    static UINavigationBarAppearance *blurAppearance = nil;
    static UINavigationBarAppearance *translucentAppearance = nil;
    static UIColor *translucentBarColor = nil;
    static NSInteger blurAppearanceStyle = -1;   // ★ [GLASS-STYLE] UI style associated with the frosted-glass appearance
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        emptyImage = [UIImage new];
        // The translucent appearance is built on first use using the current uiOpacity (lazy-loaded below).
    });

    // ★ [GLASS-STYLE] Cache the frosted-glass appearance by UI style and rebuild it when the style changes
    //   (native ⇒ standard system material; liquid ⇒ system UIGlassEffect). This updates the navigation
    //   bar immediately after a style switch while retaining the "build only once per style" behavior
    //   (avoiding accumulated internal iOS hairlines from repeated rebuilds).
    NSInteger curAmeNavStyle = (NSInteger)AMEGlassStyleResolved();
    if (blurAppearance == nil || blurAppearanceStyle != curAmeNavStyle) {
        blurAppearance = [[UINavigationBarAppearance alloc] init];
        [blurAppearance configureWithTransparentBackground];
        blurAppearance.backgroundColor = [UIColor clearColor];
        blurAppearance.backgroundEffect = AmeGlassEffect(UIBlurEffectStyleSystemMaterial);   // ★ Navigation-bar glass (style-dependent)
        blurAppearance.shadowColor = nil;
        blurAppearance.shadowImage = emptyImage;
        blurAppearanceStyle = curAmeNavStyle;
    }

    // Recursively remove accumulated internal iOS hairline UIImageViews (extremely short separator views).
    // Hairlines are often nested in private subviews such as _UINavigationBarBackground / _UIBarBackground.
    //
    // Key fix (hardens against crashes when entering pages from Card/Root layouts):
    //   A block that references itself (removeHairlines(sub)) must use the __block qualifier;
    //   otherwise it captures nil (the stack value before the block literal assignment completes),
    //   making recursive calls no-ops. Only direct navigationBar children would be processed,
    //   leaving hairlines nested inside _UIBarBackground untouched.
    //   Accumulated hairlines can cause private subview layout failures during repeated
    //   setContentViewController switches, resulting in EXC_BAD_ACCESS (not caught by
    //   NSUncaughtExceptionHandler).
    __block void (^removeHairlines)(UIView *) = ^(UIView *view) {
        for (UIView *sub in view.subviews) {
            if ([sub isKindOfClass:[UIImageView class]] &&
                sub.bounds.size.height > 0 &&
                sub.bounds.size.height <= 2.0) {
                [sub removeFromSuperview];
            } else {
                removeHairlines(sub);
            }
        }
    };
    removeHairlines(navigationBar);

    if (self.uiEffect == BackgroundUIEffectBlur) {
        // Frosted-glass effect — reuse the static singleton.
        if (@available(iOS 13.0, *)) {
            navigationBar.standardAppearance = blurAppearance;
            navigationBar.scrollEdgeAppearance = blurAppearance;
            navigationBar.compactAppearance = blurAppearance;
        }
        navigationBar.barTintColor = [UIColor clearColor];
        navigationBar.backgroundColor = [UIColor clearColor];
        navigationBar.shadowImage = emptyImage;
    } else {
        // Translucent effect.
        if (@available(iOS 13.0, *)) {
            UIColor *barColor = [[UIColor secondarySystemBackgroundColor] colorWithAlphaComponent:self.uiOpacity];
            navigationBar.barTintColor = barColor;
            navigationBar.backgroundColor = barColor;
            // The translucent appearance must use the current uiOpacity (it varies, so it cannot be a
            // global singleton like blur), but reuse the same instance for the same uiOpacity to avoid
            // repeated rebuilding.
            if (!translucentAppearance || ![translucentBarColor isEqual:barColor]) {
                UINavigationBarAppearance *appearance = [[UINavigationBarAppearance alloc] init];
                [appearance configureWithTransparentBackground];
                appearance.backgroundColor = barColor;
                appearance.backgroundEffect = nil;
                appearance.shadowColor = nil;
                appearance.shadowImage = emptyImage;
                translucentAppearance = appearance;
                translucentBarColor = barColor;
            }
            navigationBar.standardAppearance = translucentAppearance;
            navigationBar.scrollEdgeAppearance = translucentAppearance;
            navigationBar.compactAppearance = translucentAppearance;
        } else {
            navigationBar.barTintColor = [UIColor colorWithWhite:0.1 alpha:self.uiOpacity];
            navigationBar.backgroundColor = [UIColor colorWithWhite:0.1 alpha:self.uiOpacity];
        }
        navigationBar.shadowImage = emptyImage;
    }
}

- (void)applyEffectToToolbar:(UIToolbar *)toolbar {
    // Key fix (same as applyEffectToNavigationBar:): static singleton appearance + recursive hairline cleanup.
    static UIImage *emptyImage = nil;
    static UIToolbarAppearance *blurToolbarAppearance = nil;
    static UIToolbarAppearance *translucentToolbarAppearance = nil;
    static UIColor *translucentToolbarColor = nil;
    static NSInteger blurToolbarAppearanceStyle = -1;   // ★ [GLASS-STYLE] Same as navigation bar
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        emptyImage = [UIImage new];
    });
    // ★ [GLASS-STYLE] Rebuild the toolbar's frosted-glass appearance by UI style as well
    // (see applyEffectToNavigationBar:).
    NSInteger curAmeBarStyle = (NSInteger)AMEGlassStyleResolved();
    if (blurToolbarAppearance == nil || blurToolbarAppearanceStyle != curAmeBarStyle) {
        blurToolbarAppearance = [[UIToolbarAppearance alloc] init];
        [blurToolbarAppearance configureWithTransparentBackground];
        blurToolbarAppearance.backgroundColor = [UIColor clearColor];
        blurToolbarAppearance.backgroundEffect = AmeGlassEffect(UIBlurEffectStyleSystemMaterial);   // ★ Toolbar glass (style-dependent)
        blurToolbarAppearance.shadowColor = nil;
        blurToolbarAppearance.shadowImage = emptyImage;
        blurToolbarAppearanceStyle = curAmeBarStyle;
    }

    // Recursively remove accumulated hairline UIImageViews.
    // Key fix: as in applyEffectToNavigationBar:, a block referencing itself must use the __block
    // qualifier; otherwise recursive calls are no-ops and cannot clean hairlines nested in _UIBarBackground.
    __block void (^removeHairlines)(UIView *) = ^(UIView *view) {
        for (UIView *sub in view.subviews) {
            if ([sub isKindOfClass:[UIImageView class]] &&
                sub.bounds.size.height > 0 &&
                sub.bounds.size.height <= 2.0) {
                [sub removeFromSuperview];
            } else {
                removeHairlines(sub);
            }
        }
    };
    removeHairlines(toolbar);

    if (self.uiEffect == BackgroundUIEffectBlur) {
        // Frosted-glass effect — reuse the static singleton.
        if (@available(iOS 13.0, *)) {
            toolbar.standardAppearance = blurToolbarAppearance;
            // ★ [API-GUARD] UIToolbar.scrollEdgeAppearance is available only on iOS 15+.
            //   (UINavigationBar.scrollEdgeAppearance exists since iOS 13 ⇒ the @available(iOS 13.0)
            //   check above could mistakenly allow it.)
            //   Direct assignment on older systems (iOS 14) causes an unrecognized-selector crash.
            //   Two checks: OS version + respondsToSelector.
            if (@available(iOS 15.0, *)) {
                if ([toolbar respondsToSelector:@selector(setScrollEdgeAppearance:)]) {
                    toolbar.scrollEdgeAppearance = blurToolbarAppearance;
                }
            }
            toolbar.compactAppearance = blurToolbarAppearance;
        }
        toolbar.barTintColor = [UIColor clearColor];
        toolbar.backgroundColor = [UIColor clearColor];
    } else {
        // Translucent effect.
        if (@available(iOS 13.0, *)) {
            UIColor *barColor = [[UIColor secondarySystemBackgroundColor] colorWithAlphaComponent:self.uiOpacity];
            toolbar.barTintColor = barColor;
            toolbar.backgroundColor = barColor;
            if (!translucentToolbarAppearance || ![translucentToolbarColor isEqual:barColor]) {
                UIToolbarAppearance *appearance = [[UIToolbarAppearance alloc] init];
                [appearance configureWithTransparentBackground];
                appearance.backgroundColor = barColor;
                appearance.backgroundEffect = nil;
                appearance.shadowColor = nil;
                appearance.shadowImage = emptyImage;
                translucentToolbarAppearance = appearance;
                translucentToolbarColor = barColor;
            }
            toolbar.standardAppearance = translucentToolbarAppearance;
            // ★ [API-GUARD] Same as above: UIToolbar.scrollEdgeAppearance is iOS 15+ only
            // (assignment on older systems causes a crash).
            if (@available(iOS 15.0, *)) {
                if ([toolbar respondsToSelector:@selector(setScrollEdgeAppearance:)]) {
                    toolbar.scrollEdgeAppearance = translucentToolbarAppearance;
                }
            }
            toolbar.compactAppearance = translucentToolbarAppearance;
        } else {
            toolbar.barTintColor = [UIColor colorWithWhite:0.1 alpha:self.uiOpacity];
            toolbar.backgroundColor = [UIColor colorWithWhite:0.1 alpha:self.uiOpacity];
        }
    }
}

- (void)handleUIThemeChanged:(NSNotification *)notification {
    [self refreshUIEffect];
}

- (void)refreshUIEffect {
    if (self.appearanceRefreshPending) return;
    self.appearanceRefreshPending = YES;
    // At most one refresh per frame, no wallpaper decoding/player rebuild or root-tree traversal.
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(NSEC_PER_SEC / 60)), dispatch_get_main_queue(), ^{
        self.appearanceRefreshPending = NO;
        for (UIView *host in self.appearanceHosts.allObjects) {
            if (host.window) [self applyEffectToView:host];
        }
        [[NSNotificationCenter defaultCenter] postNotificationName:@"BackgroundUIEffectChanged" object:nil];
    });
}

- (void)applyInterfaceAppearanceToMaterial:(UIVisualEffectView *)material inView:(UIView *)host {
    // Material visibility and panel tint are separate from both content alpha and wallpaper effects.
    material.alpha = self.uiEffect == BackgroundUIEffectBlur ? self.interfaceBlurIntensity : 0.0;
    CGFloat tintStrength = self.uiEffect == BackgroundUIEffectBlur ? self.uiOpacity * 0.22 : self.uiOpacity;
    host.backgroundColor = [UIColor.secondarySystemBackgroundColor colorWithAlphaComponent:tintStrength];
}

- (void)applyEffectToView:(UIView *)view {
    if (!view) return;
    if (!self.appearanceHosts) self.appearanceHosts = [NSHashTable weakObjectsHashTable];
    [self.appearanceHosts addObject:view];
    UIVisualEffectView *material = nil;
    for (UIView *subview in view.subviews) {
        if (subview.tag == kBackgroundBlurTag && [subview isKindOfClass:UIVisualEffectView.class]) {
            material = (UIVisualEffectView *)subview;
            break;
        }
    }
    BOOL installed = (material == nil);
    if (!material) {
        material = [[UIVisualEffectView alloc] initWithEffect:AmeGlassEffect(UIBlurEffectStyleSystemThinMaterial)];
        material.tag = kBackgroundBlurTag;
        material.userInteractionEnabled = NO;
        material.isAccessibilityElement = NO;
        material.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        [view insertSubview:material atIndex:0];
    }
    NSNumber *oldStyle = objc_getAssociatedObject(material, "ameInterfaceStyle");
    NSInteger style = AMEGlassStyleResolved();
    if (oldStyle && oldStyle.integerValue != style) material.effect = AmeGlassEffect(UIBlurEffectStyleSystemThinMaterial);
    objc_setAssociatedObject(material, "ameInterfaceStyle", @(style), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    material.frame = view.bounds;
    material.layer.cornerRadius = view.layer.cornerRadius;
    material.clipsToBounds = YES;
    [self applyInterfaceAppearanceToMaterial:material inView:view];
    // Keep established optional highlight hosting and frame repair, without private backdrop tuning.
    if (![objc_getAssociatedObject(view, "ameNoPanelRim") boolValue]) {
        AmeAttachGlassRim(view, view.layer.cornerRadius);
        AmeRefreshGlassRim(view);
        if (installed || CGRectIsEmpty(view.bounds)) dispatch_async(dispatch_get_main_queue(), ^{
            [view layoutIfNeeded];
            AmeRefreshGlassRim(view);
        });
    }
}

- (void)applyEffectToCollectionViewCell:(UICollectionViewCell *)cell {
    if (!cell) return;

    // ★ [CORNER-FIX] Effective corner radius: if contentView has none, fall back to the first
    //   rounded inner card container.
    //   Previously, only cell.contentView.layer.cornerRadius was used. For cells in the instance
    //   screen's VMTileBaseCell family, the radius is on the inner container while contentView has
    //   radius 0; the injected blur therefore had square corners and covered the entire cell, exposing
    //   square corners around the rounded card (user report: "the sharp rectangular corners are still there").
    //   Consistent fix: apply the effective radius to contentView and clip it; give blur the same
    //   radius so no square corners remain around the rounded card.
    CGFloat ameEffectiveRadius = cell.contentView.layer.cornerRadius;
    if (ameEffectiveRadius <= 0.0) {
        for (UIView *ameSub in cell.contentView.subviews) {
            if (ameSub.layer.cornerRadius > 0.0) { ameEffectiveRadius = ameSub.layer.cornerRadius; break; }
        }
    }
    if (ameEffectiveRadius > 0.0) {
        cell.contentView.layer.cornerRadius = ameEffectiveRadius;
        cell.contentView.layer.cornerCurve = kCACornerCurveContinuous;   // ★ [CORNER-FIX] Match system cards.
        cell.contentView.layer.masksToBounds = YES;
    }

    cell.backgroundColor = UIColor.clearColor;
    objc_setAssociatedObject(cell.contentView, "ameNoPanelRim", @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [self applyEffectToView:cell.contentView];
}

- (void)applyEffectToSearchBar:(UISearchBar *)searchBar {
    if (!searchBar) return;

    // 1. Make the entire searchBar background transparent so the custom launcher background shows through.
    //    UISearchBar defaults to opaque systemBackgroundColor, which hides the global background image/glass.
    searchBar.barTintColor = [UIColor clearColor];
    searchBar.backgroundColor = [UIColor clearColor];
    searchBar.translucent = YES;
    // Minimal style prevents the system from drawing an opaque background, retaining only the input field background.
    searchBar.searchBarStyle = UISearchBarStyleMinimal;
    // Remove the opaque _UISearchBarBackground view added automatically by the system.
    for (UIView *sub in searchBar.subviews) {
        for (UIView *inner in sub.subviews) {
            if ([NSStringFromClass(inner.class) containsString:@"Background"]) {
                inner.backgroundColor = [UIColor clearColor];
                inner.hidden = NO;
            }
        }
        if ([NSStringFromClass(sub.class) containsString:@"Background"]) {
            sub.backgroundColor = [UIColor clearColor];
        }
    }

    // 2. Make the inner UITextField (search input) background transparent.
    //    UITextField defaults to a light-gray systemFillColor background that obscures the custom background.
    UITextField *textField = nil;
    for (UIView *sub in searchBar.subviews) {
        for (UIView *inner in sub.subviews) {
            if ([inner isKindOfClass:[UITextField class]]) {
                textField = (UITextField *)inner;
                break;
            }
        }
        if (textField) break;
    }
    // On iOS 13+, use -searchTextField directly.
    if (!textField && [searchBar respondsToSelector:@selector(searchTextField)]) {
        @try {
            textField = [searchBar performSelector:@selector(searchTextField)];
        } @catch (NSException *e) {
            textField = nil;
        }
    }
    if (textField) {
        if (self.uiEffect == BackgroundUIEffectBlur) {
            // Frosted glass: give the input field a light, translucent background so text stays
            // readable without obscuring the background.
            if (@available(iOS 13.0, *)) {
                textField.backgroundColor = [[UIColor secondarySystemBackgroundColor] colorWithAlphaComponent:0.5];
            } else {
                textField.backgroundColor = [UIColor colorWithWhite:0.95 alpha:0.5];
            }
        } else {
            // Translucent effect: adjust the input-field background according to uiOpacity.
            if (@available(iOS 13.0, *)) {
                textField.backgroundColor = [[UIColor secondarySystemBackgroundColor] colorWithAlphaComponent:MAX(0.3, self.uiOpacity)];
            } else {
                textField.backgroundColor = [UIColor colorWithWhite:0.95 alpha:MAX(0.3, self.uiOpacity)];
            }
        }
    }
}

#pragma mark - Legacy Methods

- (void)applyBackgroundToView:(UIView *)view {
    // Find the view controller or window
    UIResponder *responder = view;
    while (responder) {
        if ([responder isKindOfClass:[UISplitViewController class]]) {
            [self applyBackgroundToSplitViewController:(UISplitViewController *)responder];
            return;
        }
        if ([responder isKindOfClass:[UIWindow class]]) {
            [self applyBackgroundToWindow:(UIWindow *)responder];
            return;
        }
        responder = responder.nextResponder;
    }
}

- (void)removeBackgroundFromView:(UIView *)view {
    [self removeGlobalBackground];
}

#pragma mark - Video Management

- (void)cleanupVideoPlayer {
    if (self.videoPlayer) {
        [self.videoPlayer pause];
        self.videoPlayer = nil;
    }
    if (self.videoPlayerLayer) {
        [self.videoPlayerLayer removeFromSuperlayer];
        self.videoPlayerLayer = nil;
    }
}

- (void)playerItemDidReachEnd:(NSNotification *)notification {
    AVPlayerItem *playerItem = notification.object;
    [playerItem seekToTime:kCMTimeZero completionHandler:nil];
}

#pragma mark - App Lifecycle

- (void)appDidEnterBackground {
    [self pauseVideo];
}

- (void)appWillEnterForeground {
    [self resumeVideo];
}

- (void)pauseVideo {
    if (self.videoPlayer) [self.videoPlayer pause];
}

- (void)resumeVideo {
    if (self.videoPlayer) {
        [self.videoPlayer play];
    }
}

#pragma mark - Set Background

- (void)setImageBackground:(UIImage *)image completion:(void (^)(BOOL success, NSError * _Nullable error))completion {
    if (!image) {
        if (completion) {
            completion(NO, [NSError errorWithDomain:@"BackgroundManager" code:1 userInfo:@{NSLocalizedDescriptionKey: localize(@"i18n_str_48", nil)}]);
        }
        return;
    }
    
    NSUUID *selection = NSUUID.UUID;
    self.pendingWallpaperSelection = selection;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        // Save image
        NSString *fileName = [NSString stringWithFormat:@"background_image_%@.jpg", NSUUID.UUID.UUIDString];
        NSString *filePath = [[self backgroundsFolderPath] stringByAppendingPathComponent:fileName];
        
        NSData *imageData = UIImageJPEGRepresentation(image, 0.85);
        if (!imageData) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (completion) completion(NO, [NSError errorWithDomain:@"BackgroundManager" code:2 userInfo:@{NSLocalizedDescriptionKey: localize(@"i18n_str_49", nil)}]);
            });
            return;
        }
        
        BOOL saved = [imageData writeToFile:filePath atomically:YES];
        
        if (saved) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (self.pendingWallpaperSelection != selection) {
                    [[NSFileManager defaultManager] removeItemAtPath:filePath error:nil];
                    if (completion) completion(NO, [NSError errorWithDomain:NSCocoaErrorDomain code:NSUserCancelledError userInfo:nil]);
                    return;
                }
                [self clearBackgroundInternal];
                self.currentType = BackgroundTypeImage;
                self.currentBackgroundPath = filePath;
                [self saveBackgroundSettings];
                self.cachedBackgroundImage = image;
                self.cachedImagePath = filePath;
                // Reapply if needed
                if (self.currentSplitVC) {
                    [self applyBackgroundToSplitViewController:self.currentSplitVC];
                } else if (self.currentWindow) {
                    [self applyBackgroundToWindow:self.currentWindow];
                }
                
                if (completion) completion(YES, nil);
            });
        } else {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (completion) completion(NO, [NSError errorWithDomain:@"BackgroundManager" code:3 userInfo:@{NSLocalizedDescriptionKey: localize(@"i18n_str_50", nil)}]);
            });
        }
    });
}

- (void)setVideoBackgroundWithURL:(NSURL *)videoURL completion:(void (^)(BOOL success, NSError * _Nullable error))completion {
    if (!videoURL) {
        if (completion) {
            completion(NO, [NSError errorWithDomain:@"BackgroundManager" code:4 userInfo:@{NSLocalizedDescriptionKey: localize(@"i18n_str_51", nil)}]);
        }
        return;
    }
    // ★ [ISSUE-FIX] #92: videos selected from the Files app (UIDocumentPickerViewController) use
    //   security-scoped URLs. Without startAccessingSecurityScopedResource, fileExistsAtPath: /
    //   copyItemAtURL: both fail ⇒ the user sees "Video file does not exist" (i18n_str_51).
    //   Hold the security scope while reading/copying and release it immediately afterward.
    //   Temporary URLs returned by Photos (UIImagePickerController) are not scoped:
    //   start returns NO, so nothing needs to be released.
    BOOL ame92Scoped = videoURL.isFileURL ? [videoURL startAccessingSecurityScopedResource] : NO;
    if (![[NSFileManager defaultManager] fileExistsAtPath:videoURL.path]) {
        if (ame92Scoped) [videoURL stopAccessingSecurityScopedResource];
        if (completion) {
            completion(NO, [NSError errorWithDomain:@"BackgroundManager" code:4 userInfo:@{NSLocalizedDescriptionKey: localize(@"i18n_str_51", nil)}]);
        }
        return;
    }
    
    NSUUID *selection = NSUUID.UUID;
    self.pendingWallpaperSelection = selection;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        // Copy video
        NSString *fileName = [NSString stringWithFormat:@"background_video_%@.mp4", NSUUID.UUID.UUIDString];
        NSString *filePath = [[self backgroundsFolderPath] stringByAppendingPathComponent:fileName];
        
        NSError *copyError = nil;
        BOOL copied = [[NSFileManager defaultManager] copyItemAtURL:videoURL toURL:[NSURL fileURLWithPath:filePath] error:&copyError];
        // ★ [ISSUE-FIX] #92: once copying is complete, release the security scope (subsequent
        // operations use only the copy in the sandbox).
        if (ame92Scoped) [videoURL stopAccessingSecurityScopedResource];
        
        if (copied) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (self.pendingWallpaperSelection != selection) {
                    [[NSFileManager defaultManager] removeItemAtPath:filePath error:nil];
                    if (completion) completion(NO, [NSError errorWithDomain:NSCocoaErrorDomain code:NSUserCancelledError userInfo:nil]);
                    return;
                }
                [self clearBackgroundInternal];
                self.currentType = BackgroundTypeVideo;
                self.currentBackgroundPath = filePath;
                [self saveBackgroundSettings];
                // Reapply if needed
                if (self.currentSplitVC) {
                    [self applyBackgroundToSplitViewController:self.currentSplitVC];
                } else if (self.currentWindow) {
                    [self applyBackgroundToWindow:self.currentWindow];
                }
                
                if (completion) completion(YES, nil);
            });
        } else {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (completion) completion(NO, copyError ?: [NSError errorWithDomain:@"BackgroundManager" code:5 userInfo:@{NSLocalizedDescriptionKey: localize(@"i18n_str_52", nil)}]);
            });
        }
    });
}

- (void)clearBackground {
    self.pendingWallpaperSelection = nil;
    UIWindow *window = self.currentWindow;
    UISplitViewController *split = self.currentSplitVC;
    [self clearBackgroundInternal];
    [self saveBackgroundSettings];
    // Install the established default immediately, retaining the presentation host for future picks.
    if (split) [self applyBackgroundToSplitViewController:split];
    else if (window) [self applyBackgroundToWindow:window];
    [self refreshUIEffect];
}

- (void)clearBackgroundInternal {
    [self cleanupVideoPlayer];
    // Delete only app-owned wallpaper copies, never arbitrary persisted Documents paths.
    NSString *path = self.currentBackgroundPath.stringByStandardizingPath;
    NSString *folder = [[self backgroundsFolderPath].stringByStandardizingPath stringByAppendingString:@"/"];
    NSString *name = path.lastPathComponent;
    if ([path hasPrefix:folder] && ([name hasPrefix:@"background_image_"] || [name hasPrefix:@"background_video_"])) {
        [[NSFileManager defaultManager] removeItemAtPath:path error:nil];
    }
    self.cachedBackgroundImage = nil;
    self.cachedImagePath = nil;
    self.currentType = BackgroundTypeNone;
    self.currentBackgroundPath = nil;
}

#pragma mark - Check Background

- (BOOL)hasBackground {
    return self.currentType != BackgroundTypeNone && self.currentBackgroundPath != nil;
}

- (BOOL)hasImageBackground {
    return self.currentType == BackgroundTypeImage && self.currentBackgroundPath != nil;
}

- (BOOL)hasVideoBackground {
    return self.currentType == BackgroundTypeVideo && self.currentBackgroundPath != nil;
}

#pragma mark - Preview

- (nullable UIImage *)backgroundPreview {
    if (self.currentType == BackgroundTypeImage && self.currentBackgroundPath) {
        return [self.cachedImagePath isEqualToString:self.currentBackgroundPath] ? self.cachedBackgroundImage : nil;
    }
    return nil;
}


// ★ [UI-B] Recursively refresh glass highlights (the frame does not change with autoresizing and
// must be reset after layout).
- (void)ameRefreshRimsRecursive:(UIView *)v {
    if (!v) return;
    AmeRefreshGlassRim(v);
    for (UIView *sub in v.subviews) { [self ameRefreshRimsRecursive:sub]; }
}

#pragma mark - ★ [GLASSUI] Apply glass highlight settings immediately

// Traverse the view tree: remove and rebuild highlights at the current switch/intensity only on
// views that already have a highlight layer (tag 'MRIM').
// Off ⇒ AmeDetachGlassRim removes it; on ⇒ AmeAttachGlassRim rebuilds at the new intensity
// (it checks the intensity internally and does nothing when it is 0).
// Highlights added by the main path (applyEffectToView:) and by other files are both rebuilt here.
- (void)ameApplyGlassRimSettingsToViewTree:(UIView *)root {
    if (root == nil) { return; }
    static const NSInteger kAmeGlassRimTag = 0x4D52494D;   // 'MRIM', matches UIKit+GlassSurface.h
    // ★ [RIM-STATE] The "carrier" check must not depend on the switch:
    //   The old logic checked only whether a highlight sublayer was currently attached. After
    //   turning highlights off, every carrier had no sublayer, so this code skipped them when
    //   highlights were turned back on: the switch was on but no highlights appeared. Newly
    //   created/reused cells each followed the switch independently, which looked "random / like
    //   the switch was ignored this time" to users. Now use a persistent "highlight carrier" marker.
    BOOL isCarrier = AmeIsGlassRimHost(root);
    if (!isCarrier) {
        for (UIView *sub in root.subviews) {
            if (sub.tag == kAmeGlassRimTag) { isCarrier = YES; break; }
        }
    }
    if (isCarrier) {
        [self ameSyncGlassRimStrengthForCurrentStyle];   // ★ [GLASS-STYLE] Native style ⇒ always 0
        AmeDetachGlassRim(root);                         // ★ Remove first to ensure only one layer remains.
        if (AMEGlassStyleAllowsHandDrawnGlass() && self.glassRimEnabled && self.glassRimStrength > 0.001) {
            AmeAttachGlassRim(root, root.layer.cornerRadius);   // ★ Add according to current switch
                                                                // (native/off ⇒ immediate no-op internally).
        }
        AmeRefreshGlassRim(root);
    }
    for (UIView *sub in [root.subviews copy]) {
        [self ameApplyGlassRimSettingsToViewTree:sub];
    }
}

// Immediately apply the current switch/intensity to all windows (coalescing duplicate calls in the
// same run loop), then broadcast a notification for each page to reapply it.
- (void)applyGlassRimSettingsNow {
    [self ameSyncGlassRimStrengthForCurrentStyle];   // ★ [GLASS-STYLE]
    if (gAmeGlassRimApplyScheduled) { return; }   // ★ Already queued in this run loop ⇒ coalesce; do not traverse again.
    gAmeGlassRimApplyScheduled = YES;
    dispatch_async(dispatch_get_main_queue(), ^{
        gAmeGlassRimApplyScheduled = NO;
        for (UIWindow *w in [UIApplication sharedApplication].windows) {
            [self ameApplyGlassRimSettingsToViewTree:w];
        }
        [self refreshUIEffect];
    });
}

#pragma mark - ★ [GLASS-STYLE] Apply UI style (native / Liquid Glass) immediately

// Constrain hand-drawn glass intensity by the actual style: native (iOS<26 or user selected native
// on iOS>=26) ⇒ always 0; Liquid Glass ⇒ controlled by the "highlight switch + intensity slider".
// All writes to the global intensity go through this method to prevent conflicts between style and switch.
- (void)ameSyncGlassRimStrengthForCurrentStyle {
    CGFloat s = 0.0;
    if (AMEGlassStyleAllowsHandDrawnGlass() && self.glassRimEnabled) { s = self.glassRimStrength; }
    AmeSetGlassRimStrength(s);
}

// Traverse the view tree and resolve already-added glass layers again using the current style.
// Only consider layers marked with our tag (kBackgroundBlurTag). This includes the wallpaper
// container's blur layer, which has no managed marker; therefore, change only its material and
// never overlay a white fill.
- (void)ameReapplyGlassStyleToViewTree:(UIView *)root {
    // Interface glass changes must never replace the independent wallpaper material.
    if (root == nil || root == self.globalBackgroundContainer) { return; }
    for (UIView *sub in [root.subviews copy]) {
        if ([sub isKindOfClass:[UIVisualEffectView class]] && sub.tag == kBackgroundBlurTag) {
            UIVisualEffectView *vev = (UIVisualEffectView *)sub;
            // Host type determines fallback material: list/collection rows use SystemMaterial, while
            // panels/cards/containers use SystemThinMaterial (matching the original choices in
            // applyEffectToCell: / applyEffectToView: / applyEffectToCollectionViewCell:).
            BOOL isRow = [vev.superview isKindOfClass:[UITableViewCell class]] ||
                         [vev.superview isKindOfClass:[UICollectionViewCell class]] ||
                         [vev.superview.superview isKindOfClass:[UITableViewCell class]] ||
                         [vev.superview.superview isKindOfClass:[UICollectionViewCell class]];
            // An explicit style change replaces the system material; slider updates never do.
            vev.effect = AmeGlassEffect(isRow ? UIBlurEffectStyleSystemMaterial : UIBlurEffectStyleSystemThinMaterial);
            objc_setAssociatedObject(vev, "ameInterfaceStyle", @(AMEGlassStyleResolved()), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            if (AmeIsManagedGlass(vev)) {
                AmeApplyGlassFillForCurrentStyle(vev);
            }
        }
        [self ameReapplyGlassStyleToViewTree:sub];
    }
}

// UI style changed (Settings → AMEGlassStyleSetConfigured → notification) ⇒ refresh immediately:
//   ① Constrain hand-drawn glass intensity; ② resolve material/fill/tuning again for all existing
//      glass layers; ③ rebuild highlights; ④ broadcast BackgroundUIEffectChanged so each page
//      reapplies the new style (navigation/toolbar appearances are rebuilt in their own apply methods).
- (void)ameGlassStyleChanged:(NSNotification *)note {
    (void)note;
    [self ameSyncGlassRimStrengthForCurrentStyle];
    dispatch_async(dispatch_get_main_queue(), ^{
        for (UIWindow *w in [UIApplication sharedApplication].windows) {
            [self ameReapplyGlassStyleToViewTree:w];
            [self ameApplyGlassRimSettingsToViewTree:w];
        }
        [self refreshUIEffect];
        NSLog(@"[glass] UI style change applied: configured=%@ · actually in effect=%@",
              AMEGlassStyleStringFromEnum(AMEGlassStyleConfigured()),
              AMEGlassStyleStringFromEnum(AMEGlassStyleResolved()));
    });
}
@end