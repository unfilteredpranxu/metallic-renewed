//
//  AiAskTool.m
//  Amethyst
//

#import "AiAskTool.h"
#import <UIKit/UIKit.h>

@implementation AiAskTool

- (NSString *)name {
    return @"ask";
}

- (AiToolPermission)permission {
    return AiToolPermissionReadOnly;
}

- (NSString *)summary {
    return @"Use when the user needs to make a decision (e.g. choose a version, loader, target instance, or asset)."
           "\nParameters (choose one):"
           "\n  - questions (string or array): JSON array or NSArray; each item is @{question, options:[...], allowCustom:bool}."
           "\n  - Single question: question (string) + options (array) + allowCustom (bool, optional)."
           "\nFlow: present a selection wizard on the main thread in order and collect the user's answer to each question; supports \"Custom…\" input and \"Cancel\"."
           "\nAfter all questions are answered, return JSON {\"answers\":[{\"question\":..,\"answer\":..}]};"
           "\nIf the user cancels at any step, return {\"cancelled\":true}."
           "\nUsage: call this tool first to get the answers, then perform the subsequent operation accordingly; do not guess the user's choices.";
}

#pragma mark - View controller lookup

- (UIViewController * _Nullable)topmostPresentableViewController {
    UIWindow *keyWindow = nil;
    if (@available(iOS 13.0, *)) {
        for (UIWindowScene *scene in [UIApplication sharedApplication].connectedScenes) {
            if (scene.activationState == UISceneActivationStateForegroundActive) {
                keyWindow = scene.windows.firstObject;
                break;
            }
        }
    }
    if (!keyWindow) keyWindow = [[UIApplication sharedApplication] windows].firstObject;
    if (!keyWindow) keyWindow = [UIApplication sharedApplication].keyWindow;
    UIViewController *top = keyWindow.rootViewController;
    while (top.presentedViewController) {
        top = top.presentedViewController;
    }
    return top;
}

#pragma mark - Parameter parsing

- (NSArray<NSDictionary *> *)parseSteps:(NSDictionary *)params {
    id questionsValue = params[@"questions"];
    NSArray *questionsArray = nil;

    if ([questionsValue isKindOfClass:[NSArray class]]) {
        questionsArray = questionsValue;
    } else if ([questionsValue isKindOfClass:[NSString class]] && [(NSString *)questionsValue length] > 0) {
        NSData *data = [(NSString *)questionsValue dataUsingEncoding:NSUTF8StringEncoding];
        id parsed = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
        if ([parsed isKindOfClass:[NSArray class]]) questionsArray = parsed;
    }

    NSMutableArray *steps = [NSMutableArray array];
    if (questionsArray) {
        for (id item in questionsArray) {
            if (![item isKindOfClass:[NSDictionary class]]) continue;
            id question = item[@"question"];
            if (![question isKindOfClass:[NSString class]] || [(NSString *)question length] == 0) continue;
            NSMutableArray *options = [NSMutableArray array];
            if ([item[@"options"] isKindOfClass:[NSArray class]]) {
                for (id opt in item[@"options"]) {
                    if ([opt isKindOfClass:[NSString class]] && [(NSString *)opt length] > 0) {
                        [options addObject:opt];
                    }
                }
            }
            BOOL allowCustom = [item[@"allowCustom"] isKindOfClass:[NSNumber class]] && [item[@"allowCustom"] boolValue];
            [steps addObject:@{
                @"question": question,
                @"options": options,
                @"allowCustom": @(allowCustom),
            }];
        }
    } else {
        // Single-question form
        id question = params[@"question"];
        if ([question isKindOfClass:[NSString class]] && [(NSString *)question length] > 0) {
            NSMutableArray *options = [NSMutableArray array];
            if ([params[@"options"] isKindOfClass:[NSArray class]]) {
                for (id opt in params[@"options"]) {
                    if ([opt isKindOfClass:[NSString class]] && [(NSString *)opt length] > 0) [options addObject:opt];
                }
            }
            BOOL allowCustom = [params[@"allowCustom"] isKindOfClass:[NSNumber class]] && [params[@"allowCustom"] boolValue];
            [steps addObject:@{
                @"question": question,
                @"options": options,
                @"allowCustom": @(allowCustom),
            }];
        }
    }
    return steps;
}

#pragma mark - Execute

