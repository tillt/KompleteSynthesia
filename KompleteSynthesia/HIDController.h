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

enum {
    KKBUTTON_PLAY,
    KKBUTTON_LEFT,
    KKBUTTON_RIGHT,
    KKBUTTON_UP,
    KKBUTTON_DOWN,
    KKBUTTON_ENTER
};

@protocol HIDControllerDelegate <NSObject>
- (void)receivedKeyEvent:(const int)event;
@end

@interface HIDController : NSObject
@property (nonatomic, copy) NSString* deviceName;
@property (nonatomic, copy) NSString* status;
@property (nonatomic, assign) BOOL mk2Controller;
@property (nonatomic, assign) int keyOffset;
@property (nonatomic, assign) unsigned int keyCount;
@property (nonatomic, weak) id<HIDControllerDelegate> delegate;

- (id)initWithDelegate:(id)delegate error:(NSError**)error;
- (void)lightKey:(int)note color:(unsigned char)color;
- (void)lightsOff;
- (void)lightsSwoop;
- (BOOL)drawImage:(NSImage*)image screen:(uint8_t)screen x:(unsigned int)x y:(unsigned int)y error:(NSError**)error;
- (void)receivedReport:(unsigned char*)report;

@end

NS_ASSUME_NONNULL_END
