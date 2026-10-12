#import "HomeTopNavView.h"

@interface HomeTopNavView ()
@property (nonatomic, strong) NSArray<UIButton *> *buttons;
@end

@implementation HomeTopNavView

static UIColor *NavPink(void) {
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
    UIColor *bg = [UIColor colorWithWhite:0.2 alpha:0.95];

    UIView *pill = [[UIView alloc] init];
    pill.translatesAutoresizingMaskIntoConstraints = NO;
    pill.backgroundColor = bg;
    pill.layer.cornerRadius = 22;
    UILabel *title = [[UILabel alloc] init];
    title.translatesAutoresizingMaskIntoConstraints = NO;
    title.text = @"Home";
    title.font = [UIFont systemFontOfSize:17 weight:UIFontWeightMedium];
    title.textColor = UIColor.whiteColor;
    [pill addSubview:title];

    UIView *bar = [[UIView alloc] init];
    bar.translatesAutoresizingMaskIntoConstraints = NO;
    bar.backgroundColor = bg;
    bar.layer.cornerRadius = 22;

    NSArray *icons = @[@"house.fill", @"arrow.down", @"sparkles",
                       @"puzzlepiece.extension.fill", @"gearshape.fill", @"questionmark"];
    NSMutableArray *btns = [NSMutableArray array];
    for (NSInteger i = 0; i < icons.count; i++) {
        UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
        [b setImage:[UIImage systemImageNamed:icons[i]] forState:UIControlStateNormal];
        b.tag = i;
        b.layer.cornerRadius = 8;
        [b.widthAnchor constraintEqualToConstant:40].active = YES;
        [b.heightAnchor constraintEqualToConstant:34].active = YES;
        [b addTarget:self action:@selector(tapped:) forControlEvents:UIControlEventTouchUpInside];
        [btns addObject:b];
    }
    self.buttons = btns;

    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:btns];
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    stack.axis = UILayoutConstraintAxisHorizontal;
    stack.spacing = 6;
    [bar addSubview:stack];

    [self addSubview:pill];
    [self addSubview:bar];

    [NSLayoutConstraint activateConstraints:@[
        [pill.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [pill.topAnchor constraintEqualToAnchor:self.topAnchor],
        [pill.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
        [pill.heightAnchor constraintEqualToConstant:44],
        [title.leadingAnchor constraintEqualToAnchor:pill.leadingAnchor constant:20],
        [title.trailingAnchor constraintEqualToAnchor:pill.trailingAnchor constant:-20],
        [title.centerYAnchor constraintEqualToAnchor:pill.centerYAnchor],

        [bar.leadingAnchor constraintEqualToAnchor:pill.trailingAnchor constant:10],
        [bar.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        [bar.topAnchor constraintEqualToAnchor:self.topAnchor],
        [bar.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
        [stack.leadingAnchor constraintEqualToAnchor:bar.leadingAnchor constant:10],
        [stack.trailingAnchor constraintEqualToAnchor:bar.trailingAnchor constant:-10],
        [stack.centerYAnchor constraintEqualToAnchor:bar.centerYAnchor],
    ]];
}

- (void)setSelectedIndex:(NSInteger)index {
    _selectedIndex = index;
    for (UIButton *b in self.buttons) {
        BOOL sel = (b.tag == index);
        b.tintColor = sel ? NavPink() : [UIColor colorWithWhite:0.75 alpha:1.0];
        b.backgroundColor = sel ? [NavPink() colorWithAlphaComponent:0.25] : UIColor.clearColor;
    }
}

- (void)tabNote:(NSNotification *)n {
    NSNumber *i = n.userInfo[@"index"];
    if ([i isKindOfClass:[NSNumber class]]) self.selectedIndex = i.integerValue;
}

- (void)tapped:(UIButton *)b {
    if (b.tag <= 4) self.selectedIndex = b.tag;
    if (self.onSelect) self.onSelect(b.tag);
}

@end
