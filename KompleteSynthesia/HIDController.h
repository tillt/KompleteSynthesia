//
//  HIDController.h
//  KompleteSynthesia
//
//  Created by Till Toenshoff on 06.01.23.
//

#import <Foundation/Foundation.h>
#import <Appkit/Appkit.h>

NS_ASSUME_NONNULL_BEGIN

extern const unsigned char kKompleteKontrolColorBlue;
extern const unsigned char kKompleteKontrolColorLightBlue;
extern const unsigned char kKompleteKontrolColorBrightBlue;
extern const unsigned char kKompleteKontrolColorGreen;
extern const unsigned char kKompleteKontrolColorLightGreen;
extern const unsigned char kKompleteKontrolColorBrightGreen;
extern const unsigned char kKompleteKontrolColorBrightWhite;
extern const unsigned char kKompleteKontrolColorRed;

extern const uint8_t kKeyColorUnpressed;
extern const uint8_t kKeyColorPressed;

extern const size_t kKompleteKontrolColorCount;
extern const size_t kKompleteKontrolColorIntensityLevelCount;

enum {
    KKBUTTON_PLAY,
    KKBUTTON_LEFT,
    KKBUTTON_RIGHT,
    KKBUTTON_UP,
    KKBUTTON_DOWN,
    KKBUTTON_ENTER,
    KKBUTTON_PAGE_RIGHT,
    KKBUTTON_PAGE_LEFT,
    KKBUTTON_FUNCTION1,
    KKBUTTON_FUNCTION2,
    KKBUTTON_FUNCTION3,
    KKBUTTON_FUNCTION4,
    KKBUTTON_SETUP,
    KKBUTTON_VOLUME,
    KKBUTTON_SCROLL
};
@protocol HIDControllerDelegate <NSObject>
- (void)receivedEvent:(const int)event value:(int)value;
- (void)deviceRemoved;
@end

@interface HIDController : NSObject
@property (nonatomic, copy) NSString* deviceName;
@property (nonatomic, copy) NSString* status;
@property (nonatomic, assign) BOOL mk2Controller;
@property (nonatomic, assign) int keyOffset;
@property (nonatomic, assign) unsigned int keyCount;
@property (nonatomic, weak) id<HIDControllerDelegate> delegate;

+ (NSColor*)colorWithKeyState:(const unsigned char)keyState;

- (id)initWithDelegate:(id)delegate error:(NSError**)error;
- (void)lightKey:(int)note color:(unsigned char)color;
- (void)lightsOff;
- (void)lightKeysWithColor:(unsigned char)color;
- (void)lightsSwooshTo:(unsigned char)color;
- (void)receivedReport:(unsigned char*)report;
- (void)deviceRemoved;
- (unsigned char)keyColor:(int)note;

@end

NS_ASSUME_NONNULL_END
