#import "utils.h"
//
//  DataPackService.m
//  Amethyst
//
//  Data-pack service implementation, structured like ShaderService/ModService.
//  API signatures consistently use NSString *profileName.
//  File downloads now use the shared PLDownloadClient (mirror candidates + SHA1 validation +
//  incremental download + resume support), removing the custom NSURLSession download delegate
//  (spec optimize-download-system Task 4.2 / 5.1 / 5.2).
//  Parses pack.mcmeta (pack_format / description).
//  Supports the worldName parameter to download to a specific world's datapacks directory.
//

#import "DataPackService.h"
#import <CommonCrypto/CommonCrypto.h>
#import <UIKit/UIKit.h>
#import "PLProfiles.h"
#import "DataPackItem.h"
#import "UZKArchive.h"
#import "DownloadTaskManager.h"
#import "DownloadTaskItem.h"
#import "PLTaskStages.h"
#import "LauncherPreferences.h"
#import "PLDownloadClient.h"
#import "PLMirrorCenter.h"

@interface DataPackService ()
// ---- PLDownloadClient download tracking (key = DownloadTaskItem.taskId, i.e. PLDownloadRequest.taskIdentifier) ----
@property (nonatomic, strong) NSLock *downloadStateLock;
@property (nonatomic, strong) NSMutableDictionary<NSString *, DownloadTaskItem *> *downloadTaskItems;
// Strongly retain the current operation: PLDownloadClient removes its internal task mapping after
// pause, so the Service must keep it alive for DownloadTaskManager's rawTask (weak) to continue
// supporting pause/resume.
@property (nonatomic, strong) NSMutableDictionary<NSString *, PLDownloadOperation *> *downloadOperations;
// Retry generation: discard late callbacks (such as cancellation) from the old operation after
// retryHandler creates a new request.
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSNumber *> *downloadGenerations;
// Accumulated progress (PLDownloadClient reports deltas, including negative deltas when reverting
// for mirror switches/retries; simply accumulate them).
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSNumber *> *downloadAccumulatedBytes;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSNumber *> *downloadTotalBytes;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSNumber *> *downloadLastSpeeds;
// Cached request description: retryHandler reuses the same request (a shared taskIdentifier can
// reuse resume-data semantics).
@property (nonatomic, strong) NSMutableDictionary<NSString *, PLDownloadRequest *> *downloadRequests;
@property (nonatomic, strong) NSMutableDictionary<NSString *, DataPackDownloadProgressHandler> *downloadProgressHandlers;
@property (nonatomic, strong) NSMutableDictionary<NSString *, DataPackDownloadCompletionHandler> *downloadCompletionHandlers;
@end

@implementation DataPackService

+ (instancetype)sharedService {
    static DataPackService *s;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        s = [[DataPackService alloc] init];
    });
    return s;
}

- (instancetype)init {
    if (self = [super init]) {
        _onlineSearchEnabled = NO;

        // Downloads now use [PLDownloadClient sharedClient] (mirror candidates + SHA1 validation + resume
        // support); no custom NSURLSession download delegate.
        _downloadStateLock = [[NSLock alloc] init];
        _downloadTaskItems = [NSMutableDictionary dictionary];
        _downloadOperations = [NSMutableDictionary dictionary];
        _downloadGenerations = [NSMutableDictionary dictionary];
        _downloadAccumulatedBytes = [NSMutableDictionary dictionary];
        _downloadTotalBytes = [NSMutableDictionary dictionary];
        _downloadLastSpeeds = [NSMutableDictionary dictionary];
        _downloadRequests = [NSMutableDictionary dictionary];
        _downloadProgressHandlers = [NSMutableDictionary dictionary];
        _downloadCompletionHandlers = [NSMutableDictionary dictionary];
    }
    return self;
}

#pragma mark - Utility methods

