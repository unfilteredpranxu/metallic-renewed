//
//  ModsManagerViewController.m
//  Amethyst
//
//  Mod management page implementation (inherits from ResourceListViewController).
//  Based on the ZL2 ModsManagerScreen pattern: the navigation-bar "Check for updates" button runs the built-in update flow
//  (concurrent checks → confirmation dialog → concurrent downloads to a temporary directory → replace old files → refresh + badges).
//

#import "ModsManagerViewController.h"
#import "ModTableViewCell.h"
#import "ModService.h"
#import "ModItem.h"
#import "ModUpdateService.h"
#import "ModVersion.h"
#import "PLDownloadClient.h"
#import "PLMirrorCenter.h"
#import "PLProfiles.h"
#import "LauncherPreferences.h"
#import "DownloadViewController.h"
#import "utils.h"
#import <CommonCrypto/CommonDigest.h>

#pragma mark - Internal models and enums

/// Update download task (a pending update found by the check).
@interface ModUpdateTask : NSObject
/// Update-check result (includes local file path and candidate versions).
@property (nonatomic, strong) ModUpdateResult *result;
/// Corresponding local ModItem (used to display the name and replace the file).
@property (nonatomic, strong) ModItem *mod;
/// Target version (first in candidateVersions, i.e. the latest candidate).
@property (nonatomic, strong) ModVersion *targetVersion;
/// Temporary file path after download (nonempty on success).
@property (nonatomic, copy) NSString *tempPath;
/// Whether the download succeeded.
@property (nonatomic, assign) BOOL downloadSucceeded;
@end

@implementation ModUpdateTask
@end

/// Status filter mode.
typedef NS_ENUM(NSInteger, ModsFilterMode) {
    ModsFilterModeAll = 0,
    ModsFilterModeEnabled,
    ModsFilterModeDisabled,
};

/// Sort mode.
typedef NS_ENUM(NSInteger, ModsSortMode) {
    ModsSortModeName = 0,
    ModsSortModeModifiedDate,
};

#pragma mark - Utility functions

/// Computes a file's SHA1 incrementally (chunked with CommonCrypto; supports large files); returns nil on failure.
static NSString *ModsManagerSHA1ForFile(NSString *path) {
    if (path.length == 0) return nil;
    NSFileHandle *handle = [NSFileHandle fileHandleForReadingAtPath:path];
    if (!handle) return nil;
    CC_SHA1_CTX ctx;
    CC_SHA1_Init(&ctx);
    @try {
        while (YES) {
            @autoreleasepool {
                NSData *chunk = [handle readDataOfLength:1 << 16];
                if (chunk.length == 0) break;
                CC_SHA1_Update(&ctx, chunk.bytes, (CC_LONG)chunk.length);
            }
        }
    } @catch (NSException *exception) {
        [handle closeFile];
        return nil;
    }
    [handle closeFile];
    unsigned char digest[CC_SHA1_DIGEST_LENGTH];
    CC_SHA1_Final(digest, &ctx);
    NSMutableString *hex = [NSMutableString stringWithCapacity:CC_SHA1_DIGEST_LENGTH * 2];
    for (int i = 0; i < CC_SHA1_DIGEST_LENGTH; i++) {
        [hex appendFormat:@"%02x", digest[i]];
    }
    return hex;
}

#pragma mark - Class extension

@interface ModsManagerViewController () <UITableViewDataSource, UITableViewDelegate, ModTableViewCellDelegate, UISearchBarDelegate, UIDocumentPickerDelegate>

// ===== Data =====
@property (nonatomic, strong) NSMutableArray<ModItem *> *localMods;       // All local mods.
@property (nonatomic, strong) NSMutableArray<ModItem *> *filteredLocalMods; // After search + filtering + sorting.
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSDate *> *modDates; // filePath → modification time (for sorting).

// ===== Filtering / sorting =====
@property (nonatomic, assign) ModsFilterMode filterMode;
@property (nonatomic, assign) ModsSortMode sortMode;
@property (nonatomic, strong) UIScrollView *chipsScrollView;   // Horizontal chip-scrolling container.
@property (nonatomic, strong) UIStackView *chipsStack;         // Chip layout.
@property (nonatomic, strong) NSArray<UIButton *> *filterChips;
@property (nonatomic, strong) UIButton *sortChipButton;

// ===== Navigation buttons =====
@property (nonatomic, strong) UIBarButtonItem *closeButtonItem;
@property (nonatomic, strong) UIBarButtonItem *refreshButton;
@property (nonatomic, strong) UIBarButtonItem *checkUpdateButton;
@property (nonatomic, strong) UIBarButtonItem *importButton;
@property (nonatomic, strong) UIBarButtonItem *selectButtonItem;
@property (nonatomic, strong) UIBarButtonItem *doneButtonItem;
@property (nonatomic, strong) UIBarButtonItem *navSpinnerItem;
@property (nonatomic, strong) UIActivityIndicatorView *navSpinner;

// ===== Batch-action buttons (contents of batchActionStack) =====
@property (nonatomic, strong) UIButton *batchEnableButton;
@property (nonatomic, strong) UIButton *batchDisableButton;
@property (nonatomic, strong) UIButton *batchDeleteButton;

// ===== Update-flow state =====
/// Whether an update flow is active (YES while checking or downloading/replacing; buttons are disabled to prevent duplicate actions).
@property (nonatomic, assign) BOOL isUpdateBusy;
/// Update-flow stage text (displayed in the navigation title).
@property (nonatomic, copy) NSString *updateBusyText;
/// Results for mods with available updates: filePath → result, used for cell badges.
@property (nonatomic, strong) NSMutableDictionary<NSString *, ModUpdateResult *> *updateResultsByPath;

// ===== Other =====
@property (nonatomic, assign) BOOL hasPlayedInitialAnimation; // Play the cascading entrance animation only on the first load.

@end

@implementation ModsManagerViewController

#pragma mark - Init

- (instancetype)init {
    // Preserve compatibility with existing call sites [[ModsManagerViewController alloc] init]:
    // delegate to the base class convenience initializer (title + mod semantic color puzzlepiece.fill / systemOrange).
    return [self initWithTitle:localize(@"resman.mods.title", nil)
              resourceTypeIcon:@"puzzlepiece.fill"
                      iconColor:[UIColor systemOrangeColor]];
}

#pragma mark - Lifecycle

- (void)viewDidLoad {
    [super viewDidLoad]; // The base class builds the background/search bar/table/empty state/loading state/batch toolbar.

    self.localMods = [NSMutableArray array];
    self.filteredLocalMods = [NSMutableArray array];
    self.modDates = [NSMutableDictionary dictionary];
    self.updateResultsByPath = [NSMutableDictionary dictionary];

    // Search bar.
    self.searchBar.delegate = self;
    self.searchBar.placeholder = localize(@"resman.mods.search_placeholder", nil);

    [self setupNavigationButtons];
    [self setupChipsRow];
    [self setupTableViewExtras];

    [self loadMods];
}

