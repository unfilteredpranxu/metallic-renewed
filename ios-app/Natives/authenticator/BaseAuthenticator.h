#import <Foundation/Foundation.h>

typedef void(^Callback)(id status, BOOL success);

@interface BaseAuthenticator : NSObject

@property (nonatomic, strong) NSMutableDictionary *authData;

+ (id)current;
+ (void)setCurrent:(BaseAuthenticator *)auth;
// Load an account file from disk by accountId. Also supports legacy accounts named by username:
// if loaded authData has no accountId field, generate one and migrate the file, avatar, and selected_account.
+ (id)loadSavedName:(NSString *)accountId;
// Generate a unique accountId from account data: Microsoft uses xuid, third-party uses profileId, and local accounts get a UUID.
+ (NSString *)generateAccountIdForData:(NSMutableDictionary *)authData;

// ★ [ACCT-DUP] Idempotent storage deduplication (account identity). A **stable identity key**
// determines whether two records represent the same account:
//   Microsoft = xuid; third-party = authserver|profileId (falls back to username without profileId); local = username.
//   Returns nil when identity cannot be determined (missing key fields), so callers skip deduplication rather than risk a false merge.
+ (NSString *)accountIdentityKeyForData:(NSDictionary *)authData;
// The accountId of the first account in the account directory with the same identity key and accountId != excludeId (or nil).
+ (NSString *)existingAccountIdForIdentityKey:(NSString *)identityKey excluding:(NSString *)excludeId;

// ★ [ACCT-DUP-MS] Layered Microsoft fallback identity keys, ordered from strongest to weakest:
//   Microsoft = ms:<xuid> → ms:uuid:<profileId> → ms:gt:<gamertag>|<username>; third-party/local use the keys above.
//   Missing xuid falls back to UUID, then gamertag+username, allowing incomplete Microsoft records without xuid to be merged.
+ (NSArray<NSString *> *)accountIdentitySignalsForData:(NSDictionary *)authData;
// Whether two account records represent the same account (share any identity signal).
+ (BOOL)accountData:(NSDictionary *)a matchesAccountData:(NSDictionary *)b;
// The accountId of the first matching account in the directory whose accountId != excludeId (or nil).
+ (NSString *)existingAccountIdForData:(NSDictionary *)authData excluding:(NSString *)excludeId;
// Called at startup or when opening the account page to merge duplicate files for the same identity; returns the number removed.
// Only records with matching identity keys are merged; accounts with different usernames, xuids, or profileIds are retained.
+ (NSInteger)deduplicateAccountsDirectory;

- (id)initWithData:(NSMutableDictionary *)data;
- (id)initWithInput:(NSString *)string;
- (void)loginWithCallback:(Callback)callback;
- (void)refreshTokenWithCallback:(Callback)callback;
- (BOOL)saveChanges;

@end

@interface LocalAuthenticator : BaseAuthenticator
@end

@interface MicrosoftAuthenticator : BaseAuthenticator

+ (void)clearTokenDataOfProfile:(NSString *)profile;
+ (NSDictionary *)tokenDataOfProfile:(NSString *)profile;

@end
