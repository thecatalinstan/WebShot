//
//  AppDelegate.h
//  WebShot
//
//  Created by Cătălin Stan on 10/04/15.
//  Copyright (c) 2015 Catalin Stan. All rights reserved.
//

#import <Criollo/Criollo.h>

NS_ASSUME_NONNULL_BEGIN

@interface WSAppDelegate : NSObject <CRApplicationDelegate>

+ (NSURL *)baseDirectory;
+ (NSURL *)baseURL;
+ (dispatch_queue_t)backgroundQueue;

+ (NSString *)serverSpecString;
+ (NSString *)ETag;

@end

NS_ASSUME_NONNULL_END

