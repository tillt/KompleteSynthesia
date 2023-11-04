//
//  MIDI2HIDController.h
//  KompleteSynthesia
//
//  Created by Till Toenshoff on 01.01.23.
//

#import <Foundation/Foundation.h>
#import "HIDController.h"
#import "USBController.h"
#import "MIDIController.h"
#import "SynthesiaController.h"

NS_ASSUME_NONNULL_BEGIN

typedef enum colorMapState {
    kColorMapUnpressed = 0,
    kColorMapPressed,
    kColorMapLeft,
    kColorMapLeftThumb,
    kColorMapLeftPressed,
    kColorMapRight,
    kColorMapRightThumb,
    kColorMapRightPressed,
    kColorMapSize
} ColorMapState;

@class LogViewController;
@class SynthesiaController;

@protocol MIDI2HIDControllerDelegate <NSObject>
- (void)preferences:(id)sender;
- (void)reset:(id)sender;
@end

@interface MIDI2HIDController : NSObject <MIDIControllerDelegate, HIDControllerDelegate, SynthesiaControllerDelegate>

@property (copy, nonatomic) NSString* hidStatus;
@property (copy, nonatomic) NSString* midiStatus;

@property (assign, nonatomic) BOOL forwardButtonsToSynthesiaOnly;
@property (assign, nonatomic, readonly) unsigned char* colors;

@property (nonatomic, weak) id<MIDI2HIDControllerDelegate> delegate;

- (id)initWithLogController:(LogViewController*)lc
                   delegate:(id)delegate
                      error:(NSError**)error;

- (BOOL)resetWithError:(NSError**)error;
- (void)swoosh;
- (void)teardown;
- (void)lightsDefault;
- (void)boostrapSynthesia;
- (int)mk;

@end

NS_ASSUME_NONNULL_END
