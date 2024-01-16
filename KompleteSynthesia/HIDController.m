//
//  HIDController.m
//  KompleteSynthesia
//
//  Created by Till Toenshoff on 06.01.23.
//

#import "HIDController.h"

#include <stdatomic.h>

#import <AppKit/AppKit.h>
#import <Foundation/Foundation.h>

#import <IOKit/IOKitLib.h>
#import <IOKit/hid/IOHIDKeys.h>
#import <IOKit/hid/IOHIDManager.h>
#import <IOKit/usb/IOUSBLib.h>

#import "LogViewController.h"
#import "USBController.h"

/// Detects a Komplete Kontrol S-series controller. Listens for any incoming button presses and forwards them
/// to the delegate.

const uint8_t kKompleteKontrolKeyStateLightOff = 0x00;
const uint8_t kKompleteKontrolButtonLightOff = 0x00;

// We have 16 colors accross the rainbow, with 4 levels of intensity.
// Additionally there is white (sort of), again with 4 levels of intensity.
const size_t kKompleteKontrolColorCount = 17;
const size_t kKompleteKontrolColorIntensityLevelCount = 4;

const uint8_t kKompleteKontrolColorMask = 0xFC;
const uint8_t kKompleteKontrolIntensityMask = 0x03;

// Quote from https://www.native-instruments.com/forum/threads/programming-the-guide-lights.320806/
// By @jasonbrent:
// Seems to be overall device state/Mode Sending just 0xa0 initializes the
// device and keyboard light control works.
const uint8_t kCommandInit = 0xA0;
const uint8_t kKompleteKontrolInit[] = {kCommandInit, 0x00, 0x00};

// FIXME: This likely is not be enough to get the MK3 controller fully initialized. It is what
// FIXME: Komplete Kontrol sends on an 8 second interval to the controller.
const uint8_t kKompleteKontrolInitMK3[] = {0x06, 0x00, 0x00, 0x00, 0x93, 0x02, 0xcd, 0x01, 0x2c, 0x90};

const uint8_t kCommandLightGuideUpdateMK1 = 0x82;
const uint8_t kCommandLightGuideUpdateMK2 = 0x81;

// FIXME: This appears to be wrong for MK3 devices -- instead of lighting keys, we are
// FIXME: lighting the touchstrip with 0x81.
// const uint8_t kCommandLightGuideUpdateMK3 = 0x81;

// See https://github.com/tillt/KompleteSynthesia/discussions/29#discussioncomment-8089141
const uint8_t kKompleteKontrolLightGuidePrefixMK3[] = {0x93, 0x02, 0xCD, 0x01, 0x16, 0x92, 0xCD, 0x01,
                                                       0x51, 0x81, 0xCC, 0xFC, 0xDC, 0x00, 0x80};
const uint8_t kCommandLightGuideKeyCommandMK3 = 0x92;

const size_t kKompleteKontrolLightGuideMessageSizeMK3 = 403;

const size_t kKompleteKontrolLightGuideMessageSize = 250;
const size_t kKompleteKontrolLightGuideKeyMapSize = kKompleteKontrolLightGuideMessageSize - 1;

// This buttons lighting message likely is MK2 specific.
const uint8_t kCommandButtonLightsUpdate = 0x80;
const size_t kKompleteKontrolButtonsMessageSize = 80;
const size_t kKompleteKontrolButtonsMapSize = kKompleteKontrolButtonsMessageSize - 1;

// Funky defaults - users might hate me - but I like orange, eat it!
const uint8_t kKeyColorUnpressed = kKompleteKontrolKeyStateLightOff;
const uint8_t kKeyColorPressed = kKompleteKontrolColorLightOrange;

const float kLightsSwooshTick = 1.0f / 24.0;

const size_t kInputBufferSize = 64;

