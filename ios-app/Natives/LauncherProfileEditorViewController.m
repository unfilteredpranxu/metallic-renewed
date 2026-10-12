#import "LauncherNavigationController.h"
#import "LauncherPreferences.h"
#import "LauncherProfileEditorViewController.h"
#import "MinecraftResourceUtils.h"
#import "PickTextField.h"
#import "PLProfiles.h"
#import "ios_uikit_bridge.h"
#import "utils.h"
#import "VersionDataMigration.h"   // ★ [VER-ISOLATE-MIGRATE] Version-isolation data migration engine
#import "BackgroundManager.h"

@interface LauncherProfileEditorViewController()<UIPickerViewDataSource, UIPickerViewDelegate>
@property(nonatomic) NSString* oldName;

@property(nonatomic) NSArray<NSDictionary *> *versionList;
@property(nonatomic) UITextField* versionTextField;
@property(nonatomic) UISegmentedControl* versionTypeControl;
@property(nonatomic) UIPickerView* versionPickerView;
@property(nonatomic) UIToolbar* versionPickerToolbar;
@property(nonatomic) int versionSelectedAt;
// ★ [VER-ISOLATE-MIGRATE] Version-isolation data migration (per instance, copy-only, no automatic transfer by default)
- (void)actionMigrateVersionData;
- (void)runMigrateItems:(NSArray<NSString *> *)names removeSource:(BOOL)removeSource;
- (NSString *)ameHumanBytes:(unsigned long long)bytes;
@end

@implementation LauncherProfileEditorViewController

