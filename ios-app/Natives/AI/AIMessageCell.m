//
//  AIMessageCell.m
//  Amethyst
//

#import "AIMessageCell.h"
#import "MarkdownParser.h"
#import "LauncherPreferences.h"

// Note: Assistant bubbles use a translucent white 0.08 background and do not add a UIVisualEffectView blur,
// to avoid performance/reuse issues caused by repeatedly inserting blur views in a scrolling table. The outer content area
// already gets an overall blur from BackgroundManager, so the bubbles can remain transparent. See AnnouncementCardCell.

/// Content font
static const CGFloat kMsgFontSize = 16.0;
/// Bubble padding
static const CGFloat kMsgBubblePadding = 10.0;
/// Maximum bubble width as a proportion of the container
static const CGFloat kMsgMaxBubbleWidthRatio = 0.72;
/// Horizontal outer margin
static const CGFloat kMsgHMargin = 12.0;
/// Vertical cell spacing
static const CGFloat kMsgVerticalPadding = 10.0;
/// Bubble corner radius (continuous corners)
static const CGFloat kMsgCornerRadius = 12.0;

@interface AIMessageCell ()
@property (nonatomic, strong) UIView *bubbleView;
@property (nonatomic, strong) UITextView *contentTextView;
@property (nonatomic, strong) UIView *toolCardView;
@property (nonatomic, strong) UILabel *toolCardLabel;
@end

@implementation AIMessageCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        self.backgroundColor = [UIColor clearColor];
        self.contentView.backgroundColor = [UIColor clearColor];
        self.selectionStyle = UITableViewCellSelectionStyleNone;

        self.bubbleView = [[UIView alloc] init];
        self.bubbleView.translatesAutoresizingMaskIntoConstraints = NO;
        self.bubbleView.layer.cornerRadius = kMsgCornerRadius;
        self.bubbleView.layer.cornerCurve = kCACornerCurveContinuous;
        self.bubbleView.clipsToBounds = YES;
        [self.contentView addSubview:self.bubbleView];

        self.contentTextView = [[UITextView alloc] init];
        self.contentTextView.translatesAutoresizingMaskIntoConstraints = NO;
        self.contentTextView.editable = NO;
        self.contentTextView.scrollEnabled = NO;
        self.contentTextView.selectable = YES;
        self.contentTextView.backgroundColor = [UIColor clearColor];
        self.contentTextView.textContainerInset = UIEdgeInsetsZero;
        self.contentTextView.textContainer.lineFragmentPadding = 0;
        [self.bubbleView addSubview:self.contentTextView];

        // Constraints: text top/left/right align to the bubble padding; content size determines bubble height (no forced height)
        [NSLayoutConstraint activateConstraints:@[
            [self.contentTextView.topAnchor constraintEqualToAnchor:self.bubbleView.topAnchor constant:kMsgBubblePadding],
            [self.contentTextView.leadingAnchor constraintEqualToAnchor:self.bubbleView.leadingAnchor constant:kMsgBubblePadding],
            [self.contentTextView.trailingAnchor constraintEqualToAnchor:self.bubbleView.trailingAnchor constant:-kMsgBubblePadding],
            [self.contentTextView.bottomAnchor constraintEqualToAnchor:self.bubbleView.bottomAnchor constant:-kMsgBubblePadding],
            // Limit the maximum bubble width
            [self.bubbleView.widthAnchor constraintLessThanOrEqualToAnchor:self.contentView.widthAnchor multiplier:kMsgMaxBubbleWidthRatio],
        ]];

        // Content determines the bubble's vertical size; cell top/bottom spacing constrains the minimum height
        [NSLayoutConstraint activateConstraints:@[
            [self.bubbleView.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:kMsgVerticalPadding],
            [self.bubbleView.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-kMsgVerticalPadding],
        ]];

        // Tool card: compact centered system style (does not affect bubble layout when hidden)
        self.toolCardView = [[UIView alloc] init];
        self.toolCardView.translatesAutoresizingMaskIntoConstraints = NO;
        self.toolCardView.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.06];
        self.toolCardView.layer.cornerRadius = 8.0;
        self.toolCardView.layer.cornerCurve = kCACornerCurveContinuous;
        self.toolCardView.clipsToBounds = YES;
        self.toolCardView.hidden = YES;
        [self.contentView addSubview:self.toolCardView];

        self.toolCardLabel = [[UILabel alloc] init];
        self.toolCardLabel.translatesAutoresizingMaskIntoConstraints = NO;
        self.toolCardLabel.font = [UIFont systemFontOfSize:11.0];
        self.toolCardLabel.textColor = [UIColor tertiaryLabelColor];
        self.toolCardLabel.numberOfLines = 0;
        self.toolCardLabel.backgroundColor = [UIColor clearColor];
        [self.toolCardView addSubview:self.toolCardLabel];

        [NSLayoutConstraint activateConstraints:@[
            // Center the card horizontally, leaving margins on both sides
            [self.toolCardView.centerXAnchor constraintEqualToAnchor:self.contentView.centerXAnchor],
            [self.toolCardView.leadingAnchor constraintGreaterThanOrEqualToAnchor:self.contentView.leadingAnchor constant:kMsgHMargin],
            [self.toolCardView.trailingAnchor constraintLessThanOrEqualToAnchor:self.contentView.trailingAnchor constant:-kMsgHMargin],
            [self.toolCardView.widthAnchor constraintLessThanOrEqualToAnchor:self.contentView.widthAnchor multiplier:kMsgMaxBubbleWidthRatio],
            // Center the card vertically, with cell spacing around it (padding 6)
            [self.toolCardView.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:6],
            [self.toolCardView.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-6],
            [self.toolCardLabel.topAnchor constraintEqualToAnchor:self.toolCardView.topAnchor constant:5],
            [self.toolCardLabel.bottomAnchor constraintEqualToAnchor:self.toolCardView.bottomAnchor constant:-5],
            [self.toolCardLabel.leadingAnchor constraintEqualToAnchor:self.toolCardView.leadingAnchor constant:10],
            [self.toolCardLabel.trailingAnchor constraintEqualToAnchor:self.toolCardView.trailingAnchor constant:-10],
        ]];
    }
    return self;
}

