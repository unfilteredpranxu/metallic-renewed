//
//  AiSessionStore.h
//  Amethyst
//
//  AI session storage: singleton. Reads/writes sessions in Documents/AI/sessions.json (descending by updatedAt),
//  and stores the most recent session ID in NSUserDefaults (ai.last_session_id).
//

#import <Foundation/Foundation.h>
#import "AiSession.h"

NS_ASSUME_NONNULL_BEGIN

@interface AiSessionStore : NSObject

/// Session list (lazy-loaded, sorted by updatedAt descending)
@property (nonatomic, strong, readonly) NSMutableArray<AiSession *> *sessions;

/// Singleton
+ (instancetype)sharedStore;

/// Create and persist a new session, and set it as the most recent session
- (AiSession *)newSession;
- (void)deleteSession:(AiSession *)session;
- (void)updateSession:(AiSession *)session;
- (nullable AiSession *)sessionById:(NSString *)identifier;

/// Search by title keyword (case-insensitive)
- (NSArray<AiSession *> *)sessionsMatchingQuery:(NSString *)query;

/// Automatic naming: take the first 20 characters of the message (optionally append an ellipsis)
+ (NSString *)autoTitleForMessage:(NSString *)message;

/// Most recent session: prefer the session matching ai.last_session_id; otherwise return the newest session by time, or nil if none exists
- (nullable AiSession *)lastActiveSession;
- (void)setLastActiveSessionId:(NSString *)identifier;

@end

NS_ASSUME_NONNULL_END