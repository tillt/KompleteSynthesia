//
//  MIDI2HIDController.m
//  KompleteSynthesia
//
//  Created by Till Toenshoff on 01.01.23.
//

#import "MIDI2HIDController.h"
#import <CoreFoundation/CoreFoundation.h>
#import <CoreMIDI/CoreMIDI.h>
#import "LogViewController.h"
#import "HIDController.h"
#import "MIDIController.h"

@interface MIDI2HIDController ()
@end

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
    LogViewController* log;
    MIDIController* midi;
    HIDController* hid;
}

- (id)initWithLogController:(LogViewController*)lc error:(NSError**)error
{
    self = [super init];
    if (self) {
        log = lc;
        
        hid = [[HIDController alloc] init:error];
        if (hid == nil) {
            return nil;
        }

        [log logLine:[NSString stringWithFormat:@"detected Native Instruments %@\n", hid.deviceName]];

        [hid lightsOff];
        
        midi = [[MIDIController alloc] initWithDelegate:self error:error];
        if (midi == nil) {
            return nil;
        }

        [hid lightsSwoop];
    }
    return self;
}

- (NSString*)hidStatus
{
    return hid.status;
}

- (NSString*)midiStatus
{
    return [NSString stringWithFormat:@"MIDI: %@", midi.status];
}

- (void)lightNote:(unsigned int)note type:(unsigned int)type channel:(unsigned int)channel velocity:(unsigned int)velocity
{
    int key = note + hid.keyOffset;

    if (key < 0 || key > hid.keyCount) {
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
        [hid lightKey:key color:color];
    }
    if (type == kMIDICVStatusNoteOff || velocity == 0) {
        [hid lightKey:key color:0x00];
    }
}

#pragma mark MIDIControllerDelegate

-(void)receivedMIDIEvent:(unsigned char )cv channel:(unsigned char)channel param1:(unsigned char)param1 param2:(unsigned char)param2;
{
    if (cv == kMIDICVStatusNoteOn || cv == kMIDICVStatusNoteOff) {
        [log logLine:[NSString stringWithFormat:@"note %-3s - channel %02d - note %@ - velocity %d\n",
                              cv == kMIDICVStatusNoteOn ? "on" : "off" ,
                              channel,
                              [MIDIController readableNote:param1], param2]];

        [self lightNote:param1 type:cv channel:channel velocity:param2];
    } else if (cv == kMIDICVStatusControlChange) {
        if (channel == 0x00 && param1 == 0x10) {
            if (param2 & 0x04) {
                [log logLine:@"user is playing\n"];
            }
            if (param2 & 0x01) {
                [log logLine:@"playing right hand\n"];
            }
            if (param2 & 0x02) {
                [log logLine:@"playing left hand\n"];
            }
            [hid lightsOff];
        }
    }
}

@end
