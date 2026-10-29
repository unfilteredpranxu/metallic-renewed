#import "HomeActionPanelView.h"
#import "BackgroundManager.h"
#import "UIKit+GlassSurface.h"
#import <math.h>

// Keep the existing avatar tap route available to VoiceOver as well as touch.
@interface AMEProfileImageView : UIImageView
@end
@implementation AMEProfileImageView
- (BOOL)pointInside:(CGPoint)point withEvent:(UIEvent *)event {
    CGFloat x=MAX(0,(44-self.bounds.size.width)/2),y=MAX(0,(44-self.bounds.size.height)/2);
    return CGRectContainsPoint(CGRectInset(self.bounds,-x,-y),point);
}
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
    return 44.0;
}

static inline CGFloat AmeAvatarSize(void) {
    return 32.0;
}

static inline CGFloat AmeAvatarPadding(void) {
    return (AmeCollapsedSize() - AmeAvatarSize()) / 2.0;
}

static const CGFloat kExpandedWidth = 260.0;
static const CGFloat kCollapsedTopOffset = 8.0;    // level with the top nav bar (safe.topAnchor + 8)
static const CGFloat kExpandedTopOffset = 76.0;   // opens right below the nav bar

static UIButton *MakeHiddenActionButton(NSString *title, NSString *symbol) {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    button.translatesAutoresizingMaskIntoConstraints = NO;
    [button setTitle:title forState:UIControlStateNormal];
    [button setImage:[UIImage systemImageNamed:symbol] forState:UIControlStateNormal];
    button.hidden = YES;
    return button;
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
@property (nonatomic, strong) UIScrollView *bodyScrollView;
@property (nonatomic, strong) UIView *accessibilityBackdrop;
@property (nonatomic, strong) NSLayoutConstraint *collapsedBodyHeight;
@property (nonatomic, strong) NSLayoutConstraint *naturalBodyHeight;
@property (nonatomic, strong) NSLayoutConstraint *minimumBodyHeight;
@property (nonatomic, strong) NSLayoutConstraint *loginMinimumHeight;
@property (nonatomic, copy) NSArray<NSLayoutConstraint *> *expandedBoundsConstraints;
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
        self.accessibilityBackdrop = [[UIView alloc] initWithFrame:self.bounds];
        self.accessibilityBackdrop.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        self.accessibilityBackdrop.userInteractionEnabled = NO;
        self.accessibilityBackdrop.isAccessibilityElement = NO;
        [self insertSubview:self.accessibilityBackdrop atIndex:0];
        NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
        [center addObserver:self selector:@selector(accessibilityAppearanceDidChange:)
                       name:UIAccessibilityReduceTransparencyStatusDidChangeNotification object:nil];
        [center addObserver:self selector:@selector(accessibilityAppearanceDidChange:)
                       name:UIAccessibilityDarkerSystemColorsStatusDidChangeNotification object:nil];
        [self updateAccessibilityAppearance];
        [self setExpanded:NO animated:NO];
    }
    return self;
}

- (void)dealloc {
    [NSNotificationCenter.defaultCenter removeObserver:self];
}

- (void)accessibilityAppearanceDidChange:(NSNotification *)notification {
    [self updateAccessibilityAppearance];
}

- (void)updateAccessibilityAppearance {
    // A single noninteractive solid backing, not another material or a preference override.
    BOOL needsBacking = UIAccessibilityIsReduceTransparencyEnabled() || UIAccessibilityDarkerSystemColorsEnabled();
    self.accessibilityBackdrop.backgroundColor = UIColor.secondarySystemBackgroundColor;
    self.accessibilityBackdrop.hidden = !needsBacking;
    self.avatarView.backgroundColor = UIColor.tertiarySystemFillColor;
    self.avatarView.layer.borderColor = [AmeUIBorderColor() resolvedColorWithTraitCollection:self.traitCollection].CGColor;
}

- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];
    [self updateAccessibilityAppearance];
}