#pragma mark - Navigation buttons

- (void)setupNavigationButtons {
    self.closeButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone
                                                                         target:self
                                                                         action:@selector(closeTapped)];
    self.closeButtonItem.accessibilityLabel = localize(@"resman.common.close", nil);

    self.refreshButton = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemRefresh
                                                                       target:self
                                                                       action:@selector(handleRefresh:)];
    self.refreshButton.accessibilityLabel = localize(@"resman.common.refresh", nil);

    UIImage *checkImage = [UIImage systemImageNamed:@"arrow.triangle.2.circlepath"];
    self.checkUpdateButton = [[UIBarButtonItem alloc] initWithImage:checkImage
                                                              style:UIBarButtonItemStylePlain
                                                             target:self
                                                             action:@selector(checkForUpdates)];
    self.checkUpdateButton.accessibilityLabel = localize(@"resman.mods.check_update", nil);

    UIImage *importImage = [UIImage systemImageNamed:@"square.and.arrow.down"] ?: [UIImage systemImageNamed:@"plus"];
    self.importButton = [[UIBarButtonItem alloc] initWithImage:importImage
                                                         style:UIBarButtonItemStylePlain
                                                        target:self
                                                        action:@selector(importModTapped)];
    self.importButton.accessibilityLabel = localize(@"resman.mods.import", nil);

    UIImage *selectImage = [UIImage systemImageNamed:@"checklist"] ?: [UIImage systemImageNamed:@"checkmark.circle"];
    self.selectButtonItem = [[UIBarButtonItem alloc] initWithImage:selectImage
                                                             style:UIBarButtonItemStylePlain
                                                            target:self
                                                            action:@selector(enterSelectMode)];
    self.selectButtonItem.accessibilityLabel = localize(@"resman.common.select", nil);

    self.doneButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone
                                                                        target:self
                                                                        action:@selector(exitSelectMode)];
    self.doneButtonItem.accessibilityLabel = localize(@"resman.common.done", nil);

    // Show a navigation-bar spinner while an update flow is busy.
    self.navSpinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    self.navSpinner.hidesWhenStopped = YES;
    self.navSpinnerItem = [[UIBarButtonItem alloc] initWithCustomView:self.navSpinner];

    [self updateNavigationButtons];
}

/// Refreshes navigation buttons and title based on the current state (normal / selection mode / update busy).
- (void)updateNavigationButtons {
    if (self.selectModeEnabled) {
        self.navigationItem.leftBarButtonItem = self.closeButtonItem;
        self.navigationItem.rightBarButtonItems = @[self.doneButtonItem];
        [self updateSelectModeTitle];
    } else if (self.isUpdateBusy) {
        // Update flow in progress: show only the spinner and disable other actions to prevent duplicate triggers.
        self.navigationItem.leftBarButtonItem = self.closeButtonItem;
        self.navigationItem.rightBarButtonItems = @[self.navSpinnerItem];
        [self.navSpinner startAnimating];
        self.navigationItem.title = self.updateBusyText ?: localize(@"resman.mods.processing", nil);
    } else {
        self.navigationItem.leftBarButtonItem = self.closeButtonItem;
        // From right to left: import, refresh, check for updates, select.
        self.navigationItem.rightBarButtonItems = @[self.importButton, self.refreshButton, self.checkUpdateButton, self.selectButtonItem];
        self.navigationItem.title = self.pageTitle;
    }
}

/// Selection-mode title: displays the number of selected items.
- (void)updateSelectModeTitle {
    if (self.selectModeEnabled) {
        self.navigationItem.title = [NSString stringWithFormat:localize(@"resman.common.selected_count", nil), (long)self.selectedIndexPaths.count];
    }
}

- (void)closeTapped {
    // Support both container types: pop if pushed onto a navigation stack; dismiss if presented modally.
    if (self.navigationController && self.navigationController.viewControllers.firstObject != self) {
        [self.navigationController popViewControllerAnimated:YES];
    } else {
        [self dismissViewControllerAnimated:YES completion:nil];
    }
}

- (void)handleRefresh:(id)sender {
    // Exit selection mode before refreshing to avoid inconsistent selection state with new data.
    if (self.selectModeEnabled) {
        [self setSelectMode:NO];
    }
    [self loadMods];
}

#pragma mark - Filter-chip row (below the search bar)

