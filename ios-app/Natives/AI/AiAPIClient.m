//
//  AiAPIClient.m
//  Amethyst
//

#import "AiAPIClient.h"

/// Throttle threshold: invoke streaming callbacks at most every 200ms to avoid overloading the main queue/UI
static const NSTimeInterval kChunkThrottleInterval = 0.2;

@interface AiAPIClient () <NSURLSessionDataDelegate>
@property (nonatomic, strong, nullable) NSURLSession *session;
@property (nonatomic, strong, nullable) NSURLSessionDataTask *currentTask;

@property (nonatomic, copy, nullable) void (^onChunk)(NSString * _Nullable delta, NSDictionary * _Nullable toolCalls);
@property (nonatomic, copy, nullable) void (^onComplete)(NSDictionary * _Nullable fullResponse, NSError * _Nullable error);

@property (nonatomic, strong) NSMutableString *streamBuffer;    // Incomplete stream buffer
@property (nonatomic, strong) NSMutableData *streamData;        // Raw byte buffer (preserves multibyte characters across chunks)
@property (nonatomic, strong) NSMutableString *fullResponseText; // Full response received so far
@property (nonatomic, strong) NSMutableString *pendingDelta;     // Increment pending a throttled flush
@property (nonatomic, assign) NSTimeInterval lastChunkFlushTime;
@property (nonatomic, assign) BOOL streamDone;
@property (nonatomic, assign) NSInteger statusCode;
@end

@implementation AiAPIClient

- (instancetype)init {
    self = [super init];
    if (self) {
        self.streamBuffer = [NSMutableString string];
        self.streamData = [NSMutableData data];
        self.fullResponseText = [NSMutableString string];
        self.pendingDelta = [NSMutableString string];
    }
    return self;
}

- (void)dealloc {
    [self.session invalidateAndCancel];
}

#pragma mark - Request entry

