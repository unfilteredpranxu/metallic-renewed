#import "BaseAuthenticator.h"
#include "jni.h"

JNIEXPORT jstring JNICALL Java_net_kdt_pojavlaunch_value_MinecraftAccount_getAccessTokenFromKeychain(JNIEnv *env, jclass clazz, jstring xuid) {
    // This function should only be called once
    static BOOL called = NO;
    if (called) {
        // ★ [DEMINE] This used to call abort(): a second JNI call (repeat login / multi-account token
        //   refresh) killed the process. Re-reading the keychain is idempotent, so now log and continue.
        NSLog(@"[DEMINE] getAccessTokenFromKeychain called more than once; continuing (previously aborted)");
    }
    called = YES;

    const char *xuidC = (*env)->GetStringUTFChars(env, xuid, 0);
    NSString *accessToken = [NSClassFromString(@"MicrosoftAuthenticator") tokenDataOfProfile:@(xuidC)][@"accessToken"];
    (*env)->ReleaseStringUTFChars(env, xuid, xuidC);
    // ★ [DEMINE] Previously passed accessToken.UTF8String directly to NewStringUTF; if MicrosoftAuthenticator
    //   is missing or there is no token, this is NULL, and NewStringUTF(NULL) is undefined behavior (may crash). Use an empty string.
    if (accessToken.length == 0) {
        NSLog(@"[DEMINE] getAccessTokenFromKeychain: no access token available; returning empty string");
        return (*env)->NewStringUTF(env, "");
    }
    return (*env)->NewStringUTF(env, accessToken.UTF8String);
}
