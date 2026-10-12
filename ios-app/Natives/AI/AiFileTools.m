//
//  AiFileTools.m
//  Amethyst
//

#import "AiFileTools.h"
#import "LauncherPreferences.h"

static NSString * const kAiToolDomain = @"AiTool";

@interface AiFileTools ()
@property (nonatomic, copy) NSString *internalName;
@end

@implementation AiFileTools

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
    if ([self.internalName isEqualToString:@"write_file"] || [self.internalName isEqualToString:@"edit_file"]) {
        return AiToolPermissionControlledWrite;
    }
    if ([self.internalName isEqualToString:@"delete_file"]) {
        return AiToolPermissionDangerousWrite;
    }
    return AiToolPermissionReadOnly;
}

- (NSString *)summary {
    if ([self.internalName isEqualToString:@"list_files"]) {
        return @"List files/subdirectories in the specified directory (not recursive)."
               "\nParameter: path (string, optional, defaults to the current instance root directory)."
               "\nReturns a JSON array; each item contains name, type (file/dir), size (bytes), and modifiedUnixTS (modification timestamp), sorted by name.";
    }
    if ([self.internalName isEqualToString:@"read_file"]) {
        return @"Read the contents of a text file."
               "\nParameters: path (string, required), maxChars (number, optional, defaults to 8000; truncate if longer)."
               "\nReturns the file text; returns \"Binary file is not readable\" for binary files.";
    }
    if ([self.internalName isEqualToString:@"grep_files"]) {
        return @"Search a file for matching lines using a regular expression."
               "\nParameters: path (string, optional, defaults to the current instance root directory), pattern (string, required, regular expression), "
               "recursive (boolean, optional, defaults to NO), maxResults (number, optional, defaults to 50)."
               "\nReturns a JSON array {path, lineNumber, line}.";
    }
    if ([self.internalName isEqualToString:@"write_file"]) {
        return @"Write a text file (atomic write; automatically creates parent directories)."
               "\nParameters: path (string, required), content (string, required)."
               "\nReturns \"Written (N characters).\" Overwrites existing content.";
    }
    if ([self.internalName isEqualToString:@"edit_file"]) {
        return @"Precisely replace a section of text in a file."
               "\nParameters: path (string, required), oldText (string, required), newText (string, required)."
               "\nReplaces only if oldText appears exactly once in the file; otherwise returns an error (appeared N times).";
    }
    if ([self.internalName isEqualToString:@"delete_file"]) {
        return @"Delete a file (dangerous operation)."
               "\nParameter: path (string, required)."
               "\nFor safety, only text files (.txt/.log/.json/.properties/.toml/.md/.cfg/.yml/.yaml/.xml/.xaml/.lang, etc.) may be deleted; directories cannot be deleted."
               "\nReturns \"Deleted.\"";
    }
    return @"File operation tool";
}

#pragma mark - Sandbox path safety

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

/// Valid root for file tools: launcher directory (POJAV_HOME; if unset, fall back to the launcher directory under Documents,
/// consistent with main.m initialization — Documents itself inside the sandbox, Documents/AngelAuraAmethyst outside the sandbox).
/// instances/* (mods/saves/resourcepacks, etc.) are all under it;
/// normalize with realpath to match the real prefix after resolving the POJAV_GAME_DIR symlink and avoid incorrectly flagging traversal.
/// enhance-ai-agent Task 16: restrict from the entire app sandbox to the launcher directory, preventing reads/writes outside the container.
+ (NSString *)sandboxRoot {
    NSString *root = nil;
    const char *homeEnv = getenv("POJAV_HOME");
    if (homeEnv && strlen(homeEnv) > 0) {
        root = @(homeEnv);
    } else {
        NSString *docs = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
        BOOL isNotSandboxed = [NSHomeDirectory().lastPathComponent isEqualToString:NSUserName()];
        root = isNotSandboxed ? [docs stringByAppendingPathComponent:@"AngelAuraAmethyst"] : docs;
    }
    if (root.length == 0) root = NSHomeDirectory();
    const char *rootStart = [root UTF8String];
    if (rootStart) {
        char *real = realpath(rootStart, NULL);
        if (real) {
            NSString *realRoot = @(real);
            free(real);
            return realRoot;
        }
    }
    return [root stringByStandardizingPath];
}

