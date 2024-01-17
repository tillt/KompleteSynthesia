//
//  AppDelegate.h
//  KompleteSynthesia
//
//  Created by Till Toenshoff on 28.12.22.
//

#import <Cocoa/Cocoa.h>
#import "MIDI2HIDController.h"
#import "PreferencesWindowController.h"
#import "SynthesiaController.h"

@interface AppDelegate : NSObject <NSApplicationDelegate,
                                   NSMenuDelegate,
                                   SynthesiaControllerDelegate,
                                   MIDI2HIDControllerDelegate,
                                   PreferencesDelegate>

@end
