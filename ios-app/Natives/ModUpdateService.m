#import "ModUpdateService.h"
#import "installer/modpack/ModrinthAPI.h"
#import "installer/modpack/CurseForgeAPI.h"
#import "CurseForgeMurmurHash.h"

#pragma mark - ModUpdateResult implementation

@implementation ModUpdateResult

- (instancetype)init {
    self = [super init];
    if (self) {
        _candidateVersions = @[];
        _allVersions = @[];
        _projectType = @"mod";
    }
    return self;
}

/// Whether an update is available: a nonempty candidate-version list means an update exists.
- (BOOL)hasUpdate {
    return self.candidateVersions.count > 0;
}

@end

#pragma mark - ModUpdateService implementation

@interface ModUpdateService ()
/// Serial queue used for concurrent reverse lookups (only isolates dispatch to both sources).
@property (nonatomic, strong) dispatch_queue_t lookupQueue;
@end

@implementation ModUpdateService

+ (instancetype)sharedService {
    static ModUpdateService *sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[self alloc] init];
    });
    return sharedInstance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        // Reverse-lookup tasks use the global concurrent queue; keep this only as an identifier.
        _lookupQueue = dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0);
    }
    return self;
}

#pragma mark - Check a single mod for updates (race both sources)

- (void)checkUpdateForMod:(ModItem *)mod
              gameVersion:(NSString *)gameVersion
                   loader:(nullable NSString *)loader
              projectType:(NSString *)projectType
               completion:(void (^)(ModUpdateResult *_Nullable result))completion {
    // Validate parameters: a local file path is required.
    if (!mod || mod.filePath.length == 0) {
        [self callCompletionOnMain:nil completion:completion];
        return;
    }

    // Shared state: synchronization for racing the two sources.
    NSObject *lock = [[NSObject alloc] init];
    __block BOOL resolved = NO;            // Whether a decision has been made (a match or both sources failed).
    __block BOOL modrinthDone = NO;        // Whether the Modrinth reverse lookup finished.
    __block BOOL curseforgeDone = NO;      // Whether the CurseForge reverse lookup finished.
    __block NSMutableDictionary *winnerResult = nil;  // Project dictionary from the winning source.
    __block NSNumber *winnerSource = nil;              // Winning source (1=Modrinth, 2=CurseForge).

    // Race logic: use the first nonempty result; if the first result is empty, wait for the other source.
    void (^tryResolve)(NSMutableDictionary *_Nullable, NSNumber *) = ^(NSMutableDictionary *_Nullable result, NSNumber *source) {
        @synchronized(lock) {
            // If already resolved, discard the late result (soft cancellation).
            if (resolved) return;

            if (result && result.count > 0) {
                // Match: use this source's result.
                resolved = YES;
                winnerResult = result;
                winnerSource = source;
            } else {
                // No match from this source; check whether both sources have finished.
                if (modrinthDone && curseforgeDone) {
                    // Neither source matched; overall failure.
                    resolved = YES;
                }
            }
        }

        // Determine whether to continue outside the lock (avoid callbacks while holding the lock).
        BOOL shouldFetch = NO;
        BOOL shouldFail = NO;
        @synchronized(lock) {
            if (winnerResult && [winnerSource isEqual:source]) {
                shouldFetch = YES;
                // Take the result once and clear it to prevent duplicate callbacks.
                winnerSource = nil;
            } else if (resolved && !winnerResult) {
                shouldFail = YES;
            }
        }

        if (shouldFetch) {
            // After a match, fetch all versions for the project.
            [self fetchVersionsAndBuildResultWithProjectDict:result
                                                       source:source
                                                          mod:mod
                                                  gameVersion:gameVersion
                                                       loader:loader
                                                  projectType:projectType
                                                   completion:completion];
        } else if (shouldFail) {
            // Neither source matched; call back with nil on the main thread.
            [self callCompletionOnMain:nil completion:completion];
        }
    };

    // Modrinth reverse lookup: use mod.fileSHA1 (synchronous method; run on a background queue).
    dispatch_async(self.lookupQueue, ^{
        @autoreleasepool {
            NSMutableDictionary *r = nil;
            // Modrinth requires fileSHA1.
            if (mod.fileSHA1.length > 0) {
                @try {
                    r = [[ModrinthAPI sharedInstance] projectForFileHash:mod.fileSHA1 projectType:projectType];
                } @catch (NSException *exception) {
                    r = nil;
                }
            }
            @synchronized(lock) {
                modrinthDone = YES;
            }
            tryResolve(r, @(1));
        }
    });

    // CurseForge reverse lookup: calculate the MurmurHash2 fingerprint locally from the file path, then look it up by fingerprint (synchronous method).
    // Fix: the original implementation passed the mod.filePath string directly to projectForFileHash. Internally,
    // [murmurHash longLongValue] always returned 0 for a nonnumeric path, so the fingerprint never matched.
    dispatch_async(self.lookupQueue, ^{
        @autoreleasepool {
            NSMutableDictionary *r = nil;
            if (mod.filePath.length > 0) {
                @try {
                    uint32_t fingerprint = [CurseForgeMurmurHash fingerprintForFileAtPath:mod.filePath];
                    if (fingerprint != 0) {
                        r = [[CurseForgeAPI sharedInstance] projectForFileHash:@(fingerprint) projectType:projectType];
                    }
                } @catch (NSException *exception) {
                    r = nil;
                }
            }
            @synchronized(lock) {
                curseforgeDone = YES;
            }
            tryResolve(r, @(2));
        }
    });
}

