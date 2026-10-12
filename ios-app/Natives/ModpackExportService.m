#import "utils.h"
#import "ModpackExportService.h"
#import "PLProfiles.h"
#import "ModService.h"
#import "external/UnzipKit/UZKArchive.h"
#import <CommonCrypto/CommonCrypto.h>

@interface ModpackExportService ()
/// Resolves the profile gameDir to an absolute path (reuses ModService logic).
- (nullable NSString *)resolveAbsoluteGameDirForProfile:(NSString *)profileName;
/// Computes a file's SHA1 (reads in chunks to avoid memory pressure on large files).
- (nullable NSString *)sha1ForFileAtPath:(NSString *)path;
/// Computes a file's SHA512 (reads in chunks).
- (nullable NSString *)sha512ForFileAtPath:(NSString *)path;
/// Recursively writes a directory to a ZIP.
- (void)addDirectoryToArchive:(UZKArchive *)archive
                      dirPath:(NSString *)dirPath
                  prefixInZip:(NSString *)prefixInZip
                     progress:(void (^_Nullable)(NSUInteger done, NSUInteger total))progress;
/// Internal use: checks the cancellation signal.
- (BOOL)checkCancelledWithError:(NSError **)error;
@end

@implementation ModpackExportService

+ (instancetype)sharedService {
    static ModpackExportService *sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[self alloc] init];
    });
    return sharedInstance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _cancelled = NO;
    }
    return self;
}

- (void)resetCancelState {
    @synchronized(self) {
        _cancelled = NO;
    }
}

- (BOOL)checkCancelledWithError:(NSError **)error {
    @synchronized(self) {
        if (_cancelled) {
            if (error) {
                *error = [NSError errorWithDomain:@"ModpackExportService"
                                             code:9999
                                         userInfo:@{NSLocalizedDescriptionKey: localize(@"i18n_str_469", nil)}];
            }
            return YES;
        }
    }
    return NO;
}

+ (NSArray<NSString *> *)overrideDirectoriesForOptions:(ModpackExportFileOptions)options {
    NSMutableArray *dirs = [NSMutableArray array];
    if (options & ModpackExportFileMods) {
        [dirs addObject:@"mods"];
    }
    if (options & ModpackExportFileConfigs) {
        [dirs addObject:@"config"];
        [dirs addObject:@"defaultconfigs"];
    }
    if (options & ModpackExportFileResourcePacks) {
        [dirs addObject:@"resourcepacks"];
    }
    if (options & ModpackExportFileShaderPacks) {
        [dirs addObject:@"shaderpacks"];
    }
    if (options & ModpackExportFileSaves) {
        [dirs addObject:@"saves"];
    }
    if (options & ModpackExportFileScripts) {
        [dirs addObject:@"kubejs"];
        [dirs addObject:@"scripts"];
        [dirs addObject:@"localization"];
        [dirs addObject:@"patchouli_books"];
    }
    return [dirs copy];
}

+ (NSArray<NSString *> *)overrideFilesForOptions:(ModpackExportFileOptions)options {
    NSMutableArray *files = [NSMutableArray array];
    if (options & ModpackExportFileGameSettings) {
        [files addObject:@"options.txt"];
        [files addObject:@"optionsof.txt"];
        [files addObject:@"optionsshaders.txt"];
        [files addObject:@"hotbar.nbt"];
    }
    if (options & ModpackExportFileServers) {
        [files addObject:@"servers.dat"];
        [files addObject:@"servers.dat_old"];
        [files addObject:@"realms_persistence.json"];
    }
    if (options & ModpackExportFileGameSettings) {
        [files addObject:@"launcher_profiles.json"];
    }
    return [files copy];
}

#pragma mark - Public export API

- (BOOL)exportModpackForProfile:(NSString *)profileName
                         toPath:(NSString *)destPath
                            name:(NSString *)name
                         version:(NSString *)version
                          author:(NSString *)author
                         format:(ModpackExportFormat)format
                includeOverrides:(BOOL)includeOverrides
                       progress:(void (^_Nullable)(double progress, NSString *stageMessage))progress
                          error:(NSError **)error {
    ModpackExportFileOptions options = includeOverrides ? ModpackExportFileDefault : ModpackExportFileMods;
    return [self exportModpackForProfile:profileName
                                  toPath:destPath
                                     name:name
                                  version:version
                                   author:author
                                  format:format
                              fileOptions:options
                                 progress:progress
                                    error:error];
}

