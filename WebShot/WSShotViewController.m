//
//  WSShotViewController.m
//  WebShot
//
//  Created by Cătălin Stan on 19/04/15.
//  Copyright (c) 2015 Catalin Stan. All rights reserved.
//

#import "WSShotViewController.h"
#import <Cocoa/Cocoa.h>

typedef void(^WSSuccessBlock)(NSData* data);
typedef void(^WSFailureBlock)(NSError *error);

typedef enum _WSAction
{
    WSActionScreenshot,
    WSActionHTML
} WSAction;

@interface WSShotViewController () {
    WSSuccessBlock _successBlock;
    WSFailureBlock _failureBlock;
    WSAction _action;
}

@property (strong, nonatomic) WebView *webView;

- (void)fetchHTML;
- (void)fetchScreenshot;
- (void)performAction:(WSAction)action;

- (void)performAction:(WSAction)action withURL:(NSURL *)URL success:(WSSuccessBlock)success failure:(WSFailureBlock)failure;

- (void)succeedWithResult:(NSDictionary*)result;
- (void)failWithError:(NSError*)error;

@end

@implementation WSShotViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    NSString* targetURLString = [self.request.get[@"url"] stringByReplacingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
    _targetURL = [NSURL URLWithString:targetURLString];
}

- (NSString *)presentViewController:(BOOL)writeData
{
    
    @try {
        
        if ( self.targetURL == nil ) {
            @throw [NSException exceptionWithName:NSInvalidArgumentException reason:@"No URL was specified." userInfo:self.request.get];
        }
        
        if ( self.targetURL.scheme == nil ) {
            _targetURL = [NSURL URLWithString:[@"http://" stringByAppendingString:self.targetURL.absoluteString]];
        } else if ( ![self.targetURL.scheme isEqualToString:@"http"] && ![self.targetURL.scheme isEqualToString:@"https"] ) {
            @throw [NSException exceptionWithName:NSInvalidArgumentException reason:[NSString stringWithFormat: @"Unsupported URL scheme: %@", self.targetURL.scheme] userInfo:self.request.get];
        }
        
        if ( self.request.get[@"html"] != nil ) {
            [self performSelectorOnMainThread:@selector(fetchHTML) withObject:nil waitUntilDone:NO];
        } else {
            [self performSelectorOnMainThread:@selector(fetchScreenshot) withObject:nil waitUntilDone:NO];
        }
        
    } @catch (NSException *ex) {
        
        [self failWithError:[NSError errorWithDomain:[NSBundle mainBundle].bundleIdentifier code:-1 userInfo:@{NSUnderlyingErrorKey: ex}]];
        
    }
    
    return nil;
}

#pragma mark - Responses

- (void)succeedWithResult:(NSDictionary*)result
{
    NSData* responseData = result[FKResultKey];
    NSString* contentType = @"text/plain";
    if (_action == WSActionScreenshot) {
        contentType = @"image/png";
    } if (_action == WSActionHTML) {
        contentType = @"text/html";
    }
    
    [self.response setHTTPStatus:200];
    [self.response setValue:contentType forHTTPHeaderField:@"Content-type"];
    [self.response setValue:@"inline" forHTTPHeaderField:@"Content-disposition"];
    [self.response setValue:@(responseData.length).stringValue forHTTPHeaderField:@"Content-length"];
    [self.response write:responseData];
    [self.response finish];
}

- (void)failWithError:(NSError*)error
{
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
    
    
    NSMutableDictionary* outputDictionary = [NSMutableDictionary dictionary];
    outputDictionary[@"status"] = @(NO);
    outputDictionary[@"error"] = @{
                                   @"domain": errorTitle,
                                   @"code": @(errorCode),
                                   @"description": errorDescription,
                                   };
    
    NSData* responseData = [NSJSONSerialization dataWithJSONObject:outputDictionary.copy options:0 error:&error];

    [self.response setHTTPStatus:500];
    [self.response setValue:@"application/json; charset=utf-8" forHTTPHeaderField:@"Content-type"];
    [self.response write:responseData];
    [self.response finish];
}

#pragma mark - Actions

- (void)fetchHTML
{
    [self performAction:WSActionHTML];
}

- (void)fetchScreenshot
{
    [self performAction:WSActionScreenshot];
}

- (void)performAction:(WSAction)action
{
    [self performAction:action withURL:self.targetURL success:^(NSData *data) {
        if ( data.length == 0 ) {
            NSError* error = [NSError errorWithDomain:[NSBundle mainBundle].bundleIdentifier code:-1 userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"No data was returned from the URL: %@", self.targetURL]}];
            [self failWithError:error];
        } else {
            [self succeedWithResult:@{FKResultKey:data}];
        }
    } failure:^(NSError *error) {
        [self failWithError:error];
    }];
}

- (void)performAction:(WSAction)action withURL:(NSURL *)URL success:(WSSuccessBlock)success failure:(WSFailureBlock)failure {
    
    _action = action;
    _successBlock = success;
    _failureBlock = failure;
    
    self.webView = [[WebView alloc] init];
    self.webView.frame = NSMakeRect(0, 0, 1280, 3840);
    self.webView.frameLoadDelegate = self;
    self.webView.downloadDelegate = self;
    self.webView.mainFrameURL = URL.absoluteString;
}

#pragma mark - WebViewFeameLoading Delegate

- (void)webView:(WebView *)sender didFinishLoadForFrame:(WebFrame *)frame
{
    if (frame != sender.mainFrame) {
        return;
    }
    
    NSData* returnData;
    
    if ( _action == WSActionHTML ) {
        
        NSString* renderedContent = ((DOMHTMLElement*)frame.DOMDocument.documentElement).outerHTML;
        returnData = [renderedContent dataUsingEncoding:NSUTF8StringEncoding];
        
    } else if ( _action == WSActionScreenshot ) {
        
        NSView *webFrameViewDocView = frame.frameView.documentView;
        CGFloat actualHeight;
        DOMNodeList* nodes = [frame.DOMDocument getElementsByTagName:@"body"];
        if ( nodes.length == 1 ) {
            DOMElement* body = (DOMElement*)[nodes item:0];
            actualHeight = body.offsetHeight;
        } else {
            actualHeight = @(frame.DOMDocument.documentElement.offsetHeight).floatValue;
        }
        
        NSRect cacheRect = webFrameViewDocView.bounds;
        
        NSSize imgSize = cacheRect.size;
        imgSize.height = MIN(MAX(actualHeight, 800), 3840);
        
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
        returnData = [rep representationUsingType:NSPNGFileType properties:nil];
    }
    
    _successBlock(returnData);
}

- (void)webView:(WebView *)sender didFailLoadWithError:(NSError *)error forFrame:(WebFrame *)frame
{
    if (frame != sender.mainFrame){
        return;
    }
    _failureBlock(error);
}

@end
