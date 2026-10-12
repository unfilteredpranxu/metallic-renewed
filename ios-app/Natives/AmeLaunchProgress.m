//
//  AmeLaunchProgress.m
//  ★ [LAUNCH-PROGRESS] Implementation of the launch-stage reporting API
//
//  Does only three things: store state, lock, and broadcast. It does not depend on launcher internals,
//  so it can evolve independently.
//

#import "AmeLaunchProgress.h"

// Starting fraction for each stage: the progress bar jumps to this fraction when a stage begins.
// Monotonically increasing; Completed = 1.0. These are empirical values: the early stages
// (environment / JIT / renderer resolution) are fast, while the final "wait for game frame" takes
// the most time, so it gets a larger range (0.90 → 1.00).
static double const kAmeStageFractions[] = {
    0.00,  // AmeLaunchStagePrepareEnv
    0.10,  // AmeLaunchStageJITReady
    0.25,  // AmeLaunchStageRenderer
    0.40,  // AmeLaunchStageRuntime
    0.60,  // AmeLaunchStageArgsReady
    0.75,  // AmeLaunchStageJVMStarting
    0.90,  // AmeLaunchStageWaitingFirstFrame
    1.00,  // AmeLaunchStageCompleted
};

NSNotificationName const AmeLaunchProgressChangedNotification = @"AmeLaunchProgressChanged";

// ---- Internal state (protected by sAmeLock) ----
static NSLock *sAmeLock = nil;
static AmeLaunchStage sAmeStage = AmeLaunchStagePrepareEnv;
static double sAmeFraction = 0.0;
static NSString *sAmeKey = nil;

/// Lazily create the lock. dispatch_once is thread-safe, so the first call is safe on any thread.
static NSLock *AmeLaunchProgressLock(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sAmeLock = [[NSLock alloc] init];
    });
    return sAmeLock;
}

/// Always broadcast on the main queue, so subscribers (the UI) do not need to switch threads.
static void AmeLaunchProgressPostChanged(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:AmeLaunchProgressChangedNotification
                                                            object:nil];
    });
}

NSInteger AmeLaunchProgressStageCount(void) {
    return (NSInteger)(sizeof(kAmeStageFractions) / sizeof(kAmeStageFractions[0]));
}

void AmeLaunchProgressReset(void) {
    NSLock *lock = AmeLaunchProgressLock();
    [lock lock];
    sAmeStage = AmeLaunchStagePrepareEnv;
    sAmeFraction = kAmeStageFractions[AmeLaunchStagePrepareEnv];
    sAmeKey = nil;
    [lock unlock];
    AmeLaunchProgressPostChanged();
}

void AmeLaunchProgressSetStage(AmeLaunchStage stage) {
    if (stage < 0 || stage >= AmeLaunchProgressStageCount()) {
        return;   // Ignore out-of-range values defensively; a broken reporting call must not disrupt launch.
    }
    NSLock *lock = AmeLaunchProgressLock();
    [lock lock];
    sAmeStage = stage;
    sAmeFraction = kAmeStageFractions[stage];
    sAmeKey = nil;
    [lock unlock];
    AmeLaunchProgressPostChanged();
}

void AmeLaunchProgressReport(NSString *key, double fraction) {
    if (fraction < 0.0) fraction = 0.0;
    if (fraction > 1.0) fraction = 1.0;
    NSLock *lock = AmeLaunchProgressLock();
    [lock lock];
    sAmeFraction = fraction;
    sAmeKey = [key copy];   // key may be nil
    [lock unlock];
    AmeLaunchProgressPostChanged();
}

AmeLaunchStage AmeLaunchProgressCurrentStage(void) {
    NSLock *lock = AmeLaunchProgressLock();
    [lock lock];
    AmeLaunchStage stage = sAmeStage;
    [lock unlock];
    return stage;
}

double AmeLaunchProgressCurrentFraction(void) {
    NSLock *lock = AmeLaunchProgressLock();
    [lock lock];
    double fraction = sAmeFraction;
    [lock unlock];
    return fraction;
}

NSString *AmeLaunchProgressCurrentKey(void) {
    NSLock *lock = AmeLaunchProgressLock();
    [lock lock];
    NSString *key = sAmeKey;
    [lock unlock];
    return key;
}

NSString *AmeLaunchStageLocalizationKey(AmeLaunchStage stage) {
    switch (stage) {
        case AmeLaunchStagePrepareEnv:      return @"launch.progress.stage.prepare_env";
        case AmeLaunchStageJITReady:        return @"launch.progress.stage.jit_ready";
        case AmeLaunchStageRenderer:        return @"launch.progress.stage.renderer";
        case AmeLaunchStageRuntime:         return @"launch.progress.stage.runtime";
        case AmeLaunchStageArgsReady:       return @"launch.progress.stage.args_ready";
        case AmeLaunchStageJVMStarting:     return @"launch.progress.stage.jvm_starting";
        case AmeLaunchStageWaitingFirstFrame: return @"launch.progress.stage.waiting_first_frame";
        case AmeLaunchStageCompleted:       return @"launch.progress.stage.completed";
    }
    return @"launch.progress.stage.prepare_env";
}
