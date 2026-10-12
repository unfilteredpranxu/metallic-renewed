#import "DownloadTaskItem.h"

NSString * const DownloadTaskResourceTypeMinecraft    = @"minecraft";
NSString * const DownloadTaskResourceTypeModloader    = @"modloader";
NSString * const DownloadTaskResourceTypeMod          = @"mod";
NSString * const DownloadTaskResourceTypeShader       = @"shader";
NSString * const DownloadTaskResourceTypeResourcePack = @"resourcepack";
NSString * const DownloadTaskResourceTypeDataPack     = @"datapack";
NSString * const DownloadTaskResourceTypeModpack      = @"modpack";
NSString * const DownloadTaskResourceTypeWorld        = @"world";
NSString * const DownloadTaskResourceTypeJavaRuntime  = @"javaruntime";

/// Snapshot-value helper: accept only a non-empty NSString; otherwise return a fallback value
/// (snapshot contents are untrusted and must be type-checked).
static NSString *PLSnapshotString(id value, NSString *fallback) {
    if ([value isKindOfClass:[NSString class]] && [(NSString *)value length] > 0) {
        return value;
    }
    return fallback;
}

@implementation DownloadTaskItem

- (instancetype)initWithResourceType:(NSString *)resourceType
                        resourceName:(NSString *)resourceName
                         displayName:(NSString *)displayName
                      downloadSource:(NSString *)downloadSource
                             rawTask:(id)rawTask
                      supportsResume:(BOOL)supportsResume
                             iconURL:(NSString *)iconURL {
    self = [super init];
    if (self) {
        _taskId = [[NSUUID UUID] UUIDString];
        _resourceType = [resourceType copy] ?: @"";
        _resourceName = [resourceName copy] ?: @"";
        _displayName = [displayName copy] ?: _resourceName;
        _downloadSource = [downloadSource copy] ?: @"official";
        _state = DownloadTaskStatePending;
        _progress = -1.0;
        _totalSize = -1;
        _downloadedSize = 0;
        _speed = 0.0;
        _estimatedTimeRemaining = 0.0;
        _completedFileCount = 0;
        _totalFileCount = 0;
        _iconURL = [iconURL copy];
        _supportsResume = supportsResume;
        _createdDate = [NSDate date];
        _rawTask = rawTask;
        _errorInfo = nil;
        _userInfo = [NSMutableDictionary dictionary];
        _retryCount = 0;
        _maxRetryCount = 3;
        _needsRecreate = NO;
        _stages = @[];
        _currentStageIndex = -1;
    }
    return self;
}

#pragma mark - Staged progress

- (PLTaskStage *)currentStage {
    if (self.currentStageIndex < 0) return nil;
    NSUInteger index = (NSUInteger)self.currentStageIndex;
    if (index >= self.stages.count) return nil;
    PLTaskStage *stage = self.stages[index];
    return [stage isKindOfClass:[PLTaskStage class]] ? stage : nil;
}

#pragma mark - Snapshot serialization

- (NSDictionary *)snapshotDictionary {
    // Export each stage snapshot (serialize an empty list when stages is empty).
    NSMutableArray<NSDictionary *> *stageSnapshots = [NSMutableArray array];
    for (PLTaskStage *stage in self.stages) {
        if ([stage isKindOfClass:[PLTaskStage class]]) {
            [stageSnapshots addObject:[stage snapshotDictionary]];
        }
    }
    return @{
        @"taskId": self.taskId ?: @"",
        @"resourceType": self.resourceType ?: @"",
        @"resourceName": self.resourceName ?: @"",
        @"displayName": self.displayName ?: @"",
        @"downloadSource": self.downloadSource ?: @"",
        @"state": @(self.state),
        @"progress": @(self.progress),
        @"totalBytes": @(self.totalSize),
        @"receivedBytes": @(self.downloadedSize),
        @"iconURL": self.iconURL ?: @"",
        @"downloadURL": self.downloadURL ?: @"",
        @"resumeDataPath": self.resumeDataPath ?: @"",
        @"supportsResume": @(self.supportsResume),
        @"retryCount": @(self.retryCount),
        @"completedFileCount": @(self.completedFileCount),
        @"totalFileCount": @(self.totalFileCount),
        @"stages": [stageSnapshots copy],
        @"currentStageIndex": @(self.currentStageIndex),
        @"timestamp": @([self.createdDate timeIntervalSince1970]),
    };
}

