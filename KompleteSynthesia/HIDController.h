//
//  HIDController.h
//  KompleteSynthesia
//
//  Created by Till Toenshoff on 06.01.23.
//

#import <Appkit/Appkit.h>
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

extern const uint8_t kKeyColorUnpressed;
extern const uint8_t kKeyColorPressed;

extern const uint8_t kKompleteKontrolButtonLightOff;

extern const size_t kKompleteKontrolColorCount;
extern const size_t kKompleteKontrolColorIntensityLevelCount;

extern const uint8_t kKompleteKontrolIntensityMask;

typedef NS_ENUM(uint8_t, ColorIntensity) {
    kKompleteKontrolIntensityLow = 0x00,
    kKompleteKontrolIntensityMedium = 0x01,
    kKompleteKontrolIntensityHigh = 0x02,
    kKompleteKontrolIntensityBright = 0x03
};

typedef NS_ENUM(uint8_t, ColorCode) {
    kKompleteKontrolColorRed = 0x04,
    kKompleteKontrolColorOrange = 0x08,
    kKompleteKontrolColorMediumOrange = kKompleteKontrolColorOrange | kKompleteKontrolIntensityMedium,
    kKompleteKontrolColorLightOrange = kKompleteKontrolColorOrange | kKompleteKontrolIntensityHigh,
    kKompleteKontrolColorBrightOrange = kKompleteKontrolColorOrange | kKompleteKontrolIntensityBright,
    kKompleteKontrolColorYellow = 0x10,
    kKompleteKontrolColorMediumYellow = kKompleteKontrolColorYellow | kKompleteKontrolIntensityMedium,
    kKompleteKontrolColorLightYellow = kKompleteKontrolColorYellow | kKompleteKontrolIntensityHigh,
    kKompleteKontrolColorBrightYellow = kKompleteKontrolColorYellow | kKompleteKontrolIntensityBright,
    kKompleteKontrolColorGreen = 0x1C,
    kKompleteKontrolColorLightGreen = kKompleteKontrolColorGreen | kKompleteKontrolIntensityHigh,
    kKompleteKontrolColorBrightGreen = kKompleteKontrolColorGreen | kKompleteKontrolIntensityBright,
    kKompleteKontrolColorBlue = 0x2C,
    kKompleteKontrolColorLightBlue = kKompleteKontrolColorBlue | kKompleteKontrolIntensityHigh,
    kKompleteKontrolColorBrightBlue = kKompleteKontrolColorBlue | kKompleteKontrolIntensityBright,
    kKompleteKontrolColorPurple = 0x34,
    kKompleteKontrolColorPink = 0x38,
    kKompleteKontrolColorWhite = 0x44,
    kKompleteKontrolColorMediumWhite = kKompleteKontrolColorWhite | kKompleteKontrolIntensityMedium,
    kKompleteKontrolColorLightWhite = kKompleteKontrolColorWhite | kKompleteKontrolIntensityHigh,
    kKompleteKontrolColorBrightWhite = kKompleteKontrolColorWhite | kKompleteKontrolIntensityBright
};

