#import "ios_uikit_bridge.h" // Existing launch/game orientation lock query only.
#import "VersionManagerViewController.h"
// ★ [GLASS-LIQUID] 材质统一走风格层(AmeGlassEffect):iOS≥26 ⇒ 系统 UIGlassEffect
#import "UIKit+GlassSurface.h"
#import "HomeTopNavView.h"
#import "BackgroundManager.h"
#import "PLProfiles.h"
#import "ProfileSettingsViewController.h"
#import "ModsManagerViewController.h"
#import "ShadersManagerViewController.h"
#import "ResourcePacksManagerViewController.h"
#import "DataPacksManagerViewController.h"
#import "WorldsManagerViewController.h"
#import "LauncherPreferences.h"
#import "ScreenUtils.h"
#import "utils.h"
#import "ModLoaderIconHelper.h"
#import "ModpackExportService.h" // for parseVersionId:
#import "AmePerfProbe.h"        // ★ [PERF] 低开销滚动帧率探针（默认关）
#import <QuartzCore/QuartzCore.h>

// Two native sections: game directories and saved profiles (not proof of installed files).
// 重新设计要点（参照 FCL 100%）：
//   1. 版本管理界面只展示：游戏目录切换 + 已安装版本列表
//   2. 渲染器、图形 API、Mod/光影/资源包管理等全部移到"版本专属设置页"（ProfileSettingsViewController）
//      点击版本卡片直接进入该版本的专属设置页，设置只对该版本生效（FCL 风格）
//   3. 完全不调用旧 UI（LauncherPrefGameDirViewController / LauncherProfileEditorViewController）
//   4. 游戏目录卡片支持长按弹出菜单（切换/删除当前目录）
//   5. 统一使用 accentColor() 与毛玻璃背景，适配启动器新 UI
static NSInteger const kSectionGameDir     = 0;
static NSInteger const kSectionVersions    = 1;

static UILabel *VMRenewedLabel(AmeUIFontRole role, UIColor *color) {
    UILabel *label = [[UILabel alloc] init];
    label.font = AmeUIFont(role);
    label.textColor = color;
    label.adjustsFontForContentSizeCategory = YES;
    label.numberOfLines = 0;
    return label;
}

#pragma mark - Modern Tile Base Cell

@interface VMTileBaseCell : UICollectionViewCell
@property (nonatomic, strong) UIView *contentContainer;
- (void)setupViews;
@end

@implementation VMTileBaseCell

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        [self setupViews];
    }
    return self;
}

- (void)setupViews {
    self.layer.shadowColor = UIColor.blackColor.CGColor;
    self.layer.shadowOffset = CGSizeMake(0, 2);
    self.layer.shadowOpacity = 0.06;
    self.layer.shadowRadius = 4;
    self.layer.masksToBounds = NO;
    self.contentContainer = [[UIView alloc] initWithFrame:self.contentView.bounds];
    self.contentContainer.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.contentContainer.layer.cornerRadius = 22;
    self.contentContainer.layer.cornerCurve = kCACornerCurveContinuous;
    self.contentContainer.layer.masksToBounds = YES;
    self.contentView.layer.cornerRadius = 22;
    self.contentView.layer.cornerCurve = kCACornerCurveContinuous;
    self.contentView.layer.masksToBounds = YES;
    self.contentContainer.backgroundColor = UIColor.clearColor;
    self.contentContainer.layer.borderWidth = AmeUIHairlineWidth(self);
    self.contentContainer.layer.borderColor = AmeUIResolvedColor(AmeUIBorderColor(), self).CGColor;
    [self.contentView addSubview:self.contentContainer];
    [[BackgroundManager sharedManager] applyEffectToCollectionViewCell:self];
}

// ★ [PERF] 卡片外阴影必须给【显式 shadowPath】。
//   只设 shadowOffset/Opacity/Radius 而不设 shadowPath 时，CoreAnimation 每帧都要按图层
//   的 alpha 通道现算阴影形状（一次离屏绘制）—— 每个可见卡片都在滚动时重复这笔开销，
//   是典型的滚动掉帧源。这里把阴影形状钉成「与卡片同尺寸同圆角的圆角矩形」，
//   观感不变（阴影本来就是沿圆角卡片外沿投的），但阴影从「每帧现算」变成「一次缓存几何」。
- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat radius = self.contentView.layer.cornerRadius > 0 ? self.contentView.layer.cornerRadius : 12.0;
    self.layer.shadowPath = [UIBezierPath bezierPathWithRoundedRect:self.bounds
                                                      cornerRadius:radius].CGPath;
}

- (void)setHighlighted:(BOOL)highlighted {
    [super setHighlighted:highlighted];
    void (^update)(void) = ^{ self.transform = highlighted ? CGAffineTransformMakeScale(0.985, 0.985) : CGAffineTransformIdentity; };
    if (UIAccessibilityIsReduceMotionEnabled()) update();
    else [UIView animateWithDuration:0.15 delay:0 options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction animations:update completion:nil];
}

- (void)prepareForReuse {
    [super prepareForReuse];
    [self.layer removeAllAnimations];
    self.transform = CGAffineTransformIdentity;
}

@end

#pragma mark - Quick Action Tile Cell

@interface VMQuickActionCell : VMTileBaseCell
@property (nonatomic, strong) UIImageView *iconView;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *subtitleLabel;
@end

@implementation VMQuickActionCell

- (void)setupViews {
    [super setupViews];

    CGFloat iconSize = [ScreenUtils dp:24];
    CGFloat titleFont = [ScreenUtils sp:13];

    self.iconView = [[UIImageView alloc] init];
    self.iconView.translatesAutoresizingMaskIntoConstraints = NO;
    self.iconView.contentMode = UIViewContentModeScaleAspectFit;
    [self.contentContainer addSubview:self.iconView];

    self.titleLabel = [[UILabel alloc] init];
    self.titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.titleLabel.font = [UIFont systemFontOfSize:titleFont weight:UIFontWeightSemibold];
    self.titleLabel.textColor = [UIColor whiteColor];
    self.titleLabel.adjustsFontForContentSizeCategory = NO;
    [self.contentContainer addSubview:self.titleLabel];

    self.subtitleLabel = [[UILabel alloc] init];
    self.subtitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.subtitleLabel.font = [UIFont systemFontOfSize:[ScreenUtils sp:10] weight:UIFontWeightRegular];
    self.subtitleLabel.textColor = [[UIColor whiteColor] colorWithAlphaComponent:0.6];
    self.subtitleLabel.numberOfLines = 0;
    self.subtitleLabel.lineBreakMode = NSLineBreakByWordWrapping;
    self.subtitleLabel.adjustsFontForContentSizeCategory = NO;
    [self.contentContainer addSubview:self.subtitleLabel];

    [NSLayoutConstraint activateConstraints:@[
        [self.iconView.topAnchor constraintEqualToAnchor:self.contentContainer.topAnchor constant:12],
        [self.iconView.leadingAnchor constraintEqualToAnchor:self.contentContainer.leadingAnchor constant:12],
        [self.iconView.widthAnchor constraintEqualToConstant:iconSize],
        [self.iconView.heightAnchor constraintEqualToConstant:iconSize],
        [self.titleLabel.topAnchor constraintEqualToAnchor:self.iconView.bottomAnchor constant:8],
        [self.titleLabel.leadingAnchor constraintEqualToAnchor:self.contentContainer.leadingAnchor constant:12],
        [self.titleLabel.trailingAnchor constraintEqualToAnchor:self.contentContainer.trailingAnchor constant:-12],
        [self.subtitleLabel.topAnchor constraintEqualToAnchor:self.titleLabel.bottomAnchor constant:2],
        [self.subtitleLabel.leadingAnchor constraintEqualToAnchor:self.contentContainer.leadingAnchor constant:12],
        [self.subtitleLabel.trailingAnchor constraintEqualToAnchor:self.contentContainer.trailingAnchor constant:-12],
        [self.subtitleLabel.bottomAnchor constraintLessThanOrEqualToAnchor:self.contentContainer.bottomAnchor constant:-10]
    ]];
}

- (void)configureWithIcon:(NSString *)iconName title:(NSString *)title subtitle:(NSString *)subtitle color:(UIColor *)color {
    self.iconView.image = [UIImage systemImageNamed:iconName];
    self.iconView.tintColor = color;
    self.titleLabel.text = title;
    self.subtitleLabel.text = subtitle;
}

@end

#pragma mark - Version Card Cell

@interface VMVersionCardCell : VMTileBaseCell
@property (nonatomic, strong) UIImageView *iconView;
@property (nonatomic, strong) UILabel *nameLabel;
@property (nonatomic, strong) UILabel *versionLabel;
@property (nonatomic, strong) UILabel *lastPlayedLabel;
@property (nonatomic, strong) UILabel *isolatedBadge;
@property (nonatomic, strong) UIImageView *selectedBadge;
@property (nonatomic, strong) UIButton *moreButton;
@property (nonatomic, copy) void (^onMore)(void);
@property (nonatomic, assign) BOOL profileSelected;
@end

@implementation VMVersionCardCell

