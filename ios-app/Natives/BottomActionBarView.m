#import "BottomActionBarView.h"
#import "UIKit+GlassSurface.h"    // AmeInstallGlassBackdrop / AmeGlassEffect
#import "LauncherPreferences.h"   // getPrefObject / accentColor (theme color)

// Same height as the start capsule (kNoRightCapsuleHeight in LauncherNewsViewController.m).
static const CGFloat kBarButtonHeight = 36.0;

UIColor *AmeThemeTintColor(void) {
    id hex = getPrefObject(@"general.accent_color");
    if ([hex isKindOfClass:[NSString class]] && [(NSString *)hex length] > 0) {
        return accentColor();
    }
    return [UIColor colorWithRed:1.0 green:0.43 blue:0.78 alpha:1.0];   // default pink
}

@interface AmePinkGlassButton ()
@property (nonatomic, strong) UIVisualEffectView *blurView;
@property (nonatomic, strong) UIActivityIndicatorView *activityIndicator;
@end

@implementation AmePinkGlassButton

- (void)ameBuildGlassIfNeeded {
    if (self.blurView) return;
    self.backgroundColor = UIColor.clearColor;
    self.layer.cornerCurve = kCACornerCurveContinuous;
    self.clipsToBounds = YES;

    // One native material, beneath UIKit's title/image. No gesture recognizer or action forwarding.
    self.blurView = [[UIVisualEffectView alloc] initWithEffect:AmeGlassEffect(UIBlurEffectStyleSystemThinMaterial)];
    self.blurView.userInteractionEnabled = NO;
    self.blurView.isAccessibilityElement = NO;
    self.blurView.clipsToBounds = YES;
    self.blurView.layer.cornerCurve = kCACornerCurveContinuous;
    [self insertSubview:self.blurView atIndex:0];

    self.titleLabel.font = AmeUIFont(AmeUIFontRoleButton);
    self.titleLabel.adjustsFontForContentSizeCategory = YES;
    for (NSString *name in @[@"LauncherAppearanceChanged", @"UIThemeChanged", AMEGlassStyleChangedNotification]) {
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(ameAppearanceChanged:)
                                                     name:name object:nil];
    }
    [self ameApplyThemeColors];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)ameAppearanceChanged:(NSNotification *)notification {
    // Replace the effect only for a material-style change, not for every layout/theme update.
    if ([notification.name isEqualToString:AMEGlassStyleChangedNotification]) {
        self.blurView.effect = AmeGlassEffect(UIBlurEffectStyleSystemThinMaterial);
    }
    [self ameApplyThemeColors];
}

- (void)ameApplyThemeColors {
    UIColor *foreground = AmeUIPrimaryTextColor();
    if (self.ameRole == AmeGlassButtonRolePrimary) foreground = AmeUIAccentColor();
    if (self.ameRole == AmeGlassButtonRoleSubtle) foreground = AmeUISecondaryTextColor();
    if (self.ameRole == AmeGlassButtonRoleDestructive) foreground = AmeUIDestructiveColor();
    self.tintColor = self.enabled ? foreground : AmeUIDisabledColor();
    [self setTitleColor:foreground forState:UIControlStateNormal];
    [self setTitleColor:AmeUIDisabledColor() forState:UIControlStateDisabled];
    [self setTitleColor:foreground forState:UIControlStateHighlighted];
    [self setTitleColor:foreground forState:UIControlStateSelected];

    // Quiet native surfaces replace the old permanent neon glow. Keep hand-drawn tint opt-in.
    BOOL selectedPill = self.ameRole == AmeGlassButtonRoleNavigation && self.selected;
    self.blurView.contentView.backgroundColor = selectedPill ? AmeUISelectedFillColor() : UIColor.clearColor;
    if (!selectedPill && AMEGlassStyleAllowsHandDrawnGlass()) {
        self.blurView.contentView.backgroundColor = [foreground colorWithAlphaComponent:0.08];
    }
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    self.layer.borderWidth = AmeUIHairlineWidth(self);
    self.layer.borderColor = AmeUIResolvedColor(AmeUIBorderColor(), self).CGColor;
    [CATransaction commit];
    self.activityIndicator.color = foreground;
    [self ameUpdateControlAppearance];
}

- (void)ameUpdateControlAppearance {
    // Dim the decorative material, not the whole control: labels remain legible over wallpaper.
    self.blurView.alpha = self.enabled ? (self.highlighted ? 0.75 : 1.0) : 0.55;
    self.titleLabel.alpha = self.ameShowsActivityIndicator ? 0.0 : 1.0;
    self.imageView.alpha = self.ameShowsActivityIndicator ? 0.0 : 1.0;
}

