//
//  AiInstancesTool.m
//  Amethyst
//

#import "AiInstancesTool.h"
#import "PLProfiles.h"
#import "LauncherPreferences.h"
#import "utils.h"   // ★ [VER-ISOLATE-PCL] Shared version-isolation resolution

@interface AiInstancesTool ()
@property (nonatomic, copy) NSString *internalName;
@end

@implementation AiInstancesTool

- (instancetype)initWithName:(NSString *)name {
    self = [super init];
    if (self) {
        _internalName = name ?: @"";
    }
    return self;
}

- (NSString *)name {
    return self.internalName;
}

- (AiToolPermission)permission {
    return AiToolPermissionReadOnly;
}

- (NSString *)summary {
    if ([self.internalName isEqualToString:@"list_game_versions"]) {
        return @"Fetch the actual Minecraft Java version list (returns releases only by default to avoid using too much context for snapshots and other versions)."
               "\nParameter: includeSnapshots (boolean, optional, defaults to false; if true, also include the latest snapshot version)."
               "\nDetails: fetches the version manifest from the BMCLAPI mirror by default and automatically retries with the official source on failure; returns each version's id (version number) and type (release/snapshot)."
               "\nA 30-minute cache is used internally (stored in Documents/AI/game_versions.json; caches the complete manifest)."
               "\nBoundary: returns an error if the network request fails; it does not invent version numbers."
               "\nExample: [{'id':'1.21.1','type':'release'}, ...]";
    }
    // list_instances
    return @"List game instances created in the launcher (versions/directories under the game directory)."
           "\nNo parameters."
           "\nDetails: each instance item includes the profile name, name, gameDir, lastVersionId, whether it is currently selected, selected, "
           "the full instance path, path, and counts of installed mods/resourcepacks/shaders/datapacks (counts sub-object)."
           "\nData comes from the POJAV_HOME/instances/ directory and the profiles in launcher_profiles.json."
           "\nBoundary: if the instance directory does not exist, fall back to returning current instance information.";
}

#pragma mark - Paths and constants

+ (NSString *)pojavHome {
    const char *home = getenv("POJAV_HOME");
    if (home && strlen(home) > 0) return @(home);
    return [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
}

+ (NSString *)instancesDirectory {
    return [[self pojavHome] stringByAppendingPathComponent:@"instances"];
}

+ (NSString *)currentInstanceName {
    NSString *name = getPrefObject(@"general.game_directory");
    return (name.length > 0) ? name : @"default";
}

+ (NSString *)currentGameRoot {
    const char *root = getenv("POJAV_GAME_DIR");
    if (root && strlen(root) > 0) return @(root);
    return [[self instancesDirectory] stringByAppendingPathComponent:[self currentInstanceName]];
}

#pragma mark - Asset counts

- (NSUInteger)countOfDirectory:(NSString *)dir {
    NSArray *items = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:dir error:nil];
    NSUInteger count = 0;
    for (NSString *item in items) {
        if ([item hasPrefix:@"."]) continue;
        count++;
    }
    return count;
}

- (NSDictionary *)resourceCountsForDirectory:(NSString *)gameRoot {
    return @{
        @"mods": @([self countOfDirectory:[gameRoot stringByAppendingPathComponent:@"mods"]]),
        @"resourcepacks": @([self countOfDirectory:[gameRoot stringByAppendingPathComponent:@"resourcepacks"]]),
        @"shaders": @([self countOfDirectory:[gameRoot stringByAppendingPathComponent:@"shaderpacks"]]),
        @"datapacks": @([self countOfDirectory:[gameRoot stringByAppendingPathComponent:@"datapacks"]]),
    };
}

- (NSString *)jsonStringFromObject:(id)object {
    if ([NSJSONSerialization isValidJSONObject:object] == NO) return @"[]";
    NSData *data = [NSJSONSerialization dataWithJSONObject:object options:0 error:nil];
    if (!data) return @"[]";
    return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
}

#pragma mark - Execute

