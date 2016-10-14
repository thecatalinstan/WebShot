//
//  AppDelegate.m
//  WebShot
//
//  Created by Cătălin Stan on 10/04/15.
//  Copyright (c) 2015 Catalin Stan. All rights reserved.
//

#import <CSSystemInfoHelper/CSSystemInfoHelper.h>
#import <Fabric/Fabric.h>
#import <Crashlytics/Crashlytics.h>

#import "WSAppDelegate.h"
#import "WSShotController.h"

#define DefaultPortNumber          10781
#define LogConnections             0
#define LogRequests                1

static NSURL * baseURL;
static NSUInteger portNumber;
static dispatch_queue_t backgroundQueue;

NS_ASSUME_NONNULL_BEGIN

@interface WSAppDelegate () <CRServerDelegate>

@property (nonatomic, strong) CRServer *server;

- (void)startServer;
- (void)setupBaseDirectory;

@end

NS_ASSUME_NONNULL_END

@implementation WSAppDelegate

- (void)applicationWillFinishLaunching:(NSNotification *)notification {
    backgroundQueue = dispatch_queue_create([NSBundle mainBundle].bundleIdentifier.UTF8String, DISPATCH_QUEUE_SERIAL);
    dispatch_set_target_queue(backgroundQueue, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0));

    [[NSUserDefaults standardUserDefaults] registerDefaults:@{ @"NSApplicationCrashOnExceptions": @YES }];
}

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification {

//#ifndef DEBUG
    [Fabric with:@[[Crashlytics class]]];
    [CrashlyticsKit setUserIdentifier:[CSSystemInfoHelper sharedHelper].platformUUID];
    [CrashlyticsKit setUserName:[CSSystemInfoHelper sharedHelper].systemInfo[CSSystemInfoNodenameKey]];
//#endif

    [self setupBaseDirectory];

    portNumber = [[[NSUserDefaults standardUserDefaults] objectForKey:@"Port"] integerValue] ? : DefaultPortNumber;
    NSString * baseURLString = [[NSUserDefaults standardUserDefaults] objectForKey:@"BaseURL"];
    if ( !baseURLString ) {
        NSString* address = [CSSystemInfoHelper sharedHelper].IPAddress;
        baseURLString = [NSString stringWithFormat:@"http://%@:%lu", address ? : @"127.0.0.1", (unsigned long)portNumber];
    }
    baseURL = [NSURL URLWithString:baseURLString];

    BOOL isFastCGI = [[NSUserDefaults standardUserDefaults] boolForKey:@"FastCGI"];
    Class serverClass = isFastCGI ? [CRFCGIServer class] : [CRHTTPServer class];
    self.server = [[serverClass alloc] initWithDelegate:self];

    NSString* const ETagHeaderSpec = [NSString stringWithFormat:@"\"%@\"",[WSAppDelegate ETag]];
    [self.server add:^(CRRequest * _Nonnull request, CRResponse * _Nonnull response, CRRouteCompletionBlock  _Nonnull completionHandler) {
        [response setValue:[WSAppDelegate serverSpecString] forHTTPHeaderField:@"X-Criollo-Server"];
        [response setValue:ETagHeaderSpec forHTTPHeaderField:@"ETag"];
        completionHandler();
    }];
    [self.server add:@"/" block:self.server.notFoundBlock];
    [self.server add:@"/shot" controller:[WSShotController class]];

    [self startServer];
}

- (CRApplicationTerminateReply)applicationShouldTerminate:(CRApplication *)sender {
    static CRApplicationTerminateReply reply;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        // Delay the shutdown for a bit
        reply = CRTerminateLater;
        // Close server connections
        [CRApp logFormat:@"%@ Closing server connections.", [NSDate date]];
        [self.server closeAllConnections:^{
            // Stop the server and close the socket cleanly
            [CRApp logFormat:@"%@ Sutting down server.", [NSDate date]];
            [self.server stopListening];
            reply = CRTerminateNow;
        }];
    });
    return reply;
}

- (void)startServer {

    NSError *serverError;
    if ( [self.server startListening:&serverError portNumber:portNumber] ) {
        [CRApp logFormat:@"%@ Started HTTP server at %@", [NSDate date], baseURL];

        // Get the list of paths
        NSArray<NSString *> * routePaths = [self.server valueForKeyPath:@"routes.path"];
        NSMutableArray<NSURL *> *paths = [NSMutableArray array];
        [routePaths enumerateObjectsUsingBlock:^(NSString * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
            if ( [obj isKindOfClass:[NSNull class]] ) {
                return;
            }
            [paths addObject:[NSURL URLWithString:obj relativeToURL:baseURL]];
        }];
        NSArray<NSURL*>* sortedPaths =[paths sortedArrayUsingDescriptors:@[[NSSortDescriptor sortDescriptorWithKey:@"absoluteString" ascending:YES]]];

        [CRApp logFormat:@"Available paths are:"];
        [sortedPaths enumerateObjectsUsingBlock:^(NSURL * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
            [CRApp logFormat:@" * %@", obj.absoluteString];
        }];

    } else {
        [CRApp logErrorFormat:@"%@ Failed to start HTTP server. %@", [NSDate date], serverError.localizedDescription];
        [CRApp terminate:nil];
    }
}

