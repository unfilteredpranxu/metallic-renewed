//
//  AiTodoTool.h
//  Amethyst
//
//  To-do list tools (enhance-ai-agent Task 11):
//  - todo_create (CONTROLLED_WRITE): create an item
//  - todo_list (READ_ONLY): list items (including completion status)
//  - todo_update (CONTROLLED_WRITE): change the title/description/check done
//  - todo_delete (CONTROLLED_WRITE): delete an item
//
//  Persistence: Documents/AI/todos.json (JSON array; items contain id/title/description/done/createdAt).
//  Reads/writes are protected by a serial queue for thread safety; id is a monotonically increasing integer.
//

#import <Foundation/Foundation.h>
#import "AiTool.h"

NS_ASSUME_NONNULL_BEGIN

@interface AiTodoTool : NSObject <AiTool>

/// Supported internalName values: todo_create / todo_list / todo_update / todo_delete
- (instancetype)initWithName:(NSString *)name;

@end

NS_ASSUME_NONNULL_END
