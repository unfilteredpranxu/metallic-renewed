//
//  ModLoaderIconHelper.m
//  Amethyst
//
//  Implementation of the unified mod-loader icon helper.
//  Based on the FCL/ZL2 loader-icon system, unifying three parallel loader representations in the project.
//

#import "ModLoaderIconHelper.h"

@implementation ModLoaderIconHelper

#pragma mark - Brand colors

/// Unified loader brand-color mapping (shared project-wide to eliminate color inconsistencies across files).
/// Colors are based on each loader's official brand guidelines and match those used by FCL/ZL2.
+ (UIColor *)brandColorForLoader:(NSString *)loader {
    if (!loader || loader.length == 0) {
        return [UIColor tertiaryLabelColor];
    }
    NSString *lower = loader.lowercaseString;

    // Order matters: check neoforge before forge (neoforge contains the substring forge).
    // Check optifabric before optifine (optifabric contains the substring optifine).
    if ([lower containsString:@"neoforge"]) {
        // NeoForge official orange #E0732B.
        return [UIColor colorWithRed:0.88 green:0.45 blue:0.17 alpha:1.0];
    }
    if ([lower containsString:@"forge"]) {
        // Forge official brown #8B5A2B.
        return [UIColor colorWithRed:0.55 green:0.35 blue:0.20 alpha:1.0];
    }
    if ([lower containsString:@"optifabric"]) {
        // OptiFabric and OptiFine share the same color family.
        return [UIColor colorWithRed:0.90 green:0.60 blue:0.10 alpha:1.0];
    }
    if ([lower containsString:@"optifine"]) {
        // OptiFine official yellow #E6991A.
        return [UIColor colorWithRed:0.90 green:0.60 blue:0.10 alpha:1.0];
    }
    if ([lower containsString:@"quilt"]) {
        // Quilt official purple-pink #D668AC.
        return [UIColor colorWithRed:0.84 green:0.41 blue:0.67 alpha:1.0];
    }
    if ([lower containsString:@"fabric"]) {
        // Fabric official blue #5B8DF9.
        return [UIColor colorWithRed:0.18 green:0.55 blue:0.95 alpha:1.0];
    }
    if ([lower containsString:@"iris"]) {
        // Iris official light blue #4DA6F2.
        return [UIColor colorWithRed:0.30 green:0.65 blue:0.95 alpha:1.0];
    }
    if ([lower containsString:@"rift"]) {
        // Rift official green #33B280.
        return [UIColor colorWithRed:0.20 green:0.70 blue:0.50 alpha:1.0];
    }
    if ([lower containsString:@"vanilla"]) {
        // Vanilla green #66CC66.
        return [UIColor colorWithRed:0.40 green:0.80 blue:0.40 alpha:1.0];
    }
    // Unrecognized: return the system secondary label color (gray) as a fallback.
    return [UIColor tertiaryLabelColor];
}

#pragma mark - SF Symbol names

/// SF Symbol name for a loader (similar in shape to the official logo).
/// Used only as a fallback when the bundle has no corresponding PNG.
+ (NSString *)symbolNameForLoader:(NSString *)loader {
    if (!loader || loader.length == 0) {
        return @"cube.box.fill";
    }
    NSString *lower = loader.lowercaseString;

    // Keep the check order consistent with brandColorForLoader.
    if ([lower containsString:@"neoforge"]) {
        // NeoForge: hammer shape (the official logo is a hammer).
        return @"hammer.fill";
    }
    if ([lower containsString:@"forge"]) {
        // Forge: anvil shape (the official logo is an anvil).
        return @"anvil.fill";
    }
    if ([lower containsString:@"optifabric"] || [lower containsString:@"optifine"]) {
        // OptiFine: eye shape (the official logo is an eye).
        return @"eye.fill";
    }
    if ([lower containsString:@"quilt"]) {
        // Quilt: hexagonal grid (the official logo is a patchwork pattern).
        return @"circle.hexagongrid.fill";
    }
    if ([lower containsString:@"fabric"]) {
        // Fabric: lightning/star (the official logo is a loom; no SF Symbol matches exactly, so use a similar one).
        return @"wand.and.stars";
    }
    if ([lower containsString:@"iris"]) {
        // Iris: rainbow/circle (the official logo is a rainbow eye).
        return @"circle.lefthalf.filled";
    }
    if ([lower containsString:@"rift"]) {
        // Rift: lightning (the official logo is a rift/lightning bolt).
        return @"bolt.fill";
    }
    if ([lower containsString:@"vanilla"]) {
        // Vanilla: cube (vanilla block).
        return @"cube.fill";
    }
    // Default: cube box.
    return @"cube.box.fill";
}

