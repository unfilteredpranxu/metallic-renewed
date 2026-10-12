//
//  AiInstancesTool.h
//  Amethyst
//
//  Air AI Agent instance/version tools:
//    - list_instances (read-only): lists launcher game instances (game directories/versions) and their asset counts.
//    - list_game_versions (read-only): fetches the actual MC version list (with a 30-minute cache).
//

#import <Foundation/Foundation.h>
#import "AiTool.h"

NS_ASSUME_NONNULL_BEGIN

@interface AiInstancesTool : NSObject <AiTool>

@property (nonatomic, readonly) NSString *name;
@property (nonatomic, readonly) NSString *summary;
@property (nonatomic, readonly) AiToolPermission permission;

/// Set the tool name for this instance (list_instances / list_game_versions)
- (instancetype)initWithName:(NSString *)name;

@end

NS_ASSUME_NONNULL_END