#import <Foundation/Foundation.h>
#import "DownloadTaskItem.h"

NS_ASSUME_NONNULL_BEGIN

extern NSString * const DownloadTaskManagerDidUpdateTaskNotification;
extern NSString * const DownloadTaskManagerAggregateStateDidChangeNotification;
extern NSString * const DownloadTaskManagerTaskCompletedNotification;
extern NSString * const DownloadTaskManagerTaskKey;

/// Global concurrent-download limit (number of tasks simultaneously in Downloading state; controlled by a semaphore).
FOUNDATION_EXPORT NSInteger const PLDownloadMaxConcurrentTasks;

/**
 * Unified download-task manager (singleton).
 * Centrally manages the lifecycle, aggregated status, and operations for all download tasks.
 */
@interface DownloadTaskManager : NSObject

+ (instancetype)sharedManager;

#pragma mark - Registration / Query

- (DownloadTaskItem *)registerTaskWithResourceType:(NSString *)resourceType
                                      resourceName:(NSString *)resourceName
                                       displayName:(NSString *)displayName
                                    downloadSource:(NSString *)downloadSource
                                           rawTask:(nullable id)rawTask
                                    supportsResume:(BOOL)supportsResume
                                           iconURL:(nullable NSString *)iconURL;

- (void)removeTaskWithId:(NSString *)taskId;
- (nullable DownloadTaskItem *)taskWithId:(NSString *)taskId;
- (NSArray<DownloadTaskItem *> *)allTasks;
- (NSArray<DownloadTaskItem *> *)tasksWithState:(DownloadTaskState)state;
- (NSArray<DownloadTaskItem *> *)tasksWithStates:(NSArray<NSNumber *> *)states;
- (NSInteger)countOfTasksWithState:(DownloadTaskState)state;

#pragma mark - Aggregate State

- (DownloadTaskAggregateState)currentAggregateState;
- (BOOL)hasActiveTasks;                       // There are downloading / pending tasks.
- (BOOL)hasTasksInStates:(NSArray<NSNumber *> *)states;

#pragma mark - Actions

- (void)pauseTaskWithId:(NSString *)taskId;
- (void)resumeTaskWithId:(NSString *)taskId;
- (void)cancelTaskWithId:(NSString *)taskId;

/// Redownload (FCL style).
/// Cancel the old rawTask, reset item state (progress/speed/error), increment retryCount,
/// then call item.retryHandler to rebuild the underlying rawTask. No-op if retryHandler is unset
/// or maxRetryCount has been exceeded.
- (void)retryTaskWithId:(NSString *)taskId;

/// Switch download source. completion returns shouldRecreate: YES means the caller must cancel the
/// old task and recreate the download.
- (void)switchDownloadSourceForTaskId:(NSString *)taskId
                             toSource:(NSString *)source
                           completion:(void (^)(BOOL shouldRecreate,
                                                BOOL supportsResume,
                                                NSError * _Nullable error))completion;

#pragma mark - Progress / State Reporting

- (void)updateTaskWithId:(NSString *)taskId
                progress:(double)progress
              totalBytes:(int64_t)totalBytes
         downloadedBytes:(int64_t)downloadedBytes;

- (void)updateTaskWithId:(NSString *)taskId
                   speed:(double)speed
  estimatedTimeRemaining:(NSTimeInterval)estimatedTimeRemaining;

/// Report file-level progress for multi-file tasks (e.g. modpacks progressing file by file;
/// Phase 6 Task 6.1 dual-dimension progress).
/// totalFileCount <= 0 clears the file-count dimension (return to single-file display).
- (void)updateTaskWithId:(NSString *)taskId
      completedFileCount:(NSInteger)completedFileCount
          totalFileCount:(NSInteger)totalFileCount;

- (void)setTaskWithId:(NSString *)taskId state:(DownloadTaskState)state;

/// Mark the task as completed or failed; nil error indicates success.
- (void)setTaskWithId:(NSString *)taskId completedWithError:(nullable NSError *)error;

/// Update task error information (does not change the state).
- (void)updateTaskWithId:(NSString *)taskId error:(nullable NSError *)error;

#pragma mark - Stage reporting (redesign-download-ui Phase 1)

/// Replace the task's entire stage list (reset currentStageIndex to 0; an empty array clears stage
/// information and falls back to plain progress display).
- (void)setTaskWithId:(NSString *)taskId stages:(NSArray<PLTaskStage *> *)stages;

/// Update the state of the specified stage (out-of-range index is a no-op and is logged).
- (void)updateTaskWithId:(NSString *)taskId
           stageAtIndex:(NSUInteger)index
                 status:(PLTaskStageStatus)status;

/// Update the progress and dynamic detail text for the specified stage (nil message preserves the
/// current value; out-of-range index is a no-op).
- (void)updateTaskWithId:(NSString *)taskId
           stageAtIndex:(NSUInteger)index
                progress:(double)progress
                message:(nullable NSString *)message;

/// Update the rate for the specified stage (out-of-range index is a no-op).
- (void)updateTaskWithId:(NSString *)taskId
           stageAtIndex:(NSUInteger)index
                   rate:(double)rate;

/// Update the file count for the specified stage (dual dimension; totalFileCount <= 0 clears the
/// file-count dimension; out-of-range index is a no-op).
- (void)updateTaskWithId:(NSString *)taskId
           stageAtIndex:(NSUInteger)index
              fileCount:(NSInteger)completedFileCount
          totalFileCount:(NSInteger)totalFileCount;

/// Update the task's current-stage index (out-of-range index is a no-op and is logged).
- (void)updateTaskWithId:(NSString *)taskId
      currentStageIndex:(NSInteger)currentStageIndex;

#pragma mark - Concurrency / resume-data queries (added in Phase 2)

/// Current number of tasks waiting in the queue for a download slot (Pending tasks queue after the concurrency limit is reached).
- (NSInteger)pendingQueueCount;

/// Read the task's persisted resume data (saved on pause; for the caller to use inside retryHandler
/// with downloadTaskWithResumeData: to resume the download; returns nil if unavailable).
- (nullable NSData *)storedResumeDataForTaskId:(NSString *)taskId;

@end

NS_ASSUME_NONNULL_END
