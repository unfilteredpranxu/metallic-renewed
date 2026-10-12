#import "utils.h"
//
//  ModService.m
//  AmethystMods
//
//  Change: add a file modification-time cache to greatly improve scanning speed.
//  Change: route file downloads through the unified PLDownloadClient (mirror candidates + SHA1 validation + resume support),
//        removing the custom NSURLSession download delegate (spec optimize-download-system Task 4.2 / 5.1 / 5.2).
//

#import "ModService.h"
#import <CommonCrypto/CommonCrypto.h>
#import <UIKit/UIKit.h>
#import "PLProfiles.h"
#import "ModItem.h"
#import "UnzipKit.h"
#import "DownloadTaskManager.h"
#import "DownloadTaskItem.h"
#import "PLTaskStages.h"
#import "LauncherPreferences.h"
#import "PLDownloadClient.h"
#import "PLMirrorCenter.h"

@interface ModService ()
// ---- PLDownloadClient download tracking (key = DownloadTaskItem.taskId, i.e. PLDownloadRequest.taskIdentifier) ----
@property (nonatomic, strong) NSLock *downloadStateLock;
@property (nonatomic, strong) NSMutableDictionary<NSString *, DownloadTaskItem *> *downloadTaskItems;
// Strongly retain the current operation: PLDownloadClient removes its internal task mapping after pause,
// so the Service must keep it alive for DownloadTaskManager's rawTask (weak) to continue supporting pause/resume.
@property (nonatomic, strong) NSMutableDictionary<NSString *, PLDownloadOperation *> *downloadOperations;
// Retry generation: discard delayed callbacks (e.g. cancellation) from the old operation after retryHandler creates a new request.
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSNumber *> *downloadGenerations;
// Accumulated progress (PLDownloadClient reports deltas, including negative rollback deltas on mirror switches/retries; simply add them).
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSNumber *> *downloadAccumulatedBytes;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSNumber *> *downloadTotalBytes;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSNumber *> *downloadLastSpeeds;
// Cached request description: retryHandler reuses the same request (the same taskIdentifier can reuse resume data).
@property (nonatomic, strong) NSMutableDictionary<NSString *, PLDownloadRequest *> *downloadRequests;
@property (nonatomic, strong) NSMutableDictionary<NSString *, void(^)(NSProgress *)> *downloadProgressHandlers;
@property (nonatomic, strong) NSMutableDictionary<NSString *, ModDownloadHandler> *downloadCompletionHandlers;

// Cache.
@property (nonatomic, strong) NSMutableDictionary<NSString *, ModItem *> *metadataCache;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSDate *> *checkpointTimes;
@property (nonatomic, strong) dispatch_queue_t cacheQueue;
@end

@implementation ModService

