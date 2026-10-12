//
//  DataPacksManagerViewController.m
//  Amethyst
//
//  Data-pack management view-controller implementation (inherits ResourceListViewController).
//  Uses DataPackService for local scanning, enable/disable, and deletion.
//  Online downloads have moved to the unified download screen; the empty state provides a "Go to Downloads" button.
//  Note: iOS cannot select a world. Data packs are in <gameDir>/datapacks/ and must be moved manually
//  to saves/<world name>/datapacks/.
//

#import "DataPacksManagerViewController.h"
#import "DataPackService.h"
#import "DataPackItem.h"
#import "ResourceCardTableViewCell.h"
#import "DownloadViewController.h"
#import "utils.h"

#pragma mark - Data-pack card cell (lightweight subclass of Air-Design card base class in this file)

@interface DataPackCardCell : ResourceCardTableViewCell
/// Enable/disable switch callback (set by the VC in cellForRow; parameter is the cell that triggered the switch).
@property (nonatomic, copy, nullable) void (^toggleHandler)(DataPackCardCell *cell);
@end

@implementation DataPackCardCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        // Attach the switch event to the cell itself (only once) to avoid duplicate addTarget calls on reuse.
        [self.toggleSwitch addTarget:self action:@selector(internalSwitchChanged:) forControlEvents:UIControlEventValueChanged];
    }
    return self;
}

- (void)internalSwitchChanged:(UISwitch *)sender {
    if (self.toggleHandler) self.toggleHandler(self);
}

- (void)configureWithDataPack:(DataPackItem *)item {
    NSString *title = item.displayName.length > 0 ? item.displayName : item.fileName;
    // Subtitle: pack_format (fall back to the filename if unavailable).
    NSString *subtitle = item.packFormat ? [NSString stringWithFormat:localize(@"resman.common.pack_format", nil), item.packFormat] : item.fileName;
    // Metadata: data-pack description.
    NSString *detail = item.dataPackDescription.length > 0 ? item.dataPackDescription : nil;

    [self configureWithIcon:@"doc.text.fill"
                  iconColor:[UIColor systemTealColor]
                      title:title
                   subtitle:subtitle
                     detail:detail];

    // Enable/disable switch (toggles the .disabled suffix).
    self.toggleSwitch.hidden = NO;
    [self.toggleSwitch setOn:!item.disabled animated:NO];
    self.contentView.alpha = item.disabled ? 0.5 : 1.0;
}

@end

#pragma mark - View controller

@interface DataPacksManagerViewController () <UITableViewDataSource, UITableViewDelegate, UISearchBarDelegate, UIDocumentPickerDelegate>

@property (nonatomic, strong) UIBarButtonItem *refreshButton;
@property (nonatomic, strong) UIBarButtonItem *importButton;

@property (nonatomic, strong) NSMutableArray<DataPackItem *> *localItems;
@property (nonatomic, strong) NSMutableArray<DataPackItem *> *filteredLocalItems;

// Top hint banner (explains saves/<world name>/datapacks/), displayed as tableHeaderView.
@property (nonatomic, strong) UIView *tipHeaderView;
@property (nonatomic, assign) CGFloat lastTipHeaderWidth;

// Play the cascading first-screen entrance animation only once.
@property (nonatomic, assign) BOOL didPlayChainAnimation;

@end

@implementation DataPacksManagerViewController

#pragma mark - Init

- (instancetype)init {
    // Integrate with the resource-list base class: title + semantic data-pack icon (teal / doc.text.fill).
    // Preserve compatibility with existing callers that create this using [[DataPacksManagerViewController alloc] init].
    return [super initWithTitle:localize(@"resman.datapacks.title", nil) resourceTypeIcon:@"doc.text.fill" iconColor:[UIColor systemTealColor]];
}

#pragma mark - Lifecycle

