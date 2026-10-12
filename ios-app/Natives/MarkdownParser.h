//
//  MarkdownParser.h
//  Amethyst
//
//  Lightweight Markdown → NSAttributedString converter
//  Implemented with UIKit only; no third-party dependencies. Supports: h1-h3, bold **text**, italic *text*,
//  inline code `code`, unordered lists - item, ordered lists 1. item, links [text](url),
//  horizontal rules ---, paragraphs, and block quotes > text.
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface MarkdownParser : NSObject

/// Converts Markdown text to an NSAttributedString (base font is the system 15pt font).
/// @param markdown Original Markdown text.
+ (NSAttributedString *)parseMarkdown:(NSString *)markdown;

/// Converts Markdown text to an NSAttributedString.
/// @param markdown Original Markdown text.
/// @param baseFont Base font (defaults to the system 15pt font).
+ (NSAttributedString *)parseMarkdown:(NSString *)markdown baseFont:(UIFont *)baseFont;

@end

NS_ASSUME_NONNULL_END
