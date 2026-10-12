//
//  AiTodoTool.m
//  Amethyst
//

#import "AiTodoTool.h"

static NSString *const kAiTodoFileName = @"todos.json";
static const NSInteger kAiTodoMaxItems = 200;

@interface AiTodoTool ()
@property (nonatomic, copy) NSString *internalName;
/// Serial queue: thread-safety protection for todos.json reads/writes and ID allocation
@property (nonatomic, strong) dispatch_queue_t queue;
@end

@implementation AiTodoTool

- (instancetype)initWithName:(NSString *)name {
    self = [super init];
    if (self) {
        _internalName = [name copy] ?: @"";
        _queue = dispatch_queue_create("ai.todo.tool", DISPATCH_QUEUE_SERIAL);
    }
    return self;
}

- (NSString *)name {
    return self.internalName;
}

- (AiToolPermission)permission {
    if ([self.internalName isEqualToString:@"todo_list"]) {
        return AiToolPermissionReadOnly;
    }
    return AiToolPermissionControlledWrite;
}

- (NSString *)summary {
    if ([self.internalName isEqualToString:@"todo_create"]) {
        return @"Create a to-do item (an execution checklist for multi-step tasks)."
               "\nParameters: title (string, required), description (string, optional)."
               "\nReturns the new item's id.";
    }
    if ([self.internalName isEqualToString:@"todo_list"]) {
        return @"List all to-do items (including completed items)."
               "\nNo parameters."
               "\nReturns a JSON array: {id, title, description, done, createdAt}.";
    }
    if ([self.internalName isEqualToString:@"todo_update"]) {
        return @"Update a to-do item: mark/unmark as complete, or change its title and description."
               "\nParameters: id (number, required), done (boolean, optional, true=complete false=incomplete), title (string, optional), description (string, optional)."
               "\nReturns the updated item.";
    }
    // todo_delete
    return @"Delete a to-do item."
           "\nParameter: id (number, required)."
           "\nReturns \"Deleted.\"";
}

#pragma mark - Storage

+ (NSString *)todosFilePath {
    NSString *docs = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
    return [[docs stringByAppendingPathComponent:@"AI"] stringByAppendingPathComponent:kAiTodoFileName];
}

+ (NSMutableArray *)loadTodos {
    NSString *path = [AiTodoTool todosFilePath];
    NSData *data = [NSData dataWithContentsOfFile:path];
    if (!data) return [NSMutableArray array];
    id json = [NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingMutableContainers error:nil];
    return [json isKindOfClass:[NSMutableArray class]] ? json : [NSMutableArray array];
}

+ (BOOL)saveTodos:(NSArray *)todos {
    NSString *path = [AiTodoTool todosFilePath];
    [[NSFileManager defaultManager] createDirectoryAtPath:[path stringByDeletingLastPathComponent]
                              withIntermediateDirectories:YES attributes:nil error:nil];
    NSError *err = nil;
    NSData *data = [NSJSONSerialization dataWithJSONObject:todos options:NSJSONWritingPrettyPrinted error:&err];
    if (!data || err) return NO;
    return [data writeToFile:path options:NSDataWritingAtomic error:nil];
}

/// Generate a new id: current maximum id + 1 (starting from 1)
+ (NSInteger)nextIdInTodos:(NSArray *)todos {
    NSInteger maxId = 0;
    for (NSDictionary *item in todos) {
        NSInteger cur = [item[@"id"] integerValue];
        if (cur > maxId) maxId = cur;
    }
    return maxId + 1;
}

+ (NSString *)itemDescription:(NSDictionary *)item {
    if (![item isKindOfClass:[NSDictionary class]]) return @"(Invalid item)";
    NSString *done = [item[@"done"] boolValue] ? @"[Completed]" : @"[Incomplete]";
    NSString *desc = [item[@"description"] isKindOfClass:[NSString class]] ? item[@"description"] : @"";
    if (desc.length > 0) {
        return [NSString stringWithFormat:@"#%@ %@ %@ — %@", [item[@"id"] description], done, item[@"title"] ?: @"", desc];
    }
    return [NSString stringWithFormat:@"#%@ %@ %@", [item[@"id"] description], done, item[@"title"] ?: @""];
}

#pragma mark - Execution dispatch

- (void)execute:(NSDictionary<NSString *, id> *)params
     completion:(void (^)(NSString * _Nullable result, NSError * _Nullable error))completion {
    if (!completion) return;

    dispatch_async(self.queue, ^{
        NSString *result = nil;
        NSError *error = nil;

        if ([self.internalName isEqualToString:@"todo_create"]) {
            result = [self performCreate:params error:&error];
        } else if ([self.internalName isEqualToString:@"todo_list"]) {
            result = [self performList];
        } else if ([self.internalName isEqualToString:@"todo_update"]) {
            result = [self performUpdate:params error:&error];
        } else if ([self.internalName isEqualToString:@"todo_delete"]) {
            result = [self performDelete:params error:&error];
        } else {
            error = [NSError errorWithDomain:@"AiTool" code:404
                                    userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Unknown tool %@", self.internalName]}];
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            completion(result, error);
        });
    });
}

