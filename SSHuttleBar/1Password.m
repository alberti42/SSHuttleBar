#import "1Password.h"
#import "JSONParser.h"
#import "Utils.h"

@implementation OnePasswordInterface

NSString* path_op = nil;

+ (NSString *)executeShellCommandWithPath:(NSString *)path andArguments:(NSArray<NSString *> *)arguments {
#ifdef DEBUG
    // NSLog(@"Executing command: %@ %@", path, [arguments componentsJoinedByString:@" "]);
#endif

    NSTask *task = [[NSTask alloc] init];
    task.launchPath = path;
    task.arguments = arguments;

    NSPipe *outputPipe = [NSPipe pipe];
    NSPipe *errorPipe = [NSPipe pipe];
    task.standardOutput = outputPipe;
    task.standardError = errorPipe;

    NSFileHandle *outputFile = outputPipe.fileHandleForReading;
    NSFileHandle *errorFile = errorPipe.fileHandleForReading;

    [task launch];
    [task waitUntilExit];

    NSData *outputData = [outputFile readDataToEndOfFile];
    NSData *errorData = [errorFile readDataToEndOfFile];

    [outputFile closeFile];
    [errorFile closeFile];

    NSString *outputString = [[NSString alloc] initWithData:outputData encoding:NSUTF8StringEncoding];
    NSString *errorString = [[NSString alloc] initWithData:errorData encoding:NSUTF8StringEncoding];

#ifdef DEBUG
    //NSLog(@"Output: %@", outputString);
    //NSLog(@"Error: %@", errorString);
#endif
    
    if (errorString.length > 0) {
        return nil; // or handle the error appropriately
    }

    return outputString;
}

+(NSDictionary<NSString *, NSString *> *)getCredentialsForId:(NSString *)theId {
    if(!path_op) {
        path_op = [Utils find_path_executables:@[@"/usr/local/bin/op"] withLabel:@"op"];
    }
    
    NSString *theOutput = [OnePasswordInterface executeShellCommandWithPath:path_op
                                                               andArguments:@[@"item", @"get", theId, @"--format", @"json"]];
    
    if (theOutput == nil) {
        NSLog(@"Failed to execute shell command");
        return nil;
    }
    
    NSDictionary *resultQuery = [JSONParser parseJSONString:theOutput];
    
    if (resultQuery == nil) {
        NSLog(@"Failed to parse JSON string");
        return nil;
    }
    
    NSArray *fields = resultQuery[@"fields"];
    
    if (fields.count > 8) {
        NSString *theUsername = fields[1][@"value"];
        NSString *thePassword = fields[2][@"value"];
        NSString *theOTP = fields[8][@"totp"];
        
#ifdef DEBUG
        NSLog(@"Username: %@", theUsername);
        NSLog(@"Password: %@", thePassword);
        NSLog(@"OTP: %@", theOTP);
#endif
        return @{
            @"username": theUsername,
            @"password": thePassword,
            @"otp": theOTP
        };
    } else {
        NSLog(@"Unexpected JSON structure");
        return nil;
    }
    
    
}

@end
