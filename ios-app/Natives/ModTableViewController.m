#import "utils.h"
//
//  ModTableViewController.m
//  AmethystMods
//
//  Created by Copilot on 2025-08-22.
//  Updated: ensure the online-search switch is placed directly left of refresh and remains visible.
//

#import "ModTableViewController.h"
#import "ModItem.h"
#import "ModService.h"
#import "ModTableViewCell.h"
#import "BackgroundManager.h"

@interface ModTableViewController () <ModTableViewCellDelegate, UISearchBarDelegate>
@property (nonatomic, strong) NSArray<ModItem *> *mods;
@property (nonatomic, strong) NSArray<ModItem *> *filteredMods; // Stores search results.
@property (nonatomic, strong) UISwitch *onlineSearchSwitch;
@property (nonatomic, strong) UISearchBar *searchBar; // Search bar.
@end

@implementation ModTableViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    // Adapt to the custom launcher background: make this view controller transparent so the global background image/blur shows through.
    // ModTableViewController is a UITableViewController subclass; makeViewControllerTransparent also handles tableView background transparency.
    [[BackgroundManager sharedManager] makeViewControllerTransparent:self];
    // ★ [AUDIT-DECIDE] A-10: replace hard-coded "Mods" with the existing i18n_str_1283 key.
    self.title = localize(@"i18n_str_1283", nil);
    [self.tableView registerClass:[ModTableViewCell class] forCellReuseIdentifier:@"ModCell"];
    self.tableView.rowHeight = 96;

    // Create a container for label + switch and make it compact but wide enough
    UIView *container = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 140, 32)];
    UILabel *label = [[UILabel alloc] initWithFrame:CGRectMake(0, 0, 78, 32)];
    label.text = localize(@"i18n_str_455", nil);
    label.font = [UIFont systemFontOfSize:13];
    label.textAlignment = NSTextAlignmentRight;
    label.autoresizingMask = UIViewAutoresizingFlexibleHeight | UIViewAutoresizingFlexibleRightMargin;
    [container addSubview:label];

    self.onlineSearchSwitch = [[UISwitch alloc] initWithFrame:CGRectMake(86, 4, 0, 0)];
    self.onlineSearchSwitch.on = [ModService sharedService].onlineSearchEnabled;
    [self.onlineSearchSwitch addTarget:self action:@selector(toggleOnlineSearch:) forControlEvents:UIControlEventValueChanged];
    self.onlineSearchSwitch.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
    [container addSubview:self.onlineSearchSwitch];

    UIBarButtonItem *switchContainerItem = [[UIBarButtonItem alloc] initWithCustomView:container];

    // Refresh button: rightmost
    UIBarButtonItem *refresh = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemRefresh target:self action:@selector(refreshTapped)];

    // Put refresh as rightmost, switch container to its left
    self.navigationItem.rightBarButtonItems = @[refresh, switchContainerItem];

    // Create the search bar.
    self.searchBar = [[UISearchBar alloc] initWithFrame:CGRectMake(0, 0, self.view.frame.size.width, 44)];
    self.searchBar.placeholder = localize(@"i18n_str_456", nil);
    self.searchBar.delegate = self;
    self.searchBar.barStyle = UIBarStyleDefault;
    self.searchBar.searchBarStyle = UISearchBarStyleMinimal;
    // Adapt to the custom launcher background: make the searchBar's default opaque background transparent so the global background image/blur shows through.
    [[BackgroundManager sharedManager] applyEffectToSearchBar:self.searchBar];

    // Add the search bar to the tableView header.
    self.tableView.tableHeaderView = self.searchBar;
    
    // Initialize filteredMods.
    self.filteredMods = @[];
    
    // Ensure switch reflects current state when view appears
    [self refreshTapped];

    // Listen for background-effect changes and reapply transparency when the background changes.
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(reapplyBackgroundEffect)
                                                 name:@"BackgroundUIEffectChanged"
                                               object:nil];
}

- (void)reapplyBackgroundEffect {
    // Make this view controller transparent again when the background effect changes.
    // makeViewControllerTransparent handles the UITableViewController tableView background automatically.
    [[BackgroundManager sharedManager] makeViewControllerTransparent:self];
    // Reapply searchBar transparency (refresh the text-field background after switching between blur and translucency).
    [[BackgroundManager sharedManager] applyEffectToSearchBar:self.searchBar];
}

- (void)dealloc {
    // Remove the notification observer to prevent a crash from receiving notifications after dealloc.
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    self.onlineSearchSwitch.on = [ModService sharedService].onlineSearchEnabled;
}

- (void)toggleOnlineSearch:(UISwitch *)sw {
    [ModService sharedService].onlineSearchEnabled = sw.isOn;
    [self refreshTapped];
}

- (void)refreshTapped {
    [[ModService sharedService] scanModsForProfile:self.profileName completion:^(NSArray<ModItem *> *mods) {
        self.mods = mods ?: @[];
        // Display all mods if no search is active; otherwise display the search results.
        if (self.searchBar.text.length == 0) {
            self.filteredMods = self.mods;
        } else {
            [self filterModsForSearchText:self.searchBar.text];
        }
        [self.tableView reloadData];

        for (NSInteger i = 0; i < self.mods.count; i++) {
            ModItem *m = self.mods[i];
            [[ModService sharedService] fetchMetadataForMod:m completion:^(ModItem *item, NSError * _Nullable error) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    NSUInteger idx = [self.mods indexOfObjectPassingTest:^BOOL(ModItem * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
                        return [obj.filePath isEqualToString:item.filePath];
                    }];
                    if (idx != NSNotFound) {
                        NSIndexPath *path = [NSIndexPath indexPathForRow:idx inSection:0];
                        [self.tableView reloadRowsAtIndexPaths:@[path] withRowAnimation:UITableViewRowAnimationNone];
                    } else {
                        [self.tableView reloadData];
                    }
                });
            }];
        }
    }];
}

