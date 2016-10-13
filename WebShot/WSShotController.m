//
//  WSShotViewself.m
//  WebShot
//
//  Created by Cătălin Stan on 19/04/15.
//  Copyright (c) 2015 Catalin Stan. All rights reserved.
//

#import <WebKit/WebKit.h>

#import "WSShotController.h"

#define WSShotErrorDomain           @"WSShotErrorDomain"
#define WSShotErrorNoURL            101
#define WSShotErrorInvalidURL       102
#define WSShotErrorNoData           103

#define WSResultActionKey           @"WSResultAction"
#define WSResultDataKey             @"WSResultData"

typedef void(^WSSuccessBlock)(NSData* data);
typedef void(^WSFailureBlock)(NSError *error);

typedef enum _WSAction {
    WSActionScreenshot,
    WSActionHTML
} WSAction;

@interface WSShotController () <WebFrameLoadDelegate, WebDownloadDelegate>

@property (nonatomic, strong) CRRequest * request;
@property (nonatomic, strong) CRResponse * response;
@property (nonatomic, strong) NSURL * targetURL;
@property (nonatomic, copy) WSSuccessBlock successBlock;
@property (nonatomic, copy) WSFailureBlock failureBlock;
@property (nonatomic) WSAction action;

@property (strong, nonatomic) WebView *webView;

- (void)webShotWithURL:(NSURL *)URL;

- (void)succeedWithResult:(NSDictionary *)result request:(CRRequest *)request response:(CRResponse *)response;
- (void)failWithError:(NSError *)error request:(CRRequest *)request response:(CRResponse *)response;


@end

@implementation WSShotController

- (instancetype)initWithPrefix:(NSString *)prefix {
    self = [super initWithPrefix:prefix];
    if ( self != nil ) {

        self.successBlock = ^(NSData *data) { @autoreleasepool {
            if ( data.length == 0 ) {
                NSError* error = [NSError errorWithDomain:WSShotErrorDomain code:WSShotErrorNoData userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"No data was returned from the URL: %@", self.targetURL] }];
                [self failWithError:error request:self.request response:self.response];
                return;
            }
            [self succeedWithResult:@{ WSResultActionKey: @(self.action), WSResultDataKey: data } request:self.request response:self.response];
        }};

        self.failureBlock = ^(NSError *error) { @autoreleasepool {
            [self failWithError:error request:self.request response:self.response];
        }};

        self.routeBlock = ^(CRRequest * _Nonnull request, CRResponse * _Nonnull response, CRRouteCompletionBlock  _Nonnull completionHandler) { @autoreleasepool {
            NSString* targetURLString = [request.query[@"url"] stringByReplacingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
            self.targetURL = [NSURL URLWithString:targetURLString];
            if ( self.targetURL == nil ) {
                [self failWithError:[NSError errorWithDomain:WSShotErrorDomain code:WSShotErrorNoURL userInfo:request.query] request:request response:response];
                return;
            }

            if ( self.targetURL.scheme == nil ) {
                self.targetURL = [NSURL URLWithString:[@"http://" stringByAppendingString:self.targetURL.absoluteString]];
            } else if ( ![self.targetURL.scheme isEqualToString:@"http"] && ![self.targetURL.scheme isEqualToString:@"https"] ) {
                [self failWithError:[NSError errorWithDomain:WSShotErrorDomain code:WSShotErrorInvalidURL userInfo:request.query] request:request response:response];
                return;
            }

            self.request = request;
            self.response = response;
            self.action = request.query[@"html"] ? WSActionHTML : WSActionScreenshot;
            [self performSelectorOnMainThread:@selector(webShotWithURL:) withObject:self.targetURL waitUntilDone:YES];
        }};
    }
    return self;
}

#pragma mark - Responses

- (void)succeedWithResult:(NSDictionary *)result request:(CRRequest *)request response:(CRResponse *)response {
    WSAction action = (WSAction)[result[WSResultActionKey] integerValue];

    NSString* contentType = @"application/json";
    if (action == WSActionScreenshot) {
        contentType = @"image/png";
    } if (action == WSActionHTML) {
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

#pragma mark - Actions

- (void)webShotWithURL:(NSURL *)URL {
    self.webView = [[WebView alloc] initWithFrame:NSMakeRect(0, 0, 1280, 10)];
    self.webView.frameLoadDelegate = self;
    self.webView.downloadDelegate = self;
    self.webView.continuousSpellCheckingEnabled = NO;
    self.webView.mainFrame.frameView.allowsScrolling = NO;
    
    NSMutableURLRequest* request = [NSMutableURLRequest requestWithURL:URL cachePolicy:NSURLRequestReloadIgnoringCacheData timeoutInterval:10.0f];
    request.HTTPShouldHandleCookies = NO;
    [self.webView.mainFrame loadRequest:request];
}

#pragma mark - WebViewFeameLoading Delegate

- (void)webView:(WebView *)sender didFinishLoadForFrame:(WebFrame *)frame {
    if (frame != sender.mainFrame) {
        return;
    }

    NSData* returnData;

    if ( self.action == WSActionHTML ) {

        NSString* renderedContent = ((DOMHTMLElement*)frame.DOMDocument.documentElement).outerHTML;
        returnData = [renderedContent dataUsingEncoding:NSUTF8StringEncoding];

    } else if ( self.action == WSActionScreenshot ) {

        NSView *webFrameViewDocView = frame.frameView.documentView;
        NSRect webFrameRect = webFrameViewDocView.frame;
        NSRect newWebViewRect = NSMakeRect(0, 0, NSWidth(webFrameRect), NSHeight(webFrameRect) == 0 ? frame.webView.fittingSize.height : NSHeight(webFrameRect));

        NSRect cacheRect = newWebViewRect;
        NSSize imgSize = cacheRect.size;
        NSRect srcRect = NSZeroRect;
        srcRect.size = imgSize;
        srcRect.origin.y = cacheRect.size.height - imgSize.height;

        NSRect destRect = NSZeroRect;
        destRect.size = imgSize;

        NSBitmapImageRep *bitmapRep = [webFrameViewDocView bitmapImageRepForCachingDisplayInRect:cacheRect];
        [webFrameViewDocView cacheDisplayInRect:cacheRect toBitmapImageRep:bitmapRep];

        NSImage *image = [[NSImage alloc] initWithSize:imgSize];
        [image lockFocus];
        [bitmapRep drawInRect:destRect fromRect:srcRect operation:NSCompositeCopy fraction:1.0 respectFlipped:YES hints:nil];
        [image unlockFocus];

        NSBitmapImageRep* rep = [[NSBitmapImageRep alloc] initWithData:image.TIFFRepresentation];;
        returnData = [rep representationUsingType:NSPNGFileType properties:@{}];
    }
    
    self.successBlock(returnData);
}

//- (void)webView:(WebView *)sender willPerformClientRedirectToURL:(NSURL *)URL delay:(NSTimeInterval)seconds fireDate:(NSDate *)date forFrame:(WebFrame *)frame {
//}

//- (void)webView:(WebView *)sender didReceiveServerRedirectForProvisionalLoadForFrame:(WebFrame *)frame {
//}

//- (void)webView:(WebView *)sender didCommitLoadForFrame:(WebFrame *)frame {
//}

- (void)webView:(WebView *)sender didFailLoadWithError:(NSError *)error forFrame:(WebFrame *)frame {
    if (frame != sender.mainFrame){
        return;
    }
    self.failureBlock(error);
}

@end
