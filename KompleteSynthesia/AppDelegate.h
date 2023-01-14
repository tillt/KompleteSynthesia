//
//  AppDelegate.h
//  KompleteSynthesia
//
//  Created by Till Toenshoff on 28.12.22.
//

#import <Cocoa/Cocoa.h>

@protocol SynthesiaControllerDelegate;

@interface AppDelegate : NSObject <NSApplicationDelegate, NSMenuDelegate, SynthesiaControllerDelegate>


@end

