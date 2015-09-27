//
//  WSShotViewController.m
//  WebShot
//
//  Created by Cătălin Stan on 19/04/15.
//  Copyright (c) 2015 Catalin Stan. All rights reserved.
//

#import "WSShotViewController.h"
#import <Cocoa/Cocoa.h>

typedef void(^WSSuccessBlock)(NSData* data, BOOL shouldCache);
typedef void(^WSFailureBlock)(NSError *error);

typedef enum _WSAction
{
    WSActionScreenshot,
    WSActionHTML
} WSAction;

#ifdef __MAC_10_11
@interface WSShotViewController () <WebFrameLoadDelegate, WebDownloadDelegate> {
#else
@interface WSShotViewController () {
#endif
    WSSuccessBlock _successBlock;
    WSFailureBlock _failureBlock;
    WSAction _action;
}

@property (strong, nonatomic) WebView *webView;
@property (strong, nonatomic) NSWindow* window;

- (void)fetchHTML;
- (void)fetchScreenshot;
- (void)performAction:(WSAction)action;

- (void)performAction:(WSAction)action withURL:(NSURL *)URL success:(WSSuccessBlock)success failure:(WSFailureBlock)failure;

- (void)succeedWithResult:(NSDictionary*)result;
- (void)failWithError:(NSError*)error;
    
+ (NSMutableDictionary*)cachedFiles;

@end

@implementation WSShotViewController
    
+ (NSMutableDictionary *)cachedFiles
{
    static NSMutableDictionary* cachedFiles;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        cachedFiles = [NSMutableDictionary dictionary];
    });
    return cachedFiles;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
#if DEBUG
    NSLog(@"%s", __PRETTY_FUNCTION__);
#endif
    NSString* targetURLString = [self.request.get[@"url"] stringByReplacingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
    _targetURL = [NSURL URLWithString:targetURLString];
}

- (NSString *)presentViewController:(BOOL)writeData
{
#if DEBUG
    NSLog(@"%s", __PRETTY_FUNCTION__);
#endif
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
#if DEBUG
    NSLog(@"%s", __PRETTY_FUNCTION__);
#endif
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
#if DEBUG
    NSLog(@"%s", __PRETTY_FUNCTION__);
#endif
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
    
    NSData* responseData = [NSJSONSerialization dataWithJSONObject:outputDictionary.copy options:0 error:&error];

    [self.response setHTTPStatus:500];
    [self.response setValue:@"application/json; charset=utf-8" forHTTPHeaderField:@"Content-type"];
    [self.response write:responseData];
    [self.response finish];
}

#pragma mark - Actions

- (void)fetchHTML
{
#if DEBUG
    NSLog(@"%s", __PRETTY_FUNCTION__);
#endif
    [self performAction:WSActionHTML];
}

- (void)fetchScreenshot
{
#if DEBUG
    NSLog(@"%s", __PRETTY_FUNCTION__);
#endif
    [self performAction:WSActionScreenshot];
}

- (void)performAction:(WSAction)action
{
#if DEBUG
    NSLog(@"%s", __PRETTY_FUNCTION__);
#endif
    
    [self performAction:action withURL:self.targetURL success:^(NSData *data, BOOL shouldCache) {

#if DEBUG
        NSLog(@"%s", __PRETTY_FUNCTION__);
#endif
        
        if ( data.length == 0 ) {
            NSError* error = [NSError errorWithDomain:[NSBundle mainBundle].bundleIdentifier code:-1 userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"No data was returned from the URL: %@", self.targetURL]}];
            [self failWithError:error];
        } else {
            if ( shouldCache ) {
                [self cacheResult:data forAction:action forURL:self.targetURL];
            }
            [self succeedWithResult:@{FKResultKey:data}];
        }
    } failure:^(NSError *error) {
#if DEBUG
        NSLog(@"%s", __PRETTY_FUNCTION__);
#endif
        [self failWithError:error];
    }];
}

- (void)performAction:(WSAction)action withURL:(NSURL *)URL success:(WSSuccessBlock)success failure:(WSFailureBlock)failure {
    
#if DEBUG
    NSLog(@"%s", __PRETTY_FUNCTION__);
#endif
    
    _action = action;
    _successBlock = success;
    _failureBlock = failure;
    
    NSData* cachedResult = [self cachedResultForAction:action forURL:URL];
    
    if ( cachedResult != nil ) {
        _successBlock(cachedResult, NO);
    } else {
    
        self.webView = [[WebView alloc] initWithFrame:NSMakeRect(0, 0, 1280, 10)];
        self.webView.frameLoadDelegate = self;
        self.webView.downloadDelegate = self;
        self.webView.continuousSpellCheckingEnabled = NO;
        self.webView.mainFrame.frameView.allowsScrolling = NO;
        
        NSMutableURLRequest* request = [NSMutableURLRequest requestWithURL:URL cachePolicy:NSURLRequestReloadIgnoringCacheData timeoutInterval:10.0f];
        request.HTTPShouldHandleCookies = YES;
        [self.webView.mainFrame loadRequest:request.copy];
    }
}

