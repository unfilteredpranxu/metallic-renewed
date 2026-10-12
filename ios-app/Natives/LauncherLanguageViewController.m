#import "LauncherLanguageViewController.h"

#import "utils.h"
#import "BackgroundManager.h"   // ★ [PAGE-GLASS] Use the global interface style layer

// ★ [I18N] Broadcast language changes. SceneDelegate rebuilds the launcher root UI so all
// pages resolve localized text again; this and other pages can also observe for local refreshes.
NSString * const AmeLauncherLanguageChangedNotification = @"AmeLauncherLanguageChanged";

@interface LauncherLanguageViewController () <UISearchResultsUpdating>

// ★ [I18N] Selected language code (= supported-language allowlist, sorted by display name; omit empty .lproj shells)
@property (nonatomic, copy) NSArray<NSString *> *availableCodes;
// ★ [I18N] Search-filtered results; nil means no search (show availableCodes directly)
@property (nonatomic, copy) NSArray<NSString *> *filteredCodes;
@property (nonatomic, strong) UISearchController *searchController;

@end

@implementation LauncherLanguageViewController

- (instancetype)init {
    // ★ [I18N] insetGrouped style, matching the Settings page (like iOS Settings).
    return [super initWithStyle:UITableViewStyleInsetGrouped];
}

- (void)viewDidLoad {
    [super viewDidLoad];

    // ★ [I18N] The title and placeholder are refreshed together in ameRelocalize after a language change.
    self.availableCodes = AmeLauncherAvailableLanguageCodes();

    self.searchController = [[UISearchController alloc] initWithSearchResultsController:nil];
    self.searchController.searchResultsUpdater = self;
    self.searchController.obscuresBackgroundDuringPresentation = NO;
    self.searchController.searchBar.autocapitalizationType = UITextAutocapitalizationTypeNone;
    self.searchController.searchBar.autocorrectionType = UITextAutocorrectionTypeNo;
    self.navigationItem.searchController = self.searchController;
    self.navigationItem.hidesSearchBarWhenScrolling = NO;
    self.definesPresentationContext = YES;

    self.tableView.rowHeight = 44;

    // ★ [I18N] Refresh the title and selection immediately when the language changes (if the root UI has not rebuilt this page).
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(handleLanguageChanged:)
                                                 name:AmeLauncherLanguageChangedNotification
                                               object:nil];

    [self ameRelocalize];

    // ★ [PAGE-GLASS] Match the other settings subpages (Controls / JRE Management / Instance Settings…) by using the global interface style layer —
    //   iOS ≥26 uses system Liquid Glass; iOS <26 uses the native system material. iOS clears the tableView background to reveal the wallpaper/background.
    //   This page previously never used the style layer, leaving an opaque system background that looked inconsistent with related subpages.
    [[BackgroundManager sharedManager] makeViewControllerTransparent:self];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self
                                                    name:AmeLauncherLanguageChangedNotification
                                                  object:nil];
}

#pragma mark - ★ [I18N] Reload localized text

// Reload this page's text (title / search placeholder / section headers) and refresh the list. Called when the language changes.
- (void)ameRelocalize {
    self.title = localize(@"preference.lang.title", @"Language");
    self.searchController.searchBar.placeholder = localize(@"preference.lang.search_placeholder", @"Search languages");
    [self.tableView reloadData];
}

- (void)handleLanguageChanged:(NSNotification *)notification {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self ameRelocalize];
    });
}

#pragma mark - Data

// Section 0 → nil (= follow system); section 1 → a specific language code.
- (nullable NSString *)codeForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == 0) return nil;
    if (self.filteredCodes) {
        return (indexPath.row < (NSInteger)self.filteredCodes.count) ? self.filteredCodes[indexPath.row] : nil;
    }
    return (indexPath.row < (NSInteger)self.availableCodes.count) ? self.availableCodes[indexPath.row] : nil;
}

