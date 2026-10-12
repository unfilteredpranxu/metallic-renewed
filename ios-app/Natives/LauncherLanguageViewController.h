#pragma once

#import <UIKit/UIKit.h>

// ★ [LANG-SWITCH] Launcher UI language-selection subpage:
//   Section 0 is "Follow System"; section 1 lists "Available Languages" (automatically enumerate all
//   .lproj directories in the app bundle; obtain display names from NSLocale). Selecting a language
//   writes the custom NSUserDefaults key (ame_launcher_language) and broadcasts
//   AmeLauncherLanguageChangedNotification.
// Pushed from the "Language" item (typeChildPane) in LauncherPreferencesViewController.
@interface LauncherLanguageViewController : UITableViewController

@end

// ★ [LANG-SWITCH] Language-change broadcast: pages reloadData/re-fetch localize() text when received,
// applying the change immediately.
extern NSString * const AmeLauncherLanguageChangedNotification;
