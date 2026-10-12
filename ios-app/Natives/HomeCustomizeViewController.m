#import "utils.h"
#import "HomeCustomizeViewController.h"
#import "LauncherNewsViewController.h"
#import "BackgroundManager.h"
#import <QuartzCore/QuartzCore.h>

// MARK: - Available Shortcut Definitions

static NSDictionary *availableShortcuts(void) {
    return @{
        kShortcutActionMods:       @{@"title": localize(@"i18n_str_275", nil),    @"icon": @"puzzlepiece.extension.fill", @"color": @"#14B8A6"},
        kShortcutActionShaders:    @{@"title": localize(@"i18n_str_2016", nil),    @"icon": @"sun.max.fill",              @"color": @"#F97316"},
        kShortcutActionModpack:    @{@"title": localize(@"i18n_str_277", nil),  @"icon": @"shippingbox.fill",           @"color": @"#8B5CF6"},
        kShortcutActionBackground: @{@"title": localize(@"i18n_str_278", nil),    @"icon": @"photo.fill.on.rectangle.fill",@"color": @"#EC4899"},
        kShortcutActionVersions:   @{@"title": localize(@"i18n_str_279", nil),    @"icon": @"square.stack.3d.up.fill",    @"color": @"#6366F1"},
        kShortcutActionMultiplayer:@{@"title": localize(@"game.menu.multiplayer", @"Multiplayer"), @"icon": @"antenna.radiowaves.left.and.right", @"color": @"#0EA5E9"},
    };
}

static UIColor *hexColor(NSString *hex) {
    hex = [hex stringByReplacingOccurrencesOfString:@"#" withString:@""];
    unsigned int rgb = 0;
    [[NSScanner scannerWithString:hex] scanHexInt:&rgb];
    return [UIColor colorWithRed:((rgb >> 16) & 0xFF) / 255.0
                           green:((rgb >> 8) & 0xFF) / 255.0
                            blue:(rgb & 0xFF) / 255.0
                           alpha:1.0];
}

// MARK: - ★ [SIZE4] Four size options ↔ segmented-control index mapping

static HomeTileSize AmeTileSizeForSegmentIndex(NSInteger idx) {
    switch (idx) {
        case 0:  return HomeTileSizeSmall;   // 1×1
        case 1:  return HomeTileSizeWide;    // 2×1
        case 2:  return HomeTileSizeTall;    // 1×2
        case 3:  return HomeTileSizeLarge;   // 2×2
        default: return HomeTileSizeSmall;
    }
}

static NSInteger AmeSegmentIndexForTileSize(HomeTileSize size) {
    switch (size) {
        case HomeTileSizeWide:  return 1;
        case HomeTileSizeTall:  return 2;
        case HomeTileSizeLarge: return 3;
        case HomeTileSizeSmall:
        default:                return 0;
    }
}

// MARK: - Customization Tile Cell

@interface CustomizeTileCell : UITableViewCell
@property (nonatomic, strong) UIView *accentStrip;
@property (nonatomic, strong) UIImageView *tileIconView;
@property (nonatomic, strong) UILabel *tileTitleLabel;
@property (nonatomic, strong) UILabel *tileDetailLabel;
@property (nonatomic, strong) UISwitch *visibilitySwitch;
@property (nonatomic, strong) UILabel *sizeLabel;
@property (nonatomic, strong) UISegmentedControl *sizeSegmented;   // ★ [SIZE4] Four size options.
@property (nonatomic, weak)   HomeTileConfig *tile;                // ★ [SIZE4] Back-reference for changing the size.

- (void)configureWithTile:(HomeTileConfig *)tile;                  // ★ [SIZE4] Forward declaration.
- (void)sizeSegmentChanged:(UISegmentedControl *)sender;           // ★ [SIZE4] Segmented-control callback.
- (NSString *)displayTitleForTile:(HomeTileConfig *)tile;
- (NSString *)displayDetailForTile:(HomeTileConfig *)tile;
@end

