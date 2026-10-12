//
//  GameMenuOverlayView.m
//  Amethyst
//
//  Modeled on the FCL MenuView.java and ZL2 GameScreen.kt implementations.
//  Key improvement: hitTest passes touches through; only the button/label regions intercept touches, and all other areas pass through to the game.
//

#import "GameMenuOverlayView.h"
#import "LauncherPreferences.h"

// Preference key for persisting the position.
static NSString *const kPrefMenuButtonX = @"game.menu_button_x";
static NSString *const kPrefMenuButtonY = @"game.menu_button_y";
static NSString *const kPrefStatsLabelX = @"game.stats_label_x";
static NSString *const kPrefStatsLabelY = @"game.stats_label_y";
// Preference key for the FPS/memory display toggle.
static NSString *const kPrefStatsLabelVisible = @"game.stats_label_visible";
// ★ [ISSUE-152] Preference key for the in-game settings bubble (small gear) visibility toggle.
//   Stored under control.* (matching the "Custom Controls" section in Settings; the key is registered
//   among the control defaults in PLPreferences.m). Defaults to YES to preserve existing behavior.
static NSString *const kPrefMenuButtonVisible = @"control.menu_button_visible";
// ★ [ISSUE-152] Notification name used to apply settings-page changes immediately (Settings is presented
//   in this process; the game layer hosting the bubble needs a broadcast to refresh at once).

// Button dimensions.
static const CGFloat kMenuButtonSize = 44.0;
// Drag threshold: movement beyond this distance counts as a drag; otherwise it counts as a tap (matching FCL MenuView's 10 px threshold).
static const CGFloat kDragThreshold = 10.0;

// ★ [KB-SPACE] Non-focusable button.
//   Root cause: while fixing #106 ("physical keyboard key crash"), SurfaceViewController.pressesBegan/Ended
//   was changed to always call super to preserve the responder chain. The side effect was that UIKit's focus
//   system also received Space, whose default primary action is "activate with Space/Return" — UIButton maps
//   that to UIControlEventPrimaryActionTriggered (i.e. touchUpInside) → menuButtonTouchedUp:
//   → onMenuButtonTapped → open the settings menu. Thus pressing Space to jump in-game accidentally opened the settings bubble.
//   Fix: canBecomeFocused is the focus system's single source of truth (WWDC21: "canBecomeFocused is
//   the single source of truth"); always returning NO prevents keyboard activation at the root.
//   Touch and drag (the bubble's only interactions) do not use the focus system and remain unchanged.
@interface AmeFocuslessButton : UIButton
@end

@implementation AmeFocuslessButton
- (BOOL)canBecomeFocused { return NO; }   // ★ [KB-SPACE] Never take keyboard focus.
@end

@interface GameMenuOverlayView ()

// Settings button (circular).
@property (nonatomic, strong) UIButton *menuButton;
// FPS/memory display label.
@property (nonatomic, strong) UILabel *statsLabel;
// Drag-related state.
@property (nonatomic, assign) BOOL isDragging;
@property (nonatomic, assign) CGPoint dragStartPoint;
@property (nonatomic, assign) CGPoint dragStartCenter;

@end

@implementation GameMenuOverlayView

- (instancetype)initWithParentView:(UIView *)parentView {
    self = [super initWithFrame:parentView.bounds];
    if (self) {
        self.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        self.backgroundColor = [UIColor clearColor];
        // Important: userInteractionEnabled = YES lets subviews receive touches,
        // while hitTest filters out touches outside the button/label so they pass through to the game.
        self.userInteractionEnabled = YES;
        // Show the FPS/memory label by default (can be toggled from the menu).
        _statsLabelVisible = YES;
        _overlayHidden = NO;
        // ★ [ISSUE-152] Show the bubble by default to preserve existing behavior; then apply the preference.
        _menuButtonVisible = YES;

        // Load the FPS/memory display toggle from preferences.
        NSNumber *savedVisible = getPrefObject(kPrefStatsLabelVisible);
        if (savedVisible) {
            _statsLabelVisible = [savedVisible boolValue];
        }
        // ★ [ISSUE-152] Load the bubble-visibility toggle (if the preference is missing, keep YES to match previous behavior).
        NSNumber *savedMenuBtn = getPrefObject(kPrefMenuButtonVisible);
        if (savedMenuBtn) {
            _menuButtonVisible = [savedMenuBtn boolValue];
        }

        [self setupMenuButton];
        [self setupStatsLabel];
        [parentView addSubview:self];

        [self restorePositions];
        [self applyStatsLabelVisibility];
        [self applyMenuButtonVisibility];   // ★ [ISSUE-152]
        // ★ [ISSUE-152] When Settings is presented in-game, reflect toggle changes on this bubble immediately.
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(ame152_menuButtonVisibilityChanged:)
                                                     name:@"AmeGameMenuButtonVisibilityChanged"
                                                   object:nil];
    }
    return self;
}

