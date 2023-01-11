//
//  HIDController.m
//  KompleteSynthesia
//
//  Created by Till Toenshoff on 06.01.23.
//

#import "HIDController.h"

#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>

#import <IOKit/hid/IOHIDManager.h>
#import <IOKit/hid/IOHIDKeys.h>
#import <IOKit/IOKitLib.h>
#import <IOKit/usb/IOUSBLib.h>

#import <CoreGraphics/CoreGraphics.h>
#import <CoreImage/CoreImage.h>

const uint32_t kVendorID = 0x17CC;

// MK1 controllers.
const uint32_t kPID_S25MK1 = 0x1340;
const uint32_t kPID_S49MK1 = 0x1350;
const uint32_t kPID_S61MK1 = 0x1360;
const uint32_t kPID_S88MK1 = 0x1410;

// MK2 controllers.
const uint32_t kPID_S49MK2 = 0x1610;
const uint32_t kPID_S61MK2 = 0x1620;
const uint32_t kPID_S88MK2 = 0x1630;

const uint8_t kKompleteKontrolColorBlue = 0x2d;         // 011101
const uint8_t kKompleteKontrolColorLightBlue = 0x2f;    // 101111
const uint8_t kKompleteKontrolColorGreen = 0x1d;        // 011101
const uint8_t kKompleteKontrolColorLightGreen = 0x1f;   // 011111

const uint8_t kKompleteKontrolColorRed = 0x04;          // 000100
const uint8_t kKompleteKontrolColorOrange = 0x08;       // 001000
const uint8_t kKompleteKontrolColorYellow = 0x0e;       // 001110
const uint8_t kKompleteKontrolColorLightYellow = 0x12;  // 010010

const uint8_t kKompleteKontrolColorBrightWhite = 0xff;  // 111111

// Some funky colors.
const uint8_t kKompleteKontrolColorsSwoop[4] = { 0x04, 0x08, 0x0e, 0x12 };

// Quote from https://www.native-instruments.com/forum/threads/programming-the-guide-lights.320806/
// By @jasonbrent:
// Seems to be overall device state/Mode Sending just 0xa0 initializes the
// device and keyboard light control works.
const uint8_t kCommandInit = 0xA0;
const uint8_t kKompleteKontrolInit[] = { kCommandInit };

const uint8_t kCommandLightGuideUpdateMK1 = 0x82;
const uint8_t kCommandLightGuideUpdateMK2 = 0x81;
const size_t kKompleteKontrolLightGuideMessageSize = 80;
const size_t kKompleteKontrolLightGuideKeyMapSize = kKompleteKontrolLightGuideMessageSize - 1;

// This buttons lighting message likely is MK2 specific.
const uint8_t kCommandButtonLightsUpdate = 0x80;
const size_t kKompleteKontrolButtonsMessageSize = 80;
const size_t kKompleteKontrolButtonsMapSize = kKompleteKontrolButtonsMessageSize - 1;

// Button light indezes.
// FIXME: Many may be off - did not pay too much attention here - off by one.
const uint8_t kKompleteKontrolButtonIndexM = 0;
const uint8_t kKompleteKontrolButtonIndexS = 1;
const uint8_t kKompleteKontrolButtonIndexFunction1 = 2;
const uint8_t kKompleteKontrolButtonIndexFunction2 = 3;
const uint8_t kKompleteKontrolButtonIndexFunction3 = 4;
const uint8_t kKompleteKontrolButtonIndexFunction4 = 5;
const uint8_t kKompleteKontrolButtonIndexFunction5 = 6;
const uint8_t kKompleteKontrolButtonIndexFunction6 = 7;
const uint8_t kKompleteKontrolButtonIndexFunction7 = 8;
const uint8_t kKompleteKontrolButtonIndexFunction8 = 9;
const uint8_t kKompleteKontrolButtonIndexKnobLeft = 10;
const uint8_t kKompleteKontrolButtonIndexKnobUp = 11;
const uint8_t kKompleteKontrolButtonIndexKnobDown = 12;
const uint8_t kKompleteKontrolButtonIndexKnobRight = 13;
const uint8_t kKompleteKontrolButtonIndexScaleEdit = 15;
const uint8_t kKompleteKontrolButtonIndexArpEdit = 16;
const uint8_t kKompleteKontrolButtonIndexUndoRedo = 18;
const uint8_t kKompleteKontrolButtonIndexQuantize = 19;
const uint8_t kKompleteKontrolButtonIndexPattern = 21;
const uint8_t kKompleteKontrolButtonIndexPlay = 29;
const uint8_t kKompleteKontrolButtonIndexRecord = 30;
const uint8_t kKompleteKontrolButtonIndexStop = 31;
const uint8_t kKompleteKontrolButtonIndexBrowser = 35;
const uint8_t kKompleteKontrolButtonIndexSetup = 40;
const uint8_t kKompleteKontrolButtonIndexFixedVel = 41;
const uint8_t kKompleteKontrolButtonIndexStrip1 = 44;
const uint8_t kKompleteKontrolButtonIndexStrip10 = 54;
const uint8_t kKompleteKontrolButtonIndexStrip15 = 59;
const uint8_t kKompleteKontrolButtonIndexStrip20 = 64;
const uint8_t kKompleteKontrolButtonIndexStrip24 = 68;