- (BOOL)exportModpackForProfile:(NSString *)profileName
                         toPath:(NSString *)destPath
                            name:(NSString *)name
                         version:(NSString *)version
                          author:(NSString *)author
                         format:(ModpackExportFormat)format
                     fileOptions:(ModpackExportFileOptions)fileOptions
                       progress:(void (^_Nullable)(double progress, NSString *stageMessage))progress
                          error:(NSError **)error {
    if (error) *error = nil;
    NSString *resolvedAuthor = author.length > 0 ? author : @"Amethyst User";

    void (^reportProgress)(double, NSString *) = ^(double p, NSString *msg) {
        NSLog(@"[ModpackExport] Progress: %.2f - %@", p, msg);
        if (progress) progress(p, msg);
    };

    reportProgress(0.0, localize(@"i18n_str_1274", nil));

    // Cancellation checkpoint.
    if ([self checkCancelledWithError:error]) return NO;

    // 1. Get profile information.
    NSDictionary *profile = PLProfiles.current.profiles[profileName];
    if (![profile isKindOfClass:[NSDictionary class]]) {
        if (error) {
            *error = [NSError errorWithDomain:@"ModpackExportService" code:1
                                     userInfo:@{NSLocalizedDescriptionKey: localize(@"i18n_str_471", nil)}];
        }
        return NO;
    }

    NSString *lastVersionId = profile[@"lastVersionId"] ?: @"";
    NSString *gameDirAbsolute = [self resolveAbsoluteGameDirForProfile:profileName];
    if (gameDirAbsolute.length == 0) {
        const char *env = getenv("POJAV_GAME_DIR");
        gameDirAbsolute = env ? [NSString stringWithUTF8String:env] : NSHomeDirectory();
    }

    // 2. Resolve the loader and Minecraft version.
    NSDictionary *versionInfo = [ModpackExportService parseVersionId:lastVersionId];
    NSString *mcVersion = versionInfo[@"minecraft"] ?: @"";
    NSString *loader = versionInfo[@"loader"] ?: @"";
    NSString *loaderVersion = versionInfo[@"loaderVersion"] ?: @"";

    NSLog(@"[ModpackExport] Profile=%@, mcVersion=%@, loader=%@ %@, gameDir=%@",
          profileName, mcVersion, loader, loaderVersion, gameDirAbsolute);

    if (mcVersion.length == 0) {
        if (error) {
            *error = [NSError errorWithDomain:@"ModpackExportService" code:2
                                     userInfo:@{NSLocalizedDescriptionKey: localize(@"i18n_str_472", nil)}];
        }
        return NO;
    }

    // Cancellation checkpoint.
    if ([self checkCancelledWithError:error]) return NO;

    // 3. Collect the list of mod files.
    reportProgress(0.1, localize(@"i18n_str_1275", nil));
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *modsDir = [gameDirAbsolute stringByAppendingPathComponent:@"mods"];
    NSMutableArray<NSDictionary *> *modFiles = [NSMutableArray new];
    if ([fm fileExistsAtPath:modsDir]) {
        // Scan nested directories (some modpacks store mods in subdirectories).
        NSDirectoryEnumerator *enumerator = [fm enumeratorAtPath:modsDir];
        NSString *relativePath;
        while ((relativePath = [enumerator nextObject])) {
            NSString *fullPath = [modsDir stringByAppendingPathComponent:relativePath];
            BOOL isDir = NO;
            if (![fm fileExistsAtPath:fullPath isDirectory:&isDir] || isDir) continue;
            // Include only .jar files (exclude .disabled).
            if (![relativePath hasSuffix:@".jar"]) continue;
            NSDictionary *attrs = [fm attributesOfItemAtPath:fullPath error:nil];
            unsigned long long fileSize = [attrs fileSize];
            NSString *sha1 = [self sha1ForFileAtPath:fullPath];
            [modFiles addObject:@{
                @"path": [NSString stringWithFormat:@"mods/%@", relativePath],
                @"fullPath": fullPath,
                @"fileName": relativePath.lastPathComponent,
                @"sha1": sha1 ?: @"",
                @"fileSize": @(fileSize)
            }];
        }
    }
    NSLog(@"[ModpackExport] Found %lu mod files", (unsigned long)modFiles.count);

    // Cancellation checkpoint.
    if ([self checkCancelledWithError:error]) return NO;

    // 4. Export according to the format.
    switch (format) {
        case ModpackExportFormatModrinth:
            return [self exportModrinthFormat:modFiles
                                      toPath:destPath
                                         name:name
                                      version:version
                                       author:resolvedAuthor
                                    mcVersion:mcVersion
                                       loader:loader
                                loaderVersion:loaderVersion
                                gameDirAbsolute:gameDirAbsolute
                                  fileOptions:fileOptions
                                      progress:reportProgress
                                         error:error];
        case ModpackExportFormatCurseForge:
            return [self exportCurseForgeFormat:modFiles
                                         toPath:destPath
                                            name:name
                                         version:version
                                          author:resolvedAuthor
                                       mcVersion:mcVersion
                                          loader:loader
                                    loaderVersion:loaderVersion
                                gameDirAbsolute:gameDirAbsolute
                                  fileOptions:fileOptions
                                        progress:reportProgress
                                           error:error];
        case ModpackExportFormatMMC:
            return [self exportMMCFormat:modFiles
                                  toPath:destPath
                                     name:name
                                  version:version
                                   author:resolvedAuthor
                                mcVersion:mcVersion
                                   loader:loader
                            loaderVersion:loaderVersion
                            gameDirAbsolute:gameDirAbsolute
                              fileOptions:fileOptions
                                profileName:profileName
                                  progress:reportProgress
                                     error:error];
        case ModpackExportFormatPlainZip:
            return [self exportPlainZipFormat:modFiles
                                       toPath:destPath
                                          name:name
                                       version:version
                                        author:resolvedAuthor
                                     mcVersion:mcVersion
                                        loader:loader
                                  loaderVersion:loaderVersion
                                  gameDirAbsolute:gameDirAbsolute
                                    fileOptions:fileOptions
                                      progress:reportProgress
                                         error:error];
        case ModpackExportFormatLinkList:
            return [self exportLinkListFormat:modFiles
                                       toPath:destPath
                                      mcVersion:mcVersion
                                         loader:loader
                                   loaderVersion:loaderVersion
                                         name:name
                                       version:version
                                         error:error];
    }
    return NO;
}

