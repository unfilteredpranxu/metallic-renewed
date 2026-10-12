//
//  AnnouncementService.h
//  Amethyst
//
//  Announcement fetch service
//  Fetches the announcement list from the JSON API specified by general.news_url, with a 30-minute local cache.
//  Caches the raw NSData in NSUserDefaults and falls back to the cache if the network request fails.
//

#import <Foundation/Foundation.h>

@class AnnouncementItem;

NS_ASSUME_NONNULL_BEGIN

/// Announcement fetch completion callback.
typedef void(^AnnouncementFetchHandler)(NSArray<AnnouncementItem *> * _Nullable items,
                                        NSError * _Nullable error);

@interface AnnouncementService : NSObject

+ (instancetype)sharedService;

/// Fetch the announcement list remotely (with a 30-minute local cache).
/// @param completion Callback on the main thread.
- (void)fetchAnnouncementsWithCompletion:(AnnouncementFetchHandler)completion;

/// Force refresh (ignore the cache).
- (void)forceRefreshWithCompletion:(AnnouncementFetchHandler)completion;

/// Get cached announcements (without a network request).
- (NSArray<AnnouncementItem *> *)cachedAnnouncements;

@end

NS_ASSUME_NONNULL_END
