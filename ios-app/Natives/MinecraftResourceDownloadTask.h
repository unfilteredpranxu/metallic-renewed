#import <UIKit/UIKit.h>

@class AFURLSessionManager;
@class ModpackAPI;

extern NSString * const kMinecraftResourceDownloadBackgroundSessionIdentifier;

@interface MinecraftResourceDownloadTask : NSObject

+ (AFURLSessionManager *)sharedBackgroundSessionManager;

@property NSProgress *progress, *textProgress;
@property NSMutableArray *fileList, *progressList;
@property NSMutableDictionary* metadata;
@property(nonatomic, copy) void(^handleError)(void);
@property(nonatomic, copy) void(^modpackDownloadCompletion)(void);

// Retry-related properties.
@property(nonatomic) NSInteger maxRetryCount;
@property(nonatomic, readonly) NSInteger currentRetryCount;
@property(nonatomic, copy) void(^retryCallback)(NSInteger retryCount, NSInteger maxRetryCount);

// Phase 5 fix (based on FCL): list of failed files. A single-file download failure no longer cancels the whole task;
// instead, it is recorded in this array and reported to the user in the final summary. Each element is @{@"name": ..., "error": ...}.
@property(nonatomic, strong) NSMutableArray<NSDictionary *> *failedFiles;

// New method declarations (for account checks).
- (BOOL)checkAccessWithDialog:(BOOL)show;

- (void)prepareForDownload;

- (NSURLSessionDownloadTask *)createDownloadTask:(NSString *)url size:(NSUInteger)size sha:(NSString *)sha altName:(NSString *)altName toPath:(NSString *)path;
- (NSURLSessionDownloadTask *)createDownloadTask:(NSString *)url size:(NSUInteger)size sha:(NSString *)sha altName:(NSString *)altName toPath:(NSString *)path success:(void (^)())success;

// Creates a download task with retries.
- (NSURLSessionDownloadTask *)createDownloadTask:(NSString *)url size:(NSUInteger)size sha:(NSString *)sha altName:(NSString *)altName toPath:(NSString *)path retryCount:(NSInteger)retryCount success:(void (^)())success;

- (void)finishDownloadWithErrorString:(NSString *)error;

/// Cancels the entire download flow (redesign-download-ui Phase 3):
/// Called by DownloadTaskManager.cancelRawTask: via respondsToSelector:@selector(cancel).
/// When the cancel button on the unified progress page cancels a task, cancels the internal NSProgress to interrupt the flow.
/// KVO observes the cancelled state and completes using the existing path (sets the Cancelled state and removes the observer).
- (void)cancel;

- (void)downloadVersion:(NSDictionary *)version;
- (void)downloadModpackFromAPI:(ModpackAPI *)api detail:(NSDictionary *)modDetail atIndex:(NSUInteger)selectedVersion;

@end