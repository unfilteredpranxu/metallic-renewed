#import <Security/Security.h>
#import "BaseAuthenticator.h"
#import "ThirdPartyAuthenticator.h"
#import "../LauncherPreferences.h"
#import "../ios_uikit_bridge.h"
#import "../utils.h"

@implementation BaseAuthenticator

static BaseAuthenticator *current = nil;

+ (id)current {
    if (current == nil) {
        // ★ [ACCT-DUP-MS] Idempotently merge existing duplicates at startup: combine legacy records for the same account,
        //   and redirect selected_account to the retained record so old duplicates (such as five copies of one Microsoft account) do not reappear.
        [self deduplicateAccountsDirectory];
        // selected_account now stores accountId (legacy versions stored username; loadSavedName migrates it automatically).
        NSString *savedAccount = getPrefObject(@"internal.selected_account");
        if (savedAccount.length > 0) {
            [self loadSavedName:savedAccount];
        }
    }
    return current;
}

+ (void)setCurrent:(BaseAuthenticator *)auth {
    current = auth;
}

/// Generate a unique accountId from account data.
/// - Microsoft account: use xuid (Xbox User Hash, globally unique and stable across logins).
/// - Third-party account: use profileId (the stable profile UUID assigned by the authentication server).
/// - Local account: generate a random UUID because there is no natural unique ID.
/// This distinguishes accounts with the same name and avoids filename collisions.
+ (NSString *)generateAccountIdForData:(NSMutableDictionary *)authData {
    // Microsoft account: prefer xuid (uhs in the XSTS response, globally unique and stable).
    NSString *xuid = authData[@"xuid"];
    if (xuid && [xuid length] > 0) {
        return xuid;
    }
    // Third-party account: use profileId (the stable profile UUID assigned by the authentication server).
    NSString *profileId = authData[@"profileId"];
    if (profileId && [profileId length] > 0 &&
        ![profileId isEqualToString:@"00000000-0000-0000-0000-000000000000"]) {
        return profileId;
    }
    // Local account: generate a random UUID because there is no natural unique ID.
    return [[NSUUID UUID] UUIDString];
}

#pragma mark - ★ [ACCT-DUP] Idempotent storage deduplication (account identity keys / existing-record cleanup)

