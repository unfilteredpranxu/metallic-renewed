#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Modpack export format (based on FCL/HMCL/ZL2).
typedef NS_ENUM(NSInteger, ModpackExportFormat) {
    ModpackExportFormatModrinth = 0,   // Modrinth .mrpack format.
    ModpackExportFormatCurseForge = 1, // CurseForge .zip format (manifest.json).
    ModpackExportFormatMMC = 2,        // MMC (MultiMC/Prism) .zip format (mmc-pack.json + instance.cfg).
    ModpackExportFormatPlainZip = 3,   // Plain .zip format (packs the .minecraft directory directly; HMCL compatible).
    ModpackExportFormatLinkList = 4,   // Link-list .txt format (simple format supported by FCL).
};

/// File types that can optionally be included during export (bitmask).
/// Note: enum-value names must not conflict with the typedef `ModpackExportFileOptions`,
/// so the flag for options.txt is named `ModpackExportFileGameSettings`.
typedef NS_OPTIONS(NSInteger, ModpackExportFileOptions) {
    ModpackExportFileNone           = 0,
    ModpackExportFileMods           = 1 << 0,  // mods/ directory.
    ModpackExportFileConfigs        = 1 << 1,  // config/ + defaultconfigs/
    ModpackExportFileResourcePacks  = 1 << 2,  // resourcepacks/
    ModpackExportFileShaderPacks    = 1 << 3,  // shaderpacks/
    ModpackExportFileSaves          = 1 << 4,  // saves/ (excluded by default).
    ModpackExportFileGameSettings   = 1 << 5,  // options.txt/optionsof.txt/optionsshaders.txt
    ModpackExportFileServers        = 1 << 6,  // servers.dat (excluded by default; contains sensitive information).
    ModpackExportFileScripts        = 1 << 7,  // kubejs/scripts/localization/patchouli_books
    ModpackExportFileDefault        = ModpackExportFileMods | ModpackExportFileConfigs |
                                      ModpackExportFileResourcePacks | ModpackExportFileShaderPacks |
                                      ModpackExportFileGameSettings | ModpackExportFileScripts,
    ModpackExportFileAll            = ModpackExportFileMods | ModpackExportFileConfigs |
                                      ModpackExportFileResourcePacks | ModpackExportFileShaderPacks |
                                      ModpackExportFileSaves | ModpackExportFileGameSettings |
                                      ModpackExportFileServers | ModpackExportFileScripts,
};

/// Modpack export service (based on FCL ExportModpackViewModel.kt / HMCL ModpackHelper / ZL2 ExportModpackHelper).
@interface ModpackExportService : NSObject

+ (instancetype)sharedService;

/// Cancellation signal: when an external caller sets this to YES, an active export stops at the next checkpoint.
@property (nonatomic, assign, getter=isCancelled) BOOL cancelled;

/// Resets the cancellation state (call before starting a new export).
- (void)resetCancelState;

/// Exports a modpack (basic version, using default file options).
/// @param profileName Profile name (gets gameDir/lastVersionId from PLProfiles.current.profiles).
/// @param destPath Destination file path (.mrpack / .zip / .txt).
/// @param name Modpack name.
/// @param version Modpack version.
/// @param author Author.
/// @param format Export format.
/// @param includeOverrides Whether to include overrides (config/options.txt, etc.); equivalent to ModpackExportFileDefault.
/// @param progress Progress callback (0.0-1.0).
/// @param error Error information.
/// @return Whether the export succeeded.
- (BOOL)exportModpackForProfile:(NSString *)profileName
                         toPath:(NSString *)destPath
                            name:(NSString *)name
                         version:(NSString *)version
                          author:(NSString *)author
                         format:(ModpackExportFormat)format
                includeOverrides:(BOOL)includeOverrides
                       progress:(void (^_Nullable)(double progress, NSString *stageMessage))progress
                          error:(NSError **)error;

/// Exports a modpack (advanced version, supports file-type filtering).
/// @param fileOptions File-type bitmask; determines which directories/files are included in overrides.
- (BOOL)exportModpackForProfile:(NSString *)profileName
                         toPath:(NSString *)destPath
                            name:(NSString *)name
                         version:(NSString *)version
                          author:(NSString *)author
                         format:(ModpackExportFormat)format
                     fileOptions:(ModpackExportFileOptions)fileOptions
                       progress:(void (^_Nullable)(double progress, NSString *stageMessage))progress
                          error:(NSError **)error;

/// Infers the loader and Minecraft version from lastVersionId.
/// For example, "fabric-loader-0.15.7-1.20.1" → loader="fabric", loaderVersion="0.15.7", mcVersion="1.20.1".
/// "1.20.1-forge-47.3.0" → loader="forge", loaderVersion="47.3.0", mcVersion="1.20.1"
/// "1.20.1-neoforge-47.1.0" → loader="neoforge", loaderVersion="47.1.0", mcVersion="1.20.1"
+ (NSDictionary *)parseVersionId:(NSString *)versionId;

/// Returns the directories to package based on fileOptions (without the "overrides/" prefix).
+ (NSArray<NSString *> *)overrideDirectoriesForOptions:(ModpackExportFileOptions)options;

/// Returns the files to package based on fileOptions (top-level filenames).
+ (NSArray<NSString *> *)overrideFilesForOptions:(ModpackExportFileOptions)options;

@end

NS_ASSUME_NONNULL_END
