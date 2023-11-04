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
+ (BOOL)activateSynthesia;
+ (void)runSynthesiaWithCompletion:(void(^)(void))completion;
+ (int)synthesiaWindowNumber;
+ (void)triggerVirtualKeyEvents:(CGKeyCode)keyCode;
+ (void)triggerVirtualAuxKeyEvents:(uint32_t)keyCode;
+ (void)triggerVirtualMouseWheelEvent:(int)distance;

+ (NSString*)status;

- (id)initWithLogViewController:(LogViewController*)logViewController delegate:(id)delegate;

- (BOOL)assertMultiDeviceConfig:(NSError**)error message:(NSString*_Nullable *_Nullable)message;
- (BOOL)cachedAssertSynthesiaConfiguration;

@end

NS_ASSUME_NONNULL_END
