//
//  AIViewController.m
//  Amethyst
//

#import "AIViewController.h"
#import "AIMessageCell.h"
#import "AIInputBarView.h"
#import "AiAgent.h"
#import "AiSessionStore.h"
#import "AiProviderStore.h"
#import "AiSettings.h"
#import "BackgroundManager.h"
#import "LauncherPreferences.h"
#import "AISessionListViewController.h"
#import "utils.h"   // ★ [HOST-BUG-A] Use localize() consistently
#import "AIProviderConfigViewController.h"

/// Streaming UI refresh throttle threshold; avoids repeated Markdown recalculation
static const NSTimeInterval kUIThrottleInterval = 0.2;

@interface AIViewController () <UITableViewDataSource, UITableViewDelegate>
@property (nonatomic, strong) AiSession *session;
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) AIInputBarView *inputBar;
@property (nonatomic, strong) NSLayoutConstraint *inputBarBottomConstraint;
@property (nonatomic, assign) NSTimeInterval lastStreamUpdateTime;
@property (nonatomic, strong) UIActivityIndicatorView *activityIndicator;

// Empty-state view
@property (nonatomic, strong) UIView *emptyStateView;
@property (nonatomic, strong) UIImageView *emptyIcon;
@property (nonatomic, strong) UILabel *emptyTitle;
@property (nonatomic, strong) UILabel *emptySubtitle;
@property (nonatomic, strong) UIButton *configureButton;
@end

@implementation AIViewController

#pragma mark - Initialization

- (instancetype)initWithSession:(AiSession *)session {
    self = [super init];
    if (self) {
        _session = session;
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    // Lazily create a session
    if (!self.session) {
        self.session = [[AiSessionStore sharedStore] newSession];
        [[AiSessionStore sharedStore] updateSession:self.session];
    }
    if (self.session.title.length == 0) {
        self.session.title = localize(@"ai.assistant.title", @"AI Assistant");
    }

    // Light background (the outer BackgroundManager provides blur for the entire content area); do not add extra blur
    self.view.backgroundColor = [[UIColor labelColor] colorWithAlphaComponent:0.04];
    // ★ [PAGE-GLASS] Match the three related pages (AISessionList / AIProviderConfig / AISystemPromptEditor):
    //   after applying the tint, let the global interface style layer handle the background — system Liquid Glass on iOS≥26, native material on earlier versions.
    //   This page was previously the only AI page that did not use the style layer ⇒ its background differed from other AI pages and Settings.
    [[BackgroundManager sharedManager] makeViewControllerTransparent:self];

    self.navigationItem.title = self.session.title;
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeNever;

    [self setupNavBar];
    [self setupUI];
    [self setupKeyboardObservers];
    [self updateModelLabel];
    [self updateEmptyState];

    // Observe session message-change notifications, sent by AiAgent after appending tool_calls / tool result messages (object=session),
    // and immediately reload the table so "assistant tool_calls → tool result → next response" appear in order.
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(handleSessionMessagesChanged:)
                                                 name:@"AiSessionMessagesDidChangeNotification"
                                               object:nil];
}

/// Session message-change notification callback: reload the table and scroll to the bottom only if the notification is for the current session
- (void)handleSessionMessagesChanged:(NSNotification *)note {
    if (note.object && ![note.object isEqual:self.session]) return;
    [self reloadAndScrollToBottom];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [self.activityIndicator stopAnimating];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    // Scroll to the bottom when entering a session; no animation to avoid a jump on appearance. Do not scroll for an empty session.
    if (self.session.messages.count > 0) {
        [self scrollToBottomAnimated:NO];
    }
}

#pragma mark - Nav Bar

- (void)setupNavBar {
    // Right-side "Sessions" icon (placeholder for Phase 2 session list integration)
    UIBarButtonItem *sessionsItem = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"rectangle.stack.badge.person.crop"]
                                                                     style:UIBarButtonItemStylePlain
                                                                    target:self
                                                                    action:@selector(sessionsAction)];
    self.navigationItem.rightBarButtonItem = sessionsItem;
    // The navigation stack provides the Back button; no additional setup is needed
}

