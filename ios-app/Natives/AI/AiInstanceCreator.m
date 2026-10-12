//
//  AiInstanceCreator.m
//  Amethyst
//

#import "AiInstanceCreator.h"
#import "LauncherPreferences.h"
#import "PLProfiles.h"

@implementation AiInstanceCreator

- (NSString *)name {
    return @"create_instance";
}

- (AiToolPermission)permission {
    return AiToolPermissionControlledWrite;
}

- (NSString *)summary {
    return @"Create a game directory (instance) and switch to it as the current directory."
           "\nParameters: name (string, required, directory name; recommended format: \"MC version Loader YYYY.MM.DD\", e.g. \"1.20.1 Fabric 2026.08.26\"), "
           "mcVersion (string, optional), loader (string, optional)."
           "\nBehavior: create a directory under instances/ → switch the current game directory (rebuild the symlink) → register and select a profile with the same name."
           "\nReturns the full instance path. Pass the directory name as the instance parameter for subsequent install_* calls."
           "\nBoundary: if the directory already exists, switch to it without error (idempotent).";
}

- (void)execute:(NSDictionary<NSString *, id> *)params
     completion:(void (^)(NSString * _Nullable result, NSError * _Nullable error))completion {
    if (!completion) return;

    NSString *name = [params[@"name"] isKindOfClass:[NSString class]] ? params[@"name"] : @"";
    if (name.length == 0) {
        completion(nil, [NSError errorWithDomain:@"AiTool" code:400
                                     userInfo:@{NSLocalizedDescriptionKey: @"The name parameter is required"}]);
        return;
    }
    // Sanitize the directory name by removing path separators (VersionManagerViewController directly concatenates when creating directories;
    // strip separators here as an additional safeguard against "../" escaping instances/)
    NSArray *parts = [name componentsSeparatedByCharactersInSet:
                      [NSCharacterSet characterSetWithCharactersInString:@"/\\:"]];
    name = [parts componentsJoinedByString:@"_"];
    if (name.length == 0) {
        completion(nil, [NSError errorWithDomain:@"AiTool" code:400
                                     userInfo:@{NSLocalizedDescriptionKey: @"The name parameter is invalid"}]);
        return;
    }

    const char *homeEnv = getenv("POJAV_HOME");
    NSString *home = (homeEnv && strlen(homeEnv) > 0) ? [NSString stringWithUTF8String:homeEnv] : nil;
    if (home.length == 0) {
        home = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
    }

    // 1. Create the instance directory (idempotent)
    NSString *instancePath = [home stringByAppendingPathComponent:
                              [NSString stringWithFormat:@"instances/%@", name]];
    NSError *dirError = nil;
    if (![[NSFileManager defaultManager] createDirectoryAtPath:instancePath
                                   withIntermediateDirectories:YES
                                                    attributes:nil
                                                         error:&dirError]) {
        completion(nil, [NSError errorWithDomain:@"AiTool" code:500
                                     userInfo:@{NSLocalizedDescriptionKey:
                                         [NSString stringWithFormat:@"Failed to create instance directory: %@", dirError.localizedDescription ?: @"Unknown error"]}]);
        return;
    }

    // 2. Switch the current game directory (replicate LauncherPrefGameDirViewController.changeSelectionTo / VersionManagerViewController.switchGameDirTo)
    setPrefObject(@"general.game_directory", name);
    const char *gameDirEnv = getenv("POJAV_GAME_DIR");
    NSString *lasmPath = (gameDirEnv && strlen(gameDirEnv) > 0) ? [NSString stringWithUTF8String:gameDirEnv] : nil;
    if (lasmPath.length > 0) {
        [[NSFileManager defaultManager] removeItemAtPath:lasmPath error:nil];
        NSError *linkError = nil;
        BOOL linkOK = [[NSFileManager defaultManager] createSymbolicLinkAtPath:lasmPath
                                                         withDestinationPath:instancePath
                                                                       error:&linkError];
        if (!linkOK) {
            completion(nil, [NSError errorWithDomain:@"AiTool" code:500
                                         userInfo:@{NSLocalizedDescriptionKey:
                                             [NSString stringWithFormat:@"Failed to rebuild POJAV_GAME_DIR symlink: %@", linkError.localizedDescription ?: @"Unknown error"]}]);
            return;
        }
        [[NSFileManager defaultManager] changeCurrentDirectoryPath:lasmPath];
    }
    toggleIsolatedPref(NO);
    [PLProfiles updateCurrent];

    // 3. Register and select a profile with the same name (mcVersion/loader are only written as notes in the userInfo field)
    NSMutableDictionary *prof = [[PLProfiles current].profiles[name] mutableCopy];
    if (!prof) prof = [NSMutableDictionary dictionary];
    if (!prof[@"name"]) prof[@"name"] = name;
    if (!prof[@"gameDir"]) prof[@"gameDir"] = @".";
    prof[@"type"] = @"custom";
    prof[@"created"] = [[NSDate date] description];
    NSString *mcVersion = [params[@"mcVersion"] isKindOfClass:[NSString class]] ? params[@"mcVersion"] : @"";
    NSString *loader = [params[@"loader"] isKindOfClass:[NSString class]] ? params[@"loader"] : @"";
    if (mcVersion.length > 0) prof[@"aiMcVersion"] = mcVersion;
    if (loader.length > 0) prof[@"aiLoader"] = loader;
    [[PLProfiles current] saveProfile:prof withName:name];
    [PLProfiles current].selectedProfileName = name;

    // 4. Broadcast refresh
    [[NSNotificationCenter defaultCenter] postNotificationName:@"ReloadProfileList" object:nil];
    [[NSNotificationCenter defaultCenter] postNotificationName:@"SelectedProfileChanged" object:nil];

    NSString *note = @"";
    if (mcVersion.length > 0 || loader.length > 0) {
        note = [NSString stringWithFormat:@" (Note: MC %@ %@; continue installation with install_game_version / install_loader)",
                mcVersion.length > 0 ? mcVersion : @"unspecified", loader.length > 0 ? loader : @"no loader"];
    }
    completion([NSString stringWithFormat:@"Created and switched to instance \"%@\".\nPath: %@%@",
                name, instancePath, note], nil);
}

@end
