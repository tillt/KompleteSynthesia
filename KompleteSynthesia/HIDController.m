//
//  HIDController.m
//  KompleteSynthesia
//
//  Created by Till Toenshoff on 06.01.23.
//

#import "HIDController.h"
#import <Foundation/Foundation.h>
#import <IOKit/hid/IOHIDManager.h>
#import <IOKit/hid/IOHIDKeys.h>
#import <IOKit/IOKitLib.h>

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

const uint8_t kCMD_LightsMapMK2 = 0x81;
const uint8_t kCMD_LightsMapMK1 = 0x82;

const unsigned char kKompleteKontrolColorBlue = 0x2d;
const unsigned char kKompleteKontrolColorLightBlue = 0x2f;
const unsigned char kKompleteKontrolColorGreen = 0x1d;
const unsigned char kKompleteKontrolColorLightGreen = 0x1f;

const unsigned char kKompleteKontrolColorsSwoop[4] = { 0x04, 0x08, 0x0e, 0x12 };

const float kLightsSwoopDelay = 0.01;

/// HID helper functions. Original source is:
/// https://github.com/donniebreve/touchcursor-mac/blob/02f35660bbc6dd1e365f2485577cfb19a7b51fb0/src/hidInformation.c
/**
 * Gets an int from the given HID reference.
 */
static int32_t getIntProperty(IOHIDDeviceRef device, CFStringRef property)
{
    CFTypeRef typeReference = IOHIDDeviceGetProperty(device, property);
    if (typeReference) {
        if (CFGetTypeID(typeReference) == CFNumberGetTypeID()) {
            int32_t value;
            CFNumberGetValue((CFNumberRef)typeReference, kCFNumberSInt32Type, &value);
            return value;
        }
    }
    return 0;
}

/**
 * Gets the Product ID from the given HID reference.
 */
static int getProductID(IOHIDDeviceRef device)
{
    return getIntProperty(device, CFSTR(kIOHIDProductIDKey));
}

/**
 * Gets the Vendor ID from the given HID reference.
 */
static int getVendorID(IOHIDDeviceRef device)
{
    return getIntProperty(device, CFSTR(kIOHIDVendorIDKey));
}

/**
 * Prints the return string.
 */
static char* getIOReturnString(IOReturn ioReturn)
{
    switch (ioReturn)
    {
        case kIOReturnSuccess         : return "Success";
        case kIOReturnError           : return "General error";
        case kIOReturnNoMemory        : return "Can't allocate memory";
        case kIOReturnNoResources     : return "Resource shortage";
        case kIOReturnIPCError        : return "Error during IPC";
        case kIOReturnNoDevice        : return "No such device";
        case kIOReturnNotPrivileged   : return "Privilege violation";
        case kIOReturnBadArgument     : return "Invalid argument";
        case kIOReturnLockedRead      : return "Device read locked";
        case kIOReturnLockedWrite     : return "Device write locked";
        case kIOReturnExclusiveAccess : return "Exclusive access and device already open";
        case kIOReturnBadMessageID    : return "Sent/received messages had different msg_id";
        case kIOReturnUnsupported     : return "Unsupported function";
        case kIOReturnVMError         : return "Miscellaneous VM failure";
        case kIOReturnInternalError   : return "Internal error";
        case kIOReturnIOError         : return "General I/O error";
        case kIOReturnCannotLock      : return "Can't acquire lock";
        case kIOReturnNotOpen         : return "Device not open";
        case kIOReturnNotReadable     : return "Read not supported";
        case kIOReturnNotWritable     : return "Write not supported";
        case kIOReturnNotAligned      : return "Alignment error";
        case kIOReturnBadMedia        : return "Media Error";
        case kIOReturnStillOpen       : return "Device(s) still open";
        case kIOReturnRLDError        : return "RLD failure";
        case kIOReturnDMAError        : return "DMA failure";
        case kIOReturnBusy            : return "Device Busy";
        case kIOReturnTimeout         : return "I/O Timeout";
        case kIOReturnOffline         : return "Device offline";
        case kIOReturnNotReady        : return "Not ready";
        case kIOReturnNotAttached     : return "Device not attached";
        case kIOReturnNoChannels      : return "No DMA channels left";
        case kIOReturnNoSpace         : return "No space for data";
        case kIOReturnPortExists      : return "Port already exists";
        case kIOReturnCannotWire      : return "Can't wire down physical memory";
        case kIOReturnNoInterrupt     : return "No interrupt attached";
        case kIOReturnNoFrames        : return "No DMA frames enqueued";
        case kIOReturnMessageTooLarge : return "Oversized msg received on interrupt port";
        case kIOReturnNotPermitted    : return "Not permitted";
        case kIOReturnNoPower         : return "No power to device";
        case kIOReturnNoMedia         : return "Media not present";
        case kIOReturnUnformattedMedia: return "Media not formatted";
        case kIOReturnUnsupportedMode : return "No such mode";
        case kIOReturnUnderrun        : return "Data underrun";
        case kIOReturnOverrun         : return "Data overrun";
        case kIOReturnDeviceError     : return "The device is not working properly!";
        case kIOReturnNoCompletion    : return "A completion routine is required";
        case kIOReturnAborted         : return "Operation aborted";
        case kIOReturnNoBandwidth     : return "Bus bandwidth would be exceeded";
        case kIOReturnNotResponding   : return "Device not responding";
        case kIOReturnIsoTooOld       : return "Isochronous I/O request for distant past!";
        case kIOReturnIsoTooNew       : return "Isochronous I/O request for distant future";
        case kIOReturnNotFound        : return "Data was not found";
        case kIOReturnInvalid         : return "Should never be seen";
    }
    return "Unknown";
}