- (void)viewDidLoad {
    [super viewDidLoad];
    // Online downloads moved to the Downloads screen: fixed to local mode (currentMode and related
    // properties remain only for compatibility with existing declarations in .h).
    self.currentMode = DataPacksManagerModeLocal;
    self.localItems = [NSMutableArray array];
    self.filteredLocalItems = [NSMutableArray array];
    self.onlineSearchResults = [NSMutableArray array];

    // Search bar (built by the base class): search locally only.
    self.searchBar.delegate = self;
    self.searchBar.placeholder = localize(@"resman.datapacks.search_placeholder", nil);

    // List (built by the base class): register the card cell + pull-to-refresh.
    [self.tableView registerClass:[DataPackCardCell class] forCellReuseIdentifier:@"DataPackCardCell"];
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    self.tableView.rowHeight = 84;

    UIRefreshControl *rc = [UIRefreshControl new];
    [rc addTarget:self action:@selector(handleRefresh:) forControlEvents:UIControlEventValueChanged];
    self.tableView.refreshControl = rc;

    // Navigation buttons: close on the left; import + refresh on the right.
    UIBarButtonItem *closeButton = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:self action:@selector(closeTapped)];
    self.refreshButton = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemRefresh target:self action:@selector(handleRefresh:)];
    UIImage *importImage = [UIImage systemImageNamed:@"square.and.arrow.down"] ?: [UIImage systemImageNamed:@"plus"];
    self.importButton = [[UIBarButtonItem alloc] initWithImage:importImage style:UIBarButtonItemStylePlain target:self action:@selector(importTapped)];
    self.importButton.accessibilityLabel = localize(@"resman.datapacks.import", nil);
    self.navigationItem.leftBarButtonItem = closeButton;
    self.navigationItem.rightBarButtonItems = @[self.importButton, self.refreshButton];

    // Top hint banner (retain the existing hint text).
    [self setupTipHeaderView];

    [self refreshLocalList];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    // Recalculate the hint-banner height when the tableView width is determined/changes
    // (initial layout, rotation).
    CGFloat width = CGRectGetWidth(self.tableView.bounds);
    if (width > 0 && fabs(width - self.lastTipHeaderWidth) > 0.5) {
        self.lastTipHeaderWidth = width;
        [self fitTipHeaderToWidth:width];
    }
}

#pragma mark - Top hint banner

- (void)setupTipHeaderView {
    // Data-pack directory information banner: lightweight card style (translucent base + 0.5pt stroke + 10pt corner radius).
    UIView *container = [[UIView alloc] init];
    container.backgroundColor = [[UIColor whiteColor] colorWithAlphaComponent:0.06];
    container.layer.cornerRadius = 10.0;
    container.layer.cornerCurve = kCACornerCurveContinuous;
    container.layer.borderWidth = 0.5;
    container.layer.borderColor = [[UIColor whiteColor] colorWithAlphaComponent:0.10].CGColor;
    container.clipsToBounds = YES;

    UILabel *tipLabel = [[UILabel alloc] init];
    tipLabel.translatesAutoresizingMaskIntoConstraints = NO;
    tipLabel.font = [UIFont systemFontOfSize:11];
    tipLabel.textColor = [UIColor systemOrangeColor];
    tipLabel.textAlignment = NSTextAlignmentCenter;
    tipLabel.numberOfLines = 0;
    tipLabel.text = localize(@"resman.datapacks.tip", nil);
    [container addSubview:tipLabel];
    [NSLayoutConstraint activateConstraints:@[
        [tipLabel.topAnchor constraintEqualToAnchor:container.topAnchor constant:8],
        [tipLabel.leadingAnchor constraintEqualToAnchor:container.leadingAnchor constant:10],
        [tipLabel.trailingAnchor constraintEqualToAnchor:container.trailingAnchor constant:-10],
        [tipLabel.bottomAnchor constraintEqualToAnchor:container.bottomAnchor constant:-8],
    ]];
    self.tipHeaderView = container;
}

