#import "BottomActionBarView.h"
#import "UIKit+GlassSurface.h"    // AmeInstallGlassBackdrop / AmeGlassEffect

// Same height as the start capsule (kNoRightCapsuleHeight in LauncherNewsViewController.m).
static const CGFloat kBarButtonHeight = 36.0;

void AmeApplyPinkGlassButtonStyle(UIButton *b) {
    if (!b) return;
    UIColor *pink = [UIColor colorWithRed:1.0 green:0.43 blue:0.78 alpha:1.0];
    b.tintColor = pink;
    b.backgroundColor = UIColor.clearColor;
    b.layer.cornerCurve = kCACornerCurveContinuous;
    b.layer.borderWidth = 1.0;
    b.layer.borderColor = [pink colorWithAlphaComponent:0.55].CGColor;
    b.clipsToBounds = YES;
    // Always glass (system UIGlassEffect on iOS 26+, system blur material before that),
    // then a soft pink wash on top of the glass.
    UIVisualEffectView *glass = nil;
    if (AmeGlassEffect(UIBlurEffectStyleSystemThinMaterial) != nil) {
        glass = AmeInstallGlassBackdrop(b, 100.0, YES);
    }
    if (glass) {
        glass.contentView.backgroundColor = [pink colorWithAlphaComponent:0.20];
    } else {
        b.backgroundColor = [pink colorWithAlphaComponent:0.22];
    }
}

@interface BottomActionBarView ()
@end

@implementation BottomActionBarView

/// Builds a button styled exactly like the "Sign In and Launch" capsule:
/// pink liquid glass, pink hairline border, subheadline label, pink icon.
static UIButton *MakeBarButton(NSString *title, NSString *icon) {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
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