@implementation CustomizeTileCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        self.backgroundColor = [UIColor clearColor];
        self.contentView.backgroundColor = [UIColor clearColor];
        self.selectionStyle = UITableViewCellSelectionStyleNone;
        
        // Accent strip on the left.
        self.accentStrip = [[UIView alloc] init];
        self.accentStrip.translatesAutoresizingMaskIntoConstraints = NO;
        self.accentStrip.layer.cornerRadius = 2;
        self.accentStrip.layer.cornerCurve = kCACornerCurveContinuous;   // ★ [CORNER-FIX] Continuous corners (match system cards).
        [self.contentView addSubview:self.accentStrip];
        
        // Icon.
        self.tileIconView = [[UIImageView alloc] init];
        self.tileIconView.translatesAutoresizingMaskIntoConstraints = NO;
        self.tileIconView.contentMode = UIViewContentModeScaleAspectFit;
        self.tileIconView.tintColor = [UIColor labelColor];
        [self.contentView addSubview:self.tileIconView];
        
        // Title.
        self.tileTitleLabel = [[UILabel alloc] init];
        self.tileTitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        self.tileTitleLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
        self.tileTitleLabel.textColor = [UIColor labelColor];
        [self.contentView addSubview:self.tileTitleLabel];
        
        // Details (type + size).
        self.tileDetailLabel = [[UILabel alloc] init];
        self.tileDetailLabel.translatesAutoresizingMaskIntoConstraints = NO;
        self.tileDetailLabel.font = [UIFont systemFontOfSize:11 weight:UIFontWeightMedium];
        self.tileDetailLabel.textColor = [UIColor tertiaryLabelColor];
        [self.contentView addSubview:self.tileDetailLabel];
        
        // Size label.
        self.sizeLabel = [[UILabel alloc] init];
        self.sizeLabel.translatesAutoresizingMaskIntoConstraints = NO;
        self.sizeLabel.font = [UIFont systemFontOfSize:10 weight:UIFontWeightBold];
        self.sizeLabel.textColor = [UIColor secondaryLabelColor];
        self.sizeLabel.textAlignment = NSTextAlignmentCenter;
        self.sizeLabel.layer.cornerRadius = 4;
        self.sizeLabel.layer.cornerCurve = kCACornerCurveContinuous;   // ★ [CORNER-FIX] Continuous corners (match system cards).
        self.sizeLabel.layer.masksToBounds = YES;
        self.sizeLabel.backgroundColor = [UIColor colorWithWhite:0.2 alpha:0.5];
        [self.contentView addSubview:self.sizeLabel];
        
        // Visibility switch.
        self.visibilitySwitch = [[UISwitch alloc] init];
        self.visibilitySwitch.translatesAutoresizingMaskIntoConstraints = NO;
        self.visibilitySwitch.transform = CGAffineTransformMakeScale(0.7, 0.7);
        self.visibilitySwitch.onTintColor = hexColor(@"#8B5CF6");
        [self.contentView addSubview:self.visibilitySwitch];

        // ★ [SIZE4] Four-option size segmented control (1×1 / 2×1 / 1×2 / 2×2); each card is selected independently.
        self.sizeSegmented = [[UISegmentedControl alloc] initWithItems:@[
            AmeTileSizeShortName(HomeTileSizeSmall),
            AmeTileSizeShortName(HomeTileSizeWide),
            AmeTileSizeShortName(HomeTileSizeTall),
            AmeTileSizeShortName(HomeTileSizeLarge),
        ]];
        self.sizeSegmented.translatesAutoresizingMaskIntoConstraints = NO;
        self.sizeSegmented.selectedSegmentIndex = 0;
        if (@available(iOS 13.0, *)) { self.sizeSegmented.selectedSegmentTintColor = hexColor(@"#8B5CF6"); }
        self.sizeSegmented.tintColor = [UIColor labelColor];
        [self.sizeSegmented addTarget:self action:@selector(sizeSegmentChanged:)
                     forControlEvents:UIControlEventValueChanged];
        [self.contentView addSubview:self.sizeSegmented];
        
        [NSLayoutConstraint activateConstraints:@[
            [self.accentStrip.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:16],
            [self.accentStrip.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:12],
            [self.accentStrip.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-12],
            [self.accentStrip.widthAnchor constraintEqualToConstant:4],
            
            [self.tileIconView.leadingAnchor constraintEqualToAnchor:self.accentStrip.trailingAnchor constant:12],
            [self.tileIconView.centerYAnchor constraintEqualToAnchor:self.tileTitleLabel.centerYAnchor],
            [self.tileIconView.widthAnchor constraintEqualToConstant:26],
            [self.tileIconView.heightAnchor constraintEqualToConstant:26],
            
            [self.tileTitleLabel.leadingAnchor constraintEqualToAnchor:self.tileIconView.trailingAnchor constant:12],
            [self.tileTitleLabel.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:16],
            [self.tileTitleLabel.trailingAnchor constraintEqualToAnchor:self.sizeLabel.leadingAnchor constant:-8],
            
            [self.tileDetailLabel.leadingAnchor constraintEqualToAnchor:self.tileTitleLabel.leadingAnchor],
            [self.tileDetailLabel.topAnchor constraintEqualToAnchor:self.tileTitleLabel.bottomAnchor constant:2],
            [self.tileDetailLabel.trailingAnchor constraintEqualToAnchor:self.tileTitleLabel.trailingAnchor],
            
            [self.sizeLabel.centerYAnchor constraintEqualToAnchor:self.tileTitleLabel.centerYAnchor],
            [self.sizeLabel.widthAnchor constraintEqualToConstant:40],
            [self.sizeLabel.heightAnchor constraintEqualToConstant:18],
            [self.sizeLabel.trailingAnchor constraintEqualToAnchor:self.visibilitySwitch.leadingAnchor constant:-6],
            
            [self.visibilitySwitch.centerYAnchor constraintEqualToAnchor:self.tileTitleLabel.centerYAnchor],
            [self.visibilitySwitch.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-28],

            // ★ [SIZE4] Segmented control: fill the title column width, below the details (use constraints
            // rather than a fixed frame, adapting to row height).
            [self.sizeSegmented.leadingAnchor constraintEqualToAnchor:self.tileTitleLabel.leadingAnchor],
            [self.sizeSegmented.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-28],
            [self.sizeSegmented.topAnchor constraintEqualToAnchor:self.tileDetailLabel.bottomAnchor constant:8],
            [self.sizeSegmented.heightAnchor constraintEqualToConstant:28],
        ]];
        
        [[BackgroundManager sharedManager] applyEffectToView:self.contentView];
    }
    return self;
}

