#import "utils.h"
#import "ModVersionViewController.h"
#import "installer/modpack/ModrinthAPI.h"
#import "installer/modpack/CurseForgeAPI.h"
#import "ModVersion.h"
#import "ModVersionTableViewCell.h"
#import "AssetDetailHeaderView.h"
#import "BackgroundManager.h"

// ============================================================================
// Download-source constants (match ModVersion.apiSource: 1=Modrinth, 2=CurseForge).
// ============================================================================
static const NSInteger kSourceModrinth    = 1;
static const NSInteger kSourceCurseForge  = 2;

// ============================================================================
// Sort-mode constants (based on FCL/ZL2 sort options).
// ============================================================================
static NSString *const kSortRelevance = @"relevance"; // Relevance (preserve API order).
static NSString *const kSortDownloads = @"downloads"; // Downloads (not available per version; fall back to API order).
static NSString *const kSortUpdated   = @"updated";   // Recently updated (datePublished descending).
static NSString *const kSortCreated   = @"created";   // Creation date (datePublished ascending).

// Sort-option display labels (one-to-one with the constants, rendered as chips).
static NSArray<NSDictionary *> *SortOptionItems(void) {
    static NSArray *items = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        items = @[
            @{ @"key": kSortRelevance, @"title": localize(@"i18n_str_162", nil) },
            @{ @"key": kSortDownloads, @"title": localize(@"i18n_str_32", nil) },
            @{ @"key": kSortUpdated,   @"title": localize(@"i18n_str_33", nil) },
            @{ @"key": kSortCreated,   @"title": localize(@"i18n_str_34", nil) },
        ];
    });
    return items;
}

@interface ModVersionViewController () <UITableViewDataSource, UITableViewDelegate>

// Main table view (displays the version list).
@property (nonatomic, strong) UITableView *tableView;

// ===== Side filter panel (based on the horizontally scrolling chip filter bar in FCL/ZL2) =====
// Filter panel container (translucent + blur background, fixed above the tableView and does not scroll with the list).
@property (nonatomic, strong) UIView *filterContainerView;
// Main vertical stack (contains four filter rows: source / version / loader / sort).
@property (nonatomic, strong) UIStackView *filterMainStack;

// --- Download-source filter row ---
@property (nonatomic, strong) UIScrollView *sourceScrollView;   // Horizontal scrolling container.
@property (nonatomic, strong) UIStackView  *sourceChipStack;    // Chips arranged horizontally.

// --- Game-version filter row ---
@property (nonatomic, strong) UIScrollView *versionScrollView;
@property (nonatomic, strong) UIStackView  *versionChipStack;

// --- Mod-loader filter row ---
@property (nonatomic, strong) UIScrollView *loaderScrollView;
@property (nonatomic, strong) UIStackView  *loaderChipStack;

// --- Sort-mode filter row ---
@property (nonatomic, strong) UIScrollView *sortScrollView;
@property (nonatomic, strong) UIStackView  *sortChipStack;

// ===== Currently selected filter state =====
@property (nonatomic, assign) NSInteger selectedSource;  // 1=Modrinth, 2=CurseForge
@property (nonatomic, copy)   NSString *selectedSort;    // Sort-mode key.

// ===== Data source =====
@property (nonatomic, strong) NSArray<ModVersion *> *allVersions;
@property (nonatomic, strong) NSArray<ModVersion *> *filteredVersions;

// Available filter options (dynamically extracted from version data).
@property (nonatomic, strong) NSArray<NSString *> *availableGameVersions;
@property (nonatomic, strong) NSArray<NSString *> *availableLoaders;

// Currently selected version / loader ("All" means no filter).
@property (nonatomic, strong) NSString *selectedGameVersion;
@property (nonatomic, strong) NSString *selectedLoader;

// Project-details header (cover image/title/author/download count/tags/description, filling the missing information).
@property (nonatomic, strong) AssetDetailHeaderView *detailHeaderView;

@end

@implementation ModVersionViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = self.modItem.displayName;
    self.view.backgroundColor = [UIColor systemBackgroundColor];
    // Adapt to the custom launcher background: make this view controller transparent so the global background image/blur shows through.
    [[BackgroundManager sharedManager] makeViewControllerTransparent:self];

    // Initialize filter state (Modrinth source + relevance sort by default).
    // Key fix (preserve source for CurseForge search results): the version page prioritizes the API source from the search result
    // (defaults to CurseForge when apiSource=2); otherwise a CurseForge numeric ID would be sent to Modrinth and no versions would load.
    self.selectedSource = (self.apiSource == kSourceCurseForge) ? kSourceCurseForge : kSourceModrinth;
    self.selectedSort = kSortRelevance;

    [self setupSideFilterPanel];
    [self setupTableView];
    [self setupActivityIndicator];
    [self setupDetailHeader];

    // Make the tableView background transparent so it does not obscure the global background.
    self.tableView.backgroundColor = [UIColor clearColor];
    self.tableView.backgroundView = nil;

    [self fetchVersionsFromCurrentSource];

    // Listen for background-effect changes and reapply transparency when the background changes.
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(reapplyBackgroundEffect)
                                                 name:@"BackgroundUIEffectChanged"
                                               object:nil];
}

