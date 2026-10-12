//
//  AiAskTool.h
//  Amethyst
//
//  Air AI Agent interactive question tool (read-only): ask.
//  Starts a multi-step selection wizard when the AI needs the user to make a decision (version/loader/target instance/resource selection, etc.).
//

#import <Foundation/Foundation.h>
#import "AiTool.h"

NS_ASSUME_NONNULL_BEGIN

@interface AiAskTool : NSObject <AiTool>

@property (nonatomic, readonly) NSString *name;
@property (nonatomic, readonly) NSString *summary;
@property (nonatomic, readonly) AiToolPermission permission;

@end

NS_ASSUME_NONNULL_END