#include <CommonCrypto/CommonDigest.h>
#include <sys/time.h>
#import "PLDownloadFileCommit.h"

#import "authenticator/BaseAuthenticator.h"
#import "installer/modpack/ModpackAPI.h"
#import "AFNetworking.h"
#import "LauncherNavigationController.h"
#import "LauncherPreferences.h"
#import "MinecraftResourceDownloadTask.h"
#import "MinecraftResourceUtils.h"
#import "ModpackImportService.h"
#import "PLMirrorCenter.h"
#import "DownloadTaskManager.h"
#import "DownloadTaskItem.h"
#import "PLTaskStages.h"
#import "ios_uikit_bridge.h"
#import "utils.h"

NSString * const kMinecraftResourceDownloadBackgroundSessionIdentifier = @"com.air-devs.air.MinecraftResourceDownloadTask";

// Indices for the six vanilla-install stages (matches PLTaskStagesVanilla(), redesign-download-ui Phase 3 Task 3.1).
static const NSUInteger kMCStageIndexFetchManifest = 0;
static const NSUInteger kMCStageIndexVersionJSON = 1;
static const NSUInteger kMCStageIndexDownloadClient = 2;
static const NSUInteger kMCStageIndexLibraries = 3;
static const NSUInteger kMCStageIndexAssets = 4;
static const NSUInteger kMCStageIndexVerify = 5;

@interface MCDownloadItem : NSObject
@property (nonatomic, copy) NSString *url;
@property (nonatomic, assign) NSUInteger size;
@property (nonatomic, copy) NSString *sha;
@property (nonatomic, copy) NSString *altName;
@property (nonatomic, copy) NSString *toPath;
@property (nonatomic, assign) NSInteger retryCount;
@property (nonatomic, copy) void (^success)(void);
@end

@implementation MCDownloadItem
@end

@interface MinecraftResourceDownloadTask ()
@property AFURLSessionManager* manager;
@property (nonatomic, strong) DownloadTaskItem *currentDownloadTaskItem;
@property (nonatomic, copy) NSString *currentVersionId;
@property (nonatomic, assign) BOOL isObservingTaskProgress;
@property (nonatomic, assign) NSTimeInterval progressLastTime;
@property (nonatomic, assign) int64_t progressLastCompleted;
@property (nonatomic, assign) NSTimeInterval lastUIReportTime;

// ===== Stage reporting (redesign-download-ui Phase 3 Task 3.1) =====
// Stage reporting is enabled only for downloadVersion: (vanilla install flow); modpack downloads are reported by ModpackImportService.
@property (nonatomic, assign) BOOL stageReportingEnabled;
// Dual file counts for libraries/assets (classified by destination path; version JSON files under versions/ are excluded).
@property (nonatomic, assign) NSInteger libTotalFileCount;
@property (nonatomic, assign) NSInteger libCompletedFileCount;
@property (nonatomic, assign) NSInteger assetTotalFileCount;
@property (nonatomic, assign) NSInteger assetCompletedFileCount;

// Concurrent task and item queue management to prevent CFNetwork socket/daemon exhaustion and Jetsam freezes
@property (nonatomic, strong) NSMutableArray<MCDownloadItem *> *itemQueue;
@property (nonatomic, strong) NSMutableArray<NSURLSessionDownloadTask *> *taskQueue;
@property (nonatomic, assign) NSInteger runningTasksCount;

- (void)enqueueDownloadItems:(NSArray<MCDownloadItem *> *)items;
- (void)enqueueDownloadItem:(MCDownloadItem *)item;
- (void)startDownloadingItem:(MCDownloadItem *)item;
- (MCDownloadItem *)queueOrVerifyItemWithURL:(NSString *)url size:(NSUInteger)size sha:(NSString *)sha altName:(NSString *)altName toPath:(NSString *)path success:(void (^)(void))success;
- (void)enqueueDownloadTasks:(NSArray *)tasks;
- (void)enqueueSingleDownloadTask:(NSURLSessionDownloadTask *)task;
- (void)drainTaskQueue;
- (void)taskDidFinish;

// Task 5.10: Unified import entry point after an online modpack ZIP download completes (reuses ModpackImportService).
- (void)importDownloadedModpackPackage:(NSString *)packagePath;
@end

@implementation MinecraftResourceDownloadTask

+ (AFURLSessionManager *)sharedBackgroundSessionManager {
    // Based on the main branch: use foreground defaultSessionConfiguration instead of backgroundSessionConfiguration.
    //
    // Why not use a background URLSession:
    // 1. Background sessions are scheduled by the nsurlsessiond system daemon, which limits concurrency and serializes tasks,
    //    making vanilla installs (hundreds of assets and dozens of libraries) extremely slow, appearing to "spin without downloading."
    // 2. The system persists unfinished background tasks; stale tasks from failures or incomplete cancellations can block new downloads.
    // 3. Foreground sessions start concurrent work immediately on resume, which suits an actively used launcher.
    //
    // Keep the singleton pattern (to avoid creating a new session on every init), but use the foreground configuration.
    static AFURLSessionManager *manager = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSURLSessionConfiguration *configuration = [NSURLSessionConfiguration defaultSessionConfiguration];
        configuration.timeoutIntervalForRequest = 30.0;
        configuration.timeoutIntervalForResource = 60.0;
        configuration.URLCache = nil;
        configuration.requestCachePolicy = NSURLRequestReloadIgnoringLocalCacheData;
        configuration.URLCredentialStorage = nil;
        // Optimal concurrent connections for iOS without overloading network daemon
        configuration.HTTPMaximumConnectionsPerHost = 16;
        manager = [[AFURLSessionManager alloc] initWithSessionConfiguration:configuration];
    });
    return manager;
}

- (void)dealloc {
    if (self.isObservingTaskProgress && self.progress) {
        @try {
            [self.progress removeObserver:self forKeyPath:@"fractionCompleted"];
        } @catch (NSException *exception) {
            // ignore
        }
        self.isObservingTaskProgress = NO;
    }
}

- (instancetype)init {
    self = [super init];
    self.manager = [MinecraftResourceDownloadTask sharedBackgroundSessionManager];
    self.fileList = [NSMutableArray new];
    self.progressList = [NSMutableArray new];
    // Phase 5 fix: initialize the failed-file list (based on FCL's failure summary mechanism).
    self.failedFiles = [NSMutableArray new];
    self.itemQueue = [NSMutableArray new];
    self.taskQueue = [NSMutableArray new];
    self.runningTasksCount = 0;
    return self;
}

- (void)enqueueDownloadItems:(NSArray<MCDownloadItem *> *)items {
    if (items.count == 0) return;
    @synchronized (self) {
        if (!self.itemQueue) {
            self.itemQueue = [NSMutableArray array];
        }
        [self.itemQueue addObjectsFromArray:items];
    }
    [self drainTaskQueue];
}

- (void)enqueueDownloadItem:(MCDownloadItem *)item {
    if (!item) return;
    @synchronized (self) {
        if (!self.itemQueue) {
            self.itemQueue = [NSMutableArray array];
        }
        [self.itemQueue addObject:item];
    }
    [self drainTaskQueue];
}

- (void)enqueueDownloadTasks:(NSArray *)tasks {
    if (tasks.count == 0) return;
    NSMutableArray<MCDownloadItem *> *items = [NSMutableArray array];
    NSMutableArray<NSURLSessionDownloadTask *> *legacyTasks = [NSMutableArray array];
    for (id obj in tasks) {
        if ([obj isKindOfClass:[MCDownloadItem class]]) {
            [items addObject:obj];
        } else if ([obj isKindOfClass:[NSURLSessionDownloadTask class]]) {
            [legacyTasks addObject:obj];
        }
    }
    if (items.count > 0) {
        [self enqueueDownloadItems:items];
    }
    if (legacyTasks.count > 0) {
        @synchronized (self) {
            if (!self.taskQueue) {
                self.taskQueue = [NSMutableArray array];
            }
            [self.taskQueue addObjectsFromArray:legacyTasks];
        }
        [self drainTaskQueue];
    }
}

- (void)enqueueSingleDownloadTask:(NSURLSessionDownloadTask *)task {
    if (!task) return;
    @synchronized (self) {
        if (!self.taskQueue) {
            self.taskQueue = [NSMutableArray array];
        }
        [self.taskQueue addObject:task];
    }
    [self drainTaskQueue];
}

