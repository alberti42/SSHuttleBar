//
//  AppDelegate.m
//  SSHuttleBar
//
//  Created by Andrea Alberti on 11.02.24.
//

//#import "BookmarkManager.h"
#import "AppDelegate.h"
#import "CustomStatusBarView.h"

@interface AppDelegate ()
@property (strong, nonatomic) NSStatusItem *statusItem;
@property (strong, nonatomic) NSTask *sshTask;
@property (strong, nonatomic) NSTask *sshuttleTask;
@property (assign, nonatomic) BOOL isSSHconnected;
@property (assign, nonatomic) BOOL isSSHuttleConnected;
@property (strong, nonatomic) NSString *connectedIcon;
@property (strong, nonatomic) NSString *disconnectedIcon;
@property (strong, nonatomic) NSURL *bookmarkURL; // Property to store the bookmark URL
@property (assign, nonatomic) BOOL autorestartSSHuttle;
@property (assign, nonatomic) BOOL autorestartSSH;
@property (strong, nonatomic) NSLock *lock;
@property (strong, nonatomic) dispatch_semaphore_t finishedThreadCycled;
@property (assign, nonatomic) BOOL connectAfterLaunch;
@property (assign, nonatomic) NSNumber *connType;
@property (assign, nonatomic) NSMenuItem* item_ssh;
@property (assign, nonatomic) NSMenuItem* item_direct;
@end

@implementation AppDelegate

- (NSString *)getCustomPrefsFilePath {
    NSString *appSupportDirectory = NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES).firstObject;
    NSString *appName = [[NSBundle mainBundle] bundleIdentifier]; // Dynamically get your app's bundle identifier
    
    // Ensure there's a specific directory for your app's preferences within Application Support
    NSString *appSpecificPrefsDirectory = [appSupportDirectory stringByAppendingPathComponent:appName];
    
    // Check if directory exists, if not, create it
    NSFileManager *fileManager = [NSFileManager defaultManager];
    if (![fileManager fileExistsAtPath:appSpecificPrefsDirectory]) {
        NSError *error = nil;
        [fileManager createDirectoryAtPath:appSpecificPrefsDirectory withIntermediateDirectories:YES attributes:nil error:&error];
        if (error) {
            NSLog(@"SSHuttleBar: Error creating app-specific preferences directory: %@", error.localizedDescription);
            return nil; // Handle the error appropriately
        }
    }
    
    // Append the custom preferences file name
    NSString *prefsFilePath = [appSpecificPrefsDirectory stringByAppendingPathComponent:@"org.Alberti42.SSHuttleBar.plist"];
    return prefsFilePath;
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
    
    NSString *prefsFilePath = [self getCustomPrefsFilePath];
    NSDictionary *prefs = [NSDictionary dictionaryWithContentsOfFile:prefsFilePath];
    [self setConnectAfterLaunch:[([prefs objectForKey:@"connectAfterLaunch"] ? : @0) boolValue]];
    [self setConnType:[prefs objectForKey:@"connectType"] ? : @0];
    
    self.lock = [[NSLock alloc] init];
    
    self.connectedIcon = @"⚡️"; // Connected state icon
    self.disconnectedIcon = @"❌"; // Disconnected state icon
    
    // Initialize your status item here as before
    self.statusItem = [[NSStatusBar systemStatusBar] statusItemWithLength:NSVariableStatusItemLength];
    
    //self.statusItem.button.action = @selector(statusItemClicked:);
    self.statusItem.button.target = self;
    
    // Set the initial icon
    self.statusItem.button.title = self.disconnectedIcon;
    
    // Setup the right-click menu
    [self setupStatusItemMenu];
    
    if([self connectAfterLaunch]) {
        [self start_processes];
    }
}

- (void)start_processes{
    if([[self connType] intValue]==0){
        [self startSSHProcess];
        NSLog(@"SSHuttleBar: Connected to the ssh process");
    }
    [self startSSHuttleProcess];
    NSLog(@"SSHuttleBar: Connected to the sshuttle process");
}

