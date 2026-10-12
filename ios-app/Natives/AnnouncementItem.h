//
//  AnnouncementItem.h
//  Amethyst
//
//  Announcement data model
//  Data source: the JSON API specified by general.news_url (default: https://amethyst.ct.ws/api/announcements.json)
//  Field mapping:
//    id            -> announcementId
//    title         -> title
//    date          -> date        (ISO date, e.g. "2026-07-23")
//    summary       -> summary
//    content       -> content     (Markdown body)
//    priority      -> priority    ("high" / "normal" / "low")
//    action_url    -> actionURL
//    action_title  -> actionTitle
//    image_url     -> imageURL
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface AnnouncementItem : NSObject

@property (nonatomic, copy) NSString *announcementId;
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSString *date;        // ISO date string, e.g. "2026-07-23"
@property (nonatomic, copy) NSString *summary;
@property (nonatomic, copy) NSString *content;     // Markdown-formatted body
@property (nonatomic, copy) NSString *priority;    // "high" / "normal" / "low"
@property (nonatomic, copy) NSString *actionURL;
@property (nonatomic, copy) NSString *actionTitle;
@property (nonatomic, copy) NSString *imageURL;

/// Create from a JSON dictionary (use an empty string as a fallback when a field is missing).
+ (nullable instancetype)itemFromDictionary:(NSDictionary *)dict;

/// Format the date for display (e.g. "July 23, 2026").
- (NSString *)formattedDateString;

@end

NS_ASSUME_NONNULL_END