#pragma mark - Fetch version list and build result

- (void)fetchVersionsAndBuildResultWithProjectDict:(NSMutableDictionary *)projectDict
                                            source:(NSNumber *)source
                                               mod:(ModItem *)mod
                                       gameVersion:(NSString *)gameVersion
                                            loader:(nullable NSString *)loader
                                       projectType:(NSString *)projectType
                                        completion:(void (^)(ModUpdateResult *_Nullable))completion {
    // Extract the project ID from the reverse-lookup result dictionary.
    NSString *projectID = [self extractProjectIDFromDict:projectDict source:source];
    if (projectID.length == 0) {
        [self callCompletionOnMain:nil completion:completion];
        return;
    }

    // Fetch the version list from the API instance for the matching source.
    id api = ([source intValue] == 1) ? [ModrinthAPI sharedInstance] : [CurseForgeAPI sharedInstance];
    if (![api respondsToSelector:@selector(getVersionsForModWithID:completion:)]) {
        [self callCompletionOnMain:nil completion:completion];
        return;
    }

    [api getVersionsForModWithID:projectID completion:^(NSArray<ModVersion *> *_Nullable versions, NSError *_Nullable error) {
        // Note: the existing API implementation calls this block on the main thread.
        if (error || !versions || versions.count == 0) {
            [self callCompletionOnMain:nil completion:completion];
            return;
        }

        ModUpdateResult *result = [self buildResultWithMod:mod
                                                 projectID:projectID
                                                 apiSource:source
                                               projectType:projectType
                                                  versions:versions
                                              gameVersion:gameVersion
                                                   loader:loader
                                              projectDict:projectDict];
        [self callCompletionOnMain:result completion:completion];
    }];
}

#pragma mark - Filter versions and build result

