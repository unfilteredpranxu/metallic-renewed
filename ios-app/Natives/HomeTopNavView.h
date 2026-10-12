#import <UIKit/UIKit.h>

@interface HomeTopNavView : UIView
@property (nonatomic, copy) void (^onSelect)(NSInteger index);
@property (nonatomic, assign) NSInteger selectedIndex;
@end