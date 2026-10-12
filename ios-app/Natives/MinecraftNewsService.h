//
//  MinecraftNewsService.h
//  Amethyst
//
//  Minecraft official news fetch service
//  Implementation based on PCL-CE (PCL.Core/ViewModel/Homepage/NewsViewModel.cs):
//    - Data source: https://net-secondary.web.minecraft-services.net/api/v1.0/{locale}/search
//    - Parameters: pageSize=24&sortType=Recent&category=News&newsOnly=true&page=N
//    - No authentication required; only a User-Agent header is needed.
//    - Image/link URLs are absolute; no prefix needs to be added.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class MinecraftNewsItem;

/// Error domain.
extern NSString * const MCNewsErrorDomain;

typedef NS_ENUM(NSInteger, MCNewsErrorCode) {
    MCNewsErrorCodeNetwork = 1,
    MCNewsErrorCodeParsing,
    MCNewsErrorCodeEmpty,
};

/// Completion callback for fetching a single news item.
typedef void(^MCNewsFetchHandler)(NSArray<MinecraftNewsItem *> *items,
                                  NSInteger totalCount,
                                  NSError * _Nullable error);

@interface MinecraftNewsService : NSObject

+ (instancetype)sharedService;

/// Locale for the current request (defaults to zh-cn; can be set to follow the system language).
@property (nonatomic, copy) NSString *locale;

/// Fetches a news list.
/// @param page Page number (starting at 1).
/// @param pageSize Number of items per page (PCL-CE uses 24).
/// @param completion Main-thread callback; items contains this page's news, and totalCount is the total item count.
- (void)fetchNewsWithPage:(NSInteger)page
                 pageSize:(NSInteger)pageSize
               completion:(MCNewsFetchHandler)completion;

/// Convenience method to fetch the first page of news (page=1, pageSize=24).
- (void)fetchLatestNewsWithCompletion:(MCNewsFetchHandler)completion;

/// Link safety check (based on PCL-CE IsSafeNewsLink).
/// Only allows minecraft.net, minecraft-services.net, microsoft.com, and their subdomains.
+ (BOOL)isSafeNewsLink:(NSString *)urlString;

@end

NS_ASSUME_NONNULL_END
