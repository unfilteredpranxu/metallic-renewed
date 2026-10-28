#import "HomeActionPanelView.h"

// Keep the existing avatar tap route available to VoiceOver as well as touch.
@interface AMEProfileImageView : UIImageView
@end
@implementation AMEProfileImageView
- (BOOL)accessibilityActivate {
    HomeActionPanelView *panel = (HomeActionPanelView *)self.superview;
    if (![panel isKindOfClass:HomeActionPanelView.class] || !panel.userInteractionEnabled) return NO;
    if (!panel.expanded && panel.onWillExpand) panel.onWillExpand();
    [panel setExpanded:!panel.expanded animated:!UIAccessibilityIsReduceMotionEnabled()];
    return YES;
}
@end

static inline BOOL AmeIsPad(void) {
    return UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPad;
}

static inline CGFloat AmeCollapsedSize(void) {
    return AmeIsPad() ? 56.0 : 46.0;
}

static inline CGFloat AmeAvatarSize(void) {
    return AmeIsPad() ? 48.0 : 44.0;
}

static inline CGFloat AmeAvatarPadding(void) {
    return (AmeCollapsedSize() - AmeAvatarSize()) / 2.0;
}

static const CGFloat kExpandedWidth = 260.0;
static const CGFloat kExpandedHeight = 306.0;
static const CGFloat kChipRowHeight = 44.0;
static const CGFloat kCollapsedTopOffset = 8.0;    // level with the top nav bar (safe.topAnchor + 8)
static const CGFloat kExpandedTopOffset = 76.0;   // opens right below the nav bar

static UIColor *PanelAccentColor(void) {
    // Pink to match the glass nav bar selector.
    return [UIColor colorWithRed:1.0 green:0.43 blue:0.78 alpha:1.0];
}

static UIButton *MakeHiddenActionButton(NSString *title, NSString *symbol) {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    button.translatesAutoresizingMaskIntoConstraints = NO;
    [button setTitle:title forState:UIControlStateNormal];
    [button setImage:[UIImage systemImageNamed:symbol] forState:UIControlStateNormal];
    button.hidden = YES;
    return button;
}

static UIVisualEffectView *ApplyGlass(UIView *host) {
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
    return glassView;
}

@interface HomeActionPanelView ()
@property (nonatomic, assign, readwrite) BOOL expanded;
@property (nonatomic, strong, readwrite) UIImageView *avatarView;
@property (nonatomic, strong, readwrite) UIButton *toggleButton;
@property (nonatomic, strong, readwrite) UIButton *launchButton;
@property (nonatomic, strong, readwrite) UIButton *executeJarButton;
@property (nonatomic, strong, readwrite) UIButton *chooseVersionButton;
@property (nonatomic, strong, readwrite) UIButton *loginButton;
@property (nonatomic, strong, readwrite) UIStackView *chipRow;
@property (nonatomic, strong, readwrite) UIView *badgeLayer;
@property (nonatomic, strong) UIVisualEffectView *glassView;
@property (nonatomic, strong) UILabel *accountNameLabel;
@property (nonatomic, strong) UIStackView *cardStack;
@property (nonatomic, strong) UILabel *launcherValue;
@property (nonatomic, strong) UILabel *gameValue;
@property (nonatomic, strong) UILabel *deviceValue;
@property (nonatomic, strong) NSLayoutConstraint *heightConstraint;
@property (nonatomic, strong) NSLayoutConstraint *widthConstraint;
@property (nonatomic, strong) NSLayoutConstraint *avatarLeadingConstraint;
@property (nonatomic, strong) NSLayoutConstraint *avatarTopConstraint;
@property (nonatomic, strong) NSLayoutConstraint *avatarWidthConstraint;
@property (nonatomic, strong) NSLayoutConstraint *avatarHeightConstraint;
@property (nonatomic, strong) NSLayoutConstraint *cardStackTopConstraint;
@property (nonatomic, strong) NSLayoutConstraint *cardStackBottomConstraint;
@end