- (void)setupMenuButton {
    // ★ [KB-SPACE] Use a non-focusable subclass (not a plain UIButton) to prevent Space/Return/Tab from activating the bubble.
    self.menuButton = [AmeFocuslessButton buttonWithType:UIButtonTypeSystem];
    self.menuButton.frame = CGRectMake(0, 0, kMenuButtonSize, kMenuButtonSize);
    self.menuButton.layer.cornerRadius = kMenuButtonSize / 2;
    self.menuButton.layer.cornerCurve = kCACornerCurveContinuous;   // ★ [CORNER-FIX] Continuous corners (matching system cards).
    // Translucent dark background keeps the button visible over the game.
    self.menuButton.backgroundColor = [UIColor colorWithRed:0.1 green:0.1 blue:0.1 alpha:0.6];
    self.menuButton.layer.borderWidth = 1.5;
    self.menuButton.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.4].CGColor;
    // Following FCL, use the settings icon (gearshape).
    UIImage *icon = [UIImage systemImageNamed:@"gearshape.fill"]
                    ?: [UIImage systemImageNamed:@"gear"];
    [self.menuButton setImage:icon forState:UIControlStateNormal];
    self.menuButton.tintColor = [UIColor whiteColor];
    // Use frame-based layout (not Auto Layout) because the button position is set and persisted manually through center.
    // Leave translatesAutoresizingMaskIntoConstraints at its default YES; setting it to NO without constraints would make the frame indeterminate.
    // Ensure the button responds to touches.
    self.menuButton.userInteractionEnabled = YES;

    // Add a drag gesture.
    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handleMenuButtonPan:)];
    pan.minimumNumberOfTouches = 1;
    [self.menuButton addGestureRecognizer:pan];

    // Tap event.
    [self.menuButton addTarget:self action:@selector(menuButtonTouchedDown:) forControlEvents:UIControlEventTouchDown];
    [self.menuButton addTarget:self action:@selector(menuButtonTouchedUp:) forControlEvents:UIControlEventTouchUpInside];

    [self addSubview:self.menuButton];
}

- (void)setupStatsLabel {
    self.statsLabel = [[UILabel alloc] init];
    self.statsLabel.text = @"FPS: -- | MEM: --";
    self.statsLabel.font = [UIFont monospacedDigitSystemFontOfSize:12 weight:UIFontWeightBold];
    self.statsLabel.textColor = [UIColor whiteColor];
    self.statsLabel.backgroundColor = [UIColor colorWithRed:0 green:0 blue:0 alpha:0.5];
    self.statsLabel.layer.cornerRadius = 4;
    self.statsLabel.layer.cornerCurve = kCACornerCurveContinuous;   // ★ [CORNER-FIX] Continuous corners (matching system cards).
    self.statsLabel.layer.masksToBounds = YES;
    self.statsLabel.textAlignment = NSTextAlignmentCenter;
    self.statsLabel.numberOfLines = 1;
    // Use frame-based layout; position is set and persisted manually through center.
    self.statsLabel.frame = CGRectMake(0, 0, 130, 24);

    // Drag gesture.
    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handleStatsLabelPan:)];
    [self.statsLabel addGestureRecognizer:pan];
    self.statsLabel.userInteractionEnabled = YES;

    [self addSubview:self.statsLabel];
}

#pragma mark - ★ [KB-SPACE] Keyboard-focus guard (overlay level)

// ★ [KB-SPACE] The overlay root view also does not take keyboard focus (belt and suspenders; UIView defaults to NO, but state it explicitly).
- (BOOL)canBecomeFocused { return NO; }

