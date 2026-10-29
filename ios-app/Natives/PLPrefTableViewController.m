#import "HomeTopNavView.h"
#import <Foundation/Foundation.h>
#import <objc/runtime.h>

#import "DBNumberedSlider.h"
#import "LauncherNavigationController.h"
#import "LauncherMenuViewController.h"
#import "LauncherPreferences.h"
#import "PLPrefTableViewController.h"
#import "BackgroundManager.h"
#import "UIKit+GlassSurface.h"
#import "UIKit+hook.h"

#import "ios_uikit_bridge.h"
#import "utils.h"

// Five description keys are absent from the pinned complete English catalog. Keep existing
// translations first; fallback only these verified first-party presentation descriptions.
static NSString *MetallicReferencePreferenceDetail(NSString *key) {
    NSString *resource=[@"preference.detail." stringByAppendingString:key];
    NSString *translated=localize(resource,nil);
    if(translated.length && ![translated isEqualToString:resource])return translated;
    NSDictionary *fallbacks=@{
        @"ui_theme":@"Changes apply across the launcher immediately.",
        @"custom_accent_color":@"Choose the launcher accent color.",
        @"custom_text_color":@"Choose the launcher text color.",
        @"multi_threaded":@"Enable multi-threaded downloads.",
        @"manage_runtime":@"Manage the Java runtimes available to the launcher.",
        @"debug_always_attached_jit":@"Controls the existing always-attached JIT option. Requires the universal JIT script option."
    };
    return fallbacks[key] ?: translated;
}

// Opt-in presentation only. Legacy preference controllers keep stock cells and layout.
// The public label/accessory getters still expose the SAME values/controls used by the binding code.
@interface AMERefinedPreferenceCell : UITableViewCell
@property(nonatomic,strong) NSLayoutConstraint *referenceRowMinimum;
@property(nonatomic, strong) UILabel *nameLabel;
@property(nonatomic, strong) UILabel *valueLabel;
@property(nonatomic, strong) UILabel *explanationLabel;
@property(nonatomic, strong) UIImageView *symbolView;
@property(nonatomic, strong) UIImageView *disclosure;
@property(nonatomic, strong) UIView *surface;
@property(nonatomic, strong) UIView *accessoryHost;
@property(nonatomic, strong) UIView *boundAccessory;
@property(nonatomic, strong) UIStackView *textStack;
@property(nonatomic, strong) UIStackView *headingRow;
@property(nonatomic, strong) UIStackView *bodyStack;
@property(nonatomic, strong) NSArray<NSLayoutConstraint *> *accessoryConstraints;
@property(nonatomic) UITableViewCellAccessoryType presentedAccessoryType;
@property(nonatomic) BOOL sectionHeading;
@property(nonatomic) BOOL sectionExpanded;
@property(nonatomic) BOOL destructive;
- (void)configureHeading:(BOOL)heading expanded:(BOOL)expanded first:(BOOL)first last:(BOOL)last explanation:(NSString *)explanation destructive:(BOOL)destructive;
- (void)refreshPresentation;
@end

