//
//  MIDIController.h
//  KompleteSynthesia
//
//  Created by Till Toenshoff on 06.01.23.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN


@protocol MIDIControllerDelegate <NSObject>
-(void)receivedMIDIEvent:(unsigned char )cv channel:(unsigned char)channel param1:(unsigned char)control param2:(unsigned char)value;
@end

@interface MIDIController : NSObject
@property (nonatomic, weak) id<MIDIControllerDelegate> delegate;
@property (nonatomic, copy) NSString* status;
- (id)initWithDelegate:delegate error:(NSError**)error;
@end

NS_ASSUME_NONNULL_END