- (void)setupStatusItemMenu {
    NSMenu *menu = [[NSMenu alloc] init];
    
    [self setItem_ssh:[menu addItemWithTitle:@"Connect through SSH" action:@selector(selectSSHconnect:) keyEquivalent:@"0"]];
    [self setItem_direct:[menu addItemWithTitle:@"Connect directly" action:@selector(selectDirectConnect:) keyEquivalent:@"1"]];
    
    switch ([[self connType] intValue]) {
        case 0:
            [[self item_ssh] setState:YES];
            break;
        case 1:
        default:
            [[self item_direct] setState:YES];
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
    
    BOOL current_status_ssh = [[self item_ssh] state];
    BOOL current_status_direct = [[self item_direct] state];
    
    if( current_status_ssh || current_status_direct)
    {
        [self terminate_processes];
    }
    
    [self setConnType:@0];
    
    if(!current_status_ssh){
        [self start_processes];
    }
    
    [[self item_ssh] setState:!current_status_ssh];
    [[self item_direct] setState:NO];
    
    NSString *prefsFilePath = [self getCustomPrefsFilePath];
    NSMutableDictionary *prefs = [NSMutableDictionary dictionaryWithContentsOfFile:prefsFilePath] ?: [NSMutableDictionary dictionary];
    
    // Update the connectAfterLaunch field in the dictionary
    prefs[@"connectType"] = [self connType];
    
    // Write the updated dictionary back to the preferences file
    BOOL success = [prefs writeToFile:prefsFilePath atomically:YES];
    if (!success) {
        NSLog(@"SSHuttleBar: Failed to save preferences");
    }
}

- (void) selectDirectConnect:(NSMenuItem*)menuItem {
    BOOL current_status_ssh = [[self item_ssh] state];
    BOOL current_status_direct = [[self item_direct] state];
    
    if( current_status_ssh || current_status_direct)
    {
        [self terminate_processes];
    }
    
    [self setConnType:@1];
    
    if(!current_status_direct){
        [self start_processes];
    }
    
    [[self item_ssh] setState:NO];
    [[self item_direct] setState:!current_status_direct];
        
    NSString *prefsFilePath = [self getCustomPrefsFilePath];
    NSMutableDictionary *prefs = [NSMutableDictionary dictionaryWithContentsOfFile:prefsFilePath] ?: [NSMutableDictionary dictionary];
    
    // Update the connectAfterLaunch field in the dictionary
    prefs[@"connectType"] = [self connType];
    
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
    [self.sshTask setLaunchPath:@"/usr/bin/ssh"];
    [self.sshTask setArguments:@[@"-N", @"-L", @"8022:localhost:8022", @"-i", @"/Users/andrea/.ssh/id_computing-server_bonn", @"computing-server2.iap.uni-bonn.de"]];
    
    // Redirect output and error to /dev/null
    NSFileHandle *nullFileHandle = [NSFileHandle fileHandleWithNullDevice];
    [self.sshTask setStandardOutput:nullFileHandle];
    [self.sshTask setStandardError:nullFileHandle];

    // Handle ssh task termination
    __weak typeof(self) weakSelf = self;
    [self.sshTask setTerminationHandler:^(NSTask *task) {
        dispatch_async(dispatch_get_main_queue(), ^{
            NSLog(@"SSHuttleBar: Lost ssh connection");
            __strong typeof(weakSelf) strongSelf1 = weakSelf;
            strongSelf1.isSSHconnected = NO;
            [strongSelf1 updateConnectionStatus];
            
            if ([strongSelf1 autorestartSSH]) {
                // Wait for 1 second before trying to restart the SSH process
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                    __strong typeof(weakSelf) strongSelf2 = weakSelf;
                    [strongSelf2 setAutorestartSSHuttle:NO];
                    [strongSelf2 terminateSSHuttleProcess];
                    
                    [strongSelf2 startSSHProcess];
                    NSLog(@"SSHuttleBar: Reconnected to the ssh process");
                    
                    [strongSelf2 setAutorestartSSHuttle:YES];
                    [strongSelf2 startSSHuttleProcess];
                    NSLog(@"SSHuttleBar: Reconnected to the sshuttle process");
                });
            };
        });
    }];

    // Start the ssh process
    [self.sshTask launch];
    self.statusItem.button.title = self.connectedIcon;
}