@implementation AMERefinedPreferenceCell
- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)identifier {
    self = [super initWithStyle:UITableViewCellStyleDefault reuseIdentifier:identifier];
    if (!self) return nil;
    self.backgroundColor = UIColor.clearColor;
    self.contentView.backgroundColor = UIColor.clearColor;
    self.nameLabel = [[UILabel alloc] init];
    self.valueLabel = [[UILabel alloc] init];
    self.explanationLabel = [[UILabel alloc] init];
    for (UILabel *label in @[self.nameLabel, self.valueLabel, self.explanationLabel]) {
        label.numberOfLines = 0;
        label.adjustsFontForContentSizeCategory = YES;
        label.lineBreakMode = NSLineBreakByWordWrapping;
    }
    self.symbolView = [[UIImageView alloc] init];
    self.symbolView.contentMode = UIViewContentModeScaleAspectFit;
    self.symbolView.translatesAutoresizingMaskIntoConstraints = NO;
    self.symbolView.isAccessibilityElement = NO;
    self.disclosure = [[UIImageView alloc] init];
    self.disclosure.contentMode = UIViewContentModeScaleAspectFit;
    self.disclosure.translatesAutoresizingMaskIntoConstraints = NO;
    self.disclosure.isAccessibilityElement = NO;
    self.surface = [[UIView alloc] init];
    self.surface.translatesAutoresizingMaskIntoConstraints = NO;
    self.surface.layer.cornerRadius = 26;
    self.surface.layer.cornerCurve = kCACornerCurveContinuous;
    self.surface.clipsToBounds = YES;
    [self.contentView addSubview:self.surface];
    [[BackgroundManager sharedManager] applyEffectToView:self.surface];
    self.textStack = [[UIStackView alloc] initWithArrangedSubviews:@[self.nameLabel, self.valueLabel, self.explanationLabel]];
    self.textStack.axis = UILayoutConstraintAxisVertical;
    self.textStack.spacing = 4;
    self.accessoryHost = [[UIView alloc] init];
    self.accessoryHost.translatesAutoresizingMaskIntoConstraints = NO;
    self.headingRow = [[UIStackView alloc] initWithArrangedSubviews:@[self.symbolView, self.textStack, self.disclosure]];
    self.headingRow.alignment = UIStackViewAlignmentCenter;
    self.headingRow.spacing = 12;
    self.bodyStack = [[UIStackView alloc] initWithArrangedSubviews:@[self.headingRow, self.accessoryHost]];
    self.bodyStack.translatesAutoresizingMaskIntoConstraints = NO;
    self.bodyStack.axis = UILayoutConstraintAxisVertical;
    self.bodyStack.spacing = 10;
    [self.surface addSubview:self.bodyStack];
    UILayoutGuide *guide = self.contentView.layoutMarginsGuide;
    self.contentView.directionalLayoutMargins = NSDirectionalEdgeInsetsMake(0, 8, 0, 8);
    NSLayoutConstraint *width = [self.surface.widthAnchor constraintEqualToAnchor:guide.widthAnchor];
    width.priority = UILayoutPriorityDefaultHigh;
    NSLayoutConstraint *symbolWidth = [self.symbolView.widthAnchor constraintEqualToConstant:22];
    NSLayoutConstraint *disclosureWidth = [self.disclosure.widthAnchor constraintEqualToConstant:12];
    symbolWidth.priority = disclosureWidth.priority = 999; // UISV-hiding owns zero width when absent.
    [NSLayoutConstraint activateConstraints:@[
        [self.surface.leadingAnchor constraintGreaterThanOrEqualToAnchor:guide.leadingAnchor],
        [self.surface.trailingAnchor constraintLessThanOrEqualToAnchor:guide.trailingAnchor],
        [self.surface.centerXAnchor constraintEqualToAnchor:guide.centerXAnchor],
        [self.surface.widthAnchor constraintLessThanOrEqualToConstant:840], width,
        [self.surface.topAnchor constraintEqualToAnchor:self.contentView.topAnchor],
        [self.surface.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor],
        [self.surface.heightAnchor constraintGreaterThanOrEqualToConstant:56],
        [self.bodyStack.leadingAnchor constraintEqualToAnchor:self.surface.leadingAnchor constant:14],
        [self.bodyStack.trailingAnchor constraintEqualToAnchor:self.surface.trailingAnchor constant:-14],
        [self.bodyStack.topAnchor constraintEqualToAnchor:self.surface.topAnchor constant:12],
        [self.bodyStack.bottomAnchor constraintEqualToAnchor:self.surface.bottomAnchor constant:-12],
        symbolWidth, [self.symbolView.heightAnchor constraintEqualToConstant:22],
        disclosureWidth, [self.disclosure.heightAnchor constraintEqualToConstant:16]
    ]];
    // No second material in the selected state; native cell selection remains the original input path.
    UIView *selected = [[UIView alloc] init];
    selected.backgroundColor = UIColor.clearColor;
    self.selectedBackgroundView = selected;
    self.referenceRowMinimum=[self.surface.heightAnchor constraintGreaterThanOrEqualToConstant:56]; self.referenceRowMinimum.active=NO;
    [self refreshPresentation];
    return self;
}
// A global transparency pass may propose a full-row backdrop. Keep glass inside the bounded surface.
- (void)setBackgroundView:(UIView *)view { [super setBackgroundView:nil]; }
- (UILabel *)textLabel { return self.nameLabel; }
- (UILabel *)detailTextLabel { return self.valueLabel; }
- (UIImageView *)imageView { return self.symbolView; }
- (UIView *)accessoryView { return self.boundAccessory; }
- (UITableViewCellAccessoryType)accessoryType { return self.presentedAccessoryType; }
- (void)setAccessoryType:(UITableViewCellAccessoryType)type { self.presentedAccessoryType = type; }
- (void)setAccessoryView:(UIView *)view {
    if (self.boundAccessory == view) return;
    [NSLayoutConstraint deactivateConstraints:self.accessoryConstraints ?: @[]];
    [self.headingRow removeArrangedSubview:self.accessoryHost];
    [self.bodyStack removeArrangedSubview:self.accessoryHost];
    [self.accessoryHost removeFromSuperview];
    [self.boundAccessory removeFromSuperview];
    self.boundAccessory = view;
    self.accessoryConstraints = nil;
    if (!self.accessoryHost) return; // UIKit may invoke setters during superclass initialization.
    [self.bodyStack addArrangedSubview:self.accessoryHost];
    self.accessoryHost.hidden = (view == nil);
    if (!view) return;
    [self.accessoryHost addSubview:view];
    view.translatesAutoresizingMaskIntoConstraints = NO;
    BOOL nativeSwitch = [view isKindOfClass:UISwitch.class];
    if (nativeSwitch) {
        [self.bodyStack removeArrangedSubview:self.accessoryHost];
        [self.accessoryHost removeFromSuperview];
        [self.headingRow insertArrangedSubview:self.accessoryHost atIndex:2];
        self.accessoryConstraints = @[
            [view.leadingAnchor constraintEqualToAnchor:self.accessoryHost.leadingAnchor],
            [view.trailingAnchor constraintEqualToAnchor:self.accessoryHost.trailingAnchor],
            [view.centerYAnchor constraintEqualToAnchor:self.accessoryHost.centerYAnchor],
            [self.accessoryHost.heightAnchor constraintGreaterThanOrEqualToConstant:44]
        ];
    } else {
        self.accessoryConstraints = @[
            [view.leadingAnchor constraintEqualToAnchor:self.accessoryHost.leadingAnchor],
            [view.trailingAnchor constraintEqualToAnchor:self.accessoryHost.trailingAnchor],
            [view.topAnchor constraintEqualToAnchor:self.accessoryHost.topAnchor],
            [view.bottomAnchor constraintEqualToAnchor:self.accessoryHost.bottomAnchor],
            [view.heightAnchor constraintGreaterThanOrEqualToConstant:44]
        ];
    }
    [NSLayoutConstraint activateConstraints:self.accessoryConstraints];
}
- (void)configureHeading:(BOOL)heading expanded:(BOOL)expanded first:(BOOL)first last:(BOOL)last explanation:(NSString *)explanation destructive:(BOOL)destructive {
    self.sectionHeading = heading;
    self.sectionExpanded = expanded;
    self.destructive = destructive;
    self.explanationLabel.text = explanation;
    self.explanationLabel.hidden = !explanation.length;
    self.nameLabel.hidden = NO;
    self.surface.layer.maskedCorners = (first ? kCALayerMinXMinYCorner | kCALayerMaxXMinYCorner : 0)
        | (last ? kCALayerMinXMaxYCorner | kCALayerMaxXMaxYCorner : 0);
    // Keep the material's own clipping consistent with the connected group corners.
    for (UIView *backdrop in self.surface.subviews) {
        if ([backdrop isKindOfClass:UIVisualEffectView.class]) backdrop.layer.maskedCorners = self.surface.layer.maskedCorners;
    }
    self.nameLabel.adjustsFontSizeToFitWidth = NO;
    self.nameLabel.font = AmeUIFont(heading ? AmeUIFontRoleSectionHeading : AmeUIFontRoleBody);
    self.valueLabel.font = AmeUIFont(AmeUIFontRoleDescription);
    self.explanationLabel.font = AmeUIFont(AmeUIFontRoleDescription);
    self.accessoryHost.hidden = !self.boundAccessory;
    self.disclosure.hidden = !heading && self.presentedAccessoryType == UITableViewCellAccessoryNone;
    self.disclosure.image = [UIImage systemImageNamed:heading && expanded ? @"chevron.down" : @"chevron.right"];
    self.symbolView.hidden = !self.symbolView.image;
    if (self.boundAccessory) {
        self.isAccessibilityElement = NO;
        self.boundAccessory.accessibilityLabel = self.nameLabel.text;
        self.accessibilityElements = @[self.nameLabel, self.valueLabel, self.explanationLabel, self.boundAccessory];
    } else {
        self.accessibilityElements = nil;
        self.isAccessibilityElement = YES;
        self.accessibilityLabel = [@[self.nameLabel.text ?: @"", self.valueLabel.text ?: @"", explanation ?: @""] componentsJoinedByString:@". "];
        self.accessibilityTraits = heading ? UIAccessibilityTraitButton | UIAccessibilityTraitHeader : UIAccessibilityTraitButton;
        self.accessibilityValue = heading ? (expanded ? @"Expanded" : @"Collapsed") : nil;
        if (!self.userInteractionEnabled) self.accessibilityTraits |= UIAccessibilityTraitNotEnabled;
    }
    [self refreshPresentation];
}
- (NSString *)accessibilityLabel {
    if (!self.nameLabel || !self.isAccessibilityElement) return [super accessibilityLabel];
    NSMutableArray<NSString *> *parts = [NSMutableArray array];
    for (UILabel *label in @[self.nameLabel, self.valueLabel, self.explanationLabel]) {
        if (!label.hidden && label.text.length) [parts addObject:label.text];
    }
    return [parts componentsJoinedByString:@". "]; // Picker callbacks update the actual value label immediately.
}
- (void)refreshPresentation {
    self.backgroundView = nil; // Only the bounded managed surface owns material.
    self.backgroundColor = UIColor.clearColor;
    self.nameLabel.textColor = !self.userInteractionEnabled ? AmeUIDisabledColor()
        : self.destructive ? UIColor.systemRedColor : AmeUIPrimaryTextColor();
    self.valueLabel.textColor = self.userInteractionEnabled ? AmeUISecondaryTextColor() : AmeUIDisabledColor();
    self.explanationLabel.textColor = AmeUISecondaryTextColor();
    self.nameLabel.shadowColor = self.valueLabel.shadowColor = nil;
    self.symbolView.tintColor = self.destructive ? UIColor.systemRedColor : AmeUIAccentColor();
    self.disclosure.tintColor = AmeUISecondaryTextColor();
    self.surface.layer.borderWidth = AmeUIHairlineWidth(self);
    self.surface.layer.borderColor = AmeUIResolvedColor(AmeUIBorderColor(), self).CGColor;
    self.boundAccessory.tintColor = AmeUIAccentColor();
    if ([self.boundAccessory isKindOfClass:UITextField.class]) {
        UITextField *field = (UITextField *)self.boundAccessory;
        field.font = AmeUIFont(AmeUIFontRoleBody);
        field.adjustsFontForContentSizeCategory = YES;
        field.textColor = AmeUIPrimaryTextColor();
        field.backgroundColor = UIColor.clearColor;
    }
}
- (void)setHighlighted:(BOOL)highlighted animated:(BOOL)animated {
    [super setHighlighted:highlighted animated:animated];
    self.surface.layer.borderColor = AmeUIResolvedColor(highlighted ? AmeUIAccentColor() : AmeUIBorderColor(), self).CGColor;
}
- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];
    [self refreshPresentation];
}
@end

