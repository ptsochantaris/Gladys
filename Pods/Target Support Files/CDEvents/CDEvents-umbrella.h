#ifdef __OBJC__
#import <Cocoa/Cocoa.h>
#else
#ifndef FOUNDATION_EXPORT
#if defined(__cplusplus)
#define FOUNDATION_EXPORT extern "C"
#else
#define FOUNDATION_EXPORT extern
#endif
#endif
#endif

#import "CDEvent.h"
#import "CDEvents.h"
#import "CDEventsDelegate.h"
#import "compat.h"

FOUNDATION_EXPORT double CDEventsVersionNumber;
FOUNDATION_EXPORT const unsigned char CDEventsVersionString[];

