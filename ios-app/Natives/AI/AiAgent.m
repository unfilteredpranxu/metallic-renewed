//
//  AiAgent.m
//  Amethyst
//

#import "AiAgent.h"
#import "AiMessage.h"
#import "AiSessionStore.h"
#import "AiSettings.h"
#import "AiAPIClient.h"
#import "AiToolRegistry.h"
#import "AiSafetyManager.h"

/// Maximum number of tool-loop rounds
static const NSInteger kMaxToolRounds = 10;
/// Maximum attempts for the same tool call (including failures)
static const NSInteger kMaxToolAttempts = 3;

/// Message-change notification after tool-call results are written to a session (object=AiSession)
static NSString * const kAiSessionMessagesDidChangeNotification = @"AiSessionMessagesDidChangeNotification";

@interface AiAgent ()
@property (nonatomic, strong) AiAPIClient *client;

// Tool-loop runtime state (valid for one sendUserMessage lifecycle)
@property (nonatomic, assign) BOOL running;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSNumber *> *attempts; // toolCallID -> attempt count
@property (nonatomic, assign) NSInteger toolRound;                                   // Current tool round
@end

@implementation AiAgent

+ (instancetype)sharedAgent {
    static AiAgent *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[AiAgent alloc] init];
    });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _client = [[AiAPIClient alloc] init];
        _attempts = [NSMutableDictionary dictionary];
    }
    return self;
}

/// Session persistence (called after each tool round trip so history remains complete after interruption/process termination)
- (void)saveSession:(AiSession *)session {
    if (!session) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        [[AiSessionStore sharedStore] updateSession:session];
    });
}

/// Broadcast session message changes (for immediate UI refresh; broadcast only, does not disrupt message protocol order)
- (void)notifyMessagesChanged:(AiSession *)session {
    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:kAiSessionMessagesDidChangeNotification
                                                            object:session];
    });
}

/// Accumulate streaming tool_calls fragments: merge name and args by index (arguments are concatenated incrementally)
- (void)accumulateToolCalls:(NSArray *)rawToolCalls
                       into:(NSMutableDictionary *)accumulator {
    for (id item in rawToolCalls) {
        if (![item isKindOfClass:[NSDictionary class]]) continue;
        NSDictionary *tc = item;
        NSNumber *idxNum = tc[@"index"];
        NSInteger idx = (idxNum && [idxNum isKindOfClass:[NSNumber class]]) ? idxNum.integerValue : (NSInteger)accumulator.count;
        NSMutableDictionary *entry = accumulator[@(idx)];
        if (!entry) {
            entry = [NSMutableDictionary dictionary];
            entry[@"index"] = @(idx);
            accumulator[@(idx)] = entry;
        }
        // id usually appears only in the first fragment
        if ([tc[@"id"] isKindOfClass:[NSString class]] && [tc[@"id"] length] > 0) {
            entry[@"id"] = tc[@"id"];
        }
        NSDictionary *func = tc[@"function"];
        if ([func isKindOfClass:[NSDictionary class]]) {
            if ([func[@"name"] isKindOfClass:[NSString class]] && [func[@"name"] length] > 0) {
                entry[@"name"] = func[@"name"];
            }
            if ([func[@"arguments"] isKindOfClass:[NSString class]]) {
                NSString *prev = entry[@"arguments"] ?: @"";
                entry[@"arguments"] = [prev stringByAppendingString:func[@"arguments"]];
            }
        }
        // Support models that partially implement the OpenAI protocol and place name at the tc top level (rather than function.name)
        if (![entry[@"name"] isKindOfClass:[NSString class]] || [entry[@"name"] length] == 0) {
            if ([tc[@"name"] isKindOfClass:[NSString class]] && [tc[@"name"] length] > 0) {
                entry[@"name"] = tc[@"name"];
            }
        }
    }
}

/// Parse the tool arguments JSON string as a dictionary (return an empty dictionary on failure)
- (NSDictionary *)parseArgumentsJSON:(NSString *)jsonString {
    if (jsonString.length == 0) return @{};
    NSData *data = [jsonString dataUsingEncoding:NSUTF8StringEncoding];
    if (!data) return @{};
    id obj = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    if ([obj isKindOfClass:[NSDictionary class]]) {
        return obj;
    }
    return @{};
}

