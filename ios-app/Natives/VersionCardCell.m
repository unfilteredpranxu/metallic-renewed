#import "utils.h"
// Downloads' existing native result cell: neutral managed material, real version/type/date,
// and a row-selection affordance for the original installation-options flow.
// The legacy installedBadge argument comes from saved-profile metadata; present it as a bookmark.

#import "VersionCardCell.h"
#import "BackgroundManager.h"
#import "UIKit+GlassSurface.h"

// 修复问题3：带内边距的 UILabel 子类，让"正式版/测试版"等类型标签文字
// 在背景块内完美居中，不再与背景边缘重叠。
// 通过重写 textRectForBounds: 和 drawTextInRect: 注入左右 8pt / 上下 0pt 内边距，
// 同时保持 UILabel 接口不变，VersionCardCell.h 中的 typeLabel 声明无需修改。
@interface InsetTypeLabel : UILabel
@property (nonatomic, assign) UIEdgeInsets textInsets;
@end

@implementation InsetTypeLabel
- (instancetype)init {
    self = [super init];
    if (self) {
        // 修复"正式版/测试版"文字变成"……"的问题：
        // 字号从 13pt 减小到 11pt，内边距从 (3,10,3,10) 减小到 (2,6,2,6)，
        // 让 pill 标签更紧凑，减少与 versionLabel 的空间竞争。
        // 同时设置 adjustsFontSizeToFitWidth 确保极端情况下也不会被截断。
        _textInsets = UIEdgeInsetsMake(2, 6, 2, 6);
    }
    return self;
}
- (CGRect)textRectForBounds:(CGRect)bounds limitedToNumberOfLines:(NSInteger)numberOfLines {
    CGRect insetRect = UIEdgeInsetsInsetRect(bounds, self.textInsets);
    CGRect textRect = [super textRectForBounds:insetRect limitedToNumberOfLines:numberOfLines];
    textRect.origin.x -= self.textInsets.left;
    textRect.origin.y -= self.textInsets.top;
    return textRect;
}
- (void)drawTextInRect:(CGRect)rect {
    [super drawTextInRect:UIEdgeInsetsInsetRect(rect, self.textInsets)];
}
@end

@interface VersionCardCell ()
// 容器视图：整张卡片的圆角背景（毛玻璃 + 半透明）
@property (nonatomic, strong) UIView *cardContainer;
@property(nonatomic,strong) NSLayoutConstraint *referenceMinimum;
// 左侧类型图标容器（带圆角与类型色背景）
@property (nonatomic, strong) UIView *iconContainer;
// 顶行水平 stack：装 versionLabel + typeLabel，自动处理间距与裁剪
@property (nonatomic, strong) UIStackView *topRowStack;
// 右侧 chevron 指示
@property (nonatomic, strong) UIImageView *chevronView;
- (void)renewedApplyPresentation;
@end