- (void)drainTaskQueue {
    const NSInteger kMaxConcurrentDownloads = 16;
    while (YES) {
        MCDownloadItem *itemToStart = nil;
        NSURLSessionDownloadTask *taskToResume = nil;
        @synchronized (self) {
            if (self.progress.cancelled) {
                [self.itemQueue removeAllObjects];
                [self.taskQueue removeAllObjects];
                return;
            }
            if (self.runningTasksCount < kMaxConcurrentDownloads) {
                if (self.itemQueue.count > 0) {
                    itemToStart = self.itemQueue.firstObject;
                    [self.itemQueue removeObjectAtIndex:0];
                    self.runningTasksCount++;
                } else if (self.taskQueue.count > 0) {
                    taskToResume = self.taskQueue.firstObject;
                    [self.taskQueue removeObjectAtIndex:0];
                    self.runningTasksCount++;
                }
            }
        }
        if (itemToStart) {
            [self startDownloadingItem:itemToStart];
        } else if (taskToResume) {
            [taskToResume resume];
        } else {
            break;
        }
    }
}

- (void)startDownloadingItem:(MCDownloadItem *)item {
    NSString *url = item.url;
    NSUInteger size = item.size;
    NSString *sha = item.sha;
    NSString *altName = item.altName;
    NSString *path = item.toPath;
    NSInteger retryCount = item.retryCount;
    void (^success)(void) = item.success;

    NSString *name = altName ?: path.lastPathComponent;
    @synchronized (self.fileList) {
        [self.fileList addObject:name];
    }

    NSArray<NSURL *> *mirrorCandidates = [self mirrorCandidatesForOriginalURL:url];
    if (mirrorCandidates.count == 0) {
        NSURL *fallbackURL = [NSURL URLWithString:url];
        mirrorCandidates = fallbackURL ? @[fallbackURL] : @[];
    }
    NSInteger maxRetry = self.maxRetryCount > 0 ? self.maxRetryCount : 3;
    NSInteger attemptCount = MAX((NSInteger)mirrorCandidates.count, 1) * maxRetry;
    NSUInteger candidateIndex = mirrorCandidates.count > 0
        ? MIN((NSUInteger)(MAX(retryCount, 0) / MAX(maxRetry, 1)), mirrorCandidates.count - 1)
        : 0;
    NSString *replacedURL = mirrorCandidates.count > 0
        ? (mirrorCandidates[candidateIndex].absoluteString ?: url)
        : url;

    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:replacedURL]
                                                           cachePolicy:NSURLRequestReloadIgnoringLocalCacheData
                                                       timeoutInterval:30.0];

    NSString *stagingPath = [path stringByAppendingFormat:@".metallic-%@.part", NSUUID.UUID.UUIDString];
    __block int64_t lastCompleted = 0;
    __weak MinecraftResourceDownloadTask *weakSelf = self;
    NSURLSessionDownloadTask *task = [self.manager downloadTaskWithRequest:request progress:^(NSProgress * _Nonnull downloadProgress) {
        int64_t current = downloadProgress.completedUnitCount;
        int64_t delta = current - lastCompleted;
        if (delta > 0) {
            lastCompleted = current;
            @synchronized (weakSelf) {
                weakSelf.progress.completedUnitCount += delta;
            }
        }
    } destination:^NSURL * _Nonnull(NSURL * _Nonnull targetPath, NSURLResponse * _Nonnull response) {
        [NSFileManager.defaultManager createDirectoryAtPath:path.stringByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:nil];
        return [NSURL fileURLWithPath:stagingPath];
    } completionHandler:^(NSURLResponse * _Nonnull response, NSURL * _Nullable filePath, NSError * _Nullable error) {
        @autoreleasepool {
        if (!error && !weakSelf.progress.cancelled) {
            error = [weakSelf mc_publishStagedFile:filePath.path toPath:path size:size sha:sha altName:altName];
        }
        [NSFileManager.defaultManager removeItemAtPath:stagingPath error:nil];
            int64_t expected = (size > 0 ? size : 1);
            int64_t remaining = expected - lastCompleted;

            if (weakSelf.progress.cancelled) {
                // ignore
            } else if (error != nil) {
                if (retryCount + 1 < attemptCount) {
                    item.retryCount = retryCount + 1;
                    if (lastCompleted > 0) {
                        @synchronized (weakSelf) {
                            if (weakSelf.progress.completedUnitCount >= lastCompleted) {
                                weakSelf.progress.completedUnitCount -= lastCompleted;
                            }
                        }
                    }
                    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                        [weakSelf enqueueDownloadItem:item];
                    });
                } else {
                    [weakSelf finishDownloadWithError:error file:name];
                    [weakSelf mc_recordStageFileFinishedAtPath:path];
                    if (remaining > 0) {
                        @synchronized (weakSelf) {
                            weakSelf.progress.completedUnitCount += remaining;
                        }
                    }
                }
            } else {
                if (remaining > 0) {
                    @synchronized (weakSelf) {
                        weakSelf.progress.completedUnitCount += remaining;
                    }
                }
                [weakSelf mc_recordStageFileFinishedAtPath:path];
                if (success) success();
            }
        }
        [weakSelf taskDidFinish];
    }];

    if (task && self.currentDownloadTaskItem) {
        task.taskDescription = self.currentDownloadTaskItem.taskId;
    }
    [task resume];
}


// All caller-supplied final paths are preserved. A same-directory POSIX rename is atomic;
// failed transfer, length/hash validation, cancellation or disk errors leave the old file intact.
- (NSError *)mc_publishStagedFile:(NSString *)staged toPath:(NSString *)path size:(NSUInteger)size sha:(NSString *)sha altName:(NSString *)altName {
    NSError *error = nil;
    NSDictionary *attributes = staged.length ? [NSFileManager.defaultManager attributesOfItemAtPath:staged error:&error] : nil;
    if (!attributes) return error ?: [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileNoSuchFileError userInfo:@{NSLocalizedDescriptionKey:@"Downloaded staging file is missing."}];
    if ((size > 0 && attributes.fileSize != size) || (sha.length > 0 && ![self checkSHAIgnorePref:sha forFile:staged altName:altName logSuccess:YES])) {
        NSLog(@"[Metallic Download] Integrity rejected %@: expected bytes=%llu actual=%llu hash supplied=%d", path.lastPathComponent, (unsigned long long)size, attributes.fileSize, sha.length>0);
        return [NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorCannotDecodeContentData userInfo:@{NSLocalizedDescriptionKey:@"Downloaded file failed length or SHA-1 verification."}];
    }
    if (self.progress.cancelled) return [NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorCancelled userInfo:nil];
    if (PLDownloadCommitStagedFile(staged.fileSystemRepresentation, path.fileSystemRepresentation) != 0) {
        int failure = errno;
        NSLog(@"[Metallic Download] Final placement failed %@: errno=%d", path.lastPathComponent, failure);
        return [NSError errorWithDomain:NSPOSIXErrorDomain code:failure userInfo:@{NSLocalizedDescriptionKey:@"Verified download could not be placed in its destination."}];
    }
    return nil;
}

- (void)taskDidFinish {
    @synchronized (self) {
        if (self.runningTasksCount > 0) {
            self.runningTasksCount--;
        }
    }
    [self drainTaskQueue];
}

// Selects and substitutes the download source according to configuration.
- (NSString *)replaceURLWithDownloadSource:(NSString *)originalURL {
    return [self replaceURLWithDownloadSource:originalURL forceSource:nil];
}

/// Generates mirror candidates for game files (using the PLMirrorCenter mirror hub).
/// Candidates include the original (official) URL and BMCLAPI mirror URLs, deduplicated and sorted according to the current mirror policy.
/// Unrecognized hosts return only the original URL. Mirror-prefix mapping is centralized in PLMirrorCenter;
/// this class no longer hard-codes mirror root URLs.
- (NSArray<NSURL *> *)mirrorCandidatesForOriginalURL:(NSString *)originalURL {
    NSURL *url = [NSURL URLWithString:originalURL];
    if (!url) return @[];
    return [PLMirrorCenter candidateURLsForOriginalURL:url
                                          resourceType:PLMirrorResourceTypeGameFile];
}

