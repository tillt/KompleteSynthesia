//
//  AppDelegate.m
//  KompleteSynthesia
//
//  Created by Till Toenshoff on 28.12.22.
//

#import "AppDelegate.h"

#import "ApplicationObserver.h"
#import "CoreAudioTools.h"
#import "HIDController.h"
#import "LogViewController.h"
#import "MIDI2HIDController.h"
#import "PreferencesWindowController.h"
#import "UpdateManager.h"
#import "VideoController.h"

@interface AppDelegate ()

@property (nonatomic, strong) IBOutlet NSWindow* window;
@property (nonatomic, strong) MIDI2HIDController* midi2hidController;
@property (nonatomic, strong) VideoController* videoController;
@property (nonatomic, strong) HIDController* hidController;
@property (nonatomic, strong) MIDIController* midiController;
@property (nonatomic, strong) LogViewController* log;
@property (nonatomic, strong) SynthesiaController* synthesia;
@property (nonatomic, strong) PreferencesWindowController* preferences;
@property (nonatomic, strong) ApplicationObserver* observer;

@property (nonatomic, strong) NSPopover* popover;
@property (nonatomic, strong) NSMenu* statusMenu;
@property (strong, nonatomic) NSStatusItem* statusItem;

@end

enum {
    kAlienHardwareAgent = 0,
    kAlienHostIntegration,
    kAlienDaemon,
    kAlienItemCount
};

@implementation AppDelegate {
    BOOL restartAlien[kAlienItemCount];
    unsigned int awaitingAlienCount;
    BOOL usbAvailable;
}

NSString* kHardwareAgentName = @"NIHardwareAgent.app";
NSString* kHardwareAgentBundleIdentifier = @"com.native-instruments.NIHardwareService";
NSString* kHardwareAgentPath = @"/Library/Application Support/Native Instruments/Hardware/NIHardwareAgent.app";

NSString* kHostIntegrationAgentName = @"NIHostIntegrationAgent.app";
NSString* kHostIntegrationAgentBundleIdentifier = @"com.native-instruments.NIHostIntegrationAgent";
NSString* kHostIntegrationAgentPath = @"/Library/Application Support/Native Instruments/Hardware/NIHostIntegrationAgent.app";

NSString* kDaemonName = @"NTKDaemon.app";
NSString* kDaemonBundleIdentifier = @"com.native-instruments.NTKDaemon";
NSString* kDaemonPath = @"/Library/Application Support/Native Instruments/NTK/NTKDaemon.app";

