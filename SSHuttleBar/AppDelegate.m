//
//  AppDelegate.m
//  SSHuttleBar
//
//  Created by Andrea Alberti on 11.02.24.
//

#import "BookmarkManager.h"
#import "AppDelegate.h"

@interface AppDelegate ()
@property (strong, nonatomic) NSStatusItem *statusItem;
@property (strong, nonatomic) NSTask *sshTask;
@property (assign, nonatomic) BOOL isConnected;
@property (strong, nonatomic) NSString *connectedIcon;
@property (strong, nonatomic) NSString *disconnectedIcon;
@property (strong, nonatomic) NSURL *bookmarkURL; // Property to store the bookmark URL
@end

@implementation AppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification {
    self.connectedIcon = @"⚡️"; // Connected state icon
    self.disconnectedIcon = @"❌"; // Disconnected state icon
    
    // Initialize your status item here as before
    self.statusItem = [[NSStatusBar systemStatusBar] statusItemWithLength:NSVariableStatusItemLength];
    self.statusItem.button.action = @selector(statusItemClicked:);
    self.statusItem.button.target = self;
    
    // Initially, let's assume it's disconnected.
    self.statusItem.button.title = self.disconnectedIcon;
    
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
    
    [[BookmarkManager sharedManager] ensureSSHBookmarkAvailableAndExecuteBlock:^(NSURL *bookmarkURL) {
        // Your custom code with access to bookmarkURL
        NSLog(@"Executing SSH process");
        // Start the ssh process
        [self.sshTask launch];
        
    }];

    
    // Optionally, start monitoring the process in a separate thread or via dispatch queue here
}

- (void)statusItemClicked:(id)sender {
    if (self.isConnected) {
        // Terminate the ssh process
        [self.sshTask terminate];
    } else {
        // Start the ssh process
        [self startSSHProcess];
    }
    // Toggle the connection status
    self.isConnected = !self.isConnected;
    // Update the icon based on the new connection status
    [self updateConnectionStatus:self.isConnected];
}

- (void)updateConnectionStatus:(BOOL)connected {
    if (connected) {
        self.statusItem.button.title = @"⚡️"; // Connected icon
    } else {
        self.statusItem.button.title = @"❌"; // Disconnected icon
    }
}

- (void)applicationWillTerminate:(NSNotification *)aNotification {
    // Insert code here to tear down your application
}


- (BOOL)applicationSupportsSecureRestorableState:(NSApplication *)app {
    return YES;
}


@end
