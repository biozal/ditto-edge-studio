//
//  NSExceptionHandler.h
//  Edge Debug Helper
//
//  C-based NSException handler for catching Objective-C exceptions
//

#ifndef NSExceptionHandler_h
#define NSExceptionHandler_h

#import <objc/objc.h>

#ifdef __cplusplus
extern "C" {
#endif

// Returns 0 if no exception, 1 if exception was caught
int try_objective_c_block(void (^block)(void));

#ifdef __cplusplus
}
#endif

#endif /* NSExceptionHandler_h */