#pragma mark - WebViewFeameLoading Delegate

- (void)webView:(WebView *)sender didFinishLoadForFrame:(WebFrame *)frame
{
    
#if DEBUG
    NSLog(@"%s", __PRETTY_FUNCTION__);
#endif
    
    if (frame != sender.mainFrame) {
        return;
    }
    
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        NSData* returnData;
        
        if ( _action == WSActionHTML ) {
            
            NSString* renderedContent = ((DOMHTMLElement*)frame.DOMDocument.documentElement).outerHTML;
            returnData = [renderedContent dataUsingEncoding:NSUTF8StringEncoding];
            
        } else if ( _action == WSActionScreenshot ) {
            
            NSView *webFrameViewDocView = frame.frameView.documentView;
            NSRect webFrameRect = webFrameViewDocView.frame;
            NSRect newWebViewRect = NSMakeRect(0, 0, NSWidth(webFrameRect), NSHeight(webFrameRect) == 0 ? frame.webView.fittingSize.height : NSHeight(webFrameRect));
            
            NSRect cacheRect = newWebViewRect;
            NSLog(@"%@", NSStringFromRect(cacheRect));
            
            NSSize imgSize = cacheRect.size;
            //        imgSize.height = MIN(MAX(actualHeight, 800), 3840);
            
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
        
        _successBlock(returnData, YES);
    });
}
    
- (void)webView:(WebView *)sender willPerformClientRedirectToURL:(NSURL *)URL delay:(NSTimeInterval)seconds fireDate:(NSDate *)date forFrame:(WebFrame *)frame
{
#if DEBUG
    NSLog(@"%s", __PRETTY_FUNCTION__);
#endif
}
    
- (void)webView:(WebView *)sender didReceiveServerRedirectForProvisionalLoadForFrame:(WebFrame *)frame
{
#if DEBUG
        NSLog(@"%s %@", __PRETTY_FUNCTION__, frame.DOMDocument.URL);
#endif

}
    
- (void)webView:(WebView *)sender didCommitLoadForFrame:(WebFrame *)frame
{
#if DEBUG
        NSLog(@"%s", __PRETTY_FUNCTION__);
#endif

}

- (void)webView:(WebView *)sender didFailLoadWithError:(NSError *)error forFrame:(WebFrame *)frame
{
#if DEBUG
    NSLog(@"%s", __PRETTY_FUNCTION__);
#endif
    
    if (frame != sender.mainFrame){
        return;
    }
    _failureBlock(error);
}
    
#pragma mark - Cache
    
- (NSString*)cacheDir:(WSAction)action
{
    NSString* cacheDirName = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSBundle mainBundle].bundleIdentifier];
    cacheDirName = [cacheDirName stringByAppendingPathComponent:(action == WSActionHTML ? @"HTMLs" : @"Screenshots")];
    if ( ![[NSFileManager defaultManager] fileExistsAtPath:cacheDirName isDirectory:nil] ) {
        [[NSFileManager defaultManager] createDirectoryAtPath:cacheDirName withIntermediateDirectories:YES attributes:nil error:nil];
    }
    return cacheDirName;
}
    
- (NSData*)cachedResultForAction:(WSAction)action forURL:(NSURL*)URL
{
#if DEBUG
    NSLog(@"%s", __PRETTY_FUNCTION__);
#endif
    
    NSString* cacheDirName = [self cacheDir:action];
    
    NSString* fileName;
    @synchronized([WSShotViewController cachedFiles]) {
        fileName = [WSShotViewController cachedFiles][URL.absoluteString];
    }

    if ( fileName == nil ) {
        return nil;
    } else {
        NSString* filePath = [cacheDirName stringByAppendingPathComponent:fileName];
        if ( ![[NSFileManager defaultManager] fileExistsAtPath:filePath isDirectory:nil] ) {
            return nil;
        } else {
            return [NSData dataWithContentsOfFile:filePath options:NSDataReadingMappedIfSafe error:nil];
        }
    }
    
}
    
- (void)cacheResult:(NSData*)result forAction:(WSAction)action forURL:(NSURL*)URL
{
#if DEBUG
    NSLog(@"%s", __PRETTY_FUNCTION__);
#endif
    
    NSString* cacheDirName = [self cacheDir:action];

    NSString* fileName;
    @synchronized([WSShotViewController cachedFiles]) {
        fileName = [WSShotViewController cachedFiles][URL.absoluteString];
    }
    
    if ( fileName != nil ) {
        return;
    } else {
        fileName = [[NSProcessInfo processInfo] globallyUniqueString];
        NSString* filePath = [cacheDirName stringByAppendingPathComponent:fileName];
        
        [result writeToFile:filePath atomically:YES];
        
        @synchronized([WSShotViewController cachedFiles]) {
            [WSShotViewController cachedFiles][URL.absoluteString] = fileName;
        }
    }
}
    
@end
