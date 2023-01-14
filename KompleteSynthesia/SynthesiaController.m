//
//  SynthesiaController.m
//  KompleteSynthesia
//
//  Created by Till Toenshoff on 13.01.23.
//

#import "SynthesiaController.h"
#import <AppKit/AppKit.h>

NSString* kSynthesiaApplicationName = @"Synthesia";

/// Tries to locate Synthesia among the running applications and informs the delegate when the state changed.

@implementation SynthesiaController

+ (NSString*)status
{
    if ([SynthesiaController synthesiaHasFocus]) {
        return @"Synthesia active";
    } else if ([SynthesiaController synthesiaRunning]) {
        return @"Synthesia running";
    }
    return @"No Synthesia";
}

+ (BOOL)synthesiaRunning
{
    NSArray* apps = [[NSWorkspace sharedWorkspace] runningApplications];
    for (NSRunningApplication* app in apps) {
        if ([app.localizedName compare:kSynthesiaApplicationName] == NSOrderedSame) {
            return YES;
        }
    }
    return NO;
}

+ (BOOL)synthesiaHasFocus
{
    NSRunningApplication* app = [[NSWorkspace sharedWorkspace] frontmostApplication];
    if ([app.localizedName compare:kSynthesiaApplicationName] == NSOrderedSame) {
        return YES;
    }
    return NO;
}

+ (void)triggerVirtualKeyEvents:(CGKeyCode)keyCode
{
    NSLog(@"sending virtual key events with keyCode:%d", keyCode);
    CGEventPost(kCGHIDEventTap, CGEventCreateKeyboardEvent(nil, keyCode, true));
    CGEventPost(kCGHIDEventTap, CGEventCreateKeyboardEvent(nil, keyCode, false));
}

- (id)initWithDelegate:(id)delegate
{
    self = [super init];
    if (self) {
        _delegate = delegate;

        [[[NSWorkspace sharedWorkspace] notificationCenter] addObserver:self
                                                               selector:@selector(synthesiaMayHaveChangedStatus:)
                                                                   name:NSWorkspaceDidActivateApplicationNotification
                                                                 object:nil];

        [[[NSWorkspace sharedWorkspace] notificationCenter] addObserver:self
                                                               selector:@selector(synthesiaMayHaveChangedStatus:)
                                                                   name:NSWorkspaceDidTerminateApplicationNotification
                                                                 object:nil];
    }
    return self;
}

- (void)synthesiaMayHaveChangedStatus:(NSNotification*)notification
{
    [_delegate synthesiaStateUpdate:[SynthesiaController status]];
}

@end