- (void)fitTipHeaderToWidth:(CGFloat)width {
    if (width <= 0 || !self.tipHeaderView) return;
    // Temporary width constraint for adaptive height calculation; remove it afterward.
    NSLayoutConstraint *widthConstraint = [self.tipHeaderView.widthAnchor constraintEqualToConstant:width];
    widthConstraint.active = YES;
    CGSize size = [self.tipHeaderView systemLayoutSizeFittingSize:UILayoutFittingCompressedSize];
    widthConstraint.active = NO;
    CGRect frame = CGRectMake(0, 0, width, ceil(size.height));
    if (!CGRectEqualToRect(self.tipHeaderView.frame, frame)) {
        self.tipHeaderView.frame = frame;
        self.tableView.tableHeaderView = self.tipHeaderView;
    }
}

#pragma mark - Close

- (void)closeTapped {
    // Support two containers:
    // - Pushed into a UINavigationController (from ProfileSettingsViewController): pop to the previous page.
    // - Presented as a modal (legacy call path): dismiss.
    if (self.navigationController && self.navigationController.viewControllers.firstObject != self) {
        [self.navigationController popViewControllerAnimated:YES];
    } else {
        [self dismissViewControllerAnimated:YES completion:nil];
    }
}

#pragma mark - Import data pack

- (void)importTapped {
    NSError *dirError = nil;
    NSString *dir = [[DataPackService sharedService] ensureDataPacksFolderForProfile:self.profileName error:&dirError];
    if (!dir) {
        [self showSimpleAlertWithTitle:localize(@"resman.common.cannot_import", nil) message:dirError.localizedDescription ?: localize(@"resman.datapacks.dir_not_found", nil)];
        return;
    }

    UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc] initWithDocumentTypes:@[@"public.zip", @"public.item"] inMode:UIDocumentPickerModeImport];
    picker.allowsMultipleSelection = YES;
    picker.delegate = self;
    picker.title = localize(@"resman.datapacks.picker_title", nil);
    [self presentViewController:picker animated:YES completion:nil];
}

- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    if (urls.count == 0) return;

    NSError *dirError = nil;
    NSString *dir = [[DataPackService sharedService] ensureDataPacksFolderForProfile:self.profileName error:&dirError];
    if (!dir) {
        [self showSimpleAlertWithTitle:localize(@"resman.common.import_failed", nil) message:dirError.localizedDescription ?: localize(@"resman.datapacks.dir_not_found", nil)];
        return;
    }

    NSFileManager *fm = [NSFileManager defaultManager];
    NSInteger successCount = 0;
    NSMutableArray<NSString *> *failedFiles = [NSMutableArray array];

    for (NSURL *url in urls) {
        BOOL accessing = [url startAccessingSecurityScopedResource];
        @try {
            NSString *fileName = url.lastPathComponent;
            NSString *destPath = [dir stringByAppendingPathComponent:fileName];
            if ([fm fileExistsAtPath:destPath]) {
                NSString *baseName = [fileName stringByDeletingPathExtension];
                NSString *ext = [fileName pathExtension];
                destPath = [dir stringByAppendingPathComponent:[NSString stringWithFormat:@"%@_copy.%@", baseName, ext]];
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

    [self refreshLocalList];

    if (failedFiles.count > 0) {
        [self showSimpleAlertWithTitle:[NSString stringWithFormat:localize(@"resman.common.import_result", nil), (long)successCount, (long)failedFiles.count]
                               message:[failedFiles componentsJoinedByString:@"\n"]];
    }
}

#pragma mark - Data loading

- (void)handleRefresh:(id)sender {
    [self refreshLocalList];
}

/// Base-class refresh hook: reload the data-pack list on download-completion notification / viewWillAppear.
/// Key fix (resource manager did not refresh after successful download): refresh the page automatically
/// after the file is saved.
- (void)reloadResourceList {
    [self refreshLocalList];
}

- (void)refreshLocalList {
    [self setLoading:YES];
    NSString *profile = self.profileName ?: @"default";
    [[DataPackService sharedService] scanDataPacksForProfile:profile completion:^(NSArray<DataPackItem *> *items) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.localItems removeAllObjects];
            [self.localItems addObjectsFromArray:items];
            [self filterLocalItems];
            [self setLoading:NO];
            [self.tableView.refreshControl endRefreshing];
            // First-screen cascading entrance animation (Air-Design 15.3): play only once.
            if (!self.didPlayChainAnimation && self.filteredLocalItems.count > 0) {
                self.didPlayChainAnimation = YES;
                [self animateCellsInChain];
            }
        });
    }];
}