- (void)setupChipsRow {
    // The base class anchors the tableView top to the searchBar bottom by default; disable that constraint before inserting a chip row.
    for (NSLayoutConstraint *constraint in [self.view.constraints copy]) {
        if (constraint.firstItem == self.tableView && constraint.secondItem == self.searchBar
            && constraint.firstAttribute == NSLayoutAttributeTop) {
            constraint.active = NO;
            break;
        }
    }

    // Horizontally scrolling chip container.
    self.chipsScrollView = [[UIScrollView alloc] init];
    self.chipsScrollView.translatesAutoresizingMaskIntoConstraints = NO;
    self.chipsScrollView.showsHorizontalScrollIndicator = NO;
    self.chipsScrollView.alwaysBounceHorizontal = NO;
    [self.view addSubview:self.chipsScrollView];

    self.chipsStack = [[UIStackView alloc] init];
    self.chipsStack.translatesAutoresizingMaskIntoConstraints = NO;
    self.chipsStack.axis = UILayoutConstraintAxisHorizontal;
    self.chipsStack.alignment = UIStackViewAlignmentCenter;
    self.chipsStack.spacing = 8.0;
    [self.chipsScrollView addSubview:self.chipsStack];

    // Three filter chips: All / Enabled / Disabled.
    NSMutableArray<UIButton *> *chips = [NSMutableArray array];
    NSArray<NSString *> *titles = @[localize(@"resman.mods.filter.all", nil),
                                    localize(@"resman.mods.filter.enabled", nil),
                                    localize(@"resman.mods.filter.disabled", nil)];
    for (NSUInteger i = 0; i < titles.count; i++) {
        UIButton *chip = [self makeChipButtonWithTitle:titles[i]];
        chip.tag = i;
        [chip addTarget:self action:@selector(filterChipTapped:) forControlEvents:UIControlEventTouchUpInside];
        [self.chipsStack addArrangedSubview:chip];
        [chips addObject:chip];
    }
    self.filterChips = chips;

    // Trailing sort button: toggle between name / modification time.
    self.sortChipButton = [self makeChipButtonWithTitle:localize(@"resman.mods.sort.name", nil)];
    [self.sortChipButton setImage:[UIImage systemImageNamed:@"arrow.up.arrow.down"]
                  forState:UIControlStateNormal];
    self.sortChipButton.semanticContentAttribute = UISemanticContentAttributeForceLeftToRight; // Icon on the left.
    [self.sortChipButton addTarget:self action:@selector(sortChipTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.chipsStack addArrangedSubview:self.sortChipButton];

    [NSLayoutConstraint activateConstraints:@[
        // Place the chip row directly below the search bar and anchor the tableView to the bottom of the chip row.
        [self.chipsScrollView.topAnchor constraintEqualToAnchor:self.searchBar.bottomAnchor constant:2],
        [self.chipsScrollView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:ResourceListCardSideInset],
        [self.chipsScrollView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-ResourceListCardSideInset],
        [self.chipsScrollView.heightAnchor constraintEqualToConstant:34],

        [self.chipsStack.topAnchor constraintEqualToAnchor:self.chipsScrollView.topAnchor],
        [self.chipsStack.bottomAnchor constraintEqualToAnchor:self.chipsScrollView.bottomAnchor],
        [self.chipsStack.leadingAnchor constraintEqualToAnchor:self.chipsScrollView.contentLayoutGuide.leadingAnchor],
        [self.chipsStack.trailingAnchor constraintEqualToAnchor:self.chipsScrollView.contentLayoutGuide.trailingAnchor],
        [self.chipsStack.centerYAnchor constraintEqualToAnchor:self.chipsScrollView.centerYAnchor],

        [self.tableView.topAnchor constraintEqualToAnchor:self.chipsScrollView.bottomAnchor constant:2],
    ]];

    [self refreshChipStyles];
}

/// Creates a pill-shaped chip button (selected = accent background with white text; unselected = translucent background with labelColor text).
- (UIButton *)makeChipButtonWithTitle:(NSString *)title {
    UIButton *chip = [UIButton buttonWithType:UIButtonTypeSystem];
    chip.translatesAutoresizingMaskIntoConstraints = NO;
    [chip setTitle:title forState:UIControlStateNormal];
    chip.titleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
    chip.contentEdgeInsets = UIEdgeInsetsMake(5, 14, 5, 14);
    chip.layer.cornerRadius = 14.0;
    chip.layer.cornerCurve = kCACornerCurveContinuous;
    chip.layer.masksToBounds = YES;
    [chip.heightAnchor constraintEqualToConstant:28].active = YES;
    [chip setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    [chip setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    return chip;
}

/// Applies selected/unselected styling.
- (void)applyChipStyle:(UIButton *)chip selected:(BOOL)selected {
    if (selected) {
        chip.backgroundColor = accentColor();
        [chip setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        chip.tintColor = [UIColor whiteColor];
        chip.layer.borderWidth = 0;
    } else {
        chip.backgroundColor = [[UIColor whiteColor] colorWithAlphaComponent:0.08];
        [chip setTitleColor:[UIColor labelColor] forState:UIControlStateNormal];
        chip.tintColor = [UIColor labelColor];
        chip.layer.borderWidth = 0.5;
        chip.layer.borderColor = [[UIColor whiteColor] colorWithAlphaComponent:0.15].CGColor;
    }
}

/// Refreshes all chip styles based on the current filter/sort state.
- (void)refreshChipStyles {
    for (NSUInteger i = 0; i < self.filterChips.count; i++) {
        [self applyChipStyle:self.filterChips[i] selected:((NSInteger)i == self.filterMode)];
    }
    [self applyChipStyle:self.sortChipButton selected:YES]; // Sort button typically stays selected (the current sort is active).
    NSString *sortTitle = (self.sortMode == ModsSortModeName) ? localize(@"resman.mods.sort.name", nil)
                                                              : localize(@"resman.mods.sort.modified", nil);
    [self.sortChipButton setTitle:sortTitle forState:UIControlStateNormal];
}

- (void)filterChipTapped:(UIButton *)sender {
    self.filterMode = (ModsFilterMode)sender.tag;
    [self refreshChipStyles];
    [self applyFilter];
}

- (void)sortChipTapped {
    self.sortMode = (self.sortMode == ModsSortModeName) ? ModsSortModeModifiedDate : ModsSortModeName;
    [self refreshChipStyles];
    [self applyFilter];
}

#pragma mark - Additional TableView configuration

- (void)setupTableViewExtras {
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    [self.tableView registerClass:[ModTableViewCell class] forCellReuseIdentifier:@"ModCell"];
    self.tableView.rowHeight = 68.0;
}

#pragma mark - Data Loading

/// Base-class refresh hook: reloads the mod list on download-complete notification / viewWillAppear.
/// Key fix (resource-management page did not refresh after a successful download): automatically refresh the page after the file is written.
- (void)reloadResourceList {
    [self loadMods];
}

- (void)loadMods {
    [self setLoading:YES];
    NSString *profile = self.profileName ?: @"default";
    __weak typeof(self) weakSelf = self;
    [[ModService sharedService] scanModsForProfile:profile completion:^(NSArray<ModItem *> *mods) {
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf) return;
            [strongSelf.localMods removeAllObjects];
            [strongSelf.localMods addObjectsFromArray:mods];
            [strongSelf cacheModificationDates];
            [strongSelf applyFilter];
            [strongSelf setLoading:NO];
            // Play the cascading entrance animation on the first load (Air-Design 15.3).
            if (!strongSelf.hasPlayedInitialAnimation && strongSelf.localMods.count > 0) {
                strongSelf.hasPlayedInitialAnimation = YES;
                [strongSelf animateCellsInChain];
            }
        });
    }];
}

/// Caches each mod file's modification time for sorting (avoids repeated I/O in the comparator).
- (void)cacheModificationDates {
    [self.modDates removeAllObjects];
    NSFileManager *fm = [NSFileManager defaultManager];
    for (ModItem *mod in self.localMods) {
        if (mod.filePath.length == 0) continue;
        NSDate *date = [[fm attributesOfItemAtPath:mod.filePath error:nil] fileModificationDate];
        if (date) self.modDates[mod.filePath] = date;
    }
}

/// Search + status filtering + sorting → filteredLocalMods + refresh empty state.
- (void)applyFilter {
    NSString *query = [self.searchBar.text lowercaseString];
    NSMutableArray<ModItem *> *result = [NSMutableArray array];
    for (ModItem *mod in self.localMods) {
        // Status filter.
        if (self.filterMode == ModsFilterModeEnabled && mod.disabled) continue;
        if (self.filterMode == ModsFilterModeDisabled && !mod.disabled) continue;
        // Search filter.
        if (query.length > 0) {
            NSString *name = mod.displayName.lowercaseString ?: @"";
            NSString *file = mod.fileName.lowercaseString ?: @"";
            if (![name containsString:query] && ![file containsString:query]) continue;
        }
        [result addObject:mod];
    }

    // Sort.
    if (self.sortMode == ModsSortModeName) {
        [result sortUsingComparator:^NSComparisonResult(ModItem *_Nonnull a, ModItem *_Nonnull b) {
            NSString *nameA = a.displayName ?: a.fileName;
            NSString *nameB = b.displayName ?: b.fileName;
            return [nameA localizedCaseInsensitiveCompare:nameB];
        }];
    } else {
        // Modification time descending (most recently changed first; items without a date last).
        [result sortUsingComparator:^NSComparisonResult(ModItem *_Nonnull a, ModItem *_Nonnull b) {
            NSDate *dateA = self.modDates[a.filePath];
            NSDate *dateB = self.modDates[b.filePath];
            if (!dateA && !dateB) return NSOrderedSame;
            if (!dateA) return NSOrderedDescending;
            if (!dateB) return NSOrderedAscending;
            return [dateB compare:dateA];
        }];
    }

    [self.filteredLocalMods removeAllObjects];
    [self.filteredLocalMods addObjectsFromArray:result];

    // Empty state.
    if (result.count == 0) {
        if (self.localMods.count == 0) {
            __weak typeof(self) weakSelf = self;
            [self showEmptyStateWithIcon:nil
                               iconColor:nil
                                 message:localize(@"resman.mods.empty", nil)
                            actionTitle:localize(@"resman.common.go_download", nil)
                          actionHandler:^{
                [weakSelf openDownloadPage];
            }];
        } else {
            [self showEmptyStateWithIcon:@"magnifyingglass"
                               iconColor:[UIColor secondaryLabelColor]
                                 message:localize(@"resman.mods.search_empty", nil)
                            actionTitle:nil
                          actionHandler:nil];
        }
    } else {
        [self hideEmptyState];
    }

    // "Select" button availability.
    self.selectButtonItem.enabled = (result.count > 0);

    [self.tableView reloadData];
}

/// Empty-state "Download" action: opens the unified download page (no parameterized resource-type entry point; opens the default page).
- (void)openDownloadPage {
    DownloadViewController *vc = [[DownloadViewController alloc] init];
    // Key fix (target instance mismatch): pass the profileName bound to this management page,
    // ensuring downloads go to the same instance that is currently open.
    vc.targetProfileName = self.profileName;
    if (self.navigationController) {
        [self.navigationController pushViewController:vc animated:YES];
    } else {
        UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:vc];
        nav.modalPresentationStyle = UIModalPresentationFullScreen;
        [self presentViewController:nav animated:YES completion:nil];
    }
}

