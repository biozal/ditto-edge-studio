//
//  NSExceptionHandler.c
//  Edge Debug Helper
//
//  C-based NSException handler for catching Objective-C exceptions
//

#include <stdio.h>
#include <objc/objc-exception.h>
#include <setjmp.h>
#include <stdint.h>
#include "NSExceptionHandler.h"

static jmp_buf exception_buf;
static int exception_caught = 0;

// Exception handler function
static void exception_handler(id exception, void *context) {
    exception_caught = 1;
    longjmp(exception_buf, 1);
}

int try_objective_c_block(void (^block)(void)) {
    exception_caught = 0;
    
    // Set up the exception handler
    uintptr_t token = objc_addExceptionHandler(exception_handler, NULL);
    
    // Set up the jump buffer
    if (setjmp(exception_buf) == 0) {
        // Execute the block
        if (block) {
            block();
        }
        
        // Clear the exception handler
        objc_removeExceptionHandler(token);
        return 0; // Success, no exception
    } else {
        // We jumped here due to an exception
        // Clear the exception handler
        objc_removeExceptionHandler(token);
        return 1; // Exception caught
    }
}
