//
//  CustomStatusBarView.h
//  SSHuttleBar
//
//  Created by Andrea Alberti on 11.02.24.
//

#import <Cocoa/Cocoa.h>
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface CustomStatusBarView : NSObject
@property (nonatomic, copy) void (^leftClickHandler)(void);
@property (nonatomic, copy) void (^rightClickHandler)(void);
@end

NS_ASSUME_NONNULL_END
