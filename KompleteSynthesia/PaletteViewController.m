//
//  PaletteViewController.m
//  KompleteSynthesia
//
//  Created by Till Toenshoff on 24.01.23.
//

#import "PaletteViewController.h"
#import <CoreGraphics/CoreGraphics.h>

#import "ColorField.h"
#import "HIDController.h"

/// Provides the functionality of a palette selector.

const CGFloat kBorderSize = 7.0;

@interface PaletteViewController ()

@end

@implementation PaletteViewController

- (void)viewDidLoad
{
    [super viewDidLoad];

    // All those colors.
    const size_t tileCountVertical = kKompleteKontrolColorCount;
    // All those intensities.
    const size_t tileCountHorizontal = kKompleteKontrolColorIntensityLevelCount;
    // We want to show an additional row for lights-off/black.
    const size_t totalTileCountVertical = tileCountVertical + 1;

    const CGFloat width = self.view.frame.size.width - (kBorderSize * 2);
    const CGFloat height = self.view.frame.size.height - (kBorderSize * 2);

    CGSize tileSize = CGSizeMake(floorf(width / tileCountHorizontal), floorf(height / totalTileCountVertical));

    unsigned char index = 0;
    for (int h = 0; h < tileCountVertical; h++) {
        for (int w = 0; w < tileCountHorizontal; w++) {
            const unsigned char keyIntensity = index & kKompleteKontrolIntensityMask;
            const unsigned char keyColor = (index / kKompleteKontrolColorIntensityLevelCount) + 1;
            assert(keyColor <= kKompleteKontrolColorCount);
            const unsigned char selectableKeyState = (keyColor << 2) | keyIntensity;
            ColorField* colorField = [[ColorField alloc]
                initWithFrame:CGRectMake(self.view.frame.size.width - (((w + 1) * tileSize.width) + kBorderSize),
                                         self.view.frame.size.height - (((h + 1) * tileSize.height) + kBorderSize),
                                         tileSize.width, tileSize.height)];
            colorField.keyState = selectableKeyState;
            colorField.tag = selectableKeyState;
            colorField.target = self;
            colorField.action = @selector(keyStatePicked:);
            [self.view addSubview:colorField];
            ++index;
        }
    }

    // Last row is occupied by lights-off/black.
    ColorField* colorField =
        [[ColorField alloc] initWithFrame:CGRectMake(kBorderSize, kBorderSize, tileSize.width, tileSize.height)];
    colorField.keyState = 0;
    colorField.tag = 0;
    colorField.target = self;
    colorField.action = @selector(keyStatePicked:);
    [self.view addSubview:colorField];
}

- (void)viewWillAppear
{
    [self.view.window makeFirstResponder:[self.view viewWithTag:_keyState]];
}

- (void)keyStatePicked:(id)sender
{
    ColorField* colorField = sender;
    self.keyState = colorField.keyState;
    [self.view.window makeFirstResponder:colorField];
    if (_delegate != nil) {
        [_delegate keyStatePicked:colorField.keyState index:_index];
    }
}

@end
