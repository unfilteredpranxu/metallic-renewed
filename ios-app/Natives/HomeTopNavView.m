#import <AudioToolbox/AudioToolbox.h>
#import <dlfcn.h>
#import "ios_uikit_bridge.h"
#import "HomeTopNavView.h"
#import "LauncherPreferences.h"
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
@property(nonatomic,strong) UIScrollView *destinationScroll;
@property(nonatomic,strong) UIButton *moreButton;
@property (nonatomic, strong) UIStackView *stack;
@property (nonatomic, strong) UIVisualEffectView *selector;   // the sliding "liquid" capsule
@property (nonatomic, strong) NSArray<UIView *> *items;
@property (nonatomic, strong) NSArray<UIImageView *> *icons;
@property (nonatomic, strong) NSArray<UILabel *> *labels;
@property (nonatomic, strong) NSArray<UIButton *> *buttons;
@property (nonatomic, assign) CGFloat lastBarWidth;
@property(nonatomic) NSInteger lastPresentedDestination;
@property(nonatomic,copy) UIContentSizeCategory referenceTextCategory;
@property (nonatomic, strong) NSLayoutConstraint *naturalWidth;
@property (nonatomic, strong) NSLayoutConstraint *barHeight;
@property (nonatomic, strong) NSMutableArray<NSLayoutConstraint *> *itemWidths;
@property (nonatomic, strong) NSMutableArray<NSLayoutConstraint *> *itemHeights;
@end

@implementation HomeTopNavView