@interface PLPrefTableViewController()<UIContextMenuInteractionDelegate>{
    NSString *_currentSearchText;
}
@property(nonatomic) UIMenu* currentMenu;
- (void)configureRefinedCell:(UITableViewCell *)cell item:(NSDictionary *)item indexPath:(NSIndexPath *)indexPath;
@property(nonatomic) UIBarButtonItem *helpBtn;
@property(nonatomic, strong) UISearchController *searchController;
/// 搜索结果：filteredSections[0] 为扁平化的所有匹配项（忽略 section 归属）
@property(nonatomic, strong) NSArray<NSDictionary *> *filteredItems;

@end

@implementation PLPrefTableViewController

- (BOOL)usesRefinedSettingsPresentation { return NO; }
- (BOOL)usesReferenceTableGeometry { return NO; }
- (UISearchBar *)presentationSearchBar { return self.searchController.searchBar; }
- (void)endPresentationSearch {
    self.searchController.active = NO;
    self.searchController.searchBar.text = @"";
    [self updateSearchResultsForSearchController:self.searchController];
}

- (NSIndexPath *)sourceIndexPathForDisplayIndexPath:(NSIndexPath *)indexPath {
    return self.presentationRows ? self.presentationRows[indexPath.section][indexPath.row] : indexPath;
}
- (NSIndexPath *)displayIndexPathForSourceIndexPath:(NSIndexPath *)source {
    if (!self.presentationRows) return source;
    for (NSUInteger section=0; section<self.presentationRows.count; section++) {
        NSUInteger row = [self.presentationRows[section] indexOfObject:source];
        if (row != NSNotFound) return [NSIndexPath indexPathForRow:row inSection:section];
    }
    return nil;
}
- (NSDictionary *)preferenceItemAtDisplayIndexPath:(NSIndexPath *)indexPath {
    NSIndexPath *source = [self sourceIndexPathForDisplayIndexPath:indexPath];
    return self.prefContents[source.section][source.row];
}
- (NSString *)preferenceSectionAtDisplayIndexPath:(NSIndexPath *)indexPath {
    return self.prefSections[[self sourceIndexPathForDisplayIndexPath:indexPath].section];
}

- (void)refreshRefinedSettingsPresentation {
    if (!self.usesRefinedSettingsPresentation) return;
    self.tableView.backgroundColor = UIColor.clearColor;
    self.tableView.backgroundView = nil;
    self.tableView.alpha = 1;
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 64;
    self.tableView.sectionHeaderHeight = 8;
    self.tableView.estimatedSectionHeaderHeight = 8;
    self.tableView.sectionFooterHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedSectionFooterHeight = 60;
    for (UITableViewCell *cell in self.tableView.visibleCells) {
        if ([cell isKindOfClass:AMERefinedPreferenceCell.class]) [(AMERefinedPreferenceCell *)cell refreshPresentation];
    }
}