// ---------- TOML parsing (unchanged) ----------
- (nullable id)parseTomlValue:(NSString *)valPart inLines:(NSArray<NSString *> *)lines atIndex:(NSUInteger *)i {
    NSString *trimmedVal = [valPart stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    NSString *delimiter = nil;
    if ([trimmedVal hasPrefix:@"'''"]) delimiter = @"'''";
    else if ([trimmedVal hasPrefix:@"\"\"\""]) delimiter = @"\"\"\"";

    if (delimiter) {
        NSMutableString *multiLineContent = [[trimmedVal substringFromIndex:3] mutableCopy];
        if ([multiLineContent hasSuffix:delimiter]) {
            return [multiLineContent substringToIndex:multiLineContent.length - 3];
        } else {
            NSMutableArray<NSString *> *contentLines = [NSMutableArray array];
            [contentLines addObject:multiLineContent];
            (*i)++;
            while (*i < lines.count) {
                NSString *nextLine = lines[*i];
                NSRange endDelimiterRange = [nextLine rangeOfString:delimiter];
                if (endDelimiterRange.location != NSNotFound) {
                    [contentLines addObject:[nextLine substringToIndex:endDelimiterRange.location]];
                    break;
                } else {
                    [contentLines addObject:nextLine];
                }
                (*i)++;
            }
            return [contentLines componentsJoinedByString:@"\n"];
        }
    }

    if (([trimmedVal hasPrefix:@"\""] && [trimmedVal hasSuffix:@"\""]) ||
        ([trimmedVal hasPrefix:@"'"] && [trimmedVal hasSuffix:@"'"])) {
        if (trimmedVal.length > 1) {
            return [trimmedVal substringWithRange:NSMakeRange(1, trimmedVal.length - 2)];
        }
        return @"";
    }
    return trimmedVal;
}

- (NSDictionary<NSString *, id> *)parseTomlString:(NSString *)s {
    if (!s) return nil;
    NSMutableDictionary<NSString *, id> *root = [NSMutableDictionary dictionary];
    NSMutableDictionary *currentTable = root;
    NSString *currentTableName = nil;
    NSArray<NSString *> *lines = [s componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]];
    for (NSUInteger i = 0; i < lines.count; i++) {
        NSString *line = lines[i];
        NSString *trimmed = [line stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        if ([trimmed hasPrefix:@"#"] || trimmed.length == 0) continue;

        if ([trimmed hasPrefix:@"[["] && [trimmed hasSuffix:@"]]"]) {
            currentTableName = [trimmed substringWithRange:NSMakeRange(2, trimmed.length - 4)];
            NSMutableArray *array = root[currentTableName] ?: [NSMutableArray array];
            root[currentTableName] = array;
            currentTable = [NSMutableDictionary dictionary];
            [array addObject:currentTable];
            continue;
        } else if ([trimmed hasPrefix:@"["] && [trimmed hasSuffix:@"]"]) {
            currentTableName = [trimmed substringWithRange:NSMakeRange(1, trimmed.length - 2)];
            currentTable = [NSMutableDictionary dictionary];
            root[currentTableName] = currentTable;
            continue;
        }

        NSRange eqRange = [trimmed rangeOfString:@"="];
        if (eqRange.location != NSNotFound) {
            NSString *key = [[trimmed substringToIndex:eqRange.location] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
            NSString *valPart = [trimmed substringFromIndex:NSMaxRange(eqRange)];
            id value = [self parseTomlValue:valPart inLines:lines atIndex:&i];
            if (value) {
                currentTable[key] = value;
            }
        }
    }
    return root;
}

// ---------- Initialization ----------
+ (instancetype)sharedService {
    static ModService *s;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        s = [[ModService alloc] init];
    });
    return s;
}

- (instancetype)init {
    if (self = [super init]) {
        _onlineSearchEnabled = NO;

        // Downloads now use [PLDownloadClient sharedClient] (mirror candidates + SHA1 validation + resume support);
        // no custom NSURLSession download delegate is created.
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

        // Initialize cache.
        _metadataCache = [NSMutableDictionary dictionary];
        _checkpointTimes = [NSMutableDictionary dictionary];
        _cacheQueue = dispatch_queue_create("com.amethyst.modcache", DISPATCH_QUEUE_CONCURRENT);
    }
    return self;
}

// ---------- Helper methods ----------
- (nullable NSString *)sha1ForFileAtPath:(NSString *)path {
    NSData *d = [NSData dataWithContentsOfFile:path];
    if (!d) return nil;
    unsigned char digest[CC_SHA1_DIGEST_LENGTH];
    CC_SHA1(d.bytes, (CC_LONG)d.length, digest);
    NSMutableString *hex = [NSMutableString stringWithCapacity:CC_SHA1_DIGEST_LENGTH * 2];
    for (int i = 0; i < CC_SHA1_DIGEST_LENGTH; i++) {
        [hex appendFormat:@"%02x", digest[i]];
    }
    return [hex copy];
}

- (NSString *)iconCachePathForURL:(NSString *)urlString {
    if (!urlString) return nil;
    NSString *cacheDir = [NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES) firstObject];
    NSString *folder = [cacheDir stringByAppendingPathComponent:@"mod_icons"];
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