- (ModUpdateResult *)buildResultWithMod:(ModItem *)mod
                              projectID:(NSString *)projectID
                              apiSource:(NSNumber *)apiSource
                            projectType:(NSString *)projectType
                               versions:(NSArray<ModVersion *> *)versions
                           gameVersion:(NSString *)gameVersion
                                loader:(nullable NSString *)loader
                           projectDict:(NSDictionary *)projectDict {
    // 1. Identify the current version (the version matched by reverse lookup).
    ModVersion *currentVersion = [self findCurrentVersionIn:versions
                                                        mod:mod
                                              projectDict:projectDict
                                                   apiSource:apiSource];

    // 2. Sort all versions by datePublished descending (newest first).
    NSArray<ModVersion *> *sortedAll = [versions sortedArrayUsingComparator:^NSComparisonResult(ModVersion *_Nonnull v1, ModVersion *_Nonnull v2) {
        NSDate *d1 = [self parseISO8601:v1.datePublished];
        NSDate *d2 = [self parseISO8601:v2.datePublished];
        if (!d1 && !d2) return NSOrderedSame;
        if (!d1) return NSOrderedAscending;
        if (!d2) return NSOrderedDescending;
        return [d2 compare:d1]; // Descending.
    }];

    // 3. Get the current version's publish date (for strict greater-than comparisons).
    NSDate *currentDate = [self parseISO8601:currentVersion.datePublished];
    if (!currentDate && currentVersion.datePublished.length > 0) {
        currentDate = [self parseISO8601:currentVersion.datePublished];
    }

    // 4. Determine the loader-filtering strategy (smart fallback).
    NSArray<NSString *> *effectiveLoaders = [self effectiveLoadersForMod:mod inputLoader:loader];

    // 5. Filter update candidates: datePublished strictly later than the current version + game-version filter + loader filter.
    NSMutableArray<ModVersion *> *candidates = [NSMutableArray array];
    for (ModVersion *v in sortedAll) {
        // 5.1 The publish date must be parseable.
        NSDate *vDate = [self parseISO8601:v.datePublished];
        if (!vDate) continue;

        // 5.2 Must be strictly later than the current version's date (skip this filter if the current date is unknown).
        if (currentDate && [vDate compare:currentDate] != NSOrderedDescending) {
            continue;
        }

        // 5.3 Game-version filter (must include the provided gameVersion).
        if (gameVersion.length > 0 && ![v.gameVersions containsObject:gameVersion]) {
            continue;
        }

        // 5.4 Loader filter (smart fallback; do not filter when effectiveLoaders is empty).
        if (effectiveLoaders.count > 0) {
            BOOL loaderMatch = NO;
            for (NSString *l in effectiveLoaders) {
                if ([v.loaders containsObject:l]) {
                    loaderMatch = YES;
                    break;
                }
            }
            if (!loaderMatch) continue;
        }

        [candidates addObject:v];
    }

    // 6. Build the result object.
    ModUpdateResult *result = [[ModUpdateResult alloc] init];
    result.localFilePath = mod.filePath;
    result.currentVersion = currentVersion;
    result.candidateVersions = [candidates copy]; // Already in descending order.
    result.allVersions = sortedAll;
    result.projectID = projectID;
    result.apiSource = apiSource;
    result.projectType = projectType;
    return result;
}

#pragma mark - Identify current version

/// Identifies the current version in the full version list (the version matched by reverse lookup).
/// Priority: fileId (CurseForge) > fileSHA1 (Modrinth primaryFile) > versionNumber > latest-version fallback.
- (ModVersion *)findCurrentVersionIn:(NSArray<ModVersion *> *)versions
                                 mod:(ModItem *)mod
                        projectDict:(NSDictionary *)projectDict
                            apiSource:(NSNumber *)apiSource {
    if (versions.count == 0) return nil;

    // Strategy 1: match CurseForge by fileId (the reverse-lookup result includes fileId).
    if ([apiSource intValue] == 2) {
        NSString *curFileId = [projectDict[@"fileId"] isKindOfClass:[NSString class]] ? projectDict[@"fileId"] : nil;
        if (curFileId.length > 0) {
            for (ModVersion *v in versions) {
                if ([v.fileId isEqualToString:curFileId]) {
                    return v;
                }
            }
        }
    }

    // Strategy 2: match Modrinth using fileSHA1 against primaryFile hashes.sha1.
    if (mod.fileSHA1.length > 0) {
        for (ModVersion *v in versions) {
            NSDictionary *primaryFile = v.primaryFile;
            if (![primaryFile isKindOfClass:[NSDictionary class]]) continue;
            // Modrinth format: hashes[@"sha1"].
            id hashesVal = primaryFile[@"hashes"];
            if ([hashesVal isKindOfClass:[NSDictionary class]]) {
                NSString *sha1 = [hashesVal[@"sha1"] isKindOfClass:[NSString class]] ? hashesVal[@"sha1"] : nil;
                if (sha1 && [sha1 isEqualToString:mod.fileSHA1]) {
                    return v;
                }
            }
            // Fallback: sha1 is included in the URL (Modrinth file URLs usually use sha1 as the filename).
            NSString *url = [primaryFile[@"url"] isKindOfClass:[NSString class]] ? primaryFile[@"url"] : nil;
            if (url && [url containsString:mod.fileSHA1]) {
                return v;
            }
        }
    }

    // Strategy 3: match by version number (compare mod.version with versionNumber).
    if (mod.version.length > 0) {
        for (ModVersion *v in versions) {
            if ([v.versionNumber isEqualToString:mod.version]) {
                return v;
            }
        }
    }

    // Strategy 4: match CurseForge fileId against ModVersion.fileId (Mod has no fileId field, so skip).

    // Strategy 5: fallback; if there is only one version, return it.
    if (versions.count == 1) {
        return versions.firstObject;
    }

    // Strategy 6: fallback; return the first in descending order (the latest version).
    NSArray<ModVersion *> *sorted = [versions sortedArrayUsingComparator:^NSComparisonResult(ModVersion *_Nonnull v1, ModVersion *_Nonnull v2) {
        NSDate *d1 = [self parseISO8601:v1.datePublished];
        NSDate *d2 = [self parseISO8601:v2.datePublished];
        if (!d1 && !d2) return NSOrderedSame;
        if (!d1) return NSOrderedAscending;
        if (!d2) return NSOrderedDescending;
        return [d2 compare:d1];
    }];
    return sorted.firstObject;
}

