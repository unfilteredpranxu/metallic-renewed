#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// Custom account-avatar import manager (singleton).
/// Stores custom avatar PNGs as Documents/avatars/<accountName>.png.
/// Prefer local images when loading; fall back to the online URL.
@interface AvatarManager : NSObject

+ (instancetype)sharedManager;

/// Save a custom avatar image for the specified account.
/// No-op if accountName is nil or empty.
- (void)saveAvatarForAccount:(NSString *)accountName
                     image:(UIImage *)image
          withCompletion:(void (^)(BOOL success, NSError * _Nullable error))completion;

/// Read the custom avatar image for the specified account; return nil if it does not exist.
- (nullable UIImage *)avatarForAccount:(NSString *)accountName;

/// Whether a custom avatar exists for the specified account.
- (BOOL)hasCustomAvatarForAccount:(NSString *)accountName;

/// Delete the specified account's custom avatar (restore use of its online URL avatar).
- (void)removeAvatarForAccount:(NSString *)accountName;

@end

NS_ASSUME_NONNULL_END
