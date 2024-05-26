//
//  AppDelegate.m
//  SSHuttleBar
//
//  Created by Andrea Alberti on 11.02.24.
//


//#import "BookmarkManager.h"
#import "AppDelegate.h"
#import "CustomStatusBarView.h"

#define NUM_SECONDS_BETWEEN_REPS 1

static const int NoConnection = -1;
static const int BonnConnection = 0;
static const int DirectConnection = 1;

@interface AppDelegate ()
@property (strong, nonatomic) NSStatusItem *statusItem;
@property (strong, nonatomic) NSTask *sshuttleTask;
@property (assign, nonatomic) BOOL isSSHuttleConnected;
@property (strong, nonatomic) NSImage *connectedIcon;
@property (strong, nonatomic) NSImage *disconnectedIcon;
@property (strong, nonatomic) NSURL *bookmarkURL; // Property to store the bookmark URL
@property (assign, nonatomic) BOOL autorestartSSHuttle;
@property (strong, nonatomic) NSLock *lock;
@property (strong, nonatomic) dispatch_semaphore_t finishedThreadCycled;
@property (assign, nonatomic) BOOL connectAfterLaunch;
@property (assign, nonatomic) int connType;
@property (assign, nonatomic) NSMenuItem* menu_item_ssh_conn;
@property (assign, nonatomic) NSMenuItem* menu_item_direct_conn;
@property (assign, nonatomic) NSString* path_sshuttle;
@property (assign, nonatomic) NSString* path_sudo;
@end

@implementation AppDelegate

- (NSString *)getCustomPrefsFilePath {
    NSString *appPreferencesDirectory = [NSSearchPathForDirectoriesInDomains(NSLibraryDirectory, NSUserDomainMask, YES).firstObject  stringByAppendingPathComponent:@"Preferences"];
    NSString *appName = [[NSBundle mainBundle] bundleIdentifier]; // Dynamically get your app's bundle identifier
    
    // Append the custom preferences file name
    NSString *prefsFilePath = [[appPreferencesDirectory stringByAppendingPathComponent:appName] stringByAppendingPathExtension:@"plist"];
    return prefsFilePath;
}

+ (NSString *)find_path_executables:(NSArray<NSString *> *)possiblePaths withLabel:(NSString*) label {
    
    NSFileManager *fileManager = [NSFileManager defaultManager];
    
    for (NSString *path in possiblePaths) {
        if ([fileManager fileExistsAtPath:path]) {
            NSLog(@"Found %@ executable at: %@", label, path);
            return path;
        }
    }
    
    NSLog(@"%@ executable not found in any of the specified locations.",label);
    return nil;
}

- (void)terminate_processes {
    [self terminateSSHuttleProcess];
}

- (void)applicationWillTerminate:(NSNotification *)notification {
    NSLog(@"SSHuttleBar: Exiting SSHuttleBar");
    [self terminate_processes];
}

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification {
    
    self.path_sshuttle = [AppDelegate find_path_executables:@[@"/opt/homebrew/bin/sshuttle", @"/usr/local/bin/sshuttle"] withLabel:@"ssh"];
    self.path_sudo = [AppDelegate find_path_executables:@[@"/usr/bin/sudo"] withLabel:@"sudo"];
    
    NSString *prefsFilePath = [self getCustomPrefsFilePath];
    NSDictionary *prefs = [NSDictionary dictionaryWithContentsOfFile:prefsFilePath];
    self.connectAfterLaunch = [([prefs objectForKey:@"connectAfterLaunch"] ? : @NO) boolValue];
    if(self.connectAfterLaunch){
        self.connType = [([prefs objectForKey:@"connectType"] ? : [NSNumber numberWithInt:NoConnection]) intValue];
    } else {
        self.connType = NoConnection;
    }
    
    self.lock = [[NSLock alloc] init];
    
    // Load the icons from the asset catalog
    self.connectedIcon = [NSImage imageNamed:@"ConnectedIcon"];
    [self.connectedIcon setTemplate:YES];
    self.disconnectedIcon = [NSImage imageNamed:@"DisconnectedIcon"];
    [self.disconnectedIcon setTemplate:YES];
    
    // Initialize your status item here as before
    self.statusItem = [[NSStatusBar systemStatusBar] statusItemWithLength:NSVariableStatusItemLength];
    
    self.statusItem.button.target = self;
    
    // Set the initial icon
    [self updateConnectionStatus];
    
    // Setup the right-click menu
    [self setupStatusItemMenu];
    
    NSLog(@"SSHuttleBar: Starting SSHuttleBar");
    
    if([self connectAfterLaunch]) {
        [self start_processes];
    }
}