// This is just a very rough, initial approximation of the actual palette of the S-series
// MK2 controllers.
const unsigned char kMK2Palette[17][3] = {
    {0xFF, 0x00, 0x00}, // 0: red
    {0xFF, 0x3F, 0x00}, // 1:
    {0xFF, 0x7F, 0x00}, // 2: orange
    {0xFF, 0xCF, 0x00}, // 3: orange-yellow
    {0xFF, 0xFF, 0x00}, // 4: yellow
    {0x7F, 0xFF, 0x00}, // 5: green-yellow
    {0x00, 0xFF, 0x00}, // 6: green
    {0x00, 0xFF, 0x7F}, // 7:
    {0x00, 0xFF, 0xFF}, // 8:
    {0x00, 0x7F, 0xFF}, // 9:
    {0x00, 0x00, 0xFF}, // 10: blue
    {0x3F, 0x00, 0xFF}, // 11:
    {0x7F, 0x00, 0xFF}, // 12: purple
    {0xFF, 0x00, 0xFF}, // 13: pink
    {0xFF, 0x00, 0x7F}, // 14:
    {0xFF, 0x00, 0x3F}, // 15:
    {0xFF, 0xFF, 0xFF}  // 16: white
};

#define DEBUG_HID_INPUT

static void HIDDeviceRemovedCallback(void* context, IOReturn result, void* sender)
{
    HIDController* controller = (__bridge HIDController*)context;
    [controller deviceRemoved];
}

@interface HIDController ()
@property (assign, nonatomic) unsigned char* feedbackIntensityBuffer;
@end

@implementation HIDController {
    LogViewController* log;
    USBController* usb;

    size_t lightGuideUpdateMessageSize;
    unsigned char* lightGuideUpdateMessage;
    NSMutableData* lightGuideStreamMK3;

    unsigned char buttonLightingFeedback[kKompleteKontrolButtonsMessageSize];
    unsigned char buttonLightingUpdateMessage[kKompleteKontrolButtonsMessageSize];

    // FIXME: This may need double-buffering, not sure.
    unsigned char inputBuffer[kInputBufferSize];

    IOHIDDeviceRef device;

    short int lastVolumeKnobValue;

    dispatch_queue_t swooshQueue;
    atomic_int swooshActive;
}

+ (NSColor*)colorWithKeyState:(const unsigned char)keyState
{
    if (keyState < kKompleteKontrolColorIntensityLevelCount) {
        return [NSColor blackColor];
    }

    const int intensityShift = 5;
    const int intensityDivider = intensityShift + 3;
    const unsigned char colorIndex = ((keyState >> 2) - 1) % kKompleteKontrolColorCount;
    const unsigned char colorIntensity = (keyState & kKompleteKontrolIntensityMask) + intensityShift;

    // FIXME: This intensity simulation only really works for white - racist shit!
    return [NSColor colorWithRed:(((float)kMK2Palette[colorIndex][0] / 255.0f) * colorIntensity) / intensityDivider
                           green:(((float)kMK2Palette[colorIndex][1] / 255.0f) * colorIntensity) / intensityDivider
                            blue:(((float)kMK2Palette[colorIndex][2] / 255.0f) * colorIntensity) / intensityDivider
                           alpha:1.0f];
}

- (id)initWithUSBController:(USBController*)uc logViewController:(LogViewController*)lc;
{
    self = [super init];
    if (self) {
        log = lc;
        usb = uc;

        lastVolumeKnobValue = INTMAX_C(16);
        atomic_fetch_and(&swooshActive, 0);
        swooshQueue = dispatch_queue_create("KompleteSynthesia.SwooshQueue", NULL);
    }
    return self;
}

