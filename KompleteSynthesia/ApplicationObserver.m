//
//  ApplicationHelperFunction.m
//  KompleteSynthesia
//
//  Created by Till Toenshoff on 05.02.23.
//

#import "ApplicationObserver.h"
#import <AppKit/AppKit.h>

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

- (BOOL)terminateApplication:(NSString*)name completion:(void(^)(BOOL))completion
{
    for (NSRunningApplication* app in [[NSWorkspace sharedWorkspace] runningApplications]) {
        if ([app.localizedName compare:name] == NSOrderedSame) {
            NSLog(@"found and trying to kill...");
            
            NSTimer* timer = [NSTimer scheduledTimerWithTimeInterval:kShutdownTimeout repeats:NO block:^(NSTimer* timer){
                if ([observedApplications objectForKey:app.localizedName] != nil) {
                    // Seems like that application was still running, give up!
                    NSLog(@"timeout when trying to kill %@", app.localizedName);
                    NSDictionary* dict = observedApplications[app.localizedName];
                    void(^completion)(BOOL) = dict[@"completion"];
                    
                    [dict[@"application"] removeObserver:self forKeyPath:@"isTerminated"];
                    [observedApplications removeObjectForKey:app.localizedName];
                    
                    completion(NO);
                }
            }];
            
            observedApplications[app.localizedName] = @{
                @"application": app,
                @"completion": completion,
                @"timer": timer };

            [app addObserver:self
                  forKeyPath:@"isTerminated"
                     options:NSKeyValueObservingOptionNew
                     context:(void*)CFBridgingRetain(KVO_CONTEXT_TERMINATED_CHANGED)];

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
            NSDictionary* dict = observedApplications[app.localizedName];

            NSTimer* timer = dict[@"timer"];
            void(^completion)(BOOL) = dict[@"completion"];

            [timer invalidate];
            [observedApplications removeObjectForKey:app.localizedName];

            completion(YES);
        }
    }
}

@end