- (UIView *)cardWithIcon:(NSString *)icon title:(NSString *)title valueLabel:(UILabel *)value {
    UIView *card = [[UIView alloc] init];
    card.translatesAutoresizingMaskIntoConstraints = NO;
    card.backgroundColor = UIColor.tertiarySystemFillColor;
    card.layer.cornerRadius = 12.0;
    card.layer.cornerCurve = kCACornerCurveContinuous;
    [card.heightAnchor constraintGreaterThanOrEqualToConstant:48.0].active = YES;

    UIImageView *iconView = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:icon]];
    iconView.translatesAutoresizingMaskIntoConstraints = NO;
    iconView.contentMode = UIViewContentModeScaleAspectFit;
    iconView.tintColor = AmeUIAccentColor();
    iconView.isAccessibilityElement = NO;

    UILabel *titleLabel = [[UILabel alloc] init];
    titleLabel.text = title;
    titleLabel.font = AmeUIFont(AmeUIFontRoleStatus);
    titleLabel.adjustsFontForContentSizeCategory = YES;
    titleLabel.numberOfLines = 0;
    titleLabel.textColor = AmeUISecondaryTextColor();

    value.font = AmeUIFont(AmeUIFontRoleButton);
    value.adjustsFontForContentSizeCategory = YES;
    value.textColor = AmeUIPrimaryTextColor();
    value.numberOfLines = 0;

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
        [textStack.topAnchor constraintEqualToAnchor:card.topAnchor constant:8.0],
        [textStack.bottomAnchor constraintEqualToAnchor:card.bottomAnchor constant:-8.0]
    ]];
    // Keep the live value exposed; do not cache an accessibility copy of runtime state.
    card.isAccessibilityElement = NO;
    titleLabel.isAccessibilityElement = YES;
    value.isAccessibilityElement = YES;
    return card;
}

