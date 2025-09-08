//
//  ExceptionCatcher.h
//  Edge Debug Helper
//

#import <Foundation/Foundation.h>

@interface ExceptionCatcher : NSObject

+ (NSError *)performBlock:(void (^)(void))block;

@end