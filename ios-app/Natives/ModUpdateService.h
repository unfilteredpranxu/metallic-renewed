#import <Foundation/Foundation.h>
#import "ModItem.h"
#import "ModVersion.h"

NS_ASSUME_NONNULL_BEGIN

/// Update-check result for a single mod.
@interface ModUpdateResult : NSObject
/// Local mod file path.
@property (nonatomic, copy) NSString *localFilePath;
/// Current version (the version matched by reverse lookup).
@property (nonatomic, strong, nullable) ModVersion *currentVersion;
/// Candidate update versions (sorted by datePublished descending, newest first).
@property (nonatomic, copy) NSArray<ModVersion *> *candidateVersions;
/// All versions (for selecting a downgrade, sorted by datePublished descending).
@property (nonatomic, copy) NSArray<ModVersion *> *allVersions;
/// Project ID (used to fetch the version list).
@property (nonatomic, copy, nullable) NSString *projectID;
/// API source (1=Modrinth, 2=CurseForge).
@property (nonatomic, strong, nullable) NSNumber *apiSource;
/// Project type (mod/shader/resourcepack/datapack).
@property (nonatomic, copy) NSString *projectType;
/// Whether an update is available.
- (BOOL)hasUpdate;
@end

@interface ModUpdateService : NSObject

+ (instancetype)sharedService;

/// Checks a single mod for updates.
/// @param mod Local mod item (must have filePath and fileSHA1).
/// @param gameVersion Current game version (e.g. "1.20.1").
/// @param loader Current loader (e.g. "fabric"/"forge"/"neoforge"/"quilt"; may be nil).
/// @param projectType Project type (mod/shader/resourcepack/datapack).
/// @param completion Result callback (on the main thread; result is nil if the check fails or there is no match).
- (void)checkUpdateForMod:(ModItem *)mod
              gameVersion:(NSString *)gameVersion
                   loader:(nullable NSString *)loader
              projectType:(NSString *)projectType
               completion:(void (^)(ModUpdateResult *_Nullable result))completion;

/// Checks a batch of mods for updates (limited to 3 concurrent requests).
/// @param mods Array of local mods.
/// @param gameVersion Current game version.
/// @param loader Current loader.
/// @param projectType Project type.
/// @param progress Progress callback (completed count / total count).
/// @param completion Callback when all checks finish (results array contains one result per mod; mods without updates are omitted).
- (void)checkUpdatesForMods:(NSArray<ModItem *> *)mods
               gameVersion:(NSString *)gameVersion
                    loader:(nullable NSString *)loader
               projectType:(NSString *)projectType
                  progress:(void (^)(NSInteger completed, NSInteger total))progress
                completion:(void (^)(NSArray<ModUpdateResult *> *results))completion;

@end

NS_ASSUME_NONNULL_END
