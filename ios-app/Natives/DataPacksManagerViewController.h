//
//  DataPacksManagerViewController.h
//  Amethyst
//
//  Data-pack management view controller (inherits the ResourceListViewController list base class).
//  Supports local scanning, search, enable/disable, deletion, and import; online downloads have
//  moved to the unified download screen.
//  Note: Minecraft requires data packs in saves/<world name>/datapacks/. This manager scans
//  <gameDir>/datapacks/ (the general directory); users must move packs to the corresponding world directory.
//

#import <UIKit/UIKit.h>
#import "ResourceListViewController.h"

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, DataPacksManagerMode) {
    DataPacksManagerModeLocal,
    DataPacksManagerModeOnline
};

@interface DataPacksManagerViewController : ResourceListViewController

@property (nonatomic, copy, nullable) NSString *profileName;

// Online downloads have moved to the unified download screen; the following properties are retained
// only for compatibility with existing callers, and the UI is fixed to local mode.
@property (nonatomic, assign) DataPacksManagerMode initialMode;
@property (nonatomic, assign) DataPacksManagerMode currentMode;
@property (nonatomic, strong) NSMutableArray *onlineSearchResults;

@end

NS_ASSUME_NONNULL_END