- (nullable NSData *)readFileFromJar:(NSString *)jarPath entryName:(NSString *)entryName {
    if (!jarPath || !entryName) return nil;
    NSError *err = nil;
    UZKArchive *archive = [[UZKArchive alloc] initWithPath:jarPath error:&err];
    if (!archive || err) return nil;
    NSData *data = [archive extractDataFromFile:entryName error:&err];
    return data;
}

/// Resolves the profile's gameDir to an absolute path.
/// A profile gameDir is usually a relative path (e.g. "./custom_gamedir/{name}") and must be resolved relative to POJAV_GAME_DIR.
/// Using the relative path directly could make the mods folder unfindable (fileExistsAtPath resolves relative paths from cwd,
/// which is not necessarily POJAV_GAME_DIR).
- (nullable NSString *)resolveAbsoluteGameDirForProfile:(NSString *)profileName {
    NSString *profile = profileName.length ? profileName : @"default";
    @try {
        NSDictionary *profiles = PLProfiles.current.profiles;
        NSDictionary *prof = profiles[profile];
        if (![prof isKindOfClass:[NSDictionary class]]) return nil;
        NSString *gameDir = amePCLVersionGameDirSubpath(prof, nil);   // ★ [VER-ISOLATE-PCL] Unified resolution for version isolation.
        if (![gameDir isKindOfClass:[NSString class]] || gameDir.length == 0) return nil;
        if ([gameDir isEqualToString:@"."]) {
            // "." means the root directory.
            const char *env = getenv("POJAV_GAME_DIR");
            return env ? [NSString stringWithUTF8String:env] : NSHomeDirectory();
        }
        if ([gameDir isAbsolutePath]) {
            return gameDir;
        }
        // Resolve relative paths against POJAV_GAME_DIR.
        const char *env = getenv("POJAV_GAME_DIR");
        NSString *baseDir = env ? [NSString stringWithUTF8String:env] : NSHomeDirectory();
        // Remove the "./" prefix if present; stringByAppendingPathComponent handles it correctly.
        NSString *cleanGameDir = [gameDir hasPrefix:@"./"] ? [gameDir substringFromIndex:2] : gameDir;
        return [baseDir stringByAppendingPathComponent:cleanGameDir];
    } @catch (NSException *ex) {
        return nil;
    }
}

- (nullable NSString *)existingModsFolderForProfile:(NSString *)profileName {
    NSString *profile = profileName.length ? profileName : @"default";
    NSFileManager *fm = [NSFileManager defaultManager];

    // Prefer the profile gameDir (already resolved to an absolute path).
    NSString *resolvedGameDir = [self resolveAbsoluteGameDirForProfile:profile];
    if (resolvedGameDir.length > 0) {
        NSString *modsPath = [resolvedGameDir stringByAppendingPathComponent:@"mods"];
        BOOL isDir = NO;
        if ([fm fileExistsAtPath:modsPath isDirectory:&isDir] && isDir) {
            return modsPath;
        }
    }

    // Fall back to POJAV_GAME_DIR/mods.
    const char *gameDirC = getenv("POJAV_GAME_DIR");
    if (gameDirC) {
        NSString *gameDir = [NSString stringWithUTF8String:gameDirC];
        NSString *modsPath = [gameDir stringByAppendingPathComponent:@"mods"];
        BOOL isDir = NO;
        if ([fm fileExistsAtPath:modsPath isDirectory:&isDir] && isDir) {
            return modsPath;
        }
    }
    return nil;
}