- (void)buildUI {
    self.layer.cornerRadius = 22.0;
    self.layer.cornerCurve = kCACornerCurveContinuous;
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
    self.avatarView.tintColor = AmeUISecondaryTextColor();
    // Tapping the picture opens/closes the panel; the name inside the panel opens the account manager.
    [self.avatarView addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(toggleTapped)]];
    [self addSubview:self.avatarView];

    self.accountNameLabel = [[UILabel alloc] init];
    self.accountNameLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.accountNameLabel.font = AmeUIFont(AmeUIFontRoleButton);
    self.accountNameLabel.adjustsFontForContentSizeCategory = YES;
    self.accountNameLabel.textColor = AmeUIPrimaryTextColor();
    self.accountNameLabel.text = @"Not Logged In";
    self.accountNameLabel.numberOfLines = 1;
    self.accountNameLabel.adjustsFontSizeToFitWidth = YES;
    self.accountNameLabel.minimumScaleFactor = 0.75;
    self.accountNameLabel.userInteractionEnabled = YES;
    // Login below exposes the same account route with a full 44-point button.
    self.accountNameLabel.isAccessibilityElement = NO;
    [self.accountNameLabel addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(profileTapped)]];
    [self addSubview:self.accountNameLabel];

    self.toggleButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.toggleButton.translatesAutoresizingMaskIntoConstraints = NO;
    self.toggleButton.tintColor = AmeUIPrimaryTextColor();
    self.toggleButton.accessibilityLabel = @"Close profile";
    [self.toggleButton addTarget:self action:@selector(toggleTapped) forControlEvents:UIControlEventTouchUpInside];
    [self addSubview:self.toggleButton];

    self.launchButton = MakeHiddenActionButton(@"Launch Game", @"play.fill");
    self.executeJarButton = MakeHiddenActionButton(@"Execute JAR", @"square.and.arrow.up");
    self.chooseVersionButton = MakeHiddenActionButton(@"Choose Version", @"square.stack.3d.up.fill");

    self.launcherValue = [[UILabel alloc] init];
    self.gameValue = [[UILabel alloc] init];
    self.deviceValue = [[UILabel alloc] init];
    self.launcherValue.text = @"—"; // Filled by the existing owner; no invented build version.
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
    self.bodyScrollView = [[UIScrollView alloc] init];
    self.bodyScrollView.translatesAutoresizingMaskIntoConstraints = NO;
    self.bodyScrollView.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;
    self.bodyScrollView.directionalLockEnabled = YES;
    self.bodyScrollView.showsHorizontalScrollIndicator = NO;
    [self addSubview:self.bodyScrollView];
    [self.bodyScrollView addSubview:self.chipRow];

    self.badgeLayer = [[UIView alloc] init];
    self.badgeLayer.translatesAutoresizingMaskIntoConstraints = NO;
    self.badgeLayer.userInteractionEnabled = NO;
    [self.bodyScrollView addSubview:self.badgeLayer];

    self.loginButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.loginButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.loginButton setTitle:@"Log In / Add Account" forState:UIControlStateNormal];
    [self.loginButton setImage:[UIImage systemImageNamed:@"person.crop.circle.badge.plus"] forState:UIControlStateNormal];
    self.loginButton.titleLabel.font = AmeUIFont(AmeUIFontRoleButton);
    self.loginButton.titleLabel.adjustsFontForContentSizeCategory = YES;
    self.loginButton.titleLabel.numberOfLines = 0;
    self.loginButton.titleLabel.textAlignment = NSTextAlignmentCenter;
    self.loginButton.tintColor = AmeUIAccentColor();
    self.loginButton.backgroundColor = UIColor.tertiarySystemFillColor;
    self.loginButton.layer.cornerRadius = 12.0;
    self.loginButton.contentEdgeInsets = UIEdgeInsetsMake(10, 10, 10, 10);
    self.loginButton.imageEdgeInsets = UIEdgeInsetsMake(0, -6, 0, 6);
    [self.loginButton addTarget:self action:@selector(loginButtonTapped) forControlEvents:UIControlEventTouchUpInside];
    self.loginMinimumHeight = [self.loginButton.heightAnchor constraintGreaterThanOrEqualToConstant:44.0];
    self.loginMinimumHeight.active = YES;

    self.cardStack = [[UIStackView alloc] initWithArrangedSubviews:@[self.loginButton, launcherCard, gameCard, deviceCard]];
    self.cardStack.translatesAutoresizingMaskIntoConstraints = NO;
    self.cardStack.axis = UILayoutConstraintAxisVertical;
    self.cardStack.spacing = 6.0;
    [self.bodyScrollView addSubview:self.cardStack];

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
        [self.bodyScrollView.bottomAnchor constraintEqualToAnchor:self.bottomAnchor constant:-12.0];
    self.collapsedBodyHeight = [self.bodyScrollView.heightAnchor constraintEqualToConstant:0];
    // Fit content naturally on tall windows, yield to safe-area bounds on short ones.
    self.naturalBodyHeight = [self.bodyScrollView.heightAnchor constraintEqualToAnchor:self.bodyScrollView.contentLayoutGuide.heightAnchor];
    self.naturalBodyHeight.priority = UILayoutPriorityDefaultLow - 1; // Never compress labels to avoid scrolling.
    self.minimumBodyHeight = [self.bodyScrollView.heightAnchor constraintGreaterThanOrEqualToConstant:44.0];
    self.minimumBodyHeight.priority = 999;
    UILayoutGuide *content = self.bodyScrollView.contentLayoutGuide;
    UILayoutGuide *viewport = self.bodyScrollView.frameLayoutGuide;
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
        [self.bodyScrollView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:10.0],
        [self.bodyScrollView.widthAnchor constraintEqualToConstant:(AmeIsPad() ? 280.0 : kExpandedWidth) - 20.0],
        [self.bodyScrollView.topAnchor constraintEqualToAnchor:self.avatarView.bottomAnchor constant:10.0],
        [content.widthAnchor constraintEqualToAnchor:viewport.widthAnchor],
        [self.chipRow.leadingAnchor constraintEqualToAnchor:content.leadingAnchor],
        [self.chipRow.trailingAnchor constraintEqualToAnchor:content.trailingAnchor],
        [self.chipRow.topAnchor constraintEqualToAnchor:content.topAnchor constant:6.0],
        [self.chipRow.heightAnchor constraintGreaterThanOrEqualToConstant:44.0],
        [self.badgeLayer.leadingAnchor constraintEqualToAnchor:content.leadingAnchor],
        [self.badgeLayer.trailingAnchor constraintEqualToAnchor:content.trailingAnchor],
        [self.badgeLayer.topAnchor constraintEqualToAnchor:content.topAnchor],
        [self.badgeLayer.bottomAnchor constraintEqualToAnchor:content.bottomAnchor],
        [self.cardStack.leadingAnchor constraintEqualToAnchor:content.leadingAnchor],
        [self.cardStack.trailingAnchor constraintEqualToAnchor:content.trailingAnchor],
        [self.cardStack.bottomAnchor constraintEqualToAnchor:content.bottomAnchor],
        self.cardStackTopConstraint,
        self.collapsedBodyHeight
    ]];
}

