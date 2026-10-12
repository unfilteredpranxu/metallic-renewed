//
//  AccountLoginViewController.m
//  Amethyst
//
//  Account login screen modeled on FCL (Fold Craft Launcher) and HMCL:
//  - Header area at the top (large title + subtitle)
//  - Four tappable sign-in method cards (Microsoft / LittleSkin / custom third party / local)
//  - Each card: colored icon circle on the left + title/description in the middle + arrow on the right
//  - Adapts to the custom launcher background (transparent view + frosted-glass cards)
//  - Uses UIButton instead of UIControl to avoid touch interception
//

#import "AccountLoginViewController.h"
#import "BackgroundManager.h"
#import "ScreenUtils.h"
#import "utils.h"

@interface AccountLoginViewController () <UIScrollViewDelegate>
@property (nonatomic, strong) UIScrollView *scrollView;
@property (nonatomic, strong) UIStackView *cardStack;
@property (nonatomic, strong) UIView *headerContainer;
@property (nonatomic, strong) UILabel *headerTitleLabel;
@property (nonatomic, strong) UILabel *headerSubtitleLabel;
// ★ [ACCT-DUP] Re-entry guard: once a sign-in method is selected on this page, lock it and ignore
//   subsequent taps to prevent a quick double-tap from triggering two sign-ins (two random UUIDs
//   for a local account would create two duplicate accounts).
@property (nonatomic) BOOL ameLoginTypeSelected;
@end

@implementation AccountLoginViewController

#pragma mark - Lifecycle

- (void)viewDidLoad {
    [super viewDidLoad];
    // Adapt to the custom launcher background: make this view controller transparent so the global wallpaper shows through.
    [[BackgroundManager sharedManager] makeViewControllerTransparent:self];
    self.title = localize(@"i18n_str_2", nil);
    // Use a transparent background so the custom launcher background shows through
    // (applyBackgroundToView adds the background at the bottom of the window/splitVC).
    self.view.backgroundColor = [UIColor clearColor];

    [self setupUI];
    // Apply the background (traverse the responder chain to find splitVC/window and add the background at the bottom).
    [[BackgroundManager sharedManager] applyBackgroundToView:self.view];

    // Listen for background UI-effect changes and reapply transparency when the user switches the
    // background effect (translucent/frosted glass).
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(reapplyBackgroundEffect)
                                                 name:@"BackgroundUIEffectChanged"
                                               object:nil];
}

/// Reapply transparency when the background effect changes (triggered by the BackgroundUIEffectChanged notification).
- (void)reapplyBackgroundEffect {
    [[BackgroundManager sharedManager] makeViewControllerTransparent:self];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    // Ensure scrollView contentSize is correct.
    [self.scrollView layoutIfNeeded];
}

#pragma mark - Setup

