//
//  AnnouncementListViewController.h
//  Amethyst
//
//  Announcement list view controller
//  A simplified implementation inspired by the waterfall card style of MinecraftNewsViewController:
//  - Two-column UICollectionViewCompositionalLayout
//  - Each cell displays a title, date, and summary
//  - Cards with priority=high have a blue bar on the left
//  - Tapping opens AnnouncementDetailViewController
//  - Supports pull-to-refresh and forced refresh from the top-right corner
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface AnnouncementListViewController : UIViewController

@end

NS_ASSUME_NONNULL_END
