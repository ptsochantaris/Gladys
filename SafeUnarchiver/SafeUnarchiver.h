//
//  SafeUnarchiver.h
//  SafeUnarchiver
//
//  Created by Paul Tsochantaris on 26/10/2019.
//  Copyright © 2019 Paul Tsochantaris. All rights reserved.
//

#import <Foundation/Foundation.h>

//! Project version number for SafeUnarchiver.
FOUNDATION_EXPORT double SafeUnarchiverVersionNumber;

//! Project version string for SafeUnarchiver.
FOUNDATION_EXPORT const unsigned char SafeUnarchiverVersionString[];

// In this header, you should import all the public headers of your framework using statements like #import <SafeUnarchiver/PublicHeader.h>

@interface SafeArchiver: NSKeyedArchiver
+ (NSData *)archive:(id)object;
@end

@interface SafeUnarchiver: NSKeyedUnarchiver
+ (id)unarchive:(NSData *)data;
@end