#pragma mark - UITableViewDataSource

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 2;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (section == 0) return 1;
    return self.filteredCodes ? self.filteredCodes.count : self.availableCodes.count;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    if (section == 0) return localize(@"preference.lang.section.system", @"System");
    return localize(@"preference.lang.section.available", @"Available languages");
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *cellID = @"AmeLanguageCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:cellID];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:cellID];
    }
    cell.textLabel.textColor = [UIColor labelColor];
    cell.detailTextLabel.textColor = [UIColor secondaryLabelColor];

    NSString *currentOverride = AmeLauncherPreferredLanguageOverride();

    if (indexPath.section == 0) {
        // ★ [I18N] "Follow System": the subtitle states which language is actually active when following the system,
        // directly answering "English system → English, Chinese system → Chinese". Uses the same source of truth as rendering.
        cell.textLabel.text = localize(@"preference.lang.follow_system", @"Follow System");
        // ★ [I18N-PARTIAL] If the active language is partially translated (such as Japanese), mark it as "Partially Translated" here too.
        cell.detailTextLabel.text = AmeLauncherDisplayNameAnnotatedForLanguageCode(AmeLauncherEffectiveLanguageCode());
        cell.accessoryType = (currentOverride.length == 0) ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
    } else {
        NSString *code = [self codeForRowAtIndexPath:indexPath];
        // ★ [I18N-PARTIAL] Show partially translated languages (single source of truth) as "Japanese (Partially Translated)".
        cell.textLabel.text = AmeLauncherDisplayNameAnnotatedForLanguageCode(code);
        NSString *subtitle = code;
        // ★ [I18N-PARTIAL] For partially translated languages, always show an explanatory subtitle (e.g. "Some of the interface is still in Chinese"),
        // which answers "what happens if I select this?" more clearly than a translation percentage and avoids surprises.
        NSString *partialNote = AmeLauncherPartiallyTranslatedNoteForLanguageCode(code);
        if (partialNote.length > 0) {
            subtitle = [NSString stringWithFormat:@"%@ · %@", code, partialNote];
        } else {
            // ★ [I18N] Subtitle: original code + (for partial translations) the human-translated percentage, making it easy to see
            // which languages are complete and which are only partially translated.
            // ★ [I18N-ORDER] Relaxed the threshold to 0.85: values such as "AI/%d" that match English can lower the ratio in complete locales.
            // Show a percentage only for shell locales that are largely untranslated, avoiding noise such as "·98%" for complete locales.
            double ratio = AmeLauncherLanguageTranslatedRatio(code);
            if (ratio > 0.0 && ratio < 0.85) {
                subtitle = [NSString stringWithFormat:@"%@ · %.0f%%", code, ratio * 100.0];
            }
        }
        cell.detailTextLabel.text = subtitle;
        cell.accessoryType = (code && [code isEqualToString:currentOverride])
            ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
    }
    return cell;
}

#pragma mark - UITableViewDelegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];

    // Section 0 → nil (follow system)
    NSString *code = [self codeForRowAtIndexPath:indexPath];

    NSString *before = AmeLauncherPreferredLanguageOverride() ?: @"";
    // ★ [I18N] Persist using a custom key (do not touch system AppleLanguages).
    AmeLauncherSetPreferredLanguageOverride(code);
    NSString *after = AmeLauncherPreferredLanguageOverride() ?: @"";

    [tableView reloadData];
    if (self.searchController.isActive) {
        self.searchController.active = NO;
    }

    if (![before isEqualToString:after]) {
        // ★ [I18N] Apply immediately: broadcast asynchronously — SceneDelegate rebuilds the launcher's root UI and all pages
        // Resolve localized text again (including this page). Dispatch asynchronously so didSelect
        // can return cleanly first,
        // Avoid replacing/releasing this controller within its own callback stack.
        dispatch_async(dispatch_get_main_queue(), ^{
            [[NSNotificationCenter defaultCenter] postNotificationName:AmeLauncherLanguageChangedNotification
                                                                object:nil];
        });
    }
}

#pragma mark - UISearchResultsUpdating

- (void)updateSearchResultsForSearchController:(UISearchController *)searchController {
    NSString *query = [searchController.searchBar.text stringByTrimmingCharactersInSet:
                       [NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (query.length == 0) {
        self.filteredCodes = nil;
        [self.tableView reloadData];
        return;
    }
    NSString *lower = query.lowercaseString;
    NSMutableArray<NSString *> *results = [NSMutableArray array];
    for (NSString *code in self.availableCodes) {
        NSString *name = AmeLauncherDisplayNameForLanguageCode(code);
        if ([name.lowercaseString containsString:lower] || [code.lowercaseString containsString:lower]) {
            [results addObject:code];
        }
    }
    self.filteredCodes = results;
    [self.tableView reloadData];
}

@end
