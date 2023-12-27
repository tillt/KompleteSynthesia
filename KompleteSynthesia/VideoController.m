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

// Note that this is only used when mirroring isnt active.
const double kRefreshDelay = 1.0 / 40.0;

const double kTimeoutDelay = 0.1;

// FIXME: This smells too magic -- try to find that size from a system function!
const int kHeaderHeight = 26;

@implementation VideoController
{
    void* screenBuffer[2];
    void* imageConversionScaleBuffer;
    void* imageConversionTempBuffer;
    size_t imageConversionTempBufferSize;

    USBController* usb;
    LogViewController* log;

    atomic_int stopScreenUpdating;
    atomic_int screenUpdateActive;
    atomic_int mirror;

    dispatch_queue_t mirrorQueue;

    NSMutableData* stream;

    NSView* osdView;
    NSTimer* osdHideTimer;
    BOOL showValue;
}

- (id)initWithLogViewController:(LogViewController*)lc error:(NSError**)error
{
    self = [super init];
    if (self) {
        screenBuffer[0] = NULL;
        screenBuffer[1] = NULL;

        atomic_fetch_and(&stopScreenUpdating, 0);
        atomic_fetch_and(&screenUpdateActive, 0);
        atomic_fetch_and(&mirror, 0);

        imageConversionTempBuffer = NULL;
        imageConversionTempBufferSize = 0;
        imageConversionScaleBuffer = NULL;

        log = lc;

        usb = [[USBController alloc] initWithError:error];
        if (usb == nil) {
            return nil;
        }
        [log logLine:[NSString stringWithFormat:@"detected %@ USB device", usb.deviceName]];

        if (usb.mk > 1) {
            _screenCount = usb.mk == 2 ? 2 : 1;
            _screenSize = usb.mk == 2 ? CGSizeMake(480.0f, 272.0f) : CGSizeMake(1280.0f, 480.0f);

            // width * height * 2 (261120) + commands (36) * number-of-screens
            stream = [[NSMutableData alloc] initWithCapacity:_screenCount * ((_screenSize.width * 2 * _screenSize.height) + 36)];

            showValue = NO;

            for (int i=0;i < _screenCount;i++) {
                if (screenBuffer[i] == NULL) {
                    screenBuffer[i] = malloc(_screenSize.width * 2 * _screenSize.height);
                }
            }

            osdView = [[NSView alloc] initWithFrame:CGRectMake(0, 0, 180, 100)];
            osdView.wantsLayer = YES;
            osdView.layer.backgroundColor = [[NSColor blackColor] colorWithAlphaComponent:0.90].CGColor;

            NSTextField* tf = [[NSTextField alloc] initWithFrame:NSMakeRect(20.0,
                                                                50.0,
                                                                160,
                                                                32.0)];
            tf.editable = NO;
            tf.font = [NSFont systemFontOfSize:21.0];
            tf.drawsBackground = NO;
            tf.bordered = NO;
            tf.alignment = NSTextAlignmentLeft;
            tf.textColor = [NSColor tertiaryLabelColor];
            tf.stringValue = @"Volume";
            [osdView addSubview:tf];

            tf = [[NSTextField alloc] initWithFrame:NSMakeRect(20.0,
                                                                0.0,
                                                                160,
                                                                42.0)];
            tf.editable = NO;
            tf.font = [NSFont systemFontOfSize:31.0];
            tf.drawsBackground = NO;
            tf.bordered = NO;
            tf.alignment = NSTextAlignmentLeft;
            tf.textColor = [NSColor secondaryLabelColor];
            [osdView addSubview:tf];
            _volumeValue = tf;

            mirrorQueue = dispatch_queue_create("KompleteSynthesia.MirrorQueue", NULL);
        } else {
            return nil;
        }
    }
    return self;
}

- (void)setMirrorSynthesiaApplicationWindow:(BOOL)mirrorSynthesiaApplicationWindow
{
    if (mirrorSynthesiaApplicationWindow == _mirrorSynthesiaApplicationWindow) {
        return;
    }
    if (mirrorSynthesiaApplicationWindow) {
        atomic_fetch_or(&mirror, 1);
    } else {
        atomic_fetch_and(&mirror, 0);
    }
    _mirrorSynthesiaApplicationWindow = mirrorSynthesiaApplicationWindow;
}

- (void)stopUpdatingAndWait:(BOOL)wait
{
    atomic_fetch_or(&stopScreenUpdating, 1);

    if (wait == YES) {
        while (atomic_load(&screenUpdateActive) != 0) {
            [NSThread sleepForTimeInterval:0.01f];
        };
    }
}

- (void)teardown
{
    [self stopUpdatingAndWait:YES];
    [self clearScreen:0 error:nil];
    if (_screenCount > 1) {
        [self clearScreen:1 error:nil];
    }
}

