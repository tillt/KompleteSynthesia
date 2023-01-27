//
//  MIDI2HIDController.m
//  KompleteSynthesia
//
//  Created by Till Toenshoff on 01.01.23.
//

#import "MIDI2HIDController.h"
#import <CoreFoundation/CoreFoundation.h>
#import <CoreMIDI/CoreMIDI.h>
#import <CoreServices/CoreServices.h>
#import "LogViewController.h"
#import "SynthesiaController.h"

const CGKeyCode kVK_ANSI_Z = 0x06;
const CGKeyCode kVK_ANSI_X = 0x07;
const CGKeyCode kVK_Return = 0x24;
const CGKeyCode kVK_Space = 0x31;
const CGKeyCode kVK_PageUp = 0x74;
const CGKeyCode kVK_F1 = 0x7A;
const CGKeyCode kVK_F2 = 0x78;
const CGKeyCode kVK_F3 = 0x63;
const CGKeyCode kVK_F4 = 0x76;
const CGKeyCode kVK_PageDown = 0x79;
const CGKeyCode kVK_ArrowLeft = 0x7B;
const CGKeyCode kVK_ArrowRight = 0x7C;
const CGKeyCode kVK_ArrowDown = 0x7D;
const CGKeyCode kVK_ArrowUp = 0x7E;

const unsigned char kKeyStateRight = 0x02;
const unsigned char kKeyStateLeft = 0x04;

const unsigned char kKeyStateMaskOn = 0x01;
const unsigned char kKeyStateMaskHand = (kKeyStateLeft | kKeyStateRight);
const unsigned char kKeyStateMaskThumb = 0x08;
const unsigned char kKeyStateMaskUser = 0x10;
const unsigned char kKeyStateMaskMusic = 0x20;

@interface MIDI2HIDController ()
@end

///
/// Detects a Native Instruments keyboard controller USB device. Listens on the "LoopBe" MIDI input interface port.
/// Notes received are forwarded to the keyboard controller USB device as key lighting requests adhering to the Synthesia
/// protocol.
///
/// The initial approach and implementation was closely following a neat little Python project called
/// https://github.com/ojacques/SynthesiaKontrol
/// Kudos to you Olivier Jacques for sharing!
///
/// The inspiration for re-implementing this as a native macOS appllication struck me when I had a bit of a hard time getting
/// that original Python project to build on a recent system as it would not run on anything beyond Python 3.7 for me.
///
/// TODO: Fully implement MK1 support. Sorry, too lazy and no way to test.
///
///


@implementation MIDI2HIDController {
    LogViewController* log;
    MIDIController* midi;
    HIDController* hid;
    USBController* usb;

    unsigned char keyStates[255];
    unsigned char colorMap[kColorMapSize];
}

- (id)initWithLogController:(LogViewController*)lc delegate:(id)delegate error:(NSError**)error
{
    self = [super init];
    if (self) {
        log = lc;
        
        _delegate = delegate;

        NSUserDefaults *userDefaults = [NSUserDefaults standardUserDefaults];

        [userDefaults registerDefaults:@{@"kColorMapUnpressed": @(kKeyColorUnpressed)}];
        colorMap[kColorMapUnpressed] = (unsigned char)[userDefaults integerForKey:@"kColorMapUnpressed"];

        [userDefaults registerDefaults:@{@"kColorMapPressed": @(kKeyColorPressed)}];
        colorMap[kColorMapPressed] = (unsigned char)[userDefaults integerForKey:@"kColorMapPressed"];

        [userDefaults registerDefaults:@{@"kColorMapLeft": @(kKompleteKontrolColorBlue)}];
        colorMap[kColorMapLeft] = (unsigned char)[userDefaults integerForKey:@"kColorMapLeft"];

        [userDefaults registerDefaults:@{@"kColorMapLeftThumb": @(kKompleteKontrolColorLightBlue)}];
        colorMap[kColorMapLeftThumb] = (unsigned char)[userDefaults integerForKey:@"kColorMapLeftThumb"];

        [userDefaults registerDefaults:@{@"kColorMapLeftPressed": @(kKompleteKontrolColorBrightBlue)}];
        colorMap[kColorMapLeftPressed] = (unsigned char)[userDefaults integerForKey:@"kColorMapLeftPressed"];

        [userDefaults registerDefaults:@{@"kColorMapRight": @(kKompleteKontrolColorGreen)}];
        colorMap[kColorMapRight] = (unsigned char)[userDefaults integerForKey:@"kColorMapRight"];

        [userDefaults registerDefaults:@{@"kColorMapRightThumb": @(kKompleteKontrolColorLightGreen)}];
        colorMap[kColorMapRightThumb] = (unsigned char)[userDefaults integerForKey:@"kColorMapRightThumb"];

        [userDefaults registerDefaults:@{@"kColorMapRightPressed": @(kKompleteKontrolColorBrightGreen)}];
        colorMap[kColorMapRightPressed] = (unsigned char)[userDefaults integerForKey:@"kColorMapRightPressed"];

        if ([self reset:error] == NO) {
            return nil;
        }
    }
    
    return self;
}