NSString* kAppDefaultActivateSynthesia = @"forward_buttons_to_synthesia_only";
NSString* kAppDefaultMirrorSynthesia = @"mirror_synthesia_to_controller_screen";

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification
{
    usbAvailable = NO;

    _log = [[LogViewController alloc] initWithNibName:@"LogViewController" bundle:NULL];

    NSString *appName = [[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleDisplayName"];
    NSString *version = [[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleShortVersionString"];
    NSString *commit = [[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleVersion"];
    [_log logLine:[NSString stringWithFormat:@"%@ %@.%@", appName, version, commit]];

    // First thing, we assert that a bunch of interlopers are kept from interfering
    // with controlling the Native Instruments hardware.
    // That approach is rather brutal and possibly even harmful if a user was in the
    // process of running state mutating things like flashing a device firmware
    // update.

    _observer = [[ApplicationObserver alloc] init];

    NSString* fmtAssert = @"%@ is active";
    NSString* fmtStopped = @"stopped %@";
    NSString* fmtFailed = @"failed to stop %@";
    NSString* fmtSkipping = @"%@ is not running";

    NSArray<NSString*>* items = @[ kHardwareAgentBundleIdentifier, kHostIntegrationAgentBundleIdentifier, kDaemonBundleIdentifier ];
    
    awaitingAlienCount = 0;
    
    assert(items.count == kAlienItemCount);

    // Identify unwanted processes.
    for (int i = 0; i < kAlienItemCount; i++) {
        if ([ApplicationObserver applicationIsRunning:items[i]] == YES) {
            ++awaitingAlienCount;
            [_log logLine:[NSString stringWithFormat:fmtAssert, items[i]]];
        } else {
            [_log logLine:[NSString stringWithFormat:fmtSkipping, items[i]]];
        }
    }

    if (awaitingAlienCount == 0) {
        // No more processes to wait for, continue our mission with full steam!
        [self applicationDidFinishInitializingWithUSBHighwayOpen:YES];
        return;
    }

    for (int i = 0; i < kAlienItemCount; i++) {
        if ([ApplicationObserver applicationIsRunning:items[i]] == NO) {
            continue;
        }
        restartAlien[i] = [_observer terminateApplication:items[i] completion:^(BOOL complete){
            if (complete == NO) {
                [self.log logLine:[NSString stringWithFormat:fmtFailed, items[i]]];

                NSDictionary *userInfo = @{
                    NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Failed to terminate %@", items[i]],
                    NSLocalizedRecoverySuggestionErrorKey : @"USB bulk transfer is blocked, no screen updates possible."
                };
                [[NSAlert alertWithError:[NSError errorWithDomain:[[NSBundle bundleForClass:[self class]] bundleIdentifier]
                                                             code:-1
                                                         userInfo:userInfo]] runModal];

                [self applicationDidFinishInitializingWithUSBHighwayOpen:NO];
                return;
            }

            [self.log logLine:[NSString stringWithFormat:fmtStopped, items[i]]];

            --self->awaitingAlienCount;
            
            if (self->awaitingAlienCount == 0) {
                [self applicationDidFinishInitializingWithUSBHighwayOpen:YES];
            }
        }];
        NSLog(@"restart %@ returned %d", items[i], restartAlien[i]);
    }
}

- (void)applicationDidFinishInitializingWithUSBHighwayOpen:(BOOL)usbHighwayOpen
{
    usbAvailable = usbHighwayOpen;
    _synthesia = [[SynthesiaController alloc] initWithLogViewController:_log
                                                               delegate:self];
    [_synthesia cachedAssertSynthesiaConfiguration];

    if ([SynthesiaController synthesiaRunning] == NO) {
        [_log logLine:@"Synthesia not running, starting it now"];
        [self bootstrapSynthesia:self withCompletion:^(){
            [self applicationDidFinishInitializingWithSynthesiaRunning];
        }];
        return;
    }
    [self applicationDidFinishInitializingWithSynthesiaRunning];
}

- (void)applicationDidFinishInitializingWithSynthesiaRunning
{
    NSError* error = nil;

    _hidController = [[HIDController alloc] initWithLogViewController:_log];
    
    _midiController = [[MIDIController alloc] initWithLogViewController:_log];

    _midi2hidController = [[MIDI2HIDController alloc] initWithLogController:_log
                                                              hidController:_hidController
                                                             midiController:_midiController
                                                                   delegate:self];
    if (_midi2hidController == nil) {
        [[NSAlert alertWithError:error] runModal];
        [NSApp performSelector:@selector(terminate:) withObject:nil afterDelay:0.0];
        return;
    }
    
    if ([_midi2hidController resetWithError:&error] == NO) {
        [[NSAlert alertWithError:error] runModal];
        [NSApp performSelector:@selector(terminate:) withObject:nil afterDelay:0.0];
        return;
    }

    // We won't need any bulk USB access for MK1 controllers - they have no screens.
    if (_hidController.mk == 1) {
        usbAvailable = NO;
    }

    // FIXME: Actively disable USB bulk transfer on MK3 until further notice...
    if (_hidController.mk == 3) {
        usbAvailable = NO;
    }

    NSUserDefaults* userDefaults = [NSUserDefaults standardUserDefaults];

    [userDefaults registerDefaults:@{kAppDefaultActivateSynthesia: @(YES)}];
    _midi2hidController.forwardButtonsToSynthesiaOnly = [userDefaults boolForKey:kAppDefaultActivateSynthesia];

    if (usbAvailable == YES) {
        _videoController = [[VideoController alloc] initWithLogViewController:_log
                                                                        error:&error];
        if (_videoController == nil) {
            [[NSAlert alertWithError:error] runModal];
            [NSApp performSelector:@selector(terminate:) withObject:nil afterDelay:0.0];
            return;
        }

        [userDefaults registerDefaults:@{kAppDefaultMirrorSynthesia: @(YES)}];
        _videoController.mirrorSynthesiaApplicationWindow = [userDefaults boolForKey:kAppDefaultMirrorSynthesia];

        if (![_videoController reset:&error]) {
            [[NSAlert alertWithError:error] runModal];
            [NSApp performSelector:@selector(terminate:) withObject:nil afterDelay:0.0];
            return;
        }
    }
    
    // Hide application icon.
    [[NSApplication sharedApplication] setActivationPolicy:NSApplicationActivationPolicyAccessory];
    
    self.statusItem = [[NSStatusBar systemStatusBar] statusItemWithLength:NSVariableStatusItemLength];
    self.statusItem.button.action = @selector(showStatusMenu:);
    [self.statusItem.button sendActionOn:NSEventMaskLeftMouseDown | NSEventMaskRightMouseDown];
    
    NSImage *image = [NSImage imageNamed:@"StatusIcon"];
    [image setTemplate:true];
    self.statusItem.button.image = image;
    
    NSMenu *menu = [[NSMenu alloc] init];
    [menu addItemWithTitle:_midi2hidController.hidStatus action:nil keyEquivalent:@""];
    [menu addItemWithTitle:[SynthesiaController status] action:nil keyEquivalent:@""];
    [menu addItem:[NSMenuItem separatorItem]];
    [menu addItemWithTitle:@"Settings" action:@selector(preferences:) keyEquivalent:@""];
    [menu addItem:[NSMenuItem separatorItem]];
    [menu addItemWithTitle:@"Reset" action:@selector(reset:) keyEquivalent:@""];
    [menu addItemWithTitle:@"Show Log" action:@selector(showLog:) keyEquivalent:@""];
    [menu addItem:[NSMenuItem separatorItem]];
    [menu addItemWithTitle:@"Quit" action:@selector(terminate:) keyEquivalent:@"q"];
    
    menu.delegate = self;
    self.statusMenu = menu;
    
    [_midi2hidController swoosh];
    [self updateButtonStates];

    [userDefaults registerDefaults:@{kAppDefaultCheckForUpdate: @(YES)}];
    BOOL checkForUpdate = [userDefaults boolForKey:kAppDefaultCheckForUpdate];
    if (checkForUpdate) {
        [UpdateManager UpdateCheckWithCompletion:^(NSString* state) {
            NSString* message = [NSString stringWithFormat:@"update check: %@", state];
            [self.log logLine:message];
        }];
    }
}

- (void)preferences:(id)sender
{
    if (_preferences == nil) {
        _preferences = [[PreferencesWindowController alloc] initWithWindowNibName:@"PreferencesWindowController"];
        _preferences.delegate = self;
    }
    _preferences.synthesia = _synthesia;
    _preferences.midi2hid = _midi2hidController;
    _preferences.video = _videoController;

    NSWindow* window = [_preferences window];
    
    // We need to do some trickery here as the Application itself has no window. Not sure
    // if this really works in all cases but it does for me, so far.
    [[NSApplication sharedApplication] activateIgnoringOtherApps:YES];
    [window makeKeyAndOrderFront:sender];
    [[NSApplication sharedApplication] activateIgnoringOtherApps:NO];
}

- (void)showStatusMenu:(id)sender
{
    self.statusItem.menu = self.statusMenu;
    [self.statusItem.button performClick:nil];
}

- (void)reset:(id)sender
{
    NSError* error = nil;
    
    if ([_midi2hidController swooshIsActive]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self->_log logLine:@"ignoring reset request as we are still swooshing"];
        });
        return;
    }

    if (usbAvailable) {
        if ([_videoController reset:&error] == NO) {
            [[NSAlert alertWithError:error] runModal];
        }
    }

    if ([_midi2hidController resetWithError:&error] == NO) {
        [[NSAlert alertWithError:error] runModal];
        [NSApp performSelector:@selector(terminate:) withObject:nil afterDelay:0.0];
    }

    [self updateButtonStates];

    [_midi2hidController swoosh];
}

- (void)updateVolume:(id)sender
{
    _videoController.volumeValue.stringValue = [NSString stringWithFormat:@"%f", [CoreAudioTools volume]];
    [_videoController showOSD];
}

- (void)toggleMirror:(id)sender
{
    _videoController.mirrorSynthesiaApplicationWindow = !_videoController.mirrorSynthesiaApplicationWindow;
    [_videoController reset:nil];
    [self preferencesUpdatedMirror];
}

- (void)bootstrapSynthesia:(id)sender withCompletion:(void(^)(void))completion
{
    [SynthesiaController runSynthesiaWithCompletion:^{
        // This should really not be done via polling.... instead use KVO on RunningApplication.
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
            // Wait for the Synthesia window to come up.
            // TODO: I wonder if it was good enough to use KVO on application.hasLaunched - 
            // if that was good for asserting a Window was there, that would be cleaner.
            int timeoutMs = 5000;
            while (![SynthesiaController synthesiaWindowNumber] && timeoutMs) {
                [NSThread sleepForTimeInterval:0.01f];
                timeoutMs -= 10;
            };
            if (timeoutMs <= 0) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    [self->_log logLine:@"timeout waiting for Synthesia's application window"];
                });
            }
            dispatch_async(dispatch_get_main_queue(), ^{
                completion();
            });
        });
    }];
}