- (void)start_processes{
    [self startSSHuttleProcess];
    NSLog(@"SSHuttleBar: Connected to the sshuttle process (PID=%d)", [[self sshuttleTask] processIdentifier]);
}

- (void)setupStatusItemMenu {
    NSMenu *menu = [[NSMenu alloc] init];
    
    self.menu_item_ssh_conn = [menu addItemWithTitle:@"Connect through SSH" action:@selector(selectSSHconnect:) keyEquivalent:@"0"];
    self.menu_item_direct_conn = [menu addItemWithTitle:@"Connect directly" action:@selector(selectDirectConnect:) keyEquivalent:@"1"];
    
    switch([self connType])
    {
        case BonnConnection:
            [[self menu_item_ssh_conn] setState:YES];
            break;
        case DirectConnection:
            [[self menu_item_direct_conn] setState:YES];
            break;
    }
    
    [menu addItem:[NSMenuItem separatorItem]];
    
    NSMenuItem* item_activate = [menu addItemWithTitle:@"Activate on launch" action:@selector(toggleAutoConnect:) keyEquivalent:@"a"];
    [item_activate setState:[self connectAfterLaunch]];
    
    [menu addItemWithTitle:@"Quit" action:@selector(quitApp:) keyEquivalent:@"q"];
    
    [self.statusItem setMenu:menu]; // This enables right-click menu
}

- (void)quitApp:(NSMenuItem*)menuItem {
    [NSApp terminate:nil];
}

- (void) selectSSHconnect:(NSMenuItem*)menuItem {
    
    BOOL current_status_ssh = [[self menu_item_ssh_conn] state];
    BOOL current_status_direct = [[self menu_item_direct_conn] state];
    
    if( current_status_ssh || current_status_direct)
    {
        [self terminate_processes];
    }
    
    if(!current_status_ssh){
        [self setConnType:BonnConnection];
        [self start_processes];
    }
    else{
        [self setConnType:NoConnection];
    }
    
    [[self menu_item_ssh_conn] setState:!current_status_ssh];
    [[self menu_item_direct_conn] setState:NO];
    
    NSString *prefsFilePath = [self getCustomPrefsFilePath];
    NSMutableDictionary *prefs = [NSMutableDictionary dictionaryWithContentsOfFile:prefsFilePath] ?: [NSMutableDictionary dictionary];
    
    // Update the connectAfterLaunch field in the dictionary
    prefs[@"connectType"] = [NSNumber numberWithInt:[self connType]];
    
    // Write the updated dictionary back to the preferences file
    BOOL success = [prefs writeToFile:prefsFilePath atomically:YES];
    if (!success) {
        NSLog(@"SSHuttleBar: Failed to save preferences");
    }
}

- (void) selectDirectConnect:(NSMenuItem*)menuItem {
    BOOL current_status_ssh = [[self menu_item_ssh_conn] state];
    BOOL current_status_direct = [[self menu_item_direct_conn] state];
    
    if( current_status_ssh || current_status_direct)
    {
        [self terminate_processes];
    }
    
    if(!current_status_direct){
        [self setConnType:DirectConnection];
        [self start_processes];
    }
    else{
        [self setConnType:NoConnection];
    }
    
    [[self menu_item_ssh_conn] setState:NO];
    [[self menu_item_direct_conn] setState:!current_status_direct];
    
    NSString *prefsFilePath = [self getCustomPrefsFilePath];
    NSMutableDictionary *prefs = [NSMutableDictionary dictionaryWithContentsOfFile:prefsFilePath] ?: [NSMutableDictionary dictionary];
    
    // Update the connectAfterLaunch field in the dictionary
    prefs[@"connectType"] = [NSNumber numberWithInt:[self connType]];
    
    // Write the updated dictionary back to the preferences file
    BOOL success = [prefs writeToFile:prefsFilePath atomically:YES];
    if (!success) {
        NSLog(@"SSHuttleBar: Failed to save preferences");
    }
}

