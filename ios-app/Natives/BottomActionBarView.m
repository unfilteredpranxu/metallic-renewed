#import "BottomActionBarView.h"

@interface BottomActionBarView ()
@property (nonatomic, strong) CAGradientLayer *launchGradient;
@end

@implementation BottomActionBarView

static UIButton *MakeBarButton(NSString *title, NSString *icon, CGFloat size) {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeCustom];
    b.translatesAutoresizingMaskIntoConstraints = NO;
    b.titleLabel.font = [UIFont systemFontOfSize:size weight:UIFontWeightSemibold];
    [b setTitle:title forState:UIControlStateNormal];
    [b setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    [b setImage:[UIImage systemImageNamed:icon] forState:UIControlStateNormal];
    b.tintColor = [UIColor colorWithWhite:0.9 alpha:1];
    b.titleEdgeInsets = UIEdgeInsetsMake(0, 8, 0, -8);
    b.layer.borderWidth = 1.5;
    b.layer.borderColor = [UIColor colorWithWhite:0.85 alpha:0.9].CGColor;
    b.clipsToBounds = YES;
    return b;
}
- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return nil;
    _launchButton = MakeBarButton(@"Launch Game", @"play.fill", 22);
    _executeJarButton = MakeBarButton(@"Execute Jar", @"square.and.arrow.up", 16);
    _chooseVersionButton = MakeBarButton(@"Choose Version", @"square.stack.3d.up.fill", 16);

    _launchGradient = [CAGradientLayer layer];
    _launchGradient.colors = @[(id)[UIColor colorWithRed:0.10 green:0.25 blue:0.55 alpha:1].CGColor,
                               (id)[UIColor colorWithRed:0.02 green:0.08 blue:0.25 alpha:1].CGColor];
    [_launchButton.layer insertSublayer:_launchGradient atIndex:0];

    UIColor *dark = [UIColor colorWithRed:0.08 green:0.11 blue:0.13 alpha:0.85];
    _executeJarButton.backgroundColor = dark;
    _chooseVersionButton.backgroundColor = dark;

    UIStackView *row = [[UIStackView alloc] initWithArrangedSubviews:@[_executeJarButton, _chooseVersionButton]];
    row.axis = UILayoutConstraintAxisHorizontal;
    row.distribution = UIStackViewDistributionFillEqually;
    row.spacing = 12;

    UIStackView *col = [[UIStackView alloc] initWithArrangedSubviews:@[_launchButton, row]];
    col.axis = UILayoutConstraintAxisVertical;
    col.spacing = 12;
    col.translatesAutoresizingMaskIntoConstraints = NO;
    [self addSubview:col];

    [NSLayoutConstraint activateConstraints:@[
        [col.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [col.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        [col.topAnchor constraintEqualToAnchor:self.topAnchor],
        [col.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
        [_launchButton.heightAnchor constraintEqualToConstant:64],
        [_executeJarButton.heightAnchor constraintEqualToConstant:52]
    ]];
    return self;
}
- (void)layoutSubviews {
    [super layoutSubviews];
    _launchGradient.frame = _launchButton.bounds;
    for (UIButton *b in @[_launchButton, _executeJarButton, _chooseVersionButton]) {
        b.layer.cornerRadius = b.bounds.size.height / 2;
    }
}

@end