//
//  AppDelegate.m
//  KompleteSynthesia
//
//  Created by Till Toenshoff on 28.12.22.
//

#import "AppDelegate.h"
#import "MIDI2HIDController.h"
#import "LogViewController.h"

@interface AppDelegate ()

@property (strong) IBOutlet NSWindow *window;
@property (strong) MIDI2HIDController* midi2hidController;
@property (strong) LogViewController* logViewController;

@property (nonatomic, strong) NSPopover *popover;
@property (nonatomic, strong) NSMenu *statusMenu;
@property (strong, nonatomic) NSStatusItem *statusItem;

@end

@implementation AppDelegate

- (void)updateStatusItemImage
{
}

- (void)updateStatusItemMenu
{
    NSMenuItem *item = self.statusMenu.itemArray[0];
    item.title = _midi2hidController.status;
}

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification {
    self.statusItem = [[NSStatusBar systemStatusBar] statusItemWithLength:NSVariableStatusItemLength];
    
    self.statusItem.button.action = @selector(showStatusMenu:);
    [self.statusItem.button sendActionOn:NSEventMaskLeftMouseDown | NSEventMaskRightMouseDown];
    NSImage *image = [NSImage imageNamed:@"StatusIcon"];
    [image setTemplate:true];
    self.statusItem.button.image = image;

    NSMenu *menu = [[NSMenu alloc] init];
    [menu addItemWithTitle:@"unknown" action:nil keyEquivalent:@""];
    [menu addItem:[NSMenuItem separatorItem]];
    [menu addItemWithTitle:@"Show Log" action:@selector(showLog:) keyEquivalent:@""];
    [menu addItemWithTitle:@"Quit" action:@selector(terminate:) keyEquivalent:@"q"];

    menu.delegate = self;
    self.statusMenu = menu;

    _logViewController = [[LogViewController alloc] initWithNibName:@"LogViewController" bundle:NULL];

    NSError* error = nil;
    _midi2hidController = [[MIDI2HIDController alloc] initWithLogController:_logViewController error:&error];
    if (_midi2hidController == nil) {
        [[NSAlert alertWithError:error] runModal];
        return;
    }

    [self updateStatusItemMenu];

    // Hide application icon.
    [[NSApplication sharedApplication] setActivationPolicy:NSApplicationActivationPolicyAccessory];
}

- (void)statusItemClicked:(id)sender
{
    
}

- (void)showStatusMenu:(id)sender
{
    self.statusItem.menu = self.statusMenu;
    [self.statusItem.button performClick:nil];
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
        __block AppDelegate *blocksafeSelf = self;
        [NSEvent addGlobalMonitorForEventsMatchingMask:NSEventTypeLeftMouseDown | NSEventTypeRightMouseDown handler:^(NSEvent *event) {
            [blocksafeSelf.popover performClose:nil];
        }];
    }
}

- (void)applicationWillTerminate:(NSNotification *)aNotification {
    // Insert code here to tear down your application
}


- (BOOL)applicationSupportsSecureRestorableState:(NSApplication *)app {
    return YES;
}


@end