- (void)viewDidLoad {
    // Setup navigation bar & appearance
    // ★ [AUDIT-DECIDE] A-11: English literal as key (no matching .strings entry) → reuse existing key i18n_str_1091.
    self.title = localize(@"i18n_str_1091", nil);
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:self action:@selector(actionDone)];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemClose target:self action:@selector(actionClose)];
    self.navigationController.modalInPresentation = YES;
    self.prefSectionsVisible = YES;
    
    // Apply a translucent background.
    [[BackgroundManager sharedManager] applyEffectToView:self.view];
    
    // Apply a translucent navigation-bar style.
    [[BackgroundManager sharedManager] applyEffectToNavigationBar:self.navigationController.navigationBar];
    self.navigationController.navigationBar.tintColor = [UIColor systemBlueColor];

    // Setup preference getter and setter
    __weak LauncherProfileEditorViewController *weakSelf = self;
    self.getPreference = ^id(NSString *section, NSString *key){
        // ★ [VER-ISOLATE-PCL] Version isolation: when not explicitly set, show the "resolved effective value"
        // (matching the PCL settings page — show the result of global inheritance/automatic detection); write an explicit value only when the user changes it.
        if ([key isEqualToString:@"versionIsolation"]) {
            id raw = weakSelf.profile[key];
            if (raw) return [raw boolValue] ? @"1" : @"0";
            id vid = weakSelf.profile[@"lastVersionId"];
            return amePCLVersionIsolationForProfile(weakSelf.profile,
                       [vid isKindOfClass:NSString.class] ? (NSString *)vid : nil) ? @"1" : @"0";
        }
        id rawValue = weakSelf.profile[key];
        // Support NSDictionary-type javaVersion values written by older installers.
        if ([rawValue isKindOfClass:[NSDictionary class]]) {
            id major = rawValue[@"majorVersion"];
            return major ? [major description] : @"(default)";
        }
        NSString *value = rawValue;
        if (value.length > 0 || ![weakSelf isPickFieldAtSection:section key:key]) {
            return value;
        } else {
            return @"(default)";
        }
    };
    self.setPreference = ^(NSString *section, NSString *key, NSString *value){
        if ([value isEqualToString:@"(default)"] && [weakSelf isPickFieldAtSection:section key:key]) {
            [weakSelf.profile removeObjectForKey:key];
        } else if (value) {
            weakSelf.profile[key] = value;
        }
    };

    // Obtain all the lists
    self.oldName = self.getPreference(nil, @"name");
    if ([self.oldName length] == 0) {
        self.setPreference(nil, @"name", @"New Profile");
    }
    NSArray *rendererKeys = getRendererKeys(YES);
    NSArray *rendererList = getRendererNames(YES);
    NSArray *touchControlList = [self listFilesAtPath:[NSString stringWithFormat:@"%s/controlmap", getenv("POJAV_HOME")]];
    NSArray *gamepadControlList = [self listFilesAtPath:[NSString stringWithFormat:@"%s/controlmap/gamepads", getenv("POJAV_HOME")]];
    NSMutableArray *javaList = [getPrefObject(@"java.java_homes") allKeys].mutableCopy;
    [javaList sortUsingSelector:@selector(compare:)];
    javaList[0] = @"(default)";

    // Setup version picker
    [self setupVersionPicker];
    id typeVersionPicker = ^void(UITableViewCell *cell, NSString *section, NSString *key, NSDictionary *item){
        self.typeTextField(cell, section, key, item);
        UITextField *textField = (id)cell.accessoryView;
        weakSelf.versionTextField = textField;
        textField.inputAccessoryView = weakSelf.versionPickerToolbar;
        textField.inputView = weakSelf.versionPickerView;
        // Auto pick version type
        if (self.versionList) return;
        if ([MinecraftResourceUtils findVersion:textField.text inList:localVersionList]) {
            self.versionTypeControl.selectedSegmentIndex = 0;
        } else {
            NSDictionary *selected = (id)[MinecraftResourceUtils findVersion:textField.text inList:remoteVersionList];
            if (selected) {
                NSArray *types = @[@"installed", @"release", @"snapshot", @"old_beta", @"old_alpha"];
                NSString *type = selected[@"type"];
                self.versionTypeControl.selectedSegmentIndex = [types indexOfObject:type];
            } else {
                // Version not found
                self.versionTypeControl.selectedSegmentIndex = 0;
            }
        }
        self.versionSelectedAt = -1;
        [self changeVersionType:nil];
    };

    self.prefContents = @[
        @[
            // General settings
            @{@"key": @"name",
              @"icon": @"tag",
              @"title": @"preference.profile.title.name",
              @"type": self.typeTextField,
              @"placeholder": self.oldName
            },
            @{@"key": @"lastVersionId",
              @"icon": @"archivebox",
              @"title": @"preference.profile.title.version",
              @"type": typeVersionPicker,
              @"placeholder": self.getPreference(nil, @"lastVersionId"),
              @"customClass": PickTextField.class
            },
            @{@"key": @"gameDir",
              @"icon": @"folder",
              @"title": @"preference.title.game_directory",
              @"type": self.typeTextField,
              @"placeholder": [NSString stringWithFormat:@". -> /Documents/instances/%@", getPrefObject(@"general.game_directory")]
            },
            // ★ [VER-ISOLATE-PCL] Version-isolation switch (matches "Instance Isolation" on the PCL-CE instance settings page):
            // On = this version's mods/config/saves/... are stored separately under <instance root>/versions/<version id>/;
            // Off = shared with other versions in the instance (current behavior). Store the value as a string ("1"/"0")
            // to match the types of other profile keys (NSDictionary<NSString*,NSString*>).
            @{@"key": @"versionIsolation",
              @"icon": @"square.on.square.dashed",
              @"title": @"preference.profile.title.version_isolation",
              @"type": self.typeSwitch,
              @"customSwitchValue": @[@"0", @"1"],
              @"hasDetail": @YES,
              // ★ [VER-ISOLATE-MIGRATE] Toggling isolation changes whether the "Migrate Version Data" row below is enabled,
              // so request a full table refresh to recalculate enableCondition (reuse the existing mechanism; no visual changes).
              @"requestReload": @YES
            },
            // ★ [VER-ISOLATE-MIGRATE] Entry point for version-isolation data migration (per instance, copy-only, no automatic transfer by default):
            // available only when version isolation is enabled (enableCondition). Tapping lists the directories/files and sizes to transfer;
            // copy only after user confirmation. Sources are never deleted; same-name files are skipped by default and kept on both sides.
            // Reuses the existing typeButton row style; no visual changes.
            @{@"key": @"migrate_version_data",
              @"icon": @"arrow.right.square.on.square",
              @"title": @"preference.profile.title.migrate_version_data",
              @"type": self.typeButton,
              @"hasDetail": @YES,
              @"enableCondition": ^BOOL{
                  id vid = weakSelf.profile[@"lastVersionId"];
                  return amePCLVersionIsolationForProfile(weakSelf.profile,
                             [vid isKindOfClass:NSString.class] ? (NSString *)vid : nil);
              },
              @"action": ^void(){ [weakSelf actionMigrateVersionData]; }
            },
            // Video and renderer settings
            @{@"key": @"renderer",
              @"icon": @"cpu",
              @"type": self.typePickField,
              @"pickKeys": rendererKeys,
              @"pickList": rendererList
            },
            // Control settings
            @{@"key": @"defaultTouchCtrl",
              @"icon": @"hand.tap",
              @"title": @"preference.profile.title.default_touch_control",
              @"type": self.typePickField,
              @"pickKeys": touchControlList,
              @"pickList": touchControlList
            },
            @{@"key": @"defaultGamepadCtrl",
              @"icon": @"gamecontroller",
              @"title": @"preference.profile.title.default_gamepad_control",
              @"type": self.typePickField,
              @"pickKeys": gamepadControlList,
              @"pickList": gamepadControlList
            },
            // Java tweaks
            @{@"key": @"javaVersion",
              @"icon": @"cube",
              @"title": @"preference.manage_runtime.header.default",
              @"type": self.typePickField,
              @"pickKeys": javaList,
              @"pickList": javaList
            },
            @{@"key": @"lwjglVersion",
              @"icon": @"shippingbox",
              @"title": @"preference.profile.title.lwjgl_version",
              @"type": self.typePickField,
              @"pickKeys": @[@"(default)", @"333", @"341"],
              @"pickList": @[@"(default)", @"3.3.3", @"3.4.1"]
            },
            @{@"key": @"javaArgs",
              @"icon": @"slider.vertical.3",
              @"title": @"preference.title.java_args",
              @"type": self.typeTextField,
              @"placeholder": @"(default)"
            }
        ]
    ];

    [super viewDidLoad];
    // Adapt to the custom launcher background: make the current view controller transparent so the global background (image/video) shows through.
    // applyEffectToView above has already applied the glass/translucency effect to the view;
    // call makeViewControllerTransparent here to ensure the tableView background is transparent too.
    [[BackgroundManager sharedManager] makeViewControllerTransparent:self];

    // Listen for version-list refresh notifications.
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(reloadVersionList)
                                                 name:@"ReloadProfileList"
                                               object:nil];

    // Listen for background UI effect changes: when the user switches between glass/translucency or adjusts opacity in Background Settings,
    // call makeViewControllerTransparent again to apply the latest appearance and keep the background showing through correctly.
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(reapplyBackgroundEffect)
                                                 name:@"BackgroundUIEffectChanged"
                                               object:nil];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