/// Gets the current profile's mods directory, creating it if it does not exist.
- (nullable NSString *)ensureModsFolderForProfile:(NSString *)profileName error:(NSError **)error {
    NSString *profile = profileName.length ? profileName : @"default";
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *modsPath = nil;

    // Prefer the profile gameDir (already resolved to an absolute path).
    NSString *resolvedGameDir = [self resolveAbsoluteGameDirForProfile:profile];
    if (resolvedGameDir.length > 0) {
        modsPath = [resolvedGameDir stringByAppendingPathComponent:@"mods"];
    }

    if (!modsPath) {
        const char *gameDirC = getenv("POJAV_GAME_DIR");
        if (gameDirC) {
            NSString *gameDir = [NSString stringWithUTF8String:gameDirC];
            modsPath = [gameDir stringByAppendingPathComponent:@"mods"];
        }
    }

    if (!modsPath) {
        if (error) {
            *error = [NSError errorWithDomain:@"ModService" code:1 userInfo:@{NSLocalizedDescriptionKey: localize(@"i18n_str_105", nil)}];
        }
        return nil;
    }

    BOOL isDir = NO;
    if (![fm fileExistsAtPath:modsPath isDirectory:&isDir]) {
        // Directory does not exist; create it.
        NSError *createError = nil;
        [fm createDirectoryAtPath:modsPath withIntermediateDirectories:YES attributes:nil error:&createError];
        if (createError) {
            if (error) *error = createError;
            return nil;
        }
        NSLog(@"[ModService] Created mods directory: %@", modsPath);
    } else if (!isDir) {
        if (error) {
            *error = [NSError errorWithDomain:@"ModService" code:2 userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:localize(@"i18n_str_451", nil), modsPath]}];
        }
        return nil;
    }
    return modsPath;
}

// ---------- Cache methods ----------
- (BOOL)needsRescanForPath:(NSString *)path {
    __block BOOL needs = YES;
    dispatch_sync(self.cacheQueue, ^{
        NSDate *lastScan = self.checkpointTimes[path];
        if (lastScan) {
            NSDictionary *attrs = [[NSFileManager defaultManager] attributesOfItemAtPath:path error:nil];
            NSDate *modifyDate = attrs[NSFileModificationDate];
            if (modifyDate && [modifyDate isEqualToDate:lastScan]) {
                needs = NO;
            }
        }
    });
    return needs;
}

- (void)updateCheckpointForPath:(NSString *)path {
    dispatch_barrier_async(self.cacheQueue, ^{
        NSDictionary *attrs = [[NSFileManager defaultManager] attributesOfItemAtPath:path error:nil];
        NSDate *modifyDate = attrs[NSFileModificationDate];
        if (modifyDate) {
            self.checkpointTimes[path] = modifyDate;
        }
    });
}

- (nullable ModItem *)cachedModForPath:(NSString *)path {
    __block ModItem *item = nil;
    dispatch_sync(self.cacheQueue, ^{
        item = self.metadataCache[path];
    });
    return item;
}

- (void)cacheModItem:(ModItem *)item forPath:(NSString *)path {
    dispatch_barrier_async(self.cacheQueue, ^{
        self.metadataCache[path] = item;
    });
}

// ---------- Scan mods (core optimization) ----------
- (void)scanModsForProfile:(NSString *)profileName completion:(ModListHandler)completion {
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSString *modsFolder = [self existingModsFolderForProfile:profileName];
        NSMutableArray<ModItem *> *items = [NSMutableArray array];

        if (!modsFolder) {
            if (completion) {
                dispatch_async(dispatch_get_main_queue(), ^{ completion(items); });
            }
            return;
        }

        NSArray<NSString *> *contents = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:modsFolder error:nil];
        dispatch_group_t group = dispatch_group_create();

        for (NSString *fileName in contents) {
            if ([fileName.lowercaseString hasSuffix:@".jar"] || [fileName.lowercaseString hasSuffix:@".jar.disabled"]) {
                NSString *fullPath = [modsFolder stringByAppendingPathComponent:fileName];

                // Check the cache.
                if (![self needsRescanForPath:fullPath]) {
                    ModItem *cached = [self cachedModForPath:fullPath];
                    if (cached) {
                        [items addObject:cached];
                        continue;
                    }
                }

                ModItem *mod = [[ModItem alloc] initWithFilePath:fullPath];
                [items addObject:mod];

                dispatch_group_enter(group);
                [self fetchMetadataForMod:mod completion:^(ModItem *populatedMod, NSError *error) {
                    if (!error) {
                        [self cacheModItem:populatedMod forPath:fullPath];
                        [self updateCheckpointForPath:fullPath];
                    }
                    dispatch_group_leave(group);
                }];
            }
        }

        dispatch_group_notify(group, dispatch_get_main_queue(), ^{
            [items sortUsingComparator:^NSComparisonResult(ModItem *obj1, ModItem *obj2) {
                NSString *name1 = obj1.displayName ?: obj1.fileName;
                NSString *name2 = obj2.displayName ?: obj2.fileName;
                return [name1 localizedCaseInsensitiveCompare:name2];
            }];
            if (completion) completion(items);
        });
    });
}

