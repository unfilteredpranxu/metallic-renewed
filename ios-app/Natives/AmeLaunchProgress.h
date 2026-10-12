//
//  AmeLaunchProgress.h
//  ★ [LAUNCH-PROGRESS] Launch-stage reporting API
//
//  Design goal: provide a single, observable source of truth for the current launch stage.
//  The launch pipeline is spread across JavaLauncher.m / SurfaceViewController.m, while the
//  overlay UI is in SurfaceViewController.m. This provides a very thin "stage + fraction" pub/sub layer:
//
//    - Reporter (any thread): AmeLaunchProgressSetStage(...) / Report(...)
//    - Subscriber (main thread): listen for AmeLaunchProgressChangedNotification, then read the getters.
//
//  Thread-safe: NSLock protects the state internally; notifications are always dispatched to the main
//  queue, so the UI does not need to switch threads itself.
//  This layer does not change any launch logic; it only reports the current stage.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Launch stages (listed in actual pipeline order so the "step skeleton" reads top to bottom).
///
/// Note: the requested order was "renderer → runtime → JIT ready", but JIT26 region setup/script
/// attachment (the requiresDebugJITMapping branch in JavaLauncher.m) occurs before renderer
/// resolution in the code. These stages are therefore listed in execution order; otherwise the
/// step skeleton would skip ahead and obscure where progress is stuck.
typedef NS_ENUM(NSInteger, AmeLaunchStage) {
    AmeLaunchStagePrepareEnv = 0,      ///< Prepare environment
    AmeLaunchStageJITReady,            ///< JIT ready
    AmeLaunchStageRenderer,            ///< Renderer and graphics API
    AmeLaunchStageRuntime,             ///< Runtime (Java · memory)
    AmeLaunchStageArgsReady,           ///< Assemble launch arguments
    AmeLaunchStageJVMStarting,         ///< Start JVM
    AmeLaunchStageWaitingFirstFrame,   ///< Wait for game frame
    AmeLaunchStageCompleted,           ///< Completed
};

/// Number of stages (for iterating over the step skeleton).
FOUNDATION_EXPORT NSInteger AmeLaunchProgressStageCount(void);

/// Broadcast when the stage / fraction changes. Dispatched on the main queue for the overlay to observe.
FOUNDATION_EXPORT NSNotificationName const AmeLaunchProgressChangedNotification;

/// Reset to the initial state (call before each launch; broadcasts once).
FOUNDATION_EXPORT void AmeLaunchProgressReset(void);

/// Report entry into a stage. The stage fraction is set to its starting weight; thread-safe.
FOUNDATION_EXPORT void AmeLaunchProgressSetStage(AmeLaunchStage stage);

/// Fine-grained report: set a 0..1 fraction directly and optionally attach a text key
/// (nil = keep the stage's text). Thread-safe. Used for smooth progress within a stage
/// (for example, while waiting for the game frame).
FOUNDATION_EXPORT void AmeLaunchProgressReport(NSString * _Nullable key, double fraction);

/// Read the current state (for overlay rendering). Thread-safe.
FOUNDATION_EXPORT AmeLaunchStage AmeLaunchProgressCurrentStage(void);
FOUNDATION_EXPORT double AmeLaunchProgressCurrentFraction(void);
FOUNDATION_EXPORT NSString * _Nullable AmeLaunchProgressCurrentKey(void);

/// Stage → localization key (used for both the current-stage text and step-skeleton text).
FOUNDATION_EXPORT NSString *AmeLaunchStageLocalizationKey(AmeLaunchStage stage);

NS_ASSUME_NONNULL_END
