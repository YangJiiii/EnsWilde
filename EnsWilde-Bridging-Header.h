//
//  Use this file to import your target's public headers that you would like to expose to Swift.
//

@import UIKit;
#import "idevice.h"
#import "applist.h"
#import "mount.h"
#import "JITEnableContext.h"

// --- AIRLIFT & GRAPPA ---
#import "airlift.h"
#import "GrappaHelper.h"

long FindCacheDataOffset(const char *mgKey);

#pragma mark - Private API

@interface LSApplicationWorkspace : NSObject
+ (instancetype)defaultWorkspace;
- (BOOL)openApplicationWithBundleID:(NSString *)arg1 ;
@end
LSApplicationWorkspace *LSApplicationWorkspaceDefaultWorkspace(void);

@interface UIDevice(Private)
@property(nonatomic, strong, readonly) NSString *buildVersion;
+ (BOOL)_hasHomeButton;
@end

#pragma mark - worse_query
//
// Khai báo trực tiếp 3 hàm C thay vì #include "worse_query.h" / "pathleak.h".
// Lý do: HEADER_SEARCH_PATHS trong project.pbxproj chỉ có `include`,
// nên compiler không tìm được .h nằm trong Sources/Helpers/.
// Khai báo inline dưới đây giúp bridging header luôn compile được,
// trong khi worse_query.m và pathleak.m vẫn tự động compile nhờ
// PBXFileSystemSynchronizedRootGroup.
//
#include <stdint.h>
#include <stdbool.h>

// worse_query.h
int64_t worse_query(NSString *path, NSString *group, bool alt_flags, bool create_dir);
void    worse_query_release(int64_t handle);

// pathleak.h
NSArray *pathleak(NSString *filter, uint64_t max_inode);