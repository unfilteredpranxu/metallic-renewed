//
//  AISessionListViewController.m
//  Amethyst
//
//  AI session list page implementation: UITableView + UISearchController.
//

#import "AISessionListViewController.h"
#import "AiSessionStore.h"
#import "BackgroundManager.h"
#import "LauncherPreferences.h"
#import "utils.h"   // ★ [HOST-BUG-A] Use localize() consistently
#import "AIViewController.h"   // ★ [AI-SESSION-TAP] Chat page opened when a session is tapped

@interface AISessionListViewController () <UITableViewDataSource, UITableViewDelegate, UISearchResultsUpdating>

@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UISearchController *searchController;
@property (nonatomic, strong) UILabel *emptyLabel;
/// Sessions to display (filtered during search, otherwise all; sorted with pinned first, then update time descending)
@property (nonatomic, strong) NSMutableArray<AiSession *> *displayedSessions;

@end

@implementation AISessionListViewController

- (void)viewDidLoad {
    [super viewDidLoad];

    self.title = localize(@"ai.session_list.title", @"Sessions");   // ★ [HOST-BUG-A]
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeNever;
    self.view.backgroundColor = [[UIColor labelColor] colorWithAlphaComponent:0.04];
    [[BackgroundManager sharedManager] makeViewControllerTransparent:self];

    // Top-left "New Session" button
    UIBarButtonItem *newItem = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"plus"]
                                                                style:UIBarButtonItemStylePlain
                                                               target:self
                                                               action:@selector(newSessionAction)];
    self.navigationItem.leftBarButtonItem = newItem;

    // ★ [LAND-BUG] Besides being pushed from an AI session, this page is presented full-screen modally by LauncherMenuViewController.showAI.
    //   Full-screen modals cannot be dismissed by swiping down, and the page previously had only a top-left "+" with no back/close option ⇒ users could not exit.
    //   Add a Close button in viewWillAppear only when presented modally (keep the navigation back button when pushed).
    //   See viewWillAppear: / landBugCloseTapped below.

    [self setupTable];
    [self setupSearch];
    [self setupEmptyState];

    [self reloadDisplayedSessions];
}

#pragma mark - ★ [LAND-BUG] Close control for modal presentation

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    // When presented full-screen modally (nav is the presented controller), add a top-right "Close";
    // when pushed, presentingViewController is nil, so do not inject it or override the navigation back button.
    UINavigationController *nav = self.navigationController;
    if (nav.presentingViewController != nil && nav.viewControllers.firstObject == self &&
        self.navigationItem.rightBarButtonItem == nil) {
        UIBarButtonItem *close = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemClose
                                                                              target:self
                                                                              action:@selector(landBugCloseTapped)];
        close.accessibilityLabel = @"Close";
        self.navigationItem.rightBarButtonItem = close;
    }
}

- (void)landBugCloseTapped {
    UINavigationController *nav = self.navigationController;
    if (nav.presentingViewController) {
        [nav dismissViewControllerAnimated:YES completion:nil];
    } else {
        [self dismissViewControllerAnimated:YES completion:nil];
    }
}

#pragma mark - Layout

