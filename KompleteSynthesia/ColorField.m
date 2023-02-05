//
//  ColorField.m
//  KompleteSynthesia
//
//  Created by Till Toenshoff on 24.01.23.
//

#import "ColorField.h"
#import "HIDController.h"

/// Clickable control for sampling a color.

@implementation ColorField

- (void)drawRect:(NSRect)dirtyRect
{
    [super drawRect:dirtyRect];
    
    NSGraphicsContext* currentContext = [NSGraphicsContext currentContext];
    [currentContext saveGraphicsState];

    if (self.isHighlighted) {
        [self.pushedColor setFill];
    } else {
        [self.color setFill];
    }

    NSBezierPath* rectanglePath = nil;

    if (_rounded) {
        rectanglePath = [NSBezierPath bezierPathWithRoundedRect:NSMakeRect(0, 0, self.frame.size.width, self.frame.size.height) xRadius:7.0f yRadius:7.0f];
    } else {
        rectanglePath = [NSBezierPath bezierPathWithRect:NSMakeRect(0, 0, self.frame.size.width, self.frame.size.height)];
    }
    [rectanglePath fill];
    
    [currentContext restoreGraphicsState];
}

- (void)setColor:(NSColor*)color
{
    if (color == _color) {
        return;
    }
    _color = color;
    _pushedColor = [color colorWithSystemEffect:NSColorSystemEffectDeepPressed];
}

- (void)setKeyState:(const unsigned char)keyState
{
    _keyState = keyState;
    self.color = [HIDController colorWithKeyState:_keyState];
}

@end
