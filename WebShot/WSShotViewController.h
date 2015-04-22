//
//  WSShotViewController.h
//  WebShot
//
//  Created by Cătălin Stan on 19/04/15.
//  Copyright (c) 2015 Catalin Stan. All rights reserved.
//

#import <FCGIKit/FCGIKit.h>

@interface WSShotViewController : FKViewController {
    NSMutableData *outData;
    NSMutableData *errData;
}

@property (nonatomic, strong, readonly) NSURL* targetURL;

@end