/// Send a user message and drive the tool loop
- (void)sendUserMessage:(NSString *)text
                session:(AiSession *)session
               provider:(AiProvider *)provider
               streaming:(BOOL)streaming
           chunkHandler:(void (^)(NSString *partial))chunkHandler
     completionHandler:(void (^)(NSError *error))completionHandler {
    if (!session) {
        if (completionHandler) {
            dispatch_async(dispatch_get_main_queue(), ^{
                completionHandler([NSError errorWithDomain:@"AiAgent" code:1 userInfo:@{NSLocalizedDescriptionKey: @"Session is empty"}]);
            });
        }
        return;
    }

    // Concurrency protection: reject new messages while the previous flow is still active (e.g. tool executing or awaiting confirmation)
    if (self.running) {
        if (completionHandler) {
            dispatch_async(dispatch_get_main_queue(), ^{
                completionHandler([NSError errorWithDomain:@"AiAgent" code:3 userInfo:@{NSLocalizedDescriptionKey: @"The previous response is not complete. Please wait or stop it first."}]);
            });
        }
        return;
    }

    // Initialize loop state
    self.running = YES;
    self.toolRound = 0;
    [self.attempts removeAllObjects];

    // Append user message
    AiMessage *userMessage = [AiMessage messageWithRole:@"user" content:text ?: @""];
    [session.messages addObject:userMessage];

    [self startRoundInSession:session
                     provider:provider
                 chunkHandler:chunkHandler
           completionHandler:completionHandler];
}

#pragma mark - Tool loop: single-round request

