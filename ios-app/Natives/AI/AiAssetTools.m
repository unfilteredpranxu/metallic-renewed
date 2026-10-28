//
//  AiAssetTools.m
//  Amethyst
//
//  Air AI Agent asset/network tool implementation (Phase 3b):
//  - AiAssetSearchTool: Modrinth search (search_mods / search_resourcepacks / search_shaders /
//    search_datapacks / search_modpacks / search_worlds）。
//  - AiAssetInstallTool: direct installation (fully automated in the style of HMCL AE):
//      install_mod / install_resourcepack / install_shader / install_datapack (Modrinth download + gameVersion matching);
//      install_game_version (directly installs the Minecraft base game with MinecraftResourceDownloadTask and six-stage download-center progress);
//      install_loader (direct Fabric/Quilt installation: automatically installs vanilla first + meta profile + Fabric API;
//                     Forge/NeoForge/OptiFine require a JVM graphical installer; retain download-page guidance).
//  Both tool groups share file-private helpers (AiAssetNetworkUtil / AiAssetInstaller).
//  - Network requests consistently use NSURLSession GET JSON (see AnnouncementService).
//  - File downloads consistently use PLDownloadClient and register with DownloadTaskManager for progress tracking.
//  - Traditional square-bracket syntax + ARC; always dispatch results to the main thread.
//
//  Second-round enhance-ai-agent improvements:
//  - Modrinth request chain: official → MCIM mirror (mod.mcimirror.top) → retry official; download file candidates
//    (official CDN → mod.mcimirror.top mirror) automatically switch on failure (PLDownloadClient candidateURLs).
//  - Version manifest chain: BMCLAPI by default → official fallback (independent of the general.download_source preference).
//  - latest aliases: install_loader's loaderVersion and asset installation's versionId both accept
//    "latest"/"latest-release", which automatically selects the latest stable version without fetching a version list first.
//  - install_mod detects Sodium and automatically installs Podium (or Podium Port); Iris adds a reminder to use the Zink renderer;
//    all installations include a reminder that dependencies may be missing and the user should test by launching the game.
//  - install_* supports the wait parameter (defaults to true): with wait=false, run in the background and immediately return task info,
//    so the AI can use check_downloads to query progress.
//

#import "AiAssetTools.h"
#import "PLProfiles.h"
#import "LauncherPreferences.h"
#import "ModService.h"
#import "ShaderService.h"
#import "ResourcePackService.h"
#import "DataPackService.h"
#import "PLDownloadClient.h"
#import "DownloadTaskManager.h"
#import "DownloadTaskItem.h"
#import "MinecraftResourceDownloadTask.h"
#import "PLTaskStages.h"
#import "AiSafetyManager.h"
#import "utils.h"   // ★ [VER-ISOLATE-PCL] Shared version-isolation resolution

/// Tool error domain and common error codes
static NSString * const kAiAssetToolDomain = @"AiAssetTool";

/// Parse the wait parameter (defaults to YES; "false"/"no"/"0"/JSON false → NO)
static BOOL aiWaitRequested(NSDictionary *params) {
    id v = params[@"wait"];
    if (v == nil) return YES;
    if ([v isKindOfClass:[NSNumber class]]) return [v boolValue];
    if ([v isKindOfClass:[NSString class]]) {
        NSString *s = [(NSString *)v lowercaseString];
        if ([s isEqualToString:@"false"] || [s isEqualToString:@"no"] || [s isEqualToString:@"0"]) return NO;
        return YES;
    }
    return YES;
}

/// Determine whether a string is a latest alias (latest / latest-release)
static BOOL aiIsLatestAlias(NSString *s) {
    return [s isEqualToString:@"latest"] || [s isEqualToString:@"latest-release"];
}

#pragma mark - File-private helpers: network and paths

/// General network / path / safe filename helper (file-private)
@interface AiAssetNetworkUtil : NSObject

/// GET JSON (object or array); always dispatch to the main thread
+ (void)getJSONFromURL:(NSURL *)url completion:(void (^)(id _Nullable json, NSError * _Nullable error))completion;

/// Modrinth API GET JSON (official → MCIM mirror → retry official):
/// apiPath is a v2 path starting with / (e.g. /search?... or /project/xxx/version).
/// completion returns json, the source actually used (Modrinth / Modrinth-MCIM mirror), and any error.
+ (void)getModrinthJSONWithPath:(NSString *)apiPath
                     completion:(void (^)(id _Nullable json, NSString * _Nullable usedSource, NSError * _Nullable error))completion;

/// Sanitize a filename (remove separators that could break the path)
+ (NSString *)safeFileName:(NSString *)rawName;

/// Resolve the target profile (instance parameter takes precedence; default to the currently selected profile)
+ (NSString *)resolveProfileName:(NSDictionary *)params;

/// Resolve the profile's absolute gameDir path (expand relative paths against POJAV_GAME_DIR)
+ (NSString *)resolveGameDirForProfile:(NSString *)profileName;

/// Check whether the vanilla game for the specified MC version is installed in an instance (gameDir)
+ (BOOL)isGameVersionInstalled:(NSString *)mcVersion inGameDir:(NSString *)gameDir;

/// Fetch the Mojang/BMCLAPI version manifest and return the manifest entry for the specified version (including id/url).
/// versionId supports latest-release / latest-snapshot / latest (alias for latest-release).
+ (void)fetchVersionEntry:(NSString *)versionId
               completion:(void (^)(NSDictionary * _Nullable entry, NSError * _Nullable error))completion;

/// Ensure versions/{versionId}/{versionId}.json exists (download from the manifest if missing, including BMCLAPI domain replacement)
+ (void)ensureVersionJSONExists:(NSString *)versionId
                     completion:(void (^)(BOOL success))completion;

/// Resolve the game version for the parameters: prefer params.gameVersion; otherwise use the instance profile's
/// lastVersionId and normalize it (strip fabric/forge/neoforge/quilt/optifine loader suffixes)
+ (NSString *)resolveGameVersionForParams:(NSDictionary *)params;

/// Post a ShowDownloadPage notification to the main thread (guide the user to the built-in download page)
+ (void)postShowDownloadPage;

@end

#pragma mark - File-private helpers: file downloads (PLDownloadClient + DownloadTaskManager)

@interface AiAssetInstaller : NSObject

/// Download a file to the target directory, register DownloadTask progress, and invoke completion on the main thread
+ (void)downloadFileFromURL:(NSURL *)url
                   filename:(NSString *)filename
                     folder:(NSString *)folder
                displayName:(NSString *)displayName
               resourceType:(NSString *)resourceType
                expectedSHA1:(nullable NSString *)expectedSHA1
                 completion:(void (^)(NSString * _Nullable result, NSError * _Nullable error))completion;

/// Download a file to the target directory (enhanced):
/// - Download candidates include the MCIM mirror (cdn.modrinth.com → mod.mcimirror.top), with automatic switching on failure.
/// - When waitForCompletion=NO, register the task and immediately report "Added to background downloads"; continue downloading in the background,
///   and invoke only onFinished at the terminal state (may be nil).
/// - When waitForCompletion=YES, behave as before (invoke completion at the terminal state); onFinished is also invoked.
+ (void)downloadFileFromURL:(NSURL *)url
                   filename:(NSString *)filename
                     folder:(NSString *)folder
                displayName:(NSString *)displayName
               resourceType:(NSString *)resourceType
                expectedSHA1:(nullable NSString *)expectedSHA1
          waitForCompletion:(BOOL)waitForCompletion
                 completion:(void (^)(NSString * _Nullable result, NSError * _Nullable error))completion
                 onFinished:(nullable void (^)(BOOL success, NSString * _Nullable message))onFinished;

/// Directly install the vanilla MC game (version JSON + libraries + assets):
/// 1) Fetch the version manifest entry and ensure the version JSON is saved.
/// 2) MinecraftResourceDownloadTask downloadVersion: performs the complete download — it automatically registers with
///    DownloadTaskManager (six stages + autoPresentDetail), showing live progress in the download center/unified progress page.
/// 3) Poll progress.finished (maximum 30 minutes, consistent with ensureVanillaInstalled).
/// 4) On success, create and select the corresponding instance profile, then post ReloadProfileList to refresh the version list.
+ (void)installVanillaVersionId:(NSString *)versionId
                     completion:(void (^)(BOOL success, NSString * _Nullable message))completion;

@end

@implementation AiAssetSearchTool {
    NSString *_internalName;
}

- (instancetype)initWithName:(NSString *)name {
    self = [super init];
    if (self) {
        _internalName = name ?: @"";
    }
    return self;
}

- (NSString *)name {
    return _internalName;
}

- (AiToolPermission)permission {
    return AiToolPermissionExternalNetwork;
}

- (NSString *)summary {
    if ([_internalName isEqualToString:@"search_resourcepacks"]) {
        return @"Search Modrinth for resource packs."
               "\nParameter: query (string, required, search keywords)."
               "\nReturns up to 8 results as a JSON array [{slug,title,description,downloads,project_id}]; displays \"No matching projects found\" if there are no results.";
    }
    if ([_internalName isEqualToString:@"search_shaders"]) {
        return @"Search Modrinth for shader packs."
               "\nParameter: query (string, required, search keywords)."
               "\nReturns up to 8 results as a JSON array [{slug,title,description,downloads,project_id}]; displays \"No matching projects found\" if there are no results.";
    }
    if ([_internalName isEqualToString:@"search_datapacks"]) {
        return @"Search Modrinth for data packs."
               "\nParameter: query (string, required, search keywords)."
               "\nReturns up to 8 results as a JSON array [{slug,title,description,downloads,project_id}]; displays \"No matching projects found\" if there are no results.";
    }
    if ([_internalName isEqualToString:@"search_modpacks"]) {
        return @"Search Modrinth for modpacks."
               "\nParameter: query (string, required, search keywords)."
               "\nReturns up to 8 results as a JSON array [{slug,title,description,downloads,project_id}]; displays \"No matching projects found\" if there are no results.";
    }
    if ([_internalName isEqualToString:@"search_worlds"]) {
        return @"Search Modrinth for worlds."
               "\nParameter: query (string, required, search keywords)."
               "\nReturns up to 8 results as a JSON array [{slug,title,description,downloads,project_id}]; displays \"No matching projects found\" if there are no results.";
    }
    // search_mods
    return @"Search Modrinth for mods."
           "\nParameters: query (string, required, search keywords), facets (string, optional, mod/resourcepack/shaderpack/datapack/world/modpack; defaults to mod)."
           "\nReturns up to 8 results as a JSON array [{slug,title,description,downloads,project_id}]; displays \"No matching projects found\" if there are no results.";
}

