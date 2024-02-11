//
//  BookmarkManager.m
//  SSHuttleBar
//
//  Created by Andrea Alberti on 11.02.24.
//

#import "BookmarkManager.h"

@implementation BookmarkManager

+ (instancetype)sharedManager {
    static BookmarkManager *sharedManager = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedManager = [[self alloc] init];
    });
    return sharedManager;
}

- (void)ensureSSHBookmarkAvailableAndExecuteBlock:(void (^)(NSURL *bookmarkURL))block {
    [self ensureBookmarkAvailableWithCompletion:^(NSURL *bookmarkURL, NSError *error) {
        if (!error && bookmarkURL) {
            if ([bookmarkURL startAccessingSecurityScopedResource]) {
                // Execute the provided block with the bookmarkURL
                if (block) {
                    block(bookmarkURL);
                }
                [bookmarkURL stopAccessingSecurityScopedResource];
            } else {
                NSError *accessError = [NSError errorWithDomain:@"BookmarkManagerError" code:200 userInfo:@{NSLocalizedDescriptionKey: @"Unable to access security-scoped resource."}];
                [self handleBookmarkAccessError:accessError];
            }
        } else {
            [self handleBookmarkAccessError:error];
        }
    }];
}

- (void)handleBookmarkAccessError:(NSError *)error {
    NSLog(@"An error occurred: %@", error.localizedDescription);
    // Move the dispatch to the main queue here for UI-related operations
    dispatch_async(dispatch_get_main_queue(), ^{
        NSAlert *alert = [[NSAlert alloc] init];
        [alert setMessageText:@"Permission Required"];
        [alert setInformativeText:@"You must grant permissions to the SSH configuration file folder for the application to function properly."];
        [alert addButtonWithTitle:@"OK"];
        [alert setAlertStyle:NSAlertStyleCritical];
        
        [alert runModal];
        
        // Terminate the application
        [NSApp terminate:nil];
    });
}

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

- (void)getBookmarkWithCompletion:(void (^)(NSData *bookmarkData, NSError *error))completion {
    NSOpenPanel *openPanel = [NSOpenPanel openPanel];
    [openPanel setCanChooseFiles:YES];
    [openPanel setCanChooseDirectories:NO];
    [openPanel setAllowsMultipleSelection:NO];
    [openPanel setPrompt:@"Select"];
    [openPanel setMessage:@"Please grant access to your .ssh directory."];
    
    // Set the initial directory to /Users/andrea/.ssh
    NSURL *initialDirectoryURL = [NSURL fileURLWithPath:theFilePath]; // IMPORTANT: theFilePath is a variable containing the standard file path
    [openPanel setDirectoryURL:initialDirectoryURL];
    
    [openPanel beginWithCompletionHandler:^(NSInteger result) {
        if (result == NSModalResponseOK) {
            NSURL *selectedDirectory = openPanel.URLs.firstObject;
            NSError *error = nil;
            NSData *bookmarkData = [selectedDirectory bookmarkDataWithOptions:NSURLBookmarkCreationWithSecurityScope
                                               includingResourceValuesForKeys:nil
                                                                relativeToURL:nil
                                                                        error:&error];
            if (!bookmarkData) {
                NSLog(@"Failed to create bookmark: %@", error);
                if (completion) {
                    completion(nil, error);
                }
                return;
            }
            
            // Save the bookmark data as needed, for example, to a plist
            // For simplicity, this step is omitted here. You would include your saving logic here.
            
            // Call the completion handler with the bookmark data
            if (completion) {
                completion(bookmarkData, nil);
            }
        } else {
            if (completion) {
                NSError *cancelError = [NSError errorWithDomain:NSCocoaErrorDomain
                                                           code:NSUserCancelledError
                                                       userInfo:@{NSLocalizedDescriptionKey: @"User cancelled the open panel."}];
                completion(nil, cancelError);
            }
        }
    }];
}

- (void)requestNewBookmarkWithCompletion:(void (^)(NSURL *bookmarkURL, NSError *error))completion {
    [self getBookmarkWithCompletion:^(NSData *bookmarkData, NSError *error) {
        if (error) {
            // Propagate the error through the completion handler
            if (completion) completion(nil, error);
        } else {
            NSLog(@"Bookmark data obtained successfully.");
            // Save the bookmark data for future use
            NSString *prefsFilePath = [self getCustomPrefsFilePath];
            
            NSDictionary *prefs = @{@"sshBookmarkData": bookmarkData};
            BOOL success = [prefs writeToFile:prefsFilePath atomically:YES];
            if (!success) {
                NSLog(@"Failed to save the bookmark data.");
                if (completion) completion(nil, [NSError errorWithDomain:@"YourAppErrorDomain" code:100 userInfo:@{NSLocalizedDescriptionKey: @"Failed to save the bookmark data."}]);
                return;
            }
            
            // Resolve the bookmark data to an NSURL
            BOOL isStale = NO;
            NSURL *bookmarkURL = [NSURL URLByResolvingBookmarkData:bookmarkData
                                                           options:NSURLBookmarkResolutionWithSecurityScope
                                                     relativeToURL:nil
                                               bookmarkDataIsStale:&isStale
                                                             error:&error];
            if (bookmarkURL && !isStale) {
                if (completion) completion(bookmarkURL, nil);
            } else {
                if (completion) completion(nil, error);
            }
        }
    }];
}

- (void)ensureBookmarkAvailableWithCompletion:(void (^)(NSURL *bookmarkURL, NSError *error))completion {
    NSString *prefsFilePath = [self getCustomPrefsFilePath];
    
    NSDictionary *prefs = [NSDictionary dictionaryWithContentsOfFile:prefsFilePath];
    NSData *sshBookmark = [prefs objectForKey:@"sshBookmarkData"];
    
    if (sshBookmark) {
        BOOL isStale = NO;
        NSError *error = nil;
        NSURL *bookmarkURL = [NSURL URLByResolvingBookmarkData:sshBookmark
                                                       options:NSURLBookmarkResolutionWithSecurityScope
                                                 relativeToURL:nil
                                           bookmarkDataIsStale:&isStale
                                                         error:&error];
        if (bookmarkURL && !isStale) {
            // Successfully resolved the bookmark
            if (completion) completion(bookmarkURL, nil);
        } else {
            // The bookmark is stale or there was an error resolving it; obtain a new bookmark.
            [self requestNewBookmarkWithCompletion:completion];
        }
    } else {
        // No bookmark data found; request a new bookmark.
        [self requestNewBookmarkWithCompletion:completion];
    }
}

@end
