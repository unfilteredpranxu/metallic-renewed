//
//  ModTableViewCell.h
//  Amethyst
//
//  Mod card cell (inherits ResourceCardTableViewCell, Air-Design L2 standard card).
//  The base class provides the card background, corner radius, shadow, icon container, text hierarchy, and accessory slot.
//  This class handles only mod-specific icons (embedded JAR icons / loader brand icons),
//  ModItem content configuration, the enable switch, update badge, and online-mode buttons.
//

#import <UIKit/UIKit.h>
#import "ResourceCardTableViewCell.h"

@class ModItem;

NS_ASSUME_NONNULL_BEGIN

// Display mode for the cell
typedef NS_ENUM(NSInteger, ModTableViewCellDisplayMode) {
    ModTableViewCellDisplayModeLocal,
    ModTableViewCellDisplayModeOnline
};

@protocol ModTableViewCellDelegate <NSObject>
- (void)modCellDidTapToggle:(UITableViewCell *)cell;
- (void)modCellDidTapOpenLink:(UITableViewCell *)cell;
@optional // Optional because it's only for online mode
- (void)modCellDidTapDownload:(UITableViewCell *)cell;
@end

@interface ModTableViewCell : ResourceCardTableViewCell

// --- Configuration ---
- (void)configureWithMod:(ModItem *)mod displayMode:(ModTableViewCellDisplayMode)mode;

// --- State Updates ---
/// Synchronizes the enabled-switch state (when disabled=YES, turns the switch off and reduces card-content opacity).
- (void)updateToggleState:(BOOL)disabled;

/// Shows/hides the update badge (arrow.up.circle.fill in the accent color, set by the management page after checking for updates).
- (void)setUpdateAvailable:(BOOL)available;

@property (nonatomic, weak) id<ModTableViewCellDelegate> delegate;

@end

NS_ASSUME_NONNULL_END
