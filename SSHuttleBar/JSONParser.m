#import "JSONParser.h"

@implementation JSONParser
+ (NSDictionary *)parseJSONString:(NSString *)jsonString {
    NSData *jsonData = [jsonString dataUsingEncoding:NSUTF8StringEncoding];
    NSError *error;
    NSDictionary *json = [NSJSONSerialization JSONObjectWithData:jsonData options:0 error:&error];
    
    if (error) {
        NSLog(@"JSON conversion error: %@", [error localizedDescription]);
        return nil;
    }
    
    return json;
}
@end
