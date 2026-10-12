#import <UIKit/UIKit.h>

#define TYPE_INSTALLED 0
#define TYPE_RELEASE 1
#define TYPE_SNAPSHOT 2
#define TYPE_OLDBETA 3
#define TYPE_OLDALPHA 4

@interface MinecraftResourceUtils : NSObject

+ (void)processVersion:(NSMutableDictionary *)json inheritsFrom:(NSMutableDictionary *)inheritsFrom;
+ (void)tweakVersionJson:(NSMutableDictionary *)json;

+ (NSObject *)findVersion:(NSString *)version inList:(NSArray *)list;
+ (NSObject *)findNearestVersion:(NSObject *)version expectedType:(int)type;

// Evaluates OS rules in Mojang version JSON (treats iOS as osx).
+ (BOOL)evaluateRules:(NSArray *)rules;
// Expands structured JVM argument entries into a string array.
+ (NSArray<NSString *> *)flattenJvmArg:(id)arg;

/// Based on ZL2 Install.ForgeLike.progressIgnoreList:
/// bootstraplauncher 0.1.17+ applies -DignoreList only to library filenames in the classpath.
/// Append ${primary_jar_name} to the end of -DignoreList; otherwise SecureJarHandler ignores the main jar and the launch crashes.
/// No-op for older bootstraplauncher versions. json must be a mutable arguments.jvm array.
+ (void)applyBootstrapLauncherIgnoreListFix:(NSMutableDictionary *)json;

/// Based on ZL2 Install.OptiFine.checkOFLaunchWrapper:
/// Generates the launchwrapper library entry required to run OptiFine (also writes it to disk/downloads it if needed).
///   - OptiFine 1.13+ packages include launchwrapper-of-<ver>.jar + launchwrapper-of.txt;
///     the official installer extracts them to libraries/optifine/launchwrapper-of/<ver>/.
///   - Older versions (1.12 and earlier) use net.minecraft:launchwrapper:1.12.
/// @return A libraries array that can be added directly to version.json; nil on failure.
+ (NSArray *)optifineLaunchWrapperLibrariesWithOptiFineJarPath:(NSString *)optifineJarPath
                                                  librariesDir:(NSString *)librariesDir;

@end
