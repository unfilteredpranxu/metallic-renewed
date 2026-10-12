#import "AFNetworking.h"
#import "BaseAuthenticator.h"
#import "../ios_uikit_bridge.h"
#import "../utils.h"
#include "jni.h"

typedef void(^XSTSCallback)(NSString *xsts, NSString *uhs);

// ★ [AUTH-FIX] Convert an NSError from a failed step into **recognizable**, user-readable text.
//   In testing, user.auth.xboxlive.com / xsts.auth.xboxlive.com / api.minecraftservices.com often return
//   an **empty body or one without XErr** on token failures. AFNetworking only reports a generic string such as
//   "Request failed: unauthorized (401)", which does not distinguish an unreachable network/region from a token rejected by the server.
//   Include the **step name + HTTP status + (if available) XErr/body summary** consistently.
//   Safety: the body contains only error codes/descriptions, **no credentials**; this function never echoes tokens.
static NSError *AmeStepError(NSString *stepName, NSString *hint, NSInteger code, NSError *error) {
    NSHTTPURLResponse *http = error.userInfo[AFNetworkingOperationFailingURLResponseErrorKey];
    NSInteger httpCode = ([http isKindOfClass:[NSHTTPURLResponse class]]) ? http.statusCode : 0;
    NSString *detail = error.localizedDescription ?: @"";
    NSData *body = error.userInfo[AFNetworkingOperationFailingURLResponseDataErrorKey];
    if (body.length > 0) {
        id json = [NSJSONSerialization JSONObjectWithData:body options:kNilOptions error:nil];
        if ([json isKindOfClass:[NSDictionary class]]) {
            id xerr = json[@"XErr"];
            id msg = json[@"Message"] ?: json[@"errorMessage"] ?: json[@"error_description"] ?: json[@"error"];
            if (xerr != nil || msg != nil) {
                detail = [NSString stringWithFormat:@"XErr=%@ %@", xerr ?: @"-", msg ?: @""];
            }
        }
    }
    NSString *core = (httpCode > 0)
        ? [NSString stringWithFormat:@"%@ (HTTP %ld): %@", stepName, (long)httpCode, detail]
        : [NSString stringWithFormat:@"%@: %@", stepName, detail];
    NSString *message = (hint.length > 0) ? [NSString stringWithFormat:@"%@\n%@", hint, core] : core;
    return [NSError errorWithDomain:@"MicrosoftAuthenticator" code:code
                           userInfo:@{NSLocalizedDescriptionKey: message}];
}


@implementation MicrosoftAuthenticator

- (void)acquireAccessToken:(NSString *)authcode refresh:(BOOL)refresh callback:(Callback)callback {
    callback(localize(@"login.msa.progress.acquireAccessToken", nil), YES);

    NSDictionary *data = @{
        @"client_id": @"00000000402b5328",
        (refresh ? @"refresh_token" : @"code"): authcode,
        @"grant_type": refresh ? @"refresh_token" : @"authorization_code",
        @"redirect_url": @"https://login.live.com/oauth20_desktop.srf",
        @"scope": @"service::user.auth.xboxlive.com::MBI_SSL"
    };

    AFHTTPSessionManager *manager = AFHTTPSessionManager.manager;
    [manager GET:@"https://login.live.com/oauth20_token.srf" parameters:data headers:nil progress:nil success:^(NSURLSessionDataTask *task, NSDictionary *response) {
        self.authData[@"msaRefreshToken"] = response[@"refresh_token"];
        [self acquireXBLToken:response[@"access_token"] callback:callback];
    } failure:^(NSURLSessionDataTask *task, NSError *error) {
        if (isConnectivityError(error)) {
            // ★ [AUTH-FIX] Distinguish these two cases to avoid silently treating a failed login as a local/offline account:
            //   · refresh = YES (refreshing an existing account's token): preserve the old offline behavior when offline—mark offline
            //     and continue without blocking startup; log a recognizable message.
            //   · refresh = NO (the user's **first login** after web authorization): without a token, login cannot succeed,
            //     so report a **recognizable error** and never use callback(nil, YES) to pretend it succeeded
            //     (previously Microsoft login appeared successful but the account was actually treated as offline).
            NSString *reason = [NSString stringWithFormat:@"%@ (%ld)", error.localizedDescription, (long)error.code];
            if (refresh) {
                NSLog(@"[MSA] refresh failed due to connectivity error, falling back to offline: %@", reason);
                self.authData[@"accessToken"] = @"offline";
                callback(nil, YES);
            } else {
                NSLog(@"[MSA] login failed: no reachable token endpoint (%@)", reason);
                callback([NSError errorWithDomain:@"MicrosoftAuthenticator" code:2001
                                        userInfo:@{NSLocalizedDescriptionKey:
                    [NSString stringWithFormat:localize(@"login.msa.error.network.token", nil), reason]}], NO);
            }
        } else {
            callback(error, NO);
        }
    }];
}