static UIColor *NavAccentColor(void) {
    return AmeUIPrimaryTextColor(); // The reference uses neutral text; selection comes from the translucent capsule.
}

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        _referenceScale = 0.8;
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
    NSString *downloads=MetallicPresentationText(@"tab.download",@"Downloads");
    // The authoritative English catalog uses the singular action; this destination is a catalogue.
    if ([AmeLauncherEffectiveLanguageCode() hasPrefix:@"en"] && [downloads isEqualToString:@"Download"]) downloads=@"Downloads";
    NSArray<NSString *> *titles = @[
        MetallicPresentationText(@"tab.home", @"Home"),
        MetallicPresentationText(@"tab.instances", @"Instances"),
        downloads,
        MetallicPresentationText(@"renewed.appearance.title", @"Appearance"),
        MetallicPresentationText(@"tab.settings", @"Settings")
    ];

    self.itemWidths = [NSMutableArray array]; self.itemHeights = [NSMutableArray array];
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

        NSArray *referenceWidths = @[@132,@170,@176,@190,@158];
        NSLayoutConstraint *itemWidth = [item.widthAnchor constraintEqualToConstant:[referenceWidths[index] doubleValue]*self.referenceScale];
        NSLayoutConstraint *itemHeight = [item.heightAnchor constraintEqualToConstant:44];
        [self.itemWidths addObject:itemWidth]; [self.itemHeights addObject:itemHeight];
        [NSLayoutConstraint activateConstraints:@[
            itemHeight, itemWidth,
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
    self.naturalWidth.priority=UILayoutPriorityDefaultLow; self.naturalWidth.active = YES;
    [self setContentCompressionResistancePriority:UILayoutPriorityDefaultLow forAxis:UILayoutConstraintAxisHorizontal];
    self.stack = [[UIStackView alloc] initWithArrangedSubviews:items];
    self.stack.translatesAutoresizingMaskIntoConstraints = NO;
    self.stack.axis = UILayoutConstraintAxisHorizontal;
    self.stack.alignment = UIStackViewAlignmentCenter;
    self.stack.spacing = 0.0;
    self.stack.distribution = UIStackViewDistributionFill;
    self.destinationScroll=[[UIScrollView alloc] init]; self.destinationScroll.translatesAutoresizingMaskIntoConstraints=NO;
    self.destinationScroll.showsHorizontalScrollIndicator=NO; self.destinationScroll.contentInsetAdjustmentBehavior=UIScrollViewContentInsetAdjustmentNever;
    [self.bar addSubview:self.destinationScroll]; [self.destinationScroll addSubview:self.selector]; [self.destinationScroll addSubview:self.stack];
    self.moreButton=[UIButton buttonWithType:UIButtonTypeSystem]; self.moreButton.translatesAutoresizingMaskIntoConstraints=NO;
    [self.moreButton setImage:[UIImage systemImageNamed:@"ellipsis"] forState:UIControlStateNormal]; self.moreButton.tintColor=AmeUIPrimaryTextColor();
    [self.moreButton addTarget:self action:@selector(menuOpened:) forControlEvents:UIControlEventMenuActionTriggered];
    self.moreButton.accessibilityLabel=@"More launcher actions"; self.moreButton.showsMenuAsPrimaryAction=YES;
    [self.bar addSubview:self.moreButton];
    [NSLayoutConstraint activateConstraints:@[
        [self.moreButton.trailingAnchor constraintEqualToAnchor:self.bar.trailingAnchor constant:-16], [self.moreButton.centerYAnchor constraintEqualToAnchor:self.bar.centerYAnchor],
        [self.moreButton.widthAnchor constraintEqualToConstant:44], [self.moreButton.heightAnchor constraintEqualToConstant:44],
        [self.destinationScroll.leadingAnchor constraintEqualToAnchor:self.bar.leadingAnchor constant:6], [self.destinationScroll.trailingAnchor constraintEqualToAnchor:self.moreButton.leadingAnchor constant:-8],
        [self.destinationScroll.topAnchor constraintEqualToAnchor:self.bar.topAnchor], [self.destinationScroll.bottomAnchor constraintEqualToAnchor:self.bar.bottomAnchor],
        [self.stack.topAnchor constraintEqualToAnchor:self.destinationScroll.contentLayoutGuide.topAnchor], [self.stack.bottomAnchor constraintEqualToAnchor:self.destinationScroll.contentLayoutGuide.bottomAnchor], [self.stack.heightAnchor constraintEqualToAnchor:self.destinationScroll.frameLayoutGuide.heightAnchor]
    ]];

    self.barHeight = [self.bar.heightAnchor constraintEqualToConstant:kNavBarHeight];
    [NSLayoutConstraint activateConstraints:@[
        [self.bar.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [self.bar.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        [self.bar.topAnchor constraintEqualToAnchor:self.topAnchor],
        [self.bar.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
        self.barHeight,
        [self.stack.leadingAnchor constraintEqualToAnchor:self.destinationScroll.contentLayoutGuide.leadingAnchor],
        [self.stack.trailingAnchor constraintEqualToAnchor:self.destinationScroll.contentLayoutGuide.trailingAnchor],
        [self.stack.centerYAnchor constraintEqualToAnchor:self.destinationScroll.centerYAnchor]
    ]];
}

- (void)setMoreMenu:(UIMenu *)menu { _moreMenu=menu; self.moreButton.menu=menu; }

- (CGSize)intrinsicContentSize {
    return CGSizeMake(MAX(842*self.referenceScale,self.naturalWidth.constant),MAX(MAX(48,68*self.referenceScale),self.barHeight.constant));
}
- (void)setReferenceScale:(CGFloat)scale {
    UIContentSizeCategory category=self.traitCollection.preferredContentSizeCategory;
    if (fabs(_referenceScale-scale)<0.001 && [self.referenceTextCategory isEqualToString:category]) return;
    _referenceScale=scale; self.referenceTextCategory=category;
    NSArray *widths=@[@132,@170,@176,@190,@158];
    for (NSUInteger i=0;i<self.labels.count;i++) {
        self.labels[i].font = [[UIFontMetrics metricsForTextStyle:UIFontTextStyleBody] scaledFontForFont:[UIFont systemFontOfSize:22*scale weight:UIFontWeightMedium]];
        self.icons[i].image = [UIImage systemImageNamed:@[@"house",@"square.stack.3d.up",@"arrow.down.circle",@"paintpalette",@"slider.horizontal.3"][i] withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:24*scale weight:UIImageSymbolWeightRegular]];
        for (NSLayoutConstraint *c in self.icons[i].constraints) if (c.firstAttribute==NSLayoutAttributeWidth || c.firstAttribute==NSLayoutAttributeHeight) c.constant=24*scale;
        self.itemWidths[i].constant=MAX(MAX(44,[widths[i] doubleValue]*scale),self.labels[i].intrinsicContentSize.width+47*scale);
        self.itemHeights[i].constant=MAX(MAX(44,56*scale),self.labels[i].font.lineHeight+8*scale);
    }
    CGFloat contentHeight=44,contentWidth=12*scale;
    for(NSLayoutConstraint *width in self.itemWidths)contentWidth+=width.constant;
    for(UILabel *label in self.labels)contentHeight=MAX(contentHeight,label.font.lineHeight+8*scale);
    self.barHeight.constant=MAX(MAX(48,68*scale),contentHeight+6*scale);
    self.naturalWidth.constant=MAX(842*scale,contentWidth);
    self.bar.layer.cornerRadius=self.barHeight.constant/2;
    [self.moreButton setPreferredSymbolConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:24*scale weight:UIImageSymbolWeightMedium] forImageInState:UIControlStateNormal];
    [self invalidateIntrinsicContentSize]; self.lastBarWidth=-1; [self setNeedsLayout];
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
    CGRect target = [self.destinationScroll convertRect:item.bounds fromView:item];
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
    NSInteger destination=self.appearanceActive?AMEPrimaryDestinationAppearance:AMEPrimaryDestinationForTab(index);
    BOOL changed = (_selectedIndex != index) || self.lastPresentedDestination!=destination;
    self.lastPresentedDestination=destination;
    _selectedIndex = index;
    for (NSInteger i = 0; i < (NSInteger)self.icons.count; i++) {
        BOOL selected = (i == (self.appearanceActive ? AMEPrimaryDestinationAppearance : AMEPrimaryDestinationForTab(index)));
        UIColor *color = selected ? NavAccentColor() : AmeUIPrimaryTextColor();
        self.icons[i].tintColor = color;
        self.labels[i].textColor = color;
        self.buttons[i].accessibilityTraits = UIAccessibilityTraitButton | (selected ? UIAccessibilityTraitSelected : 0);
    }
    [self placeSelectorAnimated:changed];
    if(changed && destination!=NSNotFound) { [self.destinationScroll layoutIfNeeded]; CGRect target=[self.destinationScroll convertRect:self.items[destination].bounds fromView:self.items[destination]]; [self.destinationScroll scrollRectToVisible:target animated:!UIAccessibilityIsReduceMotionEnabled()]; }
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
        CGFloat scale=self.referenceScale;
        _referenceScale=-1; // Refit the existing controls after text metrics change.
        self.referenceScale=scale;
        [self.superview setNeedsLayout];
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

- (void)menuOpened:(UIButton *)button { MetallicPlayUIFeedback(@"menu"); }

- (void)tapped:(UIButton *)button {
    MetallicPlayUIFeedback(@"navigation");
    // The root owns selection; presenting Appearance must not pretend to switch internal tabs.
    if (self.onSelect) self.onSelect((AMEPrimaryDestination)button.tag);
}

@end


void MetallicPlayUIFeedback(NSString *event) {
    if(!NSThread.isMainThread) { dispatch_async(dispatch_get_main_queue(),^{ MetallicPlayUIFeedback(event); }); return; }
    if(UIApplication.sharedApplication.applicationState!=UIApplicationStateActive || AmeGameLandscapeLockActive())return;
    static CFTimeInterval last=0; CFTimeInterval now=CACurrentMediaTime(); if(now-last<.08)return; last=now;
    if(!getPrefBool(@"control.disable_haptics") && UIDevice.currentDevice.userInterfaceIdiom==UIUserInterfaceIdiomPhone && !NSProcessInfo.processInfo.lowPowerModeEnabled) {
        static UISelectionFeedbackGenerator *feedback; if(!feedback)feedback=[[UISelectionFeedbackGenerator alloc] init]; [feedback selectionChanged];
    }
    if(![NSUserDefaults.standardUserDefaults boolForKey:@"metallic.ui.interfaceSounds"])return;
    // Public system sound API, resolved once: no new linker requirement, audio-session changes,
    // playback engine, external code or impact on the Minecraft audio category.
    static OSStatus (*createSound)(CFURLRef,SystemSoundID *); static void (*playSound)(SystemSoundID);
    static NSMutableDictionary<NSString *,NSNumber *> *cache; static dispatch_once_t once;
    dispatch_once(&once,^{
        void *framework=dlopen("/System/Library/Frameworks/AudioToolbox.framework/AudioToolbox",RTLD_LAZY|RTLD_LOCAL);
        if(framework) { createSound=(OSStatus(*)(CFURLRef,SystemSoundID *))dlsym(framework,"AudioServicesCreateSystemSoundID"); playSound=(void(*)(SystemSoundID))dlsym(framework,"AudioServicesPlaySystemSound"); }
        cache=[NSMutableDictionary dictionary];
    });
    if(!createSound || !playSound)return;
    if(![@[@"navigation",@"confirm",@"menu",@"toggle",@"instance",@"completed",@"failed",@"launch"] containsObject:event])return;
    NSNumber *cached=cache[event];
    if(!cached) {
        NSURL *url=[NSBundle.mainBundle URLForResource:event withExtension:@"wav" subdirectory:@"MetallicUI"]; if(!url)return;
        SystemSoundID sound=0; if(createSound((__bridge CFURLRef)url,&sound)!=noErr)return;
        cached=@(sound);cache[event]=cached;
    }
    playSound(cached.unsignedIntValue);
}
