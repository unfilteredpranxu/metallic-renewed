#import "HomeTopNavView.h"
#import "UIKit+GlassSurface.h"   // AmeApplyGlassChipStyle / AmeGlassEffect (system Liquid Glass on iOS 26+)
#import "utils.h"                // localize()

// Bar geometry. AmeRootTabController and LauncherNewsViewController reserve space for this height,
// so if you change it, update kHomeNavReserve in LauncherNewsViewController.m and the
// additionalSafeAreaInsets value in AmeRootTabController.m as well (height + 8 top margin + 8 gap).
static const CGFloat kNavBarHeight  = 60.0;
static const CGFloat kNavBarPad     = 6.0;    // gap between the bar edge and the selector
static const CGFloat kNavItemPadH   = 16.0;   // horizontal padding inside each item

@interface HomeTopNavView ()
@property (nonatomic, strong) UIView *bar;
@property (nonatomic, strong) UIStackView *stack;
@property (nonatomic, strong) UIVisualEffectView *selector;   // the sliding "liquid" capsule
@property (nonatomic, strong) NSArray<UIView *> *items;
@property (nonatomic, strong) NSArray<UIImageView *> *icons;
@property (nonatomic, strong) NSArray<UILabel *> *labels;
@property (nonatomic, assign) CGFloat lastBarWidth;
@end

@implementation HomeTopNavView

static UIColor *NavAccentColor(void) {
    return [UIColor colorWithRed:1.0 green:0.43 blue:0.78 alpha:1.0];
}

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        [self build];
        self.selectedIndex = 0;
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(tabNote:)
                                                     name:@"AmeTabSelected"
                                                   object:nil];
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
    self.selector.contentView.backgroundColor = [NavAccentColor() colorWithAlphaComponent:0.22];
    [self.bar addSubview:self.selector];

    // 3) Items: icon + label. The last one (Help) is icon-only and does not switch tabs.
    NSArray<NSString *> *symbols = @[
        @"house.fill", @"arrow.down", @"sparkles",
        @"puzzlepiece.extension.fill", @"gearshape.fill", @"questionmark"
    ];
    NSArray<NSString *> *titles = @[
        localize(@"tab.home", @"Home"),
        localize(@"tab.download", @"Downloads"),
        localize(@"tab.ai", @"AI"),
        localize(@"tab.instances", @"Instances"),
        localize(@"tab.settings", @"Settings"),
        @""
    ];

    NSMutableArray<UIView *> *items = [NSMutableArray array];
    NSMutableArray<UIImageView *> *icons = [NSMutableArray array];
    NSMutableArray<UILabel *> *labels = [NSMutableArray array];
    for (NSInteger index = 0; index < (NSInteger)symbols.count; index++) {
        UIImageView *icon = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:symbols[index]]];
        icon.translatesAutoresizingMaskIntoConstraints = NO;
        icon.contentMode = UIViewContentModeScaleAspectFit;
        [icon.widthAnchor constraintEqualToConstant:24.0].active = YES;
        [icon.heightAnchor constraintEqualToConstant:24.0].active = YES;

        UILabel *label = [[UILabel alloc] init];
        label.text = titles[index];
        label.font = [UIFont systemFontOfSize:15.0 weight:UIFontWeightSemibold];
        label.hidden = (titles[index].length == 0);

        UIStackView *content = [[UIStackView alloc] initWithArrangedSubviews:@[icon, label]];
        content.translatesAutoresizingMaskIntoConstraints = NO;
        content.axis = UILayoutConstraintAxisHorizontal;
        content.alignment = UIStackViewAlignmentCenter;
        content.spacing = 7.0;
        content.userInteractionEnabled = NO;

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
            [content.leadingAnchor constraintEqualToAnchor:item.leadingAnchor constant:kNavItemPadH],
            [content.trailingAnchor constraintEqualToAnchor:item.trailingAnchor constant:-kNavItemPadH],
            [content.centerYAnchor constraintEqualToAnchor:item.centerYAnchor],
            [hit.leadingAnchor constraintEqualToAnchor:item.leadingAnchor],
            [hit.trailingAnchor constraintEqualToAnchor:item.trailingAnchor],
            [hit.topAnchor constraintEqualToAnchor:item.topAnchor],
            [hit.bottomAnchor constraintEqualToAnchor:item.bottomAnchor]
        ]];

        // The AI entry is no longer shown in the bar. The slot is only hidden (not removed) so the
        // tab indices used by the rest of the app (Instances = 3, Settings = 4) stay valid.
        if (index == 2) item.hidden = YES;

        [items addObject:item];
        [icons addObject:icon];
        [labels addObject:label];
    }
    self.items = items;
    self.icons = icons;
    self.labels = labels;

    self.stack = [[UIStackView alloc] initWithArrangedSubviews:items];
    self.stack.translatesAutoresizingMaskIntoConstraints = NO;
    self.stack.axis = UILayoutConstraintAxisHorizontal;
    self.stack.alignment = UIStackViewAlignmentCenter;
    self.stack.spacing = 2.0;
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