- (void)acquireXBLToken:(NSString *)accessToken callback:(Callback)callback {
    callback(localize(@"login.msa.progress.acquireXBLToken", nil), YES);

    NSDictionary *data = @{
        @"Properties": @{
            @"AuthMethod": @"RPS",
            @"SiteName": @"user.auth.xboxlive.com",
            @"RpsTicket": accessToken
        },
        @"RelyingParty": @"http://auth.xboxlive.com",
        @"TokenType": @"JWT"
    };

    AFHTTPSessionManager *manager = AFHTTPSessionManager.manager;
    manager.requestSerializer = AFJSONRequestSerializer.serializer;
    [manager POST:@"https://user.auth.xboxlive.com/user/authenticate" parameters:data headers:nil progress:nil success:^(NSURLSessionDataTask *task, NSDictionary *response) {
        Callback innerCallback = ^(NSString* status, BOOL success) {
            if (!success) {
                callback(status, NO);
                return;
            } else if (status) {
                return;
            }
            // Obtain XSTS for authenticating to Minecraft
            [self acquireXSTSFor:@"rp://api.minecraftservices.com/" token:response[@"Token"] xstsCallback:^(NSString *xsts, NSString *uhs){
                if (xsts == nil) {
                    callback(nil, NO);
                    return;
                }
                self.authData[@"xuid"] = uhs;
                [self acquireMinecraftToken:uhs xstsToken:xsts callback:callback];
            } callback:callback];
        };

        // Obtain XSTS for getting the Xbox gamertag
        [self acquireXSTSFor:@"http://xboxlive.com" token:response[@"Token"] xstsCallback:^(NSString *xsts, NSString *uhs){
            if (xsts == nil) {
                callback(nil, NO);
                return;
            }
            [self acquireXboxProfile:uhs xstsToken:xsts callback:innerCallback];
        } callback:callback];
    } failure:^(NSURLSessionDataTask *task, NSError *error) {
        // ★ [AUTH-FIX] Report a recognizable error instead of passing up only the raw NSError (which would appear as
        //   "Request failed: unauthorized (401)"）。
        callback(AmeStepError(localize(@"login.msa.progress.acquireXBLToken", nil),
                              localize(@"login.msa.error.xbl.rejected", nil), 2002, error), NO);
    }];
}

- (void)acquireXSTSFor:(NSString *)replyingParty token:(NSString *)xblToken xstsCallback:(XSTSCallback)xstsCallback callback:(Callback)callback {
    callback(localize(@"login.msa.progress.acquireXSTS", nil), YES);

    NSDictionary *data = @{
       @"Properties": @{
           @"SandboxId": @"RETAIL",
           @"UserTokens": @[
               xblToken
           ]
       },
       @"RelyingParty": replyingParty,
       @"TokenType": @"JWT",
    };

    AFHTTPSessionManager *manager = AFHTTPSessionManager.manager;
    manager.requestSerializer = AFJSONRequestSerializer.serializer;
    [manager POST:@"https://xsts.auth.xboxlive.com/xsts/authorize" parameters:data headers:nil progress:nil success:^(NSURLSessionDataTask *task, NSDictionary *response) {
        // ★ [ACCT-AUDIT] Crash guard: DisplayClaims.xui may be empty if the XSTS response is malformed.
        //   Indexing [0] on an empty array throws NSRangeException and crashes. Check types and counts at each level first.
        NSArray *xui = response[@"DisplayClaims"][@"xui"];
        NSString *uhs = ([xui isKindOfClass:NSArray.class] && xui.count > 0) ? xui[0][@"uhs"] : nil;
        xstsCallback(response[@"Token"], uhs);
    } failure:^(NSURLSessionDataTask *task, NSError *error) {
        // ★ [AUTH-FIX] When XErr is absent (empty response body / network-layer error), report a **recognizable** error
        //   instead of "Unknown XErr code, response: (null)". Testing shows xsts.auth.xboxlive.com may also return
        //   an empty body (HTTP 400/401) for an invalid user token.
        NSData *errorData = error.userInfo[AFNetworkingOperationFailingURLResponseDataErrorKey];
        NSDictionary *errorDict = (errorData.length > 0)
            ? [NSJSONSerialization JSONObjectWithData:errorData options:kNilOptions error:nil] : nil;
        if (![errorDict isKindOfClass:[NSDictionary class]] || errorDict[@"XErr"] == nil) {
            callback(AmeStepError(localize(@"login.msa.progress.acquireXSTS", nil), nil, 2003, error), NO);
            return;
        }
        NSString *errorString;
        switch ((int)([errorDict[@"XErr"] longValue]-2148916230l)) {
            case 3:
                errorString = @"login.msa.error.xsts.noxboxacc";
                break;
            case 5:
                errorString = @"login.msa.error.xsts.noxbox";
                break;
            case 6:
            case 7:
                errorString = @"login.msa.error.xsts.krverify";
                break;
            case 8:
                errorString = @"login.msa.error.xsts.underage";
                break;
            default:
                errorString = [NSString stringWithFormat:@"%@\n\nUnknown XErr code, response:\n%@", error.localizedDescription, errorDict];
                break;
        }
        callback(localize(errorString, nil), NO);
    }];
}


