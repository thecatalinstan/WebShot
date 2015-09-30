//
//  WSShotViewController.h
//  WebShot
//
//  Created by Cătălin Stan on 19/04/15.
//  Copyright (c) 2015 Catalin Stan. All rights reserved.
//

#import <FCGIKit/FCGIKit.h>
#import <Cocoa/Cocoa.h>
#import <WebKit/WebKit.h>

@interface WSShotViewController : FKViewController

@property (nonatomic, strong, readonly) NSURL* targetURL;
@property (readonly) BOOL ignoreCache;

@end