- (void)configureWithTile:(HomeTileConfig *)tile {
    self.tile = tile;   // ★ [SIZE4] Remember the owning card; the segmented control changes its tileSize directly.
    self.tileTitleLabel.text = [self displayTitleForTile:tile];
    self.tileDetailLabel.text = [self displayDetailForTile:tile];
    self.tileIconView.image = [UIImage systemImageNamed:tile.iconName ?: @"square.grid.2x2"];
    self.tileIconView.tintColor = [tile accentColor];
    self.accentStrip.backgroundColor = [tile accentColor];
    self.visibilitySwitch.on = tile.visible;
    // ★ [SIZE4] Use geometric names (1×1/2×1/1×2/2×2) for badges so all four options fit; restore
    // the selected state to the segmented control.
    self.sizeLabel.text = AmeTileSizeShortName(tile.tileSize);
    self.sizeSegmented.selectedSegmentIndex = AmeSegmentIndexForTileSize(tile.tileSize);
    
    CGFloat alpha = tile.visible ? 1.0 : 0.45;
    self.tileTitleLabel.alpha = alpha;
    self.tileIconView.alpha = alpha;
    self.tileDetailLabel.alpha = alpha;
}

/// ★ [SIZE4] Segmented-control callback: switch this card directly to the selected size (independent
/// of other cards), then refresh this row's text.
- (void)sizeSegmentChanged:(UISegmentedControl *)sender {
    HomeTileSize size = AmeTileSizeForSegmentIndex(sender.selectedSegmentIndex);
    self.tile.tileSize = size;
    self.sizeLabel.text = AmeTileSizeShortName(size);
    self.tileDetailLabel.text = [self displayDetailForTile:self.tile];
}

