//
//  AiAssetTools.h
//  Amethyst
//
//  Air AI Agent asset/network tools (Phase 3b):
//  - AiAssetSearchTool: Modrinth search tools (search_mods / search_resourcepacks / search_shaders /
//    search_datapacks / search_modpacks / search_worlds), permission ExternalNetwork.
//  - AiAssetInstallTool: installation tools (install_mod / install_resourcepack / install_shader /
//    install_datapack / install_game_version / install_loader), permission ControlledWrite.
//  Both tool groups share a set of file-private helpers in AiAssetTools.m (NSURLSession networking / PLDownloadClient downloads).
//

#import <Foundation/Foundation.h>
#import "AiTool.h"

NS_ASSUME_NONNULL_BEGIN

/// Modrinth asset search / installation tool (specific tool name determined by internalName)
@interface AiAssetSearchTool : NSObject <AiTool>

@property (nonatomic, readonly) NSString *name;
@property (nonatomic, readonly) NSString *summary;
@property (nonatomic, readonly) AiToolPermission permission;

/// Set the tool name for this instance
- (instancetype)initWithName:(NSString *)name;

@end

/// Asset installation / loader tool (specific tool name determined by internalName)
@interface AiAssetInstallTool : NSObject <AiTool>

@property (nonatomic, readonly) NSString *name;
@property (nonatomic, readonly) NSString *summary;
@property (nonatomic, readonly) AiToolPermission permission;

/// Set the tool name for this instance
- (instancetype)initWithName:(NSString *)name;

@end

NS_ASSUME_NONNULL_END