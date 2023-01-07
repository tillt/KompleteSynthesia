//
//  MIDIController.m
//  KompleteSynthesia
//
//  Created by Till Toenshoff on 06.01.23.
//

#import "MIDIController.h"
#import <CoreMIDI/CoreMIDI.h>

NSString* kMIDIInputInterface = @"LoopBe";

@implementation MIDIController {
    MIDIClientRef client;
    MIDIPortRef port;
    BOOL connected;
}

- (id)initWithDelegate:(id)delegate error:(NSError**)error
{
    self = [super init];
    if (self) {
        _delegate = delegate;
        
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
            if (error != nil) {
                NSDictionary *userInfo = @{
                    NSLocalizedDescriptionKey : [NSString stringWithFormat:@"MIDI Error: %@", [MIDIController OSStatusString:status]],
                    NSLocalizedRecoverySuggestionErrorKey : @"Try switching it off and on again."
                };
                *error = [NSError errorWithDomain:[[NSBundle bundleForClass:[self class]] bundleIdentifier] code:status userInfo:userInfo];
            }
            return nil;
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
            if (error != nil) {
                NSDictionary *userInfo = @{
                    NSLocalizedDescriptionKey : [NSString stringWithFormat:@"MIDI Error: %@", [MIDIController OSStatusString:status]],
                    NSLocalizedRecoverySuggestionErrorKey : @"Try switching it off and on again."
                };
                *error = [NSError errorWithDomain:[[NSBundle bundleForClass:[self class]] bundleIdentifier] code:status userInfo:userInfo];
            }
            return nil;
        }
        
        if ([self rescanMIDI] == NO) {
            NSLog(@"MIDI interface port not found");
            if (error != nil) {
                NSDictionary *userInfo = @{
                    NSLocalizedDescriptionKey : [NSString stringWithFormat:@"MIDI Error: Interface port \'%@\' not found", kMIDIInputInterface],
                    NSLocalizedRecoverySuggestionErrorKey : @"Make sure you setup the interface port as documented."
                };
                *error = [NSError errorWithDomain:[[NSBundle bundleForClass:[self class]] bundleIdentifier] code:-1 userInfo:userInfo];
            }
           return nil;
        }
    }

    return self;
}

- (NSString*)status
{
    return connected ? @"receiving" : @"endpoint not found";
}

- (void)dealloc
{
    if (port != 0) {
        MIDIPortDispose(port);
    }

    if (client != 0) {
        MIDIClientDispose(client);
    }
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

- (BOOL)rescanMIDI
{
    NSLog(@"midi configuration changed");
    connected = NO;
    
    // Try to locate the input endpoint we are configured for and connect.
    // FIXME(tillt): This seems not entirely correct - the MIDI input scanning and
    // connection setup seems weirdly redundant the way this is now implemented.
    // But hey, it works for me!
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
            if ([name compare:kMIDIInputInterface] == NSOrderedSame) {
                NSLog(@"found our input port");
                status = MIDIPortConnectSource(port, source, NULL);
                if (status != 0) {
                    NSLog(@"MIDIPortConnectSource: %d", status);
                    return NO;
                }
                connected = YES;
                return YES;
            }
        }
    }
    return NO;
}

- (void)receivedMIDIEvents:(const MIDIEventList*)eventList
{
    const MIDIEventPacket *packet = &eventList->packet[0];

    for (unsigned i = 0; i < eventList->numPackets; ++i) {
        for (unsigned w = 0; w < packet->wordCount; ++w) {
            unsigned char cvStatus = (packet->words[w] & 0x00F00000) >> 20;
            if (cvStatus == kMIDICVStatusNoteOn ||
                cvStatus == kMIDICVStatusNoteOff ||
                cvStatus == kMIDICVStatusControlChange) {
                unsigned char channel = (packet->words[w] & 0x000F0000) >> 16;
                unsigned char p1 = (packet->words[w] & 0x0000FF00) >> 8;
                unsigned char p2 = packet->words[w] & 0x000000FF;

                dispatch_async(dispatch_get_main_queue(), ^{
                    [self.delegate receivedMIDIEvent:cvStatus channel:channel param1:p1 param2:p2];
                });
            }
        }
        packet = MIDIEventPacketNext(packet);
    }
}

@end
