//
//  AppDelegate.m
//  WebShot
//
//  Created by Cătălin Stan on 10/04/15.
//  Copyright (c) 2015 Catalin Stan. All rights reserved.
//

#import "AppDelegate.h"

@implementation AppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification {
}

- (void)applicationWillTerminate:(NSNotification *)aNotification {
}

- (void)application:(FKApplication *)application didReceiveRequest:(NSDictionary *)userInfo
{
}

- (void)application:(FKApplication *)application didPrepareResponse:(NSDictionary *)userInfo
{
}

- (void)application:(FKApplication *)application presentViewController:(FKViewController *)viewController
{
#if DEBUG
    NSLog(@"%s", __PRETTY_FUNCTION__);
#endif
    [viewController presentViewController:NO];
}

- (void)application:(FKApplication *)application didNotFindViewController:(NSDictionary *)userInfo
{
#if DEBUG
    NSLog(@"%s", __PRETTY_FUNCTION__);
#endif
    FKHTTPRequest* request = userInfo[FKRequestKey];
    FKHTTPResponse* response = userInfo[FKResponseKey];
    
    NSString* responseString = [NSString stringWithFormat:@"The URL %@ was not found", request.parameters[@"REQUEST_URI"]];
    
    [response setHTTPStatus:404];
    [response setValue:@"text/plain; charset=utf-8" forHTTPHeaderField:@"Content-type"];
    [response writeString: responseString];
    
    [response finish];
}

@end
