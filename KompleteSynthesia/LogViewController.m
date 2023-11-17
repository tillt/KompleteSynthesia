//
//  LogViewController.m
//  KompleteSynthesia
//
//  Created by Till Toenshoff on 28.12.22.
//

#import "LogViewController.h"

@interface LogViewController ()
@end

@implementation LogViewController {
    NSDate* startedAt;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    startedAt = [NSDate date];
}

- (void)dealloc
{
}

- (void)logLine:(NSString*)l
{
    NSLog(@"%@", l);
    
    // Assert the view is loaded.
    NSView* view = self.view;
    // Avoid unused variable.
    view = nil;

    NSTimeInterval timeIntervalSinceStarted = -[startedAt timeIntervalSinceNow];
    
    NSDateComponentsFormatter *formatter = [[NSDateComponentsFormatter alloc] init];
    formatter.allowedUnits = NSCalendarUnitHour | NSCalendarUnitMinute | NSCalendarUnitSecond;
    formatter.zeroFormattingBehavior = NSDateComponentsFormatterZeroFormattingBehaviorPad;
    NSString* t = [formatter stringFromTimeInterval:timeIntervalSinceStarted];
    
    NSDictionary *attributes = @{
        NSFontAttributeName:[NSFont monospacedSystemFontOfSize:11.0 weight:NSFontWeightLight],
        NSForegroundColorAttributeName:NSColor.textColor
    };

    NSAttributedString *attrstr = [[NSAttributedString alloc] initWithString:[NSString stringWithFormat:@"%@  %@\n", t, l] attributes:attributes];
    [self.textView.textStorage appendAttributedString:attrstr];
    [self.textView scrollRangeToVisible: NSMakeRange(self.textView.string.length, 0)];
}

@end
