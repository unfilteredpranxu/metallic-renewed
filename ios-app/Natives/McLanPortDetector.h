//
//  McLanPortDetector.h
//  Amethyst
//
//  ★ [PORT-AUTO] Automatic Minecraft "Open to LAN" port detector
//
//  Background: The game itself chooses a random LAN port (generated when the player selects "Open to LAN"),
//  not the launcher. Therefore, never bind a port yourself as the host port (it would differ from the game's
//  actual port, and guests would be unable to connect).
//
//  Detection methods (in order of reliability):
//    1. Parse game logs: the "Open to LAN" line in the instance's logs/latest.log (MC log) and the launcher's
//       latestlog.txt (which includes game stdout) — typical forms:
//         [Render thread/INFO]: Started serving on port 54321
//         [Client thread/INFO]: Local game hosted on port 54321
//       Use the last port found (opening LAN again adds another line).
//    2. Incremental polling: reread logs every second while the room-creation panel is open; call back if the port changes.
//    3. Fallback: return 0 if detection fails — no hard-coded value or crash; users can still enter it manually.
//
//  This class only reads logs, polls on a timer, and calls back; it does not bind to the network.
//
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface McLanPortDetector : NSObject

/// Singleton (for convenience; use [[McLanPortDetector alloc] init] when an independent lifecycle is needed).
+ (instancetype)sharedDetector;

#pragma mark - Path resolution (environment variables/sandbox only; no preferences, for easier unit testing)

/// Launcher home directory: POJAV_HOME → Documents.
+ (nullable NSString *)launcherHome;

/// Current instance root: POJAV_GAME_DIR → <POJAV_HOME>/instances/<instanceName|default> → Documents.
/// @param instanceName Current instance name (read by the caller from general.game_directory; nil/empty → "default").
+ (nullable NSString *)resolveGameDirectoryWithInstanceName:(nullable NSString *)instanceName;

#pragma mark - Parsing

/// Parses a log string and returns the last Minecraft LAN port found (1024..65535); returns 0 if none is found.
+ (uint16_t)parsePortFromLogText:(nullable NSString *)text;

/// Finds the port in the given log file paths: uses the file with a match and the newest modification time
/// (i.e., the most recent LAN session). Returns 0 if none is found. Reads are limited to the last 8 MB of each file.
+ (uint16_t)detectPortInLogFiles:(NSArray<NSString *> *)paths;

/// Collects and parses candidate logs (logs/latest.log, latestlog.txt, logs/*.log, etc.) from the instance and launcher directories.
/// Returns 0 if none is found.
+ (uint16_t)detectPortInGameDirectory:(nullable NSString *)gameDir
                         launcherHome:(nullable NSString *)home;

#pragma mark - Polling (while the room-creation panel is open)

/// Starts polling (1s): calls back on the main thread when the port changes (also called on first detection).
/// Stops any existing poll before starting a new one.
/// @param gameDir Instance directory (may be nil).
/// @param home    Launcher home directory (may be nil).
/// @param handler Main-thread callback (port > 0).
- (void)startPollingGameDirectory:(nullable NSString *)gameDir
                     launcherHome:(nullable NSString *)home
                          handler:(void (^)(uint16_t port))handler;

/// Stops polling (call when leaving the page, starting a session, or disconnecting). Idempotent.
- (void)stopPolling;

/// Whether polling is currently active.
@property (nonatomic, readonly) BOOL polling;

@end

NS_ASSUME_NONNULL_END
