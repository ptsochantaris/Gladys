#import <CommonCrypto/CommonCrypto.h>
#import "GladysFramework.h"

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
        return [super archivedDataWithRootObject:object requiringSecureCoding:NO error:&error];
    } @catch (NSException *exception) {
        return nil;
    }
}
@end

@implementation SafeUnarchiver
+ (id)unarchive:(NSData *)data {
    @try {
        NSError *error;
        return [super unarchivedObjectOfClass:[NSObject class] fromData:data error:&error];
    } @catch (NSException *exception) {
        return nil;
    }
}
@end

BOOL isRunningInTestFlightEnvironment(void) {
#if TARGET_IPHONE_SIMULATOR
    return YES;
#else
    BOOL sandbox = [NSBundle.mainBundle.appStoreReceiptURL.lastPathComponent isEqualToString:@"sandboxReceipt"];
    BOOL provision = [[NSBundle mainBundle] pathForResource:@"embedded" ofType:@"mobileprovision"];
    return sandbox && !provision;
#endif
}