#pragma mark - Export Modrinth format

- (BOOL)exportModrinthFormat:(NSArray<NSDictionary *> *)modFiles
                      toPath:(NSString *)destPath
                        name:(NSString *)name
                     version:(NSString *)version
                      author:(NSString *)author
                   mcVersion:(NSString *)mcVersion
                      loader:(NSString *)loader
              loaderVersion:(NSString *)loaderVersion
            gameDirAbsolute:(NSString *)gameDirAbsolute
                fileOptions:(ModpackExportFileOptions)fileOptions
                    progress:(void (^)(double, NSString *))progress
                       error:(NSError **)error {
    (void)author;
    if ([self checkCancelledWithError:error]) return NO;

    progress(0.2, localize(@"i18n_str_1276", nil));
    NSFileManager *fm = [NSFileManager defaultManager];

    // Build dependencies.
    NSMutableDictionary *dependencies = @{@"minecraft": mcVersion}.mutableCopy;
    if ([loader isEqualToString:@"fabric"] && loaderVersion.length > 0) {
        dependencies[@"fabric-loader"] = loaderVersion;
    } else if ([loader isEqualToString:@"quilt"] && loaderVersion.length > 0) {
        dependencies[@"quilt-loader"] = loaderVersion;
    } else if ([loader isEqualToString:@"forge"] && loaderVersion.length > 0) {
        dependencies[@"forge"] = loaderVersion;
    } else if ([loader isEqualToString:@"neoforge"] && loaderVersion.length > 0) {
        dependencies[@"neoforge"] = loaderVersion;
    }

    // Build the files list.
    NSMutableArray *files = [NSMutableArray new];
    for (NSDictionary *modFile in modFiles) {
        if ([self checkCancelledWithError:error]) return NO;
        NSString *sha512 = [self sha512ForFileAtPath:modFile[@"fullPath"]];
        [files addObject:@{
            @"path": modFile[@"path"],
            @"hashes": @{
                @"sha1": modFile[@"sha1"],
                @"sha512": sha512 ?: @""
            },
            @"downloads": @[],  // Leave download links empty; restore from overrides during import (matches HMCL export strategy).
            @"fileSize": modFile[@"fileSize"]
        }];
    }

    // Build modrinth.index.json.
    NSDictionary *indexJson = @{
        @"formatVersion": @(1),
        @"game": @"minecraft",
        @"versionId": version.length > 0 ? version : @"1.0",
        @"name": name.length > 0 ? name : @"Exported Modpack",
        @"files": files,
        @"dependencies": dependencies
    };

    NSData *indexData = [NSJSONSerialization dataWithJSONObject:indexJson options:NSJSONWritingPrettyPrinted error:error];
    if (!indexData) {
        if (error && !*error) {
            *error = [NSError errorWithDomain:@"ModpackExportService" code:3
                                     userInfo:@{NSLocalizedDescriptionKey: localize(@"i18n_str_475", nil)}];
        }
        return NO;
    }

    if ([self checkCancelledWithError:error]) return NO;

    progress(0.3, localize(@"i18n_str_1258", nil));
    [fm removeItemAtPath:destPath error:nil];

    NSError *archiveError = nil;
    UZKArchive *archive = [[UZKArchive alloc] initWithPath:destPath error:&archiveError];
    if (!archive || archiveError) {
        if (error) *error = archiveError;
        return NO;
    }

    // Write modrinth.index.json.
    progress(0.4, localize(@"i18n_str_1277", nil));
    if (![archive writeData:indexData filePath:@"modrinth.index.json" error:&archiveError]) {
        if (error) *error = archiveError;
        return NO;
    }

    // Write overrides.
    if (![self writeOverridesToArchive:archive
                          gameDirAbsolute:gameDirAbsolute
                            fileOptions:fileOptions
                              zipPrefix:@"overrides"
                          baseProgress:0.5
                          progressRange:0.4
                                progress:progress
                                  error:error]) {
        return NO;
    }

    progress(0.95, localize(@"i18n_str_1259", nil));
    archive = nil;

    progress(1.0, localize(@"i18n_str_1260", nil));
    NSLog(@"[ModpackExport] Modrinth format export completed: %@", destPath);
    return YES;
}