/// Reapply background effects when a BackgroundUIEffectChanged notification arrives,
/// using BackgroundManager to reset the current view controller's opacity/glass effect
/// so the tableView background is transparent and the global background shows through.
- (void)reapplyBackgroundEffect {
    [[BackgroundManager sharedManager] makeViewControllerTransparent:self];
}

- (void)reloadVersionList {
    // Clear the current version-list cache; it will reload the next time the picker opens.
    self.versionList = nil;
    self.versionSelectedAt = -1;
    
    // If the version picker is visible, refresh it immediately.
    if (self.versionPickerView && self.versionPickerView.window) {
        [self changeVersionType:nil];
    }
}

- (void)actionClose {
    [self.navigationController dismissViewControllerAnimated:YES completion:nil];
}

- (void)actionDone {
    // We might be saving without ending editing, so make sure textFieldDidEndEditing is always called
    UITextField *currentTextField = [self performSelector:@selector(_firstResponder)];
    if ([currentTextField isKindOfClass:UITextField.class] && [currentTextField isDescendantOfView:self.tableView]) {
        [self textFieldDidEndEditing:currentTextField];
    }

    if ([self.profile[@"name"] length] == 0 && self.oldName.length > 0) {
        // Return to its old name
        self.profile[@"name"] = self.oldName;
    }

    if ([self.oldName isEqualToString:self.profile[@"name"]]) {
        // Not a rename, directly create/replace
        PLProfiles.current.profiles[self.oldName] = self.profile;
    } else if (!PLProfiles.current.profiles[self.profile[@"name"]]) {
        // A rename, remove then re-add to update its key name
        if (self.oldName.length > 0) {
            [PLProfiles.current.profiles removeObjectForKey:self.oldName];
        }
        PLProfiles.current.profiles[self.profile[@"name"]] = self.profile;
        // Update selected name
        if ([PLProfiles.current.selectedProfileName isEqualToString:self.oldName]) {
            PLProfiles.current.selectedProfileName = self.profile[@"name"];
        }
    } else {
        // Cancel rename since a profile with the same name already exists
        showDialog(localize(@"Error", nil), localize(@"profile.error.name_exists", nil));
        // Skip dismissing this view controller
        return;
    }

    [PLProfiles.current save];
    
    // Post a notification to refresh the profile list.
    [[NSNotificationCenter defaultCenter] postNotificationName:@"SelectedProfileChanged" object:self.profile[@"name"]];
    
    [self actionClose];
}