+ (nullable NSString *)resolveSafely:(NSString *)path {
    if (path.length == 0) return nil;
    NSString *stdRoot = [self sandboxRoot];

    BOOL usedGameDir = ([path rangeOfString:@"$GAMEDIR"].location != NSNotFound);
    NSString *worked = path;
    if (usedGameDir) {
        NSString *gameRoot = [self currentGameRoot];
        worked = [worked stringByReplacingOccurrencesOfString:@"$GAMEDIR" withString:(gameRoot.length ? gameRoot : stdRoot)];
    }

    NSString *joined;
    if (usedGameDir) {
        joined = worked; // Replaced with a physical absolute path (inside the sandbox)
    } else if ([worked hasPrefix:@"/"]) {
        // Absolute physical path (may be an instance root returned directly by getenv("POJAV_GAME_DIR"),
        // or a sandbox file such as /var/.../Documents/...).
        // Important fix (list_files path traversal): previously all paths "starting with /" were treated as
        // "relative paths to join with Documents", causing an absolute instance root to become Documents/<absolute container path>,
        // which always escaped the sandbox; it also caused out-of-bounds errors when path was omitted (defaulting to the absolute currentGameRoot).
        // Absolute paths are now used as-is, and the unified sandbox-root check below determines whether they escape.
        joined = worked;
    } else {
        // Relative path: relative to the current instance root
        joined = [[self currentGameRoot] stringByAppendingPathComponent:worked];
    }

    // Normalize (remove ./ .., resolve symlinks), then check for sandbox traversal
    NSString *std = [joined stringByResolvingSymlinksInPath];
    stdRoot = [stdRoot stringByResolvingSymlinksInPath];
    NSString *prefix = [stdRoot hasSuffix:@"/"] ? stdRoot : [stdRoot stringByAppendingString:@"/"];
    if (![std isEqualToString:stdRoot] && ![std hasPrefix:prefix]) {
        return nil; // Traversal
    }
    return std;
}

#pragma mark - Execution dispatch

- (void)execute:(NSDictionary<NSString *, id> *)params
     completion:(void (^)(NSString * _Nullable result, NSError * _Nullable error))completion {
    if (!completion) return;

    if ([self.internalName isEqualToString:@"list_files"]) { [self performListFiles:params completion:completion]; return; }
    if ([self.internalName isEqualToString:@"read_file"])   { [self performReadFile:params completion:completion]; return; }
    if ([self.internalName isEqualToString:@"grep_files"])  { [self performGrepFiles:params completion:completion]; return; }
    if ([self.internalName isEqualToString:@"write_file"])  { [self performWriteFile:params completion:completion]; return; }
    if ([self.internalName isEqualToString:@"edit_file"])   { [self performEditFile:params completion:completion]; return; }
    if ([self.internalName isEqualToString:@"delete_file"]) { [self performDeleteFile:params completion:completion]; return; }

    NSError *err = [NSError errorWithDomain:kAiToolDomain code:404
                                   userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Unknown tool %@", self.internalName]}];
    completion(nil, err);
}

- (NSError *)errorWithCode:(NSInteger)code message:(NSString *)message {
    return [NSError errorWithDomain:kAiToolDomain code:code
                           userInfo:@{NSLocalizedDescriptionKey: message}];
}

#pragma mark - list_files

- (void)performListFiles:(NSDictionary *)params completion:(void(^)(NSString *, NSError *))completion {
    NSString *path = [params[@"path"] isKindOfClass:[NSString class]] ? params[@"path"] : nil;
    if (path.length == 0) path = [[self class] currentGameRoot];
    NSString *resolved = [[self class] resolveSafely:path];
    if (!resolved) { completion(nil, [self errorWithCode:403 message:@"Path traversal or invalid path"]); return; }

    NSArray *items = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:resolved error:nil];
    if (!items) { completion(nil, [self errorWithCode:404 message:@"Directory does not exist"]); return; }

    NSMutableArray *entries = [NSMutableArray array];
    for (NSString *name in items) {
        if ([name hasPrefix:@"."]) continue;
        NSString *full = [resolved stringByAppendingPathComponent:name];
        BOOL isDir = NO;
        if (![[NSFileManager defaultManager] fileExistsAtPath:full isDirectory:&isDir]) continue;
        NSDictionary *attrs = [[NSFileManager defaultManager] attributesOfItemAtPath:full error:nil];
        long long size = isDir ? 0 : [attrs[NSFileSize] longLongValue];
        double ts = [attrs[NSFileModificationDate] timeIntervalSince1970];
        [entries addObject:@{
            @"name": name,
            @"type": isDir ? @"dir" : @"file",
            @"size": @(size),
            @"modifiedUnixTS": @(ts),
        }];
    }
    [entries sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        return [a[@"name"] localizedCaseInsensitiveCompare:b[@"name"]];
    }];
    completion([self jsonStringFromObject:entries], nil);
}