- (void)configureWithMessage:(AiMessage *)message markdownEnabled:(BOOL)enabled {
    if (!message) return;

    // Tool result: render as a centered system card (show only success/failure status)
    if (message.isToolResult) {
        self.bubbleView.hidden = YES;
        self.toolCardView.hidden = NO;
        self.toolCardLabel.text = [[self class] toolCardTextForMessage:message];
        return;
    }

    self.toolCardView.hidden = YES;
    self.bubbleView.hidden = NO;
    BOOL isUser = [message.role isEqualToString:@"user"];
    // Tool-call message coexists with AI text: show the AI text and append a tool-call hint in the bubble
    NSString *content = message.isToolCall ? [[self class] displayContentForMessage:message] : (message.content ?: @"");
    UIColor *contentColor = [UIColor labelColor];

    // Text content
    if (isUser || !enabled) {
        UIFont *font = [UIFont systemFontOfSize:kMsgFontSize];
        self.contentTextView.font = font;
        self.contentTextView.text = content;
        self.contentTextView.textColor = contentColor;
    } else {
        NSAttributedString *attr = [MarkdownParser parseMarkdown:content baseFont:[UIFont systemFontOfSize:kMsgFontSize]];
        self.contentTextView.attributedText = attr;
    }

    // Bubble style
    if (isUser) {
        // User message: right aligned, accent-tinted 0.10 background + labelColor text
        self.bubbleView.backgroundColor = [accentColor() colorWithAlphaComponent:0.10];
        self.contentTextView.textColor = contentColor;
        [self rebuildHorizontalConstraintsForUser:YES];
    } else {
        // Assistant message: left aligned, white 0.08 background + MarkdownParser's built-in system text color + blur
        self.bubbleView.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.08];
        [self rebuildHorizontalConstraintsForUser:NO];
    }
}

/// Rebuild the bubble's horizontal alignment constraints (user right aligned, assistant left aligned)
- (void)rebuildHorizontalConstraintsForUser:(BOOL)isUser {
    // Remove previously added horizontal alignment constraints (identified by the stored marker)
    NSMutableArray *toRemove = [NSMutableArray array];
    for (NSLayoutConstraint *c in [self.contentView constraints]) {
        BOOL touchesBubble = (c.firstItem == self.bubbleView || c.secondItem == self.bubbleView);
        BOOL horizontal = (c.firstAttribute == NSLayoutAttributeLeading ||
                           c.firstAttribute == NSLayoutAttributeTrailing ||
                           c.secondAttribute == NSLayoutAttributeLeading ||
                           c.secondAttribute == NSLayoutAttributeTrailing);
        if (touchesBubble && horizontal) {
            [toRemove addObject:c];
        }
    }
    if (toRemove.count > 0) {
        [NSLayoutConstraint deactivateConstraints:toRemove];
    }

    if (isUser) {
        // Right aligned
        [NSLayoutConstraint activateConstraints:@[
            [self.bubbleView.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-kMsgHMargin],
            [self.bubbleView.leadingAnchor constraintGreaterThanOrEqualToAnchor:self.contentView.leadingAnchor constant:kMsgHMargin],
        ]];
    } else {
        // Left aligned
        [NSLayoutConstraint activateConstraints:@[
            [self.bubbleView.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:kMsgHMargin],
            [self.bubbleView.trailingAnchor constraintLessThanOrEqualToAnchor:self.contentView.trailingAnchor constant:-kMsgHMargin],
        ]];
    }
}

