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

const uint8_t kKompleteKontrolKeyStateLightOff = 0x00;

// We have 16 colors, accross the rainbow, with 4 levels of intensity.
// Additionally, there is white (sort of), again with 4 levels of intensity.
const size_t kKompleteKontrolColorCount = 17;
const size_t kKompleteKontrolColorIntensityLevelCount = 4;

const uint8_t kKompleteKontrolColorRed = 0x04;
const uint8_t kKompleteKontrolColorOrange = 0x08;
const uint8_t kKompleteKontrolColorYellow = 0x10;
const uint8_t kKompleteKontrolColorGreen = 0x1C;
const uint8_t kKompleteKontrolColorBlue = 0x2C;
const uint8_t kKompleteKontrolColorPurple = 0x34;
const uint8_t kKompleteKontrolColorPink = 0x38;
const uint8_t kKompleteKontrolColorWhite = 0x44;

const uint8_t kKompleteKontrolColorMask = 0xfc;
const uint8_t kKompleteKontrolIntensityMask = 0x03;

const uint8_t kKompleteKontrolIntensityLow = 0x00;
const uint8_t kKompleteKontrolIntensityMedium = 0x01;
const uint8_t kKompleteKontrolIntensityHigh = 0x02;
const uint8_t kKompleteKontrolIntensityBright = 0x03;

const uint8_t kKompleteKontrolColorLightBlue = kKompleteKontrolColorBlue | kKompleteKontrolIntensityHigh;
const uint8_t kKompleteKontrolColorBrightBlue = kKompleteKontrolColorBlue | kKompleteKontrolIntensityBright;

const uint8_t kKompleteKontrolColorLightGreen = kKompleteKontrolColorGreen | kKompleteKontrolIntensityHigh;
const uint8_t kKompleteKontrolColorBrightGreen = kKompleteKontrolColorGreen | kKompleteKontrolIntensityBright;

const uint8_t kKompleteKontrolColorLightYellow = kKompleteKontrolColorYellow | kKompleteKontrolIntensityHigh;

const uint8_t kKompleteKontrolColorLightOrange = kKompleteKontrolColorOrange | kKompleteKontrolIntensityHigh;
const uint8_t kKompleteKontrolColorBrightOrange = kKompleteKontrolColorOrange | kKompleteKontrolIntensityBright;

const uint8_t kKompleteKontrolColorLightWhite = kKompleteKontrolColorWhite | kKompleteKontrolIntensityHigh;
const uint8_t kKompleteKontrolColorBrightWhite = kKompleteKontrolColorWhite | kKompleteKontrolIntensityBright;

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
enum {
    kKompleteKontrolButtonIndexM = 0,
    kKompleteKontrolButtonIndexS = 1,
    kKompleteKontrolButtonIndexFunction1 = 2,
    kKompleteKontrolButtonIndexFunction2 = 3,
    kKompleteKontrolButtonIndexFunction3 = 4,
    kKompleteKontrolButtonIndexFunction4 = 5,
    kKompleteKontrolButtonIndexFunction5 = 6,
    kKompleteKontrolButtonIndexFunction6 = 7,
    kKompleteKontrolButtonIndexFunction7 = 8,
    kKompleteKontrolButtonIndexFunction8 = 9,
    kKompleteKontrolButtonIndexKnobLeft = 10,
    kKompleteKontrolButtonIndexKnobUp = 11,
    kKompleteKontrolButtonIndexKnobDown = 12,
    kKompleteKontrolButtonIndexKnobRight = 13,
    kKompleteKontrolButtonIndexScaleEdit = 15,
    kKompleteKontrolButtonIndexArpEdit = 16,
    kKompleteKontrolButtonIndexUndoRedo = 18,
    kKompleteKontrolButtonIndexQuantize = 19,
    kKompleteKontrolButtonIndexPattern = 21,
    kKompleteKontrolButtonIndexPresetUp = 22,
    kKompleteKontrolButtonIndexTrack = 23,
    kKompleteKontrolButtonIndexLoop = 24,
    kKompleteKontrolButtonIndexMetro = 25,
    kKompleteKontrolButtonIndexTempo = 26,
    kKompleteKontrolButtonIndexPresetDown = 27,
    kKompleteKontrolButtonIndexKeyMode = 28,
    kKompleteKontrolButtonIndexPlay = 29,
    kKompleteKontrolButtonIndexRecord = 30,
    kKompleteKontrolButtonIndexStop = 31,
    kKompleteKontrolButtonIndexPageLeft = 32,
    kKompleteKontrolButtonIndexPageRight = 33,
    kKompleteKontrolButtonIndexClear = 34,
    kKompleteKontrolButtonIndexBrowser = 35,
    kKompleteKontrolButtonIndexPlugin = 36,
    kKompleteKontrolButtonIndexMixer = 37,
    kKompleteKontrolButtonIndexInstance = 38,
    kKompleteKontrolButtonIndexMIDI = 39,
    kKompleteKontrolButtonIndexSetup = 40,
    kKompleteKontrolButtonIndexFixedVel = 41,
    kKompleteKontrolButtonIndexUnused1 = 42,
    kKompleteKontrolButtonIndexUnused2 = 43,
    kKompleteKontrolButtonIndexStrip1 = 44,
    kKompleteKontrolButtonIndexStrip10 = 54,
    kKompleteKontrolButtonIndexStrip15 = 59,
    kKompleteKontrolButtonIndexStrip20 = 64,
    kKompleteKontrolButtonIndexStrip24 = 68,
};

