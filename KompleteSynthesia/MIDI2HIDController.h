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

NS_ASSUME_NONNULL_BEGIN

enum {
    kColorMapUnpressed = 0,
    kColorMapPressed,
    kColorMapLeft,
    kColorMapLeftThumb,
    kColorMapLeftPressed,
    kColorMapRight,
    kColorMapRightThumb,
    kColorMapRightPressed,
    kColorMapSize
};

@class LogViewController;

@interface MIDI2HIDController : NSObject <MIDIControllerDelegate, HIDControllerDelegate>

@property (copy, nonatomic) NSString* hidStatus;
@property (copy, nonatomic) NSString* midiStatus;

@property (assign, nonatomic) BOOL forwardButtonsToSynthesiaOnly;
@property (assign, nonatomic) unsigned char* colors;

- (id)initWithLogController:(LogViewController*)lc error:(NSError**)error;
- (BOOL)reset:(NSError**)error;
- (void)teardown;
- (void)lightsDefault;

@end

NS_ASSUME_NONNULL_END