#pragma mark - Export CurseForge format

- (BOOL)exportCurseForgeFormat:(NSArray<NSDictionary *> *)modFiles
                        toPath:(NSString *)destPath
                           name:(NSString *)name
                        version:(NSString *)version
                         author:(NSString *)author
                      mcVersion:(NSString *)mcVersion
                         loader:(NSString *)loader
                 loaderVersion:(NSString *)loaderVersion
               gameDirAbsolute:(NSString *)gameDirAbsolute
                   fileOptions:(ModpackExportFileOptions)fileOptions
                       progress:(void (^)(double, NSString *))progress
                          error:(NSError **)error {
    if ([self checkCancelledWithError:error]) return NO;

    progress(0.2, localize(@"i18n_str_1278", nil));
    NSFileManager *fm = [NSFileManager defaultManager];

    // Build modLoaders.
    NSMutableArray *modLoaders = [NSMutableArray new];
    if (loader.length > 0 && loaderVersion.length > 0) {
        NSString *loaderId = [NSString stringWithFormat:@"%@-%@", loader, loaderVersion];
        [modLoaders addObject:@{@"id": loaderId, @"primary": @YES}];
    }

    // Build manifest.json.
    // Note: CurseForge format requires projectID/fileID, which are unavailable for local mods.
    // Simplified approach: leave files empty and pack all mods into overrides/mods/ (matches HMCL export strategy).
    NSDictionary *manifest = @{
        @"minecraft": @{
            @"version": mcVersion,
            @"modLoaders": modLoaders
        },
        @"manifestType": @"minecraftModpack",
        @"manifestVersion": @(1),
        @"name": name.length > 0 ? name : @"Exported Modpack",
        @"version": version.length > 0 ? version : @"1.0",
        @"author": author.length > 0 ? author : @"Amethyst User",
        @"files": @[],
        @"overrides": @"overrides"
    };

    NSData *manifestData = [NSJSONSerialization dataWithJSONObject:manifest options:NSJSONWritingPrettyPrinted error:error];
    if (!manifestData) {
        if (error && !*error) {
            *error = [NSError errorWithDomain:@"ModpackExportService" code:4
                                     userInfo:@{NSLocalizedDescriptionKey: localize(@"i18n_str_481", nil)}];
        }
        return NO;
    }

    if ([self checkCancelledWithError:error]) return NO;

    progress(0.3, localize(@"i18n_str_1258", nil));
    [fm removeItemAtPath:destPath error:nil];

    NSError *archiveError = nil;
    UZKArchive *archive = [[UZKArchive alloc] initWithPath:destPath error:&archiveError];
    if (!archive || archiveError) {
        if (error) *error = archiveError;
        return NO;
    }

    progress(0.4, localize(@"i18n_str_1279", nil));
    if (![archive writeData:manifestData filePath:@"manifest.json" error:&archiveError]) {
        if (error) *error = archiveError;
        return NO;
    }

    if (![self writeOverridesToArchive:archive
                          gameDirAbsolute:gameDirAbsolute
                            fileOptions:fileOptions
                              zipPrefix:@"overrides"
                          baseProgress:0.5
                          progressRange:0.4
                                progress:progress
                                  error:error]) {
        return NO;
    }

    progress(0.95, localize(@"i18n_str_1259", nil));
    archive = nil;

    progress(1.0, localize(@"i18n_str_1260", nil));
    NSLog(@"[ModpackExport] CurseForge format export completed: %@", destPath);
    return YES;
}

#pragma mark - Export MMC (MultiMC/Prism) format

