//
//  AIProviderConfigViewController.m
//  Amethyst
//
//  AI provider configuration page + provider edit form (private class in same file) + connectivity test.
//

#import "AIProviderConfigViewController.h"
#import "AiProvider.h"
#import "AiProviderStore.h"
#import "AiAPIClient.h"
#import "BackgroundManager.h"
#import "LauncherPreferences.h"
#import "utils.h"   // ★ [HOST-BUG-A] Use localize() consistently
#import <objc/runtime.h>

NS_ASSUME_NONNULL_BEGIN

#pragma mark - Provider edit form (private)

/// Provider form page for editing / adding
@interface AIProviderEditViewController : UITableViewController

/// Provider to edit (nil means add)
@property (nonatomic, strong, nullable) AiProvider *provider;
/// Save success callback (used to refresh the parent list)
@property (nonatomic, copy, nullable) void (^onSaved)(void);

@end

NS_ASSUME_NONNULL_END

#pragma mark - Provider configuration list

@interface AIProviderConfigViewController () <UITableViewDataSource, UITableViewDelegate>
@property (nonatomic, strong) UITableView *tableView;
@end

@implementation AIProviderConfigViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = localize(@"ai.provider_config.title", @"Provider Configuration");   // ★ [HOST-BUG-A]
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeNever;
    self.view.backgroundColor = [[UIColor labelColor] colorWithAlphaComponent:0.04];
    [[BackgroundManager sharedManager] makeViewControllerTransparent:self];

    [self setupTable];
    [self.tableView reloadData];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    // Refresh after returning from the edit page (selection / list)
    [self.tableView reloadData];

    // ★ [LAND-BUG] This page is presented as the root of a modal UINavigationController from "Settings ▸ AI ▸ Provider Configuration" (LauncherPreferencesViewController:1167)
    //   and from the AI session page. It previously had no navigationItem, so a full-screen modal had no back/close control ⇒ users could not exit.
    //   Add a top-left "Close" button (do not inject it when pushed onto a navigation stack).
    UINavigationController *landBugNav = self.navigationController;
    if (landBugNav.presentingViewController != nil && landBugNav.viewControllers.firstObject == self &&
        self.navigationItem.leftBarButtonItem == nil) {
        UIBarButtonItem *landBugCloseItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemClose
                                                                                          target:self
                                                                                          action:@selector(landBugCloseTapped)];
        landBugCloseItem.accessibilityLabel = @"Close";
        self.navigationItem.leftBarButtonItem = landBugCloseItem;
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