/// Core mirror-source substitution implementation (integrated with PLMirrorCenter, spec Task 4.2).
/// Based on FCL (FoldCraftLauncher) and ZalithLauncher2: supports fallback across multiple mirrors.
/// @param originalURL Original URL.
/// @param forceSource Source to force (retains the semantics of the legacy parameter):
///                    nil=choose the preferred source according to PLMirrorCenter's current policy (which includes legacy-key fallback);
///                    @"official"=lock to the original official URL;
///                    @"bmclapi"=lock to a BMCLAPI mirror candidate (fall back to the original URL if none is available);
///                    @"mcim"=retain legacy behavior: MCIM does not override Mojang game files, so return the original URL.
- (NSString *)replaceURLWithDownloadSource:(NSString *)originalURL forceSource:(nullable NSString *)forceSource {
    if (!originalURL) return originalURL;

    NSArray<NSURL *> *candidates = [self mirrorCandidatesForOriginalURL:originalURL];
    if (candidates.count == 0) return originalURL;

    if (forceSource.length == 0) {
        // nil → select the preferred candidate according to PLMirrorCenter policy.
        return candidates.firstObject.absoluteString ?: originalURL;
    }
    if ([forceSource isEqualToString:@"official"] || [forceSource isEqualToString:@"mcim"]) {
        // Connect directly to the official source; mcim retains legacy behavior (game files are not rewritten by MCIM).
        return originalURL;
    }
    if ([forceSource isEqualToString:@"bmclapi"]) {
        // Lock to the BMCLAPI mirror candidate (the candidate that differs from the original URL).
        for (NSURL *candidate in candidates) {
            if (![candidate.absoluteString isEqualToString:originalURL]) {
                return candidate.absoluteString;
            }
        }
        return originalURL;
    }
    // Unknown source value: select the preferred source according to policy.
    return candidates.firstObject.absoluteString ?: originalURL;
}

// Add file to the queue
- (NSURLSessionDownloadTask *)createDownloadTask:(NSString *)url size:(NSUInteger)size sha:(NSString *)sha altName:(NSString *)altName toPath:(NSString *)path success:(void (^)())success {
    return [self createDownloadTask:url size:size sha:sha altName:altName toPath:path retryCount:0 success:success];
}

- (NSURLSessionDownloadTask *)createDownloadTask:(NSString *)url size:(NSUInteger)size sha:(NSString *)sha altName:(NSString *)altName toPath:(NSString *)path retryCount:(NSInteger)retryCount success:(void (^)())success {
    BOOL fileExists = [NSFileManager.defaultManager fileExistsAtPath:path];
    if (fileExists) {
        BOOL valid = YES;
        if (size > 0) {
            NSDictionary *attrs = [NSFileManager.defaultManager attributesOfItemAtPath:path error:nil];
            if ([attrs fileSize] != size) {
                valid = NO;
            }
        }
        if (valid && sha.length > 0) {
            valid = [self checkSHAIgnorePref:sha forFile:path altName:altName logSuccess:NO];
        }
        if (valid) {
            if (retryCount == 0) {
                [self mc_recordStageFileStartedAtPath:path];
                [self mc_recordStageFileFinishedAtPath:path];
            }
            if (success) success();
            return nil;
        } else {
            NSLog(@"[MCDL] Replacing invalid existing file only after verified staging: %@", path.lastPathComponent);
        }
    } else if (![self checkAccessWithDialog:YES]) {
        return nil;
    }
    // Stage count: add to the total on first creation (do not count retry rotations again).
    if (retryCount == 0) {
        [self mc_recordStageFileStartedAtPath:path];
    }

    NSString *name = altName ?: path.lastPathComponent;
    // Mirror candidates and failover (integrated with PLMirrorCenter, spec Task 4.2):
    // Candidates are sorted according to the current mirror policy (e.g. [official, BMCLAPI mirror]). During retries,
    // move to the next candidate after exhausting the retry budget for the current one; fail only after all candidates are exhausted.
    // This prevents a single mirror failure from stalling the entire download (based on the multi-source fallback in FCL / ZalithLauncher2).
    // SHA1 validation still runs as usual, preserving download integrity.
    NSArray<NSURL *> *mirrorCandidates = [self mirrorCandidatesForOriginalURL:url];
    if (mirrorCandidates.count == 0) {
        // Edge case where the URL cannot be parsed: use a single candidate containing the original URL, preserving legacy behavior.
        NSURL *fallbackURL = [NSURL URLWithString:url];
        mirrorCandidates = fallbackURL ? @[fallbackURL] : @[];
    }
    NSInteger maxRetry = self.maxRetryCount > 0 ? self.maxRetryCount : 3;
    // Total attempts = per-candidate retry budget × number of candidates (fail only after all candidates are exhausted).
    NSInteger attemptCount = MAX((NSInteger)mirrorCandidates.count, 1) * maxRetry;
    // Candidate index for the current attempt: attempts 0 through (maxRetry-1) use candidate 0, then rotate to the next candidate.
    NSUInteger candidateIndex = mirrorCandidates.count > 0
        ? MIN((NSUInteger)(MAX(retryCount, 0) / MAX(maxRetry, 1)), mirrorCandidates.count - 1)
        : 0;
    NSString *replacedURL = mirrorCandidates.count > 0
        ? (mirrorCandidates[candidateIndex].absoluteString ?: url)
        : url;
    if (retryCount > 0) {
        NSLog(@"[MCDL] Retry %@ (attempt %ld/%ld, mirror candidate %lu/%lu)",
              name, (long)(retryCount + 1), (long)attemptCount,
              (unsigned long)(candidateIndex + 1), (unsigned long)mirrorCandidates.count);
    }
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:replacedURL]
                                                           cachePolicy:NSURLRequestReloadIgnoringLocalCacheData
                                                       timeoutInterval:30.0];
    NSString *stagingPath = [path stringByAppendingFormat:@".metallic-%@.part", NSUUID.UUID.UUIDString];
    __block int64_t lastCompleted = 0;
    __weak MinecraftResourceDownloadTask *weakSelf = self;
    __block NSURLSessionDownloadTask *task = [self.manager downloadTaskWithRequest:request progress:^(NSProgress * _Nonnull downloadProgress) {
        int64_t current = downloadProgress.completedUnitCount;
        int64_t delta = current - lastCompleted;
        if (delta > 0) {
            lastCompleted = current;
            @synchronized (weakSelf) {
                weakSelf.progress.completedUnitCount += delta;
            }
        }
    } destination:^NSURL * _Nonnull(NSURL * _Nonnull targetPath, NSURLResponse * _Nonnull response) {
        @autoreleasepool {
            if (!weakSelf) {
                [NSFileManager.defaultManager createDirectoryAtPath:path.stringByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:nil];
                return [NSURL fileURLWithPath:stagingPath];
            }
            if (!size && task) {
                [weakSelf addDownloadTaskToProgress:task size:response.expectedContentLength];
                @synchronized(weakSelf.fileList) {
                    [weakSelf.fileList addObject:name];
                }
            }
            [NSFileManager.defaultManager createDirectoryAtPath:path.stringByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:nil];
            return [NSURL fileURLWithPath:stagingPath];
        }
    } completionHandler:^(NSURLResponse * _Nonnull response, NSURL * _Nullable filePath, NSError * _Nullable error) {
        @autoreleasepool {
        if (!error && !weakSelf.progress.cancelled) {
            error = [weakSelf mc_publishStagedFile:filePath.path toPath:path size:size sha:sha altName:altName];
        }
        [NSFileManager.defaultManager removeItemAtPath:stagingPath error:nil];
        int64_t expected = (size > 0 ? size : 1);
        int64_t remaining = expected - lastCompleted;

        if (self.progress.cancelled) {
            // Ignore any further errors
        } else if (error != nil) {
            // The staging file was removed; an existing destination is untouched.
            if (retryCount + 1 < attemptCount) {
                NSInteger nextRetry = retryCount + 1;
                NSLog(@"[MCDL] Retrying %@ (attempt %ld/%ld)", name, (long)(nextRetry + 1), (long)attemptCount);

                if (weakSelf.retryCallback) {
                    dispatch_async(dispatch_get_main_queue(), ^{
                        weakSelf.retryCallback(nextRetry, attemptCount);
                    });
                }
                
                if (lastCompleted > 0) {
                    @synchronized (weakSelf) {
                        if (weakSelf.progress.completedUnitCount >= lastCompleted) {
                            weakSelf.progress.completedUnitCount -= lastCompleted;
                        }
                    }
                }

                // Delayed retry through queue to avoid socket flood
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                    NSURLSessionDownloadTask *retryTask = [weakSelf createDownloadTask:url size:size sha:sha altName:altName toPath:path retryCount:nextRetry success:success];
                    if (retryTask) {
                        [weakSelf enqueueSingleDownloadTask:retryTask];
                    }
                });
            } else {
                [weakSelf finishDownloadWithError:error file:name];
                [weakSelf mc_recordStageFileFinishedAtPath:path];
                if (remaining > 0) {
                    @synchronized (weakSelf) {
                        weakSelf.progress.completedUnitCount += remaining;
                    }
                }
            }
        } else {
            if (remaining > 0) {
                @synchronized (weakSelf) {
                    weakSelf.progress.completedUnitCount += remaining;
                }
            }
            [self mc_recordStageFileFinishedAtPath:path];
            if (success) success();
        }
        } // @autoreleasepool
        [weakSelf taskDidFinish];
    }];

    if (size && task) {
        [self addDownloadTaskToProgress:task size:size];
        @synchronized(self.fileList) {
            [self.fileList addObject:name];
        }
    }

    if (task && self.currentDownloadTaskItem) {
        task.taskDescription = self.currentDownloadTaskItem.taskId;
    }

    return task;
}