const float kLightsSwoopDelay = 0.01;
const float kLightsSwooshDelay = 0.4;

const size_t kInputBufferSize = 64;

//#define DEBUG_HID_INPUT

void HIDInputCallback(void* context,
                      IOReturn result,
                      void* sender,
                      IOHIDReportType type,
                      uint32_t reportID,
                      uint8_t *report,
                      CFIndex reportLength)
{
    HIDController* controller = (__bridge HIDController*)context;
    
#ifdef DEBUG_HID_INPUT
    NSMutableString* hex = [NSMutableString string];
    for (int i=0; i < reportLength; i++) {
        [hex appendFormat:@"%02x ", report[i]];
    }
    NSLog(@"hid report: %@", hex);
#endif
    
    assert(report);
    if (reportLength > 8) {
        [controller receivedReport:report];
    }
}

@interface HIDController ()
@property (assign, nonatomic) unsigned char* keys;
@property (assign, nonatomic) unsigned char* buttons;
@end

@implementation HIDController {
    unsigned char lightGuideUpdateMessage[kKompleteKontrolLightGuideMessageSize];
    unsigned char buttonLightingUpdateMessage[kKompleteKontrolButtonsMessageSize];
    // FIXME: This may need double-buffering, not sure.
    unsigned char inputBuffer[kInputBufferSize];
    IOHIDDeviceRef device;
}

- (void)receivedReport:(unsigned char*)report
{
    if (report[2] == 0x10) {
        [_delegate receivedKeyEvent:KKBUTTON_PLAY];
        return;
    }
    if (report[6] == 0x44) {
        [_delegate receivedKeyEvent:KKBUTTON_DOWN];
        return;
    }
    if (report[6] == 0x24) {
        [_delegate receivedKeyEvent:KKBUTTON_UP];
        return;
    }
    if (report[6] == 0x14) {
        [_delegate receivedKeyEvent:KKBUTTON_LEFT];
        return;
    }
    if (report[6] == 0x84) {
        [_delegate receivedKeyEvent:KKBUTTON_RIGHT];
        return;
    }
    if (report[6] == 0x0C) {
        [_delegate receivedKeyEvent:KKBUTTON_ENTER];
        return;
    }
}

- (id)initWithDelegate:(id)delegate error:(NSError**)error
{
    self = [super init];
    if (self) {
        _delegate = delegate;
        device = [self detectKeyboardController:error];
        if (device == nil) {
            return nil;
        }
        if ([self initKeyboardController:error] == NO) {
            return nil;
        }
        lightGuideUpdateMessage[0] = kCommandLightGuideUpdateMK2;
        _keys = &lightGuideUpdateMessage[1];
        memset(_keys, 0, kKompleteKontrolLightGuideKeyMapSize);

        buttonLightingUpdateMessage[0] = kCommandButtonLightsUpdate;
        _buttons = &buttonLightingUpdateMessage[1];
        memset(_buttons, 0, kKompleteKontrolButtonsMapSize);
        _buttons[kKompleteKontrolButtonIndexPlay] = kKompleteKontrolColorBrightWhite;
        _buttons[kKompleteKontrolButtonIndexKnobDown] = kKompleteKontrolColorBrightWhite;
        _buttons[kKompleteKontrolButtonIndexKnobUp] = kKompleteKontrolColorBrightWhite;
        _buttons[kKompleteKontrolButtonIndexKnobLeft] = kKompleteKontrolColorBrightWhite;
        _buttons[kKompleteKontrolButtonIndexKnobRight] = kKompleteKontrolColorBrightWhite;
        
        if ([self updateButtonLightMap:error] == NO) {
            return nil;
        }
    }
    return self;
}