- (void)startSSHuttleProcess {
    self.autorestartSSHuttle = YES;
    self.sshuttleTask = [[NSTask alloc] init];
    [self.sshuttleTask setLaunchPath:@"/usr/local/bin/sshuttle"];
    switch ([[self connType] intValue]) {
        case 0:
            [self.sshuttleTask setArguments:@[@"-r", @"m1-gateway", @"--dns", @"0/0"]];
            break;
        case 1:
        default:
            [self.sshuttleTask setArguments:@[@"-r", @"m1-gateway-local", @"--dns", @"0/0"]];
            break;
    }
    
    // Redirect output and error to /dev/null
    NSFileHandle *nullFileHandle = [NSFileHandle fileHandleWithNullDevice];
    [self.sshuttleTask setStandardOutput:nullFileHandle];
    [self.sshuttleTask setStandardError:nullFileHandle];
    
    // Handle ssh task termination
    __weak typeof(self) weakSelf = self;
    [self.sshuttleTask setTerminationHandler:^(NSTask *task) {
        dispatch_async(dispatch_get_main_queue(), ^{
            NSLog(@"SSHuttleBar: Lost sshuttle connection");
            __strong typeof(weakSelf) strongSelf1 = weakSelf;
            strongSelf1.isSSHuttleConnected = NO;
            [strongSelf1 updateConnectionStatus];
            
            BOOL relaunch = false;
            if([[self connType] intValue] == 1){
                relaunch = true;
            }
            [strongSelf1.lock lock];
            if ([strongSelf1.sshTask isRunning]) {
                relaunch = true;
            }
            [strongSelf1.lock unlock];
            if (relaunch && [strongSelf1 autorestartSSHuttle]) {
                // Wait for 1 second before trying to restart the SSH process
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                    __strong typeof(weakSelf) strongSelf2 = weakSelf;
                    [strongSelf2 startSSHuttleProcess];
                    NSLog(@"SSHuttleBar: Reconnected to the sshuttle process");
                });
            }
            
        });
    }];
    
    // Start the ssh process
    [self.sshuttleTask launch];
    self.statusItem.button.title = self.connectedIcon;
}

- (void)terminateSSHprocess {
    self.autorestartSSH = NO;
    if ([self.sshTask isRunning]) {
        NSLog(@"SSHuttleBar: Terminate the ssh process");
        [self.sshTask terminate];
    }
}

- (void)terminateSSHuttleProcess {
    self.autorestartSSHuttle = NO;
    if ([self.sshuttleTask isRunning]) {
        NSLog(@"SSHuttleBar: Terminate the sshuttle process");
        [self.sshuttleTask terminate];
    }
}

- (void)statusItemClicked:(id)sender {
    if (self.isSSHconnected) {
        // Terminate the ssh process
        [self terminateSSHprocess];
    } else {
        // Start the ssh process
        NSLog(@"SSHuttleBar: Start the ssh process");
    }
    // Toggle the connection status
    self.isSSHconnected = !self.isSSHconnected;
    // Update the icon based on the new connection status
    [self updateConnectionStatus];
}

- (void)updateConnectionStatus {
    
    BOOL connected = [self isSSHuttleConnected] && ([self isSSHconnected] || ([[self connType] intValue] == 1));
    
    if (connected) {
        self.statusItem.button.title = self.connectedIcon; // Connected icon
    } else {
        self.statusItem.button.title = self.disconnectedIcon; // DisSSHconnected icon
    }
}

- (BOOL)applicationSupportsSecureRestorableState:(NSApplication *)app {
    return YES;
}


@end