// Calculate the SHA1 of a URL string for use as the icon-cache filename.
- (NSString *)iconCachePathForURL:(NSString *)urlString {
    if (!urlString) return nil;
    NSString *cacheDir = [NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES) firstObject];
    NSString *folder = [cacheDir stringByAppendingPathComponent:@"datapack_icons"];
    if (![[NSFileManager defaultManager] fileExistsAtPath:folder]) {
        [[NSFileManager defaultManager] createDirectoryAtPath:folder withIntermediateDirectories:YES attributes:nil error:nil];
    }
    const char *cstr = [urlString UTF8String];
    unsigned char digest[CC_SHA1_DIGEST_LENGTH];
    CC_SHA1(cstr, (CC_LONG)strlen(cstr), digest);
    NSMutableString *hex = [NSMutableString stringWithCapacity:CC_SHA1_DIGEST_LENGTH * 2];
    for (int i = 0; i < CC_SHA1_DIGEST_LENGTH; i++) {
        [hex appendFormat:@"%02x", digest[i]];
    }
    return [folder stringByAppendingPathComponent:hex];
}

// Read the data for a specified entry from a zip file.
- (nullable NSData *)readFileFromZip:(NSString *)zipPath entryName:(NSString *)entryName {
    if (!zipPath || !entryName) return nil;
    NSError *err = nil;
    UZKArchive *archive = [[UZKArchive alloc] initWithPath:zipPath error:&err];
    if (!archive || err) return nil;
    NSData *data = [archive extractDataFromFile:entryName error:&err];
    return data;
}

// Parse pack.mcmeta to extract pack_format and description.
- (void)parsePackMcmetaForItem:(DataPackItem *)item {
    if (!item.filePath) return;
    NSData *mcmetaData = [self readFileFromZip:item.filePath entryName:@"pack.mcmeta"];
    if (!mcmetaData) return;
    NSDictionary *json = [NSJSONSerialization JSONObjectWithData:mcmetaData options:0 error:nil];
    if (![json isKindOfClass:[NSDictionary class]]) return;
    NSDictionary *pack = json[@"pack"];
    if (![pack isKindOfClass:[NSDictionary class]]) return;

    id packFormatValue = pack[@"pack_format"];
    if ([packFormatValue isKindOfClass:[NSNumber class]]) {
        item.packFormat = packFormatValue;
    } else if ([packFormatValue respondsToSelector:@selector(integerValue)]) {
        item.packFormat = @([packFormatValue integerValue]);
    }

    id descValue = pack[@"description"];
    if ([descValue isKindOfClass:[NSString class]]) {
        item.dataPackDescription = descValue;
    } else if ([descValue respondsToSelector:@selector(description)]) {
        item.dataPackDescription = [descValue description];
    }
}

// Resolve the profile's gameDir; return gameDir or nil.
- (nullable NSString *)gameDirForProfile:(NSString *)profileName {
    NSString *profile = profileName.length ? profileName : @"default";
    @try {
        NSDictionary *profiles = PLProfiles.current.profiles;
        NSDictionary *prof = profiles[profile];
        if ([prof isKindOfClass:[NSDictionary class]]) {
            // ★ [VER-ISOLATE-PCL] Unified version-isolation resolution (absolute path).
            NSString *gameDir = amePCLVersionGameDirAbsolute(prof, nil);
            if ([gameDir isKindOfClass:[NSString class]] && gameDir.length > 0) {
                return gameDir;
            }
        }
    } @catch (NSException *ex) { }

    const char *gameDirC = getenv("POJAV_GAME_DIR");
    if (gameDirC) {
        return [NSString stringWithUTF8String:gameDirC];
    }
    return nil;
}

#pragma mark - DataPacks folder detection & scan