// ---------- Retrieve metadata (original logic, called only above) ----------
- (void)fetchMetadataForMod:(ModItem *)mod completion:(ModMetadataHandler)completion {
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        @try {
            // Fabric
            NSData *fabricData = [self readFileFromJar:mod.filePath entryName:@"fabric.mod.json"];
            if (fabricData) {
                NSDictionary *json = [NSJSONSerialization JSONObjectWithData:fabricData options:0 error:nil];
                if ([json isKindOfClass:[NSDictionary class]]) {
                    mod.isFabric = YES;
                    mod.onlineID = json[@"id"];
                    mod.version = json[@"version"];
                    mod.displayName = json[@"name"];
                    mod.modDescription = json[@"description"];
                    mod.author = [json[@"authors"] componentsJoinedByString:@", "];

                    NSDictionary *deps = json[@"depends"];
                    if ([deps isKindOfClass:[NSDictionary class]] && [deps[@"minecraft"] isKindOfClass:[NSString class]]) {
                        mod.gameVersion = deps[@"minecraft"];
                    }

                    NSString *iconPath = json[@"icon"];
                    if ([iconPath isKindOfClass:[NSString class]]) {
                        NSData *iconData = [self readFileFromJar:mod.filePath entryName:iconPath];
                        if (iconData) mod.icon = [[UIImage alloc] initWithData:iconData];
                    }
                    if (completion) completion(mod, nil);
                    return;
                }
            }

            // Forge / NeoForge
            NSData *tomlData = [self readFileFromJar:mod.filePath entryName:@"META-INF/mods.toml"];
            if (tomlData) {
                mod.isForge = YES;
            } else {
                tomlData = [self readFileFromJar:mod.filePath entryName:@"META-INF/neoforge.mods.toml"];
                if (tomlData) mod.isNeoForge = YES;
            }

            if (tomlData) {
                NSString *tomlString = [[NSString alloc] initWithData:tomlData encoding:NSUTF8StringEncoding];
                NSDictionary<NSString *, id> *toml = [self parseTomlString:tomlString];
                NSArray *mods = toml[@"mods"];
                if ([mods isKindOfClass:[NSArray class]] && mods.count > 0) {
                    NSDictionary *modInfo = mods.firstObject;
                    if ([modInfo isKindOfClass:[NSDictionary class]]) {
                        mod.onlineID = modInfo[@"modId"];
                        mod.version = modInfo[@"version"];
                        mod.displayName = modInfo[@"displayName"];
                        mod.modDescription = modInfo[@"description"];
                        mod.author = modInfo[@"authors"];

                        NSArray *deps = nil;
                        for (NSString *key in toml) {
                            if ([key hasPrefix:@"dependencies"]) {
                                deps = toml[key];
                                break;
                            }
                        }
                        if ([deps isKindOfClass:[NSArray class]]) {
                            for (NSDictionary *depInfo in deps) {
                                if ([depInfo isKindOfClass:[NSDictionary class]] && [depInfo[@"modId"] isEqualToString:@"minecraft"]) {
                                    mod.gameVersion = depInfo[@"versionRange"];
                                    break;
                                }
                            }
                        }

                        NSString *logoFile = modInfo[@"logoFile"];
                        if (logoFile.length > 0) {
                            NSData *logoData = [self readFileFromJar:mod.filePath entryName:logoFile];
                            if (logoData) mod.icon = [[UIImage alloc] initWithData:logoData];
                        }
                        if (completion) completion(mod, nil);
                        return;
                    }
                }
            }
        } @catch (NSException *exception) {
            NSLog(@"[ModService] CRITICAL: Exception while parsing %@: %@", mod.fileName, exception);
        }
        if (completion) completion(mod, nil);
    });
}

