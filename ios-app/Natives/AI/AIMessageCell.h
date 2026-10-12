//
//  AIMessageCell.h
//  Amethyst
//
//  Chat message bubble cell: user messages right aligned (accent-tinted background), assistant messages left aligned (blurred bubble),
//  assistant content rendered with MarkdownParser. Provides a static height estimation method for automatic row sizing.
//

#import <UIKit/UIKit.h>
#import "AiMessage.h"

NS_ASSUME_NONNULL_BEGIN

@interface AIMessageCell : UITableViewCell

/// Configure bubble content and layout (isToolCall/isToolResult are rendered as compact centered system cards)
- (void)configureWithMessage:(AiMessage *)message markdownEnabled:(BOOL)enabled;

/// Estimate the row height needed for a message at the given width
+ (CGFloat)cellHeightForMessage:(AiMessage *)message width:(CGFloat)width markdownEnabled:(BOOL)enabled;

/// Text for the tool card (shared by configure and height estimation)
+ (NSString *)toolCardTextForMessage:(AiMessage *)message;

@end

NS_ASSUME_NONNULL_END