- (BOOL)setupWithError:(NSError**)error
{
    if (device != 0) {
        IOHIDDeviceUnscheduleFromRunLoop(device, CFRunLoopGetCurrent(), kCFRunLoopDefaultMode);
        IOHIDDeviceClose(device, kIOHIDOptionsTypeNone);
    }

    device = [self detectKeyboardController:error];
    if (device == nil) {
        return NO;
    }

    if ([self initKeyboardController:error] == NO) {
        return NO;
    }

    if (_mk == 3) {
        // TODO: Make this less magic. Consider abstracting away from this direct buffer access.
        _keys = lightGuideUpdateMessage + 4 + sizeof(kKompleteKontrolLightGuidePrefixMK3);
    } else {
        _keys = &lightGuideUpdateMessage[1];
    }

    [self lightKeysWithColor:kKeyColorUnpressed];

    _buttons = &buttonLightingUpdateMessage[1];
    _feedbackIntensityBuffer = &buttonLightingFeedback[1];

    memset(_buttons, 0, kKompleteKontrolButtonsMapSize);
    memset(_feedbackIntensityBuffer, 0, kKompleteKontrolButtonsMapSize);

    // Supported controls get illuminated.
    _buttons[kKompleteKontrolButtonIdPlay] = kKompleteKontrolColorWhite;
    _buttons[kKompleteKontrolButtonIdJogDown] = kKompleteKontrolColorWhite;
    _buttons[kKompleteKontrolButtonIdJogUp] = kKompleteKontrolColorWhite;
    _buttons[kKompleteKontrolButtonIdJogLeft] = kKompleteKontrolColorWhite;
    _buttons[kKompleteKontrolButtonIdJogRight] = kKompleteKontrolColorWhite;
    _buttons[kKompleteKontrolButtonIdPageLeft] = kKompleteKontrolColorWhite;
    _buttons[kKompleteKontrolButtonIdPageRight] = kKompleteKontrolColorWhite;
    _buttons[kKompleteKontrolButtonIdFunction1] = kKompleteKontrolColorOrange;
    _buttons[kKompleteKontrolButtonIdFunction2] = kKompleteKontrolColorWhite;
    _buttons[kKompleteKontrolButtonIdFunction3] = kKompleteKontrolColorWhite;
    _buttons[kKompleteKontrolButtonIdFunction4] = kKompleteKontrolColorWhite;
    _buttons[kKompleteKontrolButtonIdSetup] = kKompleteKontrolColorWhite;
    _buttons[kKompleteKontrolButtonIdClear] = kKompleteKontrolColorWhite;

    if ([self updateButtonLightMap:error] == NO) {
        return NO;
    }
    return YES;
}

- (void)dealloc
{
    if (device != 0) {
        IOHIDDeviceUnscheduleFromRunLoop(device, CFRunLoopGetCurrent(), kCFRunLoopDefaultMode);
        IOHIDDeviceClose(device, kIOHIDOptionsTypeNone);
    }
}

