//
//  MIDI2HIDController.m
//  KompleteSynthesia
//
//  Created by Till Toenshoff on 01.01.23.
//

#import "MIDI2HIDController.h"
#import <CoreFoundation/CoreFoundation.h>
#import <CoreMIDI/CoreMIDI.h>
#import "hid.h"
#import "LogViewController.h"

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

const float kLightsSwoopDelay = 0.01;

NSString* kMIDIInputInterface = @"LoopBe";

///
/// Detects a Native Instruments keyboard controller USB device. Listens on the "LoopBe" MIDI input interface port.
/// Notes received are forwarded to the keyboard controller USB device as key lighting requests adhering to the Synthesia
/// protocol.
///
/// The entire approach and implementation is closely following a neat little Python project called
/// https://github.com/ojacques/SynthesiaKontrol
/// Kudos to you Olivier Jacques for sharing!
///
/// The inspiration for re-implementing this as a native macOS appllication struck me when I had a bit of a hard time getting
/// that original Python project to build on a recent system as it would not run on anything beyond Python 3.7 for me.
///
/// TODO: Fully implement MK1 support. Sorry, too lazy and no way to test.
///
/// TODO: Hot swap / re-detection of HID devices.
///
@implementation MIDI2HIDController {
    LogViewController* logViewController;
    MIDIClientRef client;
    MIDIPortRef port;

    unsigned char* keys;
    unsigned char blob[250];
    
    NSString* deviceName;

    IOHIDDeviceRef device;

    unsigned int keyCount;
    BOOL mk2Controller;
    int keyOffset;

    NSTimeInterval startTime;
}

- (id)initWithLogController:(LogViewController*)lc error:(NSError**)error
{
    self = [super init];
    if (self) {
        logViewController = lc;

        device = [self detectKeyboardController:error];
        if (device == nil) {
            return nil;
        }
        
        keys = &blob[1];
        memset(keys, 0, 249);

        if ([self initKeyboardController:error] == NO) {
            return nil;
        }

        [self lightsOff];

        if ([self initMIDI:error] == NO) {
            return nil;
        }

        if ([self rescanMIDI] == NO) {
            NSLog(@"MIDI interface port not found");
            NSDictionary *userInfo = @{
                NSLocalizedDescriptionKey : [NSString stringWithFormat:@"MIDI Error: Interface port \'%@\' not found", kMIDIInputInterface],
                NSLocalizedRecoverySuggestionErrorKey : @"Make sure you setup the interface port as documented."
            };
            *error = [NSError errorWithDomain:[[NSBundle bundleForClass:[self class]] bundleIdentifier] code:-1 userInfo:userInfo];
           return nil;
        }

        [self lightsSwoop];
    }
    return self;
}

