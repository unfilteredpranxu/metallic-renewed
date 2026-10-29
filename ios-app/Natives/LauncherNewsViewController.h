#import <UIKit/UIKit.h>

// MARK: - Tile Type & Size Enums

typedef NS_ENUM(NSInteger, HomeTileType) {
    HomeTileTypeProfile = 0,
    HomeTileTypeAnnouncement,
    HomeTileTypeVersionRelease,
    HomeTileTypeVersionSnapshot,
    HomeTileTypeNews,
    HomeTileTypeShortcut,
};

// ★ [FIX511] When rebasing to 5.1.0, this header was mistakenly replaced with the upstream two-size enum, dropping
//   the fork's [SIZE4] four-span enum and four helper prototypes. LauncherNewsViewController.m /
//   HomeCustomizeViewController.m in tree510 use the four-size symbols, which caused
//   "use of undeclared identifier 'HomeTileSizeSmall' / no prototype for AmeTileSizeShortName".
//   Restored the full block from the fork (same-value aliases keep old Compact/Full call sites unchanged).
typedef NS_ENUM(NSInteger, HomeTileSize) {
    HomeTileSizeSmall   = 0,   // 1×1 (formerly HomeTileSizeCompact).
    HomeTileSizeWide    = 1,   // 2×1 (formerly HomeTileSizeFull).
    HomeTileSizeTall    = 2,   // 1×2
    HomeTileSizeLarge   = 3,   // 2×2

    HomeTileSizeCompact = HomeTileSizeSmall,  // ★ [SIZE4] Alias for the old symbol (same value).
    HomeTileSizeFull    = HomeTileSizeWide,   // ★ [SIZE4] Alias for the old symbol (same value).
};

// ★ [SIZE4] Span / name helpers (implemented in LauncherNewsViewController.m).
NSInteger AmeTileSpanColumns(HomeTileSize size);    // Column span: Small/Tall ⇒ 1, Wide/Large ⇒ 2.
NSInteger AmeTileSpanRows(HomeTileSize size);       // Row span: Small/Wide ⇒ 1, Tall/Large ⇒ 2.
NSString *AmeTileSizeShortName(HomeTileSize size);  // "1×1"/"2×1"/"1×2"/"2×2" (geometric; does not need localization).
NSString *AmeTileSizeDisplayName(HomeTileSize size);// Localized name (Half Width / Full Width / Tall / Large).

// MARK: - HomeTileConfig

@interface HomeTileConfig : NSObject <NSSecureCoding>

@property (nonatomic, copy) NSString *tileId;
@property (nonatomic, assign) HomeTileType tileType;
@property (nonatomic, assign) HomeTileSize tileSize;
@property (nonatomic, assign) BOOL visible;
@property (nonatomic, copy) NSString *customTitle;
@property (nonatomic, copy) NSString *iconName;
@property (nonatomic, copy) NSString *accentColorHex;
@property (nonatomic, copy) NSString *shortcutAction;  // For HomeTileTypeShortcut

+ (NSArray<HomeTileConfig *> *)defaultTileConfigs;
+ (NSArray<HomeTileConfig *> *)loadSavedConfigs;
+ (void)saveConfigs:(NSArray<HomeTileConfig *> *)configs;
- (UIColor *)accentColor;
- (NSDictionary *)toDictionary;
+ (instancetype)fromDictionary:(NSDictionary *)dict;

@end

// MARK: - Shortcut Action Constants

extern NSString * const kShortcutActionMods;
extern NSString * const kShortcutActionShaders;
extern NSString * const kShortcutActionModpack;
extern NSString * const kShortcutActionBackground;
extern NSString * const kShortcutActionVersions;
extern NSString * const kShortcutActionMultiplayer;   // ★ [MP-RESTORE] Multiplayer shortcut entry.

// MARK: - LauncherNewsViewController

@interface LauncherNewsViewController : UIViewController
- (void)openCustomize; // Existing editor and saved-layout callbacks.

@end
