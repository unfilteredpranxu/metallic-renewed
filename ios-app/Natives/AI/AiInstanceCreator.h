//
//  AiInstanceCreator.h
//  Amethyst
//
//  create_instance tool (enhance-ai-agent Task 12.2):
//  Creates a same-named directory under <POJAV_HOME>/instances/ and switches to it as the current game directory (replicating
//  VersionManagerViewController switchGameDirTo logic: rebuild the POJAV_GAME_DIR
//  symlink + toggleIsolatedPref + PLProfiles updateCurrent), registers and selects
//  the profile, and posts ReloadProfileList. Returns the full path.
//
//  Optional mcVersion/loader are written only as profile notes (lastVersionId is not preset;
//  version installation is performed by install_game_version / install_loader).
//

#import <Foundation/Foundation.h>
#import "AiTool.h"

NS_ASSUME_NONNULL_BEGIN

@interface AiInstanceCreator : NSObject <AiTool>
@end

NS_ASSUME_NONNULL_END