- (void)setupTable {
    self.tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    self.tableView.translatesAutoresizingMaskIntoConstraints = NO;
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    self.tableView.backgroundColor = [UIColor clearColor];
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    self.tableView.estimatedRowHeight = 88;
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.contentInset = UIEdgeInsetsMake(8, 0, 40, 0);
    self.tableView.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;
    [self.tableView registerClass:[UITableViewCell class] forCellReuseIdentifier:@"AiSessionCell"];
    [self.view addSubview:self.tableView];

    [NSLayoutConstraint activateConstraints:@[
        [self.tableView.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [self.tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.tableView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
    ]];
}

- (void)setupSearch {
    self.searchController = [[UISearchController alloc] initWithSearchResultsController:nil];
    self.searchController.searchResultsUpdater = self;
    self.searchController.obscuresBackgroundDuringPresentation = NO;
    self.searchController.hidesNavigationBarDuringPresentation = NO;
    self.navigationItem.searchController = self.searchController;
    // Adapt to global background: transparent search field, text follows the system
    self.searchController.searchBar.barTintColor = [UIColor clearColor];
    self.searchController.searchBar.tintColor = accentColor();
    self.searchController.searchBar.backgroundImage = [UIImage new];
    if (@available(iOS 13.0, *)) {
        self.searchController.searchBar.searchTextField.backgroundColor = [[UIColor whiteColor] colorWithAlphaComponent:0.08];
    }
    self.definesPresentationContext = YES;
}

- (void)setupEmptyState {
    self.emptyLabel = [[UILabel alloc] init];
    self.emptyLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.emptyLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightRegular];
    self.emptyLabel.textColor = [UIColor secondaryLabelColor];
    self.emptyLabel.textAlignment = NSTextAlignmentCenter;
    self.emptyLabel.numberOfLines = 0;
    [self.view addSubview:self.emptyLabel];

    [NSLayoutConstraint activateConstraints:@[
        [self.emptyLabel.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [self.emptyLabel.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor],
        [self.emptyLabel.leadingAnchor constraintGreaterThanOrEqualToAnchor:self.view.leadingAnchor constant:32],
        [self.emptyLabel.trailingAnchor constraintLessThanOrEqualToAnchor:self.view.trailingAnchor constant:-32],
    ]];
}

#pragma mark - Data source

/// Reorder: pinned sessions first, then the rest by updatedAt descending (newest first)
- (void)reloadDisplayedSessions {
    NSString *query = self.searchController.active ? self.searchController.searchBar.text : @"";
    NSArray<AiSession *> *base = [[AiSessionStore sharedStore] sessionsMatchingQuery:query ?: @""];

    self.displayedSessions = [NSMutableArray array];
    NSMutableArray *pinned = [NSMutableArray array];
    NSMutableArray *normal = [NSMutableArray array];
    for (AiSession *session in base) {
        if (session.pinned) {
            [pinned addObject:session];
        } else {
            [normal addObject:session];
        }
    }
    [self.displayedSessions addObjectsFromArray:pinned];
    [self.displayedSessions addObjectsFromArray:normal];

    [self.tableView reloadData];
    [self updateEmptyState];
}

- (void)updateEmptyState {
    if (!self.emptyLabel) return;
    BOOL hasAny = [AiSessionStore sharedStore].sessions.count > 0;
    BOOL searching = self.searchController.active && self.searchController.searchBar.text.length > 0;

    if (self.displayedSessions.count == 0) {
        self.emptyLabel.hidden = NO;
        if (!hasAny) {
            self.emptyLabel.text = @"No sessions yet. Tap + in the top left to create one.";
        } else if (searching) {
            self.emptyLabel.text = @"No matching sessions";
        } else {
            self.emptyLabel.text = @"No sessions yet";
        }
    } else {
        self.emptyLabel.hidden = YES;
    }
}

#pragma mark - Create / delete

- (void)newSessionAction {
    AiSession *session = [[AiSessionStore sharedStore] newSession];
    if (self.onNewSession) {
        self.onNewSession(session);
    } else {
        [self reloadDisplayedSessions];
    }
}

- (void)deleteSession:(AiSession *)session {
    [[AiSessionStore sharedStore] deleteSession:session];
    [self reloadDisplayedSessions];
}

#pragma mark - Relative time

/// Simple relative time: just now / X minutes ago / X hours ago / X days ago / date
- (NSString *)relativeTimeString:(NSDate *)date {
    if (!date) return @"";
    NSTimeInterval interval = -[date timeIntervalSinceNow];
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    formatter.locale = [NSLocale localeWithLocaleIdentifier:@"zh_CN"];
    if (interval < 60) {
        return @"Just now";
    } else if (interval < 3600) {
        return [NSString stringWithFormat:@"%ld min ago", (long)(interval / 60)];
    } else if (interval < 86400) {
        return [NSString stringWithFormat:@"%ld hr ago", (long)(interval / 3600)];
    } else if (interval < 7 * 86400) {
        return [NSString stringWithFormat:@"%ld days ago", (long)(interval / 86400)];
    }
    formatter.dateFormat = @"MM-dd";
    return [formatter stringFromDate:date];
}

#pragma mark - UITableViewDataSource

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.displayedSessions.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"AiSessionCell" forIndexPath:indexPath];
    AiSession *session = self.displayedSessions[indexPath.row];

    // Clear reused view residue
    for (UIView *sub in cell.contentView.subviews) {
        [sub removeFromSuperview];
    }
    cell.accessoryType = UITableViewCellAccessoryNone;
    cell.accessoryView = nil;
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    cell.backgroundColor = [UIColor clearColor];
    cell.contentView.backgroundColor = [UIColor clearColor];

    // Card container
    UIView *cardView = [[UIView alloc] init];
    cardView.translatesAutoresizingMaskIntoConstraints = NO;
    cardView.backgroundColor = [[UIColor whiteColor] colorWithAlphaComponent:0.08];
    cardView.layer.cornerRadius = 16;
    cardView.layer.cornerCurve = kCACornerCurveContinuous;
    cardView.layer.borderWidth = 0.5;
    cardView.layer.borderColor = [[UIColor whiteColor] colorWithAlphaComponent:0.10].CGColor;
    cardView.layer.shadowColor = [UIColor blackColor].CGColor;
    cardView.layer.shadowOffset = CGSizeMake(0, 2);
    cardView.layer.shadowOpacity = 0.10;
    cardView.layer.shadowRadius = 6;
    [[BackgroundManager sharedManager] applyEffectToView:cardView];
    [cell.contentView addSubview:cardView];

    // Session icon
    UIImageView *iconView = [[UIImageView alloc] init];
    iconView.translatesAutoresizingMaskIntoConstraints = NO;
    iconView.image = [UIImage systemImageNamed:@"bubble.left.and.bubble.right.fill"];
    iconView.tintColor = [UIColor whiteColor];
    iconView.contentMode = UIViewContentModeCenter;
    iconView.backgroundColor = accentColor();
    iconView.layer.cornerRadius = 12;
    iconView.layer.cornerCurve = kCACornerCurveContinuous;
    iconView.layer.masksToBounds = YES;
    [cardView addSubview:iconView];

    // Title
    UILabel *titleLabel = [[UILabel alloc] init];
    titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    titleLabel.text = session.title.length > 0 ? session.title : @"New Session";
    titleLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightSemibold];
    titleLabel.textColor = [UIColor labelColor];
    titleLabel.numberOfLines = 1;
    titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    [cardView addSubview:titleLabel];

    // Subtitle: message count + update time
    UILabel *subtitleLabel = [[UILabel alloc] init];
    subtitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    subtitleLabel.text = [NSString stringWithFormat:@"%lu messages · %@",
                          (unsigned long)session.messages.count,
                          [self relativeTimeString:session.updatedAt]];
    subtitleLabel.font = [UIFont systemFontOfSize:12];
    subtitleLabel.textColor = [UIColor secondaryLabelColor];
    subtitleLabel.numberOfLines = 1;
    subtitleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    [cardView addSubview:subtitleLabel];

    // Pin icon
    UIImageView *pinView = [[UIImageView alloc] init];
    pinView.translatesAutoresizingMaskIntoConstraints = NO;
    pinView.image = [UIImage systemImageNamed:@"pin.fill"];
    pinView.tintColor = accentColor();
    pinView.contentMode = UIViewContentModeScaleAspectFit;
    pinView.hidden = !session.pinned;
    [cardView addSubview:pinView];

    [NSLayoutConstraint activateConstraints:@[
        [cardView.topAnchor constraintEqualToAnchor:cell.contentView.topAnchor constant:6],
        [cardView.leadingAnchor constraintEqualToAnchor:cell.contentView.leadingAnchor constant:16],
        [cardView.trailingAnchor constraintEqualToAnchor:cell.contentView.trailingAnchor constant:-16],
        [cardView.bottomAnchor constraintEqualToAnchor:cell.contentView.bottomAnchor constant:-6],

        [iconView.leadingAnchor constraintEqualToAnchor:cardView.leadingAnchor constant:14],
        [iconView.centerYAnchor constraintEqualToAnchor:cardView.centerYAnchor],
        [iconView.widthAnchor constraintEqualToConstant:42],
        [iconView.heightAnchor constraintEqualToConstant:42],

        [titleLabel.leadingAnchor constraintEqualToAnchor:iconView.trailingAnchor constant:14],
        [titleLabel.trailingAnchor constraintLessThanOrEqualToAnchor:pinView.leadingAnchor constant:-8],
        [titleLabel.topAnchor constraintEqualToAnchor:cardView.topAnchor constant:16],

        [subtitleLabel.leadingAnchor constraintEqualToAnchor:titleLabel.leadingAnchor],
        [subtitleLabel.trailingAnchor constraintEqualToAnchor:titleLabel.trailingAnchor],
        [subtitleLabel.topAnchor constraintEqualToAnchor:titleLabel.bottomAnchor constant:4],
        [subtitleLabel.bottomAnchor constraintEqualToAnchor:cardView.bottomAnchor constant:-16],

        [pinView.trailingAnchor constraintEqualToAnchor:cardView.trailingAnchor constant:-14],
        [pinView.centerYAnchor constraintEqualToAnchor:cardView.centerYAnchor],
        [pinView.widthAnchor constraintEqualToConstant:16],
        [pinView.heightAnchor constraintEqualToConstant:16],
    ]];

    return cell;
}

- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath {
    return YES;
}

- (NSArray<UITableViewRowAction *> *)tableView:(UITableView *)tableView editActionsForRowAtIndexPath:(NSIndexPath *)indexPath {
    __weak typeof(self) weakSelf = self;
    UITableViewRowAction *deleteAction = [UITableViewRowAction rowActionWithStyle:UITableViewRowActionStyleDestructive
                                                                           title:@"Delete"
                                                                         handler:^(UITableViewRowAction * _Nonnull action, NSIndexPath * _Nonnull ip) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        AiSession *session = strongSelf.displayedSessions[ip.row];
        [strongSelf deleteSession:session];
    }];
    return @[deleteAction];
}

- (UITableViewCellEditingStyle)tableView:(UITableView *)tableView editingStyleForRowAtIndexPath:(NSIndexPath *)indexPath {
    return UITableViewCellEditingStyleDelete;
}

#pragma mark - UITableViewDelegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.row >= (NSInteger)self.displayedSessions.count) return;   // ★ [AI-SESSION-TAP] Prevent out-of-bounds access
    AiSession *session = self.displayedSessions[indexPath.row];
    if (!session) return;
    if (self.onSelectSession) {
        // ★ [AI-SESSION-TAP] For entry points with a callback (session list presented from chat), let the caller handle it; behavior is unchanged
        self.onSelectSession(session);
        return;
    }
    // ★ [AI-SESSION-TAP] Fallback for standalone entry points without a callback; see ameOpenChatForSession:
    [self ameOpenChatForSession:session];
}