#pragma mark ★ [VER-ISOLATE-MIGRATE] Version-isolation data migration

- (NSString *)ameHumanBytes:(unsigned long long)bytes {
    return [NSByteCountFormatter stringFromByteCount:(long long)bytes
                                           countStyle:NSByteCountFormatterCountStyleFile];
}

- (NSString *)ameMigrationVersionId {
    id vid = self.profile[@"lastVersionId"];
    return [vid isKindOfClass:NSString.class] ? (NSString *)vid : nil;
}

/// Migration entry point (the "Migrate Version Data" row on the instance editor). Lists only the directories/files and sizes to transfer;
/// items can be selected individually and are copied only after user confirmation. Copy-only by default; sources are not deleted.
/// Does not touch rendered output or change the UI appearance.
- (void)actionMigrateVersionData {
    NSString *title = localize(@"preference.profile.title.migrate_version_data", nil);
    NSString *vid = [self ameMigrationVersionId];

    // Isolation is disabled, so there is no isolated target. Prompt the user to enable the switch; do not enable it silently.
    if (!amePCLVersionIsolationForProfile(self.profile, vid)) {
        showDialog(title, localize(@"preference.migrate.need_isolation", nil));
        return;
    }
    // Source = gameDir returned by the resolver when isolation is off (the directory the user is currently using);
    // target = directory returned when isolation is on. Both paths use the same resolver; do not construct paths manually.
    NSString *src = amePCLSharedGameDirForProfile(self.profile, vid);
    NSString *dst = amePCLVersionGameDirAbsolute(self.profile, vid);
    if (src.length == 0 || dst.length == 0 || [src isEqualToString:dst]) {
        showDialog(title, localize(@"preference.migrate.no_target", nil));
        return;
    }

    ameVDMCleanupStaleTemps(dst, ameVDMDefaultItemNames());   // Clean up leftovers from the previous interrupted operation.
    NSArray<NSDictionary *> *plan = ameVDMPlan(src, dst, ameVDMDefaultItemNames());
    if (plan.count == 0) {
        showDialog(title, localize(@"preference.migrate.nothing", nil));
        return;
    }

    NSUInteger totalFiles = 0;
    unsigned long long totalBytes = 0;
    for (NSDictionary *it in plan) {
        totalFiles += [it[@"files"] unsignedIntegerValue];
        totalBytes += [it[@"bytes"] unsignedLongLongValue];
    }
    NSString *msg = [NSString stringWithFormat:localize(@"preference.migrate.confirm.message", nil),
                     (unsigned long)plan.count, (unsigned long)totalFiles,
                     [self ameHumanBytes:totalBytes], dst];

    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:title message:msg
                                                           preferredStyle:UIAlertControllerStyleActionSheet];
    __weak LauncherProfileEditorViewController *weakSelf = self;
    // Per-item actions: show each item's size (file count / bytes) and allow it to be migrated separately.
    for (NSDictionary *it in plan) {
        NSString *rowTitle = [NSString stringWithFormat:localize(@"preference.migrate.item.title", nil),
                              it[@"name"], (unsigned long)[it[@"files"] unsignedIntegerValue],
                              [self ameHumanBytes:[it[@"bytes"] unsignedLongLongValue]]];
        [sheet addAction:[UIAlertAction actionWithTitle:rowTitle style:UIAlertActionStyleDefault
                                               handler:^(UIAlertAction *a){
            [weakSelf runMigrateItems:@[it[@"name"]] removeSource:NO];
        }]];
    }
    NSMutableArray<NSString *> *allNames = [NSMutableArray array];
    for (NSDictionary *it in plan) [allNames addObject:it[@"name"]];
    [sheet addAction:[UIAlertAction actionWithTitle:localize(@"preference.migrate.all", nil)
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction *a){
        [weakSelf runMigrateItems:allNames removeSource:NO];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:localize(@"Cancel", nil)
                                              style:UIAlertActionStyleCancel handler:nil]];
    sheet.popoverPresentationController.sourceView = self.tableView;
    sheet.popoverPresentationController.sourceRect = self.tableView.bounds;
    [self presentViewController:sheet animated:YES completion:nil];
}

