//
//  AiSleepTool.m
//  Amethyst
//

#import "AiSleepTool.h"

/// Maximum single wait (prevents an excessively large model-provided value from hanging the session)
static const double kAiSleepMaxSeconds = 120.0;

@implementation AiSleepTool

- (NSString *)name {
    return @"sleep";
}

- (AiToolPermission)permission {
    return AiToolPermissionReadOnly;
}

- (NSString *)summary {
    return @"Wait for the specified number of seconds before returning (used to wait for background downloads to progress or to simulate an interval between tasks)."
           "\nParameter: seconds (number, optional, defaults to 1, maximum 120)."
           "\nReturns \"Waited N seconds.\"";
}

- (void)execute:(NSDictionary<NSString *, id> *)params
     completion:(void (^)(NSString * _Nullable result, NSError * _Nullable error))completion {
    if (!completion) return;

    double seconds = 1.0;
    id v = params[@"seconds"];
    if ([v isKindOfClass:[NSNumber class]]) {
        seconds = [(NSNumber *)v doubleValue];
    } else if ([v isKindOfClass:[NSString class]]) {
        seconds = [(NSString *)v doubleValue];
    }
    if (seconds < 0) seconds = 0;
    if (seconds > kAiSleepMaxSeconds) seconds = kAiSleepMaxSeconds;

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(seconds * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        completion([NSString stringWithFormat:@"Waited %.1f seconds", seconds], nil);
    });
}

@end
