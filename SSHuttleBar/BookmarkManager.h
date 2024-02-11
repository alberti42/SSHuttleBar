//
//  BookmarkManager.h
//  SSHuttleBar
//
//  Created by Andrea Alberti on 11.02.24.
//

#import <Foundation/Foundation.h>
#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@interface BookmarkManager : NSObject

+ (instancetype)sharedManager;

- (NSString *)getCustomPrefsFilePath;
- (void)ensureSSHBookmarkAvailableAndExecuteBlock:(void (^)(NSURL *bookmarkURL))block;


@end

NS_ASSUME_NONNULL_END
