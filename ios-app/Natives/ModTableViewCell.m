//
//  ModTableViewCell.m
//  Amethyst
//
//  Mod card cell implementation (inherits ResourceCardTableViewCell).
//  The base class provides the three-layer card background, corner radius, shadow, and selected-state appearance.
//  This class adds only mod-specific content: icons (embedded JAR > loader brand > semantic-color fallback),
//  three lines of text (name / filename / version · game version), the enable switch, and online-mode buttons.
//

#import "ModTableViewCell.h"
#import "ModItem.h"
#import "ModService.h"
#import "ModLoaderIconHelper.h"
#import "LauncherPreferences.h"
#import "utils.h"
#import <QuartzCore/QuartzCore.h>

@interface ModTableViewCell ()
// Current mod configuration and display mode (used to reload icons when appearance changes).
@property (nonatomic, strong, nullable) ModItem *currentMod;
@property (nonatomic, assign) ModTableViewCellDisplayMode currentMode;
// Online-mode-only accessory (lazily loaded; not created for the local list).
@property (nonatomic, strong, nullable) UIButton *downloadButton;
@property (nonatomic, strong, nullable) UIButton *openLinkButton;
@end

@implementation ModTableViewCell

#pragma mark - Init

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        // Trigger the base class's lazy creation of the enable-switch slot and bind its event (shown in local mode).
        [self.toggleSwitch addTarget:self action:@selector(toggleTapped) forControlEvents:UIControlEventValueChanged];
    }
    return self;
}

#pragma mark - Configuration

- (void)configureWithMod:(ModItem *)mod displayMode:(ModTableViewCellDisplayMode)mode {
    self.currentMod = mod;
    self.currentMode = mode;

    [self configureIconForMod:mod];

    // Main title: display name (falls back to filename).
    self.nameLabel.text = mod.displayName.length > 0 ? mod.displayName
                       : (mod.fileName.length > 0 ? mod.fileName : mod.basename);

    if (mode == ModTableViewCellDisplayModeLocal) {
        [self configureLocalContent:mod];
    } else {
        [self configureOnlineContent:mod];
    }
}

/// Configures the leading icon:
/// embedded JAR icon > loader brand icon (PNG/SF Symbol, standardized by ModLoaderIconHelper) > puzzlepiece fallback.
/// The icon-container background uses the loader brand color, or the mod semantic orange when no loader is known.
- (void)configureIconForMod:(ModItem *)mod {
    NSString *loaderName = nil;
    if (mod.isFabric) {
        loaderName = @"fabric";
    } else if (mod.isForge) {
        loaderName = @"forge";
    } else if (mod.isNeoForge) {
        loaderName = @"neoforge";
    }

    UIColor *brandColor = loaderName ? [ModLoaderIconHelper brandColorForLoader:loaderName] : nil;
    self.iconContainer.backgroundColor = brandColor ?: [UIColor systemOrangeColor];

    if (mod.icon) {
        // Locally parsed embedded JAR icon (e.g. pack.png): display directly without tinting.
        self.iconImageView.image = mod.icon;
        self.iconImageView.tintColor = nil;
        return;
    }

    if (loaderName) {
        // Loader brand icon: prefer PNG (preserve original colors), fall back to a tinted SF Symbol (brand color).
        [ModLoaderIconHelper configureImageView:self.iconImageView
                                      forLoader:loaderName
                              traitCollection:self.traitCollection];
    } else {
        self.iconImageView.image = nil;
    }
    // Semantic-color fallback when no icon is available (SF Symbol inside a container, not a bare icon).
    if (!self.iconImageView.image) {
        self.iconImageView.image = [UIImage systemImageNamed:@"puzzlepiece.extension.fill"];
        self.iconImageView.tintColor = [UIColor whiteColor];
    }
}

/// Local mode: subtitle = filename, metadata = version · game version, trailing accessory = enable switch.
- (void)configureLocalContent:(ModItem *)mod {
    self.subtitleLabel.text = mod.fileName.length > 0 ? mod.fileName : mod.basename;
    self.subtitleLabel.hidden = (self.subtitleLabel.text.length == 0);

    // Version information row: version · Minecraft version (hidden when both are missing).
    NSMutableArray<NSString *> *parts = [NSMutableArray array];
    if (mod.version.length > 0) [parts addObject:[NSString stringWithFormat:@"v%@", mod.version]];
    if (mod.gameVersion.length > 0) [parts addObject:[NSString stringWithFormat:@"MC %@", mod.gameVersion]];
    self.detailLabel.text = [parts componentsJoinedByString:@" · "];
    self.detailLabel.hidden = (parts.count == 0);

    // Accessory: local mode shows only the enable switch (base-class slot; stack automatically collapses hidden items).
    self.toggleSwitch.hidden = NO;
    if (self.downloadButton) self.downloadButton.hidden = YES;
    if (self.openLinkButton) self.openLinkButton.hidden = YES;
    self.chevronImageView.hidden = YES;

    [self updateToggleState:mod.disabled];
}