- (void)dealloc
{
    if (port != 0) {
        MIDIPortDispose(port);
        port = 0;
    }

    if (client != 0) {
        MIDIClientDispose(client);
        client = 0;
    }

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
    
    IOHIDManagerRef mgr;
    
    mgr = IOHIDManagerCreate(kCFAllocatorDefault, kIOHIDOptionsTypeNone);
    IOHIDManagerSetDeviceMatching(mgr, NULL);
    IOHIDManagerOpen(mgr, kIOHIDOptionsTypeNone);
   
    CFSetRef deviceSet = IOHIDManagerCopyDevices(mgr);
    CFIndex deviceCount = CFSetGetCount(deviceSet);
    IOHIDDeviceRef* devices = calloc(deviceCount, sizeof(IOHIDDeviceRef));
    CFSetGetValues(deviceSet, (const void **)devices);

    for (CFIndex i = 0; i < deviceCount; i++) {
        uint32_t product = getProductID(devices[i]);
        uint32_t vendor = getVendorID(devices[i]);

        if (vendor == kVendorID) {
            for (NSNumber* key in [supportedDevices allKeys]) {
                if (product == key.intValue) {
                    keyCount = [supportedDevices[key][@"keys"] intValue];
                    mk2Controller = [supportedDevices[key][@"mk2"] boolValue];
                    keyOffset = [supportedDevices[key][@"offset"] intValue];
                    blob[0] = mk2Controller ? kCMD_LightsMapMK2 : kCMD_LightsMapMK1;

                    deviceName = [NSString stringWithFormat:@"Komplete Kontrol S%d MK%d", keyCount, mk2Controller ? 2 : 1];
                    // FIXME(tillt): For some reason that line never shows - race of some sort?
                    [logViewController dispatchLogLine:[NSString stringWithFormat:@"detected Native Instruments %@\n", deviceName]];

                    IOReturn ret = IOHIDDeviceOpen(devices[i], kIOHIDOptionsTypeNone);
                    if (ret != kIOReturnSuccess) {
                        NSString* reason = [NSString stringWithCString:getIOReturnString(ret) encoding:NSStringEncodingConversionAllowLossy];
                        NSDictionary *userInfo = @{
                            NSLocalizedDescriptionKey : [NSString stringWithFormat:@"Keyboard Error: %@", reason],
                            NSLocalizedRecoverySuggestionErrorKey : @"This is entirely unexpected - how did you get here?"
                        };
                        *error = [NSError errorWithDomain:[[NSBundle bundleForClass:[self class]] bundleIdentifier] code:ret userInfo:userInfo];
                        return NULL;
                    }

                    return devices[i];
                }
            }
        }
    }

    NSLog(@"no Native Instruments keyboard controller detected");
    NSDictionary *userInfo = @{
        NSLocalizedDescriptionKey : @"Keyboard Error: No Native Instruments controller detected",
        NSLocalizedRecoverySuggestionErrorKey : @"Make sure the keyboard is connected and powered on."
    };
    *error = [NSError errorWithDomain:[[NSBundle bundleForClass:[self class]] bundleIdentifier] code:-1 userInfo:userInfo];

    return 0;
}

- (BOOL)initKeyboardController:(NSError**)error
{
    uint8_t initBlob[] = { 0xA0 };
    IOReturn ret = IOHIDDeviceSetReport(device, kIOHIDReportTypeOutput, 0xA0, initBlob, sizeof(initBlob));
    if (ret != kIOReturnSuccess) {
        NSLog(@"couldnt send init");
        NSString* reason = [NSString stringWithCString:getIOReturnString(ret) encoding:NSStringEncodingConversionAllowLossy];
        NSDictionary *userInfo = @{
            NSLocalizedDescriptionKey : [NSString stringWithFormat:@"Keyboard Error: %@", reason],
            NSLocalizedRecoverySuggestionErrorKey : @"Try switching it off and on again."
        };
        *error = [NSError errorWithDomain:[[NSBundle bundleForClass:[self class]] bundleIdentifier] code:ret userInfo:userInfo];
        return NO;
    }
    return YES;
}

- (NSString*)status
{
    return device != 0 ? deviceName : @"disconnected";
}

- (void)lightNote:(unsigned int)note type:(unsigned int)type channel:(unsigned int)channel velocity:(unsigned int)velocity
{
    int key = note + keyOffset;

    if (key < 0 || key > keyCount) {
        NSLog(@"unexpected note lighting requested for key %d", key);
        return;
    }

    unsigned char left = kKompleteKontrolColorBlue;
    unsigned char left_thumb = kKompleteKontrolColorLightBlue;
    unsigned char right = kKompleteKontrolColorGreen;
    unsigned char right_thumb = kKompleteKontrolColorLightGreen;

    unsigned char def = right;
    unsigned char color = def;

    if (channel == 0) {
        // We do not know who or what this note belongs to,
        // but light something up anyway.
        color = def;
    } else if (channel >= 1 && channel <= 5) {
        // Left hand fingers, thumb through pinky.
        if (channel == 1) {
            color = left_thumb;
        } else {
            color = left;
        }
    }
    if (channel >= 6 && channel <= 10) {
        // Right hand fingers, thumb through pinky.
        if (channel == 6) {
            color = right_thumb;
        } else {
            color = right;
        }
    }
    if (channel == 11) {
        // Left hand, unknown finger.
        color = left;
    }
    if (channel == 12) {
        // Right hand, unknown finger.
        color = right;
    }
    
    if (type == kMIDICVStatusNoteOn && velocity != 0) {
        keys[key] = color;
    }
    if (type == kMIDICVStatusNoteOff || velocity == 0) {
        keys[key] = 0x00;
    }

    [self updateLightMap];
}

