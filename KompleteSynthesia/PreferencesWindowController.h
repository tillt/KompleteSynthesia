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
@class VideoController;

@protocol PreferencesDelegate <NSObject>
- (void)preferencesUpdatedActivate;
- (void)preferencesUpdatedMirror;
//- (void)preferencesUpdatedMirror:(id)sender;
- (void)preferencesUpdatedKeyState:(int)keyState forKeyIndex:(int)index;

@end

@interface PreferencesWindowController : NSWindowController<PaletteViewControllerDelegate>

@property (weak, nonatomic) IBOutlet NSTabView *tabView;
@property (weak, nonatomic) IBOutlet NSButton *forwardButtonsOnlyToSynthesia;
@property (weak, nonatomic) IBOutlet NSButton *mirrorSynthesiaToControllerScreen;
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
@property (weak, nonatomic) VideoController* video;

@property (nonatomic, weak) id<PreferencesDelegate> delegate;

- (IBAction)assertSynthesiaConfig:(id)sender;

@end

NS_ASSUME_NONNULL_END