/// MMC format:
///   mmc-pack.json: contains a components array (net.minecraft + loader component).
///   instance.cfg: key=value format, including name/JvmArgs/InstanceType, etc.
///   .minecraft/: contains mods/config/options.txt, etc. (not under overrides/; stored directly in .minecraft/).
- (BOOL)exportMMCFormat:(NSArray<NSDictionary *> *)modFiles
                 toPath:(NSString *)destPath
                    name:(NSString *)name
                 version:(NSString *)version
                  author:(NSString *)author
               mcVersion:(NSString *)mcVersion
                  loader:(NSString *)loader
          loaderVersion:(NSString *)loaderVersion
          gameDirAbsolute:(NSString *)gameDirAbsolute
            fileOptions:(ModpackExportFileOptions)fileOptions
            profileName:(NSString *)profileName
                progress:(void (^)(double, NSString *))progress
                   error:(NSError **)error {
    if ([self checkCancelledWithError:error]) return NO;

    progress(0.2, localize(@"i18n_str_1280", nil));
    NSFileManager *fm = [NSFileManager defaultManager];

    // Build the components array.
    NSMutableArray *components = [NSMutableArray array];
    [components addObject:@{
        @"cachedName": @"Minecraft",
        @"cachedVersion": mcVersion,
        @"important": @YES,
        @"uid": @"net.minecraft",
        @"version": mcVersion
    }];
    if ([loader isEqualToString:@"fabric"] && loaderVersion.length > 0) {
        [components addObject:@{
            @"cachedName": @"Fabric Loader",
            @"uid": @"net.fabricmc.fabric-loader",
            @"version": loaderVersion
        }];
    } else if ([loader isEqualToString:@"quilt"] && loaderVersion.length > 0) {
        [components addObject:@{
            @"cachedName": @"Quilt Loader",
            @"uid": @"org.quiltmc.quilt-loader",
            @"version": loaderVersion
        }];
    } else if ([loader isEqualToString:@"forge"] && loaderVersion.length > 0) {
        [components addObject:@{
            @"cachedName": @"Forge",
            @"uid": @"net.minecraftforge",
            @"version": loaderVersion
        }];
    } else if ([loader isEqualToString:@"neoforge"] && loaderVersion.length > 0) {
        [components addObject:@{
            @"cachedName": @"NeoForge",
            @"uid": @"net.neoforged",
            @"version": loaderVersion
        }];
    }

    NSDictionary *mmcPack = @{
        @"components": components,
        @"formatVersion": @(1)
    };

    NSData *mmcPackData = [NSJSONSerialization dataWithJSONObject:mmcPack options:NSJSONWritingPrettyPrinted error:error];
    if (!mmcPackData) {
        if (error && !*error) {
            *error = [NSError errorWithDomain:@"ModpackExportService" code:5
                                     userInfo:@{NSLocalizedDescriptionKey: localize(@"i18n_str_484", nil)}];
        }
        return NO;
    }

    // Build instance.cfg (key=value format).
    NSString *instanceName = name.length > 0 ? name : (profileName ?: @"Exported Modpack");
    NSMutableString *cfgContent = [NSMutableString string];
    [cfgContent appendFormat:@"InstanceType=OneSix\n"];
    [cfgContent appendFormat:@"name=%@\n", instanceName];
    [cfgContent appendFormat:@"%s=%@\n", "notes", [NSString stringWithFormat:@"Exported by Amethyst v%@", version.length > 0 ? version : @"1.0"]];
    [cfgContent appendFormat:@"%s=%@\n", "iconKey", "default"];
    [cfgContent appendFormat:@"%s=%@\n", "OverrideCommands", "false"];
    [cfgContent appendFormat:@"%s=%@\n", "OverrideConsole", "false"];
    [cfgContent appendFormat:@"%s=%@\n", "OverrideJava", "false"];
    [cfgContent appendFormat:@"%s=%@\n", "OverrideJavaArgs", "false"];
    [cfgContent appendFormat:@"%s=%@\n", "OverrideMCLauncher", "false"];
    [cfgContent appendFormat:@"%s=%@\n", "OverrideWindow", "false"];
    NSData *cfgData = [cfgContent dataUsingEncoding:NSUTF8StringEncoding];

    if ([self checkCancelledWithError:error]) return NO;

    progress(0.3, localize(@"i18n_str_1258", nil));
    [fm removeItemAtPath:destPath error:nil];

    NSError *archiveError = nil;
    UZKArchive *archive = [[UZKArchive alloc] initWithPath:destPath error:&archiveError];
    if (!archive || archiveError) {
        if (error) *error = archiveError;
        return NO;
    }

    progress(0.4, localize(@"i18n_str_1281", nil));
    if (![archive writeData:mmcPackData filePath:@"mmc-pack.json" error:&archiveError]) {
        if (error) *error = archiveError;
        return NO;
    }
    progress(0.45, localize(@"i18n_str_1282", nil));
    if (cfgData && ![archive writeData:cfgData filePath:@"instance.cfg" error:&archiveError]) {
        if (error) *error = archiveError;
        return NO;
    }

    // Write MMC overrides with the .minecraft/ prefix (standard MMC structure).
    if (![self writeOverridesToArchive:archive
                          gameDirAbsolute:gameDirAbsolute
                            fileOptions:fileOptions
                              zipPrefix:@".minecraft"
                          baseProgress:0.5
                          progressRange:0.4
                                progress:progress
                                  error:error]) {
        return NO;
    }

    progress(0.95, localize(@"i18n_str_1259", nil));
    archive = nil;

    progress(1.0, localize(@"i18n_str_1260", nil));
    NSLog(@"[ModpackExport] MMC format export completed: %@", destPath);
    return YES;
}

#pragma mark - Export Plain Zip format (HMCL compatible)

