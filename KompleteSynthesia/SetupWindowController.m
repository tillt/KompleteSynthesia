//
//  SetupWindowController.m
//  KompleteSynthesia
//
//  Created by Till Toenshoff on 17.01.24.
//

#import "SetupWindowController.h"

#import <Carbon/Carbon.h>

#import "VirtualEvent.h"

@interface SetupWindowController ()

@end

@implementation SetupWindowController

- (void)windowDidLoad
{
    [super windowDidLoad];

    // Implement this method to handle any initialization after your window controller's window has been loaded from its
    // nib file.
    BOOL ret = [self isInputMonitoringEnabled];
    NSLog(@"input monitoring: %d", ret);
    //
    //    ret = [self isAccessibilityEnabled];
    //    NSLog(@"accessibility: %d", ret);

    //    ret = [self isScreenRecordingEnabled];
    //    NSLog(@"screen recording: %d", ret);
}

- (BOOL)isAccessibilityEnabled
{
    return AXIsProcessTrusted();
}

- (BOOL)isInputMonitoringEnabled
{
    // NOTE: This appears to be buggy in macOS - or I am holding it wrong.
    // Result is that the access returned appears to be shadowed by whatever
    // `Accessibility` is currently setup to. That is, when `Accessibility` is
    // granted, HIDAccess is "granted" as well from what the function returns.
    // In reality that is plain wrong and HID access will not function as expected.
    // See https://openradar.appspot.com/7381305
    IOHIDAccessType accessType = IOHIDCheckAccess(kIOHIDRequestTypeListenEvent);
    return accessType == kIOHIDAccessTypeGranted;
}

- (BOOL)isScreenRecordingEnabled
{
    CFArrayRef cflist = CGWindowListCopyWindowInfo(kCGWindowListOptionAll, kCGNullWindowID);
    NSArray* list = CFBridgingRelease(cflist);

    NSInteger setupWindowNumber = self.window.windowNumber;
    for (NSDictionary* dict in list) {
        // NSLog(@"dict %@", dict);
        NSLog(@"number %@", dict[@"kCGWindowNumber"]);
        NSNumber* number = dict[@"kCGWindowNumber"];
        if (setupWindowNumber != number.intValue) {
            NSLog(@"name %@", dict[@"kCGWindowName"]);
        }
    }

    return NO;
}

- (IBAction)requestAccessibility:(id)sender
{
    BOOL ret = IOHIDRequestAccess(kIOHIDRequestTypePostEvent);
    //    NSLog(@"input monitoring: %d", ret);
    //    [VirtualEvent triggerKeyEvents:kVK_Space];
}

- (IBAction)requestScreenRecording:(id)sender
{
    CGImageRef image = CGWindowListCreateImage(CGRectInfinite, kCGWindowListOptionOnScreenOnly, kCGNullWindowID,
                                               kCGWindowImageDefault);
    CGImageRelease(image);
}

- (IBAction)requestInputMonitoring:(id)sender
{
    BOOL ret = IOHIDRequestAccess(kIOHIDRequestTypeListenEvent);
    NSLog(@"input monitoring: %d", ret);
}

@end