#pragma mark - read_file

- (void)performReadFile:(NSDictionary *)params completion:(void(^)(NSString *, NSError *))completion {
    NSString *path = [params[@"path"] isKindOfClass:[NSString class]] ? params[@"path"] : nil;
    if (path.length == 0) { completion(nil, [self errorWithCode:400 message:@"The path parameter is required"]); return; }
    NSString *resolved = [[self class] resolveSafely:path];
    if (!resolved) { completion(nil, [self errorWithCode:403 message:@"Path traversal or invalid path"]); return; }

    NSUInteger maxChars = 8000;
    NSNumber *maxNum = params[@"maxChars"];
    if ([maxNum isKindOfClass:[NSNumber class]]) {
        NSInteger v = maxNum.integerValue;
        if (v > 0) maxChars = (NSUInteger)v;
    }

    NSData *data = [NSData dataWithContentsOfFile:resolved];
    if (!data) { completion(nil, [self errorWithCode:404 message:@"File does not exist or is unreadable"]); return; }

    // Binary detection: contains a NUL byte or cannot be decoded as UTF-8
    BOOL hasNull = [data rangeOfData:[NSData dataWithBytes:"\0" length:1] options:0 range:NSMakeRange(0, data.length)].location != NSNotFound;
    if (hasNull) { completion(@"Binary file is not readable", nil); return; }
    NSString *content = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    if (!content) {
        content = [[NSString alloc] initWithData:data encoding:NSISOLatin1StringEncoding];
    }
    if (!content) { completion(@"Binary file is not readable", nil); return; }
    if (content.length > maxChars) {
        content = [NSString stringWithFormat:@"(Content too long; truncated to the first %lu characters)\n%@", (unsigned long)maxChars,
                   [content substringToIndex:maxChars]];
    }
    completion(content, nil);
}

#pragma mark - grep_files