@implementation HomeActionPanelView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        [self buildUI];
        self.glassView = ApplyGlass(self);
        [self setExpanded:NO animated:NO];
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

    self.avatarView = [[AMEProfileImageView alloc] init];
    self.avatarView.isAccessibilityElement = YES;
    self.avatarView.accessibilityLabel = @"Profile";
    self.avatarView.accessibilityTraits = UIAccessibilityTraitButton;
    self.avatarView.translatesAutoresizingMaskIntoConstraints = NO;
    self.avatarView.backgroundColor = [UIColor colorWithWhite:0.25 alpha:1.0];
    self.avatarView.layer.borderWidth = 1.0;
    self.avatarView.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.35].CGColor;
    self.avatarView.clipsToBounds = YES;
    self.avatarView.contentMode = UIViewContentModeScaleAspectFill;
    self.avatarView.userInteractionEnabled = YES;
    self.avatarView.image = [UIImage systemImageNamed:@"person.crop.circle.fill"];
    self.avatarView.tintColor = [UIColor colorWithWhite:0.82 alpha:1.0];
    // Tapping the picture opens/closes the panel; the name inside the panel opens the account manager.
    [self.avatarView addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(toggleTapped)]];
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
    self.launcherValue.text = @"Metallic/ 1.2 alpha";
    self.gameValue.text = @"-";
    self.deviceValue.text = UIDevice.currentDevice.model;

    UIView *launcherCard = [self cardWithIcon:@"sparkles" title:@"Launcher Version" valueLabel:self.launcherValue];
    UIView *gameCard = [self cardWithIcon:@"gamecontroller.fill" title:@"Game Version" valueLabel:self.gameValue];
    UIView *deviceCard = [self cardWithIcon:@"iphone" title:@"Device" valueLabel:self.deviceValue];
    self.chipRow = [[UIStackView alloc] init];
    self.chipRow.translatesAutoresizingMaskIntoConstraints = NO;
    self.chipRow.axis = UILayoutConstraintAxisHorizontal;
    self.chipRow.alignment = UIStackViewAlignmentFill;
    self.chipRow.distribution = UIStackViewDistributionFill;
    self.chipRow.spacing = 6.0;
    [self addSubview:self.chipRow];

    self.badgeLayer = [[UIView alloc] init];
    self.badgeLayer.translatesAutoresizingMaskIntoConstraints = NO;
    self.badgeLayer.userInteractionEnabled = NO;
    [self addSubview:self.badgeLayer];

    self.loginButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.loginButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.loginButton setTitle:@"Log In / Add Account" forState:UIControlStateNormal];
    [self.loginButton setImage:[UIImage systemImageNamed:@"person.crop.circle.badge.plus"] forState:UIControlStateNormal];
    self.loginButton.titleLabel.font = [UIFont systemFontOfSize:13.0 weight:UIFontWeightSemibold];
    self.loginButton.tintColor = PanelAccentColor();
    self.loginButton.backgroundColor = [UIColor colorWithWhite:0.04 alpha:0.55];
    self.loginButton.layer.cornerRadius = 12.0;
    self.loginButton.layer.borderWidth = 1.0;
    self.loginButton.layer.borderColor = [PanelAccentColor() colorWithAlphaComponent:0.45].CGColor;
    self.loginButton.contentEdgeInsets = UIEdgeInsetsMake(0, 10, 0, 10);
    self.loginButton.imageEdgeInsets = UIEdgeInsetsMake(0, -6, 0, 6);
    [self.loginButton addTarget:self action:@selector(loginButtonTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.loginButton.heightAnchor constraintEqualToConstant:38.0].active = YES;

    self.cardStack = [[UIStackView alloc] initWithArrangedSubviews:@[self.loginButton, launcherCard, gameCard, deviceCard]];
    self.cardStack.translatesAutoresizingMaskIntoConstraints = NO;
    self.cardStack.axis = UILayoutConstraintAxisVertical;
    self.cardStack.spacing = 6.0;
    [self addSubview:self.cardStack];

    CGFloat collSize = AmeCollapsedSize();
    CGFloat avSize = AmeAvatarSize();
    CGFloat pad = AmeAvatarPadding();
    self.heightConstraint = [self.heightAnchor constraintEqualToConstant:collSize];
    self.widthConstraint = [self.widthAnchor constraintEqualToConstant:collSize];
    self.avatarLeadingConstraint = [self.avatarView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:pad];
    self.avatarTopConstraint = [self.avatarView.topAnchor constraintEqualToAnchor:self.topAnchor constant:pad];
    self.avatarWidthConstraint = [self.avatarView.widthAnchor constraintEqualToConstant:avSize];
    self.avatarHeightConstraint = [self.avatarView.heightAnchor constraintEqualToConstant:avSize];
    self.cardStackTopConstraint =
        [self.cardStack.topAnchor constraintEqualToAnchor:self.chipRow.bottomAnchor constant:8.0];
    self.cardStackBottomConstraint =
        [self.cardStack.bottomAnchor constraintLessThanOrEqualToAnchor:self.bottomAnchor constant:-12.0];
    // The name may be squeezed to nothing while the panel is collapsed: keep that constraint soft.
    NSLayoutConstraint *nameTrailing =
        [self.accountNameLabel.trailingAnchor constraintLessThanOrEqualToAnchor:self.toggleButton.leadingAnchor constant:-6.0];
    nameTrailing.priority = UILayoutPriorityDefaultHigh;
    [self.accountNameLabel setContentCompressionResistancePriority:UILayoutPriorityDefaultLow
                                                           forAxis:UILayoutConstraintAxisHorizontal];
    [NSLayoutConstraint activateConstraints:@[
        self.heightConstraint,
        self.widthConstraint,
        self.avatarLeadingConstraint,
        self.avatarTopConstraint,
        self.avatarWidthConstraint,
        self.avatarHeightConstraint,
        [self.accountNameLabel.leadingAnchor constraintEqualToAnchor:self.avatarView.trailingAnchor constant:10.0],
        nameTrailing,
        [self.accountNameLabel.centerYAnchor constraintEqualToAnchor:self.avatarView.centerYAnchor],
        [self.toggleButton.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-8.0],
        [self.toggleButton.centerYAnchor constraintEqualToAnchor:self.avatarView.centerYAnchor],
        [self.toggleButton.widthAnchor constraintEqualToConstant:44.0],
        [self.toggleButton.heightAnchor constraintEqualToConstant:44.0],
        [self.chipRow.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:10.0],
        [self.chipRow.widthAnchor constraintEqualToConstant:(AmeIsPad() ? 280.0 : kExpandedWidth) - 20.0],
        [self.chipRow.topAnchor constraintEqualToAnchor:self.avatarView.bottomAnchor constant:10.0],
        [self.chipRow.heightAnchor constraintEqualToConstant:kChipRowHeight],
        [self.badgeLayer.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [self.badgeLayer.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        [self.badgeLayer.topAnchor constraintEqualToAnchor:self.topAnchor],
        [self.badgeLayer.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
        [self.cardStack.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:10.0],
        [self.cardStack.widthAnchor constraintEqualToConstant:(AmeIsPad() ? 280.0 : kExpandedWidth) - 20.0],
        self.cardStackTopConstraint,
        self.cardStackBottomConstraint
    ]];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat collSize = AmeCollapsedSize();
    CGFloat avSize = AmeAvatarSize();
    if (!self.expanded) {
        self.layer.cornerRadius = collSize / 2.0;
        self.avatarView.layer.cornerRadius = avSize / 2.0;
    } else {
        self.layer.cornerRadius = 22.0;
        self.avatarView.layer.cornerRadius = (AmeIsPad() ? 52.0 : 46.0) / 2.0;
    }
}

- (void)profileTapped {
    if (self.onProfileTap) self.onProfileTap();
}

- (void)loginButtonTapped {
    if (self.onLoginTap) {
        self.onLoginTap();
    } else if (self.onProfileTap) {
        self.onProfileTap();
    }
}

- (void)toggleTapped {
    if (!self.expanded && self.onWillExpand) self.onWillExpand();
    [self setExpanded:!self.expanded animated:!UIAccessibilityIsReduceMotionEnabled()];
}

- (void)setExpanded:(BOOL)expanded animated:(BOOL)animated {
    _expanded = expanded;
    CGFloat collSize = AmeCollapsedSize();
    CGFloat avSize = AmeAvatarSize();
    CGFloat pad = AmeAvatarPadding();
    self.topOffsetConstraint.constant = expanded ? kExpandedTopOffset : kCollapsedTopOffset;
    self.widthConstraint.constant = expanded ? (AmeIsPad() ? 280.0 : kExpandedWidth) : collSize;
    self.heightConstraint.constant = expanded ? (AmeIsPad() ? 320.0 : kExpandedHeight) : collSize;
    self.avatarLeadingConstraint.constant = expanded ? 12.0 : pad;
    self.avatarTopConstraint.constant = expanded ? 10.0 : pad;
    self.avatarWidthConstraint.constant = expanded ? (AmeIsPad() ? 52.0 : 46.0) : avSize;
    self.avatarHeightConstraint.constant = expanded ? (AmeIsPad() ? 52.0 : 46.0) : avSize;
    self.cardStackTopConstraint.active = YES; // Keep hidden contents laid out at expanded size behind the clipped avatar.
    self.cardStackBottomConstraint.active = expanded;
    [self.toggleButton setImage:[UIImage systemImageNamed:(expanded ? @"chevron.up" : @"chevron.down")]
                       forState:UIControlStateNormal];
    self.cardStack.userInteractionEnabled = expanded;
    self.chipRow.userInteractionEnabled = expanded;
    self.toggleButton.userInteractionEnabled = expanded;
    self.accountNameLabel.userInteractionEnabled = expanded;
    CGFloat radius = expanded ? 22.0 : collSize / 2.0;

    void (^changes)(void) = ^{
        self.cardStack.alpha = expanded ? 1.0 : 0.0;
        self.chipRow.alpha = expanded ? 1.0 : 0.0;
        self.badgeLayer.alpha = expanded ? 1.0 : 0.0;
        self.accountNameLabel.alpha = expanded ? 1.0 : 0.0;
        self.toggleButton.alpha = expanded ? 1.0 : 0.0;
        self.layer.cornerRadius = radius;
        self.glassView.layer.cornerRadius = radius;
        [self.superview layoutIfNeeded];
        [self layoutIfNeeded];
    };
    if (animated && !UIAccessibilityIsReduceMotionEnabled() && self.superview) {
        [UIView animateWithDuration:0.22
                              delay:0
                            options:UIViewAnimationOptionCurveEaseInOut | UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction
                         animations:changes
                         completion:nil];
    } else {
        changes();
    }
}

- (void)setProfileName:(NSString *)name avatar:(UIImage *)avatar {
    BOOL loggedIn = (name.length > 0 && ![name isEqualToString:@"Not Logged In"]);
    self.accountNameLabel.text = loggedIn ? name : @"Not Logged In";
    self.avatarView.image = avatar ?: [UIImage systemImageNamed:@"person.crop.circle.fill"];
    [self.loginButton setTitle:(loggedIn ? @"Switch Account" : @"Log In / Add Account") forState:UIControlStateNormal];
    [self.loginButton setImage:[UIImage systemImageNamed:(loggedIn ? @"person.2.fill" : @"person.crop.circle.badge.plus")] forState:UIControlStateNormal];
}

- (void)setLauncherVersion:(NSString *)launcher gameVersion:(NSString *)game device:(NSString *)device {
    if (launcher.length > 0) self.launcherValue.text = launcher;
    if (game.length > 0) self.gameValue.text = game;
    if (device.length > 0) self.deviceValue.text = device;
}

@end