- (void)setupViews {
    [super setupViews];
    self.iconView = [[UIImageView alloc] init];
    self.iconView.translatesAutoresizingMaskIntoConstraints = NO;
    self.iconView.contentMode = UIViewContentModeScaleAspectFit;
    [self.contentContainer addSubview:self.iconView];
    self.nameLabel = VMRenewedLabel(AmeUIFontRoleCardTitle, AmeUIPrimaryTextColor());
    self.nameLabel.numberOfLines = 2;
    self.versionLabel = VMRenewedLabel(AmeUIFontRoleDescription, AmeUISecondaryTextColor());
    self.versionLabel.numberOfLines = 2;
    self.lastPlayedLabel = VMRenewedLabel(AmeUIFontRoleStatus, AmeUITertiaryTextColor());
    self.lastPlayedLabel.numberOfLines = 1;
    self.isolatedBadge = VMRenewedLabel(AmeUIFontRoleStatus, AmeUISecondaryTextColor());
    self.isolatedBadge.numberOfLines = 1;
    UIStackView *text = [[UIStackView alloc] initWithArrangedSubviews:@[self.nameLabel, self.versionLabel, self.lastPlayedLabel, self.isolatedBadge]];
    text.axis = UILayoutConstraintAxisVertical;
    text.spacing = 5;
    text.translatesAutoresizingMaskIntoConstraints = NO;
    [self.contentContainer addSubview:text];
    self.selectedBadge = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"checkmark.circle.fill"]];
    self.selectedBadge.translatesAutoresizingMaskIntoConstraints = NO;
    self.selectedBadge.contentMode = UIViewContentModeScaleAspectFit;
    self.selectedBadge.tintColor = AmeUIAccentColor();
    [self.contentContainer addSubview:self.selectedBadge];
    self.moreButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.moreButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.moreButton setImage:[UIImage systemImageNamed:@"ellipsis"] forState:UIControlStateNormal];
    [self.moreButton addTarget:self action:@selector(showProfileActions) forControlEvents:UIControlEventTouchUpInside];
    [self.contentContainer addSubview:self.moreButton];
    [NSLayoutConstraint activateConstraints:@[
        [self.iconView.leadingAnchor constraintEqualToAnchor:self.contentContainer.leadingAnchor constant:16],
        [self.iconView.topAnchor constraintEqualToAnchor:self.contentContainer.topAnchor constant:18],
        [self.iconView.widthAnchor constraintEqualToConstant:28],
        [self.iconView.heightAnchor constraintEqualToConstant:28],
        [text.leadingAnchor constraintEqualToAnchor:self.iconView.trailingAnchor constant:12],
        [text.trailingAnchor constraintEqualToAnchor:self.contentContainer.trailingAnchor constant:-48],
        [text.topAnchor constraintEqualToAnchor:self.contentContainer.topAnchor constant:16],
        [text.bottomAnchor constraintLessThanOrEqualToAnchor:self.contentContainer.bottomAnchor constant:-16],
        [self.selectedBadge.trailingAnchor constraintEqualToAnchor:self.contentContainer.trailingAnchor constant:-16],
        [self.selectedBadge.topAnchor constraintEqualToAnchor:self.contentContainer.topAnchor constant:18],
        [self.selectedBadge.widthAnchor constraintEqualToConstant:20],
        [self.selectedBadge.heightAnchor constraintEqualToConstant:20],
        [self.moreButton.trailingAnchor constraintEqualToAnchor:self.contentContainer.trailingAnchor constant:-4],
        [self.moreButton.bottomAnchor constraintEqualToAnchor:self.contentContainer.bottomAnchor constant:-4],
        [self.moreButton.widthAnchor constraintEqualToConstant:44],
        [self.moreButton.heightAnchor constraintEqualToConstant:44]
    ]];
    self.isAccessibilityElement = YES;
    self.accessibilityHint = localize(@"renewed.instances.edit_hint", @"Opens profile settings. Use Profile actions to select or delete.");
    self.accessibilityCustomActions = @[[[UIAccessibilityCustomAction alloc] initWithName:localize(@"renewed.instances.actions", @"Profile actions") target:self selector:@selector(accessibilityShowProfileActions:)]];
}

- (void)refreshSelectionAppearance {
    self.contentContainer.layer.borderColor = AmeUIResolvedColor(self.profileSelected ? AmeUIAccentColor() : AmeUIBorderColor(), self).CGColor;
    self.contentContainer.layer.borderWidth = self.profileSelected ? 1.5 : AmeUIHairlineWidth(self);
    self.contentContainer.backgroundColor = UIColor.clearColor; // M3 owns the backdrop tint, not text/content alpha.
    self.selectedBadge.tintColor = AmeUIAccentColor();
    self.moreButton.tintColor = AmeUIPrimaryTextColor();
}

- (void)configureWithName:(NSString *)name version:(NSString *)version isSelected:(BOOL)isSelected isolated:(BOOL)isolated lastPlayed:(NSString *)lastPlayed {
    self.nameLabel.text = name;
    self.versionLabel.text = version ?: localize(@"i18n_str_1052", nil);
    self.lastPlayedLabel.text = lastPlayed ?: @"";
    self.lastPlayedLabel.hidden = self.lastPlayedLabel.text.length == 0;
    self.isolatedBadge.text = localize(@"i18n_str_2026", nil);
    self.isolatedBadge.hidden = !isolated;
    self.profileSelected = isSelected;
    self.selectedBadge.hidden = !isSelected;
    // Saved profile metadata is not proof that game files or a compatible runtime are installed.
    NSString *loader = [ModLoaderIconHelper detectLoaderFromVersionId:version];
    self.iconView.image = nil;
    self.iconView.tintColor = AmeUISecondaryTextColor();
    if (loader) [ModLoaderIconHelper configureImageView:self.iconView forLoader:loader traitCollection:self.traitCollection];
    else self.iconView.image = [UIImage systemImageNamed:@"cube.box"];
    self.moreButton.accessibilityLabel = [NSString stringWithFormat:@"%@: %@", localize(@"renewed.instances.actions", @"Profile actions"), name];
    self.accessibilityLabel = [NSString stringWithFormat:@"%@, %@%@%@", name, self.versionLabel.text,
        lastPlayed.length ? [@", " stringByAppendingString:lastPlayed] : @"",
        isolated ? [@", " stringByAppendingString:self.isolatedBadge.text] : @""];
    self.accessibilityTraits = UIAccessibilityTraitButton | (isSelected ? UIAccessibilityTraitSelected : 0);
    [self refreshSelectionAppearance];
}

- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];
    [self refreshSelectionAppearance];
}

- (void)showProfileActions { if (self.onMore) self.onMore(); }
- (BOOL)accessibilityShowProfileActions:(UIAccessibilityCustomAction *)action {
    if (!self.onMore) return NO;
    self.onMore();
    return YES;
}

- (void)prepareForReuse {
    [super prepareForReuse];
    self.onMore = nil;
    self.profileSelected = NO;
    self.selectedBadge.hidden = YES;
    self.iconView.image = nil;
    self.accessibilityLabel = nil;
    self.accessibilityTraits = UIAccessibilityTraitButton;
    [self refreshSelectionAppearance];
}
@end

#pragma mark - Game Directory Cell (FCL 风格版本隔离卡片)

@interface VMGameDirCell : VMTileBaseCell
@property (nonatomic, strong) UIView *iconContainer;
@property (nonatomic, strong) UIImageView *iconView;
@property (nonatomic, strong) UILabel *nameLabel;
@property (nonatomic, strong) UILabel *detailLabel;
@property (nonatomic, strong) UIView *selectedBadge;
@property (nonatomic, strong) UIImageView *chevronView;
@property (nonatomic, assign) BOOL directorySelected;

@end

@implementation VMGameDirCell

- (void)setupViews {
    [super setupViews];

    CGFloat iconBoxSize = [ScreenUtils dp:28];
    CGFloat iconSize = [ScreenUtils dp:16];

    // 规范 8.2：图标容器
    self.iconContainer = [[UIView alloc] init];
    self.iconContainer.translatesAutoresizingMaskIntoConstraints = NO;
    self.iconContainer.layer.cornerRadius = 8;
    self.iconContainer.layer.cornerCurve = kCACornerCurveContinuous;
    self.iconContainer.backgroundColor = [UIColor systemBlueColor];
    [self.contentContainer addSubview:self.iconContainer];

    self.iconView = [[UIImageView alloc] init];
    self.iconView.translatesAutoresizingMaskIntoConstraints = NO;
    self.iconView.contentMode = UIViewContentModeScaleAspectFit;
    self.iconView.image = [UIImage systemImageNamed:@"folder.fill"];
    self.iconView.tintColor = [UIColor whiteColor];
    [self.iconContainer addSubview:self.iconView];

    self.nameLabel = [[UILabel alloc] init];
    self.nameLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.nameLabel.font = AmeUIFont(AmeUIFontRoleBody);
    // 规范 2.1：系统色
    self.nameLabel.textColor = [UIColor labelColor];
    self.nameLabel.numberOfLines = 2;
    self.nameLabel.adjustsFontForContentSizeCategory = YES;
    [self.contentContainer addSubview:self.nameLabel];

    self.detailLabel = [[UILabel alloc] init];
    self.detailLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.detailLabel.font = AmeUIFont(AmeUIFontRoleStatus);
    // 规范 2.1：副文字 secondaryLabelColor
    self.detailLabel.textColor = [UIColor secondaryLabelColor];
    self.detailLabel.numberOfLines = 2;
    self.detailLabel.lineBreakMode = NSLineBreakByWordWrapping;
    self.detailLabel.adjustsFontForContentSizeCategory = YES;
    [self.contentContainer addSubview:self.detailLabel];

    self.selectedBadge = [[UIView alloc] init];
    self.selectedBadge.translatesAutoresizingMaskIntoConstraints = NO;
    self.selectedBadge.backgroundColor = accentColor();
    self.selectedBadge.layer.cornerRadius = 9;
    self.selectedBadge.layer.cornerCurve = kCACornerCurveContinuous;
    self.selectedBadge.hidden = YES;
    [self.contentContainer addSubview:self.selectedBadge];

    UIImageView *checkmark = [[UIImageView alloc] init];
    checkmark.translatesAutoresizingMaskIntoConstraints = NO;
    checkmark.image = [UIImage systemImageNamed:@"checkmark" withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:8 weight:UIFontWeightBold]];
    checkmark.tintColor = [UIColor whiteColor];
    [self.selectedBadge addSubview:checkmark];

    // 规范 9.4：chevron 暗示可点击
    self.chevronView = [[UIImageView alloc] init];
    self.chevronView.translatesAutoresizingMaskIntoConstraints = NO;
    self.chevronView.image = [UIImage systemImageNamed:@"chevron.right" withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:11 weight:UIFontWeightSemibold]];
    self.chevronView.tintColor = [UIColor tertiaryLabelColor];
    [self.contentContainer addSubview:self.chevronView];

    [NSLayoutConstraint activateConstraints:@[
        [self.iconContainer.leadingAnchor constraintEqualToAnchor:self.contentContainer.leadingAnchor constant:10],
        [self.iconContainer.centerYAnchor constraintEqualToAnchor:self.contentContainer.centerYAnchor],
        [self.iconContainer.widthAnchor constraintEqualToConstant:iconBoxSize],
        [self.iconContainer.heightAnchor constraintEqualToConstant:iconBoxSize],
        [self.iconView.centerXAnchor constraintEqualToAnchor:self.iconContainer.centerXAnchor],
        [self.iconView.centerYAnchor constraintEqualToAnchor:self.iconContainer.centerYAnchor],
        [self.iconView.widthAnchor constraintEqualToConstant:iconSize],
        [self.iconView.heightAnchor constraintEqualToConstant:iconSize],
        [self.nameLabel.leadingAnchor constraintEqualToAnchor:self.iconContainer.trailingAnchor constant:8],
        [self.nameLabel.topAnchor constraintEqualToAnchor:self.contentContainer.topAnchor constant:8],
        [self.nameLabel.trailingAnchor constraintEqualToAnchor:self.chevronView.leadingAnchor constant:-6],
        [self.detailLabel.leadingAnchor constraintEqualToAnchor:self.nameLabel.leadingAnchor],
        [self.detailLabel.topAnchor constraintEqualToAnchor:self.nameLabel.bottomAnchor constant:2],
        [self.detailLabel.trailingAnchor constraintEqualToAnchor:self.chevronView.leadingAnchor constant:-6],
        [self.detailLabel.bottomAnchor constraintLessThanOrEqualToAnchor:self.contentContainer.bottomAnchor constant:-8],
        [self.selectedBadge.trailingAnchor constraintEqualToAnchor:self.contentContainer.trailingAnchor constant:-10],
        [self.selectedBadge.topAnchor constraintEqualToAnchor:self.contentContainer.topAnchor constant:8],
        [self.selectedBadge.widthAnchor constraintEqualToConstant:18],
        [self.selectedBadge.heightAnchor constraintEqualToConstant:18],
        [self.chevronView.trailingAnchor constraintEqualToAnchor:self.contentContainer.trailingAnchor constant:-10],
        [self.chevronView.centerYAnchor constraintEqualToAnchor:self.contentContainer.centerYAnchor],
        [self.chevronView.widthAnchor constraintEqualToConstant:11],
        [self.chevronView.heightAnchor constraintEqualToConstant:11],
        [checkmark.centerXAnchor constraintEqualToAnchor:self.selectedBadge.centerXAnchor],
        [checkmark.centerYAnchor constraintEqualToAnchor:self.selectedBadge.centerYAnchor]
    ]];
}

