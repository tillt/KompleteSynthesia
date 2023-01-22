//
//  PreferencesWindowController.m
//  KompleteSynthesia
//
//  Created by Till Toenshoff on 20.01.23.
//

#import "PreferencesWindowController.h"
#import "SynthesiaController.h"
#import "MIDI2HIDController.h"

@interface PreferencesWindowController ()

@end

@implementation PreferencesWindowController

- (void)windowDidLoad
{
    [super windowDidLoad];
    
    [self.forwardButtonsOnlyToSynthesia setState:_midi2hid.forwardButtonsToSynthesiaOnly ? NSControlStateValueOn : NSControlStateValueOff];
}

- (IBAction)fowardingValueChanged:(id)sender
{
    _midi2hid.forwardButtonsToSynthesiaOnly = self.forwardButtonsOnlyToSynthesia.state == NSControlStateValueOn;
    
    NSUserDefaults *userDefaults = [NSUserDefaults standardUserDefaults];
    [userDefaults setBool:_midi2hid.forwardButtonsToSynthesiaOnly forKey:@"forward_buttons_to_synthesia_only"];
}

- (IBAction)assertSynthesiaConfig:(id)sender
{
    NSError* error = nil;
    if ([_synthesia assertMultiDeviceConfig:&error] == NO) {
        NSLog(@"failed to assert Synthesia key light loopback setup");
        [[NSAlert alertWithError:error] runModal];
    }
}

@end