- (void)constrainExpandedPresentationToSafeArea:(UILayoutGuide *)safeArea {
    [NSLayoutConstraint deactivateConstraints:self.expandedBoundsConstraints ?: @[]];
    self.expandedBoundsConstraints = @[
        [self.leadingAnchor constraintGreaterThanOrEqualToAnchor:safeArea.leadingAnchor constant:8.0],
        [self.trailingAnchor constraintLessThanOrEqualToAnchor:safeArea.trailingAnchor constant:-8.0],
        [self.bottomAnchor constraintLessThanOrEqualToAnchor:safeArea.bottomAnchor constant:-8.0]
    ];
    if (self.expanded) [NSLayoutConstraint activateConstraints:self.expandedBoundsConstraints];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    // UIButton's single-line intrinsic size must not clip a wrapping accessibility title.
    CGFloat contentWidth = CGRectGetWidth(self.bodyScrollView.bounds);
    if (contentWidth > 0) {
        CGFloat imageWidth = MAX(24.0, self.loginButton.currentImage.size.width);
        CGFloat textWidth = MAX(1.0, contentWidth - imageWidth - 32.0);
        CGSize titleSize = [self.loginButton.titleLabel sizeThatFits:CGSizeMake(textWidth, CGFLOAT_MAX)];
        CGFloat height = MAX(44.0, ceil(titleSize.height) + 20.0);
        if (fabs(self.loginMinimumHeight.constant - height) > 0.5) self.loginMinimumHeight.constant = height;
    }
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
    BOOL stateChanged = (_expanded != expanded);
    _expanded = expanded;
    CGFloat collSize = AmeCollapsedSize();
    CGFloat avSize = AmeAvatarSize();
    CGFloat pad = AmeAvatarPadding();
    self.topOffsetConstraint.constant = expanded ? kExpandedTopOffset : kCollapsedTopOffset;
    self.widthConstraint.constant = expanded ? (AmeIsPad() ? 280.0 : kExpandedWidth) : collSize;
    // UIKit cannot change an installed constraint between required and optional priorities.
    self.heightConstraint.active = NO;
    self.cardStackBottomConstraint.active = NO;
    self.collapsedBodyHeight.active = NO;
    self.naturalBodyHeight.active = NO;
    self.minimumBodyHeight.active = NO;
    self.heightConstraint.priority = expanded ? UILayoutPriorityFittingSizeLevel : UILayoutPriorityRequired;
    self.heightConstraint.constant = expanded ? 320.0 : collSize;
    self.avatarLeadingConstraint.constant = expanded ? 12.0 : pad;
    self.avatarTopConstraint.constant = expanded ? 10.0 : pad;
    self.avatarWidthConstraint.constant = expanded ? (AmeIsPad() ? 52.0 : 46.0) : avSize;
    self.avatarHeightConstraint.constant = expanded ? (AmeIsPad() ? 52.0 : 46.0) : avSize;
    self.cardStackTopConstraint.active = YES; // Keep hidden contents laid out at expanded size behind the clipped avatar.
    self.collapsedBodyHeight.active = !expanded;
    self.cardStackBottomConstraint.active = expanded;
    self.naturalBodyHeight.active = expanded;
    self.minimumBodyHeight.active = expanded;
    for (NSLayoutConstraint *constraint in self.expandedBoundsConstraints) constraint.active = expanded;
    self.heightConstraint.active = YES;
    self.bodyScrollView.accessibilityElementsHidden = !expanded;
    self.toggleButton.accessibilityElementsHidden = !expanded;
    self.avatarView.accessibilityValue = expanded ? @"Expanded" : @"Collapsed";
    self.bodyScrollView.scrollEnabled = expanded;
    if (!expanded) [self.bodyScrollView setContentOffset:CGPointZero animated:NO];
    [self.toggleButton setImage:[UIImage systemImageNamed:(expanded ? @"chevron.up" : @"chevron.down")]
                       forState:UIControlStateNormal];
    self.cardStack.userInteractionEnabled = expanded;
    self.chipRow.userInteractionEnabled = expanded;
    self.toggleButton.userInteractionEnabled = expanded;
    self.accountNameLabel.userInteractionEnabled = expanded;
    CGFloat radius = expanded ? 22.0 : collSize / 2.0;
    self.layer.cornerRadius = radius;
    [[BackgroundManager sharedManager] applyEffectToView:self];

    void (^changes)(void) = ^{
        self.cardStack.alpha = expanded ? 1.0 : 0.0;
        self.chipRow.alpha = expanded ? 1.0 : 0.0;
        self.badgeLayer.alpha = expanded ? 1.0 : 0.0;
        self.accountNameLabel.alpha = expanded ? 1.0 : 0.0;
        self.toggleButton.alpha = expanded ? 1.0 : 0.0;
        self.layer.cornerRadius = radius;
        [self.superview layoutIfNeeded];
        [self layoutIfNeeded];
    };
    void (^announce)(void) = ^{
        if (stateChanged && self.expanded == expanded && UIAccessibilityIsVoiceOverRunning()) {
            UIAccessibilityPostNotification(UIAccessibilityLayoutChangedNotification, self.avatarView);
        }
    };
    if (animated && !UIAccessibilityIsReduceMotionEnabled() && self.superview) {
        [UIView animateWithDuration:0.22
                              delay:0
                            options:UIViewAnimationOptionCurveEaseInOut | UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction
                         animations:changes
                         completion:^(BOOL finished) { announce(); }];
    } else {
        changes();
        announce();
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
