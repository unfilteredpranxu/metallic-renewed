#import "utils.h"
// ModVersionTableViewCell.m
// Based on the FCL/ZL2 version-list row design, with enhanced visual hierarchy:
// - Rounded card container (14pt corners + light shadow + translucent background), visually consistent with ModernAssetCell.
// - Left: version name (15pt semibold) + version number (12pt secondary).
// - Loader badge row: colored fabric/forge/quilt/neoforge pill labels (based on ZL2 LittleTextLabel).
// - Right: release date + file size + game version (right-aligned vertically).
// - Chevron indicates that tapping opens the download page.
//
// Compact variant: reduce card padding, font sizes, and badge height to approach VersionCardCell's compactness
// (cardContainer vertical spacing 6→4, inner padding 12→10, all font sizes down 1pt, badge height 18→16).

#import "ModVersionTableViewCell.h"
#import "BackgroundManager.h"
#import "ModLoaderIconHelper.h"

@interface ModVersionTableViewCell ()
// Card container: rounded corners + shadow + translucent background (shared visual standard).
@property (nonatomic, strong) UIView *cardContainer;
// Left information area (version-name row + version number + loader-badge row).
@property (nonatomic, strong) UIStackView *leftStackView;
// Version-name row (horizontal: nameLabel + releaseTypeBadge; based on FCL's release-type label).
@property (nonatomic, strong) UIStackView *nameRowStack;
// Loader-badge container (horizontally arranged colored pill labels).
@property (nonatomic, strong) UIStackView *loaderBadgeStack;
// Right information area (date + size + game version).
@property (nonatomic, strong) UIStackView *rightStackView;
// Subviews.
@property (nonatomic, strong) UILabel *nameLabel;
@property (nonatomic, strong) UILabel *releaseTypeBadge; // Release-type badge (Release/Beta/Alpha).
@property (nonatomic, strong) UILabel *versionNumberLabel;
@property (nonatomic, strong) UILabel *datePublishedLabel;
@property (nonatomic, strong) UILabel *fileSizeLabel;
@property (nonatomic, strong) UILabel *gameVersionsLabel;
@end

@implementation ModVersionTableViewCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        [self setupUI];
    }
    return self;
}

