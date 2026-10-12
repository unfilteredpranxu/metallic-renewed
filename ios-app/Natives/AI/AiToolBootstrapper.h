//
//  AiToolBootstrapper.h
//  Amethyst
//
//  Air AI Agent built-in tool bootstrapper: centrally registers the built-in tools implemented in Phase 3a with AiToolRegistry.
//  Phase 3b tools will be registered in this file (see the "Add Phase 3b here" comment in registerBuiltinTools).
//

#import <Foundation/Foundation.h>
#import "AiToolRegistry.h"

NS_ASSUME_NONNULL_BEGIN

@interface AiToolBootstrapper : NSObject

/// Register all built-in tools with the specified registry (called automatically during AiToolRegistry initialization, or explicitly from elsewhere)
+ (void)registerBuiltinToolsIntoRegistry:(AiToolRegistry *)registry;

@end

NS_ASSUME_NONNULL_END