- (void)toggleAutoConnect:(NSMenuItem*)menuItem {
    [self setConnectAfterLaunch:![self connectAfterLaunch]];
    
    // Update the menu item state to reflect the toggle
    menuItem.state=self.connectAfterLaunch ? NSControlStateValueOn : NSControlStateValueOff;
    
    NSString *prefsFilePath = [self getCustomPrefsFilePath];
    NSMutableDictionary *prefs = [NSMutableDictionary dictionaryWithContentsOfFile:prefsFilePath] ?: [NSMutableDictionary dictionary];
    
    // Update the connectAfterLaunch field in the dictionary
    prefs[@"connectAfterLaunch"] = [NSNumber numberWithBool:[self connectAfterLaunch]];
    
    // Write the updated dictionary back to the preferences file
    BOOL success = [prefs writeToFile:prefsFilePath atomically:YES];
    if (!success) {
        NSLog(@"SSHuttleBar: Failed to save preferences");
    }
}

- (void)startSSHuttleProcess {
    self.autorestartSSHuttle = YES;
    self.sshuttleTask = [[NSTask alloc] init];
    [self.sshuttleTask setLaunchPath:[self path_sudo]];
    switch ([self connType]) {
        case 0:
            [self.sshuttleTask setArguments:@[[self path_sshuttle], @"-e", @"ssh -F /Users/andrea/.ssh/config", @"-r", @"m1-gateway-bonn", @"--dns", @"0/0"]];
            break;
        case 1:
            [self.sshuttleTask setArguments:@[[self path_sshuttle], @"-e", @"ssh -F /Users/andrea/.ssh/config", @"-r", @"m1-gateway-local", @"--dns", @"0/0"]];
            break;
    }
    
#ifndef DEBUG
    // Redirect output and error to /dev/null
    NSFileHandle *nullFileHandle = [NSFileHandle fileHandleWithNullDevice];
    [self.sshuttleTask setStandardOutput:nullFileHandle];
    [self.sshuttleTask setStandardError:nullFileHandle];
#endif
    
    // Handle ssh task termination
    __weak typeof(self) weakSelf = self;
    [self.sshuttleTask setTerminationHandler:^(NSTask *task) {
        dispatch_async(dispatch_get_main_queue(), ^{
            NSLog(@"SSHuttleBar: Lost sshuttle connection (PID=%d)", [task processIdentifier]);
            __strong typeof(weakSelf) strongSelf1 = weakSelf;
            strongSelf1.isSSHuttleConnected = NO;
            [strongSelf1 updateConnectionStatus];
            
            if ([strongSelf1 autorestartSSHuttle]) {
                // Wait for 1 second before trying to restart the SSH process
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(NUM_SECONDS_BETWEEN_REPS * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                    __strong typeof(weakSelf) strongSelf2 = weakSelf;
                    [strongSelf2 startSSHuttleProcess];
                    NSLog(@"SSHuttleBar: Reconnected to the sshuttle process (PID=%d)", [[strongSelf2 sshuttleTask] processIdentifier]);
                });
            }
            
        });
    }];
    
    // Start the ssh process
    [self.sshuttleTask launch];
    self.statusItem.button.image = self.connectedIcon;
}

- (void)terminateSSHuttleProcess {
    self.autorestartSSHuttle = NO;
    [self.sshuttleTask setTerminationHandler:nil];
    if ([self.sshuttleTask isRunning]) {
        NSLog(@"SSHuttleBar: Terminate the sshuttle process (PID=%d)", [[self sshuttleTask] processIdentifier]);
        [self.sshuttleTask terminate];
        [self.sshuttleTask waitUntilExit];
        [self updateConnectionStatus];
    }
}

- (void)updateConnectionStatus {
    if ([self isSSHuttleConnected]) {
        self.statusItem.button.image = self.connectedIcon; // Connected icon
    } else {
        self.statusItem.button.image = self.disconnectedIcon; // DisSSHconnected icon
    }
}

- (BOOL)applicationSupportsSecureRestorableState:(NSApplication *)app {
    return YES;
}


@end