- (unsigned char*)colors
{
    return colorMap;
}

//#define USB_DEVICE_SHIZZLE

- (BOOL)reset:(NSError**)error
{
#ifdef USB_DEVICE_SHIZZLE
    usb = [[USBController alloc] initWithDelegate:self error:error];
    if (usb == nil) {
        return NO;
    }
    [log logLine:[NSString stringWithFormat:@"detected %@ USB device", usb.deviceName]];
#endif

    hid = [[HIDController alloc] initWithDelegate:self error:error];
    if (hid == nil) {
        return NO;
    }
    [log logLine:[NSString stringWithFormat:@"detected %@ HID device", hid.deviceName]];

    midi = [[MIDIController alloc] initWithDelegate:self error:error];
    if (midi == nil) {
        return NO;
    }

    [hid lightsSwooshTo:colorMap[kColorMapUnpressed]];

    return YES;
}

- (void)teardown
{
    [hid lightsOff];
}

- (NSString*)hidStatus
{
    return hid.status;
}

- (NSString*)midiStatus
{
    return [NSString stringWithFormat:@"MIDI: %@", midi.status];
}

- (unsigned char)lightColorWithState:(unsigned char)state
{
    if ((state & kKeyStateMaskOn) == 0x00) {
        return colorMap[kColorMapUnpressed];
    }
    unsigned char index = kColorMapUnpressed;
    if ((state & kKeyStateMaskHand) == kKeyStateLeft) {
        if (state & kKeyStateMaskUser) {
            index = kColorMapLeftPressed;
        } else if ((state & kKeyStateMaskThumb) == kKeyStateMaskThumb) {
            index = kColorMapLeftThumb;
        } else {
            index = kColorMapLeft;
        }
    } else if ((state & kKeyStateMaskHand) == kKeyStateRight) {
        if (state & kKeyStateMaskUser) {
            index = kColorMapRightPressed;
        } else if ((state & kKeyStateMaskThumb) == kKeyStateMaskThumb) {
            index = kColorMapRightThumb;
        } else {
            index = kColorMapRight;
        }
    } else if (state & kKeyStateMaskUser) {
        index = kColorMapPressed;
    }
    return colorMap[index];
}

- (void)lightsDefault
{
    memset(keyStates, 0, sizeof(keyStates));
    [hid lightKeysWithColor:colorMap[kColorMapUnpressed]];
}

/// The Synthesia lighting loopback interface expects the Synthesia "Per Channel"  lighting protocol:
///  channel 0 = unknown
///  channel 1 = left hand, thumb
///  channel 2-5 = left hand
///  channel 6 = right hand, thumb
///  channel 7-10 = right hand
///  channel 11 = left hand, unknown finger
///  channel 12 = left hand, unknown finger
- (void)lightNote:(unsigned int)note
           status:(unsigned int)status
          channel:(unsigned int)channel
         velocity:(unsigned int)velocity
        interface:(unsigned int)interface
{
    int key = note + hid.keyOffset;

    if (key < 0 || key > hid.keyCount) {
        NSLog(@"unexpected note lighting requested for key %d", key);
        return;
    }
    switch(interface) {
        case 0:
        {
            unsigned char state = kKeyStateMaskOn;
            unsigned char hand = kKeyStateRight;
            if (channel == 0) {
                // We do not know who or what this note belongs to,
                // but light something up anyway.
                hand = kKeyStateRight;
            } else if (channel >= 1 && channel <= 5) {
                // Left hand fingers, thumb through pinky.
                hand = kKeyStateLeft;
                if (channel == 1) {
                    state |= kKeyStateMaskThumb;
                }
            }
            // Right hand fingers, thumb through pinky.
            if (channel >= 6 && channel <= 10) {
                hand = kKeyStateRight;
                if (channel == 6) {
                    state |= kKeyStateMaskThumb;
                }
            }
            // Left hand, unknown finger.
            if (channel == 11) {
                hand = kKeyStateLeft;
            }
            // Right hand, unknown finger.
            if (channel == 12) {
                hand = kKeyStateRight;
            }
            if (status == kMIDICVStatusNoteOn && velocity > 0) {
                keyStates[key] |= hand | state;
            } else if (status == kMIDICVStatusNoteOff || velocity == 0) {
                keyStates[key] &= ((kKeyStateMaskHand | kKeyStateMaskThumb) ^ 0xFF);
            }
            break;
        }
        case 1:
            if (status == kMIDICVStatusNoteOn && velocity > 0) {
                keyStates[key] |= kKeyStateMaskOn | kKeyStateMaskUser;
            } else if (status == kMIDICVStatusNoteOff || velocity == 0) {
                keyStates[key] &= (kKeyStateMaskUser ^ 0xFF);
            }
            break;
    }
    
    [hid lightKey:key color:[self lightColorWithState:keyStates[key]]];
}

#pragma mark MIDIControllerDelegate

-(void)receivedMIDIEvent:(unsigned char)cv
                 channel:(unsigned char)channel
                  param1:(unsigned char)param1
                  param2:(unsigned char)param2
               interface:(unsigned char)interface;
{
    if (cv != kMIDICVStatusNoteOn && cv != kMIDICVStatusNoteOff && cv != kMIDICVStatusControlChange) {
        return;
    }

