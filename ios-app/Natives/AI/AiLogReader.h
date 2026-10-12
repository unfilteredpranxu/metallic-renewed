//
//  AiLogReader.h
//  Amethyst
//
//  Air AI Agent log reader tools (read-only):
//    - read_latest_log: reads logs/latest.log for the currently selected instance (truncated to the last 4000 characters).
//    - read_crash_report: reads the latest crash report .txt (truncated to 6000 characters).
//

#import <Foundation/Foundation.h>
#import "AiTool.h"

NS_ASSUME_NONNULL_BEGIN

@interface AiLogReader : NSObject <AiTool>

@property (nonatomic, readonly) NSString *name;
@property (nonatomic, readonly) NSString *summary;
@property (nonatomic, readonly) AiToolPermission permission;

/// Set the tool name (read_latest_log / read_crash_report)
- (instancetype)initWithName:(NSString *)name;

@end

NS_ASSUME_NONNULL_END