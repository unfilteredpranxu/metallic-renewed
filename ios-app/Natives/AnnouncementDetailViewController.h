//
//  AnnouncementDetailViewController.h
//  Amethyst
//
//  Announcement detail view controller
//  - Large title at the top + small gray date
//  - Body rendered as an NSAttributedString using UITextView + MarkdownParser
//  - If the announcement has an actionURL, show a button at the bottom (opened with SFSafariViewController)
//

#import <UIKit/UIKit.h>

@class AnnouncementItem;

NS_ASSUME_NONNULL_BEGIN

@interface AnnouncementDetailViewController : UIViewController

/// Create the detail page for the specified announcement.
- (instancetype)initWithAnnouncement:(AnnouncementItem *)item;

@end

NS_ASSUME_NONNULL_END
