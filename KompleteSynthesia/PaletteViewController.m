//
//  PaletteViewController.m
//  KompleteSynthesia
//
//  Created by Till Toenshoff on 24.01.23.
//

#import "PaletteViewController.h"
#import <CoreGraphics/CoreGraphics.h>

#import "ColorField.h"

@interface PaletteViewController ()

@end

@implementation PaletteViewController
{
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    const int tileCountHorizontal = 4;
    const int tileCountVertical = 18;
    
    const CGFloat width = self.view.frame.size.width - 14.0;
    const CGFloat height = self.view.frame.size.height - 14.0;
    CGSize tileSize = CGSizeMake(floorf(width / tileCountHorizontal),
                                 floorf(height / tileCountVertical));

    // Last row is occupied by Lights-Off.
    unsigned char index = 0;
    for (int h = 0; h < tileCountVertical - 1;h++) {
        for (int w = 0; w < tileCountHorizontal;w++) {
            const unsigned char keyIntensity = index & 0x03;
            const unsigned char keyColor = (index / 4) + 1;
            assert(keyColor <= 17);
            const unsigned char selectableKeyState = (keyColor << 2) | keyIntensity;
            ColorField* colorField = [[ColorField alloc] initWithFrame:CGRectMake(self.view.frame.size.width - (((w + 1) * tileSize.width) + 7.0),
                                                                                  self.view.frame.size.height - (((h + 1) * tileSize.height) + 7.0),
                                                                                  tileSize.width,
                                                                                  tileSize.height)];
            colorField.keyState = selectableKeyState;
            colorField.tag = selectableKeyState;
            colorField.target = self;
            colorField.action = @selector(keyStatePicked:);
            [self.view addSubview:colorField];
            ++index;
        }
    }

    ColorField* colorField = [[ColorField alloc] initWithFrame:CGRectMake(7.0,
                                                                          7.0,
                                                                          tileSize.width,
                                                                          tileSize.height)];
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
