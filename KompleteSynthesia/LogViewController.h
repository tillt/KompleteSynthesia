//
//  LogViewController.h
//  KompleteSynthesia
//
//  Created by Till Toenshoff on 28.12.22.
//

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@interface LogViewController : NSViewController
@property (weak, nonatomic) IBOutlet NSTextView *textView;

- (void)logLine:(NSString*)l;
- (void)dispatchLogLine:(NSString*)l;

@end

NS_ASSUME_NONNULL_END
