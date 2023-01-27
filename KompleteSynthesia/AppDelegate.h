//
//  AppDelegate.h
//  KompleteSynthesia
//
//  Created by Till Toenshoff on 28.12.22.
//

#import <Cocoa/Cocoa.h>
#import "SynthesiaController.h"
#import "MIDI2HIDController.h"

@interface AppDelegate : NSObject <NSApplicationDelegate, NSMenuDelegate, SynthesiaControllerDelegate, MIDI2HIDControllerDelegate>


@end