// ---------- File operations (enable/disable, delete) ----------
- (BOOL)toggleEnableForMod:(ModItem *)mod error:(NSError **)error {
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSString *currentPath = mod.filePath;
    NSString *newPath;

    if (mod.disabled) {
        if ([currentPath.lowercaseString hasSuffix:@".jar.disabled"]) {
            newPath = [currentPath substringToIndex:currentPath.length - 9];
        } else {
            if (error) *error = [NSError errorWithDomain:@"ModServiceError" code:101 userInfo:@{NSLocalizedDescriptionKey:localize(@"i18n_str_452", nil)}];
            return NO;
        }
    } else {
        newPath = [currentPath stringByAppendingString:@".disabled"];
    }

    BOOL success = [fileManager moveItemAtPath:currentPath toPath:newPath error:error];
    if (success) {
        mod.filePath = newPath;
        mod.fileName = [newPath lastPathComponent];
        [mod refreshDisabledFlag];
    }
    return success;
}

- (BOOL)deleteMod:(ModItem *)mod error:(NSError **)error {
    return [[NSFileManager defaultManager] removeItemAtPath:mod.filePath error:error];
}

// ---------- Download (PLDownloadClient unified downloader: mirror candidates + SHA1 validation + incremental hits + resume support) ----------
- (void)downloadMod:(ModItem *)mod toProfile:(NSString *)profileName completion:(ModDownloadHandler)completion {
    [self downloadMod:mod toProfile:profileName expectedSHA1:nil progress:nil completion:completion];
}

// ---------- Download with progress callback ----------
- (void)downloadMod:(ModItem *)mod
          toProfile:(NSString *)profileName
            progress:(void (^)(NSProgress *downloadProgress))progress
          completion:(ModDownloadHandler)completion {
    [self downloadMod:mod toProfile:profileName expectedSHA1:nil progress:progress completion:completion];
}