- (NSString *)displayTitleForTile:(HomeTileConfig *)tile {
    if (tile.customTitle.length > 0) return tile.customTitle;
    switch (tile.tileType) {
        case HomeTileTypeProfile:        return localize(@"i18n_str_282", nil);
        case HomeTileTypeAnnouncement:   return localize(@"i18n_str_20", nil);
        case HomeTileTypeVersionRelease: return localize(@"i18n_str_283", nil);
        case HomeTileTypeVersionSnapshot:return localize(@"i18n_str_284", nil);
        case HomeTileTypeNews:           return localize(@"i18n_str_285", nil);
        case HomeTileTypeShortcut:       return tile.shortcutAction ?: localize(@"i18n_str_286", nil);
        default:                         return localize(@"i18n_str_287", nil);
    }
}

- (NSString *)displayDetailForTile:(HomeTileConfig *)tile {
    NSString *type;
    switch (tile.tileType) {
        case HomeTileTypeProfile:        type = localize(@"i18n_str_288", nil); break;
        case HomeTileTypeAnnouncement:   type = localize(@"i18n_str_20", nil); break;
        case HomeTileTypeVersionRelease: type = localize(@"i18n_str_289", nil); break;
        case HomeTileTypeVersionSnapshot:type = localize(@"i18n_str_289", nil); break;
        case HomeTileTypeNews:           type = localize(@"i18n_str_290", nil); break;
        case HomeTileTypeShortcut:       type = localize(@"i18n_str_286", nil); break;
        default:                         type = localize(@"i18n_str_121", nil); break;
    }
    // ★ [SIZE4] Localized names for the four options (reuse old keys 2018/281; Tall/Large use new
    // keys 9101/9102).
    NSString *size = AmeTileSizeDisplayName(tile.tileSize);
    return [NSString stringWithFormat:@"%@ · %@", type, size];
}

@end

// MARK: - HomeCustomizeViewController

@interface HomeCustomizeViewController () <UITableViewDataSource, UITableViewDelegate>

@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) NSMutableArray<HomeTileConfig *> *editingConfigs;

@end