- (CGImageRef)renderOverlayOntoCGImage:(CGImageRef)original
{
    CGRect originalRect = CGRectMake(0, 0, CGImageGetWidth(original), CGImageGetHeight(original));

    // FIXME: Allow for pre-allocated data.
    CGContextRef context = CGBitmapContextCreate(NULL,
                                                 originalRect.size.width,
                                                 originalRect.size.height,
                                                 CGImageGetBitsPerComponent(original),
                                                 CGImageGetBytesPerRow(original),
                                                 CGImageGetColorSpace(original),
                                                 CGImageGetAlphaInfo(original));

    // Draw original
    CGContextDrawImage(context, originalRect, original);
    NSGraphicsContext* c = [NSGraphicsContext graphicsContextWithCGContext:context flipped:NO];
    if (showValue) {
        // We are drawing UI elements in a non main thread, that would normally cause issues.
        // Hope is that given this entirely virtual element, things are not that bad. It stinks
        // still.
        [osdView displayRectIgnoringOpacity:osdView.frame inContext:c];
    }
    CGImageRef image = CGBitmapContextCreateImage(c.CGContext);
    CGContextRelease(context);
    return image;
}

- (BOOL)startUpdating
{
    atomic_fetch_and(&stopScreenUpdating, 0);

    const int windowNumber = [SynthesiaController synthesiaWindowNumber];
    if (windowNumber == 0) {
        NSLog(@"synthesia window not found");
        return NO;
    }

    [log logLine:@"starting screen update loop"];

    dispatch_async(mirrorQueue, ^{
        NSImage* image = [NSImage imageNamed:[NSString stringWithFormat:@"ScreenMK%d", self->usb.mk]];
        assert(image);
        CGImageRef cgi = [image CGImageForProposedRect:NULL context:NULL hints:NULL];

        [self beginEncoding];

        [self encodeCGImage:cgi
                     screen:0
                          x:0
                          y:0
           skipHeaderHeight:0];

        if (_screenCount > 1) {
            [self encodeCGImage:cgi
                         screen:1
                              x:0
                              y:0
               skipHeaderHeight:0];
        }

        if (![self sendStreamWithError:nil]) {
            return;
        }

        atomic_fetch_or(&self->screenUpdateActive, 1);

        static mach_timebase_info_data_t sTimebaseInfo;
        mach_timebase_info(&sTimebaseInfo);
        uint64_t lastTime = mach_absolute_time();

        while(atomic_load(&self->stopScreenUpdating) == 0) {
            // Reset the output stream.
            [self beginEncoding];

            if (atomic_load(&self->mirror) == 1) {
                CGImageRef original = CGWindowListCreateImage(CGRectNull,
                                                              kCGWindowListOptionIncludingWindow,
                                                              windowNumber,
                                                              kCGWindowImageBoundsIgnoreFraming);
                if (original == nil) {
                    NSLog(@"window disappeared, lets stop this");
                    goto doneUpdating;
                }

                CGImageRef overlayed = [self renderOverlayOntoCGImage:original];
                CGImageRelease(original);

                [self encodeCGImage:overlayed
                             screen:0
                                  x:0
                                  y:0
                   skipHeaderHeight:kHeaderHeight];
                CGImageRelease(overlayed);

                if (![self sendStreamWithError:nil]) {
                    NSLog(@"usb transfer failed right away, lets stop this");
                    goto doneUpdating;
                }
            }

            uint64_t currentTime = mach_absolute_time();
            uint64_t elapsedNano = (currentTime - lastTime) * sTimebaseInfo.numer / sTimebaseInfo.denom;

            self->_framesPerSecond = 1000000000.0 / (float)elapsedNano;

            lastTime = currentTime;
        };

    doneUpdating:
        [self clearScreen:0 error:nil];

        atomic_fetch_and(&self->screenUpdateActive, 0);
        
        dispatch_async(dispatch_get_main_queue(), ^{
            [self->log logLine:@"stopped screen update loop"];
        });
    });
    
    return YES;
}

- (void)showOSD
{
    if (osdHideTimer != nil) {
        [osdHideTimer invalidate];
    }
    showValue = YES;
    osdHideTimer = [NSTimer scheduledTimerWithTimeInterval:5.0 repeats:NO block:^(NSTimer* timer){
        self->showValue = NO;
    }];
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

    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        [self stopUpdatingAndWait:YES];

        dispatch_async(dispatch_get_main_queue(), ^{
            [self startUpdating];
        });
    });

    return YES;
}