- (void)setupTable {
    self.tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    self.tableView.translatesAutoresizingMaskIntoConstraints = NO;
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    self.tableView.backgroundColor = [UIColor clearColor];
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    self.tableView.estimatedRowHeight = 96;
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    [self.tableView registerClass:[UITableViewCell class] forCellReuseIdentifier:@"AiProviderCell"];
    [self.view addSubview:self.tableView];

    [NSLayoutConstraint activateConstraints:@[
        [self.tableView.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [self.tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.tableView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
    ]];
}

#pragma mark - Top information / add card

- (UIView *)headerView {
    UIView *header = [[UIView alloc] initWithFrame:CGRectMake(0, 0, self.tableView.bounds.size.width, 0)];

    // Information card
    UIView *infoCard = [[UIView alloc] init];
    infoCard.translatesAutoresizingMaskIntoConstraints = NO;
    infoCard.backgroundColor = [[UIColor whiteColor] colorWithAlphaComponent:0.08];
    infoCard.layer.cornerRadius = 16;
    infoCard.layer.cornerCurve = kCACornerCurveContinuous;
    infoCard.layer.borderWidth = 0.5;
    infoCard.layer.borderColor = [[UIColor whiteColor] colorWithAlphaComponent:0.10].CGColor;
    [[BackgroundManager sharedManager] applyEffectToView:infoCard];
    [header addSubview:infoCard];

    UILabel *infoLabel = [[UILabel alloc] init];
    infoLabel.translatesAutoresizingMaskIntoConstraints = NO;
    infoLabel.text = @"Supports any OpenAI-compatible endpoint, including OpenAI / DeepSeek / Kimi / GLM / Ollama. Enter the Base URL and model name to get started.";
    infoLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightRegular];
    infoLabel.textColor = [UIColor secondaryLabelColor];
    infoLabel.numberOfLines = 0;
    [infoCard addSubview:infoLabel];

    // Add button
    UIButton *addButton = [UIButton buttonWithType:UIButtonTypeSystem];
    addButton.translatesAutoresizingMaskIntoConstraints = NO;
    [addButton setTitle:@"＋ Add Provider" forState:UIControlStateNormal];
    addButton.titleLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
    [addButton setTitleColor:accentColor() forState:UIControlStateNormal];
    addButton.backgroundColor = [accentColor() colorWithAlphaComponent:0.15];
    addButton.layer.cornerRadius = 16;
    addButton.layer.cornerCurve = kCACornerCurveContinuous;
    addButton.clipsToBounds = YES;
    [addButton addTarget:self action:@selector(addProviderAction) forControlEvents:UIControlEventTouchUpInside];
    [header addSubview:addButton];

    [NSLayoutConstraint activateConstraints:@[
        [infoCard.topAnchor constraintEqualToAnchor:header.topAnchor constant:8],
        [infoCard.leadingAnchor constraintEqualToAnchor:header.leadingAnchor constant:16],
        [infoCard.trailingAnchor constraintEqualToAnchor:header.trailingAnchor constant:-16],

        [infoLabel.topAnchor constraintEqualToAnchor:infoCard.topAnchor constant:14],
        [infoLabel.leadingAnchor constraintEqualToAnchor:infoCard.leadingAnchor constant:16],
        [infoLabel.trailingAnchor constraintEqualToAnchor:infoCard.trailingAnchor constant:-16],
        [infoLabel.bottomAnchor constraintEqualToAnchor:infoCard.bottomAnchor constant:-14],

        [addButton.topAnchor constraintEqualToAnchor:infoCard.bottomAnchor constant:12],
        [addButton.leadingAnchor constraintEqualToAnchor:header.leadingAnchor constant:16],
        [addButton.trailingAnchor constraintEqualToAnchor:header.trailingAnchor constant:-16],
        [addButton.heightAnchor constraintEqualToConstant:44],
        [addButton.bottomAnchor constraintEqualToAnchor:header.bottomAnchor constant:-4],
    ]];

    // Calculate height
    CGFloat width = self.tableView.bounds.size.width ?: [UIScreen mainScreen].bounds.size.width;
    header.frame = CGRectMake(0, 0, width, 0);
    [header setNeedsLayout];
    [header layoutIfNeeded];
    CGFloat height = [header systemLayoutSizeFittingSize:CGSizeMake(width, 0)
                            withHorizontalFittingPriority:UILayoutPriorityRequired
                                  verticalFittingPriority:UILayoutPriorityFittingSizeLevel].height;
    header.frame = CGRectMake(0, 0, width, height);
    return header;
}

#pragma mark - Actions

- (void)addProviderAction {
    AIProviderEditViewController *editVC = [[AIProviderEditViewController alloc] init];
    editVC.provider = nil;
    __weak typeof(self) weakSelf = self;
    editVC.onSaved = ^{
        [weakSelf.tableView reloadData];
    };
    [self.navigationController pushViewController:editVC animated:YES];
}

- (void)editProvider:(AiProvider *)provider {
    AIProviderEditViewController *editVC = [[AIProviderEditViewController alloc] init];
    editVC.provider = provider;
    __weak typeof(self) weakSelf = self;
    editVC.onSaved = ^{
        [weakSelf.tableView reloadData];
    };
    [self.navigationController pushViewController:editVC animated:YES];
}

- (void)selectProvider:(AiProvider *)provider {
    [[AiProviderStore sharedStore] setSelectedProvider:provider];
    [self.tableView reloadData];
}

#pragma mark - UITableViewDataSource

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 1;
}