- (void)configureWithName:(NSString *)name detail:(NSString *)detail isSelected:(BOOL)isSelected isAddButton:(BOOL)isAddButton {
    self.directorySelected = isSelected && !isAddButton;
    if (isAddButton) {
        self.iconView.image = [UIImage systemImageNamed:@"plus"];
        self.iconView.tintColor = [UIColor whiteColor];
        self.iconContainer.backgroundColor = [UIColor systemGreenColor];
        self.nameLabel.text = localize(@"i18n_str_1053", nil);
        self.detailLabel.text = localize(@"i18n_str_1054", nil);
        self.selectedBadge.hidden = YES;
        self.chevronView.hidden = YES;
        // 规范 5.3：推荐态描边 1.0pt accentColor 0.4
        self.contentContainer.layer.borderColor = AmeUIResolvedColor(AmeUIBorderColor(), self).CGColor;
        self.contentContainer.layer.borderWidth = 1.0;
        self.contentContainer.backgroundColor = UIColor.clearColor;
        self.isAccessibilityElement = YES;
        self.accessibilityHint = nil;
        self.accessibilityLabel = self.nameLabel.text;
        self.accessibilityTraits = UIAccessibilityTraitButton;
        return;
    }

    self.isAccessibilityElement = YES;
    self.accessibilityHint = localize(@"renewed.instances.directory_hint", @"Selects this directory. Touch and hold for directory actions.");
    self.accessibilityLabel = name;
    self.accessibilityTraits = UIAccessibilityTraitButton | (isSelected ? UIAccessibilityTraitSelected : 0);
    self.chevronView.hidden = NO;
    self.iconView.image = [UIImage systemImageNamed:@"folder.fill"];
    self.iconView.tintColor = [UIColor whiteColor];
    self.iconContainer.backgroundColor = [UIColor systemBlueColor];
    self.nameLabel.text = name;
    self.detailLabel.text = detail ?: @"";
    self.selectedBadge.hidden = !isSelected;
    self.selectedBadge.backgroundColor = accentColor();

    // 规范 9.1：选中态三层强化
    if (isSelected) {
        self.contentContainer.layer.borderColor = AmeUIResolvedColor(AmeUIAccentColor(), self).CGColor;
        self.contentContainer.layer.borderWidth = 1.5;
        self.contentContainer.backgroundColor = UIColor.clearColor;
        self.chevronView.tintColor = accentColor();
    } else {
        self.contentContainer.layer.borderColor = AmeUIResolvedColor(AmeUIBorderColor(), self).CGColor;
        self.contentContainer.layer.borderWidth = AmeUIHairlineWidth(self);
        self.contentContainer.backgroundColor = UIColor.clearColor;
        self.chevronView.tintColor = [UIColor tertiaryLabelColor];
    }
}

- (NSString *)accessibilityValue { return self.detailLabel.text; }

- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];
    self.contentContainer.layer.borderColor = AmeUIResolvedColor(self.directorySelected ? AmeUIAccentColor() : AmeUIBorderColor(), self).CGColor;
}
@end

#pragma mark - Renderer Card Cell (图形 API 选择卡片，FCL 风格)

@interface VMRendererCell : VMTileBaseCell
@property (nonatomic, strong) UIImageView *iconView;
@property (nonatomic, strong) UILabel *nameLabel;
@property (nonatomic, strong) UILabel *descLabel;
@property (nonatomic, strong) UIView *selectedBadge;
@end

@implementation VMRendererCell

- (void)setupViews {
    [super setupViews];

    CGFloat iconSize = [ScreenUtils dp:22];

    self.iconView = [[UIImageView alloc] init];
    self.iconView.translatesAutoresizingMaskIntoConstraints = NO;
    self.iconView.contentMode = UIViewContentModeScaleAspectFit;
    [self.contentContainer addSubview:self.iconView];

    self.nameLabel = [[UILabel alloc] init];
    self.nameLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.nameLabel.font = [UIFont systemFontOfSize:[ScreenUtils sp:13] weight:UIFontWeightSemibold];
    self.nameLabel.textColor = [UIColor whiteColor];
    self.nameLabel.numberOfLines = 1;
    self.nameLabel.adjustsFontForContentSizeCategory = NO;
    [self.contentContainer addSubview:self.nameLabel];

    self.descLabel = [[UILabel alloc] init];
    self.descLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.descLabel.font = [UIFont systemFontOfSize:[ScreenUtils sp:10] weight:UIFontWeightRegular];
    self.descLabel.textColor = [[UIColor whiteColor] colorWithAlphaComponent:0.55];
    self.descLabel.numberOfLines = 2;
    self.descLabel.lineBreakMode = NSLineBreakByWordWrapping;
    self.descLabel.adjustsFontForContentSizeCategory = NO;
    [self.contentContainer addSubview:self.descLabel];

    self.selectedBadge = [[UIView alloc] init];
    self.selectedBadge.translatesAutoresizingMaskIntoConstraints = NO;
    self.selectedBadge.backgroundColor = accentColor();
    self.selectedBadge.layer.cornerRadius = 8;
    self.selectedBadge.hidden = YES;
    [self.contentContainer addSubview:self.selectedBadge];

    UIImageView *checkmark = [[UIImageView alloc] init];
    checkmark.translatesAutoresizingMaskIntoConstraints = NO;
    checkmark.image = [UIImage systemImageNamed:@"checkmark" withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:8 weight:UIFontWeightBold]];
    checkmark.tintColor = [UIColor whiteColor];
    [self.selectedBadge addSubview:checkmark];

    [NSLayoutConstraint activateConstraints:@[
        [self.iconView.topAnchor constraintEqualToAnchor:self.contentContainer.topAnchor constant:10],
        [self.iconView.leadingAnchor constraintEqualToAnchor:self.contentContainer.leadingAnchor constant:10],
        [self.iconView.widthAnchor constraintEqualToConstant:iconSize],
        [self.iconView.heightAnchor constraintEqualToConstant:iconSize],
        [self.nameLabel.topAnchor constraintEqualToAnchor:self.iconView.bottomAnchor constant:6],
        [self.nameLabel.leadingAnchor constraintEqualToAnchor:self.contentContainer.leadingAnchor constant:10],
        [self.nameLabel.trailingAnchor constraintEqualToAnchor:self.contentContainer.trailingAnchor constant:-10],
        [self.descLabel.topAnchor constraintEqualToAnchor:self.nameLabel.bottomAnchor constant:2],
        [self.descLabel.leadingAnchor constraintEqualToAnchor:self.contentContainer.leadingAnchor constant:10],
        [self.descLabel.trailingAnchor constraintEqualToAnchor:self.contentContainer.trailingAnchor constant:-10],
        [self.descLabel.bottomAnchor constraintLessThanOrEqualToAnchor:self.contentContainer.bottomAnchor constant:-8],
        [self.selectedBadge.topAnchor constraintEqualToAnchor:self.contentContainer.topAnchor constant:8],
        [self.selectedBadge.trailingAnchor constraintEqualToAnchor:self.contentContainer.trailingAnchor constant:-8],
        [self.selectedBadge.widthAnchor constraintEqualToConstant:16],
        [self.selectedBadge.heightAnchor constraintEqualToConstant:16],
        [checkmark.centerXAnchor constraintEqualToAnchor:self.selectedBadge.centerXAnchor],
        [checkmark.centerYAnchor constraintEqualToAnchor:self.selectedBadge.centerYAnchor]
    ]];
}

- (void)configureWithIcon:(NSString *)iconName
                     name:(NSString *)name
                  details:(NSString *)details
              isSelected:(BOOL)isSelected
                  isBest:(BOOL)isBest {
    self.iconView.image = [UIImage systemImageNamed:iconName];
    self.iconView.tintColor = isBest ? accentColor() : [UIColor systemGrayColor];
    self.nameLabel.text = name;
    self.descLabel.text = details;
    self.selectedBadge.hidden = !isSelected;
    self.selectedBadge.backgroundColor = accentColor();

    if (isSelected) {
        self.contentView.layer.borderColor = accentColor().CGColor;
        self.contentView.layer.borderWidth = 1.5;
    } else if (isBest) {
        self.contentView.layer.borderColor = [[accentColor() colorWithAlphaComponent:0.4] CGColor];
        self.contentView.layer.borderWidth = 1.0;
    } else {
        self.contentView.layer.borderColor = [[UIColor whiteColor] colorWithAlphaComponent:0.12].CGColor;
        self.contentView.layer.borderWidth = 0.5;
    }
    self.contentView.layer.cornerRadius = 12;
    self.contentView.layer.masksToBounds = YES;
}

@end

#pragma mark - Header View

@interface VMSectionHeaderView : UICollectionReusableView
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *subtitleLabel;
@property (nonatomic, strong) UILabel *countBadge;
- (void)configureWithIcon:(NSString *)iconName title:(NSString *)title subtitle:(NSString *)subtitle count:(NSInteger)count;
@end

@implementation VMSectionHeaderView
- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.titleLabel = VMRenewedLabel(AmeUIFontRoleSectionHeading, AmeUIPrimaryTextColor());
        self.titleLabel.accessibilityTraits = UIAccessibilityTraitHeader;
        self.subtitleLabel = VMRenewedLabel(AmeUIFontRoleDescription, AmeUISecondaryTextColor());
        self.countBadge = VMRenewedLabel(AmeUIFontRoleStatus, AmeUISecondaryTextColor());
        [self.countBadge setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
        UIStackView *row = [[UIStackView alloc] initWithArrangedSubviews:@[self.titleLabel, self.countBadge]];
        row.spacing = 12;
        row.alignment = UIStackViewAlignmentFirstBaseline;
        UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[row, self.subtitleLabel]];
        stack.axis = UILayoutConstraintAxisVertical;
        stack.spacing = 6;
        stack.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:stack];
        [NSLayoutConstraint activateConstraints:@[
            [stack.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
            [stack.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
            [stack.topAnchor constraintEqualToAnchor:self.topAnchor constant:12],
            [stack.bottomAnchor constraintEqualToAnchor:self.bottomAnchor constant:-16]
        ]];
    }
    return self;
}
- (void)configureWithIcon:(NSString *)iconName title:(NSString *)title subtitle:(NSString *)subtitle count:(NSInteger)count {
    self.titleLabel.text = title;
    self.subtitleLabel.text = subtitle;
    self.subtitleLabel.hidden = subtitle.length == 0;
    self.countBadge.text = count < 0 ? @"" : [NSString stringWithFormat:@"%ld", (long)count];
    self.countBadge.hidden = count < 0;
}
@end

