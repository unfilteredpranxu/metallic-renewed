//
//  AmePerfProbe.h
//  ★ [PERF] Low-overhead scrolling frame-rate probe (disabled by default)
//
//  Purpose: use logs to determine whether scrolling still produces stuttering frames that exceed
//  the per-frame budget (16.7ms at 60Hz).
//
//  ★ Criteria (single source of truth in AmePerfProbe.m; change it there to change the criteria):
//    · Frame interval > 16.7ms ⇒ count one jank (below 60fps; a frame was dropped)
//    · Frame interval > 33.4ms ⇒ count one severe event (below 30fps)
//    · A single frame > 500ms ⇒ treat as a session gap and exclude from statistics
//    · At the end of each scrolling session, print one line:
//        [PERF][scroll] tag=<page> frames=N avg=?ms p95=?ms max=?ms
//                       jank(>16.7ms)=n(P%) severe(>33.4ms)=m ⇒ result: smooth/stuttering
//      "Smooth" means severe == 0 and the jank percentage is < 1%.
//    · If severe > 0, print one additional line with the slowest frame times to help locate the issue.
//
//  ★ Overhead: when not scrolling, the probe does not run at all—no CADisplayLink, timer, or polling.
//    While scrolling, each frame requires only a dozen or so floating-point comparisons and one static
//    array write; it allocates no objects, takes no locks, and builds no strings (the string is built
//    only once, at the end of a session). The probe therefore does not itself cause stuttering.
//
//  ★ Enable it with either of the following (disabled by default):
//    1) Environment variable: AME_PERF_PROBE=1
//    2) Preference key: debug.perf_probe = YES (setPrefObject(@"debug.perf_probe", @YES))
//
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface AmePerfProbe : NSObject

/// Whether the probe is enabled (environment variable AME_PERF_PROBE=1 or preference key debug.perf_probe=YES).
/// The result is read and cached only once.
+ (BOOL)isEnabled;

/// Call from the scrolling callback (once per scrollViewDidScroll is sufficient).
/// The first call starts CADisplayLink; the session ends and emits statistics after about 0.25s
/// without scrolling activity.
/// If disabled, this method returns immediately (one static BOOL check).
/// tag distinguishes pages (e.g. @"VersionManager" / @"ProfileSettings"); only the first tag per
/// session is recorded.
+ (void)noteScrollActivity:(NSString *)tag;

@end

NS_ASSUME_NONNULL_END
