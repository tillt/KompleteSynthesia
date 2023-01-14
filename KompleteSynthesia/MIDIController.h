//
//  MIDIController.h
//  KompleteSynthesia
//
//  Created by Till Toenshoff on 06.01.23.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

extern const int kMIDIConnectionInterfaceLightLoopback;
extern const int kMIDIConnectionInterfaceKeyboard;

@protocol MIDIControllerDelegate <NSObject>
-(void)receivedMIDIEvent:(unsigned char)cv
                 channel:(unsigned char)channel
                  param1:(unsigned char)param1
                  param2:(unsigned char)param2
               interface:(unsigned char)interface;
@end

@interface MIDIController : NSObject
@property (nonatomic, weak) id<MIDIControllerDelegate> delegate;
@property (nonatomic, copy) NSString* status;

+ (NSString*)readableNote:(unsigned char)note;
- (id)initWithDelegate:delegate error:(NSError**)error;
@end

NS_ASSUME_NONNULL_END