- (NSString *)performCreate:(NSDictionary *)params error:(NSError **)error {
    NSString *title = [params[@"title"] isKindOfClass:[NSString class]] ? params[@"title"] : @"";
    if (title.length == 0) {
        if (error) *error = [NSError errorWithDomain:@"AiTool" code:400
                                            userInfo:@{NSLocalizedDescriptionKey: @"The title parameter is required"}];
        return nil;
    }
    NSString *desc = [params[@"description"] isKindOfClass:[NSString class]] ? params[@"description"] : @"";

    NSMutableArray *todos = [AiTodoTool loadTodos];
    if (todos.count >= kAiTodoMaxItems) {
        if (error) *error = [NSError errorWithDomain:@"AiTool" code:409
                                            userInfo:@{NSLocalizedDescriptionKey: @"The to-do list is full (200 items); please clear some items first"}];
        return nil;
    }
    NSInteger newId = [AiTodoTool nextIdInTodos:todos];
    NSDictionary *item = @{
        @"id": @(newId),
        @"title": title,
        @"description": desc ?: @"",
        @"done": @NO,
        @"createdAt": [[NSDate date] description],
    };
    [todos addObject:item];
    if (![AiTodoTool saveTodos:todos]) {
        if (error) *error = [NSError errorWithDomain:@"AiTool" code:500
                                            userInfo:@{NSLocalizedDescriptionKey: @"Failed to write todos.json"}];
        return nil;
    }
    return [NSString stringWithFormat:@"Created to-do #%ld: %@", (long)newId, title];
}

- (NSString *)performList {
    NSMutableArray *todos = [AiTodoTool loadTodos];
    if (todos.count == 0) return @"The to-do list is empty.";

    NSMutableString *out = [NSMutableString string];
    NSInteger doneCount = 0;
    for (NSDictionary *item in todos) {
        if ([item[@"done"] boolValue]) doneCount++;
        [out appendFormat:@"%@\n", [AiTodoTool itemDescription:item]];
    }
    [out appendFormat:@"%lu items total, %ld completed.",
        (unsigned long)todos.count, (long)doneCount];
    return out;
}

- (NSString *)performUpdate:(NSDictionary *)params error:(NSError **)error {
    NSDictionary *target = nil;
    NSMutableArray *todos = [AiTodoTool loadTodos];
    NSInteger itemId = [params[@"id"] integerValue];
    for (NSUInteger i = 0; i < todos.count; i++) {
        NSDictionary *item = todos[i];
        if ([item isKindOfClass:[NSDictionary class]] && [item[@"id"] integerValue] == itemId) {
            target = item;
            break;
        }
    }
    if (!target) {
        if (error) *error = [NSError errorWithDomain:@"AiTool" code:404
                                            userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"To-do #%ld does not exist", (long)itemId]}];
        return nil;
    }

    NSMutableDictionary *updated = [target mutableCopy];
    id doneVal = params[@"done"];
    if (doneVal != nil && ![doneVal isKindOfClass:[NSNull class]]) {
        BOOL doneFlag;
        if ([doneVal isKindOfClass:[NSString class]]) {
            NSString *s = [(NSString *)doneVal lowercaseString];
            doneFlag = [s hasPrefix:@"t"] || [s isEqualToString:@"1"] || [s isEqualToString:@"yes"];
        } else {
            doneFlag = [doneVal boolValue];
        }
        updated[@"done"] = @(doneFlag);
    }
    NSString *title = [params[@"title"] isKindOfClass:[NSString class]] ? params[@"title"] : nil;
    if (title.length > 0) updated[@"title"] = title;
    NSString *desc = [params[@"description"] isKindOfClass:[NSString class]] ? params[@"description"] : nil;
    if (desc.length > 0) updated[@"description"] = desc;

    NSUInteger idx = [todos indexOfObject:target];
    if (idx != NSNotFound) todos[idx] = updated;
    if (![AiTodoTool saveTodos:todos]) {
        if (error) *error = [NSError errorWithDomain:@"AiTool" code:500
                                            userInfo:@{NSLocalizedDescriptionKey: @"Failed to write todos.json"}];
        return nil;
    }
    return [NSString stringWithFormat:@"Updated: %@", [AiTodoTool itemDescription:updated]];
}

- (NSString *)performDelete:(NSDictionary *)params error:(NSError **)error {
    NSMutableArray *todos = [AiTodoTool loadTodos];
    NSInteger itemId = [params[@"id"] integerValue];
    NSDictionary *target = nil;
    for (NSDictionary *item in todos) {
        if ([item isKindOfClass:[NSDictionary class]] && [item[@"id"] integerValue] == itemId) {
            target = item;
            break;
        }
    }
    if (!target) {
        if (error) *error = [NSError errorWithDomain:@"AiTool" code:404
                                            userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"To-do #%ld does not exist", (long)itemId]}];
        return nil;
    }
    [todos removeObject:target];
    if (![AiTodoTool saveTodos:todos]) {
        if (error) *error = [NSError errorWithDomain:@"AiTool" code:500
                                            userInfo:@{NSLocalizedDescriptionKey: @"Failed to write todos.json"}];
        return nil;
    }
    return [NSString stringWithFormat:@"Deleted to-do #%ld", (long)itemId];
}

@end