- (void)showLog:(id)sender
{
    if (self.popover == nil) {
        self.popover = [[NSPopover alloc] init];
        self.popover.contentViewController = _log;
        self.popover.contentSize = NSMakeSize(600.0f, 300.0f);
        self.popover.animates = YES;
        self.popover.appearance = [NSAppearance currentDrawingAppearance];
    }

    if (self.popover.isShown) {
        [self.popover performClose:sender];
    } else {
        [self.popover showRelativeToRect:self.statusItem.button.bounds ofView:self.statusItem.button preferredEdge:NSRectEdgeMinY];
        __block AppDelegate* blocksafeSelf = self;
        [NSEvent addGlobalMonitorForEventsMatchingMask:NSEventTypeLeftMouseDown | NSEventTypeRightMouseDown handler:^(NSEvent* event) {
            [blocksafeSelf.popover performClose:nil];
        }];
    }
}

- (void)applicationWillTerminate:(NSNotification *)aNotification
{
    if (usbAvailable) {
        [_videoController teardown];
    }
    [_midi2hidController teardown];
    
    NSArray<NSString*>* items = @[ kHardwareAgentPath, kHostIntegrationAgentPath, kDaemonPath ];

    assert(items.count == kAlienItemCount);

    for (int i = 0; i < kAlienItemCount; i++) {
        if (restartAlien[i]) {
            const char* command = [[NSString stringWithFormat:@"open '%@'", items[i]] cStringUsingEncoding:NSStringEncodingConversionAllowLossy];
            system(command);
        }
    }
}

