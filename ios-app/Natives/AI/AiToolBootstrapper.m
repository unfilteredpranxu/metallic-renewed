//
//  AiToolBootstrapper.m
//  Amethyst
//

#import "AiToolBootstrapper.h"
#import "AiToolRegistry.h"

#import "AiInstancesTool.h"
#import "AiLogReader.h"
#import "AiCrashAnalyzer.h"
#import "AiFileTools.h"
#import "AiAskTool.h"
#import "AiAssetTools.h"
#import "AiSettingsTools.h"
#import "AiTodoTool.h"
#import "AiSleepTool.h"
#import "AiDownloadProbe.h"
#import "AiInstanceCreator.h"

@implementation AiToolBootstrapper

+ (void)registerBuiltinToolsIntoRegistry:(AiToolRegistry *)registry {
    if (!registry) return;

    // ===== Phase 3a built-in tools =====

    // Instance/version tools (list_instances, list_game_versions)
    [registry registerTool:[[AiInstancesTool alloc] initWithName:@"list_instances"]];
    [registry registerTool:[[AiInstancesTool alloc] initWithName:@"list_game_versions"]];

    // Log reader tools (read_latest_log, read_crash_report)
    [registry registerTool:[[AiLogReader alloc] initWithName:@"read_latest_log"]];
    [registry registerTool:[[AiLogReader alloc] initWithName:@"read_crash_report"]];

    // Crash analysis tool (match_known_errors)
    [registry registerTool:[[AiCrashAnalyzer alloc] init]];

    // File tools (list_files, read_file, grep_files, write_file, edit_file, delete_file)
    [registry registerTool:[[AiFileTools alloc] initWithName:@"list_files"]];
    [registry registerTool:[[AiFileTools alloc] initWithName:@"read_file"]];
    [registry registerTool:[[AiFileTools alloc] initWithName:@"grep_files"]];
    [registry registerTool:[[AiFileTools alloc] initWithName:@"write_file"]];
    [registry registerTool:[[AiFileTools alloc] initWithName:@"edit_file"]];
    [registry registerTool:[[AiFileTools alloc] initWithName:@"delete_file"]];

    // Interactive question tool (ask)
    [registry registerTool:[[AiAskTool alloc] init]];

    // ===== Phase 3b asset tools =====

    // Modrinth search tool (ExternalNetwork)
    [registry registerTool:[[AiAssetSearchTool alloc] initWithName:@"search_mods"]];
    [registry registerTool:[[AiAssetSearchTool alloc] initWithName:@"search_resourcepacks"]];
    [registry registerTool:[[AiAssetSearchTool alloc] initWithName:@"search_shaders"]];
    [registry registerTool:[[AiAssetSearchTool alloc] initWithName:@"search_datapacks"]];
    [registry registerTool:[[AiAssetSearchTool alloc] initWithName:@"search_modpacks"]];
    [registry registerTool:[[AiAssetSearchTool alloc] initWithName:@"search_worlds"]];

    // Asset installation / loader tools (ControlledWrite)
    [registry registerTool:[[AiAssetInstallTool alloc] initWithName:@"install_mod"]];
    [registry registerTool:[[AiAssetInstallTool alloc] initWithName:@"install_resourcepack"]];
    [registry registerTool:[[AiAssetInstallTool alloc] initWithName:@"install_shader"]];
    [registry registerTool:[[AiAssetInstallTool alloc] initWithName:@"install_datapack"]];
    [registry registerTool:[[AiAssetInstallTool alloc] initWithName:@"install_game_version"]];
    [registry registerTool:[[AiAssetInstallTool alloc] initWithName:@"install_loader"]];

    // ===== Additional enhance-ai-agent tools =====

    // Log extensions (read_latest_log/read_crash_report support the instance parameter)
    [registry registerTool:[[AiLogReader alloc] initWithName:@"read_logs"]];

    // Download progress query (ReadOnly)
    [registry registerTool:[[AiDownloadProbe alloc] initWithName:@"check_downloads"]];

    // Settings tools (list/get are ReadOnly; set is ControlledWrite)
    [registry registerTool:[[AiSettingsTools alloc] initWithName:@"list_settings"]];
    [registry registerTool:[[AiSettingsTools alloc] initWithName:@"get_setting"]];
    [registry registerTool:[[AiSettingsTools alloc] initWithName:@"set_setting"]];

    // To-do list tools
    [registry registerTool:[[AiTodoTool alloc] initWithName:@"todo_create"]];
    [registry registerTool:[[AiTodoTool alloc] initWithName:@"todo_list"]];
    [registry registerTool:[[AiTodoTool alloc] initWithName:@"todo_update"]];
    [registry registerTool:[[AiTodoTool alloc] initWithName:@"todo_delete"]];

    // sleep (ReadOnly, no side effects)
    [registry registerTool:[[AiSleepTool alloc] init]];

    // Create a game directory instance (ControlledWrite)
    [registry registerTool:[[AiInstanceCreator alloc] init]];
}

@end