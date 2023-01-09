//
//  MIDI2HIDController.h
//  KompleteSynthesia
//
//  Created by Till Toenshoff on 01.01.23.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN


@class LogViewController;

@protocol MIDIControllerDelegate;
@protocol HIDControllerDelegate;

@interface MIDI2HIDController : NSObject <MIDIControllerDelegate, HIDControllerDelegate>

@property (copy, nonatomic) NSString* hidStatus;
@property (copy, nonatomic) NSString* midiStatus;

- (id)initWithLogController:(LogViewController*)lc error:(NSError**)error;

@end

NS_ASSUME_NONNULL_END
