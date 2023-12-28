//
//  MIDIController.m
//  KompleteSynthesia
//
//  Created by Till Toenshoff on 06.01.23.
//

#import "MIDIController.h"

#import <CoreMIDI/CoreMIDI.h>

#import "LogViewController.h"

NSString* kMIDIInputInterfaceLightLoopback = @"LoopBe";
NSString* kMIDIInputInterfaceKeyboard = @"Port 1";

const int kMIDIConnectionInterfaceLightLoopback = 0;
const int kMIDIConnectionInterfaceKeyboard = 1;

/// Listens on the "IAC Driver LoopBe" and the "Komplete Kontrol Sx MKx Port 1" interfaces and forwards
/// note on/off events as well as control change events to its delegate.

@implementation MIDIController {
    MIDIClientRef client;
    MIDIPortRef portKeyboard;
    MIDIPortRef portLight;
    BOOL connected;
}

+ (NSString*)readableNote:(unsigned char)note
{
    int octave = ((int)note / 12) - 1;
    NSArray* noteNames = @[@"C", @"C#", @"D", @"D#", @"E", @"F", @"F#", @"G", @"G#", @"A", @"A#", @"B"];
    NSString* readable = [NSString stringWithFormat:@"%@%d", noteNames[note % 12], octave];
    NSString* output = @"   ";
    return [output stringByReplacingCharactersInRange:NSMakeRange(0, readable.length) withString:readable];
}