#pragma mark - Execute

- (void)execute:(NSDictionary<NSString *, id> *)params
     completion:(void (^)(NSString * _Nullable result, NSError * _Nullable error))completion {
    if (!completion) return;

    // Facet type mapping (fixed or based on the facets parameter)
    NSString *type = [self fixedType];
    NSString *query = [params[@"query"] isKindOfClass:[NSString class]] ? params[@"query"] : @"";
    if (query.length == 0) {
        NSError *err = [NSError errorWithDomain:kAiAssetToolDomain code:400
                                        userInfo:@{NSLocalizedDescriptionKey: @"Required parameter query (search keywords) is missing"}];
        completion(nil, err);
        return;
    }
    // search_mods allows facets override; facets are fixed for other tools
    if ([_internalName isEqualToString:@"search_mods"]) {
        NSString *f = [params[@"facets"] isKindOfClass:[NSString class]] ? params[@"facets"] : @"";
        if (f.length > 0) type = f;
    }

    NSString *encQuery = [query stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]];
    NSString *facetsJSON = [NSString stringWithFormat:@"[[[\"project_type:%@\"]]]", type ?: @"mod"];
    NSString *encFacets = [facetsJSON stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]];
    NSString *apiPath = [NSString stringWithFormat:@"/search?query=%@&facets=%@&limit=8", encQuery, encFacets];

    // Modrinth official → MCIM mirror → retry official (source switching is handled internally by the helper)
    [AiAssetNetworkUtil getModrinthJSONWithPath:apiPath completion:^(id _Nullable json, NSString * _Nullable usedSource, NSError * _Nullable error) {
        if (error) {
            completion(nil, error);
            return;
        }
        NSArray *hits = nil;
        if ([json isKindOfClass:[NSDictionary class]]) {
            hits = json[@"hits"];
        } else if ([json isKindOfClass:[NSArray class]]) {
            hits = json;
        }
        if (![hits isKindOfClass:[NSArray class]] || hits.count == 0) {
            completion(@"No matching projects found", nil);
            return;
        }
        NSMutableArray *items = [NSMutableArray array];
        for (id hit in hits) {
            if (![hit isKindOfClass:[NSDictionary class]] || items.count >= 8) continue;
            NSString *title = hit[@"title"];
            NSString *desc = hit[@"description"];
            if (![desc isKindOfClass:[NSString class]]) desc = @"";
            // Truncate descriptions to 120 characters
            if (desc.length > 120) desc = [NSString stringWithFormat:@"%@…", [desc substringToIndex:120]];
            NSString *slug = hit[@"slug"];
            NSString *pid = hit[@"project_id"];
            NSNumber *downloads = hit[@"downloads"];
            if (![slug isKindOfClass:[NSString class]]) slug = @"";
            [items addObject:@{
                @"slug": slug,
                @"title": [title isKindOfClass:[NSString class]] ? title : @"",
                @"description": desc,
                @"downloads": ([downloads isKindOfClass:[NSNumber class]] ? downloads : @0),
                @"project_id": [pid isKindOfClass:[NSString class]] ? pid : @"",
            }];
        }
        if (items.count == 0) {
            completion(@"No matching projects found", nil);
            return;
        }
        NSData *data = [NSJSONSerialization dataWithJSONObject:items options:0 error:nil];
        NSString *jsonStr = data ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : @"[]";
        completion([NSString stringWithFormat:@"%@\n(Data source: %@)", jsonStr, usedSource ?: @"Modrinth"], nil);
    }];
}

/// Fixed project_type for the tool (search_mods defaults to mod)
- (NSString *)fixedType {
    if ([_internalName isEqualToString:@"search_resourcepacks"]) return @"resourcepack";
    if ([_internalName isEqualToString:@"search_shaders"]) return @"shaderpack";
    if ([_internalName isEqualToString:@"search_datapacks"]) return @"datapack";
    if ([_internalName isEqualToString:@"search_modpacks"]) return @"modpack";
    if ([_internalName isEqualToString:@"search_worlds"]) return @"world";
    return @"mod";
}

@end

#pragma mark - AiAssetInstallTool

@implementation AiAssetInstallTool {
    NSString *_internalName;
}

- (instancetype)initWithName:(NSString *)name {
    self = [super init];
    if (self) {
        _internalName = name ?: @"";
    }
    return self;
}

- (NSString *)name {
    return _internalName;
}

- (AiToolPermission)permission {
    return AiToolPermissionControlledWrite;
}

- (NSString *)summary {
    if ([_internalName isEqualToString:@"install_resourcepack"]) {
        return @"Download and install a resource pack from Modrinth into the resource pack directory, fully automatically with progress shown in the download center."
               "\nParameters: slugOrId (string, required, Modrinth project slug or id), versionId (string, optional, use \"latest\" for the latest version), gameVersion (string, optional, filter by MC version), instance (string, optional, instance name), wait (boolean, optional, defaults to true; false returns immediately while downloading in the background; use check_downloads to check progress)."
               "\nDetails: Modrinth is the default source; on failure, automatically switch to the MCIM mirror and then fall back to the official source. Create the directory automatically if missing. Returns an installation result.";
    }
    if ([_internalName isEqualToString:@"install_shader"]) {
        return @"Download and install a shader pack from Modrinth into the shader directory, fully automatically with progress shown in the download center."
               "\nParameters: slugOrId (string, required, Modrinth project slug or id), versionId (string, optional, use \"latest\" for the latest version), gameVersion (string, optional, filter by MC version), instance (string, optional, instance name), wait (boolean, optional, defaults to true; false returns immediately while downloading in the background; use check_downloads to check progress)."
               "\nDetails: Modrinth is the default source; on failure, automatically switch to the MCIM mirror and then fall back to the official source. If installing Iris shaders, recommend switching the renderer to Zink. Returns an installation result.";
    }
    if ([_internalName isEqualToString:@"install_datapack"]) {
        return @"Download and install a data pack from Modrinth into the data pack directory, fully automatically with progress shown in the download center."
               "\nParameters: slugOrId (string, required, Modrinth project slug or id), versionId (string, optional, use \"latest\" for the latest version), gameVersion (string, optional, filter by MC version), instance (string, optional, instance name), wait (boolean, optional, defaults to true; false returns immediately while downloading in the background; use check_downloads to check progress)."
               "\nDetails: Modrinth is the default source; on failure, automatically switch to the MCIM mirror and then fall back to the official source. Returns an installation result.";
    }
    if ([_internalName isEqualToString:@"install_game_version"]) {
        return @"Directly download and install the specified vanilla Minecraft game (version JSON + libraries + assets), fully automatically with live progress in the download center and no user action required."
               "\nParameters: versionId (string, required, e.g. 1.20.1; also supports latest-release / latest-snapshot / latest), wait (boolean, optional, defaults to true; false returns immediately while installing in the background; use check_downloads to check progress)."
               "\nDetails: fetches the version manifest from the BMCLAPI mirror by default and automatically switches to the official source on failure. After installation, automatically create and select the corresponding instance. Returns an installation result.";
    }
    if ([_internalName isEqualToString:@"install_loader"]) {
        return @"Directly install a Mod loader (fully automated, with progress shown in the download center)."
               "\nParameters: mcVersion (string, required, target MC version), loaderType (string, required, fabric/forge/neoforge/quilt/optifine), loaderVersion (string, optional, use \"latest\" for the latest stable version; no need to fetch a version list first), instance (string, optional, instance name), wait (boolean, optional, defaults to true; false returns immediately while installing in the background; use check_downloads to check progress)."
               "\nBehavior: Fabric/Quilt are installed directly — if the vanilla game is missing, install it first, then save the loader version JSON and register the instance; Fabric also automatically installs Fabric API; "
               "Forge/NeoForge/OptiFine installers require running a Java graphical installer/processor and cannot yet be fully automated, so the built-in download page will open to guide the user.";
    }
    // install_mod
    return @"Download and install a Mod from Modrinth into the mods directory, fully automatically with progress shown in the download center."
           "\nParameters: slugOrId (string, required, Modrinth project slug or id), versionId (string, optional, use \"latest\" for the latest version; no need to fetch a version list first), gameVersion (string, optional, filter by MC version; defaults to the instance's current MC version), instance (string, optional, instance name), wait (boolean, optional, defaults to true; false returns immediately while downloading in the background; use check_downloads to check progress)."
           "\nDetails: Modrinth is the default source; on failure, automatically switch to the MCIM mirror and then fall back to the official source. When installing Sodium, also install Podium (or Podium Port) automatically. Returns an installation result.";
}

#pragma mark - Execute

- (void)execute:(NSDictionary<NSString *, id> *)params
     completion:(void (^)(NSString * _Nullable result, NSError * _Nullable error))completion {
    if (!completion) return;

    if ([_internalName isEqualToString:@"install_game_version"]) {
        [self performInstallGameVersion:params completion:completion];
        return;
    }
    if ([_internalName isEqualToString:@"install_loader"]) {
        [self performInstallLoader:params completion:completion];
        return;
    }
    [self performResourceInstall:params completion:completion];
}

#pragma mark - Asset installation (mod / resourcepack / shader / datapack)

/// Resolve target directory: return the corresponding Service ensure directory based on tool name
- (nullable NSString *)resolvedFolderForParams:(NSDictionary *)params {
    NSString *profile = [AiAssetNetworkUtil resolveProfileName:params];
    NSError *err = nil;
    if ([_internalName isEqualToString:@"install_mod"]) {
        return [[ModService sharedService] ensureModsFolderForProfile:profile error:&err];
    }
    if ([_internalName isEqualToString:@"install_resourcepack"]) {
        return [[ResourcePackService sharedService] ensureResourcePacksFolderForProfile:profile error:&err];
    }
    if ([_internalName isEqualToString:@"install_shader"]) {
        return [[ShaderService sharedService] ensureShadersFolderForProfile:profile error:&err];
    }
    if ([_internalName isEqualToString:@"install_datapack"]) {
        return [[DataPackService sharedService] ensureDataPacksFolderForProfile:profile error:&err];
    }
    return nil;
}

/// Asset type corresponding to the Install tool (used when registering DownloadTask)
- (NSString *)resourceTypeForTool {
    if ([_internalName isEqualToString:@"install_mod"]) return DownloadTaskResourceTypeMod;
    if ([_internalName isEqualToString:@"install_resourcepack"]) return DownloadTaskResourceTypeResourcePack;
    if ([_internalName isEqualToString:@"install_shader"]) return DownloadTaskResourceTypeShader;
    if ([_internalName isEqualToString:@"install_datapack"]) return DownloadTaskResourceTypeDataPack;
    return DownloadTaskResourceTypeMod;
}