- (void)reapplyBackgroundEffect {
    // Make this view controller transparent again when the background effect changes.
    [[BackgroundManager sharedManager] makeViewControllerTransparent:self];
    // Reset the tableView background to transparent so the global background still shows after an effect change.
    self.tableView.backgroundColor = [UIColor clearColor];
    self.tableView.backgroundView = nil;
}

- (void)dealloc {
    // Remove the notification observer to prevent a crash from receiving notifications after dealloc.
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

#pragma mark - Detail Header (project information)

/// Creates and configures the project-details header view and sets it as tableView.tableHeaderView.
/// Adds previously missing project cover image/title/author/download count/tags/description to the version page.
- (void)setupDetailHeader {
    self.detailHeaderView = [[AssetDetailHeaderView alloc] init];

    // Recalculate header height when the description is expanded/collapsed (use weak to avoid a retain cycle).
    __weak typeof(self) weakSelf = self;
    self.detailHeaderView.onSizeChanged = ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (strongSelf) [strongSelf updateTableHeaderHeight];
    };

    // Populate with the modItem data from the search stage (no additional API call required).
    [self.detailHeaderView configureWithIconURL:self.modItem.iconURL
                                          title:self.modItem.displayName
                                         author:self.modItem.author
                                      downloads:self.modItem.downloads
                                          likes:self.modItem.likes
                                descriptionText:self.modItem.modDescription
                                    categories:self.modItem.categories
                                   lastUpdated:self.modItem.lastUpdated
                           placeholderSymbolName:@"puzzlepiece.extension.fill"
                               placeholderColor:[UIColor systemOrangeColor]];

    [self updateTableHeaderHeight];
    self.tableView.tableHeaderView = self.detailHeaderView;
}

/// Recalculates and refreshes the tableHeaderView height (called in viewDidLayoutSubviews and when the description expands/collapses).
- (void)updateTableHeaderHeight {
    if (!self.detailHeaderView) return;
    CGFloat width = self.tableView.bounds.size.width;
    if (width <= 0) width = self.view.bounds.size.width;
    if (width <= 0) width = [UIScreen mainScreen].bounds.size.width;
    CGFloat height = [self.detailHeaderView fittingHeightForWidth:width];
    CGRect frame = self.detailHeaderView.frame;
    if (fabs(frame.size.height - height) < 1) return; // Skip if the height has not changed.
    frame.size.height = height;
    self.detailHeaderView.frame = frame;
    // Reassign to trigger the tableView to lay out the header again.
    self.tableView.tableHeaderView = self.detailHeaderView;
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    // The tableView width is known only after the first layout; update the header height then.
    if (self.detailHeaderView) {
        [self updateTableHeaderHeight];
    }
}

#pragma mark - Side filter panel (based on FCL/ZL2 horizontally scrolling chips)