// Find the specified profile's datapacks directory (return its path if it exists; otherwise nil).
- (nullable NSString *)existingDataPacksFolderForProfile:(NSString *)profileName {
    NSString *profile = profileName.length ? profileName : @"default";
    NSFileManager *fm = [NSFileManager defaultManager];

    @try {
        NSDictionary *profiles = PLProfiles.current.profiles;
        NSDictionary *prof = profiles[profile];
        if ([prof isKindOfClass:[NSDictionary class]]) {
            // ★ [VER-ISOLATE-PCL] Unified version-isolation resolution (absolute path).
            NSString *gameDir = amePCLVersionGameDirAbsolute(prof, nil);
            if ([gameDir isKindOfClass:[NSString class]] && gameDir.length > 0) {
                NSString *dataPacksPath = [gameDir stringByAppendingPathComponent:@"datapacks"];
                BOOL isDir = NO;
                if ([fm fileExistsAtPath:dataPacksPath isDirectory:&isDir] && isDir) {
                    return dataPacksPath;
                }
            }
        }
    } @catch (NSException *ex) { }

    // Fallback: read the POJAV_GAME_DIR environment variable.
    const char *gameDirC = getenv("POJAV_GAME_DIR");
    if (gameDirC) {
        NSString *gameDir = [NSString stringWithUTF8String:gameDirC];
        NSString *dataPacksPath = [gameDir stringByAppendingPathComponent:@"datapacks"];
        BOOL isDir = NO;
        if ([fm fileExistsAtPath:dataPacksPath isDirectory:&isDir] && isDir) {
            return dataPacksPath;
        }
    }
    return nil;
}

/// Get the current profile's datapacks directory, creating it if it does not exist.
- (nullable NSString *)ensureDataPacksFolderForProfile:(NSString *)profileName error:(NSError **)error {
    NSString *profile = profileName.length ? profileName : @"default";
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *dataPacksPath = nil;

    @try {
        NSDictionary *profiles = PLProfiles.current.profiles;
        NSDictionary *prof = profiles[profile];
        if ([prof isKindOfClass:[NSDictionary class]]) {
            // ★ [VER-ISOLATE-PCL] Unified version-isolation resolution (absolute path).
            NSString *gameDir = amePCLVersionGameDirAbsolute(prof, nil);
            if ([gameDir isKindOfClass:[NSString class]] && gameDir.length > 0) {
                dataPacksPath = [gameDir stringByAppendingPathComponent:@"datapacks"];
            }
        }
    } @catch (NSException *ex) { }

    if (!dataPacksPath) {
        const char *gameDirC = getenv("POJAV_GAME_DIR");
        if (gameDirC) {
            NSString *gameDir = [NSString stringWithUTF8String:gameDirC];
            dataPacksPath = [gameDir stringByAppendingPathComponent:@"datapacks"];
        }
    }

    if (!dataPacksPath) {
        if (error) {
            *error = [NSError errorWithDomain:@"DataPackService" code:1 userInfo:@{NSLocalizedDescriptionKey: localize(@"i18n_str_105", nil)}];
        }
        return nil;
    }

    BOOL isDir = NO;
    if (![fm fileExistsAtPath:dataPacksPath isDirectory:&isDir]) {
        NSError *createError = nil;
        [fm createDirectoryAtPath:dataPacksPath withIntermediateDirectories:YES attributes:nil error:&createError];
        if (createError) {
            if (error) *error = createError;
            return nil;
        }
        NSLog(@"[DataPackService] Created datapacks directory: %@", dataPacksPath);
    } else if (!isDir) {
        if (error) {
            *error = [NSError errorWithDomain:@"DataPackService" code:2 userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"%@ is not a directory", dataPacksPath]}];
        }
        return nil;
    }
    return dataPacksPath;
}

- (void)scanDataPacksForProfile:(NSString *)profileName completion:(DataPackListHandler)completion {
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSString *dataPacksFolder = [self existingDataPacksFolderForProfile:profileName];
        NSMutableArray<DataPackItem *> *items = [NSMutableArray array];

        if (!dataPacksFolder) {
            if (completion) {
                dispatch_async(dispatch_get_main_queue(), ^{ completion(items); });
            }
            return;
        }

        NSArray<NSString *> *contents = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:dataPacksFolder error:nil];
        dispatch_group_t group = dispatch_group_create();

        for (NSString *fileName in contents) {
            if ([fileName.lowercaseString hasSuffix:@".zip"] || [fileName.lowercaseString hasSuffix:@".zip.disabled"]) {
                NSString *fullPath = [dataPacksFolder stringByAppendingPathComponent:fileName];
                DataPackItem *dataPack = [[DataPackItem alloc] initWithFilePath:fullPath];
                [items addObject:dataPack];

                dispatch_group_enter(group);
                [self fetchMetadataForDataPack:dataPack completion:^(DataPackItem *populatedItem, NSError * _Nullable error) {
                    dispatch_group_leave(group);
                }];
            }
        }

        dispatch_group_notify(group, dispatch_get_main_queue(), ^{
            [items sortUsingComparator:^NSComparisonResult(DataPackItem *obj1, DataPackItem *obj2) {
                NSString *name1 = obj1.displayName ?: obj1.fileName;
                NSString *name2 = obj2.displayName ?: obj2.fileName;
                return [name1 localizedCaseInsensitiveCompare:name2];
            }];

            if (completion) {
                completion(items);
            }
        });
    });
}

