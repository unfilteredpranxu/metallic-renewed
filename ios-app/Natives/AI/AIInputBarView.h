//
//  AIInputBarView.h
//  Amethyst
//
//  AI chat bottom input bar: capsule input field + send/stop toggle button + model name label.
//  Keyboard and bottom safe-area adjustments are handled externally (AIViewController) via bottomInset and keyboard notifications.
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface AIInputBarView : UIView

/// Input field text (read as the current input)
@property (nonatomic, copy) NSString *text;
/// Bottom safe-area inset (updated externally with safeAreaInsets / keyboard changes)
@property (nonatomic, assign) CGFloat bottomInset;
/// Whether generation is in progress (switches to the stop icon)
@property (nonatomic, assign) BOOL isSending;

/// Model name label (tapping triggers onModelTap)
@property (nonatomic, strong, readonly) UILabel *modelLabel;

/// Send callback
@property (nonatomic, copy, nullable) void (^onSend)(NSString *text);
/// Stop callback
@property (nonatomic, copy, nullable) void (^onStop)(void);
/// Model label tap callback
@property (nonatomic, copy, nullable) void (^onModelTap)(void);

/// Clear the input field
- (void)clearText;

@end

NS_ASSUME_NONNULL_END