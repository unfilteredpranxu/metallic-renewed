//
//  CurseForgeMurmurHash.h
//  Amethyst
//
//  CurseForge MurmurHash2 file-fingerprint calculation (used to look up a mod's fingerprint for "Check for Updates")
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Core of CurseForge's standard fingerprint algorithm: MurmurHash2 (32-bit, seed 1).
/// Run pure MurmurHash2 over the input byte sequence (do not filter any bytes).
uint32_t CFMurmurHash2(const uint8_t *data, size_t len);

/// CurseForge file-fingerprint utility.
@interface CurseForgeMurmurHash : NSObject

/// Calculate the CurseForge fingerprint of the specified file.
/// Follow CurseForge's actual rule: first filter whitespace bytes (0x09/0x0a/0x0d/0x20),
/// then run MurmurHash2 (seed 1) over the filtered byte stream.
/// @param path Local file path (mod JAR).
/// @return Unsigned 32-bit fingerprint; returns 0 if the file cannot be read.
+ (uint32_t)fingerprintForFileAtPath:(NSString *)path;

@end

NS_ASSUME_NONNULL_END
