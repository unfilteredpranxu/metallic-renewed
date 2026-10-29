#import <UIKit/UIKit.h>
#import "PLPrefTableViewController.h"

@interface LauncherPreferencesViewController : PLPrefTableViewController <UIImagePickerControllerDelegate, UINavigationControllerDelegate, UIColorPickerViewControllerDelegate>

@property(nonatomic) BOOL referenceContentMode;
@end

@interface MetallicSettingsContainerViewController : UIViewController
- (void)selectCategory:(NSInteger)index;
@property(nonatomic, strong, readonly) LauncherPreferencesViewController *preferences;
@end
