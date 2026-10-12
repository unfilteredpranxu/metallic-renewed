//
//  AiFileTools.h
//  Amethyst
//
//  Air AI Agent file tools: list_files / read_file / grep_files (read-only),
//  write_file / edit_file (controlled writes), delete_file (dangerous write).
//  All file operations are restricted to the app sandbox by the sandbox path safety check (resolveSafely).
//

#import <Foundation/Foundation.h>
#import "AiTool.h"

NS_ASSUME_NONNULL_BEGIN

@interface AiFileTools : NSObject <AiTool>

@property (nonatomic, readonly) NSString *name;
@property (nonatomic, readonly) NSString *summary;
@property (nonatomic, readonly) AiToolPermission permission;

/// Set the tool name for this instance
- (instancetype)initWithName:(NSString *)name;

/// Safely resolve a sandbox path. Absolute paths (starting with /) are joined from the app sandbox root (Documents),
/// and the $GAMEDIR placeholder is replaced with the current instance's gameDir; relative paths are resolved from the current instance root.
/// After normalization, verify the path remains inside the sandbox; return nil if it escapes.
+ (nullable NSString *)resolveSafely:(NSString *)path;

@end

NS_ASSUME_NONNULL_END