- (void)dealloc
{
    if (device != 0) {
        IOHIDDeviceClose(device, kIOHIDOptionsTypeNone);
    }
}

+ (NSString*)descriptionWithIOReturn:(IOReturn)code
{
    NSDictionary* descriptions = @{
        @(kIOReturnSuccess): @"Success",
        @(kIOReturnError): @"General error",
        @(kIOReturnNoMemory): @"Can't allocate memory",
        @(kIOReturnNoResources): @"Resource shortage",
        @(kIOReturnIPCError): @"Error during IPC",
        @(kIOReturnNoDevice): @"No such device",
        @(kIOReturnNotPrivileged): @"Privilege violation",
        @(kIOReturnBadArgument): @"Invalid argument",
        @(kIOReturnLockedRead): @"Device read locked",
        @(kIOReturnLockedWrite): @"Device write locked",
        @(kIOReturnExclusiveAccess): @"Exclusive access and device already open",
        @(kIOReturnBadMessageID): @"Sent/received messages had different 'msg_id'",
        @(kIOReturnUnsupported): @"Unsupported function",
        @(kIOReturnVMError):  @"VM failure",
        @(kIOReturnInternalError): @"Internal error",
        @(kIOReturnIOError): @"General I/O error",
        @(kIOReturnCannotLock): @"Can't acquire lock",
        @(kIOReturnNotOpen): @"Device not open",
        @(kIOReturnNotReadable): @"Read not supported",
        @(kIOReturnNotWritable): @"Write not supported",
        @(kIOReturnNotAligned): @"Alignment error",
        @(kIOReturnBadMedia): @"Media error",
        @(kIOReturnStillOpen): @"Device(s) still open",
        @(kIOReturnRLDError): @"RLD failure",
        @(kIOReturnDMAError): @"DMA failure",
        @(kIOReturnBusy): @"Device busy",
        @(kIOReturnTimeout): @"I/O timeout",
        @(kIOReturnOffline): @"Device offline",
        @(kIOReturnNotReady): @"Not ready",
        @(kIOReturnNotAttached): @"Device not attached",
        @(kIOReturnNoChannels): @"No DMA channels left",
        @(kIOReturnNoSpace): @"No space for data",
        @(kIOReturnPortExists): @"Port already exists",
        @(kIOReturnCannotWire): @"Can't wire down physical memory",
        @(kIOReturnNoInterrupt): @"No interrupt attached",
        @(kIOReturnNoFrames): @"No DMA frames enqueued",
        @(kIOReturnMessageTooLarge): @"Oversized message received on interrupt port",
        @(kIOReturnNotPermitted): @"Not permitted",
        @(kIOReturnNoPower): @"No power to device",
        @(kIOReturnNoMedia): @"Media not present",
        @(kIOReturnUnformattedMedia): @"Media not formatted",
        @(kIOReturnUnsupportedMode): @"No such mode",
        @(kIOReturnUnderrun): @"Data underrun",
        @(kIOReturnOverrun): @"Data overrun",
        @(kIOReturnDeviceError): @"The device is not working properly",
        @(kIOReturnNoCompletion): @"A completion routine is required",
        @(kIOReturnAborted): @"Operation aborted",
        @(kIOReturnNoBandwidth): @"Bus bandwidth would be exceeded",
        @(kIOReturnNotResponding): @"Device not responding",
        @(kIOReturnIsoTooOld): @"Isochronous I/O request for distant past",
        @(kIOReturnIsoTooNew): @"Isochronous I/O request for distant future",
        @(kIOReturnNotFound): @"Data was not found",
        @(kIOReturnInvalid): @"Invalid return value"
    };
    NSString* message = [descriptions objectForKey:@(code)];
    if (message == nil) {
        message = @"Unknown 'IOReturn' code";
    }
    return message;
}

