//
//  ColorField.m
//  KompleteSynthesia
//
//  Created by Till Toenshoff on 24.01.23.
//

#import "ColorField.h"

@implementation ColorField

+ (NSColor*)colorWithKeyState:(const unsigned char)keyState
{
    if (keyState < 0x04) {
        return [NSColor blackColor];
    }
  
    const int intensityShift = 5;
    const int intensityDivider = intensityShift + 3;
    const unsigned char colorIndex = ((keyState >> 2) - 1) % 17;
    const unsigned char colorIntensity = (keyState & 0x03) + intensityShift;

    // TODO: This is just a very rough, initial approximation of the actual palette of the S-series controllers.
    const unsigned char palette[17][3] = {
        { 0xFF, 0x00, 0x00 },   // 0: red
        { 0xFF, 0x3F, 0x00 },   // 1:
        { 0xFF, 0x7F, 0x00 },   // 2: orange
        { 0xFF, 0xCF, 0x00 },   // 3: orange-yellow
        { 0xFF, 0xFF, 0x00 },   // 4: yellow
        { 0x7F, 0xFF, 0x00 },   // 5: green-yellow
        { 0x00, 0xFF, 0x00 },   // 6: green
        { 0x00, 0xFF, 0x7F },   // 7:
        { 0x00, 0xFF, 0xFF },   // 8:
        { 0x00, 0x7F, 0xFF },   // 9:
        { 0x00, 0x00, 0xFF },   // 10: blue
        { 0x3F, 0x00, 0xFF },   // 11:
        { 0x7F, 0x00, 0xFF },   // 12: purple
        { 0xFF, 0x00, 0xFF },   // 13: pink
        { 0xFF, 0x00, 0x7F },   // 14:
        { 0xFF, 0x00, 0x3F },   // 15:
        { 0xFF, 0xFF, 0xFF }    // 16: white
    };
    
    // FIXME: This intensity simulation only really works for white - racist shit!
    return [NSColor colorWithRed:(((float)palette[colorIndex][0] / 255.0) * colorIntensity) / intensityDivider
                           green:(((float)palette[colorIndex][1] / 255.0) * colorIntensity) / intensityDivider
                            blue:(((float)palette[colorIndex][2] / 255.0) * colorIntensity) / intensityDivider
                           alpha:1.0];
}

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
    self.color = [ColorField colorWithKeyState:_keyState];
}

@end
