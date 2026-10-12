#import <UIKit/UIKit.h>
#import "DownloadTaskItem.h"

NS_ASSUME_NONNULL_BEGIN

/**
 * Full-screen download-task management page.
 * Centrally displays all download tasks registered with DownloadTaskManager.
 * Supports two-level filtering by download state and resource type, as well as pausing/resuming/
 * cancelling/switching sources and other operations.
 */
@interface DownloadTasksViewController : UIViewController

/// Download-state filter selected by default on entry (DownloadTaskStatePending means all by default).
@property (nonatomic, assign) DownloadTaskState filterState;

/// Resource-type filter selected by default on entry (nil means all).
@property (nonatomic, copy, nullable) NSString *filterType;

@end

NS_ASSUME_NONNULL_END
