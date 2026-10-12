//
//  LanPortDetector.h
//  Amethyst
//
//  Minecraft "Open to LAN" port detector (manual-entry version)
//
//  Note: automatic detection (parsing latestlog.txt) was removed because log formats vary widely
//  between Minecraft versions and old logs may cause false detections. Only the manual port-entry
//  API remains.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Notification name: sent when the port is set manually.
/// userInfo: @{ @"port": @(port number) }
extern NSString *const LanPortDetectorDidDetectPortNotification;

/// Minecraft "Open to LAN" port detector (manual-entry version).
@interface LanPortDetector : NSObject

/// Access the singleton.
+ (instancetype)sharedInstance;

/// Set the MC LAN port manually.
/// @param port Port number shown in the Minecraft chat after "Open to LAN".
- (void)setManualPort:(uint16_t)port;

@end

NS_ASSUME_NONNULL_END