- (void)performResourceInstall:(NSDictionary *)params
                    completion:(void (^)(NSString * _Nullable result, NSError * _Nullable error))completion {
    NSString *slugOrId = [params[@"slugOrId"] isKindOfClass:[NSString class]] ? params[@"slugOrId"] : @"";
    if (slugOrId.length == 0) {
        completion(nil, [NSError errorWithDomain:kAiAssetToolDomain code:400
                                        userInfo:@{NSLocalizedDescriptionKey: @"Required parameter slugOrId is missing"}]);
        return;
    }

    // Target directory
    NSString *folder = [self resolvedFolderForParams:params];
    if (folder.length == 0) {
        completion(nil, [NSError errorWithDomain:kAiAssetToolDomain code:500 userInfo:@{NSLocalizedDescriptionKey: @"Could not determine installation directory"}]);
        return;
    }
    // latest alias: equivalent to no version specified (automatically select the latest release)
    NSString *versionId = [params[@"versionId"] isKindOfClass:[NSString class]] ? params[@"versionId"] : @"";
    if (aiIsLatestAlias(versionId)) versionId = @"";
    // Version matching (key to HMCL AE-style automation): install_mod filters automatically by the instance MC version,
    // other asset types filter only when gameVersion is explicitly provided
    NSString *gameVersion = [params[@"gameVersion"] isKindOfClass:[NSString class]] ? params[@"gameVersion"] : @"";
    if (gameVersion.length == 0 && [_internalName isEqualToString:@"install_mod"]) {
        gameVersion = [AiAssetNetworkUtil resolveGameVersionForParams:params];
    }

    NSString *encSlug = [slugOrId stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]];
    // 1. Project info (use project name as displayName; official → MCIM → official fallback)
    NSString *projectPath = [NSString stringWithFormat:@"/project/%@", encSlug];
    [AiAssetNetworkUtil getModrinthJSONWithPath:projectPath completion:^(id _Nullable projectJSON, NSString * _Nullable projectSource, NSError * _Nullable projectError) {
        if (projectError) {
            completion(nil, projectError);
            return;
        }
        NSString *projectTitle = @"";
        if ([projectJSON isKindOfClass:[NSDictionary class]] && [projectJSON[@"title"] isKindOfClass:[NSString class]]) {
            projectTitle = projectJSON[@"title"];
        }
        [self fetchVersionsForSlug:encSlug versionId:versionId gameVersion:gameVersion completion:^(NSString * _Nullable filename, NSURL * _Nullable fileURL, NSString * _Nullable sha1, NSError * _Nullable verError) {
            if (verError) {
                completion(nil, verError);
                return;
            }
            NSString *displayName = projectTitle.length > 0 ? projectTitle : filename;
            NSString *safeFile = [AiAssetNetworkUtil safeFileName:filename];

            // Install Podium/Podium Port with Sodium (suppresses Sodium's launcher detection; otherwise the game crashes)
            BOOL isModInstall = [_internalName isEqualToString:@"install_mod"];
            NSString *lowerIdent = [NSString stringWithFormat:@"%@ %@", slugOrId, projectTitle].lowercaseString;
            BOOL needsPodium = isModInstall && ([lowerIdent rangeOfString:@"sodium"].location != NSNotFound);
            // Iris reminder (recommend switching renderer to Zink)
            BOOL isIris = [lowerIdent rangeOfString:@"iris"].location != NSNotFound;

            BOOL wait = aiWaitRequested(params);

            // Assemble final completion message (dependency reminder + Iris reminder + Podium installation details)
            void (^finishWithNote)(NSString * _Nullable, NSString * _Nullable podiumNote) = ^(NSString * _Nullable result, NSString * _Nullable podiumNote) {
                NSMutableString *final = [NSMutableString stringWithString:result ?: @""];
                if (podiumNote.length > 0) [final appendFormat:@"。%@", podiumNote];
                [final appendString:@". Note: dependencies (required Mods) may not yet be installed; launch Minecraft to test first. If it crashes, I can read the logs (read_logs), which will show the missing dependencies so I can install them for you."];
                if (isIris) {
                    [final appendString:@" Reminder: to run Iris shaders, switch the renderer to Zink (use set_setting to change it)."];
                }
                completion(final, nil);
            };

            if (wait) {
                [AiAssetInstaller downloadFileFromURL:fileURL
                                             filename:safeFile
                                               folder:folder
                                          displayName:displayName
                                         resourceType:[self resourceTypeForTool]
                                          expectedSHA1:sha1
                                    waitForCompletion:YES
                                           completion:^(NSString * _Nullable result, NSError * _Nullable error) {
                    if (error) {
                        completion(nil, error);
                        return;
                    }
                    if (needsPodium) {
                        // Sodium: install Podium (or Podium Port) as well, then return the final message
                        [self installPodiumCompanionForGameVersion:(gameVersion.length > 0 ? gameVersion : @"")
                                                            profile:[AiAssetNetworkUtil resolveProfileName:params]
                                                         completion:^(BOOL podOK, NSString * _Nullable podName, NSString * _Nullable podMsg) {
                            NSString *note = podOK
                                ? [NSString stringWithFormat:@"Automatically installed %@ as well (it suppresses Sodium's launcher detection; the game will crash without it)", podName ?: @"Podium"]
                                : @"Note: Sodium requires Podium or Podium Port (to suppress launcher detection; otherwise the game will crash). Automatic installation also failed; ask me to retry or install it manually.";
                            finishWithNote(result, note);
                        }];
                    } else {
                        finishWithNote(result, nil);
                    }
                }
                                          onFinished:nil];
            } else {
                // Run in the background: return immediately after registering the task; download continues and Podium is installed afterward (no AI callback)
                [AiAssetInstaller downloadFileFromURL:fileURL
                                             filename:safeFile
                                               folder:folder
                                          displayName:displayName
                                         resourceType:[self resourceTypeForTool]
                                          expectedSHA1:sha1
                                    waitForCompletion:NO
                                           completion:^(NSString * _Nullable bgResult, NSError * _Nullable bgError) {
                    if (bgError) {
                        completion(nil, bgError);
                        return;
                    }
                    NSMutableString *final = [NSMutableString stringWithString:bgResult ?: @""];
                    if (needsPodium) {
                        [final appendString:@". Podium (or Podium Port) will also be installed automatically after the download completes"];
                    }
                    [final appendString:@". The task is running in the background; use check_downloads to check progress."];
                    completion(final, nil);
                }
                                          onFinished:^(BOOL success, NSString * _Nullable message) {
                    // Background download terminal state: if successful and this is Sodium, also install Podium in the background (do not callback the AI)
                    if (!success || !needsPodium) return;
                    [self installPodiumCompanionForGameVersion:(gameVersion.length > 0 ? gameVersion : @"")
                                                        profile:[AiAssetNetworkUtil resolveProfileName:params]
                                                     completion:^(BOOL podOK, NSString * _Nullable podName, NSString * _Nullable podMsg) {
                        if (!podOK) {
                            NSLog(@"[AI] Failed to install Podium with Sodium: %@", podMsg ?: @"");
                        }
                    }];
                }];
            }
        }];
    }];
}

/// Install Podium with Sodium: try Podium / Podium Port in order (match version by gameVersion and install to the mods directory)
- (void)installPodiumCompanionForGameVersion:(NSString *)gameVersion
                                      profile:(NSString *)profile
                                   completion:(void (^)(BOOL success, NSString * _Nullable installedName, NSString * _Nullable message))completion {
    NSArray *candidateSlugs = @[@"podium", @"podium-port"];
    __weak typeof(self) weakSelf = self;

    void (^tryAtIndex)(NSUInteger) = ^(NSUInteger idx) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        if (idx >= candidateSlugs.count) {
            completion(NO, nil, @"Neither Podium nor Podium Port could be installed (Modrinth found no compatible version)");
            return;
        }
        NSString *slug = candidateSlugs[idx];
        NSError *err = nil;
        NSString *modsFolder = [[ModService sharedService] ensureModsFolderForProfile:profile error:&err];
        if (modsFolder.length == 0) {
            completion(NO, nil, @"Could not determine mods directory");
            return;
        }
        [strongSelf fetchVersionsForSlug:slug
                                versionId:@""
                              gameVersion:gameVersion
                               completion:^(NSString * _Nullable filename, NSURL * _Nullable fileURL, NSString * _Nullable sha1, NSError * _Nullable verError) {
            if (verError || !fileURL) {
                // Current slug is incompatible → try the next (e.g. only a specific version has a Port)
                tryAtIndex(idx + 1);
                return;
            }
            NSString *safeFile = [AiAssetNetworkUtil safeFileName:filename];
            [AiAssetInstaller downloadFileFromURL:fileURL
                                         filename:safeFile
                                           folder:modsFolder
                                      displayName:[slug isEqualToString:@"podium"] ? @"Podium" : @"Podium Port"
                                     resourceType:DownloadTaskResourceTypeMod
                                      expectedSHA1:sha1
                                waitForCompletion:YES
                                       completion:^(NSString * _Nullable result, NSError * _Nullable error) {
                if (error) {
                    tryAtIndex(idx + 1);
                    return;
                }
                completion(YES, [slug isEqualToString:@"podium"] ? @"Podium" : @"Podium Port", nil);
            }
                                       onFinished:nil];
        }];
    };
    tryAtIndex(0);
}