/// Account identity key used to determine whether records represent the same account.
///   · Microsoft (has xuid) → "ms:<xuid>"
///   · Third-party (has clientToken) → "tp:<authserver>|<profileId>", falling back to "…|u:<username>" without profileId.
///   · Local (no xuid/clientToken/valid expiresAt) → "local:<username>"
/// Returns nil when a key field is missing, so callers **skip deduplication** (a missed merge is safer than a false merge).
+ (NSString *)accountIdentityKeyForData:(NSDictionary *)authData {
    if (![authData isKindOfClass:[NSDictionary class]]) {
        return nil;
    }
    // Microsoft: xuid is globally unique and stable.
    NSString *xuid = authData[@"xuid"];
    if ([xuid isKindOfClass:[NSString class]] && xuid.length > 0) {
        return [NSString stringWithFormat:@"ms:%@", xuid];
    }
    // Third-party: authserver + profileId (profile UUID) is unique and stable.
    if (authData[@"clientToken"] != nil) {
        NSString *server = authData[@"authserver"];
        if (![server isKindOfClass:[NSString class]]) {
            server = @"";
        } else {
            // Normalize by trimming surrounding whitespace, removing trailing slashes, and lowercasing;
            // variations in how the same server is written should not produce separate identity keys.
            server = [server stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
            while ([server hasSuffix:@"/"]) {
                server = [server substringToIndex:server.length - 1];
            }
            server = server.lowercaseString;
        }
        NSString *pid = authData[@"profileId"];
        if ([pid isKindOfClass:[NSString class]] && pid.length > 0 &&
            ![pid isEqualToString:@"00000000-0000-0000-0000-000000000000"]) {
            return [NSString stringWithFormat:@"tp:%@|%@", server, pid];
        }
        NSString *user = authData[@"username"];
        if ([user isKindOfClass:[NSString class]] && user.length > 0) {
            return [NSString stringWithFormat:@"tp:%@|u:%@", server, user];
        }
        return nil;
    }
    // A nonzero expiresAt without xuid may be an incomplete Microsoft record; its identity is indeterminate, so do not deduplicate it.
    if ([authData[@"expiresAt"] longValue] != 0) {
        return nil;
    }
    // Local account: there is no natural unique ID, so matching names are treated as the same account (the UI cannot distinguish them).
    NSString *user = authData[@"username"];
    if ([user isKindOfClass:[NSString class]] && user.length > 0) {
        return [NSString stringWithFormat:@"local:%@", user];
    }
    return nil;
}

#pragma mark - ★ [ACCT-DUP-MS] Microsoft fallback identity keys (layers: xuid → profileId(uuid) → gamertag+username)

/// Normalize by trimming surrounding whitespace and lowercasing (for comparison only; not written to disk).
static NSString *ameNormString(NSString *s) {
    if (![s isKindOfClass:[NSString class]]) {
        return @"";
    }
    return [[s stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] lowercaseString];
}

/// Account type: 0=local, 1=Microsoft, 2=third-party.
static NSInteger ameAccountKind(NSDictionary *data) {
    if (data[@"clientToken"] != nil) {
        return 2;
    }
    if (data[@"xboxGamertag"] != nil) {
        return 1;
    }
    // A nonzero expiry without gamertag or clientToken indicates an old/incomplete Microsoft account; treat it as Microsoft
    // to avoid misclassifying it as local and merging it with a local account of the same name.
    if ([data[@"expiresAt"] longValue] != 0) {
        return 1;
    }
    return 0;
}

/// Disjoint-set union: find the root (with path compression).
static NSInteger ameFindRoot(NSMutableArray<NSNumber *> *parent, NSInteger x) {
    while (parent[x].integerValue != x) {
        parent[x] = parent[parent[x].integerValue];
        x = parent[x].integerValue;
    }
    return x;
}

/// Ordered identity signals (strongest to weakest). Two accounts are treated as identical if they **share any signal**.
///   · Microsoft: ms:<xuid> → ms:uuid:<profileId> → ms:gt:<gamertag>|<username>
///   · Third-party: tp:<server>|<profileId> → tp:<server>|u:<username>
///   · Local: local:<username>
/// Each signal is produced only when its fields exist and are nonempty: missing xuid falls back to UUID, then gamertag.
/// If no signal can be produced, the record is excluded from deduplication. This also lets incomplete Microsoft records
/// with expiresAt but no xuid be merged when their UUID or gamertag+username matches.
+ (NSArray<NSString *> *)accountIdentitySignalsForData:(NSDictionary *)authData {
    if (![authData isKindOfClass:[NSDictionary class]]) {
        return @[];
    }
    NSMutableArray<NSString *> *signals = [NSMutableArray array];
    NSInteger kind = ameAccountKind(authData);

    if (kind == 2) {
        // Third-party: normalized authserver + profileId (profile UUID), falling back to username without profileId.
        NSString *server = authData[@"authserver"];
        if (![server isKindOfClass:[NSString class]]) {
            server = @"";
        } else {
            server = [server stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
            while ([server hasSuffix:@"/"]) {
                server = [server substringToIndex:server.length - 1];
            }
            server = server.lowercaseString;
        }
        NSString *pid = [authData[@"profileId"] isKindOfClass:[NSString class]] ? authData[@"profileId"] : @"";
        if (pid.length > 0 && ![pid isEqualToString:@"00000000-0000-0000-0000-000000000000"]) {
            [signals addObject:[NSString stringWithFormat:@"tp:%@|%@", server, pid.lowercaseString]];
        }
        NSString *user = [authData[@"username"] isKindOfClass:[NSString class]] ? authData[@"username"] : @"";
        if (user.length > 0) {
            [signals addObject:[NSString stringWithFormat:@"tp:%@|u:%@", server, user.lowercaseString]];
        }
        return signals;
    }

    if (kind == 1) {
        // Microsoft: xuid (strongest signal).
        NSString *xuid = [authData[@"xuid"] isKindOfClass:[NSString class]] ? authData[@"xuid"] : @"";
        if (xuid.length > 0) {
            [signals addObject:[NSString stringWithFormat:@"ms:%@", xuid]];
        }
        // Microsoft: Minecraft profile UUID (legacy records often have this but lack xuid).
        NSString *pid = [authData[@"profileId"] isKindOfClass:[NSString class]] ? authData[@"profileId"] : @"";
        if (pid.length > 0 && ![pid isEqualToString:@"00000000-0000-0000-0000-000000000000"]) {
            [signals addObject:[NSString stringWithFormat:@"ms:uuid:%@", pid.lowercaseString]];
        }
        // Microsoft fallback: produce a signal only when both gamertag and username match (**username confirms the account identity**).
        // If only the gamertag matches, produce no signal and do not merge; log it as a suspected duplicate and retain both.
        NSString *gt = ameNormString(authData[@"xboxGamertag"]);
        NSString *user = ameNormString(authData[@"username"]);
        if (gt.length > 0 && user.length > 0) {
            [signals addObject:[NSString stringWithFormat:@"ms:gt:%@|%@", gt, user]];
        }
        return signals;
    }

    // Local: matching names identify the same account (consistent with existing [ACCT-DUP] behavior).
    NSString *user = authData[@"username"];
    if ([user isKindOfClass:[NSString class]] && user.length > 0) {
        [signals addObject:[NSString stringWithFormat:@"local:%@", user]];
    }
    return signals;
}

/// Whether two account records represent the same account (share any identity signal).
+ (BOOL)accountData:(NSDictionary *)a matchesAccountData:(NSDictionary *)b {
    NSArray<NSString *> *sa = [self accountIdentitySignalsForData:a];
    NSArray<NSString *> *sb = [self accountIdentitySignalsForData:b];
    if (sa.count == 0 || sb.count == 0) {
        return NO;
    }
    for (NSString *k in sa) {
        if ([sb containsObject:k]) {
            return YES;
        }
    }
    return NO;
}

/// The representative signal shared by two account records (for merge logs; nil if none is shared).
+ (NSString *)sharedSignalBetween:(NSDictionary *)a and:(NSDictionary *)b {
    NSArray<NSString *> *sa = [self accountIdentitySignalsForData:a];
    NSArray<NSString *> *sb = [self accountIdentitySignalsForData:b];
    for (NSString *k in sa) {
        if ([sb containsObject:k]) {
            return k;
        }
    }
    return nil;
}

/// The accountId of the first other matching account in the directory whose accountId != excludeId (or nil).
+ (NSString *)existingAccountIdForData:(NSDictionary *)authData excluding:(NSString *)excludeId {
    NSString *dir = [self accountsDirectoryPath];
    NSArray *files = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:dir error:nil];
    if (![files isKindOfClass:[NSArray class]]) {
        return nil;
    }
    for (NSString *file in files) {
        if (![file hasSuffix:@".json"]) continue;
        NSString *accountId = [file stringByDeletingPathExtension];
        if (excludeId.length > 0 && [accountId isEqualToString:excludeId]) continue;
        NSMutableDictionary *data = parseJSONFromFile([dir stringByAppendingPathComponent:file]);
        if (data == nil || data[@"NSErrorObject"] != nil) continue;
        if ([self accountData:authData matchesAccountData:data]) {
            return accountId;
        }
    }
    return nil;
}

/// Account directory path (POJAV_HOME/accounts).
+ (NSString *)accountsDirectoryPath {
    return [NSString stringWithFormat:@"%s/accounts", getenv("POJAV_HOME")];
}

/// The accountId of the first other account in the directory with the same identityKey and accountId != excludeId (or nil).
+ (NSString *)existingAccountIdForIdentityKey:(NSString *)identityKey excluding:(NSString *)excludeId {
    if (identityKey.length == 0) {
        return nil;
    }
    NSString *dir = [self accountsDirectoryPath];
    NSArray *files = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:dir error:nil];
    if (![files isKindOfClass:[NSArray class]]) {
        return nil;
    }
    for (NSString *file in files) {
        if (![file hasSuffix:@".json"]) continue;
        NSString *accountId = [file stringByDeletingPathExtension];
        if (excludeId.length > 0 && [accountId isEqualToString:excludeId]) continue;
        NSMutableDictionary *data = parseJSONFromFile([dir stringByAppendingPathComponent:file]);
        if (data == nil || data[@"NSErrorObject"] != nil) continue;
        NSString *key = [self accountIdentityKeyForData:data];
        if (key.length > 0 && [key isEqualToString:identityKey]) {
            return accountId;
        }
    }
    return nil;
}