+ (NSString*)OSStatusString:(int)status
{
    char fourcc[8] = {};
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

- (id)initWithLogViewController:(LogViewController*)lc
{
    self = [super init];
    if (self) {
        log = lc;
    }
    return self;
}

- (BOOL)setupWithError:(NSError**)error
{
    __weak MIDIController* weakSelf = self;

    portLight = 0;
    portKeyboard = 0;

    OSStatus status = MIDIClientCreateWithBlock((CFStringRef)@"KompleteSynthesia",
                                                &client,
                                                ^(const MIDINotification * _Nonnull message) {
        if (message->messageID == kMIDIMsgSetupChanged) {
            if (![weakSelf rescanMIDI]) {
                NSLog(@"failed to create midi client interface connections");
            }
        }
    });
    if (status != 0) {
        NSLog(@"MIDIClientCreate: %d", status);
        if (error != nil) {
            NSDictionary *userInfo = @{
                NSLocalizedDescriptionKey: [NSString stringWithFormat:@"MIDI Error: %@", [MIDIController OSStatusString:status]],
                NSLocalizedRecoverySuggestionErrorKey: @"Try switching it off and on again."
            };
            *error = [NSError errorWithDomain:[[NSBundle bundleForClass:[self class]] bundleIdentifier] code:status userInfo:userInfo];
        }
        return NO;
    }
    MIDIReceiveBlock receiveBlockLightLoopback = ^void (const MIDIEventList *evtlist, void *srcConRef) {
        [weakSelf receivedMIDIEvents:evtlist interface:kMIDIConnectionInterfaceLightLoopback];
    };

    // MIDIInputPortCreateWithProtocol does not exist on macOS 10.15. We could replace this
    // logic with `MIDIInputPortCreateWithBlock` which works based on MIDIPackets and not
    // MIDIEvents - that in turn makes the parser a more complex and prone to failurea. But
    // it would give us 10.15 (catalina) compatiblity.
    status = MIDIInputPortCreateWithProtocol(client,
                                             (__bridge CFStringRef)kMIDIInputInterfaceLightLoopback,
                                             kMIDIProtocol_1_0,
                                             &portLight,
                                             receiveBlockLightLoopback);
    if (status != 0) {
        NSLog(@"MIDIInputPortCreate: %d", status);
        if (error != nil) {
            NSDictionary *userInfo = @{
                NSLocalizedDescriptionKey: [NSString stringWithFormat:@"MIDI Error: %@", [MIDIController OSStatusString:status]],
                NSLocalizedRecoverySuggestionErrorKey: @"Try to restart this application."
            };
            *error = [NSError errorWithDomain:[[NSBundle bundleForClass:[self class]] bundleIdentifier] code:status userInfo:userInfo];
        }
        return NO;
    }

    // It was so nice, we do it twice...

    MIDIReceiveBlock receiveBlockKeyboard = ^void (const MIDIEventList *evtlist, void *srcConRef) {
        [weakSelf receivedMIDIEvents:evtlist interface:kMIDIConnectionInterfaceKeyboard];
    };

    status = MIDIInputPortCreateWithProtocol(client,
                                             (__bridge CFStringRef)kMIDIInputInterfaceKeyboard,
                                             kMIDIProtocol_1_0,
                                             &portKeyboard,
                                             receiveBlockKeyboard);
    if (status != 0) {
        NSLog(@"MIDIInputPortCreate: %d", status);
        if (error != nil) {
            NSDictionary *userInfo = @{
                NSLocalizedDescriptionKey: [NSString stringWithFormat:@"MIDI Error: %@", [MIDIController OSStatusString:status]],
                NSLocalizedRecoverySuggestionErrorKey: @"Try to restart this application."
            };
            *error = [NSError errorWithDomain:[[NSBundle bundleForClass:[self class]] bundleIdentifier] code:status userInfo:userInfo];
        }
        return NO;
    }

    if ([self rescanMIDI] == NO) {
        NSLog(@"MIDI interfaces ports not found");
        if (error != nil) {
            NSDictionary *userInfo = @{
                NSLocalizedDescriptionKey: [NSString stringWithFormat:@"MIDI interface ports \'%@\' and \'%@' not found",
                                            kMIDIInputInterfaceLightLoopback,
                                            kMIDIInputInterfaceKeyboard],
                NSLocalizedRecoverySuggestionErrorKey: @"Make sure you setup the interface port as documented."
            };
            *error = [NSError errorWithDomain:[[NSBundle bundleForClass:[self class]] bundleIdentifier] code:-1 userInfo:userInfo];
        }
        return NO;
    }
    return YES;
}

- (NSString*)status
{
    return connected ? [NSString stringWithFormat:@"Receiving from %@", kMIDIInputInterfaceLightLoopback]
                     : @"Interface not found";
}

- (void)dealloc
{
    if (portLight != 0) {
        MIDIPortDispose(portLight);
    }
    if (portKeyboard != 0) {
        MIDIPortDispose(portKeyboard);
    }
    if (client != 0) {
        MIDIClientDispose(client);
    }
}

- (BOOL)rescanMIDI
{
    NSLog(@"midi configuration changed");
    BOOL connectedToLightLoopback = NO;
    BOOL connectedToKeyboard = NO;

    // Try to locate the input endpoints we are configured for and connect.
    // FIXME: This seems not entirely correct - the MIDI input scanning and
    // FIXME: connection setup seems weirdly redundant the way this is now implemented.
    // FIXME: But hey, it works for me!
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

            CFPropertyListRef pl = NULL;
            status = MIDIObjectGetProperties(entity, &pl, true);
            if (status != 0) {
                NSLog(@"MIDIObjectGetProperties: %d", status);
                continue;
            }
            NSDictionary* dictionary = (__bridge NSDictionary*)pl;
            NSString* name = [dictionary valueForKey:@"name"];
            NSLog(@"input name:  %@", name);
            if ([name compare:kMIDIInputInterfaceLightLoopback] == NSOrderedSame) {
                NSLog(@"found light loopback interface");
                status = MIDIPortConnectSource(portLight, source, NULL);
                if (status != 0) {
                    NSLog(@"MIDIPortConnectSource: %d", status);
                    return NO;
                }
                connectedToLightLoopback = YES;
            }
            if ([name compare:kMIDIInputInterfaceKeyboard] == NSOrderedSame) {
                NSLog(@"found keyboard interface");
                status = MIDIPortConnectSource(portKeyboard, source, NULL);
                if (status != 0) {
                    NSLog(@"MIDIPortConnectSource: %d", status);
                    return NO;
                }
                connectedToKeyboard = YES;
            }
        }
    }
    if (connectedToLightLoopback) {
        connected = YES;
    }
    return connected;
}

- (void)receivedMIDIEvents:(const MIDIEventList*)eventList interface:(unsigned char)interface
{
    const MIDIEventPacket* packet = &eventList->packet[0];

    for (unsigned i = 0; i < eventList->numPackets; ++i) {
        for (unsigned w = 0; w < packet->wordCount; ++w) {
            unsigned char cvStatus = (packet->words[w] & 0x00F00000) >> 20;
            if (cvStatus == kMIDICVStatusNoteOn ||
                cvStatus == kMIDICVStatusNoteOff ||
                cvStatus == kMIDICVStatusControlChange) {
                unsigned char channel = (packet->words[w] & 0x000F0000) >> 16;
                unsigned char param1 = (packet->words[w] & 0x0000FF00) >> 8;
                unsigned char param2 = packet->words[w] & 0x000000FF;

                [self.delegate receivedMIDIEvent:cvStatus
                                         channel:channel
                                          param1:param1
                                          param2:param2
                                       interface:interface];
            }
        }
        packet = MIDIEventPacketNext(packet);
    }
}

@end
