#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface HomeActionPanelView : UIView

@property (nonatomic, readonly) BOOL expanded;
/// Presentation-only hook: ensure the panel's existing owner is visible before expansion.
@property (nonatomic, copy, nullable) void (^onWillExpand)(void);
@property (nonatomic, strong, readonly) UIImageView *avatarView;
@property (nonatomic, strong, readonly) UIButton *toggleButton;
@property (nonatomic, strong, readonly) UIButton *launchButton;
@property (nonatomic, strong, readonly) UIButton *executeJarButton;
@property (nonatomic, strong, readonly) UIButton *chooseVersionButton;
@property (nonatomic, strong, readonly) UIButton *loginButton;
@property (nonatomic, copy, nullable) void (^onProfileTap)(void);
@property (nonatomic, copy, nullable) void (^onLoginTap)(void);
/// The owner's top-edge constraint. The panel moves it so it opens lower (below the nav bar)
/// and returns to the corner when collapsed.
@property (nonatomic, weak, nullable) NSLayoutConstraint *topOffsetConstraint;
/// Horizontal row shown at the top of the expanded panel. The home screen puts the JIT status
/// and download-center chips in here (arranged subviews fill the row height).
@property (nonatomic, strong, readonly) UIStackView *chipRow;
/// Overlay host for small badges that should float over the chips (e.g. the download count).
@property (nonatomic, strong, readonly) UIView *badgeLayer;

- (void)setExpanded:(BOOL)expanded animated:(BOOL)animated;
- (void)setProfileName:(nullable NSString *)name avatar:(nullable UIImage *)avatar;
- (void)setLauncherVersion:(nullable NSString *)launcher
               gameVersion:(nullable NSString *)game
                    device:(nullable NSString *)device;

@end

NS_ASSUME_NONNULL_END
