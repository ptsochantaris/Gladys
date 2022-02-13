#import "GladysFramework.h"
#if TARGET_OS_IPHONE
@import UIKit;
#endif
@import MapKit;
@import CloudKit;

uint32_t valueForKeyedArchiverUID(id keyedArchiverUID) {
	void *uid = (__bridge void*)keyedArchiverUID;
	uint32_t *valuePtr = uid+16;
	return *valuePtr;
}

NSSet *_allowedClasses = nil;

@implementation SafeArchiving
+ (NSData *)archive:(id)object {
    @try {
        return [NSKeyedArchiver archivedDataWithRootObject:object requiringSecureCoding:NO error:nil];
    } @catch (NSException *exception) {
        return nil;
    }
}

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
                           [NSDate class],
                           nil
        ];
    }
    return _allowedClasses;
}
+ (id)unarchive:(NSData *)data {
    @try {
        return [NSKeyedUnarchiver unarchivedObjectOfClasses:[SafeArchiving allowedClasses] fromData:data error:nil];
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