static NSString * const VMOverviewKind = @"VMInstancesOverview";

@interface VMOverviewHeader : UICollectionReusableView
@property (nonatomic, strong) UILabel *overviewSubtitle;
@property (nonatomic, strong) UIStackView *overviewStack;
@property (nonatomic, copy) void (^onCreate)(void);
- (void)configureCount:(NSUInteger)count;
@end

@implementation VMOverviewHeader
- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        UILabel *title = VMRenewedLabel(AmeUIFontRoleScreenTitle, AmeUIPrimaryTextColor());
        title.text = localize(@"tab.instances", @"Instances");
        title.accessibilityTraits = UIAccessibilityTraitHeader;
        self.overviewSubtitle = VMRenewedLabel(AmeUIFontRoleDescription, AmeUISecondaryTextColor());
        UIStackView *text = [[UIStackView alloc] initWithArrangedSubviews:@[title, self.overviewSubtitle]];
        text.axis = UILayoutConstraintAxisVertical;
        text.spacing = 4;
        AmePinkGlassButton *create = [AmePinkGlassButton buttonWithType:UIButtonTypeSystem];
        create.ameRole = AmeGlassButtonRoleSecondary;
        [create setTitle:localize(@"renewed.instances.new", @"New instance") forState:UIControlStateNormal];
        [create setImage:[UIImage systemImageNamed:@"plus"] forState:UIControlStateNormal];
        create.contentEdgeInsets = UIEdgeInsetsMake(10, 16, 10, 16);
        [create.heightAnchor constraintGreaterThanOrEqualToConstant:44].active = YES;
        [create addTarget:self action:@selector(createTapped) forControlEvents:UIControlEventTouchUpInside];
        self.overviewStack = [[UIStackView alloc] initWithArrangedSubviews:@[text, create]];
        self.overviewStack.spacing = 12;
        self.overviewStack.alignment = UIStackViewAlignmentCenter;
        self.overviewStack.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:self.overviewStack];
        [NSLayoutConstraint activateConstraints:@[
            [self.overviewStack.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:16],
            [self.overviewStack.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-16],
            [self.overviewStack.topAnchor constraintEqualToAnchor:self.topAnchor constant:12],
            [self.overviewStack.bottomAnchor constraintEqualToAnchor:self.bottomAnchor constant:-16]
        ]];
    }
    return self;
}
- (void)createTapped { if (self.onCreate) self.onCreate(); }
- (void)configureCount:(NSUInteger)count {
    self.overviewSubtitle.text = [NSString stringWithFormat:localize(@"renewed.instances.count", @"%lu saved profiles · Select a card to edit"), (unsigned long)count];
}
- (void)configureWidth:(CGFloat)width {
    BOOL stack = width < 600 || UIContentSizeCategoryIsAccessibilityCategory(self.traitCollection.preferredContentSizeCategory);
    self.overviewStack.axis = stack ? UILayoutConstraintAxisVertical : UILayoutConstraintAxisHorizontal;
    self.overviewStack.alignment = stack ? UIStackViewAlignmentFill : UIStackViewAlignmentCenter;
}
- (UICollectionViewLayoutAttributes *)preferredLayoutAttributesFittingAttributes:(UICollectionViewLayoutAttributes *)attributes {
    UICollectionViewLayoutAttributes *result = [attributes copy];
    if (attributes.size.width <= 0) return result;
    [self configureWidth:attributes.size.width];
    CGSize size = [self systemLayoutSizeFittingSize:CGSizeMake(attributes.size.width, UILayoutFittingCompressedSize.height)
        withHorizontalFittingPriority:UILayoutPriorityRequired verticalFittingPriority:UILayoutPriorityFittingSizeLevel];
    result.size = CGSizeMake(attributes.size.width, MAX(1, ceil(size.height)));
    return result;
}
- (void)layoutSubviews { [super layoutSubviews]; [self configureWidth:self.bounds.size.width]; }
- (void)prepareForReuse { [super prepareForReuse]; self.onCreate = nil; }
@end

#pragma mark - View Controller

@interface VersionManagerViewController () <UICollectionViewDataSource, UICollectionViewDelegate, UITextFieldDelegate>
@property (nonatomic, strong) UICollectionView *collectionView;
@property (nonatomic, strong) NSArray<NSString *> *profileList;
@property (nonatomic, strong) NSString *selectedProfile;
@property (nonatomic, strong) NSMutableArray<NSString *> *gameDirList;
@property (nonatomic, strong) NSString *currentGameDir;
// Weak visible overview; profiles remain owned by PLProfiles.
@property (nonatomic, weak) VMOverviewHeader *overviewHeader;
// 渲染器 section 数据（启动器 native 渲染器库选择，LWJGL 层）
@property (nonatomic, strong) NSArray<NSString *> *rendererKeys;
@property (nonatomic, strong) NSArray<NSString *> *rendererNames;
@property (nonatomic, strong) NSArray<NSString *> *rendererIcons;
@property (nonatomic, strong) NSArray<NSString *> *rendererDescs;
// 图形 API section 数据（MC 26.2+ 游戏内 OpenGL/Vulkan 切换，游戏层）
@property (nonatomic, strong) NSArray<NSString *> *graphicsApiKeys;
@property (nonatomic, strong) NSArray<NSString *> *graphicsApiNames;
@property (nonatomic, strong) NSArray<NSString *> *graphicsApiIcons;
@property (nonatomic, strong) NSArray<NSString *> *graphicsApiDescs;
// ★ [PERF] 版本隔离判定结果缓存：判定里含【磁盘嗅探】(fileExistsAtPath + contentsOfDirectoryAtPath)，
//   原先在 cellForItemAtIndexPath 里逐卡实时算 ⇒ 每次卡片出队 = 主线程文件 I/O（滚动卡顿主因）。
//   现在只在数据加载时（loadProfiles，见 viewDidLoad / 切目录 / ReloadProfileList）算一次，
//   滚动期间只查表。判定结果与观感完全不变，只是不再每帧重算。
@property (nonatomic, strong) NSDictionary<NSString *, NSNumber *> *isolationByProfile;
// ★ [PERF] 实例目录大小缓存 + 在算集合：算大小是【递归遍历整个实例目录】的重活，
//   原先每次 VMGameDirCell 出队都重新跑一遍（横向滚动 = 每秒几十次全量磁盘遍历）。
//   现在按目录名缓存，同一目录只算一次；方向键在 loadGameDirList 时整体失效。
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSNumber *> *gameDirSizeCache;
@property (nonatomic, strong) NSMutableSet<NSString *> *gameDirSizeInFlight;
@end

@implementation VersionManagerViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    // 不设置 self.title，避免顶部导航栏出现"版本管理"标题黑条（参照 FCL 无 title 风格）
    self.view.backgroundColor = [UIColor clearColor];
    // 彻底隐藏导航栏黑条（仅当作为非 modal 根页面且是栈中唯一 VC 时）
    // 快捷入口（showModsManager 等）会预 push 子页面，此时 count > 1，不隐藏导航栏
    if (self.navigationController &&
        self.navigationController.viewControllers.firstObject == self &&
        self.navigationController.presentingViewController == nil &&
        self.navigationController.viewControllers.count == 1) {
        self.navigationController.navigationBarHidden = YES;
    }
    if (self.navigationController) {
        [[BackgroundManager sharedManager] applyEffectToNavigationBar:self.navigationController.navigationBar];
    }
    [[BackgroundManager sharedManager] makeViewControllerTransparent:self];
    [self setupRendererData];
    [self setupGraphicsApiData];
    [self setupCollectionView];
    [self setupLongPressGesture];
    [self loadProfiles];
    [self loadGameDirList];
    [self updateEmptyState];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(profileChanged)
                                                 name:@"SelectedProfileChanged"
                                               object:nil];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(profileChanged)
                                                 name:@"ReloadProfileList"
                                               object:nil];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(handleAccentColorChanged)
                                                 name:@"LauncherAppearanceChanged"
                                               object:nil];
}

- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];
    if (![previousTraitCollection.preferredContentSizeCategory isEqualToString:self.traitCollection.preferredContentSizeCategory]) {
        [self.collectionView.collectionViewLayout invalidateLayout];
        [self.view setNeedsLayout];
    }
}

- (void)setupLongPressGesture {
    UILongPressGestureRecognizer *longPress = [[UILongPressGestureRecognizer alloc]
        initWithTarget:self action:@selector(handleLongPress:)];
    longPress.minimumPressDuration = 0.5;
    [self.collectionView addGestureRecognizer:longPress];
}

- (void)createNewVersion {
    // ★ [TABFIX] 旧行为:发 ShowDownloadPage 通知,让 LauncherRootViewController 换自己的内容。
    //   但本页现在是【独立标签】,那个通知是在用户看不见的主页里换内容 ——
    //   表现就是「点 + 没反应」+「切回主页发现变成实例下载页」(用户实测)。
    //   正解:直接切到"下载"标签(它本来就是 DownloadViewController)。
    UITabBarController *tbc = self.tabBarController;
    if (tbc) {
        NSLog(@"[TABFIX] '+' ⇒ 切到下载标签(index 1)");
        tbc.selectedIndex = AMELauncherTabDownloads;
    } else {
        // 兜底:不在标签栏里(老流程)时保持原行为
        [[NSNotificationCenter defaultCenter] postNotificationName:@"ShowDownloadPage" object:nil];
    }
}

#pragma mark - Empty State

/// Empty guidance lives in the profile section without hiding game directories.
- (void)updateEmptyState {
    // Keep directories and their New action reachable even with zero saved profiles.
    [self.overviewHeader configureCount:self.profileList.count];
}

- (void)handleLongPress:(UILongPressGestureRecognizer *)gesture {
    if (gesture.state != UIGestureRecognizerStateBegan || self.presentedViewController || self.navigationController.transitionCoordinator) return;
    CGPoint point = [gesture locationInView:self.collectionView];
    NSIndexPath *indexPath = [self.collectionView indexPathForItemAtPoint:point];
    if (!indexPath) return;

    if (indexPath.section == kSectionGameDir) {
        // 游戏目录区段：长按弹出切换/删除菜单（不含"新建目录"按钮项）
        if (indexPath.item >= (NSInteger)self.gameDirList.count) return;
        NSString *dirName = self.gameDirList[indexPath.item];
        [self showGameDirActions:dirName];
    } else if (indexPath.section == kSectionVersions) {
        // 版本卡片区段：长按弹出操作菜单（选择/删除）
        if (indexPath.item >= (NSInteger)self.profileList.count) return;
        [self showProfileActions:self.profileList[indexPath.item]];
    }
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    // 重新隐藏导航栏黑条（pop 回根页面时 topViewController == self）
    if (self.navigationController &&
        self.navigationController.viewControllers.firstObject == self &&
        self.navigationController.presentingViewController == nil &&
        self.navigationController.topViewController == self) {
        self.navigationController.navigationBarHidden = YES;
    }
    [PLProfiles updateCurrent];
    [self loadProfiles];
    [self loadGameDirList];
    [self.collectionView reloadData];
    [self updateEmptyState];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    // push 子页面时显示导航栏（子页面需要返回按钮）
    if (self.navigationController &&
        self.navigationController.viewControllers.firstObject == self &&
        self.navigationController.presentingViewController == nil) {
        self.navigationController.navigationBarHidden = NO;
    }
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)profileChanged {
    [PLProfiles updateCurrent];
    [self loadProfiles];
    [self loadGameDirList];
    [self.collectionView reloadData];
    [self updateEmptyState];
}

