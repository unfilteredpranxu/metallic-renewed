#import "HomeActionPanelView.h"

static const CGFloat kCollapsedHeight = 70.0;
static const CGFloat kExpandedHeight = 210.0;

static UIColor *PanelAccentColor(void) {
    return [UIColor colorWithRed:0.38 green:0.69 blue:1.0 alpha:1.0];
}

static UIButton *MakeHiddenActionButton(NSString *title, NSString *symbol) {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    button.translatesAutoresizingMaskIntoConstraints = NO;
    [button setTitle:title forState:UIControlStateNormal];
    [button setImage:[UIImage systemImageNamed:symbol] forState:UIControlStateNormal];
    button.hidden = YES;
    return button;
}

static void ApplyGlass(UIView *host) {
    UIVisualEffect *effect = [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemThinMaterialDark];
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 260000
    if (@available(iOS 26.0, *)) {
        UIGlassEffect *glass = [[UIGlassEffect alloc] init];
        glass.interactive = YES;
        effect = glass;
    }
#endif
    UIVisualEffectView *glassView = [[UIVisualEffectView alloc] initWithEffect:effect];
    glassView.translatesAutoresizingMaskIntoConstraints = NO;
    glassView.userInteractionEnabled = NO;
    glassView.layer.cornerRadius = 22.0;
    glassView.clipsToBounds = YES;
    host.backgroundColor = UIColor.clearColor;
    [host insertSubview:glassView atIndex:0];
    [NSLayoutConstraint activateConstraints:@[
        [glassView.leadingAnchor constraintEqualToAnchor:host.leadingAnchor],
        [glassView.trailingAnchor constraintEqualToAnchor:host.trailingAnchor],
        [glassView.topAnchor constraintEqualToAnchor:host.topAnchor],
        [glassView.bottomAnchor constraintEqualToAnchor:host.bottomAnchor]
    ]];
}

@interface HomeActionPanelView ()
@property (nonatomic, assign, readwrite) BOOL expanded;
@property (nonatomic, strong, readwrite) UIImageView *avatarView;
@property (nonatomic, strong, readwrite) UIButton *toggleButton;
@property (nonatomic, strong, readwrite) UIButton *launchButton;
@property (nonatomic, strong, readwrite) UIButton *executeJarButton;
@property (nonatomic, strong, readwrite) UIButton *chooseVersionButton;
@property (nonatomic, strong) UILabel *accountNameLabel;
@property (nonatomic, strong) UIStackView *cardStack;
@property (nonatomic, strong) UILabel *launcherValue;
@property (nonatomic, strong) UILabel *gameValue;
@property (nonatomic, strong) UILabel *deviceValue;
@property (nonatomic, strong) NSLayoutConstraint *heightConstraint;
@property (nonatomic, strong) NSLayoutConstraint *cardStackTopConstraint;
@property (nonatomic, strong) NSLayoutConstraint *cardStackBottomConstraint;
@end

@implementation HomeActionPanelView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        [self buildUI];
        ApplyGlass(self);
        [self setExpanded:YES animated:NO];
    }
    return self;
}

