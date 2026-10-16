#import "ContourObjC.h"
#import <Foundation/Foundation.h>
#include <sys/stat.h>
#include <errno.h>
#include <string.h>
int32_t CTReadFileInfo(const char *path, CTFileInfo *result) {
    struct stat s;
    if (lstat(path, &s) != 0) return errno;
    memset(result, 0, sizeof(*result));
    result->logicalBytes = (uint64_t)s.st_size;
    result->allocatedBytes = (uint64_t)s.st_blocks * 512;
    result->device = (uint64_t)s.st_dev;
    result->inode = (uint64_t)s.st_ino;
    result->modifiedAt = s.st_mtimespec.tv_sec + s.st_mtimespec.tv_nsec / 1e9;
    result->isDirectory = S_ISDIR(s.st_mode);
    result->isRegular = S_ISREG(s.st_mode);
    result->isSymbolicLink = S_ISLNK(s.st_mode);
    if (result->isRegular) {
        @autoreleasepool {
            NSURL *url = [NSURL fileURLWithFileSystemRepresentation:path isDirectory:NO relativeToURL:nil];
            NSNumber *size = nil;
            if ([url getResourceValue:&size forKey:NSURLTotalFileAllocatedSizeKey error:nil] && size) {
                result->allocatedBytes = size.unsignedLongLongValue;
            }
        }
    }
    return 0;
}
