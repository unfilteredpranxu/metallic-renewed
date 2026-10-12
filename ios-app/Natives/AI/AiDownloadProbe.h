//
//  AiDownloadProbe.h
//  Amethyst
//
//  Download progress query tool (check_downloads): iterates over all DownloadTaskManager tasks,
//  returning the name/asset type/status/progress/speed/download source.
//  Lets the AI poll progress after install_* starts a background download with wait=false (enhance-ai-agent Task 8.2).
//

#import <Foundation/Foundation.h>
#import "AiTool.h"

NS_ASSUME_NONNULL_BEGIN

@interface AiDownloadProbe : NSObject <AiTool>

/// Currently, internalName supports only check_downloads
- (instancetype)initWithName:(NSString *)name;

@end

NS_ASSUME_NONNULL_END
