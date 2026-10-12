//
//  CurseForgeMurmurHash.m
//  Amethyst
//
//  CurseForge MurmurHash2 file-fingerprint calculation (used to look up a mod's fingerprint for "Check for Updates")
//
//  Fix rationale: ModUpdateService previously passed the mod.filePath string directly to
//  CurseForgeAPI projectForFileHash:. Internally, [murmurHash longLongValue] always evaluates a
//  file path to 0, so its fingerprint never matches. This file calculates the actual local fingerprint.
//
//  Algorithm notes (verified by sandbox testing, 2026-08):
//  CurseForge fingerprints use MurmurHash2 (32-bit, seed 1), and must filter four whitespace bytes
//  before calculation: 0x09 (tab) / 0x0a (LF) / 0x0d (CR) / 0x20 (space) (unlike Modrinth's full
//  SHA-1). Test evidence: submitting the full bytes of sodium-fabric-0.5.13+mc1.20.1.jar
//  (murmur2=1718316660) to /v1/fingerprints/432 returned unmatchedFingerprints; after filtering
//  whitespace, murmur2=2838862230 matched exactMatches (file.modId=394468).
//  JEI 15.49.0.191 likewise matched only with the filtered variant (2268438859; file.modId=238222).
//  Consistent with the repository's existing MurmurHash2.m (streaming implementation) and reference
//  implementations such as packwiz/murmwur.
//

#import "CurseForgeMurmurHash.h"
#include <stdint.h>
#include <stdlib.h>

// MurmurHash2 algorithm constants.
static const uint32_t kCFMurmur2_M = 0x5bd1e995u;
static const int kCFMurmur2_R = 24;
static const uint32_t kCFMurmur2_Seed = 1u;

uint32_t CFMurmurHash2(const uint8_t *data, size_t len) {
    uint32_t h = kCFMurmur2_Seed ^ (uint32_t)len;
    while (len >= 4) {
        // Assemble a 4-byte block in little-endian order.
        uint32_t k = ((uint32_t)data[0])
                   | ((uint32_t)data[1] << 8)
                   | ((uint32_t)data[2] << 16)
                   | ((uint32_t)data[3] << 24);
        // Core mixing.
        k *= kCFMurmur2_M;
        k ^= k >> kCFMurmur2_R;
        k *= kCFMurmur2_M;
        h *= kCFMurmur2_M;
        h ^= k;
        data += 4;
        len -= 4;
    }
    // Fewer than 4 trailing bytes (intentional fall-through, matching the standard implementation).
    switch (len) {
        case 3:
            h ^= ((uint32_t)data[2]) << 16;
            // fall through
        case 2:
            h ^= ((uint32_t)data[1]) << 8;
            // fall through
        case 1:
            h ^= (uint32_t)data[0];
            h *= kCFMurmur2_M;
            break;
        default:
            break;
    }
    // Final mixing.
    h ^= h >> 13;
    h *= kCFMurmur2_M;
    h ^= h >> 15;
    return h;
}

@implementation CurseForgeMurmurHash

+ (uint32_t)fingerprintForFileAtPath:(NSString *)path {
    if (path.length == 0) return 0;
    NSData *data = [NSData dataWithContentsOfFile:path];
    if (!data || data.length == 0 || data.length > UINT32_MAX) return 0;

    const uint8_t *src = (const uint8_t *)data.bytes;
    NSUInteger length = data.length;
    // Buffer after filtering whitespace bytes (worst case equals the original length).
    uint8_t *filtered = malloc(length);
    if (!filtered) return 0;
    NSUInteger filteredLen = 0;
    for (NSUInteger i = 0; i < length; i++) {
        uint8_t b = src[i];
        if (b == 0x09 || b == 0x0a || b == 0x0d || b == 0x20) continue;
        filtered[filteredLen++] = b;
    }
    uint32_t fingerprint = CFMurmurHash2(filtered, filteredLen);
    free(filtered);
    return fingerprint;
}

@end
