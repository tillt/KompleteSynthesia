//
//  SynthesiaController.h
//  KompleteSynthesia
//
//  Created by Till Toenshoff on 13.01.23.
//

#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

NS_ASSUME_NONNULL_BEGIN

@class LogViewController;

@protocol SynthesiaControllerDelegate <NSObject>
- (void)synthesiaStateUpdate:(NSString*)status;
@end

@interface SynthesiaController : NSObject <NSXMLParserDelegate>

@property (nonatomic, weak) id<SynthesiaControllerDelegate> delegate;

+ (BOOL)synthesiaRunning;
+ (BOOL)synthesiaHasFocus;
+ (void)triggerVirtualKeyEvents:(CGKeyCode)keyCode;
+ (void)triggerVirtualMouseWheelEvent:(int)distance;

+ (NSString*)status;

- (id)initWithLogViewController:(LogViewController*)logViewController delegate:(id)delegate error:(NSError**)error;
- (BOOL)assertMultiDeviceConfig:(NSError**)error;

@end

NS_ASSUME_NONNULL_END
