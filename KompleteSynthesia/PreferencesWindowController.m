//
//  PreferencesWindowController.m
//  KompleteSynthesia
//
//  Created by Till Toenshoff on 20.01.23.
//

#import "PreferencesWindowController.h"
#import "SynthesiaController.h"
#import "MIDI2HIDController.h"

/// Preferences window controller.

@interface PreferencesWindowController ()
@end

@implementation PreferencesWindowController {
    NSArray<ColorField*>* controls;
    NSArray<NSString*>* userDefaultKeys;

    PaletteViewController* paletteViewController;
}

- (void)windowDidLoad
{
    [super windowDidLoad];
    
    controls = @[ _colorUnpressed,
                  _colorPressed,
                  _colorLeft,
                  _colorLeftThumb,
                  _colorLeftPressed,
                  _colorRight,
                  _colorRightThumb,
                  _colorRightPressed ];

    userDefaultKeys = @[ @"kColorMapUnpressed",
                         @"kColorMapPressed",
                         @"kColorMapLeft",
                         @"kColorMapLeftThumb",
                         @"kColorMapLeftPressed",
                         @"kColorMapRight",
                         @"kColorMapRightThumb",
                         @"kColorMapRightPressed" ];
    
    for (int key = 0;key < controls.count;key++) {
        ColorField* colorField = controls[key];
        colorField.keyState = _midi2hid.colors[key];
        colorField.rounded = YES;
    }

    [self.forwardButtonsOnlyToSynthesia setState:_midi2hid.forwardButtonsToSynthesiaOnly ? NSControlStateValueOn : NSControlStateValueOff];
}

- (IBAction)selectKeyState:(id)sender
{
    if (sender == nil || ![controls containsObject:sender]) {
        return;
    }
    ColorField* colorField = sender;
    
    if (paletteViewController == nil) {
        paletteViewController = [[PaletteViewController alloc] initWithNibName:@"PaletteViewController" bundle:NULL];
        paletteViewController.delegate = self;
    }
    paletteViewController.keyState = colorField.keyState;
    
    NSInteger key = [controls indexOfObject:colorField];
    assert(key != NSNotFound);
    assert(key < kColorMapSize);
    paletteViewController.index = key;

    NSPopover* popOver = [NSPopover new];
    popOver.contentViewController = paletteViewController;
    popOver.contentSize = paletteViewController.view.bounds.size;
    popOver.animates = YES;
    // TODO: Recent macOS versions appear to have tinkered on the popover effect views,
    // making the colors appear much lighter than they should be. We need to fall
    // back to aqua appaerance or do much more elaborate things.
    popOver.appearance = [NSAppearance appearanceNamed:NSAppearanceNameDarkAqua];
    popOver.behavior = NSPopoverBehaviorTransient;
    [popOver showRelativeToRect:colorField.frame ofView:[self.window contentView] preferredEdge:NSMaxXEdge];
}

- (void)keyStatePicked:(const unsigned char)keyState index:(const unsigned char)index
{
    NSLog(@"picked key state %02Xh for map index %d", keyState, index);

    assert(index < kColorMapSize);
    _midi2hid.colors[index] = keyState;
    if (index == 0) {
        [_midi2hid lightsDefault];
    }

    assert(controls.count > index);
    ColorField* colorField = controls[index];
    colorField.keyState = keyState;
    [colorField setNeedsDisplay:YES];

    NSUserDefaults *userDefaults = [NSUserDefaults standardUserDefaults];
    [userDefaults setInteger:keyState forKey:userDefaultKeys[index]];
}

- (IBAction)fowardingValueChanged:(id)sender
{
    _midi2hid.forwardButtonsToSynthesiaOnly = self.forwardButtonsOnlyToSynthesia.state == NSControlStateValueOn;
    
    NSUserDefaults *userDefaults = [NSUserDefaults standardUserDefaults];
    [userDefaults setBool:_midi2hid.forwardButtonsToSynthesiaOnly 
                   forKey:@"forward_buttons_to_synthesia_only"];
}

- (IBAction)assertSynthesiaConfig:(id)sender
{
    NSError* error = nil;
    NSString* message = nil;
    if ([_synthesia assertMultiDeviceConfig:&error message:&message] == NO) {
        NSLog(@"failed to assert Synthesia key light loopback setup");
        NSAlert* alert = [NSAlert alertWithError:error];
        alert.alertStyle = NSAlertStyleWarning;
        alert.messageText = message;
        [alert runModal];
    } else {
        [[NSUserDefaults standardUserDefaults] setBool:YES 
                                                forKey:@"initial_synthesia_config_assert_done"];
        if (message != nil) {
            NSAlert* alert = [NSAlert new];
            alert.messageText = message;
            alert.alertStyle = NSAlertStyleInformational;
            [alert runModal];
        }
    }
}

@end
