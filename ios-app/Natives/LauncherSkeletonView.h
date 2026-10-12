//
//  LauncherSkeletonView.h
//  Amethyst
//
//  List skeleton screen: show placeholder shapes in the list area while loading asynchronously, instead of an unresponsive blank area or spinner.
//  Uses only UIKit + QuartzCore; no third-party dependencies.
//
//  Usage:
//      self.skeleton = [LauncherSkeletonView attachToView:self.modTableView
//                                                   style:LauncherSkeletonStyleList];
//      [self.skeleton showSkeleton];   // When the request starts.
//      [self.skeleton hideSkeleton];   // Hide on either success or failure.
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// Skeleton placeholder style.
typedef NS_ENUM(NSInteger, LauncherSkeletonStyle) {
    /// List-row style (mods / shaders / resource packs / data packs / modpacks / worlds / version lists).
    LauncherSkeletonStyleList = 0,
    /// Card-grid style (card flow used by version lists).
    LauncherSkeletonStyleCardGrid,
};

/// Skeleton placeholder layer overlaid on a list view.
///
/// Note: the skeleton layer itself does not receive touches (userInteractionEnabled = NO),
/// so it does not interfere with list scrolling or pull-to-refresh.
@interface LauncherSkeletonView : UIView

/// Whether the skeleton is currently visible (read-only).
@property (nonatomic, assign, readonly, getter=isSkeletonVisible) BOOL skeletonVisible;

/// Create the skeleton layer over hostView (align all edges; its constraints follow hostView automatically).
/// @return nil if hostView is nil.
+ (nullable instancetype)attachToView:(UIView *)hostView style:(LauncherSkeletonStyle)style;

/// Show the skeleton (fade in + breathing animation).
- (void)showSkeleton;

/// Hide the skeleton (fade out; safe to call repeatedly).
- (void)hideSkeleton;

/// Hide immediately and stop animations (cleanup before destroying the list).
- (void)hideSkeletonImmediately;

@end

NS_ASSUME_NONNULL_END