// Carefully chosen IDs - the first 68 are reflecting the button lighting map index.
enum {
    kKompleteKontrolButtonIdM = 0,
    kKompleteKontrolButtonIdS = 1,
    kKompleteKontrolButtonIdFunction1 = 2,
    kKompleteKontrolButtonIdFunction2 = 3,
    kKompleteKontrolButtonIdFunction3 = 4,
    kKompleteKontrolButtonIdFunction4 = 5,
    kKompleteKontrolButtonIdFunction5 = 6,
    kKompleteKontrolButtonIdFunction6 = 7,
    kKompleteKontrolButtonIdFunction7 = 8,
    kKompleteKontrolButtonIdFunction8 = 9,
    kKompleteKontrolButtonIdJogLeft = 10,
    kKompleteKontrolButtonIdJogUp = 11,
    kKompleteKontrolButtonIdJogDown = 12,
    kKompleteKontrolButtonIdJogRight = 13,
    kKompleteKontrolButtonIdScaleEdit = 15,
    kKompleteKontrolButtonIdArpEdit = 16,
    kKompleteKontrolButtonIdScene = 17,
    kKompleteKontrolButtonIdUndoRedo = 18,
    kKompleteKontrolButtonIdQuantize = 19,
    kKompleteKontrolButtonIdAuto = 20,
    kKompleteKontrolButtonIdPattern = 21,
    kKompleteKontrolButtonIdPresetUp = 22,
    kKompleteKontrolButtonIdTrack = 23,
    kKompleteKontrolButtonIdLoop = 24,
    kKompleteKontrolButtonIdMetro = 25,
    kKompleteKontrolButtonIdTempo = 26,
    kKompleteKontrolButtonIdPresetDown = 27,
    kKompleteKontrolButtonIdKeyMode = 28,
    kKompleteKontrolButtonIdPlay = 29,
    kKompleteKontrolButtonIdRecord = 30,
    kKompleteKontrolButtonIdStop = 31,
    kKompleteKontrolButtonIdPageLeft = 32,
    kKompleteKontrolButtonIdPageRight = 33,
    kKompleteKontrolButtonIdClear = 34,
    kKompleteKontrolButtonIdBrowser = 35,
    kKompleteKontrolButtonIdPlugin = 36,
    kKompleteKontrolButtonIdMixer = 37,
    kKompleteKontrolButtonIdInstance = 38,
    kKompleteKontrolButtonIdMIDI = 39,
    kKompleteKontrolButtonIdSetup = 40,
    kKompleteKontrolButtonIdFixedVel = 41,
    kKompleteKontrolButtonIdUnused1 = 42,
    kKompleteKontrolButtonIdUnused2 = 43,
    kKompleteKontrolButtonIdStrip1 = 44,
    kKompleteKontrolButtonIdStrip10 = 54,
    kKompleteKontrolButtonIdStrip15 = 59,
    kKompleteKontrolButtonIdStrip20 = 64,
    kKompleteKontrolButtonIdStrip24 = 68,

    kKompleteKontrolButtonIdJogPress = 80,

    kKompleteKontrolButtonIdKnob1 = 90,
    kKompleteKontrolButtonIdKnob2 = 91,
    kKompleteKontrolButtonIdKnob3 = 92,
    kKompleteKontrolButtonIdKnob4 = 93,
    kKompleteKontrolButtonIdKnob5 = 94,
    kKompleteKontrolButtonIdKnob6 = 95,
    kKompleteKontrolButtonIdKnob7 = 96,
    kKompleteKontrolButtonIdKnob8 = 97,

    kKompleteKontrolButtonIdJogScroll = 99,
};

@class LogViewController;
@class USBController;

@protocol HIDControllerDelegate <NSObject>
- (void)receivedEvent:(const int)event value:(int)value;
- (void)deviceRemoved;
@end

@interface HIDController : NSObject
@property (nonatomic, copy) NSString* deviceName;
@property (nonatomic, copy) NSString* status;
@property (nonatomic, assign) int mk;
@property (nonatomic, assign) int keyOffset;
@property (nonatomic, assign) unsigned int keyCount;
@property (assign, nonatomic) uint8_t* keys;
@property (assign, nonatomic) uint8_t* buttons;
@property (nonatomic, weak) id<HIDControllerDelegate> delegate;

@property (assign, nonatomic) uint8_t* initialCommand;
@property (assign, nonatomic) size_t initialCommandLength;

@property (assign, nonatomic) uint8_t* lightGuideUpdateMessage;
@property (assign, nonatomic) size_t lightGuideUpdateMessageSize;

+ (NSColor*)colorWithKeyState:(const unsigned char)keyState;

- (id)initWithUSBController:(USBController*)uc logViewController:(LogViewController*)lc;

- (BOOL)setupWithError:(NSError**)error;

- (void)lightButton:(int)button color:(unsigned char)color;
- (void)buttonsOff;
- (void)lightKey:(int)note color:(unsigned char)color;
- (void)lightsOff;
- (void)lightKeysWithColor:(unsigned char)color;
- (void)lightsSwooshTo:(unsigned char)color;
- (BOOL)swooshIsActive;
- (BOOL)updateButtonLightMap:(NSError**)error;

- (BOOL)registerKeyboardController:(NSError**)error;
- (BOOL)initKeyboardController:(NSError**)error;

- (void)deviceRemoved;
- (unsigned char)keyColor:(int)note;

@end

NS_ASSUME_NONNULL_END