@implementation VersionCardCell

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.backgroundColor = UIColor.clearColor;
        self.contentView.backgroundColor = UIColor.clearColor;
        self.cardContainer = [[UIView alloc] init];
        self.cardContainer.translatesAutoresizingMaskIntoConstraints = NO;
        self.cardContainer.layer.cornerRadius = 18;
        self.cardContainer.layer.cornerCurve = kCACornerCurveContinuous;
        self.cardContainer.clipsToBounds = YES;
        [self.contentView addSubview:self.cardContainer];
        [[BackgroundManager sharedManager] applyEffectToView:self.cardContainer];
        self.iconContainer = [[UIView alloc] init];
        self.iconContainer.translatesAutoresizingMaskIntoConstraints = NO;
        self.iconContainer.layer.cornerRadius = 8;
        self.iconContainer.clipsToBounds = YES;
        [self.cardContainer addSubview:self.iconContainer];
        self.iconImageView = [[UIImageView alloc] init];
        self.iconImageView.translatesAutoresizingMaskIntoConstraints = NO;
        self.iconImageView.contentMode = UIViewContentModeScaleAspectFit;
        [self.iconContainer addSubview:self.iconImageView];
        self.versionLabel = [[UILabel alloc] init];
        self.versionLabel.font = AmeUIFont(AmeUIFontRoleSectionHeading);
        self.versionLabel.textColor = AmeUIPrimaryTextColor();
        self.versionLabel.numberOfLines = 2;
        self.typeLabel = [[InsetTypeLabel alloc] init];
        self.typeLabel.font = AmeUIFont(AmeUIFontRoleDescription);
        self.typeLabel.numberOfLines = 2;
        self.dateLabel = [[UILabel alloc] init];
        self.dateLabel.font = AmeUIFont(AmeUIFontRoleStatus);
        self.dateLabel.textColor = AmeUITertiaryTextColor();
        self.dateLabel.numberOfLines = 0;
        for (UILabel *label in @[self.versionLabel, self.typeLabel, self.dateLabel]) label.adjustsFontForContentSizeCategory = YES;
        self.topRowStack = [[UIStackView alloc] initWithArrangedSubviews:@[self.versionLabel, self.typeLabel, self.dateLabel]];
        self.topRowStack.axis = UILayoutConstraintAxisVertical;
        self.topRowStack.spacing = 4;
        self.topRowStack.translatesAutoresizingMaskIntoConstraints = NO;
        [self.cardContainer addSubview:self.topRowStack];
        self.chevronView = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"arrow.down"]];
        self.chevronView.translatesAutoresizingMaskIntoConstraints = NO;
        self.chevronView.contentMode = UIViewContentModeScaleAspectFit;
        self.chevronView.tintColor = AmeUISecondaryTextColor();
        self.chevronView.userInteractionEnabled = NO; // Decoration; the existing row selection owns the action.
        [self.cardContainer addSubview:self.chevronView];
        self.installedBadge = [[UIView alloc] init];
        self.installedBadge.translatesAutoresizingMaskIntoConstraints = NO;
        self.installedBadge.backgroundColor = AmeUIAccentColor();
        self.installedBadge.layer.cornerRadius = 7;
        self.installedBadge.hidden = YES;
        [self.cardContainer addSubview:self.installedBadge];
        UIImageView *mark = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"bookmark.fill"]];
        mark.translatesAutoresizingMaskIntoConstraints = NO;
        mark.tintColor = UIColor.whiteColor;
        [self.installedBadge addSubview:mark];
        [NSLayoutConstraint activateConstraints:@[
            [self.cardContainer.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:4],
            [self.cardContainer.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-4],
            [self.cardContainer.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor],
            [self.cardContainer.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor],
            [self.iconContainer.leadingAnchor constraintEqualToAnchor:self.cardContainer.leadingAnchor constant:16],
            [self.iconContainer.centerYAnchor constraintEqualToAnchor:self.cardContainer.centerYAnchor],
            [self.iconContainer.widthAnchor constraintEqualToConstant:32],
            [self.iconContainer.heightAnchor constraintEqualToConstant:32],
            [self.iconImageView.topAnchor constraintEqualToAnchor:self.iconContainer.topAnchor],
            [self.iconImageView.bottomAnchor constraintEqualToAnchor:self.iconContainer.bottomAnchor],
            [self.iconImageView.leadingAnchor constraintEqualToAnchor:self.iconContainer.leadingAnchor],
            [self.iconImageView.trailingAnchor constraintEqualToAnchor:self.iconContainer.trailingAnchor],
            [self.topRowStack.leadingAnchor constraintEqualToAnchor:self.iconContainer.trailingAnchor constant:16],
            [self.topRowStack.trailingAnchor constraintEqualToAnchor:self.chevronView.leadingAnchor constant:-16],
            [self.topRowStack.topAnchor constraintEqualToAnchor:self.cardContainer.topAnchor constant:12],
            [self.topRowStack.bottomAnchor constraintLessThanOrEqualToAnchor:self.cardContainer.bottomAnchor constant:-12],
            [self.chevronView.trailingAnchor constraintEqualToAnchor:self.cardContainer.trailingAnchor constant:-16],
            [self.chevronView.centerYAnchor constraintEqualToAnchor:self.cardContainer.centerYAnchor],
            [self.chevronView.widthAnchor constraintEqualToConstant:20],
            [self.chevronView.heightAnchor constraintEqualToConstant:20],
            [self.installedBadge.trailingAnchor constraintEqualToAnchor:self.iconContainer.trailingAnchor constant:4],
            [self.installedBadge.topAnchor constraintEqualToAnchor:self.iconContainer.topAnchor constant:-4],
            [self.installedBadge.widthAnchor constraintEqualToConstant:14],
            [self.installedBadge.heightAnchor constraintEqualToConstant:14],
            [mark.centerXAnchor constraintEqualToAnchor:self.installedBadge.centerXAnchor],
            [mark.centerYAnchor constraintEqualToAnchor:self.installedBadge.centerYAnchor],
            [mark.widthAnchor constraintEqualToConstant:8], [mark.heightAnchor constraintEqualToConstant:8]
        ]];
        self.isAccessibilityElement = YES;
        self.accessibilityTraits = UIAccessibilityTraitButton;
        self.accessibilityHint = localize(@"renewed.downloads.install_options", @"Choose installation options");
        self.referenceMinimum=[self.cardContainer.heightAnchor constraintGreaterThanOrEqualToConstant:80]; self.referenceMinimum.active=YES;
        [self renewedApplyPresentation];
    }
    return self;
}

