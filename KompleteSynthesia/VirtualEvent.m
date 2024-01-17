//
//  VirtualEvent.m
//  KompleteSynthesia
//
//  Created by Till Toenshoff on 04.11.23.
//
#import "VirtualEvent.h"

#import <AppKit/AppKit.h>

@implementation VirtualEvent

+ (void)triggerKeyEvents:(CGKeyCode)keyCode
{
    NSLog(@"sending virtual key events with keyCode:%d", keyCode);

    CGEventRef down = CGEventCreateKeyboardEvent(nil, keyCode, true);
    CGEventPost(kCGHIDEventTap, down);
    CFRelease(down);

    CGEventRef up = CGEventCreateKeyboardEvent(nil, keyCode, false);
    CGEventPost(kCGHIDEventTap, up);
    CFRelease(up);
}

+ (void)triggerAuxKeyEvents:(uint32_t)key
{
    NSLog(@"sending virtual aux key events with keyCode:%d", key);

    NSEventModifierFlags flags = 0xa00;
    uint32_t data1 = (key << 16) | (uint32_t)flags;

    NSEvent* ev = [NSEvent otherEventWithType:NSEventTypeSystemDefined
                                     location:NSMakePoint(0.0f, 0.0f)
                                modifierFlags:flags
                                    timestamp:0
                                 windowNumber:0
                                      context:nil
                                      subtype:8
                                        data1:data1
                                        data2:-1];

    CGEventPost(kCGHIDEventTap, ev.CGEvent);

    flags = 0xb00;
    data1 = (key << 16) | (uint32_t)flags;

    ev = [NSEvent otherEventWithType:NSEventTypeSystemDefined
                            location:NSMakePoint(0.0f, 0.0f)
                       modifierFlags:flags
                           timestamp:0
                        windowNumber:0
                             context:nil
                             subtype:8
                               data1:data1
                               data2:-1];

    CGEventPost(kCGHIDEventTap, ev.CGEvent);
}

+ (void)triggerMouseWheelEvent:(int)distance
{
    NSLog(@"sending virtual mouse wheel event with delta:%d", distance);

    CGEventRef ourEvent = CGEventCreate(NULL);
    CGPoint point = CGEventGetLocation(ourEvent);
    CFRelease(ourEvent);

    CGEventRef event = CGEventCreateScrollWheelEvent(NULL, kCGScrollEventUnitPixel, distance, point.y, point.x);
    CGEventSetType(event, kCGEventScrollWheel);
    CGEventSetIntegerValueField(event, kCGScrollWheelEventDeltaAxis1, distance);
    CGEventPost(kCGSessionEventTap, event);
    CFRelease(event);
}

@end