#pragma mark - Display name

/// Localized display name for a loader (used as badge text).
+ (NSString *)displayNameForLoader:(NSString *)loader {
    if (!loader || loader.length == 0) {
        return @"Unknown";
    }
    NSString *lower = loader.lowercaseString;

    if ([lower containsString:@"neoforge"])   return @"NeoForge";
    if ([lower containsString:@"forge"])      return @"Forge";
    if ([lower containsString:@"optifabric"]) return @"OptiFabric";
    if ([lower containsString:@"optifine"])   return @"OptiFine";
    if ([lower containsString:@"quilt"])      return @"Quilt";
    if ([lower containsString:@"fabric"])     return @"Fabric";
    if ([lower containsString:@"iris"])       return @"Iris";
    if ([lower containsString:@"rift"])       return @"Rift";
    if ([lower containsString:@"vanilla"])    return @"Vanilla";

    // Unknown loader: return it with the first letter capitalized.
    if (loader.length > 0) {
        NSString *firstChar = [[loader substringToIndex:1] uppercaseString];
        NSString *rest = [loader substringFromIndex:1];
        return [NSString stringWithFormat:@"%@%@", firstChar, rest];
    }
    return @"Unknown";
}

#pragma mark - Load icon

/// Loads a loader icon (prefers bundle PNG, falls back to SF Symbol).
/// Loading order:
///   1. ModLoaderIcons/{key}.png (HMCL official standard single file, not appearance-specific, transparent PNG in brand color).
///   2. ModLoaderIcons/{key}_{light|dark}.png (legacy format, appearance-specific).
///   3. SF Symbol tinted with the brand color (fallback).
+ (UIImage *)iconImageForLoader:(NSString *)loader
                 traitCollection:(UITraitCollection *)traitCollection {
    if (!loader || loader.length == 0) {
        return [UIImage systemImageNamed:@"cube.box.fill"];
    }

    // Vanilla: use the grass-block VanillaIcon from Assets.xcassets.
    // Matches the vanilla icon in VersionCardCell (the standard grass block included in the HMCL repository).
    if ([loader.lowercaseString containsString:@"vanilla"]) {
        UIImage *vanillaIcon = [UIImage imageNamed:@"VanillaIcon"];
        if (vanillaIcon) {
            return vanillaIcon;
        }
        // If VanillaIcon fails to load, fall back to an SF Symbol.
        return [UIImage systemImageNamed:@"cube.fill"];
    }

    // Extract the normalized loader name (used to match PNG filenames).
    NSString *pngKey = [self pngKeyForLoader:loader];
    if (pngKey) {
        NSBundle *bundle = [NSBundle mainBundle];
        NSString *resourcePath = [bundle resourcePath];

        // 1. Prefer the HMCL official standard single file (not appearance-specific).
        NSString *standardPath = [resourcePath stringByAppendingPathComponent:
                                  [NSString stringWithFormat:@"ModLoaderIcons/%@.png", pngKey]];
        UIImage *image = [UIImage imageWithContentsOfFile:standardPath];
        if (image) {
            return image;
        }

        // 2. Fall back to the legacy format (appearance-specific light/dark).
        BOOL isDarkMode = NO;
        if (traitCollection) {
            isDarkMode = (traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark);
        }
        NSString *theme = isDarkMode ? @"dark" : @"light";
        NSString *themedPath = [resourcePath stringByAppendingPathComponent:
                                [NSString stringWithFormat:@"ModLoaderIcons/%@_%@.png", pngKey, theme]];
        image = [UIImage imageWithContentsOfFile:themedPath];
        if (image) {
            return image;
        }
        // Try the opposite appearance.
        theme = isDarkMode ? @"light" : @"dark";
        themedPath = [resourcePath stringByAppendingPathComponent:
                      [NSString stringWithFormat:@"ModLoaderIcons/%@_%@.png", pngKey, theme]];
        image = [UIImage imageWithContentsOfFile:themedPath];
        if (image) {
            return image;
        }
    }

    // 3. No PNG or loading failed: fall back to an SF Symbol.
    NSString *symbolName = [self symbolNameForLoader:loader];
    UIImage *symbolImage = [UIImage systemImageNamed:symbolName];
    return symbolImage ?: [UIImage systemImageNamed:@"cube.box.fill"];
}