// ---------- Download with SHA1 validation (spec Task 5.1: providing expectedSHA1 enables validation) ----------
- (void)downloadMod:(ModItem *)mod
          toProfile:(NSString *)profileName
       expectedSHA1:(nullable NSString *)expectedSHA1
           progress:(nullable void (^)(NSProgress *downloadProgress))progress
         completion:(ModDownloadHandler)completion {
    NSString *modsFolder = [self existingModsFolderForProfile:profileName];
    if (!modsFolder) {
        if (completion) {
            NSError *error = [NSError errorWithDomain:@"ModServiceError" code:1 userInfo:@{NSLocalizedDescriptionKey:localize(@"i18n_str_453", nil)}];
            dispatch_async(dispatch_get_main_queue(), ^{ completion(error); });
        }
        return;
    }

    NSURL *url = [NSURL URLWithString:mod.selectedVersionDownloadURL];
    if (!url) {
        if (completion) {
            NSError *error = [NSError errorWithDomain:@"ModServiceError" code:2 userInfo:@{NSLocalizedDescriptionKey:localize(@"i18n_str_454", nil)}];
            dispatch_async(dispatch_get_main_queue(), ^{ completion(error); });
        }
        return;
    }

    NSString *destinationPath = [modsFolder stringByAppendingPathComponent:mod.fileName];

    // Register with the unified download task manager (rawTask is later set to PLDownloadOperation; the floating bubble was removed,
    // so always register for tracking in the download task list).
    NSString *resourceName = mod.fileName.length > 0 ? mod.fileName : (mod.displayName.length > 0 ? mod.displayName : @"mod");
    NSString *displayName = mod.displayName.length > 0 ? mod.displayName : resourceName;
    NSString *downloadSource = getPrefObject(@"general.download_source") ?: @"official";
    DownloadTaskItem *taskItem = [[DownloadTaskManager sharedManager]
        registerTaskWithResourceType:DownloadTaskResourceTypeMod
                        resourceName:resourceName
                         displayName:displayName
                      downloadSource:downloadSource
                             rawTask:nil
                      supportsResume:YES
                             iconURL:mod.iconURL];
    taskItem.downloadURL = mod.selectedVersionDownloadURL;
    // redesign-download-ui Phase 4: integrate single-file downloads with the unified progress page —
    // PLTaskStagesSingleFile single stage + autoPresentDetail automatically presents PLTaskProgressViewController.
    [[DownloadTaskManager sharedManager] setTaskWithId:taskItem.taskId stages:PLTaskStagesSingleFile()];
    taskItem.autoPresentDetail = YES;

    // retryHandler: FCL-style retry; reuse the same taskItem and issue a new PLDownloadClient request.
    __weak typeof(self) weakSelf = self;
    taskItem.retryHandler = ^id(DownloadTaskItem *taskItemRef) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return nil;
        return [strongSelf restartPLDownloadForTaskId:taskItemRef.taskId];
    };

    PLDownloadRequest *request = [[PLDownloadRequest alloc] init];
    // Mirror candidates: original CDN URLs (cdn.modrinth.com / edge.forgecdn.net, etc.) + MCIM mirrors,
    // sorted by the download.assetDownloadSource policy (centralized in PLMirrorCenter, replacing the old standalone mirror utility).
    request.candidateURLs = [PLMirrorCenter candidateURLsForOriginalURL:url
                                                          resourceType:PLMirrorResourceTypeAssetDownload];
    // Task 5.1: providing expectedSHA1 (version model files[].hashes.sha1) enables SHA1 validation;
    // PLDownloadClient retries validation failures using mirror/backoff logic.
    request.expectedSHA1 = expectedSHA1;
    // Task 5.2: if the destination already exists and passes validation, PLDownloadClient succeeds without network traffic (incremental download);
    // destination path semantics match the original implementation (mods/<fileName>.jar).
    request.destinationPath = destinationPath;
    // Use DownloadTaskManager's taskId as taskIdentifier so resumeData can be reused across download attempts.
    request.taskIdentifier = taskItem.taskId;
    // If SHA1 is unavailable, use EOCD as a fallback integrity check for .jar files (ZIP format).
    request.allowZipFallbackCheck = YES;

    [self startPLDownloadWithRequest:request taskItem:taskItem progress:progress completion:completion];
}

#pragma mark - PLDownloadClient wrapper (accumulate progress deltas / sample speed / dispatch completion)

/// Starts (or retries) a PLDownloadClient request and attaches progress, speed, and completion callbacks.
/// If progress/completion is nil, does not overwrite the registered callback (retryHandler reuses the original callback).
- (nullable PLDownloadOperation *)startPLDownloadWithRequest:(PLDownloadRequest *)request
                                                     taskItem:(DownloadTaskItem *)taskItem
                                                     progress:(nullable void(^)(NSProgress *))progress
                                                   completion:(nullable ModDownloadHandler)completion {
    NSString *taskId = taskItem.taskId;
    __weak typeof(self) weakSelf = self;

    [self.downloadStateLock lock];
    NSInteger generation = [self.downloadGenerations[taskId] integerValue] + 1;
    self.downloadGenerations[taskId] = @(generation);
    self.downloadTaskItems[taskId] = taskItem;
    self.downloadRequests[taskId] = request;
    if (progress) self.downloadProgressHandlers[taskId] = progress;
    if (completion) self.downloadCompletionHandlers[taskId] = completion;
    // Restart from the beginning on retry: reset the accumulated total (PLDownloadClient's negative-delta rollback is consistent within an operation).
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
        // Invalid argument: PLDownloadClient calls completion asynchronously with an error; the unified failure path handles cleanup.
        return nil;
    }

    [self.downloadStateLock lock];
    self.downloadOperations[taskId] = operation;
    [self.downloadStateLock unlock];

    // rawTask is a weak reference: PLDownloadClient and this Service jointly retain the operation,
    // allowing DownloadTaskManager to pause/resume/cancel PLDownloadOperation.
    taskItem.rawTask = operation;
    // Occupy a concurrency slot (if full, DownloadTaskManager queues it by calling pauseOperation automatically).
    [[DownloadTaskManager sharedManager] setTaskWithId:taskId state:DownloadTaskStateDownloading];
    // redesign-download-ui Phase 4: set stage 0 to Running when a single-stage task begins downloading.
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