#pragma mark - UISearchBarDelegate

- (void)searchBar:(UISearchBar *)searchBar textDidChange:(NSString *)searchText {
    [self applyFilter];
}

- (void)searchBarSearchButtonClicked:(UISearchBar *)searchBar {
    [searchBar resignFirstResponder];
}

#pragma mark - UITableViewDataSource & Delegate

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.filteredLocalMods.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    ModTableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"ModCell" forIndexPath:indexPath];
    cell.delegate = self;

    ModItem *mod = self.filteredLocalMods[indexPath.row];
    [cell configureWithMod:mod displayMode:ModTableViewCellDisplayModeLocal];

    // Update badge: show arrow.up.circle.fill for mods with available updates.
    [cell setUpdateAvailable:(self.updateResultsByPath[mod.filePath] != nil)];

    // Hide the enable switch in selection mode (to avoid visual conflict with the checkmark); restore it in normal mode.
    cell.toggleSwitch.hidden = self.selectModeEnabled;

    return cell;
}

- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section {
    return [ResourceListViewController cardSpacingHeaderView];
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section {
    return ResourceListCardSpacing;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    if (self.selectModeEnabled) {
        // Editing (selection) mode: row taps toggle selection and update the title count.
        [self updateSelectModeTitle];
    } else {
        [tableView deselectRowAtIndexPath:indexPath animated:YES];
    }
}

- (void)tableView:(UITableView *)tableView didDeselectRowAtIndexPath:(NSIndexPath *)indexPath {
    if (self.selectModeEnabled) {
        [self updateSelectModeTitle];
    }
}

- (UISwipeActionsConfiguration *)tableView:(UITableView *)tableView trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath {
    // Disable swipe-to-delete in selection mode to prevent accidental actions.
    if (self.selectModeEnabled) return nil;

    UIContextualAction *deleteAction = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleDestructive
                                                                               title:localize(@"resman.common.delete", nil)
                                                                             handler:^(UIContextualAction *_Nonnull action, __kindof UIView *_Nonnull sourceView, void (^_Nonnull completionHandler)(BOOL)) {
        ModItem *modToDelete = self.filteredLocalMods[indexPath.row];
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:localize(@"resman.common.confirm_delete", nil)
                                                                       message:[NSString stringWithFormat:localize(@"resman.common.delete_message_irreversible", nil), modToDelete.displayName]
                                                                preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:localize(@"resman.common.cancel", nil) style:UIAlertActionStyleCancel handler:^(UIAlertAction *_Nonnull a) {
            completionHandler(NO);
        }]];
        [alert addAction:[UIAlertAction actionWithTitle:localize(@"resman.common.delete", nil) style:UIAlertActionStyleDestructive handler:^(UIAlertAction *_Nonnull a) {
            NSError *error = nil;
            [[ModService sharedService] deleteMod:modToDelete error:&error];
            if (error) {
                NSLog(@"[ModsManager] Error deleting mod: %@", error);
                completionHandler(NO);
            } else {
                // Synchronize the data source and delete the row.
                NSUInteger idxFull = [self.localMods indexOfObject:modToDelete];
                if (idxFull != NSNotFound) [self.localMods removeObjectAtIndex:idxFull];
                [self.modDates removeObjectForKey:modToDelete.filePath];
                [self.updateResultsByPath removeObjectForKey:modToDelete.filePath];
                [self.filteredLocalMods removeObjectAtIndex:indexPath.row];
                [tableView deleteRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationAutomatic];
                completionHandler(YES);
            }
        }]];
        [self presentViewController:alert animated:YES completion:nil];
    }];
    deleteAction.backgroundColor = [UIColor systemRedColor];

    UISwipeActionsConfiguration *configuration = [UISwipeActionsConfiguration configurationWithActions:@[deleteAction]];
    configuration.performsFirstActionWithFullSwipe = YES;
    return configuration;
}

#pragma mark - Batch selection mode (integrated with the base-class toolbar)

- (void)enterSelectMode {
    if (self.filteredLocalMods.count == 0) return;
    [self setSelectMode:YES]; // The base class handles editing mode + toolbar slide-in + selectModeDidChange.
}

- (void)exitSelectMode {
    [self setSelectMode:NO];
}

