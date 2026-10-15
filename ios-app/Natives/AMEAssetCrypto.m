#import "AMEAssetCrypto.h"
#import <CommonCrypto/CommonCryptor.h>

static const uint8_t kAmeKey[] = {
    0x4D, 0x65, 0x74, 0x61, 0x6C, 0x6C, 0x69, 0x63,
    0x41, 0x6D, 0x65, 0x74, 0x68, 0x79, 0x73, 0x74,
    0x56, 0x46, 0x53, 0x32, 0x30, 0x32, 0x36, 0x21,
    0x45, 0x6E, 0x63, 0x72, 0x79, 0x70, 0x74, 0x24
};

static const uint8_t kAmeIV[] = {
    0x1A, 0x3F, 0x9B, 0x82, 0x44, 0x71, 0x05, 0xE2,
    0x68, 0x90, 0xAC, 0xDF, 0x51, 0x73, 0x29, 0xB4
};

@implementation AMEAssetCrypto

+ (nullable NSData *)decryptData:(NSData *)encryptedData {
    if (!encryptedData || encryptedData.length == 0) return nil;
    
    size_t outLength = 0;
    NSMutableData *decrypted = [NSMutableData dataWithLength:encryptedData.length + kCCBlockSizeAES128];
    
    CCCryptorStatus status = CCCrypt(
        kCCDecrypt,
        kCCAlgorithmAES,
        kCCOptionPKCS7Padding,
        kAmeKey,
        sizeof(kAmeKey),
        kAmeIV,
        encryptedData.bytes,
        encryptedData.length,
        decrypted.mutableBytes,
        decrypted.length,
        &outLength
    );
    
    if (status == kCCSuccess) {
        decrypted.length = outLength;
        return decrypted;
    }
    return nil;
}

+ (nullable NSData *)dataForResource:(NSString *)name ofType:(NSString *)ext {
    // 1. Check for encrypted container (.enc)
    NSString *encPath = [[NSBundle mainBundle] pathForResource:name ofType:@"enc"];
    if (encPath.length > 0) {
        NSData *encData = [NSData dataWithContentsOfFile:encPath];
        NSData *dec = [self decryptData:encData];
        if (dec) return dec;
    }
    
    // 2. Fallback to raw unencrypted resource if present
    NSString *rawPath = [[NSBundle mainBundle] pathForResource:name ofType:ext];
    if (rawPath.length > 0) {
        return [NSData dataWithContentsOfFile:rawPath];
    }
    return nil;
}

+ (nullable UIImage *)imageForResource:(NSString *)name ofType:(NSString *)ext {
    NSData *data = [self dataForResource:name ofType:ext];
    if (data.length > 0) {
        return [UIImage imageWithData:data];
    }
    return nil;
}

@end