- (void)sessionsAction {
    AISessionListViewController *listVC = [[AISessionListViewController alloc] init];
    __weak typeof(self) weakSelf = self;
    listVC.onSelectSession = ^(AiSession *session) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        [strongSelf switchToSession:session];
        [strongSelf.navigationController popViewControllerAnimated:YES];
    };
    listVC.onNewSession = ^(AiSession *session) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        [strongSelf switchToSession:session];
        [strongSelf.navigationController popToRootViewControllerAnimated:YES];
    };

    if (self.navigationController) {
        [self.navigationController pushViewController:listVC animated:YES];
    } else {
        UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:listVC];
        nav.modalPresentationStyle = UIModalPresentationFormSheet;
        [self presentViewController:nav animated:YES completion:nil];
    }
}

/// Switch to the specified session and refresh the interface
- (void)switchToSession:(AiSession *)session {
    if (!session) return;
    self.session = session;
    NSString *title = session.title.length > 0 ? session.title : localize(@"ai.assistant.title", @"AI Assistant");
    self.navigationItem.title = title;
    [self reloadAndScrollToBottom];
    [self updateEmptyState];
}

/// Open the provider configuration page
- (void)presentProviderConfig {
    AIProviderConfigViewController *vc = [[AIProviderConfigViewController alloc] init];
    if (self.navigationController) {
        [self.navigationController pushViewController:vc animated:YES];
    } else {
        UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:vc];
        nav.modalPresentationStyle = UIModalPresentationFormSheet;
        [self presentViewController:nav animated:YES completion:nil];
    }
}

#pragma mark - Layout

