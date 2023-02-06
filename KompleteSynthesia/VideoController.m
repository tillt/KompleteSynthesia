//
//  VideoController.m
//  KompleteSynthesia
//
//  Created by Till Toenshoff on 02.02.23.
//

#import "VideoController.h"

#include <stdatomic.h>

#import <Accelerate/Accelerate.h>
#import <CoreImage/CoreImage.h>

#import <AppKit/AppKit.h>

#import "USBController.h"
#import "SynthesiaController.h"
#import "LogViewController.h"

/// Makes use of a detected Synthesia instance by streaming the application window onto the first LCD screen of a
/// detected Komplete Kontrol S-series USB controller.

const double kRefreshDelay = 1.0 / 40.0;
const int kHeaderHeight = 26;

@implementation VideoController
{
    void* screenBuffer[2];
    void* resizeBuffer;
    void* tempBuffer;
    USBController* usb;
    LogViewController* log;
    atomic_int stopMirroring;
    atomic_int mirrorActive;
    NSMutableData* stream;
}

- (id)initWithLogViewController:(LogViewController*)lc error:(NSError**)error
{
    self = [super init];
    if (self) {
        screenBuffer[0] = NULL;
        screenBuffer[1] = NULL;
        atomic_fetch_and(&stopMirroring, 0);
        atomic_fetch_and(&mirrorActive, 0);
        
        log = lc;

        usb = [[USBController alloc] initWithError:error];
        if (usb == nil) {
            return nil;
        }
        [log logLine:[NSString stringWithFormat:@"detected %@ USB device", usb.deviceName]];

        if (usb.mk2Controller == YES) {
            _screenCount = 2;
            _screenSize = CGSizeMake(480.0f, 272.0f);
            tempBuffer = malloc(_screenSize.width * 4 * _screenSize.height);
            resizeBuffer = malloc(_screenSize.width * 4 * _screenSize.height);
            // width * height * 2 (261120) + commands (36)
            stream = [[NSMutableData alloc] initWithCapacity:(_screenSize.width * 2 * _screenSize.height) + 36];
            
            for (int i=0;i < _screenCount;i++) {
                if (screenBuffer[i] == NULL) {
                    screenBuffer[i] = malloc(_screenSize.width * 2 * _screenSize.height);
                }
            }
        } else {
            return nil;
        }

        [self reset:nil];
    }
    return self;
}

- (void)stopMirroringAndWait:(BOOL)wait
{
    atomic_fetch_or(&stopMirroring, 1);

    if (wait == YES) {
        while (mirrorActive != 0) {
            [NSThread sleepForTimeInterval:0.01f];
        };
    }
}

- (void)teardown
{
    [self stopMirroringAndWait:YES];

    [self clearScreen:0 error:nil];
    [self clearScreen:1 error:nil];

    [usb teardown];
}

- (BOOL)startMirroring
{
    atomic_fetch_and(&stopMirroring, 0);

    if ([self clearScreen:0 error:nil] == NO) {
        return NO;
    }

    int windowNumber = [SynthesiaController synthesiaWindowNumber];
    if (windowNumber == 0) {
        NSLog(@"synthesia window not found");
        return NO;
    }

    [log logLine:@"starting window mirroring"];

    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        atomic_fetch_or(&mirrorActive, 1);

        while(stopMirroring == 0) {
            CGImageRef original = CGWindowListCreateImage(CGRectNull, kCGWindowListOptionIncludingWindow, windowNumber, kCGWindowImageBoundsIgnoreFraming);
            if (original == nil) {
                NSLog(@"window disappeared, lets stop this");
                goto doneMirroring;
            }
            [self drawCGImage:original screen:0 x:0 y:0 error:nil];
            CGImageRelease(original);
            
            // FIXME: We should try to find something more reliable than a fixed delay...
            // possibly tie it to the v-refresh of the host machine.
            [NSThread sleepForTimeInterval:kRefreshDelay];
        };

    doneMirroring:
        [self clearScreen:0 error:nil];
        atomic_fetch_and(&mirrorActive, 0);
    });
    
    return YES;
}

- (BOOL)reset:(NSError**)error
{
    if ([SynthesiaController synthesiaRunning] == NO) {
        [log logLine:@"we need synthesia running for grabbing its video"];

        if (error != nil) {
            NSDictionary *userInfo = @{
                NSLocalizedDescriptionKey : @"Can't mirror application window",
                NSLocalizedRecoverySuggestionErrorKey : @"Make sure Synthesia.app is running."
            };
            *error = [NSError errorWithDomain:[[NSBundle bundleForClass:[self class]] bundleIdentifier]
                                         code:-1
                                     userInfo:userInfo];
        }
        return NO;
    }
    
    if (usb.connected == NO) {
        NSLog(@"we need the USB device to be accessable");
        return NO;
    }
    
    NSImage* image = [NSImage imageNamed:@"ScreenOne"];
    CGImageRef cgi = [image CGImageForProposedRect:NULL context:NULL hints:NULL];
    [self drawCGImage:cgi screen:1 x:0 y:0 error:nil];

    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        [self stopMirroringAndWait:YES];

        dispatch_async(dispatch_get_main_queue(), ^{
            [self startMirroring];
        });
    });

    return YES;
}

