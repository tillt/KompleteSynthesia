//
//  HIDController.h
//  KompleteSynthesia
//
//  Created by Till Toenshoff on 06.01.23.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

extern const unsigned char kKompleteKontrolColorBlue;
extern const unsigned char kKompleteKontrolColorLightBlue;
extern const unsigned char kKompleteKontrolColorGreen;
extern const unsigned char kKompleteKontrolColorLightGreen;

@interface HIDController : NSObject
@property (nonatomic, copy) NSString* deviceName;
@property (nonatomic, copy) NSString* status;
@property (nonatomic, assign) BOOL mk2Controller;
@property (nonatomic, assign) int keyOffset;
@property (nonatomic, assign) unsigned int keyCount;

- (id)init:(NSError**)error;
- (void)lightKey:(int)note color:(unsigned char)color;
- (void)lightsOff;
- (void)lightsSwoop;

@end

NS_ASSUME_NONNULL_END
