//
//  USBController.h
//  KompleteSynthesia
//
//  Created by Till Toenshoff on 15.01.23.
//

#import <CoreGraphics/CoreGraphics.h>
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

extern const uint32_t kVendorID_NativeInstruments;

typedef NS_ENUM(uint32_t, ProductID) {
    // MK1 controllers.
    kPID_S25MK1 = 0x1340,
    kPID_S49MK1 = 0x1350,
    kPID_S61MK1 = 0x1360,
    kPID_S88MK1 = 0x1410,
    // MK2 controllers.
    kPID_S49MK2 = 0x1610,
    kPID_S61MK2 = 0x1620,
    kPID_S88MK2 = 0x1630,
    // MK3 controllers.
    kPID_S49MK3 = 0x2100, // FIXME: NO IDEA - THESE ARE PLACEHOLDERS SO FAR
    kPID_S61MK3 = 0x2110, // Confirmed, thanks to @Bounga.
    kPID_S88MK3 = 0x2120  // FIXME: NO IDEA - THESE ARE PLACEHOLDERS SO FAR
};

@class LogViewController;

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

- (id)initWithLogViewController:(LogViewController*)lc;
- (BOOL)setupWithError:(NSError**)error;
- (BOOL)bulkWriteData:(NSData*)data error:(NSError**)error;
- (BOOL)waitForBulkTransfer:(NSTimeInterval)timeout;
- (void)teardown;

@end

NS_ASSUME_NONNULL_END
