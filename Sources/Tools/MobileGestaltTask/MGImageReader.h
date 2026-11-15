//
//  MGImageReader.h
//  Erosion
//

#ifndef MGImageReader_h
#define MGImageReader_h

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Read-only snapshot of the currently loaded /usr/lib/libMobileGestalt.dylib sections.
/// Never hooks functions, dereferences arbitrary pointers, or mutates memory.
FOUNDATION_EXPORT NSDictionary<NSString *, id> * _Nullable MGCopyLoadedMobileGestaltImage(void);

NS_ASSUME_NONNULL_END

#endif /* MGImageReader_h */
