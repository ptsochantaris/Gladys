//
//  SafeUnarchiver.h
//  SafeUnarchiver
//
//  Created by Paul Tsochantaris on 26/10/2019.
//  Copyright © 2019 Paul Tsochantaris. All rights reserved.
//

@import Foundation;

FOUNDATION_EXPORT double SafeUnarchiverVersionNumber;
FOUNDATION_EXPORT const unsigned char SafeUnarchiverVersionString[];

@interface SafeArchiver: NSKeyedArchiver
+ (NSData *)archive:(id)object;
@end

@interface SafeUnarchiver: NSKeyedUnarchiver
+ (id)unarchive:(NSData *)data;
@end
