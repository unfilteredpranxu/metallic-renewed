//
//  AiAgent.h
//  Amethyst
//
//  AI session orchestration (simplified Phase 1): assembles system + history + new user message,
//  calls AiAPIClient to start a streaming request, and writes/persists increments to the session.
//

#import <Foundation/Foundation.h>
#import "AiProvider.h"
#import "AiSession.h"

NS_ASSUME_NONNULL_BEGIN

@interface AiAgent : NSObject

+ (instancetype)sharedAgent;

/// Send a user message and drive a streaming response
/// @param text User input
/// @param session Target session (user message and assistant placeholder are appended in place)
/// @param provider Current AI provider
/// @param streaming Whether to stream (always YES in Phase 1; parameter retained)
/// @param chunkHandler Increment callback (on main thread; delta is the content increment since the most recent update)
/// @param completionHandler Completion callback (a nil error indicates success)
- (void)sendUserMessage:(NSString *)text
                session:(AiSession *)session
               provider:(AiProvider *)provider
               streaming:(BOOL)streaming
           chunkHandler:(void (^)(NSString *partial))chunkHandler
     completionHandler:(void (^)(NSError *error))completionHandler;

/// Cancel the current request (used by the Stop button)
- (void)stopCurrent;

@end

NS_ASSUME_NONNULL_END