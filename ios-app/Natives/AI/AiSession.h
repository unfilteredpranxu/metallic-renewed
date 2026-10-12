//
//  AiSession.h
//  Amethyst
//
//  AI session data model: contains the message list and metadata, with JSON serialization for persistence.
//

#import <Foundation/Foundation.h>
#import "AiMessage.h"

NS_ASSUME_NONNULL_BEGIN

@interface AiSession : NSObject

/// Unique session identifier (UUID)
@property (nonatomic, copy) NSString *identifier;
/// Session title (automatically named from the first user message)
@property (nonatomic, copy) NSString *title;
/// Creation time
@property (nonatomic, strong) NSDate *createdAt;
/// Last updated time
@property (nonatomic, strong) NSDate *updatedAt;
/// Whether the session is pinned
@property (nonatomic, assign) BOOL pinned;
/// Message list
@property (nonatomic, strong) NSMutableArray<AiMessage *> *messages;

/// Convenience initializer: identifier uses NSUUID; created/updated use the current time
+ (instancetype)sessionWithTitle:(NSString *)title;

/// JSON serialization
- (instancetype)initWithDictionary:(NSDictionary *)dict;
- (NSDictionary *)toDictionary;

@end

NS_ASSUME_NONNULL_END