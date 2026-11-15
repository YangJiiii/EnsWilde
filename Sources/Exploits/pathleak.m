//
//  pathleak.m
//  worse_query
//
//  Created by Taj C on 9/2/26.
//

/*
     pathleak - The dumbest arbitrary path enumeration.
     Copyright (C) 2026 Taj C (forcequit)

     This program is free software: you can redistribute it and/or modify
     it under the terms of the GNU General Public License as published by
     the Free Software Foundation, either version 3 of the License, or
     (at your option) any later version.

     This program is distributed in the hope that it will be useful,
     but WITHOUT ANY WARRANTY; without even the implied warranty of
     MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
     GNU General Public License for more details.

     You should have received a copy of the GNU General Public License
     along with this program.  If not, see <https://www.gnu.org/licenses/>.
*/

#import <Foundation/Foundation.h>
#include <sys/fsgetpath.h>
#include <sys/mount.h>

// This is just a rewrite of bad_query_list to return an NSString array and run faster
// The way this works is literally just brute-forcing inodes and doing fsgetpath until it gets a matching path, lol.
// Which is still, obviously, dramatically faster than brute-forcing UUIDs.

// It might be possible to derive a sane inode value automagically by just creating a file, doing stat() on it, getting *that* file's inode, then using that for the max_inode count.

NSArray<NSString *> *pathleak(NSString *path, uint64_t max_inode) {
    // Sanity checks
    if (path.length == 0 || max_inode < 1) return nil;
    NSString *dir = path;
    while (dir.length > 1 && [dir hasSuffix: @"/"]) { // Trim trailing slash (if present)
        dir = [dir substringToIndex: dir.length - 1];
    }
    if ([dir hasPrefix: @"/private/var/"]) {
        dir = [dir substringFromIndex: 8];
    } else if ([dir isEqualToString: @"/private/var"]) {
        dir = @"/var";
    }
    
    // Set everything up
    struct statfs sfs;
    if (statfs(dir.fileSystemRepresentation, &sfs) != 0) {
        NSString *home = NSHomeDirectory();
        if ((!home.length || statfs(home.fileSystemRepresentation, &sfs) != 0) &&
            statfs("/private/var/mobile", &sfs) != 0 &&
            statfs("/private/var", &sfs) != 0 &&
            statfs("/var", &sfs) != 0) {
            return nil;
        }
    }
    fsid_t fsid = sfs.f_fsid;
    
    char prefix[PATH_MAX];
    if (![dir getFileSystemRepresentation: prefix maxLength: sizeof(prefix)]) return nil;
    const char *prefixPtr = prefix;
    size_t prefix_length = strlen(prefixPtr);
    if (prefix_length == 1 && prefixPtr[0] == '/') prefix_length = 0;
    
    NSFileManager *files = [NSFileManager defaultManager];
    NSMutableArray<NSString *> *result = [NSMutableArray array];
    NSLock *lock = [[NSLock alloc] init];

    const uint64_t chunk = 65536;
    const uint64_t totalChunks = (max_inode + chunk - 1) / chunk;
    __block uint64_t nextChunk = 0;

    NSUInteger cores = NSProcessInfo.processInfo.activeProcessorCount;
    size_t workers = (size_t)MAX((NSUInteger)1, MIN((NSUInteger)4, cores / 2));

    dispatch_apply(workers, dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^(size_t __unused w) {
        fsid_t localFsid = fsid;
        char buffer[PATH_MAX];
        NSMutableArray<NSString *> *localHits = [NSMutableArray array];

        for (;;) {
            [lock lock];
            uint64_t c = nextChunk++;
            [lock unlock];
            if (c >= totalChunks) break;

            uint64_t startInode = c * chunk + 1;
            uint64_t endInode = startInode + chunk - 1;
            if (endInode > max_inode) endInode = max_inode;

            for (uint64_t inode = startInode; inode <= endInode; inode++) {
                ssize_t n = fsgetpath(buffer, sizeof(buffer), &localFsid, inode);
                if (n <= 0) continue;

                char *p = buffer;
                if (strncmp(p, "/private/var/", 13) == 0) p += 8;

                if (strncmp(p, prefixPtr, prefix_length) != 0) continue;
                if (p[prefix_length] != '/') continue;
                if (strchr(p + prefix_length + 1, '/')) continue;

                NSString *string = [files stringWithFileSystemRepresentation: p length: strlen(p)];
                if (string) [localHits addObject: string];
            }
        }

        if (localHits.count > 0) {
            [lock lock];
            [result addObjectsFromArray: localHits];
            [lock unlock];
        }
    });

    [result sortUsingSelector:@selector(compare:)];
    return result;
}
