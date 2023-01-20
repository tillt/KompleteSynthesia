//
//  SynthesiaController.m
//  KompleteSynthesia
//
//  Created by Till Toenshoff on 13.01.23.
//

#import "SynthesiaController.h"
#import <AppKit/AppKit.h>
#import "LogViewController.h"

NSString* kSynthesiaApplicationName = @"Synthesia";

/// Tries to locate Synthesia among the running applications and informs the delegate when the state changed.

@implementation SynthesiaController {
    BOOL needsConfigurationPatch;
    LogViewController* log;
}

+ (NSString*)status
{
    if ([SynthesiaController synthesiaHasFocus]) {
        return @"Synthesia active";
    } else if ([SynthesiaController synthesiaRunning]) {
        return @"Synthesia running";
    }
    return @"No Synthesia";
}

+ (BOOL)synthesiaRunning
{
    NSArray* apps = [[NSWorkspace sharedWorkspace] runningApplications];
    for (NSRunningApplication* app in apps) {
        if ([app.localizedName compare:kSynthesiaApplicationName] == NSOrderedSame) {
            return YES;
        }
    }
    return NO;
}

+ (BOOL)synthesiaHasFocus
{
    NSRunningApplication* app = [[NSWorkspace sharedWorkspace] frontmostApplication];
    if ([app.localizedName compare:kSynthesiaApplicationName] == NSOrderedSame) {
        return YES;
    }
    return NO;
}

+ (void)triggerVirtualKeyEvents:(CGKeyCode)keyCode
{
    NSLog(@"sending virtual key events with keyCode:%d", keyCode);
    CGEventPost(kCGHIDEventTap, CGEventCreateKeyboardEvent(nil, keyCode, true));
    CGEventPost(kCGHIDEventTap, CGEventCreateKeyboardEvent(nil, keyCode, false));
}

+ (void)triggerVirtualMouseWheelEvent:(int)distance
{
    NSLog(@"sending virtual mouse wheel event with delta:%d", distance);
    
    CGEventRef ourEvent = CGEventCreate(NULL);
    CGPoint point = CGEventGetLocation(ourEvent);
    CFRelease(ourEvent);
    
    CGEventRef event = CGEventCreateScrollWheelEvent(NULL, kCGScrollEventUnitPixel, distance, point.y, point.x);
    CGEventSetType(event, kCGEventScrollWheel);
    CGEventSetIntegerValueField(event, kCGScrollWheelEventDeltaAxis1, distance);
    CGEventPost(kCGSessionEventTap, event);
    CFRelease(event);
}

- (id)initWithLogViewController:(LogViewController*)logViewController delegate:(id)delegate;
{
    self = [super init];
    if (self) {
        needsConfigurationPatch = YES;
        _delegate = delegate;
        NSError* error = nil;
        [[[NSWorkspace sharedWorkspace] notificationCenter] addObserver:self
                                                               selector:@selector(synthesiaMayHaveChangedStatus:)
                                                                   name:NSWorkspaceDidActivateApplicationNotification
                                                                 object:nil];

        [[[NSWorkspace sharedWorkspace] notificationCenter] addObserver:self
                                                               selector:@selector(synthesiaMayHaveChangedStatus:)
                                                                   name:NSWorkspaceDidTerminateApplicationNotification
                                                                 object:nil];

        // If not done before, assert that Synthesia is configured the way we need it.
        NSUserDefaults *userDefaults = [NSUserDefaults standardUserDefaults];
        [userDefaults registerDefaults:@{@"initial_synthesia_config_assert_done": @(NO)}];

        if ([userDefaults boolForKey:@"initial_synthesia_config_assert_done"] == NO) {
            if ([self assertMultiDeviceConfig:&error] == NO) {
                [log logLine:@"failed to patch Synthesia configuration"];
            } else {
                [userDefaults setBool:YES forKey:@"initial_synthesia_config_assert_done"];
            }
        }
    }
    return self;
}

- (void)synthesiaMayHaveChangedStatus:(NSNotification*)notification
{
    [_delegate synthesiaStateUpdate:[SynthesiaController status]];
}