/// Perform the migration and report each item; offer the destructive "Delete Source" follow-up only when the item was copied without conflicts.
- (void)runMigrateItems:(NSArray<NSString *> *)names removeSource:(BOOL)removeSource {
    NSString *vid = [self ameMigrationVersionId];
    NSString *src = amePCLSharedGameDirForProfile(self.profile, vid);   // Resolver result with isolation off.
    NSString *dst = amePCLVersionGameDirAbsolute(self.profile, vid);    // Resolver result with isolation on.
    NSDictionary *opts = @{@"conflictPolicy": @(ameVDMConflictSkip), @"removeSource": @(removeSource)};
    NSDictionary *rep = ameVDMExecute(src, dst, names, opts);

    NSUInteger copied = 0, identical = 0, conflicts = 0, renamed = 0;
    NSMutableString *body = [NSMutableString string];
    NSMutableArray<NSString *> *issues = [NSMutableArray array];
    for (NSDictionary *r in rep[@"items"]) {
        copied    += [r[@"copied"] unsignedIntegerValue];
        identical += [r[@"identical"] unsignedIntegerValue];
        conflicts += [r[@"conflict"] unsignedIntegerValue];
        renamed   += [r[@"renamed"] unsignedIntegerValue];
        [body appendFormat:@"%@\n", [NSString stringWithFormat:localize(@"preference.migrate.line", nil),
            r[@"name"], (unsigned long)[r[@"copied"] unsignedIntegerValue],
            (unsigned long)[r[@"identical"] unsignedIntegerValue],
            (unsigned long)[r[@"conflict"] unsignedIntegerValue],
            (unsigned long)[r[@"renamed"] unsignedIntegerValue]]];
        for (NSString *e in r[@"errors"]) [issues addObject:e];
    }
    [body appendFormat:@"%@", [NSString stringWithFormat:localize(@"preference.migrate.summary", nil),
        (unsigned long)copied, (unsigned long)identical, (unsigned long)conflicts, (unsigned long)renamed]];
    if (removeSource && [rep[@"removed"] boolValue]) {
        [body appendFormat:@"\n%@", localize(@"preference.migrate.removed", nil)];
    }
    if (issues.count > 0) {
        [body appendFormat:@"\n\n%@\n· %@", localize(@"preference.migrate.issues", nil),
            [issues componentsJoinedByString:@"\n· "]];
    }

    UIAlertController *alert = [UIAlertController alertControllerWithTitle:localize(@"preference.migrate.result.title", nil)
                                                                  message:body
                                                           preferredStyle:UIAlertControllerStyleAlert];
    if (!removeSource && copied > 0 && conflicts == 0) {
        __weak LauncherProfileEditorViewController *weakSelf = self;
        [alert addAction:[UIAlertAction actionWithTitle:localize(@"preference.migrate.cleanup_source", nil)
                                                  style:UIAlertActionStyleDestructive
                                                handler:^(UIAlertAction *a){
            [weakSelf runMigrateItems:names removeSource:YES];
        }]];
    }
    [alert addAction:[UIAlertAction actionWithTitle:localize(@"OK", nil)
                                              style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (BOOL)isPickFieldAtSection:(NSString *)section key:(NSString *)key {
    NSDictionary *pref = [self.prefContents[0] filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"(key == %@)", key]].firstObject;
    return pref[@"type"] == self.typePickField;
}

- (NSArray *)listFilesAtPath:(NSString *)path {
    NSMutableArray *files = [NSFileManager.defaultManager contentsOfDirectoryAtPath:path error:nil].mutableCopy;
    for (int i = 0; i < files.count;) {
        if ([files[i] hasSuffix:@".json"]) {
            i++;
        } else {
            [files removeObjectAtIndex:i];
        }
    }
    [files insertObject:@"(default)" atIndex:0];
    return files;
}

#pragma mark Version picker

- (void)setupVersionPicker {
    self.versionPickerView = [[UIPickerView alloc] init];
    self.versionPickerView.delegate = self;
    self.versionPickerView.dataSource = self;
    self.versionPickerToolbar = [[UIToolbar alloc] initWithFrame:CGRectMake(0.0, 0.0, self.view.frame.size.width, 44.0)];
    self.versionTypeControl = [[UISegmentedControl alloc] initWithItems:@[
        localize(@"Installed", nil),
        localize(@"Releases", nil),
        localize(@"Snapshot", nil),
        localize(@"Old-beta", nil),
        localize(@"Old-alpha", nil)
    ]];
    [self.versionTypeControl addTarget:self action:@selector(changeVersionType:) forControlEvents:UIControlEventValueChanged];
    self.versionPickerToolbar.items = @[
        [[UIBarButtonItem alloc] initWithCustomView:self.versionTypeControl],
        [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:nil action:nil],
        [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:self action:@selector(versionClosePicker)]
    ];
}

- (void)pickerView:(UIPickerView *)pickerView didSelectRow:(NSInteger)row inComponent:(NSInteger)component {
    if (self.versionList.count == 0) {
        self.versionTextField.text = @"";
        return;
    }
    self.versionSelectedAt = row;
    self.versionTextField.text = [self pickerView:pickerView titleForRow:row forComponent:component];
}

- (NSInteger)numberOfComponentsInPickerView:(UIPickerView *)thePickerView {
    return 1;
}

- (NSInteger)pickerView:(UIPickerView *)pickerView numberOfRowsInComponent:(NSInteger)component {
    return self.versionList.count;
}

- (NSString *)pickerView:(UIPickerView *)pickerView titleForRow:(NSInteger)row forComponent:(NSInteger)component {
    if (self.versionList.count <= row) return nil;
    NSObject *object = self.versionList[row];
    if ([object isKindOfClass:[NSString class]]) {
        return (NSString*) object;
    } else {
        return [object valueForKey:@"id"];
    }
}

- (void)versionClosePicker {
    [self.versionTextField endEditing:YES];
    [self pickerView:self.versionPickerView didSelectRow:[self.versionPickerView selectedRowInComponent:0] inComponent:0];
}

- (void)changeVersionType:(UISegmentedControl *)sender {
    NSArray *newVersionList = self.versionList;
    if (sender || !self.versionList) {
        if (self.versionTypeControl.selectedSegmentIndex == 0) {
            // installed
            newVersionList = localVersionList;
        } else {
            NSString *type = @[@"installed", @"release", @"snapshot", @"old_beta", @"old_alpha"][self.versionTypeControl.selectedSegmentIndex];
            newVersionList = [remoteVersionList filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"(type == %@)", type]];
        }
    }

    if (self.versionSelectedAt == -1) {
        NSDictionary *selected = (id)[MinecraftResourceUtils findVersion:self.versionTextField.text inList:newVersionList];
        self.versionSelectedAt = [newVersionList indexOfObject:selected];
    } else {
        // Find the most matching version for this type
        NSObject *lastSelected = nil; 
        if (self.versionList.count > self.versionSelectedAt) {
            lastSelected = self.versionList[self.versionSelectedAt];
        }
        if (lastSelected != nil) {
            NSObject *nearest = [MinecraftResourceUtils findNearestVersion:lastSelected expectedType:self.versionTypeControl.selectedSegmentIndex];
            if (nearest != nil) {
                self.versionSelectedAt = [newVersionList indexOfObject:(id)nearest];
            }
        }
        lastSelected = nil;
        // Get back the currently selected in case none matching version found
        self.versionSelectedAt = MIN(abs(self.versionSelectedAt), newVersionList.count - 1);
    }

    self.versionList = newVersionList;
    [self.versionPickerView reloadAllComponents];
    if (self.versionSelectedAt != -1) {
        [self.versionPickerView selectRow:self.versionSelectedAt inComponent:0 animated:NO];
        [self pickerView:self.versionPickerView didSelectRow:self.versionSelectedAt inComponent:0];
    }
}

@end
