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
// #define DEBUG_OUTPUT_PROCESSES 0

static const int NoConnection = -1;
static const int SshConnection = 0;
static const int DirectConnection = 1;

@interface AppDelegate ()
@property (strong, nonatomic) NSStatusItem *statusItem;
@property (strong, nonatomic) NSTask *sshTask;
@property (strong, nonatomic) NSTask *sshuttleTask;
@property (assign, nonatomic) BOOL isSSHconnected;
@property (assign, nonatomic) BOOL isSSHuttleConnected;
@property (strong, nonatomic) NSImage *connectedIcon;
@property (strong, nonatomic) NSImage *disconnectedIcon;
@property (strong, nonatomic) NSURL *bookmarkURL; // Property to store the bookmark URL
@property (assign, nonatomic) BOOL autorestartSSHuttle;
@property (assign, nonatomic) BOOL autorestartSSH;
@property (strong, nonatomic) NSLock *lock;
@property (strong, nonatomic) dispatch_semaphore_t finishedThreadCycled;
@property (assign, nonatomic) BOOL connectAfterLaunch;
@property (assign, nonatomic) int connType;
@property (assign, nonatomic) NSMenuItem* menu_item_ssh_conn;
@property (assign, nonatomic) NSMenuItem* menu_item_direct_conn;
@property (assign, nonatomic) NSString* path_sshuttle;
@property (assign, nonatomic) NSString* path_ssh;
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
    [self terminateSSHprocess];
}

- (void)applicationWillTerminate:(NSNotification *)notification {
    NSLog(@"SSHuttleBar: Exiting SSHuttleBar");
    [self terminate_processes];
}

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification {
    
    self.path_ssh = [AppDelegate find_path_executables:@[@"/opt/homebrew/bin/ssh", @"/usr/local/bin/ssh", @"/usr/bin/ssh"] withLabel:@"sshuttle"];
    self.path_sshuttle = [AppDelegate find_path_executables:@[@"/opt/homebrew/bin/sshuttle", @"/usr/local/bin/sshuttle"] withLabel:@"ssh"];
    
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
    switch([self connType]){
        case 0:
            [self startSSHProcess];
            NSLog(@"SSHuttleBar: Connected to the ssh process (PID=%d)", [[self sshTask] processIdentifier]);
        case 1:
            [self startSSHuttleProcess];
            NSLog(@"SSHuttleBar: Connected to the sshuttle process (PID=%d)", [[self sshuttleTask] processIdentifier]);
    }
}