#pragma mark - Search and empty state

- (void)searchBar:(UISearchBar *)searchBar textDidChange:(NSString *)searchText {
    [self filterLocalItems];
}

- (void)searchBarSearchButtonClicked:(UISearchBar *)searchBar {
    [searchBar resignFirstResponder];
}

- (void)searchBarCancelButtonClicked:(UISearchBar *)searchBar {
    searchBar.text = @"";
    [searchBar resignFirstResponder];
    [self filterLocalItems];
}

- (void)filterLocalItems {
    [self.filteredLocalItems removeAllObjects];
    if (self.searchBar.text.length == 0) {
        [self.filteredLocalItems addObjectsFromArray:self.localItems];
    } else {
        NSString *searchText = [self.searchBar.text lowercaseString];
        for (DataPackItem *item in self.localItems) {
            if ([item.displayName.lowercaseString containsString:searchText] ||
                [item.fileName.lowercaseString containsString:searchText]) {
                [self.filteredLocalItems addObject:item];
            }
        }
    }
    [self.tableView reloadData];
    [self updateEmptyState];
}

- (void)updateEmptyState {
    if (self.filteredLocalItems.count > 0) {
        [self hideEmptyState];
        return;
    }
    if (self.localItems.count == 0) {
        // Empty directory: type icon + "Go to Downloads" prompt (opens the unified Downloads screen).
        [self showEmptyStateWithIcon:nil
                           iconColor:nil
                             message:localize(@"resman.datapacks.empty", nil)
                        actionTitle:localize(@"resman.common.go_download", nil)
                      actionHandler:^{
                          [self openDownloadPage];
                      }];
    } else {
        // No search results: do not show the prompt button.
        [self showEmptyStateWithIcon:@"magnifyingglass"
                           iconColor:[UIColor secondaryLabelColor]
                             message:localize(@"resman.datapacks.search_empty", nil)
                        actionTitle:nil
                      actionHandler:nil];
    }
}

#pragma mark - Navigate to unified Downloads screen

- (void)openDownloadPage {
    // Online downloads are consolidated on the unified Downloads screen (no resource-type tab
    // selected; open its default page).
    DownloadViewController *downloadVC = [[DownloadViewController alloc] init];
    // Key fix (target instance mismatch): pass the profileName bound to this management page.
    downloadVC.targetProfileName = self.profileName;
    if (self.navigationController) {
        [self.navigationController pushViewController:downloadVC animated:YES];
    } else {
        // Present full-screen when there is no navigation stack (legacy present path).
        UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:downloadVC];
        nav.modalPresentationStyle = UIModalPresentationFullScreen;
        [self presentViewController:nav animated:YES completion:nil];
    }
}

#pragma mark - UITableView DataSource & Delegate

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.filteredLocalItems.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    DataPackCardCell *cell = [tableView dequeueReusableCellWithIdentifier:@"DataPackCardCell" forIndexPath:indexPath];
    DataPackItem *item = self.filteredLocalItems[indexPath.row];
    __weak typeof(self) weakSelf = self;
    cell.toggleHandler = ^(DataPackCardCell *toggleCell) {
        [weakSelf handleToggleOnCell:toggleCell];
    };
    [cell configureWithDataPack:item];
    return cell;
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section {
    // Card spacing (Air-Design space-sm): top padding + space between cards.
    return ResourceListCardSpacing;
}

- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section {
    return [ResourceListViewController cardSpacingHeaderView];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
}

- (UISwipeActionsConfiguration *)tableView:(UITableView *)tableView trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath {
    __weak typeof(self) weakSelf = self;
    UIContextualAction *deleteAction = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleDestructive title:localize(@"resman.common.delete", nil) handler:^(UIContextualAction * _Nonnull action, __kindof UIView * _Nonnull sourceView, void (^ _Nonnull completionHandler)(BOOL)) {
        DataPackItem *item = weakSelf.filteredLocalItems[indexPath.row];
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:localize(@"resman.common.confirm_delete", nil)
                                                                        message:[NSString stringWithFormat:localize(@"resman.common.delete_message", nil), item.displayName ?: item.fileName]
                                                                 preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:localize(@"resman.common.cancel", nil) style:UIAlertActionStyleCancel handler:^(UIAlertAction * _Nonnull action) {
            completionHandler(NO);
        }]];
        [alert addAction:[UIAlertAction actionWithTitle:localize(@"resman.common.delete", nil) style:UIAlertActionStyleDestructive handler:^(UIAlertAction * _Nonnull action) {
            NSError *error = nil;
            if (![[DataPackService sharedService] deleteDataPack:item error:&error]) {
                [weakSelf showSimpleAlertWithTitle:localize(@"resman.common.delete_failed", nil) message:error.localizedDescription];
                completionHandler(NO);
                return;
            }
            NSInteger indexInFull = [weakSelf.localItems indexOfObject:item];
            if (indexInFull != NSNotFound) {
                [weakSelf.localItems removeObjectAtIndex:indexInFull];
            }
            // ★ [DEMINE] Previously, removeObjectAtIndex:indexPath.row ran unconditionally. If the data
            //   source refreshed while the dialog was open (async refresh/another deletion), indexPath
            //   became stale ⇒ an out-of-range NSRangeException crashed the app.
            //   Skip these two steps when out of range (the next reload corrects the state); when the index
            //   is valid, behavior is unchanged.
            if (indexPath.row < (NSInteger)weakSelf.filteredLocalItems.count) {
                [weakSelf.filteredLocalItems removeObjectAtIndex:indexPath.row];
                [tableView deleteRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationAutomatic];
            } else {
                NSLog(@"[DEMINE] stale delete index %ld >= filtered count %lu -- skipping removal",
                      (long)indexPath.row, (unsigned long)weakSelf.filteredLocalItems.count);
                [tableView reloadData];
            }
            completionHandler(YES);
        }]];
        [weakSelf presentViewController:alert animated:YES completion:nil];
    }];
    deleteAction.backgroundColor = [UIColor systemRedColor];

    return [UISwipeActionsConfiguration configurationWithActions:@[deleteAction]];
}

#pragma mark - Local enable/disable toggle

- (void)handleToggleOnCell:(DataPackCardCell *)cell {
    NSIndexPath *indexPath = [self.tableView indexPathForCell:cell];
    if (!indexPath || indexPath.row >= (NSInteger)self.filteredLocalItems.count) return;
    DataPackItem *item = self.filteredLocalItems[indexPath.row];
    NSError *error = nil;
    if (![[DataPackService sharedService] toggleEnableForDataPack:item error:&error]) {
        // Restore the switch state on failure.
        [cell.toggleSwitch setOn:!cell.toggleSwitch.on animated:NO];
        [self showSimpleAlertWithTitle:localize(@"resman.common.operation_failed", nil) message:error.localizedDescription];
    } else {
        // Translucent hint for the disabled state.
        cell.contentView.alpha = item.disabled ? 0.5 : 1.0;
    }
}

#pragma mark - Utility methods

- (void)showSimpleAlertWithTitle:(NSString *)title message:(NSString *)message {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:localize(@"resman.common.ok", nil) style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

@end