/// ★ [ACCT-DUP-MS] Existing-record cleanup: merge duplicate files for the **same account** in the directory and delete the rest.
///
/// Uses **disjoint-set union + layered identity signals** (see accountIdentitySignalsForData:): records are the same account
/// if they share any signal (xuid / profileId(uuid) / gamertag+username / local username).
/// An incomplete Microsoft record with expiresAt but no xuid can still be merged when its UUID or gamertag+username matches.
///
/// Keep one record per group, preferring the selected_account target, then the record with the most fields, then the newest mtime.
/// **Backfill missing fields** from deleted records into the retained record (do not overwrite existing nonempty values, except accountId), then save it.
/// **Log and retain** uncertain matches (Microsoft records with the same gamertag but different usernames).
/// **Keep valid multi-account records with different gamertags, xuids, or profileIds untouched.**
+ (NSInteger)deduplicateAccountsDirectory {
    NSString *dir = [self accountsDirectoryPath];
    NSFileManager *fm = [NSFileManager defaultManager];
    NSArray *files = [fm contentsOfDirectoryAtPath:dir error:nil];
    if (![files isKindOfClass:[NSArray class]]) {
        return 0;
    }

    // 1) Load all valid account files (corrupt files are neither included nor deleted).
    NSMutableArray<NSMutableDictionary *> *nodes = [NSMutableArray array];
    for (NSString *file in files) {
        if (![file hasSuffix:@".json"]) continue;
        NSString *path = [dir stringByAppendingPathComponent:file];
        NSMutableDictionary *data = parseJSONFromFile(path);
        if (data == nil || data[@"NSErrorObject"] != nil) continue;
        NSDate *mtime = [fm attributesOfItemAtPath:path error:nil][NSFileModificationDate] ?: [NSDate distantPast];
        [nodes addObject:[@{
            @"id": [file stringByDeletingPathExtension],
            @"path": path,
            @"data": data,
            @"signals": [NSSet setWithArray:[self accountIdentitySignalsForData:data]],
            @"mtime": mtime,
        } mutableCopy]];
    }
    if (nodes.count < 2) {
        return 0;
    }

    // 2) Disjoint-set union: sharing any identity signal means the records are the same account.
    NSInteger n = (NSInteger)nodes.count;
    NSMutableArray<NSNumber *> *parent = [NSMutableArray array];
    for (NSInteger i = 0; i < n; i++) {
        [parent addObject:@(i)];
    }
    for (NSInteger i = 0; i < n; i++) {
        for (NSInteger j = i + 1; j < n; j++) {
            NSSet *si = nodes[i][@"signals"];
            NSSet *sj = nodes[j][@"signals"];
            if (si.count == 0 || sj.count == 0) {
                continue;
            }
            NSString *shared = nil;
            for (NSString *k in si) {
                if ([sj containsObject:k]) { shared = k; break; }
            }
            if (shared == nil) {
                continue;
            }
            // ★ Merge log: record which key matched which two entries (for on-device verification).
            NSLog(@"[ACCT-DUP-MS] union by key '%@': %@ <-> %@",
                  shared, nodes[i][@"id"], nodes[j][@"id"]);
            if (ameFindRoot(parent, i) != ameFindRoot(parent, j)) {
                parent[ameFindRoot(parent, j)] = @(ameFindRoot(parent, i));
            }
        }
    }

    // 3) Group records (root → member indices).
    NSMutableDictionary<NSNumber *, NSMutableArray<NSNumber *> *> *groupOf = [NSMutableDictionary dictionary];
    for (NSInteger i = 0; i < n; i++) {
        NSNumber *root = @(ameFindRoot(parent, i));
        NSMutableArray *g = groupOf[root];
        if (g == nil) { g = [NSMutableArray array]; groupOf[root] = g; }
        [g addObject:@(i)];
    }

    // 4) Suspected but unconfirmed duplicates: log them and retain both.
    for (NSInteger i = 0; i < n; i++) {
        for (NSInteger j = i + 1; j < n; j++) {
            if (ameFindRoot(parent, i) == ameFindRoot(parent, j)) continue;
            if (ameAccountKind(nodes[i][@"data"]) == 1 && ameAccountKind(nodes[j][@"data"]) == 1) {
                NSString *gti = ameNormString(nodes[i][@"data"][@"xboxGamertag"]);
                NSString *gtj = ameNormString(nodes[j][@"data"][@"xboxGamertag"]);
                if (gti.length > 0 && [gti isEqualToString:gtj]) {
                    NSLog(@"[ACCT-DUP-MS] suspect duplicate but NOT merged (same gamertag '%@', different/absent username): %@ vs %@ => keep both",
                          gti, nodes[i][@"id"], nodes[j][@"id"]);
                }
            }
        }
    }

    // 5) Retain one record per group; backfill its fields and delete the rest.
    NSString *selected = getPrefObject(@"internal.selected_account");
    NSArray *scoreKeys = @[@"xuid", @"profileId", @"xboxGamertag", @"username",
                           @"expiresAt", @"profilePicURL", @"uuid", @"authserver", @"clientToken"];
    NSInteger removed = 0;
    for (NSNumber *root in groupOf) {
        NSArray<NSNumber *> *g = groupOf[root];
        if (g.count < 2) continue;

        // Retention priority: (a) selected_account target > (b) most complete fields > (c) newest mtime > (d) first entry.
        NSInteger keepIdx = g[0].integerValue;
        BOOL keepIsSelected = (selected.length > 0 && [nodes[keepIdx][@"id"] isEqualToString:selected]);
        for (NSNumber *idxN in g) {
            if (selected.length > 0 && [nodes[idxN.integerValue][@"id"] isEqualToString:selected]) {
                keepIdx = idxN.integerValue;
                keepIsSelected = YES;
                break;
            }
        }
        if (!keepIsSelected) {
            NSInteger bestScore = -1;
            for (NSNumber *idxN in g) {
                NSDictionary *d = nodes[idxN.integerValue][@"data"];
                NSInteger score = 0;
                for (NSString *k in scoreKeys) {
                    id v = d[k];
                    if (v != nil && ![v isEqual:@""]) score++;
                }
                NSDictionary *node = nodes[idxN.integerValue];
                if (score > bestScore ||
                    (score == bestScore && [node[@"mtime"] compare:nodes[keepIdx][@"mtime"]] == NSOrderedDescending)) {
                    bestScore = score;
                    keepIdx = idxN.integerValue;
                }
            }
        }

        // Representative signal (for merge logs).
        NSString *keyLog = nil;
        for (NSNumber *idxN in g) {
            if (idxN.integerValue == keepIdx) continue;
            keyLog = [self sharedSignalBetween:nodes[keepIdx][@"data"] and:nodes[idxN.integerValue][@"data"]];
            if (keyLog.length > 0) break;
        }

        // Backfill fields and delete the other records.
        NSMutableDictionary *keepData = nodes[keepIdx][@"data"];
        NSMutableArray<NSString *> *removedIds = [NSMutableArray array];
        BOOL selectedSurvives = NO;
        for (NSNumber *idxN in g) {
            NSInteger idx = idxN.integerValue;
            if ([nodes[idx][@"id"] isEqualToString:selected]) selectedSurvives = YES;
            if (idx == keepIdx) continue;
            NSDictionary *other = nodes[idx][@"data"];
            for (NSString *k in other) {
                if ([k isEqualToString:@"accountId"]) continue;   // Keep the retained record's accountId.
                id cur = keepData[k];
                id val = other[k];
                BOOL curEmpty = (cur == nil || [cur isEqual:@""]);
                BOOL valEmpty = (val == nil || [val isEqual:@""]);
                if (curEmpty && !valEmpty) {
                    keepData[k] = val;   // ★ Fill missing fields in the retained record (token/avatar/xuid, etc.).
                }
            }
            if ([fm removeItemAtPath:nodes[idx][@"path"] error:nil]) {
                removed++;
                [removedIds addObject:nodes[idx][@"id"]];
            }
        }
        saveJSONToFile(keepData, nodes[keepIdx][@"path"]);   // Write the record back after backfilling.

        NSLog(@"[ACCT-DUP-MS] merged group key=%@ keep=%@ removed(%lu)=%@",
              keyLog.length > 0 ? keyLog : @"(multi)",
              nodes[keepIdx][@"id"], (unsigned long)removedIds.count, removedIds);

        // If selected_account pointed to a deleted entry, redirect it to the retained entry (the same account).
        if (selected.length > 0 && !selectedSurvives &&
            ![nodes[keepIdx][@"id"] isEqualToString:selected]) {
            setPrefObject(@"internal.selected_account", nodes[keepIdx][@"id"]);
        }
    }
    if (removed > 0) {
        NSLog(@"[ACCT-DUP-MS] deduplicated accounts directory: removed %ld duplicate file(s)", (long)removed);
    }
    return removed;
}

