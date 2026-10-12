//
//  AssetVersionViewController.h
//  Amethyst
//
//  Generic asset-version selection view controller
//  For resource packs / data packs / worlds, which have no "loader" concept
//  Modeled on ModVersionViewController, but without a loader-filter button (only game-version filtering)
//  Reuses ModVersion as the version model (its structure matches ShaderVersion)
//

#import <UIKit/UIKit.h>
#import "ModVersion.h"

NS_ASSUME_NONNULL_BEGIN

// Asset type enumeration: determines the title and default behavior.
typedef NS_ENUM(NSInteger, AssetVersionType) {
    AssetVersionTypeResourcePack = 0, // Resource pack
    AssetVersionTypeDataPack = 1,     // Data pack
    AssetVersionTypeWorld = 2,        // World
};

@class AssetVersionViewController;

@protocol AssetVersionViewControllerDelegate <NSObject>
// Callback after the user selects a version.
- (void)assetVersionViewController:(AssetVersionViewController *)viewController
               didSelectVersion:(ModVersion *)version;
@end

@interface AssetVersionViewController : UIViewController

// Asset type (determines the title text, e.g. "Select resource-pack version").
@property (nonatomic, assign) AssetVersionType assetType;
// Modrinth/CurseForge ID of the online project.
@property (nonatomic, copy, nullable) NSString *projectID;
// Project display name (used as the navigation-bar title).
@property (nonatomic, copy, nullable) NSString *projectDisplayName;
// Proxy.
@property (nonatomic, weak, nullable) id<AssetVersionViewControllerDelegate> delegate;

// API source: 1 = Modrinth (default), 2 = CurseForge.
// Key fix (preserve source for CurseForge search results): the search-results page may come from
// CurseForge (numeric project ID). When opening the version page from search results, retain the
// search API source; otherwise the CurseForge numeric ID is sent to the Modrinth API and the version
// list cannot be fetched. Following ZL2, carry the platform enum through search → details → versions.
@property (nonatomic, assign) NSInteger apiSource;

// FCL style: pass the preferred version for the current profile.
// AssetVersionViewController selects the matching chip first and pins the matching version to the top.
// Note: asset types (resource packs/data packs/worlds) have no loader concept, so there is no preferredLoader.
// Phase 3 alignment: add the preferred property missing relative to ModVersionViewController.
@property (nonatomic, copy, nullable) NSString *preferredGameVersion;

// --- Project display information (for the details header, passed in by DownloadViewController) ---
// Fill in project cover/title/author/download-count/tag/description information missing from prior version pages.
@property (nonatomic, copy, nullable) NSString *projectIconURL;
@property (nonatomic, copy, nullable) NSString *projectAuthor;
@property (nonatomic, strong, nullable) NSNumber *projectDownloads;
@property (nonatomic, strong, nullable) NSNumber *projectLikes;
@property (nonatomic, copy, nullable) NSString *projectDescription;
@property (nonatomic, strong, nullable) NSArray<NSString *> *projectCategories;
@property (nonatomic, copy, nullable) NSString *projectLastUpdated;

@end

NS_ASSUME_NONNULL_END