- (void)configureRefinedCell:(UITableViewCell *)cell item:(NSDictionary *)item indexPath:(NSIndexPath *)indexPath {
    if (![cell isKindOfClass:AMERefinedPreferenceCell.class]) return;
    if (self.presentationRows) {
        cell.contentView.directionalLayoutMargins = NSDirectionalEdgeInsetsZero;
        cell.imageView.image=nil;
        NSString *key=item[@"key"];
        if ([key isEqualToString:@"custom_accent_color"]) {
            id rawValue=self.getPreference(@"general",@"accent_color");
            NSString *value=[rawValue isKindOfClass:NSString.class]?rawValue:@"";
            cell.detailTextLabel.text=value.length?value:@"Use native default";
            cell.detailTextLabel.backgroundColor=UIColor.clearColor;
            cell.detailTextLabel.textColor=AmeUISecondaryTextColor();
        } else cell.detailTextLabel.backgroundColor=UIColor.clearColor;
    }
    BOOL heading = !self.presentationRows && !self.filteredItems && self.prefSections && indexPath.row == 0;
    BOOL first = indexPath.row == 0;
    BOOL last = indexPath.row == [self.tableView numberOfRowsInSection:indexPath.section] - 1;
    BOOL expanded = !self.presentationRows && !self.filteredItems && self.prefSectionsVisibility[indexPath.section].boolValue;
    NSString *explanation = nil;
    if (!self.filteredItems && !heading && self.prefDetailVisible && [item[@"hasDetail"] boolValue]
        && (item[@"type"] == self.typePickField || item[@"type"] == self.typeChildPane)) {
        explanation = self.usesReferenceTableGeometry ? MetallicReferencePreferenceDetail(item[@"key"]) : localize([NSString stringWithFormat:@"preference.detail.%@", item[@"key"]], nil);
    }
    [(AMERefinedPreferenceCell *)cell configureHeading:heading expanded:expanded first:first last:last
        explanation:explanation destructive:[item[@"destructive"] boolValue]];
    AMERefinedPreferenceCell *reference=(AMERefinedPreferenceCell *)cell;
    reference.referenceRowMinimum.active=NO;
    if(self.presentationRows) {
        CGFloat viewport=self.view.window.bounds.size.width; if(viewport<=0)viewport=UIScreen.mainScreen.bounds.size.width;
        CGFloat scale=viewport>=900?viewport/1536.0:.72;
        NSString *key=item[@"key"]; CGFloat height=[key isEqualToString:@"custom_accent_color"]?136:[key isEqualToString:@"announcement_preview_level"]?146:100;
        reference.referenceRowMinimum.constant=height*scale;
        reference.nameLabel.font=[[UIFontMetrics metricsForTextStyle:UIFontTextStyleBody] scaledFontForFont:[UIFont systemFontOfSize:24*scale]];
        reference.valueLabel.font=reference.nameLabel.font;
        reference.explanationLabel.font=[[UIFontMetrics metricsForTextStyle:UIFontTextStyleFootnote] scaledFontForFont:[UIFont systemFontOfSize:16*scale]];
        if(item[@"type"]==self.typePickField) {
            id current=self.getPreference([self preferenceSectionAtDisplayIndexPath:indexPath],item[@"key"]);
            NSUInteger selected=[item[@"pickKeys"] indexOfObject:current]; NSArray *labels=item[@"pickList"];
            if(selected<labels.count) reference.valueLabel.text=labels[selected];
        }
        if([key isEqualToString:@"announcement_preview_level"]) {
            reference.nameLabel.hidden=YES;
            reference.disclosure.image=[UIImage systemImageNamed:@"chevron.up.chevron.down"];
            reference.explanationLabel.text=@"How much detail announcements show on the home screen.";
            reference.explanationLabel.hidden=NO;
        }
        id accentValue=getPrefObject(@"general.accent_color");
        UIColor *accent=[accentValue isKindOfClass:NSString.class] && [accentValue length]?AmeUIAccentColor():UIColor.systemBlueColor;
        if([cell.accessoryView isKindOfClass:UISwitch.class]) ((UISwitch *)cell.accessoryView).onTintColor=accent;
    }

}

- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];
    if (self.usesRefinedSettingsPresentation && self.isViewLoaded) {
        [self refreshRefinedSettingsPresentation];
        if (previousTraitCollection && ![previousTraitCollection.preferredContentSizeCategory isEqual:self.traitCollection.preferredContentSizeCategory]) {
            // Refit existing rows without replacing controls or interrupting slider tracking with reloadData.
            [self.tableView beginUpdates];
            [self.tableView endUpdates];
        }
    }
}

- (id)init {
    self = [super init];
    [self initViewCreation];
    return self;
}

- (void)viewDidLoad
{
    [super viewDidLoad];

    self.tableView = [[UITableView alloc] initWithFrame:CGRectZero style:(self.usesReferenceTableGeometry ? UITableViewStylePlain : UITableViewStyleInsetGrouped)];
    self.tableView.keyboardDismissMode = UIScrollViewKeyboardDismissModeInteractive;
    if (self.prefSections) {
        self.prefSectionsVisibility = [[NSMutableArray<NSNumber *> alloc] initWithCapacity:self.prefSections.count];
        for (int i = 0; i < self.prefSections.count; i++) {
            [self.prefSectionsVisibility addObject:@(self.prefSectionsVisible)];
        }
    } else {
        // Display one singe section if prefSection is unspecified
        self.prefSectionsVisibility = (id)@[@YES];
    }

    // 搜索栏初始化（仅当 searchEnabled=YES 时启用，子类负责设置）
    if (self.searchEnabled) {
        self.searchController = [[UISearchController alloc] initWithSearchResultsController:nil];
        self.searchController.searchResultsUpdater = self;
        self.searchController.obscuresBackgroundDuringPresentation = NO;
        self.searchController.searchBar.placeholder = localize(@"i18n_str_844", nil);
        self.searchController.searchBar.autocapitalizationType = UITextAutocapitalizationTypeNone;
        self.searchController.searchBar.autocorrectionType = UITextAutocorrectionTypeNo;
        self.tableView.tableHeaderView = self.searchController.searchBar;
        self.definesPresentationContext = YES;
        _currentSearchText = @"";
    }

    // 适配自定义启动器背景：将当前视图控制器透明化，让全局背景（图片/视频）能够透出显示。
    // 放在 tableView 重新创建之后调用，确保 makeViewControllerTransparent 处理的是最终的 tableView。
    if (self.usesRefinedSettingsPresentation) [self refreshRefinedSettingsPresentation];
    else [[BackgroundManager sharedManager] makeViewControllerTransparent:self];

    // 监听背景 UI 效果变化通知：当用户在背景设置中切换毛玻璃/半透明或调整透明度时，
    // 重新调用 makeViewControllerTransparent 以应用最新的视觉效果，保证背景始终正确透出。
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(reapplyBackgroundEffect)
                                                 name:@"BackgroundUIEffectChanged"
                                               object:nil];
}