/// Converts a loader name to a PNG filename key (e.g. "fabric-loader" → "fabric").
/// Used to match PNG files in the ModLoaderIcons/ directory.
+ (nullable NSString *)pngKeyForLoader:(NSString *)loader {
    if (!loader || loader.length == 0) return nil;
    NSString *lower = loader.lowercaseString;

    // Order matters: check neoforge before forge, and optifabric before optifine.
    if ([lower containsString:@"neoforge"])   return @"neoforge";
    if ([lower containsString:@"forge"])      return @"forge";
    if ([lower containsString:@"optifabric"]) return @"optifine"; // Shares icon with OptiFine.
    if ([lower containsString:@"optifine"])   return @"optifine"; // HMCL official PNG.
    if ([lower containsString:@"quilt"])      return @"quilt";    // HMCL official PNG.
    if ([lower containsString:@"fabric"])     return @"fabric";
    if ([lower containsString:@"iris"])       return nil; // No official PNG yet; fall back to SF Symbol.
    if ([lower containsString:@"rift"])       return nil; // No official PNG yet; fall back to SF Symbol.
    if ([lower containsString:@"vanilla"])    return nil; // Use VanillaIcon from Assets.xcassets.
    return nil;
}

#pragma mark - UIImageView configuration

/// Configures a UIImageView to display a loader icon.
/// PNG icons retain their original colors; SF Symbols are tinted with the brand color.
+ (void)configureImageView:(UIImageView *)imageView
                forLoader:(NSString *)loader
           traitCollection:(UITraitCollection *)traitCollection {
    if (!imageView) return;

    UIImage *image = [self iconImageForLoader:loader traitCollection:traitCollection];
    imageView.image = image;
    imageView.contentMode = UIViewContentModeScaleAspectFit;

    // Do not tint PNGs or VanillaIcon; tint SF Symbols.
    // Vanilla uses the grass-block icon from Assets.xcassets and retains its original colors.
    if ([loader.lowercaseString containsString:@"vanilla"]) {
        imageView.tintColor = nil;
        return;
    }

    // Match iconImageForLoader's loading order: standard single file first, then appearance-specific file.
    NSString *pngKey = [self pngKeyForLoader:loader];
    BOOL hasPng = NO;
    if (pngKey) {
        NSBundle *bundle = [NSBundle mainBundle];
        NSString *resourcePath = [bundle resourcePath];
        // 1. Check the HMCL official standard single file first.
        NSString *standardPath = [resourcePath stringByAppendingPathComponent:
                                  [NSString stringWithFormat:@"ModLoaderIcons/%@.png", pngKey]];
        if ([NSFileManager.defaultManager fileExistsAtPath:standardPath]) {
            hasPng = YES;
        } else {
            // 2. Then check the legacy appearance-specific file.
            BOOL isDarkMode = traitCollection ? (traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark) : NO;
            NSString *theme = isDarkMode ? @"dark" : @"light";
            NSString *themedPath = [resourcePath stringByAppendingPathComponent:
                                    [NSString stringWithFormat:@"ModLoaderIcons/%@_%@.png", pngKey, theme]];
            if ([NSFileManager.defaultManager fileExistsAtPath:themedPath]) {
                hasPng = YES;
            } else {
                theme = isDarkMode ? @"light" : @"dark";
                themedPath = [resourcePath stringByAppendingPathComponent:
                              [NSString stringWithFormat:@"ModLoaderIcons/%@_%@.png", pngKey, theme]];
                if ([NSFileManager.defaultManager fileExistsAtPath:themedPath]) {
                    hasPng = YES;
                }
            }
        }
    }

    if (hasPng) {
        // PNG icon: preserve original colors; do not tint.
        imageView.tintColor = nil;
    } else {
        // SF Symbol: tint with the brand color.
        imageView.tintColor = [self brandColorForLoader:loader];
    }
}

#pragma mark - Badge views