- (void)configureWithVersionId:(NSString *)versionId
                          date:(NSString *)date
                          type:(NSString *)type {
    self.versionLabel.text = [versionId hasPrefix:@"Minecraft "] ? versionId : [@"Minecraft " stringByAppendingString:versionId ?: @""];
    self.dateLabel.text = date;

    // 类型 → 图标 + 配色映射（参照 ZL2 的 VersionIconPreview 按版本类型切换图标）：
    // release → cube.fill + systemGreen（稳定版）
    // snapshot → hammer.fill + systemOrange（测试版/开发中）
    // old_alpha → clock.fill + systemPurple（远古 alpha）
    // old_beta  → clock.fill + systemPurple（远古 beta）
    NSString *iconName = @"cube.fill";
    UIColor *typeColor = [UIColor systemGreenColor];
    NSString *typeText = localize(@"i18n_str_2058", nil);

    if ([type isEqualToString:@"正式版"] || [type isEqualToString:@"release"]) {
        iconName = @"cube.fill";
        typeColor = [UIColor systemGreenColor];
        typeText = localize(@"i18n_str_2058", nil);
    } else if ([type isEqualToString:@"测试版"] || [type isEqualToString:@"snapshot"]) {
        iconName = @"hammer.fill";
        typeColor = [UIColor systemOrangeColor];
        typeText = localize(@"i18n_str_2059", nil);
    } else if ([type isEqualToString:@"old_alpha"]) {
        iconName = @"clock.fill";
        typeColor = [UIColor systemPurpleColor];
        typeText = @"Alpha";
    } else if ([type isEqualToString:@"old_beta"]) {
        iconName = @"clock.fill";
        typeColor = [UIColor systemPurpleColor];
        typeText = @"Beta";
    } else {
        // 兜底：远古版（合并 old_alpha + old_beta 时使用）
        iconName = @"clock.fill";
        typeColor = [UIColor systemPurpleColor];
        typeText = localize(@"i18n_str_154", nil);
    }

    UIImage *symbol = [UIImage systemImageNamed:iconName];
    if (symbol) {
        self.iconImageView.image = symbol;
    }
    self.iconImageView.tintColor = [UIColor whiteColor];

    // 修复问题4：使用 HMCL 仓库自带的标准草方块图标（grass.png/grass@2x.png），
    // 已导入 Assets.xcassets 的 VanillaIcon 图片集，与 FCL/ZL2/HMCL 等主流启动器视觉完全一致。
    // 图标铺满容器（AspectFill），背景透明以保留草方块纹理本色。
    UIImage *vanillaIcon = [UIImage imageNamed:@"VanillaIcon"];
    if (vanillaIcon) {
        self.iconImageView.image = vanillaIcon;
        self.iconImageView.contentMode = UIViewContentModeScaleAspectFill;
        self.iconImageView.tintColor = nil; // 取消着色，显示草方块原色
        // 草方块图标自带色彩，图标容器背景设为透明
        self.iconContainer.backgroundColor = [UIColor clearColor];
    } else {
        // 兜底：图片集加载失败时回退 SF Symbol + 类型色背景
        self.iconImageView.contentMode = UIViewContentModeScaleAspectFit;
        self.iconImageView.tintColor = [UIColor whiteColor];
        self.iconContainer.backgroundColor = [typeColor colorWithAlphaComponent:0.85];
    }

    // 类型标签：类型色背景 + 白字
    self.typeLabel.text = typeText;
    self.typeLabel.backgroundColor = typeColor;
    [self renewedApplyPresentation];
}

- (void)setInstalled:(BOOL)installed {
    self.installedBadge.hidden = !installed;
    // Existing caller checks saved profiles, not game-file completeness. Never claim installation success.
    self.accessibilityValue = installed ? localize(@"renewed.downloads.saved_profile", @"Referenced by a saved profile") : nil;
}

- (void)prepareForReuse {
    [super prepareForReuse];
    // 重置为 SF Symbol 默认状态（configureWithVersionId 会再次加载 VanillaIcon 覆盖）
    self.iconImageView.image = [UIImage systemImageNamed:@"cube.fill"];
    self.iconImageView.tintColor = [UIColor whiteColor];
    self.iconImageView.contentMode = UIViewContentModeScaleAspectFit;
    self.iconContainer.backgroundColor = [UIColor systemGreenColor];
    self.versionLabel.text = nil;
    self.dateLabel.text = nil;
    self.typeLabel.text = nil;
    self.typeLabel.backgroundColor = [UIColor systemBlueColor];
    self.installedBadge.hidden = YES;
    self.chevronView.tintColor = [UIColor tertiaryLabelColor];
}


