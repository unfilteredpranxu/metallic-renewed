//
//  AiToolRegistry.h
//  Amethyst
//
//  Air AI Agent tool registry: registers all built-in tools, exposes an OpenAI-style schema to the LLM,
//  and normalizes LLM-provided arguments before dispatching them to the corresponding tool.
//

#import <Foundation/Foundation.h>
#import "AiTool.h"

NS_ASSUME_NONNULL_BEGIN

@interface AiToolRegistry : NSObject

/// Singleton
+ (instancetype)sharedRegistry;

/// Register a tool (a duplicate name replaces the existing tool)
- (void)registerTool:(id<AiTool>)tool;

/// Convert to an OpenAI function calling tools array
/// Structure: [{type:function, function:{name, description, parameters:{type:object, properties, required}}}]
- (NSArray<NSDictionary *> *)openAIToolSchemas;

/// Find by tool name; returns nil if not found
- (id<AiTool> _Nullable)toolForName:(NSString *)name;

/// Normalize parameters: lowercase keys + remove separator/case differences → normalize to lowercase camelCase,
/// discard keys with empty values; return a new dictionary (do not modify the original).
- (NSDictionary * _Nonnull)normalizedParams:(NSDictionary * _Nonnull)params;

/// Execute a tool by name (pass normalizedParams through first; always invoke the result callback on the main thread)
- (void)executeToolNamed:(NSString *)name
                  params:(NSDictionary *)params
              completion:(void (^)(NSString * _Nullable result, NSError * _Nullable error))completion;

@end

NS_ASSUME_NONNULL_END