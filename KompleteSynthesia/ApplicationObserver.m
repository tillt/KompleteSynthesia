//
//  ApplicationHelperFunction.m
//  KompleteSynthesia
//
//  Created by Till Toenshoff on 05.02.23.
//

#import "ApplicationObserver.h"
#import <AppKit/AppKit.h>

static NSString *const KVO_CONTEXT_TERMINATED_CHANGED = @"KVO_CONTEXT_TERMINATED_CHANGED";

@implementation ApplicationObserver
{
    NSMutableDictionary<NSString*,NSArray*>* observedApplications;
}

- (id)initWithDelegate:(id)delegate
{
    self = [super init];
    if (self) {
        _delegate = delegate;
        observedApplications = [NSMutableDictionary dictionary];
    }
    return self;
}

+ (BOOL)applicationIsRunning:(NSString*)name
{
    NSArray* apps = [[NSWorkspace sharedWorkspace] runningApplications];
    for (NSRunningApplication* app in apps) {
        if ([app.localizedName compare:name] == NSOrderedSame && !app.isTerminated) {
            return YES;
        }
    }
    return NO;
}

- (BOOL)terminateApplication:(NSString*)name completion:(void(^)(void))completion
{
    for (NSRunningApplication* app in [[NSWorkspace sharedWorkspace] runningApplications]) {
        if ([app.localizedName compare:name] == NSOrderedSame) {
            NSLog(@"found and trying to kill...");
            observedApplications[app.localizedName] = @[app, completion];
            [app addObserver:self
                  forKeyPath:@"isTerminated"
                     options:NSKeyValueObservingOptionNew
                     context:CFBridgingRetain(KVO_CONTEXT_TERMINATED_CHANGED)];
            return [app forceTerminate];
        }
    }
    return NO;
}

- (void)observeValueForKeyPath:(NSString*)keyPath
                      ofObject:(id)object
                        change:(NSDictionary*)change
                       context:(void*)context
{
    if (context == CFBridgingRetain(KVO_CONTEXT_TERMINATED_CHANGED)) {
        NSRunningApplication* app = object;
        [app removeObserver:self forKeyPath:@"isTerminated"];
        if (app.isTerminated) {
            assert([observedApplications objectForKey:app.localizedName] != nil);
            void(^completion)(void) = observedApplications[app.localizedName][1];
            completion();
            [observedApplications removeObjectForKey:app.localizedName];
        }
    }
}

@end