- (void)selectModeDidChange:(BOOL)enabled {
    if (enabled) {
        // Populate batch-action buttons (lazily created once, then retained in the stack as the toolbar appears/disappears).
        if (!self.batchEnableButton) {
            self.batchEnableButton = [self makeBatchActionButtonWithTitle:localize(@"resman.common.enable", nil) tintColor:[UIColor systemGreenColor]];
            [self.batchEnableButton addTarget:self action:@selector(batchEnableTapped) forControlEvents:UIControlEventTouchUpInside];

            self.batchDisableButton = [self makeBatchActionButtonWithTitle:localize(@"resman.common.disable", nil) tintColor:[UIColor systemOrangeColor]];
            [self.batchDisableButton addTarget:self action:@selector(batchDisableTapped) forControlEvents:UIControlEventTouchUpInside];

            self.batchDeleteButton = [self makeBatchActionButtonWithTitle:localize(@"resman.common.delete", nil) tintColor:[UIColor systemRedColor]];
            [self.batchDeleteButton addTarget:self action:@selector(batchDeleteTapped) forControlEvents:UIControlEventTouchUpInside];

            [self.batchActionStack addArrangedSubview:self.batchEnableButton];
            [self.batchActionStack addArrangedSubview:self.batchDisableButton];
            [self.batchActionStack addArrangedSubview:self.batchDeleteButton];
        }
    }
    [self updateNavigationButtons];
    [self.tableView reloadData];
}

/// Batch-action pill button.
- (UIButton *)makeBatchActionButtonWithTitle:(NSString *)title tintColor:(UIColor *)color {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    button.translatesAutoresizingMaskIntoConstraints = NO;
    [button setTitle:title forState:UIControlStateNormal];
    button.titleLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightMedium];
    [button setTitleColor:color forState:UIControlStateNormal];
    button.backgroundColor = [color colorWithAlphaComponent:0.14];
    button.contentEdgeInsets = UIEdgeInsetsMake(6, 14, 6, 14);
    button.layer.cornerRadius = 15.0;
    button.layer.cornerCurve = kCACornerCurveContinuous;
    button.layer.masksToBounds = YES;
    [button.heightAnchor constraintEqualToConstant:30].active = YES;
    [button setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    [button setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    return button;
}

/// Currently selected ModItem list (based on the base class's selectedIndexPaths).
- (NSArray<ModItem *> *)selectedModItems {
    NSMutableArray<ModItem *> *items = [NSMutableArray array];
    NSArray<NSIndexPath *> *indexPaths = [self.selectedIndexPaths sortedArrayUsingComparator:^NSComparisonResult(NSIndexPath *a, NSIndexPath *b) {
        return [a compare:b];
    }];
    for (NSIndexPath *indexPath in indexPaths) {
        if (indexPath.row < (NSInteger)self.filteredLocalMods.count) {
            [items addObject:self.filteredLocalMods[indexPath.row]];
        }
    }
    return items;
}

- (void)batchEnableTapped {
    [self batchSetDisabled:NO];
}

- (void)batchDisableTapped {
    [self batchSetDisabled:YES];
}

/// Batch enable (target=NO) / disable (target=YES): toggle only items whose state does not match.
- (void)batchSetDisabled:(BOOL)target {
    NSArray<ModItem *> *mods = [self selectedModItems];
    if (mods.count == 0) {
        [self showDialogWithTitle:localize(@"resman.common.notice", nil) message:localize(@"resman.mods.none_selected", nil)];
        return;
    }

    NSInteger success = 0, failed = 0;
    for (ModItem *mod in mods) {
        if (mod.disabled == target) continue; // State already matches; skip.
        NSError *error = nil;
        if ([[ModService sharedService] toggleEnableForMod:mod error:&error]) {
            success++;
        } else {
            failed++;
            NSLog(@"[ModsManager] Batch toggle failed: %@ - %@", mod.displayName, error);
        }
    }

    [self setSelectMode:NO];
    [self loadMods]; // Filename (.disabled suffix) changed; rescan.

    NSString *verb = target ? localize(@"resman.common.disable", nil) : localize(@"resman.common.enable", nil);
    if (failed > 0) {
        [self showDialogWithTitle:[NSString stringWithFormat:localize(@"resman.mods.batch.toggle_complete", nil), verb]
                         message:[NSString stringWithFormat:localize(@"resman.mods.batch.result_message", nil), (long)success, (long)failed]];
    }
}

- (void)batchDeleteTapped {
    NSArray<ModItem *> *mods = [self selectedModItems];
    if (mods.count == 0) {
        [self showDialogWithTitle:localize(@"resman.common.notice", nil) message:localize(@"resman.mods.none_selected", nil)];
        return;
    }

    UIAlertController *alert = [UIAlertController alertControllerWithTitle:localize(@"resman.common.batch_delete", nil)
                                                                   message:[NSString stringWithFormat:localize(@"resman.mods.batch.delete_message", nil), (long)mods.count]
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:localize(@"resman.common.cancel", nil) style:UIAlertActionStyleCancel handler:nil]];
    __weak typeof(self) weakSelf = self;
    [alert addAction:[UIAlertAction actionWithTitle:localize(@"resman.common.delete", nil) style:UIAlertActionStyleDestructive handler:^(UIAlertAction *_Nonnull action) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;

        NSMutableArray<ModItem *> *failedMods = [NSMutableArray array];
        for (ModItem *mod in mods) {
            NSError *error = nil;
            if (![[ModService sharedService] deleteMod:mod error:&error]) {
                NSLog(@"[ModsManager] Batch delete failed: %@ - %@", mod.displayName, error);
                [failedMods addObject:mod];
            } else {
                [strongSelf.modDates removeObjectForKey:mod.filePath];
                [strongSelf.updateResultsByPath removeObjectForKey:mod.filePath];
            }
        }

        [strongSelf setSelectMode:NO];
        [strongSelf loadMods]; // Rescan and synchronize the data source.

        if (failedMods.count > 0) {
            NSMutableArray<NSString *> *names = [NSMutableArray array];
            for (ModItem *m in failedMods) [names addObject:m.displayName ?: m.fileName];
            [strongSelf showDialogWithTitle:[NSString stringWithFormat:localize(@"resman.common.delete_complete_failures", nil), (long)failedMods.count]
                                    message:[names componentsJoinedByString:@"\n"]];
        }
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

#pragma mark - Import Mod

- (void)importModTapped {
    NSError *dirError = nil;
    NSString *modsDir = [[ModService sharedService] ensureModsFolderForProfile:nil error:&dirError];
    if (!modsDir) {
        [self showDialogWithTitle:localize(@"resman.common.cannot_import", nil) message:dirError.localizedDescription ?: localize(@"resman.mods.dir_not_found", nil)];
        return;
    }

    UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc] initWithDocumentTypes:@[@"com.sun.java.jar", @"public.item"]
                                                                                                   inMode:UIDocumentPickerModeImport];
    picker.allowsMultipleSelection = YES;
    picker.delegate = self;
    picker.title = localize(@"resman.mods.picker_title", nil);
    [self presentViewController:picker animated:YES completion:nil];
}

- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    if (urls.count == 0) return;

    NSError *dirError = nil;
    NSString *modsDir = [[ModService sharedService] ensureModsFolderForProfile:nil error:&dirError];
    if (!modsDir) {
        [self showDialogWithTitle:localize(@"resman.common.import_failed", nil) message:dirError.localizedDescription ?: localize(@"resman.mods.dir_not_found", nil)];
        return;
    }

    NSFileManager *fm = [NSFileManager defaultManager];
    NSInteger successCount = 0;
    NSMutableArray<NSString *> *failedFiles = [NSMutableArray array];

    for (NSURL *url in urls) {
        BOOL accessing = [url startAccessingSecurityScopedResource];
        @try {
            NSString *fileName = url.lastPathComponent;
            NSString *destPath = [modsDir stringByAppendingPathComponent:fileName];
            // Handle files with the same name.
            if ([fm fileExistsAtPath:destPath]) {
                NSString *baseName = [fileName stringByDeletingPathExtension];
                NSString *ext = [fileName pathExtension];
                destPath = [modsDir stringByAppendingPathComponent:[NSString stringWithFormat:@"%@_copy.%@", baseName, ext]];
            }
            NSError *copyError = nil;
            [fm copyItemAtPath:url.path toPath:destPath error:&copyError];
            if (copyError) {
                [failedFiles addObject:[NSString stringWithFormat:@"%@: %@", fileName, copyError.localizedDescription]];
            } else {
                successCount++;
            }
        } @finally {
            if (accessing) [url stopAccessingSecurityScopedResource];
        }
    }

    [self loadMods];

    if (failedFiles.count > 0) {
        [self showDialogWithTitle:[NSString stringWithFormat:localize(@"resman.common.import_result", nil), (long)successCount, (long)failedFiles.count]
                          message:[failedFiles componentsJoinedByString:@"\n"]];
    } else {
        NSLog(@"[ModsManager] Successfully imported %ld mods", (long)successCount);
    }
}