#pragma mark - Smart loader fallback

/// Computes the set of loaders to use when filtering versions.
/// Strategy:
///   - If the mod's declared loaders (isFabric/isForge/isNeoForge) include the provided loader, filter by the provided loader.
///   - If they do not match (e.g. cross-platform use), filter using the loaders declared by the file itself.
///   - If the mod declares no loader and loader is nil, return an empty array (no filtering).
- (NSArray<NSString *> *)effectiveLoadersForMod:(ModItem *)mod inputLoader:(nullable NSString *)loader {
    // Collect loaders declared by the mod.
    NSMutableArray<NSString *> *declared = [NSMutableArray array];
    if (mod.isFabric) [declared addObject:@"fabric"];
    if (mod.isForge) [declared addObject:@"forge"];
    if (mod.isNeoForge) [declared addObject:@"neoforge"];

    // Check whether the provided loader matches the mod's declaration.
    if (loader.length > 0) {
        NSString *lowerLoader = [loader lowercaseString];
        for (NSString *l in declared) {
            if ([l isEqualToString:lowerLoader]) {
                // Match: filter using the provided loader.
                return @[lowerLoader];
            }
        }
        // Mismatch: if the mod declares no loaders at all, trust the provided loader.
        if (declared.count == 0) {
            return @[lowerLoader];
        }
        // Otherwise, use the fallback branch (keep the mod's declared loader set).
    }

    // Mismatch or empty loader: use the loaders declared by the file itself.
    if (declared.count > 0) {
        return [declared copy];
    }

    // Neither has a loader: return an empty array to indicate no loader filtering.
    return @[];
}

#pragma mark - Utility methods

/// Extracts the project ID from the reverse-lookup result dictionary.
- (nullable NSString *)extractProjectIDFromDict:(NSDictionary *)dict source:(NSNumber *)source {
    if (!dict || dict.count == 0) return nil;

    if ([source intValue] == 1) {
        // Modrinth: the id field in the dictionary returned by projectForFileHash is the project_id.
        id v = dict[@"id"];
        if ([v isKindOfClass:[NSString class]]) return v;
        if ([v isKindOfClass:[NSNumber class]]) return [v stringValue];
        // Fallback: try the project_id key.
        id pid = dict[@"project_id"];
        if ([pid isKindOfClass:[NSString class]]) return pid;
        if ([pid isKindOfClass:[NSNumber class]]) return [pid stringValue];
        return nil;
    } else {
        // CurseForge: the id field in the dictionary returned by projectForFileHash is modId.
        id v = dict[@"id"];
        if ([v isKindOfClass:[NSString class]]) return v;
        if ([v isKindOfClass:[NSNumber class]]) return [v stringValue];
        // Fallback: try the modId key.
        id mid = dict[@"modId"];
        if ([mid isKindOfClass:[NSString class]]) return mid;
        if ([mid isKindOfClass:[NSNumber class]]) return [mid stringValue];
        return nil;
    }
}