- (void)execute:(NSDictionary<NSString *, id> *)params
     completion:(void (^)(NSString * _Nullable result, NSError * _Nullable error))completion {
    if (!completion) return;
    NSArray *steps = [self parseSteps:params];
    if (steps.count == 0) {
        NSError *err = [NSError errorWithDomain:@"AiTool" code:400
                                       userInfo:@{NSLocalizedDescriptionKey: @"No valid question provided (questions/question parameter missing)"}];
        completion(nil, err);
        return;
    }
    // Always perform UI work on the main thread
    dispatch_async(dispatch_get_main_queue(), ^{
        [self presentStepAtIndex:0 steps:steps answers:[NSMutableArray array] completion:completion];
    });
}

- (void)presentStepAtIndex:(NSUInteger)index
                     steps:(NSArray *)steps
                   answers:(NSMutableArray *)answers
                completion:(void (^)(NSString * _Nullable result, NSError * _Nullable error))completion {
    // All questions answered → produce the result
    if (index >= steps.count) {
        NSDictionary *result = @{@"answers": answers};
        NSData *data = [NSJSONSerialization dataWithJSONObject:result options:0 error:nil];
        completion(data ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : @"{\"answers\":[]}", nil);
        return;
    }

    NSDictionary *step = steps[index];
    NSString *question = step[@"question"];
    NSArray *options = step[@"options"];
    BOOL allowCustom = [step[@"allowCustom"] boolValue];

    UIViewController *presentingVC = [self topmostPresentableViewController];
    if (!presentingVC) {
        // No available view controller: handle as cancelled
        NSDictionary *cancelled = @{@"cancelled": @YES};
        NSData *data = [NSJSONSerialization dataWithJSONObject:cancelled options:0 error:nil];
        completion(data ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : @"{\"cancelled\":true}", nil);
        return;
    }

    UIAlertController *alert = [UIAlertController
        alertControllerWithTitle:[NSString stringWithFormat:@"%lu. %@", (unsigned long)(index + 1), question]
                         message:nil
                  preferredStyle:UIAlertControllerStyleAlert];

    // Option buttons
    for (NSString *option in options) {
        [alert addAction:[UIAlertAction actionWithTitle:option
                                                  style:UIAlertActionStyleDefault
                                                handler:^(UIAlertAction *action) {
            [answers addObject:@{@"question": question, @"answer": option}];
            [self presentStepAtIndex:(index + 1) steps:steps answers:answers completion:completion];
        }]];
    }

    // Custom input
    if (allowCustom) {
        [alert addAction:[UIAlertAction actionWithTitle:@"Custom…"
                                                  style:UIAlertActionStyleDefault
                                                handler:^(UIAlertAction *action) {
            UIViewController *presenting2 = [self topmostPresentableViewController];
            UIAlertController *textAlert = [UIAlertController
                alertControllerWithTitle:[NSString stringWithFormat:@"%lu. %@", (unsigned long)(index + 1), question]
                                 message:@"Enter a custom answer"
                          preferredStyle:UIAlertControllerStyleAlert];
            [textAlert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
                textField.placeholder = @"Enter here…";
                textField.autocapitalizationType = UITextAutocapitalizationTypeNone;
            }];
            [textAlert addAction:[UIAlertAction actionWithTitle:@"OK"
                                                          style:UIAlertActionStyleDefault
                                                        handler:^(UIAlertAction *submit) {
                NSString *text = [textAlert.textFields.firstObject.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
                [answers addObject:@{@"question": question, @"answer": (text.length ? text : @"")}];
                [self presentStepAtIndex:(index + 1) steps:steps answers:answers completion:completion];
            }]];
            [textAlert addAction:[UIAlertAction actionWithTitle:@"Cancel"
                                                          style:UIAlertActionStyleCancel
                                                        handler:^(UIAlertAction *cancel) {
                [self finishWithCancel:completion];
            }]];
            if (presenting2) [presenting2 presentViewController:textAlert animated:YES completion:nil];
            else [self finishWithCancel:completion];
        }]];
    }

    // Cancel
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel"
                                              style:UIAlertActionStyleCancel
                                            handler:^(UIAlertAction *action) {
        [self finishWithCancel:completion];
    }]];

    [presentingVC presentViewController:alert animated:YES completion:nil];
}

- (void)finishWithCancel:(void (^)(NSString * _Nullable result, NSError * _Nullable error))completion {
    NSDictionary *cancelled = @{@"cancelled": @YES};
    NSData *data = [NSJSONSerialization dataWithJSONObject:cancelled options:0 error:nil];
    completion(data ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : @"{\"cancelled\":true}", nil);
}

@end