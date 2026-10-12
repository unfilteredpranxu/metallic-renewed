//
//  MinecraftNewsItem.h
//  Amethyst
//
//  Minecraft official news data model
//  Field definitions based on PCL-CE (PCL.Core/Model/Homepage/News/NewsItem.cs)
//
//  Data source: net-secondary.web.minecraft-services.net/api/v1.0/{locale}/search
//  Field mapping:
//    title          -> title
//    url            -> articleURL (absolute URL; no concatenation needed)
//    description    -> summary (HTML entities must be decoded)
//    author         -> author
//    image          -> imageURL (absolute URL)
//    imageAltText   -> imageAltText
//    time           -> publishDate (Unix timestamp in seconds)
//    type           -> newsType
//    locale         -> locale
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface MinecraftNewsItem : NSObject

/// Article title.
@property (nonatomic, copy) NSString *title;
/// Article detail page URL (absolute URL).
@property (nonatomic, copy) NSString *articleURL;
/// Summary (HTML entities returned by the API have been decoded).
@property (nonatomic, copy) NSString *summary;
/// Author.
@property (nonatomic, copy, nullable) NSString *author;
/// Cover image URL (absolute URL).
@property (nonatomic, copy) NSString *imageURL;
/// Cover image alt text.
@property (nonatomic, copy, nullable) NSString *imageAltText;
/// Publish time (Unix timestamp in seconds).
@property (nonatomic, assign) NSTimeInterval publishDate;
/// Type (e.g. "News").
@property (nonatomic, copy, nullable) NSString *newsType;
/// Locale (e.g. "zh-cn").
@property (nonatomic, copy, nullable) NSString *locale;

/// Creates an instance from an API response dictionary (uses an empty string for missing fields).
+ (instancetype)itemFromDictionary:(NSDictionary *)dict;

/// Formats as a local date string (e.g. "2026-07-16").
- (NSString *)formattedDateString;

@end

NS_ASSUME_NONNULL_END
