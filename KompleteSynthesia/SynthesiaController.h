//
//  SynthesiaController.h
//  KompleteSynthesia
//
//  Created by Till Toenshoff on 13.01.23.
//

#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

NS_ASSUME_NONNULL_BEGIN

@protocol SynthesiaControllerDelegate <NSObject>
- (void)synthesiaStateUpdate:(NSString*)status;
@end

@interface SynthesiaController : NSObject

@property (nonatomic, weak) id<SynthesiaControllerDelegate> delegate;

+ (BOOL)synthesiaRunning;
+ (BOOL)synthesiaHasFocus;
+ (void)triggerVirtualKeyEvents:(CGKeyCode)keyCode;
+ (NSString*)status;

- (id)initWithDelegate:(id)delegate;

@end

NS_ASSUME_NONNULL_END