/// ★ [KB-SPACE] The focus system asks this method on the shared ancestor's focus environment:
/// reject every focus update that would move focus into this overlay (menu bubble / FPS label), so keyboard
/// input (Space/Return/Tab/arrow keys) cannot activate its controls. Touch handling does not use the focus system and is unaffected.
- (BOOL)shouldUpdateFocusInContext:(UIFocusUpdateContext *)context {
    id<UIFocusItem> next = context.nextFocusedItem;
    if (next && [next isKindOfClass:[UIView class]] && [(UIView *)next isDescendantOfView:self]) {
        NSLog(@"[KB-SPACE] Rejected keyboard focus entering in-game settings overlay: %@", NSStringFromClass([(UIView *)next class]));
        return NO;
    }
    return [super shouldUpdateFocusInContext:context];
}

#pragma mark - hitTest passthrough (lets touches pass through to the game)

/// Override hitTest:withEvent: so only menuButton and statsLabel intercept touches;
/// return nil for other areas to pass touches through to the game below (surfaceView/ctrlView).
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    if (self.hidden || !self.userInteractionEnabled || self.overlayHidden) {
        return nil;
    }
    // Check whether menuButton contains the touch point.
    if (self.menuButton && !self.menuButton.hidden && self.menuButton.userInteractionEnabled) {
        CGPoint btnPoint = [self convertPoint:point toView:self.menuButton];
        if (CGRectContainsPoint(self.menuButton.bounds, btnPoint)) {
            return [self.menuButton hitTest:btnPoint withEvent:event];
        }
    }
    // Check whether statsLabel contains the touch point (and is visible).
    if (self.statsLabel && !self.statsLabel.hidden && self.statsLabelVisible && self.statsLabel.userInteractionEnabled) {
        CGPoint labelPoint = [self convertPoint:point toView:self.statsLabel];
        if (CGRectContainsPoint(self.statsLabel.bounds, labelPoint)) {
            return [self.statsLabel hitTest:labelPoint withEvent:event];
        }
    }
    // Return nil for other areas so touches pass through to the game.
    return nil;
}

#pragma mark - Position persistence

- (void)restorePositions {
    CGFloat bw = self.bounds.size.width;
    CGFloat bh = self.bounds.size.height;

    // Default button position: near the upper-right corner, but lower to avoid the status bar and upper-right controls.
    CGFloat defaultBtnX = bw - kMenuButtonSize - 20;
    CGFloat defaultBtnY = bh * 0.3;

    // Sentinel value -1 means unset (PLPreferences default); fall back to the hardcoded default position.
    NSNumber *savedX = getPrefObject(kPrefMenuButtonX);
    NSNumber *savedY = getPrefObject(kPrefMenuButtonY);
    if (savedX && savedY && [savedX floatValue] >= 0 && [savedY floatValue] >= 0) {
        CGFloat x = [savedX floatValue] * bw;
        CGFloat y = [savedY floatValue] * bh;
        self.menuButton.center = CGPointMake(x, y);
    } else {
        self.menuButton.center = CGPointMake(defaultBtnX, defaultBtnY);
    }

    // Default stats-label position: upper-left corner.
    CGFloat defaultLabelX = 70;
    CGFloat defaultLabelY = bh * 0.05 + 30;

    NSNumber *savedLX = getPrefObject(kPrefStatsLabelX);
    NSNumber *savedLY = getPrefObject(kPrefStatsLabelY);
    if (savedLX && savedLY && [savedLX floatValue] >= 0 && [savedLY floatValue] >= 0) {
        CGFloat x = [savedLX floatValue] * bw;
        CGFloat y = [savedLY floatValue] * bh;
        self.statsLabel.center = CGPointMake(x, y);
    } else {
        self.statsLabel.center = CGPointMake(defaultLabelX, defaultLabelY);
    }

    [self clampViewsToScreen];
}

