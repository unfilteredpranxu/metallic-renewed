#import "BottomActionBarView.h"
#import "LauncherPreferences.h"   // accentColor() — the same accent the start button uses

// Same height as the start capsule (kNoRightCapsuleHeight in LauncherNewsViewController.m).
static const CGFloat kBarButtonHeight = 36.0;

@interface BottomActionBarView ()
@end

@implementation BottomActionBarView

/// Builds a button styled exactly like the "Sign In and Launch" capsule:
/// accent-tinted 15% fill, 1pt accent border, subheadline label, accent icon.
static UIButton *MakeBarButton(NSString *title, NSString *icon) {
    UIColor *accent = accentColor() ?: [UIColor systemBlueColor];
    UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
    b.translatesAutoresizingMaskIntoConstraints = NO;
    b.titleLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleSubheadline];
    b.titleLabel.adjustsFontSizeToFitWidth = YES;
    b.titleLabel.minimumScaleFactor = 0.7;
    [b setTitle:title forState:UIControlStateNormal];
    [b setTitleColor:[UIColor labelColor] forState:UIControlStateNormal];
    UIImage *image = [[UIImage systemImageNamed:icon] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    if (image) [b setImage:image forState:UIControlStateNormal];
    b.tintColor = accent;
    b.imageEdgeInsets = UIEdgeInsetsMake(0, -6, 0, 0);
    b.titleEdgeInsets = UIEdgeInsetsMake(0, 6, 0, 0);
    b.contentHorizontalAlignment = UIControlContentHorizontalAlignmentCenter;
    b.backgroundColor = [accent colorWithAlphaComponent:0.15];
    b.layer.borderWidth = 1.0;
    b.layer.borderColor = accent.CGColor;
    b.layer.cornerCurve = kCACornerCurveContinuous;
    b.clipsToBounds = YES;
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
