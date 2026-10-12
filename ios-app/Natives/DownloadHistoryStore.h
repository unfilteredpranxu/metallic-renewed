#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/**
 * Download-history store (singleton).
 * Records completed download-task entries (name/type/size/time/result, etc.).
 * Persists as JSON at <Home>/Library/Application Support/Amethyst/download_history.json.
 * Limit: 200 LRU entries; insert new entries at the top and trim the tail when over the limit.
 *
 * Threading: all disk I/O runs on a dedicated serial queue; the in-memory array is protected by
 * NSLock and may be accessed from any thread.
 */
@interface DownloadHistoryStore : NSObject

+ (instancetype)sharedStore;

/// Record a history entry (insert at the top; automatically trim over 200 entries). Ignore empty entries.
- (void)recordEntryWithDictionary:(NSDictionary *)entry;

/// Return all history entries (newest → oldest). Lazily load the disk file on first access.
- (NSArray<NSDictionary *> *)allEntries;

/// Clear all history (memory + delete disk file).
- (void)clearAll;

@end

NS_ASSUME_NONNULL_END
