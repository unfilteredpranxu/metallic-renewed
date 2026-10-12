#import <Foundation/Foundation.h>
#import "PLTaskStage.h"

NS_ASSUME_NONNULL_BEGIN

// Download-task states.
typedef NS_ENUM(NSInteger, DownloadTaskState) {
    DownloadTaskStatePending = 0,    // Pending
    DownloadTaskStateDownloading,    // Downloading
    DownloadTaskStatePaused,         // Paused
    DownloadTaskStateCompleted,      // Completed
    DownloadTaskStateCancelled,      // Cancelled
    DownloadTaskStateFailed          // Failed
};

// Aggregate states (for the floating ball, launch protection, etc.).
typedef NS_ENUM(NSInteger, DownloadTaskAggregateState) {
    DownloadTaskAggregateStateNone = 0,   // No tasks
    DownloadTaskAggregateStateIdle,       // All paused/waiting; none active
    DownloadTaskAggregateStateActive,     // At least one task is downloading
    DownloadTaskAggregateStatePaused,     // At least one paused task and none active
    DownloadTaskAggregateStateCompleted,  // All completed
    DownloadTaskAggregateStateFailed      // All failed/cancelled, with failure records remaining (optional)
};

// Resource-type constants.
extern NSString * const DownloadTaskResourceTypeMinecraft;
extern NSString * const DownloadTaskResourceTypeModloader;
extern NSString * const DownloadTaskResourceTypeMod;
extern NSString * const DownloadTaskResourceTypeShader;
extern NSString * const DownloadTaskResourceTypeResourcePack;
extern NSString * const DownloadTaskResourceTypeDataPack;
extern NSString * const DownloadTaskResourceTypeModpack;
extern NSString * const DownloadTaskResourceTypeWorld;
extern NSString * const DownloadTaskResourceTypeJavaRuntime;

@class DownloadTaskItem;

/// Retry callback type: set by the caller when registering a task; DownloadTaskManager.retryTaskWithId:
/// invokes it to rebuild the underlying rawTask.
/// The caller creates a new NSURLSessionTask in the handler and assigns it to item.rawTask; the old
/// item does not need to be removed (the manager handles that).
/// The parameter is the current item (with reset state); return the new rawTask so the manager can
/// update item.rawTask.
typedef id _Nullable (^DownloadRetryHandler)(DownloadTaskItem *item);

/**
 * Unified download-task data model.
 * Each download task (Minecraft itself, loader, mod, resource pack, etc.) has an instance in DownloadTaskManager.
 */
@interface DownloadTaskItem : NSObject

@property (nonatomic, copy) NSString *taskId;
@property (nonatomic, copy) NSString *resourceType;
@property (nonatomic, copy) NSString *resourceName;
@property (nonatomic, copy) NSString *displayName;
@property (nonatomic, copy) NSString *downloadSource;
@property (nonatomic, assign) DownloadTaskState state;

/// 0.0 ~ 1.0; < 0 means unknown/undetermined.
@property (nonatomic, assign) double progress;
@property (nonatomic, assign) int64_t totalSize;
@property (nonatomic, assign) int64_t downloadedSize;
@property (nonatomic, assign) double speed;                    // bytes/s
@property (nonatomic, assign) NSTimeInterval estimatedTimeRemaining;

/// File-level progress for multi-file tasks (such as modpacks; Phase 6 Task 6.1 dual-dimension progress).
/// totalFileCount <= 0 indicates a single-file task (do not show the file-count dimension).
@property (nonatomic, assign) NSInteger completedFileCount;
@property (nonatomic, assign) NSInteger totalFileCount;

@property (nonatomic, copy, nullable) NSString *iconURL;
@property (nonatomic, assign) BOOL supportsResume;
@property (nonatomic, strong) NSDate *createdDate;

/// Underlying task object, weakly referenced to avoid retain cycles
/// (MinecraftResourceDownloadTask / NSURLSessionTask, etc.).
@property (nonatomic, weak, nullable) id rawTask;
@property (nonatomic, strong, nullable) NSError *errorInfo;

