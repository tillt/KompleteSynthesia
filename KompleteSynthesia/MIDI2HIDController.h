//
//  MIDI2HIDController.h
//  KompleteSynthesia
//
//  Created by Till Toenshoff on 01.01.23.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class LogViewController;

@interface MIDI2HIDController : NSObject

@property (copy, nonatomic) NSString *status;

- (id)initWithLogController:(LogViewController*)lc error:(NSError**)error;

@end

NS_ASSUME_NONNULL_END