- (NSString *)currentSearchText {
    return _currentSearchText ?: @"";
}

#pragma mark - Search

- (void)updateSearchResultsForSearchController:(UISearchController *)searchController {
    NSString *query = [searchController.searchBar.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    _currentSearchText = query ?: @"";

    if (query.length == 0) {
        self.filteredItems = nil;
        [self.tableView reloadData];
        return;
    }

    // 扁平化所有 prefContents 中的设置项，按 title/key/icon/localizedTitle 模糊匹配
    NSMutableArray *results = [NSMutableArray array];
    NSString *lowerQuery = query.lowercaseString;
    for (int s = 0; s < self.prefContents.count; s++) {
        NSArray *section = self.prefContents[s];
        // 第 0 项是 section 头，跳过
        for (int r = (self.prefSections ? 1 : 0); r < section.count; r++) {
            NSDictionary *item = section[r];
            NSString *title = item[@"title"];
            if (!title) {
                title = [NSString stringWithFormat:@"preference.title.%@", item[@"key"]];
            }
            NSString *localizedTitle = localize(title, nil);
            NSString *key = item[@"key"] ?: @"";
            NSString *icon = item[@"icon"] ?: @"";
            // 匹配本地化标题、key、icon 名、原文标题
            if ([localizedTitle.lowercaseString containsString:lowerQuery] ||
                [key.lowercaseString containsString:lowerQuery] ||
                [icon.lowercaseString containsString:lowerQuery] ||
                [title.lowercaseString containsString:lowerQuery]) {
                // 记录原始 section 和 row，便于点击时定位
                NSMutableDictionary *matched = [item mutableCopy];
                matched[@"__origSection"] = @(s);
                matched[@"__origRow"] = @(r);
                matched[@"__localizedTitle"] = localizedTitle;
                [results addObject:matched];
            }
        }
    }
    self.filteredItems = results;
    [self.tableView reloadData];
}

- (UIBarButtonItem *)drawHelpButton {
    if (!self.helpBtn) {
        self.helpBtn = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"questionmark.circle"] style:UIBarButtonItemStyleDone target:self action:@selector(toggleDetailVisibility)];
    }
    return self.helpBtn;
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];

    // Put navigation buttons back in place if we're first of the navigation controller
    if (self.hasDetail && self.navigationController) {
        self.navigationItem.rightBarButtonItems = @[[self drawHelpButton]];
    }

    if (self.presentationRows) { [self.tableView reloadData]; return; }

    // Scan for child pane cells and reload them
    // FIXME: any cheaper operations?
    NSMutableArray *indexPaths = [[NSMutableArray alloc] init];
    for (int section = 0; section < self.prefContents.count; section++) {
        if (!self.prefSectionsVisibility[section].boolValue) {
            continue;
        }
        for (int row = 0; row < self.prefContents[section].count; row++) {
            if (self.prefContents[section][row][@"type"] == self.typeChildPane) {
                [indexPaths addObject:[NSIndexPath indexPathForRow:row inSection:section]];
            }
        }
    }
    [self.tableView reloadRowsAtIndexPaths:indexPaths withRowAnimation:UITableViewRowAnimationNone];
}

#pragma mark UITableView

- (void)toggleDetailVisibility {
    self.prefDetailVisible = !self.prefDetailVisible;
    [self.tableView reloadData];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    // 搜索结果为单一扁平 section
    if (self.filteredItems) return 1;
    if (self.presentationRows) return self.presentationRows.count;
    return self.prefSectionsVisibility.count;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    // 搜索结果模式
    if (self.filteredItems) {
        return self.filteredItems.count;
    }
    if (self.presentationRows) return self.presentationRows[section].count;
    if (self.prefSectionsVisibility[section].boolValue) {
        return self.prefContents[section].count;
    }
    return 1;
}