- (void)acquireXboxProfile:(NSString *)xblUhs xstsToken:(NSString *)xblXsts callback:(Callback)callback {
    callback(localize(@"login.msa.progress.acquireXboxProfile", nil), YES);

    NSDictionary *headers = @{
        @"x-xbl-contract-version": @"2",
        @"Authorization": [NSString stringWithFormat:@"XBL3.0 x=%@;%@", xblUhs, xblXsts]
    };

    AFHTTPSessionManager *manager = AFHTTPSessionManager.manager;
    [manager GET:@"https://profile.xboxlive.com/users/me/profile/settings?settings=PublicGamerpic,Gamertag" parameters:nil headers:headers progress:nil success:^(NSURLSessionDataTask *task, NSDictionary *response) {
        // ★ [ACCT-AUDIT] Crash guard: profileUsers/settings may be missing or empty if the profile endpoint behaves unexpectedly.
        //   Consecutive [0]/[1] indexing can throw an out-of-bounds exception. Check types and counts at each level first;
        //   if fields are missing, still invoke the success callback.
        NSArray *profileUsers = response[@"profileUsers"];
        NSDictionary *firstUser = ([profileUsers isKindOfClass:NSArray.class] && profileUsers.count > 0 &&
                                   [profileUsers[0] isKindOfClass:NSDictionary.class]) ? profileUsers[0] : nil;
        NSArray *settings = firstUser[@"settings"];
        if ([settings isKindOfClass:NSArray.class] && settings.count > 0) {
            id picValue = [settings[0] isKindOfClass:NSDictionary.class] ? settings[0][@"value"] : nil;
            if (picValue) {
                self.authData[@"profilePicURL"] = [NSString stringWithFormat:@"%@&h=120&w=120", picValue];
            }
        }
        if ([settings isKindOfClass:NSArray.class] && settings.count > 1) {
            id tagValue = [settings[1] isKindOfClass:NSDictionary.class] ? settings[1][@"value"] : nil;
            if (tagValue) {
                self.authData[@"xboxGamertag"] = tagValue;
            }
        }
        callback(nil, YES);
    } failure:^(NSURLSessionDataTask *task, NSError *error) {
        callback(error, NO);
    }];
}

- (void)acquireMinecraftToken:(NSString *)xblUhs xstsToken:(NSString *)xblXsts callback:(Callback)callback {
    callback(localize(@"login.msa.progress.acquireMCToken", nil), YES);

    NSDictionary *data = @{
        @"identityToken": [NSString stringWithFormat:@"XBL3.0 x=%@;%@", xblUhs, xblXsts]
    };

    AFHTTPSessionManager *manager = AFHTTPSessionManager.manager;
    manager.requestSerializer = AFJSONRequestSerializer.serializer;
    [manager POST:@"https://api.minecraftservices.com/authentication/login_with_xbox" parameters:data headers:nil progress:nil success:^(NSURLSessionDataTask *task, NSDictionary *response) {
        self.authData[@"accessToken"] = response[@"access_token"];
        [self checkMCProfile:response[@"access_token"] callback:callback];
    } failure:^(NSURLSessionDataTask *task, NSError *error) {
        // ★ [AUTH-FIX] Recognizable error: login_with_xbox failures include a JSON body (error/errorMessage);
        //   the old implementation returned only the raw NSError, so users saw only "Request failed: unauthorized (401)".
        callback(AmeStepError(localize(@"login.msa.progress.acquireMCToken", nil),
                              localize(@"login.msa.error.mc.token", nil), 2004, error), NO);
    }];
}

