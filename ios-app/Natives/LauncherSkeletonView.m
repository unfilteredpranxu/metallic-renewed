//
//  LauncherSkeletonView.m
//  Amethyst
//
//  List skeleton-screen implementation.
//
//  Visual style follows the project's existing glass system (see BackgroundManager / InlineMessageView):
//  translucent white rounded placeholders with a subtle border reveal the wallpaper underneath, with staggered
//  fade-in/fade-out "breathing" animations to make loading visible instead of appearing blank or stuck.
//

#import "LauncherSkeletonView.h"
// ★ [GLASS-LIQUID] Placeholder material uses the style layer: system material by default (system glass/material), not a custom white fill and border.
#import "UIKit+GlassSurface.h"

#include <math.h>

/// List-row placeholder height / row spacing.
static CGFloat const kSkeletonListRowHeight = 64.0;
static CGFloat const kSkeletonListRowSpacing = 10.0;
/// Grid-card height / card spacing.
static CGFloat const kSkeletonGridCardHeight = 104.0;
static CGFloat const kSkeletonGridSpacing = 10.0;
/// Placeholder fill / border (remain translucent so the wallpaper is not obscured).
static CGFloat const kSkeletonFillAlpha = 0.12;
static CGFloat const kSkeletonBorderAlpha = 0.06;
/// Grid-column thresholds for wide layouts (iPad / landscape).
static CGFloat const kSkeletonGridMinCardWidth = 150.0;  // ★ [UI-ADAPT] Minimum readable card width determines the column count (2–4).

@interface LauncherSkeletonView ()

/// Placeholder style (fixed at creation).
@property (nonatomic, assign) LauncherSkeletonStyle skeletonStyle;
/// All current placeholders.
@property (nonatomic, strong) NSMutableArray<UIView *> *placeholderViews;
/// Size used to build the placeholders last time (rebuild only when the size changes).
@property (nonatomic, assign) CGSize lastPlaceholderLayoutSize;

/// Initializer for the specified style (internal use only).
- (instancetype)initWithFrame:(CGRect)frame style:(LauncherSkeletonStyle)style;
/// Rebuild placeholders for the current size.
- (void)rebuildPlaceholdersIfNeeded:(BOOL)force;
/// Build list-row-style placeholders.
- (void)buildListPlaceholdersForSize:(CGSize)size;
/// Build card-grid-style placeholders.
- (void)buildCardGridPlaceholdersForSize:(CGSize)size;
/// Create one placeholder.
- (UIView *)makePlaceholderViewWithFrame:(CGRect)frame cornerRadius:(CGFloat)cornerRadius;
/// Apply consistent placeholder styling (fill / corner radius / border).
- (void)applyPlaceholderStyleToView:(UIView *)view cornerRadius:(CGFloat)cornerRadius;
/// Breathing animation.
- (void)startBreathingAnimation;
- (void)stopBreathingAnimation;

@end

@implementation LauncherSkeletonView

#pragma mark - Create / destroy

+ (instancetype)attachToView:(UIView *)hostView style:(LauncherSkeletonStyle)style {
    if (!hostView) {
        return nil;
    }
    UIView *parentView = hostView.superview ?: hostView;
    if (!parentView) {
        return nil;
    }

    LauncherSkeletonView *skeleton = [[LauncherSkeletonView alloc] initWithFrame:hostView.bounds style:style];
    skeleton.translatesAutoresizingMaskIntoConstraints = NO;
    skeleton.hidden = YES;
    // Visual-only layer: does not intercept touches, so list scrolling / pull-to-refresh continue to work.
    skeleton.userInteractionEnabled = NO;
    [parentView addSubview:skeleton];

    [NSLayoutConstraint activateConstraints:@[
        [skeleton.topAnchor constraintEqualToAnchor:hostView.topAnchor],
        [skeleton.bottomAnchor constraintEqualToAnchor:hostView.bottomAnchor],
        [skeleton.leadingAnchor constraintEqualToAnchor:hostView.leadingAnchor],
        [skeleton.trailingAnchor constraintEqualToAnchor:hostView.trailingAnchor],
    ]];

    return skeleton;
}

- (instancetype)initWithFrame:(CGRect)frame style:(LauncherSkeletonStyle)style {
    self = [super initWithFrame:frame];
    if (self) {
        _skeletonStyle = style;
        _placeholderViews = [NSMutableArray array];
        self.backgroundColor = [UIColor clearColor];
        self.clipsToBounds = YES;
        self.layer.masksToBounds = YES;
    }
    return self;
}

