//
//  GladysFramework.h
//  GladysFramework
//
//  Created by Paul Tsochantaris on 09/07/2017.
//  Copyright © 2017 Paul Tsochantaris. All rights reserved.
//

@import Foundation;

FOUNDATION_EXPORT double GladysFrameworkVersionNumber;
FOUNDATION_EXPORT const unsigned char GladysFrameworkVersionString[];

BOOL verifyIapReceipt(NSData *deviceIdentifier);
NSData *sha1(NSString *input);

#if TARGET_OS_IOS
NSString *bundleId = @"build.bru.Gladys.Framework";
NSString *receiptId = @"build.bru.Gladys";
NSString *infiniteId = @"INFINITE";
uint32_t valueForKeyedArchiverUID(id keyedArchiverUID);
#else
NSString *bundleId = @"build.bru.MacGladys.Framework";
NSString *receiptId = @"build.bru.MacGladys";
NSString *infiniteId = @"MACINFINITE";
#endif
