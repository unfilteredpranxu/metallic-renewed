//
//  ModLoaderIconHelper.h
//  Amethyst
//
//  Unified mod-loader icon helper.
//  Based on the FCL/ZL2 loader-icon system, unifying three parallel loader representations in the project:
//   1. PNG images (ModLoaderIcons/ directory; dark/light variants exist for fabric/forge/neoforge).
//   2. SF Symbols (used by VersionManagerViewController/ModLoaderInstallViewController, with inconsistent colors).
//   3. Text-only pill badges (ModVersionTableViewCell/ShaderVersionTableViewCell/AssetDetailHeaderView/DownloadViewController).
//  This helper provides a single entry point for all three, preferring official PNG icons in the bundle;
//  when unavailable, it falls back to an SF Symbol similar in shape to the official logo + the official brand color for visual consistency.
//
// Loader brand colors are based on each loader's official brand guidelines:
//   fabric   = #5B8DF9 (official blue)
//   quilt    = #D668AC (official purple-pink)
//   forge    = #8B5A2B (official brown)
//   neoforge = #E0732B (official orange)
//   optifine = #E6991A (official yellow)
//   iris     = #4DA6F2 (official light blue)
//   rift     = #33B280 (official green)
//   vanilla  = #66CC66 (vanilla green)
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface ModLoaderIconHelper : NSObject

/// Gets the official brand color for a loader name (shared color mapping across the project).
/// Supports keywords such as fabric/quilt/forge/neoforge/optifine/optifabric/iris/rift/vanilla.
/// @param loader Loader name (case-insensitive; supports substring matches, e.g. "fabric-loader").
/// @return Official brand color; returns the system secondary label color if unrecognized.
+ (UIColor *)brandColorForLoader:(NSString *)loader;

/// Gets the SF Symbol name for a loader (a symbol similar in shape to its official logo).
/// Used as a fallback when the bundle has no corresponding PNG.
+ (NSString *)symbolNameForLoader:(NSString *)loader;

/// Gets the localized display name for a loader (used as badge text).
+ (NSString *)displayNameForLoader:(NSString *)loader;

/// Loads a loader icon (prefers bundle PNG, falls back to SF Symbol).
/// Automatically chooses a dark/light theme PNG based on traitCollection's userInterfaceStyle.
/// @param loader Loader name.
/// @param traitCollection Current interface traitCollection (used to determine appearance); nil defaults to light.
/// @return Loader icon UIImage (PNG or SF Symbol), or nil if unrecognized.
+ (nullable UIImage *)iconImageForLoader:(NSString *)loader
                         traitCollection:(nullable UITraitCollection *)traitCollection;

/// Configures a UIImageView to display a loader icon.
/// Automatically sets image, tintColor (tinted for SF Symbols, not for PNGs to preserve original colors), and contentMode.
/// @param imageView UIImageView to configure.
/// @param loader Loader name.
/// @param traitCollection Current traitCollection.
+ (void)configureImageView:(UIImageView *)imageView
                forLoader:(NSString *)loader
           traitCollection:(nullable UITraitCollection *)traitCollection;

/// Creates a loader badge view (icon + text pill, based on FCL/ZL2 loader labels).
/// Prefers a PNG icon; text uses displayNameForLoader:.
/// @param loader Loader name.
/// @param traitCollection Current traitCollection.
/// @return Configured UIView (icon and text arranged horizontally).
+ (UIView *)createBadgeViewForLoader:(NSString *)loader
                      traitCollection:(nullable UITraitCollection *)traitCollection;

/// Creates an icon-only badge (no text, just an icon + brand-colored rounded background; based on ZL2 LittleTextLabel).
/// Used where space is limited (e.g. small loader icons on the right side of a version row).
/// @param loader Loader name.
/// @param traitCollection Current traitCollection.
/// @param size Icon size (defaults to 18pt).
+ (UIView *)createIconBadgeForLoader:(NSString *)loader
                      traitCollection:(nullable UITraitCollection *)traitCollection
                                size:(CGFloat)size;

/// Determines whether a loader name is known (used to filter display).
+ (BOOL)isKnownLoader:(NSString *)loader;

/// Identifies the loader type from a version ID string.
/// For example, "1.20.1-Fabric-0.15.7" → "fabric", "1.20.1-forge-47.2.0" → "forge".
+ (nullable NSString *)detectLoaderFromVersionId:(NSString *)versionId;

@end

NS_ASSUME_NONNULL_END
