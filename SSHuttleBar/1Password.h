#import <Foundation/Foundation.h>

@interface OnePasswordInterface : NSObject
+(NSDictionary<NSString *, NSString *> *)getCredentialsForId:(NSString *)theId;
@end
