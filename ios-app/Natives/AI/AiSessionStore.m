//
//  AiSessionStore.m
//  Amethyst
//

#import "AiSessionStore.h"

@implementation AiSessionStore {
    NSMutableArray<AiSession *> *_sessions;
    BOOL _loaded;
}

static NSString * const kLastSessionIdKey = @"ai.last_session_id";
/// Maximum of the first 20 characters used for automatic naming
static const NSUInteger kAutoTitleMaxLength = 20;

+ (instancetype)sharedStore {
    static AiSessionStore *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[AiSessionStore alloc] init];
    });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _sessions = [NSMutableArray array];
        _loaded = NO;
    }
    return self;
}

#pragma mark - File path

- (NSString *)aiDirectoryPath {
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *docDir = [paths firstObject];
    NSString *aiDir = [docDir stringByAppendingPathComponent:@"AI"];
    NSFileManager *fm = [NSFileManager defaultManager];
    if (![fm fileExistsAtPath:aiDir]) {
        [fm createDirectoryAtPath:aiDir withIntermediateDirectories:YES attributes:nil error:nil];
    }
    return aiDir;
}

- (NSString *)filePath {
    return [[self aiDirectoryPath] stringByAppendingPathComponent:@"sessions.json"];
}

#pragma mark - Sorting

/// Sort by updatedAt descending (newest first)
- (void)reloadSort {
    [_sessions sortUsingComparator:^NSComparisonResult(AiSession *a, AiSession *b) {
        return [b.updatedAt compare:a.updatedAt];
    }];
}

#pragma mark - Load / save

- (NSMutableArray<AiSession *> *)sessions {
    [self loadIfNeeded];
    // Returns an internal mutable reference, but callers should avoid modifying it out of order; use updateSession to make changes
    return _sessions;
}

- (void)loadIfNeeded {
    if (_loaded) return;
    _loaded = YES;

    NSString *path = [self filePath];
    NSData *data = [NSData dataWithContentsOfFile:path];
    if (data) {
        NSError *error = nil;
        id obj = [NSJSONSerialization JSONObjectWithData:data options:0 error:&error];
        if (!error && [obj isKindOfClass:[NSArray class]]) {
            [_sessions removeAllObjects];
            for (NSDictionary *dict in obj) {
                AiSession *session = [[AiSession alloc] initWithDictionary:dict];
                if (session) [_sessions addObject:session];
            }
            [self reloadSort];
            return;
        }
    }
}

- (void)save {
    [self reloadSort];
    NSMutableArray *array = [NSMutableArray array];
    for (AiSession *session in _sessions) {
        if (session.messages.count == 0 && session.title == nil) continue;
        [array addObject:[session toDictionary]];
    }
    NSError *error = nil;
    NSData *json = [NSJSONSerialization dataWithJSONObject:array options:NSJSONWritingPrettyPrinted error:&error];
    if (json && !error) {
        [json writeToFile:[self filePath] options:NSDataWritingAtomic error:nil];
    }
}

#pragma mark - CRUD

- (AiSession *)newSession {
    [self loadIfNeeded];
    AiSession *session = [AiSession sessionWithTitle:nil];
    [_sessions insertObject:session atIndex:0];
    [self setLastActiveSessionId:session.identifier];
    [self save];
    return session;
}

- (void)deleteSession:(AiSession *)session {
    if (!session) return;
    [self loadIfNeeded];
    [_sessions removeObject:session];
    // If deleting the most recent session, clear the record
    NSString *lastId = [[NSUserDefaults standardUserDefaults] stringForKey:kLastSessionIdKey];
    if ([session.identifier isEqualToString:lastId]) {
        [[NSUserDefaults standardUserDefaults] removeObjectForKey:kLastSessionIdKey];
    }
    [self save];
}

- (void)updateSession:(AiSession *)session {
    if (!session) return;
    [self loadIfNeeded];
    session.updatedAt = [NSDate date];
    [self save];
}

- (nullable AiSession *)sessionById:(NSString *)identifier {
    if (identifier.length == 0) return nil;
    [self loadIfNeeded];
    for (AiSession *session in _sessions) {
        if ([session.identifier isEqualToString:identifier]) {
            return session;
        }
    }
    return nil;
}

- (NSArray<AiSession *> *)sessionsMatchingQuery:(NSString *)query {
    [self loadIfNeeded];
    if (query.length == 0) return [_sessions copy];
    NSString *lower = [query lowercaseString];
    NSMutableArray *result = [NSMutableArray array];
    for (AiSession *session in _sessions) {
        if ([[session.title lowercaseString] containsString:lower]) {
            [result addObject:session];
        }
    }
    return result;
}

+ (NSString *)autoTitleForMessage:(NSString *)message {
    if (message.length == 0) return @"New Session";
    NSString *trimmed = [message stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSString *single = [[trimmed stringByReplacingOccurrencesOfString:@"\n" withString:@" "] stringByReplacingOccurrencesOfString:@"\r" withString:@" "];
    if (single.length <= kAutoTitleMaxLength) {
        return single;
    }
    return [[single substringToIndex:kAutoTitleMaxLength] stringByAppendingString:@"…"];
}

#pragma mark - Most recent session

- (nullable AiSession *)lastActiveSession {
    [self loadIfNeeded];
    NSString *lastId = [[NSUserDefaults standardUserDefaults] stringForKey:kLastSessionIdKey];
    AiSession *byId = [self sessionById:lastId];
    if (byId) return byId;
    // No record or invalid record: return the newest session (sessions are sorted by updatedAt descending)
    return _sessions.count > 0 ? _sessions[0] : nil;
}

- (void)setLastActiveSessionId:(NSString *)identifier {
    if (identifier.length == 0) return;
    [[NSUserDefaults standardUserDefaults] setObject:identifier forKey:kLastSessionIdKey];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

@end