/// Creates the side filter panel: four rows of horizontally scrolling chips (source / game version / loader / sort mode).
/// Based on the FCL Android filter bar: one row per category, icon + label prefix, horizontally scrolling chips,
/// selected item highlighted (theme-color background + white text), unselected items with translucent backgrounds + light borders.
- (void)setupSideFilterPanel {
    // ===== Filter panel container (translucent + blur, fixed at the top and does not scroll with the list) =====
    self.filterContainerView = [[UIView alloc] init];
    self.filterContainerView.translatesAutoresizingMaskIntoConstraints = NO;
    self.filterContainerView.backgroundColor = [[UIColor whiteColor] colorWithAlphaComponent:0.06];
    self.filterContainerView.layer.cornerRadius = 14;
    self.filterContainerView.layer.cornerCurve = kCACornerCurveContinuous;
    self.filterContainerView.layer.borderWidth = 0.5;
    self.filterContainerView.layer.borderColor = [[UIColor whiteColor] colorWithAlphaComponent:0.10].CGColor;
    [self.view addSubview:self.filterContainerView];
    // Apply the blur background effect to match the launcher's overall style.
    [[BackgroundManager sharedManager] applyEffectToView:self.filterContainerView];

    // ===== Main vertical stack (four filter rows, each = icon label + horizontally scrolling chips) =====
    self.filterMainStack = [[UIStackView alloc] init];
    self.filterMainStack.translatesAutoresizingMaskIntoConstraints = NO;
    self.filterMainStack.axis = UILayoutConstraintAxisVertical;
    self.filterMainStack.spacing = 4;
    self.filterMainStack.alignment = UIStackViewAlignmentFill;
    [self.filterContainerView addSubview:self.filterMainStack];

    // ----- Row 1: download source (Modrinth / CurseForge) -----
    {
        UIScrollView *scrollOut = nil;
        UIStackView *chipOut = nil;
        UIStackView *sourceRow = [self createFilterRowWithIconName:@"globe"
                                                             label:localize(@"i18n_str_462", nil)
                                                        scrollStackOut:&scrollOut
                                                          chipStackOut:&chipOut];
        self.sourceScrollView = scrollOut;
        self.sourceChipStack = chipOut;
        [self.filterMainStack addArrangedSubview:sourceRow];
    }
    [self rebuildSourceChips];

    // ----- Row 2: game version (populated dynamically; initially displays "Loading") -----
    {
        UIScrollView *scrollOut = nil;
        UIStackView *chipOut = nil;
        UIStackView *versionRow = [self createFilterRowWithIconName:@"gamecontroller.fill"
                                                              label:localize(@"i18n_str_39", nil)
                                                         scrollStackOut:&scrollOut
                                                           chipStackOut:&chipOut];
        self.versionScrollView = scrollOut;
        self.versionChipStack = chipOut;
        [self.filterMainStack addArrangedSubview:versionRow];
    }
    [self addChipToStack:self.versionChipStack title:localize(@"i18n_str_40", nil) selected:NO action:NULL];

    // ----- Row 3: mod loader (populated dynamically; initially displays "Loading") -----
    {
        UIScrollView *scrollOut = nil;
        UIStackView *chipOut = nil;
        UIStackView *loaderRow = [self createFilterRowWithIconName:@"puzzlepiece.extension.fill"
                                                             label:localize(@"i18n_str_114", nil)
                                                        scrollStackOut:&scrollOut
                                                          chipStackOut:&chipOut];
        self.loaderScrollView = scrollOut;
        self.loaderChipStack = chipOut;
        [self.filterMainStack addArrangedSubview:loaderRow];
    }
    [self addChipToStack:self.loaderChipStack title:localize(@"i18n_str_40", nil) selected:NO action:NULL];

    // ----- Row 4: sort mode (relevance / downloads / recently updated / creation date) -----
    {
        UIScrollView *scrollOut = nil;
        UIStackView *chipOut = nil;
        UIStackView *sortRow = [self createFilterRowWithIconName:@"arrow.up.arrow.down"
                                                           label:localize(@"i18n_str_41", nil)
                                                      scrollStackOut:&scrollOut
                                                        chipStackOut:&chipOut];
        self.sortScrollView = scrollOut;
        self.sortChipStack = chipOut;
        [self.filterMainStack addArrangedSubview:sortRow];
    }
    [self rebuildSortChips];

    // ===== Container constraints: flush with the top safe area, 8pt side margins =====
    [NSLayoutConstraint activateConstraints:@[
        [self.filterContainerView.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:6],
        [self.filterContainerView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:8],
        [self.filterContainerView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-8],
        // Main stack padding.
        [self.filterMainStack.topAnchor constraintEqualToAnchor:self.filterContainerView.topAnchor constant:8],
        [self.filterMainStack.bottomAnchor constraintEqualToAnchor:self.filterContainerView.bottomAnchor constant:-8],
        [self.filterMainStack.leadingAnchor constraintEqualToAnchor:self.filterContainerView.leadingAnchor constant:10],
        [self.filterMainStack.trailingAnchor constraintEqualToAnchor:self.filterContainerView.trailingAnchor constant:-10],
    ]];
}

