//
//  AiCrashAnalyzer.h
//  Amethyst
//
//  Air AI Agent crash analysis tool (read-only): match_known_errors.
//  Matches built-in rule keywords against the provided log/crash report and returns structured analysis results.
//

#import <Foundation/Foundation.h>
#import "AiTool.h"

NS_ASSUME_NONNULL_BEGIN

@interface AiCrashAnalyzer : NSObject <AiTool>

@property (nonatomic, readonly) NSString *name;
@property (nonatomic, readonly) NSString *summary;
@property (nonatomic, readonly) AiToolPermission permission;

@end

NS_ASSUME_NONNULL_END