// Information card + add button as the header; provider cards follow
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return [AiProviderStore sharedStore].providers.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"AiProviderCell" forIndexPath:indexPath];
    for (UIView *sub in cell.contentView.subviews) {
        [sub removeFromSuperview];
    }
    cell.accessoryType = UITableViewCellAccessoryNone;
    cell.accessoryView = nil;
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    cell.backgroundColor = [UIColor clearColor];
    cell.contentView.backgroundColor = [UIColor clearColor];

    AiProvider *provider = [AiProviderStore sharedStore].providers[indexPath.row];
    AiProvider *selected = [[AiProviderStore sharedStore] selectedProvider];
    BOOL isSelected = (selected != nil && [selected.identifier isEqualToString:provider.identifier]);

    // Card container
    UIView *cardView = [[UIView alloc] init];
    cardView.translatesAutoresizingMaskIntoConstraints = NO;
    cardView.backgroundColor = isSelected ? [accentColor() colorWithAlphaComponent:0.15]
                                         : [[UIColor whiteColor] colorWithAlphaComponent:0.08];
    cardView.layer.cornerRadius = 16;
    cardView.layer.cornerCurve = kCACornerCurveContinuous;
    cardView.layer.borderWidth = 0.5;
    cardView.layer.borderColor = isSelected ? accentColor().CGColor
                                            : [[UIColor whiteColor] colorWithAlphaComponent:0.10].CGColor;
    cardView.layer.shadowColor = [UIColor blackColor].CGColor;
    cardView.layer.shadowOffset = CGSizeMake(0, 2);
    cardView.layer.shadowOpacity = 0.10;
    cardView.layer.shadowRadius = 6;
    [[BackgroundManager sharedManager] applyEffectToView:cardView];
    [cell.contentView addSubview:cardView];

    // Name
    UILabel *nameLabel = [[UILabel alloc] init];
    nameLabel.translatesAutoresizingMaskIntoConstraints = NO;
    nameLabel.text = provider.name.length > 0 ? provider.name : @"Unnamed Provider";
    nameLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightSemibold];
    nameLabel.textColor = [UIColor labelColor];
    nameLabel.numberOfLines = 1;
    [cardView addSubview:nameLabel];

    // Model
    UILabel *modelLabel = [[UILabel alloc] init];
    modelLabel.translatesAutoresizingMaskIntoConstraints = NO;
    modelLabel.text = provider.model.length > 0 ? provider.model : @"Model Not Set";
    modelLabel.font = [UIFont monospacedSystemFontOfSize:12 weight:UIFontWeightRegular];
    modelLabel.textColor = [UIColor secondaryLabelColor];
    modelLabel.numberOfLines = 1;
    modelLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;
    [cardView addSubview:modelLabel];

    // Base URL
    UILabel *urlLabel = [[UILabel alloc] init];
    urlLabel.translatesAutoresizingMaskIntoConstraints = NO;
    urlLabel.text = provider.baseURL.length > 0 ? provider.baseURL : @"Base URL Not Set";
    urlLabel.font = [UIFont systemFontOfSize:12];
    urlLabel.textColor = [UIColor secondaryLabelColor];
    urlLabel.numberOfLines = 1;
    urlLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;
    [cardView addSubview:urlLabel];

    // Selected checkmark
    UIImageView *checkView = [[UIImageView alloc] init];
    checkView.translatesAutoresizingMaskIntoConstraints = NO;
    checkView.image = [UIImage systemImageNamed:@"checkmark.circle.fill"];
    checkView.tintColor = accentColor();
    checkView.contentMode = UIViewContentModeScaleAspectFit;
    checkView.hidden = !isSelected;
    [cardView addSubview:checkView];

    // Edit button
    UIButton *editButton = [UIButton buttonWithType:UIButtonTypeSystem];
    editButton.translatesAutoresizingMaskIntoConstraints = NO;
    [editButton setImage:[UIImage systemImageNamed:@"pencil"] forState:UIControlStateNormal];
    editButton.tintColor = accentColor();
    __weak typeof(self) weakSelf = self;
    [editButton addTarget:weakSelf action:@selector(editProviderAction:) forControlEvents:UIControlEventTouchUpInside];
    // Pass provider reference using an associated object
    objc_setAssociatedObject(editButton, "provider", provider, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [cardView addSubview:editButton];

    [NSLayoutConstraint activateConstraints:@[
        [cardView.topAnchor constraintEqualToAnchor:cell.contentView.topAnchor constant:6],
        [cardView.leadingAnchor constraintEqualToAnchor:cell.contentView.leadingAnchor constant:16],
        [cardView.trailingAnchor constraintEqualToAnchor:cell.contentView.trailingAnchor constant:-16],
        [cardView.bottomAnchor constraintEqualToAnchor:cell.contentView.bottomAnchor constant:-6],

        [nameLabel.leadingAnchor constraintEqualToAnchor:cardView.leadingAnchor constant:16],
        [nameLabel.topAnchor constraintEqualToAnchor:cardView.topAnchor constant:14],
        [nameLabel.trailingAnchor constraintLessThanOrEqualToAnchor:editButton.leadingAnchor constant:-8],

        [modelLabel.leadingAnchor constraintEqualToAnchor:nameLabel.leadingAnchor],
        [modelLabel.trailingAnchor constraintEqualToAnchor:nameLabel.trailingAnchor],
        [modelLabel.topAnchor constraintEqualToAnchor:nameLabel.bottomAnchor constant:4],

        [urlLabel.leadingAnchor constraintEqualToAnchor:nameLabel.leadingAnchor],
        [urlLabel.trailingAnchor constraintEqualToAnchor:cardView.trailingAnchor constant:-16],
        [urlLabel.topAnchor constraintEqualToAnchor:modelLabel.bottomAnchor constant:4],
        [urlLabel.bottomAnchor constraintEqualToAnchor:cardView.bottomAnchor constant:-14],

        [editButton.trailingAnchor constraintEqualToAnchor:cardView.trailingAnchor constant:-12],
        [editButton.topAnchor constraintEqualToAnchor:cardView.topAnchor constant:12],
        [editButton.widthAnchor constraintEqualToConstant:28],
        [editButton.heightAnchor constraintEqualToConstant:28],

        [checkView.trailingAnchor constraintEqualToAnchor:cardView.trailingAnchor constant:-14],
        [checkView.bottomAnchor constraintEqualToAnchor:cardView.bottomAnchor constant:-12],
        [checkView.widthAnchor constraintEqualToConstant:18],
        [checkView.heightAnchor constraintEqualToConstant:18],
    ]];

    return cell;
}

