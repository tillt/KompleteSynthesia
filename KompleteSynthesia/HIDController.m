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

const uint8_t kLightGuideCommandUpdateMK2 = 0x81;
const uint8_t kLightGuideCommandUpdateMK1 = 0x82;

const size_t kLightGuideMessageSize = 250;

const uint8_t kKompleteKontrolColorBlue = 0x2d;
const uint8_t kKompleteKontrolColorLightBlue = 0x2f;
const uint8_t kKompleteKontrolColorGreen = 0x1d;
const uint8_t kKompleteKontrolColorLightGreen = 0x1f;

// Some funky colors.
const uint8_t kKompleteKontrolColorsSwoop[4] = { 0x04, 0x08, 0x0e, 0x12 };

const float kLightsSwoopDelay = 0.01;

@interface HIDController ()
@property (assign, nonatomic) unsigned char* keys;
@end

@implementation HIDController {
    unsigned char lightGuideUpdateMessage[kLightGuideMessageSize];
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
        if ([self initKeyboardController:error] == NO) {
            return nil;
        }
        lightGuideUpdateMessage[0] = kLightGuideCommandUpdateMK2;
        _keys = &lightGuideUpdateMessage[1];
        memset(_keys, 0, kLightGuideMessageSize-1);
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

+ (int)intProperty:(NSString*)property fromDevice:(IOHIDDeviceRef)device
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
    return [HIDController intProperty:@(kIOHIDProductIDKey) fromDevice:device];
}

+ (int)vendorIDWithDevice:(IOHIDDeviceRef)device
{
    return [HIDController intProperty:@(kIOHIDVendorIDKey) fromDevice:device];
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
            lightGuideUpdateMessage[0] = _mk2Controller ? kLightGuideCommandUpdateMK2 : kLightGuideCommandUpdateMK1;

            _deviceName = [NSString stringWithFormat:@"Komplete Kontrol S%d MK%d", _keyCount, _mk2Controller ? 2 : 1];
            return devices[i];
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
    IOReturn ret = IOHIDDeviceOpen(device, kIOHIDOptionsTypeNone);
    if (ret != kIOReturnSuccess) {
        if (error != nil) {
            NSDictionary *userInfo = @{
                NSLocalizedDescriptionKey : [NSString stringWithFormat:@"Keyboard Error: %@", [HIDController descriptionWithIOReturn:ret]],
                NSLocalizedRecoverySuggestionErrorKey : @"This is entirely unexpected - how did you get here?"
            };
            *error = [NSError errorWithDomain:[[NSBundle bundleForClass:[self class]] bundleIdentifier] code:ret userInfo:userInfo];
        }
        return NO;
    }

    const uint8_t initBlob[] = { 0xA0 };
    ret = IOHIDDeviceSetReport(device, kIOHIDReportTypeOutput, initBlob[0], initBlob, sizeof(initBlob));
    if (ret == kIOReturnSuccess) {
        return YES;
    }

    NSLog(@"couldnt send init");
    if (error != nil) {
        NSDictionary *userInfo = @{
            NSLocalizedDescriptionKey : [NSString stringWithFormat:@"Keyboard Error: %@", [HIDController descriptionWithIOReturn:ret]],
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
    [self updateLightMap:nil];
}

- (void)lightsOff
{
    memset(_keys, 0, kLightGuideMessageSize-1);
    [self updateLightMap:nil];
}

- (void)lightsSwoop
{
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        for (int key = 0;key < self.keyCount - 3;key++) {
            self.keys[key]   = kKompleteKontrolColorsSwoop[0];
            self.keys[key+1] = kKompleteKontrolColorsSwoop[1];
            self.keys[key+2] = kKompleteKontrolColorsSwoop[2];
            self.keys[key+3] = kKompleteKontrolColorsSwoop[3];
            [self updateLightMap:nil];

            [NSThread sleepForTimeInterval:kLightsSwoopDelay];

            self.keys[key] = 0x0;
            self.keys[key+1] = 0x0;
            self.keys[key+2] = 0x0;
            self.keys[key+3] = 0x0;
            [self updateLightMap:nil];
        }

        for (int key = self.keyCount - 3;key > 0;key--) {
            self.keys[key]   = kKompleteKontrolColorsSwoop[3];
            self.keys[key+1] = kKompleteKontrolColorsSwoop[2];
            self.keys[key+2] = kKompleteKontrolColorsSwoop[1];
            self.keys[key+3] = kKompleteKontrolColorsSwoop[0];
            [self updateLightMap:nil];

            [NSThread sleepForTimeInterval:kLightsSwoopDelay];

            self.keys[key] = 0x0;
            self.keys[key+1] = 0x0;
            self.keys[key+2] = 0x0;
            self.keys[key+3] = 0x0;
            [self updateLightMap:nil];
        }
    });
}

- (void)updateLightMap:(NSError**)error
{
    IOReturn ret = IOHIDDeviceSetReport(device,
                                        kIOHIDReportTypeOutput,
                                        lightGuideUpdateMessage[0],
                                        lightGuideUpdateMessage,
                                        sizeof(lightGuideUpdateMessage));
    if (ret == kIOReturnSuccess) {
        return;
    }

    NSLog(@"couldnt send light map");
    if (error != nil) {
        NSDictionary *userInfo = @{
            NSLocalizedDescriptionKey : [NSString stringWithFormat:@"Keyboard Error: %@", [HIDController descriptionWithIOReturn:ret]],
            NSLocalizedRecoverySuggestionErrorKey : @"Try switching it off and on again."
        };
        *error = [NSError errorWithDomain:[[NSBundle bundleForClass:[self class]] bundleIdentifier] code:ret userInfo:userInfo];
    }
}

@end
