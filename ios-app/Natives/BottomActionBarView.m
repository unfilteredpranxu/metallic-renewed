#import "BottomActionBarView.h"

@interface BottomActionBarView ()
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
    _executeJarButton = MakeBarButton(@"Execute Jar", @"square.and.arrow.up", 12);
    _chooseVersionButton = MakeBarButton(@"Choose Version", @"square.stack.3d.up.fill", 12);

    UIColor *dark = [UIColor colorWithRed:0.08 green:0.11 blue:0.13 alpha:0.85];
    _executeJarButton.backgroundColor = dark;
    _chooseVersionButton.backgroundColor = dark;

    UIStackView *row = [[UIStackView alloc] initWithArrangedSubviews:@[_executeJarButton, _chooseVersionButton]];
    row.axis = UILayoutConstraintAxisHorizontal;
    row.distribution = UIStackViewDistributionFillEqually;
    row.spacing = 12;

    row.spacing = 8;
    row.translatesAutoresizingMaskIntoConstraints = NO;
    [self addSubview:row];

    [NSLayoutConstraint activateConstraints:@[
        [row.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [row.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        [row.topAnchor constraintEqualToAnchor:self.topAnchor],
        [row.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
        [_executeJarButton.heightAnchor constraintEqualToConstant:34]
    ]];
    return self;
}
- (void)layoutSubviews {
    [super layoutSubviews];
    for (UIButton *b in @[_executeJarButton, _chooseVersionButton]) {
        b.layer.cornerRadius = b.bounds.size.height / 2;
    }
}

@end