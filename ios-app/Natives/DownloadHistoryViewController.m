#import "utils.h"
#import "DownloadHistoryViewController.h"
#import "DownloadHistoryStore.h"
#import "DownloadTaskItem.h"
#import "BackgroundManager.h"

static NSString * const kHistoryCellReuseIdentifier = @"DownloadHistoryCell";

/// History-entry cell: name + type/size/result subtitle + time (on the right).
@interface DownloadHistoryEntryCell : UITableViewCell

@property (nonatomic, strong) UILabel *nameLabel;
@property (nonatomic, strong) UILabel *detailLabel;
@property (nonatomic, strong) UILabel *timeLabel;

- (void)configureWithEntry:(NSDictionary *)entry typeDisplayName:(NSString *)typeDisplayName;

@end

@implementation DownloadHistoryEntryCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        self.backgroundColor = [UIColor secondarySystemBackgroundColor];
        self.layer.cornerRadius = 12.0;
        self.layer.cornerCurve = kCACornerCurveContinuous;   // ★ [CORNER-FIX] Continuous corners (match system cards).
        self.layer.masksToBounds = YES;

        self.nameLabel = [[UILabel alloc] init];
        self.nameLabel.translatesAutoresizingMaskIntoConstraints = NO;
        self.nameLabel.font = [UIFont boldSystemFontOfSize:15];
        self.nameLabel.textColor = [UIColor labelColor];
        self.nameLabel.numberOfLines = 1;
        self.nameLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;
        [self.contentView addSubview:self.nameLabel];

        self.detailLabel = [[UILabel alloc] init];
        self.detailLabel.translatesAutoresizingMaskIntoConstraints = NO;
        self.detailLabel.font = [UIFont systemFontOfSize:12];
        self.detailLabel.textColor = [UIColor secondaryLabelColor];
        self.detailLabel.numberOfLines = 1;
        [self.contentView addSubview:self.detailLabel];

        self.timeLabel = [[UILabel alloc] init];
        self.timeLabel.translatesAutoresizingMaskIntoConstraints = NO;
        self.timeLabel.font = [UIFont monospacedDigitSystemFontOfSize:11 weight:UIFontWeightRegular];
        self.timeLabel.textColor = [UIColor tertiaryLabelColor];
        self.timeLabel.textAlignment = NSTextAlignmentRight;
        self.timeLabel.numberOfLines = 2;
        [self.contentView addSubview:self.timeLabel];

        [NSLayoutConstraint activateConstraints:@[
            [self.nameLabel.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:10],
            [self.nameLabel.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:14],
            [self.nameLabel.trailingAnchor constraintLessThanOrEqualToAnchor:self.timeLabel.leadingAnchor constant:-8],

            [self.detailLabel.topAnchor constraintEqualToAnchor:self.nameLabel.bottomAnchor constant:3],
            [self.detailLabel.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:14],
            [self.detailLabel.trailingAnchor constraintLessThanOrEqualToAnchor:self.timeLabel.leadingAnchor constant:-8],
            [self.detailLabel.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-10],

            [self.timeLabel.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
            [self.timeLabel.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-14],
            [self.timeLabel.widthAnchor constraintLessThanOrEqualToConstant:110],
        ]];
    }
    return self;
}

- (void)prepareForReuse {
    [super prepareForReuse];
    self.nameLabel.text = nil;
    self.detailLabel.text = nil;
    self.timeLabel.text = nil;
}