- (void)startRoundInSession:(AiSession *)session
                   provider:(AiProvider *)provider
               chunkHandler:(void (^)(NSString *partial))chunkHandler
         completionHandler:(void (^)(NSError *error))completionHandler {
    if (!self.running) return;

    // Round limit
    if (self.toolRound >= kMaxToolRounds) {
        AiMessage *capMsg = [AiMessage messageWithRole:@"assistant" content:@"The tool-call limit for this round has been reached. Please ask the user for more details."];
        [session.messages addObject:capMsg];
        [self saveSession:session];
        self.running = NO;
        if (completionHandler) completionHandler(nil);
        return;
    }

    // 1. Assemble payload: system + history (exclude streaming placeholders; include tool messages)
    NSMutableArray *payloadMessages = [NSMutableArray array];
    NSString *systemPrompt = [[AiSettings sharedSettings] systemPrompt];

    // Dynamically inject today's date (needed for automatic gameDir naming: "MC version Loader YYYY.MM.DD")
    NSDateFormatter *dateFmt = [[NSDateFormatter alloc] init];
    dateFmt.locale = [[NSLocale alloc] initWithLocaleIdentifier:@"zh_CN"];
    [dateFmt setDateFormat:@"yyyy-MM-dd"];
    NSString *todayLine = [NSString stringWithFormat:@"Today is %@. If creating a new game directory, use the naming format \"Minecraft version Loader YYYY.MM.DD\".", [dateFmt stringFromDate:[NSDate date]]];
    systemPrompt = [systemPrompt stringByAppendingString:[NSString stringWithFormat:@"\n\n[Today's date] %@", todayLine]];

    // 2. Tool definitions
    NSArray *tools = [[AiToolRegistry sharedRegistry] openAIToolSchemas];

    // Important fix (AI did not know it could use tools): even when tools are passed as functions with the request,
    // the model often gives text suggestions instead of calling tools unless the system prompt explicitly says so.
    // Therefore, when tools are available, append a clear capability statement to the system prompt (do not replace user customization; append only).
    if (tools.count > 0) {
        systemPrompt = [systemPrompt stringByAppendingString:@"\n\nYou can use built-in tools to directly control the launcher, for example: troubleshoot and analyze crash logs; read installed game versions and component status; directly install Minecraft versions or Fabric/Quilt loaders (the vanilla game is installed first automatically if missing, and Fabric API is installed automatically for Fabric); download/install mods, shaders, resource packs, and data packs (automatically matching the instance's MC version); view and change launcher settings (global and instance settings); create game directories (create_instance); manage to-do lists (todo_*); check download progress (check_downloads); and read multiple logs (read_logs, including launcher logs)."
            "Version convention: loaderVersion for install_loader and versionId for install_* may be \"latest\" to indicate the latest stable version; there is no need to fetch a version list first."
            "Installation order: install the vanilla game before the loader — before calling install_loader, use list_instances to confirm the vanilla game is installed in the target instance. If not, call install_game_version first; install the loader only after it succeeds, then install mods. Likewise, install the vanilla game first when uninstalling or switching directories."
            "These installations are fully automatic. Users can monitor progress in the download center; you should not direct them to download or perform manual actions there (except Forge/NeoForge/OptiFine, which require a graphical installer)."
            "You can execute multiple tool calls in parallel; download tools can run in the background (wait=false) while you do other work, then use check_downloads to check progress."
            "When the user's request can be completed using these tools, proactively call the appropriate tool rather than merely giving text suggestions; use the tool results to continue the task."];
    }
    if (systemPrompt.length > 0) {
        [payloadMessages addObject:[AiMessage messageWithRole:@"system" content:systemPrompt]];
    }
    for (AiMessage *m in session.messages) {
        if (m.streaming) continue;
        [payloadMessages addObject:m];
    }

    // 3. Create assistant placeholder message (streaming flag)
    AiMessage *assistantMessage = [AiMessage messageWithRole:@"assistant" content:@""];
    assistantMessage.streaming = YES;
    [session.messages addObject:assistantMessage];

    __weak typeof(self) weakSelf = self;
    __block NSMutableDictionary *accToolCalls = [NSMutableDictionary dictionary];

    [self.client streamChatWithProvider:provider
                               messages:payloadMessages
                                  tools:tools
                                onChunk:^(NSString * _Nullable delta, NSDictionary * _Nullable toolCalls) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf || !strongSelf.running) return;
        if (delta.length > 0) {
            assistantMessage.content = [assistantMessage.content stringByAppendingString:delta];
            if (chunkHandler) chunkHandler(delta);
        }
        NSArray *raw = toolCalls[@"tool_calls"];
        if ([raw isKindOfClass:[NSArray class]] && raw.count > 0) {
            [strongSelf accumulateToolCalls:raw into:accToolCalls];
        }
    } onComplete:^(NSDictionary * _Nullable fullResponse, NSError * _Nullable error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;

        assistantMessage.streaming = NO;

        // Stopped request: finish immediately without invoking completionHandler (the Stop button already reset the UI)
        if (!strongSelf.running) {
            [strongSelf saveSession:session];
            return;
        }

        if (error) {
            // Error: do not append an error message to history; notify the UI via completionHandler so it can show the error
            if (assistantMessage.content.length == 0) {
                [session.messages removeObject:assistantMessage];
            }
            [strongSelf saveSession:session];
            strongSelf.running = NO;
            if (completionHandler) completionHandler(error);
            return;
        }

        if (accToolCalls.count > 0) {
            // Enter tool execution stage
            [strongSelf saveSession:session];
            [strongSelf runToolCalls:accToolCalls
                    assistantMessage:assistantMessage
                             session:session
                            provider:provider
                        chunkHandler:chunkHandler
                  completionHandler:completionHandler];
        } else {
            // No tool calls; finish normally
            [strongSelf saveSession:session];
            strongSelf.running = NO;
            if (completionHandler) completionHandler(nil);
        }
    }];
}

#pragma mark - Tool execution stage