/// Parses an ISO8601 date string into NSDate (supports formats both with and without milliseconds).
- (nullable NSDate *)parseISO8601:(NSString *)dateString {
    if (![dateString isKindOfClass:[NSString class]] || dateString.length == 0) return nil;
    NSISO8601DateFormatter *formatter = [[NSISO8601DateFormatter alloc] init];
    // First try the format with milliseconds (common for CurseForge fileDate).
    formatter.formatOptions = NSISO8601DateFormatWithInternetDateTime | NSISO8601DateFormatWithFractionalSeconds;
    NSDate *date = [formatter dateFromString:dateString];
    if (!date) {
        // Fall back to the format without milliseconds.
        formatter.formatOptions = NSISO8601DateFormatWithInternetDateTime;
        date = [formatter dateFromString:dateString];
    }
    return date;
}

/// Calls completion on the main thread.
- (void)callCompletionOnMain:(ModUpdateResult *_Nullable)result
                  completion:(void (^)(ModUpdateResult *_Nullable))completion {
    if (!completion) return;
    if ([NSThread isMainThread]) {
        completion(result);
    } else {
        dispatch_async(dispatch_get_main_queue(), ^{
            completion(result);
        });
    }
}

#pragma mark - Batch update checks (limited to 3 concurrent requests)

- (void)checkUpdatesForMods:(NSArray<ModItem *> *)mods
               gameVersion:(NSString *)gameVersion
                    loader:(nullable NSString *)loader
               projectType:(NSString *)projectType
                  progress:(void (^)(NSInteger completed, NSInteger total))progress
                completion:(void (^)(NSArray<ModUpdateResult *> *results))completion {
    NSInteger total = mods.count;

    // Immediately call back for an empty array.
    if (total == 0) {
        [self callProgressOnMain:0 total:0 progress:progress];
        [self callBatchCompletionOnMain:@[] completion:completion];
        return;
    }

    // Concurrency-limit semaphore (maximum of 3).
    dispatch_semaphore_t semaphore = dispatch_semaphore_create(3);
    dispatch_queue_t workQueue = dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0);

    // Synchronization lock for collecting results.
    NSObject *lock = [[NSObject alloc] init];
    __block NSMutableArray<ModUpdateResult *> *results = [NSMutableArray array];
    __block NSInteger completed = 0;

    for (ModItem *mod in mods) {
        dispatch_async(workQueue, ^{
            // Wait on the semaphore (rate limit).
            dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);

            // Check a single mod for updates.
            [self checkUpdateForMod:mod
                        gameVersion:gameVersion
                             loader:loader
                        projectType:projectType
                         completion:^(ModUpdateResult *_Nullable result) {
                // This callback runs on the main thread.
                @synchronized(lock) {
                    if (result && [result hasUpdate]) {
                        [results addObject:result];
                    }
                    completed++;
                    NSInteger c = completed;
                    NSArray<ModUpdateResult *> *snapshot = [results copy];

                    // Progress callback.
                    [self callProgressOnMain:c total:total progress:progress];

                    // Call back with the final result when all checks finish.
                    if (c >= total) {
                        [self callBatchCompletionOnMain:snapshot completion:completion];
                    }
                }
                // Release the semaphore to let the next task proceed.
                dispatch_semaphore_signal(semaphore);
            }];
        });
    }
}

/// Calls back with progress on the main thread.
- (void)callProgressOnMain:(NSInteger)completed
                     total:(NSInteger)total
                  progress:(void (^)(NSInteger completed, NSInteger total))progress {
    if (!progress) return;
    if ([NSThread isMainThread]) {
        progress(completed, total);
    } else {
        dispatch_async(dispatch_get_main_queue(), ^{
            progress(completed, total);
        });
    }
}

/// Calls back with batch completion on the main thread.
- (void)callBatchCompletionOnMain:(NSArray<ModUpdateResult *> *)results
                       completion:(void (^)(NSArray<ModUpdateResult *> *results))completion {
    if (!completion) return;
    if ([NSThread isMainThread]) {
        completion(results);
    } else {
        dispatch_async(dispatch_get_main_queue(), ^{
            completion(results);
        });
    }
}

@end
