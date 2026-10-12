//
//  AiProvider.h
//  Amethyst
//
//  AI provider data model: describes an OpenAI-compatible LLM endpoint.
//  Supports JSON serialization/deserialization (compatible with NSJSONSerialization) for persistence by AiProviderStore.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface AiProvider : NSObject

/// Unique identifier (UUID)
@property (nonatomic, copy) NSString *identifier;
/// Display name, e.g. DeepSeek / OpenAI / Ollama
@property (nonatomic, copy) NSString *name;
/// API protocol, defaults to @"openai_compatible"
@property (nonatomic, copy) NSString *protocol;
/// Service base URL, e.g. https://api.deepseek.com/v1
@property (nonatomic, copy) NSString *baseURL;
/// API Key (may be empty; requests omit Authorization when apiKey is empty)
@property (nonatomic, copy) NSString *apiKey;
/// Model name, e.g. deepseek-chat
@property (nonatomic, copy) NSString *model;
/// Sampling temperature, defaults to 0.7
@property (nonatomic, assign) double temperature;
/// Maximum number of generated tokens, defaults to 4096
@property (nonatomic, assign) NSInteger maxTokens;
/// Context window length, defaults to 8192
@property (nonatomic, assign) NSInteger contextWindow;

/// Create from a JSON dictionary (use defaults for missing fields)
+ (nullable instancetype)providerWithDictionary:(NSDictionary *)dict;
- (nullable instancetype)initWithDictionary:(NSDictionary *)dict;
/// Convert to a JSON-compatible dictionary
- (NSDictionary *)toDictionary;

@end

NS_ASSUME_NONNULL_END