- (void)handleAccentColorChanged {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.collectionView reloadData];
        [self updateEmptyState];
    });
}

#pragma mark - Renderer Data Setup

/// 初始化渲染器选项数据（启动器 native 渲染器库选择，LWJGL 层）
/// 参照 FCL/HMCL 的渲染器选择面板，提供 7 个选项及对应描述
/// 注意：名称使用简短标识，不使用 getRendererNames 返回的长本地化字符串
- (void)setupRendererData {
    self.rendererKeys = getRendererKeys(NO);
    // 简短渲染器名称（不使用 getRendererNames 的长本地化字符串）
    // 顺序必须与 getRendererKeys() 完全一致（索引配对）
    self.rendererNames = @[
        @"Auto",
        @"GL4ES",
        @"ANGLE",
        @"MobileGlues",
        @"Zink",
        @"LTW",
        @"MoltenVK"
    ];
    self.rendererIcons = @[
        @"wand.and.stars",
        @"cpu",
        @"rectangle.stack.fill",
        @"bolt.fill",
        @"circle.hexagongrid.fill",
        @"square.stack.3d.up.fill",
        @"flame.fill"
    ];
    self.rendererDescs = @[
        localize(@"i18n_str_1059", nil),
        localize(@"i18n_str_1060", nil),
        localize(@"i18n_str_1061", nil),
        localize(@"i18n_str_1062", nil),
        localize(@"i18n_str_1063", nil),
        localize(@"i18n_str_1064", nil),
        localize(@"i18n_str_1065", nil)
    ];
}

#pragma mark - Graphics API Data Setup (MC 26.2+)

/// 初始化图形 API 选项数据（MC 26.2+ 游戏内 OpenGL/Vulkan 切换，游戏层）
///
/// Mojang 在 MC 26.2 Snapshot 1 引入了 "Graphics API" 视频设置项，有 3 个值：
///   - default        由 Mojang 决定（snapshot-1~7 为 Vulkan，snapshot-8+ 为 OpenGL）
///   - prefer_vulkan  优先使用 Vulkan，失败时回退 OpenGL
///   - prefer_opengl  优先使用 OpenGL，失败时回退 Vulkan
///
/// 注意：与渲染器（renderer）是两个不同维度
- (void)setupGraphicsApiData {
    self.graphicsApiKeys = @[@"default", @"prefer_metal", @"prefer_vulkan", @"prefer_opengl"];
    self.graphicsApiNames = @[localize(@"i18n_str_943", nil), @"Metal (pure)", localize(@"i18n_str_941", nil), localize(@"i18n_str_942", nil)];
    self.graphicsApiIcons = @[
        @"wand.and.stars",
        @"bolt.fill",
        @"flame.fill",
        @"rectangle.stack.fill"
    ];
    self.graphicsApiDescs = @[
        localize(@"i18n_str_1066", nil),
        @"Pure Metal backend (com.metallum) without translation layers",
        localize(@"i18n_str_1067", nil),
        localize(@"i18n_str_1068", nil)
    ];
}

/// 判断当前选中 profile 的版本是否为 MC 26.2+（即 1.21.8+ 后的新版本号方案）
/// 26.x 系列 = 1.21.8 起的快照/正式版采用的新版本号格式
- (BOOL)isCurrentProfileModernVersion {
    if (!self.selectedProfile) return NO;
    NSDictionary *profile = PLProfiles.current.profiles[self.selectedProfile];
    NSString *versionId = profile[@"lastVersionId"];
    if (!versionId) return NO;
    // 修复 Fabric/Quilt/Forge loader profile 的版本号识别：
    //   原实现用 digits 字符集截取 prefix，但 fabric-loader-0.16.0-26.2 的第 0 个
    //   字符 'f' 不是数字，prefix 截成空字符串，导致 MC 26.2+ Fabric profile
    //   看不到"图形 API"选项。
    //   修复：先用 ModpackExportService.parseVersionId 提取 minecraft 版本号，
    //   再用提取后的版本号判断。也支持 forge/neoforge 形如 "26.2-forge-..."。
    NSDictionary *parsed = [ModpackExportService parseVersionId:versionId];
    NSString *mcVersion = parsed[@"minecraft"] ?: versionId;
    // 26.x 系列
    if ([mcVersion hasPrefix:@"26."]) return YES;
    if ([mcVersion hasPrefix:@"26w"]) return YES;
    // 1.21.8 及以上
    if ([mcVersion hasPrefix:@"1.21."]) {
        NSString *minorStr = [mcVersion substringFromIndex:5];
        NSInteger minor = [minorStr integerValue];
        if (minor >= 8) return YES;
    }
    return NO;
}

/// 获取当前选中 profile 的渲染器（如未设置则回退到全局偏好）
- (NSString *)currentRendererForSelectedProfile {
    if (!self.selectedProfile) return @"auto";
    NSDictionary *profile = PLProfiles.current.profiles[self.selectedProfile];
    NSString *r = profile[@"renderer"];
    if (r.length == 0) {
        r = getPrefObject(@"video.renderer");
    }
    return r.length > 0 ? r : @"auto";
}

/// 获取当前选中 profile 的图形 API（MC 26.2+，如未设置则回退到全局偏好，再回退到 default）
- (NSString *)currentGraphicsApiForSelectedProfile {
    if (!self.selectedProfile) return @"default";
    NSDictionary *profile = PLProfiles.current.profiles[self.selectedProfile];
    NSString *g = profile[@"graphicsApi"];
    if (g.length == 0) {
        g = getPrefObject(@"video.graphics_api");
    }
    return g.length > 0 ? g : @"default";
}

#pragma mark - Setup

- (void)setupCollectionView {
    self.collectionView = [[UICollectionView alloc] initWithFrame:CGRectZero collectionViewLayout:[self createLayout]];
    self.collectionView.translatesAutoresizingMaskIntoConstraints = NO;
    self.collectionView.backgroundColor = UIColor.clearColor;
    self.collectionView.dataSource = self;
    self.collectionView.delegate = self;
    self.collectionView.alwaysBounceVertical = YES;
    self.collectionView.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;
    self.collectionView.contentInset = UIEdgeInsetsMake(0, 0, 24, 0);

    [self.collectionView registerClass:[VMGameDirCell class] forCellWithReuseIdentifier:@"GameDirCell"];
    [self.collectionView registerClass:[VMVersionCardCell class] forCellWithReuseIdentifier:@"VersionCell"];
    [self.collectionView registerClass:[VMSectionHeaderView class] forSupplementaryViewOfKind:UICollectionElementKindSectionHeader withReuseIdentifier:@"HeaderView"];

    [self.collectionView registerClass:VMOverviewHeader.class forSupplementaryViewOfKind:VMOverviewKind withReuseIdentifier:VMOverviewKind];
    [self.view addSubview:self.collectionView];
    UILayoutGuide *safe = self.view.safeAreaLayoutGuide;
    // The root's 76-point reservation remains authoritative; all content scrolls inside it.
    [NSLayoutConstraint activateConstraints:@[
        [self.collectionView.topAnchor constraintEqualToAnchor:safe.topAnchor],
        [self.collectionView.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor],
        [self.collectionView.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor],
        [self.collectionView.bottomAnchor constraintEqualToAnchor:safe.bottomAnchor]
    ]];
}

- (UICollectionViewLayout *)createLayout {
    UICollectionViewCompositionalLayout *layout = [[UICollectionViewCompositionalLayout alloc] initWithSectionProvider:^NSCollectionLayoutSection *(NSInteger sectionIndex, id<NSCollectionLayoutEnvironment> environment) {
        CGFloat width = environment.container.effectiveContentSize.width;
        BOOL accessibility = UIContentSizeCategoryIsAccessibilityCategory(environment.traitCollection.preferredContentSizeCategory);
        NSCollectionLayoutSize *headerSize = [NSCollectionLayoutSize sizeWithWidthDimension:[NSCollectionLayoutDimension fractionalWidthDimension:1]
            heightDimension:[NSCollectionLayoutDimension estimatedDimension:80]];
        NSCollectionLayoutBoundarySupplementaryItem *header = [NSCollectionLayoutBoundarySupplementaryItem boundarySupplementaryItemWithLayoutSize:headerSize elementKind:UICollectionElementKindSectionHeader alignment:NSRectAlignmentTop];
        CGFloat height;
        NSInteger columns = 1;
        if (sectionIndex == kSectionGameDir) {
            height = MAX(88, 2 * AmeUIFont(AmeUIFontRoleBody).lineHeight + 2 * AmeUIFont(AmeUIFontRoleStatus).lineHeight + 24);
        } else {
            columns = accessibility ? 1 : (width >= 1100 ? 3 : (width >= 700 ? 2 : 1));
            height = MAX(156, 2 * AmeUIFont(AmeUIFontRoleCardTitle).lineHeight + 2 * AmeUIFont(AmeUIFontRoleDescription).lineHeight + 2 * AmeUIFont(AmeUIFontRoleStatus).lineHeight + 52);
        }
        CGFloat cardWidth = sectionIndex == kSectionGameDir ? MIN(MAX(220, width * 0.28), MAX(44, width - 32)) : 1.0;
        NSCollectionLayoutDimension *itemWidth = sectionIndex == kSectionGameDir ? [NSCollectionLayoutDimension absoluteDimension:cardWidth] : [NSCollectionLayoutDimension fractionalWidthDimension:1.0 / columns];
        NSCollectionLayoutSize *itemSize = [NSCollectionLayoutSize sizeWithWidthDimension:itemWidth heightDimension:[NSCollectionLayoutDimension absoluteDimension:height]];
        NSCollectionLayoutItem *item = [NSCollectionLayoutItem itemWithLayoutSize:itemSize];
        item.contentInsets = NSDirectionalEdgeInsetsMake(0, 0, 0, 0);
        NSCollectionLayoutSize *groupSize = [NSCollectionLayoutSize sizeWithWidthDimension:sectionIndex == kSectionGameDir ? itemWidth : [NSCollectionLayoutDimension fractionalWidthDimension:1]
            heightDimension:[NSCollectionLayoutDimension absoluteDimension:height]];
        // Count-based groups distribute spacing within the width, avoiding overflowing fractional cards.
        NSCollectionLayoutGroup *group = [NSCollectionLayoutGroup horizontalGroupWithLayoutSize:groupSize subitem:item count:sectionIndex == kSectionGameDir ? 1 : columns];
        group.interItemSpacing = [NSCollectionLayoutSpacing fixedSpacing:12];
        NSCollectionLayoutSection *section = [NSCollectionLayoutSection sectionWithGroup:group];
        section.interGroupSpacing = 12;
        section.contentInsets = NSDirectionalEdgeInsetsMake(0, 16, 24, 16);
        section.boundarySupplementaryItems = @[header];
        if (sectionIndex == kSectionGameDir) section.orthogonalScrollingBehavior = UICollectionLayoutSectionOrthogonalScrollingBehaviorContinuous;
        return section;
    }];
    UICollectionViewCompositionalLayoutConfiguration *configuration = layout.configuration;
    NSCollectionLayoutSize *overviewSize = [NSCollectionLayoutSize sizeWithWidthDimension:[NSCollectionLayoutDimension fractionalWidthDimension:1]
        heightDimension:[NSCollectionLayoutDimension estimatedDimension:120]];
    configuration.boundarySupplementaryItems = @[[NSCollectionLayoutBoundarySupplementaryItem boundarySupplementaryItemWithLayoutSize:overviewSize elementKind:VMOverviewKind alignment:NSRectAlignmentTop]];
    layout.configuration = configuration;
    return layout;
}

