#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/**
 * Download history screen (spec Phase 6 Task 6.2).
 * Data source: [DownloadHistoryStore sharedStore].allEntries (newest → oldest).
 * Displays name/type/size/time/result and supports clearing all at once (with a confirmation dialog).
 */
@interface DownloadHistoryViewController : UITableViewController

@end

NS_ASSUME_NONNULL_END