/// Fetch the project version list and select the target version file:
/// - If versionId is non-empty: match that version id exactly.
/// - If gameVersion is non-empty: select only versions whose game_versions include that MC version (error if none match).
/// - Otherwise, select the latest release.
- (void)fetchVersionsForSlug:(NSString *)encSlug
                   versionId:(NSString *)versionId
                 gameVersion:(NSString *)gameVersion
                  completion:(void (^)(NSString * _Nullable filename, NSURL * _Nullable fileURL, NSString * _Nullable sha1, NSError * _Nullable error))completion {
    // featured=true omits many compatible versions marked as non-featured when filtering by gameVersion,
    // so fetch the full version list and filter locally (official → MCIM → official fallback)
    NSString *apiPath = [NSString stringWithFormat:@"/project/%@/version", encSlug];
    [AiAssetNetworkUtil getModrinthJSONWithPath:apiPath completion:^(id _Nullable json, NSString * _Nullable usedSource, NSError * _Nullable error) {
        if (error) {
            completion(nil, nil, nil, error);
            return;
        }
        NSArray *versions = [json isKindOfClass:[NSArray class]] ? json : nil;
        if (versions.count == 0) {
            completion(nil, nil, nil, [NSError errorWithDomain:kAiAssetToolDomain code:404 userInfo:@{NSLocalizedDescriptionKey: @"This project has no available versions"}]);
            return;
        }
        // gameVersion compatibility filtering (the game_versions array in the Modrinth version object)
        if (gameVersion.length > 0) {
            NSMutableArray *filtered = [NSMutableArray array];
            for (id v in versions) {
                if (![v isKindOfClass:[NSDictionary class]]) continue;
                NSArray *gvs = v[@"game_versions"];
                if ([gvs isKindOfClass:[NSArray class]] && [gvs containsObject:gameVersion]) {
                    [filtered addObject:v];
                }
            }
            if (filtered.count == 0) {
                completion(nil, nil, nil, [NSError errorWithDomain:kAiAssetToolDomain code:404
                                                        userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"No version compatible with MC %@ found; retry with a versionId to specify a version", gameVersion]}]);
                return;
            }
            versions = filtered;
        }
        // Select version
        NSDictionary *chosen = nil;
        if (versionId.length > 0) {
            for (id v in versions) {
                if ([v isKindOfClass:[NSDictionary class]] && [v[@"id"] isEqualToString:versionId]) { chosen = v; break; }
            }
            if (!chosen) {
                completion(nil, nil, nil, [NSError errorWithDomain:kAiAssetToolDomain code:404
                                                           userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Version %@ not found", versionId]}]);
                return;
            }
        } else {
            // Prefer release / latest, fall back to the first
            for (id v in versions) {
                if (![v isKindOfClass:[NSDictionary class]]) continue;
                id vt = v[@"version_type"];
                if ([vt isKindOfClass:[NSString class]] && [vt isEqualToString:@"release"]) { chosen = v; break; }
            }
            if (!chosen) chosen = [versions firstObject];
        }
        NSArray *files = [chosen isKindOfClass:[NSDictionary class]] ? chosen[@"files"] : nil;
        NSDictionary *file = ([files isKindOfClass:[NSArray class]] && files.count > 0) ? files[0] : nil;
        if (![file isKindOfClass:[NSDictionary class]]) {
            completion(nil, nil, nil, [NSError errorWithDomain:kAiAssetToolDomain code:404 userInfo:@{NSLocalizedDescriptionKey: @"The selected version has no available files"}]);
            return;
        }
        NSString *fileURLStr = file[@"url"];
        NSString *filename = file[@"filename"];
        NSString *sha1 = nil;
        NSDictionary *hashes = file[@"hashes"];
        if ([hashes isKindOfClass:[NSDictionary class]] && [hashes[@"sha1"] isKindOfClass:[NSString class]]) {
            sha1 = hashes[@"sha1"];
        }
        NSURL *fileURL = [NSURL URLWithString:[fileURLStr isKindOfClass:[NSString class]] ? fileURLStr : @""];
        if (![filename isKindOfClass:[NSString class]]) filename = @"download";
        if (!fileURL) {
            completion(nil, nil, nil, [NSError errorWithDomain:kAiAssetToolDomain code:404 userInfo:@{NSLocalizedDescriptionKey: @"Invalid download URL"}]);
            return;
        }
        completion(filename, fileURL, sha1, nil);
    }];
}

#pragma mark - install_game_version (fully automated direct installation in the style of HMCL AE)