/// Moves the glass selector over the selected item. Animated moves use a spring with a small
/// squash-and-stretch so the capsule behaves like a drop of liquid sliding between items.
- (void)placeSelectorAnimated:(BOOL)animated {
    if (self.items.count == 0 || self.bar.bounds.size.width < 1.0) return;
    [self.bar layoutIfNeeded];

    NSInteger index = MAX(0, MIN(self.selectedIndex, (NSInteger)self.items.count - 1));
    UIView *item = self.items[index];
    CGRect target = [self.bar convertRect:item.bounds fromView:item];
    self.selector.layer.cornerRadius = target.size.height / 2.0;

    void (^place)(void) = ^{
        self.selector.bounds = CGRectMake(0, 0, target.size.width, target.size.height);
        self.selector.center = CGPointMake(CGRectGetMidX(target), CGRectGetMidY(target));
    };

    BOOL firstPlacement = (self.selector.bounds.size.width < 1.0);
    if (!animated || firstPlacement) {
        self.selector.transform = CGAffineTransformIdentity;
        place();
        return;
    }

    UIViewAnimationOptions options = UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction;
    [UIView animateWithDuration:0.55
                          delay:0
         usingSpringWithDamping:0.62
          initialSpringVelocity:0.5
                        options:options
                     animations:place
                     completion:nil];
    [UIView animateKeyframesWithDuration:0.55
                                   delay:0
                                 options:UIViewKeyframeAnimationOptionAllowUserInteraction
                              animations:^{
        [UIView addKeyframeWithRelativeStartTime:0.0 relativeDuration:0.35 animations:^{
            self.selector.transform = CGAffineTransformMakeScale(1.16, 0.90);
        }];
        [UIView addKeyframeWithRelativeStartTime:0.35 relativeDuration:0.65 animations:^{
            self.selector.transform = CGAffineTransformIdentity;
        }];
    } completion:nil];
}

- (void)setSelectedIndex:(NSInteger)index {
    BOOL changed = (_selectedIndex != index);
    _selectedIndex = index;
    for (NSInteger i = 0; i < (NSInteger)self.icons.count; i++) {
        BOOL selected = (i == index);
        UIColor *color = selected ? NavAccentColor() : [UIColor colorWithWhite:0.92 alpha:0.9];
        self.icons[i].tintColor = color;
        self.labels[i].textColor = color;
    }
    [self placeSelectorAnimated:changed];
}

- (void)tabNote:(NSNotification *)notification {
    NSNumber *index = notification.userInfo[@"index"];
    if ([index isKindOfClass:NSNumber.class]) self.selectedIndex = index.integerValue;
}

- (void)tapped:(UIButton *)button {
    if (button.tag <= 4) self.selectedIndex = button.tag;
    if (self.onSelect) self.onSelect(button.tag);
}

@end
