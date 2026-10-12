//
//  ModDependencyResolver.m
//  Automatic mod dependency resolution (prerequisites)
//
//  The dependency-field structures differ between the two sources; normalize them here:
//
//    Modrinth  Each item from GET /project/{id}/version:
//      "dependencies": [
//        { "version_id": "xxx", "project_id": "yyy",
//          "file_name": null, "dependency_type": "required" }
//      ]
//      dependency_type ∈ required / optional / incompatible / embedded
//
//    CurseForge The data from GET /mods/{id}/files/{fid}:
//      "dependencies": [ { "modId": 394468, "relationType": 3 } ]
//      relationType: 1=Embedded 2=Optional 3=Required 4=Tool
//                    5=Incompatible 6=Include
//
//  Install only required dependencies automatically; collect optional ones for a UI notice.
//  Do not handle incompatible / embedded / tool dependencies (the first declares a conflict; the latter two are bundled or are not mods).
//

#import "ModDependencyResolver.h"
#import "installer/modpack/ModrinthAPI.h"
#import "installer/modpack/CurseForgeAPI.h"

/// Number of prerequisite lookups to run concurrently. ZL2 uses 4; keep the same limit here.
/// A lower value makes chained dependency resolution slow; a higher value may trigger source rate limiting.
static const NSInteger kMaxConcurrentLookups = 4;

/// Maximum number of projects to resolve. ZL2's MAX_DEPENDENCY_PROJECTS = 64.
/// Stop once exceeded and list the omitted projects in plan.truncated to prevent malicious/abnormal dependency graphs
/// from hanging the launcher (also protects against cycles).
static const NSInteger kMaxProjects = 64;

/// Maximum resolution depth. Normal mod dependency chains rarely exceed 6 levels; deeper graphs are considered abnormal.
static const NSInteger kMaxDepth = 8;

#pragma mark -

@implementation ModDependencyItem
- (NSString *)description {
    return [NSString stringWithFormat:@"<ModDependencyItem src=%ld project=%@ kind=%ld>",
            (long)self.apiSource, self.projectId ?: @"?", (long)self.kind];
}
@end

#pragma mark -

@implementation ModDependencyPlan
- (instancetype)init {
    if ((self = [super init])) {
        _required = @[];
        _optional = @[];
        _skippedAlreadyInstalled = @[];
        _truncated = @[];
    }
    return self;
}
@end

#pragma mark -

@interface ModDependencyResolver ()
@property(nonatomic, strong) dispatch_queue_t stateQueue;   /* Protects visited/collected. */
@property(nonatomic, strong) NSMutableSet<NSString *> *visitedKeys;
@property(nonatomic, strong) NSMutableArray<ModDependencyItem *> *collectedRequired;
@property(nonatomic, strong) NSMutableArray<ModDependencyItem *> *collectedOptional;
@property(nonatomic, strong) NSMutableArray<NSString *> *truncatedIds;
@end

@implementation ModDependencyResolver

+ (instancetype)sharedResolver {
    static ModDependencyResolver *shared = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ shared = [[ModDependencyResolver alloc] init]; });
    return shared;
}

- (instancetype)init {
    if ((self = [super init])) {
        _stateQueue = dispatch_queue_create("ame.mod.dependency.resolver", DISPATCH_QUEUE_SERIAL);
    }
    return self;
}

#pragma mark - Entry point

- (void)resolveDependenciesFromVersionDetail:(NSDictionary *)versionDetail
                                   apiSource:(NSInteger)apiSource
                        installedProjectIds:(NSSet<NSString *> *)installedProjectIds
                                      loader:(NSString *)loader
                                 gameVersion:(NSString *)gameVersion
                                  completion:(void (^)(ModDependencyPlan *, NSError *))completion {
    if (!completion) return;

    if (![versionDetail isKindOfClass:[NSDictionary class]]) {
        // If there are no version details, do not block downloads with an error; return an empty plan.
        dispatch_async(dispatch_get_main_queue(), ^{
            completion([[ModDependencyPlan alloc] init], nil);
        });
        return;
    }

    // Reset state for each resolution. The resolver is a singleton, but each resolution is a separate batch
    // and does not share state; if multiple root mods must be resolved concurrently later, use instances instead.
    self.visitedKeys = [NSMutableSet new];
    self.collectedRequired = [NSMutableArray new];
    self.collectedOptional = [NSMutableArray new];
    self.truncatedIds = [NSMutableArray new];

    NSSet<NSString *> *installed = installedProjectIds ?: [NSSet set];
    NSString *key = [self dependencyKeyForProjectId:[self projectIdFromVersionDetail:versionDetail apiSource:apiSource]];
    if (key) [self.visitedKeys addObject:key];   // Mark the root mod too, to prevent a dependency cycle returning to itself.

    [self expandFromVersionDetail:versionDetail
                        apiSource:apiSource
                       installed:installed
                           loader:loader
                      gameVersion:gameVersion
                            depth:0
                       completion:^(NSError *error) {
        ModDependencyPlan *plan = [[ModDependencyPlan alloc] init];
        plan.required = [self.collectedRequired copy];
        plan.optional = [self.collectedOptional copy];
        plan.skippedAlreadyInstalled = [installed.allObjects copy];
        plan.truncated = [self.truncatedIds copy];
        dispatch_async(dispatch_get_main_queue(), ^{ completion(plan, error); });
    }];
}

