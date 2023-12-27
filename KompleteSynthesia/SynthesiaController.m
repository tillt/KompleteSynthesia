//
//  SynthesiaController.m
//  KompleteSynthesia
//
//  Created by Till Toenshoff on 13.01.23.
//

#import "SynthesiaController.h"

#import <AppKit/AppKit.h>

#import "LogViewController.h"
#import "ApplicationObserver.h"

NSString* kSynthesiaApplicationName = @"Synthesia";
NSString* kSynthesiaApplicationBundleIdentifier = @"com.synthesiallc.synthesia";
NSString* kSynthesiaApplicationPath = @"/Applications/Synthesia.app";

NSString* kDefaultsKeyInitialSynthesiaAssertDone = @"initial_synthesia_config_assert_done";

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

+ (int)synthesiaWindowNumber
{
    CFArrayRef list = CGWindowListCopyWindowInfo(kCGWindowListOptionOnScreenOnly,kCGNullWindowID);
    NSArray* windows = (__bridge NSArray*)list;
    for(NSDictionary* window in windows)
    {
        NSString* currentWindowTitle = window[(NSString*)kCGWindowOwnerName];
        CGRect currentBounds;
        CGRectMakeWithDictionaryRepresentation((CFDictionaryRef)window[(NSString*)kCGWindowBounds], &currentBounds);
        
        if ([currentWindowTitle compare:@"Synthesia"] != NSOrderedSame) {
            continue;
        }
        NSLog(@"\"%s\" size=%gx%g id=%d\n", currentWindowTitle.UTF8String,
                                            currentBounds.size.width,
                                            currentBounds.size.height,
                                            [window[(NSString *)kCGWindowNumber] intValue]);
        CFRelease(list);
        return [window[(NSString*)kCGWindowNumber] intValue];
    }
    CFRelease(list);
    return 0;
}

+ (BOOL)synthesiaRunning
{
    return [ApplicationObserver applicationIsRunning:kSynthesiaApplicationBundleIdentifier];
}

+ (BOOL)synthesiaHasFocus
{
    return [ApplicationObserver applicationHasFocus:kSynthesiaApplicationBundleIdentifier];
}

+ (void)runSynthesiaWithCompletion:(void(^)(void))completion
{
    NSWorkspaceOpenConfiguration* configuration = [NSWorkspaceOpenConfiguration new];
    [configuration setPromptsUserIfNeeded: YES];
    [[NSWorkspace sharedWorkspace] openApplicationAtURL:[NSURL fileURLWithPath:kSynthesiaApplicationPath]
                                          configuration:configuration
                                      completionHandler:^(NSRunningApplication* app, NSError* error){
        dispatch_async(dispatch_get_main_queue(), ^{
            completion();
        });
    }];
}

+ (BOOL)activateSynthesia
{
    NSRunningApplication* app = [ApplicationObserver runningApplicationWithBundleIdentifier:kSynthesiaApplicationBundleIdentifier];

    if (app == nil || app.isTerminated == YES) {
        return NO;
    }

    [app activateWithOptions:NSApplicationActivateIgnoringOtherApps];

    return YES;
}

- (id)initWithLogViewController:(LogViewController*)logViewController delegate:(id)delegate
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
    }
    return self;
}

- (void)synthesiaMayHaveChangedStatus:(NSNotification*)notification
{
    [_delegate synthesiaStateUpdate:[SynthesiaController status]];
}

- (BOOL)cachedAssertSynthesiaConfiguration
{
    // If not done before, assert that Synthesia is configured the way we need it.
    NSUserDefaults *userDefaults = [NSUserDefaults standardUserDefaults];
    [userDefaults registerDefaults:@{kDefaultsKeyInitialSynthesiaAssertDone: @(NO)}];

    if ([userDefaults boolForKey:kDefaultsKeyInitialSynthesiaAssertDone] == NO) {
        [log logLine:@"Synthesia configuration needs to get validated"];
        NSString* message = nil;
        NSError* error = nil;
        if ([self assertMultiDeviceConfig:&error message:&message] == NO) {
            [log logLine:@"Failed to assert Synthesia key light loopback setup"];

            NSAlert* alert = [NSAlert alertWithError:error];
            alert.alertStyle = NSAlertStyleWarning;
            alert.messageText = message;
            [alert runModal];
            return NO;
        } else {
            [log logLine:@"Synthesia configuration validated"];
            [userDefaults setBool:YES forKey:kDefaultsKeyInitialSynthesiaAssertDone];
            return YES;
        }
    } else {
        [log logLine:@"Synthesia configuration was validated before"];
        return YES;
    }
    return YES;
}

- (BOOL)assertMultiDeviceConfig:(NSError**)error message:(NSString*_Nullable *_Nullable)message
{
    // Assert that Synthesia is configured the way we need it.
    NSOpenPanel* panel = [NSOpenPanel openPanel];
    panel.title = @"Locate Synthesia configuration file";
    panel.message = @"Please locate and select the Synthesia 'multiDevice.xml' configuration file and activate 'Open' below!";
    panel.directoryURL = [NSURL fileURLWithFileSystemRepresentation:"~/Library/Application Support/Synthesia" isDirectory:YES relativeToURL:nil];
    if ([panel runModal] != NSModalResponseOK) {
        *message = @"User canceled the file selection.";
        NSLog(@"%@", *message);
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

    NSString* kSynthesiaConfigDeviceHead = @"<OutputDevice version=\"1\" name=\"IAC Driver LoopBe\"";
    NSString* kSynthesiaConfigDeviceTail = @" enabled=\"1\" userNotes=\"0\" backgroundNotes=\"0\" metronome=\"0\" percussion=\"0\" lightChannel=\"-2\" />";
    NSString* kSynthesiaConfigListTail = @"</DeviceInfoList>";

    NSString* configurationText = [NSString stringWithCString:data.bytes
                                                     encoding:NSStringEncodingConversionAllowLossy];

    NSArray<NSString*>* configurationLines = [configurationText componentsSeparatedByString:@"\n"];
    
    NSMutableArray<NSString*>* patchedConfigurationLines = [NSMutableArray array];
    
    for (NSString* line in configurationLines) {
        if ([line rangeOfString:kSynthesiaConfigDeviceHead].location == NSNotFound) {
            [patchedConfigurationLines addObject:line];
        }
    }
    
    for (int i = 0; i < patchedConfigurationLines.count; i++) {
        if ([patchedConfigurationLines[i] rangeOfString:kSynthesiaConfigListTail].location != NSNotFound) {
            NSString* expected = [NSString stringWithFormat:@"\t%@%@", kSynthesiaConfigDeviceHead, kSynthesiaConfigDeviceTail];
            [patchedConfigurationLines insertObject:expected atIndex:i];
            break;
        }
    }
    
    NSString* output = [patchedConfigurationLines componentsJoinedByString:@"\n"];

    NSString* filename = [NSString stringWithCString:panel.URL.fileSystemRepresentation
                                            encoding:NSStringEncodingConversionAllowLossy];

    if ([output writeToFile:filename
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