- (UITableViewCell *)tableView:(nonnull UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    // 搜索结果模式：使用扁平化的 filteredItems
    if (self.filteredItems) {
        NSDictionary *item = self.filteredItems[indexPath.row];
        NSString *cellID = self.usesRefinedSettingsPresentation ? @"refinedSearchResultCell" : @"searchResultCell";
        UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:cellID];
        if (cell == nil) {
            Class cellClass = self.usesRefinedSettingsPresentation ? AMERefinedPreferenceCell.class : UITableViewCell.class;
            cell = [[cellClass alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:cellID];
            cell.textLabel.adjustsFontSizeToFitWidth = YES;
            cell.textLabel.numberOfLines = 0;
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
            cell.selectionStyle = UITableViewCellSelectionStyleDefault;
        }
        cell.textLabel.text = item[@"__localizedTitle"];
        // 副标题显示所属 section
        NSNumber *origSection = item[@"__origSection"];
        if (origSection && self.prefSections && origSection.intValue < (int)self.prefSections.count) {
            NSString *sectionKey = self.prefSections[origSection.intValue];
            cell.detailTextLabel.text = localize(([NSString stringWithFormat:@"preference.section.%@", sectionKey]), nil);
        } else {
            cell.detailTextLabel.text = nil;
        }
        cell.imageView.image = [UIImage systemImageNamed:item[@"icon"]];
        cell.imageView.tintColor = [item[@"destructive"] boolValue] ? UIColor.systemRedColor : nil;
        cell.userInteractionEnabled = YES;
        if (self.usesRefinedSettingsPresentation) [self configureRefinedCell:cell item:item indexPath:indexPath];
        return cell;
    }

    NSDictionary *item = [self preferenceItemAtDisplayIndexPath:indexPath];

    NSString *cellID;
    UITableViewCellStyle cellStyle;
    if (item[@"type"] == self.typeChildPane || item[@"type"] == self.typePickField) {
        cellID = @"cellValue1";
        cellStyle = UITableViewCellStyleValue1;
    } else {
        cellID = @"cellSubtitle";
        cellStyle = UITableViewCellStyleSubtitle;
    }

    if (self.usesRefinedSettingsPresentation) cellID = [@"refined." stringByAppendingString:cellID];
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:cellID];
    if (cell == nil) {
        Class cellClass = self.usesRefinedSettingsPresentation ? AMERefinedPreferenceCell.class : UITableViewCell.class;
        cell = [[cellClass alloc] initWithStyle:cellStyle reuseIdentifier:cellID];
        cell.textLabel.adjustsFontSizeToFitWidth = YES;
        cell.textLabel.numberOfLines = 0;
        cell.textLabel.lineBreakMode = NSLineBreakByWordWrapping;
        cell.detailTextLabel.numberOfLines = 0;
        cell.detailTextLabel.lineBreakMode = NSLineBreakByWordWrapping;
    }
    // Reset cell properties, as it could be reused
    cell.accessoryType = UITableViewCellAccessoryNone;
    cell.accessoryView = nil;
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    cell.textLabel.textColor = nil;
    cell.detailTextLabel.text = nil;

    NSString *key = item[@"key"];
    if (!self.presentationRows && indexPath.row == 0 && self.prefSections) {
        key = [self preferenceSectionAtDisplayIndexPath:indexPath];
        cell.selectionStyle = UITableViewCellSelectionStyleDefault;
        cell.textLabel.text = localize(([NSString stringWithFormat:@"preference.section.%@", key]), nil);
    } else {
        CreateView createView = item[@"type"];
        createView(cell, [self preferenceSectionAtDisplayIndexPath:indexPath], key, item);
        if (cell.accessoryView) {
            objc_setAssociatedObject(cell.accessoryView, @"section", [self preferenceSectionAtDisplayIndexPath:indexPath], OBJC_ASSOCIATION_ASSIGN);
            objc_setAssociatedObject(cell.accessoryView, @"key", key, OBJC_ASSOCIATION_ASSIGN);
            objc_setAssociatedObject(cell.accessoryView, @"item", item, OBJC_ASSOCIATION_ASSIGN);
        }
        cell.textLabel.text = localize((item[@"title"] ? item[@"title"] :
            [NSString stringWithFormat:@"preference.title.%@", key]), nil);
    }

    // Preserve translated labels; fallback only the reported first-party identifiers.
    NSString *titleKey=[@"preference.title." stringByAppendingString:key];
    if ([cell.textLabel.text isEqualToString:titleKey]) {
        NSDictionary *titles=@{@"debug_universal_script_jit":@"Universal JIT script",@"debug_always_attached_jit":@"Always-attached JIT"};
        if(titles[key])cell.textLabel.text=titles[key];
    }
    // Set general properties
    BOOL destructive = [item[@"destructive"] boolValue];
    cell.imageView.tintColor = destructive ? UIColor.systemRedColor : nil;
    cell.imageView.image = [UIImage systemImageNamed:item[@"icon"]];
    
    if (cellStyle != UITableViewCellStyleValue1) {
        cell.detailTextLabel.text = nil;
        if ([item[@"hasDetail"] boolValue] && self.prefDetailVisible) {
            cell.detailTextLabel.text = self.usesReferenceTableGeometry ? MetallicReferencePreferenceDetail(key) : localize(([NSString stringWithFormat:@"preference.detail.%@", key]), nil);
        }
    }

    // Check if one has enable condition and call if it does
    BOOL(^checkEnable)(void) = item[@"enableCondition"];
    cell.userInteractionEnabled = !checkEnable || checkEnable();
    cell.textLabel.enabled = cell.detailTextLabel.enabled = cell.userInteractionEnabled;
    [(id)cell.accessoryView setEnabled:cell.userInteractionEnabled];

    if (self.usesRefinedSettingsPresentation) [self configureRefinedCell:cell item:item indexPath:indexPath];
    return cell;
}

#pragma mark initViewCreation, showAlert, checkWarn

- (void)initViewCreation {
    __weak PLPrefTableViewController *weakSelf = self;

    self.typeButton = ^void(UITableViewCell *cell, NSString *section, NSString *key, NSDictionary *item) {
        BOOL destructive = [item[@"destructive"] boolValue];
        cell.selectionStyle = UITableViewCellSelectionStyleGray;
        cell.textLabel.textColor = destructive ? UIColor.systemRedColor : weakSelf.view.tintColor;
    };

    self.typeChildPane = ^void(UITableViewCell *cell, NSString *section, NSString *key, NSDictionary *item) {
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        cell.selectionStyle = UITableViewCellSelectionStyleGray;
        id value = weakSelf.getPreference(section, key);
        if ([value isKindOfClass:[NSString class]]) {
            cell.detailTextLabel.text = value;
        } else if ([value isKindOfClass:[NSNumber class]]) {
            cell.detailTextLabel.text = [value boolValue] ? @"YES" : @"NO";
        } else {
            cell.detailTextLabel.text = [value description];
        }
    };

    self.typeTextField = ^void(UITableViewCell *cell, NSString *section, NSString *key, NSDictionary *item) {
        Class cls = item[@"customClass"];
        if (!cls) cls = UITextField.class;
        UITextField *view = [[cls alloc] initWithFrame:CGRectMake(0, 0, cell.bounds.size.width / 2.1, cell.bounds.size.height)];
        [view addTarget:view action:@selector(resignFirstResponder) forControlEvents:UIControlEventEditingDidEndOnExit];
        view.adjustsFontSizeToFitWidth = YES;
        view.autocorrectionType = UITextAutocorrectionTypeNo;
        view.autocapitalizationType = UITextAutocapitalizationTypeNone;
        view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleLeftMargin;
        //view.contentVerticalAlignment = UIControlContentVerticalAlignmentTop;
        view.delegate = weakSelf;
        //view.nonEditingLinebreakMode = NSLineBreakByCharWrapping;
        view.returnKeyType = UIReturnKeyDone;
        view.textAlignment = NSTextAlignmentRight;
        view.placeholder = localize((item[@"placeholder"] ? item[@"placeholder"] :
            [NSString stringWithFormat:@"preference.placeholder.%@", key]), nil);
        view.text = weakSelf.getPreference(section, key);
        cell.accessoryView = view;
    };

    self.typePickField = ^void(UITableViewCell *cell, NSString *section, NSString *key, NSDictionary *item) {
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        cell.selectionStyle = UITableViewCellSelectionStyleGray;
        id value = weakSelf.getPreference(section, key);
        if ([value isKindOfClass:[NSString class]]) {
            cell.detailTextLabel.text = value;
        } else if ([value isKindOfClass:[NSNumber class]]) {
            cell.detailTextLabel.text = [value boolValue] ? @"YES" : @"NO";
        } else {
            cell.detailTextLabel.text = [value description];
        }
    };

    self.typeSlider = ^void(UITableViewCell *cell, NSString *section, NSString *key, NSDictionary *item) {
        DBNumberedSlider *view = [[DBNumberedSlider alloc] initWithFrame:CGRectMake(0, 0, cell.bounds.size.width / 2.1, cell.bounds.size.height)];
        [view addTarget:weakSelf action:@selector(sliderMoved:) forControlEvents:UIControlEventValueChanged];
        view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleLeftMargin;
        view.minimumValue = [item[@"min"] intValue];
        view.maximumValue = [item[@"max"] intValue];
        view.continuous = YES;
        view.value = [weakSelf.getPreference(section, key) intValue];
        cell.accessoryView = view;
    };

    self.typeSwitch = ^void(UITableViewCell *cell, NSString *section, NSString *key, NSDictionary *item) {
        UISwitch *view = [[UISwitch alloc] init];
        NSArray *customSwitchValue = item[@"customSwitchValue"];
        if (customSwitchValue == nil) {
            [view setOn:[weakSelf.getPreference(section, key) boolValue] animated:NO];
        } else {
            [view setOn:[weakSelf.getPreference(section, key) isEqualToString:customSwitchValue[1]] animated:NO];
        }
        [view addTarget:weakSelf action:@selector(switchChanged:) forControlEvents:UIControlEventValueChanged];
        cell.accessoryView = view;
    };
}

