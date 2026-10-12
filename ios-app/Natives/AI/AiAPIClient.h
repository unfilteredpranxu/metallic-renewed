//
//  AiAPIClient.h
//  Amethyst
//
//  OpenAI-compatible streaming Chat Completions client.
//  Supports SSE streaming responses, throttles onChunk callbacks (≤200ms), and always invokes blocks on the main thread.
//

#import <Foundation/Foundation.h>
#import "AiProvider.h"
#import "AiMessage.h"

NS_ASSUME_NONNULL_BEGIN

@interface AiAPIClient : NSObject

/// Start a streaming chat request
/// @param messages Conversation context (system/user/assistant)
/// @param tools Tool definitions (used in Phase 3; usually nil in this release)
/// @param onChunk Streaming chunk callback (delta is the content increment accumulated for this request; toolCalls are passed through for Phase 3)
/// @param onComplete Request completion callback (fullResponse contains the complete @"content"; a nil error indicates success)
- (void)streamChatWithProvider:(AiProvider *)provider
                      messages:(NSArray<AiMessage *> *)messages
                         tools:(nullable NSArray<NSDictionary *> *)tools
                       onChunk:(void (^)(NSString * _Nullable delta, NSDictionary * _Nullable toolCalls))onChunk
                    onComplete:(void (^)(NSDictionary * _Nullable fullResponse, NSError * _Nullable error))onComplete;

/// Cancel the current request (used by the Stop button)
- (void)stop;

/// Connectivity test: send the provider a very short user "ping" message (reuses the streaming channel internally),
/// returning successMessage (e.g. "Connection successful") on success or error on failure.
/// Does not change the existing streamChatWithProvider:... method signature.
- (void)testConnectionWithProvider:(AiProvider *)provider
                        completion:(void (^)(NSString * _Nullable successMessage, NSError * _Nullable error))completion;

@end

NS_ASSUME_NONNULL_END