#pragma mark - Metadata fetch

// Parse pack.mcmeta inside the zip to get pack_format and description.
- (void)fetchMetadataForDataPack:(DataPackItem *)item completion:(DataPackMetadataHandler)completion {
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        @try {
            [self parsePackMcmetaForItem:item];
        } @catch (NSException *exception) {
            NSLog(@"[DataPackService] Exception parsing pack.mcmeta for %@: %@", item.fileName, exception);
        }
        if (completion) completion(item, nil);
    });
}

#pragma mark - File operations

// Enable/disable the data pack by adding/removing the .disabled suffix.
- (BOOL)toggleEnableForDataPack:(DataPackItem *)item error:(NSError **)error {
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSString *currentPath = item.filePath;
    NSString *newPath;

    if (item.disabled) {
        if ([currentPath.lowercaseString hasSuffix:@".zip.disabled"]) {
            newPath = [currentPath substringToIndex:currentPath.length - [@".disabled" length]];
        } else {
            if (error) *error = [NSError errorWithDomain:@"DataPackServiceError" code:101 userInfo:@{NSLocalizedDescriptionKey:@"File state mismatch, cannot enable."}];
            return NO;
        }
    } else {
        newPath = [currentPath stringByAppendingString:@".disabled"];
    }

    BOOL success = [fileManager moveItemAtPath:currentPath toPath:newPath error:error];
    if (success) {
        item.filePath = newPath;
        item.fileName = [newPath lastPathComponent];
        [item refreshDisabledFlag];
    }

    return success;
}

// Delete the data-pack file.
- (BOOL)deleteDataPack:(DataPackItem *)item error:(NSError **)error {
    return [[NSFileManager defaultManager] removeItemAtPath:item.filePath error:error];
}

#pragma mark - Online data-pack downloads (shared PLDownloadClient)

// Download the data pack to the default datapacks directory (no worldName).
- (void)downloadDataPack:(DataPackItem *)item
               toProfile:(NSString *)profileName
                progress:(DataPackDownloadProgressHandler _Nullable)progress
              completion:(DataPackDownloadCompletionHandler _Nullable)completion {
    [self downloadDataPack:item toProfile:profileName worldName:nil expectedSHA1:nil progress:progress completion:completion];
}

// Download the data pack to saves/<worldName>/datapacks/ when worldName is not empty.
- (void)downloadDataPack:(DataPackItem *)item
               toProfile:(NSString *)profileName
               worldName:(nullable NSString *)worldName
                progress:(DataPackDownloadProgressHandler _Nullable)progress
              completion:(DataPackDownloadCompletionHandler _Nullable)completion {
    [self downloadDataPack:item toProfile:profileName worldName:worldName expectedSHA1:nil progress:progress completion:completion];
}

