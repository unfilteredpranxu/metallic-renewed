//
//  AiMessage.h
//  Amethyst
//
//  Chat message data model: role + content.
//  Fields such as tool_calls / function_call are reserved for Phase 3; this release retains only role/content.
//  streaming is a runtime-only flag marking an assistant placeholder message being generated; it is not persisted.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface AiMessage : NSObject

/// Message role: system / user / assistant / tool
@property (nonatomic, copy) NSString *role;
/// Message content
@property (nonatomic, copy) NSString *content;
/// Whether a response is being streamed (runtime-only flag; not written to disk)
@property (nonatomic, assign) BOOL streaming;
/// Creation time
@property (nonatomic, strong) NSDate *createdAt;

// ===== Phase 3 tool-call extension fields (optional, backward compatible) =====
/// Tool call ID (assistant function_call and the corresponding tool result's tool_call_id)
@property (nonatomic, copy, nullable) NSString *toolCallID;
/// Tool name (assistant function_call name)
@property (nonatomic, copy, nullable) NSString *toolName;
/// Tool arguments (JSON string, assistant function_call arguments)
@property (nonatomic, copy, nullable) NSString *toolArguments;
/// Whether this is an assistant tool-call record (function_call)
@property (nonatomic, assign) BOOL isToolCall;
/// Whether this is a tool execution result message (role=tool)
@property (nonatomic, assign) BOOL isToolResult;
/// Whether tool execution succeeded (the result card distinguishes ✅/❌; defaults to success)
@property (nonatomic, assign) BOOL toolSucceeded;

/// Convenience initializer
+ (instancetype)messageWithRole:(NSString *)role content:(NSString *)content;

/// Create an assistant tool-call message (isToolCall=YES, role=assistant, content may be empty)
+ (instancetype)toolCallMessageWithName:(NSString *)name arguments:(NSString *)arguments;

/// Create a tool result message (isToolResult=YES, role=tool, with tool_call_id attached)
+ (instancetype)toolResultMessageWithContent:(NSString *)content toolCallID:(NSString *)toolCallID;

/// JSON serialization
- (instancetype)initWithDictionary:(NSDictionary *)dict;
- (NSDictionary *)toDictionary;

@end

NS_ASSUME_NONNULL_END