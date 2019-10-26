//
//  SafeUnarchiver.m
//  Gladys
//
//  Created by Paul Tsochantaris on 26/10/2019.
//  Copyright © 2019 Paul Tsochantaris. All rights reserved.
//

#import "SafeUnarchiver.h"

@implementation SafeArchiver
+ (NSData *)archive:(id)object {
    @try {
        NSError *error;
        return [super archivedDataWithRootObject:object
                           requiringSecureCoding:NO
                                           error:&error];
    } @catch (NSException *exception) {
        return nil;
    }
}
@end

@implementation SafeUnarchiver
+ (id)unarchive:(NSData *)data {
    @try {
        NSError *error;
        return [super unarchivedObjectOfClass:[NSObject class]
                                     fromData:data
                                        error:&error];
    } @catch (NSException *exception) {
        return nil;
    }
}
@end
