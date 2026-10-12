//
//  AiSettingsTools.m
//  Amethyst
//

#import "AiSettingsTools.h"
#import "LauncherPreferences.h"
#import "PLProfiles.h"
#import "utils.h"

@interface AiSettingsTools ()
@property (nonatomic, copy) NSString *internalName;
@end

@implementation AiSettingsTools

- (instancetype)initWithName:(NSString *)name {
    self = [super init];
    if (self) {
        _internalName = [name copy] ?: @"";
    }
    return self;
}

- (NSString *)name {
    return self.internalName;
}

- (AiToolPermission)permission {
    if ([self.internalName isEqualToString:@"set_setting"]) {
        return AiToolPermissionControlledWrite;
    }
    return AiToolPermissionReadOnly;
}

- (NSString *)summary {
    if ([self.internalName isEqualToString:@"list_settings"]) {
        return @"List the setting keys supported by the launcher and their value descriptions."
               "\nNo parameters."
               "\nAvailable keys: video.renderer (renderer, instance-level: auto/GL4ES/ANGLE/MobileGlues/Zink/MoltenVK/LTW), "
               "video.graphics_api (graphics API, instance-level, effective in MC 26.2+: default/prefer_vulkan/prefer_opengl), "
               "java.allocated_memory (game memory in MB, global), java.auto_ram (automatic memory allocation, global, true/false), "
               "java.java_args (JVM arguments, global with instance-level override), general.download_source (download source, global: official/bmclapi), "
               "general.game_directory (current game directory name, global), control.default_ctrl (default control layout, global).";
    }
    if ([self.internalName isEqualToString:@"get_setting"]) {
        return @"Read the current value of a specified setting key."
               "\nParameters: key (string, required, see list_settings), instance (string, optional, instance/profile name; defaults to the currently selected instance)."
               "\nReturns: global value + effective instance value (instance value takes precedence; falls back to global if not set for the instance).";
    }
    // set_setting
    return @"Change a launcher setting."
           "\nParameters: key (string, required), value (string/number/boolean, required), instance (string, optional; defaults to changing the currently selected instance or the global setting)."
           "\nDetails: video.renderer / video.graphics_api are instance-level settings (written to the specified instance's profile); "
           "all other keys are global. For renderer, you may provide a friendly name (MoltenVK/Zink/MobileGlues/GL4ES/ANGLE/auto); it is automatically mapped to its stored key."
           "\nOn success, returns the new value and broadcasts a refresh notification. User confirmation is requested before execution unless in YOLO mode.";
}

#pragma mark - Key metadata

/// Instance-level key → profile field name
+ (NSDictionary<NSString *, NSString *> *)profileKeyMap {
    return @{
        @"video.renderer": @"renderer",
        @"video.graphics_api": @"graphicsApi",
        @"java.java_args": @"javaArgs",
    };
}

/// Renderer friendly name → storage key (actual value from getRendererKeys)
+ (NSString *)rendererStorageKeyForValue:(NSString *)value {
    if (value.length == 0) return nil;
    NSString *lower = [value lowercaseString];
    // If the input is already a storage key (libxxx.dylib / auto), return it unchanged
    NSArray *keys = getRendererKeys(NO);
    for (NSString *key in keys) {
        if ([key.lowercaseString isEqualToString:lower]) return key;
    }
    if ([lower isEqualToString:@"auto"] || [lower containsString:@"automatic"]) return @"auto";
    if ([lower containsString:@"moltenvk"] || [lower containsString:@"vulkan"]) return @(RENDERER_NAME_VULKAN);
    if ([lower containsString:@"zink"] || [lower containsString:@"mesa"] || [lower containsString:@"osmesa"]) return @(RENDERER_NAME_VK_ZINK);
    if ([lower containsString:@"mobileglues"] || [lower isEqualToString:@"mg"]) return @(RENDERER_NAME_MOBILEGLUES);
    if ([lower containsString:@"angle"] || [lower containsString:@"tinygl4"]) return @(RENDERER_NAME_MTL_ANGLE);
    // Must come after angle: "MetalANGLE" also contains the "metal" substring
    if ([lower containsString:@"metallum"] || [lower containsString:@"metal"]) return @(RENDERER_NAME_METAL);
    if ([lower containsString:@"gl4es"]) return @(RENDERER_NAME_GL4ES);
    if ([lower containsString:@"ltw"]) return @(RENDERER_NAME_LTW);
    return nil;
}