- (void)setupUI {
    // Table
    self.tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    self.tableView.translatesAutoresizingMaskIntoConstraints = NO;
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    self.tableView.backgroundColor = [UIColor clearColor];
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    self.tableView.keyboardDismissMode = UIScrollViewKeyboardDismissModeInteractive;
    self.tableView.alwaysBounceVertical = YES;
    self.tableView.estimatedRowHeight = 80;
    [self.tableView registerClass:[AIMessageCell class] forCellReuseIdentifier:@"AIMessageCell"];
    [self.view addSubview:self.tableView];

    // Bottom input bar
    self.inputBar = [[AIInputBarView alloc] init];
    [self.view addSubview:self.inputBar];
    self.inputBar.bottomInset = self.view.safeAreaInsets.bottom;

    __weak typeof(self) weakSelf = self;
    self.inputBar.onSend = ^(NSString *text) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        [strongSelf handleSend:text];
    };
    self.inputBar.onStop = ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        [strongSelf handleStop];
    };
    self.inputBar.onModelTap = ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        [strongSelf handleModelTap];
    };

    // Empty-state view
    [self setupEmptyState];

    self.inputBarBottomConstraint = [self.inputBar.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor];
    [NSLayoutConstraint activateConstraints:@[
        [self.tableView.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [self.tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.tableView.bottomAnchor constraintEqualToAnchor:self.inputBar.topAnchor],

        [self.inputBar.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.inputBar.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        self.inputBarBottomConstraint,
    ]];

    // Loading indicator: simple loading feedback when sending a message
    self.activityIndicator = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    self.activityIndicator.translatesAutoresizingMaskIntoConstraints = NO;
    self.activityIndicator.hidesWhenStopped = YES;
    [self.view addSubview:self.activityIndicator];
    [NSLayoutConstraint activateConstraints:@[
        [self.activityIndicator.centerXAnchor constraintEqualToAnchor:self.tableView.centerXAnchor],
        [self.activityIndicator.centerYAnchor constraintEqualToAnchor:self.tableView.centerYAnchor],
    ]];
}

- (void)viewSafeAreaInsetsDidChange {
    [super viewSafeAreaInsetsDidChange];
    // Keep the input bar's bottom inset in sync when rotation/split-screen changes the safe area
    self.inputBar.bottomInset = self.view.safeAreaInsets.bottom;
}

- (void)setupEmptyState {
    self.emptyStateView = [[UIView alloc] init];
    self.emptyStateView.translatesAutoresizingMaskIntoConstraints = NO;
    self.emptyStateView.hidden = YES;
    self.emptyStateView.backgroundColor = [UIColor clearColor];
    [self.view addSubview:self.emptyStateView];

    // Important fix (empty-state icon appeared as a string of letters): it was a UILabel filled with an SF Symbol name ("sparkles"),
    // so it displayed as text. Use UIImageView + systemImageNamed: to render the icon properly.
    self.emptyIcon = [[UIImageView alloc] init];
    self.emptyIcon.translatesAutoresizingMaskIntoConstraints = NO;
    self.emptyIcon.contentMode = UIViewContentModeScaleAspectFit;
    UIImageSymbolConfiguration *iconConfig = [UIImageSymbolConfiguration configurationWithPointSize:56 weight:UIImageSymbolWeightRegular];
    self.emptyIcon.image = [UIImage systemImageNamed:@"sparkles" withConfiguration:iconConfig];
    self.emptyIcon.tintColor = [UIColor secondaryLabelColor];
    [self.emptyStateView addSubview:self.emptyIcon];

    self.emptyTitle = [[UILabel alloc] init];
    self.emptyTitle.translatesAutoresizingMaskIntoConstraints = NO;
    self.emptyTitle.font = [UIFont systemFontOfSize:18 weight:UIFontWeightSemibold];
    self.emptyTitle.textColor = [UIColor labelColor];
    self.emptyTitle.textAlignment = NSTextAlignmentCenter;
    self.emptyTitle.numberOfLines = 0;
    [self.emptyStateView addSubview:self.emptyTitle];

    self.emptySubtitle = [[UILabel alloc] init];
    self.emptySubtitle.translatesAutoresizingMaskIntoConstraints = NO;
    self.emptySubtitle.font = [UIFont systemFontOfSize:14 weight:UIFontWeightRegular];
    self.emptySubtitle.textColor = [UIColor secondaryLabelColor];
    self.emptySubtitle.textAlignment = NSTextAlignmentCenter;
    self.emptySubtitle.numberOfLines = 0;
    [self.emptyStateView addSubview:self.emptySubtitle];

    self.configureButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.configureButton.translatesAutoresizingMaskIntoConstraints = NO;
    self.configureButton.hidden = YES;
    self.configureButton.titleLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
    [self.configureButton setTitle:@"Configure" forState:UIControlStateNormal];
    [self.configureButton addTarget:self action:@selector(configureAction) forControlEvents:UIControlEventTouchUpInside];
    // Capsule button
    self.configureButton.backgroundColor = [accentColor() colorWithAlphaComponent:0.15];
    self.configureButton.layer.cornerRadius = 16;
    self.configureButton.layer.cornerCurve = kCACornerCurveContinuous;
    self.configureButton.clipsToBounds = YES;
    [self.configureButton setTitleColor:accentColor() forState:UIControlStateNormal];
    [self.emptyStateView addSubview:self.configureButton];

    [NSLayoutConstraint activateConstraints:@[
        [self.emptyStateView.centerXAnchor constraintEqualToAnchor:self.tableView.centerXAnchor],
        [self.emptyStateView.centerYAnchor constraintEqualToAnchor:self.tableView.centerYAnchor],
        [self.emptyStateView.leadingAnchor constraintGreaterThanOrEqualToAnchor:self.tableView.leadingAnchor constant:32],
        [self.emptyStateView.trailingAnchor constraintLessThanOrEqualToAnchor:self.tableView.trailingAnchor constant:-32],

        [self.emptyIcon.topAnchor constraintEqualToAnchor:self.emptyStateView.topAnchor],
        [self.emptyIcon.centerXAnchor constraintEqualToAnchor:self.emptyStateView.centerXAnchor],

        [self.emptyTitle.topAnchor constraintEqualToAnchor:self.emptyIcon.bottomAnchor constant:12],
        [self.emptyTitle.leadingAnchor constraintEqualToAnchor:self.emptyStateView.leadingAnchor],
        [self.emptyTitle.trailingAnchor constraintEqualToAnchor:self.emptyStateView.trailingAnchor],

        [self.emptySubtitle.topAnchor constraintEqualToAnchor:self.emptyTitle.bottomAnchor constant:6],
        [self.emptySubtitle.leadingAnchor constraintEqualToAnchor:self.emptyStateView.leadingAnchor],
        [self.emptySubtitle.trailingAnchor constraintEqualToAnchor:self.emptyStateView.trailingAnchor],

        [self.configureButton.topAnchor constraintEqualToAnchor:self.emptySubtitle.bottomAnchor constant:16],
        [self.configureButton.centerXAnchor constraintEqualToAnchor:self.emptyStateView.centerXAnchor],
        [self.configureButton.heightAnchor constraintEqualToConstant:36],
        [self.configureButton.widthAnchor constraintEqualToConstant:96],
        [self.configureButton.bottomAnchor constraintEqualToAnchor:self.emptyStateView.bottomAnchor],
    ]];
}

#pragma mark - Keyboard

- (void)setupKeyboardObservers {
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(keyboardWillShow:)
                                                 name:UIKeyboardWillShowNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(keyboardWillHide:)
                                                 name:UIKeyboardWillHideNotification
                                               object:nil];
}