@implementation HomeCustomizeViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    
    self.title = localize(@"i18n_str_292", nil);
    self.editingConfigs = [self.tileConfigs mutableCopy];
    
    // Navigation-bar buttons.
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:localize(@"resman.common.cancel", nil)
                                                                            style:UIBarButtonItemStylePlain
                                                                           target:self
                                                                           action:@selector(cancelTapped)];
    
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:localize(@"i18n_str_88", nil)
                                                                             style:UIBarButtonItemStyleDone
                                                                            target:self
                                                                            action:@selector(saveTapped)];
    
    // Toolbar buttons.
    UIBarButtonItem *addBtn = [[UIBarButtonItem alloc] initWithTitle:localize(@"i18n_str_293", nil)
                                                              style:UIBarButtonItemStylePlain
                                                             target:self
                                                             action:@selector(addShortcutTapped)];
    UIBarButtonItem *resetBtn = [[UIBarButtonItem alloc] initWithTitle:localize(@"i18n_str_294", nil)
                                                                style:UIBarButtonItemStylePlain
                                                               target:self
                                                               action:@selector(resetTapped)];
    resetBtn.tintColor = [UIColor systemRedColor];
    UIBarButtonItem *flex = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:nil action:nil];
    
    self.toolbarItems = @[addBtn, flex, resetBtn];
    self.navigationController.toolbarHidden = NO;
    
    // Background.
    if ([[BackgroundManager sharedManager] hasBackground]) {
        self.view.backgroundColor = [UIColor clearColor];
    } else {
        self.view.backgroundColor = [UIColor systemGroupedBackgroundColor];
    }
    
    [self setupTableView];

    // Adapt to the custom launcher background: make this view controller transparent so the global
    // background (image/video) shows through.
    // This controller is a UIViewController subclass (not UITableViewController) and creates its
    // tableView manually; makeViewControllerTransparent clears the view background, and setupTableView
    // already clears the tableView background.
    [[BackgroundManager sharedManager] makeViewControllerTransparent:self];

    // Listen for background UI-effect changes: when the user switches frosted glass/translucent or
    // adjusts opacity in Background Settings, call makeViewControllerTransparent again to apply the
    // latest appearance and keep the background showing through correctly.
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(reapplyBackgroundEffect)
                                                 name:@"BackgroundUIEffectChanged"
                                               object:nil];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(handleBackgroundUIEffectChanged:)
                                                 name:@"BackgroundUIEffectChanged"
                                               object:nil];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self name:@"BackgroundUIEffectChanged" object:nil];
}

- (void)setupTableView {
    self.tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    self.tableView.translatesAutoresizingMaskIntoConstraints = NO;
    self.tableView.backgroundColor = [UIColor clearColor];
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    self.tableView.rowHeight = 100;   // ★ [SIZE4] 68 → 100: make room for the four-option size segmented control.
    self.tableView.editing = YES;  // Always use editing mode to support dragging.
    self.tableView.allowsSelectionDuringEditing = YES;
    self.tableView.showsVerticalScrollIndicator = NO;
    self.tableView.contentInset = UIEdgeInsetsMake(8, 0, 20, 0);
    
    [self.tableView registerClass:[CustomizeTileCell class] forCellReuseIdentifier:@"TileCell"];
    
    [self.view addSubview:self.tableView];
    
    [NSLayoutConstraint activateConstraints:@[
        [self.tableView.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [self.tableView.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor],
        [self.tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
    ]];
}

// MARK: - Navigation Actions

- (void)cancelTapped {
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)saveTapped {
    if (self.onConfigsChanged) {
        self.onConfigsChanged([self.editingConfigs copy]);
    }
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)resetTapped {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:localize(@"i18n_str_295", nil)
                                                                   message:localize(@"i18n_str_296", nil)
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:localize(@"resman.common.cancel", nil) style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:localize(@"i18n_str_297", nil) style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
        self.editingConfigs = [[HomeTileConfig defaultTileConfigs] mutableCopy];
        [self.tableView reloadData];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)addShortcutTapped {
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:localize(@"i18n_str_293", nil)
                                                                   message:localize(@"i18n_str_298", nil)
                                                            preferredStyle:UIAlertControllerStyleActionSheet];
    
    NSDictionary *shortcuts = availableShortcuts();
    for (NSString *key in shortcuts) {
        NSDictionary *info = shortcuts[key];
        
        // Check whether it already exists.
        BOOL exists = NO;
        for (HomeTileConfig *c in self.editingConfigs) {
            if ([c.shortcutAction isEqualToString:key]) {
                exists = YES;
                break;
            }
        }
        if (exists) continue;
        
        [sheet addAction:[UIAlertAction actionWithTitle:info[@"title"] style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            HomeTileConfig *newTile = [[HomeTileConfig alloc] init];
            newTile.tileId = [NSString stringWithFormat:@"shortcut_%@_%@", key, [[NSUUID UUID] UUIDString]];
            newTile.tileType = HomeTileTypeShortcut;
            newTile.tileSize = HomeTileSizeCompact;   // ★ [SIZE4] == HomeTileSizeSmall (legacy alias, default 1×1).
            newTile.visible = YES;
            newTile.customTitle = info[@"title"];
            newTile.iconName = info[@"icon"];
            newTile.shortcutAction = key;
            newTile.accentColorHex = info[@"color"];
            
            [self.editingConfigs addObject:newTile];
            [self.tableView insertRowsAtIndexPaths:@[[NSIndexPath indexPathForRow:self.editingConfigs.count - 1 inSection:0]]
                                  withRowAnimation:UITableViewRowAnimationAutomatic];
        }]];
    }
    
    [sheet addAction:[UIAlertAction actionWithTitle:localize(@"resman.common.cancel", nil) style:UIAlertActionStyleCancel handler:nil]];
    
    // iPad popover support
    sheet.popoverPresentationController.barButtonItem = self.toolbarItems.firstObject;
    
    [self presentViewController:sheet animated:YES completion:nil];
}