- (NSURLSessionDownloadTask *)createDownloadTask:(NSString *)url size:(NSUInteger)size sha:(NSString *)sha altName:(NSString *)altName toPath:(NSString *)path {
    return [self createDownloadTask:url size:size sha:sha altName:altName toPath:path success:nil];
}

- (void)addDownloadTaskToProgress:(NSURLSessionDownloadTask *)task size:(NSInteger)size {
    @synchronized(self) {
        NSUInteger fileSize = size > 0 ? size : 1;
        self.progress.totalUnitCount += fileSize;
        self.textProgress.totalUnitCount = self.progress.totalUnitCount;
    }
}

- (void)downloadVersionMetadata:(NSDictionary *)version success:(void (^)())success {
    // Download base json
    NSString *versionStr = version[@"id"];
    if ([versionStr isEqualToString:@"latest-release"]) {
        versionStr = getPrefObject(@"internal.latest_version.release");
    } else if ([versionStr isEqualToString:@"latest-snapshot"]) {
        versionStr = getPrefObject(@"internal.latest_version.snapshot");
    }

    NSString *path = [NSString stringWithFormat:@"%1$s/versions/%2$@/%2$@.json", getenv("POJAV_GAME_DIR"), versionStr];
    // Find it again to resolve latest-*
    version = (id)[MinecraftResourceUtils findVersion:versionStr inList:remoteVersionList];

    void(^completionBlock)(void) = ^{
        self.metadata = parseJSONFromFile(path);
        if (self.metadata[@"NSErrorObject"]) {
            [self finishDownloadWithErrorString:[self.metadata[@"NSErrorObject"] localizedDescription]];
            return;
        }
        if (self.metadata[@"inheritsFrom"]) {
            NSMutableDictionary *inheritsFromDict = parseJSONFromFile([NSString stringWithFormat:@"%1$s/versions/%2$@/%2$@.json", getenv("POJAV_GAME_DIR"), self.metadata[@"inheritsFrom"]]);
            if (inheritsFromDict && !inheritsFromDict[@"NSErrorObject"]) {  // Check for an error dictionary.
                // Fix: parseJSONFromFile returns an error dictionary instead of nil,
                //   so a missing inheritsFrom parent version could cause the error dictionary to be treated as metadata.
                [MinecraftResourceUtils processVersion:self.metadata inheritsFrom:inheritsFromDict];
                self.metadata = inheritsFromDict;
            } else {
                // Parent version is missing or corrupted; report an error.
                [self finishDownloadWithErrorString:[NSString stringWithFormat:localize(@"i18n_str_446", nil), self.metadata[@"inheritsFrom"]]];
                return;
            }
        }
        [MinecraftResourceUtils tweakVersionJson:self.metadata];
        success();
    };

    if (!version) {
        // This is likely local version, check if json exists and has inheritsFrom
        NSMutableDictionary *json = parseJSONFromFile(path);
        if (json[@"NSErrorObject"]) {
            [self finishDownloadWithErrorString:[json[@"NSErrorObject"] localizedDescription]];
            return;
        } else if (json[@"inheritsFrom"]) {
            version = (id)[MinecraftResourceUtils findVersion:json[@"inheritsFrom"] inList:remoteVersionList];
            if (version) {
                path = [NSString stringWithFormat:@"%1$s/versions/%2$@/%2$@.json", getenv("POJAV_GAME_DIR"), json[@"inheritsFrom"]];
            } else {
                // Phase 5 fix (based on FCL ModpackHelper.ensureCompleteVersion):
                // findVersion usually fails because remoteVersionList has not loaded (modpack import runs on a background thread
                // and does not go through DownloadViewController's manifest-loading flow).
                // Check whether ensureParentVersionExists has already downloaded the parent version JSON:
                //   - If present → call completionBlock directly; subsequent libraries/assets downloads proceed as usual.
                //   - If absent → report an error (the launcher cannot continue).
                NSString *parentJsonPath = [NSString stringWithFormat:@"%1$s/versions/%2$@/%2$@.json",
                                            getenv("POJAV_GAME_DIR"), json[@"inheritsFrom"]];
                if ([NSFileManager.defaultManager fileExistsAtPath:parentJsonPath]) {
                    NSLog(@"[MCDL] remoteVersionList not loaded, but parent version JSON exists: %@", parentJsonPath);
                    completionBlock();
                    return;
                } else {
                    [self finishDownloadWithErrorString:[NSString stringWithFormat:localize(@"i18n_str_447", nil), json[@"inheritsFrom"]]];
                    return;
                }
            }
        } else {
            completionBlock();
            return;
        }
    }

    versionStr = version[@"id"];
    NSString *url = version[@"url"];
    NSString *sha = url.stringByDeletingLastPathComponent.lastPathComponent;
    NSUInteger size = [version[@"size"] unsignedLongLongValue];

    NSURLSessionDownloadTask *task = [self createDownloadTask:url size:size sha:sha altName:nil toPath:path success:completionBlock];
    [task resume];
}

#pragma mark - Minecraft installation

- (void)downloadAssetMetadataWithSuccess:(void (^)())success {
    NSDictionary *assetIndex = self.metadata[@"assetIndex"];
    if (!assetIndex) {
        success();
        return;
    }
    NSString *name = [NSString stringWithFormat:@"assets/indexes/%@.json", assetIndex[@"id"]];
    NSString *path = [@(getenv("POJAV_GAME_DIR")) stringByAppendingPathComponent:name];
    NSString *url = assetIndex[@"url"];
    NSString *sha = url.stringByDeletingLastPathComponent.lastPathComponent;
    NSUInteger size = [assetIndex[@"size"] unsignedLongLongValue];
    NSURLSessionDownloadTask *task = [self createDownloadTask:url size:size sha:sha altName:name toPath:path success:^{
        self.metadata[@"assetIndexObj"] = parseJSONFromFile(path);
        success();
    }];
    [task resume];
}

- (MCDownloadItem *)queueOrVerifyItemWithURL:(NSString *)url size:(NSUInteger)size sha:(NSString *)sha altName:(NSString *)altName toPath:(NSString *)path success:(void (^)(void))success {
    BOOL fileExists = [NSFileManager.defaultManager fileExistsAtPath:path];
    if (fileExists) {
        BOOL valid = YES;
        if (size > 0) {
            NSDictionary *attrs = [NSFileManager.defaultManager attributesOfItemAtPath:path error:nil];
            if ([attrs fileSize] != size) {
                valid = NO;
            }
        }
        if (valid && sha.length > 0) {
            valid = [self checkSHAIgnorePref:sha forFile:path altName:altName logSuccess:NO];
        }
        if (valid) {
            [self mc_recordStageFileStartedAtPath:path];
            [self mc_recordStageFileFinishedAtPath:path];
            if (success) success();
            return nil;
        } else {
            NSLog(@"[MCDL] Replacing invalid existing file only after verified staging: %@", path.lastPathComponent);
        }
    } else if (![self checkAccessWithDialog:YES]) {
        return nil;
    }

    [self mc_recordStageFileStartedAtPath:path];
    NSUInteger fileSize = size > 0 ? size : 1;
    @synchronized (self) {
        self.progress.totalUnitCount += fileSize;
        self.textProgress.totalUnitCount = self.progress.totalUnitCount;
    }

    MCDownloadItem *item = [MCDownloadItem new];
    item.url = url;
    item.size = size;
    item.sha = sha;
    item.altName = altName;
    item.toPath = path;
    item.retryCount = 0;
    item.success = success;
    return item;
}