#pragma mark - ★ [AI-SESSION-TAP] Open chat page when a session is tapped

/// ★ [AI-SESSION-TAP] Root-cause fix ("none of the session items could be opened"):
///   This page has several independent entry points — the root tab bar's "AI" tab (AmeRootTabController case 2),
///   menu showAI (LauncherMenuViewController), and Settings "Sessions" (LauncherPreferencesViewController) —
///   and each only calls `[[AISessionListViewController alloc] init]`; **none sets onSelectSession**.
///   So self.onSelectSession == nil in didSelectRowAtIndexPath ⇒ tapping any session item did nothing;
///   the top-left "+" is a UIBarButtonItem target/action (newSessionAction) and needs no callback,
///   which explains why creating sessions worked while tapping items did not — the only difference in the view tree is whether that callback is connected.
///   Fix: when there is no callback, this page opens the chat page (AIViewController) itself by
///   **pushing onto this page's navigation stack** (rather than replacing the root via setContentViewController — prohibited by this repository's navigation rule),
///   which naturally preserves Back behavior; entry points with a callback (list presented from chat) still use the callback and do not push again.
- (void)ameOpenChatForSession:(AiSession *)session {
    if (!session) return;
    AIViewController *chat = [[AIViewController alloc] initWithSession:session];
    UINavigationController *nav = self.navigationController;
    if (nav) {
        [nav pushViewController:chat animated:YES];
        return;
    }
    // Fallback: if this page is not in a navigation stack (all current entry points wrap it in a nav controller, so this should not happen), present it in a new modal nav controller
    UINavigationController *wrap = [[UINavigationController alloc] initWithRootViewController:chat];
    wrap.modalPresentationStyle = UIModalPresentationFormSheet;
    [self presentViewController:wrap animated:YES completion:nil];
}

#pragma mark - UISearchResultsUpdating

- (void)updateSearchResultsForSearchController:(UISearchController *)searchController {
    [self reloadDisplayedSessions];
}

@end