- (void)keyboardWillShow:(NSNotification *)notification {
    NSDictionary *userInfo = notification.userInfo;
    CGRect keyboardFrame = [userInfo[UIKeyboardFrameEndUserInfoKey] CGRectValue];
    CGRect converted = [self.view convertRect:keyboardFrame fromView:nil];
    CGFloat overlap = self.view.bounds.size.height - converted.origin.y;
    if (overlap < 0) overlap = 0;
    self.inputBarBottomConstraint.constant = -overlap;
    // The input field's bottom is anchored to view.bottomAnchor; the bottom safe area disappears when the keyboard appears, so simply lift it
    [self animateLayoutWithUserInfo:userInfo];
    [self scrollToBottomAnimated:YES];
}

- (void)keyboardWillHide:(NSNotification *)notification {
    self.inputBarBottomConstraint.constant = 0;
    [self animateLayoutWithUserInfo:notification.userInfo];
}

- (void)animateLayoutWithUserInfo:(NSDictionary *)userInfo {
    NSTimeInterval duration = [userInfo[UIKeyboardAnimationDurationUserInfoKey] doubleValue] ?: 0.25;
    [UIView animateWithDuration:duration animations:^{
        [self.view layoutIfNeeded];
    }];
}

#pragma mark - Model / provider

- (AiProvider *)currentProvider {
    return [[AiProviderStore sharedStore] selectedProvider];
}

- (void)updateModelLabel {
    AiProvider *provider = [self currentProvider];
    if (provider && provider.name.length > 0) {
        NSString *model = provider.model.length > 0 ? provider.model : @"Default Model";
        self.inputBar.modelLabel.text = [NSString stringWithFormat:@"%@ / %@", provider.name, model];
        self.inputBar.modelLabel.textColor = [UIColor labelColor];
    } else {
        self.inputBar.modelLabel.text = @"No AI Provider Configured";
        self.inputBar.modelLabel.textColor = [UIColor secondaryLabelColor];
    }
}

- (void)handleModelTap {
    // Phase 2: tap the model label to open the provider configuration page (switch/configure service)
    [self presentProviderConfig];
}

- (void)showConfigureHint {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"No AI Provider Configured"
                                                                    message:@"Configure the API service in Settings → AI Assistant."
                                                             preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)configureAction {
    [self presentProviderConfig];
}

#pragma mark - Send / stop

- (void)handleSend:(NSString *)text {
    NSString *trimmed = [text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (trimmed.length == 0) return;

    AiProvider *provider = [self currentProvider];
    if (!provider) {
        [self showConfigureHint];
        return;
    }

    [self.inputBar clearText];
    [self.inputBar setIsSending:YES];

    // Send flow: AiAgent appends the user message + assistant placeholder and handles persistence
    __weak typeof(self) weakSelf = self;
    [[AiAgent sharedAgent] sendUserMessage:trimmed
                                   session:self.session
                                  provider:provider
                                  streaming:YES
                              chunkHandler:^(NSString *partial) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        [strongSelf updateStreamingCell];
    } completionHandler:^(NSError *error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        // Important fix (crash when sending a message): completionHandler also runs on a background queue; UI updates must run on the main thread
        dispatch_async(dispatch_get_main_queue(), ^{
            [strongSelf.inputBar setIsSending:NO];
            [strongSelf.activityIndicator stopAnimating];
            strongSelf.lastStreamUpdateTime = 0;
            if (error) {
                [strongSelf showErrorAlert:error];
            }
            [strongSelf reloadAndScrollToBottom];
            [strongSelf updateEmptyState];
        });
    }];

    // Important fix (user message did not appear immediately after sending): sendUserMessage synchronously appends the user message and assistant placeholder
    // to session.messages, so calling reloadData now displays the user message immediately. Previously the table was refreshed before the call,
    // before the user message had been added, so it did not appear until the first AI chunk arrived.
    [self reloadAndScrollToBottom];
    // Hide the welcome text immediately after the first message is sent: the user message is synchronously added to session.messages, so refresh the empty state now.
    [self updateEmptyState];
}