// Convert a CGImage to a NIImage, adjusting the color depth and the size, if needed.
- (void)NIImageFromCGImage:(CGImageRef)source 
               destination:(NIImage*)destination
          skipHeaderHeight:(const int)headerHeight
{
    const unsigned long width = CGImageGetWidth(source);
    const unsigned long height = CGImageGetHeight(source);
    const size_t bytesPerRow = CGImageGetBytesPerRow(source);
    const size_t size = bytesPerRow * height;
    
    // We make use of the vImage tempBuffer feature, allowing us to provide an operational
    // buffer for conversion and scaling. The source of our operation is resizeable during
    // runtime and thus we need to make sure the tempBuffer is properly sized.
    if (imageConversionTempBufferSize < size) {
        if (imageConversionTempBuffer != NULL) {
            free(imageConversionTempBuffer);
        }
        if (imageConversionScaleBuffer != NULL) {
            free(imageConversionScaleBuffer);
        }
        imageConversionTempBufferSize = size;
        imageConversionTempBuffer = malloc(size);
        imageConversionScaleBuffer = malloc(bytesPerRow * _screenSize.height);
    }

    CFDataRef raw = CGDataProviderCopyData(CGImageGetDataProvider(source));
    
    vImage_Buffer sourceBuffer = {
        (void*)CFDataGetBytePtr(raw),
        height,
        width,
        bytesPerRow
    };

    vImage_CGImageFormat sourceFormat = {
        .bitsPerComponent = (unsigned int)CGImageGetBitsPerComponent(source),
        .bitsPerPixel = (unsigned int)CGImageGetBitsPerPixel(source),
        .bitmapInfo = CGImageGetBitmapInfo(source),
        .colorSpace = NULL,
    };

    // We want to skip the header part of the application window, that does not add any
    // value in the mirrored image.
    sourceBuffer.data += headerHeight * sourceBuffer.rowBytes;
    sourceBuffer.height -= headerHeight;

    // If the image is too big, resize it.
    if (width > _screenSize.width || height > _screenSize.height ) {
        vImage_Buffer resizedBuffer = {
            imageConversionScaleBuffer,
            destination->height,
            destination->width,
            destination->width * (((unsigned int)CGImageGetBitsPerPixel(source)) >> 3)
        };

        vImageScale_ARGB8888(&sourceBuffer, 
                             &resizedBuffer,
                             imageConversionTempBuffer,
                             kvImageDoNotTile);

        sourceBuffer.data = imageConversionScaleBuffer;
        sourceBuffer.height = resizedBuffer.height;
        sourceBuffer.width = resizedBuffer.width;
        sourceBuffer.rowBytes = resizedBuffer.rowBytes;
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
                                                                           kvImageDoNotTile,
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
                           imageConversionTempBuffer,
                           kvImageDoNotTile);

    vImageConverter_Release(converter);

    CFRelease(raw);
}

- (void)beginEncoding
{
    stream.length = 0;
}

- (void)encodeImage:(NIImage*)image screen:(uint8_t)screen x:(unsigned int)x y:(unsigned int)y
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

    assert(imageLongs == (image->width * image->height) / 2);
    // FIXME: This may explode - watch your image sizes used for the transfer!
    assert((imageLongs << 2) == imageSize);
    uint16_t writtenLongs = htons(imageLongs);
    [stream appendBytes:&writtenLongs length:sizeof(writtenLongs)];
    [stream appendBytes:image->data length:imageSize];

    const unsigned char commandBlob3[] = { 0x02, 0x00, 0x00, 0x00, 0x03, 0x00, 0x00, 0x00, 0x40, 0x00, 0x00, 0x00 };
    [stream appendBytes:commandBlob3 length:sizeof(commandBlob3)];
}

- (BOOL)asyncSendStreamWithError:(NSError**)error
{
    return [usb bulkWriteData:stream error:error];
}

- (BOOL)sendStreamWithError:(NSError**)error
{
    BOOL ret = [usb bulkWriteData:stream error:error];

    // TODO: Use double-buffering so we can grab a new screen while the last one is being transfered.

    [usb waitForBulkTransfer:kTimeoutDelay];

    return ret;
}

- (void)encodeCGImage:(CGImageRef)image
               screen:(const uint8_t)screen
                    x:(const unsigned int)x
                    y:(const unsigned int)y
     skipHeaderHeight:(const unsigned int)headerHeight
{
    const unsigned int width = MIN(CGImageGetWidth(image), _screenSize.width);
    const unsigned int height = MIN(CGImageGetHeight(image), _screenSize.height);

    NIImage convertedImage = {
        width,
        height,
        screenBuffer[screen]
    };

    [self NIImageFromCGImage:image
                 destination:&convertedImage
            skipHeaderHeight:headerHeight];

    [self encodeImage:&convertedImage screen:screen x:x y:y];
}

- (BOOL)clearScreen:(uint8_t)screen error:(NSError**)error
{
    memset(screenBuffer[screen], 0, _screenSize.width * _screenSize.height * 2);
    NIImage image = {
        _screenSize.width,
        _screenSize.height,
        screenBuffer[screen]
    };
    [self beginEncoding];
    [self encodeImage:&image screen:screen x:0 y:0];
    return [self sendStreamWithError:error];
}

@end
