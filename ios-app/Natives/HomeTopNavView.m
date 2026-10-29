#import "HomeTopNavView.h"
#import "BackgroundManager.h"
#import "UIKit+GlassSurface.h"   // AmeApplyGlassChipStyle / AmeGlassEffect (system Liquid Glass on iOS 26+)
#import "utils.h"                // localize()
#import "BottomActionBarView.h"   // AmeThemeTintColor

// Bar geometry. AmeRootTabController and LauncherNewsViewController reserve space for this height,
// so if you change it, update kHomeNavReserve in LauncherNewsViewController.m and the
// additionalSafeAreaInsets value in AmeRootTabController.m as well (height + 8 top margin + 8 gap).
static const CGFloat kNavBarHeight  = 60.0;
static const CGFloat kNavBarPad     = 6.0;    // gap between the bar edge and the selector
static const CGFloat kNavItemPadH   = 8.0;   // horizontal padding inside each item

static NSString *MetallicPresentationText(NSString *key, NSString *fallback) {
    NSString *translated = localize(key, fallback);
    return translated.length && ![translated isEqualToString:key] ? translated : (fallback ?: key);
}

@interface HomeTopNavView ()
@property (nonatomic, strong) UIView *bar;
@property (nonatomic, strong) UIStackView *stack;
@property (nonatomic, strong) UIVisualEffectView *selector;   // the sliding "liquid" capsule
@property (nonatomic, strong) NSArray<UIView *> *items;
@property (nonatomic, strong) NSArray<UIImageView *> *icons;
@property (nonatomic, strong) NSArray<UILabel *> *labels;
@property (nonatomic, strong) NSArray<UIButton *> *buttons;
@property (nonatomic, assign) CGFloat lastBarWidth;
@property (nonatomic, strong) NSLayoutConstraint *naturalWidth;
@end

@implementation HomeTopNavView

