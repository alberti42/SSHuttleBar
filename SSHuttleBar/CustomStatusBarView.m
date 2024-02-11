//
//  CustomStatusBarView.m
//  SSHuttleBar
//
//  Created by Andrea Alberti on 11.02.24.
//

#import "CustomStatusBarView.h"

@implementation CustomStatusBarView

- (void)mouseDown:(NSEvent *)event {
    if (self.leftClickHandler) {
        self.leftClickHandler();
    }
}

- (void)rightMouseDown:(NSEvent *)event {
    if (self.rightClickHandler) {
        self.rightClickHandler();
    }
}

@end
