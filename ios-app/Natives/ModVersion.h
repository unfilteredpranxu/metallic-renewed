#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface ModVersion : NSObject

@property (nonatomic, copy, readonly) NSString *name;
@property (nonatomic, copy, readonly) NSString *versionNumber;
@property (nonatomic, copy, readonly) NSString *datePublished; // ISO 8601 string
@property (nonatomic, copy, readonly) NSArray<NSString *> *gameVersions;
@property (nonatomic, copy, readonly) NSArray<NSString *> *loaders;
@property (nonatomic, copy, readonly, nullable) NSDictionary *primaryFile; // The first file in the files array
// Release type (Modrinth: release/beta/alpha; CurseForge: 1=release/2=beta/3=alpha).
// Used to display a release-type badge in the version row (based on FCL/ZL2 Release/Beta/Alpha labels).
@property (nonatomic, copy, readonly) NSString *versionType;

// Source API (1=Modrinth, 2=CurseForge).
@property (nonatomic, assign) NSInteger apiSource;
// File size (bytes).
@property (nonatomic, strong, nullable) NSNumber *fileSize;
// CurseForge file ID
@property (nonatomic, copy, nullable) NSString *fileId;
// CurseForge project ID
@property (nonatomic, copy, nullable) NSString *projectId;

/// Original JSON (dependency resolution needs to read dependencies[]; the other fields are flattened).
/// Retains the original dictionary for both Modrinth and CurseForge.
@property (nonatomic, copy, readonly, nullable) NSDictionary *rawDictionary;

- (nullable instancetype)initWithDictionary:(NSDictionary *)dictionary;

@end

NS_ASSUME_NONNULL_END
