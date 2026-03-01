//
//  ExceptionCatcher.m
//  Edge Debug Helper
//

#import "ExceptionCatcher.h"

@implementation ExceptionCatcher

+ (NSError *)performBlock:(void (^)(void))block {
    @try {
        if (block) {
            block();
        }
        return nil;
    }
    @catch (NSException *exception) {
        return [NSError errorWithDomain:@"DittoExceptionError"
                                   code:1001
                               userInfo:@{
                                   NSLocalizedDescriptionKey: exception.reason ?: @"Unknown exception",
                                   NSLocalizedFailureReasonErrorKey: exception.name ?: @"NSException",
                                   @"ExceptionName": exception.name ?: @"",
                                   @"ExceptionReason": exception.reason ?: @""
                               }];
    }
}

@end