// MARK: - UITableView DataSource

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.editingConfigs.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    CustomizeTileCell *cell = [tableView dequeueReusableCellWithIdentifier:@"TileCell" forIndexPath:indexPath];
    HomeTileConfig *config = self.editingConfigs[indexPath.row];
    [cell configureWithTile:config];
    
    // Bind the switch event.
    [cell.visibilitySwitch removeTarget:nil action:nil forControlEvents:UIControlEventValueChanged];
    cell.visibilitySwitch.tag = indexPath.row;
    [cell.visibilitySwitch addTarget:self action:@selector(visibilitySwitchChanged:) forControlEvents:UIControlEventValueChanged];
    
    return cell;
}

// MARK: - UITableView Delegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    
    HomeTileConfig *config = self.editingConfigs[indexPath.row];
    [self showEditOptionsForTile:config atIndex:indexPath.row];
}

// Drag to reorder.
- (BOOL)tableView:(UITableView *)tableView canMoveRowAtIndexPath:(NSIndexPath *)indexPath {
    return YES;
}

- (void)tableView:(UITableView *)tableView moveRowAtIndexPath:(NSIndexPath *)sourceIndexPath toIndexPath:(NSIndexPath *)destinationIndexPath {
    HomeTileConfig *tile = self.editingConfigs[sourceIndexPath.row];
    [self.editingConfigs removeObjectAtIndex:sourceIndexPath.row];
    [self.editingConfigs insertObject:tile atIndex:destinationIndexPath.row];
}

// Delete (only shortcuts can be deleted).
- (UITableViewCellEditingStyle)tableView:(UITableView *)tableView editingStyleForRowAtIndexPath:(NSIndexPath *)indexPath {
    HomeTileConfig *config = self.editingConfigs[indexPath.row];
    return config.tileType == HomeTileTypeShortcut ? UITableViewCellEditingStyleDelete : UITableViewCellEditingStyleNone;
}

- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath *)indexPath {
    if (editingStyle == UITableViewCellEditingStyleDelete) {
        [self.editingConfigs removeObjectAtIndex:indexPath.row];
        [tableView deleteRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationFade];
    }
}

- (BOOL)tableView:(UITableView *)tableView shouldIndentWhileEditingRowAtIndexPath:(NSIndexPath *)indexPath {
    return NO;
}

// MARK: - Edit Tile Options