#pragma mark - Data

- (void)loadProfiles {
    NSMutableDictionary *profiles = PLProfiles.current.profiles;
    NSMutableArray *list = [NSMutableArray array];
    for (NSString *key in profiles.allKeys) {
        [list addObject:key];
    }
    self.profileList = [list sortedArrayUsingComparator:^NSComparisonResult(NSString *obj1, NSString *obj2) {
        return [obj2 compare:obj1];
    }];
    self.selectedProfile = PLProfiles.current.selectedProfileName;

    // ★ [PERF] 一次性算好各 profile 的版本隔离判定（含磁盘嗅探），滚动期间只查表。
    //   本方法在 viewDidLoad / 切游戏目录 / ReloadProfileList 时被调用 ⇒ 缓存随之刷新，
    //   判定时机与原「每张卡片实时算」在可见范围内等价（页面打开与数据变更时都是最新的）。
    NSMutableDictionary<NSString *, NSNumber *> *isoMap = [NSMutableDictionary dictionaryWithCapacity:self.profileList.count];
    for (NSString *name in self.profileList) {
        NSDictionary *prof = PLProfiles.current.profiles[name];
        if (![prof isKindOfClass:[NSDictionary class]]) continue;
        // 与原 cellForItemAtIndexPath 里完全同一条判定（concreteVersionId 传 nil）
        isoMap[name] = @(amePCLVersionIsolationForProfile(prof, nil));
    }
    self.isolationByProfile = isoMap;
}

/// 加载游戏目录（实例）列表
- (void)loadGameDirList {
    NSMutableArray *list = [NSMutableArray array];
    [list addObject:@"default"];

    NSString *instancesPath = [NSString stringWithFormat:@"%s/instances", getenv("POJAV_HOME")];
    NSFileManager *fm = [NSFileManager defaultManager];
    NSArray *files = [fm contentsOfDirectoryAtPath:instancesPath error:nil];
    BOOL isDir = NO;
    for (NSString *file in files) {
        NSString *fullPath = [instancesPath stringByAppendingPathComponent:file];
        if ([fm fileExistsAtPath:fullPath isDirectory:&isDir] && isDir && ![file isEqualToString:@"default"]) {
            [list addObject:file];
        }
    }
    self.gameDirList = list;
    id raw = getPrefObject(@"general.game_directory");
    self.currentGameDir = [raw isKindOfClass:[NSString class]] ? raw : @"default";
    // ★ [PERF] 目录列表是唯一会改变「目录大小」的入口（新建/删除/切目录）⇒ 在此整体失效缓存，
    //   保证缓存里的数字只在同一份目录列表内被复用。
    self.gameDirSizeCache = [NSMutableDictionary dictionary];
    self.gameDirSizeInFlight = [NSMutableSet set];
}

#pragma mark - UICollectionViewDataSource

- (NSInteger)numberOfSectionsInCollectionView:(UICollectionView *)collectionView {
    return 2;
}

- (NSInteger)collectionView:(UICollectionView *)collectionView numberOfItemsInSection:(NSInteger)section {
    if (section == kSectionGameDir) {
        return self.gameDirList.count + 1;  // 末尾追加"新建目录"按钮
    } else {
        return self.profileList.count;
    }
}

- (UICollectionViewCell *)collectionView:(UICollectionView *)collectionView cellForItemAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == kSectionGameDir) {
        VMGameDirCell *cell = [collectionView dequeueReusableCellWithReuseIdentifier:@"GameDirCell" forIndexPath:indexPath];

        if (indexPath.item == (NSInteger)self.gameDirList.count) {
            [cell configureWithName:nil detail:nil isSelected:NO isAddButton:YES];
            return cell;
        }

        NSString *dirName = self.gameDirList[indexPath.item];
        BOOL isSelected = [dirName isEqualToString:self.currentGameDir];

        // ★ [PERF] 目录大小是【递归枚举整个实例目录】的重活，原先每次 cell 出队（dequeue）都重跑一遍
        //   ⇒ 横向滚动时每秒几十次全量磁盘遍历 + NSFileManager 属性查询（滚动卡顿主因之一）。
        //   现在：命中缓存直接显示；未命中只发起一次（in-flight 去重），其余出队走占位文案。
        //   观感不变（数字仍会异步补上），磁盘遍历次数从 O(出队次数) 降到 O(目录数)。
        NSString *sizeStr = nil;
        // 防御：容器正常由 loadGameDirList 建立；万一路径上先出卡也不会退化成「每次都重算」。
        if (!self.gameDirSizeCache) self.gameDirSizeCache = [NSMutableDictionary dictionary];
        if (!self.gameDirSizeInFlight) self.gameDirSizeInFlight = [NSMutableSet set];
        NSNumber *cachedSize = self.gameDirSizeCache[dirName];
        if (cachedSize) {
            sizeStr = [NSByteCountFormatter stringFromByteCount:cachedSize.unsignedLongLongValue
                                                      countStyle:NSByteCountFormatterCountStyleMemory];
        }
        [cell configureWithName:dirName detail:(sizeStr ?: localize(@"i18n_str_134", nil)) isSelected:isSelected isAddButton:NO];

        if (!cachedSize && ![self.gameDirSizeInFlight containsObject:dirName]) {
            [self.gameDirSizeInFlight addObject:dirName];
            NSString *capturedDir = dirName;
            __weak typeof(self) weakSelf = self;
            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                unsigned long long folderSize = 0;
                NSString *directory = [NSString stringWithFormat:@"%s/instances/%@", getenv("POJAV_HOME"), capturedDir];
                [weakSelf calculateFolderSizeAtPath:directory size:&folderSize];
                NSString *computedSizeStr = [NSByteCountFormatter stringFromByteCount:folderSize countStyle:NSByteCountFormatterCountStyleMemory];
                dispatch_async(dispatch_get_main_queue(), ^{
                    __strong typeof(weakSelf) strongSelf = weakSelf;
                    if (!strongSelf) return;
                    [strongSelf.gameDirSizeInFlight removeObject:capturedDir];
                    strongSelf.gameDirSizeCache[capturedDir] = @(folderSize);
                    // 只更新「当前仍在屏、且确实对应这个目录」的那张卡片（按目录名反查索引，
                    // 不用出队时的 indexPath —— 复用/插入后索引可能已经变了）
                    NSInteger idx = [strongSelf.gameDirList indexOfObject:capturedDir];
                    if (idx == NSNotFound) return;
                    NSIndexPath *ip = [NSIndexPath indexPathForItem:idx inSection:kSectionGameDir];
                    VMGameDirCell *targetCell = (VMGameDirCell *)[collectionView cellForItemAtIndexPath:ip];
                    if (targetCell && [targetCell isKindOfClass:[VMGameDirCell class]]) {
                        targetCell.detailLabel.text = computedSizeStr;
                    }
                });
            });
        }

        return cell;
    } else {
        VMVersionCardCell *cell = [collectionView dequeueReusableCellWithReuseIdentifier:@"VersionCell" forIndexPath:indexPath];

        NSString *profileName = self.profileList[indexPath.item];
        NSDictionary *profile = PLProfiles.current.profiles[profileName];
        NSString *versionId = profile[@"lastVersionId"] ?: localize(@"i18n_str_1052", nil);
        BOOL isSelected = [profileName isEqualToString:self.selectedProfile];
        // ★ [VI-SWITCH-UI] 隔离态以「版本隔离」统一 resolver 为准（显式 versionIsolation / 自动判定 /
        //   全局默认），不再只看 gameDir —— 新的隔离开关不改写 gameDir，只看它会把已隔离的版本漏报成共享。
        // ★ [PERF] 该判定含磁盘嗅探，已改为在 loadProfiles 里一次算好（见 isolationByProfile），
        //   这里只查表 —— 滚动期间不再做任何文件 I/O。
        BOOL isolated = [self.isolationByProfile[profileName] boolValue];
        NSString *lastPlayed = [self formatLastPlayed:profile[@"lastPlayed"]];

        [cell configureWithName:profileName version:versionId isSelected:isSelected isolated:isolated lastPlayed:lastPlayed];
        NSString *identity = [profileName copy];
        __weak typeof(self) weakSelf = self;
        cell.onMore = ^{
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf || strongSelf.presentedViewController || strongSelf.navigationController.transitionCoordinator || !PLProfiles.current.profiles[identity]) return;
            [strongSelf showProfileActions:identity];
        };
        return cell;
    }
}

/// 简易目录大小计算（递归）
- (void)calculateFolderSizeAtPath:(NSString *)path size:(unsigned long long *)size {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSDirectoryEnumerator *enumerator = [fm enumeratorAtPath:path];
    NSString *relativePath;
    while ((relativePath = [enumerator nextObject])) {
        NSString *fullPath = [path stringByAppendingPathComponent:relativePath];
        NSDictionary *attrs = [fm attributesOfItemAtPath:fullPath error:nil];
        if (attrs) {
            *size += [attrs fileSize];
        }
    }
}