@interface HIDController ()
@property (assign, nonatomic) unsigned char* keys;
@end

@implementation HIDController {
    unsigned char blob[250];
    IOHIDDeviceRef device;
}

- (id)init:(NSError**)error
{
    self = [super init];
    if (self) {
        device = [self detectKeyboardController:error];
        if (device == nil) {
            return nil;
        }
        
        _keys = &blob[1];
        memset(_keys, 0, 249);
        
        if ([self initKeyboardController:error] == NO) {
            return nil;
        }
    }

    return self;
}

- (void)dealloc
{
    if (device != 0) {
        IOHIDDeviceClose(device, kIOHIDOptionsTypeNone);
        device = 0;
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
        uint32_t vendor = getVendorID(devices[i]);

        if (vendor != kVendorID) {
            continue;
        }

        uint32_t product = getProductID(devices[i]);

        for (NSNumber* key in [supportedDevices allKeys]) {
            if (product != key.intValue) {
                continue;
            }

            _keyCount = [supportedDevices[key][@"keys"] intValue];
            _mk2Controller = [supportedDevices[key][@"mk2"] boolValue];
            _keyOffset = [supportedDevices[key][@"offset"] intValue];
            blob[0] = _mk2Controller ? kCMD_LightsMapMK2 : kCMD_LightsMapMK1;

            _deviceName = [NSString stringWithFormat:@"Komplete Kontrol S%d MK%d", _keyCount, _mk2Controller ? 2 : 1];

            IOReturn ret = IOHIDDeviceOpen(devices[i], kIOHIDOptionsTypeNone);
            if (ret == kIOReturnSuccess) {
                return devices[i];
            }

            if (error != nil) {
                NSString* reason = [NSString stringWithCString:getIOReturnString(ret) encoding:NSStringEncodingConversionAllowLossy];
                NSDictionary *userInfo = @{
                    NSLocalizedDescriptionKey : [NSString stringWithFormat:@"Keyboard Error: %@", reason],
                    NSLocalizedRecoverySuggestionErrorKey : @"This is entirely unexpected - how did you get here?"
                };
                *error = [NSError errorWithDomain:[[NSBundle bundleForClass:[self class]] bundleIdentifier] code:ret userInfo:userInfo];
            }
            break;
        }
    }

    NSLog(@"no Native Instruments keyboard controller detected");
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
    const uint8_t initBlob[] = { 0xA0 };

    IOReturn ret = IOHIDDeviceSetReport(device, kIOHIDReportTypeOutput, initBlob[0], initBlob, sizeof(initBlob));
    if (ret == kIOReturnSuccess) {
        return YES;
    }

    NSLog(@"couldnt send init");
    if (error != nil) {
        NSString* reason = [NSString stringWithCString:getIOReturnString(ret) encoding:NSStringEncodingConversionAllowLossy];
        NSDictionary *userInfo = @{
            NSLocalizedDescriptionKey : [NSString stringWithFormat:@"Keyboard Error: %@", reason],
            NSLocalizedRecoverySuggestionErrorKey : @"Try switching it off and on again."
        };
        *error = [NSError errorWithDomain:[[NSBundle bundleForClass:[self class]] bundleIdentifier] code:ret userInfo:userInfo];
    }
    return NO;
}

- (NSString*)status
{
    return device != 0 ? _deviceName : @"disconnected";
}

- (void)lightKey:(int)key color:(unsigned char)color
{
    _keys[key] = color;
    [self updateLightMap];
}

- (void)lightsOff
{
    memset(blob, 0, sizeof(blob));
    blob[0] = kCMD_LightsMapMK2;
    [self updateLightMap];
}

- (void)lightsSwoop
{
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        // Some funky colors.
        for (int key = 0;key < self.keyCount - 3;key++) {
            self.keys[key]   = kKompleteKontrolColorsSwoop[0];
            self.keys[key+1] = kKompleteKontrolColorsSwoop[1];
            self.keys[key+2] = kKompleteKontrolColorsSwoop[2];
            self.keys[key+3] = kKompleteKontrolColorsSwoop[3];
            [self updateLightMap];

            [NSThread sleepForTimeInterval:kLightsSwoopDelay];

            self.keys[key] = 0x0;
            self.keys[key+1] = 0x0;
            self.keys[key+2] = 0x0;
            self.keys[key+3] = 0x0;
            [self updateLightMap];
        }

        for (int key = self.keyCount - 3;key > 0;key--) {
            self.keys[key]   = kKompleteKontrolColorsSwoop[3];
            self.keys[key+1] = kKompleteKontrolColorsSwoop[2];
            self.keys[key+2] = kKompleteKontrolColorsSwoop[1];
            self.keys[key+3] = kKompleteKontrolColorsSwoop[0];
            [self updateLightMap];

            [NSThread sleepForTimeInterval:kLightsSwoopDelay];

            self.keys[key] = 0x0;
            self.keys[key+1] = 0x0;
            self.keys[key+2] = 0x0;
            self.keys[key+3] = 0x0;
            [self updateLightMap];
        }
    });
}

- (void)updateLightMap
{
    IOReturn ret = IOHIDDeviceSetReport(device, kIOHIDReportTypeOutput, blob[0], blob, sizeof(blob));
    if (ret != kIOReturnSuccess) {
        NSLog(@"couldnt send light map");
    }
}

@end