+ (int)intProperty:(NSString*)property withDevice:(IOHIDDeviceRef)device
{
    CFTypeRef type = IOHIDDeviceGetProperty(device, (__bridge CFStringRef)property);
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

// TODO: Make this MK1 compatible
- (unsigned char)keyColor:(int)note
{
    assert(_mk != 1);
    assert(note < kKompleteKontrolLightGuideKeyMapSize);
    return _keys[note];
}

static void setMk1ColorWithMk2ColorCode(unsigned char mk2ColorCode, unsigned char* destination)
{
    if (destination == NULL) {
        return;
    }
    if (mk2ColorCode == kKompleteKontrolKeyStateLightOff) {
        destination[0] = 0x00;
        destination[1] = 0x00;
        destination[2] = 0x00;
        return;
    }

    int index = (mk2ColorCode >> 2) - 1;
    assert(index <= 16);
    const int intensity = mk2ColorCode & 0x03;
    const int shift = 1 + (3 - intensity);

    destination[0] = kMK2Palette[index][0] >> shift;
    destination[1] = kMK2Palette[index][1] >> shift;
    destination[2] = kMK2Palette[index][2] >> shift;
}

- (void)deviceRemoved
{
    if (device != 0) {
        IOHIDDeviceClose(device, kIOHIDOptionsTypeNone);
    }
    device = 0;

    [_delegate deviceRemoved];
}

- (void)feedbackWithEvent:(const unsigned int)identifier
{
    _buttons[identifier] |= kKompleteKontrolIntensityBright;
    [self updateButtonLightMap:nil];
}

- (void)resetFeedback
{
    for (int i = 0; i < kKompleteKontrolButtonIdUnused1; i++) {
        _buttons[i] = (_buttons[i] & kKompleteKontrolColorMask) | _feedbackIntensityBuffer[i];
    }
    [self updateButtonLightMap:nil];
}

- (void)receivedReport:(unsigned char*)report length:(int)length
{
#ifdef DEBUG_HID_INPUT
    NSMutableString* hex = [NSMutableString string];
    for (int i = 0; i < length; i++) {
        [hex appendFormat:@"%02x ", report[i]];
    }
    NSLog(@"hid report: %@", hex);
    [log logLine:[NSString stringWithFormat:@"hid report: %@", hex]];
#endif

    if (report[0] != 0x01) {
        NSLog(@"ignoring report %02Xh", report[0]);
        return;
    }

    typedef struct {
        const unsigned char index;
        const unsigned char value;

        const unsigned int identifier;
    } EventReport;

    EventReport keyEvents[] = {
        {1, 0x10, kKompleteKontrolButtonIdFunction1}, {1, 0x20, kKompleteKontrolButtonIdFunction2},
        {1, 0x40, kKompleteKontrolButtonIdFunction3}, {1, 0x80, kKompleteKontrolButtonIdFunction4},
        {1, 0x01, kKompleteKontrolButtonIdFunction5}, {2, 0x10, kKompleteKontrolButtonIdPlay},
        {3, 0x80, kKompleteKontrolButtonIdPageLeft},  {3, 0x20, kKompleteKontrolButtonIdPageRight},
        {4, 0x04, kKompleteKontrolButtonIdScene},     {4, 0x20, kKompleteKontrolButtonIdClear},
        {5, 0x02, kKompleteKontrolButtonIdPlugin},    {5, 0x08, kKompleteKontrolButtonIdSetup},
        {6, 0x14, kKompleteKontrolButtonIdJogLeft},   {6, 0x24, kKompleteKontrolButtonIdJogUp},
        {6, 0x44, kKompleteKontrolButtonIdJogDown},   {6, 0x84, kKompleteKontrolButtonIdJogRight},
        {6, 0x0C, kKompleteKontrolButtonIdJogPress},
    };

    if (report[7] == 0x80) {
        const short int* newValue = (short int*)&report[10];
        if (lastVolumeKnobValue != INTMAX_C(16)) {
            int delta = *newValue - lastVolumeKnobValue;
            [_delegate receivedEvent:kKompleteKontrolButtonIdKnob1 value:delta];
        }
        lastVolumeKnobValue = *newValue;
        return;
    }

    // FIXME: This shouldnt be a loop - have a proper map instead.
    for (int i = 0; i < (sizeof(keyEvents) / sizeof(EventReport)); i++) {
        if (report[keyEvents[i].index] == keyEvents[i].value) {
            // Provide some feedback for most controls when the user activated them.
            if (keyEvents[i].identifier <= kKompleteKontrolButtonIdUnused1) {
                [self feedbackWithEvent:keyEvents[i].identifier];
            }

            [_delegate receivedEvent:keyEvents[i].identifier value:0];

            return;
        }
    }

    static int lastJogWheelValue = INT_MAX;
    int delta = lastJogWheelValue == INT_MAX ? 0 : report[30] - lastJogWheelValue;
    if (delta == 15) {
        delta = -1;
    } else if (delta == -15) {
        delta = 1;
    }
    if (delta != 0) {
        [_delegate receivedEvent:kKompleteKontrolButtonIdJogScroll value:delta];
    }
    lastJogWheelValue = report[30];

    // Reset feedback lighting as no such button was pressed anymore.
    [self resetFeedback];
}

static void HIDInputCallback(void* context,
                             IOReturn result,
                             void* sender,
                             IOHIDReportType type,
                             uint32_t reportID,
                             uint8_t* report,
                             CFIndex reportLength)
{
    HIDController* controller = (__bridge HIDController*)context;

    assert(report);
    if (reportLength > 8) {
        [controller receivedReport:report length:(int)reportLength];
    }
}

- (IOHIDDeviceRef)detectKeyboardController:(NSError**)error
{
    NSDictionary* supportedDevices = @{
        @(kPID_S25MK1) : @{@"keys" : @(25), @"mk" : @(1), @"offset" : @(-21)},
        @(kPID_S49MK1) : @{@"keys" : @(49), @"mk" : @(1), @"offset" : @(-36)},
        @(kPID_S61MK1) : @{@"keys" : @(61), @"mk" : @(1), @"offset" : @(-36)},
        @(kPID_S88MK1) : @{@"keys" : @(88), @"mk" : @(1), @"offset" : @(-21)},

        @(kPID_S49MK2) : @{@"keys" : @(49), @"mk" : @(2), @"offset" : @(-36)},
        @(kPID_S61MK2) : @{@"keys" : @(61), @"mk" : @(2), @"offset" : @(-36)},
        @(kPID_S88MK2) : @{@"keys" : @(88), @"mk" : @(2), @"offset" : @(-21)},

        @(kPID_S61MK3) : @{@"keys" : @(61), @"mk" : @(3), @"offset" : @(-36)},
        @(kPID_S88MK3) : @{@"keys" : @(88), @"mk" : @(3), @"offset" : @(-21)},
    };

#ifdef DEBUG_FAKE_CONTROLLER
    _keyCount = 88;
    _mk = 2;
    _keyOffset = -21;
    lightGuideUpdateMessage[0] = kCommandLightGuideUpdateMK2;
    // FIXME: This is likely wrong for MK1 devices!
    buttonLightingUpdateMessage[0] = kCommandButtonLightsUpdate;
    _deviceName = [NSString stringWithFormat:@"FAKE Komplete Kontrol S%d MK%d", _keyCount, _mk2Controller ? 2 : 1];
    return NULL;
#else
    IOHIDManagerRef mgr = IOHIDManagerCreate(kCFAllocatorDefault, kIOHIDOptionsTypeNone);
    IOHIDManagerSetDeviceMatching(mgr, NULL);
    IOHIDManagerOpen(mgr, kIOHIDOptionsTypeNone);

    CFSetRef deviceSet = IOHIDManagerCopyDevices(mgr);
    CFIndex deviceCount = CFSetGetCount(deviceSet);
    IOHIDDeviceRef* devices = calloc(deviceCount, sizeof(IOHIDDeviceRef));
    CFSetGetValues(deviceSet, (const void**)devices);

    for (CFIndex i = 0; i < deviceCount; i++) {
        int vendor = [HIDController vendorIDWithDevice:devices[i]];
        if (vendor != kVendorID_NativeInstruments) {
            continue;
        }

        int product = [HIDController productIDWithDevice:devices[i]];

        NSLog(@"Found a Native Instruments HID device: product-id is %xh", product);

        if ([supportedDevices objectForKey:@(product)] != nil) {
            _keyCount = [supportedDevices[@(product)][@"keys"] intValue];
            _mk = [supportedDevices[@(product)][@"mk"] intValue];
            _keyOffset = [supportedDevices[@(product)][@"offset"] intValue];

            lightGuideUpdateMessageSize =
                _mk == 3 ? kKompleteKontrolLightGuideMessageSizeMK3 : kKompleteKontrolLightGuideMessageSize;

            lightGuideStreamMK3 = nil;

            if (_mk == 3) {
                lightGuideStreamMK3 = [[NSMutableData alloc] initWithCapacity:lightGuideUpdateMessageSize];
                unsigned int length = (unsigned int)lightGuideUpdateMessageSize - 4;
                [lightGuideStreamMK3 appendBytes:&length length:sizeof(length)];
                [lightGuideStreamMK3 appendBytes:&kKompleteKontrolLightGuidePrefixMK3
                                          length:sizeof(kKompleteKontrolLightGuidePrefixMK3)];
                for (int i = 0; i < 128; i++) {
                    unsigned char entry[] = {0x92, 0x00, 0x00};
                    [lightGuideStreamMK3 appendBytes:entry length:sizeof(entry)];
                }
                lightGuideUpdateMessage = (unsigned char*)lightGuideStreamMK3.bytes;
            } else {
                lightGuideUpdateMessage = calloc(lightGuideUpdateMessageSize, 1);
                lightGuideUpdateMessage[0] = _mk == 1 ? kCommandLightGuideUpdateMK1 : kCommandLightGuideUpdateMK2;
            }

            // FIXME: This is likely wrong for MK1 devices!
            buttonLightingUpdateMessage[0] = kCommandButtonLightsUpdate;
            _deviceName =
                [NSString stringWithFormat:@"%@Kontrol S%d MK%d", _mk != 3 ? @"Komplete " : @"", _keyCount, _mk];
            return devices[i];
        }
    }

    NSLog(@"No Native Instruments keyboard controller HID device detected");
    if (error != nil || _mk == 0) {
        NSDictionary* userInfo = @{
            NSLocalizedDescriptionKey : @"No Native Instruments HID controller detected",
            NSLocalizedRecoverySuggestionErrorKey : @"Make sure the keyboard is connected and powered on."
        };
        if (error != nil) {
            *error = [NSError errorWithDomain:[[NSBundle bundleForClass:[self class]] bundleIdentifier]
                                         code:-1
                                     userInfo:userInfo];
        }
    }

    free(devices);
    CFRelease(mgr);
    CFRelease(deviceSet);
#endif
    return NULL;
}

- (BOOL)initKeyboardController:(NSError**)error
{
    IOHIDDeviceRegisterRemovalCallback(device, HIDDeviceRemovedCallback, (__bridge void*)self);

    // This would fail if we were not entitled to access USB devices - the result would be
    // "not permitted".
    IOReturn ret = IOHIDDeviceOpen(device, kIOHIDOptionsTypeNone);
    if (ret != kIOReturnSuccess) {
        if (error != nil) {
            NSDictionary* userInfo = @{
                NSLocalizedDescriptionKey :
                    [NSString stringWithFormat:@"Keyboard Error: %@", [USBController descriptionWithIOReturn:ret]],
                NSLocalizedRecoverySuggestionErrorKey : @"This is entirely unexpected - how did you get here?"
            };
            *error = [NSError errorWithDomain:[[NSBundle bundleForClass:[self class]] bundleIdentifier]
                                         code:ret
                                     userInfo:userInfo];
        }
        return NO;
    }

    memset(inputBuffer, 0, kInputBufferSize);
    IOHIDDeviceScheduleWithRunLoop(device, CFRunLoopGetCurrent(), kCFRunLoopDefaultMode);
    IOHIDDeviceRegisterInputReportCallback(device, inputBuffer, sizeof(inputBuffer), HIDInputCallback,
                                           (__bridge void*)self);

    const uint8_t* init = _mk == 3 ? kKompleteKontrolInitMK3 : kKompleteKontrolInit;
    size_t length = _mk == 3 ? sizeof(kKompleteKontrolInitMK3) : sizeof(kKompleteKontrolInit);
    ret = IOHIDDeviceSetReport(device, kIOHIDReportTypeOutput, *init, init, length);
    if (ret != kIOReturnSuccess) {
        if (error != nil) {
            NSDictionary* userInfo = @{
                NSLocalizedDescriptionKey :
                    [NSString stringWithFormat:@"Keyboard Error: %@", [USBController descriptionWithIOReturn:ret]],
                NSLocalizedRecoverySuggestionErrorKey : @"This is entirely unexpected - how did you get here?"
            };
            *error = [NSError errorWithDomain:[[NSBundle bundleForClass:[self class]] bundleIdentifier]
                                         code:ret
                                     userInfo:userInfo];
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
    if (device == NULL) {
        return NO;
    }
    IOReturn ret = IOHIDDeviceSetReport(device, kIOHIDReportTypeOutput, report[0], report, length);
    if (ret == kIOReturnSuccess) {
        return YES;
    }

    NSLog(@"couldnt set report");
    if (error != nil) {
        NSDictionary* userInfo = @{
            NSLocalizedDescriptionKey :
                [NSString stringWithFormat:@"Keyboard Error: %@", [USBController descriptionWithIOReturn:ret]],
            NSLocalizedRecoverySuggestionErrorKey : @"Try switching it off and on again."
        };
        *error = [NSError errorWithDomain:[[NSBundle bundleForClass:[self class]] bundleIdentifier]
                                     code:ret
                                 userInfo:userInfo];
    }
    return NO;
}

- (BOOL)updateLightGuideMap:(NSError**)error
{
    extern const double kTimeoutDelay;

    if (_mk == 3) {
        BOOL ret = [usb bulkWriteData:lightGuideStreamMK3 error:error];
        [usb waitForBulkTransfer:kTimeoutDelay];
        return ret;
    }
    return [self setReport:lightGuideUpdateMessage length:lightGuideUpdateMessageSize error:error];
}

- (void)lightKey:(int)key color:(unsigned char)color
{
    switch (_mk) {
        case 1:
            setMk1ColorWithMk2ColorCode(color, &_keys[key * 3]);
            break;
        case 2:
            _keys[key] = color;
            break;
        case 3:
            _keys[key * 3 + 0] = kCommandLightGuideKeyCommandMK3;
            _keys[key * 3 + 1] = key;
            _keys[key * 3 + 2] = color;
            break;
    }
    [self updateLightGuideMap:nil];
}

- (void)lightKeysWithColor:(unsigned char)color
{
    if (_keys == NULL) {
        return;
    }

    switch (_mk) {
        case 1:
            for (unsigned int i = 0; i < kKompleteKontrolLightGuideKeyMapSize; i += 3) {
                setMk1ColorWithMk2ColorCode(color, &_keys[i]);
            }
            break;
        case 2:
            memset(_keys, color, kKompleteKontrolLightGuideKeyMapSize);
            break;
        case 3:

            for (unsigned int i = 0; i < 128; i++) {
                _keys[i * 3 + 0] = kCommandLightGuideKeyCommandMK3;
                _keys[i * 3 + 1] = i;
                _keys[i * 3 + 2] = color;
            }
            break;
    }

    [self updateLightGuideMap:nil];
}

- (void)lightsOff
{
    [self lightKeysWithColor:kKompleteKontrolKeyStateLightOff];
}

static unsigned char dimmedKeyState(unsigned char keyState, BOOL lightUp, unsigned char endState)
{
    if (keyState == endState) {
        return endState;
    }

    const unsigned char keyColor = keyState & kKompleteKontrolColorMask;
    unsigned char keyIntensity = keyState & kKompleteKontrolIntensityMask;

    if (lightUp == NO && keyIntensity == 0) {
        return endState;
    }

    if (lightUp == NO) {
        --keyIntensity;
    } else {
        ++keyIntensity;
    }

    if (lightUp == YES && keyIntensity > kKompleteKontrolIntensityBright) {
        return endState;
    }

    return keyColor | keyIntensity;
}

- (BOOL)swooshIsActive
{
    return atomic_load(&swooshActive) != 0;
}

- (void)lightsSwooshTo:(unsigned char)unpressedKeyState
{
    if (atomic_load(&swooshActive) != 0) {
        return;
    }

    dispatch_async(swooshQueue, ^{
      atomic_fetch_or(&self->swooshActive, 1);
      const int midIndex = self.keyCount / 2;

      // Total number of ticks this animation will be using.
      const unsigned int rainbowDuration = 10;
      const unsigned int fadeInDuration = midIndex;
      const unsigned int fadeOutDuration = midIndex;
      const unsigned int totalDuration = rainbowDuration + fadeInDuration + fadeOutDuration;
      const unsigned long int lastTick = midIndex * totalDuration;
      // Animation tick to start fading into final state.
      const unsigned long int fadeOutTick = midIndex * (rainbowDuration + fadeInDuration);
      const unsigned long int rainbowTick = midIndex * fadeInDuration;

      const unsigned char rainbowIntensity = kKompleteKontrolIntensityMedium;

      // We start dark for groovy effects...
      [self lightsOff];

      // Depending on the users selection for the unpressed key state color, we need
      // to ramp up or down the intensity for the fade into the final key state color.
      const BOOL lightsUp = (unpressedKeyState & kKompleteKontrolIntensityMask) >= rainbowIntensity;

      // Animate!
      for (unsigned long int tick = 0; tick < lastTick; tick++) {
          const unsigned int keyIndex = tick % (midIndex + 1);
          if (tick >= fadeOutTick) {
              // Fade into final state.
              const unsigned int keysPerShade = 4;
              const unsigned long normalizedTick = tick - fadeOutTick;
              const unsigned long round = normalizedTick / midIndex;
              if (keyIndex < round * keysPerShade) {
                  self.keys[midIndex + keyIndex] =
                      dimmedKeyState(self.keys[midIndex + keyIndex], lightsUp, unpressedKeyState);
                  self.keys[midIndex - keyIndex] =
                      dimmedKeyState(self.keys[midIndex - keyIndex], lightsUp, unpressedKeyState);
              }
          }
          if (tick < rainbowTick) {
              // Fade into rainbow.
              const unsigned int keysPerShade = 4;
              const unsigned long round = tick / midIndex;
              if (keyIndex < round * keysPerShade) {
                  // FIXME: This is MK2 specific and needs and update for MK1!
                  self.keys[keyIndex] =
                      dimmedKeyState(self.keys[keyIndex], YES, (self.keys[keyIndex] & 0xfc) | rainbowIntensity);
                  // FIXME: This is MK2 specific and needs and update for MK1!
                  self.keys[(self.keyCount - 1) - keyIndex] =
                      dimmedKeyState(self.keys[(self.keyCount - 1) - keyIndex], YES,
                                     (self.keys[(self.keyCount - 1) - keyIndex] & 0xfc) | rainbowIntensity);
              }
          }
          // Don't touch lights that reached final state.
          if ((self.keys[keyIndex] != unpressedKeyState && tick < fadeOutTick) && self.keys[keyIndex] > 0x00) {
              // Rainbow scrolling.
              const unsigned long round = tick / midIndex;
              const unsigned int keysPerColor = 4;
              const unsigned int rollStepsPerRound = 4;
              const unsigned long phase = (keyIndex + (round * rollStepsPerRound)) / keysPerColor;
              // Exclude the last color in the palette, white.
              const unsigned int colorIndex = phase % (kKompleteKontrolColorCount - 1);
              unsigned int colorCode = (colorIndex + 1) << 2;
              colorCode = MIN(colorCode, kKompleteKontrolColorMask);
              const unsigned int intensity = self.keys[keyIndex] & kKompleteKontrolIntensityMask;
              // FIXME: This is MK2 specific and needs and update for MK1!
              self.keys[keyIndex] = colorCode | intensity;
              // FIXME: This is MK2 specific and needs and update for MK1!
              self.keys[(self.keyCount - 1) - keyIndex] = colorCode | intensity;
          }
          // Once we are starting a new round of shading, we can display the old one.
          if (keyIndex == 0) {
              [self updateLightGuideMap:nil];
              [NSThread sleepForTimeInterval:kLightsSwooshTick];
          }
      }
      // FIXME: This shouldnt be needed - but it is right now.
      // Assert final state on all keys - if the above left some garbage.
      [self lightKeysWithColor:unpressedKeyState];

      atomic_fetch_and(&self->swooshActive, 0);
    });
}

- (BOOL)updateButtonLightMap:(NSError**)error
{
    if (_mk == 3) {
        // FIXME: We dont know yet how to specifically update the button lighting.
        return true;
    }

    return [self setReport:buttonLightingUpdateMessage length:sizeof(buttonLightingUpdateMessage) error:error];
}

- (void)lightButton:(int)button color:(unsigned char)color
{
    if (_buttons == NULL || _feedbackIntensityBuffer == NULL) {
        return;
    }
    _feedbackIntensityBuffer[button] = color & kKompleteKontrolIntensityMask;
    _buttons[button] = color;
}

- (void)lightButtonsWithColor:(unsigned char)color
{
    if (_buttons == NULL) {
        return;
    }
    memset(_buttons, color, kKompleteKontrolButtonsMapSize);
    [self updateButtonLightMap:nil];
}

- (void)buttonsOff
{
    [self lightButtonsWithColor:kKompleteKontrolButtonLightOff];
}

@end