- (void)setupUI {
    // ScrollView container.
    self.scrollView = [[UIScrollView alloc] init];
    self.scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    self.scrollView.alwaysBounceVertical = YES;
    self.scrollView.backgroundColor = [UIColor clearColor];
    self.scrollView.delegate = self;
    self.scrollView.showsVerticalScrollIndicator = NO;
    [self.view addSubview:self.scrollView];

    // Card stack.
    self.cardStack = [[UIStackView alloc] init];
    self.cardStack.translatesAutoresizingMaskIntoConstraints = NO;
    self.cardStack.axis = UILayoutConstraintAxisVertical;
    self.cardStack.spacing = [ScreenUtils dp:14];
    self.cardStack.alignment = UIStackViewAlignmentFill;
    [self.scrollView addSubview:self.cardStack];

    [NSLayoutConstraint activateConstraints:@[
        [self.scrollView.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [self.scrollView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.scrollView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.scrollView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],

        [self.cardStack.topAnchor constraintEqualToAnchor:self.scrollView.contentLayoutGuide.topAnchor constant:[ScreenUtils dp:20]],
        [self.cardStack.leadingAnchor constraintEqualToAnchor:self.scrollView.contentLayoutGuide.leadingAnchor constant:[ScreenUtils dp:20]],
        [self.cardStack.trailingAnchor constraintEqualToAnchor:self.scrollView.contentLayoutGuide.trailingAnchor constant:-[ScreenUtils dp:20]],
        [self.cardStack.bottomAnchor constraintEqualToAnchor:self.scrollView.contentLayoutGuide.bottomAnchor constant:-[ScreenUtils dp:20]],
        [self.cardStack.widthAnchor constraintEqualToAnchor:self.scrollView.frameLayoutGuide.widthAnchor constant:-[ScreenUtils dp:40]],
    ]];

    // Header area.
    [self setupHeader];

    // Spacing.
    [self.cardStack addArrangedSubview:[self spacerViewWithHeight:[ScreenUtils dp:8]]];

    // Four sign-in cards.
    [self.cardStack addArrangedSubview:[self createLoginCardWithType:AccountLoginTypeMicrosoft
                                                                title:localize(@"i18n_str_10", nil)
                                                          description:localize(@"i18n_str_11", nil)
                                                           iconName:@"xbox.logo"
                                                       fallbackIcon:@"person.crop.circle.fill"
                                                          accentColor:[UIColor colorWithRed:0.0 green:0.45 blue:0.93 alpha:1.0]]];
    [self.cardStack addArrangedSubview:[self createLoginCardWithType:AccountLoginTypeLittleSkin
                                                                title:@"LittleSkin"
                                                          description:localize(@"i18n_str_12", nil)
                                                           iconName:@"person.fill.viewfinder"
                                                       fallbackIcon:@"person.crop.circle.fill"
                                                          accentColor:[UIColor colorWithRed:0.55 green:0.30 blue:0.85 alpha:1.0]]];
    [self.cardStack addArrangedSubview:[self createLoginCardWithType:AccountLoginTypeThirdParty
                                                                title:localize(@"i18n_str_13", nil)
                                                          description:localize(@"i18n_str_14", nil)
                                                           iconName:@"globe"
                                                       fallbackIcon:@"globe"
                                                          accentColor:[UIColor colorWithRed:0.90 green:0.55 blue:0.15 alpha:1.0]]];
    [self.cardStack addArrangedSubview:[self createLoginCardWithType:AccountLoginTypeLocal
                                                                title:localize(@"i18n_str_15", nil)
                                                          description:localize(@"i18n_str_16", nil)
                                                           iconName:@"person.fill"
                                                       fallbackIcon:@"person.fill"
                                                          accentColor:[UIColor colorWithRed:0.50 green:0.55 blue:0.60 alpha:1.0]]];
}

/// Top header area (FCL/HMCL style: large title + subtitle).
- (void)setupHeader {
    self.headerContainer = [[UIView alloc] init];
    self.headerContainer.translatesAutoresizingMaskIntoConstraints = NO;
    [self.cardStack addArrangedSubview:self.headerContainer];

    self.headerTitleLabel = [[UILabel alloc] init];
    self.headerTitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.headerTitleLabel.text = localize(@"i18n_str_17", nil);
    self.headerTitleLabel.font = [UIFont systemFontOfSize:[ScreenUtils sp:26] weight:UIFontWeightBold];
    self.headerTitleLabel.textColor = [UIColor labelColor];   // ★ [HOST-BUG-A]
    self.headerTitleLabel.numberOfLines = 1;
    [self.headerContainer addSubview:self.headerTitleLabel];

    self.headerSubtitleLabel = [[UILabel alloc] init];
    self.headerSubtitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.headerSubtitleLabel.text = localize(@"i18n_str_18", nil);
    self.headerSubtitleLabel.font = [UIFont systemFontOfSize:[ScreenUtils sp:14] weight:UIFontWeightRegular];
    self.headerSubtitleLabel.textColor = [UIColor secondaryLabelColor];   // ★ [HOST-BUG-A]
    self.headerSubtitleLabel.numberOfLines = 0;
    [self.headerContainer addSubview:self.headerSubtitleLabel];

    [NSLayoutConstraint activateConstraints:@[
        [self.headerTitleLabel.topAnchor constraintEqualToAnchor:self.headerContainer.topAnchor],
        [self.headerTitleLabel.leadingAnchor constraintEqualToAnchor:self.headerContainer.leadingAnchor],
        [self.headerTitleLabel.trailingAnchor constraintEqualToAnchor:self.headerContainer.trailingAnchor],

        [self.headerSubtitleLabel.topAnchor constraintEqualToAnchor:self.headerTitleLabel.bottomAnchor constant:[ScreenUtils dp:6]],
        [self.headerSubtitleLabel.leadingAnchor constraintEqualToAnchor:self.headerContainer.leadingAnchor],
        [self.headerSubtitleLabel.trailingAnchor constraintEqualToAnchor:self.headerContainer.trailingAnchor],
        [self.headerSubtitleLabel.bottomAnchor constraintEqualToAnchor:self.headerContainer.bottomAnchor],
    ]];
}

/// Create a sign-in method card (FCL/HMCL style).
/// Use UIButton instead of UIControl to ensure touch events fire reliably.
- (UIView *)createLoginCardWithType:(AccountLoginType)type
                              title:(NSString *)title
                        description:(NSString *)description
                         iconName:(NSString *)iconName
                     fallbackIcon:(NSString *)fallbackIcon
                        accentColor:(UIColor *)accentColor {
    // Card container (UIView + gesture); do not use UIButton directly because the internal layout is complex.
    // Use UIView + UITapGestureRecognizer instead of UIControl to avoid UIVisualEffectView interception.
    UIView *card = [[UIView alloc] init];
    card.translatesAutoresizingMaskIntoConstraints = NO;
    card.layer.cornerRadius = [ScreenUtils dp:16];
    card.layer.cornerCurve = kCACornerCurveContinuous;
    card.layer.borderWidth = 0.5;
    card.layer.borderColor = [UIColor separatorColor].CGColor;   // ★ [HOST-BUG-A]
    // Enable touch interaction.
    card.userInteractionEnabled = YES;

    // Frosted-glass background (applyEffectToView ensures blurView.userInteractionEnabled = NO).
    [[BackgroundManager sharedManager] applyEffectToView:card];

    // Icon circle on the left (light accentColor background + SF Symbol).
    UIView *iconCircle = [[UIView alloc] init];
    iconCircle.translatesAutoresizingMaskIntoConstraints = NO;
    iconCircle.backgroundColor = [accentColor colorWithAlphaComponent:0.18];
    iconCircle.layer.cornerRadius = [ScreenUtils dp:24];
    iconCircle.layer.cornerCurve = kCACornerCurveContinuous;   // ★ [CORNER-FIX] Continuous corners (match system cards).
    iconCircle.userInteractionEnabled = NO;
    [card addSubview:iconCircle];

    UIImageView *iconView = [[UIImageView alloc] init];
    iconView.translatesAutoresizingMaskIntoConstraints = NO;
    UIImage *icon = [UIImage systemImageNamed:iconName] ?: [UIImage systemImageNamed:fallbackIcon];
    iconView.image = icon;
    iconView.tintColor = accentColor;
    iconView.contentMode = UIViewContentModeScaleAspectFit;
    iconView.userInteractionEnabled = NO;
    [iconCircle addSubview:iconView];

    // Title in the middle.
    UILabel *titleLabel = [[UILabel alloc] init];
    titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    titleLabel.text = title;
    titleLabel.font = [UIFont systemFontOfSize:[ScreenUtils sp:17] weight:UIFontWeightSemibold];
    titleLabel.textColor = [UIColor labelColor];   // ★ [HOST-BUG-A]
    titleLabel.numberOfLines = 1;
    titleLabel.userInteractionEnabled = NO;
    [card addSubview:titleLabel];

    // Description in the middle.
    UILabel *descLabel = [[UILabel alloc] init];
    descLabel.translatesAutoresizingMaskIntoConstraints = NO;
    descLabel.text = description;
    descLabel.font = [UIFont systemFontOfSize:[ScreenUtils sp:13] weight:UIFontWeightRegular];
    descLabel.textColor = [UIColor secondaryLabelColor];   // ★ [HOST-BUG-A]
    descLabel.numberOfLines = 0;
    descLabel.userInteractionEnabled = NO;
    [card addSubview:descLabel];

    // Arrow on the right.
    UIImageView *chevron = [[UIImageView alloc] init];
    chevron.translatesAutoresizingMaskIntoConstraints = NO;
    chevron.image = [UIImage systemImageNamed:@"chevron.right"];
    chevron.tintColor = [UIColor tertiaryLabelColor];   // ★ [HOST-BUG-A]
    chevron.contentMode = UIViewContentModeScaleAspectFit;
    chevron.userInteractionEnabled = NO;
    [card addSubview:chevron];

    // Layout constraints.
    CGFloat padding = [ScreenUtils dp:16];
    CGFloat iconSize = [ScreenUtils dp:48];
    CGFloat iconInset = [ScreenUtils dp:24];

    [NSLayoutConstraint activateConstraints:@[
        [iconCircle.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:padding],
        [iconCircle.centerYAnchor constraintEqualToAnchor:card.centerYAnchor],
        [iconCircle.widthAnchor constraintEqualToConstant:iconSize],
        [iconCircle.heightAnchor constraintEqualToConstant:iconSize],

        [iconView.centerXAnchor constraintEqualToAnchor:iconCircle.centerXAnchor],
        [iconView.centerYAnchor constraintEqualToAnchor:iconCircle.centerYAnchor],
        [iconView.widthAnchor constraintEqualToConstant:iconInset],
        [iconView.heightAnchor constraintEqualToConstant:iconInset],

        [titleLabel.leadingAnchor constraintEqualToAnchor:iconCircle.trailingAnchor constant:[ScreenUtils dp:14]],
        [titleLabel.topAnchor constraintEqualToAnchor:card.topAnchor constant:[ScreenUtils dp:18]],
        [titleLabel.trailingAnchor constraintEqualToAnchor:chevron.leadingAnchor constant:-[ScreenUtils dp:8]],

        [descLabel.leadingAnchor constraintEqualToAnchor:titleLabel.leadingAnchor],
        [descLabel.topAnchor constraintEqualToAnchor:titleLabel.bottomAnchor constant:[ScreenUtils dp:4]],
        [descLabel.trailingAnchor constraintEqualToAnchor:titleLabel.trailingAnchor],
        [descLabel.bottomAnchor constraintEqualToAnchor:card.bottomAnchor constant:-[ScreenUtils dp:18]],

        [chevron.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-padding],
        [chevron.centerYAnchor constraintEqualToAnchor:card.centerYAnchor],
        [chevron.widthAnchor constraintEqualToConstant:[ScreenUtils dp:14]],
        [chevron.heightAnchor constraintEqualToConstant:[ScreenUtils dp:20]],
    ]];

    // Use UITapGestureRecognizer to handle taps (more reliable than UIControlEventTouchUpInside
    // and not intercepted by UIVisualEffectView's contentView).
    // Start tags at 1 so UIKit does not treat 0 as "tag not set".
    card.tag = type + 1;
    UITapGestureRecognizer *tapGesture = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(cardTapped:)];
    tapGesture.cancelsTouchesInView = NO;
    [card addGestureRecognizer:tapGesture];

    return card;
}

