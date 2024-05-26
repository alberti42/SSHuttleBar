#import "Utils.h"

@implementation Utils

+ (NSString *)find_path_executables:(NSArray<NSString *> *)possiblePaths withLabel:(NSString*) label {
    
    NSFileManager *fileManager = [NSFileManager defaultManager];
    
    for (NSString *path in possiblePaths) {
        if ([fileManager fileExistsAtPath:path]) {
#ifdef DEBUG
            NSLog(@"Found %@ executable at: %@", label, path);
#endif
            return path;
        }
    }
    
    NSLog(@"%@ executable not found in any of the specified locations.",label);
    return nil;
}

@end
