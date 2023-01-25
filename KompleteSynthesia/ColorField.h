//
//  ColorField.h
//  KompleteSynthesia
//
//  Created by Till Toenshoff on 24.01.23.
//

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@interface ColorField : NSButton

@property (nonatomic, strong) NSColor* color;
@property (nonatomic, strong) NSColor* pushedColor;

@property (nonatomic, assign) unsigned char keyState;

// FIXME: System provided attributes might be a better choice.
@property (nonatomic, assign) BOOL rounded;

+ (NSColor*)colorWithKeyState:(const unsigned char)keyState;

@end

NS_ASSUME_NONNULL_END