- (void)showEditOptionsForTile:(HomeTileConfig *)tile atIndex:(NSInteger)index {
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:localize(@"i18n_str_299", nil)
                                                                   message:nil
                                                            preferredStyle:UIAlertControllerStyleActionSheet];
    
    // ★ [SIZE4] Choose one of four sizes (previously a one-tap "Compact ⇄ Full" switch); prefix
    // the current option with ✓.
    for (NSNumber *sizeNum in @[@(HomeTileSizeSmall), @(HomeTileSizeWide),
                                @(HomeTileSizeTall),  @(HomeTileSizeLarge)]) {
        HomeTileSize size = (HomeTileSize)sizeNum.integerValue;
        NSString *sizeTitle = [NSString stringWithFormat:@"%@ %@ · %@",
                               (tile.tileSize == size ? @"✓" : @" "),
                               AmeTileSizeShortName(size),
                               AmeTileSizeDisplayName(size)];
        [sheet addAction:[UIAlertAction actionWithTitle:sizeTitle style:UIAlertActionStyleDefault
                                                handler:^(UIAlertAction *action) {
            tile.tileSize = size;
            [self.tableView reloadRowsAtIndexPaths:@[[NSIndexPath indexPathForRow:index inSection:0]]
                                  withRowAnimation:UITableViewRowAnimationAutomatic];
        }]];
    }
    
    // Edit title (only shortcuts and some tiles).
    if (tile.tileType == HomeTileTypeShortcut || tile.tileType == HomeTileTypeVersionRelease || tile.tileType == HomeTileTypeVersionSnapshot) {
        [sheet addAction:[UIAlertAction actionWithTitle:localize(@"i18n_str_302", nil) style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            [self showEditTitleForTile:tile atIndex:index];
        }]];
    }
    
    // Edit color.
    [sheet addAction:[UIAlertAction actionWithTitle:localize(@"i18n_str_303", nil) style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        [self showColorPickerForTile:tile atIndex:index];
    }]];
    
    // Toggle visibility.
    NSString *visTitle = tile.visible ? localize(@"i18n_str_2021", nil) : localize(@"i18n_str_305", nil);
    [sheet addAction:[UIAlertAction actionWithTitle:visTitle style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        tile.visible = !tile.visible;
        [self.tableView reloadRowsAtIndexPaths:@[[NSIndexPath indexPathForRow:index inSection:0]]
                              withRowAnimation:UITableViewRowAnimationAutomatic];
    }]];
    
    // Delete (shortcuts only).
    if (tile.tileType == HomeTileTypeShortcut) {
        [sheet addAction:[UIAlertAction actionWithTitle:localize(@"i18n_str_306", nil) style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
            [self.editingConfigs removeObjectAtIndex:index];
            [self.tableView deleteRowsAtIndexPaths:@[[NSIndexPath indexPathForRow:index inSection:0]]
                                  withRowAnimation:UITableViewRowAnimationFade];
        }]];
    }
    
    [sheet addAction:[UIAlertAction actionWithTitle:localize(@"resman.common.cancel", nil) style:UIAlertActionStyleCancel handler:nil]];
    
    // iPad popover
    sheet.popoverPresentationController.sourceView = [self.tableView cellForRowAtIndexPath:[NSIndexPath indexPathForRow:index inSection:0]];
    sheet.popoverPresentationController.sourceRect = sheet.popoverPresentationController.sourceView.bounds;
    
    [self presentViewController:sheet animated:YES completion:nil];
}