- (NSArray *)downloadClientLibraries {
    NSMutableArray *tasks = [NSMutableArray new];
    for (NSDictionary *library in self.metadata[@"libraries"]) {
        @autoreleasepool {
        NSString *name = library[@"name"];

        NSMutableDictionary *artifact = library[@"downloads"][@"artifact"];
        if (artifact == nil && [name containsString:@":"]) {
            NSLog(@"[MCDL] Unknown artifact object for %@, attempting to generate one", name);
            artifact = [[NSMutableDictionary alloc] init];
            NSString *prefix = library[@"url"] == nil ? @"https://libraries.minecraft.net/" : [library[@"url"] stringByReplacingOccurrencesOfString:@"http://" withString:@"https://"];
            NSArray *libParts = [name componentsSeparatedByString:@":"];
            // ★ [DEMINE] Previously indexed libParts[2] directly; if name had only one colon (two segments, not a standard
            //   three-part Maven coordinate), this caused an out-of-bounds NSRangeException and crashed the app.
            //   Skip libraries with missing segments (do not generate an artifact).
            if (libParts.count < 3) {
                NSLog(@"[DEMINE] skip artifact generation for non-3-part lib name: %@", name);
                continue;
            }
            artifact[@"path"] = [NSString stringWithFormat:@"%1$@/%2$@/%3$@/%2$@-%3$@.jar", [libParts[0] stringByReplacingOccurrencesOfString:@"." withString:@"/"], libParts[1], libParts[2]];
            artifact[@"url"] = [NSString stringWithFormat:@"%@%@", prefix, artifact[@"path"]];
            artifact[@"sha1"] = library[@"checksums"][0];
        }

        NSString *path = [NSString stringWithFormat:@"%s/libraries/%@", getenv("POJAV_GAME_DIR"), artifact[@"path"]];
        NSString *sha = artifact[@"sha1"];
        NSUInteger size = [artifact[@"size"] unsignedLongLongValue];
        NSString *url = artifact[@"url"];
        if ([library[@"skip"] boolValue]) {
            NSLog(@"[MDCL] Skipped library %@", name);
            continue;
        }

        MCDownloadItem *item = [self queueOrVerifyItemWithURL:url size:size sha:sha altName:name toPath:path success:nil];
        if (item) {
            [tasks addObject:item];
        } else if (self.progress.cancelled) {
            return nil;
        }
        } // @autoreleasepool
    }
    return tasks;
}

- (NSArray *)downloadClientAssets {
    NSMutableArray *tasks = [NSMutableArray new];
    NSDictionary *assets = self.metadata[@"assetIndexObj"];
    if (!assets) {
        return @[];
    }
    for (NSString *name in assets[@"objects"]) {
        @autoreleasepool {
        NSDictionary *object = assets[@"objects"][name];
        NSString *hash = object[@"hash"];
        NSString *pathname = [NSString stringWithFormat:@"%@/%@", [hash substringToIndex:2], hash];
        NSUInteger size = [object[@"size"] unsignedLongLongValue];

        NSString *path;
        if ([assets[@"map_to_resources"] boolValue]) {
            path = [NSString stringWithFormat:@"%s/resources/%@", getenv("POJAV_GAME_DIR"), name];
        } else {
            path = [NSString stringWithFormat:@"%s/assets/objects/%@", getenv("POJAV_GAME_DIR"), pathname];
        }

        /* Special case for 1.19+
         * Since 1.19-pre1, setting the window icon on macOS invokes ObjC.
         * However, if an IOException occurs, it won't try to set.
         * We skip downloading the icon file to workaround this. */
        if ([name hasSuffix:@"/minecraft.icns"]) {
            [NSFileManager.defaultManager removeItemAtPath:path error:nil];
            continue;
        }

        NSString *url = [NSString stringWithFormat:@"https://resources.download.minecraft.net/%@", pathname];
        MCDownloadItem *item = [self queueOrVerifyItemWithURL:url size:size sha:hash altName:name toPath:path success:nil];
        if (item) {
            [tasks addObject:item];
        } else if (self.progress.cancelled) {
            return nil;
        }
        } // @autoreleasepool
    }
    return tasks;
}

- (void)downloadVersion:(NSDictionary *)version {
    self.currentVersionId = version[@"id"];
    self.stageReportingEnabled = YES;
    [self prepareForDownload];

    // ===== Initialize stage reporting (redesign-download-ui Phase 3 Task 3.1) =====
    // Six vanilla-install stages: fetch version manifest → download version JSON → download client → download libraries → download assets → verify integrity.
    DownloadTaskManager *manager = [DownloadTaskManager sharedManager];
    NSString *taskId = self.currentDownloadTaskItem.taskId;
    [manager setTaskWithId:taskId stages:PLTaskStagesVanilla()];
    self.currentDownloadTaskItem.autoPresentDetail = YES;
    // Stage 0, version manifest: the caller (version list/preinstall flow) provides the parsed version object; mark complete directly.
    [manager updateTaskWithId:taskId stageAtIndex:kMCStageIndexFetchManifest status:PLTaskStageStatusCompleted];
    // ★ [158-FIX] Do not unconditionally mark stage 2, "Download client," as Skipped.
    //   The client JAR is added by tweakVersionJson as a pseudo-library entry
    //   (path=../versions/<id>/<id>.jar) and actually downloads during the "Download libraries" stage.
    //   The old code always marked it Skipped, so the UI always rendered ⊖ (PLTaskProgressViewController
    //   displays Skipped as minus.circle), which looked like "never downloaded / always -" (issue #158).
    //   After receiving the version JSON, determine Running / Skipped based on whether downloads.client exists
    //   (see the success block in downloadVersionMetadata below).
    // Stage 1, downloading version JSON (progress is indeterminate; the JSON is small, so a percentage is unnecessary).
    [manager updateTaskWithId:taskId stageAtIndex:kMCStageIndexVersionJSON status:PLTaskStageStatusRunning];
    [manager updateTaskWithId:taskId stageAtIndex:kMCStageIndexVersionJSON progress:-1 message:nil];
    [manager updateTaskWithId:taskId currentStageIndex:kMCStageIndexVersionJSON];

    __weak MinecraftResourceDownloadTask *weakSelf = self;
    [self downloadVersionMetadata:version success:^{
        __strong MinecraftResourceDownloadTask *strongSelf = weakSelf;
        if (!strongSelf) return;
        [manager updateTaskWithId:taskId stageAtIndex:kMCStageIndexVersionJSON status:PLTaskStageStatusCompleted];
        // ★ [158-FIX] Stage 2, "Download client": mark as in progress when the version has downloads.client (as vanilla/26.x versions do).
        //   client.jar is added by tweakVersionJson as a pseudo-library entry and is downloaded during the "Download libraries"
        //   stage. The finalization loop (mc_finishAllStagesWithFailure:nil changes Running → Completed) then marks it complete.
        //   Keep it Skipped only when the version JSON truly has no client download information (e.g. an inheritsFrom skeleton version).
        //   This prevents "Download client" from staying at ⊖ indefinitely (issue #158's "always -").
        if (strongSelf.metadata[@"downloads"][@"client"] != nil) {
            [manager updateTaskWithId:taskId stageAtIndex:kMCStageIndexDownloadClient status:PLTaskStageStatusRunning];
            [manager updateTaskWithId:taskId stageAtIndex:kMCStageIndexDownloadClient progress:-1 message:nil];
        } else {
            [manager updateTaskWithId:taskId stageAtIndex:kMCStageIndexDownloadClient status:PLTaskStageStatusSkipped];
        }
        [strongSelf downloadAssetMetadataWithSuccess:^{
            NSArray *libTasks = [strongSelf downloadClientLibraries];
            NSArray *assetTasks = [strongSelf downloadClientAssets];
            // Drop the 1 byte we set initially
            strongSelf.progress.totalUnitCount--;
            strongSelf.textProgress.totalUnitCount--;
            if (strongSelf.progress.totalUnitCount == 0) {
                // We have nothing to download, invoke completion observer
                strongSelf.progress.totalUnitCount = 1;
                strongSelf.progress.completedUnitCount = 1;
                strongSelf.textProgress.totalUnitCount = 1;
                strongSelf.textProgress.completedUnitCount = 1;
                return;
            }
            // Stages 3/4: download libraries and assets concurrently (indeterminate progress; advance using dual file counts).
            [manager updateTaskWithId:taskId stageAtIndex:kMCStageIndexLibraries status:PLTaskStageStatusRunning];
            [manager updateTaskWithId:taskId stageAtIndex:kMCStageIndexAssets status:PLTaskStageStatusRunning];
            [manager updateTaskWithId:taskId stageAtIndex:kMCStageIndexLibraries progress:-1 message:nil];
            [manager updateTaskWithId:taskId stageAtIndex:kMCStageIndexAssets progress:-1 message:nil];
            [manager updateTaskWithId:taskId currentStageIndex:kMCStageIndexLibraries];
            [strongSelf mc_reportStageFileCounts];
            [strongSelf enqueueDownloadTasks:libTasks];
            [strongSelf enqueueDownloadTasks:assetTasks];
            [strongSelf.metadata removeObjectForKey:@"assetIndexObj"];

            if (strongSelf.currentDownloadTaskItem) {
                [[DownloadTaskManager sharedManager] setTaskWithId:strongSelf.currentDownloadTaskItem.taskId
                                                              state:DownloadTaskStateDownloading];
            }
        }];
    }];
}

