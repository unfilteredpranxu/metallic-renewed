//
//  AMEGlassStyle.h — ★ [GLASS-STYLE] UI style resolution layer (single source of truth)
//
//  Background (upstream request):
//    The home and settings screens previously implemented LiquidGlass entirely in code
//    (blur + highlight stroke + inner highlight + outer shadow + private backdrop tuning).
//    This let older systems "experience" liquid glass, but looked out of place. The requested split:
//      ① iOS < 26 ⇒ use the system's native style (system colors / materials / default control appearance);
//         no more drawing glass entirely in code.
//      ② iOS >= 26 ⇒ call the system Liquid Glass API (UIGlassEffect) by default, rather than
//         implementing it in code.
//      ③ On iOS >= 26, users can choose "Native Style / Liquid Glass Style" in Settings;
//         iOS < 26 supports only native style due to system limitations.
//
//  Design: this header is the single source of truth, shared by the UI (Settings screen) and material
//  layer (BackgroundManager / UIKit+GlassSurface). Header-only, all static inline / #define ⇒
//  no new .m file and no change to the CMake source list.
//
//  ★ [GLASS-LIQUID|2026-10-03] Clarified definition: "pure liquid" = use only the system UIGlassEffect
//    on iOS ≥26; do not draw glass in code. On iOS <26, use only system-native materials.
//    Hand-drawn glass effects (stroke/inner highlight/outer shadow/white fill/private backdrop tuning)
//    are disabled globally by default and are added only if the user explicitly enables the
//    "Hand-drawn Highlights" switch on the same Settings screen.
//
//  Decision matrix (see _GLASS_STYLE.md §② / _GLASS_LIQUID_FIX.md):
//    ┌───────────┬──────────────┬──────────────┬──────────────┐
//    │ Setting   │ iOS < 26     │ iOS == 26    │ Description   │
//    ├───────────┼──────────────┼──────────────┼──────────────┤
//    │ auto      │ native       │ liquid       │ Default       │
//    │ native    │ native       │ native       │ User chose native explicitly │
//    │ liquid    │ native(forced)│ liquid      │ Disabled on <26 │
//    └───────────┴──────────────┴──────────────┴──────────────┘
//    · Material: liquid ⇒ system UIGlassEffect; native ⇒ standard system UIBlurEffect material.
//    · Hand-drawn effects: off by default (AMEGlassStyleAllowsHandDrawnGlass()==NO); added only
//      when "Hand-drawn Highlights" is explicitly enabled.
//
//  Compatibility: minimum iOS 14.0; iPhone / iPad; portrait / landscape (this layer contains no
//  layout and is therefore orientation-independent).
//
#ifndef AME_GLASS_STYLE_H
#define AME_GLASS_STYLE_H

#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <objc/message.h>
#import <objc/runtime.h>

NS_ASSUME_NONNULL_BEGIN

/// UI style (user-configurable).
typedef NS_ENUM(NSInteger, AMEGlassStyle) {
    AMEGlassStyleAuto   = 0,   // Automatic: iOS>=26 ⇒ Liquid Glass; iOS<26 ⇒ native
    AMEGlassStyleNative = 1,   // Native: system controls/materials; no more drawing glass entirely in code
    AMEGlassStyleLiquid = 2,   // Liquid Glass: system UIGlassEffect (iOS 26+)
};

/// Preference key: uses the same store and prefix as the "highlight switch / intensity" in this
/// section (BackgroundManager's NSUserDefaults key background_glass_*). Does not occupy the
/// launcher's launcher_preferences.plist general.* namespace (those use PLPreferences/getPrefObject,
/// not NSUserDefaults; mixing them up could suggest that Settings Reset will clear these values).
#define AMEGlassStylePrefKey                @"background_glass_style"
/// ★ [GLASS-LIQUID] Optional switch for hand-drawn glass effects (stroke / inner highlight / outer shadow /
///   white fill / private backdrop tuning).
///   Defaults to **NO** — per the "pure liquid" definition, iOS ≥26 uses only system UIGlassEffect,
///   with no hand-drawn overlay; iOS <26 uses only the system-native style.
///   Hand-drawn effects are added only when the user explicitly enables them (as extra decoration
///   over system glass, not as a "code-drawn imitation of liquid glass").
#define AMEGlassStyleHandDrawnPrefKey       @"background_glass_handdrawn"
/// Notification for style / hand-drawn switch changes (BackgroundManager listens and immediately
/// refreshes using the new style).
#define AMEGlassStyleChangedNotification    @"AMEGlassStyleChanged"