// ---------- Download with SHA1 validation (spec Task 5.1: providing expectedSHA1 enables validation) ----------
- (void)downloadDataPack:(DataPackItem *)item
               toProfile:(NSString *)profileName
               worldName:(nullable NSString *)worldName
            expectedSHA1:(nullable NSString *)expectedSHA1
                progress:(DataPackDownloadProgressHandler _Nullable)progress
              completion:(DataPackDownloadCompletionHandler _Nullable)completion {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *dataPacksFolder = nil;

    // Determine the download directory based on whether worldName is specified.
    if (worldName.length > 0) {
        // Download to saves/<worldName>/datapacks/.
        NSString *gameDir = [self gameDirForProfile:profileName];
        if (!gameDir) {
            if (completion) {
                NSError *error = [NSError errorWithDomain:@"DataPackServiceError"
                                                     code:1
                                                 userInfo:@{NSLocalizedDescriptionKey: @"Cannot find game directory."}];
                dispatch_async(dispatch_get_main_queue(), ^{ completion(NO, error); });
            }
            return;
        }
        NSString *savesDir = [gameDir stringByAppendingPathComponent:@"saves"];
        NSString *worldDir = [savesDir stringByAppendingPathComponent:worldName];
        dataPacksFolder = [worldDir stringByAppendingPathComponent:@"datapacks"];
        // Ensure the destination directory exists (including saves/<worldName>/datapacks/).
        NSError *dirError = nil;
        BOOL created = [fm createDirectoryAtPath:dataPacksFolder
                     withIntermediateDirectories:YES
                                      attributes:nil
                                           error:&dirError];
        if (!created || dirError) {
            if (completion) {
                NSError *error = [NSError errorWithDomain:@"DataPackServiceError"
                                                     code:1
                                                 userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Failed to create world datapacks directory: %@", dirError.localizedDescription ?: @"Unknown error"]}];
                dispatch_async(dispatch_get_main_queue(), ^{ completion(NO, error); });
            }
            return;
        }
    } else {
        // Default to downloading to <gameDir>/datapacks/.
        dataPacksFolder = [self existingDataPacksFolderForProfile:profileName];
        if (!dataPacksFolder) {
            NSString *gameDir = [self gameDirForProfile:profileName];
            if (gameDir) {
                dataPacksFolder = [gameDir stringByAppendingPathComponent:@"datapacks"];
                NSError *dirError = nil;
                BOOL created = [fm createDirectoryAtPath:dataPacksFolder
                             withIntermediateDirectories:YES
                                              attributes:nil
                                                   error:&dirError];
                if (!created || dirError) {
                    if (completion) {
                        NSError *error = [NSError errorWithDomain:@"DataPackServiceError"
                                                             code:1
                                                         userInfo:@{NSLocalizedDescriptionKey: @"Failed to create datapacks directory, please check storage permissions."}];
                        dispatch_async(dispatch_get_main_queue(), ^{ completion(NO, error); });
                    }
                    return;
                }
            } else {
                if (completion) {
                    NSError *error = [NSError errorWithDomain:@"DataPackServiceError"
                                                         code:1
                                                     userInfo:@{NSLocalizedDescriptionKey: localize(@"i18n_str_106", nil)}];
                    dispatch_async(dispatch_get_main_queue(), ^{ completion(NO, error); });
                }
                return;
            }
        }
    }

    // Validate the download URL.
    NSURL *url = [NSURL URLWithString:item.selectedVersionDownloadURL];
    if (!url) {
        if (completion) {
            NSError *error = [NSError errorWithDomain:@"DataPackServiceError"
                                                 code:2
                                             userInfo:@{NSLocalizedDescriptionKey: @"Invalid download URL."}];
            dispatch_async(dispatch_get_main_queue(), ^{ completion(NO, error); });
        }
        return;
    }

    // Ensure the filename is valid.
    NSString *fileName = item.fileName;
    if (!fileName || fileName.length == 0) {
        fileName = [url lastPathComponent];
    }
    if (!fileName || fileName.length == 0) {
        fileName = @"datapack.zip";
    }
    if (![fileName.lowercaseString hasSuffix:@".zip"]) {
        fileName = [fileName stringByAppendingString:@".zip"];
    }

    NSString *destinationPath = [dataPacksFolder stringByAppendingPathComponent:fileName];

    // Register with the unified download-task manager (rawTask is assigned PLDownloadOperation later;
    // the floating ball has been removed, so always register for download-list tracking).
    NSString *resourceName = item.fileName.length > 0 ? item.fileName : (item.displayName.length > 0 ? item.displayName : @"datapack");
    NSString *displayName = item.displayName.length > 0 ? item.displayName : resourceName;
    NSString *downloadSource = getPrefObject(@"general.download_source") ?: @"official";
    DownloadTaskItem *taskItem = [[DownloadTaskManager sharedManager]
        registerTaskWithResourceType:DownloadTaskResourceTypeDataPack
                        resourceName:resourceName
                         displayName:displayName
                      downloadSource:downloadSource
                             rawTask:nil
                      supportsResume:YES
                             iconURL:item.iconURL];
    taskItem.downloadURL = item.selectedVersionDownloadURL;
    // redesign-download-ui Phase 3: integrate single-file downloads with the unified progress page —
    // PLTaskStagesSingleFile single stage + autoPresentDetail automatically presents PLTaskProgressViewController.
    [[DownloadTaskManager sharedManager] setTaskWithId:taskItem.taskId stages:PLTaskStagesSingleFile()];
    taskItem.autoPresentDetail = YES;

    // retryHandler: FCL-style redownload; reuse the same taskItem and issue a new PLDownloadClient request.
    __weak typeof(self) weakSelf = self;
    taskItem.retryHandler = ^id(DownloadTaskItem *taskItemRef) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return nil;
        return [strongSelf restartPLDownloadForTaskId:taskItemRef.taskId];
    };

    PLDownloadRequest *request = [[PLDownloadRequest alloc] init];
    // Mirror candidates: original CDN URL + MCIM mirror, ordered according to the
    // download.assetDownloadSource policy (PLMirrorCenter centralizes mirror mapping and policy lookup).
    request.candidateURLs = [PLMirrorCenter candidateURLsForOriginalURL:url
                                                          resourceType:PLMirrorResourceTypeAssetDownload];
    // Task 5.1: providing expectedSHA1 (version-model files[].hashes.sha1) enables SHA1 validation;
    // PLDownloadClient retries validation failures using its mirror/backoff schedule.
    request.expectedSHA1 = expectedSHA1;
    // Task 5.2: if the destination file already exists and passes validation, succeed with zero
    // traffic (incremental download). Destination-path semantics match the original implementation
    // (datapacks/<fileName>.zip or saves/<worldName>/datapacks/<fileName>.zip); PLDownloadClient
    // atomically replaces the file on disk.
    request.destinationPath = destinationPath;
    // Use DownloadTaskManager's taskId as taskIdentifier so resumeData can be reused across download attempts.
    request.taskIdentifier = taskItem.taskId;
    // Without SHA1, use EOCD as a fallback integrity check for the .zip.
    request.allowZipFallbackCheck = YES;

    [self startPLDownloadWithRequest:request taskItem:taskItem progress:progress completion:completion];

    NSLog(@"[DataPackService] Starting download task (with progress) for datapack: %@ -> %@", url, destinationPath);
}