- (void)performInstallGameVersion:(NSDictionary *)params
                       completion:(void (^)(NSString * _Nullable result, NSError * _Nullable error))completion {
    NSString *versionId = [params[@"versionId"] isKindOfClass:[NSString class]] ? params[@"versionId"] : @"";
    if (versionId.length == 0) {
        completion(nil, [NSError errorWithDomain:kAiAssetToolDomain code:400
                                        userInfo:@{NSLocalizedDescriptionKey: @"Required parameter versionId is missing"}]);
        return;
    }

    // wait=false: install in the background and return immediately (no result callback; use check_downloads to query progress)
    if (!aiWaitRequested(params)) {
        completion([NSString stringWithFormat:@"Started installing MC %@ in the background (version JSON, libraries, and assets). The task is registered in the download center; use check_downloads anytime to see progress. The corresponding instance will be created and selected automatically after installation.", versionId], nil);
        [AiAssetInstaller installVanillaVersionId:versionId completion:^(BOOL bgSuccess, NSString * _Nullable bgMessage) {
            if (!bgSuccess) {
                NSLog(@"[AI] Background installation of MC %@ failed: %@", versionId, bgMessage ?: @"");
            }
        }];
        return;
    }

    // Install directly: MinecraftResourceDownloadTask automatically registers progress in the download center (six stages + autoPresentDetail),
    // where the user can monitor it live; there is no need to open the download page and guide manual operation.
    [AiAssetInstaller installVanillaVersionId:versionId completion:^(BOOL success, NSString * _Nullable message) {
        if (success) {
            completion([NSString stringWithFormat:@"MC %@ has been installed (version JSON, libraries, and assets are ready), and the corresponding instance has been created and selected.", versionId], nil);
        } else {
            completion(nil, [NSError errorWithDomain:kAiAssetToolDomain code:500
                                            userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Failed to install MC %@: %@", versionId, message ?: @"Unknown error"]}]);
        }
    }];
}

#pragma mark - install_loader (direct Fabric/Quilt installation; guide Forge/NeoForge/OptiFine to the download page)

- (void)performInstallLoader:(NSDictionary *)params
                  completion:(void (^)(NSString * _Nullable result, NSError * _Nullable error))completion {
    NSString *mcVersion = [params[@"mcVersion"] isKindOfClass:[NSString class]] ? params[@"mcVersion"] : @"";
    NSString *loaderType = [params[@"loaderType"] isKindOfClass:[NSString class]] ? [params[@"loaderType"] lowercaseString] : @"";
    if (mcVersion.length == 0) {
        completion(nil, [NSError errorWithDomain:kAiAssetToolDomain code:400 userInfo:@{NSLocalizedDescriptionKey: @"Required parameter mcVersion is missing"}]);
        return;
    }
    NSSet *validLoaders = [NSSet setWithObjects:@"fabric", @"forge", @"neoforge", @"quilt", @"optifine", nil];
    if (![validLoaders containsObject:loaderType]) {
        completion(nil, [NSError errorWithDomain:kAiAssetToolDomain code:400
                                        userInfo:@{NSLocalizedDescriptionKey: @"loaderType must be one of fabric / forge / neoforge / quilt / optifine"}]);
        return;
    }

    // Fabric/Quilt: install directly via meta API (profile JSON + version registration + Fabric API); show progress in the download center throughout
    if ([loaderType isEqualToString:@"fabric"] || [loaderType isEqualToString:@"quilt"]) {
        [self performFabricLikeLoaderInstall:params mcVersion:mcVersion loaderType:loaderType completion:completion];
        return;
    }

    // Forge/NeoForge/OptiFine: installers require running a Java graphical installer/processor (the in-process JVM can only be created once),
    // so fully automated installation is not safe; retain download-page guidance
    NSString *profile = [AiAssetNetworkUtil resolveProfileName:params];
    NSString *gameDir = [AiAssetNetworkUtil resolveGameDirForProfile:profile];
    BOOL installed = [AiAssetNetworkUtil isGameVersionInstalled:mcVersion inGameDir:gameDir];

    [AiAssetNetworkUtil postShowDownloadPage];
    if (!installed) {
        completion([NSString stringWithFormat:@"%@ installer requires a Java graphical installer and cannot yet be fully automated. MC %@ is not installed either; the download page has been opened. Install MC first, then install %@ on that page.", [loaderType capitalizedString], mcVersion, loaderType], nil);
    } else {
        completion([NSString stringWithFormat:@"%@ installer requires a Java graphical installer and cannot yet be fully automated. MC %@ is ready; the download page has been opened. Install the %@ loader on that page.", [loaderType capitalizedString], mcVersion, loaderType], nil);
    }
}

/// Directly install Fabric/Quilt (see DownloadViewController installFabricLikeLoader; no UI dependency):
/// 1) If the vanilla game is missing → install it directly first (installVanillaVersionId).
/// 2) Resolve loader version (latest stable by default) → fetch meta profile JSON.
/// 3) Register installation task (Modloader + three Fabric stages + autoPresentDetail) → write versions/{id}/{id}.json.
/// 4) Register and select instance profile; post ReloadProfileList.
/// 5) For Fabric (not Quilt), automatically install Fabric API to the mods directory (separate Mod download task).
- (void)performFabricLikeLoaderInstall:(NSDictionary *)params
                             mcVersion:(NSString *)mcVersion
                            loaderType:(NSString *)loaderType
                            completion:(void (^)(NSString * _Nullable result, NSError * _Nullable error))completion {
    BOOL isQuilt = [loaderType isEqualToString:@"quilt"];
    NSString *displayName = isQuilt ? @"Quilt" : @"Fabric";
    NSString *metaBase = isQuilt ? @"https://meta.quiltmc.org/v3/versions/loader"
                                 : @"https://meta.fabricmc.net/v2/versions/loader";
    // latest alias: equivalent to no version specified (automatically select the latest stable version below)
    NSString *loaderVersion = [params[@"loaderVersion"] isKindOfClass:[NSString class]] ? params[@"loaderVersion"] : @"";
    if (aiIsLatestAlias(loaderVersion)) loaderVersion = @"";

    // wait=false: install in the background and return immediately; swallow later completion callbacks (progress is available in the download center/check_downloads)
    if (!aiWaitRequested(params)) {
        completion([NSString stringWithFormat:@"Started installing the %@ loader (MC %@) in the background: the vanilla game will be installed first if missing, then the loader version JSON will be written and the instance registered%@. Check task progress in the download center or with check_downloads.", displayName, mcVersion, isQuilt ? @"" : @", and Fabric API will be installed automatically"], nil);
        completion = ^(NSString * _Nullable r, NSError * _Nullable e) {
            // Background execution: do not return the terminal result (progress and result are visible in the download center)
        };
    }

    // Stage indices match PLTaskStagesFabricExtra()
    static const NSUInteger kAiFabricStageProfile = 0;
    static const NSUInteger kAiFabricStageLoaderLibs = 1;
    static const NSUInteger kAiFabricStageWriteJSON = 2;

    __weak typeof(self) weakSelf = self;

    // Check for and install the vanilla game first
    NSString *profile = [AiAssetNetworkUtil resolveProfileName:params];
    NSString *gameDir = [AiAssetNetworkUtil resolveGameDirForProfile:profile];
    BOOL vanillaInstalled = [AiAssetNetworkUtil isGameVersionInstalled:mcVersion inGameDir:gameDir];

    void (^continueWithLoader)(void) = ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        [strongSelf continueFabricInstallWithMetaBase:metaBase
                                           displayName:displayName
                                               isQuilt:isQuilt
                                             mcVersion:mcVersion
                                         loaderVersion:loaderVersion
                                         profileStage:kAiFabricStageProfile
                                            libsStage:kAiFabricStageLoaderLibs
                                            jsonStage:kAiFabricStageWriteJSON
                                            completion:completion];
    };

    if (vanillaInstalled) {
        continueWithLoader();
        return;
    }

    // Automatically preinstall the vanilla game (fully automated in the style of HMCL AE; progress shown as a separate MC task in the download center)
    [AiAssetInstaller installVanillaVersionId:mcVersion completion:^(BOOL success, NSString * _Nullable message) {
        if (!success) {
            completion(nil, [NSError errorWithDomain:kAiAssetToolDomain code:500
                                            userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Failed to preinstall MC %@: %@ (cannot continue installing %@)", mcVersion, message ?: @"Unknown error", displayName]}]);
            return;
        }
        continueWithLoader();
    }];
}

/// Main Fabric/Quilt installation after vanilla is ready (resolve loader version → meta profile → write JSON → Fabric API)
- (void)continueFabricInstallWithMetaBase:(NSString *)metaBase
                               displayName:(NSString *)displayName
                                   isQuilt:(BOOL)isQuilt
                                 mcVersion:(NSString *)mcVersion
                              loaderVersion:(NSString *)loaderVersion
                               profileStage:(NSUInteger)profileStage
                                  libsStage:(NSUInteger)libsStage
                                  jsonStage:(NSUInteger)jsonStage
                                completion:(void (^)(NSString * _Nullable result, NSError * _Nullable error))completion {
    __weak typeof(self) weakSelf = self;

    void (^startWithLoaderVersion)(NSString *) = ^(NSString *resolvedLoaderVersion) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;

        DownloadTaskManager *manager = [DownloadTaskManager sharedManager];
        NSString *downloadSource = getPrefObject(@"general.download_source") ?: @"official";
        NSString *taskName = [NSString stringWithFormat:@"%@-%@-%@", isQuilt ? @"quilt" : @"fabric", mcVersion, resolvedLoaderVersion];
        DownloadTaskItem *task = [manager registerTaskWithResourceType:DownloadTaskResourceTypeModloader
                                                          resourceName:taskName
                                                           displayName:[NSString stringWithFormat:@"%@ %@ (%@)", displayName, resolvedLoaderVersion, mcVersion]
                                                        downloadSource:downloadSource
                                                               rawTask:nil
                                                        supportsResume:NO
                                                               iconURL:nil];
        if (!task) {
            completion(nil, [NSError errorWithDomain:kAiAssetToolDomain code:500
                                            userInfo:@{NSLocalizedDescriptionKey: @"Failed to register loader installation task"}]);
            return;
        }
        [manager setTaskWithId:task.taskId stages:PLTaskStagesFabricExtra()];
        task.autoPresentDetail = YES;
        [manager setTaskWithId:task.taskId state:DownloadTaskStateDownloading];

        // Stage 0: fetch loader profile
        [manager updateTaskWithId:task.taskId stageAtIndex:profileStage status:PLTaskStageStatusRunning];
        [manager updateTaskWithId:task.taskId currentStageIndex:profileStage];

        NSString *profileURLStr = [NSString stringWithFormat:@"%@/%@/%@/profile/json", metaBase, mcVersion, resolvedLoaderVersion];
        NSURL *profileURL = [NSURL URLWithString:profileURLStr];
        if (!profileURL) {
            [manager updateTaskWithId:task.taskId stageAtIndex:profileStage status:PLTaskStageStatusFailed];
            NSError *err = [NSError errorWithDomain:kAiAssetToolDomain code:400
                                        userInfo:@{NSLocalizedDescriptionKey: @"Invalid loader profile URL"}];
            [manager setTaskWithId:task.taskId completedWithError:err];
            completion(nil, err);
            return;
        }

        [AiAssetNetworkUtil getJSONFromURL:profileURL completion:^(id _Nullable json, NSError * _Nullable pError) {
            if (pError || ![json isKindOfClass:[NSDictionary class]]) {
                [manager updateTaskWithId:task.taskId stageAtIndex:profileStage status:PLTaskStageStatusFailed];
                [manager updateTaskWithId:task.taskId stageAtIndex:profileStage progress:0 message:pError.localizedDescription];
                NSError *err = pError ?: [NSError errorWithDomain:kAiAssetToolDomain code:2
                                                         userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Failed to fetch %@ profile", displayName]}];
                [manager setTaskWithId:task.taskId completedWithError:err];
                completion(nil, err);
                return;
            }
            [manager updateTaskWithId:task.taskId stageAtIndex:profileStage status:PLTaskStageStatusCompleted];

            // Stage 2: write version JSON (same as DownloadViewController installFabricLikeLoader; use POJAV_GAME_DIR)
            [manager updateTaskWithId:task.taskId stageAtIndex:jsonStage status:PLTaskStageStatusRunning];
            [manager updateTaskWithId:task.taskId currentStageIndex:jsonStage];

            NSDictionary *profileJson = (NSDictionary *)json;
            NSString *versionId = [profileJson[@"id"] isKindOfClass:[NSString class]] ? profileJson[@"id"] : @"";
            if (versionId.length == 0) {
                [manager updateTaskWithId:task.taskId stageAtIndex:jsonStage status:PLTaskStageStatusFailed];
                NSError *err = [NSError errorWithDomain:kAiAssetToolDomain code:3
                                                userInfo:@{NSLocalizedDescriptionKey: @"profile JSON is missing the version id"}];
                [manager setTaskWithId:task.taskId completedWithError:err];
                completion(nil, err);
                return;
            }

            const char *env = getenv("POJAV_GAME_DIR");
            NSString *gameDirRoot = (env && strlen(env) > 0) ? [NSString stringWithUTF8String:env] : NSHomeDirectory();
            NSString *jsonPath = [gameDirRoot stringByAppendingPathComponent:
                                  [NSString stringWithFormat:@"versions/%@/%@.json", versionId, versionId]];
            [[NSFileManager defaultManager] createDirectoryAtPath:[jsonPath stringByDeletingLastPathComponent]
                                      withIntermediateDirectories:YES
                                                       attributes:nil
                                                            error:nil];
            NSError *saveError = nil;
            NSData *jsonData = [NSJSONSerialization dataWithJSONObject:profileJson options:NSJSONWritingPrettyPrinted error:&saveError];
            if (!jsonData || ![jsonData writeToFile:jsonPath options:NSDataWritingAtomic error:&saveError]) {
                [manager updateTaskWithId:task.taskId stageAtIndex:jsonStage status:PLTaskStageStatusFailed];
                NSError *err = [NSError errorWithDomain:kAiAssetToolDomain code:4
                                                userInfo:@{NSLocalizedDescriptionKey: saveError.localizedDescription ?: @"Failed to write version JSON"}];
                [manager setTaskWithId:task.taskId completedWithError:err];
                completion(nil, err);
                return;
            }

            // Register and select the instance profile (same as the normal installation flow)
            NSMutableDictionary *prof = [NSMutableDictionary dictionary];
            prof[@"name"] = versionId;
            prof[@"lastVersionId"] = versionId;
            prof[@"gameDir"] = @".";
            prof[@"type"] = @"custom";
            prof[@"created"] = [NSDate date].description;
            [PLProfiles.current saveProfile:prof withName:versionId];
            PLProfiles.current.selectedProfileName = versionId;
            [[NSNotificationCenter defaultCenter] postNotificationName:@"ReloadProfileList" object:nil];
            [manager updateTaskWithId:task.taskId stageAtIndex:jsonStage status:PLTaskStageStatusCompleted];

            // Fabric automatically installs Fabric API (separate Mod download task); Quilt uses QSL/QFAPI, so skip
            if (!isQuilt) {
                [manager updateTaskWithId:task.taskId stageAtIndex:libsStage status:PLTaskStageStatusRunning];
                [manager updateTaskWithId:task.taskId currentStageIndex:libsStage];
                [strongSelf installFabricAPIForGameVersion:mcVersion completion:^(BOOL apiOK, NSString * _Nullable apiMessage) {
                    if (apiOK) {
                        [manager updateTaskWithId:task.taskId stageAtIndex:libsStage status:PLTaskStageStatusCompleted];
                    } else {
                        // Fabric API failure does not block loader installation; only mark the stage failure reason
                        [manager updateTaskWithId:task.taskId stageAtIndex:libsStage status:PLTaskStageStatusFailed];
                        [manager updateTaskWithId:task.taskId stageAtIndex:libsStage progress:0 message:apiMessage];
                    }
                    [manager setTaskWithId:task.taskId completedWithError:nil];
                    NSString *result = apiOK
                        ? [NSString stringWithFormat:@"%@ %@ installed successfully (MC %@); Fabric API was also installed automatically, and the instance was created and selected.", displayName, resolvedLoaderVersion, mcVersion]
                        : [NSString stringWithFormat:@"%@ %@ installed successfully (MC %@), and the instance was created and selected; however, automatic Fabric API installation failed: %@. Ask me to reinstall it or handle it manually.", displayName, resolvedLoaderVersion, mcVersion, apiMessage ?: @"Unknown reason"];
                    completion(result, nil);
                }];
            } else {
                [manager updateTaskWithId:task.taskId stageAtIndex:libsStage status:PLTaskStageStatusSkipped];
                [manager setTaskWithId:task.taskId completedWithError:nil];
                completion([NSString stringWithFormat:@"Quilt %@ installed successfully (MC %@); the instance was created and selected.", resolvedLoaderVersion, mcVersion], nil);
            }
        }];
    };

    if (loaderVersion.length > 0) {
        startWithLoaderVersion(loaderVersion);
        return;
    }

    // Loader version not specified: select the latest stable version (fall back to the first)
    NSString *listURLStr = [NSString stringWithFormat:@"%@/%@", metaBase, mcVersion];
    NSURL *listURL = [NSURL URLWithString:listURLStr];
    if (!listURL) {
        completion(nil, [NSError errorWithDomain:kAiAssetToolDomain code:400
                                        userInfo:@{NSLocalizedDescriptionKey: @"Invalid loader version list URL"}]);
        return;
    }
    [AiAssetNetworkUtil getJSONFromURL:listURL completion:^(id _Nullable json, NSError * _Nullable error) {
        if (error) {
            NSLog(@"[AI] %@ loader version list request failed (URL: %@, error: %@)", displayName, listURLStr, error);
            completion(nil, error);
            return;
        }
        NSArray *list = [json isKindOfClass:[NSArray class]] ? json : nil;
        if (list.count == 0) {
            // Response is not an array or is empty: log the actual type and response summary to help diagnose mirror hijacking/incorrect gateway
            NSString *body = [json isKindOfClass:[NSDictionary class]] ? [[NSString alloc] initWithData:[NSJSONSerialization dataWithJSONObject:json options:0 error:nil] encoding:NSUTF8StringEncoding] : ([json isKindOfClass:[NSString class]] ? json : NSStringFromClass([json class]));
            NSLog(@"[AI] %@ loader version list is empty (URL: %@, response type: %@, content: %@)", displayName, listURLStr, NSStringFromClass([json class]), [body substringToIndex:MIN(body.length, 200)]);
            completion(nil, [NSError errorWithDomain:kAiAssetToolDomain code:404
                                            userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"No %@ loader versions are available for MC %@", displayName, mcVersion]}]);
            return;
        }
        // Important fix (install_loader could not resolve "latest"): Fabric/Quilt meta versions are nested under
        // loader.version, and stable under loader.stable; also support older implementations that put version/stable at the top level.
        NSString *picked = nil;
        for (id v in list) {
            if (![v isKindOfClass:[NSDictionary class]]) continue;
            NSDictionary *loaderObj = [v[@"loader"] isKindOfClass:[NSDictionary class]] ? v[@"loader"] : nil;
            NSString *ver = [loaderObj[@"version"] isKindOfClass:[NSString class]] ? loaderObj[@"version"] : nil;
            if (ver.length == 0 && [v[@"version"] isKindOfClass:[NSString class]]) ver = v[@"version"];
            BOOL stable = (loaderObj && [loaderObj[@"stable"] isKindOfClass:[NSNumber class]])
                ? [loaderObj[@"stable"] boolValue]
                : [v[@"stable"] boolValue];
            if (ver.length > 0 && stable) {
                picked = ver;
                break;
            }
        }
        if (!picked) {
            // Fallback: take the first entry when none is marked stable
            NSDictionary *first = [list.firstObject isKindOfClass:[NSDictionary class]] ? list.firstObject : nil;
            NSDictionary *firstLoader = [first[@"loader"] isKindOfClass:[NSDictionary class]] ? first[@"loader"] : nil;
            if ([firstLoader[@"version"] isKindOfClass:[NSString class]] && [firstLoader[@"version"] length] > 0) picked = firstLoader[@"version"];
            else if ([first[@"version"] isKindOfClass:[NSString class]] && [first[@"version"] length] > 0) picked = first[@"version"];
        }
        if (picked.length == 0) {
            NSLog(@"[AI] Could not resolve %@ loader version (URL: %@, traversed %lu entries, first entry: %@)", displayName, listURLStr, (unsigned long)list.count, list.firstObject);
            completion(nil, [NSError errorWithDomain:kAiAssetToolDomain code:404
                                            userInfo:@{NSLocalizedDescriptionKey: @"Could not resolve loader version"}]);
            return;
        }
        startWithLoaderVersion(picked);
    }];
}

/// Automatically install Fabric API (slug=fabric-api, select version matching gameVersion, download to mods directory as a separate Mod task)
- (void)installFabricAPIForGameVersion:(NSString *)mcVersion
                            completion:(void (^)(BOOL success, NSString * _Nullable message))completion {
    NSError *err = nil;
    NSString *modsFolder = [[ModService sharedService] ensureModsFolderForProfile:[AiAssetNetworkUtil resolveProfileName:@{}] error:&err];
    if (modsFolder.length == 0) {
        completion(NO, @"Could not determine mods directory");
        return;
    }
    [self fetchVersionsForSlug:@"fabric-api"
                     versionId:@""
                   gameVersion:mcVersion
                    completion:^(NSString * _Nullable filename, NSURL * _Nullable fileURL, NSString * _Nullable sha1, NSError * _Nullable verError) {
        if (verError) {
            completion(NO, verError.localizedDescription);
            return;
        }
        NSString *safeFile = [AiAssetNetworkUtil safeFileName:filename];
        [AiAssetInstaller downloadFileFromURL:fileURL
                                     filename:safeFile
                                       folder:modsFolder
                                  displayName:@"Fabric API"
                                 resourceType:DownloadTaskResourceTypeMod
                                  expectedSHA1:sha1
                                   completion:^(NSString * _Nullable result, NSError * _Nullable dError) {
            if (dError) {
                completion(NO, dError.localizedDescription);
            } else {
                completion(YES, nil);
            }
        }];
    }];
}

@end

#pragma mark - AiAssetNetworkUtil implementation

@implementation AiAssetNetworkUtil

+ (void)getJSONFromURL:(NSURL *)url completion:(void (^)(id _Nullable, NSError * _Nullable))completion {
    if (!url) {
        if (completion) completion(nil, [NSError errorWithDomain:kAiAssetToolDomain code:400 userInfo:@{NSLocalizedDescriptionKey: @"URL is empty"}]);
        return;
    }
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    [request setHTTPMethod:@"GET"];
    [request setValue:@"Air/1.0 (iOS)" forHTTPHeaderField:@"User-Agent"];
    request.timeoutInterval = 20.0;

    NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (error || !data) {
                if (completion) completion(nil, error ?: [NSError errorWithDomain:kAiAssetToolDomain code:1 userInfo:@{NSLocalizedDescriptionKey: @"Network request failed"}]);
                return;
            }
            NSInteger status = [(NSHTTPURLResponse *)response statusCode];
            if (status < 200 || status >= 300) {
                NSString *msg = (status == 404) ? @"Asset not found (404)" : [NSString stringWithFormat:@"Request failed (HTTP %ld)", (long)status];
                if (completion) completion(nil, [NSError errorWithDomain:kAiAssetToolDomain code:status userInfo:@{NSLocalizedDescriptionKey: msg}]);
                return;
            }
            id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
            if (completion) completion(json, nil);
        });
    }];
    [task resume];
}