    if (cv == kMIDICVStatusNoteOn || cv == kMIDICVStatusNoteOff) {
        [self lightNote:param1 status:cv channel:channel velocity:param2 interface:interface];
    } else if (cv == kMIDICVStatusControlChange && channel == 0x00 && param1 == 0x10) {
        [self lightsDefault];
    }

    // Logging (UI related) has to happen on the main thread and this callback is invoked
    // on a CoreMidi thread.
    dispatch_async(dispatch_get_main_queue(), ^{
        if (cv == kMIDICVStatusNoteOn || cv == kMIDICVStatusNoteOff) {
            [log logLine:[NSString stringWithFormat:@"port %d - note %-3s - channel %02d - note %@ - velocity %d",
                          interface,
                          cv == kMIDICVStatusNoteOn ? "on" : "off" ,
                          channel + 1,
                          [MIDIController readableNote:param1],
                          param2]];
        } else if (cv == kMIDICVStatusControlChange) {
            if (channel == 0x00 && param1 == 0x10) {
                if (param2 & 0x04) {
                    [log logLine:@"user is playing"];
                }
                if (param2 & 0x01) {
                    [log logLine:@"playing right hand"];
                }
                if (param2 & 0x02) {
                    [log logLine:@"playing left hand"];
                }
            }
        }
    });
}

#pragma mark HIDControllerDelegate

- (void)deviceRemoved
{
    [log logLine:@"HID device removed"];
    
    NSError* error = nil;
    if ([self reset:&error] == NO) {
        [[NSAlert alertWithError:error] runModal];
        [NSApp performSelector:@selector(terminate:) withObject:nil afterDelay:0.0];
        return;
    }
}

- (void)receivedEvent:(const int)event value:(int)value
{
    // The SETUP button shall work in all cases as it is not intended to control Synthesia
    // but KompleteSynthesia.
    if (event == KKBUTTON_SETUP) {
        [log logLine:@"SETUP -> opening setup"];
        [_delegate preferences:self];
        return;
    }
    
    if  (_forwardButtonsToSynthesiaOnly) {
        if (![SynthesiaController synthesiaHasFocus]) {
            [log logLine:@"Synthesia not in foreground"];
            return;
        }
    }

    switch(event) {
        case KKBUTTON_PLAY:
            [log logLine:@"PLAY button -> sending SPACE key"];
            [SynthesiaController triggerVirtualKeyEvents:kVK_Space];
            break;
        case KKBUTTON_ENTER:
            [log logLine:@"ENTER -> sending RETURN key"];
            [SynthesiaController triggerVirtualKeyEvents:kVK_Return];
            break;
        case KKBUTTON_LEFT:
            [log logLine:@"CURSOR LEFT -> sending ARROW LEFT key"];
            [SynthesiaController triggerVirtualKeyEvents:kVK_ArrowLeft];
            break;
        case KKBUTTON_RIGHT:
            [log logLine:@"CURSOR RIGHT -> sending ARROW RIGHT key"];
            [SynthesiaController triggerVirtualKeyEvents:kVK_ArrowRight];
            break;
        case KKBUTTON_UP:
            [log logLine:@"CURSOR UP -> sending ARROW UP key"];
            [SynthesiaController triggerVirtualKeyEvents:kVK_ArrowUp];
            break;
        case KKBUTTON_PAGE_LEFT:
            [log logLine:@"PAGE LEFT -> sending PAGE UP key"];
            [SynthesiaController triggerVirtualKeyEvents:kVK_ANSI_Z];
            break;
        case KKBUTTON_PAGE_RIGHT:
            [log logLine:@"PAGE RIGHT -> sending PAGE DOWN key"];
            [SynthesiaController triggerVirtualKeyEvents:kVK_ANSI_X];
            break;
        case KKBUTTON_DOWN:
            [log logLine:@"CURSOR DOWN -> sending ARROW DOWN key"];
            [SynthesiaController triggerVirtualKeyEvents:kVK_ArrowDown];
            break;
        case KKBUTTON_FUNCTION1:
            [log logLine:@"FUNCTION1 -> sending F1 key"];
            [SynthesiaController triggerVirtualKeyEvents:kVK_F1];
            break;
        case KKBUTTON_FUNCTION2:
            [log logLine:@"FUNCTION2 -> sending F2 key"];
            [SynthesiaController triggerVirtualKeyEvents:kVK_F2];
            break;
        case KKBUTTON_FUNCTION3:
            [log logLine:@"FUNCTION3 -> sending F3 key"];
            [SynthesiaController triggerVirtualKeyEvents:kVK_F3];
            break;
        case KKBUTTON_FUNCTION4:
            [log logLine:@"FUNCTION4 -> sending F4 key"];
            [SynthesiaController triggerVirtualKeyEvents:kVK_F4];
            break;
        case KKBUTTON_SCROLL:
            [log logLine:@"SCROLL -> sending mouse WHEEL"];
            [SynthesiaController triggerVirtualMouseWheelEvent:-value];
            break;
    }
}

@end
