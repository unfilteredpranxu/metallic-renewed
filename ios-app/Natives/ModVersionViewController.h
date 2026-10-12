#import <UIKit/UIKit.h>
#import <UIKit/UIKit.h>
#import "ModItem.h"
#import "ModVersion.h"

NS_ASSUME_NONNULL_BEGIN

@class ModVersionViewController;

@protocol ModVersionViewControllerDelegate <NSObject>
- (void)modVersionViewController:(ModVersionViewController *)viewController didSelectVersion:(ModVersion *)version;
@end

@interface ModVersionViewController : UIViewController

@property (nonatomic, strong) UIActivityIndicatorView *activityIndicator;
@property (nonatomic, strong) ModItem *modItem;
@property (nonatomic, weak) id<ModVersionViewControllerDelegate> delegate;

// FCL style: pass the current profile's preferred version and loader.
// ModVersionViewController prioritizes the matching chip and pins matching versions to the top.
// If omitted, preserves the original "All" default behavior.
@property (nonatomic, copy, nullable) NSString *preferredGameVersion;
@property (nonatomic, copy, nullable) NSString *preferredLoader;

// API source: 1 = Modrinth (default), 2 = CurseForge.
// Key fix (preserve source for CurseForge search results): mod search results may come from CurseForge (numeric project ID).
// The version page must keep the API source used for search; otherwise, it would send a CurseForge numeric ID to the Modrinth API
// and fail to fetch the version list. Based on ZL2's platform enum throughout the search → details → versions flow.
@property (nonatomic, assign) NSInteger apiSource;

@end

NS_ASSUME_NONNULL_END