- (void)performGrepFiles:(NSDictionary *)params completion:(void(^)(NSString *, NSError *))completion {
    NSString *path = [params[@"path"] isKindOfClass:[NSString class]] ? params[@"path"] : nil;
    if (path.length == 0) path = [[self class] currentGameRoot];
    NSString *pattern = [params[@"pattern"] isKindOfClass:[NSString class]] ? params[@"pattern"] : nil;
    if (pattern.length == 0) { completion(nil, [self errorWithCode:400 message:@"The pattern (regular expression) parameter is required"]); return; }
    NSString *resolved = [[self class] resolveSafely:path];
    if (!resolved) { completion(nil, [self errorWithCode:403 message:@"Path traversal or invalid path"]); return; }

    BOOL recursive = NO;
    NSNumber *recNum = params[@"recursive"];
    if ([recNum isKindOfClass:[NSNumber class]]) recursive = recNum.boolValue;

    NSUInteger maxResults = 50;
    NSNumber *maxNum = params[@"maxResults"];
    if ([maxNum isKindOfClass:[NSNumber class]] && maxNum.integerValue >= 0) maxResults = (NSUInteger)maxNum.integerValue;
    if (maxResults == 0) maxResults = 50;

    NSError *regexError = nil;
    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:pattern options:0 error:&regexError];
    if (!regex) {
        completion(nil, [self errorWithCode:400 message:[NSString stringWithFormat:@"Invalid regular expression: %@", regexError.localizedDescription]]);
        return;
    }

    NSMutableArray *results = [NSMutableArray array];
    NSMutableArray *pendingDirs = [NSMutableArray arrayWithObject:resolved];
    NSFileManager *fm = [NSFileManager defaultManager];

    while (pendingDirs.count > 0 && results.count < maxResults) {
        NSString *dir = [pendingDirs lastObject];
        [pendingDirs removeLastObject];
        NSArray *items = [fm contentsOfDirectoryAtPath:dir error:nil];
        for (NSString *name in items) {
            if ([name hasPrefix:@"."]) continue;
            if (results.count >= maxResults) break;
            NSString *full = [dir stringByAppendingPathComponent:name];
            BOOL isDir = NO;
            if (![fm fileExistsAtPath:full isDirectory:&isDir]) continue;
            if (isDir) {
                if (recursive) [pendingDirs addObject:full];
                continue;
            }
            NSData *data = [fm contentsAtPath:full];
            if (!data) continue;
            NSString *text = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
            if (!text) continue;
            NSArray<NSString *> *lines = [text componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]];
            NSUInteger lineNumber = 1;
            for (NSString *line in lines) {
                if (results.count >= maxResults) break;
                if ([regex numberOfMatchesInString:line options:0 range:NSMakeRange(0, line.length)] > 0) {
                    [results addObject:@{
                        @"path": name,
                        @"lineNumber": @(lineNumber),
                        @"line": line,
                    }];
                }
                lineNumber++;
            }
        }
    }
    completion([self jsonStringFromObject:results], nil);
}

#pragma mark - write_file

- (void)performWriteFile:(NSDictionary *)params completion:(void(^)(NSString *, NSError *))completion {
    NSString *path = [params[@"path"] isKindOfClass:[NSString class]] ? params[@"path"] : nil;
    NSString *content = [params[@"content"] isKindOfClass:[NSString class]] ? params[@"content"] : @"";
    if (path.length == 0) { completion(nil, [self errorWithCode:400 message:@"The path parameter is required"]); return; }
    if (![params[@"content"] isKindOfClass:[NSString class]]) {
        completion(nil, [self errorWithCode:400 message:@"The content parameter is required"]); return;
    }
    NSString *resolved = [[self class] resolveSafely:path];
    if (!resolved) { completion(nil, [self errorWithCode:403 message:@"Path traversal or invalid path"]); return; }

    NSString *parentDir = [resolved stringByDeletingLastPathComponent];
    NSError *dirError = nil;
    [[NSFileManager defaultManager] createDirectoryAtPath:parentDir withIntermediateDirectories:YES attributes:nil error:&dirError];
    if (dirError) { completion(nil, [self errorWithCode:500 message:[NSString stringWithFormat:@"Failed to create directory: %@", dirError.localizedDescription]]); return; }

    NSData *data = [content dataUsingEncoding:NSUTF8StringEncoding];
    NSError *writeError = nil;
    BOOL ok = [data writeToURL:[NSURL fileURLWithPath:resolved] options:NSDataWritingAtomic error:&writeError];
    if (!ok) {
        completion(nil, [self errorWithCode:500 message:[NSString stringWithFormat:@"Write failed: %@", writeError.localizedDescription]]);
        return;
    }
    completion([NSString stringWithFormat:@"Written (%lu characters)", (unsigned long)content.length], nil);
}

#pragma mark - edit_file

