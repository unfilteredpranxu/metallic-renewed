#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface AMEAssetCrypto : NSObject

+ (nullable NSData *)decryptData:(NSData *)encryptedData;
+ (nullable NSData *)dataForResource:(NSString *)name ofType:(NSString *)ext;
+ (nullable UIImage *)imageForResource:(NSString *)name ofType:(NSString *)ext;

@end

NS_ASSUME_NONNULL_END
