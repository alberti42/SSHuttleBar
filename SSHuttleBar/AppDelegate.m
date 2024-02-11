//
//  AppDelegate.m
//  SSHuttleBar
//
//  Created by Andrea Alberti on 11.02.24.
//

//#import "BookmarkManager.h"
#import "AppDelegate.h"
#import "CustomStatusBarButton.h"

@interface AppDelegate ()
@property (strong, nonatomic) NSStatusItem *statusItem;
@property (strong, nonatomic) NSTask *sshTask;
@property (assign, nonatomic) BOOL isConnected;
@property (strong, nonatomic) NSString *connectedIcon;
@property (strong, nonatomic) NSString *disconnectedIcon;
@property (strong, nonatomic) NSURL *bookmarkURL; // Property to store the bookmark URL
@property (assign, nonatomic) BOOL shouldMonitorSSH;
@property (assign, nonatomic) BOOL isThreadSleeping;
@property (strong, nonatomic) NSLock *lock;
@property (strong, nonatomic) dispatch_semaphore_t finishedThreadCycled;
@property (assign, nonatomic) BOOL connectAfterLaunch;
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
            NSLog(@"Error creating app-specific preferences directory: %@", error.localizedDescription);
            return nil; // Handle the error appropriately
        }
    }
    
    // Append the custom preferences file name
    NSString *prefsFilePath = [appSpecificPrefsDirectory stringByAppendingPathComponent:@"org.Alberti42.SSHuttleBar.plist"];
    return prefsFilePath;
}

- (void)applicationWillTerminate:(NSNotification *)notification {
    [self terminateSSHprocess];
    
    if ([self.sshTask isRunning]) {
        [self.sshTask terminate];
    }
}

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification {
    
    NSString *prefsFilePath = [self getCustomPrefsFilePath];
    NSDictionary *prefs = [NSDictionary dictionaryWithContentsOfFile:prefsFilePath];
    [self setConnectAfterLaunch:[([prefs objectForKey:@"connectAfterLaunch"] ? : 0) boolValue]];
    
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
    
    self.isThreadSleeping = NO; // Initially, the thread is not sleeping
    self.shouldMonitorSSH = NO;
    if([self connectAfterLaunch]) {
        self.shouldMonitorSSH = YES;
        [self monitorSSHProcess];
    }
}

- (void)monitorSSHProcess {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0), ^{
        BOOL wasDisconnected = false;
        while (self.shouldMonitorSSH) {
            [self.lock lock];
            self.finishedThreadCycled = dispatch_semaphore_create(0);
            [self.lock unlock];
            
            if (!self.sshTask.isRunning) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    self.statusItem.button.title = self.disconnectedIcon;
                    // NSLog(@"Change status");
                });
                wasDisconnected = true;
                dispatch_async(dispatch_get_main_queue(), ^{
                    [self startSSHProcess]; // Attempt to start the process again
                    NSLog(@"Restarted");
                });
            } else {
                if(wasDisconnected){
                    wasDisconnected = false;
                    dispatch_async(dispatch_get_main_queue(), ^{
                        self.statusItem.button.title = self.connectedIcon;
                    });
                }
            }
            
            dispatch_semaphore_signal(self.finishedThreadCycled); // Signal that thread is finished
            
            [self.lock lock];
            self.isThreadSleeping = YES; // Thread is about to sleep
            [self.lock unlock];
            sleep(1); // Check every second
            [self.lock lock];
            self.isThreadSleeping = NO; // Thread is about to sleep
            [self.lock unlock];
        }
    });
}

- (void)setupStatusItemMenu {
    NSMenu *menu = [[NSMenu alloc] init];
    NSMenuItem* item = [menu addItemWithTitle:@"Connect after launch" action:@selector(toggleAutoConnect:) keyEquivalent:@"a"];
    [item setState:[self connectAfterLaunch]];
    [menu addItemWithTitle:@"Quit" action:@selector(quitApp:) keyEquivalent:@"q"];
    
    [self.statusItem setMenu:menu]; // This enables right-click menu
}

- (void)quitApp:(NSMenuItem*)menuItem {
    [NSApp terminate:nil];
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
        NSLog(@"Failed to save preferences");
    }
}

- (void)startSSHProcess {
    self.sshTask = [[NSTask alloc] init];
    [self.sshTask setLaunchPath:@"/usr/bin/ssh"];
    [self.sshTask setArguments:@[@"-N", @"-L", @"8022:localhost:8022", @"-i", @"/Users/andrea/.ssh/id_computing-server_bonn", @"computing-server2.iap.uni-bonn.de"]];
    
    // Handle ssh task termination
    __weak typeof(self) weakSelf = self;
    [self.sshTask setTerminationHandler:^(NSTask *task) {
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) strongSelf = weakSelf;
            strongSelf.isConnected = NO;
            [strongSelf updateConnectionStatus:NO];
        });
    }];
    
    // Start the ssh process
    [self.sshTask launch];
    
    
    // Optionally, start monitoring the process in a separate thread or via dispatch queue here
}

- (void)terminateSSHprocess {
    NSLog(@"Terminate the ssh process");
    self.shouldMonitorSSH = NO;
    if (!self.isThreadSleeping) {
        // Wait for the thread to enter the sleep phase
        dispatch_semaphore_wait(self.finishedThreadCycled, DISPATCH_TIME_FOREVER);
    }
    [self.sshTask terminate];
}

- (void)statusItemClicked:(id)sender {
    if (self.isConnected) {
        // Terminate the ssh process
        [self terminateSSHprocess];
    } else {
        // Start the ssh process
        NSLog(@"Start the ssh process");
        self.shouldMonitorSSH = YES;
        [self monitorSSHProcess];
    }
    // Toggle the connection status
    self.isConnected = !self.isConnected;
    // Update the icon based on the new connection status
    [self updateConnectionStatus:self.isConnected];
}

- (void)updateConnectionStatus:(BOOL)connected {
    if (connected) {
        self.statusItem.button.title = self.connectedIcon; // Connected icon
    } else {
        self.statusItem.button.title = self.disconnectedIcon; // Disconnected icon
    }
}


- (BOOL)applicationSupportsSecureRestorableState:(NSApplication *)app {
    return YES;
}


@end
