//
//  DataPackService.h
//  Amethyst
//
//  Local data-pack management and download service, structured like ShaderService/ModService.
//  API signatures consistently use NSString *profileName (matching ModService).
//  Adds pack.mcmeta parsing (pack_format / description).
//  Adds a worldName parameter to support downloading to a specific world's datapacks directory
//  (saves/<worldName>/datapacks/).
//  Downloads use the shared PLDownloadClient (mirror candidates + SHA1 validation + incremental
//  download + resume support).
//

#import <Foundation/Foundation.h>
#import "DataPackItem.h"

NS_ASSUME_NONNULL_BEGIN

// Data-pack list callback.
typedef void(^DataPackListHandler)(NSArray<DataPackItem *> *items);
// Data-pack metadata callback.
typedef void(^DataPackMetadataHandler)(DataPackItem *item, NSError * _Nullable error);
// Download completion callback (success indicates whether it succeeded).
typedef void(^DataPackDownloadCompletionHandler)(BOOL success, NSError * _Nullable error);
// Download progress callback (runs on the main thread; safe for UI updates).
typedef void(^DataPackDownloadProgressHandler)(NSProgress * _Nullable downloadProgress);

@interface DataPackService : NSObject

@property (nonatomic, assign) BOOL onlineSearchEnabled;

+ (instancetype)sharedService;

// --- Local data-pack management ---
// Scan the specified profile's datapacks directory and return .zip and .zip.disabled files.
- (void)scanDataPacksForProfile:(NSString *)profileName completion:(DataPackListHandler)completion;
// Get data-pack metadata (parse pack.mcmeta inside the zip to get pack_format and description).
- (void)fetchMetadataForDataPack:(DataPackItem *)item completion:(DataPackMetadataHandler)completion;
// Enable/disable a data pack (add/remove the .disabled suffix).
- (BOOL)toggleEnableForDataPack:(DataPackItem *)item error:(NSError **)error;
// Delete a data-pack file.
- (BOOL)deleteDataPack:(DataPackItem *)item error:(NSError **)error;

// --- Online data-pack downloads ---
// Download a data pack to the specified profile's datapacks directory (<gameDir>/datapacks/),
// with real-time progress callbacks.
// Note: Minecraft requires data packs in <gameDir>/saves/<world name>/datapacks/, but iOS cannot
// select a world, so downloads default to <gameDir>/datapacks/ and the user must move them manually.
- (void)downloadDataPack:(DataPackItem *)item
               toProfile:(NSString *)profileName
                progress:(DataPackDownloadProgressHandler _Nullable)progress
              completion:(DataPackDownloadCompletionHandler _Nullable)completion;

// Download a data pack to the specified world's datapacks directory
// (<gameDir>/saves/<worldName>/datapacks/).
// If worldName is nil, fall back to <gameDir>/datapacks/.
- (void)downloadDataPack:(DataPackItem *)item
               toProfile:(NSString *)profileName
               worldName:(nullable NSString *)worldName
                progress:(DataPackDownloadProgressHandler _Nullable)progress
              completion:(DataPackDownloadCompletionHandler _Nullable)completion;

/// Download the data pack with SHA1 validation enabled (spec optimize-download-system Task 5.1).
/// expectedSHA1 comes from the version model primaryFile[@"hashes"][@"sha1"] (Modrinth
/// files[].hashes.sha1 / CurseForge hashes algo=1). If provided, validation is enabled and the
/// shared downloader retries on validation failure according to the mirror/backoff schedule.
/// If nil, skip SHA1 validation and rely on the zip EOCD fallback check for integrity.
- (void)downloadDataPack:(DataPackItem *)item
               toProfile:(NSString *)profileName
               worldName:(nullable NSString *)worldName
            expectedSHA1:(nullable NSString *)expectedSHA1
                progress:(DataPackDownloadProgressHandler _Nullable)progress
              completion:(DataPackDownloadCompletionHandler _Nullable)completion;

// --- Utility methods ---
- (NSString *)iconCachePathForURL:(NSString *)urlString;

/// Get the current profile's datapacks directory, creating it if it does not exist.
- (nullable NSString *)ensureDataPacksFolderForProfile:(NSString *)profileName error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