+ (id)loadSavedName:(NSString *)accountId {
    // accountId may be in the current accountId format or the legacy username format (during migration).
    NSString *path = [NSString stringWithFormat:@"%s/accounts/%@.json", getenv("POJAV_HOME"), accountId];
    NSMutableDictionary *authData = parseJSONFromFile(path);
    if (authData[@"NSErrorObject"] != nil) {
        NSError *error = ((NSError *)authData[@"NSErrorObject"]);
        if (error.code != NSFileReadNoSuchFileError) {
            showDialog(localize(@"Error", nil), error.localizedDescription);
        }
        return nil;
    }

    // Create the appropriate authenticator from account data (initWithData sets the current singleton).
    // ★ [AUTH-FIX] Fix the classification order (the root cause of third-party accounts being mistaken for offline/local):
    //   Previously, expiresAt == 0 was checked first and selected LocalAuthenticator. Third-party accounts may lack expiresAt
    //   (the multi-profile refreshToBindProfile path historically did not write it), so a third-party account with clientToken/authserver
    //   was classified as Local (offline) by loadSavedName. BaseAuthenticator.current was then not ThirdPartyAuthenticator,
    //   so authlib-injector was not injected at startup and the game treated the account as offline.
    //   Now classify by account-type marker fields first, and use expiresAt == 0 only as a fallback for local accounts.
    //   Legacy records without marker fields retain the expiresAt-based fallback for compatibility.
    BaseAuthenticator *auth = nil;
    if (authData[@"clientToken"] != nil) {
        // clientToken indicates a third-party (Yggdrasil / authlib-injector) account.
        auth = [[ThirdPartyAuthenticator alloc] initWithData:authData];
    } else if (authData[@"xboxGamertag"] != nil || authData[@"xuid"] != nil) {
        // Xbox identifiers indicate a Microsoft account (do not treat it as local/offline even if expiresAt is missing).
        auth = [[MicrosoftAuthenticator alloc] initWithData:authData];
    } else if ([authData[@"expiresAt"] longValue] == 0) {
        auth = [[LocalAuthenticator alloc] initWithData:authData];
    } else {
        auth = [[MicrosoftAuthenticator alloc] initWithData:authData];
    }

    // Migrate a legacy account: if authData has no accountId field, it was named by username in the old format.
    // Generate an accountId, save to <accountId>.json, remove <username>.json, migrate the avatar, and update selected_account.
    NSString *existingAccountId = authData[@"accountId"];
    if (existingAccountId == nil || [existingAccountId length] == 0) {
        NSString *newAccountId = [BaseAuthenticator generateAccountIdForData:authData];
        // ★ [ACCT-DUP-MS] Before migration, check for an existing record with the same fallback identity and reuse its accountId if found,
        //   avoiding a second record for the same account when migrating a legacy account (username-named / missing xuid).
        NSString *migDupId = [BaseAuthenticator existingAccountIdForData:authData excluding:accountId];
        if (migDupId.length > 0) {
            newAccountId = migDupId;
        }
        authData[@"accountId"] = newAccountId;

        NSString *newPath = [NSString stringWithFormat:@"%s/accounts/%@.json", getenv("POJAV_HOME"), newAccountId];
        NSError *saveError = saveJSONToFile(authData, newPath);

        if (saveError == nil) {
            // Remove the old file (if the accountId argument differs from the generated newAccountId, it was a legacy username).
            if (![accountId isEqualToString:newAccountId]) {
                [NSFileManager.defaultManager removeItemAtPath:path error:nil];
            }
            // Migrate the avatar file: <username>.png → <accountId>.png.
            // The avatar directory (<Documents>/avatars/) is separate from the account directory (POJAV_HOME/accounts/).
            NSString *username = authData[@"username"];
            if (username && username.length > 0 && ![username isEqualToString:newAccountId]) {
                NSString *docsDir = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
                NSString *oldAvatarPath = [NSString stringWithFormat:@"%@/avatars/%@.png", docsDir, username];
                NSString *newAvatarPath = [NSString stringWithFormat:@"%@/avatars/%@.png", docsDir, newAccountId];
                // Migrate only when the old avatar exists and the new one does not, to avoid overwriting.
                if ([NSFileManager.defaultManager fileExistsAtPath:oldAvatarPath] &&
                    ![NSFileManager.defaultManager fileExistsAtPath:newAvatarPath]) {
                    [NSFileManager.defaultManager moveItemAtPath:oldAvatarPath toPath:newAvatarPath error:nil];
                }
            }
            // Update selected_account: if the selected value is the old username/accountId, replace it with the new accountId.
            if ([getPrefObject(@"internal.selected_account") isEqualToString:accountId]) {
                setPrefObject(@"internal.selected_account", newAccountId);
            }
        }
    }

    return auth;
}

