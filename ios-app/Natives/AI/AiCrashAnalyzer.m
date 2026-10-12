//
//  AiCrashAnalyzer.m
//  Amethyst
//

#import "AiCrashAnalyzer.h"

@implementation AiCrashAnalyzer

- (NSString *)name {
    return @"match_known_errors";
}

- (AiToolPermission)permission {
    return AiToolPermissionReadOnly;
}

- (NSString *)summary {
    return @"Analyze a log or crash report, identify known error types, and provide clear explanations and repair suggestions."
           "\nParameters (provide either one):"
           "\n  - log (string, optional): full launch log (usually from read_latest_log)."
           "\n  - crashReport (string, optional): full crash report (usually from read_crash_report)."
           "\nAt least one parameter is required. Returns JSON: {matched, category, explanation, suggestions}."
           "\ncategory values: Out of memory / JNI initialization failed / Graphics initialization failed / Java version mismatch / Numeric value out of range / "
           "iOS-Magic Keyboard crash / iOS-MC 26.2 OpenGL syntax error / iOS-MC 26.3-Snapshot4 launch failure (SDL3) / "
           "iOS-launcher crash / iOS-LWJGL compatibility issue / iOS-black screen or immediate crash on launch (JIT) / Unknown."
           "\nBoundary: only built-in rules are matched; a match is not guaranteed. General troubleshooting suggestions are provided when no rule matches.";
}

/// A single match rule: category + alternatives (all keywords in an alternative must match for that alternative to match)
- (NSArray<NSDictionary *> *)ruleTable {
    return @[
        @{
            @"category": @"Out of memory",
            @"alternatives": @[
                @[@"OutOfMemoryError"],
            ],
            @"explanation": @"It's like having a fixed monthly salary but needing to pay rent, utilities, and snacks until your balance runs out."
                            "The game does not have enough memory (available space). When Java requests more, the system rejects it and the game crashes.",
            @"suggestions": @[
                @"Increase the memory allocated to the game in launcher settings (the -Xmx Java argument; give it a bigger \"salary\").",
                @"Disable or remove some installed mods or shader packs to reduce the \"rent burden.\"",
                @"If changing the memory does not help, try reducing the render distance and disabling shaders.",
            ],
        },
        @{
            @"category": @"JNI initialization failed",
            @"alternatives": @[
                @[@"Failed to initialize JNI", @"META-INF"],
                @[@"java.lang.UnsatisfiedLinkError"],
            ],
            @"explanation": @"JNI is like a \"visa\" that lets the game (Java) communicate with native system libraries."
                            "If the visa has expired or the documents are incomplete (a native library is missing or has the wrong version), Java cannot proceed and launch fails.",
            @"suggestions": @[
                @"Reinstall/re-download the game so all native libraries are present.",
                @"Make sure you are using the full Java runtime, not a trimmed-down version.",
                @"If the font library is corrupted, delete this version and reinstall it.",
            ],
        },
        @{
            @"category": @"Graphics initialization failed",
            @"alternatives": @[
                @[@"OpenGL", @"GLFW error"],
                @[@"GLX"],
            ],
            @"explanation": @"It's like a driver with a standard car license trying to drive a heavy truck — the license does not match."
                            "The game is trying to initialize graphics with an API (OpenGL/GLFW/GLX), but the current renderer has incomplete support or the driver is incompatible.",
            @"suggestions": @[
                @"Switch to another renderer in launcher settings (e.g. MobileGlues / GL4ES / Auto).",
                @"Update the launcher or game, or lower the required OpenGL version.",
                @"Reset/restore the default rendering configuration in Settings and try again.",
            ],
        },
        @{
            @"category": @"Java version mismatch",
            @"alternatives": @[
                @[@"Unsupported Java version"],
                @[@"Java 8"],
            ],
            @"explanation": @"It's like speaking Mandarin to someone who only speaks a dialect — neither side understands the other."
                            "The Java version required by this game does not match the one currently provided by the launcher, so it cannot start.",
            @"suggestions": @[
                @"Check which Java version the game requires in the launcher's version manager and install the matching Java (8/17/21, etc.).",
                @"Use the launcher's recommended option to select a Java version automatically.",
            ],
        },
        @{
            @"category": @"Numeric value out of range",
            @"alternatives": @[
                @[@"Zombie"],
                @[@"invalid range"],
            ],
            @"explanation": @"It's like trying to fit five boxes into a cabinet with only three drawers — the numbers do not add up."
                            "A value (version/index/range) is outside its valid bounds, usually because a configuration file is corrupted or versions do not match.",
            @"suggestions": @[
                @"Delete/reset the relevant configuration files for this instance, then recreate it.",
                @"Reinstall this game version to avoid mixing in corrupted old configuration.",
            ],
        },
        // ===== Known iOS issues (enhance-ai-agent Task 17) =====
        @{
            @"category": @"iOS-Magic Keyboard crash",
            @"alternatives": @[
                @[@"Magic Keyboard", @"crash"],
                @[@"妙控键盘"],
            ],
            @"explanation": @"This is a known iOS crash triggered by tapping the Magic Keyboard; the developers are aware of the issue.",
            @"suggestions": @[
                @"The developers are aware of this issue; please wait patiently for a fix.",
                @"Until it is fixed, avoid connecting/tapping the Magic Keyboard, or use the touchscreen and virtual keyboard instead.",
            ],
        },
        @{
            @"category": @"iOS-MC 26.2 OpenGL syntax error",
            @"alternatives": @[
                @[@"26.2", @"OpenGL", @"syntax"],
                @[@"GL_INVALID_OPERATION", @"syntax error"],
            ],
            @"explanation": @"Minecraft 26.2 triggers an OpenGL syntax error in the iOS rendering layer; this is a compatibility issue between the current renderer and this version.",
            @"suggestions": @[
                @"Switch this instance's renderer to MoltenVK (set_setting: key=video.renderer, value=MoltenVK).",
                @"Restart the game to verify after switching renderers.",
            ],
        },
        @{
            @"category": @"iOS-MC 26.3-Snapshot4 launch failure (SDL3)",
            @"alternatives": @[
                @[@"26.3-Snapshot4"],
                @[@"SDL3"],
            ],
            @"explanation": @"Mojang changed the rendering library from LWJGL to SDL3 in 26.3-Snapshot4. Corresponding iOS support has not yet been implemented, so it cannot launch.",
            @"suggestions": @[
                @"There is currently no workaround; try another Minecraft version (e.g. 26.2 or an earlier release).",
            ],
        },
        @{
            @"category": @"iOS-launcher crash",
            @"alternatives": @[
                @[@"启动器", @"闪退"],
                @[@"launcher", @"SIGKILL"],
            ],
            @"explanation": @"The launcher itself crashed (rather than the game), and the developers need to investigate.",
            @"suggestions": @[
                @"Report the issue through GitHub Issues or the official QQ group (966475918), and attach latestlog.txt.",
                @"The developers generally fix these issues during statutory holidays.",
            ],
        },
        @{
            @"category": @"iOS-LWJGL compatibility issue",
            @"alternatives": @[
                @[@"LWJGL", @"UnsatisfiedLinkError"],
                @[@"LWJGL", @"no such function"],
                @[@"LWJGL", @"NoSuchMethodError"],
            ],
            @"explanation": @"Starting with the 5.0.0 public beta, the developers modified LWJGL 3.3.3 to support Minecraft 26.2 (including some 3.4.1 features),"
                            "which may prevent some older game versions from launching.",
            @"suggestions": @[
                @"Check compatibility between the game and LWJGL versions (for older games, use the corresponding older instance configuration).",
                @"Report the specific version combination through GitHub Issues or the official QQ group (966475918).",
            ],
        },
        @{
            @"category": @"iOS-black screen or immediate crash on launch (JIT)",
            @"alternatives": @[
                @[@"JIT", @"SIGSEGV"],
                @[@"JIT", @"SIGTRAP"],
                @[@"ptrace", @"debugged"],
            ],
            @"explanation": @"This issue is caused by JIT (just-in-time compilation) not being enabled correctly: the screen goes black or the app crashes immediately after launch.",
            @"suggestions": @[
                @"Try enabling JIT with StikDebug or LiveContainer before launching the game.",
                @"The developers are aware of this issue; wait for a future fix.",
            ],
        },
    ];
}