/// Plain Zip format: packs the .minecraft directory directly, without manifest/mmc-pack.json.
/// Suitable for PojavLauncher/HMCL interoperability: packs the gameDir contents under a .minecraft/ prefix.
- (BOOL)exportPlainZipFormat:(NSArray<NSDictionary *> *)modFiles
                      toPath:(NSString *)destPath
                         name:(NSString *)name
                      version:(NSString *)version
                       author:(NSString *)author
                     mcVersion:(NSString *)mcVersion
                        loader:(NSString *)loader
                  loaderVersion:(NSString *)loaderVersion
                  gameDirAbsolute:(NSString *)gameDirAbsolute
                    fileOptions:(ModpackExportFileOptions)fileOptions
                      progress:(void (^)(double, NSString *))progress
                         error:(NSError **)error {
    (void)name; (void)version; (void)author; (void)loader; (void)loaderVersion;
    if ([self checkCancelledWithError:error]) return NO;

    progress(0.2, localize(@"i18n_str_1258", nil));
    NSFileManager *fm = [NSFileManager defaultManager];
    [fm removeItemAtPath:destPath error:nil];

    NSError *archiveError = nil;
    UZKArchive *archive = [[UZKArchive alloc] initWithPath:destPath error:&archiveError];
    if (!archive || archiveError) {
        if (error) *error = archiveError;
        return NO;
    }

    // Write .minecraft/AMETHYST_INFO.txt metadata (optional; helps other launchers identify the source).
    NSString *infoContent = [NSString stringWithFormat:
        @"Amethyst Exported Modpack\n"
        @"Minecraft: %@\n"
        @"Loader: %@ %@\n"
        @"Export Time: %@\n",
        mcVersion,
        loader ?: @"vanilla",
        loaderVersion ?: @"",
        [[NSDate date] description]];
    NSData *infoData = [infoContent dataUsingEncoding:NSUTF8StringEncoding];
    if (infoData) {
        [archive writeData:infoData filePath:@".minecraft/AMETHYST_INFO.txt" error:nil];
    }

    // Write the .minecraft/<...> prefix.
    if (![self writeOverridesToArchive:archive
                          gameDirAbsolute:gameDirAbsolute
                            fileOptions:fileOptions
                              zipPrefix:@".minecraft"
                          baseProgress:0.3
                          progressRange:0.6
                                progress:progress
                                  error:error]) {
        return NO;
    }

    progress(0.95, localize(@"i18n_str_1259", nil));
    archive = nil;

    progress(1.0, localize(@"i18n_str_1260", nil));
    NSLog(@"[ModpackExport] Plain Zip format export completed: %@", destPath);
    return YES;
}

#pragma mark - Export link-list format (simple format supported by FCL)

- (BOOL)exportLinkListFormat:(NSArray<NSDictionary *> *)modFiles
                      toPath:(NSString *)destPath
                   mcVersion:(NSString *)mcVersion
                      loader:(NSString *)loader
              loaderVersion:(NSString *)loaderVersion
                        name:(NSString *)name
                     version:(NSString *)version
                       error:(NSError **)error {
    // FCL link-list format:
    // # Minecraft: <mcVersion>
    // # Loader: <loader>-<loaderVersion>
    // # Name: <name>
    // # Version: <version>
    // <path inside ZIP>|<download URL or local path>
    NSMutableString *content = [NSMutableString string];
    [content appendFormat:@"# Minecraft: %@\n", mcVersion];
    if (loader.length > 0 && loaderVersion.length > 0) {
        [content appendFormat:@"# Loader: %@-%@\n", loader, loaderVersion];
    }
    [content appendFormat:@"# Name: %@\n", name.length > 0 ? name : @"Exported Modpack"];
    [content appendFormat:@"# Version: %@\n", version.length > 0 ? version : @"1.0"];
    [content appendString:localize(@"i18n_str_487", nil)];

    for (NSDictionary *modFile in modFiles) {
        // Link-list format: mod path + empty download URL (users can fill it in manually).
        [content appendFormat:@"%@|\n", modFile[@"path"]];
    }

    NSError *writeError = nil;
    BOOL success = [content writeToFile:destPath atomically:YES encoding:NSUTF8StringEncoding error:&writeError];
    if (!success) {
        if (error) *error = writeError;
        return NO;
    }
    NSLog(@"[ModpackExport] Link list format export completed: %@", destPath);
    return YES;
}

#pragma mark - Write common overrides

