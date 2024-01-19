//
//  FuzzingWindowController.h
//  KompleteSynthesia
//
//  Created by Till Toenshoff on 19.01.24.
//

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@class HIDController;
@protocol PreferencesDelegate;

@interface FuzzingWindowController : NSWindowController

@property (nonatomic, weak) IBOutlet NSTextField* initialCommand;
@property (nonatomic, weak) IBOutlet NSTextField* currentControlCommand;
@property (nonatomic, weak) IBOutlet NSSliderCell* delaySlider;

@property (nonatomic, weak) HIDController* hidController;

@property (nonatomic, weak) id<PreferencesDelegate> delegate;

- (IBAction)start:(id)sender;
- (IBAction)stop:(id)sender;

@end

NS_ASSUME_NONNULL_END
