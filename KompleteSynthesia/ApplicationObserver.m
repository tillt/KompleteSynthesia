//
//  ApplicationHelperFunction.m
//  KompleteSynthesia
//
//  Created by Till Toenshoff on 05.02.23.
//

#import "ApplicationObserver.h"
#import <AppKit/AppKit.h>

@implementation ApplicationObserver


+ (BOOL)applicationIsRunning:(NSString*)name
{
    NSArray* apps = [[NSWorkspace sharedWorkspace] runningApplications];
    for (NSRunningApplication* app in apps) {
        if ([app.localizedName compare:name] == NSOrderedSame && !app.terminated) {
            return YES;
        }
    }
    return NO;
}

+ (BOOL)terminateApplication:(NSString*)name
{
    NSArray* apps = [[NSWorkspace sharedWorkspace] runningApplications];
    for (NSRunningApplication* app in apps) {
        if ([app.localizedName compare:name] == NSOrderedSame) {
            NSLog(@"found and trying to kill...");
            return [app forceTerminate];
        }
    }
    return NO;
}

static NSString *const KVO_CONTEXT_TERMINATED_CHANGED = @"KVO_CONTEXT_TERMINATED_CHANGED";

- (void)observeApplication:(NSString*)name
{
    NSArray* apps = [[NSWorkspace sharedWorkspace] runningApplications];
    for (NSRunningApplication* app in apps) {
        if ([app.localizedName compare:name] == NSOrderedSame) {
            NSLog(@"found and observing...");
            [app addObserver:self
                  forKeyPath:@"terminated"
                     options:0
                     context:CFBridgingRetain(KVO_CONTEXT_TERMINATED_CHANGED)];
        }
    }
}

// whenever an observed key path changes, this method will be called
- (void)observeValueForKeyPath:(NSString *)keyPath
                      ofObject:(id)object
                        change:(NSDictionary *)change
                       context:(void *)context
{
    // use the context to make sure this is a change in the address,
    // because we may also be observing other things
    if(context == CFBridgingRetain(KVO_CONTEXT_TERMINATED_CHANGED)) {
        NSValue *terminated = [object valueForKey:@"terminated"];
        NSLog(@"application has a new value: %@", terminated);
    }
}

@end