/// Creates a single filter row: fixed-width icon + label on the left, horizontally scrolling chip container on the right.
/// Based on the FCL filter-panel row structure: icon + label + horizontal scroll view.
- (UIStackView *)createFilterRowWithIconName:(NSString *)iconName
                                       label:(NSString *)labelText
                                scrollStackOut:(UIScrollView **)scrollStackOut
                                  chipStackOut:(UIStackView **)chipStackOut {
    // --- Left: icon + label (fixed width; does not scroll with the chips) ---
    UIImageView *iconView = [[UIImageView alloc] init];
    iconView.translatesAutoresizingMaskIntoConstraints = NO;
    iconView.image = [UIImage systemImageNamed:iconName];
    iconView.tintColor = [UIColor secondaryLabelColor];
    iconView.contentMode = UIViewContentModeScaleAspectFit;
    [iconView setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    [iconView setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    [NSLayoutConstraint activateConstraints:@[
        [iconView.widthAnchor constraintEqualToConstant:15],
        [iconView.heightAnchor constraintEqualToConstant:15],
    ]];

    UILabel *label = [[UILabel alloc] init];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    label.text = labelText;
    label.font = [UIFont systemFontOfSize:11 weight:UIFontWeightMedium];
    label.textColor = [UIColor secondaryLabelColor];
    label.textAlignment = NSTextAlignmentLeft;
    [label setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    [label setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    [label.widthAnchor constraintEqualToConstant:34].active = YES;

    UIStackView *labelStack = [[UIStackView alloc] initWithArrangedSubviews:@[iconView, label]];
    labelStack.translatesAutoresizingMaskIntoConstraints = NO;
    labelStack.axis = UILayoutConstraintAxisHorizontal;
    labelStack.spacing = 3;
    labelStack.alignment = UIStackViewAlignmentCenter;
    [labelStack setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];

    // --- Right: horizontally scrolling chip container ---
    UIScrollView *scrollView = [[UIScrollView alloc] init];
    scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    scrollView.showsHorizontalScrollIndicator = NO;
    scrollView.alwaysBounceHorizontal = YES;

    UIStackView *chipStack = [[UIStackView alloc] init];
    chipStack.translatesAutoresizingMaskIntoConstraints = NO;
    chipStack.axis = UILayoutConstraintAxisHorizontal;
    chipStack.spacing = 6;
    chipStack.alignment = UIStackViewAlignmentCenter;
    [scrollView addSubview:chipStack];

    // chipStack fills the scrollView's contentLayoutGuide and matches the frameLayoutGuide height.
    [NSLayoutConstraint activateConstraints:@[
        [chipStack.topAnchor constraintEqualToAnchor:scrollView.contentLayoutGuide.topAnchor],
        [chipStack.bottomAnchor constraintEqualToAnchor:scrollView.contentLayoutGuide.bottomAnchor],
        [chipStack.leadingAnchor constraintEqualToAnchor:scrollView.contentLayoutGuide.leadingAnchor],
        [chipStack.trailingAnchor constraintEqualToAnchor:scrollView.contentLayoutGuide.trailingAnchor],
        [chipStack.heightAnchor constraintEqualToAnchor:scrollView.frameLayoutGuide.heightAnchor],
    ]];

    // Expose properties to the caller.
    if (scrollStackOut) *scrollStackOut = scrollView;
    if (chipStackOut) *chipStackOut = chipStack;

    // --- Row container: label + scroll view arranged horizontally ---
    UIStackView *row = [[UIStackView alloc] initWithArrangedSubviews:@[labelStack, scrollView]];
    row.translatesAutoresizingMaskIntoConstraints = NO;
    row.axis = UILayoutConstraintAxisHorizontal;
    row.spacing = 6;
    row.alignment = UIStackViewAlignmentCenter;
    // Fixed row height keeps the total height of the four rows predictable.
    [row.heightAnchor constraintEqualToConstant:30].active = YES;
    return row;
}

/// Creates a single filter chip button (pill style, based on the FCL/ZL2 label bar).
/// Selected: theme-color (systemBlue) background + white text; unselected: translucent background + label-color text + light border.
- (UIButton *)createFilterChipWithTitle:(NSString *)title selected:(BOOL)selected {
    UIButton *chip = [UIButton buttonWithType:UIButtonTypeSystem];
    chip.translatesAutoresizingMaskIntoConstraints = NO;
    [chip setTitle:title forState:UIControlStateNormal];
    chip.titleLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightMedium];
    chip.titleLabel.adjustsFontSizeToFitWidth = YES;
    chip.titleLabel.minimumScaleFactor = 0.75;
    chip.contentEdgeInsets = UIEdgeInsetsMake(4, 12, 4, 12);
    chip.layer.cornerRadius = 14;
    chip.layer.cornerCurve = kCACornerCurveContinuous;
    chip.layer.masksToBounds = YES;
    // Fixed height prevents layout jumps when content changes.
    [chip.heightAnchor constraintEqualToConstant:28].active = YES;
    [chip setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    [chip setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    [self applyChipStyle:chip selected:selected];
    return chip;
}

/// Applies selected/unselected styling to a chip.
- (void)applyChipStyle:(UIButton *)chip selected:(BOOL)selected {
    if (selected) {
        // Selected: theme-color background + white text (based on FCL's selected-label highlight).
        chip.backgroundColor = [UIColor systemBlueColor];
        [chip setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        chip.layer.borderWidth = 0;
    } else {
        // Unselected: translucent background + label-color text + light border.
        chip.backgroundColor = [[UIColor whiteColor] colorWithAlphaComponent:0.08];
        [chip setTitleColor:[UIColor labelColor] forState:UIControlStateNormal];
        chip.layer.borderWidth = 0.5;
        chip.layer.borderColor = [[UIColor whiteColor] colorWithAlphaComponent:0.15].CGColor;
    }
}

/// Adds a chip to chipStack (convenience method for initial placeholders).
- (void)addChipToStack:(UIStackView *)stack title:(NSString *)title selected:(BOOL)selected action:(SEL)action {
    UIButton *chip = [self createFilterChipWithTitle:title selected:selected];
    if (action) {
        [chip addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    }
    [stack addArrangedSubview:chip];
}

/// Clears all arranged subviews from chipStack (used to rebuild chips).
- (void)clearChipStack:(UIStackView *)stack {
    [stack.arrangedSubviews makeObjectsPerformSelector:@selector(removeFromSuperview)];
}

#pragma mark - Rebuild filter-row chips

/// Rebuilds download-source chips (Modrinth / CurseForge).
- (void)rebuildSourceChips {
    [self clearChipStack:self.sourceChipStack];

    // Modrinth chip
    UIButton *modrinthChip = [self createFilterChipWithTitle:@"Modrinth"
                                                    selected:(self.selectedSource == kSourceModrinth)];
    modrinthChip.tag = kSourceModrinth;
    [modrinthChip addTarget:self action:@selector(sourceChipTapped:) forControlEvents:UIControlEventTouchUpInside];
    [self.sourceChipStack addArrangedSubview:modrinthChip];

    // CurseForge chip
    UIButton *curseforgeChip = [self createFilterChipWithTitle:@"CurseForge"
                                                      selected:(self.selectedSource == kSourceCurseForge)];
    curseforgeChip.tag = kSourceCurseForge;
    [curseforgeChip addTarget:self action:@selector(sourceChipTapped:) forControlEvents:UIControlEventTouchUpInside];
    [self.sourceChipStack addArrangedSubview:curseforgeChip];
}

/// Rebuilds game-version chips (dynamically populated from availableGameVersions, including "All").
- (void)rebuildVersionChips {
    [self clearChipStack:self.versionChipStack];
    if (!self.availableGameVersions || self.availableGameVersions.count == 0) {
        [self addChipToStack:self.versionChipStack title:localize(@"i18n_str_463", nil) selected:NO action:NULL];
        return;
    }
    for (NSString *version in self.availableGameVersions) {
        BOOL isSelected = [self.selectedGameVersion isEqualToString:version];
        UIButton *chip = [self createFilterChipWithTitle:version selected:isSelected];
        [chip addTarget:self action:@selector(versionChipTapped:) forControlEvents:UIControlEventTouchUpInside];
        [self.versionChipStack addArrangedSubview:chip];
    }
    // Scroll to the selected item so users can see the current chip.
    [self scrollToSelectedChipInStack:self.versionChipStack withTitle:self.selectedGameVersion];
}

/// Rebuilds loader chips (dynamically populated from availableLoaders, including "All").
- (void)rebuildLoaderChips {
    [self clearChipStack:self.loaderChipStack];
    if (!self.availableLoaders || self.availableLoaders.count == 0) {
        [self addChipToStack:self.loaderChipStack title:localize(@"i18n_str_464", nil) selected:NO action:NULL];
        return;
    }
    for (NSString *loader in self.availableLoaders) {
        BOOL isSelected = [self.selectedLoader isEqualToString:loader];
        UIButton *chip = [self createFilterChipWithTitle:loader selected:isSelected];
        [chip addTarget:self action:@selector(loaderChipTapped:) forControlEvents:UIControlEventTouchUpInside];
        [self.loaderChipStack addArrangedSubview:chip];
    }
    // Scroll to the selected item.
    [self scrollToSelectedChipInStack:self.loaderChipStack withTitle:self.selectedLoader];
}

/// Rebuilds sort-mode chips (four fixed options: relevance / downloads / recently updated / creation date).
- (void)rebuildSortChips {
    [self clearChipStack:self.sortChipStack];
    for (NSDictionary *item in SortOptionItems()) {
        NSString *key = item[@"key"];
        NSString *title = item[@"title"];
        BOOL isSelected = [self.selectedSort isEqualToString:key];
        UIButton *chip = [self createFilterChipWithTitle:title selected:isSelected];
        chip.accessibilityIdentifier = key; // Store the sort key in accessibilityIdentifier.
        [chip addTarget:self action:@selector(sortChipTapped:) forControlEvents:UIControlEventTouchUpInside];
        [self.sortChipStack addArrangedSubview:chip];
    }
}

/// Scrolls the scrollView to make the chip with the specified title visible.
- (void)scrollToSelectedChipInStack:(UIStackView *)stack withTitle:(NSString *)title {
    if (!title || title.length == 0) return;
    UIScrollView *scrollView = (UIScrollView *)stack.superview;
    if (![scrollView isKindOfClass:[UIScrollView class]]) return;
    for (UIButton *chip in stack.arrangedSubviews) {
        if (![chip isKindOfClass:[UIButton class]]) continue;
        NSString *chipTitle = chip.titleLabel.text;
        if ([chipTitle isEqualToString:title]) {
            CGRect frameInScroll = [chip.superview convertRect:chip.frame toView:scrollView];
            CGFloat targetX = frameInScroll.origin.x - scrollView.bounds.size.width / 2 + frameInScroll.size.width / 2;
            targetX = MAX(0, targetX);
            CGFloat maxOffset = scrollView.contentSize.width - scrollView.bounds.size.width;
            targetX = MIN(targetX, MAX(0, maxOffset));
            [scrollView setContentOffset:CGPointMake(targetX, 0) animated:YES];
            break;
        }
    }
}

#pragma mark - Chip tap handlers

/// Download-source chip tap: switches between Modrinth / CurseForge and fetches the version list again.
- (void)sourceChipTapped:(UIButton *)sender {
    NSInteger newSource = sender.tag;
    if (newSource == self.selectedSource) return; // Ignore if the source did not change.

    // ★ [MODPACK-FIX] CurseForge source works without a key (baseURL forces the MCIM mirror without one; tested with HTTP 200).
    // Gate using isSourceAvailable; a key is needed only for direct official access.
    if (newSource == kSourceCurseForge && ![CurseForgeAPI isSourceAvailable]) {
        [self showSourceAlertWithTitle:localize(@"i18n_str_465", nil)
                                message:localize(@"i18n_str_466", nil)];
        return;
    }

    self.selectedSource = newSource;
    // Update chip selection styling.
    for (UIButton *chip in self.sourceChipStack.arrangedSubviews) {
        if (![chip isKindOfClass:[UIButton class]]) continue;
        [self applyChipStyle:chip selected:(chip.tag == self.selectedSource)];
    }
    // Clear existing data and fetch again.
    self.allVersions = nil;
    self.filteredVersions = nil;
    [self.tableView reloadData];
    [self fetchVersionsFromCurrentSource];
}

/// Game-version chip tap: switches the selected version and reapplies filters.
- (void)versionChipTapped:(UIButton *)sender {
    NSString *newVersion = sender.titleLabel.text;
    if ([newVersion isEqualToString:self.selectedGameVersion]) return;
    self.selectedGameVersion = newVersion;
    // Update chip selection styling.
    for (UIButton *chip in self.versionChipStack.arrangedSubviews) {
        if (![chip isKindOfClass:[UIButton class]]) continue;
        [self applyChipStyle:chip selected:[chip.titleLabel.text isEqualToString:self.selectedGameVersion]];
    }
    [self applyFiltersAndSort];
}

/// Loader chip tap: switches the selected loader and reapplies filters.
- (void)loaderChipTapped:(UIButton *)sender {
    NSString *newLoader = sender.titleLabel.text;
    if ([newLoader isEqualToString:self.selectedLoader]) return;
    self.selectedLoader = newLoader;
    // Update chip selection styling.
    for (UIButton *chip in self.loaderChipStack.arrangedSubviews) {
        if (![chip isKindOfClass:[UIButton class]]) continue;
        [self applyChipStyle:chip selected:[chip.titleLabel.text isEqualToString:self.selectedLoader]];
    }
    [self applyFiltersAndSort];
}

/// Sort-mode chip tap: switches the sort mode, resorts, and refreshes the list.
- (void)sortChipTapped:(UIButton *)sender {
    NSString *newSort = sender.accessibilityIdentifier;
    if (!newSort || [newSort isEqualToString:self.selectedSort]) return;
    self.selectedSort = newSort;
    // Update chip selection styling.
    for (UIButton *chip in self.sortChipStack.arrangedSubviews) {
        if (![chip isKindOfClass:[UIButton class]]) continue;
        [self applyChipStyle:chip selected:[chip.accessibilityIdentifier isEqualToString:self.selectedSort]];
    }
    [self applyFiltersAndSort];
}

/// Displays a source-switch failure message.
- (void)showSourceAlertWithTitle:(NSString *)title message:(NSString *)message {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title
                                                                    message:message
                                                             preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:localize(@"i18n_str_44", nil) style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

#pragma mark - TableView setup

- (void)setupTableView {
    self.tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    self.tableView.translatesAutoresizingMaskIntoConstraints = NO;
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    // Enable automatic row heights so compact cards adapt to their content.
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 78;
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    [self.tableView registerClass:[ModVersionTableViewCell class] forCellReuseIdentifier:@"ModVersionCell"];
    [self.view addSubview:self.tableView];

    // Place the tableView directly below the filter panel.
    [NSLayoutConstraint activateConstraints:@[
        [self.tableView.topAnchor constraintEqualToAnchor:self.filterContainerView.bottomAnchor constant:6],
        [self.tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.tableView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
    ]];
}

- (void)setupActivityIndicator {
    self.activityIndicator = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleLarge];
    self.activityIndicator.translatesAutoresizingMaskIntoConstraints = NO;
    self.activityIndicator.hidesWhenStopped = YES;
    [self.view addSubview:self.activityIndicator];

    [NSLayoutConstraint activateConstraints:@[
        [self.activityIndicator.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [self.activityIndicator.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor],
    ]];
}

#pragma mark - Fetch data

/// Fetches the version list from the currently selected source.
/// Modrinth source → ModrinthAPI; CurseForge source → CurseForgeAPI.
- (void)fetchVersionsFromCurrentSource {
    [self.activityIndicator startAnimating];

    if (self.selectedSource == kSourceCurseForge) {
        // ===== CurseForge source =====
        // CurseForgeAPI.getVersionsForModWithID: returns an array of ModVersion (including CurseForge fileId/projectId).
        [[CurseForgeAPI sharedInstance] getVersionsForModWithID:self.modItem.onlineID
                                                     completion:^(NSArray<ModVersion *> * _Nullable versions, NSError * _Nullable error) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [self handleVersionsResponse:versions error:error];
            });
        }];
    } else {
        // ===== Modrinth source (default) =====
        [[ModrinthAPI sharedInstance] getVersionsForModWithID:self.modItem.onlineID
                                                   completion:^(NSArray<ModVersion *> * _Nullable versions, NSError * _Nullable error) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [self handleVersionsResponse:versions error:error];
            });
        }];
    }
}

/// Handles version-fetch callbacks consistently.
- (void)handleVersionsResponse:(NSArray<ModVersion *> *)versions error:(NSError *)error {
    [self.activityIndicator stopAnimating];
    if (error) {
        NSLog(@"[ModVersionVC] Error fetching versions (source=%ld): %@", (long)self.selectedSource, error);
        // Fix for "tapping the download button on a version does nothing":
        // Previously, a failed version-list fetch only logged to NSLog, leaving users with a blank list and no feedback, as if the button were broken.
        // Now show a UIAlertController message (consistent with ShaderVersionViewController).
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:localize(@"i18n_str_42", nil)
                                                                        message:localize(@"i18n_str_467", nil)
                                                                 preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:localize(@"i18n_str_44", nil) style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
        return;
    }
    if (!versions || versions.count == 0) {
        // Also provide feedback for an empty list so users do not think "the button did nothing."
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:localize(@"i18n_str_388", nil)
                                                                        message:localize(@"i18n_str_468", nil)
                                                                 preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:localize(@"i18n_str_44", nil) style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
        return;
    }
    self.allVersions = versions;
    [self processFilters];
    [self applyFiltersAndSort];
}

- (void)processFilters {
    // Extract all available game versions and loaders from the version data.
    NSMutableSet<NSString *> *gameVersions = [NSMutableSet setWithObject:localize(@"resman.mods.filter.all", nil)];
    NSMutableSet<NSString *> *loaders = [NSMutableSet setWithObject:localize(@"resman.mods.filter.all", nil)];

    for (ModVersion *version in self.allVersions) {
        for (NSString *gameVersion in version.gameVersions) {
            [gameVersions addObject:gameVersion];
        }
        for (NSString *loader in version.loaders) {
            [loaders addObject:[loader capitalizedString]]; // Capitalize for display.
        }
    }

    // Sort game versions in descending semantic-version order (newest first); keep "All" at the top.
    self.availableGameVersions = [[gameVersions allObjects] sortedArrayUsingComparator:^NSComparisonResult(NSString *obj1, NSString *obj2) {
        if ([obj1 isEqualToString:localize(@"resman.mods.filter.all", nil)]) return NSOrderedAscending;  // ★ [AUDIT-FIX]
        if ([obj2 isEqualToString:localize(@"resman.mods.filter.all", nil)]) return NSOrderedDescending;  // ★ [AUDIT-FIX]
        return [obj2 compare:obj1 options:NSNumericSearch];
    }];

    // Sort loaders alphabetically; keep "All" at the top.
    self.availableLoaders = [[loaders allObjects] sortedArrayUsingSelector:@selector(compare:)];

    // FCL style: default to "All", but automatically select preferredGameVersion/preferredLoader
    // when available, so users do not need to filter manually.
    self.selectedGameVersion = self.availableGameVersions.firstObject ?: localize(@"resman.mods.filter.all", nil);
    self.selectedLoader = self.availableLoaders.firstObject ?: localize(@"resman.mods.filter.all", nil);

    // Automatically select the preferred version (case-insensitive comparison).
    if (self.preferredGameVersion.length > 0) {
        NSString *preferred = self.preferredGameVersion;
        for (NSString *gv in self.availableGameVersions) {
            if ([gv caseInsensitiveCompare:preferred] == NSOrderedSame) {
                self.selectedGameVersion = gv;
                break;
            }
        }
    }
    // Automatically select the preferred loader (preferredLoader is lowercase, e.g. "fabric",
    // whereas availableLoaders is capitalized, e.g. "Fabric").
    if (self.preferredLoader.length > 0) {
        NSString *preferredCapitalized = [self.preferredLoader capitalizedString];
        for (NSString *ld in self.availableLoaders) {
            if ([ld caseInsensitiveCompare:preferredCapitalized] == NSOrderedSame) {
                self.selectedLoader = ld;
                break;
            }
        }
    }

    // Rebuild version/loader chips (replace "Loading..." with actual data).
    [self rebuildVersionChips];
    [self rebuildLoaderChips];
}

#pragma mark - Filter + sort

/// Applies filters and sorting, then refreshes the table.
/// First filters by game version/loader, then sorts using the selected sort mode.
- (void)applyFiltersAndSort {
    // ----- 1. Filter: game version + loader -----
    NSPredicate *predicate = [NSPredicate predicateWithBlock:^BOOL(ModVersion *evaluatedObject, NSDictionary *bindings) {
        BOOL gameVersionMatch = [self.selectedGameVersion isEqualToString:localize(@"resman.mods.filter.all", nil)] ||  // ★ [AUDIT-FIX]
                                 [evaluatedObject.gameVersions containsObject:self.selectedGameVersion];
        BOOL loaderMatch = [self.selectedLoader isEqualToString:localize(@"resman.mods.filter.all", nil)] ||  // ★ [AUDIT-FIX]
                            [evaluatedObject.loaders containsObject:self.selectedLoader.lowercaseString];
        return gameVersionMatch && loaderMatch;
    }];
    NSArray<ModVersion *> *filtered = [self.allVersions filteredArrayUsingPredicate:predicate];

    // ----- 2. Sort: by selected sort mode -----
    NSArray<ModVersion *> *sorted = [self sortVersions:filtered];

    // ----- 3. FCL style: pin versions matching the preferred version + loader to the top -----
    // When users open the version list from a profile (e.g. neoforge + 1.21.1),
    // automatically pin exact matches to the top so they do not have to search a long list manually.
    if (self.preferredGameVersion.length > 0 || self.preferredLoader.length > 0) {
        NSMutableArray<ModVersion *> *pinned = [NSMutableArray array];
        NSMutableArray<ModVersion *> *rest = [NSMutableArray array];
        for (ModVersion *v in sorted) {
            BOOL versionMatch = (self.preferredGameVersion.length == 0) ||
                                [v.gameVersions containsObject:self.preferredGameVersion];
            BOOL loaderMatch = (self.preferredLoader.length == 0) ||
                               [v.loaders containsObject:self.preferredLoader.lowercaseString];
            if (versionMatch && loaderMatch) {
                [pinned addObject:v];
            } else {
                [rest addObject:v];
            }
        }
        // Keep the pinned section in its original sort order, followed by the rest.
        if (pinned.count > 0 && pinned.count < sorted.count) {
            sorted = [pinned arrayByAddingObjectsFromArray:rest];
        }
    }

    self.filteredVersions = sorted;

    [self.tableView reloadData];
}

/// Sorts the version array using the currently selected sort mode.
- (NSArray<ModVersion *> *)sortVersions:(NSArray<ModVersion *> *)versions {
    if (!versions || versions.count <= 1) return versions;

    // Relevance / downloads: preserve the original API order.
    // (ModVersion has no per-version download-count field, so download sorting falls back to the original order;
    //   download counts are available only at the project level in ModItem.downloads.)
    if ([self.selectedSort isEqualToString:kSortRelevance] ||
        [self.selectedSort isEqualToString:kSortDownloads]) {
        return versions;
    }

    // Recently updated / creation date: sort by datePublished.
    NSISO8601DateFormatter *dateFormatter = [[NSISO8601DateFormatter alloc] init];
    NSMutableArray<ModVersion *> *sorted = [versions mutableCopy];
    __weak typeof(self) weakSelf = self;
    [sorted sortUsingComparator:^NSComparisonResult(ModVersion *v1, ModVersion *v2) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        NSDate *d1 = [dateFormatter dateFromString:v1.datePublished];
        NSDate *d2 = [dateFormatter dateFromString:v2.datePublished];
        if (!d1) d1 = [NSDate distantPast];
        if (!d2) d2 = [NSDate distantPast];

        if ([strongSelf.selectedSort isEqualToString:kSortUpdated]) {
            // Recently updated: descending (newest first).
            return [d2 compare:d1];
        } else if ([strongSelf.selectedSort isEqualToString:kSortCreated]) {
            // Creation date: ascending (oldest first).
            return [d1 compare:d2];
        }
        return NSOrderedSame;
    }];
    return [sorted copy];
}


#pragma mark - UITableViewDataSource

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.filteredVersions.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    ModVersionTableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"ModVersionCell" forIndexPath:indexPath];
    ModVersion *version = self.filteredVersions[indexPath.row];
    [cell configureWithVersion:version];
    return cell;
}

#pragma mark - UITableViewDelegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    ModVersion *selectedVersion = self.filteredVersions[indexPath.row];
    if ([self.delegate respondsToSelector:@selector(modVersionViewController:didSelectVersion:)]) {
        [self.delegate modVersionViewController:self didSelectVersion:selectedVersion];
    }
    [self.navigationController popViewControllerAnimated:YES];
}

@end