// Convert a CGImage to a NIImage, adjusting the color depth and the size, if needed.
- (void)NIImageFromCGImage:(CGImageRef)source destination:(NIImage*)destination
{
    unsigned long width = CGImageGetWidth(source);
    unsigned long height = CGImageGetHeight(source);
    
    CFDataRef raw = CGDataProviderCopyData(CGImageGetDataProvider(source));
    
    vImage_Buffer sourceBuffer = {
        (void*)CFDataGetBytePtr(raw),
        height,
        width,
        (((width + 31) >> 5) << 5) * 4      // Stride is remains for chunks of 32 pixels.
    };

    vImage_CGImageFormat sourceFormat = {
        .bitsPerComponent = (unsigned int)CGImageGetBitsPerComponent(source),
        .bitsPerPixel = (unsigned int)CGImageGetBitsPerPixel(source),
        .bitmapInfo = CGImageGetBitmapInfo(source),
        .colorSpace = NULL,
    };

    // If the image is too big, resize it.
    if (width > _screenSize.width || height > _screenSize.height ) {
        // We want to skip the header part of the application window, that does not add any
        // value in the mirrored image.
        sourceBuffer.data += kHeaderHeight * sourceBuffer.rowBytes;
        sourceBuffer.height -= kHeaderHeight;

        vImage_Buffer resizedBuffer = {
            resizeBuffer,
            _screenSize.height,
            _screenSize.width,
            _screenSize.width * 4
        };

        vImageScale_ARGB8888(&sourceBuffer, &resizedBuffer, nil, kvImageHighQualityResampling);

        sourceBuffer.data = resizeBuffer;
        sourceBuffer.height = _screenSize.height;
        sourceBuffer.width = _screenSize.width;
        sourceBuffer.rowBytes = _screenSize.width * 4;
    }

    vImage_CGImageFormat screenFormat = {
        .bitsPerComponent = 5,
        .bitsPerPixel = 16,
        .bitmapInfo = kCGBitmapByteOrder16Big | kCGImageAlphaNone,
        .colorSpace = NULL,
    };

    vImage_Error err = kvImageNoError;
    vImageConverterRef converter = vImageConverter_CreateWithCGImageFormat(&sourceFormat,
                                                                           &screenFormat,
                                                                           NULL,
                                                                           kvImageNoFlags,
                                                                           &err);
    vImage_Buffer destinationBuffer = {
        destination->data,
        destination->height,
        destination->width,
        destination->width * 2
    };

    vImageConvert_AnyToAny(converter,
                           &sourceBuffer,
                           &destinationBuffer,
                           tempBuffer,
                           kvImageNoFlags);

    vImageConverter_Release(converter);

    CFRelease(raw);
}

- (BOOL)drawNIImage:(NIImage*)image screen:(uint8_t)screen x:(unsigned int)x y:(unsigned int)y error:(NSError**)error
{
    const unsigned char commandBlob1[] = { 0x84, 0x00, screen, 0x60, 0x00, 0x00, 0x00, 0x00 };
    [stream appendBytes:commandBlob1 length:sizeof(commandBlob1)];

    const uint16_t rect[] = { htons(x), htons(y), htons(image->width), htons(image->height) };
    [stream appendBytes:&rect length:sizeof(rect)];

    const unsigned char commandBlob2[] = { 0x02, 0x00, 0x00, 0x00, 0x00, 0x00 };
    [stream appendBytes:commandBlob2 length:sizeof(commandBlob2)];

    // Pretty sure that hardware expects 32bit boundary data.
    size_t imageSize = image->width * image->height * 2;
    uint16_t imageLongs = (imageSize >> 2);

    assert(imageLongs == (image->width * image->height)/2);
    // FIXME: This may explode - watch your image sizes used for the transfer!
    assert((imageLongs << 2) == imageSize);
    uint16_t writtenLongs = htons(imageLongs);
    [stream appendBytes:&writtenLongs length:sizeof(writtenLongs)];
    [stream appendBytes:image->data length:imageSize];

    const unsigned char commandBlob3[] = { 0x02, 0x00, 0x00, 0x00, 0x03, 0x00, 0x00, 0x00, 0x40, 0x00, 0x00, 0x00 };
    [stream appendBytes:commandBlob3 length:sizeof(commandBlob3)];

    BOOL ret = [usb bulkWriteData:stream endpoint:3 error:error];

    stream.length = 0;

    return ret;
}

- (BOOL)drawCGImage:(CGImageRef)image screen:(uint8_t)screen x:(unsigned int)x y:(unsigned int)y error:(NSError**)error
{
    const unsigned int width = MIN(CGImageGetWidth(image), _screenSize.width);
    const unsigned int height = MIN(CGImageGetHeight(image), _screenSize.height);
    NIImage convertedImage = {
        width,
        height,
        screenBuffer[screen]
    };
    [self NIImageFromCGImage:image destination:&convertedImage];
    return [self drawNIImage:&convertedImage screen:screen x:x y:y error:error];
}

- (BOOL)clearScreen:(uint8_t)screen error:(NSError**)error
{
    memset(screenBuffer[screen], 0, _screenSize.width * _screenSize.height * 2);
    NIImage image = {
        _screenSize.width,
        _screenSize.height,
        screenBuffer[screen]
    };
    return [self drawNIImage:&image screen:screen x:0 y:0 error:error];
}

@end
