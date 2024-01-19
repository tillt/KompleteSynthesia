//
//  FuzzingWindowController.m
//  KompleteSynthesia
//
//  Created by Till Toenshoff on 19.01.24.
//

#import "FuzzingWindowController.h"
#import "HIDController.h"
#import "PreferencesWindowController.h"

/// Hacked together window for getting some ideas on how to control the lightguide on MK3 devices - totally ugly!

static const NSTimeInterval kCommandUpdateTimerDelay = 0.01;
static const NSTimeInterval kFuzzTimerDelay = 0.05;

@interface FuzzingWindowController ()
@end

@implementation FuzzingWindowController {
    NSTimer* commandUpdateTimer;
    NSTimer* fuzzTimer;
}

- (NSString*)hexStringFromBinaryData:(unsigned char*)data withLength:(size_t)length
{
    NSString* output = @"";
    for (int i = 0; i < length; i++) {
        if (i > 0) {
            output = [NSString stringWithFormat:@"%@ ", output];
        }
        output = [NSString stringWithFormat:@"%@%02X", output, data[i]];
    }
    return output;
}

- (void)windowDidLoad
{
    [super windowDidLoad];

    [_delegate preferencesUpdatedKeyState:0x00 forKeyIndex:0];

    _initialCommand.stringValue = [self hexStringFromBinaryData:_hidController.initialCommand
                                                     withLength:_hidController.initialCommandLength];

    commandUpdateTimer = [NSTimer
        scheduledTimerWithTimeInterval:kCommandUpdateTimerDelay
                               repeats:YES
                                 block:^(NSTimer* timer) {
                                   self->_currentControlCommand.stringValue =
                                       [self hexStringFromBinaryData:self->_hidController.lightGuideUpdateMessage
                                                          withLength:self->_hidController.lightGuideUpdateMessageSize];
                                 }];
}

- (IBAction)stop:(id)sender
{
    if (fuzzTimer != nil) {
        [fuzzTimer invalidate];
    }
}

- (IBAction)start:(id)sender
{
    self->_hidController.lightGuideUpdateMessage[0] = 0x01;
    [_delegate preferencesUpdatedKeyState:0x06 forKeyIndex:0];

    if (fuzzTimer != nil) {
        [fuzzTimer invalidate];
    }

    fuzzTimer = [NSTimer
        scheduledTimerWithTimeInterval:kFuzzTimerDelay * _delaySlider.intValue
                               repeats:YES
                                 block:^(NSTimer* timer) {
                                   [self->_hidController initKeyboardController:nil];
                                   if (self->_hidController.lightGuideUpdateMessage[0] == 0xFF) {
                                       self->_hidController.lightGuideUpdateMessage[1] += 0x0C;
                                   }
                                   [_delegate preferencesUpdatedKeyState:self->_hidController.lightGuideUpdateMessage[1]
                                                             forKeyIndex:0];
                                   self->_hidController.lightGuideUpdateMessage[0]++;
                                 }];
}

@end
