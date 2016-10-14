//
//  WSShotViewself.m
//  WebShot
//
//  Created by Cătălin Stan on 19/04/15.
//  Copyright (c) 2015 Catalin Stan. All rights reserved.
//

#import <WebKit/WebKit.h>
#import <CSWebShot/CSWebShot.h>

#import "WSShotController.h"
#import "WSAppDelegate.h"

#define WSShotErrorDomain           @"WSShotErrorDomain"
#define WSShotErrorNoURL            101
#define WSShotErrorInvalidURL       102
#define WSShotErrorNoData           103

#define WSResultActionKey           @"WSResultAction"
#define WSResultDataKey             @"WSResultData"

@interface WSShotController () <WebFrameLoadDelegate, WebDownloadDelegate>

@property (nonatomic, strong) CRRequest * request;
@property (nonatomic, strong) CRResponse * response;

@property (nonatomic, strong) NSURL * targetURL;

@property (nonatomic, strong) CSWebShot * webshot;
@property (nonatomic, copy) WSCompletionBlock completion;

- (void)succeedWithResult:(NSDictionary *)result request:(CRRequest *)request response:(CRResponse *)response;
- (void)failWithError:(NSError *)error request:(CRRequest *)request response:(CRResponse *)response;

@end

@implementation WSShotController

- (instancetype)initWithPrefix:(NSString *)prefix {
    self = [super initWithPrefix:prefix];
    if ( self != nil ) {

        self.webshot = [[CSWebShot alloc] initWithURL:nil];
        self.webshot.delegateQueue = [WSAppDelegate backgroundQueue];

        WSShotController * __weak controller = self;
        self.completion = ^ (WSAction action, NSData *data, NSError *error ){
            if ( error ) {
                [controller failWithError:error request:controller.request response:controller.response];
                return;
            }

            if ( data.length == 0 ) {
                NSError* error = [NSError errorWithDomain:WSShotErrorDomain code:WSShotErrorNoData userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"No data was returned from the URL: %@", controller.targetURL] }];
                [controller failWithError:error request:controller.request response:controller.response];
                return;
            }

            [controller succeedWithResult:@{ WSResultActionKey: @(action), WSResultDataKey: data } request:controller.request response:controller.response];
        };

        self.routeBlock = ^(CRRequest * _Nonnull request, CRResponse * _Nonnull response, CRRouteCompletionBlock  _Nonnull completionHandler) { @autoreleasepool {
            NSString* targetURLString = [request.query[@"url"] stringByReplacingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
            controller.targetURL = [NSURL URLWithString:targetURLString];
            if ( self.targetURL == nil ) {
                [controller failWithError:[NSError errorWithDomain:WSShotErrorDomain code:WSShotErrorNoURL userInfo:request.query] request:request response:response];
                return;
            }

            if ( controller.targetURL.scheme == nil ) {
                controller.targetURL = [NSURL URLWithString:[@"http://" stringByAppendingString:controller.targetURL.absoluteString]];
            } else if ( ![controller.targetURL.scheme isEqualToString:@"http"] && ![controller.targetURL.scheme isEqualToString:@"https"] ) {
                [controller failWithError:[NSError errorWithDomain:WSShotErrorDomain code:WSShotErrorInvalidURL userInfo:request.query] request:request response:response];
                return;
            }

            controller.request = request;
            controller.response = response;

            controller.webshot.URL = controller.targetURL;

            if ( request.query[@"w"] ) {
                CGFloat width = MIN(MAX([request.query[@"w"] floatValue], 320), 3840);
                controller.webshot.browserWidth = width;
            }

            if ( request.query[@"t"] ) {
                NSTimeInterval timeout = MIN(MAX([request.query[@"t"] doubleValue], 1), 60);
                controller.webshot.renderingTimeout = timeout;
            }

            if ( request.query[@"html"] ) {
                [controller.webshot renderedHTMLWithCompletion:controller.completion];
            } else {
                [controller.webshot webshotWithCompletion:controller.completion];
            }
        }};
    }
    return self;
}

#pragma mark - Responses

- (void)succeedWithResult:(NSDictionary *)result request:(CRRequest *)request response:(CRResponse *)response {
    WSAction action = (WSAction)[result[WSResultActionKey] integerValue];

    NSString* contentType = @"application/json";
    if (action == WSActionWebShot) {
        contentType = @"image/png";
    } if (action == WSActionFetchHTML) {
        contentType = @"text/html";
    }

    [response setStatusCode:200 description:nil];
    [response setValue:contentType forHTTPHeaderField:@"Content-type"];
    [response setValue:@"inline" forHTTPHeaderField:@"Content-disposition"];

    NSData* responseData = result[WSResultDataKey];
    [response setValue:@(responseData.length).stringValue forHTTPHeaderField:@"Content-length"];
    [response sendData:responseData];
}

- (void)failWithError:(NSError*)error request:(CRRequest *)request response:(CRResponse *)response {
    NSString* errorDescription;
    NSString* errorTitle;
    NSDictionary* errorUserInfo;
    NSUInteger errorCode;
    
    if ( error.userInfo[NSUnderlyingErrorKey] ) {
        if ( [error.userInfo[NSUnderlyingErrorKey] isKindOfClass:[NSError class] ] ) {
            NSError* underlyingError = error.userInfo[NSUnderlyingErrorKey];
            errorTitle = underlyingError.domain;
            errorCode = underlyingError.code;
            errorDescription = underlyingError.localizedDescription;
            errorUserInfo = underlyingError.userInfo;
        } else if ( [error.userInfo[NSUnderlyingErrorKey] isKindOfClass:[NSException class] ] ) {
            NSException* underlyingError = error.userInfo[NSUnderlyingErrorKey];
            errorTitle = underlyingError.name;
            errorCode = NSNotFound;
            errorDescription = underlyingError.reason;
            errorUserInfo = underlyingError.userInfo;
        } else {
            errorTitle = error.domain;
            errorCode = error.code;
            errorDescription = error.localizedDescription;
            errorUserInfo = error.userInfo;
        }
    } else {
        errorTitle = error.domain;
        errorCode = error.code;
        errorDescription = error.localizedDescription;
        errorUserInfo = error.userInfo;
    }
    
    if ( errorUserInfo == nil ) {
        errorUserInfo = @{};
    }

    NSMutableDictionary* outputDictionary = [NSMutableDictionary dictionary];
    outputDictionary[@"status"] = @(NO);
    outputDictionary[@"error"] = @{
                                   @"domain": errorTitle,
                                   @"code": @(errorCode),
                                   @"description": errorDescription,
                                   @"userInfo": errorUserInfo,
                                   };
    
    [response setStatusCode:500 description:nil];
    [response setValue:@"application/json; charset=utf-8" forHTTPHeaderField:@"Content-type"];
    [response send:outputDictionary];
}

@end