- (void)setupUI {
    self.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    self.selectionStyle = UITableViewCellSelectionStyleNone;
    self.backgroundColor = [UIColor clearColor];
    self.contentView.backgroundColor = [UIColor clearColor];

    // ===== Card container: rounded corners + translucent background + light shadow (Phase 3 UI adjustment: corners 14→12, lighter shadow) =====
    self.cardContainer = [[UIView alloc] init];
    self.cardContainer.translatesAutoresizingMaskIntoConstraints = NO;
    self.cardContainer.backgroundColor = [[UIColor whiteColor] colorWithAlphaComponent:0.08];
    self.cardContainer.layer.cornerRadius = 12;
    self.cardContainer.layer.cornerCurve = kCACornerCurveContinuous;
    self.cardContainer.layer.borderWidth = 0.5;
    self.cardContainer.layer.borderColor = [[UIColor whiteColor] colorWithAlphaComponent:0.10].CGColor;
    self.cardContainer.layer.shadowColor = [UIColor blackColor].CGColor;
    self.cardContainer.layer.shadowOffset = CGSizeMake(0, 2);
    self.cardContainer.layer.shadowOpacity = 0.10;
    self.cardContainer.layer.shadowRadius = 4;
    [self.contentView addSubview:self.cardContainer];

    // ===== Left: version-name row (with release-type badge) + version number =====
    self.nameLabel = [[UILabel alloc] init];
    self.nameLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
    self.nameLabel.textColor = [UIColor labelColor];
    self.nameLabel.numberOfLines = 1;
    self.nameLabel.adjustsFontSizeToFitWidth = YES;
    self.nameLabel.minimumScaleFactor = 0.7;
    self.nameLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    [self.nameLabel setContentHuggingPriority:UILayoutPriorityDefaultLow forAxis:UILayoutConstraintAxisHorizontal];
    [self.nameLabel setContentCompressionResistancePriority:UILayoutPriorityDefaultLow forAxis:UILayoutConstraintAxisHorizontal];

    // Release-type badge (Release/Beta/Alpha; based on FCL/ZL2 version-row labels).
    self.releaseTypeBadge = [[UILabel alloc] init];
    self.releaseTypeBadge.font = [UIFont systemFontOfSize:8 weight:UIFontWeightBold];
    self.releaseTypeBadge.textColor = [UIColor whiteColor];
    self.releaseTypeBadge.textAlignment = NSTextAlignmentCenter;
    self.releaseTypeBadge.layer.cornerRadius = 4;
    self.releaseTypeBadge.layer.cornerCurve = kCACornerCurveContinuous;
    self.releaseTypeBadge.layer.masksToBounds = YES;
    self.releaseTypeBadge.translatesAutoresizingMaskIntoConstraints = NO;
    [self.releaseTypeBadge.heightAnchor constraintEqualToConstant:14].active = YES;
    self.releaseTypeBadge.hidden = YES; // Hidden by default; shown as needed by configureWithVersion.
    [self.releaseTypeBadge setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    [self.releaseTypeBadge setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];

    // Version-name row (horizontal: nameLabel + releaseTypeBadge).
    self.nameRowStack = [[UIStackView alloc] initWithArrangedSubviews:@[self.nameLabel, self.releaseTypeBadge]];
    self.nameRowStack.axis = UILayoutConstraintAxisHorizontal;
    self.nameRowStack.spacing = 6;
    self.nameRowStack.alignment = UIStackViewAlignmentCenter;
    self.nameRowStack.distribution = UIStackViewDistributionFill;
    self.nameRowStack.translatesAutoresizingMaskIntoConstraints = NO;

    self.versionNumberLabel = [[UILabel alloc] init];
    self.versionNumberLabel.font = [UIFont systemFontOfSize:12];
    self.versionNumberLabel.textColor = [UIColor secondaryLabelColor];
    self.versionNumberLabel.numberOfLines = 1;
    self.versionNumberLabel.adjustsFontSizeToFitWidth = YES;
    self.versionNumberLabel.minimumScaleFactor = 0.7;
    self.versionNumberLabel.lineBreakMode = NSLineBreakByTruncatingTail;

    // Loader-badge stack (horizontal; populated dynamically by configureWithVersion).
    self.loaderBadgeStack = [[UIStackView alloc] init];
    self.loaderBadgeStack.axis = UILayoutConstraintAxisHorizontal;
    self.loaderBadgeStack.spacing = 5;
    self.loaderBadgeStack.alignment = UIStackViewAlignmentCenter;
    self.loaderBadgeStack.distribution = UIStackViewDistributionFill;
    self.loaderBadgeStack.translatesAutoresizingMaskIntoConstraints = NO;

    // Main left stack (vertical: version-name row → version number → loader-badge row).
    self.leftStackView = [[UIStackView alloc] initWithArrangedSubviews:@[self.nameRowStack, self.versionNumberLabel, self.loaderBadgeStack]];
    self.leftStackView.axis = UILayoutConstraintAxisVertical;
    self.leftStackView.spacing = 3;
    self.leftStackView.alignment = UIStackViewAlignmentLeading;
    self.leftStackView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.cardContainer addSubview:self.leftStackView];

    // ===== Right: date + file size + game version =====
    self.datePublishedLabel = [[UILabel alloc] init];
    self.datePublishedLabel.font = [UIFont systemFontOfSize:11];
    self.datePublishedLabel.textColor = [UIColor tertiaryLabelColor];
    self.datePublishedLabel.textAlignment = NSTextAlignmentRight;

    self.fileSizeLabel = [[UILabel alloc] init];
    self.fileSizeLabel.font = [UIFont systemFontOfSize:11];
    self.fileSizeLabel.textColor = [UIColor tertiaryLabelColor];
    self.fileSizeLabel.textAlignment = NSTextAlignmentRight;

    self.gameVersionsLabel = [[UILabel alloc] init];
    self.gameVersionsLabel.font = [UIFont systemFontOfSize:11];
    self.gameVersionsLabel.textColor = [UIColor tertiaryLabelColor];
    self.gameVersionsLabel.textAlignment = NSTextAlignmentRight;
    self.gameVersionsLabel.numberOfLines = 1;
    self.gameVersionsLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    self.gameVersionsLabel.adjustsFontSizeToFitWidth = YES;
    self.gameVersionsLabel.minimumScaleFactor = 0.7;

    self.rightStackView = [[UIStackView alloc] initWithArrangedSubviews:@[self.datePublishedLabel, self.fileSizeLabel, self.gameVersionsLabel]];
    self.rightStackView.axis = UILayoutConstraintAxisVertical;
    self.rightStackView.spacing = 3;
    self.rightStackView.alignment = UIStackViewAlignmentTrailing;
    self.rightStackView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.cardContainer addSubview:self.rightStackView];

    // ===== Layout constraints (Phase 3 UI adjustment: reduce card horizontal margins 16→10, inner padding 14→10) =====
    [NSLayoutConstraint activateConstraints:@[
        // Card container fills contentView with 4pt spacing above and below.
        [self.cardContainer.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:4],
        [self.cardContainer.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:10],
        [self.cardContainer.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-10],
        [self.cardContainer.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-4],

        // Left stack: 10pt from the left and 8pt top/bottom (Phase 3 UI adjustment: reduced from 10).
        [self.leftStackView.leadingAnchor constraintEqualToAnchor:self.cardContainer.leadingAnchor constant:10],
        [self.leftStackView.topAnchor constraintEqualToAnchor:self.cardContainer.topAnchor constant:8],
        [self.leftStackView.bottomAnchor constraintEqualToAnchor:self.cardContainer.bottomAnchor constant:-8],
        [self.leftStackView.trailingAnchor constraintLessThanOrEqualToAnchor:self.rightStackView.leadingAnchor constant:-8],

        // Right stack: 28pt from the right (to leave room for the chevron), vertically centered.
        [self.rightStackView.trailingAnchor constraintEqualToAnchor:self.cardContainer.trailingAnchor constant:-28],
        [self.rightStackView.centerYAnchor constraintEqualToAnchor:self.cardContainer.centerYAnchor]
    ]];

    // Apply the blur background effect.
    [[BackgroundManager sharedManager] applyEffectToView:self.cardContainer];
}

