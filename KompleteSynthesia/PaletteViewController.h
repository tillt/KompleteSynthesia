//
//  PaletteViewController.h
//  KompleteSynthesia
//
//  Created by Till Toenshoff on 24.01.23.
//

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@protocol PaletteViewControllerDelegate <NSObject>
- (void)keyStatePicked:(const unsigned char)keyState index:(const unsigned char)index;
@end

@interface PaletteViewController : NSViewController

@property (nonatomic, weak) id<PaletteViewControllerDelegate> delegate;
@property (nonatomic, assign) unsigned char index;
@property (nonatomic, assign) unsigned char keyState;

@end

NS_ASSUME_NONNULL_END
