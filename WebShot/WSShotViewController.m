//
//  WSShotViewController.m
//  WebShot
//
//  Created by Cătălin Stan on 19/04/15.
//  Copyright (c) 2015 Catalin Stan. All rights reserved.
//

#import "WSShotViewController.h"
#import <Cocoa/Cocoa.h>

@implementation WSShotViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    NSString* targetURLString = [self.request.get[@"url"] stringByReplacingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
    _targetURL = [NSURL URLWithString:targetURLString];
}

- (NSString *)presentViewController:(BOOL)writeData
{
    
    void(^writeDataBlock)(NSData*, BOOL) = ^(NSData* theData, BOOL error) {
        
        if ( error ) {
            [self.response setHTTPStatus:500];
            [self.response setValue:@"application/json; charset=utf-8" forHTTPHeaderField:@"Content-type"];
        } else {
            [self.response setHTTPStatus:200];
            [self.response setValue:@"image/png" forHTTPHeaderField:@"Content-type"];
            [self.response setValue:@"inline" forHTTPHeaderField:@"Content-disposition"];
        }

        [self.response setValue:@(theData.length).stringValue forHTTPHeaderField:@"Content-length"];
        
        [self.response write:theData];
        [self.response finish];
    };
    
    
    @try {
        
        if ( self.targetURL == nil ) {
            @throw [NSException exceptionWithName:NSInvalidArgumentException reason:@"No URL was specified." userInfo:self.request.get];
        }

        outData = [[NSMutableData alloc] init];
        errData = [[NSMutableData alloc] init];

        NSPipe *stdOutPipe = [NSPipe pipe];
        [stdOutPipe.fileHandleForReading setReadabilityHandler:^(NSFileHandle *file) {
            [outData appendData:file.availableData];
        }];
        
        NSPipe *stdErrPipe = [NSPipe pipe];
        [stdErrPipe.fileHandleForReading setReadabilityHandler:^(NSFileHandle *file) {
            [errData appendData:file.availableData];
        }];
        
        NSTask *captureTask = [[NSTask alloc] init];
        captureTask.launchPath = [[[[NSBundle mainBundle].bundlePath stringByAppendingPathComponent:@"Contents"] stringByAppendingPathComponent:@"MacOS"] stringByAppendingPathComponent:@"Capture"];
        captureTask.arguments = @[self.targetURL.absoluteString];
        captureTask.standardOutput = stdOutPipe;
        captureTask.standardError = stdErrPipe;

        NSDictionary* cmdInfo = @{@"launchPath": captureTask.launchPath, @"arguments": captureTask.arguments != nil ? captureTask.arguments : @"nil"};
        NSLog(@"%@", cmdInfo);
        
        [captureTask setTerminationHandler:^(NSTask *task) {
            stdOutPipe.fileHandleForReading.readabilityHandler = nil;
            [stdOutPipe.fileHandleForReading closeFile];
            
            stdErrPipe.fileHandleForReading.readabilityHandler = nil;
            [stdErrPipe.fileHandleForReading closeFile];
        }];
        
        [captureTask launch];
        [captureTask waitUntilExit];
        
        if (captureTask.terminationStatus != EXIT_SUCCESS) {
            NSString* errorString = [[[NSString alloc] initWithData:errData encoding:NSUTF8StringEncoding] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
            NSData* responseData = [self failWithError:[NSError errorWithDomain:[NSBundle mainBundle].bundleIdentifier code:-1 userInfo:@{NSUnderlyingErrorKey: [NSException exceptionWithName:NSInvalidArchiveOperationException reason:errorString userInfo:@{@"cmd": cmdInfo}]}]];
            writeDataBlock(responseData, YES);
            return nil;
        }
        
        if ( outData == nil) {
            NSData* responseData = [self failWithError:[NSError errorWithDomain:[NSBundle mainBundle].bundleIdentifier code:-1 userInfo:@{NSUnderlyingErrorKey: [NSException exceptionWithName:NSInvalidArchiveOperationException reason:@"Task returned blank" userInfo:@{@"cmd": cmdInfo}]}]];
            writeDataBlock(responseData, YES);
       return nil;
        }
        
        writeDataBlock(outData.copy, NO);
        
    } @catch (NSException *ex) {
        
        NSData* responseData = [self failWithError:[NSError errorWithDomain:[NSBundle mainBundle].bundleIdentifier code:-1 userInfo:@{NSUnderlyingErrorKey: ex}]];
        writeDataBlock(responseData, YES);
        
    }
    
    return nil;
    
    
}

#pragma mark - Responses

- (NSData*)succeedWithResult:(NSDictionary*)result
{
    NSData* imageData = result[FKResultKey];
    return imageData;
}

- (NSData*)failWithError:(NSError*)error
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
    
    [self.response setHTTPStatus:500];
    
    NSMutableDictionary* outputDictionary = [NSMutableDictionary dictionary];
    outputDictionary[@"status"] = @(NO);
    outputDictionary[@"error"] = @{
                                   @"domain": errorTitle,
                                   @"code": @(errorCode),
                                   @"description": errorDescription,
                                   };
    
    return [NSJSONSerialization dataWithJSONObject:outputDictionary.copy options:0 error:&error];
}


@end