- (void)checkMCProfile:(NSString *)mcAccessToken callback:(Callback)callback {
    self.authData[@"expiresAt"] = @((long)[NSDate.date timeIntervalSince1970] + 86400);

    callback(localize(@"login.msa.progress.checkMCProfile", nil), YES);

    NSDictionary *headers = @{
        @"Authorization": [NSString stringWithFormat:@"Bearer %@", mcAccessToken]
    };
    AFHTTPSessionManager *manager = AFHTTPSessionManager.manager;
    manager.requestSerializer = AFJSONRequestSerializer.serializer;
    [manager GET:@"https://api.minecraftservices.com/minecraft/profile" parameters:nil headers:headers progress:nil success:^(NSURLSessionDataTask *task, NSDictionary *response) {
        NSString *uuid = response[@"id"];
        // ★ [ACCT-AUDIT] Crash guard: id may be missing or too short if the profile endpoint behaves unexpectedly;
        //   calling substringWithRange directly would throw NSRangeException.
        if ([uuid isKindOfClass:NSString.class] && uuid.length >= 32) {
            self.authData[@"profileId"] = [NSString stringWithFormat:@"%@-%@-%@-%@-%@",
                [uuid substringWithRange:NSMakeRange(0, 8)],
                [uuid substringWithRange:NSMakeRange(8, 4)],
                [uuid substringWithRange:NSMakeRange(12, 4)],
                [uuid substringWithRange:NSMakeRange(16, 4)],
                [uuid substringWithRange:NSMakeRange(20, 12)]
            ];
        } else {
            self.authData[@"profileId"] = uuid ?: @"";
        }
        self.authData[@"profilePicURL"] = [NSString stringWithFormat:@"https://api.rms.net.cn/head/%@", self.authData[@"username"]];
        self.authData[@"username"] = response[@"name"];
        // Use xuid as the Microsoft accountId (globally unique and stable), allowing accounts with the same name to coexist.
        // ★ [ACCT-DUP-MS] If xuid is missing, leave accountId unset (super saveChanges will deduplicate using fallback identity keys),
        //   rather than setting it to nil and generating a new random ID on every save, which would create duplicate records.
        if ([self.authData[@"xuid"] isKindOfClass:[NSString class]] && [self.authData[@"xuid"] length] > 0) {
            self.authData[@"accountId"] = self.authData[@"xuid"];
        }
        callback(nil, [self saveChanges]);
    } failure:^(NSURLSessionDataTask *task, NSError *error) {
        NSData *errorData = error.userInfo[AFNetworkingOperationFailingURLResponseDataErrorKey];
        // ★ [ACCT-AUDIT] Crash guard: network errors have no response body (errorData=nil);
        //   passing nil to JSONObjectWithData: throws NSInvalidArgumentException and crashes.
        //   Use the same handling as acquireXSTSFor: (which already guards against nil).
        NSDictionary *errorDict = (errorData != nil)
            ? ([NSJSONSerialization JSONObjectWithData:errorData options:kNilOptions error:nil] ?: @{})
            : @{};
        if ([errorDict[@"error"] isEqualToString:@"NOT_FOUND"]) {
            // If there is no profile, use the Xbox gamertag as username with Demo mode
            self.authData[@"profileId"] = @"00000000-0000-0000-0000-000000000000";
            self.authData[@"username"] = [NSString stringWithFormat:@"Demo.%@", self.authData[@"xboxGamertag"]];
            // Use xuid as the accountId for demo accounts as well.
            // ★ [ACCT-DUP-MS] As above: if xuid is missing, leave accountId unset for super to deduplicate by fallback identity keys.
            if ([self.authData[@"xuid"] isKindOfClass:[NSString class]] && [self.authData[@"xuid"] length] > 0) {
                self.authData[@"accountId"] = self.authData[@"xuid"];
            }

            if ([self saveChanges]) {
                // ★ [ACCT-DUP] Invoke the callback only once. Previously this called callback(@"DEMO", YES) and callback(nil, YES),
                //   causing the list's callbackMicrosoftAuth to run reload/dismiss/whenItemSelected twice.
                //   The @"DEMO" callback handles both the demo notice and successful completion, so remove the redundant second call.
                callback(@"DEMO", YES);
            } else {
                callback(nil, NO);
            }
            return;
        }

        callback(error, NO);
    }];
}

