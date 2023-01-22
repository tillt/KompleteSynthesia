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

#import "USBController.h"

/// Detects a Komplete Kontrol S-series controller. Listens for any incoming button presses and forwards them
/// to the delegate.

const uint8_t kKompleteKontrolColorBlue = 0x2d;         // 011101
const uint8_t kKompleteKontrolColorLightBlue = 0x2e;
const uint8_t kKompleteKontrolColorBrightBlue = 0x2f;   // 101111
const uint8_t kKompleteKontrolColorGreen = 0x1d;        // 011101
const uint8_t kKompleteKontrolColorLightGreen = 0x1e;
const uint8_t kKompleteKontrolColorBrightGreen = 0x1f;  // 011111

const uint8_t kKompleteKontrolColorRed = 0x04;          // 000100
const uint8_t kKompleteKontrolColorOrange = 0x08;       // 001000
const uint8_t kKompleteKontrolColorYellow = 0x0e;       // 001110
const uint8_t kKompleteKontrolColorLightYellow = 0x12;  // 010010

const uint8_t kKompleteKontrolColorWhite = 0x13;        //

const uint8_t kKompleteKontrolColorDarkestPaleYellow = 0x14;   //

const uint8_t kKompleteKontrolColorDarkPaleYellow = 0x15;      //

const uint8_t kKompleteKontrolColorPaleYellow = 0x16;   //

const uint8_t kKompleteKontrolColorUnknown = 0x16;      //



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
const size_t kKompleteKontrolLightGuideMessageSize = 250;
const size_t kKompleteKontrolLightGuideKeyMapSize = kKompleteKontrolLightGuideMessageSize - 1;

// This buttons lighting message likely is MK2 specific.
const uint8_t kCommandButtonLightsUpdate = 0x80;
const size_t kKompleteKontrolButtonsMessageSize = 80;
const size_t kKompleteKontrolButtonsMapSize = kKompleteKontrolButtonsMessageSize - 1;

// Button light indezes.
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
const uint8_t kKompleteKontrolButtonIndexPresetUp = 22;
const uint8_t kKompleteKontrolButtonIndexTrack = 23;
const uint8_t kKompleteKontrolButtonIndexLoop = 24;
const uint8_t kKompleteKontrolButtonIndexMetro = 25;
const uint8_t kKompleteKontrolButtonIndexTempo = 26;
const uint8_t kKompleteKontrolButtonIndexPresetDown = 27;
const uint8_t kKompleteKontrolButtonIndexKeyMode = 28;
const uint8_t kKompleteKontrolButtonIndexPlay = 29;
const uint8_t kKompleteKontrolButtonIndexRecord = 30;
const uint8_t kKompleteKontrolButtonIndexStop = 31;
const uint8_t kKompleteKontrolButtonIndexPageLeft = 32;
const uint8_t kKompleteKontrolButtonIndexPageRight = 33;
const uint8_t kKompleteKontrolButtonIndexClear = 34;
const uint8_t kKompleteKontrolButtonIndexBrowser = 35;
const uint8_t kKompleteKontrolButtonIndexPlugin = 36;
const uint8_t kKompleteKontrolButtonIndexMixer = 37;
const uint8_t kKompleteKontrolButtonIndexInstance = 38;
const uint8_t kKompleteKontrolButtonIndexMIDI = 39;
const uint8_t kKompleteKontrolButtonIndexSetup = 40;
const uint8_t kKompleteKontrolButtonIndexFixedVel = 41;
const uint8_t kKompleteKontrolButtonIndexUnused1 = 42;
const uint8_t kKompleteKontrolButtonIndexUnused2 = 43;
const uint8_t kKompleteKontrolButtonIndexStrip1 = 44;
const uint8_t kKompleteKontrolButtonIndexStrip10 = 54;
const uint8_t kKompleteKontrolButtonIndexStrip15 = 59;
const uint8_t kKompleteKontrolButtonIndexStrip20 = 64;
const uint8_t kKompleteKontrolButtonIndexStrip24 = 68;

const uint8_t kKeyColorUnpressed = kKompleteKontrolColorOrange;
const uint8_t kKeyColorPressed = kKompleteKontrolColorLightYellow;

const float kLightsSwoopDelay = 0.01;
const float kLightsSwooshDelay = 0.4;

const size_t kInputBufferSize = 64;

//#define DEBUG_HID_INPUT

