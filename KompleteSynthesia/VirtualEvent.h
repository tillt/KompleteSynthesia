//
//  VirtualEvent.h
//  KompleteSynthesia
//
//  Created by Till Toenshoff on 04.11.23.
//

#import <CoreGraphics/CoreGraphics.h>
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface VirtualEvent : NSObject

+ (void)triggerKeyEvents:(CGKeyCode)keyCode;
+ (void)triggerAuxKeyEvents:(uint32_t)keyCode;
+ (void)triggerMouseWheelEvent:(int)distance;

@end

NS_ASSUME_NONNULL_END