/// Writes common overrides: fileOptions determines which directories/files are packaged.
- (BOOL)writeOverridesToArchive:(UZKArchive *)archive
               gameDirAbsolute:(NSString *)gameDirAbsolute
                     fileOptions:(ModpackExportFileOptions)fileOptions
                       zipPrefix:(NSString *)zipPrefix
                     baseProgress:(double)baseProgress
                   progressRange:(double)progressRange
                         progress:(void (^)(double, NSString *))progress
                            error:(NSError **)error {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSArray<NSString *> *overrideDirs = [ModpackExportService overrideDirectoriesForOptions:fileOptions];
    NSArray<NSString *> *overrideFiles = [ModpackExportService overrideFilesForOptions:fileOptions];

    NSUInteger totalItems = overrideDirs.count + overrideFiles.count;
    if (totalItems == 0) {
        progress(baseProgress + progressRange, localize(@"i18n_str_1264", nil));
        return YES;
    }

    __block NSUInteger processed = 0;
    __block NSError *blockError = nil;

    // Count files in each directory for accurate progress.
    NSUInteger totalFiles = 0;
    for (NSString *dir in overrideDirs) {
        NSString *dirPath = [gameDirAbsolute stringByAppendingPathComponent:dir];
        if (![fm fileExistsAtPath:dirPath]) continue;
        NSDirectoryEnumerator *e = [fm enumeratorAtPath:dirPath];
        NSString *rel;
        while ((rel = [e nextObject])) {
            NSString *full = [dirPath stringByAppendingPathComponent:rel];
            BOOL isDir = NO;
            if ([fm fileExistsAtPath:full isDirectory:&isDir] && !isDir) {
                totalFiles++;
            }
        }
    }
    totalFiles += overrideFiles.count;
    if (totalFiles == 0) {
        progress(baseProgress + progressRange, localize(@"i18n_str_1264", nil));
        return YES;
    }

    __block NSUInteger processedFiles = 0;

    // Package directory.
    for (NSString *dir in overrideDirs) {
        if ([self checkCancelledWithError:error]) return NO;
        NSString *dirPath = [gameDirAbsolute stringByAppendingPathComponent:dir];
        if (![fm fileExistsAtPath:dirPath]) {
            processed++;
            continue;
        }
        NSString *prefixInZip = [NSString stringWithFormat:@"%@/%@", zipPrefix, dir];
        [self addDirectoryToArchive:archive
                            dirPath:dirPath
                        prefixInZip:prefixInZip
                           progress:^(NSUInteger done, NSUInteger total) {
            processedFiles = done;
            double p = baseProgress + progressRange * ((double)processedFiles / (double)totalFiles);
            progress(p, [NSString stringWithFormat:localize(@"i18n_str_489", nil), zipPrefix, dir]);
        }];
        processed++;
    }

    // Package a single file.
    for (NSString *file in overrideFiles) {
        if ([self checkCancelledWithError:error]) return NO;
        NSString *filePath = [gameDirAbsolute stringByAppendingPathComponent:file];
        if ([fm fileExistsAtPath:filePath]) {
            NSData *data = [NSData dataWithContentsOfFile:filePath];
            if (data) {
                NSError *writeErr = nil;
                [archive writeData:data
                          filePath:[NSString stringWithFormat:@"%@/%@", zipPrefix, file]
                             error:&writeErr];
                if (writeErr) {
                    NSLog(@"[ModpackExport] Warning: failed to write %@/%@: %@", zipPrefix, file, writeErr.localizedDescription);
                }
            }
        }
        processedFiles++;
        double p = baseProgress + progressRange * ((double)processedFiles / (double)totalFiles);
        progress(p, [NSString stringWithFormat:localize(@"i18n_str_489", nil), zipPrefix, file]);
        processed++;
    }

    if (blockError) {
        if (error) *error = blockError;
        return NO;
    }
    return YES;
}

#pragma mark - Helper methods

- (void)addDirectoryToArchive:(UZKArchive *)archive
                      dirPath:(NSString *)dirPath
                  prefixInZip:(NSString *)prefixInZip
                     progress:(void (^_Nullable)(NSUInteger done, NSUInteger total))progress {
    NSFileManager *fileManager = [NSFileManager defaultManager];

    // Count the files first.
    NSUInteger total = 0;
    NSDirectoryEnumerator *counter = [fileManager enumeratorAtPath:dirPath];
    NSString *relPath;
    while ((relPath = [counter nextObject])) {
        NSString *fullPath = [dirPath stringByAppendingPathComponent:relPath];
        BOOL isDir = NO;
        if ([fileManager fileExistsAtPath:fullPath isDirectory:&isDir] && !isDir) {
            total++;
        }
    }
    if (total == 0) {
        if (progress) progress(0, 0);
        return;
    }

    NSDirectoryEnumerator *enumerator = [fileManager enumeratorAtPath:dirPath];
    NSUInteger done = 0;
    while ((relPath = [enumerator nextObject])) {
        // Cancellation checkpoint.
        @synchronized(self) {
            if (self.cancelled) {
                if (progress) progress(done, total);
                return;
            }
        }

        NSString *fullPath = [dirPath stringByAppendingPathComponent:relPath];
        BOOL isDir = NO;
        if (![fileManager fileExistsAtPath:fullPath isDirectory:&isDir] || isDir) continue;

        NSData *data = [NSData dataWithContentsOfFile:fullPath];
        if (!data) continue;

        NSString *zipPath = [NSString stringWithFormat:@"%@/%@", prefixInZip, relPath];
        [archive writeData:data filePath:zipPath error:nil];
        done++;
        if (progress) progress(done, total);
    }
}

- (nullable NSString *)resolveAbsoluteGameDirForProfile:(NSString *)profileName {
    NSString *profile = profileName.length ? profileName : @"default";
    @try {
        NSDictionary *prof = PLProfiles.current.profiles[profile];
        if (![prof isKindOfClass:[NSDictionary class]]) return nil;
        // ★ [VI-SWITCH-UI] Use the unified resolver (off = shared root; on = versions/<version id>; explicit custom gameDir still takes precedence).
        //   The old code constructed prof[@"gameDir"] directly; when isolation was enabled, that key was still ".", so export read the shared directory.
        return amePCLVersionGameDirAbsolute(prof, nil);
    } @catch (NSException *ex) {
        return nil;
    }
}

