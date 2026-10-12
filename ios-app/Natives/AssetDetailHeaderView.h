//
//  AssetDetailHeaderView.h
//  Amethyst
//
//  Asset detail-page header view (modeled on the project-detail header design in FCL/ZL2)
//
//  Purpose: use as the tableView.tableHeaderView for ModVersionViewController /
//  ShaderVersionViewController / AssetVersionViewController to show full project information at the
//  top when the user opens the version-selection page:
//    - Project cover (72x72 rounded image, loaded with AFNetworking + placeholder SF Symbol)
//    - Project title (18pt bold, up to 2 lines)
//    - Author (with person.crop.circle icon)
//    - Metadata row: downloads / likes / last updated (with SF Symbol icons)
//    - Tag row: colored category pills (modeled on ZL2 LittleTextLabel)
//    - Description area: 3 lines by default, with a "Show more/Show less" button when it overflows
//
//  Design goals:
//    1. Fill the gap in "information + corresponding image" (version pages previously showed no
//       project information or cover image).
//    2. Match the appearance of ModernAssetCell / ModVersionTableViewCell (rounded card + light
//       shadow + frosted glass).
//    3. Support expanding/collapsing the description and notify the controller through the
//       onSizeChanged callback to update the tableHeaderView height.
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface AssetDetailHeaderView : UIView

/// Size-change callback (triggered when the description is expanded/collapsed; the controller
/// should recalculate tableHeaderView height here).
@property (nonatomic, copy, nullable) void (^onSizeChanged)(void);

/// Configure the header content.
/// @param iconURL Project cover image URL (may be nil; a placeholder SF Symbol is shown).
/// @param title Project title.
/// @param author Author (may be nil).
/// @param downloads Download count (may be nil).
/// @param likes Follower/like count (may be nil).
/// @param descriptionText Project description (may be nil).
/// @param categories Category/tag array (colored pills; may be nil).
/// @param lastUpdated Last-updated time (ISO8601 or any displayable string; may be nil).
/// @param placeholderSymbolName Placeholder SF Symbol name shown when there is no cover image
/// (e.g. "puzzlepiece.extension.fill").
/// @param placeholderColor Accent color for the placeholder icon (corresponds to the asset type).
- (void)configureWithIconURL:(nullable NSString *)iconURL
                       title:(NSString *)title
                      author:(nullable NSString *)author
                   downloads:(nullable NSNumber *)downloads
                       likes:(nullable NSNumber *)likes
             descriptionText:(nullable NSString *)descriptionText
                 categories:(nullable NSArray<NSString *> *)categories
                lastUpdated:(nullable NSString *)lastUpdated
        placeholderSymbolName:(NSString *)placeholderSymbolName
            placeholderColor:(UIColor *)placeholderColor;

/// Calculate and return the header's fitting height at the specified width (for the tableHeaderView frame).
/// @param width Target width (usually tableView.bounds.size.width).
- (CGFloat)fittingHeightForWidth:(CGFloat)width;

@end

NS_ASSUME_NONNULL_END
