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
    BOOL paused;
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

- (void)binaryDataFromHexString:(NSString*)input withData:(unsigned char*)data withLength:(size_t)length
{
    NSArray* hexStringBytes = [input componentsSeparatedByString:@" "];
    size_t byteCount = MIN(length, hexStringBytes.count);
    for (size_t i = 0; i < byteCount; i++) {
        NSString* hex = hexStringBytes[i];
        const char* chars = [hex UTF8String];
        data[i] = strtoul(chars, NULL, 16);
    }
}

- (void)windowDidLoad
{
    [super windowDidLoad];

    _initialCommand.stringValue = [self hexStringFromBinaryData:_hidController.initialCommand
                                                     withLength:_hidController.initialCommandLength];
    _initialCommand.delegate = self;

    [_delegate preferencesUpdatedKeyState:0x00 forKeyIndex:0];

    commandUpdateTimer = [NSTimer
        scheduledTimerWithTimeInterval:kCommandUpdateTimerDelay
                               repeats:YES
                                 block:^(NSTimer* timer) {
                                   self->_currentControlCommand.stringValue =
                                       [self hexStringFromBinaryData:self->_hidController.lightGuideUpdateMessage
                                                          withLength:self->_hidController.lightGuideUpdateMessageSize];
                                 }];
    paused = NO;
    [self updateButtonStates];
}

- (void)controlTextDidEndEditing:(NSNotification*)notification
{
    NSTextField* textField = [notification object];
    if (textField != _initialCommand) {
        return;
    }
    [self binaryDataFromHexString:textField.stringValue
                         withData:_hidController.initialCommand
                       withLength:_hidController.initialCommandLength];
}

- (void)updateButtonStates
{
    if (paused) {
        _startButton.enabled = NO;
        _pauseButton.enabled = YES;
        _stopButton.enabled = YES;
    } else {
        _startButton.enabled = fuzzTimer == nil;
        _stopButton.enabled = fuzzTimer != nil;
        _pauseButton.enabled = fuzzTimer != nil;
    }
}

- (void)stopTimer
{
    if (fuzzTimer != nil) {
        [fuzzTimer invalidate];
    }
    fuzzTimer = nil;
}

- (IBAction)stop:(id)sender
{
    [self stopTimer];
    paused = NO;
    [self updateButtonStates];
}

- (IBAction)pause:(id)sender
{
    if (fuzzTimer != nil) {
        paused = YES;
        [self stopTimer];
    } else {
        paused = NO;
        [self startTimer];
    }
}

- (void)startTimer
{
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

- (IBAction)start:(id)sender
{
    _hidController.lightGuideUpdateMessage[0] = 0x01;
    [_delegate preferencesUpdatedKeyState:0x06 forKeyIndex:0];

    [self startTimer];
    paused = NO;
    [self updateButtonStates];
}

@end