- (void)editProviderAction:(UIButton *)sender {
    AiProvider *provider = objc_getAssociatedObject(sender, "provider");
    if (provider) {
        [self editProvider:provider];
    }
}

#pragma mark - UITableViewDelegate

- (nullable UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section {
    return [self headerView];
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section {
    return [[self headerView] frame].size.height;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    AiProvider *provider = [AiProviderStore sharedStore].providers[indexPath.row];
    [self selectProvider:provider];
}

- (nullable NSArray<UITableViewRowAction *> *)tableView:(UITableView *)tableView editActionsForRowAtIndexPath:(NSIndexPath *)indexPath {
    __weak typeof(self) weakSelf = self;
    UITableViewRowAction *deleteAction = [UITableViewRowAction rowActionWithStyle:UITableViewRowActionStyleDestructive
                                                                           title:@"Delete"
                                                                         handler:^(UITableViewRowAction * _Nonnull action, NSIndexPath * _Nonnull ip) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        AiProvider *provider = [AiProviderStore sharedStore].providers[ip.row];
        [[AiProviderStore sharedStore] deleteProvider:provider];
        [strongSelf.tableView reloadData];
    }];
    return @[deleteAction];
}

- (UITableViewCellEditingStyle)tableView:(UITableView *)tableView editingStyleForRowAtIndexPath:(NSIndexPath *)indexPath {
    return UITableViewCellEditingStyleDelete;
}

@end

#pragma mark - AIProviderEditViewController implementation

@implementation AIProviderEditViewController {
    UITextField *_nameField;
    UITextField *_baseURLField;
    UITextField *_apiKeyField;
    UITextField *_modelField;
    UITextField *_maxTokensField;
    UITextField *_contextWindowField;
    UISlider *_temperatureSlider;
    UILabel *_temperatureLabel;
    BOOL _isEditing;
}

- (instancetype)init {
    self = [super initWithStyle:UITableViewStyleInsetGrouped];
    if (self) {
        _isEditing = NO;
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    _isEditing = (self.provider != nil);
    self.title = _isEditing ? localize(@"ai.provider_config.edit", @"Edit Provider") : localize(@"ai.provider_config.add", @"Add Provider");   // ★ [HOST-BUG-A]
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeNever;
    self.view.backgroundColor = [[UIColor labelColor] colorWithAlphaComponent:0.04];
    [[BackgroundManager sharedManager] makeViewControllerTransparent:self];

    UIBarButtonItem *saveItem = [[UIBarButtonItem alloc] initWithTitle:@"Save"
                                                                 style:UIBarButtonItemStyleDone
                                                                target:self
                                                                action:@selector(saveAction)];
    self.navigationItem.rightBarButtonItem = saveItem;

    [self buildFields];
    [self loadValues];
}

#pragma mark - Build fields

- (UITextField *)makeTextField:(NSString *)placeholder keyboard:(UIKeyboardType)keyboard secure:(BOOL)secure {
    UITextField *field = [[UITextField alloc] init];
    field.placeholder = placeholder;
    field.keyboardType = keyboard;
    field.secureTextEntry = secure;
    field.autocorrectionType = UITextAutocorrectionTypeNo;
    field.autocapitalizationType = UITextAutocapitalizationTypeNone;
    field.returnKeyType = UIReturnKeyDone;
    field.delegate = self;
    return field;
}

- (void)buildFields {
    _nameField = [self makeTextField:@"e.g. DeepSeek / OpenAI / Ollama" keyboard:UIKeyboardTypeDefault secure:NO];
    _baseURLField = [self makeTextField:@"https://api.deepseek.com/v1" keyboard:UIKeyboardTypeURL secure:NO];
    _apiKeyField = [self makeTextField:@"API Key" keyboard:UIKeyboardTypeDefault secure:YES];
    _modelField = [self makeTextField:@"e.g. deepseek-chat" keyboard:UIKeyboardTypeDefault secure:NO];
    _maxTokensField = [self makeTextField:@"Leave blank to use default 4096" keyboard:UIKeyboardTypeNumberPad secure:NO];
    _contextWindowField = [self makeTextField:@"Leave blank to use default 8192" keyboard:UIKeyboardTypeNumberPad secure:NO];

    _temperatureSlider = [[UISlider alloc] init];
    _temperatureSlider.minimumValue = 0;
    _temperatureSlider.maximumValue = 2;
    _temperatureSlider.continuous = YES;
    [_temperatureSlider addTarget:self action:@selector(temperatureChanged:) forControlEvents:UIControlEventValueChanged];
}

/// Load provider values into the fields
- (void)loadValues {
    if (!self.provider) {
        _temperatureSlider.value = 0.7;
        [self refreshTemperatureLabel];
        if ([AiProviderStore sharedStore].providers.count == 0) {
            // When no providers exist, prefill the DeepSeek preset to reduce setup effort
            AiProvider *preset = [AiProvider providerWithDictionary:[AiProviderStore defaultPresets].firstObject];
            _nameField.text = preset.name;
            _baseURLField.text = preset.baseURL;
            _modelField.text = preset.model;
        }
        return;
    }
    _nameField.text = self.provider.name;
    _baseURLField.text = self.provider.baseURL;
    // Do not display an existing API Key in plain text; show a placeholder instead. Leave blank to keep the existing key.
    if (self.provider.apiKey.length > 0) {
        _apiKeyField.placeholder = @"Saved (re-enter to change)";
    }
    _modelField.text = self.provider.model;
    _temperatureSlider.value = self.provider.temperature;
    _maxTokensField.text = self.provider.maxTokens > 0 ? [NSString stringWithFormat:@"%ld", (long)self.provider.maxTokens] : @"";
    _contextWindowField.text = self.provider.contextWindow > 0 ? [NSString stringWithFormat:@"%ld", (long)self.provider.contextWindow] : @"";
    [self refreshTemperatureLabel];
}

- (void)refreshTemperatureLabel {
    if (!_temperatureLabel) return;
    _temperatureLabel.text = [NSString stringWithFormat:@"%.2f", _temperatureSlider.value];
}

- (void)temperatureChanged:(UISlider *)sender {
    [self refreshTemperatureLabel];
    // Update the current temperature cell's detail text directly to avoid rebuilding the row and interrupting scrolling
    UITableViewCell *cell = [self.tableView cellForRowAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:1]];
    cell.detailTextLabel.text = _temperatureLabel.text;
}

#pragma mark - Table

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 3;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (section == 0) return 4; // Name / Base URL / API Key / Model
    if (section == 1) return 3; // Temperature / max tokens / context window
    return 1;                    // Test connection
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    if (section == 0) return @"Connection Details";
    if (section == 1) return @"Parameters";
    return nil;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:nil];
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    cell.backgroundColor = [[UIColor whiteColor] colorWithAlphaComponent:0.08];
    [[BackgroundManager sharedManager] applyEffectToCell:cell];

    if (indexPath.section == 0) {
        switch (indexPath.row) {
            case 0:
                [self configureInputCell:cell label:@"Name" field:_nameField];
                break;
            case 1:
                [self configureInputCell:cell label:@"Base URL" field:_baseURLField];
                break;
            case 2:
                [self configureInputCell:cell label:@"API Key" field:_apiKeyField];
                break;
            case 3:
                [self configureInputCell:cell label:@"Model" field:_modelField];
                break;
        }
    } else if (indexPath.section == 1) {
        switch (indexPath.row) {
            case 0: {
                cell.textLabel.text = @"Temperature";
                if (!_temperatureLabel) {
                    _temperatureLabel = [[UILabel alloc] init];
                    _temperatureLabel.font = [UIFont monospacedSystemFontOfSize:15 weight:UIFontWeightRegular];
                    _temperatureLabel.textColor = [UIColor secondaryLabelColor];
                    _temperatureLabel.textAlignment = NSTextAlignmentCenter;
                }
                [self refreshTemperatureLabel];
                cell.detailTextLabel.text = _temperatureLabel.text;
                // Place the slider on the right side of contentView and let it fill the space to avoid a narrow accessoryView area
                _temperatureSlider.translatesAutoresizingMaskIntoConstraints = NO;
                [cell.contentView addSubview:_temperatureSlider];
                [NSLayoutConstraint activateConstraints:@[
                    [_temperatureSlider.leadingAnchor constraintEqualToAnchor:cell.textLabel.trailingAnchor constant:12],
                    [_temperatureSlider.trailingAnchor constraintEqualToAnchor:cell.contentView.trailingAnchor constant:-16],
                    [_temperatureSlider.centerYAnchor constraintEqualToAnchor:cell.contentView.centerYAnchor],
                ]];
                break;
            }
            case 1:
                [self configureInputCell:cell label:@"Maximum Token Limit" field:_maxTokensField];
                break;
            case 2:
                [self configureInputCell:cell label:@"Context Window" field:_contextWindowField];
                break;
        }
    } else {
        cell.textLabel.text = @"Test Connection";
        cell.textLabel.textAlignment = NSTextAlignmentCenter;
        cell.textLabel.textColor = accentColor();
    }
    return cell;
}