- (void)performEditFile:(NSDictionary *)params completion:(void(^)(NSString *, NSError *))completion {
    NSString *path = [params[@"path"] isKindOfClass:[NSString class]] ? params[@"path"] : nil;
    NSString *oldText = [params[@"oldText"] isKindOfClass:[NSString class]] ? params[@"oldText"] : nil;
    NSString *newText = [params[@"newText"] isKindOfClass:[NSString class]] ? params[@"newText"] : @"";
    if (path.length == 0) { completion(nil, [self errorWithCode:400 message:@"The path parameter is required"]); return; }
    if (oldText.length == 0) { completion(nil, [self errorWithCode:400 message:@"The oldText parameter is required"]); return; }
    if (![params[@"newText"] isKindOfClass:[NSString class]]) { completion(nil, [self errorWithCode:400 message:@"The newText parameter is required"]); return; }
    NSString *resolved = [[self class] resolveSafely:path];
    if (!resolved) { completion(nil, [self errorWithCode:403 message:@"Path traversal or invalid path"]); return; }

    NSError *readError = nil;
    NSString *content = [NSString stringWithContentsOfFile:resolved encoding:NSUTF8StringEncoding error:&readError];
    if (!content) { completion(nil, [self errorWithCode:404 message:@"Failed to read file or file does not exist"]); return; }

    // Count occurrences of oldText
    NSUInteger occurrences = 0;
    NSRange searchRange = NSMakeRange(0, content.length);
    while (searchRange.location < content.length) {
        NSRange found = [content rangeOfString:oldText options:0 range:searchRange];
        if (found.location == NSNotFound) break;
        occurrences++;
        NSUInteger next = found.location + found.length;
        searchRange.location = next;
        searchRange.length = content.length - next;
    }
    if (occurrences != 1) {
        completion(nil, [self errorWithCode:422 message:[NSString stringWithFormat:@"oldText is not unique or was not found (appeared %lu times)", (unsigned long)occurrences]]);
        return;
    }

    NSString *newContent = [content stringByReplacingOccurrencesOfString:oldText withString:newText
                                                                 options:0 range:NSMakeRange(0, content.length)];
    NSData *data = [newContent dataUsingEncoding:NSUTF8StringEncoding];
    NSError *writeError = nil;
    if (![data writeToURL:[NSURL fileURLWithPath:resolved] options:NSDataWritingAtomic error:&writeError]) {
        completion(nil, [self errorWithCode:500 message:[NSString stringWithFormat:@"Failed to write changes: %@", writeError.localizedDescription]]);
        return;
    }
    completion(@"Modified", nil);
}

#pragma mark - delete_file

/// Allowlist of file extensions that may be deleted (text files)
+ (NSSet<NSString *> *)deletableExtensions {
    static NSSet *set = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        set = [NSSet setWithArray:@[@"txt", @"log", @"json", @"properties", @"toml", @"md", @"cfg",
                                     @"yml", @"yaml", @"xml", @"xaml", @"lang", @"ini", @"export",
                                     @"conf", @"gradle", @"fnf", @"more"]];
    });
    return set;
}

- (void)performDeleteFile:(NSDictionary *)params completion:(void(^)(NSString *, NSError *))completion {
    NSString *path = [params[@"path"] isKindOfClass:[NSString class]] ? params[@"path"] : nil;
    if (path.length == 0) { completion(nil, [self errorWithCode:400 message:@"The path parameter is required"]); return; }
    NSString *resolved = [[self class] resolveSafely:path];
    if (!resolved) { completion(nil, [self errorWithCode:403 message:@"Path traversal or invalid path"]); return; }

    NSFileManager *fm = [NSFileManager defaultManager];
    BOOL isDir = NO;
    if (![fm fileExistsAtPath:resolved isDirectory:&isDir]) {
        completion(nil, [self errorWithCode:404 message:@"File does not exist"]); return;
    }
    if (isDir) {
        completion(nil, [self errorWithCode:403 message:@"For safety, only files may be deleted; directories cannot be deleted"]); return;
    }
    NSString *ext = [[resolved pathExtension] lowercaseString];
    if (![[[self class] deletableExtensions] containsObject:ext]) {
        completion(nil, [self errorWithCode:403 message:[NSString stringWithFormat:@"For safety, only text files may be deleted (.%@ is not supported)", ext]]);
        return;
    }
    NSError *removeError = nil;
    if (![fm removeItemAtPath:resolved error:&removeError]) {
        completion(nil, [self errorWithCode:500 message:[NSString stringWithFormat:@"Failed to delete: %@", removeError.localizedDescription]]);
        return;
    }
    completion(@"Deleted", nil);
}

#pragma mark - Tools

- (NSString *)jsonStringFromObject:(id)object {
    if (![NSJSONSerialization isValidJSONObject:object]) return @"[]";
    NSData *data = [NSJSONSerialization dataWithJSONObject:object options:0 error:nil];
    if (!data) return @"[]";
    return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
}

@end