#pragma mark - PLDownloadClient wrapper (accumulate progress deltas / sample speed / dispatch completion)

/// Start (or restart) a PLDownloadClient request and attach progress, speed, and completion callbacks.
/// If progress/completion is nil, do not overwrite the registered callback (retryHandler reuses the
/// original callback when restarting).
- (nullable PLDownloadOperation *)startPLDownloadWithRequest:(PLDownloadRequest *)request
                                                     taskItem:(DownloadTaskItem *)taskItem
                                                     progress:(DataPackDownloadProgressHandler _Nullable)progress
                                                   completion:(DataPackDownloadCompletionHandler _Nullable)completion {
    NSString *taskId = taskItem.taskId;
    __weak typeof(self) weakSelf = self;

    [self.downloadStateLock lock];
    NSInteger generation = [self.downloadGenerations[taskId] integerValue] + 1;
    self.downloadGenerations[taskId] = @(generation);
    self.downloadTaskItems[taskId] = taskItem;
    self.downloadRequests[taskId] = request;
    if (progress) self.downloadProgressHandlers[taskId] = progress;
    if (completion) self.downloadCompletionHandlers[taskId] = completion;
    // Restart from the beginning: zero the accumulated progress (PLDownloadClient's negative-delta
    // rollback semantics are self-consistent within a single operation).
    self.downloadAccumulatedBytes[taskId] = @(0);
    self.downloadTotalBytes[taskId] = @(-1);
    self.downloadLastSpeeds[taskId] = @(0.0);
    [self.downloadStateLock unlock];

    PLDownloadOperation *operation = [[PLDownloadClient sharedClient] startRequest:request
                                                                          progress:^(int64_t deltaBytes, int64_t totalExpectedBytes) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        [strongSelf handlePLDownloadDelta:deltaBytes total:totalExpectedBytes taskId:taskId generation:generation];
    }
                                                                             speed:^(int64_t bytesPerSecond) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        [strongSelf handlePLDownloadSpeed:bytesPerSecond taskId:taskId generation:generation];
    }
                                                                        completion:^(BOOL success, NSError * _Nullable error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        [strongSelf handlePLDownloadCompletion:success error:error taskId:taskId generation:generation];
    }];
    if (!operation) {
        // Invalid parameter: PLDownloadClient asynchronously invokes completion with an error; the
        // shared failure path handles cleanup.
        return nil;
    }

    [self.downloadStateLock lock];
    self.downloadOperations[taskId] = operation;
    [self.downloadStateLock unlock];

    // rawTask is weakly referenced: the operation is retained by both PLDownloadClient and this
    // Service. DownloadTaskManager uses it to pause/resume/cancel PLDownloadOperation.
    taskItem.rawTask = operation;
    // Acquire a concurrency slot (if full, DownloadTaskManager queues by automatically pausing the operation).
    [[DownloadTaskManager sharedManager] setTaskWithId:taskId state:DownloadTaskStateDownloading];
    // redesign-download-ui Phase 3: set stage 0 to Running when a single-stage task begins downloading.
    [[DownloadTaskManager sharedManager] updateTaskWithId:taskId
                                              stageAtIndex:0
                                                  status:PLTaskStageStatusRunning];
    return operation;
}