/// Extension fields for the caller.
@property (nonatomic, strong) NSMutableDictionary *userInfo;

#pragma mark - Retry support (FCL-style redownload)

/// Original download URL, allowing the model layer to rebuild directly for retry/source switching
/// (optional; callers may leave it unset).
@property (nonatomic, copy, nullable) NSString *downloadURL;

/// Retry callback: set by the caller when registering a task; DownloadTaskManager.retryTaskWithId:
/// invokes it to rebuild the underlying rawTask.
/// The caller creates a new NSURLSessionTask in the handler and assigns it to item.rawTask; the old
/// item does not need to be removed (the manager handles that).
/// The parameter is the current item (with reset state); return the new rawTask so the manager can
/// update item.rawTask.
@property (nonatomic, copy, nullable) DownloadRetryHandler retryHandler;

/// Number of retries so far (incremented by the manager on each retryTaskWithId: call).
@property (nonatomic, assign) NSInteger retryCount;

/// Maximum retry count, default 3. After this limit, the UI no longer shows "Retry" (but still shows "Remove").
@property (nonatomic, assign) NSInteger maxRetryCount;

#pragma mark - Resume / persistent-state restoration support (Phase 2)

/// Path to the resume-data file (on pause, the manager saves it to
/// <Home>/Library/Caches/PLDownloadResumeData/<taskId>.resume; retain the path reference when
/// restoring from a disk snapshot).
@property (nonatomic, copy, nullable) NSString *resumeDataPath;

/// Marks a task restored from a disk snapshot: the underlying rawTask and retryHandler closure
/// cannot be serialized, so the caller must register the restored task again before it can really
/// resume/retry; supportsResume is set to NO for restored items.
@property (nonatomic, assign) BOOL needsRecreate;

#pragma mark - Staged progress (redesign-download-ui Phase 1)

/// Stage list (multi-step progress for installation tasks; an empty array means there is no stage
/// information and falls back to plain progress display).
/// Stage objects are mutable; callers update them individually through DownloadTaskManager's
/// stage-reporting API.
@property (nonatomic, copy) NSArray<PLTaskStage *> *stages;

/// Index of the current stage; -1 means no stage has been entered (remains -1 when no stage info exists).
@property (nonatomic, assign) NSInteger currentStageIndex;

/// Current stage (returns nil if stages is empty or currentStageIndex is out of range; safe for UI to call).
- (nullable PLTaskStage *)currentStage;

/// Flag to automatically present the unified progress page for installation tasks (redesign-download-ui Phase 2):
/// the caller sets YES after registering a task; DownloadTaskManager automatically presents
/// PLTaskProgressViewController on the task's first state update (only one on screen; a new task
/// replaces its content).
/// Runtime-only flag; not serialized in snapshots (restored tasks are not presented automatically).
@property (nonatomic, assign) BOOL autoPresentDetail;

- (instancetype)initWithResourceType:(NSString *)resourceType
                        resourceName:(NSString *)resourceName
                         displayName:(NSString *)displayName
                      downloadSource:(NSString *)downloadSource
                             rawTask:(nullable id)rawTask
                      supportsResume:(BOOL)supportsResume
                             iconURL:(nullable NSString *)iconURL;

#pragma mark - Snapshot serialization (called by DownloadTaskManager during persistence/restoration)

/// Export a JSON-serializable task snapshot (fields such as taskId, resourceType, name, displayName,
/// iconURL, state, totalBytes, receivedBytes, downloadSource, timestamp, downloadURL).
- (NSDictionary *)snapshotDictionary;

/// Rebuild a task from a snapshot (retain the original taskId; rawTask/retryHandler cannot be restored).
/// Return nil for an invalid snapshot (missing taskId / incorrect type).
- (nullable instancetype)initWithSnapshotDictionary:(NSDictionary *)snapshot;

/// Export a download-history entry (name/type/size/time/result) for DownloadHistoryStore to record.
- (NSDictionary *)historyDictionary;

@end

NS_ASSUME_NONNULL_END
