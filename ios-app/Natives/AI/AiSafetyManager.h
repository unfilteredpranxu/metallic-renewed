//
//  AiSafetyManager.h
//  Amethyst
//
//  Air AI Agent safety mechanism: checks whether a permission level requires user confirmation based on AiSettings.safetyMode,
//  and presents a confirmation dialog on the main thread; also provides localized guidance when switching safety modes.
//

#import <Foundation/Foundation.h>
#import "AiTool.h"

NS_ASSUME_NONNULL_BEGIN

@interface AiSafetyManager : NSObject

/// Singleton
+ (instancetype)sharedManager;

/// Current safety mode (read from AiSettings.safetyMode)
- (AiSafetyMode)currentMode;

/// Determine whether a permission level requires user confirmation in the current safety mode
- (BOOL)needsUserConfirmationForPermission:(AiToolPermission)permission;

/// Present a confirmation dialog on the main thread; "Allow" calls back YES (the dangerous-action button is "Proceed Anyway"), and "Cancel" calls back NO.
/// If no view controller is available for presentation, default to "not allowed."
- (void)requestConfirmationWithTitle:(NSString *)title
                             message:(NSString *)message
                          completion:(void (^)(BOOL approved))completion;

/// Friendly message shown when switching safety modes (displays a description of the current mode)
- (void)showSafetyModeChangedHint;

/// Permission level description (shared by guidance and confirmation dialogs)
- (NSString *)permissionChineseName:(AiToolPermission)permission;

/// Safety mode description
+ (NSString *)safetyModeChineseName:(AiSafetyMode)mode;

@end

NS_ASSUME_NONNULL_END