/// retryHandler entry point: reuse the registered request description to restart the download.
- (nullable id)restartPLDownloadForTaskId:(NSString *)taskId {
    [self.downloadStateLock lock];
    PLDownloadRequest *request = self.downloadRequests[taskId];
    DownloadTaskItem *taskItem = self.downloadTaskItems[taskId];
    [self.downloadStateLock unlock];
    if (!request || !taskItem) return nil;
    return [self startPLDownloadWithRequest:request taskItem:taskItem progress:nil completion:nil];
}

/// Accumulate progress deltas: add negative deltas (rollback for mirror switching/retry/invalidated
/// resume data) directly to track actual progress.
- (void)handlePLDownloadDelta:(int64_t)delta total:(int64_t)total taskId:(NSString *)taskId generation:(NSInteger)generation {
    [self.downloadStateLock lock];
    if ([self.downloadGenerations[taskId] integerValue] != generation) {
        [self.downloadStateLock unlock];
        return;
    }
    int64_t accumulated = [self.downloadAccumulatedBytes[taskId] longLongValue] + delta;
    if (accumulated < 0) accumulated = 0;
    if (total > 0) self.downloadTotalBytes[taskId] = @(total);
    int64_t totalStored = [self.downloadTotalBytes[taskId] longLongValue];
    self.downloadAccumulatedBytes[taskId] = @(accumulated);
    double lastSpeed = [self.downloadLastSpeeds[taskId] doubleValue];
    DataPackDownloadProgressHandler progressHandler = self.downloadProgressHandlers[taskId];
    [self.downloadStateLock unlock];

    double fraction = totalStored > 0 ? (double)accumulated / (double)totalStored : -1.0;
    [[DownloadTaskManager sharedManager] updateTaskWithId:taskId
                                                 progress:fraction
                                               totalBytes:totalStored
                                          downloadedBytes:accumulated];
    // redesign-download-ui Phase 3: keep the stage progress of a single-stage task consistent with
    // total task progress.
    [[DownloadTaskManager sharedManager] updateTaskWithId:taskId
                                              stageAtIndex:0
                                                  progress:fraction
                                                 message:nil];

    if (!progressHandler) return;

    // Build NSProgress with throughput/ETA so callers can show speed and ETA in download-progress UI.
    NSProgress *downloadProgress = [NSProgress progressWithTotalUnitCount:totalStored > 0 ? totalStored : -1];
    downloadProgress.completedUnitCount = accumulated;
    if (lastSpeed > 0) {
        downloadProgress.throughput = @(lastSpeed);
        if (totalStored > accumulated) {
            downloadProgress.estimatedTimeRemaining = @((double)(totalStored - accumulated) / lastSpeed);
        }
    }
    // The progress callback runs on the main thread (safe for UI updates).
    dispatch_async(dispatch_get_main_queue(), ^{
        progressHandler(downloadProgress);
    });
}