- (void)configureWithEntry:(NSDictionary *)entry typeDisplayName:(NSString *)typeDisplayName {
    NSString *name = [entry[@"name"] isKindOfClass:[NSString class]] ? entry[@"name"] : @"";
    self.nameLabel.text = name.length > 0 ? name : localize(@"i18n_str_107", nil);

    // Size (the recorded value is the task's total size).
    long long size = [entry[@"size"] longLongValue];
    NSString *sizeText = size > 0 ? [NSByteCountFormatter stringFromByteCount:size
                                                                  countStyle:NSByteCountFormatterCountStyleFile]
                                  : @"--";

    // Result (currently, history records only successful entries).
    NSString *resultRaw = [entry[@"result"] isKindOfClass:[NSString class]] ? entry[@"result"] : @"success";
    NSString *resultText = [resultRaw isEqualToString:@"success"]
        // ★ [I18N-ORDER] Use the shared localize() entry point instead of bypassing language resolution.
        ? localize(@"download.history.result.success", @"Success")
        // ★ [I18N-ORDER] Use the shared localize() entry point instead of bypassing language resolution.
        : localize(@"download.history.result.failed", @"Failed");

    self.detailLabel.text = [NSString stringWithFormat:@"%@ · %@ · %@",
                             typeDisplayName ?: @"--", sizeText, resultText];

    // Time (on the right, two lines: date + time).
    NSTimeInterval timestamp = [entry[@"time"] doubleValue];
    if (timestamp > 0) {
        NSDate *date = [NSDate dateWithTimeIntervalSince1970:timestamp];
        static NSDateFormatter *dateFormatter = nil;
        static NSDateFormatter *timeFormatter = nil;
        static dispatch_once_t onceToken;
        dispatch_once(&onceToken, ^{
            dateFormatter = [[NSDateFormatter alloc] init];
            dateFormatter.dateStyle = NSDateFormatterMediumStyle;
            dateFormatter.timeStyle = NSDateFormatterNoStyle;
            timeFormatter = [[NSDateFormatter alloc] init];
            timeFormatter.dateStyle = NSDateFormatterNoStyle;
            timeFormatter.timeStyle = NSDateFormatterShortStyle;
        });
        self.timeLabel.text = [NSString stringWithFormat:@"%@\n%@",
                               [dateFormatter stringFromDate:date],
                               [timeFormatter stringFromDate:date]];
    } else {
        self.timeLabel.text = @"";
    }
}

@end

#pragma mark - Controller

@interface DownloadHistoryViewController ()

@property (nonatomic, copy) NSArray<NSDictionary *> *entries;
@property (nonatomic, strong) UILabel *emptyLabel;

@end

@implementation DownloadHistoryViewController

- (instancetype)init {
    self = [super initWithStyle:UITableViewStyleInsetGrouped];
    if (self) {
        self.entries = @[];
    }
    return self;
}

// Always use the InsetGrouped card style; ignore the externally supplied style.
- (instancetype)initWithStyle:(UITableViewStyle)style {
    return [self init];
}

- (instancetype)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil {
    return [self init];
}

- (nullable instancetype)initWithCoder:(NSCoder *)coder {
    self = [super initWithStyle:UITableViewStyleInsetGrouped];
    if (self) {
        self.entries = @[];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    // Adapt to the custom launcher background: make this view controller transparent so the global
    // wallpaper shows through (matching the Download Center).
    // ★ [PAGE-GLASS] Correct the order: transparency must be applied **last**. Previously it was
    //   applied first, then systemBackgroundColor (opaque) was assigned, covering the transparent
    //   background ⇒ on iOS≥26 there was no system Liquid Glass and the wallpaper did not show through.
    self.view.backgroundColor = [UIColor systemBackgroundColor];
    [[BackgroundManager sharedManager] makeViewControllerTransparent:self];

    // ★ [I18N-ORDER] Use the shared localize() entry point instead of bypassing language resolution.
    self.title = localize(@"download.history.title", @"Download History");

    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc]
        // ★ [I18N-ORDER] Use the shared localize() entry point instead of bypassing language resolution.
        initWithTitle:localize(@"download.history.clear", @"Clear")
        style:UIBarButtonItemStylePlain
        target:self
        action:@selector(clearTapped:)];

    [self reloadEntries];
}

- (void)reloadEntries {
    self.entries = [[DownloadHistoryStore sharedStore] allEntries] ?: @[];
    [self.tableView reloadData];
    [self updateEmptyState];
}

