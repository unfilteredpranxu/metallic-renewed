//
//  AiProviderStore.h
//  Amethyst
//
//  AI provider storage: singleton. Reads/writes providers in Documents/AI/providers.json,
//  and stores selectedProviderId in NSUserDefaults (ai.selected_provider_id).
//

#import <Foundation/Foundation.h>
#import "AiProvider.h"

NS_ASSUME_NONNULL_BEGIN

@interface AiProviderStore : NSObject

/// Configured provider list (lazy-loaded on read, seeded with defaultPresets on first use)
@property (nonatomic, strong, readonly) NSMutableArray<AiProvider *> *providers;

/// Currently selected provider (based on ai.selected_provider_id; returns nil if unconfigured or missing)
@property (nonatomic, strong, nullable) AiProvider *selectedProvider;

/// Singleton
+ (instancetype)sharedStore;

/// Three preset provider dictionaries (DeepSeek / OpenAI / Ollama), used by the initial setup UI and seeding
+ (NSArray<NSDictionary *> *)defaultPresets;

/// Explicitly trigger loading (idempotent; the first access to providers already loads automatically)
- (void)loadIfNeeded;

/// Persist providers to disk
- (void)save;

- (void)addProvider:(AiProvider *)provider;
- (void)updateProvider:(AiProvider *)provider;
- (void)deleteProvider:(AiProvider *)provider;
- (nullable AiProvider *)providerById:(NSString *)identifier;

@end

NS_ASSUME_NONNULL_END