#pragma mark - Recursive expansion

/// Extracts direct dependencies from version details and processes them one by one (recursing as needed).
- (void)expandFromVersionDetail:(NSDictionary *)detail
                      apiSource:(NSInteger)apiSource
                     installed:(NSSet<NSString *> *)installed
                         loader:(NSString *)loader
                    gameVersion:(NSString *)gameVersion
                          depth:(NSInteger)depth
                     completion:(void (^)(NSError *))completion {
    if (depth >= kMaxDepth) {
        [self noteTruncated:@"(max depth reached)"];
        completion(nil);
        return;
    }
    if (self.collectedRequired.count >= (NSUInteger)kMaxProjects) {
        [self noteTruncated:@"(max project count reached)"];
        completion(nil);
        return;
    }

    NSArray<ModDependencyItem *> *direct = [self parseDependenciesFromDetail:detail apiSource:apiSource];
    if (direct.count == 0) {
        completion(nil);
        return;
    }

    // Process each dependency: skip visited/installed projects; enqueue new ones and expand their version details as needed.
    NSMutableArray<ModDependencyItem *> *toProcess = [NSMutableArray new];
    for (ModDependencyItem *dep in direct) {
        NSString *depKey = [self dependencyKeyForProjectId:dep.projectId];
        if (depKey == nil) continue;

        @synchronized (self.visitedKeys) {
            if ([self.visitedKeys containsObject:depKey]) continue;   // Cycle / duplicate.
            [self.visitedKeys addObject:depKey];
        }
        if (dep.projectId.length > 0 && [installed containsObject:dep.projectId]) {
            continue;   // Another version of the same project is already installed; do not install it again.
        }
        if (dep.kind == ModDependencyKindRequired) {
            @synchronized (self.collectedRequired) {
                [self.collectedRequired addObject:dep];
            }
        } else {
            @synchronized (self.collectedOptional) {
                [self.collectedOptional addObject:dep];
            }
        }
        if (dep.kind == ModDependencyKindRequired) [toProcess addObject:dep];
    }

    if (toProcess.count == 0) {
        completion(nil);
        return;
    }

    // Enforce the concurrency limit by fetching version details in batches.
    dispatch_group_t group = dispatch_group_create();
    dispatch_semaphore_t sem = dispatch_semaphore_create(kMaxConcurrentLookups);
    __block NSError *firstError = nil;

    for (ModDependencyItem *dep in toProcess) {
        dispatch_semaphore_wait(sem, DISPATCH_TIME_FOREVER);
        dispatch_group_enter(group);
        [self fetchVersionDetailForDependency:dep
                                       loader:loader
                                  gameVersion:gameVersion
                                   completion:^(NSDictionary *detail2, NSError *error) {
            if (error && firstError == nil) firstError = error;
            if ([detail2 isKindOfClass:[NSDictionary class]]) {
                // Continue expansion. Use the same semaphore to serialize work; depth+1 controls recursion depth.
                [self expandFromVersionDetail:detail2
                                    apiSource:dep.apiSource
                                   installed:installed
                                       loader:loader
                                  gameVersion:gameVersion
                                        depth:depth + 1
                                   completion:^(NSError *e2) {
                    if (e2 && firstError == nil) firstError = e2;
                    dispatch_semaphore_signal(sem);
                    dispatch_group_leave(group);
                }];
            } else {
                dispatch_semaphore_signal(sem);
                dispatch_group_leave(group);
            }
        }];
    }

    dispatch_group_notify(group, self.stateQueue, ^{
        completion(firstError);
    });
}

#pragma mark - Get dependencies

