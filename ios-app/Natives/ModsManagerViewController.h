//
//  ModsManagerViewController.h
//  Amethyst
//
//  Mod management page (inherits from ResourceListViewController).
//  The base class provides a blur background, pill-shaped search bar, card table, empty/loading states,
//  bottom toolbar for batch selection, and cascading entrance animation.
//  This class handles loading mod data; filtering (all/enabled/disabled) and sorting;
//  batch enable/disable/delete; and built-in update checking and download replacement.
//

#import "ResourceListViewController.h"

NS_ASSUME_NONNULL_BEGIN

@interface ModsManagerViewController : ResourceListViewController

/// Target profile name (nil is treated as default).
@property (nonatomic, copy, nullable) NSString *profileName;

@end

NS_ASSUME_NONNULL_END