/// Throttled refresh of the last assistant message currently being streamed
- (void)updateStreamingCell {
    NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
    if ((now - self.lastStreamUpdateTime) < kUIThrottleInterval) return;
    self.lastStreamUpdateTime = now;

    // Important fix (crash when sending a message): chunkHandler is called on AiAPIClient's background dispatch queue,
    // but UITableView can only be updated on the main thread. The previous implementation called reloadRows directly on the callback thread, causing a UIKit assertion crash.
    // Always dispatch to the main thread here, and use reloadData to synchronize when the row count differs from the data source
    // (preventing reloadRows from triggering "invalid update: invalid number of rows").
    dispatch_async(dispatch_get_main_queue(), ^{
        __strong typeof(self) strongSelf = self;
        if (!strongSelf) return;

        NSInteger modelCount = strongSelf.session.messages.count;
        if (modelCount == 0) return;
        NSInteger tableCount = [strongSelf.tableView numberOfRowsInSection:0];

        // Search backward for the first streaming==YES placeholder message; reload the whole table if none is found
        NSInteger streamingRow = NSNotFound;
        for (NSInteger i = modelCount - 1; i >= 0; i--) {
            AiMessage *m = strongSelf.session.messages[i];
            if (m.streaming) {
                streamingRow = i;
                break;
            }
        }

        if (streamingRow == NSNotFound) {
            // No streaming placeholder row: fall back to reloading the entire table
            [strongSelf.tableView reloadData];
        } else if (modelCount != tableCount) {
            // Data source has a new row but the table is not synchronized yet: reload the entire table to align row counts
            [strongSelf.tableView reloadData];
        } else {
            NSIndexPath *idx = [NSIndexPath indexPathForRow:streamingRow inSection:0];
            [strongSelf.tableView reloadRowsAtIndexPaths:@[idx] withRowAnimation:UITableViewRowAnimationNone];
        }
        [strongSelf scrollToBottomAnimated:NO];
    });
}

- (void)handleStop {
    [[AiAgent sharedAgent] stopCurrent];
    [self.inputBar setIsSending:NO];
    [self.activityIndicator stopAnimating];
    [self reloadAndScrollToBottom];
}

#pragma mark - Table

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.session.messages.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    AIMessageCell *cell = [tableView dequeueReusableCellWithIdentifier:@"AIMessageCell" forIndexPath:indexPath];
    AiMessage *message = self.session.messages[indexPath.row];
    BOOL md = [[AiSettings sharedSettings] markdownEnabled];
    [cell configureWithMessage:message markdownEnabled:md];
    return cell;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    AiMessage *message = self.session.messages[indexPath.row];
    BOOL md = [[AiSettings sharedSettings] markdownEnabled];
    return [AIMessageCell cellHeightForMessage:message width:tableView.bounds.size.width markdownEnabled:md];
}

#pragma mark - Empty state

- (void)updateEmptyState {
    if (!self.emptyStateView) return;
    BOOL hasProvider = [self currentProvider] != nil;
    BOOL hasMessages = self.session.messages.count > 0;

    if (!hasProvider) {
        // Provider is not configured: show setup guidance regardless of whether there are messages
        self.emptyStateView.hidden = NO;
        self.emptyIcon.image = [UIImage systemImageNamed:@"gearshape.2" withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:56 weight:UIImageSymbolWeightRegular]];
        self.emptyTitle.text = @"No AI Provider Configured";
        self.emptySubtitle.text = @"Go to Settings → AI Assistant to configure the API service";
        self.configureButton.hidden = NO;
    } else if (!hasMessages) {
        self.emptyStateView.hidden = NO;
        self.emptyIcon.image = [UIImage systemImageNamed:@"sparkles" withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:56 weight:UIImageSymbolWeightRegular]];
        self.emptyTitle.text = @"Say hello to the AI assistant";
        self.emptySubtitle.text = @"Ask Metallic about the launcher or Minecraft";
        self.configureButton.hidden = YES;
    } else {
        self.emptyStateView.hidden = YES;
    }
}

#pragma mark - Helpers

- (void)reloadAndScrollToBottom {
    [self.tableView reloadData];
    [self scrollToBottomAnimated:YES];
}

- (void)scrollToBottomAnimated:(BOOL)animated {
    NSInteger rows = [self.tableView numberOfRowsInSection:0];
    if (rows == 0) return;
    NSIndexPath *ip = [NSIndexPath indexPathForRow:(rows - 1) inSection:0];
    [self.tableView scrollToRowAtIndexPath:ip atScrollPosition:UITableViewScrollPositionBottom animated:animated];
}

- (void)showErrorAlert:(NSError *)error {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Request Failed"
                                                                    message:error.localizedDescription ?: @"Unknown error"
                                                             preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

@end