- (void)dealloc {
    [self stopBreathingAnimation];
}

#pragma mark - Show / hide

- (void)showSkeleton {
    [self rebuildPlaceholdersIfNeeded:YES];
    self.hidden = NO;
    _skeletonVisible = YES;
    [self startBreathingAnimation];

    if (self.alpha < 1.0) {
        [UIView animateWithDuration:0.15 animations:^{
            self.alpha = 1.0;
        }];
    }
}

- (void)hideSkeleton {
    if (self.hidden) {
        return;
    }
    _skeletonVisible = NO;

    __weak typeof(self) weakSelf = self;
    [UIView animateWithDuration:0.2 animations:^{
        weakSelf.alpha = 0.0;
    } completion:^(BOOL finished) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf || strongSelf.skeletonVisible) {
            return;  // If asked to show again while fading out, keep the current state.
        }
        strongSelf.hidden = YES;
        strongSelf.alpha = 1.0;
        [strongSelf stopBreathingAnimation];
    }];
}

- (void)hideSkeletonImmediately {
    _skeletonVisible = NO;
    [self stopBreathingAnimation];
    [self.layer removeAllAnimations];
    self.hidden = YES;
    self.alpha = 1.0;
}

#pragma mark - Layout

- (void)layoutSubviews {
    [super layoutSubviews];

    if (CGSizeEqualToSize(self.bounds.size, self.lastPlaceholderLayoutSize)) {
        return;
    }
    [self rebuildPlaceholdersIfNeeded:YES];
    if (self.skeletonVisible) {
        [self startBreathingAnimation];
    }
}

- (void)rebuildPlaceholdersIfNeeded:(BOOL)force {
    if (!force && CGSizeEqualToSize(self.bounds.size, self.lastPlaceholderLayoutSize)) {
        return;
    }
    self.lastPlaceholderLayoutSize = self.bounds.size;

    for (UIView *placeholder in self.placeholderViews) {
        [placeholder.layer removeAllAnimations];
        [placeholder removeFromSuperview];
    }
    [self.placeholderViews removeAllObjects];

    CGSize size = self.bounds.size;
    if (size.width < 1.0 || size.height < 1.0) {
        return;
    }

    if (self.skeletonStyle == LauncherSkeletonStyleCardGrid) {
        [self buildCardGridPlaceholdersForSize:size];
    } else {
        [self buildListPlaceholdersForSize:size];
    }
}

/// List-row style: icon square on the left + two text lines, approximating the visual weight of a real card.
- (void)buildListPlaceholdersForSize:(CGSize)size {
    CGFloat sideInset = 4.0;
    CGFloat rowWidth = MAX(size.width - sideInset * 2.0, 1.0);
    NSInteger rowCount = (NSInteger)ceil((size.height + kSkeletonListRowSpacing) /
                                         (kSkeletonListRowHeight + kSkeletonListRowSpacing));

    for (NSInteger index = 0; index < rowCount; index++) {
        CGRect rowFrame = CGRectMake(sideInset,
                                     index * (kSkeletonListRowHeight + kSkeletonListRowSpacing),
                                     rowWidth,
                                     kSkeletonListRowHeight);
        UIView *row = [self makePlaceholderViewWithFrame:rowFrame cornerRadius:12.0];
        [self addSubview:row];
        [self.placeholderViews addObject:row];

        CGFloat iconSide = 44.0;
        UIView *icon = [[UIView alloc] initWithFrame:CGRectMake(14.0,
                                                               (kSkeletonListRowHeight - iconSide) / 2.0,
                                                               iconSide,
                                                               iconSide)];
        [self applyPlaceholderStyleToView:icon cornerRadius:10.0];
        [row addSubview:icon];

        CGFloat textLeft = 14.0 + iconSide + 12.0;
        CGFloat textWidth = MAX(rowWidth - textLeft - 16.0, 1.0);

        UIView *titleBar = [[UIView alloc] initWithFrame:CGRectMake(textLeft, 19.0, textWidth * 0.62, 13.0)];
        [self applyPlaceholderStyleToView:titleBar cornerRadius:6.0];
        [row addSubview:titleBar];

        UIView *subtitleBar = [[UIView alloc] initWithFrame:CGRectMake(textLeft, 40.0, textWidth * 0.42, 10.0)];
        [self applyPlaceholderStyleToView:subtitleBar cornerRadius:5.0];
        [row addSubview:subtitleBar];
    }
}

