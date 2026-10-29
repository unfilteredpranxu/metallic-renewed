//
//  BackgroundSettingsViewController.h
//  Amethyst
//
//  Background wallpaper settings view controller
//

#import <UIKit/UIKit.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import <Photos/Photos.h>
#import <AVFoundation/AVFoundation.h>
#import "BackgroundManager.h"

NS_ASSUME_NONNULL_BEGIN

@interface BackgroundSettingsViewController : UITableViewController <UIImagePickerControllerDelegate, UINavigationControllerDelegate, UIDocumentPickerDelegate>

@property(nonatomic) BOOL launcherPresentation;
@property(nonatomic) NSInteger themeIndex;
@property(nonatomic, copy, nullable) void (^themeSelection)(NSInteger index);
@end

@interface MetallicAppearanceContainerViewController : UIViewController
@property(nonatomic, strong) BackgroundSettingsViewController *appearance;
@end
NS_ASSUME_NONNULL_END