/// Place the input field on the right side of cell.contentView and expand its tappable area.
/// Important fix (Base URL and other fields were not tappable / visually misaligned): the input field was previously in cell.accessoryView,
/// which is narrow, near the far right of the cell, and has a small, easily obscured touch area. Using contentView + AutoLayout
/// places the field next to its label and extends it to the cell's right edge, making the tap area much larger and the layout stable.
- (void)configureInputCell:(UITableViewCell *)cell label:(NSString *)label field:(UITextField *)field {
    cell.textLabel.text = label;
    field.translatesAutoresizingMaskIntoConstraints = NO;
    [cell.contentView addSubview:field];
    [NSLayoutConstraint activateConstraints:@[
        [field.leadingAnchor constraintEqualToAnchor:cell.textLabel.trailingAnchor constant:12],
        [field.trailingAnchor constraintEqualToAnchor:cell.contentView.trailingAnchor constant:-16],
        [field.centerYAnchor constraintEqualToAnchor:cell.contentView.centerYAnchor],
        [field.heightAnchor constraintGreaterThanOrEqualToConstant:34],
    ]];
}

- (nullable UIView *)tableView:(UITableView *)tableView viewForFooterInSection:(NSInteger)section {
    if (section == 2) {
        UILabel *footer = [[UILabel alloc] init];
        footer.backgroundColor = [UIColor clearColor];
        footer.font = [UIFont systemFontOfSize:12];
        footer.textColor = [UIColor secondaryLabelColor];
        footer.textAlignment = NSTextAlignmentCenter;
        footer.numberOfLines = 0;
        footer.text = @"Test Connection sends this provider a very short \"ping\" request to verify availability.";
        return footer;
    }
    return nil;
}