#pragma mark - ModTableViewCellDelegate

- (void)modCellDidTapToggle:(UITableViewCell *)cell {
    NSIndexPath *indexPath = [self.tableView indexPathForCell:cell];
    if (!indexPath) return;

    ModItem *mod = self.filteredLocalMods[indexPath.row];
    NSError *error = nil;
    BOOL success = [[ModService sharedService] toggleEnableForMod:mod error:&error];
    if (!success) {
        NSLog(@"[ModsManager] Error toggling mod: %@", error);
    }
    // Regardless of success, refresh switch appearance from the service state (mod.disabled does not change on failure).
    if ([cell isKindOfClass:[ModTableViewCell class]]) {
        [(ModTableViewCell *)cell updateToggleState:mod.disabled];
    }
}

- (void)modCellDidTapOpenLink:(UITableViewCell *)cell {
    NSIndexPath *indexPath = [self.tableView indexPathForCell:cell];
    if (!indexPath) return;

    ModItem *modItem = self.filteredLocalMods[indexPath.row];
    if (modItem.onlineID.length > 0) {
        NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"https://modrinth.com/mod/%@", modItem.onlineID]];
        if (url) {
            [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil];
        }
    } else {
        [self showDialogWithTitle:localize(@"resman.mods.link_unavailable", nil) message:localize(@"resman.mods.link_unavailable_message", nil)];
    }
}

#pragma mark - Built-in update flow (state machine: idle → checking → confirmation → downloading/replacing → complete → idle)

/// Enters update-busy state: disables buttons and shows a navigation-bar spinner + stage text.
- (void)enterUpdateBusyWithText:(NSString *)text {
    self.isUpdateBusy = YES;
    self.updateBusyText = [text copy];
    [self updateNavigationButtons];
}

/// Updates stage text while busy (changes the title only; does not rebuild the button group).
- (void)setUpdateBusyTextOnly:(NSString *)text {
    self.updateBusyText = [text copy];
    self.navigationItem.title = self.updateBusyText;
}

/// Exits update-busy state: restores buttons and title.
- (void)exitUpdateBusy {
    self.isUpdateBusy = NO;
    self.updateBusyText = nil;
    [self.navSpinner stopAnimating];
    [self updateNavigationButtons];
}

/// Navigation-bar "Check for updates" entry point:
/// 1) Fill in each mod's SHA1 (required for Modrinth reverse lookup).
/// 2) Call ModUpdateService checkUpdateForMod concurrently with dispatch_group and a limit of 3.
/// 3) Classify results: update available / up to date (recognized, no update) / unrecognized (not found on either source).
/// 4) If updates are available, show a confirmation dialog; otherwise report "All mods are up to date."
- (void)checkForUpdates {
    if (self.isUpdateBusy) return; // Prevent duplicate triggers.
    if (self.localMods.count == 0) {
        [self showDialogWithTitle:localize(@"resman.common.notice", nil) message:localize(@"resman.mods.no_local_for_update", nil)];
        return;
    }

    // Resolve gameVersion and loader from the current profile's lastVersionId.
    NSString *lastVersionId = PLProfiles.current.selectedProfile[@"lastVersionId"];
    if (lastVersionId.length == 0) {
        [self showDialogWithTitle:localize(@"resman.common.notice", nil) message:localize(@"resman.mods.no_version_info", nil)];
        return;
    }
    NSString *gameVersion = nil;
    NSString *loader = nil;
    NSArray<NSString *> *loaders = @[@"forge", @"fabric", @"neoforge", @"quilt"];
    for (NSString *name in loaders) {
        NSRange range = [lastVersionId rangeOfString:[NSString stringWithFormat:@"-%@-", name]];
        if (range.location != NSNotFound) {
            gameVersion = [lastVersionId substringToIndex:range.location];
            loader = name;
            break;
        }
    }
    if (!gameVersion) {
        // Plain <mc> format, no loader.
        gameVersion = lastVersionId;
        loader = nil;
    }

    // Exit selection mode first if active (the data may change afterward).
    if (self.selectModeEnabled) {
        [self setSelectMode:NO];
    }

    NSArray<ModItem *> *mods = [self.localMods copy];
    [self enterUpdateBusyWithText:localize(@"resman.mods.update.checking", nil)];

    dispatch_queue_t queue = dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0);
    __weak typeof(self) weakSelf = self;
    dispatch_async(queue, ^{
        // Stage 1: fill in SHA1 (required for Modrinth reverse lookup; calculate large files incrementally in the background).
        for (ModItem *mod in mods) {
            if (mod.fileSHA1.length == 0) {
                mod.fileSHA1 = ModsManagerSHA1ForFile(mod.filePath);
            }
        }

        // Stage 2: concurrent checks (dispatch_group aggregation + semaphore limit of 3).
        dispatch_group_t group = dispatch_group_create();
        dispatch_semaphore_t semaphore = dispatch_semaphore_create(3);
        NSObject *lock = [[NSObject alloc] init];
        NSMutableArray<ModUpdateResult *> *updatable = [NSMutableArray array];
        __block NSInteger unrecognized = 0;
        __block NSInteger completed = 0;
        NSInteger total = mods.count;

        for (ModItem *mod in mods) {
            dispatch_group_enter(group);
            dispatch_async(queue, ^{
                dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);
                [[ModUpdateService sharedService] checkUpdateForMod:mod
                                                        gameVersion:gameVersion
                                                             loader:loader
                                                        projectType:@"mod"
                                                         completion:^(ModUpdateResult *_Nullable result) {
                    // The service guarantees a main-thread callback.
                    __strong typeof(weakSelf) strongSelf = weakSelf;
                    @synchronized(lock) {
                        if (result) {
                            if ([result hasUpdate]) [updatable addObject:result];
                        } else {
                            unrecognized++; // Not found on either source → unrecognized.
                        }
                        completed++;
                    }
                    if (strongSelf) {
                        [strongSelf setUpdateBusyTextOnly:[NSString stringWithFormat:localize(@"resman.mods.update.checking_progress", nil), (long)completed, (long)total]];
                    }
                    dispatch_semaphore_signal(semaphore);
                    dispatch_group_leave(group);
                }];
            });
        }

        dispatch_group_notify(group, dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf) return;
            [strongSelf exitUpdateBusy];

            // Badge: show an update marker for mods with available updates.
            [strongSelf.updateResultsByPath removeAllObjects];
            for (ModUpdateResult *result in updatable) {
                if (result.localFilePath.length > 0) {
                    strongSelf.updateResultsByPath[result.localFilePath] = result;
                }
            }
            [strongSelf.tableView reloadData];

            if (updatable.count == 0) {
                NSString *message = localize(@"resman.mods.update.all_latest", nil);
                if (unrecognized > 0) {
                    message = [NSString stringWithFormat:localize(@"resman.mods.update.all_latest_skipped", nil), (long)unrecognized];
                }
                [strongSelf showDialogWithTitle:localize(@"resman.mods.check_update", nil) message:message];
            } else {
                [strongSelf presentUpdateConfirmAlertWithResults:[updatable copy] skipped:unrecognized];
            }
        });
    });
}