/// Execute all tool calls in this round in parallel (enhance-ai-agent Task 15):
/// - Dispatch calls that do not need safety confirmation concurrently (each tool uses an asynchronous callback).
/// - Confirm calls requiring user approval serially in index order (show only one confirmation dialog at a time).
/// - Append tool result messages to session history in tool index order (after assistant tool_calls),
///   persisting each as soon as possible when completed (appendCursor advances continuously from the first unfilled slot).
/// - Once all are complete, proceed to the next round or finish with terminalError.
/// Thread safety: tool completion and safety confirmation callbacks are both on the main thread; no race conditions.
- (void)runToolCalls:(NSDictionary *)accToolCalls
    assistantMessage:(AiMessage *)assistantMessage
             session:(AiSession *)session
            provider:(AiProvider *)provider
        chunkHandler:(void (^)(NSString *partial))chunkHandler
  completionHandler:(void (^)(NSError *error))completionHandler {
    NSArray *allValues = accToolCalls.allValues;
    NSArray *orderedCalls = [allValues sortedArrayUsingComparator:^NSComparisonResult(id a, id b) {
        NSInteger ia = [a[@"index"] integerValue];
        NSInteger ib = [b[@"index"] integerValue];
        return (ia > ib) ? NSOrderedDescending : ((ia < ib) ? NSOrderedAscending : NSOrderedSame);
    }];

    // Attach the first call to the assistant message (isToolCall) and append remaining calls as toolCallMessage,
    // so serialization merges these consecutive isToolCall assistant messages into one assistant tool_calls array (see AiAPIClient).
    for (NSUInteger i = 0; i < orderedCalls.count; i++) {
        NSDictionary *call = orderedCalls[i];
        NSString *callID = call[@"id"];
        if (callID.length == 0) callID = [NSString stringWithFormat:@"call_%ld", (long)[call[@"index"] integerValue]];
        NSString *name = call[@"name"];
        NSString *args = call[@"arguments"] ?: @"";
        if (i == 0) {
            assistantMessage.isToolCall = YES;
            assistantMessage.toolCallID = callID;
            assistantMessage.toolName = name ?: @"";
            assistantMessage.toolArguments = args;
        } else {
            AiMessage *tc = [AiMessage toolCallMessageWithName:name ?: @"" arguments:args];
            tc.toolCallID = callID;
            [session.messages addObject:tc];
        }
    }
    [self saveSession:session];
    [self notifyMessagesChanged:session];

    const NSUInteger total = orderedCalls.count;
    if (total == 0) {
        [self startRoundInSession:session provider:provider chunkHandler:chunkHandler completionHandler:completionHandler];
        return;
    }

    __block NSError *terminalError = nil;
    __weak typeof(self) weakSelf = self;

    // Result slots: initially NSNull; each call fills its slot upon completion
    NSMutableArray *slots = [NSMutableArray arrayWithCapacity:total];
    for (NSUInteger i = 0; i < total; i++) [slots addObject:[NSNull null]];
    __block NSUInteger appendCursor = 0;   // Next slot to append (keeps tool results persisted in tool order)
    __block NSUInteger completedCount = 0;

    // Fill slots and append continuously from appendCursor (preserve order and persist as soon as possible)
    void (^storeResult)(NSUInteger, AiMessage *) = ^(NSUInteger idx, AiMessage *msg) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        if (idx < slots.count) slots[idx] = msg;
        while (appendCursor < total &&
               ![[slots objectAtIndex:appendCursor] isKindOfClass:[NSNull class]]) {
            [session.messages addObject:[slots objectAtIndex:appendCursor]];
            appendCursor++;
        }
        [strongSelf saveSession:session];
        [strongSelf notifyMessagesChanged:session];
    };

    // All tools in this round have completed
    void (^finishRound)(void) = ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf || !strongSelf.running) return;
        if (terminalError) {
            // Retry limit reached; finish this round with the final error
            strongSelf.running = NO;
            if (completionHandler) completionHandler(terminalError);
            return;
        }
        strongSelf.toolRound++;
        [strongSelf startRoundInSession:session
                                provider:provider
                            chunkHandler:chunkHandler
                      completionHandler:completionHandler];
    };

    // Single call completed: increment count + optional chained progress callback
    void (^noteCompleted)(dispatch_block_t) = ^(dispatch_block_t done) {
        completedCount++;
        if (completedCount >= total) finishRound();
        if (done) done();
    };

    // Execute call at idx (invoke done on completion; done may be nil)
    void (^executeCallAt)(NSUInteger, dispatch_block_t) = ^(NSUInteger idx, dispatch_block_t done) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf || !strongSelf.running) { if (done) done(); return; }

        NSDictionary *call = orderedCalls[idx];
        NSString *callID = call[@"id"];
        NSString *name = call[@"name"];
        NSString *arguments = call[@"arguments"] ?: @"";
        if (callID.length == 0) callID = [NSString stringWithFormat:@"call_%ld", (long)[call[@"index"] integerValue]];

        // Retry guard: do not feed the same callID back after it has executed ≥3 times
        NSInteger attempts = [strongSelf.attempts[callID] integerValue];
        if (attempts >= kMaxToolAttempts) {
            AiMessage *failMsg = [AiMessage toolResultMessageWithContent:[NSString stringWithFormat:@"Failed after multiple attempts: %@", name ?: @""] toolCallID:callID];
            failMsg.toolName = name ?: @"";
            failMsg.toolSucceeded = NO;
            storeResult(idx, failMsg);
            terminalError = [NSError errorWithDomain:@"AiAgent" code:2
                                            userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Tool %@ failed after multiple attempts", name ?: callID]}];
            noteCompleted(done);
            return;
        }
        strongSelf.attempts[callID] = @(attempts + 1);

        // Check whether the tool exists
        id<AiTool> tool = [[AiToolRegistry sharedRegistry] toolForName:name ?: @""];
        if (!tool) {
            AiMessage *unknownMsg = [AiMessage toolResultMessageWithContent:[NSString stringWithFormat:@"Unknown tool: %@", name ?: @""] toolCallID:callID];
            unknownMsg.toolName = name ?: @"";
            unknownMsg.toolSucceeded = NO;
            storeResult(idx, unknownMsg);
            noteCompleted(done);
            return;
        }

        NSDictionary *normalizedParams = [[AiToolRegistry sharedRegistry] normalizedParams:[strongSelf parseArgumentsJSON:arguments]];

        void (^proceed)(void) = ^{
            __strong typeof(weakSelf) ss2 = weakSelf;
            if (!ss2 || !ss2.running) { if (done) done(); return; }
            [[AiToolRegistry sharedRegistry] executeToolNamed:name ?: @""
                                                       params:normalizedParams
                                                   completion:^(NSString * _Nullable result, NSError * _Nullable error) {
                __strong typeof(weakSelf) ss3 = weakSelf;
                if (!ss3) { if (done) done(); return; }
                NSString *content = result;
                if (content.length == 0 && error) content = error.localizedDescription;
                if (content.length == 0) content = @"(No response)";
                AiMessage *resMsg = [AiMessage toolResultMessageWithContent:content toolCallID:callID];
                resMsg.toolName = name ?: @"";
                resMsg.toolSucceeded = (error == nil);
                storeResult(idx, resMsg);
                noteCompleted(done);
            }];
        };

        // Safety confirmation (wait for the user's choice when DangerousWrite etc. requires confirmation)
        if ([[AiSafetyManager sharedManager] needsUserConfirmationForPermission:tool.permission]) {
            [[AiSafetyManager sharedManager] requestConfirmationWithTitle:[NSString stringWithFormat:@"AI wants to run \"%@\"", name ?: @""]
                                                                  message:[NSString stringWithFormat:@"This tool requires your confirmation before it can run.\nParameters: %@", arguments]
                                                              completion:^(BOOL approved) {
                __strong typeof(weakSelf) ss4 = weakSelf;
                if (!ss4 || !ss4.running) { if (done) done(); return; }
                if (!approved) {
                    AiMessage *cancelMsg = [AiMessage toolResultMessageWithContent:@"The user cancelled this operation" toolCallID:callID];
                    cancelMsg.toolName = name ?: @"";
                    cancelMsg.toolSucceeded = NO;
                    storeResult(idx, cancelMsg);
                    noteCompleted(done);
                    return;
                }
                proceed();
            }];
        } else {
            proceed();
        }
    };

    // Categorize: calls requiring confirmation (serial chain to avoid showing multiple dialogs at once) / calls not requiring confirmation (dispatch concurrently)
    NSMutableArray<NSNumber *> *immediateIndices = [NSMutableArray array];
    NSMutableArray<NSNumber *> *confirmIndices = [NSMutableArray array];
    for (NSUInteger i = 0; i < total; i++) {
        NSDictionary *call = orderedCalls[i];
        NSString *name = call[@"name"];
        id<AiTool> tool = [[AiToolRegistry sharedRegistry] toolForName:name ?: @""];
        if (tool && [[AiSafetyManager sharedManager] needsUserConfirmationForPermission:tool.permission]) {
            [confirmIndices addObject:@(i)];
        } else {
            [immediateIndices addObject:@(i)];
        }
    }

    // Dispatch calls that do not require confirmation concurrently
    for (NSNumber *idxNum in immediateIndices) {
        executeCallAt(idxNum.unsignedIntegerValue, nil);
    }

    // Handle calls requiring confirmation in a serial chain (show the next dialog after the current one is resolved)
    __block void (^confirmChain)(NSUInteger);
    confirmChain = ^(NSUInteger ci) {
        if (ci >= confirmIndices.count) { confirmChain = nil; return; }
        executeCallAt([confirmIndices[ci] unsignedIntegerValue], ^{
            confirmChain(ci + 1);
        });
    };
    confirmChain(0);
}

#pragma mark - Stop

- (void)stopCurrent {
    if (self.client) [self.client stop];
    self.running = NO;
}

@end