+ (int)intProperty:(NSString*)property withDevice:(IOHIDDeviceRef)device
{
    CFTypeRef type = IOHIDDeviceGetProperty(device,  (__bridge CFStringRef)property);
    if (type && CFGetTypeID(type) == CFNumberGetTypeID()) {
        int32_t value;
        CFNumberGetValue((CFNumberRef)type, kCFNumberSInt32Type, &value);
        return value;
    }
    return 0;
}

+ (int)productIDWithDevice:(IOHIDDeviceRef)device
{
    return [HIDController intProperty:@(kIOHIDProductIDKey) withDevice:device];
}

+ (int)vendorIDWithDevice:(IOHIDDeviceRef)device
{
    return [HIDController intProperty:@(kIOHIDVendorIDKey) withDevice:device];
}

- (IOHIDDeviceRef)detectKeyboardController:(NSError**)error
{
    NSDictionary* supportedDevices = @{
        @(kPID_S25MK1): @{ @"keys": @(25), @"mk2": @NO, @"offset": @(-21) },
        @(kPID_S49MK1): @{ @"keys": @(49), @"mk2": @NO, @"offset": @(-36) },
        @(kPID_S61MK1): @{ @"keys": @(61), @"mk2": @NO, @"offset": @(-36) },
        @(kPID_S88MK1): @{ @"keys": @(88), @"mk2": @NO, @"offset": @(-21) },

        @(kPID_S49MK2): @{ @"keys": @(49), @"mk2": @YES, @"offset": @(-36) },
        @(kPID_S61MK2): @{ @"keys": @(61), @"mk2": @YES, @"offset": @(-36) },
        @(kPID_S88MK2): @{ @"keys": @(88), @"mk2": @YES, @"offset": @(-21) },
    };
    
    IOHIDManagerRef mgr = IOHIDManagerCreate(kCFAllocatorDefault, kIOHIDOptionsTypeNone);
    IOHIDManagerSetDeviceMatching(mgr, NULL);
    IOHIDManagerOpen(mgr, kIOHIDOptionsTypeNone);
   
    CFSetRef deviceSet = IOHIDManagerCopyDevices(mgr);
    CFIndex deviceCount = CFSetGetCount(deviceSet);
    IOHIDDeviceRef* devices = calloc(deviceCount, sizeof(IOHIDDeviceRef));
    CFSetGetValues(deviceSet, (const void **)devices);

    for (CFIndex i = 0; i < deviceCount; i++) {
        int vendor = [HIDController vendorIDWithDevice:devices[i]];
        if (vendor != kVendorID) {
            continue;
        }

        int product = [HIDController productIDWithDevice:devices[i]];

        for (NSNumber* key in [supportedDevices allKeys]) {
            if (product != key.intValue) {
                continue;
            }

            _keyCount = [supportedDevices[key][@"keys"] intValue];
            _mk2Controller = [supportedDevices[key][@"mk2"] boolValue];
            _keyOffset = [supportedDevices[key][@"offset"] intValue];
            lightGuideUpdateMessage[0] = _mk2Controller ? kCommandLightGuideUpdateMK2 : kCommandLightGuideUpdateMK1;

            _deviceName = [NSString stringWithFormat:@"Komplete Kontrol S%d MK%d", _keyCount, _mk2Controller ? 2 : 1];
            return devices[i];
        }
    }

    NSLog(@"No Native Instruments keyboard controller detected");
    if (error != nil) {
        NSDictionary *userInfo = @{
            NSLocalizedDescriptionKey : @"Keyboard Error: No Native Instruments controller detected",
            NSLocalizedRecoverySuggestionErrorKey : @"Make sure the keyboard is connected and powered on."
        };
        *error = [NSError errorWithDomain:[[NSBundle bundleForClass:[self class]] bundleIdentifier] code:-1 userInfo:userInfo];
    }

    free(devices);
    CFRelease(mgr);
    CFRelease(deviceSet);

    return NULL;
}

