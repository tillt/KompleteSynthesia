//
//  ApplicationObserver.h
//  KompleteSynthesia
//
//  Created by Till Toenshoff on 05.02.23.
//

#import <AppKit/AppKit.h>
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface ApplicationObserver : NSObject

+ (nullable NSRunningApplication*)runningApplicationWithBundleIdentifier:(NSString*)bundleIdentifier;
+ (BOOL)applicationIsRunning:(NSString*)bundleIdentifier;
+ (BOOL)applicationHasFocus:(NSString*)bundleIdentifier;

- (id)init;
- (BOOL)terminateApplication:(NSString*)bundleIdentifier completion:(void (^)(BOOL))completion;

@end

NS_ASSUME_NONNULL_END