- (BOOL)applicationSupportsSecureRestorableState:(NSApplication *)app
{
    return YES;
}

- (void)updateButtonStates
{
    BOOL synthesiaRunning = [SynthesiaController synthesiaRunning];

    [_midi2hidController.hid lightButton:kKompleteKontrolButtonIdScene
                                   color:synthesiaRunning ? kKompleteKontrolButtonLightOff : kKompleteKontrolColorWhite];

    [_midi2hidController.hid lightButton:kKompleteKontrolButtonIdFunction1
                                   color:synthesiaRunning ? kKompleteKontrolColorMediumOrange : kKompleteKontrolButtonLightOff];

    [_midi2hidController.hid lightButton:kKompleteKontrolButtonIdClear
                                   color:synthesiaRunning ? kKompleteKontrolColorWhite : kKompleteKontrolButtonLightOff];

    [_midi2hidController.hid lightButton:kKompleteKontrolButtonIdFunction5
                                   color:_videoController.mirrorSynthesiaApplicationWindow ? kKompleteKontrolColorMediumYellow : kKompleteKontrolColorYellow];

    [_midi2hidController.hid updateButtonLightMap:nil];
}

#pragma mark SynthesiaControllerDelegate

- (void)synthesiaStateUpdate:(NSString*)status
{
    if(self.statusMenu.itemArray.count > 1) {
        NSMenuItem* item = self.statusMenu.itemArray[1];
        item.title = status;
    }
    [self updateButtonStates];
}

#pragma mark PreferencesDelegate

- (void)preferencesUpdatedActivate
{
    NSUserDefaults* userDefaults = [NSUserDefaults standardUserDefaults];
    [userDefaults setBool:_midi2hidController.forwardButtonsToSynthesiaOnly
                   forKey:kAppDefaultActivateSynthesia];
}

- (void)preferencesUpdatedUpdates:(BOOL)enabled
{
    NSUserDefaults* userDefaults = [NSUserDefaults standardUserDefaults];
    [userDefaults setBool:enabled
                   forKey:kAppDefaultCheckForUpdate];
}

- (void)preferencesUpdatedMirror
{
    NSUserDefaults* userDefaults = [NSUserDefaults standardUserDefaults];
    [userDefaults setBool:_videoController.mirrorSynthesiaApplicationWindow
                   forKey:kAppDefaultMirrorSynthesia];
    [self updateButtonStates];
}

- (void)preferencesUpdatedKeyState:(int)keyState forKeyIndex:(int)index
{
    NSArray<NSString*>* userDefaultKeys = @[ @"kColorMapUnpressed",
                                             @"kColorMapPressed",
                                             @"kColorMapLeft",
                                             @"kColorMapLeftThumb",
                                             @"kColorMapLeftPressed",
                                             @"kColorMapRight",
                                             @"kColorMapRightThumb",
                                             @"kColorMapRightPressed" ];

    NSUserDefaults* userDefaults = [NSUserDefaults standardUserDefaults];
    [userDefaults setInteger:keyState forKey:userDefaultKeys[index]];
}

@end
