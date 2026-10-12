//
//  AiTool.h
//  Amethyst
//
//  Air AI Agent base tool protocol: defines the shared tool permission levels and execution interface.
//  All built-in tools (instances/logs/crashes/files/questions, etc.) follow this protocol and are managed by the registry.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Tool permission level (determines whether user confirmation is required)
typedef NS_ENUM(NSInteger, AiToolPermission) {
    /// Read-only: view only, no side effects, always allowed
    AiToolPermissionReadOnly = 0,
    /// Controlled write: modifies text files in the launcher/instance; allowed or prompted in Ask/YOLO modes
    AiToolPermissionControlledWrite = 1,
    /// Dangerous write: high-risk operations such as deleting files; confirmation required in all safety modes
    AiToolPermissionDangerousWrite = 2,
    /// External network: makes network requests; no confirmation in YOLO mode, prompt in other modes
    AiToolPermissionExternalNetwork = 3,
};

/// Safety mode (values match AiSettings.safetyMode)
typedef NS_ENUM(NSInteger, AiSafetyMode) {
    AiSafetyModeSafe = 0, // Safe: perform read-only operations only
    AiSafetyModeAsk = 1,  // Ask: ask the user before execution
    AiSafetyModeYOLO = 2, // Full: do not ask before execution (use with caution)
};

/// AI tool protocol: implemented by every built-in tool
@protocol AiTool <NSObject>

/// Tool name, e.g. list_instances
@property (nonatomic, readonly) NSString *name;
/// Description for the LLM (purpose + parameter details + boundaries + examples)
@property (nonatomic, readonly) NSString *summary;
/// Permission level
@property (nonatomic, readonly) AiToolPermission permission;

/// Execute the tool
/// @param params Normalized parameter dictionary
/// @param completion Result callback (at least one of result/error must be non-empty; callback must be invoked exactly once)
- (void)execute:(NSDictionary<NSString *, id> *)params
     completion:(void (^)(NSString * _Nullable result, NSError * _Nullable error))completion;

@end

NS_ASSUME_NONNULL_END