/// Card-grid style: matches the version-list card flow (two columns on iPhone, three on wide screens).
- (void)buildCardGridPlaceholdersForSize:(CGSize)size {
    CGFloat sideInset = 8.0;
    CGFloat gap = kSkeletonGridSpacing;
    // ★ [UI-ADAPT] Choose 2–4 columns based on minimum card width, matching the home Bento layout:
    //   two columns on small screens / three on medium screens / four on large screens (iPad portrait or landscape), rather than one threshold.
    NSInteger columnCount = (NSInteger)floor((size.width - sideInset * 2.0 + gap) / (kSkeletonGridMinCardWidth + gap));
    if (columnCount < 2) columnCount = 2;
    if (columnCount > 4) columnCount = 4;
    CGFloat cardWidth = floor((size.width - sideInset * 2.0 - gap * (CGFloat)(columnCount - 1)) / (CGFloat)columnCount);
    if (cardWidth < 40.0) {
        columnCount = 1;
        cardWidth = MAX(size.width - sideInset * 2.0, 1.0);
    }
    NSInteger rowCount = (NSInteger)ceil((size.height + gap) / (kSkeletonGridCardHeight + gap));

    for (NSInteger rowIndex = 0; rowIndex < rowCount; rowIndex++) {
        for (NSInteger columnIndex = 0; columnIndex < columnCount; columnIndex++) {
            CGRect cardFrame = CGRectMake(sideInset + columnIndex * (cardWidth + gap),
                                          rowIndex * (kSkeletonGridCardHeight + gap),
                                          cardWidth,
                                          kSkeletonGridCardHeight);
            UIView *card = [self makePlaceholderViewWithFrame:cardFrame cornerRadius:14.0];
            [self addSubview:card];
            [self.placeholderViews addObject:card];
        }
    }
}

#pragma mark - Placeholder styling and animation

- (UIView *)makePlaceholderViewWithFrame:(CGRect)frame cornerRadius:(CGFloat)cornerRadius {
    UIView *view = [[UIView alloc] initWithFrame:frame];
    view.autoresizingMask = UIViewAutoresizingNone;
    [self applyPlaceholderStyleToView:view cornerRadius:cornerRadius];
    return view;
}

- (void)applyPlaceholderStyleToView:(UIView *)view cornerRadius:(CGFloat)cornerRadius {
    if (!view) {
        return;
    }
    // ★ [GLASS-LIQUID] System-material path (default): use system material for placeholders (UIGlassEffect / system UIBlurEffect)
    //   instead of drawing translucent white with a 1 px white border. Keep the old appearance only when custom highlights are explicitly enabled.
    if (AMEGlassStyleAllowsHandDrawnGlass()) {
        view.backgroundColor = [UIColor colorWithWhite:1.0 alpha:kSkeletonFillAlpha];
        view.layer.cornerRadius = cornerRadius;
        view.layer.cornerCurve = kCACornerCurveContinuous;
        view.layer.borderWidth = 1.0;
        view.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:kSkeletonBorderAlpha].CGColor;
        view.layer.masksToBounds = YES;
    } else {
        AmeApplyGlassChipStyle(view, cornerRadius, NO);
    }
}

/// Breathing animation: stagger placeholder fades by row to suggest that loading is in progress.
- (void)startBreathingAnimation {
    NSTimeInterval stagger = 0.0;
    for (UIView *placeholder in self.placeholderViews) {
        [placeholder.layer removeAllAnimations];
        placeholder.alpha = 1.0;
        [UIView animateWithDuration:0.85
                              delay:stagger
                            options:(UIViewAnimationOptionRepeat |
                                     UIViewAnimationOptionAutoreverse |
                                     UIViewAnimationOptionCurveEaseInOut)
                         animations:^{
            placeholder.alpha = 0.45;
        }
                         completion:nil];

        stagger += 0.05;
        if (stagger > 0.3) {
            stagger = 0.0;
        }
    }
}

- (void)stopBreathingAnimation {
    for (UIView *placeholder in self.placeholderViews) {
        [placeholder.layer removeAllAnimations];
        placeholder.alpha = 1.0;
    }
}

@end
