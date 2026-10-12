#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface HomeActionPanelView : UIView

@property (nonatomic, readonly) BOOL expanded;
@property (nonatomic, strong, readonly) UIImageView *avatarView;
@property (nonatomic, strong, readonly) UIButton *toggleButton;
@property (nonatomic, strong, readonly) UIButton *launchButton;
@property (nonatomic, strong, readonly) UIButton *executeJarButton;
@property (nonatomic, strong, readonly) UIButton *chooseVersionButton;

- (void)setExpanded:(BOOL)expanded animated:(BOOL)animated;

- (void)setLauncherVersion:(nullable NSString *)launcher
               gameVersion:(nullable NSString *)game
                                   device:(nullable NSString *)device;

                                   @end

                                   NS_ASSUME_NONNULL_END