- (void)setupBaseDirectory {
    NSError* error = nil;
    BOOL shouldFail = NO;
    NSURL* baseDirectory = [WSAppDelegate baseDirectory];
    NSString* failureReason = @"There was an error creating or loading the application's saved data.";

    NSDictionary *properties = [baseDirectory resourceValuesForKeys:@[NSURLIsDirectoryKey] error:&error];
    if (properties) {
        if (![properties[NSURLIsDirectoryKey] boolValue]) {
            failureReason = @"Expected a folder to store application data, found a file.";
            shouldFail = YES;
        }
    } else if (error.code == NSFileReadNoSuchFileError) {
        error = nil;
        [[NSFileManager defaultManager] createDirectoryAtPath:baseDirectory.path withIntermediateDirectories:YES attributes:nil error:&error];
    }

    if (shouldFail || error) {
        if ( error ) {
            failureReason = error.localizedDescription;
        }
        [CRApp logErrorFormat:@"%@ Failed to set up application directory %@. %@", [NSDate date], baseDirectory, failureReason];
        [CRApp terminate:nil];
    } else {
        [CRApp logFormat:@"%@ Successfully set up application directory %@.", [NSDate date], baseDirectory.path];
    }
}

#pragma mark - CRServerDelegate

#if LogConnections
- (void)server:(CRServer *)server didAcceptConnection:(CRConnection *)connection {
    NSString* remoteAddress = connection.remoteAddress.copy;
    NSUInteger remotePort = connection.remotePort;
    dispatch_async( backgroundQueue, ^{
        [CRApp logFormat:@"Accepted connection from %@:%d", remoteAddress, remotePort];
    });
}

- (void)server:(CRServer *)server didCloseConnection:(CRConnection *)connection {
    NSString* remoteAddress = connection.remoteAddress.copy;
    NSUInteger remotePort = connection.remotePort;
    dispatch_async( backgroundQueue, ^{
        [CRApp logFormat:@"Disconnected %@:%d", remoteAddress, remotePort];
    });
}
#endif

#if LogRequests
- (void)server:(CRServer *)server didFinishRequest:(CRRequest *)request {
    NSString* contentLength = [request.response valueForHTTPHeaderField:@"Content-Length"];
    NSString* userAgent = request.env[@"HTTP_USER_AGENT"];
    NSString* remoteAddress = request.env[@"HTTP_X_FORWARDED_FOR"].length > 0 ? request.env[@"HTTP_X_FORWARDED_FOR"] : request.env[@"REMOTE_ADDR"];
    NSUInteger statusCode = request.response.statusCode;
    dispatch_async( backgroundQueue, ^{
        [CRApp logFormat:@"%@ %@ %@ - %lu %@ - %@", [NSDate date], remoteAddress, request, statusCode, contentLength ? : @"-", userAgent];
    });
}
#endif

#pragma mark - Utils

+ (NSString *)serverSpecString {
    static NSString* serverSpecString;
    if ( serverSpecString == nil ) {
        NSBundle* bundle = [NSBundle mainBundle];
        serverSpecString = [NSString stringWithFormat:@"%@, v%@ build %@", bundle.bundleIdentifier, [bundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"], [bundle objectForInfoDictionaryKey:@"CFBundleVersion"]];
    }
    return serverSpecString;
}

+ (NSString *)ETag {
    static NSString* ETag;
    if ( ETag == nil ) {
        ETag = [[NSUUID UUID].UUIDString stringByReplacingOccurrencesOfString:@"-" withString:@""].lowercaseString;
    }
    return ETag;
}

+ (NSURL *)baseDirectory {
    static NSURL* baseDirectory;
    if ( baseDirectory == nil ) {
        baseDirectory = [[NSFileManager defaultManager] URLsForDirectory:NSApplicationSupportDirectory inDomains:NSUserDomainMask].lastObject;
        baseDirectory = [baseDirectory URLByAppendingPathComponent:[[NSBundle mainBundle] objectForInfoDictionaryKey:(__bridge NSString*)kCFBundleNameKey]];
    }
    return baseDirectory;
}

+ (NSURL *)baseURL {
    return baseURL;
}

+ (dispatch_queue_t)backgroundQueue {
    return backgroundQueue;
}

@end
