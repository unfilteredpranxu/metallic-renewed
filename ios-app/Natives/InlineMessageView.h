//
//  InlineMessageView.h
//  Amethyst
//
//  Inline-message display modeled on FCL/ZL2, replacing UIAlertController dialogs.
//  Show loading/error/success/info states in the center of the content area without blocking user actions.
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, InlineMessageType) {
    InlineMessageTypeLoading,  // Loading (spinner, does not disappear automatically)
    InlineMessageTypeError,    // Error (red, does not disappear automatically; must be dismissed manually)
    InlineMessageTypeSuccess,  // Success (green, disappears after 1.5s)
    InlineMessageTypeInfo,     // Info (blue, disappears after 1.5s)
};

@interface InlineMessageView : UIView

/// Currently displayed message type.
@property (nonatomic, assign, readonly) InlineMessageType messageType;
/// Callback when the message view is tapped (optional; can provide a "View Details" entry for loading messages).
@property (nonatomic, copy, nullable) void (^onTap)(void);
/// Callback when the close button is tapped (optional; replaces the default dismiss behavior when set,
/// for scenarios such as cancelling a download).
@property (nonatomic, copy, nullable) void (^onClose)(void);
/// Whether to show the close button (only error messages by default).
@property (nonatomic, assign) BOOL showsCloseButton;

/// Show a message on the specified parent view (automatically laid out in the center content area).
+ (instancetype)showInViewController:(UIViewController *)vc
                             title:(NSString *)title
                          message:(nullable NSString *)message
                             type:(InlineMessageType)type;

/// Show a message on the specified parent view (with a close-button option).
+ (instancetype)showInViewController:(UIViewController *)vc
                             title:(NSString *)title
                          message:(nullable NSString *)message
                             type:(InlineMessageType)type
                  showsCloseButton:(BOOL)showsCloseButton;

/// Update the current message content and type.
- (void)updateWithMessage:(NSString *)message type:(InlineMessageType)type;

/// Update only the message text (keep the current type).
- (void)updateMessage:(NSString *)message;

/// Dismiss the message view (animated).
- (void)dismiss;

/// Dismiss the message view (without animation; remove immediately).
- (void)dismissImmediately;

@end

NS_ASSUME_NONNULL_END