/// 将 lastPlayed 时间戳格式化为"最后游玩：xxx"
- (NSString *)formatLastPlayed:(id)lastPlayedRaw {
    if (!lastPlayedRaw) return @"";
    NSTimeInterval ts;
    if ([lastPlayedRaw isKindOfClass:[NSNumber class]]) {
        ts = [lastPlayedRaw doubleValue];
    } else if ([lastPlayedRaw isKindOfClass:[NSString class]]) {
        ts = [(NSString *)lastPlayedRaw doubleValue];
    } else {
        return @"";
    }
    if (ts <= 0) return @"";
    NSDate *date = [NSDate dateWithTimeIntervalSince1970:ts];
    // ★ [PERF] NSDateFormatter 的创建成本很高（毫秒级，含 locale/calendar 解析）。
    //   原先每张卡片每次配置都 new 一个 ⇒ 滚动时等于每帧若干次毫秒级开销。
    //   改为进程内单例：只配置一次；locale 若在会话中变化则就地刷新（与原语义一致）。
    static NSDateFormatter *sAmeLastPlayedFormatter = nil;
    static dispatch_once_t sOnceToken;
    dispatch_once(&sOnceToken, ^{
        sAmeLastPlayedFormatter = [[NSDateFormatter alloc] init];
        sAmeLastPlayedFormatter.doesRelativeDateFormatting = YES;
        sAmeLastPlayedFormatter.dateStyle = NSDateFormatterShortStyle;
        sAmeLastPlayedFormatter.timeStyle = NSDateFormatterShortStyle;
    });
    NSLocale *currentLocale = [NSLocale currentLocale];
    if (![sAmeLastPlayedFormatter.locale isEqual:currentLocale]) {
        sAmeLastPlayedFormatter.locale = currentLocale;
    }
    return [NSString stringWithFormat:localize(@"i18n_str_1069", nil), [sAmeLastPlayedFormatter stringFromDate:date]];
}

- (UICollectionReusableView *)collectionView:(UICollectionView *)collectionView viewForSupplementaryElementOfKind:(NSString *)kind atIndexPath:(NSIndexPath *)indexPath {
    if ([kind isEqualToString:VMOverviewKind]) {
        VMOverviewHeader *header = [collectionView dequeueReusableSupplementaryViewOfKind:kind withReuseIdentifier:VMOverviewKind forIndexPath:indexPath];
        self.overviewHeader = header;
        [header configureCount:self.profileList.count];
        __weak typeof(self) weakSelf = self;
        header.onCreate = ^{
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf || strongSelf.presentedViewController || strongSelf.navigationController.transitionCoordinator) return;
            [strongSelf createNewVersion];
        };
        return header;
    }
    if ([kind isEqualToString:UICollectionElementKindSectionHeader]) {
        VMSectionHeaderView *header = [collectionView dequeueReusableSupplementaryViewOfKind:kind withReuseIdentifier:@"HeaderView" forIndexPath:indexPath];
        switch (indexPath.section) {
            case kSectionGameDir:
                [header configureWithIcon:@"folder.badge.gearshape"
                                     title:localize(@"i18n_str_1070", nil)
                                  subtitle:localize(@"i18n_str_1071", nil)
                                     count:(NSInteger)self.gameDirList.count];
                break;
            case kSectionVersions:
                [header configureWithIcon:@"cube.box.fill"
                                     title:localize(@"tab.instances", @"Instances")
                                  subtitle:self.profileList.count ? localize(@"renewed.instances.profile_help", @"Saved profiles · More actions selects or deletes a profile") : localize(@"i18n_str_1057", nil)
                                     count:(NSInteger)self.profileList.count];
                break;
            default:
                [header configureWithIcon:@""
                                     title:@""
                                  subtitle:@""
                                     count:-1];
                break;
        }
        return header;
    }
    return [UICollectionReusableView new];
}

#pragma mark - UICollectionViewDelegate

// ★ [PERF] 低开销滚动帧率探针（默认关，见 AmePerfProbe.h）。未启用时本方法退化成一次静态 BOOL 判断。
- (void)scrollViewDidScroll:(UIScrollView *)scrollView {
    [AmePerfProbe noteScrollActivity:@"VersionManager"];
}

- (void)collectionView:(UICollectionView *)collectionView didSelectItemAtIndexPath:(NSIndexPath *)indexPath {
    [collectionView deselectItemAtIndexPath:indexPath animated:YES];
    if (self.presentedViewController || self.navigationController.transitionCoordinator || self.navigationController.topViewController != self) return;

    if (indexPath.section == kSectionGameDir) {
        if (indexPath.item == (NSInteger)self.gameDirList.count) {
            [self showCreateGameDirAlert];
        } else {
            NSString *dirName = self.gameDirList[indexPath.item];
            if (![dirName isEqualToString:self.currentGameDir]) {
                [self switchGameDirTo:dirName];
            }
        }
    } else if (indexPath.section == kSectionVersions) {
        // 点击版本卡片直接进入该版本的专属设置页（FCL 风格）
        NSString *profileName = self.profileList[indexPath.item];
        [self editProfile:profileName];
    }
}

#pragma mark - Game Directory Actions

/// 切换游戏目录（实例），重建符号链接
- (void)switchGameDirTo:(NSString *)name {
    if (getenv("DEMO_LOCK")) return;

    setPrefObject(@"general.game_directory", name);
    NSString *multidirPath = [NSString stringWithFormat:@"%s/instances/%@", getenv("POJAV_HOME"), name];
    NSString *lasmPath = @(getenv("POJAV_GAME_DIR"));
    NSError *removeError = nil;
    [NSFileManager.defaultManager removeItemAtPath:lasmPath error:&removeError];

    NSError *linkError = nil;
    BOOL linkOK = [NSFileManager.defaultManager createSymbolicLinkAtPath:lasmPath
                                                       withDestinationPath:multidirPath
                                                                     error:&linkError];
    if (!linkOK) {
        NSLog(@"[VersionMgr] createSymbolicLink failed: %@", linkError.localizedDescription);
        [self showAlert:[NSString stringWithFormat:localize(@"i18n_str_1074", nil), linkError.localizedDescription]];
        return;
    }
    [NSFileManager.defaultManager changeCurrentDirectoryPath:lasmPath];
    toggleIsolatedPref(NO);
    [PLProfiles updateCurrent];

    [[NSNotificationCenter defaultCenter] postNotificationName:@"ReloadProfileList" object:nil];
    [[NSNotificationCenter defaultCenter] postNotificationName:@"SelectedProfileChanged" object:nil];

    [self loadGameDirList];
    [self loadProfiles];
    [self.collectionView reloadData];
    [self updateEmptyState];
}

/// 弹出新建游戏目录对话框
- (void)showCreateGameDirAlert {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:localize(@"i18n_str_1075", nil)
                                                                   message:localize(@"i18n_str_1076", nil)
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
        textField.placeholder = localize(@"i18n_str_1077", nil);
        textField.autocapitalizationType = UITextAutocapitalizationTypeNone;
        textField.autocorrectionType = UITextAutocorrectionTypeNo;
        textField.clearButtonMode = UITextFieldViewModeWhileEditing;
        textField.delegate = self;
    }];
    [alert addAction:[UIAlertAction actionWithTitle:localize(@"resman.common.cancel", nil) style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:localize(@"i18n_str_1078", nil) style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        NSString *name = alert.textFields.firstObject.text;
        if (name.length == 0) return;
        [self createGameDirWithName:name];
    }]];

    if (UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPad) {
        alert.popoverPresentationController.sourceView = self.view;
        alert.popoverPresentationController.sourceRect = CGRectMake(self.view.bounds.size.width / 2, self.view.bounds.size.height / 2, 1, 1);
    }
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)createGameDirWithName:(NSString *)name {
    NSString *dest = [NSString stringWithFormat:@"%s/instances/%@", getenv("POJAV_HOME"), name];
    NSError *error = nil;
    if (![NSFileManager.defaultManager createDirectoryAtPath:dest withIntermediateDirectories:YES attributes:nil error:&error]) {
        [self showAlert:[NSString stringWithFormat:localize(@"i18n_str_1079", nil), error.localizedDescription]];
        return;
    }
    [self switchGameDirTo:name];
}

/// 长按游戏目录卡片弹出操作菜单：切换/删除当前目录
- (void)showGameDirActions:(NSString *)dirName {
    BOOL isSelected = [dirName isEqualToString:self.currentGameDir];
    BOOL isDefault = [dirName isEqualToString:@"default"];

    UIAlertController *alert = [UIAlertController alertControllerWithTitle:dirName
                                                                   message:isSelected ? localize(@"i18n_str_2029", nil) : localize(@"i18n_str_1081", nil)
                                                            preferredStyle:UIAlertControllerStyleActionSheet];

    if (!isSelected) {
        [alert addAction:[UIAlertAction actionWithTitle:localize(@"i18n_str_1081", nil) style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
            [self switchGameDirTo:dirName];
        }]];
    }

    // 删除目录（默认目录禁止删除，正在使用的目录需要先切换才能删除）
    if (!isDefault) {
        NSString *deleteTitle = isSelected ? localize(@"i18n_str_2030", nil) : localize(@"i18n_str_1083", nil);
        [alert addAction:[UIAlertAction actionWithTitle:deleteTitle style:UIAlertActionStyleDestructive handler:^(UIAlertAction * _Nonnull action) {
            if (isSelected) {
                [self showAlert:localize(@"i18n_str_1084", nil)];
                return;
            }
            [self confirmDeleteGameDir:dirName];
        }]];
    }

    [alert addAction:[UIAlertAction actionWithTitle:localize(@"resman.common.cancel", nil) style:UIAlertActionStyleCancel handler:nil]];

    if (UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPad) {
        alert.popoverPresentationController.sourceView = self.view;
        alert.popoverPresentationController.sourceRect = CGRectMake(self.view.bounds.size.width / 2, self.view.bounds.size.height / 2, 1, 1);
        alert.popoverPresentationController.permittedArrowDirections = UIPopoverArrowDirectionAny;
    }
    [self presentViewController:alert animated:YES completion:nil];
}

/// 二次确认删除游戏目录
- (void)confirmDeleteGameDir:(NSString *)dirName {
    UIAlertController *confirm = [UIAlertController alertControllerWithTitle:localize(@"i18n_str_1085", nil)
                                                                     message:[NSString stringWithFormat:localize(@"i18n_str_1086", nil), dirName]
                                                              preferredStyle:UIAlertControllerStyleAlert];
    [confirm addAction:[UIAlertAction actionWithTitle:localize(@"resman.common.cancel", nil) style:UIAlertActionStyleCancel handler:nil]];
    [confirm addAction:[UIAlertAction actionWithTitle:localize(@"i18n_str_457", nil) style:UIAlertActionStyleDestructive handler:^(UIAlertAction * _Nonnull action) {
        [self deleteGameDir:dirName];
    }]];
    [self presentViewController:confirm animated:YES completion:nil];
}

/// 删除指定游戏目录
- (void)deleteGameDir:(NSString *)dirName {
    if ([dirName isEqualToString:@"default"]) {
        [self showAlert:localize(@"i18n_str_1087", nil)];
        return;
    }
    if ([dirName isEqualToString:self.currentGameDir]) {
        [self showAlert:localize(@"i18n_str_1084", nil)];
        return;
    }

    NSString *dest = [NSString stringWithFormat:@"%s/instances/%@", getenv("POJAV_HOME"), dirName];
    NSError *error = nil;
    if (![NSFileManager.defaultManager removeItemAtPath:dest error:&error]) {
        [self showAlert:[NSString stringWithFormat:localize(@"i18n_str_1088", nil), error.localizedDescription]];
        return;
    }

    [self loadGameDirList];
    [self.collectionView reloadData];
    [self updateEmptyState];
    [self showAlert:[NSString stringWithFormat:localize(@"i18n_str_1089", nil), dirName]];
}

