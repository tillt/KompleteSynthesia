//
//  USBController.h
//  KompleteSynthesia
//
//  Created by Till Toenshoff on 15.01.23.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

extern const uint32_t kVendorID_NativeInstruments;

// MK1 controllers.
extern const uint32_t kPID_S25MK1;
extern const uint32_t kPID_S49MK1;
extern const uint32_t kPID_S61MK1;
extern const uint32_t kPID_S88MK1;

// MK2 controllers.
extern const uint32_t kPID_S49MK2;
extern const uint32_t kPID_S61MK2;
extern const uint32_t kPID_S88MK2;


@protocol USBControllerDelegate <NSObject>
- (void)receivedSomething;
@end

@interface USBController : NSObject
@property (nonatomic, weak) id<USBControllerDelegate> delegate;
@property (nonatomic, copy) NSString* deviceName;
@property (nonatomic, copy) NSString* status;
@property (nonatomic, assign) unsigned int keyCount;
@property (nonatomic, assign) BOOL mk2Controller;

- (id)initWithDelegate:(id)delegate error:(NSError**)error;

@end

NS_ASSUME_NONNULL_END
