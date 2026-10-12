//
//  AiSafetyManager.m
//  Amethyst
//
//  Conventions:
//  - Traditional square-bracket syntax + Objective-C ARC.
//  - Always dispatch UI work to the main thread with dispatch_async(dispatch_get_main_queue(), ...).
//  - If no VC is available for presentation, default to "not allowed" (safety first).
//

#import "AiSafetyManager.h"
#import <UIKit/UIKit.h>

// Note: AiSafetyMode is defined in both AiSettings.h and AiTool.h (the contract requires them to match).
// To avoid duplicate typedefs in the same compilation unit, do not import AiSettings.h here;
// read its underlying NSUserDefaults key (ai.safety_mode) directly, which produces the same result as AiSettings.safetyMode.
static NSString * const kAiSafetyModeKey = @"ai.safety_mode";

@implementation AiSafetyManager

+ (instancetype)sharedManager {
    static AiSafetyManager *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[AiSafetyManager alloc] init];
    });
    return instance;
}

- (AiSafetyMode)currentMode {
    // Same storage and clamping logic as AiSettings.safetyMode
    NSInteger value = [[NSUserDefaults standardUserDefaults] integerForKey:kAiSafetyModeKey];
    return (value < AiSafetyModeSafe || value > AiSafetyModeYOLO) ? AiSafetyModeSafe : (AiSafetyMode)value;
}

#pragma mark - Permission confirmation

- (BOOL)needsUserConfirmationForPermission:(AiToolPermission)permission {
    switch (permission) {
        case AiToolPermissionReadOnly:
            return NO; // Read-only, always allowed
        case AiToolPermissionDangerousWrite:
            return YES; // Dangerous write, confirmation required in all modes
        case AiToolPermissionControlledWrite:
        case AiToolPermissionExternalNetwork: {
            // Only YOLO (Full) mode bypasses confirmation
            return [self currentMode] == AiSafetyModeYOLO ? NO : YES;
        }
    }
    return YES; // Handle unknown permissions conservatively
}

#pragma mark - View controller lookup

/// Get the topmost view controller currently available for presentation (handles cases where a controller is already presenting)
- (UIViewController * _Nullable)topmostPresentableViewController {
    UIWindow *keyWindow = nil;
    if (@available(iOS 13.0, *)) {
        for (UIWindowScene *scene in [UIApplication sharedApplication].connectedScenes) {
            if (scene.activationState == UISceneActivationStateForegroundActive) {
                keyWindow = scene.windows.firstObject;
                break;
            }
        }
    }
    if (!keyWindow) {
        keyWindow = [[UIApplication sharedApplication] windows].firstObject;
    }
    if (!keyWindow) {
        keyWindow = [UIApplication sharedApplication].keyWindow;
    }

    UIViewController *top = keyWindow.rootViewController;
    while (top.presentedViewController) {
        top = top.presentedViewController;
    }
    return top;
}

#pragma mark - Confirmation dialog

- (void)requestConfirmationWithTitle:(NSString *)title
                             message:(NSString *)message
                          completion:(void (^)(BOOL approved))completion {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIViewController *presentingVC = [self topmostPresentableViewController];
        if (!presentingVC) {
            // No VC available for presentation: safety first, default to not allowed
            if (completion) completion(NO);
            return;
        }

        UIAlertController *alert = [UIAlertController
            alertControllerWithTitle:title ?: @"Confirm AI Action"
                             message:message
                      preferredStyle:UIAlertControllerStyleAlert];

        // "Allow" ("Proceed Anyway" for dangerous operations); tap → approve
        NSString *actionTitle = (self.currentMode == AiSafetyModeSafe) ? @"Proceed Anyway" : @"Allow";
        UIAlertAction *allowAction = [UIAlertAction actionWithTitle:actionTitle
                                                              style:UIAlertActionStyleDefault
                                                            handler:^(UIAlertAction *action) {
            if (completion) completion(YES);
        }];
        [alert addAction:allowAction];

        // "Cancel" → do not approve
        UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:@"Cancel"
                                                               style:UIAlertActionStyleCancel
                                                             handler:^(UIAlertAction *action) {
            if (completion) completion(NO);
        }];
        [alert addAction:cancelAction];

        [presentingVC presentViewController:alert animated:YES completion:nil];
    });
}

#pragma mark - Safety mode notice

- (void)showSafetyModeChangedHint {
    dispatch_async(dispatch_get_main_queue(), ^{
        AiSafetyMode mode = [self currentMode];
        NSString *title = @"Safety Mode Changed";
        NSString *message = [[self class] safetyModeChineseName:mode];
        UIViewController *presentingVC = [self topmostPresentableViewController];
        if (!presentingVC) {
            NSLog(@"[AiSafetyManager] Could not show safety mode notice (no available VC)");
            return;
        }
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:title
                                                                        message:message
                                                                 preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"Got It"
                                                  style:UIAlertActionStyleDefault
                                                handler:nil]];
        [presentingVC presentViewController:alert animated:YES completion:nil];
    });
}

- (NSString *)permissionChineseName:(AiToolPermission)permission {
    switch (permission) {
        case AiToolPermissionReadOnly:          return @"Read-only operation";
        case AiToolPermissionControlledWrite:   return @"Controlled write";
        case AiToolPermissionDangerousWrite:    return @"Dangerous write";
        case AiToolPermissionExternalNetwork:   return @"Network access";
    }
    return @"Unknown operation";
}

+ (NSString *)safetyModeChineseName:(AiSafetyMode)mode {
    switch (mode) {
        case AiSafetyModeSafe:
            return @"Safe\n\nOnly read-only operations are allowed. Operations that modify or delete files will be denied.\nSuitable for everyday use and maximizes protection of your data.";
        case AiSafetyModeAsk:
            return @"Ask\n\nWrite operations and network requests prompt for confirmation before execution, so you can approve or deny each one.\nRecommended mode balancing safety and convenience.";
        case AiSafetyModeYOLO:
            return @"Full (YOLO)\n\nWrite operations and network requests execute without confirmation.\nFor scenarios where you fully trust the AI; use with caution!";
    }
    return @"Unknown mode";
}

@end