/// Update confirmation dialog: lists each item (name, current version → new version), with Update All / Cancel actions.
- (void)presentUpdateConfirmAlertWithResults:(NSArray<ModUpdateResult *> *)results skipped:(NSInteger)skipped {
    if (results.count == 0) return;

    // Build list text (truncate long lists; show at most 8 items).
    NSMutableArray<NSString *> *lines = [NSMutableArray array];
    NSUInteger maxLines = 8;
    for (NSUInteger i = 0; i < results.count && i < maxLines; i++) {
        ModUpdateResult *result = results[i];
        NSString *name = result.localFilePath.lastPathComponent ?: localize(@"resman.common.unknown_file", nil);
        // Prefer the ModItem display name.
        for (ModItem *mod in self.localMods) {
            if ([mod.filePath isEqualToString:result.localFilePath] && mod.displayName.length > 0) {
                name = mod.displayName;
                break;
            }
        }
        NSString *current = result.currentVersion.versionNumber ?: @"?";
        NSString *target = result.candidateVersions.firstObject.versionNumber ?: localize(@"resman.mods.update.latest", nil);
        [lines addObject:[NSString stringWithFormat:@"%@\n%@ → %@", name, current, target]];
    }
    if (results.count > maxLines) {
        [lines addObject:[NSString stringWithFormat:localize(@"resman.mods.update.more_total", nil), (long)results.count]];
    }
    if (skipped > 0) {
        [lines addObject:[NSString stringWithFormat:localize(@"resman.mods.update.skipped_line", nil), (long)skipped]];
    }

    UIAlertController *alert = [UIAlertController alertControllerWithTitle:[NSString stringWithFormat:localize(@"resman.mods.update.found_title", nil), (long)results.count]
                                                                   message:[lines componentsJoinedByString:@"\n"]
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:localize(@"resman.common.cancel", nil) style:UIAlertActionStyleCancel handler:nil]];
    __weak typeof(self) weakSelf = self;
    [alert addAction:[UIAlertAction actionWithTitle:localize(@"resman.mods.update.update_all", nil) style:UIAlertActionStyleDefault handler:^(UIAlertAction *_Nonnull action) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (strongSelf) {
            [strongSelf performModUpdatesWithResults:results skipped:skipped];
        }
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

/// Performs updates: concurrently downloads to a temporary directory (PLDownloadClient, with SHA1 validation + mirror candidates),
/// then replaces files after all downloads complete (delete old → move new, preserving the old file's disabled state),
/// clears badges, reloads the list, and shows a summary.
- (void)performModUpdatesWithResults:(NSArray<ModUpdateResult *> *)results skipped:(NSInteger)skipped {
    if (results.count == 0 || self.isUpdateBusy) return;

    // Build the download task list.
    NSMutableArray<ModUpdateTask *> *tasks = [NSMutableArray array];
    for (ModUpdateResult *result in results) {
        ModVersion *target = result.candidateVersions.firstObject;
        if (!target) continue; // No candidate version; skip.
        ModUpdateTask *task = [[ModUpdateTask alloc] init];
        task.result = result;
        task.targetVersion = target;
        for (ModItem *mod in self.localMods) {
            if ([mod.filePath isEqualToString:result.localFilePath]) {
                task.mod = mod;
                break;
            }
        }
        [tasks addObject:task];
    }
    if (tasks.count == 0) return;

    // Temporary directory.
    NSString *tempDir = [NSTemporaryDirectory() stringByAppendingPathComponent:
        [NSString stringWithFormat:@"ModUpdate_%@", [[NSUUID UUID] UUIDString]]];
    NSError *mkError = nil;
    [[NSFileManager defaultManager] createDirectoryAtPath:tempDir
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:&mkError];
    if (mkError) {
        [self showDialogWithTitle:localize(@"resman.mods.update.failed_title", nil)
                         message:[NSString stringWithFormat:localize(@"resman.mods.update.temp_dir_failed", nil), mkError.localizedDescription]];
        return;
    }

    [self enterUpdateBusyWithText:[NSString stringWithFormat:localize(@"resman.mods.update.downloading", nil), 0L, (long)tasks.count]];

    dispatch_queue_t queue = dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0);
    dispatch_group_t group = dispatch_group_create();
    dispatch_semaphore_t semaphore = dispatch_semaphore_create(4);
    NSObject *progressLock = [[NSObject alloc] init];
    __block NSInteger downloadDone = 0;
    NSInteger total = tasks.count;
    __weak typeof(self) weakSelf = self;

    for (ModUpdateTask *task in tasks) {
        // Extract download information from primaryFile (url / filename / sha1).
        NSDictionary *primaryFile = task.targetVersion.primaryFile;
        if (![primaryFile isKindOfClass:[NSDictionary class]]) {
            task.downloadSucceeded = NO;
            continue;
        }
        NSString *urlString = [primaryFile[@"url"] isKindOfClass:[NSString class]] ? primaryFile[@"url"] : nil;
        NSString *fileName = [primaryFile[@"filename"] isKindOfClass:[NSString class]] ? primaryFile[@"filename"] : nil;
        NSDictionary *hashes = [primaryFile[@"hashes"] isKindOfClass:[NSDictionary class]] ? primaryFile[@"hashes"] : nil;
        NSString *sha1 = [hashes[@"sha1"] isKindOfClass:[NSString class]] ? hashes[@"sha1"] : nil;
        NSURL *url = urlString.length > 0 ? [NSURL URLWithString:urlString] : nil;

        if (!url || fileName.length == 0) {
            task.downloadSucceeded = NO;
            continue;
        }

        dispatch_group_enter(group);
        dispatch_async(queue, ^{
            dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);

            PLDownloadRequest *request = [[PLDownloadRequest alloc] init];
            // Mirror candidates (official CDN + MCIM mirror, sorted by user policy).
            request.candidateURLs = [PLMirrorCenter candidateURLsForOriginalURL:url
                                                                   resourceType:PLMirrorResourceTypeAssetDownload];
            // The version file provides SHA1 → enable validation (the downloader retries failures using mirror/backoff logic).
            request.expectedSHA1 = sha1.length > 0 ? sha1 : nil;
            request.destinationPath = [tempDir stringByAppendingPathComponent:fileName];
            request.taskIdentifier = [NSString stringWithFormat:@"modupdate-%@", [[NSUUID UUID] UUIDString]];
            request.allowZipFallbackCheck = YES; // Use ZIP EOCD as a fallback when SHA1 is unavailable.

            [[PLDownloadClient sharedClient] startRequest:request
                                                 progress:nil
                                                    speed:nil
                                               completion:^(BOOL success, NSError *_Nullable error) {
                // Callback runs on the downloader's serial queue (not the main thread).
                if (success) {
                    task.downloadSucceeded = YES;
                    task.tempPath = request.destinationPath;
                } else {
                    task.downloadSucceeded = NO;
                    task.tempPath = nil;
                    NSLog(@"[ModsManager] Update download failed (%@): %@", fileName, error);
                }

                NSInteger done;
                @synchronized(progressLock) { downloadDone++; done = downloadDone; }
                dispatch_async(dispatch_get_main_queue(), ^{
                    __strong typeof(weakSelf) strongSelf = weakSelf;
                    if (strongSelf) {
                        [strongSelf setUpdateBusyTextOnly:[NSString stringWithFormat:localize(@"resman.mods.update.downloading", nil), (long)done, (long)total]];
                    }
                });

                dispatch_semaphore_signal(semaphore);
                dispatch_group_leave(group);
            }];
        });
    }

    dispatch_group_notify(group, dispatch_get_main_queue(), ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) {
            [[NSFileManager defaultManager] removeItemAtPath:tempDir error:nil];
            return;
        }

        // Stage: replace files (perform file operations in the background, then return to the main thread for the summary).
        [strongSelf setUpdateBusyTextOnly:localize(@"resman.mods.update.replacing", nil)];
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
            NSFileManager *fm = [NSFileManager defaultManager];
            NSInteger successCount = 0;
            NSInteger failCount = 0;

            for (ModUpdateTask *task in tasks) {
                NSString *fileName = task.result.localFilePath.lastPathComponent ?: localize(@"resman.common.unknown_file", nil);
                if (!task.downloadSucceeded || task.tempPath.length == 0) {
                    failCount++;
                    continue;
                }
                // Prefer the downloaded filename (the new version's filename may have changed).
                NSDictionary *primaryFile = task.targetVersion.primaryFile;
                NSString *downloadName = [primaryFile isKindOfClass:[NSDictionary class]]
                    ? ([primaryFile[@"filename"] isKindOfClass:[NSString class]] ? primaryFile[@"filename"] : nil)
                    : nil;
                if (downloadName.length > 0) fileName = downloadName;

                NSString *oldPath = task.result.localFilePath;
                NSString *oldDir = [oldPath stringByDeletingLastPathComponent];
                // If the old file was disabled (has a .disabled suffix), disable the new file too to preserve the user's intent.
                BOOL keepDisabled = [oldPath.lowercaseString hasSuffix:@".disabled"];
                NSString *newPath = [oldDir stringByAppendingPathComponent:fileName];
                if (keepDisabled && ![newPath.lowercaseString hasSuffix:@".disabled"]) {
                    newPath = [newPath stringByAppendingString:@".disabled"];
                }

                @try {
                    // Delete old → move new (ZL2 ModUpdater replacement logic).
                    if ([fm fileExistsAtPath:oldPath]) {
                        [fm removeItemAtPath:oldPath error:nil];
                    }
                    if (![newPath isEqualToString:oldPath] && [fm fileExistsAtPath:newPath]) {
                        [fm removeItemAtPath:newPath error:nil];
                    }
                    NSError *moveError = nil;
                    if ([fm moveItemAtPath:task.tempPath toPath:newPath error:&moveError]) {
                        successCount++;
                        task.tempPath = nil; // Already moved; avoid misclassification later.
                    } else {
                        failCount++;
                        NSLog(@"[ModsManager] Update replace failed (%@): %@", fileName, moveError);
                    }
                } @catch (NSException *exception) {
                    failCount++;
                    NSLog(@"[ModsManager] Update replace exception (%@): %@", fileName, exception);
                }
            }

            // Clean up the temporary directory.
            [fm removeItemAtPath:tempDir error:nil];

            dispatch_async(dispatch_get_main_queue(), ^{
                __strong typeof(weakSelf) innerSelf = weakSelf;
                if (!innerSelf) return;
                // Clear update badges + exit busy state + reload the list.
                [innerSelf.updateResultsByPath removeAllObjects];
                [innerSelf exitUpdateBusy];
                [innerSelf loadMods];
                [innerSelf showDialogWithTitle:localize(@"resman.mods.update.done_title", nil)
                                      message:[NSString stringWithFormat:localize(@"resman.mods.update.done_message", nil),
                                               (long)successCount, (long)failCount, (long)skipped]];
            });
        });
    });
}

#pragma mark - Utility methods

- (void)showDialogWithTitle:(NSString *)title message:(NSString *)message {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:localize(@"resman.common.ok", nil) style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

@end