#pragma mark - Renderer Selection (启动器 native 库选择)

/// 选择渲染器并保存到当前 profile
- (void)selectRendererAtIndex:(NSInteger)index {
    if (!self.selectedProfile) {
        [self showAlert:localize(@"i18n_str_431", nil)];
        return;
    }
    if (index >= (NSInteger)self.rendererKeys.count) return;

    NSString *key = self.rendererKeys[index];
    NSString *displayName = index < (NSInteger)self.rendererNames.count ? self.rendererNames[index] : key;

    // 写入当前 profile 的 renderer 字段
    NSMutableDictionary *profiles = PLProfiles.current.profiles;
    NSMutableDictionary *profile = [profiles[self.selectedProfile] mutableCopy];
    if (!profile) {
        profile = [NSMutableDictionary dictionary];
    }
    profile[@"renderer"] = key;
    profiles[self.selectedProfile] = profile;
    [PLProfiles.current save];

    // 同步到全局偏好（保证启动游戏时 LauncherRightPanelViewController 能读到）
    setPrefString(@"video.renderer", key);

    [self.collectionView reloadData];

    NSLog(@"[VersionMgr] Renderer for profile '%@' set to '%@' (%@)", self.selectedProfile, key, displayName);
}

#pragma mark - Graphics API Selection (MC 26.2+ 游戏内 OpenGL/Vulkan)

/// 选择图形 API 并保存到当前 profile
/// 注意：graphicsApi 与 renderer 是两个不同维度：
///   - renderer：LWJGL 加载哪个 native 库（libgl4es/libMoltenVK 等）
///   - graphicsApi：MC 26.2+ 内部走 OpenGL 路径还是 Vulkan 路径
/// 当用户选择 prefer_vulkan 时建议同步将 renderer 设为 libMoltenVK.dylib，
/// 但此处不强制联动，允许高级用户分开配置。
- (void)selectGraphicsApiAtIndex:(NSInteger)index {
    if (!self.selectedProfile) {
        [self showAlert:localize(@"i18n_str_431", nil)];
        return;
    }
    if (index >= (NSInteger)self.graphicsApiKeys.count) return;

    NSString *key = self.graphicsApiKeys[index];
    NSString *displayName = index < (NSInteger)self.graphicsApiNames.count ? self.graphicsApiNames[index] : key;

    // 写入当前 profile 的 graphicsApi 字段
    NSMutableDictionary *profiles = PLProfiles.current.profiles;
    NSMutableDictionary *profile = [profiles[self.selectedProfile] mutableCopy];
    if (!profile) {
        profile = [NSMutableDictionary dictionary];
    }
    profile[@"graphicsApi"] = key;
    profiles[self.selectedProfile] = profile;

    // 同时写入 PLProfiles 当前选中的 profile。
    // JavaLauncher 启动时读的是 PLProfiles.current.selectedProfile，而本界面允许
    // 浏览并修改非当前选中的 profile。两者不一致时（用户在此切换了 profile 但未
    // 将其设为当前），只写 self.selectedProfile 会让启动侧读不到，表现为
    // 「更改渲染 API 无效」。这里补写一份，消除该不一致。
    NSString *curName = PLProfiles.current.selectedProfileName;
    if (curName.length > 0 && ![curName isEqualToString:self.selectedProfile]) {
        NSMutableDictionary *curProfile = [profiles[curName] mutableCopy];
        if (!curProfile) {
            curProfile = [NSMutableDictionary dictionary];
        }
        curProfile[@"graphicsApi"] = key;
        profiles[curName] = curProfile;
        NSLog(@"[VersionMgr] Graphics API mirrored to current profile '%@'", curName);
    }

    [PLProfiles.current save];

    // 同步到全局偏好
    setPrefString(@"video.graphics_api", key);

    [self.collectionView reloadData];

    NSLog(@"[VersionMgr] Graphics API for profile '%@' set to '%@' (%@)", self.selectedProfile, key, displayName);
}

#pragma mark - Quick Actions

- (void)openModsManager {
    if (!self.selectedProfile) {
        [self showAlert:localize(@"i18n_str_431", nil)];
        return;
    }
    ModsManagerViewController *vc = [[ModsManagerViewController alloc] init];
    vc.profileName = self.selectedProfile;
    [self.navigationController pushViewController:vc animated:YES];
}

- (void)openShadersManager {
    if (!self.selectedProfile) {
        [self showAlert:localize(@"i18n_str_431", nil)];
        return;
    }
    ShadersManagerViewController *vc = [[ShadersManagerViewController alloc] init];
    vc.profileName = self.selectedProfile;
    vc.initialMode = ShadersManagerModeLocal;
    [self.navigationController pushViewController:vc animated:YES];
}

- (void)openResourcePacksManager {
    if (!self.selectedProfile) {
        [self showAlert:localize(@"i18n_str_431", nil)];
        return;
    }
    ResourcePacksManagerViewController *vc = [[ResourcePacksManagerViewController alloc] init];
    vc.profileName = self.selectedProfile;
    vc.initialMode = ResourcePacksManagerModeLocal;
    [self.navigationController pushViewController:vc animated:YES];
}

- (void)openDataPacksManager {
    if (!self.selectedProfile) {
        [self showAlert:localize(@"i18n_str_431", nil)];
        return;
    }
    DataPacksManagerViewController *vc = [[DataPacksManagerViewController alloc] init];
    vc.profileName = self.selectedProfile;
    vc.initialMode = DataPacksManagerModeLocal;
    [self.navigationController pushViewController:vc animated:YES];
}

- (void)openWorldsManager {
    if (!self.selectedProfile) {
        [self showAlert:localize(@"i18n_str_431", nil)];
        return;
    }
    WorldsManagerViewController *vc = [[WorldsManagerViewController alloc] init];
    vc.profileName = self.selectedProfile;
    vc.initialMode = WorldsManagerModeLocal;
    [self.navigationController pushViewController:vc animated:YES];
}

#pragma mark - Profile Actions

- (void)showProfileActions:(NSString *)profileName {
    NSDictionary *profile = PLProfiles.current.profiles[profileName];
    BOOL isSelected = [profileName isEqualToString:self.selectedProfile];

    UIAlertController *alert = [UIAlertController alertControllerWithTitle:profileName
                                                                   message:profile[@"lastVersionId"]
                                                            preferredStyle:UIAlertControllerStyleActionSheet];

    if (!isSelected) {
        [alert addAction:[UIAlertAction actionWithTitle:localize(@"i18n_str_1090", nil) style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
            PLProfiles.current.selectedProfileName = profileName;
            [PLProfiles.current save];
            [[NSNotificationCenter defaultCenter] postNotificationName:@"SelectedProfileChanged" object:nil];
            [self loadProfiles];
            [self.collectionView reloadData];
        }]];
    }

    [alert addAction:[UIAlertAction actionWithTitle:localize(@"i18n_str_1091", nil) style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        [self editProfile:profileName];
    }]];

    [alert addAction:[UIAlertAction actionWithTitle:localize(@"i18n_str_306", nil) style:UIAlertActionStyleDestructive handler:^(UIAlertAction * _Nonnull action) {
        [self deleteProfile:profileName];
    }]];

    [alert addAction:[UIAlertAction actionWithTitle:localize(@"resman.common.cancel", nil) style:UIAlertActionStyleCancel handler:nil]];

    if (UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPad) {
        alert.popoverPresentationController.sourceView = self.view;
        alert.popoverPresentationController.sourceRect = CGRectMake(self.view.bounds.size.width / 2, self.view.bounds.size.height / 2, 1, 1);
        alert.popoverPresentationController.permittedArrowDirections = UIPopoverArrowDirectionAny;
    }
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)editProfile:(NSString *)profileName {
    // 关键修复（实例渲染器不生效）：点击版本卡片进入其实例设置时，
    // 必须把该 profile 同步为"当前选中实例"。否则用户在实例设置里切换的渲染器
    // 保存在被点击的 profile 上，而启动游戏时 JavaLauncher 只读取
    // PLProfiles.current.selectedProfileName（当前选中实例）的 renderer，
    // 两者不一致时启动会回退到全局 video.renderer（表现为"实例设置改了渲染器，启动却用全局"）。
    // setSelectedProfileName: 内部会保存并发送 SelectedProfileChanged 通知。
    if (![PLProfiles.current.selectedProfileName isEqualToString:profileName]) {
        PLProfiles.current.selectedProfileName = profileName;
        [self loadProfiles];
        [self.collectionView reloadData];
        [self updateEmptyState];
    }

    // 使用 ProfileSettingsViewController（合并后的统一 Edit Profile 页面，新 UI）
    ProfileSettingsViewController *vc = [[ProfileSettingsViewController alloc] init];
    vc.profileName = profileName;
    [self.navigationController pushViewController:vc animated:YES];
}

- (void)deleteProfile:(NSString *)profileName {
    if (self.profileList.count <= 1) {
        [self showAlert:localize(@"i18n_str_1092", nil)];
        return;
    }

    UIAlertController *confirm = [UIAlertController alertControllerWithTitle:localize(@"i18n_str_457", nil)
                                                                     message:[NSString stringWithFormat:localize(@"i18n_str_1093", nil), profileName]
                                                              preferredStyle:UIAlertControllerStyleAlert];

    [confirm addAction:[UIAlertAction actionWithTitle:localize(@"resman.common.cancel", nil) style:UIAlertActionStyleCancel handler:nil]];
    [confirm addAction:[UIAlertAction actionWithTitle:localize(@"i18n_str_306", nil) style:UIAlertActionStyleDestructive handler:^(UIAlertAction * _Nonnull action) {
        [PLProfiles.current.profiles removeObjectForKey:profileName];
        if ([PLProfiles.current.selectedProfileName isEqualToString:profileName]) {
            PLProfiles.current.selectedProfileName = PLProfiles.current.profiles.allKeys.firstObject;
        }
        [PLProfiles.current save];
        [self loadProfiles];
        [self.collectionView reloadData];
        [self updateEmptyState];
    }]];

    [self presentViewController:confirm animated:YES completion:nil];
}

- (void)showAlert:(NSString *)message {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:localize(@"i18n_str_388", nil) message:message preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:localize(@"i18n_str_44", nil) style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

#pragma mark - Orientation

- (BOOL)shouldAutorotate {
    return YES;
}

- (UIInterfaceOrientationMask)supportedInterfaceOrientations {
    if (AmeGameLandscapeLockActive()) return UIInterfaceOrientationMaskLandscape;
    // The existing bridge can request a landscape game transition on iOS 16+.
    // Keep older systems on the original policy; do not change their launch/rotation bridge.
    if (@available(iOS 16.0, *)) {
        return UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPad
            ? UIInterfaceOrientationMaskAll : UIInterfaceOrientationMaskAllButUpsideDown;
    }
    return UIInterfaceOrientationMaskLandscape;
}

@end
