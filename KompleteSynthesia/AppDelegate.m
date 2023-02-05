//
//  AppDelegate.m
//  KompleteSynthesia
//
//  Created by Till Toenshoff on 28.12.22.
//

#import "AppDelegate.h"
#import "MIDI2HIDController.h"
#import "LogViewController.h"
#import "VideoController.h"
#import "PreferencesWindowController.h"
#import "ApplicationObserver.h"

@interface AppDelegate ()

@property (nonatomic, strong) IBOutlet NSWindow *window;
@property (nonatomic, strong) MIDI2HIDController* midi2hidController;
@property (nonatomic, strong) VideoController* videoController;
@property (nonatomic, strong) LogViewController* logViewController;
@property (nonatomic, strong) SynthesiaController* synthesia;
@property (nonatomic, strong) PreferencesWindowController* preferences;
@property (nonatomic, strong) ApplicationObserver* observer;

@property (nonatomic, strong) NSPopover *popover;
@property (nonatomic, strong) NSMenu *statusMenu;
@property (strong, nonatomic) NSStatusItem *statusItem;

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
}

NSString* kHardwareAgentName = @"NIHardwareAgent.app";
NSString* kHardwareAgentPath = @"/Library/Application Support/Native Instruments/Hardware/NIHardwareAgent.app";

NSString* kHostIntegrationAgentName = @"NIHostIntegrationAgent.app";
NSString* kHostIntegrationAgentPath = @"/Library/Application Support/Native Instruments/Hardware/NIHostIntegrationAgent.app";

NSString* kDaemonName = @"NTKDaemon.app";
NSString* kDaemonPath = @"/Library/Application Support/Native Instruments/NTK/NTKDaemon.app";

- (void)killNativeInstrumentsComponentsIfNeeded
{
    NSString* fmtAssert = @"asserting %@ not active";
    NSString* fmtStopped = @"stopped %@";
    NSString* fmtSkipping = @"%@ is not running";

    NSArray<NSString*>* items = @[ kHardwareAgentName, kHostIntegrationAgentName, kDaemonName ];
    
    awaitingAlienCount = 0;
    
    assert(items.count == kAlienItemCount);
    
    for (int i = 0; i < kAlienItemCount; i++) {
        [_logViewController logLine:[NSString stringWithFormat:fmtAssert, items[i]]];
        
        if ([ApplicationObserver applicationIsRunning:items[i]] == NO) {
            [self.logViewController logLine:[NSString stringWithFormat:fmtSkipping, items[i]]];
            continue;
        }
        
        ++awaitingAlienCount;
        
        restartAlien[i] = [_observer terminateApplication:items[i] completion:^{
            [self.logViewController logLine:[NSString stringWithFormat:fmtStopped, items[i]]];
            
            --awaitingAlienCount;
            
            if (awaitingAlienCount == 0) {
                [self applicationDidFinishInitializing];
            }
        }];
        
        NSLog(@"restart %@ returned %d", items[i], restartAlien[i]);
    }

    if (awaitingAlienCount == 0) {
        [self applicationDidFinishInitializing];
    }
}

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification
{
    _observer = [[ApplicationObserver alloc] initWithDelegate:self];
    _logViewController = [[LogViewController alloc] initWithNibName:@"LogViewController" bundle:NULL];
    [self killNativeInstrumentsComponentsIfNeeded];
}

- (void)applicationDidFinishInitializing
{
    NSError* error = nil;

    _synthesia = [[SynthesiaController alloc] initWithLogViewController:_logViewController
                                                               delegate:self
                                                                  error:&error];
    if (_synthesia == nil) {
        [[NSAlert alertWithError:error] runModal];
        [NSApp performSelector:@selector(terminate:) withObject:nil afterDelay:0.0];
        return;
    }
    
    _videoController = [[VideoController alloc] initWithLogViewController:_logViewController
                                                                    error:&error];
    if (_videoController == nil) {
        [[NSAlert alertWithError:error] runModal];
        [NSApp performSelector:@selector(terminate:) withObject:nil afterDelay:0.0];
        return;
    }
   
    _midi2hidController = [[MIDI2HIDController alloc] initWithLogController:_logViewController
                                                                   delegate:self
                                                                      error:&error];
    if (_midi2hidController == nil) {
        [[NSAlert alertWithError:error] runModal];
        [NSApp performSelector:@selector(terminate:) withObject:nil afterDelay:0.0];
        return;
    }
    
    NSUserDefaults *userDefaults = [NSUserDefaults standardUserDefaults];
    [userDefaults registerDefaults:@{@"forward_buttons_to_synthesia_only": @(YES)}];
    _midi2hidController.forwardButtonsToSynthesiaOnly = [userDefaults boolForKey:@"forward_buttons_to_synthesia_only"];
   
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
    
    if ([SynthesiaController synthesiaRunning] == NO) {
        [_logViewController logLine:@"Synthesia not running, starting it now"];
        [_midi2hidController boostrapSynthesia];
    }
}

- (void)preferences:(id)sender
{
    if (_preferences == nil) {
        _preferences = [[PreferencesWindowController alloc] initWithWindowNibName:@"PreferencesWindowController"];
    }
    _preferences.synthesia = _synthesia;
    _preferences.midi2hid = _midi2hidController;
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
    if ([_videoController reset:&error] == NO) {
        [[NSAlert alertWithError:error] runModal];
    }

    if ([_midi2hidController resetWithSwoosh:YES error:&error] == NO) {
        [[NSAlert alertWithError:error] runModal];
        [NSApp performSelector:@selector(terminate:) withObject:nil afterDelay:0.0];
    }
}

- (void)showLog:(id)sender
{
    if (self.popover == nil) {
        self.popover = [[NSPopover alloc] init];
        self.popover.contentViewController = _logViewController;
        self.popover.contentSize = NSMakeSize(500.0f, 300.0f);
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
    [_videoController teardown];
    [_midi2hidController teardown];
    
    NSArray<NSString*>* items = @[ kHardwareAgentPath, kHostIntegrationAgentPath, kDaemonPath ];

    assert(items.count == kAlienItemCount);

    for (int i = 0; i < kAlienItemCount; i++) {
        if (restartAlien[i]) {
            system([NSString stringWithFormat:@"open '%@'", items[i]].cString);
        }
    }
}

- (BOOL)applicationSupportsSecureRestorableState:(NSApplication *)app
{
    return YES;
}

#pragma mark SynthesiaControllerDelegate

- (void)synthesiaStateUpdate:(NSString*)status
{
    if(self.statusMenu.itemArray.count > 1) {
        NSMenuItem* item = self.statusMenu.itemArray[1];
        item.title = status;
    }
    
    [_midi2hidController synthesiaStateUpdate:status];
}

@end
