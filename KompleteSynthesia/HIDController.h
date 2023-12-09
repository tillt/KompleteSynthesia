//
//  HIDController.h
//  KompleteSynthesia
//
//  Created by Till Toenshoff on 06.01.23.
//

#import <Foundation/Foundation.h>
#import <Appkit/Appkit.h>

NS_ASSUME_NONNULL_BEGIN

extern const uint8_t kKompleteKontrolColorBlue;
extern const uint8_t kKompleteKontrolColorLightBlue;
extern const uint8_t kKompleteKontrolColorBrightBlue;
extern const uint8_t kKompleteKontrolColorGreen;
extern const uint8_t kKompleteKontrolColorLightGreen;
extern const uint8_t kKompleteKontrolColorBrightGreen;
extern const uint8_t kKompleteKontrolColorBrightWhite;
extern const uint8_t kKompleteKontrolColorRed;

extern const uint8_t kKompleteKontrolColorWhite;
extern const uint8_t kKompleteKontrolColorMediumWhite;
extern const uint8_t kKompleteKontrolColorBrightWhite;

extern const uint8_t kKompleteKontrolColorOrange;
extern const uint8_t kKompleteKontrolColorMediumOrange;
extern const uint8_t kKompleteKontrolColorBrightOrange;

extern const uint8_t kKompleteKontrolColorYellow;
extern const uint8_t kKompleteKontrolColorMediumYellow;
extern const uint8_t kKompleteKontrolColorBrightYellow;

extern const uint8_t kKeyColorUnpressed;
extern const uint8_t kKeyColorPressed;

extern const uint8_t kKompleteKontrolButtonLightOff;

extern const size_t kKompleteKontrolColorCount;
extern const size_t kKompleteKontrolColorIntensityLevelCount;

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
@property (assign, nonatomic) unsigned char* keys;
@property (assign, nonatomic) unsigned char* buttons;
@property (nonatomic, weak) id<HIDControllerDelegate> delegate;

+ (NSColor*)colorWithKeyState:(const unsigned char)keyState;

- (BOOL)setupWithError:(NSError**)error;

- (void)lightButton:(int)button color:(unsigned char)color;
- (void)lightKey:(int)note color:(unsigned char)color;
- (void)lightsOff;
- (void)lightKeysWithColor:(unsigned char)color;
- (void)lightsSwooshTo:(unsigned char)color;
- (BOOL)swooshIsActive;
- (void)receivedReport:(unsigned char*)report;
- (BOOL)updateButtonLightMap:(NSError**)error;

- (void)deviceRemoved;
- (unsigned char)keyColor:(int)note;

@end

NS_ASSUME_NONNULL_END
