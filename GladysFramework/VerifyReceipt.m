#import <openssl/pkcs7.h>
#import <openssl/objects.h>
#import <openssl/x509.h>
#import <openssl/evp.h>
#import <CommonCrypto/CommonCrypto.h>
#import <TargetConditionals.h>
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

BOOL checkPayload(const unsigned char *ptr, long len) {
	const unsigned char *end = ptr + len;
	const unsigned char *str_ptr;

	int type = 0, str_type = 0;
	int xclass = 0, str_xclass = 0;
	long length = 0, str_length = 0;

	NSString *productIdentifier;

	// Decode payload (a SET is expected)
	ASN1_get_object(&ptr, &length, &type, &xclass, end - ptr);
	if (type != V_ASN1_SET) {
		return NO;
	}

	while (ptr < end) {
		ASN1_INTEGER *integer;

		// Parse the attribute sequence (a SEQUENCE is expected)
		ASN1_get_object(&ptr, &length, &type, &xclass, end - ptr);
		if (type != V_ASN1_SEQUENCE) {
			return NO;
		}

		const unsigned char *seq_end = ptr + length;
		long attr_type = 0;

        integer = d2i_ASN1_INTEGER(NULL, &ptr, length);
		attr_type = ASN1_INTEGER_get(integer);
		ASN1_INTEGER_free(integer);

		integer = d2i_ASN1_INTEGER(NULL, &ptr, length);
        // unused, used to be attr_version
		ASN1_INTEGER_free(integer);

		// Check the attribute value (an OCTET STRING is expected)
		ASN1_get_object(&ptr, &length, &type, &xclass, end - ptr);
		if (type != V_ASN1_OCTET_STRING) {
			return NO;
		}

		switch (attr_type) {

			case 1702:
				// Product identifier
				str_ptr = ptr;
				ASN1_get_object(&str_ptr, &str_length, &str_type, &str_xclass, seq_end - str_ptr);
				if (str_type == V_ASN1_UTF8STRING) {
					// We store the decoded string for later
					productIdentifier = [[NSString alloc] initWithBytes:str_ptr length:str_length encoding:NSUTF8StringEncoding];
				}
				break;
		}

		// Move past the value
		ptr += length;
	}

	return [productIdentifier isEqualToString:infiniteId];
}