- (void)showEditTitleForTile:(HomeTileConfig *)tile atIndex:(NSInteger)index {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:localize(@"i18n_str_302", nil)
                                                                   message:localize(@"i18n_str_307", nil)
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *tf) {
        tf.text = tile.customTitle;
        tf.placeholder = localize(@"i18n_str_308", nil);
        tf.clearButtonMode = UITextFieldViewModeWhileEditing;
    }];
    
    [alert addAction:[UIAlertAction actionWithTitle:localize(@"resman.common.cancel", nil) style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:localize(@"i18n_str_44", nil) style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        NSString *newTitle = alert.textFields.firstObject.text;
        if (newTitle.length > 0) {
            tile.customTitle = newTitle;
            [self.tableView reloadRowsAtIndexPaths:@[[NSIndexPath indexPathForRow:index inSection:0]]
                                  withRowAnimation:UITableViewRowAnimationAutomatic];
        }
    }]];
    
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)showColorPickerForTile:(HomeTileConfig *)tile atIndex:(NSInteger)index {
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:localize(@"i18n_str_309", nil)
                                                                   message:nil
                                                            preferredStyle:UIAlertControllerStyleActionSheet];
    
    NSDictionary *colors = @{
        localize(@"i18n_str_2022", nil):   @"#8B5CF6",
        localize(@"i18n_str_2062", nil):   @"#3B82F6",
        localize(@"i18n_str_2063", nil):   @"#14B8A6",
        localize(@"i18n_str_2065", nil):   @"#10B981",
        localize(@"i18n_str_2066", nil):   @"#F59E0B",
        localize(@"i18n_str_2067", nil):   @"#F97316",
        localize(@"i18n_str_2023", nil):   @"#EF4444",
        localize(@"i18n_str_2024", nil):   @"#EC4899",
        localize(@"i18n_str_2025", nil):   @"#6366F1",
    };
    
    for (NSString *name in @[localize(@"i18n_str_2022", nil), localize(@"i18n_str_2062", nil), localize(@"i18n_str_2063", nil), localize(@"i18n_str_2065", nil), localize(@"i18n_str_2066", nil), localize(@"i18n_str_2067", nil), localize(@"i18n_str_2023", nil), localize(@"i18n_str_2024", nil), localize(@"i18n_str_2025", nil)]) {
        NSString *hex = colors[name];
        [sheet addAction:[UIAlertAction actionWithTitle:name style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            tile.accentColorHex = hex;
            [self.tableView reloadRowsAtIndexPaths:@[[NSIndexPath indexPathForRow:index inSection:0]]
                                  withRowAnimation:UITableViewRowAnimationAutomatic];
        }]];
    }
    
    [sheet addAction:[UIAlertAction actionWithTitle:localize(@"resman.common.cancel", nil) style:UIAlertActionStyleCancel handler:nil]];
    
    sheet.popoverPresentationController.sourceView = [self.tableView cellForRowAtIndexPath:[NSIndexPath indexPathForRow:index inSection:0]];
    sheet.popoverPresentationController.sourceRect = sheet.popoverPresentationController.sourceView.bounds;
    
    [self presentViewController:sheet animated:YES completion:nil];
}

// MARK: - Switch Actions

- (void)visibilitySwitchChanged:(UISwitch *)sender {
    NSInteger index = sender.tag;
    if (index < self.editingConfigs.count) {
        self.editingConfigs[index].visible = sender.on;
        [self.tableView reloadRowsAtIndexPaths:@[[NSIndexPath indexPathForRow:index inSection:0]]
                              withRowAnimation:UITableViewRowAnimationAutomatic];
    }
}

// MARK: - Orientation

- (BOOL)shouldAutorotate {
    return YES;
}

- (UIInterfaceOrientationMask)supportedInterfaceOrientations {
    // ★ [PORTRAIT-UNLOCK] Allow portrait: this was hard-coded to Landscape, preventing access in
    //   portrait on iPhone (Home is this VC, so it locked the entire app to landscape). The game page
    //   still locks itself to landscape separately.
    if (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad) { return UIInterfaceOrientationMaskAll; }
    return UIInterfaceOrientationMaskAllButUpsideDown;
}

- (void)handleBackgroundUIEffectChanged:(NSNotification *)notification {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.tableView reloadData];
    });
}

/// Reapply the background effect when the BackgroundUIEffectChanged notification arrives:
/// use BackgroundManager to reset this view controller's opacity/frosted-glass effect and manually
/// clear the tableView background color so the global background can show through correctly.
- (void)reapplyBackgroundEffect {
    [[BackgroundManager sharedManager] makeViewControllerTransparent:self];
    self.tableView.backgroundColor = [UIColor clearColor];
}

@end
