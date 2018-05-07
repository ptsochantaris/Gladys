//
//  GladysFramework.h
//  GladysFramework
//
//  Created by Paul Tsochantaris on 09/07/2017.
//  Copyright © 2017 Paul Tsochantaris. All rights reserved.
//

@import Foundation;

//! Project version number for GladysFramework.
FOUNDATION_EXPORT double MacGladysFrameworkVersionNumber;

//! Project version string for GladysFramework.
FOUNDATION_EXPORT const unsigned char MacGladysFrameworkVersionString[];

// In this header, you should import all the public headers of your framework using statements like #import <GladysFramework/PublicHeader.h>

BOOL verifyIapReceipt(void);

NSData *sha1(NSString *input);

NSString *bundleId = @"build.bru.MacGladys.MacGladysFramework";
NSString *receiptId = @"build.bru.MacGladys";
