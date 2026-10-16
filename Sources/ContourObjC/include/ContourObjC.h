#include <stdint.h>
typedef struct {
    uint64_t logicalBytes;
    uint64_t allocatedBytes;
    uint64_t device;
    uint64_t inode;
    double modifiedAt;
    int32_t isDirectory;
    int32_t isRegular;
    int32_t isSymbolicLink;
} CTFileInfo;
/// Does not follow the last path component. Returns errno, or zero on success.
int32_t CTReadFileInfo(const char *path, CTFileInfo *result);
