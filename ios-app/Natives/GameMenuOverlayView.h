//
//  GameMenuOverlayView.h
//  Amethyst
//
//  Floating-button design modeled on FCL MenuView and ZL2 GameScreen:
//  - Draggable circular settings button (position persisted), replacing the old right-side swipe strip
//  - Draggable FPS/memory label (position persisted), shown/hidden through a menu switch
//  - Tapping the settings button invokes a callback (opens the menu)
//  - hitTest pass-through: only the button/label areas intercept touches; the rest pass through to the game
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// In-game floating overlay: settings button + FPS/memory display.
/// Floating-button design modeled on FCL MenuView.java and ZL2 GameScreen.kt.
@interface GameMenuOverlayView : UIView

/// Settings-button tap callback (opens the menu).
@property (nonatomic, copy, nullable) void (^onMenuButtonTapped)(void);

/// Show/hide the entire overlay (FCL's hideMenuView concept).
@property (nonatomic, assign) BOOL overlayHidden;

/// Whether to show the FPS/memory statistics label (switchable from the menu; modeled on FCL).
@property (nonatomic, assign) BOOL statsLabelVisible;

/// ★ [ISSUE-152] Whether to show the floating settings button (the "gear" button).
/// Controlled by Settings > Custom Controls > "Show in-game floating button"
/// (preference key control.menu_button_visible).
/// Default YES = preserve existing behavior. When off, menuButton is hidden and hitTest no longer
/// intercepts touches in that area (touches continue through to the game).
@property (nonatomic, assign) BOOL menuButtonVisible;

/// Initialize and add to the specified parent view.
- (instancetype)initWithParentView:(UIView *)parentView;

/// Update the FPS and memory display (driven by the game loop; recommended call interval 500ms~1s).
/// Must be called on the main thread.
- (void)updateFPS:(NSInteger)fps memoryUsageMB:(double)memoryMB;

/// Load the persisted position from preferences.
- (void)restorePositions;

/// Save the current position to preferences.
- (void)savePositions;

/// Toggle FPS/memory display.
- (void)toggleStatsLabel;

@end

NS_ASSUME_NONNULL_END
