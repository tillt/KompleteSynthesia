//
//  VideoController.h
//  KompleteSynthesia
//
//  Created by Till Toenshoff on 02.02.23.
//

#import <Foundation/Foundation.h>
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

- (id)initWithLogViewController:(LogViewController*)lc error:(NSError**)error;

- (BOOL)drawCGImage:(CGImageRef)image screen:(uint8_t)screen x:(unsigned int)x y:(unsigned int)y error:(NSError**)error;
- (BOOL)clearScreen:(uint8_t)screen error:(NSError**)error;

- (BOOL)reset:(NSError**)error;
- (void)stopMirroringAndWait:(BOOL)wait;

@end

NS_ASSUME_NONNULL_END