#pragma mark - Modpack installation

- (void)downloadModpackFromAPI:(ModpackAPI *)api detail:(NSDictionary *)modDetail atIndex:(NSUInteger)selectedVersion {
    self.stageReportingEnabled = NO; // ModpackImportService reports modpack stages (Phase 5).
    // Task 5.10: display the ZIP download stage as a modpack (name/type/icon);
    // ModpackImportService registers the six-stage main modpack task for the import stage.
    NSString *title = [modDetail[@"title"] isKindOfClass:[NSString class]] ? modDetail[@"title"] : nil;
    self.currentVersionId = title.length > 0 ? title : localize(@"i18n_str_118", nil);
    [self prepareForDownload];
    if (self.currentDownloadTaskItem) {
        self.currentDownloadTaskItem.resourceType = DownloadTaskResourceTypeModpack;
        NSString *iconURL = [modDetail[@"imageUrl"] isKindOfClass:[NSString class]] ? modDetail[@"imageUrl"] : nil;
        self.currentDownloadTaskItem.iconURL = iconURL.length > 0 ? iconURL : nil;
    }

    NSString *url = modDetail[@"versionUrls"][selectedVersion];
    NSUInteger size = [modDetail[@"versionSizes"][selectedVersion] unsignedLongLongValue];
    NSString *sha = modDetail[@"versionHashes"][selectedVersion];
    NSString *name = [[modDetail[@"title"] lowercaseString] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
    name = [name stringByReplacingOccurrencesOfString:@" " withString:@"_"];
    NSString *packagePath = [NSTemporaryDirectory() stringByAppendingFormat:@"/%@.zip", name];

    NSURLSessionDownloadTask *task = [self createDownloadTask:url size:size sha:sha altName:nil toPath:packagePath success:^{
        // Task 5.10: unify the online modpack download path. After the ZIP download completes, reuse ModpackImportService's
        // unified import flow (parse → six-stage main task → extract/dependency downloads/loader/game files/profile),
        // removing the parallel ModrinthAPI/CurseForgeAPI submitDownloadTasksFromPackage: logic.
        [self importDownloadedModpackPackage:packagePath];
    }];
    [task resume];
}

/// Task 5.10: Unified import entry point after an online modpack ZIP download completes.
///   1. Parse the ZIP with ModpackImportService (recognizes Modrinth/CurseForge/MMC/MCBBS/plain ZIP formats).
///   2. On parse failure, call finishDownloadWithErrorString: (mark task failed, show alert, restore UI).
///   3. On success, finalize the ZIP download task (fill parent progress → KVO marks task complete →
///      LauncherNavigationController removes its observer and restores interaction), then run importModpack: in the background.
///      The service registers the six-stage main modpack task (autoPresentDetail automatically presents the unified progress page).
- (void)importDownloadedModpackPackage:(NSString *)packagePath {
    ModpackImportService *service = [[ModpackImportService alloc] init];
    [service resetCancelState];

    NSError *parseError = nil;
    NSDictionary *modpackInfo = [service parseModpackAtURL:[NSURL fileURLWithPath:packagePath] error:&parseError];
    if (!modpackInfo) {
        [self finishDownloadWithErrorString:[NSString stringWithFormat:@"Failed to parse modpack package: %@",
                                             parseError.localizedDescription ?: @"unknown error"]];
        return;
    }

    // Add the API icon for online modpacks: use the list icon if the ZIP has no icon
    // (ModpackInstallViewController writes tmp icon.png before starting the download).
    NSMutableDictionary *info = [modpackInfo mutableCopy];
    NSString *archiveIcon = info[@"iconBase64"];
    if (![archiveIcon isKindOfClass:[NSString class]] || archiveIcon.length == 0) {
        NSString *tmpIconPath = [NSTemporaryDirectory() stringByAppendingPathComponent:@"icon.png"];
        NSData *iconData = [NSData dataWithContentsOfFile:tmpIconPath];
        if (iconData.length > 0) {
            info[@"iconBase64"] = [NSString stringWithFormat:@"data:image/png;base64,%@",
                                   [iconData base64EncodedStringWithOptions:0]];
        }
    }

    // Finalize the ZIP download task: fill the parent progress (clears the one-byte unit reserved by prepareForDownload).
    // The KVO completion branch marks DownloadTaskItem complete, and LauncherNavigationController restores interaction;
    // all subsequent import progress is handled by the service's main modpack task (unified progress page).
    if (self.progress.totalUnitCount > self.progress.completedUnitCount) {
        self.progress.completedUnitCount = self.progress.totalUnitCount;
    }

    // Run the unified import in the background (six-stage progress reporting + autoPresentDetail unified progress page).
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSError *importError = nil;
        BOOL success = [service importModpack:info progress:nil error:&importError];
        if (success) {
            NSLog(@"[ModpackImport] Online modpack '%@' imported", info[@"name"]);
        } else {
            NSLog(@"[ModpackImport] Online modpack import failed: %@", importError.localizedDescription);
        }
        // Clean up the temporary ZIP file after import finishes (success/failure/cancellation).
        [NSFileManager.defaultManager removeItemAtPath:packagePath error:nil];
        // Refresh the profile list on success (same as the ReloadProfileList notification after Fabric/Forge installation).
        if (success) {
            [[NSNotificationCenter defaultCenter] postNotificationName:@"ReloadProfileList" object:nil];
        }
    });
}

#pragma mark - Utilities

- (void)prepareForDownload {
    // Clear leftover download tasks from the previous run on the singleton session (required for a foreground singleton session,
    // otherwise a task left behind by a previous failure/cancellation may affect new downloads).
    // Do not invalidate the singleton session (that would break all subsequent downloads); cancel tasks only.
    NSString *oldTaskId = self.currentDownloadTaskItem.taskId;
    if (oldTaskId.length > 0) {
        [self.manager.session getTasksWithCompletionHandler:^(NSArray<NSURLSessionDataTask *> *dataTasks,
                                                              NSArray<NSURLSessionUploadTask *> *uploadTasks,
                                                              NSArray<NSURLSessionDownloadTask *> *downloadTasks) {
            for (NSURLSessionDownloadTask *dt in downloadTasks) {
                if ([dt.taskDescription isEqualToString:oldTaskId]) {
                    [dt cancel];
                }
            }
        }];
    }

    // Create a fake progress which is used to update completedUnitCount properly
    // (completedUnitCount does not update unless subprogress completes)
    self.textProgress = [NSProgress new];
    self.textProgress.kind = NSProgressKindFile;
    self.textProgress.fileOperationKind = NSProgressFileOperationKindDownloading;
    self.textProgress.totalUnitCount = -1;

    self.progress = [NSProgress new];
    // Push 1 byte so it won't accidentally finish after downloading assets index
    self.progress.totalUnitCount = 1;
    @synchronized (self) {
        [self.itemQueue removeAllObjects];
        [self.taskQueue removeAllObjects];
        self.runningTasksCount = 0;
        [self.fileList removeAllObjects];
        [self.progressList removeAllObjects];
        // Phase 5 fix: reset the failed-file list (based on FCL).
        [self.failedFiles removeAllObjects];
    }
    // Reset stage counts (each entry point sets stageReportingEnabled itself:
    // downloadVersion: sets YES; downloadModpackFromAPI: sets NO).
    self.libTotalFileCount = 0;
    self.libCompletedFileCount = 0;
    self.assetTotalFileCount = 0;
    self.assetCompletedFileCount = 0;

    // Register/update with the unified download task manager.
    [self registerOrUpdateTaskItem];

    // Observe overall progress.
    if (!self.isObservingTaskProgress) {
        [self.progress addObserver:self
                        forKeyPath:@"fractionCompleted"
                           options:NSKeyValueObservingOptionInitial
                           context:(void *)@"MCDownloadProgressContext"];
        self.isObservingTaskProgress = YES;
        self.progressLastTime = 0;
        self.progressLastCompleted = 0;
    }
}