#pragma mark - Enum <-> string

static inline NSString *AMEGlassStyleStringFromEnum(AMEGlassStyle s) {
    switch (s) {
        case AMEGlassStyleNative: return @"native";
        case AMEGlassStyleLiquid: return @"liquid";
        case AMEGlassStyleAuto:
        default:                  return @"auto";
    }
}

static inline AMEGlassStyle AMEGlassStyleEnumFromString(NSString * _Nullable v) {
    if ([v isKindOfClass:[NSString class]]) {
        if ([v isEqualToString:@"native"]) return AMEGlassStyleNative;
        if ([v isEqualToString:@"liquid"]) return AMEGlassStyleLiquid;
    }
    return AMEGlassStyleAuto;
}

#pragma mark - System capability detection (two checks)

/// ① System-version check: running on iOS 26 or later.
/// ★ Use @available only for a runtime check — it is not an iOS 26 compile-time symbol,
///   so this also builds with older SDKs (Xcode 15.x / iOS 17 SDK).
static inline BOOL AMEGlassStyleSystemVersionIs26OrLater(void) {
    if (@available(iOS 26.0, *)) { return YES; }
    return NO;
}

/// Whether the system supports system Liquid Glass (iOS 26+ and UIGlassEffect is actually available).
/// ★ Two checks: ① runtime OS version ≥ 26 (@available, not a compile-time symbol)
///               ② UIGlassEffect exists and effectWithStyle: returns an actual UIVisualEffect.
///   No iOS 26 compile-time symbols are used, so this also builds with Xcode 15.x (iOS 17 SDK).
/// The result is cached with dispatch_once.
static inline BOOL AMEGlassStyleSystemSupportsLiquid(void) {
    static BOOL sSupports = NO;
    static dispatch_once_t sOnce;
    dispatch_once(&sOnce, ^{
        // ★ Check ①: OS version < 26 ⇒ unsupported (the system does not provide the new appearance,
        //   so finding the class alone is not sufficient).
        if (!AMEGlassStyleSystemVersionIs26OrLater()) {
            NSLog(@"[glass] UI style detection: system < iOS 26 ⇒ only native style is available");
            sSupports = NO;
            return;
        }
        // ★ Check ②: class exists and can actually create a UIVisualEffect (otherwise fall back to native).
        Class cls = NSClassFromString(@"UIGlassEffect");
        if (cls != Nil && [cls respondsToSelector:@selector(effectWithStyle:)]) {
            id eff = ((id (*)(id, SEL, NSInteger))objc_msgSend)(cls, @selector(effectWithStyle:), 0); // Regular == 0
            sSupports = (eff != nil && [eff isKindOfClass:[UIVisualEffect class]]);
        }
        NSLog(@"[glass] UI style detection: system ≥ iOS 26 · UIGlassEffect %@ ⇒ Liquid Glass %@",
              (cls != Nil) ? @"found" : @"not found", sSupports ? @"available" : @"unavailable (falling back to native)");
    });
    return sSupports;
}

#pragma mark - Read/write configuration

/// User-configured value (unset ⇒ auto).
static inline AMEGlassStyle AMEGlassStyleConfigured(void) {
    id v = [[NSUserDefaults standardUserDefaults] objectForKey:AMEGlassStylePrefKey];
    return AMEGlassStyleEnumFromString([v isKindOfClass:[NSString class]] ? v : nil);
}

/// ★ Apply the decision matrix and return the style that is actually in effect.
///   iOS < 26: always force native regardless of configuration (system limitation; liquid is disabled in the UI).
static inline AMEGlassStyle AMEGlassStyleResolved(void) {
    if (!AMEGlassStyleSystemSupportsLiquid()) {
        return AMEGlassStyleNative;   // ★ System limitation ⇒ force native
    }
    // At this point, the system must support Liquid Glass (iOS >= 26).
    return (AMEGlassStyleConfigured() == AMEGlassStyleNative) ? AMEGlassStyleNative : AMEGlassStyleLiquid;
}

/// Is Liquid Glass actually in effect?
static inline BOOL AMEGlassStyleUsesLiquidGlass(void) {
    return AMEGlassStyleResolved() == AMEGlassStyleLiquid;
}

