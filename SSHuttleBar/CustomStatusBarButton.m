//
//  CustomStatusBarButton.m
//  SSHuttleBar
//
//  Created by Andrea Alberti on 11.02.24.
//

// CustomStatusBarButton.m
#import "CustomStatusBarButton.h"

@implementation CustomStatusBarButton

- (void)mouseDown:(NSEvent *)event {
    if ([event modifierFlags] & NSEventModifierFlagControl) {
        // Handle Control-click as right click
        [self rightMouseDown:event];
    } else {
        // Handle normal left click
        [super mouseDown:event];
        // Notify somehow about the left click, e.g., via delegate or notification
        NSLog(@"Left click detected.");
    }
}

- (void)rightMouseDown:(NSEvent *)event {
    // Handle right click
    // You can show the menu programmatically here or notify about the click
    NSLog(@"Right click detected.");
    // For example, showing the menu could be done here if you have a reference to it
}

@end
