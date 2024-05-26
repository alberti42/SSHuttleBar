//
//  AppDelegate.m
//  SSHuttleBar
//
//  Created by Andrea Alberti on 11.02.24.
//


//#import "BookmarkManager.h"
#import "AppDelegate.h"
#import "CustomStatusBarView.h"
#import "1Password.h"
#import "Utils.h"

#define NUM_SECONDS_BETWEEN_REPS 1

static const int NoConnection = -1;
static const int ProxyConnection = 0;
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
@property (assign, nonatomic) NSString* path_ssh;
@property (assign, nonatomic) NSString* path_expect;
@end

@implementation AppDelegate

- (NSString *)getCustomPrefsFilePath {
    NSString *appPreferencesDirectory = [NSSearchPathForDirectoriesInDomains(NSLibraryDirectory, NSUserDomainMask, YES).firstObject  stringByAppendingPathComponent:@"Preferences"];
    NSString *appName = [[NSBundle mainBundle] bundleIdentifier]; // Dynamically get your app's bundle identifier
    
    // Append the custom preferences file name
    NSString *prefsFilePath = [[appPreferencesDirectory stringByAppendingPathComponent:appName] stringByAppendingPathExtension:@"plist"];
    return prefsFilePath;
}

- (void)terminate_processes {
    [self terminateSSHuttleProcess];
}

- (void)applicationWillTerminate:(NSNotification *)notification {
    NSLog(@"SSHuttleBar: Exiting SSHuttleBar");
    [self terminate_processes];
}

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification {
    self.path_sshuttle = [Utils find_path_executables:@[@"/opt/homebrew/bin/sshuttle", @"/usr/local/bin/sshuttle"] withLabel:@"ssh"];
    self.path_sudo = [Utils find_path_executables:@[@"/usr/bin/sudo"] withLabel:@"sudo"];
    self.path_ssh = [Utils find_path_executables:@[@"/usr/local/bin/ssh",@"/opt/homebrew/bin/ssh"] withLabel:@"ssh"];
    self.path_expect = [Utils find_path_executables:@[@"/usr/bin/expect"] withLabel:@"expect"];
    
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
    
    self.menu_item_ssh_conn = [menu addItemWithTitle:@"Connect through proxy" action:@selector(selectProxyConnect:) keyEquivalent:@"0"];
    self.menu_item_direct_conn = [menu addItemWithTitle:@"Connect directly" action:@selector(selectDirectConnect:) keyEquivalent:@"1"];
    
    switch([self connType])
    {
        case ProxyConnection:
            [[self menu_item_ssh_conn] setState:YES];
            break;
        case DirectConnection:
            [[self menu_item_direct_conn] setState:YES];
            break;
    }
    
    [menu addItem:[NSMenuItem separatorItem]];
    
    NSMenuItem* item_activate = [menu addItemWithTitle:@"Activate on launch" action:@selector(toggleAutoConnect:) keyEquivalent:@"a"];
    [item_activate setState:[self connectAfterLaunch]];
    
    [menu addItem:[NSMenuItem separatorItem]];
    
    [menu addItemWithTitle:@"Quit" action:@selector(quitApp:) keyEquivalent:@"q"];
    
    [self.statusItem setMenu:menu]; // This enables right-click menu
}

- (void)quitApp:(NSMenuItem*)menuItem {
    [NSApp terminate:nil];
}

- (void) selectProxyConnect:(NSMenuItem*)menuItem {
    
    BOOL current_status_ssh = [[self menu_item_ssh_conn] state];
    BOOL current_status_direct = [[self menu_item_direct_conn] state];
    
    if( current_status_ssh || current_status_direct)
    {
        [self terminate_processes];
    }
    
    if(!current_status_ssh){
        [self setConnType:ProxyConnection];
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

    if ([self connType] == ProxyConnection) {
        NSDictionary* theCredentials = [OnePasswordInterface getCredentialsForId:@"cmox6bkra5dv3gq3ggzz4ct4ay"];
        if (!theCredentials) {
            NSLog(@"Failed to get credentials");
            return;
        }
#ifdef DEBUG
        NSLog(@"Credentials: %@", theCredentials);
#endif

        // Get the path to the sshuttle_expect.sh script in the app bundle
        NSString* expectScriptPath = [[NSBundle mainBundle] pathForResource:@"sshuttle_expect" ofType:@"sh"];
        if (!expectScriptPath) {
            NSLog(@"Failed to find sshuttle_expect.sh script in bundle");
            return;
        }
#ifdef DEBUG
        NSLog(@"Expect script path: %@", expectScriptPath);
#endif
        // Use the expect script to handle the password and OTP prompts
        [self.sshuttleTask setLaunchPath:@"/usr/bin/expect"];
        NSArray *arguments = @[expectScriptPath, theCredentials[@"password"], theCredentials[@"otp"], self.path_sshuttle];
        [self.sshuttleTask setArguments:arguments];
#ifdef DEBUG
        NSLog(@"sshuttle task arguments: %@", arguments);
#endif
    } else if ([self connType] == DirectConnection) {
        [self.sshuttleTask setLaunchPath:self.path_sudo];
        NSString *directSshCommand = [NSString stringWithFormat:@"%@ -F /Users/andrea/.ssh/config", [self path_ssh]];
        NSArray *arguments = @[self.path_sshuttle, @"-e", directSshCommand, @"-r", @"m1-gateway-local", @"--dns", @"0/0"];
        [self.sshuttleTask setArguments:arguments];
#ifdef DEBUG
        NSLog(@"Direct connection task arguments: %@", arguments);
#endif
    }

#ifdef DEBUG
    // Redirect output and error to capture and log them
    NSPipe *outputPipe = [NSPipe pipe];
    NSPipe *errorPipe = [NSPipe pipe];
    [self.sshuttleTask setStandardOutput:outputPipe];
    [self.sshuttleTask setStandardError:errorPipe];

    NSFileHandle *outputFile = [outputPipe fileHandleForReading];
    NSFileHandle *errorFile = [errorPipe fileHandleForReading];
#else
    // Redirect output and error to /dev/null
    NSFileHandle *nullFileHandle = [NSFileHandle fileHandleWithNullDevice];
    [self.sshuttleTask setStandardOutput:nullFileHandle];
    [self.sshuttleTask setStandardError:nullFileHandle];
#endif
    
    // Handle ssh task termination
    __weak typeof(self) weakSelf = self;
    [self.sshuttleTask setTerminationHandler:^(NSTask *task) {
#ifdef DEBUG
        NSData *outputData = [outputFile readDataToEndOfFile];
        NSData *errorData = [errorFile readDataToEndOfFile];

        NSString *outputString = [[NSString alloc] initWithData:outputData encoding:NSUTF8StringEncoding];
        NSString *errorString = [[NSString alloc] initWithData:errorData encoding:NSUTF8StringEncoding];

        NSLog(@"sshuttle output: %@", outputString);
        NSLog(@"sshuttle error: %@", errorString);
#endif

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

#ifdef DEBUG
    NSLog(@"Ready to start sshuttle");
#endif
    // Start the ssh process
    @try {
        [self.sshuttleTask launch];
        NSLog(@"sshuttle task launched successfully");
        self.statusItem.button.image = self.connectedIcon;
    }
    @catch (NSException *exception) {
        NSLog(@"Failed to launch sshuttle task: %@", exception);
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