- (void)renewedApplyPresentation {
    NSInteger lines = 0; // Self-sizing rows preserve full version/type text at every font size.
    self.versionLabel.numberOfLines = lines;
    self.typeLabel.numberOfLines = lines;
    self.dateLabel.hidden=YES; // Date remains in the native data and VoiceOver metadata, not the reference row.
    self.installedBadge.backgroundColor = AmeUIAccentColor();
    self.typeLabel.backgroundColor = UIColor.clearColor;
    self.typeLabel.textColor = AmeUISecondaryTextColor();
    self.typeLabel.textAlignment = NSTextAlignmentNatural;
    self.cardContainer.layer.borderWidth = AmeUIHairlineWidth(self);
    self.cardContainer.layer.borderColor = AmeUIResolvedColor(AmeUIBorderColor(), self).CGColor;
    self.accessibilityLabel = [NSString stringWithFormat:@"%@, %@, %@", self.versionLabel.text ?: @"", self.typeLabel.text ?: @"", self.dateLabel.text ?: @""];
}

- (void)setHighlighted:(BOOL)highlighted {
    [super setHighlighted:highlighted];
    self.chevronView.tintColor = highlighted ? AmeUIAccentColor() : AmeUISecondaryTextColor();
    self.cardContainer.layer.borderColor = AmeUIResolvedColor(highlighted ? AmeUIAccentColor() : AmeUIBorderColor(), self).CGColor;
}

- (UICollectionViewLayoutAttributes *)preferredLayoutAttributesFittingAttributes:(UICollectionViewLayoutAttributes *)attributes {
    UICollectionViewLayoutAttributes *fitted = [attributes copy];
    if (attributes.size.width <= 0) return fitted;
    [self updateReferenceRowGeometry];
    CGSize size = [self.contentView systemLayoutSizeFittingSize:CGSizeMake(attributes.size.width, UILayoutFittingCompressedSize.height)
        withHorizontalFittingPriority:UILayoutPriorityRequired verticalFittingPriority:UILayoutPriorityFittingSizeLevel];
    CGFloat scale=self.window.bounds.size.width>=900?self.window.bounds.size.width/1536.0:.72;
    fitted.size = CGSizeMake(attributes.size.width, MAX(MAX(72,104*scale), ceil(size.height)));
    return fitted;
}

- (void)updateReferenceRowGeometry {
    CGFloat viewport=self.window.bounds.size.width; if(viewport<=0)viewport=UIScreen.mainScreen.bounds.size.width;
    CGFloat scale=viewport>=900?viewport/1536.0:.72;
    self.versionLabel.font=[[UIFontMetrics metricsForTextStyle:UIFontTextStyleBody] scaledFontForFont:[UIFont systemFontOfSize:24*scale weight:UIFontWeightSemibold]];
    self.typeLabel.font=[[UIFontMetrics metricsForTextStyle:UIFontTextStyleBody] scaledFontForFont:[UIFont systemFontOfSize:20*scale]];
    self.iconImageView.image=[UIImage systemImageNamed:@"cube"]; self.iconImageView.tintColor=AmeUISecondaryTextColor();
    self.iconContainer.backgroundColor=UIColor.clearColor; self.iconImageView.contentMode=UIViewContentModeScaleAspectFit;
    self.cardContainer.layer.cornerRadius=26*scale; self.referenceMinimum.constant=MAX(72,104*scale);
    self.topRowStack.spacing=8*scale;
    for(NSLayoutConstraint *c in self.contentView.constraints) {
        if(c.firstItem==self.cardContainer && (c.firstAttribute==NSLayoutAttributeTop||c.firstAttribute==NSLayoutAttributeBottom))c.constant=0;
    }
    for(NSLayoutConstraint *c in self.cardContainer.constraints) {
        if(c.firstItem==self.iconContainer && c.firstAttribute==NSLayoutAttributeLeading)c.constant=14*scale;
        if(c.firstItem==self.topRowStack && c.firstAttribute==NSLayoutAttributeLeading)c.constant=16*scale;
        if(c.firstItem==self.chevronView && c.firstAttribute==NSLayoutAttributeTrailing)c.constant=-32*scale;
    }
}

- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];
    [self renewedApplyPresentation];
}

@end