- (id)initWithData:(NSMutableDictionary *)data {
    current = self = [self init];
    self.authData = data;
    return self;
}

- (id)initWithInput:(NSString *)string {
    NSMutableDictionary *data = [[NSMutableDictionary alloc] init];
    data[@"input"] = string;
    return [self initWithData:data];
}

- (void)loginWithCallback:(Callback)callback {
}

- (void)refreshTokenWithCallback:(Callback)callback {
}

- (BOOL)saveChanges {
    NSError *error;

    [self.authData removeObjectForKey:@"input"];
    [self.authData removeObjectForKey:@"password"];
    // The oldusername mechanism is obsolete: filenames use accountId, so changing username no longer requires renaming a file.
    [self.authData removeObjectForKey:@"oldusername"];

    // Ensure accountId exists (generate a fallback on first save; normal login paths set it in subclasses).
    NSString *accountId = self.authData[@"accountId"];
    if (accountId == nil || [accountId length] == 0) {
        accountId = [BaseAuthenticator generateAccountIdForData:self.authData];
        self.authData[@"accountId"] = accountId;
    }

    // Use accountId (a unique identifier) for the filename so accounts with the same name do not conflict.
    NSString *accountsDir = [BaseAuthenticator accountsDirectoryPath];
    NSString *newPath = [accountsDir stringByAppendingPathComponent:
        [accountId stringByAppendingPathExtension:@"json"]];

    // ★ [ACCT-DUP-MS] Idempotent storage deduplication (layered identity signals): find other files for the same account
    //   using fallback identity keys (xuid→profileId(uuid)→gamertag+username). A match means the account already exists
    //   (duplicate submission / second login / incomplete record without xuid / nondeterministic accountId):
    //     · If this accountId has not yet been written, reuse the existing accountId so both writes converge on one file.
    //     · In either case, remove the duplicate file.
    //   Result: **only one record per account**, even if xuid is missing and only gamertag+UUID are available.
    NSString *dupId = [BaseAuthenticator existingAccountIdForData:self.authData excluding:accountId];
    if (dupId.length == 0) {
        // Fallback for the legacy primary-key path (consistent with the previous [ACCT-DUP] behavior).
        NSString *identityKey = [BaseAuthenticator accountIdentityKeyForData:self.authData];
        if (identityKey.length > 0) {
            dupId = [BaseAuthenticator existingAccountIdForIdentityKey:identityKey excluding:accountId];
        }
    }
    if (dupId.length > 0) {
        NSString *dupPath = [accountsDir stringByAppendingPathComponent:
            [dupId stringByAppendingPathExtension:@"json"]];
        if (![[NSFileManager defaultManager] fileExistsAtPath:newPath]) {
            accountId = dupId;
            self.authData[@"accountId"] = dupId;
            newPath = dupPath;
        }
        if (![dupPath isEqualToString:newPath]) {
            [[NSFileManager defaultManager] removeItemAtPath:dupPath error:nil];
        }
    }

    error = saveJSONToFile(self.authData, newPath);

    if (error != nil) {
        showDialog(@"Error while saving file", error.localizedDescription);
    } else {
        // Save the selected account (accountId) so login state can be restored after restart.
        setPrefObject(@"internal.selected_account", accountId);
    }
    return error == nil;
}

@end