- (UIView *)cardWithIcon:(NSString *)icon title:(NSString *)title valueLabel:(UILabel *)value {
    UIView *card = [[UIView alloc] init];
    card.translatesAutoresizingMaskIntoConstraints = NO;
    card.backgroundColor = [UIColor colorWithWhite:0.04 alpha:0.45];
    card.layer.cornerRadius = 12.0;
    card.layer.borderWidth = 1.0;
    card.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.15].CGColor;
    [card.heightAnchor constraintEqualToConstant:40.0].active = YES;

    UIImageView *iconView = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:icon]];
    iconView.translatesAutoresizingMaskIntoConstraints = NO;
    iconView.contentMode = UIViewContentModeScaleAspectFit;
    iconView.tintColor = PanelAccentColor();

    UILabel *titleLabel = [[UILabel alloc] init];
    titleLabel.text = title;
    titleLabel.font = [UIFont systemFontOfSize:10.5 weight:UIFontWeightMedium];
    titleLabel.textColor = [UIColor colorWithWhite:1.0 alpha:0.72];

    value.font = [UIFont systemFontOfSize:11.5 weight:UIFontWeightSemibold];
    value.textColor = UIColor.whiteColor;
    value.numberOfLines = 1;
    value.adjustsFontSizeToFitWidth = YES;
    value.minimumScaleFactor = 0.75;

    UIStackView *textStack = [[UIStackView alloc] initWithArrangedSubviews:@[titleLabel, value]];
    textStack.translatesAutoresizingMaskIntoConstraints = NO;
    textStack.axis = UILayoutConstraintAxisVertical;
    textStack.spacing = 1.0;

    [card addSubview:iconView];
    [card addSubview:textStack];
    [NSLayoutConstraint activateConstraints:@[
        [iconView.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:11.0],
        [iconView.centerYAnchor constraintEqualToAnchor:card.centerYAnchor],
        [iconView.widthAnchor constraintEqualToConstant:18.0],
        [iconView.heightAnchor constraintEqualToConstant:18.0],
        [textStack.leadingAnchor constraintEqualToAnchor:iconView.trailingAnchor constant:9.0],
        [textStack.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-10.0],
        [textStack.centerYAnchor constraintEqualToAnchor:card.centerYAnchor]
    ]];
    return card;
}

- (void)buildUI {
    self.layer.cornerRadius = 22.0;
    self.clipsToBounds = YES;

    self.avatarView = [[UIImageView alloc] init];
    self.avatarView.translatesAutoresizingMaskIntoConstraints = NO;
    self.avatarView.backgroundColor = [UIColor colorWithWhite:0.25 alpha:1.0];
    self.avatarView.layer.cornerRadius = 23.0;
    self.avatarView.layer.borderWidth = 1.0;
    self.avatarView.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.35].CGColor;
    self.avatarView.clipsToBounds = YES;
    self.avatarView.contentMode = UIViewContentModeScaleAspectFill;
    self.avatarView.userInteractionEnabled = YES;
    self.avatarView.image = [UIImage systemImageNamed:@"person.crop.circle.fill"];
    self.avatarView.tintColor = [UIColor colorWithWhite:0.82 alpha:1.0];
    [self.avatarView addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(profileTapped)]];
    [self addSubview:self.avatarView];

    self.accountNameLabel = [[UILabel alloc] init];
    self.accountNameLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.accountNameLabel.font = [UIFont systemFontOfSize:14.0 weight:UIFontWeightSemibold];
    self.accountNameLabel.textColor = UIColor.whiteColor;
    self.accountNameLabel.text = @"Not Logged In";
    self.accountNameLabel.numberOfLines = 1;
    self.accountNameLabel.adjustsFontSizeToFitWidth = YES;
    self.accountNameLabel.minimumScaleFactor = 0.75;
    self.accountNameLabel.userInteractionEnabled = YES;
    [self.accountNameLabel addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(profileTapped)]];
    [self addSubview:self.accountNameLabel];

    self.toggleButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.toggleButton.translatesAutoresizingMaskIntoConstraints = NO;
    self.toggleButton.tintColor = [UIColor colorWithWhite:0.88 alpha:1.0];
    [self.toggleButton addTarget:self action:@selector(toggleTapped) forControlEvents:UIControlEventTouchUpInside];
    [self addSubview:self.toggleButton];

    self.launchButton = MakeHiddenActionButton(@"Launch Game", @"play.fill");
    self.executeJarButton = MakeHiddenActionButton(@"Execute JAR", @"square.and.arrow.up");
    self.chooseVersionButton = MakeHiddenActionButton(@"Choose Version", @"square.stack.3d.up.fill");

    self.launcherValue = [[UILabel alloc] init];
    self.gameValue = [[UILabel alloc] init];
    self.deviceValue = [[UILabel alloc] init];
    self.launcherValue.text = @"Metallic / 1.2 alpha";
    self.gameValue.text = @"-";
    self.deviceValue.text = UIDevice.currentDevice.model;

    UIView *launcherCard = [self cardWithIcon:@"sparkles" title:@"Launcher Version" valueLabel:self.launcherValue];
    UIView *gameCard = [self cardWithIcon:@"gamecontroller.fill" title:@"Game Version" valueLabel:self.gameValue];
    UIView *deviceCard = [self cardWithIcon:@"iphone" title:@"Device" valueLabel:self.deviceValue];
    self.cardStack = [[UIStackView alloc] initWithArrangedSubviews:@[launcherCard, gameCard, deviceCard]];
    self.cardStack.translatesAutoresizingMaskIntoConstraints = NO;
    self.cardStack.axis = UILayoutConstraintAxisVertical;
    self.cardStack.spacing = 6.0;
    [self addSubview:self.cardStack];

    self.heightConstraint = [self.heightAnchor constraintEqualToConstant:kCollapsedHeight];
    self.cardStackTopConstraint =
        [self.cardStack.topAnchor constraintEqualToAnchor:self.avatarView.bottomAnchor constant:10.0];
    self.cardStackBottomConstraint =
        [self.cardStack.bottomAnchor constraintEqualToAnchor:self.bottomAnchor constant:-12.0];
    [NSLayoutConstraint activateConstraints:@[
        self.heightConstraint,
        [self.avatarView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:12.0],
        [self.avatarView.topAnchor constraintEqualToAnchor:self.topAnchor constant:10.0],
        [self.avatarView.widthAnchor constraintEqualToConstant:46.0],
        [self.avatarView.heightAnchor constraintEqualToConstant:46.0],
        [self.accountNameLabel.leadingAnchor constraintEqualToAnchor:self.avatarView.trailingAnchor constant:10.0],
        [self.accountNameLabel.trailingAnchor constraintEqualToAnchor:self.toggleButton.leadingAnchor constant:-6.0],
        [self.accountNameLabel.centerYAnchor constraintEqualToAnchor:self.avatarView.centerYAnchor],
        [self.toggleButton.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-8.0],
        [self.toggleButton.centerYAnchor constraintEqualToAnchor:self.avatarView.centerYAnchor],
        [self.toggleButton.widthAnchor constraintEqualToConstant:32.0],
        [self.toggleButton.heightAnchor constraintEqualToConstant:32.0],
        [self.cardStack.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:10.0],
        [self.cardStack.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-10.0],
        self.cardStackTopConstraint,
        self.cardStackBottomConstraint
    ]];
}

