//
//  UpdateManager.m
//  KompleteSynthesia
//
//  Created by Till Toenshoff on 10.12.23.
//

#import "UpdateManager.h"

#import <Cocoa/Cocoa.h>

/// Checks if we are currently running the latest version or if GitHub has a newer one available.

NSString* kAppDefaultCheckForUpdate = @"check_for_updates_on_startup";

NSString* kOwner = @"tillt";
NSString* kProject = @"KompleteSynthesia";

@implementation UpdateManager

+ (NSString*)LatestReleaseTag:(NSArray*)releases forPreReleases:(BOOL)pre
{
    // GitHub returns the tags in chronological order. That means we can pass through
    // the returned tags and find the first one that is not a pre-release to find the
    // latest release.
    //
    // Releases have a single "." splitting the major and minor version number.
    for (NSDictionary* release in releases) {
        NSString* tag = [release objectForKey:@"name"];
        unsigned long dots = [[tag componentsSeparatedByString:@"."] count] - 1;
        if (pre == NO && dots != 1) {
            NSLog(@"skipping %@ as it is not a release", tag);
            continue;
        }
        return tag;
    }
    return nil;
}

+ (void)UpdateCheckWithCompletion:(void (^)(NSString* status))completion
{
    NSString* repo = [NSString stringWithFormat:@"https://api.github.com/repos/%@/%@/tags", kOwner, kProject];

    NSMutableURLRequest* request = [[NSMutableURLRequest alloc] initWithURL:[NSURL URLWithString:repo]];
    [request setHTTPMethod:@"GET"];
    NSURLSession* session = [NSURLSession sharedSession];
    NSURLSessionDataTask* dataTask =
        [session dataTaskWithRequest:request
                   completionHandler:^(NSData* data, NSURLResponse* response, NSError* error) {
                     BOOL updateAvailable = NO;
                     NSHTTPURLResponse* httpResponse = (NSHTTPURLResponse*)response;
                     NSString* status = @"";
                     NSString* tag = @"";
                     if (httpResponse.statusCode == 200) {
                         NSError* error = nil;
                         id object = [NSJSONSerialization JSONObjectWithData:data options:0 error:&error];
                         if ([object isKindOfClass:[NSArray class]]) {
                             NSArray* results = object;
                             NSString* version =
                                 [[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleShortVersionString"];
                             NSString* versionTag = [NSString stringWithFormat:@"v%@", version];
                             unsigned long dots = [[version componentsSeparatedByString:@"."] count] - 1;
                             BOOL runningPreRelease = dots != 1;
                             tag = [UpdateManager LatestReleaseTag:results forPreReleases:runningPreRelease];
                             if ([tag compare:versionTag] != NSOrderedSame) {
                                 NSLog(@"there is a different version available");
                                 status = @"update available";
                                 updateAvailable = YES;
                             } else {
                                 NSLog(@"this is the latest version");
                                 status = @"using latest version";
                             }
                         } else {
                             NSLog(@"Expected array of tags but got something else");
                             status = @"received unexpected contents";
                         }
                     } else {
                         NSLog(@"HTTP status code %d", (int)httpResponse.statusCode);
                         status = [NSString stringWithFormat:@"received HTTP status %d", (int)httpResponse.statusCode];
                     }

                     dispatch_async(dispatch_get_main_queue(), ^{
                       completion(status);

                       if (updateAvailable) {
                           NSAlert* alert = [NSAlert new];
                           alert.messageText = @"There is a new version of Komplete Synthesia available.";
                           alert.alertStyle = NSAlertStyleInformational;
                           [alert addButtonWithTitle:@"Download"];
                           [alert addButtonWithTitle:@"Cancel"];
                           long index = [alert runModal];
                           if (index == 1000) {
                               NSString* binaryName = [NSString stringWithFormat:@"KompleteSynthesia.%@.dmg", tag];
                               NSString* updateUrl =
                                   [NSString stringWithFormat:@"https://github.com/%@/%@/releases/download/%@/%@",
                                                              kOwner, kProject, tag, binaryName];
                               [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:updateUrl]];
                           }
                       }
                     });
                   }];

    [dataTask resume];
}

+ (BOOL)CheckForUpdates
{
    NSUserDefaults* userDefaults = [NSUserDefaults standardUserDefaults];
    return [userDefaults boolForKey:kAppDefaultCheckForUpdate];
}

@end
