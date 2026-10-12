//
//  AiToolRegistry.m
//  Amethyst
//

#import "AiToolRegistry.h"
#import "AiToolBootstrapper.h"

@interface AiToolRegistry ()
@property (nonatomic, strong) NSMutableDictionary<NSString *, id<AiTool>> *tools;
@end

@implementation AiToolRegistry

+ (instancetype)sharedRegistry {
    static AiToolRegistry *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[AiToolRegistry alloc] init];
    });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _tools = [NSMutableDictionary dictionary];
        // Important fix (AI did not know which tools it could use): [AiToolBootstrapper registerBuiltinTools]
        // was never called, so the tool list remained empty and openAIToolSchemas returned an empty array.
        // The model received no tool definitions and behaved as if it had no available tools. Register automatically during singleton initialization.
        [AiToolBootstrapper registerBuiltinToolsIntoRegistry:self];
    }
    return self;
}

- (void)registerTool:(id<AiTool>)tool {
    if (!tool || tool.name.length == 0) return;
    self.tools[tool.name] = tool;
}

- (id<AiTool> _Nullable)toolForName:(NSString *)name {
    if (name.length == 0) return nil;
    return self.tools[name];
}

/// OpenAI-style schema: use summary directly as the description; describe parameters as a permissive object,
/// allowing the model to provide arguments freely (prefer permissive validation; parameter details are in summary).
- (NSArray<NSDictionary *> *)openAIToolSchemas {
    NSMutableArray<NSDictionary *> *schemas = [NSMutableArray array];
    NSArray<NSString *> *sortedNames = [self.tools.allKeys sortedArrayUsingSelector:@selector(compare:)];
    for (NSString *name in sortedNames) {
        id<AiTool> tool = self.tools[name];
        [schemas addObject:@{
            @"type": @"function",
            @"function": @{
                @"name": tool.name,
                @"description": tool.summary ?: @"",
                @"parameters": @{
                    @"type": @"object",
                    @"properties": @{},
                    @"required": @[],
                },
            },
        }];
    }
    return schemas;
}

#pragma mark - Parameter normalization

/// Normalize a key to lowercase camelCase (e.g. "game-version"→"gameVersion", "InstanceName"→"instanceName").
- (NSString *)normalizedKeyCamel:(NSString *)key {
    if (key.length == 0) return key;

    NSUInteger length = key.length;
    // Record the start index of each "word" (words are separated by delimiters or camel-case boundaries)
    NSMutableIndexSet *wordStarts = [NSMutableIndexSet indexSet];
    [wordStarts addIndex:0];
    for (NSUInteger i = 1; i < length; i++) {
        unichar c = [key characterAtIndex:i];
        if (c == '_' || c == '-' || c == '.' || c == ' ' || c == '/') {
            continue; // A delimiter does not start a word
        }
        unichar prev = [key characterAtIndex:i - 1];
        BOOL prevIsSep = (prev == '_' || prev == '-' || prev == '.' || prev == ' ' || prev == '/');
        BOOL prevIsLower = (prev >= 'a' && prev <= 'z') || (prev >= '0' && prev <= '9');
        BOOL isUpper = (c >= 'A' && c <= 'Z');
        if (prevIsSep) {
            [wordStarts addIndex:i];
        } else if (isUpper && prevIsLower) {
            // Camel-case boundary: lowercase/digit followed by uppercase (covers both PascalCase and camelCase)
            [wordStarts addIndex:i];
        }
    }

    NSMutableString *result = [NSMutableString string];
    NSMutableString *currentWord = [NSMutableString string];
    __block BOOL isFirstWord = YES;

    void (^flush)(void) = ^{
        if (currentWord.length == 0) return;
        if (isFirstWord) {
            // Keep the first word entirely lowercase
            [result appendString:currentWord];
            isFirstWord = NO;
        } else {
            // Capitalize the first letter of subsequent words and lowercase the rest
            NSString *word = currentWord;
            NSString *capitalized = [word stringByReplacingCharactersInRange:NSMakeRange(0, 1)
                                                                  withString:[[word substringToIndex:1] uppercaseString]];
            [result appendString:capitalized];
        }
        [currentWord setString:@""];
    };

    for (NSUInteger i = 0; i < length; i++) {
        unichar c = [key characterAtIndex:i];
        if (c == '_' || c == '-' || c == '.' || c == ' ' || c == '/') {
            flush();
            continue;
        }
        if (i > 0 && [wordStarts containsIndex:i]) {
            flush();
        }
        // Convert to lowercase
        unichar lower = (c >= 'A' && c <= 'Z') ? (unichar)(c - 'A' + 'a') : c;
        [currentWord appendString:[NSString stringWithFormat:@"%C", lower]];
    }
    flush();
    return result;
}

/// Determine whether value is "empty" (discard keys with nil, NSNull, or an empty string)
- (BOOL)isEmptyValue:(id)value {
    if (value == nil || [value isKindOfClass:[NSNull class]]) return YES;
    if ([value isKindOfClass:[NSString class]]) {
        return [(NSString *)value length] == 0;
    }
    return NO;
}

- (NSDictionary * _Nonnull)normalizedParams:(NSDictionary * _Nonnull)params {
    if (![params isKindOfClass:[NSDictionary class]]) return @{};
    NSMutableDictionary *normalized = [NSMutableDictionary dictionary];
    [params enumerateKeysAndObjectsUsingBlock:^(id rawKey, id value, BOOL *stop) {
        NSString *key = [rawKey isKindOfClass:[NSString class]] ? (NSString *)rawKey : [rawKey description];
        NSString *camelKey = [self normalizedKeyCamel:key];
        if (camelKey.length == 0) return;
        if ([self isEmptyValue:value]) return; // Discard keys with empty values
        normalized[camelKey] = value;
    }];
    return normalized;
}

#pragma mark - Execute

- (void)executeToolNamed:(NSString *)name
                  params:(NSDictionary *)params
              completion:(void (^)(NSString * _Nullable result, NSError * _Nullable error))completion {
    id<AiTool> tool = [self toolForName:name];
    if (!tool) {
        if (completion) {
            dispatch_async(dispatch_get_main_queue(), ^{
                NSError *err = [NSError errorWithDomain:@"AiTool" code:404
                                               userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Unknown tool %@", name ?: @""]}];
                completion(nil, err);
            });
        }
        return;
    }

    // Normalize parameters before passing them to tool execute
    NSDictionary *normalized = [self normalizedParams:params];
    [tool execute:normalized completion:^(NSString * _Nullable result, NSError * _Nullable error) {
        // Always deliver the result callback on the main thread
        dispatch_async(dispatch_get_main_queue(), ^{
            if (completion) {
                completion(result, error);
            }
        });
    }];
}

@end