/// Speed sampling (PLDownloadClient calls once per second; calls with 0 on completion/pause).
- (void)handlePLDownloadSpeed:(int64_t)bytesPerSecond taskId:(NSString *)taskId generation:(NSInteger)generation {
    [self.downloadStateLock lock];
    if ([self.downloadGenerations[taskId] integerValue] != generation) {
        [self.downloadStateLock unlock];
        return;
    }
    self.downloadLastSpeeds[taskId] = @(bytesPerSecond);
    int64_t total = [self.downloadTotalBytes[taskId] longLongValue];
    int64_t accumulated = [self.downloadAccumulatedBytes[taskId] longLongValue];
    [self.downloadStateLock unlock];

    double eta = (bytesPerSecond > 0 && total > accumulated)
        ? (double)(total - accumulated) / (double)bytesPerSecond : 0.0;
    [[DownloadTaskManager sharedManager] updateTaskWithId:taskId
                                                    speed:(double)bytesPerSecond
                                  estimatedTimeRemaining:eta];
}

/// Dispatch completion: update DownloadTaskManager state and invoke the caller (on the main thread).
/// After validation, PLDownloadClient atomically replaces the file at destinationPath; no manual
/// move is needed.
- (void)handlePLDownloadCompletion:(BOOL)success
                             error:(nullable NSError *)error
                            taskId:(NSString *)taskId
                         generation:(NSInteger)generation {
    [self.downloadStateLock lock];
    if ([self.downloadGenerations[taskId] integerValue] != generation) {
        [self.downloadStateLock unlock];
        return;
    }
    DataPackDownloadCompletionHandler completion = self.downloadCompletionHandlers[taskId];
    [self cleanupPLDownloadStateForTaskId:taskId];
    [self.downloadStateLock unlock];

    DownloadTaskManager *manager = [DownloadTaskManager sharedManager];
    if (success) {
        [manager updateTaskWithId:taskId stageAtIndex:0 status:PLTaskStageStatusCompleted];
        [manager setTaskWithId:taskId state:DownloadTaskStateCompleted];
    } else if ([error.domain isEqualToString:NSURLErrorDomain] && error.code == NSURLErrorCancelled) {
        // User cancelled (DownloadTaskManager has already set Cancelled; keep this idempotently aligned).
        [manager setTaskWithId:taskId state:DownloadTaskStateCancelled];
    } else {
        [manager updateTaskWithId:taskId stageAtIndex:0 status:PLTaskStageStatusFailed];
        [manager updateTaskWithId:taskId error:error];
        [manager setTaskWithId:taskId state:DownloadTaskStateFailed];
    }

    if (completion) {
        BOOL successFlag = success ? YES : NO;
        NSError *capturedError = success ? nil : error;
        dispatch_async(dispatch_get_main_queue(), ^{
            completion(successFlag, capturedError);
        });
    }
}

/// Clear all tracking state for the specified task (must be called under downloadStateLock).
- (void)cleanupPLDownloadStateForTaskId:(NSString *)taskId {
    [self.downloadTaskItems removeObjectForKey:taskId];
    [self.downloadOperations removeObjectForKey:taskId];
    [self.downloadGenerations removeObjectForKey:taskId];
    [self.downloadAccumulatedBytes removeObjectForKey:taskId];
    [self.downloadTotalBytes removeObjectForKey:taskId];
    [self.downloadLastSpeeds removeObjectForKey:taskId];
    [self.downloadRequests removeObjectForKey:taskId];
    [self.downloadProgressHandlers removeObjectForKey:taskId];
    [self.downloadCompletionHandlers removeObjectForKey:taskId];
}

@end