/// Creates a loader badge view (icon + text pill, based on FCL/ZL2 loader labels).
/// Uses a translucent brand-color rounded background, icon, and white text.
+ (UIView *)createBadgeViewForLoader:(NSString *)loader
                      traitCollection:(UITraitCollection *)traitCollection {
    UIView *container = [[UIView alloc] init];
    container.translatesAutoresizingMaskIntoConstraints = NO;

    UIColor *brandColor = [self brandColorForLoader:loader];

    // Rounded background.
    container.backgroundColor = [brandColor colorWithAlphaComponent:0.18];
    container.layer.cornerRadius = 8;
    container.layer.cornerCurve = kCACornerCurveContinuous;
    container.layer.borderWidth = 0.5;
    container.layer.borderColor = [brandColor colorWithAlphaComponent:0.35].CGColor;

    // Icon.
    UIImageView *iconView = [[UIImageView alloc] init];
    iconView.translatesAutoresizingMaskIntoConstraints = NO;
    [self configureImageView:iconView forLoader:loader traitCollection:traitCollection];
    [container addSubview:iconView];

    // Text.
    UILabel *label = [[UILabel alloc] init];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    label.text = [self displayNameForLoader:loader];
    label.font = [UIFont systemFontOfSize:10 weight:UIFontWeightSemibold];
    label.textColor = brandColor;
    label.textAlignment = NSTextAlignmentCenter;
    [container addSubview:label];

    [NSLayoutConstraint activateConstraints:@[
        [iconView.leadingAnchor constraintEqualToAnchor:container.leadingAnchor constant:6],
        [iconView.centerYAnchor constraintEqualToAnchor:container.centerYAnchor],
        [iconView.widthAnchor constraintEqualToConstant:12],
        [iconView.heightAnchor constraintEqualToConstant:12],

        [label.leadingAnchor constraintEqualToAnchor:iconView.trailingAnchor constant:3],
        [label.trailingAnchor constraintEqualToAnchor:container.trailingAnchor constant:-6],
        [label.topAnchor constraintEqualToAnchor:container.topAnchor constant:3],
        [label.bottomAnchor constraintEqualToAnchor:container.bottomAnchor constant:-3],

        [iconView.topAnchor constraintEqualToAnchor:container.topAnchor constant:3],
        [iconView.bottomAnchor constraintEqualToAnchor:container.bottomAnchor constant:-3],
    ]];

    return container;
}

/// Creates an icon-only badge (no text, just an icon + brand-colored rounded background).
/// Used where space is limited (e.g. small loader icons on the right side of a version row).
+ (UIView *)createIconBadgeForLoader:(NSString *)loader
                      traitCollection:(UITraitCollection *)traitCollection
                                size:(CGFloat)size {
    UIView *container = [[UIView alloc] init];
    container.translatesAutoresizingMaskIntoConstraints = NO;

    UIColor *brandColor = [self brandColorForLoader:loader];

    // Rounded background.
    container.backgroundColor = [brandColor colorWithAlphaComponent:0.15];
    container.layer.cornerRadius = size / 3.0;
    container.layer.cornerCurve = kCACornerCurveContinuous;

    // Icon.
    UIImageView *iconView = [[UIImageView alloc] init];
    iconView.translatesAutoresizingMaskIntoConstraints = NO;
    [self configureImageView:iconView forLoader:loader traitCollection:traitCollection];
    [container addSubview:iconView];

    CGFloat iconSize = size * 0.62;
    [NSLayoutConstraint activateConstraints:@[
        [container.widthAnchor constraintEqualToConstant:size],
        [container.heightAnchor constraintEqualToConstant:size],

        [iconView.centerXAnchor constraintEqualToAnchor:container.centerXAnchor],
        [iconView.centerYAnchor constraintEqualToAnchor:container.centerYAnchor],
        [iconView.widthAnchor constraintEqualToConstant:iconSize],
        [iconView.heightAnchor constraintEqualToConstant:iconSize],
    ]];

    return container;
}

#pragma mark - Utility methods

/// Determines whether a loader name is known (used to filter display).
+ (BOOL)isKnownLoader:(NSString *)loader {
    if (!loader || loader.length == 0) return NO;
    NSString *lower = loader.lowercaseString;
    if ([lower containsString:@"fabric"])     return YES;
    if ([lower containsString:@"quilt"])      return YES;
    if ([lower containsString:@"forge"])      return YES;
    if ([lower containsString:@"neoforge"])   return YES;
    if ([lower containsString:@"optifine"])   return YES;
    if ([lower containsString:@"optifabric"]) return YES;
    if ([lower containsString:@"iris"])       return YES;
    if ([lower containsString:@"rift"])       return YES;
    if ([lower containsString:@"vanilla"])    return YES;
    return NO;
}

/// Identifies the loader type from a version ID string.
/// For example, "1.20.1-Fabric-0.15.7" → "fabric", "1.20.1-forge-47.2.0" → "forge".
+ (NSString *)detectLoaderFromVersionId:(NSString *)versionId {
    if (!versionId || versionId.length == 0) return nil;
    NSString *lower = [versionId lowercaseString];

    // Order matters: check neoforge before forge.
    if ([lower containsString:@"neoforge"])   return @"neoforge";
    if ([lower containsString:@"forge"])      return @"forge";
    if ([lower containsString:@"optifabric"]) return @"optifabric";
    if ([lower containsString:@"optifine"])   return @"optifine";
    if ([lower containsString:@"quilt"])      return @"quilt";
    if ([lower containsString:@"fabric"])     return @"fabric";
    if ([lower containsString:@"iris"])       return @"iris";
    if ([lower containsString:@"rift"])       return @"rift";
    return nil;
}

@end