#pragma mark - UISearchBarDelegate

- (void)searchBar:(UISearchBar *)searchBar textDidChange:(NSString *)searchText {
    [self filterModsForSearchText:searchText];
}

- (void)searchBarSearchButtonClicked:(UISearchBar *)searchBar {
    [searchBar resignFirstResponder];
}

- (void)searchBarCancelButtonClicked:(UISearchBar *)searchBar {
    searchBar.text = @"";
    [self filterModsForSearchText:@""];
    [searchBar resignFirstResponder];
}

- (void)filterModsForSearchText:(NSString *)searchText {
    if (searchText.length == 0) {
        // Display all mods if the search text is empty.
        self.filteredMods = self.mods;
    } else {
        // Filter mods based on the search text.
        NSPredicate *predicate = [NSPredicate predicateWithFormat:@"displayName CONTAINS[cd] %@ OR modDescription CONTAINS[cd] %@", searchText, searchText];
        self.filteredMods = [self.mods filteredArrayUsingPredicate:predicate];
    }
    
    // Update the table view.
    [self.tableView reloadData];
}

#pragma mark - Table view data source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 1;
}
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.filteredMods.count;
}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    ModTableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"ModCell" forIndexPath:indexPath];
    ModItem *m = self.filteredMods[indexPath.row];
    cell.delegate = self;
    [cell configureWithMod:m displayMode:ModTableViewCellDisplayModeLocal];
    return cell;
}

#pragma mark - ModTableViewCellDelegate

- (void)modCellDidTapToggle:(UITableViewCell *)cell {
    NSIndexPath *ip = [self.tableView indexPathForCell:cell];
    if (!ip) return;
    ModItem *m = self.filteredMods[ip.row];
    NSError *err = nil;
    BOOL ok = [[ModService sharedService] toggleEnableForMod:m error:&err];
    if (!ok) {
        UIAlertController *ac = [UIAlertController alertControllerWithTitle:localize(@"i18n_str_42", nil) message:err.localizedDescription preferredStyle:UIAlertControllerStyleAlert];
        [ac addAction:[UIAlertAction actionWithTitle:localize(@"i18n_str_44", nil) style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:ac animated:YES completion:nil];
    } else {
        [self.tableView reloadRowsAtIndexPaths:@[ip] withRowAnimation:UITableViewRowAnimationAutomatic];
    }
}

- (void)modCellDidTapDelete:(UITableViewCell *)cell {
    NSIndexPath *ip = [self.tableView indexPathForCell:cell];
    if (!ip) return;
    ModItem *m = self.filteredMods[ip.row];
    UIAlertController *ac = [UIAlertController alertControllerWithTitle:localize(@"i18n_str_457", nil) message:m.displayName preferredStyle:UIAlertControllerStyleAlert];
    [ac addAction:[UIAlertAction actionWithTitle:localize(@"resman.common.cancel", nil) style:UIAlertActionStyleCancel handler:nil]];
    [ac addAction:[UIAlertAction actionWithTitle:localize(@"i18n_str_306", nil) style:UIAlertActionStyleDestructive handler:^(UIAlertAction * _Nonnull action) {
        NSError *err = nil;
        if ([[ModService sharedService] deleteMod:m error:&err]) {
            // Remove from filteredMods and mods.
            NSMutableArray *newFiltered = [self.filteredMods mutableCopy];
            [newFiltered removeObjectAtIndex:ip.row];
            self.filteredMods = [newFiltered copy];
            
            NSMutableArray *newMods = [self.mods mutableCopy];
            NSUInteger originalIndex = [newMods indexOfObject:m];
            if (originalIndex != NSNotFound) {
                [newMods removeObjectAtIndex:originalIndex];
            }
            self.mods = [newMods copy];
            
            [self.tableView deleteRowsAtIndexPaths:@[ip] withRowAnimation:UITableViewRowAnimationAutomatic];
        } else {
            UIAlertController *errAc = [UIAlertController alertControllerWithTitle:localize(@"i18n_str_458", nil) message:err.localizedDescription preferredStyle:UIAlertControllerStyleAlert];
            [errAc addAction:[UIAlertAction actionWithTitle:localize(@"i18n_str_44", nil) style:UIAlertActionStyleDefault handler:nil]];
            [self presentViewController:errAc animated:YES completion:nil];
        }
    }]];
    [self presentViewController:ac animated:YES completion:nil];
}

- (void)modCellDidTapOpenLink:(UITableViewCell *)cell {
    NSIndexPath *ip = [self.tableView indexPathForCell:cell];
    if (!ip) return;
    ModItem *m = self.filteredMods[ip.row];
    NSString *urlStr = m.homepage.length ? m.homepage : (m.sources.length ? m.sources : nil);
    if (!urlStr) return;
    NSURL *u = [NSURL URLWithString:urlStr];
    if (!u || !u.scheme) {
        NSString *withScheme = [NSString stringWithFormat:@"https://%@", urlStr];
        u = [NSURL URLWithString:withScheme];
    }
    if (u) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [[UIApplication sharedApplication] openURL:u options:@{} completionHandler:^(BOOL success) {
                if (!success) {
                    UIAlertController *ac = [UIAlertController alertControllerWithTitle:localize(@"i18n_str_459", nil) message:urlStr preferredStyle:UIAlertControllerStyleAlert];
                    [ac addAction:[UIAlertAction actionWithTitle:localize(@"i18n_str_44", nil) style:UIAlertActionStyleDefault handler:nil]];
                    [self presentViewController:ac animated:YES completion:nil];
                }
            }];
        });
    }
}

@end