#import <UIKit/UIKit.h>

// FCL-style left sidebar — feature menu.

@interface LauncherMenuViewController : UIViewController

// Menu-item tap callback.
@property(nonatomic, copy) void (^onMenuItemSelected)(NSInteger index, NSString *title);

// Refresh account information.
- (void)updateAccountInfo;

@end
