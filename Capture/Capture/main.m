//
//  main.m
//  Capture
//
//  Created by Cătălin Stan on 22/04/15.
//  Copyright (c) 2015 Catalin Stan. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <Cocoa/Cocoa.h>
#import <WebKit/WebKit.h>

BOOL shouldKeepRunning;
NSFileHandle* stdOut;
NSFileHandle* stdErr;
NSData* failWithError(NSError* error);
NSData* succeedWithResult(NSDictionary* result);

@interface WSCAppDelegate : NSObject

@property (strong, nonatomic) WebView *webView;

- (void)timerCallback;
- (void)captureImage:(NSURL*)url;

- (void)didGetImage:(NSImage*)image;
- (void)didGetError:(NSError*)error;

@end

@implementation WSCAppDelegate

- (instancetype)init
{
    self = [super init];
    if ( self != nil ) {
    }
    return self;
}

- (void)timerCallback{
}

- (void)didGetImage:(NSImage *)image
{
    NSBitmapImageRep* rep = [[NSBitmapImageRep alloc] initWithData:image.TIFFRepresentation];;
    NSData* imageData = [rep representationUsingType:NSPNGFileType properties:nil];
    NSData* responseData = succeedWithResult(@{@"result": imageData});
    [stdOut writeData:responseData];
    CFRunLoopStop([NSRunLoop mainRunLoop].getCFRunLoop);
    shouldKeepRunning = NO;
}

- (void)didGetError:(NSError *)error
{
    NSData* responseData = failWithError(error);
    [stdErr writeData:responseData];
    CFRunLoopStop([NSRunLoop mainRunLoop].getCFRunLoop);
    shouldKeepRunning = NO;
}

- (void)captureImage:(NSURL*)url
{
    self.webView = [[WebView alloc] init];
    self.webView.frame = NSMakeRect(0, 0, 1280, 3840);
    self.webView.frameLoadDelegate = self;
    self.webView.downloadDelegate = self;
    self.webView.mainFrameURL = url.absoluteString;
}

- (void)webView:(WebView *)sender didFinishLoadForFrame:(WebFrame *)frame
{
    if (frame != sender.mainFrame) {
        return;
    }
    
//    NSString* renderedContent = ((DOMHTMLElement*)frame.DOMDocument.documentElement).outerHTML;
    
    NSView *webFrameViewDocView = frame.frameView.documentView;
    CGFloat actualHeight = @(frame.DOMDocument.documentElement.offsetHeight).floatValue;
    
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

    NSImage *webImage = [[NSImage alloc] initWithSize:imgSize];
    [webImage lockFocus];
    [bitmapRep drawInRect:destRect fromRect:srcRect operation:NSCompositeCopy fraction:1.0 respectFlipped:YES hints:nil];
    [webImage unlockFocus];
    
    [self performSelectorOnMainThread:@selector(didGetImage:) withObject:webImage waitUntilDone:NO];
}

- (void)webView:(WebView *)sender didFailLoadWithError:(NSError *)error forFrame:(WebFrame *)frame
{
    if (frame != sender.mainFrame){
        return;
    }
    [self performSelectorOnMainThread:@selector(didGetError:) withObject:error waitUntilDone:NO];
}


@end

NSArray* startupArguments;
CFRunLoopObserverRef mainRunLoopObserver;
WSCAppDelegate* appDelegate;
NSURL* targetURL;

int exitStatus;

void mainRunLoopObserverCallback( CFRunLoopObserverRef observer, CFRunLoopActivity activity, void *info )
{
}

NSData* succeedWithResult(NSDictionary* result)
{
    exitStatus = EXIT_SUCCESS;
    NSData* imageData = result[@"result"];
    return imageData;
}

NSData* failWithError(NSError* error)
{
    exitStatus = EXIT_FAILURE;
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
    
    return [[errorDescription stringByAppendingString:@"\n"] dataUsingEncoding:NSUTF8StringEncoding];
}

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        ProcessSerialNumber psn = { 0, kCurrentProcess };
        TransformProcessType(&psn, kProcessTransformToBackgroundApplication);

        stdOut = [NSFileHandle fileHandleWithStandardOutput];
        stdErr = [NSFileHandle fileHandleWithStandardError];
        
        NSMutableArray* args = [[NSMutableArray alloc] initWithCapacity:argc];
        for ( int i = 0; i < argc; i++ ) {
            NSString* arg = [[NSString alloc] initWithCString:argv[i] encoding:[NSString defaultCStringEncoding]];
            [args addObject:arg];
        }
        startupArguments = args.copy;
        
        @try {
            if ( args.count > 1 ) {
                NSString* targetURLString = [args[1] stringByReplacingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
                targetURL = [NSURL URLWithString:targetURLString];
            }
            
            if ( targetURL == nil ) {
                @throw [NSException exceptionWithName:NSInvalidArgumentException reason:@"No URL was specified." userInfo:@{@"args":startupArguments}];
            }
            
            if ( targetURL.scheme == nil ) {
                @throw [NSException exceptionWithName:NSInvalidArgumentException reason:@"An invalid URL was specified." userInfo:@{@"args":startupArguments}];
            }
            
            appDelegate = [[WSCAppDelegate alloc] init];
        
            NSRunLoop* runLoop = [NSRunLoop mainRunLoop];
            CFRunLoopObserverContext  context = {0, NULL, NULL, NULL, NULL};
            mainRunLoopObserver = CFRunLoopObserverCreate(kCFAllocatorDefault, kCFRunLoopAllActivities, YES, 0, &mainRunLoopObserverCallback, &context);
            if (mainRunLoopObserver) {
                CFRunLoopRef cfLoop = [runLoop getCFRunLoop];
                CFRunLoopAddObserver(cfLoop, mainRunLoopObserver, kCFRunLoopDefaultMode);
            }
            
            [appDelegate captureImage:targetURL];

            shouldKeepRunning = YES;
            
            NSTimeInterval keepAliveInterval = [[NSDate distantFuture] timeIntervalSinceNow];
            [runLoop addTimer:[NSTimer timerWithTimeInterval:keepAliveInterval target:appDelegate selector:@selector(timerCallback) userInfo:nil repeats:YES] forMode:NSDefaultRunLoopMode];
            
            while ( shouldKeepRunning && [runLoop runMode:NSDefaultRunLoopMode beforeDate:[NSDate distantFuture]] ) {
//                NSLog(@" * Tick");
            }
        
        } @catch (NSException* exception) {
            [stdErr writeData:failWithError([NSError errorWithDomain:[startupArguments[0] lastPathComponent] code:-1 userInfo:@{NSUnderlyingErrorKey: exception}])];
        }
        
    }
    return exitStatus;
}
