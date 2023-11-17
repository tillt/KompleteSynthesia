//
//  VirtualEventController.h
//  KompleteSynthesia
//
//  Created by Till Toenshoff on 04.11.23.
//

#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

NS_ASSUME_NONNULL_BEGIN

@interface VirtualEventController : NSObject

+ (void)triggerKeyEvents:(CGKeyCode)keyCode;
+ (void)triggerAuxKeyEvents:(uint32_t)keyCode;
+ (void)triggerMouseWheelEvent:(int)distance;

@end

NS_ASSUME_NONNULL_END