static UIColor *NavAccentColor(void) {
    return AmeUIAccentColor();   // follows the theme color chosen in Settings (default pink)
}

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        [self build];
        self.selectedIndex = 0;
        [self themeChanged:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(tabNote:)
                                                     name:@"AmeTabSelected"
                                                   object:nil];
        // One visual refresh path; no extra tab-selection observer or callback.
        for (NSString *name in @[@"LauncherAppearanceChanged", @"UIThemeChanged", @"BackgroundUIEffectChanged", AMEGlassStyleChangedNotification,
                                 UIContentSizeCategoryDidChangeNotification]) {
            [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(themeChanged:)
                                                         name:name object:nil];
        }
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)build {
    // 1) Glass bar. On iOS 26+ this installs the system UIGlassEffect; on older systems the project's
    //    native-material fallback is used (see AmeApplyGlassChipStyle).
    self.bar = [[UIView alloc] init];
    self.bar.translatesAutoresizingMaskIntoConstraints = NO;
    AmeApplyGlassChipStyle(self.bar, kNavBarHeight / 2.0, YES);
    [self addSubview:self.bar];

    // 2) Liquid selector: a second glass capsule that slides to the selected item.
    //    Added after the glass backdrop (so it draws above it) and before the items (so icons stay on top).
    self.selector = [[UIVisualEffectView alloc] initWithEffect:AmeGlassEffect(UIBlurEffectStyleSystemThinMaterial)];
    self.selector.userInteractionEnabled = NO;
    self.selector.clipsToBounds = YES;
    self.selector.layer.cornerCurve = kCACornerCurveContinuous;
    self.selector.contentView.backgroundColor = AmeUISelectedFillColor();
    [self.bar addSubview:self.selector];

    // Visible order is independent of the stable internal controller array.
    NSArray<NSString *> *symbols = @[
        @"house", @"square.stack.3d.up", @"arrow.down.circle", @"paintpalette", @"slider.horizontal.3"
    ];
    NSArray<NSString *> *titles = @[
        localize(@"tab.home", @"Home"),
        localize(@"tab.instances", @"Instances"),
        localize(@"tab.download", @"Downloads"),
        MetallicPresentationText(@"renewed.appearance.title", @"Appearance"),
        localize(@"tab.settings", @"Settings")
    ];

    NSMutableArray<UIView *> *items = [NSMutableArray array];
    NSMutableArray<UIImageView *> *icons = [NSMutableArray array];
    NSMutableArray<UILabel *> *labels = [NSMutableArray array];
    NSMutableArray<UIButton *> *buttons = [NSMutableArray array];
    for (NSInteger index = 0; index < (NSInteger)symbols.count; index++) {
        UIImageView *icon = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:symbols[index]]];
        icon.translatesAutoresizingMaskIntoConstraints = NO;
        icon.contentMode = UIViewContentModeScaleAspectFit;
        [icon.widthAnchor constraintEqualToConstant:24.0].active = YES;
        [icon.heightAnchor constraintEqualToConstant:24.0].active = YES;

        UILabel *label = [[UILabel alloc] init];
        label.text = titles[index];
        label.font = AmeUINavigationFont();
        label.hidden = (titles[index].length == 0);

        UIStackView *content = [[UIStackView alloc] initWithArrangedSubviews:@[icon, label]];
        content.translatesAutoresizingMaskIntoConstraints = NO;
        content.axis = UILayoutConstraintAxisHorizontal;
        content.alignment = UIStackViewAlignmentCenter;
        content.spacing = 7.0;
        content.userInteractionEnabled = NO;
        content.accessibilityElementsHidden = YES;

        UIView *item = [[UIView alloc] init];
        item.translatesAutoresizingMaskIntoConstraints = NO;
        [item addSubview:content];

        UIButton *hit = [UIButton buttonWithType:UIButtonTypeCustom];
        hit.translatesAutoresizingMaskIntoConstraints = NO;
        hit.tag = index;
        hit.accessibilityLabel = (titles[index].length > 0) ? titles[index] : @"Help";
        [hit addTarget:self action:@selector(tapped:) forControlEvents:UIControlEventTouchUpInside];
        [item addSubview:hit];

        [NSLayoutConstraint activateConstraints:@[
            [item.heightAnchor constraintEqualToConstant:kNavBarHeight - 2.0 * kNavBarPad],
            [content.leadingAnchor constraintGreaterThanOrEqualToAnchor:item.leadingAnchor constant:kNavItemPadH],
            [content.trailingAnchor constraintLessThanOrEqualToAnchor:item.trailingAnchor constant:-kNavItemPadH],
            [content.centerYAnchor constraintEqualToAnchor:item.centerYAnchor],
            [content.centerXAnchor constraintEqualToAnchor:item.centerXAnchor],
            [item.widthAnchor constraintGreaterThanOrEqualToConstant:44],
            [hit.leadingAnchor constraintEqualToAnchor:item.leadingAnchor],
            [hit.trailingAnchor constraintEqualToAnchor:item.trailingAnchor],
            [hit.topAnchor constraintEqualToAnchor:item.topAnchor],
            [hit.bottomAnchor constraintEqualToAnchor:item.bottomAnchor]
        ]];

        [items addObject:item];
        [icons addObject:icon];
        [labels addObject:label];
        [buttons addObject:hit];
    }
    self.items = items;
    self.icons = icons;
    self.labels = labels;
    self.buttons = buttons;

    self.naturalWidth = [self.widthAnchor constraintGreaterThanOrEqualToConstant:[self intrinsicContentSize].width];
    self.naturalWidth.active = YES;
    self.stack = [[UIStackView alloc] initWithArrangedSubviews:items];
    self.stack.translatesAutoresizingMaskIntoConstraints = NO;
    self.stack.axis = UILayoutConstraintAxisHorizontal;
    self.stack.alignment = UIStackViewAlignmentCenter;
    self.stack.spacing = 0.0;
    self.stack.distribution = UIStackViewDistributionFill;
    [self.bar addSubview:self.stack];

    [NSLayoutConstraint activateConstraints:@[
        [self.bar.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [self.bar.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        [self.bar.topAnchor constraintEqualToAnchor:self.topAnchor],
        [self.bar.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
        [self.bar.heightAnchor constraintEqualToConstant:kNavBarHeight],
        [self.stack.leadingAnchor constraintEqualToAnchor:self.bar.leadingAnchor constant:kNavBarPad],
        [self.stack.trailingAnchor constraintEqualToAnchor:self.bar.trailingAnchor constant:-kNavBarPad],
        [self.stack.centerYAnchor constraintEqualToAnchor:self.bar.centerYAnchor]
    ]];
}

- (CGSize)intrinsicContentSize {
    CGFloat width = 2 * kNavBarPad;
    for (UILabel *label in self.labels) width += ceil(label.intrinsicContentSize.width) + 24 + 7 + 2 * kNavItemPadH;
    return CGSizeMake(width, kNavBarHeight);
}

- (void)layoutSubviews {
    [super layoutSubviews];
    // Re-seat the selector only when the bar's width changed (rotation, first layout), so a running
    // slide animation is never interrupted by an unrelated layout pass.
    CGFloat width = self.bar.bounds.size.width;
    if (fabs(width - self.lastBarWidth) > 0.5) {
        self.lastBarWidth = width;
        [self placeSelectorAnimated:NO];
    }
}

/// Move only the decorative selection capsule; controller transitions remain untouched.
- (void)placeSelectorAnimated:(BOOL)animated {
    if (self.items.count == 0 || self.bar.bounds.size.width < 1.0) return;
    [self.bar layoutIfNeeded];

    NSInteger index = (self.appearanceActive ? AMEPrimaryDestinationAppearance : AMEPrimaryDestinationForTab(self.selectedIndex));
    self.selector.hidden = (index == NSNotFound);
    if (index == NSNotFound) return;
    UIView *item = self.items[index];
    CGRect target = [self.bar convertRect:item.bounds fromView:item];
    self.selector.layer.cornerRadius = target.size.height / 2.0;

    void (^place)(void) = ^{
        self.selector.bounds = CGRectMake(0, 0, target.size.width, target.size.height);
        self.selector.center = CGPointMake(CGRectGetMidX(target), CGRectGetMidY(target));
    };

    BOOL firstPlacement = (self.selector.bounds.size.width < 1.0);
    if (!animated || firstPlacement || UIAccessibilityIsReduceMotionEnabled()) {
        [self.selector.layer removeAllAnimations];
        self.selector.transform = CGAffineTransformIdentity;
        place();
        return;
    }

    UIViewAnimationOptions options = UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction;
    [UIView animateWithDuration:0.22 delay:0 options:options animations:place completion:nil];
}

- (void)setSelectedIndex:(NSInteger)index {
    BOOL changed = (_selectedIndex != index);
    _selectedIndex = index;
    for (NSInteger i = 0; i < (NSInteger)self.icons.count; i++) {
        BOOL selected = (i == (self.appearanceActive ? AMEPrimaryDestinationAppearance : AMEPrimaryDestinationForTab(index)));
        UIColor *color = selected ? NavAccentColor() : AmeUIPrimaryTextColor();
        self.icons[i].tintColor = color;
        self.labels[i].textColor = color;
        self.buttons[i].accessibilityTraits = UIAccessibilityTraitButton | (selected ? UIAccessibilityTraitSelected : 0);
    }
    [self placeSelectorAnimated:changed];
}

- (void)themeChanged:(NSNotification *)notification {
    if ([notification.name isEqualToString:AMEGlassStyleChangedNotification]) {
        AmeApplyGlassChipStyle(self.bar, kNavBarHeight / 2.0, YES);
        self.selector.effect = AmeGlassEffect(UIBlurEffectStyleSystemThinMaterial);
    }
    self.selector.contentView.backgroundColor = AmeUISelectedFillColor();
    BackgroundManager *manager = [BackgroundManager sharedManager];
    UIVisualEffectView *backdrop = (UIVisualEffectView *)[self.bar viewWithTag:kAmeGlassBackdropTag];
    [manager applyInterfaceAppearanceToMaterial:backdrop inView:self.bar];
    self.selector.alpha = manager.uiEffect == BackgroundUIEffectBlur ? manager.interfaceBlurIntensity : 0.0;
    if ([notification.name isEqualToString:UIContentSizeCategoryDidChangeNotification]) {
        for (UILabel *label in self.labels) label.font = AmeUINavigationFont();
        self.naturalWidth.constant = [self intrinsicContentSize].width;
        [self invalidateIntrinsicContentSize];
        // Text width can change without the outer bar width changing.
        self.lastBarWidth = -1.0;
        [self setNeedsLayout];
    }
    self.selectedIndex = _selectedIndex;
}

- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];
    // Refresh layer-backed colors only in the existing opt-in highlight path.
    if (AMEGlassStyleAllowsHandDrawnGlass()) AmeApplyGlassChipStyle(self.bar, kNavBarHeight / 2.0, YES);
    self.selectedIndex = _selectedIndex;
}

- (void)tabNote:(NSNotification *)notification {
    NSNumber *index = notification.userInfo[@"index"];
    if ([index isKindOfClass:NSNumber.class]) self.selectedIndex = index.integerValue;
}

- (void)tapped:(UIButton *)button {
    // The root owns selection; presenting Appearance must not pretend to switch internal tabs.
    if (self.onSelect) self.onSelect((AMEPrimaryDestination)button.tag);
}

@end