- (void)setupStatusItemMenu {
    NSMenu *menu = [[NSMenu alloc] init];
    
    self.menu_item_ssh_conn = [menu addItemWithTitle:@"Connect through SSH" action:@selector(selectSSHconnect:) keyEquivalent:@"0"];
    self.menu_item_direct_conn = [menu addItemWithTitle:@"Connect directly" action:@selector(selectDirectConnect:) keyEquivalent:@"1"];
    
    switch([self connType])
    {
        case 0:
            [[self menu_item_ssh_conn] setState:YES];
            break;
        case 1:
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
        [self setConnType:SshConnection];
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

- (void)startSSHProcess {
    self.autorestartSSH = YES;
    self.sshTask = [[NSTask alloc] init];
    [self.sshTask setLaunchPath:[self path_ssh]];
    [self.sshTask setArguments:@[@"-N", @"-L", @"8022:localhost:8022", @"-i", [@"~/.ssh/id_computing-server_bonn" stringByExpandingTildeInPath], @"computing-server2.iap.uni-bonn.de"]];
    
#ifndef DEBUG_OUTPUT_PROCESSES
    // Redirect output and error to /dev/null
    NSFileHandle *nullFileHandle = [NSFileHandle fileHandleWithNullDevice];
    [self.sshTask setStandardOutput:nullFileHandle];
    [self.sshTask setStandardError:nullFileHandle];
#endif
    
    // Handle ssh task termination
    __weak typeof(self) weakSelf = self;
    
    [self.sshTask setTerminationHandler:^(NSTask *task) {
        dispatch_async(dispatch_get_main_queue(), ^{
            NSLog(@"SSHuttleBar: Lost ssh connection (PID=%d)", [task processIdentifier]);
            __strong typeof(weakSelf) strongSelf1 = weakSelf;
            strongSelf1.isSSHconnected = NO;
            [strongSelf1 updateConnectionStatus];
            
            if ([strongSelf1 autorestartSSH]) {
                // Wait for 1 second before trying to restart the SSH process
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(NUM_SECONDS_BETWEEN_REPS * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                    __strong typeof(weakSelf) strongSelf2 = weakSelf;
                    [strongSelf2 setAutorestartSSHuttle:NO];
                    [strongSelf2 terminateSSHuttleProcess];
                    
                    [strongSelf2 startSSHProcess];
                    NSLog(@"SSHuttleBar: Reconnected to the ssh process (PID=%d)", [[strongSelf2 sshTask] processIdentifier]);
                    
                    [strongSelf2 setAutorestartSSHuttle:YES];
                    [strongSelf2 startSSHuttleProcess];
                    NSLog(@"SSHuttleBar: Reconnected to the sshuttle process (PID=%d)", [[strongSelf2 sshuttleTask] processIdentifier]);
                });
            };
        });
    }];
    
    // Start the ssh process
    [self.sshTask launch];
    self.statusItem.button.image = self.connectedIcon;
}

- (void)startSSHuttleProcess {
    self.autorestartSSHuttle = YES;
    self.sshuttleTask = [[NSTask alloc] init];
    [self.sshuttleTask setLaunchPath:[self path_sshuttle]];
    switch ([self connType]) {
        case 0:
            [self.sshuttleTask setArguments:@[@"-r", @"m1-gateway", @"--dns", @"0/0"]];
            break;
        case 1:
            [self.sshuttleTask setArguments:@[@"-r", @"m1-gateway-local", @"--dns", @"0/0"]];
            break;
    }
    
#ifndef DEBUG_OUTPUT_PROCESSES
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
            
            BOOL relaunch = false;
            if([self connType] == 1){
                relaunch = true;
            }
            [strongSelf1.lock lock];
            if ([strongSelf1.sshTask isRunning]) {
                relaunch = true;
            }
            [strongSelf1.lock unlock];
            if (relaunch && [strongSelf1 autorestartSSHuttle]) {
                // Wait for 1 second before trying to restart the SSH process
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(NUM_SECONDS_BETWEEN_REPS * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                    __strong typeof(weakSelf) strongSelf2 = weakSelf;
                    [strongSelf2 startSSHuttleProcess];
                    NSLog(@"SSHuttleBar: Reconnected to the sshuttle process (PID=%d)", [[strongSelf2 sshTask] processIdentifier]);
                });
            }
            
        });
    }];
    
    // Start the ssh process
    [self.sshuttleTask launch];
    self.statusItem.button.image = self.connectedIcon;
}

- (void)terminateSSHprocess {
    self.autorestartSSH = NO;
    [self.sshTask setTerminationHandler:nil];
    if ([self.sshTask isRunning]) {
        NSLog(@"SSHuttleBar: Terminate the ssh process (PID=%d)", [[self sshTask] processIdentifier]);
        [self.sshTask terminate];
        [self.sshTask waitUntilExit];
        [self updateConnectionStatus];
    }
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
    BOOL connected = [self isSSHuttleConnected] && ([self isSSHconnected] || ([self connType] == 1));
    
    if (connected) {
        self.statusItem.button.image = self.connectedIcon; // Connected icon
    } else {
        self.statusItem.button.image = self.disconnectedIcon; // DisSSHconnected icon
    }
}

- (BOOL)applicationSupportsSecureRestorableState:(NSApplication *)app {
    return YES;
}


@end
