//
//  LanPortDetector.m
//  Amethyst
//
//  Minecraft "Open to LAN" port detector (manual-entry version) implementation
//

#import "LanPortDetector.h"

/// Notification name: sent when the port is set manually.
NSString *const LanPortDetectorDidDetectPortNotification = @"LanPortDetectorDidDetectPort";

@interface LanPortDetector ()
/// Currently configured port (0 means unset).
@property (nonatomic, assign, readwrite) uint16_t detectedPort;
@end

@implementation LanPortDetector

#pragma mark - Singleton

+ (instancetype)sharedInstance {
    static LanPortDetector *shared = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        shared = [[self alloc] init];
    });
    return shared;
}

#pragma mark - Set port manually

/// Set the MC LAN port manually.
- (void)setManualPort:(uint16_t)port {
    self.detectedPort = port;

    NSLog(@"[LanPortDetector] Manually set LAN port: %u", port);

    // Send notification; userInfo contains the port number.
    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:LanPortDetectorDidDetectPortNotification
                                                            object:self
                                                          userInfo:@{ @"port": @(port) }];
    });
}

@end