- (void)loginWithCallback:(Callback)callback {
    [self acquireAccessToken:self.authData[@"input"] refresh:NO callback:callback];
}

- (void)refreshTokenWithCallback:(Callback)callback {
    // Move tokens to keychain if we haven't
    if (!self.tokenData) {
        showDialog(localize(@"Error", nil), @"Failed to load account tokens from keychain");
        callback(nil, YES);
        return;
    }

    if ([NSDate.date timeIntervalSince1970] > [self.authData[@"expiresAt"] longValue]) {
        [self acquireAccessToken:self.tokenData[@"refreshToken"] refresh:YES callback:callback];
    } else {
        callback(nil, YES);
    }
}

- (BOOL)saveChanges {
    BOOL savedToKeychain = [self setAccessToken:self.authData[@"accessToken"] refreshToken:self.authData[@"msaRefreshToken"]];
    if (!savedToKeychain) {
        showDialog(localize(@"Error", nil), @"Failed to save account tokens to keychain");
        return NO;
    }
    [self.authData removeObjectsForKeys:@[@"accessToken", @"msaRefreshToken"]];
    return [super saveChanges];
}

#pragma mark Keychain

+ (NSDictionary *)keychainQueryForKey:(NSString *)profile extraInfo:(NSDictionary *)extra {
    NSMutableDictionary *dict = @{
        (id)kSecClass: (id)kSecClassGenericPassword,
        (id)kSecAttrService: @"AccountToken",
        (id)kSecAttrAccount: profile,
    }.mutableCopy;
    if (extra) {
        [dict addEntriesFromDictionary:extra];
    }
    return dict;
}

+ (NSDictionary *)tokenDataOfProfile:(NSString *)profile {
    NSDictionary *dict = [MicrosoftAuthenticator keychainQueryForKey:profile extraInfo:@{
        (id)kSecMatchLimit: (id)kSecMatchLimitOne,
        (id)kSecReturnData: (id)kCFBooleanTrue
    }];
    CFTypeRef result = nil;
    OSStatus status = SecItemCopyMatching((__bridge CFDictionaryRef)dict, &result);
    if (status == errSecSuccess) {
        return [NSKeyedUnarchiver unarchivedObjectOfClass:NSDictionary.class fromData:(__bridge NSData *)result error:nil];
    } else {
        return nil;
    }
}

+ (void)clearTokenDataOfProfile:(NSString *)profile {
    NSDictionary *dict = [MicrosoftAuthenticator keychainQueryForKey:profile extraInfo:nil];
    SecItemDelete((__bridge CFDictionaryRef)dict);
}

- (BOOL)setAccessToken:(NSString *)accessToken refreshToken:(NSString *)refreshToken {
    if (!accessToken || !refreshToken) {
        NSDebugLog(@"[MicrosoftAuthenticator] BUG: nil accessToken:%d, refreshToken:%d", !accessToken, !refreshToken);
        return NO;
    }
    NSData *data = [NSKeyedArchiver archivedDataWithRootObject:@{
        @"accessToken": accessToken,
        @"refreshToken": refreshToken,
    } requiringSecureCoding:YES error:nil];
    NSDictionary *dict = [MicrosoftAuthenticator keychainQueryForKey:self.authData[@"xuid"] extraInfo:@{
        (id)kSecAttrAccessible: (id)kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        (id)kSecValueData: data
    }];
    SecItemDelete((__bridge CFDictionaryRef)dict);
    OSStatus status = SecItemAdd((__bridge CFDictionaryRef)dict, NULL);
    return status == errSecSuccess;
}

- (NSDictionary *)tokenData {
    return [MicrosoftAuthenticator tokenDataOfProfile:self.authData[@"xuid"]];
}

@end
