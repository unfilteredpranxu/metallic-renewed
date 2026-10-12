#import "ModVersion.h"

@interface ModVersion ()
- (instancetype)parseCurseForgeDictionary:(NSDictionary *)dictionary;
@end

@implementation ModVersion

- (instancetype)initWithDictionary:(NSDictionary *)dictionary {
    self = [super init];
    if (self) {
        if (![dictionary isKindOfClass:[NSDictionary class]]) {
            return nil;
        }
        // Retain the original JSON: dependency resolution (ModDependencyResolver) reads the prerequisite list from dependencies[],
        // which is not present among the flattened fields below.
        _rawDictionary = [dictionary copy];

        // CurseForge file format adaptation (recognizes gameVersions/downloadUrl/fileLength/fileDate/id/modId fields).
        // ★ [MODSRC-FIX] CurseForge returns downloadUrl:null for some files (JSON null → NSNull, not nil).
        //   The old `downloadUrl != nil` check was true for NSNull, making key existence unreliable. Now identify CurseForge files
        //   using gameVersions together with CurseForge-specific fields (modId/fileDate/releaseType) to avoid missed or incorrect matches.
        if (dictionary[@"gameVersions"] != nil &&
            (dictionary[@"downloadUrl"] != nil || dictionary[@"modId"] != nil ||
             dictionary[@"fileDate"] != nil || dictionary[@"releaseType"] != nil)) {
            return [self parseCurseForgeDictionary:dictionary];
        }

        _name = [dictionary[@"name"] isKindOfClass:[NSString class]] ? dictionary[@"name"] : @"Unknown Name";
        _versionNumber = [dictionary[@"version_number"] isKindOfClass:[NSString class]] ? dictionary[@"version_number"] : @"Unknown Version";
        _datePublished = [dictionary[@"date_published"] isKindOfClass:[NSString class]] ? dictionary[@"date_published"] : @"";
        _gameVersions = [dictionary[@"game_versions"] isKindOfClass:[NSArray class]] ? dictionary[@"game_versions"] : @[];
        _loaders = [dictionary[@"loaders"] isKindOfClass:[NSArray class]] ? dictionary[@"loaders"] : @[];
        // Release type (Modrinth: release/beta/alpha).
        _versionType = [dictionary[@"version_type"] isKindOfClass:[NSString class]] ? dictionary[@"version_type"] : @"release";

        NSArray *files = [dictionary[@"files"] isKindOfClass:[NSArray class]] ? dictionary[@"files"] : @[];
        _primaryFile = [files firstObject];
    }
    return self;
}

- (instancetype)parseCurseForgeDictionary:(NSDictionary *)dictionary {
    _apiSource = 2; // CurseForge
    // Filename.
    NSString *fileName = dictionary[@"fileName"];
    // Release type (CurseForge: 1=release, 2=beta, 3=alpha).
    NSInteger releaseType = [dictionary[@"releaseType"] integerValue];
    if (releaseType == 2) {
        _versionType = @"beta";
    } else if (releaseType == 3) {
        _versionType = @"alpha";
    } else {
        _versionType = @"release";
    }
    // File size.
    if (dictionary[@"fileLength"]) {
        _fileSize = dictionary[@"fileLength"];
    }
    // Publish time (fileDate format: ISO8601; stored as a string to match the Modrinth path).
    NSString *dateStr = dictionary[@"fileDate"];
    if (dateStr) {
        _datePublished = dateStr;
    }
    // File ID and project ID.
    _fileId = [dictionary[@"id"] stringValue];
    _projectId = [dictionary[@"modId"] stringValue];
    // gameVersions array (contains game versions and loaders).
    NSArray *gameVersions = dictionary[@"gameVersions"];
    NSString *gameVer = nil;
    NSMutableArray *loaders = [NSMutableArray array];
    NSMutableArray *gameVerArr = [NSMutableArray array];
    for (NSString *v in gameVersions) {
        if ([v hasPrefix:@"Fabric"] || [v hasPrefix:@"Forge"] || [v hasPrefix:@"NeoForge"] || [v hasPrefix:@"Quilt"]) {
            [loaders addObject:v];
        } else if ([v containsString:@"."]) {
            if (gameVer == nil) {
                gameVer = v;
            }
            [gameVerArr addObject:v];
        }
    }
    _gameVersions = [gameVerArr copy];
    _loaders = [loaders copy];
    _name = [NSString stringWithFormat:@"%@ (%@)", fileName ?: @"", gameVer ?: @""];
    _versionNumber = _fileId;
    // hashes（algo 1 = SHA1）
    NSString *sha1 = nil;
    NSArray *hashes = dictionary[@"hashes"];
    for (NSDictionary *h in hashes) {
        if ([h[@"algo"] integerValue] == 1) {
            sha1 = h[@"value"];
        }
    }
    // Build primaryFile for compatibility with the Modrinth format (url/filename/hashes).
    NSMutableDictionary *pf = [NSMutableDictionary dictionary];
    // ★ [MODSRC-FIX] Accept only a nonempty string URL. The old `if (dictionary[@"downloadUrl"])` check was true for
    //   JSON null (an NSNull object), which wrote NSNull into pf["url]. The download page then failed
    //   `[primaryFile[@"url"] isKindOfClass:NSString.class]` and showed i18n_str_265.
    id downloadURLValue = dictionary[@"downloadUrl"];
    if ([downloadURLValue isKindOfClass:[NSString class]] && [(NSString *)downloadURLValue length] > 0) {
        pf[@"url"] = downloadURLValue;
    }
    if (fileName) {
        pf[@"filename"] = fileName;
    }
    pf[@"primary"] = @(YES);
    if (sha1) {
        pf[@"hashes"] = @{ @"sha1": sha1 };
    }
    _primaryFile = [pf copy];
    return self;
}

@end