/// Modrinth request source chain: official → MCIM mirror (mod.mcimirror.top) → retry official
+ (void)getModrinthJSONWithPath:(NSString *)apiPath
                     completion:(void (^)(id _Nullable json, NSString * _Nullable usedSource, NSError * _Nullable error))completion {
    NSArray *bases = @[
        @"https://api.modrinth.com/v2",        // Official (default)
        @"https://mod.mcimirror.top/modrinth/v2", // MCIM mirror
        @"https://api.modrinth.com/v2",        // Retry official (fallback if mirror is unavailable)
    ];
    [self getModrinthJSONFromBases:bases index:0 path:apiPath lastError:nil completion:completion];
}

+ (void)getModrinthJSONFromBases:(NSArray<NSString *> *)bases
                           index:(NSUInteger)index
                            path:(NSString *)path
                       lastError:(NSError * _Nullable)lastError
                       completion:(void (^)(id _Nullable json, NSString * _Nullable usedSource, NSError * _Nullable error))completion {
    if (!completion) return;
    if (path.length == 0) {
        completion(nil, nil, [NSError errorWithDomain:kAiAssetToolDomain code:400 userInfo:@{NSLocalizedDescriptionKey: @"Modrinth API path is empty"}]);
        return;
    }
    if (index >= bases.count) {
        NSString *detail = lastError.localizedDescription ?: @"Unknown error";
        completion(nil, nil, [NSError errorWithDomain:kAiAssetToolDomain code:1
                                             userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Both the official Modrinth source and MCIM mirror are unavailable: %@", detail]}]);
        return;
    }
    NSURL *url = [NSURL URLWithString:[bases[index] stringByAppendingString:path]];
    if (!url) {
        [self getModrinthJSONFromBases:bases index:index + 1 path:path lastError:lastError completion:completion];
        return;
    }
    [self getJSONFromURL:url completion:^(id _Nullable json, NSError * _Nullable error) {
        if (json) {
            NSString *source = [bases[index] containsString:@"mcimirror"] ? @"Modrinth (MCIM mirror)" : @"Modrinth";
            completion(json, source, nil);
            return;
        }
        // Current source failed (network error/HTTP non-2xx/JSON parse failure) → switch to the next source
        [self getModrinthJSONFromBases:bases index:index + 1 path:path lastError:error completion:completion];
    }];
}

+ (NSString *)safeFileName:(NSString *)rawName {
    if (rawName.length == 0) return @"download";
    NSMutableCharacterSet *bad = [NSMutableCharacterSet characterSetWithCharactersInString:@"/\\:"];
    NSArray *parts = [rawName componentsSeparatedByCharactersInSet:bad];
    return [parts componentsJoinedByString:@"_"];
}

+ (NSString *)resolveProfileName:(NSDictionary *)params {
    NSString *instance = [params[@"instance"] isKindOfClass:[NSString class]] ? params[@"instance"] : @"";
    if (instance.length > 0) return instance;
    NSString *name = [[PLProfiles current] selectedProfileName];
    return (name.length > 0) ? name : @"default";
}

+ (NSString *)resolveGameDirForProfile:(NSString *)profileName {
    NSString *profile = profileName.length ? profileName : @"default";
    @try {
        NSDictionary *profiles = [PLProfiles current].profiles;
        NSDictionary *prof = [profiles isKindOfClass:[NSDictionary class]] ? profiles[profile] : nil;
        if ([prof isKindOfClass:[NSDictionary class]]) {
            // ★ [VER-ISOLATE-PCL] Shared version-isolation resolution: when isolation is enabled, gameDir is
            //   versions/<version id>; when disabled, it is "." (instance root) — same as before.
            NSString *gameDir = amePCLVersionGameDirSubpath(prof, nil);
            if ([gameDir isKindOfClass:[NSString class]] && gameDir.length > 0) {
                if ([gameDir isEqualToString:@"."]) {
                    const char *env = getenv("POJAV_GAME_DIR");
                    return env ? [NSString stringWithUTF8String:env] : NSHomeDirectory();
                }
                if ([gameDir isAbsolutePath]) return gameDir;
                const char *env = getenv("POJAV_GAME_DIR");
                NSString *base = env ? [NSString stringWithUTF8String:env] : NSHomeDirectory();
                NSString *clean = [gameDir hasPrefix:@"./"] ? [gameDir substringFromIndex:2] : gameDir;
                return [base stringByAppendingPathComponent:clean];
            }
        }
    } @catch (NSException *ex) {
        // ignore
    }
    const char *root = getenv("POJAV_GAME_DIR");
    if (root && strlen(root) > 0) return [NSString stringWithUTF8String:root];
    return NSHomeDirectory();
}

+ (BOOL)isGameVersionInstalled:(NSString *)mcVersion inGameDir:(NSString *)gameDir {
    if (mcVersion.length == 0 || gameDir.length == 0) return NO;
    NSFileManager *fm = [NSFileManager defaultManager];
    BOOL isDir = NO;
    // 1. <gameDir>/versions/<mcVersion>/ (directory contains .json)
    NSString *versionsDir = [gameDir stringByAppendingPathComponent:@"versions"];
    NSString *verPath = [versionsDir stringByAppendingPathComponent:mcVersion];
    if ([fm fileExistsAtPath:verPath isDirectory:&isDir] && isDir) return YES;
    if ([fm fileExistsAtPath:[verPath stringByAppendingPathExtension:@"json"]]) return YES;
    // 2. <gameDir>/<mcVersion>.json
    if ([fm fileExistsAtPath:[gameDir stringByAppendingPathComponent:[mcVersion stringByAppendingPathExtension:@"json"]]]) return YES;
    return NO;
}

+ (void)fetchVersionEntry:(NSString *)versionId
               completion:(void (^)(NSDictionary * _Nullable entry, NSError * _Nullable error))completion {
    // Version manifest sources: BMCLAPI mirror by default, retry the official source on failure (independent of the general.download_source preference)
    NSArray *manifestURLStrs = @[
        @"https://bmclapi2.bangbang93.com/mc/game/version_manifest_v2.json",
        @"https://piston-meta.mojang.com/mc/game/version_manifest_v2.json",
    ];
    [self fetchVersionEntryFromManifests:manifestURLStrs
                                    index:0
                               versionId:versionId
                               lastError:nil
                               completion:completion];
}

+ (void)fetchVersionEntryFromManifests:(NSArray<NSString *> *)manifestURLStrs
                                 index:(NSUInteger)index
                             versionId:(NSString *)versionId
                             lastError:(NSError * _Nullable)lastError
                             completion:(void (^)(NSDictionary * _Nullable entry, NSError * _Nullable error))completion {
    if (index >= manifestURLStrs.count) {
        NSString *detail = lastError.localizedDescription ?: @"Unknown error";
        if (completion) completion(nil, [NSError errorWithDomain:kAiAssetToolDomain code:500
                                                        userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Failed to fetch version manifest (BMCLAPI and official sources are both unavailable): %@", detail]}]);
        return;
    }
    NSURL *manifestURL = [NSURL URLWithString:manifestURLStrs[index]];
    if (!manifestURL) {
        [self fetchVersionEntryFromManifests:manifestURLStrs index:index + 1 versionId:versionId lastError:lastError completion:completion];
        return;
    }
    [self getJSONFromURL:manifestURL completion:^(id _Nullable json, NSError * _Nullable error) {
        if (error) {
            // Current source failed → retry with the next source (BMCLAPI → official)
            [self fetchVersionEntryFromManifests:manifestURLStrs index:index + 1 versionId:versionId lastError:error completion:completion];
            return;
        }
        NSDictionary *manifest = [json isKindOfClass:[NSDictionary class]] ? json : nil;
        NSArray *versions = [manifest[@"versions"] isKindOfClass:[NSArray class]] ? manifest[@"versions"] : nil;
        if (versions.count == 0) {
            [self fetchVersionEntryFromManifests:manifestURLStrs index:index + 1 versionId:versionId
                                      lastError:[NSError errorWithDomain:kAiAssetToolDomain code:2
                                                                  userInfo:@{NSLocalizedDescriptionKey: @"Invalid version manifest format"}]
                                      completion:completion];
            return;
        }

        // Resolve latest aliases (latest-release/latest/latest-snapshot)
        NSString *target = versionId;
        if ([target isEqualToString:@"latest"] || [target isEqualToString:@"latest-release"]) {
            NSDictionary *latest = [manifest[@"latest"] isKindOfClass:[NSDictionary class]] ? manifest[@"latest"] : nil;
            NSString *release = [latest[@"release"] isKindOfClass:[NSString class]] ? latest[@"release"] : nil;
            target = release.length > 0 ? release : getPrefObject(@"internal.latest_version.release");
        } else if ([target isEqualToString:@"latest-snapshot"]) {
            NSDictionary *latest = [manifest[@"latest"] isKindOfClass:[NSDictionary class]] ? manifest[@"latest"] : nil;
            NSString *snapshot = [latest[@"snapshot"] isKindOfClass:[NSString class]] ? latest[@"snapshot"] : nil;
            target = snapshot.length > 0 ? snapshot : getPrefObject(@"internal.latest_version.snapshot");
        }
        if (![target isKindOfClass:[NSString class]] || target.length == 0) {
            if (completion) completion(nil, [NSError errorWithDomain:kAiAssetToolDomain code:404
                                                            userInfo:@{NSLocalizedDescriptionKey: @"Could not resolve target version number"}]);
            return;
        }

        for (id v in versions) {
            if (![v isKindOfClass:[NSDictionary class]]) continue;
            if ([v[@"id"] isEqualToString:target]) {
                if (completion) completion(v, nil);
                return;
            }
        }
        if (completion) completion(nil, [NSError errorWithDomain:kAiAssetToolDomain code:404
                                                        userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Version %@ not found in manifest", target]}]);
    }];
}

+ (void)ensureVersionJSONExists:(NSString *)versionId
                     completion:(void (^)(BOOL success))completion {
    if (versionId.length == 0) {
        if (completion) completion(NO);
        return;
    }
    const char *env = getenv("POJAV_GAME_DIR");
    NSString *gameDir = (env && strlen(env) > 0) ? [NSString stringWithUTF8String:env] : NSHomeDirectory();
    if (gameDir.length == 0) {
        const char *home = getenv("POJAV_HOME");
        gameDir = (home && strlen(home) > 0) ? [NSString stringWithUTF8String:home] : NSHomeDirectory();
    }
    NSString *versionDir = [gameDir stringByAppendingPathComponent:
                            [NSString stringWithFormat:@"versions/%@", versionId]];
    NSString *versionJsonPath = [versionDir stringByAppendingPathComponent:
                                 [NSString stringWithFormat:@"%@.json", versionId]];

    // 1. Already exists; succeed immediately
    if ([NSFileManager.defaultManager fileExistsAtPath:versionJsonPath]) {
        if (completion) completion(YES);
        return;
    }

    // 2. Fetch manifest entry → download version JSON → save to disk
    [self fetchVersionEntry:versionId completion:^(NSDictionary * _Nullable entry, NSError * _Nullable error) {
        if (!entry) {
            if (completion) completion(NO);
            return;
        }
        NSString *versionJSONURL = [entry[@"url"] isKindOfClass:[NSString class]] ? entry[@"url"] : nil;
        if (versionJSONURL.length == 0) {
            if (completion) completion(NO);
            return;
        }
        NSURL *jsonURL = [NSURL URLWithString:versionJSONURL];
        if (!jsonURL) {
            if (completion) completion(NO);
            return;
        }
        [self getJSONFromURL:jsonURL completion:^(id _Nullable json, NSError * _Nullable jError) {
            if (jError || ![json isKindOfClass:[NSDictionary class]]) {
                // Official domain failed → replace with BMCLAPI mirror domain and retry (automatic download-source fallback)
                NSString *mirrored = [versionJSONURL stringByReplacingOccurrencesOfString:@"piston-meta.mojang.com"
                                                                                withString:@"bmclapi2.bangbang93.com"];
                mirrored = [mirrored stringByReplacingOccurrencesOfString:@"launchermeta.mojang.com"
                                                               withString:@"bmclapi2.bangbang93.com"];
                if ([mirrored isEqualToString:versionJSONURL]) {
                    if (completion) completion(NO);
                    return;
                }
                NSURL *mirrorURL = [NSURL URLWithString:mirrored];
                if (!mirrorURL) {
                    if (completion) completion(NO);
                    return;
                }
                [self getJSONFromURL:mirrorURL completion:^(id _Nullable mJson, NSError * _Nullable mError) {
                    if (mError || ![mJson isKindOfClass:[NSDictionary class]]) {
                        if (completion) completion(NO);
                        return;
                    }
                    [self writeVersionJSON:mJson toPath:versionJsonPath versionDir:versionDir completion:completion];
                }];
                return;
            }
            [self writeVersionJSON:json toPath:versionJsonPath versionDir:versionDir completion:completion];
        }];
    }];
}

/// Save version JSON to disk (create directory + atomic write)
+ (void)writeVersionJSON:(NSDictionary *)json
                  toPath:(NSString *)versionJsonPath
               versionDir:(NSString *)versionDir
               completion:(void (^)(BOOL success))completion {
    NSData *data = [NSJSONSerialization dataWithJSONObject:json options:NSJSONWritingPrettyPrinted error:nil];
    if (!data) {
        if (completion) completion(NO);
        return;
    }
    [NSFileManager.defaultManager createDirectoryAtPath:versionDir
                            withIntermediateDirectories:YES
                                             attributes:nil
                                                  error:nil];
    BOOL ok = [data writeToFile:versionJsonPath options:NSDataWritingAtomic error:nil];
    if (completion) completion(ok);
}

+ (NSString *)resolveGameVersionForParams:(NSDictionary *)params {
    // 1. Explicit gameVersion parameter takes precedence
    NSString *explicit = [params[@"gameVersion"] isKindOfClass:[NSString class]] ? params[@"gameVersion"] : @"";
    if (explicit.length > 0) return explicit;

    // 2. Instance profile's lastVersionId (normalize and strip loader suffix)
    NSString *profileName = [self resolveProfileName:params];
    @try {
        NSDictionary *profiles = [PLProfiles current].profiles;
        NSDictionary *prof = [profiles isKindOfClass:[NSDictionary class]] ? profiles[profileName] : nil;
        if ([prof isKindOfClass:[NSDictionary class]]) {
            NSString *lastVersionId = [prof[@"lastVersionId"] isKindOfClass:[NSString class]] ? prof[@"lastVersionId"] : @"";
            if (lastVersionId.length > 0) {
                return [self normalizeGameVersion:lastVersionId];
            }
        }
    } @catch (NSException *ex) {
        // ignore
    }
    return @"";
}

/// Normalize a version number: strip fabric/forge/neoforge/quilt/optifine loader suffixes.
/// Examples: 1.20.1-forge-47.2.0 → 1.20.1; fabric-loader-0.16.9-1.20.1 → 1.20.1; 1.20.1 is unchanged.
+ (NSString *)normalizeGameVersion:(NSString *)rawVersion {
    if (rawVersion.length == 0) return @"";
    NSArray *parts = [rawVersion componentsSeparatedByString:@"-"];
    if (parts.count == 1) return rawVersion;
    NSSet *loaderTokens = [NSSet setWithObjects:@"fabric", @"forge", @"neoforge", @"quilt", @"optifine", @"loader", nil];
    for (NSUInteger i = 0; i < parts.count; i++) {
        if (![loaderTokens containsObject:[parts[i] lowercaseString]]) continue;
        // Prefer the component before the loader token (1.20.1-forge-47.2.0), otherwise the component after it (fabric-loader-x-1.20.1)
        if (i > 0 && [self isPlausibleMCVersion:parts[i - 1]]) return parts[i - 1];
        if (i + 1 < parts.count && [self isPlausibleMCVersion:parts[i + 1]]) return parts[i + 1];
    }
    return rawVersion;
}

/// Determine whether a string looks like an MC version number (1.20.1 / 1.7.10 / 24w14a, etc.)
+ (BOOL)isPlausibleMCVersion:(NSString *)s {
    if (s.length < 2) return NO;
    if (!isdigit([s characterAtIndex:0])) return NO;
    if ([s containsString:@"."]) return YES;
    // Snapshot form, e.g. 24w14a: starts with digits + w + digits + ends with a letter
    if (s.length >= 4 && [s characterAtIndex:s.length - 1] >= 'a' && [s characterAtIndex:s.length - 1] <= 'z') return YES;
    return NO;
}

+ (void)postShowDownloadPage {
    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:@"ShowDownloadPage" object:nil];
    });
}

@end

#pragma mark - AiAssetInstaller implementation

@implementation AiAssetInstaller

+ (void)downloadFileFromURL:(NSURL *)url
                   filename:(NSString *)filename
                     folder:(NSString *)folder
                displayName:(NSString *)displayName
               resourceType:(NSString *)resourceType
                expectedSHA1:(nullable NSString *)expectedSHA1
                 completion:(void (^)(NSString * _Nullable result, NSError * _Nullable error))completion {
    [self downloadFileFromURL:url
                     filename:filename
                       folder:folder
                  displayName:displayName
                 resourceType:resourceType
                  expectedSHA1:expectedSHA1
            waitForCompletion:YES
                   completion:completion
                   onFinished:nil];
}

+ (void)downloadFileFromURL:(NSURL *)url
                   filename:(NSString *)filename
                     folder:(NSString *)folder
                displayName:(NSString *)displayName
               resourceType:(NSString *)resourceType
                expectedSHA1:(nullable NSString *)expectedSHA1
          waitForCompletion:(BOOL)waitForCompletion
                 completion:(void (^)(NSString * _Nullable result, NSError * _Nullable error))completion
                 onFinished:(nullable void (^)(BOOL success, NSString * _Nullable message))onFinished {
    if (!url || folder.length == 0 || filename.length == 0) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (completion) completion(nil, [NSError errorWithDomain:kAiAssetToolDomain code:400 userInfo:@{NSLocalizedDescriptionKey: @"Incomplete download parameters"}]);
        });
        return;
    }

    NSString *resourceName = filename;
    NSString *dispName = displayName.length > 0 ? displayName : filename;
    DownloadTaskItem *task = [[DownloadTaskManager sharedManager]
        registerTaskWithResourceType:resourceType
                        resourceName:resourceName
                         displayName:dispName
                      downloadSource:@"Modrinth"
                             rawTask:nil
                      supportsResume:YES
                             iconURL:nil];
    task.downloadURL = url.absoluteString;
    [[DownloadTaskManager sharedManager] setTaskWithId:task.taskId state:DownloadTaskStateDownloading];

    // Download candidates: official CDN first, MCIM mirror as fallback (cdn.modrinth.com → mod.mcimirror.top)
    // ★ [MODSRC-FIX] The previous implementation used cdn.mcimirror.top as the mirror — that host does not exist (NXDOMAIN; verified by
    //   `curl: (6) Could not resolve host`), making the mirror fallback dead code. The correct Modrinth CDN
    //   mirror host for MCIM is mod.mcimirror.top (consistent with PLMirrorCenter.mcimPrefixPairs; verified:
    //   /data/... returns 302 → official CDN 200).
    NSMutableArray<NSURL *> *candidates = [NSMutableArray arrayWithObject:url];
    NSString *urlStr = url.absoluteString ?: @"";
    if ([urlStr containsString:@"cdn.modrinth.com"]) {
        NSString *mirrored = [urlStr stringByReplacingOccurrencesOfString:@"https://cdn.modrinth.com"
                                                                withString:@"https://mod.mcimirror.top"];
        NSURL *mirrorURL = [NSURL URLWithString:mirrored];
        if (mirrorURL) [candidates addObject:mirrorURL];
    }

    PLDownloadRequest *request = [[PLDownloadRequest alloc] init];
    request.candidateURLs = candidates;
    if (expectedSHA1.length > 0) request.expectedSHA1 = expectedSHA1;
    request.destinationPath = [folder stringByAppendingPathComponent:filename];
    request.taskIdentifier = task.taskId;
    request.allowZipFallbackCheck = YES;

    // wait=false: task is registered; immediately report "Added to background downloads" so the AI can continue other work
    if (!waitForCompletion) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (completion) {
                completion([NSString stringWithFormat:@"Added to background downloads: %@ (task ID %@, target directory %@, file %@); use check_downloads to query progress", dispName, task.taskId, [folder lastPathComponent], filename], nil);
            }
        });
    }

    __block int64_t downloadedBytes = 0;
    __block NSTimeInterval lastReport = 0;
    __block int64_t reportedTotal = -1;

    [[PLDownloadClient sharedClient] startRequest:request
        progress:^(int64_t deltaBytes, int64_t totalExpectedBytes) {
            // Throttle progress callbacks to ≤ 200ms
            NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
            if ((now - lastReport) < 0.2) return;
            lastReport = now;
            downloadedBytes += deltaBytes;
            if (totalExpectedBytes > 0) reportedTotal = totalExpectedBytes;
            double progress = -1;
            if (reportedTotal > 0) progress = (double)downloadedBytes / (double)reportedTotal;
            [[DownloadTaskManager sharedManager] updateTaskWithId:task.taskId
                                                         progress:progress
                                                       totalBytes:reportedTotal
                                                  downloadedBytes:downloadedBytes];
        }
        speed:^(int64_t bytesPerSecond) {
            [[DownloadTaskManager sharedManager] updateTaskWithId:task.taskId
                                                            speed:(double)bytesPerSecond
                                           estimatedTimeRemaining:-1];
        }
        completion:^(BOOL success, NSError * _Nullable error) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (!success) {
                    [[DownloadTaskManager sharedManager] setTaskWithId:task.taskId
                                                      completedWithError:error ?: [NSError errorWithDomain:kAiAssetToolDomain code:1 userInfo:@{NSLocalizedDescriptionKey: @"Download failed"}]];
                    if (onFinished) onFinished(NO, error.localizedDescription ?: @"Download failed");
                    if (waitForCompletion && completion) {
                        completion(nil, error ?: [NSError errorWithDomain:kAiAssetToolDomain code:1 userInfo:@{NSLocalizedDescriptionKey: @"Download failed"}]);
                    }
                    return;
                }
                [[DownloadTaskManager sharedManager] setTaskWithId:task.taskId completedWithError:nil];
                if (onFinished) onFinished(YES, nil);
                if (waitForCompletion && completion) {
                    NSString *result = [NSString stringWithFormat:@"Installed %@ to %@ (%@)", dispName, [folder lastPathComponent], filename];
                    completion(result, nil);
                }
            });
        }];
}