- (void)savePositions {
    CGFloat bw = self.bounds.size.width;
    CGFloat bh = self.bounds.size.height;
    if (bw <= 0 || bh <= 0) return;

    // Save as a percentage of screen width/height (matching FCL menuPositionX/Y) so positions remain correct after rotation.
    CGFloat btnXPercent = self.menuButton.center.x / bw;
    CGFloat btnYPercent = self.menuButton.center.y / bh;
    setPrefObject(kPrefMenuButtonX, @(btnXPercent));
    setPrefObject(kPrefMenuButtonY, @(btnYPercent));

    CGFloat labelXPercent = self.statsLabel.center.x / bw;
    CGFloat labelYPercent = self.statsLabel.center.y / bh;
    setPrefObject(kPrefStatsLabelX, @(labelXPercent));
    setPrefObject(kPrefStatsLabelY, @(labelYPercent));
}

- (void)clampViewsToScreen {
    CGFloat bw = self.bounds.size.width;
    CGFloat bh = self.bounds.size.height;
    if (bw <= 0 || bh <= 0) return;

    // Keep the settings button within the screen.
    CGFloat btnHalf = kMenuButtonSize / 2;
    CGFloat btnX = MAX(btnHalf, MIN(bw - btnHalf, self.menuButton.center.x));
    CGFloat btnY = MAX(btnHalf, MIN(bh - btnHalf, self.menuButton.center.y));
    self.menuButton.center = CGPointMake(btnX, btnY);

    // Keep the stats label within the screen.
    CGFloat labelHalfW = self.statsLabel.frame.size.width / 2;
    CGFloat labelHalfH = self.statsLabel.frame.size.height / 2;
    CGFloat labelX = MAX(labelHalfW, MIN(bw - labelHalfW, self.statsLabel.center.x));
    CGFloat labelY = MAX(labelHalfH, MIN(bh - labelHalfH, self.statsLabel.center.y));
    self.statsLabel.center = CGPointMake(labelX, labelY);
}

#pragma mark - Settings button gestures

- (void)handleMenuButtonPan:(UIPanGestureRecognizer *)sender {
    CGPoint translation = [sender translationInView:self];

    if (sender.state == UIGestureRecognizerStateBegan) {
        self.isDragging = NO;
        self.dragStartPoint = [sender locationInView:self];
        self.dragStartCenter = self.menuButton.center;
        // Highlight while dragging.
        self.menuButton.backgroundColor = [UIColor colorWithRed:0.2 green:0.5 blue:0.9 alpha:0.8];
    } else if (sender.state == UIGestureRecognizerStateChanged) {
        CGFloat dx = [sender locationInView:self].x - self.dragStartPoint.x;
        CGFloat dy = [sender locationInView:self].y - self.dragStartPoint.y;
        CGFloat distance = sqrt(dx * dx + dy * dy);
        if (distance > kDragThreshold) {
            self.isDragging = YES;
        }
        if (self.isDragging) {
            CGPoint newCenter = CGPointMake(self.dragStartCenter.x + translation.x,
                                            self.dragStartCenter.y + translation.y);
            // Keep it within the screen.
            CGFloat half = kMenuButtonSize / 2;
            newCenter.x = MAX(half, MIN(self.bounds.size.width - half, newCenter.x));
            newCenter.y = MAX(half, MIN(self.bounds.size.height - half, newCenter.y));
            self.menuButton.center = newCenter;
        }
    } else if (sender.state == UIGestureRecognizerStateEnded || sender.state == UIGestureRecognizerStateCancelled) {
        // Restore the background.
        self.menuButton.backgroundColor = [UIColor colorWithRed:0.1 green:0.1 blue:0.1 alpha:0.6];
        if (self.isDragging) {
            // Save the position when dragging ends.
            [self savePositions];
        }
        self.isDragging = NO;
    }
}

- (void)menuButtonTouchedDown:(UIButton *)sender {
    // Shrink animation while pressed.
    [UIView animateWithDuration:0.1 animations:^{
        sender.transform = CGAffineTransformMakeScale(0.9, 0.9);
    }];
}

- (void)menuButtonTouchedUp:(UIButton *)sender {
    [UIView animateWithDuration:0.1 animations:^{
        sender.transform = CGAffineTransformIdentity;
    }];
    // Do not trigger a tap if this was a drag.
    if (!self.isDragging) {
        if (self.onMenuButtonTapped) {
            self.onMenuButtonTapped();
        }
    }
}

