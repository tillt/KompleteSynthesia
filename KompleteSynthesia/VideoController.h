//
//  VideoController.h
//  KompleteSynthesia
//
//  Created by Till Toenshoff on 02.02.23.
//

#import <Foundation/Foundation.h>
#import <Cocoa/Cocoa.h>
#import <CoreGraphics/CoreGraphics.h>

NS_ASSUME_NONNULL_BEGIN

typedef struct {
    unsigned short width;
    unsigned short height;
    unsigned short* data;
} NIImage;

@class USBController;
@class LogViewController;

@interface VideoController : NSObject

@property (nonatomic, assign) int screenCount;
@property (nonatomic, assign) CGSize screenSize;
@property (nonatomic, assign) BOOL mirrorSynthesiaApplicationWindow;
@property (nonatomic, assign, readonly) float framesPerSecond;

@property (nonatomic, strong) NSTextField* volumeValue;

- (id)initWithLogViewController:(LogViewController*)lc error:(NSError**)error;
- (BOOL)reset:(NSError**)error;
- (void)teardown;
- (void)showOSD;

@end

NS_ASSUME_NONNULL_END
