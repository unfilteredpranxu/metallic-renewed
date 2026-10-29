#import <UIKit/UIKit.h>
#import "PLPrefTableViewController.h"

@interface LauncherPreferencesViewController : PLPrefTableViewController <UIImagePickerControllerDelegate, UINavigationControllerDelegate, UIColorPickerViewControllerDelegate>

@property(nonatomic) BOOL referenceContentMode;
@end

@interface MetallicSettingsContainerViewController : UIViewController
@property(nonatomic, strong, readonly) LauncherPreferencesViewController *preferences;
@end