/// Online mode: subtitle = author, metadata = downloads, trailing accessories = link + download button.
- (void)configureOnlineContent:(ModItem *)mod {
    self.subtitleLabel.text = [NSString stringWithFormat:@"by %@", mod.author ?: @"Unknown"];

    NSNumberFormatter *formatter = [[NSNumberFormatter alloc] init];
    formatter.numberStyle = NSNumberFormatterDecimalStyle;
    NSString *downloadsStr = [formatter stringFromNumber:mod.downloads ?: @0];
    self.detailLabel.text = [NSString stringWithFormat:localize(@"resman.mods.download_count", nil), downloadsStr];
    self.detailLabel.hidden = NO;

    // Accessory: hide the switch and show link + download.
    self.toggleSwitch.hidden = YES;
    self.downloadButton.hidden = NO;
    self.openLinkButton.hidden = NO;
    self.chevronImageView.hidden = YES;

    self.contentView.alpha = 1.0;
}

#pragma mark - Lazy accessory (online mode only)

- (UIButton *)downloadButton {
    if (!_downloadButton) {
        _downloadButton = [UIButton buttonWithType:UIButtonTypeSystem];
        _downloadButton.translatesAutoresizingMaskIntoConstraints = NO;
        [_downloadButton setTitle:localize(@"resman.mods.download", nil) forState:UIControlStateNormal];
        [_downloadButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        _downloadButton.titleLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightSemibold];
        _downloadButton.backgroundColor = accentColor();
        _downloadButton.contentEdgeInsets = UIEdgeInsetsMake(5, 12, 5, 12);
        _downloadButton.layer.cornerRadius = 13.0;
        _downloadButton.layer.cornerCurve = kCACornerCurveContinuous;
        _downloadButton.layer.masksToBounds = YES;
        [_downloadButton setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
        [_downloadButton setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
        [_downloadButton addTarget:self action:@selector(downloadTapped) forControlEvents:UIControlEventTouchUpInside];
        _downloadButton.hidden = YES;
        [self.accessoryStack insertArrangedSubview:_downloadButton atIndex:0];
    }
    return _downloadButton;
}

- (UIButton *)openLinkButton {
    if (!_openLinkButton) {
        _openLinkButton = [UIButton buttonWithType:UIButtonTypeSystem];
        _openLinkButton.translatesAutoresizingMaskIntoConstraints = NO;
        UIImage *image = [[UIImage systemImageNamed:@"globe"] imageWithTintColor:[UIColor secondaryLabelColor]];
        [_openLinkButton setImage:image forState:UIControlStateNormal];
        _openLinkButton.contentMode = UIViewContentModeScaleAspectFit;
        [_openLinkButton setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
        [_openLinkButton setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
        [_openLinkButton addTarget:self action:@selector(openLinkTapped) forControlEvents:UIControlEventTouchUpInside];
        _openLinkButton.hidden = YES;
        [self.accessoryStack insertArrangedSubview:_openLinkButton atIndex:0];
        [NSLayoutConstraint activateConstraints:@[
            [_openLinkButton.widthAnchor constraintEqualToConstant:28],
            [_openLinkButton.heightAnchor constraintEqualToConstant:28],
        ]];
    }
    return _openLinkButton;
}

#pragma mark - State Updates

- (void)updateToggleState:(BOOL)disabled {
    [self.toggleSwitch setOn:!disabled animated:YES];
    // Reduce opacity for the entire disabled mod (including text and icon), matching the previous appearance.
    self.contentView.alpha = disabled ? 0.6 : 1.0;
}

- (void)setUpdateAvailable:(BOOL)available {
    self.updateBadge.hidden = !available;
}

#pragma mark - Trait Collection (reload loader PNG icons when switching light/dark appearance)

- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];
    if ([self.traitCollection hasDifferentColorAppearanceComparedToTraitCollection:previousTraitCollection]) {
        if (self.currentMod && self.currentMode == ModTableViewCellDisplayModeLocal) {
            [self configureIconForMod:self.currentMod];
        }
    }
}

#pragma mark - Reuse

- (void)prepareForReuse {
    [super prepareForReuse]; // The base class has already reset text, icon, and accessory slots.
    self.contentView.alpha = 1.0;
    if (self.downloadButton) self.downloadButton.hidden = YES;
    if (self.openLinkButton) self.openLinkButton.hidden = YES;
    self.currentMod = nil;
}

#pragma mark - Actions

- (void)toggleTapped {
    if ([self.delegate respondsToSelector:@selector(modCellDidTapToggle:)]) {
        [self.delegate modCellDidTapToggle:self];
    }
}

- (void)downloadTapped {
    if ([self.delegate respondsToSelector:@selector(modCellDidTapDownload:)]) {
        [self.delegate modCellDidTapDownload:self];
    }
}

- (void)openLinkTapped {
    if ([self.delegate respondsToSelector:@selector(modCellDidTapOpenLink:)]) {
        [self.delegate modCellDidTapOpenLink:self];
    }
}

@end