- (void)showAlertOnView:(UIView *)view title:(NSString *)title message:(NSString *)message {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleActionSheet];
    alert.popoverPresentationController.sourceView = view;
    alert.popoverPresentationController.sourceRect = view.bounds;
    UIAlertAction *ok = [UIAlertAction actionWithTitle:localize(@"OK", nil) style:UIAlertActionStyleCancel handler:nil];
    [alert addAction:ok];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)checkWarn:(UIView *)view {
    NSDictionary *item = objc_getAssociatedObject(view, @"item");
    NSString *key = item[@"key"];

    BOOL(^isWarnable)(UIView *) = item[@"warnCondition"];
    NSString *warnKey = item[@"warnKey"];
    // Display warning if: warn condition is met and either one of these:
    // - does not have warnKey, always warn
    // - has warnKey and its value is YES, warn once and set it to NO
    if (isWarnable && isWarnable(view) && (!warnKey || [self.getPreference(@"warnings", warnKey) boolValue])) {
        if (warnKey) {
            self.setPreference(@"warnings", warnKey, @NO);
        }

        NSString *message = localize(([NSString stringWithFormat:@"preference.warn.%@", key]), nil);
        [self showAlertOnView:view title:localize(@"Warning", nil) message:message];
    }
}

#pragma mark Control event handlers

- (void)sliderMoved:(DBNumberedSlider *)sender {
    [self checkWarn:sender];
    NSString *section = objc_getAssociatedObject(sender, @"section");
    NSString *key = objc_getAssociatedObject(sender, @"key");

    sender.value = (int)sender.value;
    self.setPreference(section, key, @(sender.value));
}

- (void)switchChanged:(UISwitch *)sender {
    [self checkWarn:sender];
    NSDictionary *item = objc_getAssociatedObject(sender, @"item");
    NSString *section = objc_getAssociatedObject(sender, @"section");
    NSString *key = item[@"key"];

    // Special switches may define custom value instead of NO/YES
    NSArray *customSwitchValue = item[@"customSwitchValue"];
    self.setPreference(section, key, customSwitchValue ?
        customSwitchValue[sender.isOn] : @(sender.isOn));
    MetallicPlayUIFeedback(@"toggle");

    void(^invokeAction)(BOOL) = item[@"action"];
    if (invokeAction) {
        invokeAction(sender.isOn);
    }

    // Some settings may affect the availability of other settings
    // In this case, a switch may request to reload to apply user interaction change
    if ([item[@"requestReload"] boolValue]) {
        // TODO: only reload needed rows
        [self.tableView reloadData];
    }
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:NO];

    // 搜索结果模式：跳转到原始 section 并展开该 section
    if (self.filteredItems) {
        NSDictionary *item = self.filteredItems[indexPath.row];
        NSNumber *origSection = item[@"__origSection"];
        NSNumber *origRow = item[@"__origRow"];
        if (!origSection || !origRow) return;

        // 关闭搜索并恢复原始布局
        // 注意：UISearchController 没有 setActive:animated:，用 active 属性替代
        self.searchController.active = NO;
        self.filteredItems = nil;
        _currentSearchText = @"";

        NSIndexPath *source = [NSIndexPath indexPathForRow:origRow.integerValue inSection:origSection.integerValue];
        if (origSection.integerValue < self.prefSectionsVisibility.count) self.prefSectionsVisibility[origSection.integerValue] = @YES;
        NSIndexPath *visible = [self displayIndexPathForSourceIndexPath:source];
        if (!visible) { self.presentationRows = @[@[source]]; visible = [NSIndexPath indexPathForRow:0 inSection:0]; }
        [self.tableView reloadData];
        [self.tableView scrollToRowAtIndexPath:visible atScrollPosition:UITableViewScrollPositionMiddle animated:NO];
        dispatch_async(dispatch_get_main_queue(), ^{ [self tableView:tableView didSelectRowAtIndexPath:visible]; });
        return;
    }

    if (!self.presentationRows && indexPath.row == 0 && self.prefSections) {
        self.prefSectionsVisibility[indexPath.section] = @(![self.prefSectionsVisibility[indexPath.section] boolValue]);
        [tableView reloadSections:[NSIndexSet indexSetWithIndex:indexPath.section] withRowAnimation:(self.usesRefinedSettingsPresentation && UIAccessibilityIsReduceMotionEnabled() ? UITableViewRowAnimationNone : UITableViewRowAnimationFade)];
        return;
    }

    NSDictionary *item = [self preferenceItemAtDisplayIndexPath:indexPath];

    // Search forwards programmatically, so UIKit cannot enforce the disabled cell's touch gate.
    // Consult the existing condition; do not invent or change any setting's availability rule.
    if (self.usesRefinedSettingsPresentation) {
        BOOL(^checkEnable)(void) = item[@"enableCondition"];
        if (checkEnable && !checkEnable()) return;
    }

    if (item[@"type"] == self.typeButton) {
        [self tableView:tableView invokeActionWithPromptAtIndexPath:indexPath];
        return;
    } else if (item[@"type"] == self.typeChildPane) {
        [self tableView:tableView openChildPaneAtIndexPath:indexPath];
        return;
    } else if (item[@"type"] == self.typePickField) {
        [self tableView:tableView openPickerAtIndexPath:indexPath];
        return;
    } else if (realUIIdiom != UIUserInterfaceIdiomTV) {
        return;
    }

    // userInterfaceIdiom = tvOS
    UITableViewCell *cell = [tableView cellForRowAtIndexPath:indexPath];
    if (item[@"type"] == self.typeSwitch) {
        UISwitch *view = (id)cell.accessoryView;
        view.on = !view.isOn;
        [view sendActionsForControlEvents:UIControlEventValueChanged];
    }
}