- (BOOL)initKeyboardController:(NSError**)error
{
    IOReturn ret = IOHIDDeviceOpen(device, kIOHIDOptionsTypeNone);
    if (ret != kIOReturnSuccess) {
        if (error != nil) {
            NSDictionary *userInfo = @{
                NSLocalizedDescriptionKey : [NSString stringWithFormat:@"Keyboard Error: %@",
                                             [HIDController descriptionWithIOReturn:ret]],
                NSLocalizedRecoverySuggestionErrorKey : @"This is entirely unexpected - how did you get here?"
            };
            *error = [NSError errorWithDomain:[[NSBundle bundleForClass:[self class]] bundleIdentifier] code:ret userInfo:userInfo];
        }
        return NO;
    }

    memset(inputBuffer, 0, kInputBufferSize);
    IOHIDDeviceScheduleWithRunLoop(device, CFRunLoopGetCurrent(), kCFRunLoopDefaultMode);
    IOHIDDeviceRegisterInputReportCallback(device, inputBuffer, sizeof(inputBuffer), HIDInputCallback, (__bridge void*)self);
        
    ret = IOHIDDeviceSetReport(device, kIOHIDReportTypeOutput, kKompleteKontrolInit[0], kKompleteKontrolInit, sizeof(kKompleteKontrolInit));
    if (ret != kIOReturnSuccess) {
        if (error != nil) {
            NSDictionary *userInfo = @{
                NSLocalizedDescriptionKey : [NSString stringWithFormat:@"Keyboard Error: %@",
                                             [HIDController descriptionWithIOReturn:ret]],
                NSLocalizedRecoverySuggestionErrorKey : @"This is entirely unexpected - how did you get here?"
            };
            *error = [NSError errorWithDomain:[[NSBundle bundleForClass:[self class]] bundleIdentifier] code:ret userInfo:userInfo];
        }
        return NO;
    }

    return YES;
}

- (NSString*)status
{
    return device != 0 ? _deviceName : @"disconnected";
}

- (BOOL)setReport:(const unsigned char*)report length:(size_t)length error:(NSError**)error
{
    IOReturn ret = IOHIDDeviceSetReport(device,
                                        kIOHIDReportTypeOutput,
                                        report[0],
                                        report,
                                        length);
    if (ret == kIOReturnSuccess) {
        return YES;
    }

    NSLog(@"couldnt set report");
    if (error != nil) {
        NSDictionary *userInfo = @{
            NSLocalizedDescriptionKey : [NSString stringWithFormat:@"Keyboard Error: %@",
                                         [HIDController descriptionWithIOReturn:ret]],
            NSLocalizedRecoverySuggestionErrorKey : @"Try switching it off and on again."
        };
        *error = [NSError errorWithDomain:[[NSBundle bundleForClass:[self class]] bundleIdentifier] code:ret userInfo:userInfo];
    }
    return NO;
}

- (BOOL)updateLightGuideMap:(NSError**)error
{
    return [self setReport:lightGuideUpdateMessage length:sizeof(lightGuideUpdateMessage) error:error];
}

- (BOOL)updateButtonLightMap:(NSError**)error
{
    return [self setReport:buttonLightingUpdateMessage length:sizeof(buttonLightingUpdateMessage) error:error];
}

- (void)lightKey:(int)key color:(unsigned char)color
{
    _keys[key] = color;
    [self updateLightGuideMap:nil];
}

- (void)lightsOff
{
    memset(_keys, 0, kKompleteKontrolLightGuideKeyMapSize);
    [self updateLightGuideMap:nil];
}

- (void)lightsSwoop
{
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        for (int key = 0;key < self.keyCount - 3;key++) {
            self.keys[key]   = kKompleteKontrolColorsSwoop[0];
            self.keys[key+1] = kKompleteKontrolColorsSwoop[1];
            self.keys[key+2] = kKompleteKontrolColorsSwoop[2];
            self.keys[key+3] = kKompleteKontrolColorsSwoop[3];
            [self updateLightGuideMap:nil];

            [NSThread sleepForTimeInterval:kLightsSwoopDelay];

            self.keys[key] = 0x0;
            self.keys[key+1] = 0x0;
            self.keys[key+2] = 0x0;
            self.keys[key+3] = 0x0;
            [self updateLightGuideMap:nil];
        }

        for (int key = self.keyCount - 3;key > 0;key--) {
            self.keys[key]   = kKompleteKontrolColorsSwoop[3];
            self.keys[key+1] = kKompleteKontrolColorsSwoop[2];
            self.keys[key+2] = kKompleteKontrolColorsSwoop[1];
            self.keys[key+3] = kKompleteKontrolColorsSwoop[0];
            [self updateLightGuideMap:nil];

            [NSThread sleepForTimeInterval:kLightsSwoopDelay];

            self.keys[key] = 0x0;
            self.keys[key+1] = 0x0;
            self.keys[key+2] = 0x0;
            self.keys[key+3] = 0x0;
            [self updateLightGuideMap:nil];
        }
    });
}

