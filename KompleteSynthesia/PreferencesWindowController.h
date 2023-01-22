//
//  PreferencesWindowController.h
//  KompleteSynthesia
//
//  Created by Till Toenshoff on 20.01.23.
//

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@class SynthesiaController;
@class MIDI2HIDController;

@interface PreferencesWindowController : NSWindowController

@property (weak, nonatomic) IBOutlet NSTabView *tabView;
@property (weak, nonatomic) IBOutlet NSButton *forwardButtonsOnlyToSynthesia;
@property (weak, nonatomic) SynthesiaController* synthesia;
@property (weak, nonatomic) MIDI2HIDController* midi2hid;

- (IBAction)assertSynthesiaConfig:(id)sender;

@end

NS_ASSUME_NONNULL_END
