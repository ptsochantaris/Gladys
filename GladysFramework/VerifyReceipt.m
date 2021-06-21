#import <CommonCrypto/CommonCrypto.h>
#import "GladysFramework.h"
#if TARGET_OS_IPHONE
@import UIKit;
#endif
@import MapKit;
@import CloudKit;

NSData *sha1(NSString *input) {
	unsigned char digest[CC_SHA1_DIGEST_LENGTH];
	NSData *stringBytes = [input dataUsingEncoding: NSUTF8StringEncoding];
	CC_SHA1([stringBytes bytes], (CC_LONG)[stringBytes length], digest);
	return [NSData dataWithBytes:digest length:CC_SHA1_DIGEST_LENGTH];
}

uint32_t valueForKeyedArchiverUID(id keyedArchiverUID) {
	void *uid = (__bridge void*)keyedArchiverUID;
	uint32_t *valuePtr = uid+16;
	return *valuePtr;
}

@implementation SafeArchiver
+ (NSData *)archive:(id)object {
    @try {
        NSError *error;
        return [NSKeyedArchiver archivedDataWithRootObject:object requiringSecureCoding:NO error:&error];
    } @catch (NSException *exception) {
        return nil;
    }
}
@end

NSSet *_allowedClasses = nil;

@implementation SafeUnarchiver
+ (NSSet *)allowedClasses{
    if(_allowedClasses == nil) {
        _allowedClasses = [[NSSet alloc] initWithObjects:
                           [NSString class],
                           [NSAttributedString class],
#if TARGET_OS_IPHONE
                           [UIColor class],
                           [UIImage class],
#else
                           [NSColor class],
                           [NSImage class],
#endif
                           [MKMapItem class],
                           [NSURL class],
                           [NSArray class],
                           [NSDictionary class],
                           [NSSet class],
                           [CKServerChangeToken class],
                           nil
        ];
    }
    return _allowedClasses;
}
+ (id)unarchive:(NSData *)data {
    @try {
        id a = [NSKeyedUnarchiver unarchivedObjectOfClasses:[SafeUnarchiver allowedClasses] fromData:data error:nil];
/*#if DEBUG
        id b = [NSKeyedUnarchiver unarchivedObjectOfClass:[NSObject class] fromData:data error:nil];
        if(!(a == nil && b == nil) && ![a isEqual:b]) {
            abort();
        }
#endif*/
        return a;
    } @catch (NSException *exception) {
        return nil;
    }
}
@end

BOOL isRunningInTestFlightEnvironment(void) {
#if TARGET_IPHONE_SIMULATOR
    return NO;
#else
    BOOL sandbox = [NSBundle.mainBundle.appStoreReceiptURL.lastPathComponent isEqualToString:@"sandboxReceipt"];
    BOOL provision = [[NSBundle mainBundle] pathForResource:@"embedded" ofType:@"mobileprovision"] != nil;
    return sandbox && !provision;
#endif
}