- (void)registerOrUpdateTaskItem {
    // The floating bubble has been removed; always register with the unified download task manager so the download list can track tasks.
    NSString *displayName = self.currentVersionId ?: (self.metadata[@"id"] ?: @"Minecraft");
    NSString *downloadSource = getPrefObject(@"general.download_source") ?: @"official";

    if (!self.currentDownloadTaskItem) {
        self.currentDownloadTaskItem = [[DownloadTaskManager sharedManager]
            registerTaskWithResourceType:DownloadTaskResourceTypeMinecraft
                            resourceName:displayName
                             displayName:displayName
                          downloadSource:downloadSource
                                 rawTask:self
                          supportsResume:NO
                                 iconURL:nil];
    } else {
        self.currentDownloadTaskItem.resourceName = displayName;
        self.currentDownloadTaskItem.displayName = displayName;
        self.currentDownloadTaskItem.downloadSource = downloadSource;
        self.currentDownloadTaskItem.rawTask = self;
        self.currentDownloadTaskItem.supportsResume = NO;
        self.currentDownloadTaskItem.state = DownloadTaskStatePending;
        self.currentDownloadTaskItem.progress = -1.0;
        self.currentDownloadTaskItem.errorInfo = nil;
    }
}

#pragma mark - Stage Reporting Helpers (redesign-download-ui Phase 3 Task 3.1)

/// Classifies by destination path and adds to the stage file total (libraries/assets; version JSON is excluded).
- (void)mc_recordStageFileStartedAtPath:(NSString *)path {
    if (!self.stageReportingEnabled) return;
    @synchronized (self) {
        if ([path containsString:@"/libraries/"]) {
            self.libTotalFileCount++;
        } else if ([path containsString:@"/assets/"] || [path containsString:@"/resources/"]) {
            self.assetTotalFileCount++;
        } else {
            return; // Version JSON and asset indexes under versions/ belong to the stage 1/4 JSON downloads; exclude from dual counts.
        }
    }
    [self mc_reportStageFileCounts];
}

/// Counts a file toward the stage completion total when it reaches a terminal state (skipped/succeeded/ultimately failed).
- (void)mc_recordStageFileFinishedAtPath:(NSString *)path {
    if (!self.stageReportingEnabled) return;
    @synchronized (self) {
        if ([path containsString:@"/libraries/"]) {
            self.libCompletedFileCount++;
        } else if ([path containsString:@"/assets/"] || [path containsString:@"/resources/"]) {
            self.assetCompletedFileCount++;
        } else {
            return;
        }
    }
    [self mc_reportStageFileCounts];
}

/// Reports the dual file counts for library/asset stages.
- (void)mc_reportStageFileCounts {
    if (!self.stageReportingEnabled || !self.currentDownloadTaskItem) return;
    NSString *taskId = self.currentDownloadTaskItem.taskId;
    DownloadTaskManager *manager = [DownloadTaskManager sharedManager];
    [manager updateTaskWithId:taskId
                stageAtIndex:kMCStageIndexLibraries
                   fileCount:self.libCompletedFileCount
               totalFileCount:self.libTotalFileCount];
    [manager updateTaskWithId:taskId
                stageAtIndex:kMCStageIndexAssets
                   fileCount:self.assetCompletedFileCount
               totalFileCount:self.assetTotalFileCount];
}

/// Finalizes all stage states: if error is nil, mark all Completed (the validation stage transitions through Running first);
/// otherwise mark the current stage Failed with the error, leaving subsequent stages Pending.
- (void)mc_finishAllStagesWithFailure:(nullable NSString *)error {
    if (!self.stageReportingEnabled || !self.currentDownloadTaskItem) return;
    NSString *taskId = self.currentDownloadTaskItem.taskId;
    DownloadTaskManager *manager = [DownloadTaskManager sharedManager];
    NSInteger idx = self.currentDownloadTaskItem.currentStageIndex;

    if (error != nil) {
        // Failure: current stage is Failed + message; completed stages remain unchanged.
        if (idx >= 0 && (NSUInteger)idx < self.currentDownloadTaskItem.stages.count) {
            [manager updateTaskWithId:taskId
                         stageAtIndex:(NSUInteger)idx
                               status:PLTaskStageStatusFailed];
            [manager updateTaskWithId:taskId
                         stageAtIndex:(NSUInteger)idx
                              progress:0
                                message:error];
        }
        return;
    }

    // Success: mark all incomplete stages complete (leave Download client as Skipped).
    NSArray<PLTaskStage *> *stages = self.currentDownloadTaskItem.stages;
    for (NSUInteger i = 0; i < stages.count; i++) {
        if (stages[i].status == PLTaskStageStatusPending || stages[i].status == PLTaskStageStatusRunning) {
            [manager updateTaskWithId:taskId stageAtIndex:i status:PLTaskStageStatusCompleted];
        }
    }
    // Verify integrity: SHA1 checks run as each file completes, so advance quickly.
    [manager updateTaskWithId:taskId stageAtIndex:kMCStageIndexVerify status:PLTaskStageStatusRunning];
    [manager updateTaskWithId:taskId stageAtIndex:kMCStageIndexVerify progress:1 message:nil];
    [manager updateTaskWithId:taskId stageAtIndex:kMCStageIndexVerify status:PLTaskStageStatusCompleted];
    [manager updateTaskWithId:taskId currentStageIndex:kMCStageIndexVerify];
    self.stageReportingEnabled = NO;
}

- (void)cancel {
    @synchronized (self) {
        [self.itemQueue removeAllObjects];
        [self.taskQueue removeAllObjects];
        self.runningTasksCount = 0;
    }
    // Cancel the root NSProgress: all child task progress is cancelled recursively, and the KVO cancelled branch handles cleanup as before.
    [self.progress cancel];
}

- (void)finishDownloadWithErrorString:(NSString *)error {
    // Stage reporting: mark the current stage Failed when the overall flow fails.
    if (self.stageReportingEnabled) {
        [self mc_finishAllStagesWithFailure:error ?: localize(@"i18n_str_448", nil)];
    }
    if (self.currentDownloadTaskItem && self.currentDownloadTaskItem.state != DownloadTaskStateCancelled) {
        NSError *err = [NSError errorWithDomain:@"MinecraftResourceDownloadTask"
                                           code:1
                                       userInfo:@{NSLocalizedDescriptionKey: error ?: localize(@"i18n_str_448", nil)}];
        [[DownloadTaskManager sharedManager] setTaskWithId:self.currentDownloadTaskItem.taskId
                                          completedWithError:err];
    }

    [self.progress cancel];

    // Cancel all background downloads belonging to this task to avoid wasting bandwidth after failure.
    NSString *taskId = self.currentDownloadTaskItem.taskId;
    [self.manager.session getTasksWithCompletionHandler:^(NSArray<NSURLSessionDataTask *> *dataTasks,
                                                          NSArray<NSURLSessionUploadTask *> *uploadTasks,
                                                          NSArray<NSURLSessionDownloadTask *> *downloadTasks) {
        for (NSURLSessionDownloadTask *downloadTask in downloadTasks) {
            if (taskId.length > 0 && [downloadTask.taskDescription isEqualToString:taskId]) {
                [downloadTask cancel];
            }
        }
    }];

    showDialog(localize(@"Error", nil), error);
    self.handleError();
}

- (void)finishDownloadWithError:(NSError *)error file:(NSString *)file {
    NSString *errorStr = [NSString stringWithFormat:localize(@"launcher.mcl.error_download", NULL), file, error.localizedDescription];
    NSLog(@"[MCDL] Error: %@ %@", errorStr, NSThread.callStackSymbols);

    // Phase 5 fix (based on FCL): a single-file download failure no longer cancels the entire task.
    //
    // Previously, calling finishDownloadWithErrorString: would:
    //   1. Cancel all downloads with the same taskId (including other files currently downloading).
    //   2. Show an error dialog and interrupt the entire download flow.
    //   3. Leave the modpack incomplete — users reported incorrect mod names and incomplete downloads.
    //
    // FCL's approach records individual failures in failedFiles and continues downloading other files,
    // then reports a summary to the user. This matches FCL's design that a single-file failure does not affect other files.
    //
    // This recovery strategy applies only to multi-file modpack downloads. Single-version downloads (downloadVersion:)
    // should not reach this method (their completionHandler has its own error path). If one does, finishDownloadWithErrorString:
    // is not triggered when failedFiles.count == 0, preserving the original behavior.
    @synchronized(self.failedFiles) {
        [self.failedFiles addObject:@{
            @"name": file ?: @"unknown",
            @"error": error.localizedDescription ?: @"unknown error"
        }];
    }
    NSLog(@"[MCDL] File '%@' added to failedFiles (total failed: %lu), other downloads will continue",
          file, (unsigned long)self.failedFiles.count);
}