static void HIDInputCallback(void* context,
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

static void HIDDeviceRemovedCallback(void *context, IOReturn result, void *sender)
{
    HIDController* controller = (__bridge HIDController*)context;
    [controller deviceRemoved];
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
        memset(_keys, kKeyColorUnpressed, kKompleteKontrolLightGuideKeyMapSize);

        buttonLightingUpdateMessage[0] = kCommandButtonLightsUpdate;
        _buttons = &buttonLightingUpdateMessage[1];
        memset(_buttons, 0, kKompleteKontrolButtonsMapSize);
        _buttons[kKompleteKontrolButtonIndexPlay] = kKompleteKontrolColorBrightWhite;
        _buttons[kKompleteKontrolButtonIndexKnobDown] = kKompleteKontrolColorBrightWhite;
        _buttons[kKompleteKontrolButtonIndexKnobUp] = kKompleteKontrolColorBrightWhite;
        _buttons[kKompleteKontrolButtonIndexKnobLeft] = kKompleteKontrolColorBrightWhite;
        _buttons[kKompleteKontrolButtonIndexKnobRight] = kKompleteKontrolColorBrightWhite;
        _buttons[kKompleteKontrolButtonIndexPageLeft] = kKompleteKontrolColorBrightWhite;
        _buttons[kKompleteKontrolButtonIndexPageRight] = kKompleteKontrolColorBrightWhite;
        _buttons[kKompleteKontrolButtonIndexFunction1] = kKompleteKontrolColorBrightWhite;
        _buttons[kKompleteKontrolButtonIndexFunction2] = kKompleteKontrolColorBrightWhite;
        _buttons[kKompleteKontrolButtonIndexFunction3] = kKompleteKontrolColorBrightWhite;
        _buttons[kKompleteKontrolButtonIndexFunction4] = kKompleteKontrolColorBrightWhite;

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

- (unsigned char)keyColor:(int)note
{
    assert(note < kKompleteKontrolLightGuideKeyMapSize);
    return _keys[note];
}

- (void)deviceRemoved
{
    if (device != 0) {
        IOHIDDeviceClose(device, kIOHIDOptionsTypeNone);
    }
    device = 0;

    [_delegate deviceRemoved];
}

- (void)receivedReport:(unsigned char*)report
{
    static int lastValue = 0;
    int delta = report[30] - lastValue;
    if (delta == 15) {
        delta = -1;
    } else if (delta == -15) {
        delta = 1;
    }
    if (delta != 0) {
        [_delegate receivedEvent:KKBUTTON_SCROLL value:delta];
    }
    lastValue = report[30];
    
    // TODO: Consider making use of some clever mapping for slicker code.
    if (report[1] == 0x10) {
        [_delegate receivedEvent:KKBUTTON_FUNCTION1 value:0];
        return;
    }
    if (report[1] == 0x20) {
        [_delegate receivedEvent:KKBUTTON_FUNCTION2 value:0];
        return;
    }
    if (report[1] == 0x40) {
        [_delegate receivedEvent:KKBUTTON_FUNCTION3 value:0];
        return;
    }
    if (report[1] == 0x80) {
        [_delegate receivedEvent:KKBUTTON_FUNCTION4 value:0];
        return;
    }
    if (report[2] == 0x10) {
        [_delegate receivedEvent:KKBUTTON_PLAY value:0];
        return;
    }
    if (report[6] == 0x44) {
        [_delegate receivedEvent:KKBUTTON_DOWN value:0];
        return;
    }
    if (report[3] == 0x80) {
        [_delegate receivedEvent:KKBUTTON_PAGE_LEFT value:0];
        return;
    }
    if (report[3] == 0x20) {
        [_delegate receivedEvent:KKBUTTON_PAGE_RIGHT value:0];
        return;
    }
    if (report[6] == 0x24) {
        [_delegate receivedEvent:KKBUTTON_UP value:0];
        return;
    }
    if (report[6] == 0x14) {
        [_delegate receivedEvent:KKBUTTON_LEFT value:0];
        return;
    }
    if (report[6] == 0x84) {
        [_delegate receivedEvent:KKBUTTON_RIGHT value:0];
        return;
    }
    if (report[6] == 0x0C) {
        [_delegate receivedEvent:KKBUTTON_ENTER value:0];
        return;
    }
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
        if (vendor != kVendorID_NativeInstruments) {
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

    NSLog(@"No Native Instruments keyboard controller HID device detected");
    if (error != nil) {
        NSDictionary *userInfo = @{
            NSLocalizedDescriptionKey : @"No Native Instruments controller detected",
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
    IOHIDDeviceRegisterRemovalCallback(device, HIDDeviceRemovedCallback, (__bridge void*)self);
    
    IOReturn ret = IOHIDDeviceOpen(device, kIOHIDOptionsTypeNone);
    if (ret != kIOReturnSuccess) {
        if (error != nil) {
            NSDictionary *userInfo = @{
                NSLocalizedDescriptionKey : [NSString stringWithFormat:@"Keyboard Error: %@",
                                             [USBController descriptionWithIOReturn:ret]],
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
                                             [USBController descriptionWithIOReturn:ret]],
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
                                         [USBController descriptionWithIOReturn:ret]],
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
    memset(_keys, 0x00, kKompleteKontrolLightGuideKeyMapSize);
    [self updateLightGuideMap:nil];
}

- (void)lightsDefault
{
    memset(_keys, kKeyColorUnpressed, kKompleteKontrolLightGuideKeyMapSize);
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

            self.keys[key] = kKeyColorUnpressed;
            self.keys[key+1] = kKeyColorUnpressed;
            self.keys[key+2] = kKeyColorUnpressed;
            self.keys[key+3] = kKeyColorUnpressed;
            [self updateLightGuideMap:nil];
        }

        for (int key = self.keyCount - 3;key > 0;key--) {
            self.keys[key]   = kKompleteKontrolColorsSwoop[3];
            self.keys[key+1] = kKompleteKontrolColorsSwoop[2];
            self.keys[key+2] = kKompleteKontrolColorsSwoop[1];
            self.keys[key+3] = kKompleteKontrolColorsSwoop[0];
            [self updateLightGuideMap:nil];

            [NSThread sleepForTimeInterval:kLightsSwoopDelay];

            self.keys[key] = kKeyColorUnpressed;
            self.keys[key+1] = kKeyColorUnpressed;
            self.keys[key+2] = kKeyColorUnpressed;
            self.keys[key+3] = kKeyColorUnpressed;
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

@end
