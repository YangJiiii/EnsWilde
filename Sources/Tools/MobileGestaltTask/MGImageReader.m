//
//  MGImageReader.m
//  Erosion
//

#import "MGImageReader.h"
#import <TargetConditionals.h>
#import <CoreFoundation/CoreFoundation.h>
#import <objc/runtime.h>
#import <ctype.h>
#import <dlfcn.h>
#import <pthread.h>
#import <mach-o/dyld.h>
#import <mach-o/getsect.h>
#import <string.h>

extern void *__CFConstantStringClassReference;

static NSData * _Nullable MGCopySectionBytes(const struct mach_header_64 *header,
                                             const char *segment,
                                             const char *sectionName,
                                             uint64_t * _Nullable outRuntimeAddress) {
    unsigned long size = 0;
    const uint8_t *ptr = getsectiondata(header, segment, sectionName, &size);
    if (!ptr || size == 0 || size > 32 * 1024 * 1024) {
        return nil;
    }
    uintptr_t start = (uintptr_t)ptr;
    if (start + size < start) {
        return nil;
    }
    if (outRuntimeAddress) {
        *outRuntimeAddress = (uint64_t)start;
    }
    return [NSData dataWithBytes:ptr length:(NSUInteger)size];
}

static BOOL MGHasLibrarySuffix(const char *imageName, const char *suffix) {
    if (!imageName || !suffix) return NO;
    size_t nLen = strlen(imageName);
    size_t sLen = strlen(suffix);
    if (nLen < sLen) return NO;
    return strcmp(imageName + (nLen - sLen), suffix) == 0;
}

NSDictionary<NSString *, id> * _Nullable MGCopyLoadedMobileGestaltImage(void) {
#if TARGET_OS_SIMULATOR
    return nil;
#else
    static NSDictionary<NSString *, id> *cachedImage = nil;
    static pthread_mutex_t lock = PTHREAD_MUTEX_INITIALIZER;

    pthread_mutex_lock(&lock);
    if (cachedImage != nil) {
        NSDictionary<NSString *, id> *ret = cachedImage;
        pthread_mutex_unlock(&lock);
        return ret;
    }

    const char *targetPath = "/usr/lib/libMobileGestalt.dylib";
    const char *targetSuffix = "/libMobileGestalt.dylib";
    (void)dlopen(targetPath, RTLD_LAZY | RTLD_LOCAL);

    uint32_t imageCount = _dyld_image_count();
    for (uint32_t i = 0; i < imageCount; i++) {
        const char *imageName = _dyld_get_image_name(i);
        if (!imageName || (strcmp(imageName, targetPath) != 0 && !MGHasLibrarySuffix(imageName, targetSuffix))) {
            continue;
        }

        const struct mach_header_64 *header = (const struct mach_header_64 *)_dyld_get_image_header(i);
        if (!header || header->magic != MH_MAGIC_64) {
            break;
        }

        uint64_t cstringRuntimeAddr = 0;
        NSData *strings = MGCopySectionBytes(header, "__TEXT", "__cstring", &cstringRuntimeAddr);

        NSMutableArray<NSData *> *constants = [NSMutableArray arrayWithCapacity:3];
        const char *constSegments[] = { "__AUTH_CONST", "__DATA_CONST", "__DATA" };
        for (size_t s = 0; s < sizeof(constSegments) / sizeof(constSegments[0]); s++) {
            NSData *secData = MGCopySectionBytes(header, constSegments[s], "__const", NULL);
            if (secData) {
                [constants addObject:secData];
            }
        }

        // Memory-safe inspection of __cfstring without ObjC/CF type-punning or arbitrary dereferencing
        NSMutableArray<NSString *> *cfUUIDCandidates = [NSMutableArray array];
        if (strings && cstringRuntimeAddr != 0) {
            uintptr_t cstrMin = (uintptr_t)cstringRuntimeAddr;
            uintptr_t cstrMax = cstrMin + strings.length;
            const void *constRefPtr = (const void *)&__CFConstantStringClassReference;
            const void *nsConstClsPtr = (__bridge const void *)objc_getClass("__NSCFConstantString");
            uintptr_t constStrIsa1 = ((uintptr_t)constRefPtr) & 0x00007FFFFFFFFFFFULL;
            uintptr_t constStrIsa2 = ((uintptr_t)nsConstClsPtr) & 0x00007FFFFFFFFFFFULL;

            const char *cfSegments[] = { "__AUTH_CONST", "__DATA_CONST" };
            for (size_t s = 0; s < sizeof(cfSegments) / sizeof(cfSegments[0]); s++) {
                unsigned long cfSize = 0;
                const uint8_t *cfPtr = getsectiondata(header, cfSegments[s], "__cfstring", &cfSize);
                if (!cfPtr || cfSize < 32 || cfSize > 8 * 1024 * 1024) {
                    continue;
                }
                for (size_t off = 0; off + 32 <= cfSize; off += 32) {
                    uint64_t rawIsa = 0, rawDataPtr = 0, rawLen = 0;
                    memcpy(&rawIsa, cfPtr + off, sizeof(uint64_t));
                    memcpy(&rawDataPtr, cfPtr + off + 16, sizeof(uint64_t));
                    memcpy(&rawLen, cfPtr + off + 24, sizeof(uint64_t));
                    if (rawLen != 36) {
                        continue;
                    }
                    uintptr_t strippedIsa = (uintptr_t)(rawIsa & 0x00007FFFFFFFFFFFULL);
                    if (strippedIsa != constStrIsa1 && (constStrIsa2 == 0 || strippedIsa != constStrIsa2)) {
                        continue;
                    }
                    uintptr_t charPtr = (uintptr_t)(rawDataPtr & 0x00007FFFFFFFFFFFULL);
                    if (charPtr < cstrMin || charPtr + 36 > cstrMax) {
                        continue;
                    }
                    const char *chars = (const char *)charPtr;
                    BOOL isUUID = YES;
                    for (int c = 0; c < 36; c++) {
                        unsigned char ch = (unsigned char)chars[c];
                        if (c == 8 || c == 13 || c == 18 || c == 23) {
                            if (ch != '-') { isUUID = NO; break; }
                        } else if (!isxdigit(ch)) {
                            isUUID = NO; break;
                        }
                    }
                    if (isUUID) {
                        NSString *cand = [[NSString alloc] initWithBytes:chars length:36 encoding:NSASCIIStringEncoding];
                        if (cand && [[NSUUID alloc] initWithUUIDString:cand] != nil) {
                            [cfUUIDCandidates addObject:cand];
                        }
                    }
                }
            }
        }

        if (strings && cstringRuntimeAddr != 0 && constants.count > 0) {
            cachedImage = @{
                @"strings": strings,
                @"stringAddress": @(cstringRuntimeAddr),
                @"constants": [constants copy],
                @"cfUUIDs": [cfUUIDCandidates copy]
            };
        }
        break;
    }

    NSDictionary<NSString *, id> *result = cachedImage;
    pthread_mutex_unlock(&lock);
    return result;
#endif
}