- (instancetype)initWithSnapshotDictionary:(NSDictionary *)snapshot {
    if (![snapshot isKindOfClass:[NSDictionary class]]) return nil;
    NSString *taskId = snapshot[@"taskId"];
    if (![taskId isKindOfClass:[NSString class]] || taskId.length == 0) return nil;

    NSString *iconURL = snapshot[@"iconURL"];
    self = [self initWithResourceType:PLSnapshotString(snapshot[@"resourceType"], @"")
                          resourceName:PLSnapshotString(snapshot[@"resourceName"], @"")
                           displayName:PLSnapshotString(snapshot[@"displayName"], @"")
                        downloadSource:PLSnapshotString(snapshot[@"downloadSource"], @"official")
                               rawTask:nil
                        supportsResume:[snapshot[@"supportsResume"] boolValue]
                               iconURL:PLSnapshotString(iconURL, nil)];
    if (!self) return nil;

    // Retain the original taskId (preserve its association with the persisted snapshot/resume-data file).
    _taskId = [taskId copy];
    _state = [snapshot[@"state"] integerValue];
    _progress = [snapshot[@"progress"] doubleValue];
    _totalSize = [snapshot[@"totalBytes"] longLongValue];
    _downloadedSize = [snapshot[@"receivedBytes"] longLongValue];
    _retryCount = [snapshot[@"retryCount"] integerValue];
    _completedFileCount = [snapshot[@"completedFileCount"] integerValue];
    _totalFileCount = [snapshot[@"totalFileCount"] integerValue];

    NSString *downloadURL = snapshot[@"downloadURL"];
    if ([downloadURL isKindOfClass:[NSString class]] && downloadURL.length > 0) {
        _downloadURL = [downloadURL copy];
    }
    NSString *resumeDataPath = snapshot[@"resumeDataPath"];
    if ([resumeDataPath isKindOfClass:[NSString class]] && resumeDataPath.length > 0) {
        _resumeDataPath = [resumeDataPath copy];
    }

    NSNumber *timestamp = snapshot[@"timestamp"];
    if ([timestamp isKindOfClass:[NSNumber class]]) {
        _createdDate = [NSDate dateWithTimeIntervalSince1970:timestamp.doubleValue];
    }

    // Stage list (older snapshots have no stages field: keep it empty, fall back to plain progress
    // display, and avoid a crash).
    NSArray *stageSnapshots = snapshot[@"stages"];
    if ([stageSnapshots isKindOfClass:[NSArray class]]) {
        NSMutableArray *stages = [NSMutableArray array];
        for (id entry in stageSnapshots) {
            if (![entry isKindOfClass:[NSDictionary class]]) continue;
            PLTaskStage *stage = [[PLTaskStage alloc] initWithSnapshotDictionary:entry];
            if (stage) [stages addObject:stage];
        }
        _stages = [stages copy];
    } else {
        _stages = @[];
    }
    // If currentStageIndex is out of range (including an empty stage list), fall back to -1 to
    // prevent out-of-bounds UI array access.
    NSInteger stageIndex = [snapshot[@"currentStageIndex"] integerValue];
    _currentStageIndex = (stageIndex >= 0 && (NSUInteger)stageIndex < _stages.count) ? stageIndex : -1;
    return self;
}

- (NSDictionary *)historyDictionary {
    NSString *name = self.displayName.length > 0 ? self.displayName : self.resourceName;
    return @{
        @"taskId": self.taskId ?: @"",
        @"name": name ?: @"",
        @"type": self.resourceType ?: @"",
        @"size": @(self.totalSize),
        @"received": @(self.downloadedSize),
        @"result": @"success",
        @"source": self.downloadSource ?: @"",
        @"time": @([[NSDate date] timeIntervalSince1970]),
    };
}

@end
