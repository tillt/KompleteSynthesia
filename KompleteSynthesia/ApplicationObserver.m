//
//  ApplicationObserver.m
//  KompleteSynthesia
//
//  Created by Till Toenshoff on 05.02.23.
//

#import "ApplicationObserver.h"
#import <AppKit/AppKit.h>

/// Provides a collection of workspace application queries and commands.

static NSString *const KVO_CONTEXT_TERMINATED_CHANGED = @"KVO_CONTEXT_TERMINATED_CHANGED";
const NSTimeInterval kShutdownTimeout = 5.0;

@implementation ApplicationObserver
{
    NSMutableDictionary<NSString*,NSDictionary*>* observedApplications;
}

- (id)init
{
    self = [super init];
    if (self) {
        observedApplications = [NSMutableDictionary dictionary];
    }
    return self;
}

+ (NSRunningApplication*)runningApplicationWithBundleIdentifier:(NSString*)bundleIdentifier
{
    NSArray* apps = [[NSWorkspace sharedWorkspace] runningApplications];
    for (NSRunningApplication* app in apps) {
        if (app.bundleIdentifier == nil) {
            continue;
        }

        if ([app.bundleIdentifier compare:bundleIdentifier] == NSOrderedSame) {
            return app;
        }
    }
    return nil;
}

+ (BOOL)applicationHasFocus:(NSString*)bundleIdentifier
{
    NSRunningApplication* app = [[NSWorkspace sharedWorkspace] frontmostApplication];

    if (app == nil || app.isTerminated == YES || app.bundleIdentifier == nil) {
        return NO;
    }
    
    return [app.bundleIdentifier compare:bundleIdentifier] == NSOrderedSame;
}

+ (BOOL)applicationIsRunning:(NSString*)bundleIdentifier
{
    NSRunningApplication* app = [ApplicationObserver runningApplicationWithBundleIdentifier:bundleIdentifier];

    if (app == nil || app.isTerminated == YES) {
        return NO;
    }

    return YES;
}

- (BOOL)terminateApplication:(NSString*)bundleIdentifier completion:(void(^)(BOOL))completion
{
    NSRunningApplication* app = [ApplicationObserver runningApplicationWithBundleIdentifier:bundleIdentifier];

    if (app == nil || app.isTerminated == YES) {
        return NO;
    }

    NSLog(@"found %@ and trying to kill %@ ...", bundleIdentifier, app.localizedName);
    
    NSTimer* timer = [NSTimer scheduledTimerWithTimeInterval:kShutdownTimeout repeats:NO block:^(NSTimer* timer){
        if ([self->observedApplications objectForKey:bundleIdentifier] == nil) {
            // Application seems gone, we are done.
            return;
        }

        // Seems like that application was still running, give up!
        NSLog(@"timeout when trying to kill %@", bundleIdentifier);
        NSDictionary* dict = self->observedApplications[bundleIdentifier];
        void(^completion)(BOOL) = dict[@"completion"];
        
        [dict[@"application"] removeObserver:self forKeyPath:@"isTerminated"];
        [self->observedApplications removeObjectForKey:bundleIdentifier];
        
        completion(NO);
    }];
    
    observedApplications[bundleIdentifier] = @{
        @"application": app,
        @"completion": completion,
        @"timer": timer };

    [app addObserver:self
          forKeyPath:@"isTerminated"
             options:NSKeyValueObservingOptionNew
             context:(void*)CFBridgingRetain(KVO_CONTEXT_TERMINATED_CHANGED)];

    return [app forceTerminate];
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
            assert([observedApplications objectForKey:app.bundleIdentifier] != nil);
            NSDictionary* dict = observedApplications[app.bundleIdentifier];

            assert(app == dict[@"application"]);

            NSTimer* timer = dict[@"timer"];
            void(^completion)(BOOL) = dict[@"completion"];

            [timer invalidate];
            [observedApplications removeObjectForKey:app.bundleIdentifier];

            completion(YES);
        }
    }
}

@end