/// Renderer storage key → friendly name (output for the AI)
+ (NSString *)rendererFriendlyName:(NSString *)storageKey {
    if ([storageKey isEqualToString:@"auto"]) return @"auto";
    if ([storageKey isEqualToString:@(RENDERER_NAME_VULKAN)]) return @"MoltenVK (libMoltenVK.dylib)";
    if ([storageKey isEqualToString:@(RENDERER_NAME_VK_ZINK)]) return @"Zink (libOSMesa.8.dylib)";
    if ([storageKey isEqualToString:@(RENDERER_NAME_MOBILEGLUES)]) return @"MobileGlues (libmobileglues.dylib)";
    if ([storageKey isEqualToString:@(RENDERER_NAME_MTL_ANGLE)]) return @"ANGLE/MetalANGLE (libtinygl4angle.dylib)";
    if ([storageKey isEqualToString:@(RENDERER_NAME_GL4ES)]) return @"GL4ES (libgl4es_114.dylib)";
    if ([storageKey isEqualToString:@(RENDERER_NAME_METAL)]) return @"Metal (libmetallum.dylib)";
    if ([storageKey isEqualToString:@(RENDERER_NAME_LTW)]) return @"LTW (libltw.dylib)";
    return storageKey;
}

+ (NSString *)graphicsApiStorageKeyForValue:(NSString *)value {
    if (value.length == 0) return nil;
    NSString *lower = [value lowercaseString];
    if ([lower isEqualToString:@"default"] || [lower containsString:@"default"]) return @"default";
    if ([lower containsString:@"vulkan"]) return @"prefer_vulkan";
    if ([lower containsString:@"opengl"] || [lower containsString:@"gl"]) return @"prefer_opengl";
    return nil;
}

/// Resolve the target profile name (instance parameter takes precedence; defaults to the currently selected profile)
+ (NSString *)profileNameForParams:(NSDictionary *)params {
    NSString *instance = [params[@"instance"] isKindOfClass:[NSString class]] ? params[@"instance"] : @"";
    if (instance.length > 0) return instance;
    NSString *name = [PLProfiles current].selectedProfileName;
    return name.length > 0 ? name : @"(Default)";
}

/// Target profile dictionary (returns nil if it does not exist)
+ (NSMutableDictionary *)profileDictionaryForName:(NSString *)profileName {
    NSDictionary *profiles = [PLProfiles current].profiles;
    if (![profiles isKindOfClass:[NSDictionary class]]) return nil;
    id prof = profiles[profileName];
    return [prof isKindOfClass:[NSMutableDictionary class]] ? prof : nil;
}

+ (NSString *)stringFromValue:(id)value {
    if (!value || [value isKindOfClass:[NSNull class]]) return @"(Not set)";
    if ([value isKindOfClass:[NSString class]]) return value;
    return [value description];
}

#pragma mark - Execution dispatch