/// Accumulates progress deltas: add negative deltas (rollback on mirror switch/retry/invalid resume data) to match actual progress.
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
    void (^progressHandler)(NSProgress *) = self.downloadProgressHandlers[taskId];
    [self.downloadStateLock unlock];

    double fraction = totalStored > 0 ? (double)accumulated / (double)totalStored : -1.0;
    [[DownloadTaskManager sharedManager] updateTaskWithId:taskId
                                                 progress:fraction
                                               totalBytes:totalStored
                                          downloadedBytes:accumulated];
    // redesign-download-ui Phase 4: keep single-stage progress in sync with total task progress.
    [[DownloadTaskManager sharedManager] updateTaskWithId:taskId
                                              stageAtIndex:0
                                                  progress:fraction
                                                 message:nil];

    if (!progressHandler) return;

    // Build an NSProgress with throughput/ETA for the caller (DownloadViewController)
    // to display speed and ETA on the FCL-style download progress card.
    NSProgress *downloadProgress = [NSProgress progressWithTotalUnitCount:totalStored > 0 ? totalStored : -1];
    downloadProgress.completedUnitCount = accumulated;
    if (lastSpeed > 0) {
        downloadProgress.throughput = @(lastSpeed);
        if (totalStored > accumulated) {
            downloadProgress.estimatedTimeRemaining = @((double)(totalStored - accumulated) / lastSpeed);
        }
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        progressHandler(downloadProgress);
    });
}

/// Samples download speed (PLDownloadClient calls once per second; reports 0 on completion/pause).
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

/// Dispatches completion: updates DownloadTaskManager state and calls back to the client (on the main thread).
- (void)handlePLDownloadCompletion:(BOOL)success
                             error:(nullable NSError *)error
                            taskId:(NSString *)taskId
                         generation:(NSInteger)generation {
    [self.downloadStateLock lock];
    if ([self.downloadGenerations[taskId] integerValue] != generation) {
        [self.downloadStateLock unlock];
        return;
    }
    ModDownloadHandler completion = self.downloadCompletionHandlers[taskId];
    [self cleanupPLDownloadStateForTaskId:taskId];
    [self.downloadStateLock unlock];

    DownloadTaskManager *manager = [DownloadTaskManager sharedManager];
    if (success) {
        [manager updateTaskWithId:taskId stageAtIndex:0 status:PLTaskStageStatusCompleted];
        [manager setTaskWithId:taskId state:DownloadTaskStateCompleted];
    } else if ([error.domain isEqualToString:NSURLErrorDomain] && error.code == NSURLErrorCancelled) {
        // User cancellation (DownloadTaskManager already set Cancelled; keep this idempotently aligned).
        [manager setTaskWithId:taskId state:DownloadTaskStateCancelled];
    } else {
        [manager updateTaskWithId:taskId stageAtIndex:0 status:PLTaskStageStatusFailed];
        [manager updateTaskWithId:taskId error:error];
        [manager setTaskWithId:taskId state:DownloadTaskStateFailed];
    }

    if (completion) {
        NSError *capturedError = success ? nil : error;
        dispatch_async(dispatch_get_main_queue(), ^{
            completion(capturedError);
        });
    }
}

/// Clears all tracking state for the specified task (must be called inside downloadStateLock).
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