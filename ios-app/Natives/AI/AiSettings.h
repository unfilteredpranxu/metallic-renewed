//
//  AiSettings.h
//  Amethyst
//
//  AI preferences: singleton that reads/writes ai.* keys in NSUserDefaults.
//  Setters/getters access UserDefaults directly without in-memory caching.
//

#import <Foundation/Foundation.h>
#import "AiTool.h" // Provides the AiSafetyMode enum (the sole definition)

NS_ASSUME_NONNULL_BEGIN

@interface AiSettings : NSObject

/// Singleton
+ (instancetype)sharedSettings;

/// Currently selected provider ID (NSUserDefaults ai.selected_provider_id)
@property (nonatomic, copy, nullable) NSString *selectedProviderId;
/// Safety mode (0=Safe/1=Ask/2=YOLO, defaults to 0)
@property (nonatomic, assign) AiSafetyMode safetyMode;
/// Whether Markdown rendering is enabled (defaults to YES)
@property (nonatomic, assign) BOOL markdownEnabled;
/// Custom system prompt (returns defaultSystemPrompt by default)
@property (nonatomic, copy) NSString *systemPrompt;

/// Default system prompt, defining Air's behavior
+ (NSString *)defaultSystemPrompt;

@end

NS_ASSUME_NONNULL_END