// FIXME: work in progress
- (void)lightsSwoosh
{
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        int midIndex = self.keyCount / 2;
#define LERP(a,b,t) (a + t * (b - a))
        const unsigned int steps = 255;
        for (unsigned int step = 0;step < steps;step++) {
            self.keys[midIndex] = LERP(0, 255, (float)step / steps);
            [self updateLightGuideMap:nil];
            [NSThread sleepForTimeInterval:kLightsSwooshDelay];
        }
    });
}

+ (NSImage*)KKImageFromNSImage:(NSImage*)image
{
    // Reduce the color information to an NSImage that is 16bitRBG (no alpha).
    NSImageRep* rep = [[image representations] objectAtIndex:0];
    const float width = rep.pixelsWide;
    const float height = rep.pixelsHigh;

    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = CGBitmapContextCreate(NULL, width, height, 5, width * 2, colorSpace, kCGImageAlphaNoneSkipFirst);
    CGColorSpaceRelease(colorSpace);

    CGInterpolationQuality quality = kCGInterpolationHigh;
    CGContextSetInterpolationQuality(context, quality);

    CGImageSourceRef source = CGImageSourceCreateWithData((CFDataRef)[image TIFFRepresentation], NULL);
    CGImageRef srcImage =  CGImageSourceCreateImageAtIndex(source, 0, NULL);

    CGContextDrawImage(context, CGRectMake(0, 0, width, height), srcImage);
    CGImageRelease(srcImage);
    CGImageRef dst = CGBitmapContextCreateImage(context);
    CGContextRelease(context);

    return [[NSImage alloc] initWithCGImage:dst size:NSMakeSize(width, height)];
}

// FIXME: This one doesn't work, yet!
- (BOOL)drawImage:(NSImage*)image screen:(uint8_t)screen x:(unsigned int)x y:(unsigned int)y error:(NSError**)error
{
    NSImage* bitmap = [HIDController KKImageFromNSImage:image];

    NSImageRep* rep = [[image representations] objectAtIndex:0];
    const float width = rep.pixelsWide;
    const float height = rep.pixelsHigh;

    NSMutableData* stream = [NSMutableData data];

    const unsigned char commandBlob1[] = { 0x84, 0x00, screen, 0x60, 0x00, 0x00, 0x00, 0x00 };
    [stream appendBytes:commandBlob1 length:sizeof(commandBlob1)];

    const uint16_t rect[] = { x, y, width, height };
    [stream appendBytes:&rect length:sizeof(rect)];

    const unsigned char commandBlob2[] = { 0x02, 0x00, 0x00, 0x00, 0x00, 0x00 };
    [stream appendBytes:commandBlob2 length:sizeof(commandBlob2)];
    
    CGImageRef source = [bitmap CGImageForProposedRect:nil context:nil hints:nil];
    CFDataRef raw = CGDataProviderCopyData(CGImageGetDataProvider(source));

    // Pretty sure that hardware expects 32bit boundary data.
    size_t imageSize = [(__bridge NSData*)raw length];
    uint16_t imageLongs = (imageSize >> 2);
    // FIXME(tillt): This may explode - watch your image sizes used for the transfer!
    assert((imageLongs << 2) == imageSize);
    [stream appendBytes:&imageLongs length:sizeof(imageLongs)];
    [stream appendData:(__bridge NSData*)raw];

    const unsigned char commandBlob3[] = { 0x02, 0x00, 0x00, 0x00, 0x03, 0x00, 0x00, 0x00, 0x40, 0x00, 0x00, 0x00 };
    [stream appendBytes:commandBlob3 length:sizeof(commandBlob3)];

    // FIXME: We are lacking the USB bulk transfer needed for making this work.
    
    return NO;
}

@end
