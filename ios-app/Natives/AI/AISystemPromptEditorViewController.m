//
//  AISystemPromptEditorViewController.m
//  Amethyst
//
//  AI system prompt editor page implementation.
//

#import "AISystemPromptEditorViewController.h"
#import "AiSettings.h"
#import "BackgroundManager.h"
#import "LauncherPreferences.h"
#import "utils.h"   // ★ [HOST-BUG-A] Use localize() consistently

@interface AISystemPromptEditorViewController () <UITextViewDelegate>
@property (nonatomic, strong) UITextView *textView;
@property (nonatomic, strong) UIView *cardView;
@end

@implementation AISystemPromptEditorViewController

// ★ [LAND-BUG] This page is presented as the root of a modal UINavigationController from Settings. The top left was "Restore Defaults",
//   and the top right was "Save", with no close option ⇒ users could not exit without saving. Add "Close" on the far left when modal.
- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    UINavigationController *nav = self.navigationController;
    if (nav.presentingViewController == nil || nav.viewControllers.firstObject != self) return;
    if (self.navigationItem.leftBarButtonItems.count >= 2) return;   // Already injected
    UIBarButtonItem *landBugCloseItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemClose
                                                                                      target:self
                                                                                      action:@selector(landBugCloseTapped)];
    landBugCloseItem.accessibilityLabel = @"Close";
    NSMutableArray<UIBarButtonItem *> *items = [NSMutableArray arrayWithObject:landBugCloseItem];
    if (self.navigationItem.leftBarButtonItem) {
        [items addObject:self.navigationItem.leftBarButtonItem];   // Keep "Restore Defaults"
    }
    self.navigationItem.leftBarButtonItems = items;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = localize(@"ai.system_prompt.title", @"System Prompt");   // ★ [HOST-BUG-A]
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeNever;
    self.view.backgroundColor = [[UIColor labelColor] colorWithAlphaComponent:0.04];
    [[BackgroundManager sharedManager] makeViewControllerTransparent:self];

    // Restore defaults
    UIBarButtonItem *resetItem = [[UIBarButtonItem alloc] initWithTitle:@"Restore Defaults"
                                                                  style:UIBarButtonItemStylePlain
                                                                 target:self
                                                                 action:@selector(resetAction)];
    self.navigationItem.leftBarButtonItem = resetItem;
    // Save
    UIBarButtonItem *saveItem = [[UIBarButtonItem alloc] initWithTitle:@"Save"
                                                                 style:UIBarButtonItemStyleDone
                                                                target:self
                                                                action:@selector(saveAction)];
    self.navigationItem.rightBarButtonItem = saveItem;

    [self setupUI];
    // Load the current system prompt when opening
    self.textView.text = [[AiSettings sharedSettings] systemPrompt];
    [self.textView becomeFirstResponder];
}

- (void)setupUI {
    // Card container
    self.cardView = [[UIView alloc] init];
    self.cardView.translatesAutoresizingMaskIntoConstraints = NO;
    self.cardView.backgroundColor = [[UIColor whiteColor] colorWithAlphaComponent:0.08];
    self.cardView.layer.cornerRadius = 16;
    self.cardView.layer.cornerCurve = kCACornerCurveContinuous;
    self.cardView.layer.borderWidth = 0.5;
    self.cardView.layer.borderColor = [[UIColor whiteColor] colorWithAlphaComponent:0.10].CGColor;
    self.cardView.layer.shadowColor = [UIColor blackColor].CGColor;
    self.cardView.layer.shadowOffset = CGSizeMake(0, 2);
    self.cardView.layer.shadowOpacity = 0.10;
    self.cardView.layer.shadowRadius = 6;
    [[BackgroundManager sharedManager] applyEffectToView:self.cardView];
    [self.view addSubview:self.cardView];

    // Help text
    UILabel *hintLabel = [[UILabel alloc] init];
    hintLabel.translatesAutoresizingMaskIntoConstraints = NO;
    hintLabel.text = @"This is prepended to every conversation to define how the Metallic assistant should behave.";
    hintLabel.font = [UIFont systemFontOfSize:12];
    hintLabel.textColor = [UIColor secondaryLabelColor];
    hintLabel.numberOfLines = 0;
    [self.view addSubview:hintLabel];

    // Multiline text editor
    self.textView = [[UITextView alloc] init];
    self.textView.translatesAutoresizingMaskIntoConstraints = NO;
    self.textView.delegate = self;
    self.textView.font = [UIFont systemFontOfSize:15];
    self.textView.textColor = [UIColor labelColor];
    self.textView.backgroundColor = [UIColor clearColor];
    self.textView.textContainerInset = UIEdgeInsetsMake(14, 14, 14, 14);
    self.textView.keyboardDismissMode = UIScrollViewKeyboardDismissModeInteractive;
    [self.cardView addSubview:self.textView];

    [NSLayoutConstraint activateConstraints:@[
        [hintLabel.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:12],
        [hintLabel.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:24],
        [hintLabel.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-24],

        [self.cardView.topAnchor constraintEqualToAnchor:hintLabel.bottomAnchor constant:12],
        [self.cardView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:16],
        [self.cardView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-16],
        [self.cardView.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor constant:-16],

        [self.textView.topAnchor constraintEqualToAnchor:self.cardView.topAnchor],
        [self.textView.leadingAnchor constraintEqualToAnchor:self.cardView.leadingAnchor],
        [self.textView.trailingAnchor constraintEqualToAnchor:self.cardView.trailingAnchor],
        [self.textView.bottomAnchor constraintEqualToAnchor:self.cardView.bottomAnchor],
    ]];
}

#pragma mark - Actions

- (void)resetAction {
    [self.textView setText:[AiSettings defaultSystemPrompt]];
}

- (void)saveAction {
    NSString *text = [self.textView.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    [[AiSettings sharedSettings] setSystemPrompt:text];
    // ★ [LAND-BUG] This page is only presented as the root of a modal UINavigationController from Settings (LauncherPreferencesViewController:1208),
    //   so pop is a no-op ⇒ after saving the page remains open with no way out. Use dismiss instead (same compatibility pattern as ResourcePacksManagerViewController.closeTapped).
    if (self.navigationController && self.navigationController.viewControllers.firstObject != self) {
        [self.navigationController popViewControllerAnimated:YES];
    } else {
        [self dismissViewControllerAnimated:YES completion:nil];
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

@end