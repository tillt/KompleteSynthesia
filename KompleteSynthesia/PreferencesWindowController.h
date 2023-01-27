//
//  PreferencesWindowController.h
//  KompleteSynthesia
//
//  Created by Till Toenshoff on 20.01.23.
//

#import <Cocoa/Cocoa.h>
#import "PaletteViewController.h"
#import "ColorField.h"

NS_ASSUME_NONNULL_BEGIN

@class SynthesiaController;
@class MIDI2HIDController;

@interface PreferencesWindowController : NSWindowController<PaletteViewControllerDelegate>

@property (weak, nonatomic) IBOutlet NSTabView *tabView;
@property (weak, nonatomic) IBOutlet NSButton *forwardButtonsOnlyToSynthesia;
@property (weak, nonatomic) IBOutlet ColorField* colorUnpressed;
@property (weak, nonatomic) IBOutlet ColorField* colorPressed;
@property (weak, nonatomic) IBOutlet ColorField* colorLeft;
@property (weak, nonatomic) IBOutlet ColorField* colorRight;
@property (weak, nonatomic) IBOutlet ColorField* colorLeftThumb;
@property (weak, nonatomic) IBOutlet ColorField* colorRightThumb;
@property (weak, nonatomic) IBOutlet ColorField* colorLeftPressed;
@property (weak, nonatomic) IBOutlet ColorField* colorRightPressed;

@property (weak, nonatomic) SynthesiaController* synthesia;
@property (weak, nonatomic) MIDI2HIDController* midi2hid;

- (IBAction)assertSynthesiaConfig:(id)sender;

@end

NS_ASSUME_NONNULL_END