- (void)streamChatWithProvider:(AiProvider *)provider
                      messages:(NSArray<AiMessage *> *)messages
                         tools:(nullable NSArray<NSDictionary *> *)tools
                       onChunk:(void (^)(NSString * _Nullable delta, NSDictionary * _Nullable toolCalls))onChunk
                    onComplete:(void (^)(NSDictionary * _Nullable fullResponse, NSError * _Nullable error))onComplete {
    if (!provider || provider.baseURL.length == 0 || provider.model.length == 0) {
        NSError *err = [NSError errorWithDomain:@"AiAPIClient" code:100
                                        userInfo:@{NSLocalizedDescriptionKey: @"AI provider configuration is incomplete (missing baseURL or model)"}];
        if (onComplete) {
            dispatch_async(dispatch_get_main_queue(), ^{ onComplete(nil, err); });
        }
        return;
    }

    self.onChunk = onChunk;
    self.onComplete = onComplete;
    [self.streamBuffer setString:@""];
    [self.streamData setLength:0];
    [self.fullResponseText setString:@""];
    [self.pendingDelta setString:@""];
    self.streamDone = NO;
    self.statusCode = 0;

    // Build URL: append / if baseURL does not end with it, then append chat/completions
    NSString *base = provider.baseURL;
    if (![base hasSuffix:@"/"]) {
        base = [base stringByAppendingString:@"/"];
    }
    NSString *urlString = [base stringByAppendingString:@"chat/completions"];
    NSURL *url = [NSURL URLWithString:urlString];
    if (!url) {
        NSError *err = [NSError errorWithDomain:@"AiAPIClient" code:101
                                        userInfo:@{NSLocalizedDescriptionKey: @"Invalid API URL"}];
        if (onComplete) {
            dispatch_async(dispatch_get_main_queue(), ^{ onComplete(nil, err); });
        }
        return;
    }

    // Body
    NSMutableArray *payloadMessages = [NSMutableArray array];
    // Buffer assistant messages with multiple tool_calls to flush (OpenAI requires tool_calls in a single assistant message)
    __block NSString *pendingAssistantContent = @"";
    __block NSMutableArray *pendingToolCalls = nil;
    dispatch_block_t flushPendingToolCalls = ^{
        if (pendingToolCalls.count == 0) { pendingToolCalls = nil; return; }
        NSMutableDictionary *entry = [NSMutableDictionary dictionary];
        entry[@"role"] = @"assistant";
        entry[@"content"] = pendingAssistantContent ?: @"";
        entry[@"tool_calls"] = pendingToolCalls;
        [payloadMessages addObject:entry];
        pendingToolCalls = nil;
        pendingAssistantContent = @"";
    };
    for (AiMessage *m in messages) {
        // Skip streaming placeholder messages
        if (m.streaming) continue;

        // Assistant tool-call record: merge consecutive isToolCall assistant messages into one tool_calls array
        if (m.isToolCall && [m.role isEqualToString:@"assistant"]) {
            if (!pendingToolCalls) {
                pendingToolCalls = [NSMutableArray array];
                pendingAssistantContent = m.content ?: @"";
            } else if (m.content.length > 0 && pendingAssistantContent.length == 0) {
                pendingAssistantContent = m.content;
            }
            NSMutableDictionary *func = [NSMutableDictionary dictionary];
            if (m.toolName.length > 0) func[@"name"] = m.toolName;
            if (m.toolArguments.length > 0) func[@"arguments"] = m.toolArguments;
            NSMutableDictionary *call = [NSMutableDictionary dictionary];
            if (m.toolCallID.length > 0) call[@"id"] = m.toolCallID;
            call[@"type"] = @"function";
            call[@"function"] = func;
            [pendingToolCalls addObject:call];
            continue;
        }

        // Other role messages: flush any buffered assistant tool_calls first
        flushPendingToolCalls();

        NSMutableDictionary *entry = [NSMutableDictionary dictionary];
        entry[@"role"] = m.role ?: @"";
        entry[@"content"] = m.content ?: @"";
        if ([m.role isEqualToString:@"tool"] && m.toolCallID.length > 0) {
            entry[@"tool_call_id"] = m.toolCallID;
        }
        [payloadMessages addObject:entry];
    }
    flushPendingToolCalls();
    NSMutableDictionary *body = [NSMutableDictionary dictionary];
    body[@"model"] = provider.model ?: @"";
    body[@"messages"] = payloadMessages;
    body[@"stream"] = @YES;
    body[@"temperature"] = @(provider.temperature);
    body[@"max_tokens"] = @(provider.maxTokens);
    if (tools.count > 0) {
        body[@"tools"] = tools;
    }

    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.HTTPMethod = @"POST";
    [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    if (provider.apiKey.length > 0) {
        [request setValue:[NSString stringWithFormat:@"Bearer %@", provider.apiKey] forHTTPHeaderField:@"Authorization"];
    }
    request.timeoutInterval = 120;
    NSError *serializeError = nil;
    request.HTTPBody = [NSJSONSerialization dataWithJSONObject:body options:0 error:&serializeError];
    if (serializeError || !request.HTTPBody) {
        if (onComplete) {
            dispatch_async(dispatch_get_main_queue(), ^{ onComplete(nil, serializeError); });
        }
        return;
    }

    // Session (parse on a dedicated background queue to avoid blocking the main thread)
    if (!self.session) {
        NSURLSessionConfiguration *config = [NSURLSessionConfiguration defaultSessionConfiguration];
        config.timeoutIntervalForRequest = 120;
        NSOperationQueue *queue = [[NSOperationQueue alloc] init];
        queue.maxConcurrentOperationCount = 1;
        self.session = [NSURLSession sessionWithConfiguration:config delegate:self delegateQueue:queue];
    }

    self.currentTask = [self.session dataTaskWithRequest:request];
    [self.currentTask resume];
}

#pragma mark - Cancel

- (void)stop {
    [self.currentTask cancel];
}

#pragma mark - Connectivity test

- (void)testConnectionWithProvider:(AiProvider *)provider
                        completion:(void (^)(NSString * _Nullable successMessage, NSError * _Nullable error))completion {
    if (!provider || provider.baseURL.length == 0 || provider.model.length == 0) {
        NSError *err = [NSError errorWithDomain:@"AiAPIClient" code:100
                                        userInfo:@{NSLocalizedDescriptionKey: @"AI provider configuration is incomplete (missing baseURL or model)"}];
        if (completion) {
            dispatch_async(dispatch_get_main_queue(), ^{ completion(nil, err); });
        }
        return;
    }

    AiMessage *ping = [AiMessage messageWithRole:@"user" content:@"ping"];
    // Reuse the streaming channel for a very short chat request; ignore deltas and return the result only when finished
    [self streamChatWithProvider:provider
                        messages:@[ping]
                           tools:nil
                         onChunk:nil
                      onComplete:^(NSDictionary * _Nullable fullResponse, NSError * _Nullable error) {
        if (completion) {
            if (error) {
                completion(nil, error);
            } else {
                completion(@"Connection successful", nil);
            }
        }
    }];
}

#pragma mark - Stream parsing

/// Extract complete byte sequences ending in \n from the byte buffer, decode and process by line (preserving an incomplete multibyte suffix)
- (void)processBufferedStreamData {
    if (self.streamData.length == 0) return;
    static unsigned char lf = '\n';
    NSData *lfData = [NSData dataWithBytes:&lf length:1];
    NSRange lastLF = [self.streamData rangeOfData:lfData options:NSDataSearchBackwards
                                            range:NSMakeRange(0, self.streamData.length)];
    // No complete line yet: a multibyte character may have been split and is not complete; keep the bytes for the next chunk
    if (lastLF.location == NSNotFound) return;
    NSUInteger completeLen = lastLF.location + 1;
    NSData *completeData = [self.streamData subdataWithRange:NSMakeRange(0, completeLen)];
    NSString *text = [[NSString alloc] initWithData:completeData encoding:NSUTF8StringEncoding];
    if (text.length > 0) {
        [self processStreamText:text];
    }
    [self.streamData replaceBytesInRange:NSMakeRange(0, completeLen) withBytes:NULL length:0];
}

/// Append received text and process by line
- (void)processStreamText:(NSString *)text {
    if (text.length == 0 || self.streamDone) return;
    [self.streamBuffer appendString:text];

    // Process each complete line in the buffer
    NSInteger consumed = 0;
    NSRange range;
    BOOL done = NO;
    while (!done) {
        range = [self.streamBuffer rangeOfString:@"\n"];
        if (range.location == NSNotFound) break;
        NSString *line = [self.streamBuffer substringToIndex:range.location];
        NSRange fullRange = NSMakeRange(0, range.location + 1);
        [self.streamBuffer deleteCharactersInRange:fullRange];
        consumed += range.location + 1;
        [self processStreamLine:line];
    }
    (void)consumed;

    // Clear an oversized buffer with no newline (abnormal) to prevent unbounded accumulation
    if (self.streamBuffer.length > 1024 * 1024) {
        [self.streamBuffer setString:@""];
    }
}

- (void)processStreamLine:(NSString *)line {
    NSString *trimmed = [line stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (trimmed.length == 0) return;

    // Support three prefix forms: "data: ", "data:" (no space), and no prefix (use the entire bare line as the payload)
    NSString *payload = nil;
    if ([trimmed hasPrefix:@"data: "]) {
        payload = [trimmed substringFromIndex:6];
    } else if ([trimmed hasPrefix:@"data:"]) {
        payload = [trimmed substringFromIndex:5];
    } else {
        payload = trimmed;
    }
    NSString *payloadTrimmed = [payload stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    if ([payloadTrimmed isEqualToString:@"[DONE]"]) {
        self.streamDone = YES;
        // Mark for toComplete to flush the remainder
        return;
    }

    NSData *jsonData = [payloadTrimmed dataUsingEncoding:NSUTF8StringEncoding];
    NSError *error = nil;
    NSDictionary *json = [NSJSONSerialization JSONObjectWithData:jsonData options:0 error:&error];
    if (error || ![json isKindOfClass:[NSDictionary class]]) return;

    NSArray *choices = json[@"choices"];
    if (![choices isKindOfClass:[NSArray class]] || choices.count == 0) return;
    NSDictionary *choice = choices[0];
    if (![choice isKindOfClass:[NSDictionary class]]) return;
    NSDictionary *delta = choice[@"delta"];
    if (![delta isKindOfClass:[NSDictionary class]]) return;

    id content = delta[@"content"];
    NSString *deltaText = nil;
    if ([content isKindOfClass:[NSString class]] && content != (id)[NSNull null]) {
        deltaText = content;
        [self.fullResponseText appendString:deltaText];
        [self.pendingDelta appendString:deltaText];
    }

    // tool_calls (used in Phase 3; passed through in this release)
    NSArray *toolCallArr = delta[@"tool_calls"];
    if ([toolCallArr isKindOfClass:[NSArray class]]) {
        NSDictionary *toolCallsInfo = @{@"tool_calls": toolCallArr};
        void (^chunk)(NSString *, NSDictionary *) = self.onChunk;
        if (chunk) {
            NSString *emptyDelta = @"";
            dispatch_async(dispatch_get_main_queue(), ^{ chunk(emptyDelta, toolCallsInfo); });
        }
    }

    // Throttle: if less than 200ms have elapsed since the last flush, store pendingDelta until the next flush/completion
    NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
    if ((now - self.lastChunkFlushTime) >= kChunkThrottleInterval) {
        [self flushPendingDelta];
    }
}

- (void)flushPendingDelta {
    if (self.pendingDelta.length > 0 && self.onChunk) {
        NSString *delta = [self.pendingDelta copy];
        [self.pendingDelta setString:@""];
        void (^chunk)(NSString *, NSDictionary *) = self.onChunk;
        if (chunk) {
            NSString *safeDelta = delta;
            dispatch_async(dispatch_get_main_queue(), ^{ chunk(safeDelta, nil); });
        }
    }
    self.lastChunkFlushTime = [[NSDate date] timeIntervalSince1970];
}

#pragma mark - Error construction

- (NSError *)errorFromResponseBody {
    NSString *body = self.fullResponseText.length > 0 ? self.fullResponseText : @"";
    NSString *message = [NSString stringWithFormat:@"Request failed (HTTP %ld)", (long)self.statusCode];
    NSError *jsonError = nil;
    NSDictionary *json = [NSJSONSerialization JSONObjectWithData:[body dataUsingEncoding:NSUTF8StringEncoding]
                                                         options:0 error:&jsonError];
    if (json && [json isKindOfClass:[NSDictionary class]]) {
        NSDictionary *errorObj = json[@"error"];
        if ([errorObj isKindOfClass:[NSDictionary class]] && [errorObj[@"message"] isKindOfClass:[NSString class]]) {
            NSString *m = errorObj[@"message"];
            if (m.length > 0) message = m;
        }
    }
    return [NSError errorWithDomain:@"AiAPIClient" code:self.statusCode
                           userInfo:@{NSLocalizedDescriptionKey: message}];
}

#pragma mark - NSURLSessionDataDelegate

- (void)URLSession:(NSURLSession *)session
              dataTask:(NSURLSessionDataTask *)dataTask
    didReceiveResponse:(NSURLResponse *)response
     completionHandler:(void (^)(NSURLSessionResponseDisposition disposition))completionHandler {
    if ([response isKindOfClass:[NSHTTPURLResponse class]]) {
        self.statusCode = [(NSHTTPURLResponse *)response statusCode];
    }
    completionHandler(NSURLSessionResponseAllow);
}

- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)dataTask didReceiveData:(NSData *)data {
    if (self.streamDone) return;
    if (data.length == 0) return;
    // Important fix (incomplete/truncated AI responses): do not decode each data chunk as UTF-8 independently,
    // or multibyte characters such as CJK text/emoji split across two chunks will be corrupted in the first chunk,
    // causing the SSE line's JSON parse to fail and the entire line to be discarded, which appears as truncated/missing/blank text.
    // Instead, buffer at the byte level: decode only complete byte sequences ending in \n and retain split multibyte characters until completed by subsequent chunks.
    [self.streamData appendData:data];
    [self processBufferedStreamData];
}

- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didCompleteWithError:(NSError *)error {
    self.streamDone = YES;

    void (^complete)(NSDictionary *, NSError *) = self.onComplete;
    self.onComplete = nil;
    self.onChunk = nil;

    if (error) {
        NSError *outError = error;
        if (error.code == NSURLErrorCancelled) {
            outError = [NSError errorWithDomain:@"AiAPIClient" code:NSURLErrorCancelled
                                       userInfo:@{NSLocalizedDescriptionKey: @"Generation stopped"}];
        }
        [self flushPendingDelta];
        if (complete) {
            dispatch_async(dispatch_get_main_queue(), ^{ complete(nil, outError); });
        }
        return;
    }

    if (self.statusCode != 0 && self.statusCode != 200) {
        [self flushPendingDelta];
        NSError *apiError = [self errorFromResponseBody];
        if (complete) {
            dispatch_async(dispatch_get_main_queue(), ^{ complete(nil, apiError); });
        }
        return;
    }

    // Process the last byte chunk without a trailing newline (avoid losing the final characters/content)
    if (self.streamData.length > 0) {
        NSString *tail = [[NSString alloc] initWithData:self.streamData encoding:NSUTF8StringEncoding];
        if (tail.length > 0) {
            [self processStreamText:tail];
        }
        [self.streamData setLength:0];
    }
    // Fallback: if streamBuffer still contains a partial line without a trailing \n (the final content line or data: [DONE] without a newline),
    // copy and clear the buffer, then parse it once as the final complete line to ensure the trailing delta is flushed
    if (self.streamBuffer.length > 0) {
        NSString *tailLine = [self.streamBuffer copy];
        [self.streamBuffer setString:@""];
        [self processStreamLine:tailLine];
    }
    [self flushPendingDelta];
    NSDictionary *fullResponse = @{@"content": [self.fullResponseText copy] ?: @""};
    if (complete) {
        dispatch_async(dispatch_get_main_queue(), ^{ complete(fullResponse, nil); });
    }
}

@end