/// Extracts direct dependencies from version details (normalizes fields from both sources).
- (NSArray<ModDependencyItem *> *)parseDependenciesFromDetail:(NSDictionary *)detail apiSource:(NSInteger)apiSource {
    NSMutableArray<ModDependencyItem *> *out = [NSMutableArray new];
    id deps = detail[@"dependencies"];
    if (![deps isKindOfClass:[NSArray class]]) return out;

    for (id raw in (NSArray *)deps) {
        if (![raw isKindOfClass:[NSDictionary class]]) continue;
        NSDictionary *d = raw;
        ModDependencyItem *item = [[ModDependencyItem alloc] init];
        item.apiSource = apiSource;

        if (apiSource == 1) {
            // Modrinth
            item.projectId = [d[@"project_id"] isKindOfClass:[NSString class]] ? d[@"project_id"] : nil;
            item.versionId = [d[@"version_id"] isKindOfClass:[NSString class]] ? d[@"version_id"] : nil;
            NSString *type = [d[@"dependency_type"] isKindOfClass:[NSString class]] ? d[@"dependency_type"] : @"";
            if ([type isEqualToString:@"required"]) {
                item.kind = ModDependencyKindRequired;
            } else if ([type isEqualToString:@"optional"]) {
                item.kind = ModDependencyKindOptional;
            } else {
                continue;   // incompatible / embedded / unknown → do not handle.
            }
            // Modrinth sometimes provides only version_id, not project_id. In that case, dependencies cannot be deduplicated by project
            // or optional versions looked up; skip it rather than guessing.
            if (item.projectId.length == 0) continue;
        } else {
            // CurseForge: modId is numeric, and relationType is an enum.
            id modId = d[@"modId"];
            if (![modId respondsToSelector:@selector(description)]) continue;
            item.projectId = [modId description];
            NSInteger rel = [d[@"relationType"] integerValue];
            if (rel == 3) {
                item.kind = ModDependencyKindRequired;
            } else if (rel == 2) {
                item.kind = ModDependencyKindOptional;
            } else {
                continue;   // 1=Embedded 4=Tool 5=Incompatible 6=Include
            }
        }
        [out addObject:item];
    }
    return out;
}

#pragma mark - Fetch version details

/// Fetches the "available version details" for a dependency project to continue resolution.
/// Prefer a direct lookup by versionId (Modrinth); otherwise filter by loader/gameVersion and choose the latest.
- (void)fetchVersionDetailForDependency:(ModDependencyItem *)dep
                                 loader:(NSString *)loader
                            gameVersion:(NSString *)gameVersion
                             completion:(void (^)(NSDictionary *, NSError *))completion {
    if (!completion) return;

    // Both sources use the existing getVersionsForModWithID:. After receiving ModVersion entries,
    // select one compatible with this instance and use its rawDictionary as version details for further expansion.
    void (^handle)(NSArray<ModVersion *> *, NSError *) = ^(NSArray<ModVersion *> *versions, NSError *error) {
        if (error || versions.count == 0) {
            completion(nil, error);
            return;
        }
        ModVersion *picked = nil;
        // Prefer an exact match for gameVersions + loaders; if none match, fall back to the first version
        // (a potentially incompatible prerequisite is preferable to silently breaking the entire dependency chain).
        for (ModVersion *v in versions) {
            if (gameVersion.length > 0 && ![v.gameVersions containsObject:gameVersion]) continue;
            if (loader.length > 0 && v.loaders.count > 0) {
                NSString *lowered = loader.lowercaseString;
                BOOL loaderOK = NO;
                for (NSString *l in v.loaders) {
                    if ([[l lowercaseString] containsString:lowered] ||
                        [lowered containsString:[l lowercaseString]]) { loaderOK = YES; break; }
                }
                if (!loaderOK) continue;
            }
            picked = v;
            break;
        }
        if (picked == nil) picked = versions.firstObject;
        completion(picked.rawDictionary, nil);
    };

    if (dep.apiSource == 1) {
        [[ModrinthAPI sharedInstance] getVersionsForModWithID:dep.projectId completion:handle];
    } else {
        [[CurseForgeAPI sharedInstance] getVersionsForModWithID:dep.projectId completion:handle];
    }
}

#pragma mark - Utilities

- (NSString *)dependencyKeyForProjectId:(NSString *)projectId {
    if (projectId.length == 0) return nil;
    return projectId;
}

- (NSString *)projectIdFromVersionDetail:(NSDictionary *)detail apiSource:(NSInteger)apiSource {
    id pid = detail[@"project_id"];
    if ([pid isKindOfClass:[NSString class]] && [pid length] > 0) return pid;
    // A Modrinth version detail may provide the project ID only as "project_id";
    // CurseForge file details use "modId".
    id modId = detail[@"modId"];
    if ([modId respondsToSelector:@selector(description)]) return [modId description];
    return nil;
}

- (void)noteTruncated:(NSString *)what {
    @synchronized (self.truncatedIds) {
        [self.truncatedIds addObject:what];
    }
}

@end