- (void)profileTapped {
    if (self.onProfileTap) self.onProfileTap();
}

- (void)toggleTapped {
    [self setExpanded:!self.expanded animated:YES];
}

- (void)setExpanded:(BOOL)expanded animated:(BOOL)animated {
    _expanded = expanded;
    self.heightConstraint.constant = expanded ? kExpandedHeight : kCollapsedHeight;
    self.cardStackTopConstraint.active = expanded;
    self.cardStackBottomConstraint.active = expanded;
    [self.toggleButton setImage:[UIImage systemImageNamed:(expanded ? @"chevron.up" : @"chevron.down")]
                       forState:UIControlStateNormal];
    self.cardStack.userInteractionEnabled = expanded;

    void (^changes)(void) = ^{
        self.cardStack.alpha = expanded ? 1.0 : 0.0;
        [self.superview layoutIfNeeded];
    };
    if (animated && self.superview) {
        [UIView animateWithDuration:0.22
                              delay:0
                            options:UIViewAnimationOptionCurveEaseInOut
                         animations:changes
                         completion:nil];
    } else {
        changes();
    }
}

- (void)setProfileName:(NSString *)name avatar:(UIImage *)avatar {
    self.accountNameLabel.text = (name.length > 0) ? name : @"Not Logged In";
    self.avatarView.image = avatar ?: [UIImage systemImageNamed:@"person.crop.circle.fill"];
}

- (void)setLauncherVersion:(NSString *)launcher gameVersion:(NSString *)game device:(NSString *)device {
    if (launcher.length > 0) self.launcherValue.text = launcher;
    if (game.length > 0) self.gameValue.text = game;
    if (device.length > 0) self.deviceValue.text = device;
}

@end
