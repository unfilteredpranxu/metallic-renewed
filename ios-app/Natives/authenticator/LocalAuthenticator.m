#import "BaseAuthenticator.h"

@implementation LocalAuthenticator

- (void)loginWithCallback:(Callback)callback {
    self.authData[@"username"] = self.authData[@"input"];
    self.authData[@"profileId"] = @"00000000-0000-0000-0000-000000000000";
    // ★ [ACCT-DUP] Local accounts have no natural unique ID, so assign a random UUID as a fallback here.
    //   BaseAuthenticator.saveChanges deduplicates idempotently by identity key (local:<username>):
    //   if a local account with the same name already exists on disk, it **reuses its accountId** and writes to the same file,
    //   so repeated logins with the same username no longer create extra entries (previously each login created a file).
    self.authData[@"accountId"] = [[NSUUID UUID] UUIDString];
    // Load the avatar using the Minecraft Headshot API.
    self.authData[@"profilePicURL"] = [NSString stringWithFormat:@"https://api.rms.net.cn/head/%@", self.authData[@"username"]];
    callback(nil, [super saveChanges]);
}

- (void)refreshTokenWithCallback:(Callback)callback {
    // Nothing to do
    callback(nil, YES);
}

@end