- (void)updateLightMap
{
    IOReturn ret = IOHIDDeviceSetReport(device, kIOHIDReportTypeOutput, blob[0], blob, sizeof(blob));
    if (ret != kIOReturnSuccess) {
        NSLog(@"couldnt send light map");
    }
}

- (void)receivedMIDIEvents:(const MIDIEventList*)eventList {

    const MIDIEventPacket *packet = &eventList->packet[0];

    for (unsigned i = 0; i < eventList->numPackets; ++i) {
        for (unsigned w = 0; w < packet->wordCount; ++w) {
            unsigned char cvStatus = (packet->words[w] & 0x00F00000) >> 20;
            unsigned char channel = (packet->words[w] & 0x000F0000) >> 16;
            if (cvStatus == kMIDICVStatusNoteOn || cvStatus == kMIDICVStatusNoteOff) {
                unsigned char note = (packet->words[w] & 0x0000FF00) >> 8;
                unsigned char vel = packet->words[w] & 0x000000FF;

                [self lightNote:note type:cvStatus channel:channel velocity:vel];

                if (cvStatus == kMIDICVStatusNoteOn) {
                    [logViewController dispatchLogLine:[NSString stringWithFormat:@"note  on - channel %02d - note %3d - velocity %d\n", channel, note, vel]];
                } else if (cvStatus == kMIDICVStatusNoteOff) {
                    [logViewController dispatchLogLine:[NSString stringWithFormat:@"note off - channel %02d - note %3d - velocity %d\n", channel, note, vel]];
                }
            } else if (cvStatus == kMIDICVStatusControlChange) {
                unsigned char control = (packet->words[w] & 0x0000FF00) >> 8;
                unsigned char value = packet->words[w] & 0x000000FF;

                if (channel == 0x00 && control == 0x10) {
                    if (value & 0x04) {
                        [logViewController dispatchLogLine:[NSString stringWithFormat:@"user is playing\n"]];
                    }
                    if (value & 0x01) {
                        [logViewController dispatchLogLine:[NSString stringWithFormat:@"playing right hand\n"]];
                    }
                    if (value & 0x02) {
                        [logViewController dispatchLogLine:[NSString stringWithFormat:@"playing left hand\n"]];
                    }
                    [self lightsOff];
                }
            } else {
                [logViewController dispatchLogLine:[NSString stringWithFormat:@"%08X (%d)\n", packet->words[w], packet->wordCount]];
            }
        }
        packet = MIDIEventPacketNext(packet);
    }
}

- (BOOL)rescanMIDI
{
    NSLog(@"midi configuration changed");
    
    // Try to locate the input endpoint we are configured for and connect.
    MIDIEndpointRef source = 0;
    for (ItemCount i = 0; i < MIDIGetNumberOfSources(); ++i) {
        source = MIDIGetSource(i);
        if (source != 0) {
            MIDIEntityRef entity = 0;
            OSStatus status = MIDIEndpointGetEntity(source, &entity);
            if (status != 0) {
                NSLog(@"MIDIEndpointGetEntity: %d", status);
                continue;
            }

            NSDictionary* dictionary = nil;
            status = MIDIObjectGetProperties(entity, (CFPropertyListRef)&dictionary, true);
            if (status != 0) {
                NSLog(@"MIDIObjectGetProperties: %d", status);
                continue;
            }
            
            NSString* name = [dictionary valueForKey:@"name"];
            NSLog(@"input name:  %@", name);
            if ([name compare:kMIDIInputInterface] == NSOrderedSame) {
                NSLog(@"found our input port");
                MIDIPortConnectSource(port, source, NULL);
                return YES;
            }
        }
    }
    return NO;
}