- (void)execute:(NSDictionary<NSString *, id> *)params
     completion:(void (^)(NSString * _Nullable result, NSError * _Nullable error))completion {
    if (!completion) return;

    NSString *log = params[@"log"];
    NSString *crash = params[@"crashReport"];
    if (![log isKindOfClass:[NSString class]]) log = nil;
    if (![crash isKindOfClass:[NSString class]]) crash = nil;

    if (log.length == 0 && crash.length == 0) {
        NSError *err = [NSError errorWithDomain:@"AiTool" code:400
                                       userInfo:@{NSLocalizedDescriptionKey: @"At least one of the log and crashReport parameters must be provided"}];
        completion(nil, err);
        return;
    }

    NSString *combined = [NSString stringWithFormat:@"%@\n%@", (log ?: @""), (crash ?: @"")];

    // Match built-in rules
    NSDictionary *matchedResult = nil;
    for (NSDictionary *rule in [self ruleTable]) {
        BOOL ruleMatched = NO;
        for (NSArray *alternative in rule[@"alternatives"]) {
            BOOL allHit = YES;
            for (NSString *keyword in alternative) {
                if ([combined rangeOfString:keyword options:NSCaseInsensitiveSearch].location == NSNotFound) {
                    allHit = NO;
                    break;
                }
            }
            if (allHit) { ruleMatched = YES; break; }
        }
        if (ruleMatched) {
            matchedResult = @{
                @"matched": @YES,
                @"category": rule[@"category"],
                @"explanation": rule[@"explanation"],
                @"suggestions": rule[@"suggestions"],
            };
            break;
        }
    }

    if (!matchedResult) {
        matchedResult = @{
            @"matched": @NO,
            @"category": @"Unknown",
            @"explanation": @"No known error type matched, so the cause cannot be identified directly.",
            @"suggestions": @[
                @"Try launching once more and see whether the issue is reproducible.",
                @"Share the full log or exported crash report with the community/developers on the forum.",
                @"Temporarily disable mods and shaders, then check one by one whether an asset is causing the issue.",
            ],
        };
    }

    NSData *data = [NSJSONSerialization dataWithJSONObject:matchedResult options:0 error:nil];
    NSString *resultJSON = data ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : @"{}";
    completion(resultJSON, nil);
}

@end