- (UIView *)spacerViewWithHeight:(CGFloat)height {
    UIView *spacer = [[UIView alloc] init];
    spacer.translatesAutoresizingMaskIntoConstraints = NO;
    [spacer.heightAnchor constraintEqualToConstant:height].active = YES;
    return spacer;
}

#pragma mark - Actions

/// Handle a card tap (triggered by UITapGestureRecognizer).
- (void)cardTapped:(UITapGestureRecognizer *)gesture {
    UIView *card = gesture.view;
    if (!card) return;
    // ★ [ACCT-DUP] Re-entry guard: this page can still receive taps during the animation, so a
    //   double-tap would call onSelectLoginType twice and start two sign-ins (each local sign-in
    //   generates a random UUID, producing two identical-looking accounts).
    //   Lock page interaction as soon as a selection is made and ignore later taps.
    if (self.ameLoginTypeSelected) return;
    self.ameLoginTypeSelected = YES;
    // ★ [ACCT-DONE] Lock only the cards that trigger sign-in (cardStack); do not set
    //   self.view.userInteractionEnabled = NO. That would lock the entire page, including the
    //   navigation-bar back button, making it impossible to leave if the host does not consume the selection.
    self.cardStack.userInteractionEnabled = NO;

    // Restore the tag offset (createLoginCardWithType stores it with +1).
    AccountLoginType type = (AccountLoginType)(card.tag - 1);

    __weak typeof(self) weakSelf = self;
    // Subtle highlight feedback (FCL style).
    [UIView animateWithDuration:0.1 animations:^{
        card.alpha = 0.65;
    } completion:^(BOOL finished) {
        [UIView animateWithDuration:0.1 animations:^{
            card.alpha = 1.0;
        } completion:^(BOOL finished2) {
            if (weakSelf.onSelectLoginType) {
                weakSelf.onSelectLoginType(type);
            }
            // ★ [ACCT-DUP] Fallback unlock: if the host does not consume the selection (does not pop this
            //   page / callback is nil), restore interaction after 0.8s to avoid a stuck page. If already
            //   popped (view is no longer in a window), no restoration is needed.
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.8 * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{
                __strong typeof(weakSelf) strongSelf = weakSelf;
                if (strongSelf && strongSelf.view.window) {
                    strongSelf.ameLoginTypeSelected = NO;
                    strongSelf.view.userInteractionEnabled = YES;      // ★ [ACCT-DONE] Double safeguard (entire page).
                    strongSelf.cardStack.userInteractionEnabled = YES; // ★ [ACCT-DONE] Card stack.
                }
            });
        }];
    }];
}

/// ★ [ACCT-DONE] Unconditionally reset the selection lock and interaction when this page is left
///   (popped/replaced), ensuring that a selection not consumed by the host cannot leave this page
///   (or its next appearance) locked.
- (void)viewDidDisappear:(BOOL)animated {
    [super viewDidDisappear:animated];
    self.ameLoginTypeSelected = NO;
    self.view.userInteractionEnabled = YES;
    self.cardStack.userInteractionEnabled = YES;
}

@end
