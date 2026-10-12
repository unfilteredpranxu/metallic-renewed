//
//  AiDownloadProbe.m
//  Amethyst
//

#import "AiDownloadProbe.h"
#import "DownloadTaskManager.h"
#import "DownloadTaskItem.h"

@interface AiDownloadProbe ()
@property (nonatomic, copy) NSString *internalName;
@end

@implementation AiDownloadProbe

- (instancetype)initWithName:(NSString *)name {
    self = [super init];
    if (self) {
        _internalName = [name copy] ?: @"";
    }
    return self;
}

- (NSString *)name {
    return self.internalName;
}

- (AiToolPermission)permission {
    return AiToolPermissionReadOnly;
}

- (NSString *)summary {
    return @"Query the live status of all download tasks in the download center (for background downloads started by install_* tools with wait=false)."
           "\nNo parameters."
           "\nReturns JSON: {count, tasks:[{taskId, name, type, state, progress, downloadedBytes, totalBytes, speed, downloadSource}], summary:{count by state}}."
           "\nstate values: pending/downloading/paused/completed/cancelled/failed; progress is 0~1 (-1 means unknown); speed is in bytes/s."
           "\nBoundary: query only; guide the user to pause/cancel manually in the download center.";
}

+ (NSString *)stateName:(DownloadTaskState)state {
    switch (state) {
        case DownloadTaskStatePending:     return @"Pending";
        case DownloadTaskStateDownloading: return @"Downloading";
        case DownloadTaskStatePaused:      return @"Paused";
        case DownloadTaskStateCompleted:   return @"Completed";
        case DownloadTaskStateCancelled:   return @"Cancelled";
        case DownloadTaskStateFailed:      return @"Failed";
    }
    return @"Unknown";
}

- (void)execute:(NSDictionary<NSString *, id> *)params
     completion:(void (^)(NSString * _Nullable result, NSError * _Nullable error))completion {
    if (!completion) return;

    NSArray<DownloadTaskItem *> *tasks = [[DownloadTaskManager sharedManager] allTasks];

    if (tasks.count == 0) {
        completion(@"There are no current download tasks.", nil);
        return;
    }

    NSMutableArray *items = [NSMutableArray array];
    NSMutableDictionary<NSString *, NSNumber *> *summary = [NSMutableDictionary dictionary];
    for (DownloadTaskItem *task in tasks) {
        NSString *state = [AiDownloadProbe stateName:task.state];
        summary[state] = @((summary[state] ? [summary[state] integerValue] : 0) + 1);
        NSString *name = task.displayName.length > 0 ? task.displayName : (task.resourceName ?: @"");
        [items addObject:@{
            @"taskId": task.taskId ?: @"",
            @"name": name ?: @"",
            @"type": task.resourceType ?: @"",
            @"state": state,
            @"progress": @(task.progress),
            @"downloadedBytes": @(task.downloadedSize),
            @"totalBytes": @(task.totalSize),
            @"speed": @(task.speed),
            @"downloadSource": task.downloadSource ?: @"",
        }];
    }

    NSDictionary *result = @{
        @"count": @(items.count),
        @"tasks": items,
        @"summary": summary,
    };
    NSError *jsonError = nil;
    NSData *data = [NSJSONSerialization dataWithJSONObject:result options:NSJSONWritingPrettyPrinted error:&jsonError];
    if (!data || jsonError) {
        completion([NSString stringWithFormat:@"%lu download tasks in total (serialization failed: %@)",
                    (unsigned long)items.count, jsonError.localizedDescription ?: @"Unknown error"], nil);
        return;
    }
    NSString *json = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    completion(json ?: @"Failed to serialize download tasks", nil);
}

@end
