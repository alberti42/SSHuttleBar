#import <Foundation/Foundation.h>

@interface Utils : NSObject
+ (NSString *)find_path_executables:(NSArray<NSString *> *)possiblePaths withLabel:(NSString*) label;
@end
