//
//  AIViewController.h
//  Amethyst
//
//  AI chat main interface. Displays session messages and the input bar, and handles AiAgent interaction and streaming updates.
//

#import <UIKit/UIKit.h>
#import "AiSession.h"

NS_ASSUME_NONNULL_BEGIN

@interface AIViewController : UIViewController

/// Specified session; if nil, AiSessionStore creates one
- (instancetype)initWithSession:(nullable AiSession *)session;

@end

NS_ASSUME_NONNULL_END