#pragma mark - Stats label gestures

- (void)handleStatsLabelPan:(UIPanGestureRecognizer *)sender {
    CGPoint translation = [sender translationInView:self];

    if (sender.state == UIGestureRecognizerStateBegan) {
        self.isDragging = NO;
        self.dragStartCenter = self.statsLabel.center;
    } else if (sender.state == UIGestureRecognizerStateChanged) {
        self.isDragging = YES;
        CGPoint newCenter = CGPointMake(self.dragStartCenter.x + translation.x,
                                        self.dragStartCenter.y + translation.y);
        CGFloat halfW = self.statsLabel.frame.size.width / 2;
        CGFloat halfH = self.statsLabel.frame.size.height / 2;
        newCenter.x = MAX(halfW, MIN(self.bounds.size.width - halfW, newCenter.x));
        newCenter.y = MAX(halfH, MIN(self.bounds.size.height - halfH, newCenter.y));
        self.statsLabel.center = newCenter;
    } else if (sender.state == UIGestureRecognizerStateEnded || sender.state == UIGestureRecognizerStateCancelled) {
        if (self.isDragging) {
            [self savePositions];
        }
        self.isDragging = NO;
    }
}

#pragma mark - Public methods

- (void)setOverlayHidden:(BOOL)overlayHidden {
    _overlayHidden = overlayHidden;
    // ★ [ISSUE-152] Hide the bubble if the overlay is hidden OR the user turned the toggle off (both conditions must allow it to show).
    [self applyMenuButtonVisibility];
    self.statsLabel.hidden = overlayHidden || !_statsLabelVisible;
}

#pragma mark - ★ [ISSUE-152] Settings bubble (gear) visibility toggle

/// When disabled, menuButton.hidden = YES. hitTest first checks `!self.menuButton.hidden`
/// (see hitTest:withEvent: above), so touches in the hidden button's region pass through to the game,
/// just as if the button did not exist; no invisible touch hotspot remains.
- (void)applyMenuButtonVisibility {
    self.menuButton.hidden = self.overlayHidden || !_menuButtonVisible;
}

- (void)setMenuButtonVisible:(BOOL)menuButtonVisible {
    _menuButtonVisible = menuButtonVisible;
    [self applyMenuButtonVisibility];
    // Persist under control.menu_button_visible — the same source of truth as Settings.
    setPrefObject(kPrefMenuButtonVisible, @(menuButtonVisible));
    NSLog(@"[ISSUE-152] Game menu button (gear) visible=%d", menuButtonVisible ? 1 : 0);
}

/// Settings-page change broadcast ⇒ reapply the preference (idempotently).
- (void)ame152_menuButtonVisibilityChanged:(NSNotification *__unused)note {
    NSNumber *v = getPrefObject(kPrefMenuButtonVisible);
    _menuButtonVisible = v ? [v boolValue] : YES;
    dispatch_async(dispatch_get_main_queue(), ^{
        [self applyMenuButtonVisibility];
    });
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)setStatsLabelVisible:(BOOL)statsLabelVisible {
    _statsLabelVisible = statsLabelVisible;
    [self applyStatsLabelVisibility];
    // Persist the toggle state.
    setPrefObject(kPrefStatsLabelVisible, @(statsLabelVisible));
}

- (void)applyStatsLabelVisibility {
    self.statsLabel.hidden = self.overlayHidden || !_statsLabelVisible;
}

/// Toggle the FPS/memory display (matching FCL's toggleStatsView).
- (void)toggleStatsLabel {
    self.statsLabelVisible = !self.statsLabelVisible;
}

- (void)updateFPS:(NSInteger)fps memoryUsageMB:(double)memoryMB {
    // Update on the main thread (matching FCL/ZL2, driven by the game loop).
    // Use dispatch_async to avoid blocking the caller.
    dispatch_async(dispatch_get_main_queue(), ^{
        if (fps >= 0) {
            self.statsLabel.text = [NSString stringWithFormat:@"FPS: %ld | MEM: %.0fMB",
                                    (long)fps, memoryMB];
        }
    });
}

- (void)layoutSubviews {
    [super layoutSubviews];
    // Re-constrain positions after screen rotation.
    [self clampViewsToScreen];
}

@end