- (void)execute:(NSDictionary<NSString *, id> *)params
     completion:(void (^)(NSString * _Nullable result, NSError * _Nullable error))completion {
    if (!completion) return;

    if ([self.internalName isEqualToString:@"list_game_versions"]) {
        BOOL includeSnapshots = NO;
        id v = params[@"includeSnapshots"];
        if ([v isKindOfClass:[NSString class]]) {
            NSString *s = [(NSString *)v lowercaseString];
            includeSnapshots = [s hasPrefix:@"t"] || [s isEqualToString:@"1"];
        } else if (v != nil && ![v isKindOfClass:[NSNull class]]) {
            includeSnapshots = [v boolValue];
        }
        [self performListGameVersionsIncludeSnapshots:includeSnapshots completion:completion];
        return;
    }
    if ([self.internalName isEqualToString:@"list_instances"]) {
        [self performListInstances:completion];
        return;
    }

    NSError *err = [NSError errorWithDomain:@"AiTool" code:404
                                   userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Unknown tool %@", self.internalName]}];
    completion(nil, err);
}

#pragma mark - list_instances

- (void)performListInstances:(void (^)(NSString * _Nullable result, NSError * _Nullable error))completion {
    NSString *instancesDir = [[self class] instancesDirectory];
    NSString *currentInstanceName = [[self class] currentInstanceName];
    PLProfiles *profiles = [PLProfiles current];
    NSDictionary *profileDict = [profiles profiles];

    NSMutableArray *entries = [NSMutableArray array];

    // List subdirectories under instances/ (each instance is a game directory)
    NSArray *subdirs = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:instancesDir error:nil];
    for (NSString *dirname in subdirs) {
        NSString *fullPath = [instancesDir stringByAppendingPathComponent:dirname];
        BOOL isDir = NO;
        if ([[NSFileManager defaultManager] fileExistsAtPath:fullPath isDirectory:&isDir] == NO || !isDir) {
            continue;
        }
        if ([dirname hasPrefix:@"."]) continue;

        // Find the profile in launcher_profiles.json (match the name to the directory name)
        NSDictionary *profile = [profileDict isKindOfClass:[NSDictionary class]] ? profileDict[dirname] : nil;
        NSString *profileName = dirname;
        NSString *lastVersionId = @"";
        NSString *gameDir = @".";
        if ([profile isKindOfClass:[NSDictionary class]]) {
            if ([profile[@"name"] isKindOfClass:[NSString class]] && [profile[@"name"] length] > 0) profileName = profile[@"name"];
            if ([profile[@"lastVersionId"] isKindOfClass:[NSString class]]) lastVersionId = profile[@"lastVersionId"];
            // ★ [VER-ISOLATE-PCL] Shared version-isolation resolution (isolation on → versions/<version id>, off → ".")
            gameDir = amePCLVersionGameDirSubpath(profile, nil);
        }

        [entries addObject:@{
            @"name": profileName ?: dirname,
            @"gameDir": [fullPath stringByAppendingPathComponent:gameDir],
            @"lastVersionId": lastVersionId ?: @"",
            @"selected": @([dirname isEqualToString:currentInstanceName]),
            @"path": fullPath,
            @"counts": [self resourceCountsForDirectory:fullPath],
        }];
    }

    // If no instance directory is available, fall back to current instance information
    if (entries.count == 0) {
        NSString *currentRoot = [[self class] currentGameRoot];
        [entries addObject:@{
            @"name": [profiles selectedProfileName] ?: currentInstanceName,
            @"gameDir": currentRoot,
            @"lastVersionId": [PLProfiles resolveKeyForCurrentProfile:@"lastVersionId"] ?: @"",
            @"selected": @YES,
            @"path": currentRoot,
            @"counts": [self resourceCountsForDirectory:currentRoot],
        }];
    }

    completion([self jsonStringFromObject:entries], nil);
}

#pragma mark - list_game_versions

/// Version manifest cache path: Documents/AI/game_versions.json (valid for 30 minutes)
- (NSString *)gameVersionsCachePath {
    NSString *aiDir = [[NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject]
                       stringByAppendingPathComponent:@"AI"];
    [[NSFileManager defaultManager] createDirectoryAtPath:aiDir withIntermediateDirectories:YES attributes:nil error:nil];
    return [aiDir stringByAppendingPathComponent:@"game_versions.json"];
}

- (BOOL)isCacheFreshAtPath:(NSString *)path {
    NSDictionary *attrs = [[NSFileManager defaultManager] attributesOfItemAtPath:path error:nil];
    NSDate *mtime = attrs[NSFileModificationDate];
    if (!mtime) return NO;
    return ([[NSDate date] timeIntervalSinceDate:mtime] < 30 * 60); // 30 minutes
}

/// Version manifest sources: BMCLAPI mirror by default, automatically retry official source on failure
- (NSArray<NSString *> *)versionManifestURLStrings {
    return @[
        @"https://bmclapi2.bangbang93.com/mc/game/version_manifest_v2.json",
        @"https://piston-meta.mojang.com/mc/game/version_manifest_v2.json",
    ];
}

- (void)performListGameVersions:(void (^)(NSString * _Nullable result, NSError * _Nullable error))completion {
    [self performListGameVersionsIncludeSnapshots:NO completion:completion];
}