BOOL verifyIapReceipt(NSData *deviceIdentifier) {

#ifdef NO_IAP
#pragma GCC diagnostic ignored "-Wunreachable-code"
    return YES;
#endif
    
	NSURL *dataUrl = [[NSBundle mainBundle] appStoreReceiptURL];
	if (!dataUrl) {
		return NO;
	}
    
	NSData *receiptData = [NSData dataWithContentsOfURL:dataUrl];
	if (!receiptData) {
		return NO;
	}

	// Create a memory buffer to extract the PKCS #7 container
	BIO *receiptBIO = BIO_new(BIO_s_mem());
	BIO_write(receiptBIO, [receiptData bytes], (int) [receiptData length]);
	PKCS7 *receiptPKCS7 = d2i_PKCS7_bio(receiptBIO, NULL);
	if (!receiptPKCS7) {
		return NO;
	}

	// Check that the container has a signature
	if (!PKCS7_type_is_signed(receiptPKCS7)) {
		return NO;
	}

	// Check that the signed container has actual data
	if (!PKCS7_type_is_data(receiptPKCS7->d.sign->contents)) {
		return NO;
	}

	// Load the Apple Root CA (downloaded from https://www.apple.com/certificateauthority/)
	NSBundle *bundle = [NSBundle bundleWithIdentifier:bundleId];
	NSURL *appleRootURL = [bundle URLForResource:@"AppleIncRootCertificate" withExtension:@"cer"];
	NSData *appleRootData = [NSData dataWithContentsOfURL:appleRootURL];
	BIO *appleRootBIO = BIO_new(BIO_s_mem());
	BIO_write(appleRootBIO, (const void *) [appleRootData bytes], (int) [appleRootData length]);
	X509 *appleRootX509 = d2i_X509_bio(appleRootBIO, NULL);

	// Create a certificate store
	X509_STORE *store = X509_STORE_new();
	X509_STORE_add_cert(store, appleRootX509);

	// Check the signature
	int result = PKCS7_verify(receiptPKCS7, NULL, store, NULL, NULL, 0);
	if (result != 1) {
		return NO;
	}

	// Get a pointer to the ASN.1 payload
	ASN1_OCTET_STRING *octets = receiptPKCS7->d.sign->contents->d.data;
	const unsigned char *ptr = octets->data;
	const unsigned char *end = ptr + octets->length;
	const unsigned char *str_ptr;

	int type = 0, str_type = 0;
	int xclass = 0, str_xclass = 0;
	long length = 0, str_length = 0;

	// Store for the receipt information
	NSString *bundleIdString = nil;
	NSString *bundleVersionString = nil;
	NSData *bundleIdData = nil;
	NSData *hashData = nil;
	NSData *opaqueData = nil;
	//NSDate *expirationDate = nil;
	BOOL haveValidTransaction = NO;

	//NSDateFormatter *formatter = makeFormatter();

	// Decode payload (a SET is expected)
	ASN1_get_object(&ptr, &length, &type, &xclass, end - ptr);
	if (type != V_ASN1_SET) {
		return NO;
	}

	while (ptr < end) {
		ASN1_INTEGER *integer;

		// Parse the attribute sequence (a SEQUENCE is expected)
		ASN1_get_object(&ptr, &length, &type, &xclass, end - ptr);
		if (type != V_ASN1_SEQUENCE) {
			return NO;
		}

		const unsigned char *seq_end = ptr + length;
		long attr_type = 0;

		integer = d2i_ASN1_INTEGER(NULL, &ptr, length);
		attr_type = ASN1_INTEGER_get(integer);
		ASN1_INTEGER_free(integer);

		integer = d2i_ASN1_INTEGER(NULL, &ptr, length);
        // unused, used to be attr_version
		ASN1_INTEGER_free(integer);

		// Check the attribute value (an OCTET STRING is expected)
		ASN1_get_object(&ptr, &length, &type, &xclass, end - ptr);
		if (type != V_ASN1_OCTET_STRING) {
			return NO;
		}

		switch (attr_type) {
			case 2:
				// Bundle identifier
				str_ptr = ptr;
				ASN1_get_object(&str_ptr, &str_length, &str_type, &str_xclass, seq_end - str_ptr);
				if (str_type == V_ASN1_UTF8STRING) {
					// We store both the decoded string and the raw data for later
					// The raw is data will be used when computing the GUID hash
					bundleIdString = [[NSString alloc] initWithBytes:str_ptr length:str_length encoding:NSUTF8StringEncoding];
					bundleIdData = [[NSData alloc] initWithBytes:(const void *)ptr length:length];
				}
				break;

			case 3:
				// Bundle version
				str_ptr = ptr;
				ASN1_get_object(&str_ptr, &str_length, &str_type, &str_xclass, seq_end - str_ptr);
				if (str_type == V_ASN1_UTF8STRING) {
					// We store the decoded string for later
					bundleVersionString = [[NSString alloc] initWithBytes:str_ptr length:str_length encoding:NSUTF8StringEncoding];
				}
				break;

			case 4:
				// Opaque value
				opaqueData = [[NSData alloc] initWithBytes:(const void *)ptr length:length];
				break;

			case 5:
				// Computed GUID (SHA-1 Hash)
				hashData = [[NSData alloc] initWithBytes:(const void *)ptr length:length];
				break;

			case 17:
				// Transaction
				if (!haveValidTransaction) {
					haveValidTransaction = checkPayload(ptr, length);
				}
				break;
		}

		// Move past the value
		ptr += length;
	}

	// Be sure that all information is present
	if (bundleIdString == nil ||
		bundleVersionString == nil ||
		opaqueData == nil ||
		hashData == nil ||
		!haveValidTransaction) {

		return NO;
	}

	// Check the bundle identifier
	if (![bundleIdString isEqualToString:receiptId]) {
		return NO;
	}

	unsigned char hash[20];

	// Create a hashing context for computation
	SHA_CTX ctx;
	SHA1_Init(&ctx);
	SHA1_Update(&ctx, [deviceIdentifier bytes], (size_t) [deviceIdentifier length]);
	SHA1_Update(&ctx, [opaqueData bytes], (size_t) [opaqueData length]);
	SHA1_Update(&ctx, [bundleIdData bytes], (size_t) [bundleIdData length]);
	SHA1_Final(hash, &ctx);

	// Do the comparison
	NSData *computedHashData = [NSData dataWithBytes:hash length:20];
	if (![computedHashData isEqualToData:hashData]) {
		return NO;
	}

	return YES;
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
