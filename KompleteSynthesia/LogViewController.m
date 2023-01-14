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
    NSTimeInterval startTime;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    startTime = [NSDate timeIntervalSinceReferenceDate];
}

- (void)dealloc
{
}

- (void)logLine:(NSString*)l
{
    NSLog(l);
    
    // Assert the view is loaded.
    NSView* view = self.view;
    // Avoid unused variable.
    view = nil;

    NSDate* date = [NSDate dateWithTimeIntervalSinceNow:startTime];
    
    NSDateFormatter *dateFormatter = [[NSDateFormatter alloc] init];
    [dateFormatter setDateFormat:@"hh:mm:ss:SSS"];
    NSString* t = [dateFormatter stringFromDate:date];
    
    NSDictionary *attributes = @{
        NSFontAttributeName: [NSFont monospacedSystemFontOfSize:11 weight:NSFontWeightLight],
        NSForegroundColorAttributeName: NSColor.textColor
    };
    NSAttributedString *attrstr = [[NSAttributedString alloc] initWithString:[NSString stringWithFormat:@"%@: %@\n", t, l] attributes:attributes];
    [self.textView.textStorage appendAttributedString:attrstr];
    [self.textView scrollRangeToVisible: NSMakeRange(self.textView.string.length, 0)];
}

@end