- (void)setAmeRole:(AmeGlassButtonRole)ameRole {
    _ameRole = ameRole;
    [self ameApplyThemeColors];
}

- (void)setAmeShowsActivityIndicator:(BOOL)show {
    _ameShowsActivityIndicator = show;
    if (show && !self.activityIndicator) {
        self.activityIndicator = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
        self.activityIndicator.userInteractionEnabled = NO;
        self.activityIndicator.isAccessibilityElement = NO;
        self.activityIndicator.hidesWhenStopped = YES;
        [self addSubview:self.activityIndicator];
    }
    self.activityIndicator.color = self.tintColor;
    if (show) [self.activityIndicator startAnimating];
    else [self.activityIndicator stopAnimating];
    [self ameUpdateControlAppearance];
    [self setNeedsLayout];
}

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) [self ameBuildGlassIfNeeded];
    return self;
}

- (instancetype)initWithCoder:(NSCoder *)coder {
    self = [super initWithCoder:coder];
    if (self) [self ameBuildGlassIfNeeded];
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat radius = MIN(self.bounds.size.width, self.bounds.size.height) / 2.0;
    self.layer.cornerRadius = radius;
    self.blurView.frame = self.bounds;
    self.blurView.layer.cornerRadius = radius;
    self.activityIndicator.center = CGPointMake(CGRectGetMidX(self.bounds), CGRectGetMidY(self.bounds));
    [self sendSubviewToBack:self.blurView];
    [self ameUpdateControlAppearance];
}

- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];
    // UIKit resolves semantic view colors; explicitly refresh CGColor snapshots for borders.
    [self ameApplyThemeColors];
}

- (void)setEnabled:(BOOL)enabled {
    [super setEnabled:enabled];
    [self ameApplyThemeColors];
}

- (void)setSelected:(BOOL)selected {
    [super setSelected:selected];
    [self ameApplyThemeColors];
}

- (void)setHighlighted:(BOOL)highlighted {
    [super setHighlighted:highlighted];
    [self ameUpdateControlAppearance];
}

@end

void AmeApplyPinkGlassButtonStyle(UIButton *b) {
    if (![b isKindOfClass:[AmePinkGlassButton class]]) return;
    [(AmePinkGlassButton *)b ameBuildGlassIfNeeded];
    [(AmePinkGlassButton *)b ameApplyThemeColors];
    [b setNeedsLayout];
}

@interface BottomActionBarView ()
@end

@implementation BottomActionBarView

/// Existing bottom actions share the native secondary-action appearance.
static UIButton *MakeBarButton(NSString *title, NSString *icon) {
    UIButton *b = [AmePinkGlassButton buttonWithType:UIButtonTypeSystem];
    b.translatesAutoresizingMaskIntoConstraints = NO;
    ((AmePinkGlassButton *)b).ameRole = AmeGlassButtonRoleSecondary;
    b.titleLabel.font = AmeUIFont(AmeUIFontRoleButton);
    b.titleLabel.adjustsFontSizeToFitWidth = YES;
    b.titleLabel.minimumScaleFactor = 0.7;
    [b setTitle:title forState:UIControlStateNormal];
    [b setTitleColor:[UIColor labelColor] forState:UIControlStateNormal];
    UIImage *image = [[UIImage systemImageNamed:icon] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    if (image) [b setImage:image forState:UIControlStateNormal];
    b.imageEdgeInsets = UIEdgeInsetsMake(0, -6, 0, 0);
    b.titleEdgeInsets = UIEdgeInsetsMake(0, 6, 0, 0);
    b.contentHorizontalAlignment = UIControlContentHorizontalAlignmentCenter;
    AmeApplyPinkGlassButtonStyle(b);
    return b;
}

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return nil;
    _executeJarButton = MakeBarButton(@"Execute Jar", @"square.and.arrow.up");
    _chooseVersionButton = MakeBarButton(@"Choose Version", @"square.stack.3d.up.fill");

    UIStackView *row = [[UIStackView alloc] initWithArrangedSubviews:@[_executeJarButton, _chooseVersionButton]];
    row.axis = UILayoutConstraintAxisHorizontal;
    row.distribution = UIStackViewDistributionFillEqually;
    row.spacing = AmeUIItemSpacing;
    row.translatesAutoresizingMaskIntoConstraints = NO;
    [self addSubview:row];

    [NSLayoutConstraint activateConstraints:@[
        [row.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [row.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        [row.topAnchor constraintEqualToAnchor:self.topAnchor],
        [row.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
        [_executeJarButton.heightAnchor constraintEqualToConstant:kBarButtonHeight]
    ]];
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    for (UIButton *b in @[_executeJarButton, _chooseVersionButton]) {
        b.layer.cornerRadius = b.bounds.size.height / 2.0;
    }
}

@end
