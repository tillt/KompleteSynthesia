//
//  ApplicationHelperFunction.h
//  KompleteSynthesia
//
//  Created by Till Toenshoff on 05.02.23.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface ApplicationObserver : NSObject

+ (BOOL)applicationIsRunning:(NSString*)name;
+ (BOOL)terminateApplication:(NSString*)name;

@end

NS_ASSUME_NONNULL_END
