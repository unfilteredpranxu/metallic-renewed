//
//  ModDependencyResolver.h
//  Automatic mod dependency resolution (prerequisites)
//
//  Background: based on ZalithLauncher2's _Download.Dependency.Tasks.kt and
//  FoldCraftLauncher's ModrinthRemoteModRepository.loadDependencies().
//  Previously, iOS had no dependency resolution. After downloading a mod, users had to find and install any required prerequisites
//  it declared (e.g. Iris depends on Sodium, and Sodium depends on Fabric API), or the game could crash at launch or features could fail silently.
//
//  Responsibilities:
//    * This class only resolves which additional files are needed; it does not download them.
//    * Downloads are handled by the caller (ModService / resource download flow), reusing existing
//      mirror fallback, SHA1 validation, and progress reporting.
//    * It does not decide whether to downgrade/upgrade; skip a project if another version is installed and let the user decide.
//
//  The two platforms use different dependency-field structures:
//    Modrinth  version.dependencies[] = { project_id, version_id,
//                                          dependency_type }
//    CurseForge data.dependencies[]   = { modId, relationType }
//  Normalize them as ModDependencyItem before passing them to the caller.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Dependency type. Handles only "required" and "optional"; incompatible, embedded, and tool dependencies are not installed automatically.
typedef NS_ENUM(NSInteger, ModDependencyKind) {
    ModDependencyKindRequired = 0,  /* Required: do not continue if installation fails. */
    ModDependencyKindOptional = 1,  /* Optional: notify the user; do not install by default. */
};

/// A dependency to install (from Modrinth or CurseForge).
@interface ModDependencyItem : NSObject

@property(nonatomic, assign) NSInteger apiSource;         /* 1=Modrinth 2=CurseForge */
@property(nonatomic, copy, nullable) NSString *projectId; /* Project ID (used to look up versions). */
@property(nonatomic, copy, nullable) NSString *versionId; /* Specific version (may be provided by Modrinth). */
@property(nonatomic, assign) ModDependencyKind kind;
@property(nonatomic, copy, nullable) NSString *displayName; /* Used only in user-facing messages. */

@end

/// Resolution result.
@interface ModDependencyPlan : NSObject

/// Dependencies to install (topologically sorted by dependency order: dependencies come first).
@property(nonatomic, copy) NSArray<ModDependencyItem *> *required;
/// Optional dependencies (shown in the UI only; not downloaded automatically).
@property(nonatomic, copy) NSArray<ModDependencyItem *> *optional;
/// Project IDs skipped because another version of the same project is already installed.
@property(nonatomic, copy) NSArray<NSString *> *skippedAlreadyInstalled;
/// Project IDs abandoned because depth/count limits were exceeded (cycle and explosion prevention).
@property(nonatomic, copy) NSArray<NSString *> *truncated;

@end

@interface ModDependencyResolver : NSObject

+ (instancetype)sharedResolver;

/// Resolves the dependency tree from a "version details" dictionary.
///
/// @param versionDetail Version details. For Modrinth: an item from GET project/{id}/version
///                      (containing dependencies[]); for CurseForge: the data from GET mods/{id}/files/{fid}
///                      (containing dependencies[]).
/// @param apiSource     1=Modrinth，2=CurseForge
/// @param installedProjectIds Set of locally installed project IDs (used to skip already-installed prerequisites).
/// @param loader        Loader for the current instance (fabric/forge/neoforge/quilt), used for filtering.
/// @param gameVersion   Minecraft version for the current instance, used for filtering.
/// @param completion    Main-thread callback. plan is never nil (both arrays are empty when there are no dependencies).
- (void)resolveDependenciesFromVersionDetail:(NSDictionary *)versionDetail
                                   apiSource:(NSInteger)apiSource
                        installedProjectIds:(nullable NSSet<NSString *> *)installedProjectIds
                                      loader:(nullable NSString *)loader
                                 gameVersion:(nullable NSString *)gameVersion
                                  completion:(void (^)(ModDependencyPlan *plan, NSError * _Nullable error))completion;

@end

NS_ASSUME_NONNULL_END
