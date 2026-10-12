//
//  AiLogReader.m
//  Amethyst
//

#import "AiLogReader.h"
#import "LauncherPreferences.h"

@interface AiLogReader ()
@property (nonatomic, copy) NSString *internalName;
@end

@implementation AiLogReader

- (instancetype)initWithName:(NSString *)name {
    self = [super init];
    if (self) {
        _internalName = [name copy] ?: @"";
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
    if ([self.internalName isEqualToString:@"read_crash_report"]) {
        return @"Read the most recent crash report (the .txt file with the latest modification time in the crash-report directory)."
               "\nParameter: instance (string, optional, instance/game directory name; defaults to the currently selected instance)."
               "\nDetails: read logs/crash-reports/ first, then fall back to crash-reports/; return the latest .txt contents, truncated to the last 6000 characters."
               "\nBoundary: returns \"Crash report not found\" if the directory or file does not exist.";
    }
    if ([self.internalName isEqualToString:@"read_logs"]) {
        return @"Read multiple logs in parallel (the preferred tool for troubleshooting)."
               "\nParameters: logs (array, optional; items: latest.log=game log / latestlog.txt=launcher log / latestlog.old.txt=previous launcher log / crash-report=latest crash report), "
               "all (boolean, optional; true reads all of the above logs), instance (string, optional, instance name; defaults to the currently selected instance)."
               "\nImportant: launcher log latestlog.txt usually already contains the game log (stdout/stderr redirection); prioritize reading it when troubleshooting."
               "\nReturns a JSON array: {key, path, size, lastModified, content (each truncated to the last 4000 characters)}; missing files are marked as missing.";
    }
    // read_latest_log
    return @"Read the most recent launch log for an instance (logs/latest.log)."
           "\nParameter: instance (string, optional, instance/game directory name; defaults to the currently selected instance)."
           "\nDetails: returns the last 4000 characters of the log (if too long, the beginning is truncated and noted). Returns \"Log not found\" if the file does not exist."
           "\nTip: use read_logs for launcher-level logs (POJAV_HOME/latestlog.txt, which includes the game log)."
           "\nBoundary: reads .log files only; never reads other file types.";
}

#pragma mark - Paths

/// Launcher home directory (POJAV_HOME, falling back to Documents)
+ (NSString *)launcherHome {
    const char *home = getenv("POJAV_HOME");
    if (home && strlen(home) > 0) return @(home);
    return [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
}

/// Current instance root directory (POJAV_GAME_DIR or its fallback)
+ (NSString *)currentGameRoot {
    const char *root = getenv("POJAV_GAME_DIR");
    if (root && strlen(root) > 0) return @(root);
    const char *home = getenv("POJAV_HOME");
    if (home && strlen(home) > 0) {
        NSString *name = getPrefObject(@"general.game_directory");
        if (name.length == 0) name = @"default";
        return [NSString stringWithFormat:@"%s/instances/%@", home, name];
    }
    return [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
}

/// Resolve the instance parameter → instance root directory (<POJAV_HOME>/instances/<instance>; defaults to the current instance)
+ (NSString *)gameRootForParams:(NSDictionary *)params {
    NSString *instance = [params[@"instance"] isKindOfClass:[NSString class]] ? params[@"instance"] : @"";
    if (instance.length == 0) return [self currentGameRoot];
    // Sanitize directory name to prevent ../ traversal
    NSArray *parts = [instance componentsSeparatedByCharactersInSet:
                      [NSCharacterSet characterSetWithCharactersInString:@"/\\:"]];
    NSString *safe = [parts componentsJoinedByString:@"_"];
    NSString *root = [NSString stringWithFormat:@"%@/instances/%@", [self launcherHome], safe];
    BOOL isDir = NO;
    if ([[NSFileManager defaultManager] fileExistsAtPath:root isDirectory:&isDir] && isDir) {
        return root;
    }
    // Fallback: treat as the current instance (return the original joined path if the directory does not exist; the reader reports it as missing)
    return root;
}

/// Truncate content: retain the last N characters and note at the beginning if truncated
- (NSString *)truncatedContent:(NSString *)content maxChars:(NSUInteger)max header:(NSString *)header {
    if (content.length <= max) return content;
    NSString *tail = [content substringFromIndex:(content.length - max)];
    return [header stringByAppendingString:tail];
}

/// Read file (UTF-8 → Latin1 fallback)
+ (NSString *)contentAtPath:(NSString *)path {
    NSString *content = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil];
    if (!content) content = [NSString stringWithContentsOfFile:path encoding:NSISOLatin1StringEncoding error:nil];
    return content;
}

/// Parse a boolean parameter (supports JSON true/false, NSNumber, and the strings "true"/"false")
+ (BOOL)boolFromValue:(id)value {
    if (!value || [value isKindOfClass:[NSNull class]]) return NO;
    if ([value isKindOfClass:[NSString class]]) {
        NSString *s = [(NSString *)value lowercaseString];
        return [s hasPrefix:@"t"] || [s isEqualToString:@"1"] || [s isEqualToString:@"yes"];
    }
    return [value boolValue];
}

- (void)execute:(NSDictionary<NSString *, id> *)params
     completion:(void (^)(NSString * _Nullable result, NSError * _Nullable error))completion {
    if (!completion) return;

    NSString *gameRoot = [[self class] gameRootForParams:params];

    if ([self.internalName isEqualToString:@"read_crash_report"]) {
        NSString *content = [self latestCrashReportInGameRoot:gameRoot];
        completion(content ?: @"Crash report not found", nil);
        return;
    }
    if ([self.internalName isEqualToString:@"read_logs"]) {
        [self performReadLogs:params gameRoot:gameRoot completion:completion];
        return;
    }
    if ([self.internalName isEqualToString:@"read_latest_log"]) {
        NSString *logPath = [gameRoot stringByAppendingPathComponent:@"logs/latest.log"];
        NSFileManager *fm = [NSFileManager defaultManager];
        BOOL isDir = NO;
        if (![fm fileExistsAtPath:logPath isDirectory:&isDir] || isDir) {
            completion(@"Log not found", nil);
            return;
        }
        NSString *content = [AiLogReader contentAtPath:logPath];
        if (!content) {
            completion(@"Failed to read log", nil);
            return;
        }
        NSString *result = [self truncatedContent:content
                                          maxChars:4000
                                            header:@"(Log too long; truncated to the last 4000 characters)\n"];
        completion(result, nil);
        return;
    }

    NSError *err = [NSError errorWithDomain:@"AiTool" code:404
                                   userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Unknown tool %@", self.internalName]}];
    completion(nil, err);
}

#pragma mark - read_logs

- (void)performReadLogs:(NSDictionary *)params
               gameRoot:(NSString *)gameRoot
             completion:(void (^)(NSString *, NSError *))completion {
    // Collect the list of log keys to read
    NSMutableArray *keys = [NSMutableArray array];
    BOOL all = [AiLogReader boolFromValue:params[@"all"]];
    id logsParam = params[@"logs"];
    if (all) {
        [keys addObjectsFromArray:@[@"latestlog.txt", @"latestlog.old.txt", @"latest.log", @"crash-report"]];
    } else if ([logsParam isKindOfClass:[NSArray class]]) {
        for (id item in (NSArray *)logsParam) {
            if ([item isKindOfClass:[NSString class]] && [(NSString *)item length] > 0) {
                [keys addObject:item];
            }
        }
    } else if ([logsParam isKindOfClass:[NSString class]] && [(NSString *)logsParam length] > 0) {
        [keys addObject:logsParam];
    }
    if (keys.count == 0) {
        keys = [@[ @"latestlog.txt", @"latest.log" ] mutableCopy]; // Read launcher log + game log by default
    }
    // Deduplicate (preserve order)
    NSMutableArray *uniqueKeys = [NSMutableArray array];
    for (NSString *k in keys) {
        if (![uniqueKeys containsObject:k]) [uniqueKeys addObject:k];
    }

    // Resolve key → physical path (latestlog* in POJAV_HOME; others in the instance directory)
    NSString *home = [AiLogReader launcherHome];
    __block NSMutableArray *entries = [NSMutableArray array];
    dispatch_group_t group = dispatch_group_create();
    dispatch_queue_t readQueue = dispatch_queue_create("ai.log.read", DISPATCH_QUEUE_CONCURRENT);

    for (NSString *key in uniqueKeys) {
        dispatch_group_enter(group);
        dispatch_async(readQueue, ^{
            NSString *path = nil;
            if ([key isEqualToString:@"latestlog.txt"]) {
                path = [home stringByAppendingPathComponent:@"latestlog.txt"];
            } else if ([key isEqualToString:@"latestlog.old.txt"]) {
                path = [home stringByAppendingPathComponent:@"latestlog.old.txt"];
            } else if ([key isEqualToString:@"latest.log"] || [key containsString:@"latest.log"]) {
                path = [gameRoot stringByAppendingPathComponent:@"logs/latest.log"];
            } else if ([key containsString:@"crash"]) {
                path = [self latestCrashReportPathInGameRoot:gameRoot];
            } else {
                path = key; // Direct path: only relative paths within the instance directory are allowed
                if (![path hasPrefix:@"/"]) path = [gameRoot stringByAppendingPathComponent:path];
            }

            if (path.length == 0) {
                @synchronized (entries) {
                    [entries addObject:@{@"key": key, @"missing": @YES}];
                }
                dispatch_group_leave(group);
                return;
            }

            NSFileManager *fm = [NSFileManager defaultManager];
            BOOL isDir = NO;
            if (![fm fileExistsAtPath:path isDirectory:&isDir] || isDir) {
                @synchronized (entries) {
                    [entries addObject:@{@"key": key, @"missing": @YES, @"path": path}];
                }
                dispatch_group_leave(group);
                return;
            }

            NSDictionary *attrs = [fm attributesOfItemAtPath:path error:nil];
            NSString *content = [AiLogReader contentAtPath:path];
            NSString *truncated = content
                ? [self truncatedContent:content maxChars:4000
                                  header:@"(Too long; truncated to the last 4000 characters)\n"]
                : @"(Read failed)";
            NSDate *mtime = attrs[NSFileModificationDate];
            @synchronized (entries) {
                [entries addObject:@{
                    @"key": key,
                    @"path": path,
                    @"size": @([attrs[NSFileSize] integerValue]),
                    @"lastModified": mtime ? [mtime description] : @"",
                    @"content": truncated ?: @"",
                }];
            }
            dispatch_group_leave(group);
        });
    }

    dispatch_group_notify(group, dispatch_get_main_queue(), ^{
        // Sort output in the original key order
        NSMutableArray *sorted = [NSMutableArray array];
        for (NSString *key in uniqueKeys) {
            for (NSDictionary *e in entries) {
                if ([e[@"key"] isEqualToString:key]) {
                    [sorted addObject:e];
                    break;
                }
            }
        }
        NSError *jsonError = nil;
        NSData *data = [NSJSONSerialization dataWithJSONObject:@{@"logs": sorted}
                                                    options:NSJSONWritingPrettyPrinted
                                                      error:&jsonError];
        if (!data || jsonError) {
            completion([NSString stringWithFormat:@"Read %lu logs (serialization failed)", (unsigned long)sorted.count], nil);
            return;
        }
        completion([[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding], nil);
    });
}

/// Find the latest crash report path (prefer logs/crash-reports/, fall back to crash-reports/)
- (NSString *)latestCrashReportPathInGameRoot:(NSString *)gameRoot {
    NSArray *candidates = @[
        [gameRoot stringByAppendingPathComponent:@"logs/crash-reports"],
        [gameRoot stringByAppendingPathComponent:@"crash-reports"],
    ];
    NSString *bestPath = nil;
    NSDate *bestDate = nil;
    NSFileManager *fm = [NSFileManager defaultManager];

    for (NSString *dir in candidates) {
        BOOL isDir = NO;
        if (![fm fileExistsAtPath:dir isDirectory:&isDir] || !isDir) continue;
        NSArray *files = [fm contentsOfDirectoryAtPath:dir error:nil];
        for (NSString *file in files) {
            if (![file hasSuffix:@".txt"]) continue;
            NSString *full = [dir stringByAppendingPathComponent:file];
            NSDictionary *attrs = [fm attributesOfItemAtPath:full error:nil];
            if (!attrs[NSFileType] || [NSFileTypeDirectory isEqualToString:attrs[NSFileType]]) continue;
            NSDate *mtime = attrs[NSFileModificationDate];
            if (!mtime) mtime = [NSDate distantPast];
            if (bestDate == nil || [mtime compare:bestDate] == NSOrderedDescending) {
                bestDate = mtime;
                bestPath = full;
            }
        }
    }
    return bestPath;
}

/// Find the latest crash report content (prefer logs/crash-reports/, fall back to crash-reports/)
- (NSString *)latestCrashReportInGameRoot:(NSString *)gameRoot {
    NSString *bestPath = [self latestCrashReportPathInGameRoot:gameRoot];
    if (!bestPath) return nil;

    NSString *content = [AiLogReader contentAtPath:bestPath];
    if (!content) return nil;

    return [self truncatedContent:content maxChars:6000 header:@"(Crash report too long; truncated to the last 6000 characters)\n"];
}

@end