- (NSString*)OSStatusString:(int)status
{
    char fourcc[8];
    NSString* message;
    // See if it appears to be a 4-char-code.
    *(UInt32 *)(fourcc + 1) = CFSwapInt32HostToBig(status);
    if (isprint(fourcc[1]) && isprint(fourcc[2]) && isprint(fourcc[3]) && isprint(fourcc[4])) {
        fourcc[0] = fourcc[5] = '\'';
        fourcc[6] = '\0';
        message = [NSString stringWithCString:(const char*)fourcc encoding:NSStringEncodingConversionAllowLossy];
    } else {
        // Otherwise try to get a human readable string from the NSError constructor.
        NSError *error = [NSError errorWithDomain:NSOSStatusErrorDomain code:status userInfo:nil];
        message = error.localizedFailureReason;
    }
    return message;
}

- (BOOL)initMIDI:(NSError**)error
{
    OSStatus status = MIDIClientCreateWithBlock((CFStringRef)@"KompleteSynthesia",
                                                &client,
                                                ^(const MIDINotification * _Nonnull message) {
                                                    if (message->messageID == kMIDIMsgSetupChanged) {
                                                        if (![self rescanMIDI]) {
                                                            NSLog(@"failed to locate MIDI interface port %@", kMIDIInputInterface);
                                                        }
                                                    }
                                                });
    if (status != 0) {
        NSLog(@"MIDIClientCreate: %d", status);
        NSDictionary *userInfo = @{
            NSLocalizedDescriptionKey : [NSString stringWithFormat:@"MIDI Error: %@", [self OSStatusString:status]],
            NSLocalizedRecoverySuggestionErrorKey : @"Try switching it off and on again."
        };
        *error = [NSError errorWithDomain:[[NSBundle bundleForClass:[self class]] bundleIdentifier] code:status userInfo:userInfo];
        return NO;
    }

    MIDIReceiveBlock receiveBlock = ^void (const MIDIEventList *evtlist, void *srcConRef) {
        [self receivedMIDIEvents:evtlist];
    };
    
    status = MIDIInputPortCreateWithProtocol(client,
                                             (__bridge CFStringRef)kMIDIInputInterface,
                                             kMIDIProtocol_1_0,
                                             &port,
                                             receiveBlock);
    if (status != 0) {
        NSLog(@"MIDIInputPortCreate: %d", status);
        NSDictionary *userInfo = @{
            NSLocalizedDescriptionKey : [NSString stringWithFormat:@"MIDI Error: %@", [self OSStatusString:status]],
            NSLocalizedRecoverySuggestionErrorKey : @"Try switching it off and on again."
        };
        *error = [NSError errorWithDomain:[[NSBundle bundleForClass:[self class]] bundleIdentifier] code:status userInfo:userInfo];
        return NO;
    }

    return YES;
}

- (void)lightsSwoop
{
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        unsigned char colors[1][4] = {{ 0x04, 0x08, 0x0e, 0x12 } };
        for (int round = 0;round < 1;round++) {
            for (int key = 0;key < keyCount - 3;key++) {
                keys[key]   = colors[0][0];
                keys[key+1] = colors[0][1];
                keys[key+2] = colors[0][2];
                keys[key+3] = colors[0][3];
                [self updateLightMap];

                [NSThread sleepForTimeInterval:kLightsSwoopDelay];

                keys[key] = 0x0;
                keys[key+1] = 0x0;
                keys[key+2] = 0x0;
                keys[key+3] = 0x0;
                [self updateLightMap];
            }

            for (int key = keyCount - 3;key > 0;key--) {
                keys[key]   = colors[0][3];
                keys[key+1] = colors[0][2];
                keys[key+2] = colors[0][1];
                keys[key+3] = colors[0][0];
                [self updateLightMap];

                [NSThread sleepForTimeInterval:kLightsSwoopDelay];

                keys[key] = 0x0;
                keys[key+1] = 0x0;
                keys[key+2] = 0x0;
                keys[key+3] = 0x0;
                [self updateLightMap];
            }
        }
    });
}

- (void)lightsOff
{
    memset(blob, 0, sizeof(blob));
    blob[0] = kCMD_LightsMapMK2;
    IOReturn ret = IOHIDDeviceSetReport(device, kIOHIDReportTypeOutput, kCMD_LightsMapMK2, blob, sizeof(blob));
    if (ret != kIOReturnSuccess) {
        NSLog(@"lights off: failed to set report");
    }
}

@end
