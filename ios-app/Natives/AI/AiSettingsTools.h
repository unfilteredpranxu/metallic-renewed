//
//  AiSettingsTools.h
//  Amethyst
//
//  Settings read/write tools (enhance-ai-agent Task 10):
//  - list_settings (READ_ONLY): returns the available setting keys and value descriptions
//  - get_setting (READ_ONLY): reads the global and effective instance values for a key
//  - set_setting (CONTROLLED_WRITE): changes a global or instance setting and broadcasts a refresh notification after writing
//
//  Keys fall into two categories:
//  - Global keys: LauncherPreferences (getPrefObject/setPrefObject)
//  - Instance keys: PLProfiles profile fields (renderer/graphicsApi/javaArgs, etc., falling back to the global preference with the same name)
//

#import <Foundation/Foundation.h>
#import "AiTool.h"

NS_ASSUME_NONNULL_BEGIN

@interface AiSettingsTools : NSObject <AiTool>

/// Supported internalName values: list_settings / get_setting / set_setting
- (instancetype)initWithName:(NSString *)name;

@end

NS_ASSUME_NONNULL_END