+ (void)installVanillaVersionId:(NSString *)versionId
                     completion:(void (^)(BOOL success, NSString * _Nullable message))completion {
    if (versionId.length == 0) {
        if (completion) dispatch_async(dispatch_get_main_queue(), ^{ completion(NO, @"Version number is missing"); });
        return;
    }

    // 1. Fetch manifest entry (includes version JSON download URL; resolve latest-release/latest-snapshot here)
    [AiAssetNetworkUtil fetchVersionEntry:versionId completion:^(NSDictionary * _Nullable entry, NSError * _Nullable error) {
        if (!entry) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (completion) completion(NO, error.localizedDescription ?: @"Version not found in manifest");
            });
            return;
        }
        NSString *resolvedId = [entry[@"id"] isKindOfClass:[NSString class]] ? entry[@"id"] : versionId;

        // 2. Ensure version JSON is saved first (replace BMCLAPI domain; also ensure that when remoteVersionList is not loaded,
        //    downloadVersionMetadata: can continue downloading libraries/assets via the local JSON path)
        [AiAssetNetworkUtil ensureVersionJSONExists:resolvedId completion:^(BOOL jsonOK) {
            if (!jsonOK) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    if (completion) completion(NO, @"Failed to download version JSON");
                });
                return;
            }

            // 3. Full installation with MinecraftResourceDownloadTask (version JSON/libraries/assets).
            //    downloadVersion: automatically registers a DownloadTaskManager task (six stages + autoPresentDetail),
            //    showing live progress in the download center/unified progress page; automatically skips existing files with a matching SHA1.
            dispatch_async(dispatch_get_main_queue(), ^{
                __block BOOL errored = NO;
                MinecraftResourceDownloadTask *task = [MinecraftResourceDownloadTask new];
                task.maxRetryCount = 3;
                task.handleError = ^{
                    errored = YES;
                };

                dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                    [task downloadVersion:entry];

                    // Poll for completion (maximum 30 minutes, consistent with ensureVanillaInstalled).
                    // prepareForDownload recreates progress, so fetch it again each iteration to avoid dangling KVO.
                    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:30 * 60];
                    BOOL succeeded = NO;
                    while ([deadline timeIntervalSinceNow] > 0) {
                        if (errored) break;
                        NSProgress *p = task.progress;
                        if (p && p.finished) {
                            succeeded = !p.cancelled;
                            break;
                        }
                        [NSThread sleepForTimeInterval:0.5];
                    }

                    dispatch_async(dispatch_get_main_queue(), ^{
                        if (succeeded) {
                            // 4. Register and select the instance profile (same as downloadVanillaVersion:), then refresh the version list
                            NSMutableDictionary *profile = [NSMutableDictionary dictionary];
                            profile[@"name"] = resolvedId;
                            profile[@"lastVersionId"] = resolvedId;
                            profile[@"gameDir"] = @".";
                            profile[@"type"] = @"custom";
                            profile[@"created"] = [NSDate date].description;
                            [PLProfiles.current saveProfile:profile withName:resolvedId];
                            PLProfiles.current.selectedProfileName = resolvedId;
                            [[NSNotificationCenter defaultCenter] postNotificationName:@"ReloadProfileList" object:nil];
                            if (completion) completion(YES, nil);
                        } else {
                            NSString *msg = errored ? @"Download error (see download center task details)"
                                                    : @"Installation timed out (30 minutes)";
                            if (completion) completion(NO, msg);
                        }
                    });
                });
            });
        }];
    }];
}

@end