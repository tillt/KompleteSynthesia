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
@property (nonatomic, assign) CGSize screenSize;
@property (nonatomic, assign) unsigned int screenCount;
@property (nonatomic, assign) BOOL mk2Controller;

+ (NSString*)descriptionWithIOReturn:(IOReturn)code;

- (id)initWithDelegate:(id)delegate error:(NSError**)error;
- (BOOL)drawImage:(NSImage*)image screen:(uint8_t)screen x:(unsigned int)x y:(unsigned int)y error:(NSError**)error;
- (BOOL)clearScreen:(uint8_t)screen error:(NSError**)error;

@end

NS_ASSUME_NONNULL_END