- (void)performListGameVersionsIncludeSnapshots:(BOOL)includeSnapshots
                                     completion:(void (^)(NSString * _Nullable result, NSError * _Nullable error))completion {
    NSString *cachePath = [self gameVersionsCachePath];

    // Cache hit and not expired (cache complete manifest, including all types; filter by parameter before returning)
    if ([self isCacheFreshAtPath:cachePath]) {
        NSData *cached = [NSData dataWithContentsOfFile:cachePath];
        if (cached) {
            NSArray *cachedVersions = [NSJSONSerialization JSONObjectWithData:cached options:0 error:nil];
            if ([cachedVersions isKindOfClass:[NSArray class]] && cachedVersions.count > 0) {
                NSString *filtered = [self filteredVersionsJSON:cachedVersions includeSnapshots:includeSnapshots];
                if (filtered.length > 0) {
                    completion(filtered, nil);
                    return;
                }
            }
        }
    }

    NSArray *urlStrings = [self versionManifestURLStrings];
    [self fetchManifestFromSources:urlStrings
                            index:0
                     lastError:nil
                    completion:^(NSArray * _Nullable versions, NSString * _Nullable sourceUsed, NSError * _Nullable error) {
        if (error) {
            dispatch_async(dispatch_get_main_queue(), ^{ completion(nil, error); });
            return;
        }
        // Write cache (complete manifest)
        NSString *fullJSON = [self jsonStringFromObject:versions];
        NSData *resultData = [fullJSON dataUsingEncoding:NSUTF8StringEncoding];
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
            [resultData writeToFile:cachePath atomically:YES];
        });
        NSString *resultJSON = [self filteredVersionsJSON:versions includeSnapshots:includeSnapshots];
        dispatch_async(dispatch_get_main_queue(), ^{
            completion([NSString stringWithFormat:@"%@\n(Data source: %@)", resultJSON, sourceUsed ?: @"bmclapi"], nil);
        });
    }];
}

/// Try the source list in order to fetch the version manifest (BMCLAPI → official fallback)
- (void)fetchManifestFromSources:(NSArray<NSString *> *)urlStrings
                           index:(NSUInteger)index
                      lastError:(NSError * _Nullable)lastError
                      completion:(void (^)(NSArray * _Nullable versions, NSString * _Nullable sourceUsed, NSError * _Nullable error))completion {
    if (index >= urlStrings.count) {
        NSString *detail = lastError.localizedDescription ?: @"Unknown error";
        completion(nil, nil, [NSError errorWithDomain:@"AiTool" code:500
                                             userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Failed to fetch version list (BMCLAPI and official source are both unavailable): %@", detail]}]);
        return;
    }
    NSString *urlString = urlStrings[index];
    NSURL *url = [NSURL URLWithString:urlString];
    if (!url) {
        [self fetchManifestFromSources:urlStrings index:index + 1 lastError:lastError completion:completion];
        return;
    }

    NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithURL:url completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        NSError *parseError = nil;
        NSArray *versions = nil;
        if (!error && data) {
            NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
            if ([json isKindOfClass:[NSDictionary class]] && [json[@"versions"] isKindOfClass:[NSArray class]]) {
                NSMutableArray *parsed = [NSMutableArray array];
                for (id item in json[@"versions"]) {
                    if (![item isKindOfClass:[NSDictionary class]]) continue;
                    NSString *vid = item[@"id"];
                    NSString *vtype = item[@"type"];
                    if (![vid isKindOfClass:[NSString class]] || vid.length == 0) continue;
                    [parsed addObject:@{
                        @"id": vid,
                        @"type": [vtype isKindOfClass:[NSString class]] ? (vtype ?: @"") : @"",
                    }];
                }
                if (parsed.count > 0) versions = parsed;
            }
            if (!versions) {
                parseError = [NSError errorWithDomain:@"AiTool" code:500
                                              userInfo:@{NSLocalizedDescriptionKey: @"Invalid version manifest format"}];
            }
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            if (versions) {
                NSString *sourceUsed = [urlString containsString:@"bmclapi"] ? @"BMCLAPI" : @"official";
                completion(versions, sourceUsed, nil);
                return;
            }
            // Current source failed → try the next source
            NSError *err = error ?: parseError;
            [self fetchManifestFromSources:urlStrings index:index + 1 lastError:err completion:completion];
        });
    }];
    [task resume];
}

/// Filter version manifest: releases only by default; append the latest snapshot when includeSnapshots is enabled
- (NSString *)filteredVersionsJSON:(NSArray *)versions includeSnapshots:(BOOL)includeSnapshots {
    NSMutableArray *filtered = [NSMutableArray array];
    NSDictionary *latestSnapshot = nil;
    for (id item in versions) {
        if (![item isKindOfClass:[NSDictionary class]]) continue;
        NSString *vtype = item[@"type"];
        if ([vtype isEqualToString:@"release"]) {
            [filtered addObject:item];
        } else if (includeSnapshots && [vtype isEqualToString:@"snapshot"] && !latestSnapshot) {
            latestSnapshot = item; // The manifest is sorted newest to oldest; the first is the latest
        }
    }
    if (latestSnapshot) [filtered addObject:latestSnapshot];
    return [self jsonStringFromObject:filtered];
}

@end