/// Empty-state placeholder text (no pull-to-refresh; read once when entering the page).
- (void)updateEmptyState {
    if (self.entries.count > 0) {
        [self.emptyLabel removeFromSuperview];
        self.emptyLabel = nil;
        self.tableView.tableHeaderView = nil;
        return;
    }

    // ★ [HOST-BUG-B] Why the empty-history text was clipped to "No hist":
    //   header was created with CGRectMake(0, 0, 0, 240) (width=0), then the label frame was set to
    //   header.bounds.size.width - 48 ⇒ label width = -48 and only the first few characters showed.
    //   Instead, constrain the label to both sides of the header with 24pt margins using Auto Layout.
    //   UITableView assigns the header width when setting tableHeaderView ⇒ the label always wraps
    //   to the actual width and displays in full.
    //   Recreate the label each time to avoid adding constraints repeatedly to a reused instance.
    self.emptyLabel = [[UILabel alloc] init];
    self.emptyLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.emptyLabel.font = [UIFont systemFontOfSize:16];
    self.emptyLabel.textColor = [UIColor secondaryLabelColor];
    self.emptyLabel.textAlignment = NSTextAlignmentCenter;
    self.emptyLabel.numberOfLines = 0;
    // ★ [I18N-ORDER] Use the shared localize() entry point instead of bypassing language resolution.
    self.emptyLabel.text = localize(@"download.history.empty", @"No download history");

    // Host the centered empty state in tableHeaderView so it does not cover the navigation bar.
    UIView *header = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 1, 240)];
    [header addSubview:self.emptyLabel];
    [NSLayoutConstraint activateConstraints:@[
        [self.emptyLabel.leadingAnchor  constraintEqualToAnchor:header.leadingAnchor  constant:24],
        [self.emptyLabel.trailingAnchor constraintEqualToAnchor:header.trailingAnchor constant:-24],
        [self.emptyLabel.topAnchor      constraintEqualToAnchor:header.topAnchor      constant:60],
    ]];
    self.tableView.tableHeaderView = header;
}

#pragma mark - Actions

- (void)clearTapped:(UIBarButtonItem *)sender {
    if (self.entries.count == 0) return;

    UIAlertController *alert = [UIAlertController
        // ★ [I18N-ORDER] Use the shared localize() entry point instead of bypassing language resolution.
        alertControllerWithTitle:localize(@"download.history.title", @"Download History")
                         // ★ [I18N-ORDER] Use the shared localize() entry point instead of bypassing language resolution.
                         message:localize(@"download.history.clear_confirm", @"Are you sure you want to clear all download history? This action cannot be undone.")
                  preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction
        // ★ [I18N-ORDER] Use the shared localize() entry point instead of bypassing language resolution.
        actionWithTitle:localize(@"download.history.clear", @"Clear")
                  style:UIAlertActionStyleDestructive
                handler:^(UIAlertAction *action) {
        [[DownloadHistoryStore sharedStore] clearAll];
        [self reloadEntries];
    }]];
    [alert addAction:[UIAlertAction
        // ★ [I18N-ORDER] Use the shared localize() entry point (do not bypass language resolution).
        actionWithTitle:localize(@"download.history.cancel", @"Cancel")
                  style:UIAlertActionStyleCancel
                handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

#pragma mark - UITableViewDataSource

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.entries.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    DownloadHistoryEntryCell *cell = [tableView dequeueReusableCellWithIdentifier:kHistoryCellReuseIdentifier];
    if (!cell) {
        cell = [[DownloadHistoryEntryCell alloc] initWithStyle:UITableViewCellStyleDefault
                                               reuseIdentifier:kHistoryCellReuseIdentifier];
    }
    NSDictionary *entry = self.entries[indexPath.row];
    NSString *type = [entry[@"type"] isKindOfClass:[NSString class]] ? entry[@"type"] : @"";
    [cell configureWithEntry:entry typeDisplayName:[self displayNameForResourceType:type]];
    return cell;
}

#pragma mark - UITableViewDelegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    return 60.0;
}

#pragma mark - Utility methods

/// Resource-type display name (keep mappings consistent with DownloadTasksViewController).
- (NSString *)displayNameForResourceType:(NSString *)type {
    NSDictionary *map = @{
        DownloadTaskResourceTypeMinecraft: localize(@"i18n_str_113", nil),
        DownloadTaskResourceTypeModloader: localize(@"i18n_str_114", nil),
        DownloadTaskResourceTypeMod: @"Mod",
        DownloadTaskResourceTypeShader: localize(@"i18n_str_115", nil),
        DownloadTaskResourceTypeResourcePack: localize(@"i18n_str_116", nil),
        DownloadTaskResourceTypeDataPack: localize(@"i18n_str_117", nil),
        DownloadTaskResourceTypeModpack: localize(@"i18n_str_118", nil),
        DownloadTaskResourceTypeWorld: localize(@"i18n_str_119", nil),
        DownloadTaskResourceTypeJavaRuntime: localize(@"i18n_str_120", nil)
    };
    return map[type] ?: (type.length > 0 ? type : localize(@"i18n_str_121", nil));
}

@end