#pragma mark - Tool card text

/// Content shown in the bubble for a tool-call message: AI text + tool-call hint (coexist)
+ (NSString *)displayContentForMessage:(AiMessage *)message {
    if (message.isToolCall) {
        NSString *base = message.content.length > 0 ? message.content : @"(Calling tool…)";
        // Important fix (tool name displayed as call_00_...): show generic "Tool" if toolName is missing,
        // never substitute toolCallID (an ID such as call_xxx) for the actual tool name
        NSString *name = message.toolName.length > 0 ? message.toolName : @"Tool";
        return [base stringByAppendingFormat:@"\n\n⚙️ Tool: %@", name];
    }
    return message.content ?: @"";
}

+ (NSString *)toolCardTextForMessage:(AiMessage *)message {
    if (!message) return @"";
    // Important fix (tool name displayed as call_00_...): show generic "Tool" if toolName is missing,
    // never substitute toolCallID (call_xxx) for the actual tool name
    NSString *name = message.toolName.length > 0 ? message.toolName : @"Tool";
    if (message.isToolResult) {
        // Show only the success/failure status; omit verbose tool output to avoid filling the screen
        return message.toolSucceeded ? [NSString stringWithFormat:@"✅ %@ succeeded", name] : [NSString stringWithFormat:@"❌ %@ failed", name];
    }
    return [NSString stringWithFormat:@"⚙️ Tool: %@", name];
}

#pragma mark - Height estimation

+ (CGFloat)cellHeightForMessage:(AiMessage *)message width:(CGFloat)width markdownEnabled:(BOOL)enabled {
    if (!message || !width) return 60.0;

    // Tool result: rendered as a small card; estimate using only the status text line height
    if (message.isToolResult) {
        NSString *cardText = [self toolCardTextForMessage:message];
        CGFloat maxCardWidth = width * kMsgMaxBubbleWidthRatio - 20; // Subtract left and right padding
        if (maxCardWidth < 20) maxCardWidth = 20;
        UIFont *font = [UIFont systemFontOfSize:11.0];
        CGRect r = [cardText boundingRectWithSize:CGSizeMake(maxCardWidth, CGFLOAT_MAX)
                                          options:NSStringDrawingUsesLineFragmentOrigin | NSStringDrawingUsesFontLeading
                                       attributes:@{NSFontAttributeName: font}
                                          context:nil];
        CGFloat textHeight = ceil(r.size.height);
        if (textHeight < 16) textHeight = 16;
        // Text top/bottom padding 5*2 + card top/bottom spacing 6*2
        CGFloat total = textHeight + 5 * 2 + 6 * 2;
        return MAX(total, 40.0);
    }

    // Tool-call message and AI text coexist in the bubble; calculate height as for regular bubble text
    NSString *content = message.isToolCall ? [self displayContentForMessage:message] : (message.content ?: @"");
    CGFloat maxBubbleWidth = width * kMsgMaxBubbleWidthRatio;
    CGFloat textWidth = maxBubbleWidth - 2 * kMsgBubblePadding;
    if (textWidth < 20) textWidth = 20;

    BOOL isUser = [message.role isEqualToString:@"user"];
    CGSize textSize;
    if (isUser || !enabled) {
        UIFont *font = [UIFont systemFontOfSize:kMsgFontSize];
        CGRect r = [content boundingRectWithSize:CGSizeMake(textWidth, CGFLOAT_MAX)
                                         options:NSStringDrawingUsesLineFragmentOrigin | NSStringDrawingUsesFontLeading
                                      attributes:@{NSFontAttributeName: font}
                                         context:nil];
        textSize = r.size;
    } else {
        NSAttributedString *attr = [MarkdownParser parseMarkdown:content baseFont:[UIFont systemFontOfSize:kMsgFontSize]];
        CGRect r = [attr boundingRectWithSize:CGSizeMake(textWidth, CGFLOAT_MAX)
                                      options:NSStringDrawingUsesLineFragmentOrigin | NSStringDrawingUsesFontLeading
                                      context:nil];
        textSize = r.size;
    }

    CGFloat textHeight = ceil(textSize.height);
    if (textHeight < 20) textHeight = 20;
    CGFloat total = textHeight + 2 * kMsgBubblePadding + 2 * kMsgVerticalPadding;
    return MAX(total, 48.0);
}

@end