- (void)execute:(NSDictionary<NSString *, id> *)params
     completion:(void (^)(NSString * _Nullable result, NSError * _Nullable error))completion {
    if (!completion) return;

    if ([self.internalName isEqualToString:@"list_settings"]) {
        [self performListSettings:completion];
        return;
    }
    if ([self.internalName isEqualToString:@"get_setting"]) {
        [self performGetSetting:params completion:completion];
        return;
    }
    if ([self.internalName isEqualToString:@"set_setting"]) {
        [self performSetSetting:params completion:completion];
        return;
    }

    NSError *err = [NSError errorWithDomain:@"AiTool" code:404
                                   userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Unknown tool %@", self.internalName]}];
    completion(nil, err);
}

#pragma mark - list_settings

- (void)performListSettings:(void (^)(NSString *, NSError *))completion {
    NSDictionary *table = @{
        @"video.renderer": @{
            @"scope": @"Instance-level",
            @"values": @"auto / GL4ES / ANGLE(MetalANGLE) / MobileGlues / Zink / MoltenVK / LTW",
            @"note": @"Renderer. Switch to MoltenVK for OpenGL syntax errors in MC 26.2; Zink is recommended for Iris shaders.",
        },
        @"video.graphics_api": @{
            @"scope": @"Instance-level",
            @"values": @"default / prefer_vulkan / prefer_opengl",
            @"note": @"In-game graphics API selection for MC 26.2+ (including 1.21.8+)",
        },
        @"java.allocated_memory": @{
            @"scope": @"Global",
            @"values": @"Integer (MB), e.g. 2048",
            @"note": @"Memory allocated to the game; automatically determined by the launcher when java.auto_ram is enabled",
        },
        @"java.auto_ram": @{
            @"scope": @"Global",
            @"values": @"true / false",
            @"note": @"Automatically allocate memory",
        },
        @"java.java_args": @{
            @"scope": @"Global (overridable per instance)",
            @"values": @"JVM argument string, e.g. -XX:+UseG1GC",
            @"note": @"The javaArgs field in an instance profile can override the global value",
        },
        @"general.download_source": @{
            @"scope": @"Global",
            @"values": @"official / bmclapi",
            @"note": @"Minecraft game download source (assets use the automatic Modrinth fallback chain)",
        },
        @"general.game_directory": @{
            @"scope": @"Global",
            @"values": @"Instance directory name",
            @"note": @"Current game directory; use the create_instance tool to create instances; changing this key directly is not recommended",
        },
        @"control.default_ctrl": @{
            @"scope": @"Global",
            @"values": @"Control layout filename (without extension)",
            @"note": @"Default touch control layout",
        },
    };

    NSError *jsonError = nil;
    NSData *data = [NSJSONSerialization dataWithJSONObject:table options:NSJSONWritingPrettyPrinted error:&jsonError];
    if (!data || jsonError) {
        completion(@"Failed to serialize settings table", nil);
        return;
    }
    completion([[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding], nil);
}

#pragma mark - get_setting

- (void)performGetSetting:(NSDictionary *)params
              completion:(void (^)(NSString *, NSError *))completion {
    NSString *key = [params[@"key"] isKindOfClass:[NSString class]] ? params[@"key"] : @"";
    if (key.length == 0) {
        completion(nil, [NSError errorWithDomain:@"AiTool" code:400
                                     userInfo:@{NSLocalizedDescriptionKey: @"The key parameter is required"}]);
        return;
    }

    NSString *profileName = [AiSettingsTools profileNameForParams:params];
    NSString *profileField = [AiSettingsTools profileKeyMap][key];

    // Effective instance value: resolveKey semantics (instance value takes precedence, falls back to global)
    id effective = nil;
    if (profileField) {
        NSMutableDictionary *prof = [AiSettingsTools profileDictionaryForName:profileName];
        effective = [PLProfiles profile:prof resolveKey:profileField];
    }
    // Global value
    id global = getPrefObject(key);

    NSString *globalDesc = [AiSettingsTools stringFromValue:global];
    if ([key isEqualToString:@"video.renderer"]) {
        globalDesc = [AiSettingsTools rendererFriendlyName:[AiSettingsTools stringFromValue:global]];
    }

    NSString *effectiveDesc = profileField ? [AiSettingsTools stringFromValue:effective] : globalDesc;
    if (profileField && [key isEqualToString:@"video.renderer"]) {
        effectiveDesc = [AiSettingsTools rendererFriendlyName:[AiSettingsTools stringFromValue:effective]];
    }

    completion([NSString stringWithFormat:
                @"key: %@\nGlobal value: %@\nEffective instance value (%@): %@\nCurrent game directory: %@",
                key, globalDesc, profileName, effectiveDesc,
                [AiSettingsTools stringFromValue:getPrefObject(@"general.game_directory")]], nil);
}

#pragma mark - set_setting

- (void)performSetSetting:(NSDictionary *)params
              completion:(void (^)(NSString *, NSError *))completion {
    NSString *key = [params[@"key"] isKindOfClass:[NSString class]] ? params[@"key"] : @"";
    id value = params[@"value"];
    if (key.length == 0 || value == nil || [value isKindOfClass:[NSNull class]]) {
        completion(nil, [NSError errorWithDomain:@"AiTool" code:400
                                     userInfo:@{NSLocalizedDescriptionKey: @"The key and value parameters are required"}]);
        return;
    }

    // ---- Instance-level key: write to profile ----
    NSString *profileField = [AiSettingsTools profileKeyMap][key];
    if (profileField) {
        NSString *storageValue = nil;
        if ([key isEqualToString:@"video.renderer"]) {
            storageValue = [AiSettingsTools rendererStorageKeyForValue:[AiSettingsTools stringFromValue:value]];
            if (!storageValue) {
                completion(nil, [NSError errorWithDomain:@"AiTool" code:400
                                             userInfo:@{NSLocalizedDescriptionKey:
                                                 @"Invalid renderer value; options: auto/GL4ES/ANGLE/MobileGlues/Zink/MoltenVK/LTW"}]);
                return;
            }
        } else if ([key isEqualToString:@"video.graphics_api"]) {
            storageValue = [AiSettingsTools graphicsApiStorageKeyForValue:[AiSettingsTools stringFromValue:value]];
            if (!storageValue) {
                completion(nil, [NSError errorWithDomain:@"AiTool" code:400
                                             userInfo:@{NSLocalizedDescriptionKey:
                                                 @"Invalid graphics API value; options: default/prefer_vulkan/prefer_opengl"}]);
                return;
            }
        } else {
            storageValue = [AiSettingsTools stringFromValue:value];
        }

        NSString *profileName = [AiSettingsTools profileNameForParams:params];
        NSMutableDictionary *prof = [AiSettingsTools profileDictionaryForName:profileName];
        if (!prof) {
            completion(nil, [NSError errorWithDomain:@"AiTool" code:404
                                         userInfo:@{NSLocalizedDescriptionKey:
                                             [NSString stringWithFormat:@"Instance %@ does not exist", profileName]}]);
            return;
        }

        // Copy deeply, then write back and save (avoid race conditions from directly modifying a shared dictionary)
        NSMutableDictionary *mutable = [prof mutableCopy];
        mutable[profileField] = storageValue;
        [PLProfiles.current.profiles setObject:mutable forKey:profileName];
        [PLProfiles.current save];
        [[NSNotificationCenter defaultCenter] postNotificationName:@"ReloadProfileList" object:nil];

        NSString *display = storageValue;
        if ([key isEqualToString:@"video.renderer"]) {
            display = [AiSettingsTools rendererFriendlyName:storageValue];
        }
        completion([NSString stringWithFormat:@"Set %@ for instance \"%@\" to %@.",
                    key, profileName, display], nil);
        return;
    }

    // ---- Global key: write to LauncherPreferences ----
    if ([key isEqualToString:@"java.allocated_memory"]) {
        setPrefObject(@"java.allocated_memory", @([value integerValue]));
    } else if ([key isEqualToString:@"java.auto_ram"]) {
        NSString *desc = [value isKindOfClass:[NSString class]] ? (NSString *)value : [value description];
        BOOL on = [desc.lowercaseString hasPrefix:@"t"] || [desc isEqualToString:@"1"] || [desc isEqualToString:@"yes"];
        setPrefObject(@"java.auto_ram", @(on));
    } else if ([key isEqualToString:@"general.game_directory"]) {
        completion(nil, [NSError errorWithDomain:@"AiTool" code:400
                                     userInfo:@{NSLocalizedDescriptionKey:
                                         @"Changing the game directory key directly is not recommended (it requires rebuilding symlinks); use the create_instance tool to create an instance"}]);
        return;
    } else if ([key isEqualToString:@"general.download_source"] ||
               [key isEqualToString:@"java.java_args"] ||
               [key isEqualToString:@"control.default_ctrl"]) {
        setPrefObject(key, [AiSettingsTools stringFromValue:value]);
    } else {
        completion(nil, [NSError errorWithDomain:@"AiTool" code:400
                                     userInfo:@{NSLocalizedDescriptionKey:
                                         [NSString stringWithFormat:@"Unsupported setting key: %@ (use list_settings to view available keys)", key]}]);
        return;
    }

    [[NSNotificationCenter defaultCenter] postNotificationName:@"ReloadProfileList" object:nil];
    completion([NSString stringWithFormat:@"Set global %@ to %@.", key, [AiSettingsTools stringFromValue:value]], nil);
}

@end