/// Is the native appearance actually in effect?
static inline BOOL AMEGlassStyleUsesNativeAppearance(void) {
    return AMEGlassStyleResolved() == AMEGlassStyleNative;
}

/// Whether pure-code glass effects may be drawn (highlight stroke / inner highlight / outer shadow /
/// private backdrop tuning / white fill).
/// ★ [GLASS-LIQUID] Per the "pure liquid" definition, iOS ≥26 uses system UIGlassEffect and iOS <26
///   uses system-native materials; neither draws glass in code. Therefore, this returns NO by default
///   (hand-drawn effects are globally disabled).
///   The old appearance is overlaid on system glass only if the user explicitly enables
///   "Hand-drawn Highlights" on the same Settings screen (OPT-IN).
static inline BOOL AMEGlassStyleHandDrawnOverlayEnabled(void) {
    id v = [[NSUserDefaults standardUserDefaults] objectForKey:AMEGlassStyleHandDrawnPrefKey];
    return v ? [[NSUserDefaults standardUserDefaults] boolForKey:AMEGlassStyleHandDrawnPrefKey] : NO;   // Off by default
}

/// ★ [GLASS-LIQUID] Master switch: may glass currently be drawn in code?
///   = the system provides UIGlassEffect (iOS≥26) AND the user explicitly enabled the hand-drawn switch.
///   Always NO on iOS<26 (the system does not provide the new appearance; use system materials).
static inline BOOL AMEGlassStyleAllowsHandDrawnGlass(void) {
    return AMEGlassStyleUsesLiquidGlass() && AMEGlassStyleHandDrawnOverlayEnabled();
}

/// ★ [GLASS-LIQUID] Is the "system material" path active (material provided by the system, not hand-drawn)?
///   iOS≥26 ⇒ system UIGlassEffect; iOS<26 ⇒ standard system UIBlurEffect material. YES for both.
static inline BOOL AMEGlassStyleUsesSystemMaterial(void) {
    return !AMEGlassStyleAllowsHandDrawnGlass();
}

/// Write the hand-drawn switch and broadcast (called by the Settings-screen action).
static inline void AMEGlassStyleSetHandDrawnOverlayEnabled(BOOL on) {
    [[NSUserDefaults standardUserDefaults] setBool:on forKey:AMEGlassStyleHandDrawnPrefKey];
    [[NSNotificationCenter defaultCenter] postNotificationName:AMEGlassStyleChangedNotification object:nil];
    NSLog(@"[glass] Hand-drawn glass effects = %@ (default off; iOS≥26 uses system UIGlassEffect only)",
          on ? @"on (overlaid on system glass)" : @"off");
}

/// Write the configuration and broadcast (called by the Settings-screen action; the common preference
/// store handles persistence, with an additional write here as a safeguard).
static inline void AMEGlassStyleSetConfigured(AMEGlassStyle s) {
    [[NSUserDefaults standardUserDefaults] setObject:AMEGlassStyleStringFromEnum(s) forKey:AMEGlassStylePrefKey];
    [[NSNotificationCenter defaultCenter] postNotificationName:AMEGlassStyleChangedNotification object:nil];
    NSLog(@"[glass] UI style set to %@ (system supports Liquid Glass=%d ⇒ actually in effect=%@)",
          AMEGlassStyleStringFromEnum(s),
          (int)AMEGlassStyleSystemSupportsLiquid(),
          AMEGlassStyleStringFromEnum(AMEGlassStyleResolved()));
}

/// Emit one readable diagnostic at launch so the style decision can be verified.
static inline void AMEGlassStyleLogResolvedOnce(void) {
    static dispatch_once_t sOnce;
    dispatch_once(&sOnce, ^{
        NSLog(@"[glass] Style decision: configured=%@ · system supports Liquid Glass=%@ · actually in effect=%@ · hand-drawn glass=%@ (SDK=%s)",
              AMEGlassStyleStringFromEnum(AMEGlassStyleConfigured()),
              AMEGlassStyleSystemSupportsLiquid() ? @"yes" : @"no",
              AMEGlassStyleStringFromEnum(AMEGlassStyleResolved()),
              AMEGlassStyleAllowsHandDrawnGlass() ? @"on (opt-in)" : @"off (system only)",
              __VERSION__);
    });
}

NS_ASSUME_NONNULL_END
#endif /* AME_GLASS_STYLE_H */