- (void)prepareForReuse {
    [super prepareForReuse];
    // Clear loader badges to prevent leftovers when the cell is reused.
    [self.loaderBadgeStack.arrangedSubviews makeObjectsPerformSelector:@selector(removeFromSuperview)];
}

#pragma mark - Loader badges

/// Creates a single loader-badge label (pill style, colored by loader type).
/// Based on ZL2 LittleTextLabel: fabric=blue / forge=brown / quilt=red / neoforge=orange / optifine=yellow.
/// Compact variant: height 16pt (previously 18pt), font 9pt (previously 10pt), corner radius 7 (previously 8).
- (UILabel *)createLoaderBadge:(NSString *)loaderName {
    UILabel *badge = [[UILabel alloc] init];
    badge.text = loaderName;
    badge.font = [UIFont systemFontOfSize:9 weight:UIFontWeightBold];
    badge.textColor = [UIColor whiteColor];
    badge.textAlignment = NSTextAlignmentCenter;
    badge.backgroundColor = [self colorForLoader:loaderName];
    badge.layer.cornerRadius = 7;
    badge.layer.cornerCurve = kCACornerCurveContinuous;
    badge.layer.masksToBounds = YES;
    badge.translatesAutoresizingMaskIntoConstraints = NO;
    [badge setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    [badge setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    // Fixed height of 16pt (compact variant; previously 18pt).
    [NSLayoutConstraint activateConstraints:@[
        [badge.heightAnchor constraintEqualToConstant:16]
    ]];
    // Width = text width + 10pt horizontal padding (previously 12pt).
    [badge sizeToFit];
    CGFloat textWidth = badge.frame.size.width;
    [badge.widthAnchor constraintEqualToConstant:textWidth + 10].active = YES;
    return badge;
}

/// Maps loader names to brand colors (delegates to ModLoaderIconHelper to eliminate inconsistent colors across files).
- (UIColor *)colorForLoader:(NSString *)loader {
    return [ModLoaderIconHelper brandColorForLoader:loader];
}

/// Populates loader badges from version data (shows at most 4 to prevent overflow).
- (void)configureLoaderBadges:(NSArray<NSString *> *)loaders {
    [self.loaderBadgeStack.arrangedSubviews makeObjectsPerformSelector:@selector(removeFromSuperview)];
    if (![loaders isKindOfClass:[NSArray class]] || loaders.count == 0) return;

    NSInteger maxBadges = MIN(4, loaders.count);
    for (NSInteger i = 0; i < maxBadges; i++) {
        NSString *loader = loaders[i];
        if (![loader isKindOfClass:[NSString class]] || loader.length == 0) continue;
        UILabel *badge = [self createLoaderBadge:loader];
        [self.loaderBadgeStack addArrangedSubview:badge];
    }

    // If there are more than 4, add a "+N" badge (compact variant: height 16, width 24, font 9).
    if (loaders.count > 4) {
        UILabel *moreBadge = [[UILabel alloc] init];
        moreBadge.text = [NSString stringWithFormat:@"+%ld", (long)(loaders.count - 4)];
        moreBadge.font = [UIFont systemFontOfSize:9 weight:UIFontWeightBold];
        moreBadge.textColor = [UIColor whiteColor];
        moreBadge.textAlignment = NSTextAlignmentCenter;
        moreBadge.backgroundColor = [UIColor tertiaryLabelColor];
        moreBadge.layer.cornerRadius = 7;
        moreBadge.layer.cornerCurve = kCACornerCurveContinuous;   // ★ [CORNER-FIX] Continuous corners (consistent with system cards).
        moreBadge.layer.masksToBounds = YES;
        moreBadge.translatesAutoresizingMaskIntoConstraints = NO;
        [moreBadge setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
        [moreBadge setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
        [NSLayoutConstraint activateConstraints:@[
            [moreBadge.heightAnchor constraintEqualToConstant:16],
            [moreBadge.widthAnchor constraintEqualToConstant:24]
        ]];
        [self.loaderBadgeStack addArrangedSubview:moreBadge];
    }
}

#pragma mark - Configuration

- (void)configureWithVersion:(ModVersion *)version {
    self.nameLabel.text = version.name;
    self.versionNumberLabel.text = version.versionNumber;

    // Release-type badge (Release/Beta/Alpha; based on FCL/ZL2 version-row labels).
    NSString *vType = version.versionType.lowercaseString;
    if ([vType isEqualToString:@"release"] || vType.length == 0) {
        // Release: green badge.
        self.releaseTypeBadge.text = @" Release ";
        self.releaseTypeBadge.backgroundColor = [UIColor colorWithRed:0.30 green:0.75 blue:0.40 alpha:1.0];
        self.releaseTypeBadge.hidden = NO;
    } else if ([vType isEqualToString:@"beta"]) {
        // Beta: orange badge.
        self.releaseTypeBadge.text = @" Beta ";
        self.releaseTypeBadge.backgroundColor = [UIColor colorWithRed:0.90 green:0.60 blue:0.10 alpha:1.0];
        self.releaseTypeBadge.hidden = NO;
    } else if ([vType isEqualToString:@"alpha"]) {
        // Alpha: red badge.
        self.releaseTypeBadge.text = @" Alpha ";
        self.releaseTypeBadge.backgroundColor = [UIColor colorWithRed:0.85 green:0.30 blue:0.30 alpha:1.0];
        self.releaseTypeBadge.hidden = NO;
    } else {
        self.releaseTypeBadge.hidden = YES;
    }

    // Release date: ISO 8601 → short date format.
    NSISO8601DateFormatter *dateFormatter = [[NSISO8601DateFormatter alloc] init];
    NSDate *date = [dateFormatter dateFromString:version.datePublished];
    if (date) {
        NSDateFormatter *displayFormatter = [[NSDateFormatter alloc] init];
        displayFormatter.dateStyle = NSDateFormatterShortStyle;
        displayFormatter.timeStyle = NSDateFormatterNoStyle;
        self.datePublishedLabel.text = [displayFormatter stringFromDate:date];
    } else {
        self.datePublishedLabel.text = localize(@"i18n_str_460", nil);
    }

    // File size.
    if (version.primaryFile) {
        self.fileSizeLabel.text = [NSByteCountFormatter stringFromByteCount:[version.primaryFile[@"size"] longValue] countStyle:NSByteCountFormatterCountStyleFile];
    } else if (version.fileSize) {
        self.fileSizeLabel.text = [NSByteCountFormatter stringFromByteCount:[version.fileSize longValue] countStyle:NSByteCountFormatterCountStyleFile];
    } else {
        self.fileSizeLabel.text = localize(@"i18n_str_461", nil);
    }

    // Game-version compatibility.
    self.gameVersionsLabel.text = [version.gameVersions componentsJoinedByString:@", "];

    // Loader badges (new: based on ZL2's loader pill labels).
    [self configureLoaderBadges:version.loaders];
}

@end
