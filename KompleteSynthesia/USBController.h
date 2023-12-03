//
//  USBController.h
//  KompleteSynthesia
//
//  Created by Till Toenshoff on 15.01.23.
//

#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

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

// MK3 controllers.
extern const uint32_t kPID_S49MK3;
extern const uint32_t kPID_S61MK3;
extern const uint32_t kPID_S88MK3;

@interface USBController : NSObject

@property (nonatomic, copy) NSString* deviceName;
@property (nonatomic, copy) NSString* status;
@property (nonatomic, assign) unsigned int keyCount;
@property (nonatomic, assign) unsigned int mk;
@property (nonatomic, assign) CGSize screenSize;
@property (nonatomic, assign) unsigned int screenCount;
@property (nonatomic, assign) BOOL connected;
@property (nonatomic, assign) uint32_t deviceInterfaceEndpoint;


+ (NSString*)descriptionWithIOReturn:(IOReturn)code;

- (id)initWithError:(NSError**)error;
- (BOOL)bulkWriteData:(NSData*)data error:(NSError**)error;
- (BOOL)waitAllowingFor:(unsigned int)count withTimeout:(NSTimeInterval)timout;
- (void)teardown;


@end

NS_ASSUME_NONNULL_END
