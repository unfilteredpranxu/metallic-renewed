//
//  AiSleepTool.h
//  Amethyst
//
//  sleep tool (enhance-ai-agent Task 12.1): asynchronously waits for seconds (defaults to 1) before returning,
//  for AI to wait on background downloads / task intervals. READ_ONLY, with no side effects.
//

#import <Foundation/Foundation.h>
#import "AiTool.h"

NS_ASSUME_NONNULL_BEGIN

@interface AiSleepTool : NSObject <AiTool>
@end

NS_ASSUME_NONNULL_END