// Funky defaults - users might hate me - but I like orange, eat it!
const uint8_t kKeyColorUnpressed = kKompleteKontrolColorOrange;
const uint8_t kKeyColorPressed = kKompleteKontrolColorLightOrange;

const float kLightsSwooshTick = 1.0f / 24.0;
//const float kLightsSwooshTick = 1.0f ;

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

+ (NSColor*)colorWithKeyState:(const unsigned char)keyState
{
    if (keyState < kKompleteKontrolColorIntensityLevelCount) {
        return [NSColor blackColor];
    }
  
    const int intensityShift = 5;
    const int intensityDivider = intensityShift + 3;
    const unsigned char colorIndex = ((keyState >> 2) - 1) % kKompleteKontrolColorCount;
    const unsigned char colorIntensity = (keyState & kKompleteKontrolIntensityMask) + intensityShift;

    // TODO: This is just a very rough, initial approximation of the actual palette of the S-series controllers.
    const unsigned char palette[17][3] = {
        { 0xFF, 0x00, 0x00 },   // 0: red
        { 0xFF, 0x3F, 0x00 },   // 1:
        { 0xFF, 0x7F, 0x00 },   // 2: orange
        { 0xFF, 0xCF, 0x00 },   // 3: orange-yellow
        { 0xFF, 0xFF, 0x00 },   // 4: yellow
        { 0x7F, 0xFF, 0x00 },   // 5: green-yellow
        { 0x00, 0xFF, 0x00 },   // 6: green
        { 0x00, 0xFF, 0x7F },   // 7:
        { 0x00, 0xFF, 0xFF },   // 8:
        { 0x00, 0x7F, 0xFF },   // 9:
        { 0x00, 0x00, 0xFF },   // 10: blue
        { 0x3F, 0x00, 0xFF },   // 11:
        { 0x7F, 0x00, 0xFF },   // 12: purple
        { 0xFF, 0x00, 0xFF },   // 13: pink
        { 0xFF, 0x00, 0x7F },   // 14:
        { 0xFF, 0x00, 0x3F },   // 15:
        { 0xFF, 0xFF, 0xFF }    // 16: white
    };
    
    // FIXME: This intensity simulation only really works for white - racist shit!
    return [NSColor colorWithRed:(((float)palette[colorIndex][0] / 255.0f) * colorIntensity) / intensityDivider
                           green:(((float)palette[colorIndex][1] / 255.0f) * colorIntensity) / intensityDivider
                            blue:(((float)palette[colorIndex][2] / 255.0f) * colorIntensity) / intensityDivider
                           alpha:1.0f];
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
    if (report[0] != 0x01) {
        NSLog(@"ignoring report %02Xh", report[0]);
        return;
    }

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

        if ([supportedDevices objectForKey:@(product)] != nil) {
            _keyCount = [supportedDevices[@(product)][@"keys"] intValue];
            _mk2Controller = [supportedDevices[@(product)][@"mk2"] boolValue];
            _keyOffset = [supportedDevices[@(product)][@"offset"] intValue];
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
    if (device == NULL) {
        return NO;
    }
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
    [self lightKeysWithColor:kKompleteKontrolKeyStateLightOff];
}

- (void)lightKeysWithColor:(unsigned char)color
{
    memset(_keys, color, kKompleteKontrolLightGuideKeyMapSize);
    [self updateLightGuideMap:nil];
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

- (void)lightsSwooshTo:(unsigned char)unpressedKeyState
{
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
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
        for (unsigned long int tick=0;tick < lastTick;tick++) {
            const unsigned int keyIndex = tick % (midIndex + 1);
            if (tick >= fadeOutTick)  {
                // Fade into final state.
                const unsigned int keysPerShade = 4;
                const unsigned long normalizedTick = tick - fadeOutTick;
                const unsigned long round = normalizedTick / midIndex;
                if (keyIndex < round * keysPerShade) {
                    self.keys[midIndex + keyIndex] = dimmedKeyState(self.keys[midIndex + keyIndex],
                                                                    lightsUp,
                                                                    unpressedKeyState);
                    self.keys[midIndex - keyIndex] = dimmedKeyState(self.keys[midIndex - keyIndex],
                                                                    lightsUp,
                                                                    unpressedKeyState);
                }
            }
            if (tick < rainbowTick)  {
                // Fade into rainbow.
                const unsigned int keysPerShade = 4;
                const unsigned long round = tick / midIndex;
                if (keyIndex < round * keysPerShade) {
                    self.keys[keyIndex] = dimmedKeyState(self.keys[keyIndex],
                                                         YES,
                                                         (self.keys[keyIndex] & 0xfc) | rainbowIntensity);
                    self.keys[(self.keyCount - 1) - keyIndex] = dimmedKeyState(self.keys[(self.keyCount - 1) - keyIndex],
                                                                               YES,
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
                self.keys[keyIndex] = colorCode | intensity;
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
    });
}

@end
