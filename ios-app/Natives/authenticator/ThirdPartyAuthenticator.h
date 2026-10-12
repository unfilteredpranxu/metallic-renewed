#import <Foundation/Foundation.h>
#import "BaseAuthenticator.h"

@interface ThirdPartyAuthenticator : BaseAuthenticator

- (void)loginWithCallback:(Callback)callback;
- (void)refreshTokenWithCallback:(Callback)callback;
- (NSArray *)getJvmArgsForAuthlib;

/// Resolve ALI (API Location Indication) according to the authlib-injector launcher specification.
/// Expand the user's shorthand address to a complete API Root and prefetch server metadata.
/// completion is called on the main thread; resolvedURL is the final API Root (the original input on failure).
/// metadata is the server metadata JSON string (used for the prefetched argument, or nil on failure).
+ (void)resolveAuthserverURL:(NSString *)inputURL
                  completion:(void (^)(NSString *resolvedURL, NSString *_Nullable metadata))completion;

@end