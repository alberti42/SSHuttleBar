#import <Foundation/Foundation.h>

@interface JSONParser : NSObject
+ (NSDictionary *)parseJSONString:(NSString *)jsonString;
@end

