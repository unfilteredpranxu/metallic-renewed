#import "BottomActionBarView.h"
#import "UIKit+GlassSurface.h"    // AmeInstallGlassBackdrop / AmeGlassEffect

// Same height as the start capsule (kNoRightCapsuleHeight in LauncherNewsViewController.m).
static const CGFloat kBarButtonHeight = 36.0;

static UIColor *PinkGlassColor(void) {
    return [UIColor colorWithRed:1.0 green:0.43 blue:0.78 alpha:1.0];
}

@interface AmePinkGlassButton ()
@property (nonatomic, strong) UIVisualEffectView *blurView;
@property (nonatomic, strong) CAGradientLayer *pinkLayer;
@property (nonatomic, strong) CAGradientLayer *highlightLayer;
@end

@implementation AmePinkGlassButton

- (void)ameBuildGlassIfNeeded {
    if (self.blurView) return;
    UIColor *pink = PinkGlassColor();
    self.backgroundColor = UIColor.clearColor;
    self.clipsToBounds = YES;
    self.layer.cornerCurve = kCACornerCurveContinuous;
    self.layer.borderWidth = 1.0;
    self.layer.borderColor = [pink colorWithAlphaComponent:0.6].CGColor;
    self.tintColor = pink;

    // 1) Glass base (plain system blur: renders identically on every iOS version).
    self.blurView = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemUltraThinMaterialDark]];
    self.blurView.userInteractionEnabled = NO;
    self.blurView.clipsToBounds = YES;
    [self insertSubview:self.blurView atIndex:0];

    // 2) Pink gradient over the glass, edge to edge.
    self.pinkLayer = [CAGradientLayer layer];
    self.pinkLayer.colors = @[
        (id)[pink colorWithAlphaComponent:0.42].CGColor,
        (id)[pink colorWithAlphaComponent:0.22].CGColor
    ];
    self.pinkLayer.startPoint = CGPointMake(0.5, 0.0);
    self.pinkLayer.endPoint = CGPointMake(0.5, 1.0);
    [self.blurView.contentView.layer addSublayer:self.pinkLayer];

    // 3) Soft white sheen along the top half for the glassy look.
    self.highlightLayer = [CAGradientLayer layer];
    self.highlightLayer.colors = @[
        (id)[UIColor colorWithWhite:1.0 alpha:0.28].CGColor,
        (id)[UIColor colorWithWhite:1.0 alpha:0.0].CGColor
    ];
    self.highlightLayer.startPoint = CGPointMake(0.5, 0.0);
    self.highlightLayer.endPoint = CGPointMake(0.5, 0.65);
    [self.blurView.contentView.layer addSublayer:self.highlightLayer];
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
    self.blurView.frame = bounds;
    self.blurView.layer.cornerRadius = radius;
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    self.pinkLayer.frame = bounds;
    self.highlightLayer.frame = bounds;
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
    b.tintColor = PinkGlassColor();
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