#pragma mark External UITableView functions

- (void)tableView:(UITableView *)tableView openChildPaneAtIndexPath:(NSIndexPath *)indexPath {
    NSDictionary *item = [self preferenceItemAtDisplayIndexPath:indexPath];
    UIViewController *vc = [item[@"class"] new];
    if ([item[@"canDismissWithSwipe"] boolValue]) {
        [self.navigationController pushViewController:vc animated:YES];
    } else {
        UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:vc];
        nav.navigationBar.prefersLargeTitles = YES;
        nav.modalInPresentation = YES;
        [self.navigationController presentViewController:nav animated:YES completion:nil];
    }
}

- (void)tableView:(UITableView *)tableView openPickerAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView cellForRowAtIndexPath:indexPath];
    if (!cell || self.presentedViewController) return;
    NSDictionary *item = [self preferenceItemAtDisplayIndexPath:indexPath];
    NSString *section = [self preferenceSectionAtDisplayIndexPath:indexPath];
    BOOL (^enabled)(void) = item[@"enableCondition"];
    if (enabled && !enabled()) return;
    NSArray *keys = item[@"pickKeys"], *labels = item[@"pickList"];
    id selected = self.getPreference(section,item[@"key"]);
    UIAlertController *menu = [UIAlertController alertControllerWithTitle:cell.textLabel.text message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    for (NSUInteger i=0; i<MIN(keys.count,labels.count); i++) {
        id value = keys[i];
        NSString *title = [selected isEqual:value] ? [@"✓ " stringByAppendingString:labels[i]] : labels[i];
        [menu addAction:[UIAlertAction actionWithTitle:title style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            self.setPreference(section,item[@"key"],value);
            void (^originalAction)(NSString *) = item[@"action"]; if (originalAction) originalAction(value);
            [self.tableView reloadData];
        }]];
    }
    [menu addAction:[UIAlertAction actionWithTitle:localize(@"Cancel",nil) style:UIAlertActionStyleCancel handler:nil]];
    menu.popoverPresentationController.sourceView = cell;
    menu.popoverPresentationController.sourceRect = cell.bounds;
    [self presentViewController:menu animated:YES completion:nil];
}

- (void)tableView:(UITableView *)tableView invokeActionWithPromptAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *view = [self.tableView cellForRowAtIndexPath:indexPath];
    NSDictionary *item = [self preferenceItemAtDisplayIndexPath:indexPath];
    NSString *key = item[@"key"];

    if ([item[@"showConfirmPrompt"] boolValue]) {
        BOOL destructive = [item[@"destructive"] boolValue];
        NSString *title = localize(@"preference.title.confirm", nil);
        NSString *message = localize(([NSString stringWithFormat:@"preference.title.confirm.%@", key]), nil);
        UIAlertController *confirmAlert = [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleActionSheet];
        confirmAlert.popoverPresentationController.sourceView = view;
        confirmAlert.popoverPresentationController.sourceRect = view.bounds;
        UIAlertAction *ok = [UIAlertAction actionWithTitle:localize(@"OK", nil) style:destructive?UIAlertActionStyleDestructive:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
            [self tableView:tableView invokeActionAtIndexPath:indexPath];
        }];
        UIAlertAction *cancel = [UIAlertAction actionWithTitle:localize(@"Cancel", nil) style:UIAlertActionStyleCancel handler:nil];
        [confirmAlert addAction:cancel];
        [confirmAlert addAction:ok];
        [self presentViewController:confirmAlert animated:YES completion:nil];
    } else {
        [self tableView:tableView invokeActionAtIndexPath:indexPath];
    }
}

- (void)tableView:(UITableView *)tableView invokeActionAtIndexPath:(NSIndexPath *)indexPath {
    NSDictionary *item = [self preferenceItemAtDisplayIndexPath:indexPath];
    NSString *key = item[@"key"];

    void(^invokeAction)(void) = item[@"action"];
    if (invokeAction) {
        invokeAction();
    }

    // 对于typeButton类型的操作，不显示done提示
    if (item[@"type"] != self.typeButton) {
        UIView *view = [self.tableView cellForRowAtIndexPath:indexPath];
        NSString *title = localize(([NSString stringWithFormat:@"preference.title.done.%@", key]), nil);
        [self showAlertOnView:view title:title message:nil];
    }
}

#pragma mark UITextField

- (void)textFieldDidEndEditing:(UITextField *)sender {
    [self checkWarn:sender];
    NSString *section = objc_getAssociatedObject(sender, @"section");
    NSString *key = objc_getAssociatedObject(sender, @"key");

    self.setPreference(section, key, sender.text);
}

/// 重新应用背景效果：当 BackgroundUIEffectChanged 通知到达时调用，
/// 通过 BackgroundManager 重新设置当前视图控制器的透明度/毛玻璃效果，
/// 确保 tableView 背景透明、全局背景能够正常透出。
- (void)reapplyBackgroundEffect {
    if (self.usesRefinedSettingsPresentation) [self refreshRefinedSettingsPresentation];
    else [[BackgroundManager sharedManager] makeViewControllerTransparent:self];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

@end