- (CGFloat)tableView:(UITableView *)tableView heightForFooterInSection:(NSInteger)section {
    return section == 2 ? 44 : CGFLOAT_MIN;
}

#pragma mark - Keyboard
- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    [textField resignFirstResponder];
    return YES;
}

#pragma mark - Save / test

/// Create an AiProvider from the current form fields (reuse the original identifier when editing)
- (AiProvider *)providerFromForm {
    AiProvider *provider = nil;
    if (_isEditing && self.provider) {
        provider = self.provider;
    } else {
        provider = [[AiProvider alloc] init];
    }

    provider.name = [_nameField.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    provider.baseURL = [_baseURLField.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    provider.model = [_modelField.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    provider.temperature = _temperatureSlider.value;

    NSString *maxTokensText = [_maxTokensField.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (maxTokensText.length > 0) {
        provider.maxTokens = maxTokensText.integerValue;
    }
    NSString *ctxText = [_contextWindowField.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (ctxText.length > 0) {
        provider.contextWindow = ctxText.integerValue;
    }

    // API Key: when editing, keep the original key if left blank
    if (_apiKeyField.text.length > 0) {
        provider.apiKey = _apiKeyField.text;
    } else if (!_isEditing) {
        provider.apiKey = @"";
    }
    return provider;
}

- (void)saveAction {
    AiProvider *provider = [self providerFromForm];
    NSString *name = [provider.name stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (name.length == 0) {
        [self showMessage:@"Notice" body:@"Enter a provider name"];
        return;
    }
    if (provider.baseURL.length == 0) {
        [self showMessage:@"Notice" body:@"Enter a Base URL"];
        return;
    }
    if (provider.model.length == 0) {
        [self showMessage:@"Notice" body:@"Enter a model name"];
        return;
    }

    if (_isEditing) {
        [[AiProviderStore sharedStore] updateProvider:provider];
    } else {
        [[AiProviderStore sharedStore] addProvider:provider];
        [[AiProviderStore sharedStore] setSelectedProvider:provider];
    }
    if (self.onSaved) {
        self.onSaved();
    }
    [self.navigationController popViewControllerAnimated:YES];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.section == 2 && indexPath.row == 0) {
        [self testConnectionAction];
    }
}

- (void)testConnectionAction {
    AiProvider *provider = [self providerFromForm];
    if (provider.baseURL.length == 0 || provider.model.length == 0) {
        [self showMessage:@"Unable to Test" body:@"Enter a Base URL and model name first."];
        return;
    }

    UIAlertController *loading = [UIAlertController alertControllerWithTitle:@"Test Connection" message:@"Testing, please wait…" preferredStyle:UIAlertControllerStyleAlert];
    [self presentViewController:loading animated:YES completion:nil];

    AiAPIClient *client = [[AiAPIClient alloc] init];
    [client testConnectionWithProvider:provider completion:^(NSString * _Nullable successMessage, NSError * _Nullable error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [loading dismissViewControllerAnimated:YES completion:^{
                if (error) {
                    [self showMessage:@"Connection Failed" body:error.localizedDescription ?: @"Unknown error"];
                } else {
                    [self showMessage:@"Connection Successful" body:successMessage ?: @"Connection successful"];
                }
            }];
        });
    }];
}

- (void)showMessage:(NSString *)title body:(NSString *)body {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title
                                                                   message:body
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

@end