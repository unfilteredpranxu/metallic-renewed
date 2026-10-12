//
//  AISessionListViewController.h
//  Amethyst
//
//  AI session list: displays all historical sessions (sorted by update time, with pinned sessions first),
//  supports search, swipe-to-delete, and new sessions; tapping a session returns it to the caller via callback.
//

#import <UIKit/UIKit.h>
#import "AiSession.h"

NS_ASSUME_NONNULL_BEGIN

@interface AISessionListViewController : UIViewController

/// Callback when a session is tapped
@property (nonatomic, copy, nullable) void (^onSelectSession)(AiSession *session);
/// Callback after a new session is created
@property (nonatomic, copy, nullable) void (^onNewSession)(AiSession *session);

@end

NS_ASSUME_NONNULL_END