- (BOOL)assertMultiDeviceConfig:(NSError**)error
{
    NSOpenPanel* panel = [NSOpenPanel openPanel];
    panel.title = @"Locate Synthesia setup";
    panel.message = @"Please locate and select the Synthesia 'multiDevice.xml' configuration file and activate 'Open' below!";
    panel.directoryURL = [NSURL fileURLWithFileSystemRepresentation:"/Users/Till/Library/Application Support/Synthesia/multiDevice.xml" isDirectory:NO relativeToURL:nil];
    if ([panel runModal] != NSModalResponseOK) {
        NSLog(@"user canceled file selection");
        return NO;
    }

    NSData* data = [NSData dataWithContentsOfFile:[NSString stringWithCString:panel.URL.fileSystemRepresentation encoding:NSStringEncodingConversionAllowLossy]
                                          options:NSDataReadingUncached
                                            error:error];
    if(*error) {
        NSLog(@"Error %@", *error);
        return NO;
    }
    NSXMLParser* parser = [[NSXMLParser alloc] initWithData:data];
    [parser setDelegate:self];
    if ([parser parse] == NO) {
        *error = [parser parserError];
        NSLog(@"Error %@", *error);
        return NO;
    }
   
    if (!needsConfigurationPatch) {
        [log logLine:@"configuration seems fine as is, no patch needed"];
        return YES;
    }

    NSArray<NSString*>* configuration = [[NSString stringWithCString:data.bytes
                                                              length:data.length] componentsSeparatedByString:@"\n"];
    
    NSMutableArray* patched = [NSMutableArray array];
    for (NSString* line in configuration) {
        NSString* existingMatcher = @"<OutputDevice version=\"1\" name=\"IAC Driver LoopBe\"";
        NSUInteger location = [line rangeOfString:existingMatcher].location;
        if (location == NSNotFound) {
            [patched addObject:line];
        }
    }
    
    for (int i=0;i < patched.count;i++) {
        NSUInteger location = [patched[i] rangeOfString:@"</DeviceInfoList>"].location;
        if (location != NSNotFound) {
            NSString* expected = @"\t<OutputDevice version=\"1\" name=\"IAC Driver LoopBe\" enabled=\"1\" userNotes=\"0\" backgroundNotes=\"0\" metronome=\"0\" percussion=\"0\" lightChannel=\"-2\" />";
            [patched insertObject:expected atIndex:i];
            break;
        }
    }
    
    NSString* output = [patched componentsJoinedByString:@"\n"];

    if ([output writeToFile:[NSString stringWithCString:panel.URL.fileSystemRepresentation
                                                  encoding:NSStringEncodingConversionAllowLossy]
                           atomically:YES
                             encoding:NSNonLossyASCIIStringEncoding
                             error:error] == NO) {
        NSLog(@"Error %@", *error);
        return NO;
    }

    [log logLine:@"patched Synthesia configuration"];

    return YES;
}

#pragma mark - NSXMLParser Delegate

- (void)parser:(NSXMLParser *)parser didStartElement:(NSString *)elementName namespaceURI:(NSString *)namespaceURI qualifiedName:(NSString *)qName attributes:(NSDictionary *)attributeDict
{
    if ([elementName isEqualToString:@"OutputDevice"]) {
        if ([attributeDict[@"name"] compare:@"IAC Driver LoopBe"] == NSOrderedSame) {
            if ([attributeDict objectForKey:@"enabled"] != nil || [attributeDict[@"enabled"] boolValue] != YES) {
                NSLog(@"device is not enabled, we need to patch!");
            } else if ([attributeDict objectForKey:@"lightChannel"] != nil || [attributeDict[@"lightChannel"] compare:@"-2"] != NSOrderedSame) {
                NSLog(@"key lights setup not matching, we need to patch!");
            } else {
                NSLog(@"%@", attributeDict);
                needsConfigurationPatch = NO;
            }
        }
    }
}

- (void)parser:(NSXMLParser *)parser foundCharacters:(NSString *)string
{
}

- (void)parser:(NSXMLParser *)parser didEndElement:(NSString *)elementName namespaceURI:(NSString *)namespaceURI qualifiedName:(NSString *)qName
{
}

@end
