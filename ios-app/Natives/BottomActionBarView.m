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
@property (nonatomic, strong) CAGradientLayer *tintLayer;        // translucent theme tint, edge to edge
@property (nonatomic, strong) CAGradientLayer *highlightLayer;   // specular sheen on the top half
@property (nonatomic, strong) CAGradientLayer *glowLayer;        // soft inner glow along the bottom edge
@property (nonatomic, strong) CAGradientLayer *rimLayer;         // gradient hairline (bright top, tinted bottom)
@property (nonatomic, strong) CAShapeLayer *rimMask;
@end

@implementation AmePinkGlassButton

- (void)ameBuildGlassIfNeeded {
    if (self.blurView) return;
    self.backgroundColor = UIColor.clearColor;
    self.clipsToBounds = NO;                       // lets the tinted glow shadow show; the glass clips itself
    self.layer.cornerCurve = kCACornerCurveContinuous;

    // 1) Glass base: the system Liquid Glass material on iOS 26+, a thin blur on older systems.
    self.blurView = [[UIVisualEffectView alloc] initWithEffect:AmeGlassEffect(UIBlurEffectStyleSystemUltraThinMaterial)];
    self.blurView.userInteractionEnabled = NO;
    self.blurView.clipsToBounds = YES;
    self.blurView.layer.cornerCurve = kCACornerCurveContinuous;
    [self insertSubview:self.blurView atIndex:0];

    // 2) Light theme tint over the glass (kept translucent so the wallpaper shows through).
    self.tintLayer = [CAGradientLayer layer];
    self.tintLayer.startPoint = CGPointMake(0.5, 0.0);
    self.tintLayer.endPoint = CGPointMake(0.5, 1.0);
    [self.blurView.contentView.layer addSublayer:self.tintLayer];

    // 3) Soft glow rising from the bottom edge (reads as light refracting through the glass).
    self.glowLayer = [CAGradientLayer layer];
    self.glowLayer.startPoint = CGPointMake(0.5, 1.0);
    self.glowLayer.endPoint = CGPointMake(0.5, 0.45);
    [self.blurView.contentView.layer addSublayer:self.glowLayer];

    // 4) Specular sheen along the top half.
    self.highlightLayer = [CAGradientLayer layer];
    self.highlightLayer.colors = @[
        (id)[UIColor colorWithWhite:1.0 alpha:0.50].CGColor,
        (id)[UIColor colorWithWhite:1.0 alpha:0.0].CGColor
    ];
    self.highlightLayer.startPoint = CGPointMake(0.5, 0.0);
    self.highlightLayer.endPoint = CGPointMake(0.5, 0.60);
    [self.blurView.contentView.layer addSublayer:self.highlightLayer];

    // 5) Gradient hairline rim (masked to a stroke): bright at the top, theme-tinted at the bottom.
    self.rimLayer = [CAGradientLayer layer];
    self.rimLayer.startPoint = CGPointMake(0.5, 0.0);
    self.rimLayer.endPoint = CGPointMake(0.5, 1.0);
    self.rimMask = [CAShapeLayer layer];
    self.rimMask.fillColor = UIColor.clearColor.CGColor;
    self.rimMask.strokeColor = UIColor.whiteColor.CGColor;
    self.rimMask.lineWidth = 1.2;
    self.rimLayer.mask = self.rimMask;
    [self.blurView.contentView.layer addSublayer:self.rimLayer];

    self.layer.shadowOffset = CGSizeMake(0, 4);
    self.layer.shadowRadius = 10.0;
    self.layer.shadowOpacity = 0.35;

    [self ameApplyThemeColors];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(ameApplyThemeColors)
                                                 name:@"LauncherAppearanceChanged"
                                               object:nil];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

/// Re-reads the theme color and recolors every tinted part (tint, glow, rim, icon, shadow).
- (void)ameApplyThemeColors {
    UIColor *tint = AmeThemeTintColor();
    self.tintColor = tint;
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    self.tintLayer.colors = @[
        (id)[tint colorWithAlphaComponent:0.30].CGColor,
        (id)[tint colorWithAlphaComponent:0.10].CGColor
    ];
    self.glowLayer.colors = @[
        (id)[tint colorWithAlphaComponent:0.38].CGColor,
        (id)[tint colorWithAlphaComponent:0.0].CGColor
    ];
    self.rimLayer.colors = @[
        (id)[UIColor colorWithWhite:1.0 alpha:0.80].CGColor,
        (id)[tint colorWithAlphaComponent:0.65].CGColor
    ];
    self.layer.shadowColor = tint.CGColor;
    [CATransaction commit];
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
    CGRect bounds = self.bounds;
    CGFloat radius = MIN(bounds.size.width, bounds.size.height) / 2.0;
    self.layer.cornerRadius = radius;
    self.layer.shadowPath = [UIBezierPath bezierPathWithRoundedRect:bounds cornerRadius:radius].CGPath;
    self.blurView.frame = bounds;
    self.blurView.layer.cornerRadius = radius;
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    self.tintLayer.frame = bounds;
    self.glowLayer.frame = bounds;
    self.highlightLayer.frame = bounds;
    self.rimLayer.frame = bounds;
    CGRect inset = CGRectInset(bounds, 0.6, 0.6);
    self.rimMask.frame = bounds;
    self.rimMask.path = [UIBezierPath bezierPathWithRoundedRect:inset cornerRadius:MIN(inset.size.width, inset.size.height) / 2.0].CGPath;
    [CATransaction commit];
    [self sendSubviewToBack:self.blurView];
}

- (void)setHighlighted:(BOOL)highlighted {
    [super setHighlighted:highlighted];
    self.alpha = highlighted ? 0.75 : 1.0;
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

/// Builds a button styled exactly like the "Sign In and Launch" capsule:
/// pink liquid glass, pink hairline border, subheadline label, pink icon.
static UIButton *MakeBarButton(NSString *title, NSString *icon) {
    UIButton *b = [AmePinkGlassButton buttonWithType:UIButtonTypeSystem];
    b.translatesAutoresizingMaskIntoConstraints = NO;
    b.titleLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleSubheadline];
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
    row.spacing = 8;
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
