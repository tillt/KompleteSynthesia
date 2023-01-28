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
    BOOL dataFormatExpected;
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
    
    CGEventRef down = CGEventCreateKeyboardEvent(nil, keyCode, true);
    CGEventPost(kCGHIDEventTap, down);
    CFRelease(down);

    CGEventRef up = CGEventCreateKeyboardEvent(nil, keyCode, false);
    CGEventPost(kCGHIDEventTap, up);
    CFRelease(up);
}

+ (void)triggerVirtualAuxKeyEvents:(uint32_t)key
{
    NSLog(@"sending virtual aux key events with keyCode:%d", key);

    NSEventModifierFlags flags = 0xa00;
    uint32_t data1 = (key << 16) | (uint32_t)flags;
    
    NSEvent* ev = [NSEvent otherEventWithType:NSEventTypeSystemDefined
                                     location:NSMakePoint(0.0f, 0.0f)
                                modifierFlags:flags
                                    timestamp:0
                                 windowNumber:0
                                      context:nil
                                      subtype:8
                                        data1:data1
                                        data2:-1];
    
    CGEventPost(kCGHIDEventTap, ev.CGEvent);
    
    flags = 0xb00;
    data1 = (key << 16) | (uint32_t)flags;
    
    ev = [NSEvent otherEventWithType:NSEventTypeSystemDefined
                             location:NSMakePoint(0.0f, 0.0f)
                        modifierFlags:flags
                            timestamp:0
                         windowNumber:0
                              context:nil
                              subtype:8
                                data1:data1
                                data2:-1];

    CGEventPost(kCGHIDEventTap, ev.CGEvent);
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

- (id)initWithLogViewController:(LogViewController*)logViewController delegate:(id)delegate error:(NSError**)error;
{
    self = [super init];
    if (self) {
        _delegate = delegate;
        log = logViewController;
        dataFormatExpected = NO;
        needsConfigurationPatch = YES;

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
            [log logLine:@"Synthesia configuration needs to get validated"];

            NSString* message = nil;
            if ([self assertMultiDeviceConfig:error message:&message] == NO) {
                [log logLine:@"Failed to assert Synthesia key light loopback setup"];
                // Note, we don't fail here -- chances are the user knows what he is doing.
                NSAlert* alert = [NSAlert alertWithError:*error];
                alert.messageText = message;
                alert.alertStyle = NSAlertStyleWarning;
                [alert runModal];
            } else {
                [userDefaults setBool:YES forKey:@"initial_synthesia_config_assert_done"];
            }
        } else {
            [log logLine:@"Synthesia configuration was validated before"];
        }
    }
    return self;
}

- (void)synthesiaMayHaveChangedStatus:(NSNotification*)notification
{
    [_delegate synthesiaStateUpdate:[SynthesiaController status]];
}

- (BOOL)assertMultiDeviceConfig:(NSError**)error message:(NSString*_Nullable *_Nullable)message
{
    NSOpenPanel* panel = [NSOpenPanel openPanel];
    panel.title = @"Locate Synthesia configuration file";
    panel.message = @"Please locate and select the Synthesia 'multiDevice.xml' configuration file and activate 'Open' below!";
    panel.directoryURL = [NSURL fileURLWithFileSystemRepresentation:"~/Library/Application Support/Synthesia/multiDevice.xml" isDirectory:NO relativeToURL:nil];
    if ([panel runModal] != NSModalResponseOK) {
        NSLog(@"user canceled file selection");
        *message = @"User canceled the file selection.";
        return NO;
    }

    NSData* data = [NSData dataWithContentsOfFile:[NSString stringWithCString:panel.URL.fileSystemRepresentation encoding:NSStringEncodingConversionAllowLossy]
                                          options:NSDataReadingUncached
                                            error:error];
    if(*error) {
        NSLog(@"Error %@", *error);
        return NO;
    }
    needsConfigurationPatch = YES;
    dataFormatExpected = NO;

    NSXMLParser* parser = [[NSXMLParser alloc] initWithData:data];
    [parser setDelegate:self];
    
    if ([parser parse] == NO) {
        *error = [parser parserError];
        NSLog(@"Error %@", *error);
        return NO;
    }

    if (dataFormatExpected == NO) {
        *message = @"Synthesia configuration file does not seem to be valid - did you select the right file?";
        [log logLine:*message];
        return NO;
    }
    
    if (!needsConfigurationPatch) {
        *message = @"Synthesia configuration file seems fine as is, no patch needed.";
        [log logLine:*message];
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

    *message = @"Synthesia configuration file patched.";
    [log logLine:*message];

    return YES;
}

#pragma mark - NSXMLParser Delegate

- (void)parser:(NSXMLParser *)parser didStartElement:(NSString *)elementName namespaceURI:(NSString *)namespaceURI qualifiedName:(NSString *)qName attributes:(NSDictionary *)attributeDict
{
    if ([elementName isEqualToString:@"OutputDevice"]) {
        // We have parsed a valid XML file and that does contain an element called "OutputDevice".
        // That is hopefully good enough for us to assume that this file is what we hope it to be.
        // Total minefield that we open here -- could lead to all kinds of catastrophic results
        // if the user selected some crap. This code should really be re-written or nuked entirely.
        // This semi-"automated" patching seems super risky while the benefit isnt clear to me.
        // Hope it helps...
        dataFormatExpected = YES;
        if ([attributeDict[@"name"] compare:@"IAC Driver LoopBe"] == NSOrderedSame) {
            if ([attributeDict objectForKey:@"enabled"] == nil || [attributeDict[@"enabled"] boolValue] != YES) {
                NSLog(@"device is not enabled, we need to patch!");
            } else if ([attributeDict objectForKey:@"lightChannel"] == nil || [attributeDict[@"lightChannel"] compare:@"-2"] != NSOrderedSame) {
                NSLog(@"key lights setup not matching, we need to patch!");
            } else {
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