#pragma mark - Download Task Manager Reporting

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary<NSKeyValueChangeKey,id> *)change context:(void *)context {
    if (context != (void *)@"MCDownloadProgressContext") {
        [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
        return;
    }

    if (![keyPath isEqualToString:@"fractionCompleted"] || !self.currentDownloadTaskItem) return;

    NSProgress *progress = self.progress;
    double fraction = progress.fractionCompleted;
    int64_t total = progress.totalUnitCount;
    int64_t completed = (int64_t)(total * fraction);

    // Speed / estimated time remaining (calculated once per second).
    struct timeval tv;
    gettimeofday(&tv, NULL);
    NSTimeInterval now = tv.tv_sec + tv.tv_usec / 1000000.0;
    double speed = 0.0;
    NSTimeInterval eta = 0.0;

    if (self.progressLastTime > 0 && now > self.progressLastTime) {
        int64_t delta = completed - self.progressLastCompleted;
        NSTimeInterval timeDelta = now - self.progressLastTime;
        if (timeDelta > 0) {
            speed = (double)delta / timeDelta;
            if (speed > 0 && total > completed) {
                eta = (total - completed) / speed;
            }
        }
    }

    if (self.progressLastTime == 0 || now >= self.progressLastTime + 1.0) {
        self.progressLastTime = now;
        self.progressLastCompleted = completed;
    }

    // Throttle intermediate UI updates to at most 4 times a second (250ms), preventing lock contention and UI freeze
    if (!progress.finished && !progress.cancelled) {
        if (self.lastUIReportTime > 0 && (now - self.lastUIReportTime) < 0.25) {
            return;
        }
    }
    self.lastUIReportTime = now;

    DownloadTaskManager *manager = [DownloadTaskManager sharedManager];
    [manager updateTaskWithId:self.currentDownloadTaskItem.taskId
                     progress:fraction
                   totalBytes:total
              downloadedBytes:completed];
    [manager updateTaskWithId:self.currentDownloadTaskItem.taskId
                        speed:speed
       estimatedTimeRemaining:eta];

    // Stage reporting: concurrent library/asset stages share the global rate (indeterminate progress, advanced by file counts).
    if (self.stageReportingEnabled && self.currentDownloadTaskItem.stages.count > kMCStageIndexAssets) {
        [manager updateTaskWithId:self.currentDownloadTaskItem.taskId
                    stageAtIndex:kMCStageIndexLibraries
                            rate:speed];
        [manager updateTaskWithId:self.currentDownloadTaskItem.taskId
                    stageAtIndex:kMCStageIndexAssets
                            rate:speed];
    }

    if (progress.cancelled) {
        if (self.currentDownloadTaskItem.state != DownloadTaskStateCancelled &&
            self.currentDownloadTaskItem.state != DownloadTaskStateCompleted &&
            self.currentDownloadTaskItem.state != DownloadTaskStateFailed) {
            [manager setTaskWithId:self.currentDownloadTaskItem.taskId state:DownloadTaskStateCancelled];
        }
        [self removeProgressObserver];
        return;
    }

    if (progress.finished) {
        // Stage reporting: finalize — library/asset stages are complete; quickly advance and complete the integrity-validation stage.
        // (SHA1 validation is embedded in each file's download completion callback; this only finalizes stage states.)
        if (self.stageReportingEnabled) {
            [self mc_finishAllStagesWithFailure:nil];
        }
        if (self.currentDownloadTaskItem.state != DownloadTaskStateCompleted &&
            self.currentDownloadTaskItem.state != DownloadTaskStateFailed &&
            self.currentDownloadTaskItem.state != DownloadTaskStateCancelled) {
            // Phase 5 fix (based on FCL DownloadList.finishAll): after the download flow ends,
            // do not simply mark it "successfully completed" if there are failed files — users would think the modpack is complete.
            // Aggregate failed-file details into an NSError so DownloadTaskManager shows a failed status,
            // and users can see exactly which files are missing in the download task list.
            NSArray<NSDictionary *> *failedSnapshot = [self.failedFiles copy];
            if (failedSnapshot.count > 0) {
                NSMutableString *msg = [NSMutableString stringWithFormat:localize(@"i18n_str_449", nil), (unsigned long)failedSnapshot.count];
                NSUInteger showCount = MIN(failedSnapshot.count, (NSUInteger)5);
                for (NSUInteger k = 0; k < showCount; k++) {
                    NSString *n = failedSnapshot[k][@"name"];
                    [msg appendFormat:@"\n  • %@", n ?: @"(unknown)"];
                }
                if (failedSnapshot.count > showCount) {
                    [msg appendFormat:localize(@"i18n_str_450", nil), (unsigned long)failedSnapshot.count];
                }
                NSLog(@"[MCDL] %@", msg);
                NSError *partialError = [NSError errorWithDomain:@"MinecraftResourceDownloadTask"
                                                            code:2
                                                        userInfo:@{
                                                            NSLocalizedDescriptionKey: [msg copy],
                                                            @"failedFiles": failedSnapshot
                                                        }];
                [manager setTaskWithId:self.currentDownloadTaskItem.taskId completedWithError:partialError];
            } else {
                [manager setTaskWithId:self.currentDownloadTaskItem.taskId completedWithError:nil];
            }
        }
        [self removeProgressObserver];
    }
}

- (void)removeProgressObserver {
    if (self.isObservingTaskProgress) {
        @try {
            [self.progress removeObserver:self forKeyPath:@"fractionCompleted"];
        } @catch (NSException *exception) {
            // ignore
        }
        self.isObservingTaskProgress = NO;
    }
}

// Key change: remove the local-account download restriction and warning.
- (BOOL)checkAccessWithDialog:(BOOL)show {
    // Allow all download requests unconditionally.
    return YES;
}

// Check SHA of the file
- (BOOL)checkSHAIgnorePref:(NSString *)sha forFile:(NSString *)path altName:(NSString *)altName logSuccess:(BOOL)logSuccess {
    @autoreleasepool {
        if (sha.length == 0) {
            // When sha = skip, only check for file existence
            BOOL existence = [NSFileManager.defaultManager fileExistsAtPath:path];
            if (existence) {
                NSLog(@"[MCDL] Warning: couldn't find SHA for %@, have to assume it's good.", path);
            }
            return existence;
        }

        NSData *data = [NSData dataWithContentsOfFile:path options:NSDataReadingMappedIfSafe error:nil];
        if (data == nil) {
            NSLog(@"[MCDL] SHA1 checker: file doesn't exist: %@", altName ? altName : path.lastPathComponent);
            return NO;
        }

        unsigned char digest[CC_SHA1_DIGEST_LENGTH];
        CC_SHA1(data.bytes, (CC_LONG)data.length, digest);
        NSMutableString *localSHA = [NSMutableString stringWithCapacity:CC_SHA1_DIGEST_LENGTH * 2];
        for(int i = 0; i < CC_SHA1_DIGEST_LENGTH; i++) {
            [localSHA appendFormat:@"%02x", digest[i]];
        }

        BOOL check = [sha isEqualToString:localSHA];
        if (!check || (getPrefBool(@"general.debug_logging") && logSuccess)) {
            NSLog(@"[MCDL] SHA1 %@ for %@%@",
              (check ? @"passed" : @"failed"), 
              (altName ? altName : path.lastPathComponent),
              (check ? @"" : [NSString stringWithFormat:@" (expected: %@, got: %@)", sha, localSHA]));
        }
        return check;
    }
}

- (BOOL)checkSHA:(NSString *)sha forFile:(NSString *)path altName:(NSString *)altName logSuccess:(BOOL)logSuccess {
    if (getPrefBool(@"general.check_sha")) {
        return [self checkSHAIgnorePref:sha forFile:path altName:altName logSuccess:logSuccess];
    } else {
        // Check not only that the file exists, but also that its size is > 0 (to avoid treating empty files as downloaded).
        // Fix: if a file was incorrectly created with 0 bytes during a vanilla install, it was treated as downloaded,
        //   causing totalUnitCount to go from 1 to 0 and triggering forced completion (a zero-byte download).
        if (![NSFileManager.defaultManager fileExistsAtPath:path]) return NO;
        NSDictionary *attrs = [NSFileManager.defaultManager attributesOfItemAtPath:path error:nil];
        unsigned long long fileSize = [attrs fileSize];
        return fileSize > 0;
    }
}

- (BOOL)checkSHA:(NSString *)sha forFile:(NSString *)path altName:(NSString *)altName {
    return [self checkSHA:sha forFile:path altName:altName logSuccess:altName==nil];
}

@end
