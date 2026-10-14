#import "HomeTopNavView.h"

@interface HomeTopNavView ()
@property (nonatomic, strong) NSArray<UIButton *> *buttons;
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
    UIColor *surface = [UIColor colorWithWhite:0.12 alpha:0.92];
    UIView *titlePill = [[UIView alloc] init];
    titlePill.translatesAutoresizingMaskIntoConstraints = NO;
    titlePill.backgroundColor = surface;
    titlePill.layer.cornerRadius = 22.0;

    UILabel *title = [[UILabel alloc] init];
    title.translatesAutoresizingMaskIntoConstraints = NO;
    title.text = @"Home";
    title.font = [UIFont systemFontOfSize:16.0 weight:UIFontWeightSemibold];
    title.textColor = UIColor.whiteColor;
    [titlePill addSubview:title];

    UIView *bar = [[UIView alloc] init];
    bar.translatesAutoresizingMaskIntoConstraints = NO;
    bar.backgroundColor = surface;
    bar.layer.cornerRadius = 22.0;

    NSArray<NSString *> *symbols = @[
        @"house.fill", @"arrow.down", @"sparkles",
        @"puzzlepiece.extension.fill", @"gearshape.fill", @"questionmark"
    ];
    NSArray<NSString *> *labels = @[@"Home", @"Download", @"AI", @"Instances", @"Settings", @"Help"];
    NSMutableArray<UIButton *> *buttons = [NSMutableArray arrayWithCapacity:symbols.count];
    for (NSInteger index = 0; index < symbols.count; index++) {
        UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
        button.translatesAutoresizingMaskIntoConstraints = NO;
        [button setImage:[UIImage systemImageNamed:symbols[index]] forState:UIControlStateNormal];
        button.accessibilityLabel = labels[index];
        button.tag = index;
        button.layer.cornerRadius = 8.0;
        [button.widthAnchor constraintEqualToConstant:34.0].active = YES;
        [button.heightAnchor constraintEqualToConstant:34.0].active = YES;
        [button addTarget:self action:@selector(tapped:) forControlEvents:UIControlEventTouchUpInside];
        [buttons addObject:button];
    }
    self.buttons = buttons;

    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:buttons];
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    stack.axis = UILayoutConstraintAxisHorizontal;
    stack.spacing = 2.0;
    [bar addSubview:stack];
    [self addSubview:titlePill];
    [self addSubview:bar];

    [NSLayoutConstraint activateConstraints:@[
        [titlePill.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [titlePill.topAnchor constraintEqualToAnchor:self.topAnchor],
        [titlePill.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
        [titlePill.heightAnchor constraintEqualToConstant:44.0],
        [title.leadingAnchor constraintEqualToAnchor:titlePill.leadingAnchor constant:16.0],
        [title.trailingAnchor constraintEqualToAnchor:titlePill.trailingAnchor constant:-16.0],
        [title.centerYAnchor constraintEqualToAnchor:titlePill.centerYAnchor],
        [bar.leadingAnchor constraintEqualToAnchor:titlePill.trailingAnchor constant:8.0],
        [bar.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        [bar.topAnchor constraintEqualToAnchor:self.topAnchor],
        [bar.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
        [stack.leadingAnchor constraintEqualToAnchor:bar.leadingAnchor constant:6.0],
        [stack.trailingAnchor constraintEqualToAnchor:bar.trailingAnchor constant:-6.0],
        [stack.centerYAnchor constraintEqualToAnchor:bar.centerYAnchor]
    ]];
}

- (void)setSelectedIndex:(NSInteger)index {
    _selectedIndex = index;
    for (UIButton *button in self.buttons) {
        BOOL selected = (button.tag == index);
        button.tintColor = selected ? NavAccentColor() : [UIColor colorWithWhite:0.82 alpha:1.0];
        button.backgroundColor = selected ? [NavAccentColor() colorWithAlphaComponent:0.22] : UIColor.clearColor;
    }
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