- (nullable NSString *)sha1ForFileAtPath:(NSString *)path {
    NSFileHandle *handle = [NSFileHandle fileHandleForReadingAtPath:path];
    if (!handle) return nil;

    CC_SHA1_CTX ctx;
    CC_SHA1_Init(&ctx);

    static const NSUInteger bufferSize = 64 * 1024;  // 64KB
    NSData *chunk;
    while ((chunk = [handle readDataOfLength:bufferSize]) && chunk.length > 0) {
        CC_SHA1_Update(&ctx, chunk.bytes, (CC_LONG)chunk.length);
    }
    [handle closeFile];

    unsigned char digest[CC_SHA1_DIGEST_LENGTH];
    CC_SHA1_Final(digest, &ctx);

    NSMutableString *hex = [NSMutableString stringWithCapacity:CC_SHA1_DIGEST_LENGTH * 2];
    for (size_t i = 0; i < CC_SHA1_DIGEST_LENGTH; i++) {
        [hex appendFormat:@"%02x", digest[i]];
    }
    return [hex copy];
}

- (nullable NSString *)sha512ForFileAtPath:(NSString *)path {
    NSFileHandle *handle = [NSFileHandle fileHandleForReadingAtPath:path];
    if (!handle) return nil;

    CC_SHA512_CTX ctx;
    CC_SHA512_Init(&ctx);

    static const NSUInteger bufferSize = 64 * 1024;  // 64KB
    NSData *chunk;
    while ((chunk = [handle readDataOfLength:bufferSize]) && chunk.length > 0) {
        CC_SHA512_Update(&ctx, chunk.bytes, (CC_LONG)chunk.length);
    }
    [handle closeFile];

    unsigned char digest[CC_SHA512_DIGEST_LENGTH];
    CC_SHA512_Final(digest, &ctx);

    NSMutableString *hex = [NSMutableString stringWithCapacity:CC_SHA512_DIGEST_LENGTH * 2];
    for (size_t i = 0; i < CC_SHA512_DIGEST_LENGTH; i++) {
        [hex appendFormat:@"%02x", digest[i]];
    }
    return [hex copy];
}

+ (NSDictionary *)parseVersionId:(NSString *)versionId {
    if (versionId.length == 0) return @{};

    // fabric-loader-<loaderVer>-<mcVer>
    if ([versionId hasPrefix:@"fabric-loader-"]) {
        NSString *rest = [versionId substringFromIndex:@"fabric-loader-".length];
        NSArray *parts = [rest componentsSeparatedByString:@"-"];
        if (parts.count >= 2) {
            NSString *loaderVersion = parts[0];
            NSString *mcVersion = [[parts subarrayWithRange:NSMakeRange(1, parts.count - 1)] componentsJoinedByString:@"-"];
            return @{@"loader": @"fabric", @"loaderVersion": loaderVersion, @"minecraft": mcVersion};
        }
    }

    // quilt-loader-<loaderVer>-<mcVer>
    if ([versionId hasPrefix:@"quilt-loader-"]) {
        NSString *rest = [versionId substringFromIndex:@"quilt-loader-".length];
        NSArray *parts = [rest componentsSeparatedByString:@"-"];
        if (parts.count >= 2) {
            NSString *loaderVersion = parts[0];
            NSString *mcVersion = [[parts subarrayWithRange:NSMakeRange(1, parts.count - 1)] componentsJoinedByString:@"-"];
            return @{@"loader": @"quilt", @"loaderVersion": loaderVersion, @"minecraft": mcVersion};
        }
    }

    // <mcVer>-forge-<loaderVer>
    NSRange forgeRange = [versionId rangeOfString:@"-forge-"];
    if (forgeRange.location != NSNotFound) {
        NSString *mcVersion = [versionId substringToIndex:forgeRange.location];
        NSString *loaderVersion = [versionId substringFromIndex:forgeRange.location + forgeRange.length];
        return @{@"loader": @"forge", @"loaderVersion": loaderVersion, @"minecraft": mcVersion};
    }

    // <mcVer>-neoforge-<loaderVer>
    NSRange neoforgeRange = [versionId rangeOfString:@"-neoforge-"];
    if (neoforgeRange.location != NSNotFound) {
        NSString *mcVersion = [versionId substringToIndex:neoforgeRange.location];
        NSString *loaderVersion = [versionId substringFromIndex:neoforgeRange.location + neoforgeRange.length];
        return @{@"loader": @"neoforge", @"loaderVersion": loaderVersion, @"minecraft": mcVersion};
    }

    // Vanilla Minecraft version (no loader).
    return @{@"minecraft": versionId};
}

@end
